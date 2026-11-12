import { z } from 'zod';
const schema = z.object({
  ADMIN_WEB_ORIGINS: z.string().default('http://127.0.0.1:5173'),
  ADMIN_COOKIE_SAME_SITE: z.enum(['strict', 'lax', 'none']).default('strict'),
  ADMIN_SESSION_TTL_SECONDS: z.coerce.number().int().min(300).max(86400).default(28800),
  ADMIN_AUTH_RATE_LIMIT: z.coerce.number().int().min(1).max(100).default(10),
  ENABLE_GPS_SIMULATOR: z.enum(['false', 'true']).default('false'),
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
  const origins = result.data.ADMIN_WEB_ORIGINS.split(',');
  if (!origins.every(value => {
    try {
      const url = new URL(value);
      return url.origin === value && (url.protocol === 'https:' ||
        (result.data.NODE_ENV !== 'production' && url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname)));
    } catch { return false; }
  }) || (result.data.ADMIN_COOKIE_SAME_SITE === 'none' && result.data.NODE_ENV !== 'production'))
    throw new Error('Invalid administrator origin or cookie configuration');
  if (result.data.ENABLE_GPS_SIMULATOR === 'true' &&
      (result.data.NODE_ENV !== 'development' || result.data.HOST !== '127.0.0.1')) {
    throw new Error('GPS simulator requires development mode and HOST=127.0.0.1');
  }
  return result.data;
}

