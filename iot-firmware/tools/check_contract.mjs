// Tests the ACTUAL native C++ serializer against Express with an in-memory repository.
// No PostgreSQL, existing server, real device token or external HTTP destination is used.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createApp } from '../../backend/src/app.js';
import { loadConfig } from '../../backend/src/config.js';
import { hashSecret, parseToken } from '../../backend/src/security.js';
const require = createRequire(new URL('../../backend/package.json', import.meta.url));
const request = require('supertest');
const binary = new URL('../.pio/build/native/' + (process.platform === 'win32' ? 'program.exe' : 'program'), import.meta.url);
const fixture = JSON.parse(execFileSync(fileURLToPath(binary), ['--contract-fixture'], { encoding: 'utf8' }));
const token = parseToken(fixture.authorization);
const credential = { id: token.id, device_id: 'TEST-DEVICE', jeepney_id: fixture.body.jeepneyId,
  source: 'device', enabled: true, revoked_at: null, secret_hash: hashSecret(token.secret) };
let inserted = 0;
const repository = {
  credential: async id => id === token.id ? credential : undefined,
  insertUpdate: async (_credential, input) => {
    assert.deepEqual(input, fixture.body);
    return inserted++ ? { duplicate: true } : { id: '1', received_at: input.timestamp };
  },
};
const app = createApp({ repository,
  config: loadConfig({ DATABASE_URL: 'postgresql://unused@localhost/unused' }),
  clock: () => Date.parse(fixture.body.timestamp),
});
const post = (body = fixture.body, authorization = fixture.authorization) => request(app)
  .post('/api/device-updates').set('Authorization', authorization).set('Content-Type', fixture.contentType).send(body);
const accepted = await post().expect(201);
assert.equal(accepted.body.data.source, 'device'); // Mock fixture only; never stored as physical telemetry.
assert.equal(accepted.body.data.isSimulated, false);
await post().expect(409);
await post({ ...fixture.body, jeepneyId: 'OTHER-VEHICLE' }).expect(403);
await post({ jeepneyId: fixture.body.jeepneyId, status: 'FULL', timestamp: fixture.body.timestamp }).expect(400);
credential.enabled = false;
await post().expect(401);
credential.enabled = true;
credential.revoked_at = new Date();
await post().expect(401);
credential.revoked_at = null;
await post(fixture.body, 'Bearer passenger-session').expect(401);
console.log('7 firmware/Express contract checks passed (in-memory DEMO fixtures; no database/hardware).');
