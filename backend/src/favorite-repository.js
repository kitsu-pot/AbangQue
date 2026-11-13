export class FavoriteRepository {
  constructor(pool) { this.pool = pool; }
  async catalog() {
    // One SQL snapshot keeps route identities and eligible assignments consistent.
    const { rows } = await this.pool.query(`SELECT r.id,r.origin,r.destination,
      COALESCE(array_agg(j.id ORDER BY j.id) FILTER (WHERE j.id IS NOT NULL), '{}') AS jeepney_ids
      FROM registered_routes r LEFT JOIN jeepneys j ON j.route_id=r.id AND j.active AND j.source='device'
      WHERE r.active GROUP BY r.id ORDER BY r.origin,r.destination,r.id`);
    return { routes: rows.map(r => ({ id: r.id, origin: r.origin, destination: r.destination, isDemo: false })),
      assignments: rows.flatMap(r => r.jeepney_ids.map(id => ({ routeId: r.id, jeepneyId: id }))) };
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
