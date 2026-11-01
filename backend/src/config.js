import { z } from 'zod';
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  TRUST_PROXY: z.enum(['false', 'loopback']).default('false'),
  AUTH_RATE_LIMIT: z.coerce.number().int().min(1).max(100).default(10),
  SESSION_TTL_SECONDS: z.coerce.number().int().min(3600).max(2592000).default(604800),
  DATABASE_URL: z.string().url().refine(v => /^postgres(ql)?:/.test(v), 'Use a PostgreSQL URL'),
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  STALE_AFTER_SECONDS: z.coerce.number().int().min(1).default(120),
  MAX_UPDATE_AGE_SECONDS: z.coerce.number().int().min(1).default(86400),
  MAX_FUTURE_SKEW_SECONDS: z.coerce.number().int().min(0).max(300).default(30),
  DEVICE_RATE_LIMIT: z.coerce.number().int().min(1).default(120),
  INCLUDE_DEMO: z.enum(['true', 'false']).default('false'),
});
export function loadConfig(env = process.env) {
  const result = schema.safeParse(env);
  if (!result.success) throw new Error('Invalid configuration: ' + result.error.issues.map(i => i.path.join('.')).join(', '));
  return result.data;
}

