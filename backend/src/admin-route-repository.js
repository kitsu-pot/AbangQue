const columns = `r.id,r.origin,r.destination,r.active,r.display_name AS "displayName",r.description,
 r.origin_terminal AS "originTerminal",r.destination_terminal AS "destinationTerminal",
 r.boarding_notes AS "boardingNotes",r.administrative_notes AS "administrativeNotes",
 r.operations_verified AS "operationsVerified",r.version,r.created_at AS "createdAt",r.updated_at AS "updatedAt",
 (SELECT count(*)::int FROM jeepneys j WHERE j.route_id=r.id) AS "assignedCount"`;
export class AdminRouteRepository {
  constructor(pool) { this.pool = pool; }
  async get(id) { return (await this.pool.query(`SELECT ${columns} FROM registered_routes r WHERE r.id=$1`, [id])).rows[0]; }
  async list({search, municipality, status, page, pageSize}) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const where = `WHERE ($1='' OR strpos(lower(concat_ws(' ',r.origin,r.destination,r.display_name,r.id::text)),lower($1))>0)
        AND ($2='all' OR r.origin=$2 OR r.destination=$2) AND ($3='all' OR r.active=($3='active'))`;
      const args=[search,municipality,status];
      const total=(await client.query(`SELECT count(*)::int AS n FROM registered_routes r ${where}`,args)).rows[0].n;
      const counts=(await client.query('SELECT count(*)::int AS total,count(*) FILTER(WHERE active)::int AS active,count(*) FILTER(WHERE NOT active)::int AS inactive FROM registered_routes')).rows[0];
      const items=(await client.query(`SELECT ${columns} FROM registered_routes r ${where} ORDER BY r.origin,r.destination,r.id LIMIT $4 OFFSET $5`,[...args,pageSize,(page-1)*pageSize])).rows;
      await client.query('COMMIT'); return {items,total,counts,page,pageSize};
    } catch(e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async create(v) {
    return (await this.pool.query(`INSERT INTO registered_routes(origin,destination,active,display_name,description,origin_terminal,destination_terminal,boarding_notes,administrative_notes,operations_verified)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,[v.origin,v.destination,v.active,v.displayName,v.description,v.originTerminal,v.destinationTerminal,v.boardingNotes,v.administrativeNotes,v.operationsVerified])).rows[0].id;
  }
  async update(id,v,activation=false) {
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN');
      const row=(await client.query('SELECT version FROM registered_routes WHERE id=$1 FOR UPDATE',[id])).rows[0];
      if(!row) throw new Error('ROUTE_NOT_FOUND');
      if(row.version!==v.expectedVersion) throw new Error('RECORD_CHANGED');
      if(activation) await client.query('UPDATE registered_routes SET active=$2,version=version+1,updated_at=clock_timestamp() WHERE id=$1',[id,v.active]);
      else await client.query(`UPDATE registered_routes SET display_name=$2,description=$3,origin_terminal=$4,destination_terminal=$5,boarding_notes=$6,administrative_notes=$7,operations_verified=$8,version=version+1,updated_at=clock_timestamp() WHERE id=$1`,[id,v.displayName,v.description,v.originTerminal,v.destinationTerminal,v.boardingNotes,v.administrativeNotes,v.operationsVerified]);
      await client.query('COMMIT');
    } catch(e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
}
