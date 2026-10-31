import { z } from 'zod';
export const jeepneyId = z.string().regex(/^[A-Z0-9][A-Z0-9_-]{0,63}$/);
export const updateSchema = z.object({
  jeepneyId,
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  status: z.enum(['FULL', 'AVAILABLE']),
  timestamp: z.iso.datetime({ offset: true }),
}).strict();
export function timestampAllowed(timestamp, now, config) {
  const age = now - Date.parse(timestamp);
  return age <= config.MAX_UPDATE_AGE_SECONDS * 1000 &&
    age >= -config.MAX_FUTURE_SKEW_SECONDS * 1000;
}

