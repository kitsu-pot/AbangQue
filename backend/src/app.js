import express from 'express';
import { passengerAuthRouter } from './passenger-auth.js';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { parseToken, matchesSecret } from './security.js';
import { jeepneyId, updateSchema, timestampAllowed } from './validation.js';
import { presentJeepney } from './presenter.js';

export function createApp({ repository, passengerRepository, config, clock = Date.now }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.TRUST_PROXY === 'loopback' ? 'loopback' : false);
  app.use(helmet());
  app.use((_req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  app.get('/health', async (_req, res) => {
    try {
      await repository.health();
      res.json({ status: 'ok', service: 'jeeplink-backend', database: 'reachable', gpsTrackingVerified: false });
    } catch {
      res.status(503).json({ status: 'unavailable', database: 'unreachable' });
    }
  });
  if (passengerRepository) app.use('/api/auth', passengerAuthRouter({ repository: passengerRepository, config }));
  const includeDemo = config.INCLUDE_DEMO === 'true';
  app.get('/api/jeepneys', async (_req, res) => {
    const now = clock();
    const rows = await repository.list(includeDemo);
    res.json({ data: rows.map(row => presentJeepney(row, now, config.STALE_AFTER_SECONDS)),
      meta: { demoIncluded: includeDemo, etaAvailable: false, staleAfterSeconds: config.STALE_AFTER_SECONDS } });
  });
  app.get('/api/jeepneys/:id', async (req, res) => {
    if (!jeepneyId.safeParse(req.params.id).success) return res.status(400).json({ error: 'INVALID_ID' });
    const row = await repository.get(req.params.id, includeDemo);
    if (!row) return res.status(404).json({ error: 'JEEPNEY_NOT_FOUND' });
    res.json({ data: presentJeepney(row, clock(), config.STALE_AFTER_SECONDS) });
  });
  app.post('/api/device-updates',
    rateLimit({ windowMs: 60000, limit: config.DEVICE_RATE_LIMIT, standardHeaders: 'draft-8', legacyHeaders: false,
      message: { error: 'RATE_LIMITED' } }),
    async (req, res, next) => {
      const token = parseToken(req.headers.authorization);
      if (!token || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(token.id))
        return res.status(401).json({ error: 'UNAUTHORIZED' });
      const credential = await repository.credential(token.id);
      const valid = matchesSecret(token.secret, credential?.secret_hash);
      if (!valid || !credential || credential.revoked_at) return res.status(401).json({ error: 'UNAUTHORIZED' });
      req.credential = credential;
      next();
    },
    (req, res, next) => req.is('application/json') ? next() : res.status(415).json({ error: 'JSON_REQUIRED' }),
    express.json({ limit: '8kb' }),
    async (req, res) => {
      const parsed = updateSchema.safeParse(req.body);
      if (!parsed.success) return res.status(400).json({ error: 'INVALID_UPDATE',
        fields: parsed.error.issues.map(issue => ({ field: issue.path.join('.'), message: issue.message })) });
      const input = parsed.data;
      if (req.credential.jeepney_id !== input.jeepneyId) return res.status(403).json({ error: 'DEVICE_NOT_ASSIGNED' });
      if (!timestampAllowed(input.timestamp, clock(), config)) return res.status(400).json({ error: 'TIMESTAMP_OUT_OF_RANGE' });
      const result = await repository.insertUpdate(req.credential, input);
      if (result.revoked) return res.status(401).json({ error: 'UNAUTHORIZED' });
      if (result.duplicate) return res.status(409).json({ error: 'DUPLICATE_UPDATE' });
      res.status(201).json({ data: { id: String(result.id), jeepneyId: input.jeepneyId, source: 'device',
        receivedAt: new Date(result.received_at).toISOString() } });
    });
  app.use((_req, res) => res.status(404).json({ error: 'NOT_FOUND' }));
  app.use((error, _req, res, _next) => {
    if (error.type === 'entity.too.large') return res.status(413).json({ error: 'BODY_TOO_LARGE' });
    if (error.type === 'entity.parse.failed') return res.status(400).json({ error: 'INVALID_JSON' });
    // Never send database errors, headers, secrets, or payloads to clients/logs.
    res.status(503).json({ error: 'SERVICE_UNAVAILABLE' });
  });
  return app;
}

