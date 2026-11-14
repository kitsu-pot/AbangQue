import { issueCredential } from './security.js';
const selection = `SELECT d.id,d.label,d.model,d.description,d.administrative_notes AS "administrativeNotes",d.source,d.legacy,d.enabled,
 d.jeepney_id AS "jeepneyId",j.plate_number AS "plateNumber",j.active AS "jeepneyActive",d.version,d.created_at AS "createdAt",d.updated_at AS "updatedAt",
 (SELECT count(*)::int FROM device_credentials c WHERE c.device_id=d.id) AS "credentialCount",
 (SELECT count(*)::int FROM device_credentials c WHERE c.device_id=d.id AND c.revoked_at IS NULL) AS "validCredentials",
 u.jeepney_id AS "reportJeepneyId",u.latitude,u.longitude,u.status AS "lastReportedStatus",u.recorded_at AS timestamp,seen.received_at AS "lastSeenAt",
 COALESCE(u.recorded_at <= $1::timestamptz AND seen.received_at <= $1::timestamptz AND u.recorded_at > $1::timestamptz-$2*interval '1 second' AND seen.received_at > $1::timestamptz-$2*interval '1 second',false) AS fresh
 FROM iot_devices d LEFT JOIN jeepneys j ON j.id=d.jeepney_id
 LEFT JOIN LATERAL(SELECT u.* FROM location_status_updates u JOIN device_credentials c ON c.id=u.credential_id WHERE c.device_id=d.id ORDER BY u.recorded_at DESC,u.id DESC LIMIT 1)u ON true
 LEFT JOIN LATERAL(SELECT u.received_at FROM location_status_updates u JOIN device_credentials c ON c.id=u.credential_id WHERE c.device_id=d.id ORDER BY u.received_at DESC LIMIT 1)seen ON true`;
function present(r) {
  return {
    ...r,
    credentialState: r.validCredentials
      ? 'Provisioned'
      : r.credentialCount
        ? 'Revoked'
        : 'Not provisioned',
    freshness: !r.timestamp ? 'MISSING' : r.fresh ? 'FRESH' : 'STALE',
    status:
      r.enabled &&
      r.validCredentials &&
      r.source === 'device' &&
      r.jeepneyActive &&
      r.jeepneyId === r.reportJeepneyId &&
      r.fresh
        ? r.lastReportedStatus
        : 'UNKNOWN',
  };
}
export class AdminDeviceRepository {
  constructor(pool, { issue = issueCredential } = {}) {
    this.pool = pool;
    this.issue = issue;
  }
  async choices() {
    return (
      await this.pool.query(
        'SELECT id,name,plate_number AS "plateNumber",active FROM jeepneys WHERE source=\'device\' ORDER BY id',
      )
    ).rows;
  }
  async get(id, now, stale) {
    const row = (
      await this.pool.query(selection + ' WHERE d.id=$3', [
        new Date(now),
        stale,
        id,
      ])
    ).rows[0];
    return row ? present(row) : null;
  }
  async events(id) {
    return (
      await this.pool.query(
        'SELECT action,previous_jeepney_id AS "previousJeepneyId",jeepney_id AS "jeepneyId",version,created_at AS "createdAt" FROM admin_device_events WHERE device_id=$1 ORDER BY id DESC LIMIT 20',
        [id],
      )
    ).rows;
  }
  async list(v, now, stale) {
    const c = await this.pool.connect();
    try {
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const where = `WHERE ($3='' OR strpos(lower(concat_ws(' ',id,label,model,"jeepneyId")),lower($3))>0) AND ($4='all' OR ($4='fresh' AND fresh) OR ($4='stale' AND timestamp IS NOT NULL AND NOT fresh) OR ($4='missing' AND timestamp IS NULL)) AND ($5='all' OR ($5='assigned' AND "jeepneyId" IS NOT NULL) OR ($5='unassigned' AND "jeepneyId" IS NULL)) AND ($6='all' OR enabled=($6='enabled'))`;
      const args = [
        new Date(now),
        stale,
        v.search,
        v.reporting,
        v.assignment,
        v.state,
      ];
      const total = (
        await c.query(
          `WITH records AS (${selection}) SELECT count(*)::int AS n FROM records ${where}`,
          args,
        )
      ).rows[0].n;
      const counts = (
        await c.query(
          `WITH records AS (${selection}) SELECT count(*) FILTER(WHERE source='device')::int AS total,count(*) FILTER(WHERE source='device' AND enabled)::int AS enabled,count(*) FILTER(WHERE source='device' AND NOT enabled)::int AS disabled,count(*) FILTER(WHERE source='device' AND fresh)::int AS fresh,count(*) FILTER(WHERE source='device' AND NOT fresh)::int AS "staleOrMissing",min(LEAST(timestamp,"lastSeenAt")+$2*interval '1 second') FILTER(WHERE source='device' AND fresh) AS "validUntil" FROM records`,
          args.slice(0, 2),
        )
      ).rows[0];
      const items = (
        await c.query(
          `WITH records AS (${selection}) SELECT * FROM records ${where} ORDER BY id LIMIT $7 OFFSET $8`,
          [...args, v.pageSize, (v.page - 1) * v.pageSize],
        )
      ).rows.map(present);
      await c.query('COMMIT');
      return {
        items,
        total,
        counts,
        page: v.page,
        pageSize: v.pageSize,
        updatedAt: new Date(now).toISOString(),
        staleAfterSeconds: stale,
      };
    } catch (e) {
      await c.query('ROLLBACK');
      throw e;
    } finally {
      c.release();
    }
  }
  async eligible(c, id) {
    if (id === null) return;
    const r = (
      await c.query(
        "SELECT id FROM jeepneys WHERE id=$1 AND active AND source='device' FOR SHARE",
        [id],
      )
    ).rows[0];
    if (!r) throw new Error('JEEPNEY_INELIGIBLE');
  }
  async audit(c, id, actor, action, previous, assigned, version) {
    await c.query(
      'INSERT INTO admin_device_events(device_id,admin_id,action,previous_jeepney_id,jeepney_id,version) VALUES($1,$2,$3,$4,$5,$6)',
      [id, actor, action, previous, assigned, version],
    );
  }
  async create(v, actor) {
    const c = await this.pool.connect();
    try {
      await c.query('BEGIN');
      await this.eligible(c, v.jeepneyId);
      await c.query(
        'INSERT INTO iot_devices(id,label,model,description,administrative_notes,enabled,jeepney_id) VALUES($1,$2,$3,$4,$5,$6,$7)',
        [
          v.id,
          v.label,
          v.model,
          v.description,
          v.administrativeNotes,
          v.enabled,
          v.jeepneyId,
        ],
      );
      await this.audit(c, v.id, actor, 'REGISTER', null, v.jeepneyId, 1);
      await c.query('COMMIT');
    } catch (e) {
      await c.query('ROLLBACK');
      throw e;
    } finally {
      c.release();
    }
  }
  async change(id, v, actor, action) {
    const c = await this.pool.connect();
    try {
      await c.query('BEGIN');
      const d = (
        await c.query('SELECT * FROM iot_devices WHERE id=$1 FOR UPDATE', [id])
      ).rows[0];
      if (!d) throw new Error('DEVICE_NOT_FOUND');
      if (d.source !== 'device') throw new Error('TEST_RECORD_READ_ONLY');
      if (d.version !== v.expectedVersion) throw new Error('RECORD_CHANGED');
      let token,
        assigned = d.jeepney_id;
      if (action === 'EDIT')
        await c.query(
          'UPDATE iot_devices SET label=$2,model=$3,description=$4,administrative_notes=$5 WHERE id=$1',
          [id, v.label, v.model, v.description, v.administrativeNotes],
        );
      if (action === 'ASSIGN') {
        await this.eligible(c, v.jeepneyId);
        assigned = v.jeepneyId;
        if (assigned !== d.jeepney_id) {
          await c.query(
            'UPDATE device_credentials SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE device_id=$1',
            [id],
          );
          await c.query('UPDATE iot_devices SET jeepney_id=$2 WHERE id=$1', [
            id,
            assigned,
          ]);
        }
      }
      if (action === 'ENABLE' || action === 'DISABLE') {
        if (v.enabled) await this.eligible(c, d.jeepney_id);
        await c.query('UPDATE iot_devices SET enabled=$2 WHERE id=$1', [
          id,
          v.enabled,
        ]);
      }
      if (action === 'REVOKE')
        await c.query(
          'UPDATE device_credentials SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE device_id=$1',
          [id],
        );
      if (action === 'PROVISION' || action === 'ROTATE') {
        if (!d.enabled || !d.jeepney_id) throw new Error('DEVICE_NOT_READY');
        await this.eligible(c, d.jeepney_id);
        const valid = (
          await c.query(
            'SELECT 1 FROM device_credentials WHERE device_id=$1 AND revoked_at IS NULL',
            [id],
          )
        ).rowCount;
        if (action === 'PROVISION' && valid)
          throw new Error('ALREADY_PROVISIONED');
        const key = this.issue();
        await c.query(
          'UPDATE device_credentials SET revoked_at=COALESCE(revoked_at,clock_timestamp()) WHERE device_id=$1',
          [id],
        );
        await c.query(
          "INSERT INTO device_credentials(id,device_id,jeepney_id,source,secret_hash) VALUES($1,$2,$3,'device',$4)",
          [key.id, id, d.jeepney_id, key.secretHash],
        );
        token = key.token;
      }
      await c.query(
        'UPDATE iot_devices SET version=version+1,updated_at=clock_timestamp() WHERE id=$1',
        [id],
      );
      await this.audit(
        c,
        id,
        actor,
        action,
        d.jeepney_id,
        assigned,
        d.version + 1,
      );
      await c.query('COMMIT');
      return token ? { token, jeepneyId: assigned } : {};
    } catch (e) {
      await c.query('ROLLBACK');
      throw e;
    } finally {
      c.release();
    }
  }
}
