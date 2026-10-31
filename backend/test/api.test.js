import { test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { issueCredential, matchesSecret } from '../src/security.js';
import { presentJeepney } from '../src/presenter.js';
import { PostgresRepository } from '../src/repository.js';
const now = Date.parse('2026-10-31T00:00:00Z');
const config = loadConfig({ DATABASE_URL: 'postgresql://test:test@localhost/test' });
function setup(overrides = {}) {
  const key = issueCredential();
  const credential = { id: key.id, secret_hash: key.secretHash, jeepney_id: 'LAB-001', revoked_at: null };
  const row = { id: 'LAB-001', name: 'Synthetic lab fixture', source: 'device', latitude: 13.44, longitude: 121.84,
    status: 'AVAILABLE', recorded_at: new Date(now), last_seen_at: new Date(now) };
  const repository = {
    health: async () => {},
    list: async include => include ? [row, { ...row, id: 'DEMO-01', source: 'demo' }] : [row],
    get: async id => id === row.id ? row : undefined,
    credential: async id => id === key.id ? credential : undefined,
    insertUpdate: async () => ({ id: '1', received_at: new Date(now) }),
  };
  const app = createApp({ repository, config: { ...config, ...overrides }, clock: () => now });
  const body = { jeepneyId: 'LAB-001', latitude: 13.44, longitude: 121.84, status: 'FULL', timestamp: new Date(now).toISOString() };
  const post = () => request(app).post('/api/device-updates').set('Authorization', 'Bearer ' + key.token);
  return { app, repository, credential, row, body, post };
}
test('health reports database availability without leaking failures', async () => {
  const s = setup();
  assert.equal((await request(s.app).get('/health')).status, 200);
  s.repository.health = async () => { throw new Error('secret database password'); };
  const response = await request(s.app).get('/health');
  assert.equal(response.status, 503);
  assert.ok(!response.text.includes('password'));
});
test('passenger list defaults to device rows and never contains credentials or ETA claims', async () => {
  const s = setup();
  const { body } = await request(s.app).get('/api/jeepneys').expect(200);
  assert.equal(body.data.length, 1);
  assert.equal(body.data[0].connectionStatus, 'ONLINE');
  assert.equal(body.data[0].eta, null);
  assert.ok(!JSON.stringify(body).includes('secret'));
});
test('demo inclusion is explicitly configured and never ONLINE', async () => {
  const s = setup({ INCLUDE_DEMO: 'true' });
  const { body } = await request(s.app).get('/api/jeepneys').expect(200);
  assert.equal(body.data[1].connectionStatus, 'DEMO');
  assert.equal(body.data[1].isDemo, true);
});
test('detail, invalid ID, missing vehicle, and unknown routes', async () => {
  const s = setup();
  await request(s.app).get('/api/jeepneys/LAB-001').expect(200);
  await request(s.app).get('/api/jeepneys/UNKNOWN').expect(404);
  await request(s.app).get('/api/jeepneys/invalid!').expect(400);
  await request(s.app).get('/missing').expect(404);
});
test('valid authenticated ingestion returns server receipt time', async () => {
  const s = setup();
  let recorded;
  s.repository.insertUpdate = async (key, data) => { recorded = data; return { id: '2', received_at: new Date(now) }; };
  const response = await s.post().send(s.body).expect(201);
  assert.equal(recorded.jeepneyId, 'LAB-001');
  assert.equal(response.body.data.source, 'device');
  assert.equal(response.body.data.receivedAt, new Date(now).toISOString());
});
test('missing, malformed, unknown and wrong device secrets are rejected', async () => {
  const s = setup();
  for (const token of ['', 'Bearer nope', 'Bearer ' + issueCredential().token, 'Bearer ' + s.credential.id + '.' + '0'.repeat(64)]) {
    await request(s.app).post('/api/device-updates').set('Authorization', token).send(s.body).expect(401);
  }
});
test('revoked credentials and revocation during ingestion are rejected', async () => {
  const s = setup();
  s.credential.revoked_at = new Date(now);
  await s.post().send(s.body).expect(401);
  s.credential.revoked_at = null;
  s.repository.insertUpdate = async () => ({ revoked: true });
  await s.post().send(s.body).expect(401);
});
test('credentials cannot update another vehicle or demo vehicle', async () => {
  const s = setup();
  for (const jeepneyId of ['LAB-002', 'DEMO-01']) await s.post().send({ ...s.body, jeepneyId }).expect(403);
});
for (const [name, patch] of [
  ['latitude range', { latitude: 91 }], ['longitude range', { longitude: -181 }],
  ['numeric string', { latitude: '13.4' }], ['null', { latitude: null }],
  ['unknown status', { status: 'EMPTY' }], ['unknown field', { source: 'demo' }],
  ['invalid date', { timestamp: '2026-02-30T00:00:00Z' }],
  ['missing timezone', { timestamp: '2026-10-31T00:00:00' }],
  ['old timestamp', { timestamp: '2020-01-01T00:00:00Z' }],
  ['future timestamp', { timestamp: '2027-01-01T00:00:00Z' }],
]) test('validation rejects ' + name, async () => {
  const s = setup();
  await s.post().send({ ...s.body, ...patch }).expect(400);
});
test('missing fields, wrong media type, malformed JSON, oversized body', async () => {
  const s = setup();
  await s.post().send({}).expect(400);
  await s.post().type('text').send('hello').expect(415);
  await s.post().type('json').send('{').expect(400);
  await s.post().send({ ...s.body, padding: 'x'.repeat(9000) }).expect(413);
});
test('duplicates cannot refresh last-seen; API signals conflict', async () => {
  const s = setup();
  s.repository.insertUpdate = async () => ({ duplicate: true });
  await s.post().send(s.body).expect(409);
});
test('offline is evaluated on reads, including exact threshold and delayed old samples', () => {
  const { row } = setup();
  for (const sample of [
    { ...row, recorded_at: new Date(now - 120000) },
    { ...row, last_seen_at: new Date(now - 120000) },
    { ...row, recorded_at: null, last_seen_at: null },
  ]) {
    const result = presentJeepney(sample, now, 120);
    assert.equal(result.connectionStatus, 'OFFLINE');
    assert.equal(result.status, null);
    assert.equal(result.isStale, true);
  }
  assert.equal(presentJeepney({ ...row, recorded_at: new Date(now - 119999) }, now, 120).connectionStatus, 'ONLINE');
});
test('database errors are sanitized', async () => {
  const s = setup();
  s.repository.list = async () => { throw new Error('private connection string'); };
  const result = await request(s.app).get('/api/jeepneys').expect(503);
  assert.deepEqual(result.body, { error: 'SERVICE_UNAVAILABLE' });
});
test('ingestion rate limiting', async () => {
  const s = setup({ DEVICE_RATE_LIMIT: 1 });
  await s.post().send(s.body).expect(201);
  await s.post().send(s.body).expect(429);
});
test('config fails closed and secrets are hash-only', () => {
  assert.throws(() => loadConfig({}));
  assert.throws(() => loadConfig({ DATABASE_URL: config.DATABASE_URL, INCLUDE_DEMO: 'yes' }));
  const key = issueCredential();
  assert.ok(!key.secretHash.includes(key.token));
  assert.ok(matchesSecret(key.token.split('.')[1], key.secretHash));
  assert.ok(!matchesSecret('wrong', key.secretHash));
});
test('SQL adapter parameterizes values, commits, rolls back, releases connections', async () => {
  const calls = [];
  let fail = false;
  let released = 0;
  const client = { query: async (sql, params) => {
    calls.push({ sql, params });
    if (sql.startsWith('SELECT id')) return { rows: [{ id: 'credential' }] };
    if (sql.includes('INSERT INTO')) {
      if (fail) throw new Error('failure');
      return { rows: [{ id: '1' }] };
    }
    return { rows: [] };
  }, release: () => released++ };
  const repository = new PostgresRepository({ connect: async () => client });
  const s = setup();
  await repository.insertUpdate(s.credential, s.body);
  assert.equal(calls.at(-1).sql, 'COMMIT');
  assert.equal(calls.find(c => c.sql.includes('INSERT INTO')).params[0], 'LAB-001');
  fail = true;
  await assert.rejects(repository.insertUpdate(s.credential, s.body));
  assert.equal(calls.at(-1).sql, 'ROLLBACK');
  assert.equal(released, 2);
});

