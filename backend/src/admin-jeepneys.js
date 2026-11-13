import { Router, json } from 'express';
import { rateLimit } from 'express-rate-limit';
import { z } from 'zod';
import { jeepneyId } from './validation.js';

const text = max => z.string().trim().max(max).refine(v => !/[\u0000-\u001f\u007f]/u.test(v), 'Use plain text without control characters.');
const fields = {
  name: text(120).min(1, 'Enter a vehicle display name.'),
  plateNumber: z.union([z.null(), z.string().trim().toUpperCase().regex(/^[A-Z0-9][A-Z0-9 -]{1,19}$/, 'Use 2–20 letters, digits, spaces or hyphens.')]),
  description: text(500), administrativeNotes: text(2000), routeId: z.uuid().nullable(),
};
export const createJeepney = z.object({ id: jeepneyId, ...fields, active: z.boolean() }).strict();
export const editJeepney = z.object({ ...fields, expectedVersion: z.number().int().positive().max(2147483646) }).strict();
const activation = z.object({ active: z.boolean(), expectedVersion: z.number().int().positive().max(2147483646) }).strict();
const query = z.object({ search: text(120).default(''), status: z.enum(['all', 'active', 'inactive']).default('all'),
  routeId: z.union([z.uuid(), z.literal('unassigned'), z.literal('all')]).default('all'),
  page: z.coerce.number().int().min(1).max(100000).default(1), pageSize: z.coerce.number().int().min(1).max(100).default(20),
}).strict();
const validate = (schema, from = 'body') => (req, res, next) => {
  const result = schema.safeParse(req[from]);
  if (!result.success) return res.status(400).json({ error: 'INVALID_JEEPNEY_INPUT', fields: result.error.issues.map(i => ({ field: i.path.join('.'), message: i.message })) });
  req.input = result.data; next();
};

// Mounted only AFTER the existing administrator session/role and CSRF checks.
export function adminJeepneyRouter({ repository, config, clock }) {
  const router = Router();
  const writeLimit = rateLimit({ windowMs: 60000, limit: 60, keyGenerator: req => req.admin.id,
    standardHeaders: 'draft-8', legacyHeaders: false, message: { error: 'ADMIN_WRITE_RATE_LIMITED' } });
  const body = [writeLimit, (req, res, next) => req.is('application/json') ? next() : res.status(415).json({ error: 'JSON_REQUIRED' }), json({ limit: '16kb' })];
  router.get('/route-options', async (_req, res) => res.json({ data: await repository.routeOptions() }));
  router.get('/jeepneys', validate(query, 'query'), async (req, res) => res.json({ data: await repository.list(req.input, clock(), config.STALE_AFTER_SECONDS) }));
  router.post('/jeepneys', ...body, validate(createJeepney), async (req, res) => {
    await repository.create(req.input);
    res.status(201).json({ data: await repository.get(req.input.id, clock(), config.STALE_AFTER_SECONDS) });
  });
  router.use('/jeepneys/:id', (req, res, next) => {
    if (!jeepneyId.safeParse(req.params.id).success) return res.status(400).json({ error: 'INVALID_ID' });
    next();
  });
  router.get('/jeepneys/:id', async (req, res) => {
    const now = clock();
    const row = await repository.get(req.params.id, now, config.STALE_AFTER_SECONDS);
    if (!row) return res.status(404).json({ error: 'JEEPNEY_NOT_FOUND' });
    res.json({ data: { record: row, updatedAt: new Date(now).toISOString(), staleAfterSeconds: config.STALE_AFTER_SECONDS } });
  });
  router.put('/jeepneys/:id', ...body, validate(editJeepney), async (req, res) => {
    await repository.update(req.params.id, req.input);
    res.json({ data: await repository.get(req.params.id, clock(), config.STALE_AFTER_SECONDS) });
  });
  router.post('/jeepneys/:id/activation', ...body, validate(activation), async (req, res) => {
    await repository.update(req.params.id, req.input, true);
    res.json({ data: await repository.get(req.params.id, clock(), config.STALE_AFTER_SECONDS) });
  });
  router.use((error, _req, res, next) => {
    const codes = { JEEPNEY_NOT_FOUND: 404, RECORD_CHANGED: 409, ROUTE_INELIGIBLE: 409, TEST_RECORD_READ_ONLY: 409 };
    if (codes[error.message]) return res.status(codes[error.message]).json({ error: error.message });
    if (error.code === '23505') return res.status(409).json({ error: 'JEEPNEY_ID_EXISTS', fields: [{ field: 'id', message: 'This identifier is already registered.' }] });
    if (error.code === '23503') return res.status(409).json({ error: 'ROUTE_INELIGIBLE' });
    next(error);
  });
  return router;
}
