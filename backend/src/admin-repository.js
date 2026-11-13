import { randomUUID } from 'node:crypto';

const reports = `SELECT j.id, j.name, j.source, j.active, r.origin, r.destination, r.active AS route_active, u.recorded_at, u.status, seen.last_seen_at,
  COALESCE(u.recorded_at <= $1::timestamptz AND seen.last_seen_at <= $1::timestamptz
    AND u.recorded_at > $1::timestamptz - $2 * interval '1 second'
    AND seen.last_seen_at > $1::timestamptz - $2 * interval '1 second', false) AS fresh
  FROM jeepneys j
  LEFT JOIN registered_routes r ON r.id=j.route_id
  LEFT JOIN LATERAL (SELECT recorded_at, status FROM location_status_updates
    WHERE jeepney_id=j.id ORDER BY recorded_at DESC, id DESC LIMIT 1) u ON true
  LEFT JOIN LATERAL (SELECT received_at AS last_seen_at FROM location_status_updates
    WHERE jeepney_id=j.id ORDER BY received_at DESC LIMIT 1) seen ON true`;

export class AdminRepository {
  constructor(pool) { this.pool = pool; }
  async provisionFirst(email, passwordHash) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Serialize all first-admin attempts, including different email addresses.
      await client.query('LOCK TABLE admin_accounts IN EXCLUSIVE MODE');
      if ((await client.query('SELECT 1 FROM admin_accounts LIMIT 1')).rowCount)
        throw new Error('Administrator already provisioned');
      await client.query('INSERT INTO admin_accounts(id,email,password_hash) VALUES($1,$2,$3)', [randomUUID(), email, passwordHash]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async findByEmail(email) {
    return (await this.pool.query('SELECT id,email,role,password_hash FROM admin_accounts WHERE email=$1', [email])).rows[0];
  }
  async login(user, tokenHash, ttl) {
    return (await this.pool.query(`INSERT INTO admin_sessions(token_hash,admin_id,expires_at)
      SELECT $1,id,now()+$3 * interval '1 second' FROM admin_accounts
      WHERE id=$2 AND role='ADMIN' AND password_hash=$4 RETURNING expires_at`,
    [tokenHash, user.id, ttl, user.password_hash])).rows[0];
  }
  async session(tokenHash) {
    return (await this.pool.query(`SELECT a.id,a.email,a.role,s.expires_at FROM admin_sessions s
      JOIN admin_accounts a ON a.id=s.admin_id WHERE s.token_hash=$1
      AND s.revoked_at IS NULL AND s.expires_at > now() AND a.role='ADMIN'`, [tokenHash])).rows[0];
  }
  async revoke(tokenHash) {
    await this.pool.query('UPDATE admin_sessions SET revoked_at=now() WHERE token_hash=$1 AND revoked_at IS NULL', [tokenHash]);
  }
  async dashboard(now, staleSeconds) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const counts = (await client.query(`WITH reports AS (${reports}) SELECT
        count(*) FILTER (WHERE source='device')::int AS jeepneys,
        count(*) FILTER (WHERE source<>'device')::int AS "demoJeepneys",
        count(*) FILTER (WHERE source='device' AND active AND fresh)::int AS fresh,
        count(*) FILTER (WHERE source='device' AND active AND NOT fresh)::int AS "staleOrMissing",
        count(*) FILTER (WHERE source='device' AND active AND fresh AND status='FULL')::int AS full,
        count(*) FILTER (WHERE source='device' AND active AND fresh AND status='AVAILABLE')::int AS available,
        min(LEAST(recorded_at,last_seen_at) + $2 * interval '1 second')
          FILTER (WHERE fresh) AS "validUntil"
        FROM reports`, [now, staleSeconds])).rows[0];
      const routes = (await client.query('SELECT count(*)::int AS total FROM registered_routes')).rows[0].total;
      const recent = (await client.query(`WITH reports AS (${reports}) SELECT * FROM reports
        ORDER BY last_seen_at DESC NULLS LAST, id LIMIT 20`, [now, staleSeconds])).rows;
      await client.query('COMMIT');
      return { updatedAt: now.toISOString(), staleAfterSeconds: staleSeconds,
        summary: { ...counts, routes, devices: null },
        recent: recent.map(r => ({ id: r.id, name: r.name, source: r.source, active: r.active,
          route: r.origin ? r.origin + ' → ' + r.destination + (r.route_active ? '' : ' (inactive)') : null,
          timestamp: r.recorded_at?.toISOString() ?? null, lastSeenAt: r.last_seen_at?.toISOString() ?? null,
          freshness: !r.recorded_at ? 'MISSING' : r.fresh ? 'FRESH' : 'STALE',
          status: r.active && r.source === 'device' && r.fresh ? r.status : 'UNKNOWN' })) };
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
}
