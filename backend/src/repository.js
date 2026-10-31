const selection = `
  SELECT j.id, j.name, j.source, u.latitude, u.longitude, u.status,
         u.recorded_at, seen.last_seen_at
  FROM jeepneys j
  LEFT JOIN LATERAL (
    SELECT latitude, longitude, status, recorded_at FROM location_status_updates
    WHERE jeepney_id = j.id ORDER BY recorded_at DESC, id DESC LIMIT 1
  ) u ON true
  LEFT JOIN LATERAL (
    SELECT received_at AS last_seen_at FROM location_status_updates
    WHERE jeepney_id = j.id ORDER BY received_at DESC LIMIT 1
  ) seen ON true
`;
export class PostgresRepository {
  constructor(pool) { this.pool = pool; }
  async health() { await this.pool.query('SELECT 1'); }
  async list(includeDemo) {
    return (await this.pool.query(selection + ' WHERE ($1 OR j.source = \'device\') ORDER BY j.id', [includeDemo])).rows;
  }
  async get(id, includeDemo) {
    return (await this.pool.query(selection + ' WHERE j.id = $1 AND ($2 OR j.source = \'device\')', [id, includeDemo])).rows[0];
  }
  async credential(id) {
    return (await this.pool.query('SELECT id, jeepney_id, secret_hash, revoked_at FROM device_credentials WHERE id = $1', [id])).rows[0];
  }
  async insertUpdate(credential, input) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Recheck under lock so revocation cannot race authentication and ingestion.
      const { rows } = await client.query('SELECT id FROM device_credentials WHERE id=$1 AND jeepney_id=$2 AND revoked_at IS NULL AND secret_hash=$3 FOR SHARE',
        [credential.id, input.jeepneyId, credential.secret_hash]);
      if (!rows.length) {
        await client.query('ROLLBACK');
        return { revoked: true };
      }
      const result = await client.query(`
        INSERT INTO location_status_updates
          (jeepney_id, source, credential_id, latitude, longitude, status, recorded_at)
        VALUES ($1, 'device', $2, $3, $4, $5, $6)
        ON CONFLICT (credential_id, recorded_at) DO NOTHING
        RETURNING id, received_at`,
        [input.jeepneyId, credential.id, input.latitude, input.longitude, input.status, input.timestamp]);
      await client.query('COMMIT');
      return result.rows[0] ?? { duplicate: true };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }
}

