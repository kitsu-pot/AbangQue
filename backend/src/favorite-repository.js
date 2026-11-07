export class FavoriteRepository {
  constructor(pool) { this.pool = pool; }
  async catalog() {
    const { rows } = await this.pool.query('SELECT id, origin, destination FROM registered_routes WHERE active ORDER BY origin, destination, id');
    return { routes: rows.map(r => ({ ...r, isDemo: false })), assignments: [] };
  }
  async list(passengerId) {
    const { rows } = await this.pool.query(`SELECT f.route_key AS "routeId",
      COALESCE(r.origin,f.origin) AS origin, COALESCE(r.destination,f.destination) AS destination,
      COALESCE(r.active,false) AS available, f.created_at AS "savedAt"
      FROM passenger_favorite_routes f LEFT JOIN registered_routes r ON r.id=f.route_id
      WHERE f.passenger_id=$1 ORDER BY f.created_at DESC, f.route_key`, [passengerId]);
    return rows;
  }
  async save(passengerId, routeId) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const route = (await client.query('SELECT id,origin,destination FROM registered_routes WHERE id=$1 AND active FOR SHARE', [routeId])).rows[0];
      if (!route) { await client.query('ROLLBACK'); return false; }
      await client.query(`INSERT INTO passenger_favorite_routes(passenger_id,route_key,route_id,origin,destination)
        VALUES($1,$2,$2,$3,$4) ON CONFLICT(passenger_id,route_key) DO NOTHING`,
        [passengerId, route.id, route.origin, route.destination]);
      await client.query('COMMIT');
      return true;
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async remove(passengerId, routeId) {
    await this.pool.query('DELETE FROM passenger_favorite_routes WHERE passenger_id=$1 AND route_key=$2', [passengerId, routeId]);
  }
}
