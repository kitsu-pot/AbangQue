// Every history lookup is bounded to the latest row using existing indexes (plus 009).
const deviceRecords = `SELECT d.id,d.jeepney_id,d.enabled,d.legacy,
 CASE WHEN bool_or(c.revoked_at IS NULL) FILTER(WHERE c.id IS NOT NULL) THEN 'Provisioned'
 WHEN count(c.id)>0 THEN 'Revoked' ELSE 'Not provisioned' END AS credential_state,
 max(u.recorded_at) AS timestamp,max(s.received_at) AS last_seen_at
 FROM iot_devices d LEFT JOIN device_credentials c ON c.device_id=d.id
 LEFT JOIN LATERAL(SELECT recorded_at FROM location_status_updates WHERE credential_id=c.id ORDER BY recorded_at DESC LIMIT 1)u ON true
 LEFT JOIN LATERAL(SELECT received_at FROM location_status_updates WHERE credential_id=c.id ORDER BY received_at DESC LIMIT 1)s ON true
 WHERE d.source='device' GROUP BY d.id`;
const fresh = (measurement, received) =>
  `COALESCE(${measurement}<=$1 AND ${received}<=$1 AND ${measurement}>$1::timestamptz-$2*interval '1 second' AND ${received}>$1::timestamptz-$2*interval '1 second',false)`;
const records = `WITH devices AS MATERIALIZED (${deviceRecords}), records AS (
 SELECT j.id,j.name,j.active,j.source,j.plate_number AS "plateNumber",
 CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('id',r.id,'origin',r.origin,'destination',r.destination,'active',r.active) END AS route,
 COALESCE((SELECT jsonb_agg(jsonb_build_object('id',d.id,'enabled',d.enabled,'legacy',d.legacy,'credentialState',d.credential_state,'timestamp',d.timestamp,'lastSeenAt',d.last_seen_at) ORDER BY d.enabled DESC,d.id) FROM devices d WHERE d.jeepney_id=j.id),'[]') AS devices,
 u.latitude,u.longitude,u.recorded_at AS timestamp,u.received_at AS "reportReceivedAt",seen.received_at AS "lastSeenAt",u.status AS "lastReportedStatus",
 CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object('id',d.id,'enabled',d.enabled,'currentJeepneyId',d.jeepney_id,'credentialRevoked',c.revoked_at IS NOT NULL) END AS "reportDevice",
 ${fresh("u.recorded_at", "seen.received_at")} AS fresh
 FROM jeepneys j LEFT JOIN registered_routes r ON r.id=j.route_id
 LEFT JOIN LATERAL(SELECT latitude,longitude,recorded_at,received_at,status,credential_id FROM location_status_updates WHERE jeepney_id=j.id AND source='device' ORDER BY recorded_at DESC,id DESC LIMIT 1)u ON true
 LEFT JOIN LATERAL(SELECT received_at FROM location_status_updates WHERE jeepney_id=j.id AND source='device' ORDER BY received_at DESC LIMIT 1)seen ON true
 LEFT JOIN device_credentials c ON c.id=u.credential_id LEFT JOIN iot_devices d ON d.id=c.device_id
 WHERE j.source='device')`;
export function presentMonitoring(r) {
  const valid =
    Number.isFinite(r.latitude) &&
    Number.isFinite(r.longitude) &&
    Math.abs(r.latitude) <= 90 &&
    Math.abs(r.longitude) <= 180;
  const current =
    valid &&
    r.fresh &&
    r.active &&
    r.reportDevice?.enabled &&
    !r.reportDevice.credentialRevoked &&
    r.reportDevice.currentJeepneyId === r.id;
  const { latitude, longitude, fresh: isFresh, ...rest } = r;
  return {
    ...rest,
    position: valid ? { latitude, longitude } : null,
    coordinateState: !r.timestamp ? "MISSING" : valid ? "VALID" : "INVALID",
    freshness: !r.timestamp ? "MISSING" : isFresh ? "FRESH" : "STALE",
    status: current ? r.lastReportedStatus : "UNKNOWN",
    eta: null,
  };
}
export class AdminMonitoringRepository {
  constructor(pool) {
    this.pool = pool;
  }
  async snapshot(v, now, stale) {
    const c = await this.pool.connect();
    try {
      await c.query("BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY");
      const args = [
        new Date(now),
        stale,
        v.search,
        v.routeId,
        v.reporting,
        v.status,
        v.device,
      ];
      const where = `WHERE ($3='' OR strpos(lower(concat_ws(' ',id,"plateNumber")),lower($3))>0)
        AND ($4='all' OR ($4='unassigned' AND route IS NULL) OR route->>'id'=$4)
        AND ($5='all' OR ($5='fresh' AND fresh) OR ($5='stale' AND timestamp IS NOT NULL AND NOT fresh) OR ($5='missing' AND timestamp IS NULL))
        AND ($6='all' OR active=($6='active'))
        AND ($7='all' OR ($7='unassigned' AND jsonb_array_length(devices)=0) OR EXISTS(SELECT 1 FROM jsonb_array_elements(devices)d WHERE
          ($7='enabled' AND (d->>'enabled')::boolean) OR ($7='disabled' AND NOT (d->>'enabled')::boolean)
          OR ($7='revoked' AND d->>'credentialState'='Revoked') OR ($7='unprovisioned' AND d->>'credentialState'='Not provisioned')))`;
      const total = (
        await c.query(
          `${records} SELECT count(*)::int AS n FROM records ${where}`,
          args,
        )
      ).rows[0].n;
      const page = Math.min(v.page, Math.max(1, Math.ceil(total / 100)));
      const items = (
        await c.query(
          `${records} SELECT * FROM records ${where} ORDER BY id LIMIT 100 OFFSET $8`,
          [...args, (page - 1) * 100],
        )
      ).rows.map(presentMonitoring);
      const selected = v.selectedId
        ? (
            await c.query(`${records} SELECT * FROM records WHERE id=$3`, [
              new Date(now),
              stale,
              v.selectedId,
            ])
          ).rows[0]
        : null;
      const counts = (
        await c.query(
          `WITH devices AS (${deviceRecords}), states AS (SELECT *,${fresh("timestamp", "last_seen_at")} AS fresh FROM devices)
        SELECT (SELECT count(*)::int FROM jeepneys WHERE source='device') AS jeepneys,
        (SELECT count(*)::int FROM jeepneys WHERE source<>'device') AS "excludedTestVehicles",
        count(*) FILTER(WHERE fresh)::int AS fresh,
        count(*) FILTER(WHERE timestamp IS NOT NULL AND NOT fresh)::int AS stale,
        count(*) FILTER(WHERE timestamp IS NULL)::int AS missing,
        count(*) FILTER(WHERE NOT enabled OR credential_state='Revoked')::int AS restricted,
        min(LEAST(timestamp,last_seen_at)+$2*interval '1 second') FILTER(WHERE fresh) AS "validUntil"
        FROM states`,
          args.slice(0, 2),
        )
      ).rows[0];
      await c.query("COMMIT");
      return {
        items,
        selected: selected ? presentMonitoring(selected) : null,
        total,
        page,
        pageSize: 100,
        counts,
        updatedAt: new Date(now).toISOString(),
        staleAfterSeconds: stale,
      };
    } catch (e) {
      await c.query("ROLLBACK");
      throw e;
    } finally {
      c.release();
    }
  }
}
