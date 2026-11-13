import { presentJeepney } from './presenter.js';

const fields = `j.id,j.name,j.source,j.active,j.plate_number,j.description,j.administrative_notes,
  j.route_id,j.version,j.created_at,j.updated_at,r.origin,r.destination,r.active AS route_active`;
const reportJoins = `LEFT JOIN LATERAL (SELECT latitude,longitude,status,recorded_at FROM location_status_updates
  WHERE jeepney_id=j.id ORDER BY recorded_at DESC,id DESC LIMIT 1) u ON true
  LEFT JOIN LATERAL (SELECT received_at AS last_seen_at FROM location_status_updates
  WHERE jeepney_id=j.id ORDER BY received_at DESC LIMIT 1) seen ON true`;
const selection = `SELECT ${fields},u.latitude,u.longitude,u.status,u.recorded_at,seen.last_seen_at
  FROM jeepneys j LEFT JOIN registered_routes r ON r.id=j.route_id ${reportJoins}`;
function present(row, now, staleSeconds) {
  const report = presentJeepney(row, now, staleSeconds);
  const future = (row.recorded_at && row.recorded_at.getTime() > now) || (row.last_seen_at && row.last_seen_at.getTime() > now);
  const stale = report.isStale || future;
  return { id: row.id, name: row.name, source: row.source, active: row.active,
    plateNumber: row.plate_number, description: row.description, administrativeNotes: row.administrative_notes,
    route: row.route_id ? { id: row.route_id, origin: row.origin, destination: row.destination, active: row.route_active } : null,
    version: row.version, createdAt: row.created_at.toISOString(), updatedAt: row.updated_at.toISOString(),
    position: report.position, timestamp: report.timestamp, lastSeenAt: report.lastSeenAt,
    freshness: !report.timestamp ? 'MISSING' : stale ? 'STALE' : 'FRESH',
    status: row.active && row.source === 'device' && !stale ? report.status ?? 'UNKNOWN' : 'UNKNOWN',
    lastReportedStatus: report.lastReportedStatus, eta: null };
}

export class AdminJeepneyRepository {
  constructor(pool) { this.pool = pool; }
  async routeOptions() {
    return (await this.pool.query('SELECT id,origin,destination,active FROM registered_routes ORDER BY origin,destination,id')).rows;
  }
  async get(id, now, staleSeconds) {
    const row = (await this.pool.query(selection + ' WHERE j.id=$1', [id])).rows[0];
    return row ? present(row, now, staleSeconds) : null;
  }
  async list({ search, status, routeId, page, pageSize }, now, staleSeconds) {
    // strpos treats %, _ and backslashes literally, unlike unescaped LIKE patterns.
    const where = ` WHERE ($1='' OR strpos(lower(j.id),lower($1))>0 OR strpos(lower(j.name),lower($1))>0
      OR strpos(lower(COALESCE(j.plate_number,'')),lower($1))>0)
      AND ($2='all' OR j.active=($2='active'))
      AND ($3='all' OR ($3='unassigned' AND j.route_id IS NULL) OR j.route_id::text=$3)`;
    const values = [search, status, routeId];
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const total = (await client.query('SELECT count(*)::int AS total FROM jeepneys j' + where, values)).rows[0].total;
      const registeredTotal = (await client.query("SELECT count(*)::int AS total FROM jeepneys WHERE source='device'")).rows[0].total;
      const rows = (await client.query(selection + where + ' ORDER BY j.id LIMIT $4 OFFSET $5', [...values, pageSize, (page - 1) * pageSize])).rows;
      await client.query('COMMIT');
      return { items: rows.map(r => present(r, now, staleSeconds)), total, registeredTotal, page, pageSize,
        updatedAt: new Date(now).toISOString(), staleAfterSeconds: staleSeconds };
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async eligibleRoute(client, id) {
    if (id === null) return;
    const route = (await client.query('SELECT id FROM registered_routes WHERE id=$1 AND active FOR SHARE', [id])).rows[0];
    if (!route) throw new Error('ROUTE_INELIGIBLE');
  }
  async create(input) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await this.eligibleRoute(client, input.routeId);
      await client.query(`INSERT INTO jeepneys(id,name,source,active,plate_number,description,administrative_notes,route_id)
        VALUES($1,$2,'device',$3,$4,$5,$6,$7)`, [input.id, input.name, input.active, input.plateNumber, input.description, input.administrativeNotes, input.routeId]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async update(id, input, activation = false) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query('SELECT version,source,route_id FROM jeepneys WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!row) throw new Error('JEEPNEY_NOT_FOUND');
      if (row.source !== 'device') throw new Error('TEST_RECORD_READ_ONLY');
      if (row.version !== input.expectedVersion) throw new Error('RECORD_CHANGED');
      if (activation) {
        await client.query('UPDATE jeepneys SET active=$2,version=version+1,updated_at=clock_timestamp() WHERE id=$1', [id, input.active]);
      } else {
        // An already assigned inactive route may be retained, but not newly assigned.
        if (input.routeId !== row.route_id) await this.eligibleRoute(client, input.routeId);
        await client.query(`UPDATE jeepneys SET name=$2,plate_number=$3,description=$4,administrative_notes=$5,
          route_id=$6,version=version+1,updated_at=clock_timestamp() WHERE id=$1`,
        [id, input.name, input.plateNumber, input.description, input.administrativeNotes, input.routeId]);
      }
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
}
