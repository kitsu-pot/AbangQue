import { randomUUID } from 'node:crypto';

const publicFields = 'id, full_name, email, role';
export class PassengerRepository {
  constructor(pool) { this.pool = pool; }
  async findByEmail(email) {
    return (await this.pool.query('SELECT id, password_hash, role FROM passenger_accounts WHERE email=$1', [email])).rows[0];
  }
  async register({ fullName, email, passwordHash, tokenHash, ttl }) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const user = (await client.query(`INSERT INTO passenger_accounts(id, full_name, email, password_hash)
        VALUES ($1,$2,$3,$4) RETURNING ${publicFields}`, [randomUUID(), fullName, email, passwordHash])).rows[0];
      const session = await this.insertSession(client, user.id, tokenHash, ttl);
      await client.query('COMMIT');
      return { user, ...session };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }
  async insertSession(client, id, tokenHash, ttl) {
    return (await client.query(`INSERT INTO passenger_sessions(token_hash, passenger_id, expires_at)
      VALUES ($1,$2,now() + $3 * interval '1 second') RETURNING expires_at`, [tokenHash, id, ttl])).rows[0];
  }
  async login(id, tokenHash, ttl, verifiedPasswordHash) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Serialize session creation against password changes/deletion. A password
      // verified before either operation cannot create a session afterwards.
      const user = (await client.query(`SELECT ${publicFields}, password_hash FROM passenger_accounts
        WHERE id=$1 AND role='PASSENGER' FOR UPDATE`, [id])).rows[0];
      if (!user || user.password_hash !== verifiedPasswordHash) {
        await client.query('ROLLBACK'); return null;
      }
      const session = await this.insertSession(client, id, tokenHash, ttl);
      await client.query('COMMIT');
      return { ...user, ...session };
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async accountAction(tokenHash, action) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const account = (await client.query(`SELECT a.id, a.password_hash FROM passenger_accounts a
        JOIN passenger_sessions s ON s.passenger_id=a.id
        WHERE s.token_hash=$1 AND a.role='PASSENGER' FOR UPDATE OF a`, [tokenHash])).rows[0];
      // Recheck after acquiring the account lock, in a new statement snapshot.
      const session = account && (await client.query(`SELECT token_hash FROM passenger_sessions
        WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE`, [tokenHash])).rows[0];
      if (!session) throw Object.assign(new Error('Invalid session'), { accountError: 'SESSION_INVALID' });
      await action(client, account);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; }
    finally { client.release(); }
  }
  async changePassword(tokenHash, verifyAndHash) {
    await this.accountAction(tokenHash, async (client, account) => {
      const passwordHash = await verifyAndHash(account.password_hash);
      await client.query('UPDATE passenger_accounts SET password_hash=$2, updated_at=now() WHERE id=$1', [account.id, passwordHash]);
      await client.query(`UPDATE passenger_sessions SET revoked_at=COALESCE(revoked_at,now())
        WHERE passenger_id=$1 AND token_hash<>$2`, [account.id, tokenHash]);
    });
  }
  async deleteAccount(tokenHash, verify) {
    await this.accountAction(tokenHash, async (client, account) => {
      await verify(account.password_hash);
      // Existing foreign keys cascade ONLY passenger sessions and favorites.
      await client.query('DELETE FROM passenger_accounts WHERE id=$1', [account.id]);
    });
  }
  async session(tokenHash) {
    return (await this.pool.query(`SELECT a.id, a.full_name, a.email, a.role, s.expires_at
      FROM passenger_sessions s JOIN passenger_accounts a ON a.id=s.passenger_id
      WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at > now()`, [tokenHash])).rows[0];
  }
  async updateProfile(tokenHash, fullName) {
    return (await this.pool.query(`UPDATE passenger_accounts a SET full_name=$2, updated_at=now()
      WHERE a.role='PASSENGER' AND EXISTS (SELECT 1 FROM passenger_sessions s
        WHERE s.passenger_id=a.id AND s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now())
      RETURNING ${publicFields}`, [tokenHash, fullName])).rows[0];
  }
  async revoke(tokenHash) {
    await this.pool.query('UPDATE passenger_sessions SET revoked_at=COALESCE(revoked_at,now()) WHERE token_hash=$1', [tokenHash]);
  }
}
