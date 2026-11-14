import { Router, json } from 'express';
import { z } from 'zod';
import { rateLimit } from 'express-rate-limit';
import { jeepneyId } from './validation.js';
export const deviceId = z.string().regex(/^[A-Z0-9][A-Z0-9_-]{0,95}$/);
const text = (max) =>
  z
    .string()
    .trim()
    .max(max)
    .refine((v) => !/[\u0000-\u001f\u007f]/u.test(v), 'Use plain text.')
    .nullable();
const metadata = {
  label: text(120),
  model: text(120),
  description: text(500),
  administrativeNotes: text(2000),
};
export const registration = z
  .object({
    id: deviceId.refine(
      (v) =>
        !['LEGACY-', 'SIM-', 'DEMO-'].some((prefix) => v.startsWith(prefix)),
      'Reserved legacy or test prefix.',
    ),
    ...metadata,
    enabled: z.boolean(),
    jeepneyId: jeepneyId.nullable(),
  })
  .strict();
const version = {
  expectedVersion: z.number().int().positive().max(2147483646),
};
const queries = z
  .object({
    search: z.string().trim().max(120).default(''),
    reporting: z.enum(['all', 'fresh', 'stale', 'missing']).default('all'),
    assignment: z.enum(['all', 'assigned', 'unassigned']).default('all'),
    state: z.enum(['all', 'enabled', 'disabled']).default('all'),
    page: z.coerce.number().int().min(1).max(100000).default(1),
    pageSize: z.coerce.number().int().min(1).max(100).default(20),
  })
  .strict();
const validate =
  (schema, from = 'body') =>
  (req, res, next) => {
    const p = schema.safeParse(req[from]);
    if (!p.success)
      return res
        .status(400)
        .json({
          error: 'INVALID_DEVICE_INPUT',
          fields: p.error.issues.map((i) => ({
            field: i.path.join('.'),
            message: i.message,
          })),
        });
    req.input = p.data;
    next();
  };
export function adminDeviceRouter({ repository, config, clock }) {
  const router = Router();
  const body = [
    rateLimit({
      windowMs: 60000,
      limit: 20,
      keyGenerator: (req) => req.admin.id,
      standardHeaders: 'draft-8',
      legacyHeaders: false,
      message: { error: 'DEVICE_WRITE_RATE_LIMITED' },
    }),
    (req, res, next) =>
      req.is('application/json')
        ? next()
        : res.status(415).json({ error: 'JSON_REQUIRED' }),
    json({ limit: '16kb' }),
  ];
  router.get('/device-jeepney-options', async (req, res) =>
    res.json({ data: await repository.choices() }),
  );
  router.get('/devices', validate(queries, 'query'), async (req, res) =>
    res.json({
      data: await repository.list(
        req.input,
        clock(),
        config.STALE_AFTER_SECONDS,
      ),
    }),
  );
  router.post('/devices', ...body, validate(registration), async (req, res) => {
    await repository.create(req.input, req.admin.id);
    res
      .status(201)
      .json({
        data: await repository.get(
          req.input.id,
          clock(),
          config.STALE_AFTER_SECONDS,
        ),
      });
  });
  router.use('/devices/:id', (req, res, next) =>
    deviceId.safeParse(req.params.id).success
      ? next()
      : res.status(400).json({ error: 'INVALID_ID' }),
  );
  router.get('/devices/:id', async (req, res) => {
    const now = clock(),
      record = await repository.get(
        req.params.id,
        now,
        config.STALE_AFTER_SECONDS,
      );
    if (!record) return res.status(404).json({ error: 'DEVICE_NOT_FOUND' });
    res.json({
      data: {
        record,
        events: await repository.events(req.params.id),
        updatedAt: new Date(now).toISOString(),
        staleAfterSeconds: config.STALE_AFTER_SECONDS,
      },
    });
  });
  router.put(
    '/devices/:id',
    ...body,
    validate(z.object({ ...metadata, ...version }).strict()),
    async (req, res) => {
      await repository.change(req.params.id, req.input, req.admin.id, 'EDIT');
      res.json({ data: { saved: true } });
    },
  );
  const operations = [
    [
      'assignment',
      z.object({ jeepneyId: jeepneyId.nullable(), ...version }).strict(),
      'ASSIGN',
    ],
    ['state', z.object({ enabled: z.boolean(), ...version }).strict(), 'STATE'],
    ['provision', z.object(version).strict(), 'PROVISION'],
    ['rotate', z.object(version).strict(), 'ROTATE'],
    ['revoke', z.object(version).strict(), 'REVOKE'],
  ];
  for (const [path, schema, operation] of operations)
    router.post(
      '/devices/:id/' + path,
      ...body,
      validate(schema),
      async (req, res) => {
        const action =
          operation === 'STATE'
            ? req.input.enabled
              ? 'ENABLE'
              : 'DISABLE'
            : operation;
        const data = await repository.change(
          req.params.id,
          req.input,
          req.admin.id,
          action,
        );
        res.json({ data });
      },
    );
  router.use((e, req, res, next) => {
    if (e.code === '23505')
      return res
        .status(409)
        .json({
          error:
            e.constraint === 'iot_devices_pkey'
              ? 'DEVICE_ID_EXISTS'
              : 'ASSIGNMENT_CONFLICT',
        });
    const codes = {
      DEVICE_NOT_FOUND: 404,
      TEST_RECORD_READ_ONLY: 409,
      RECORD_CHANGED: 409,
      JEEPNEY_INELIGIBLE: 409,
      DEVICE_NOT_READY: 409,
      ALREADY_PROVISIONED: 409,
    };
    if (codes[e.message])
      return res.status(codes[e.message]).json({ error: e.message });
    if (e.code === '23503' || e.code === '23514')
      return res.status(409).json({ error: 'DEVICE_BINDING_REJECTED' });
    next(e);
  });
  return router;
}
