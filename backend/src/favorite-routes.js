import { Router, json } from 'express';
import { z } from 'zod';
import { rateLimit } from 'express-rate-limit';
import { requirePassenger } from './passenger-auth.js';

export function favoriteRouter({ repository, passengerRepository, config }) {
  const router = Router();
  router.use(rateLimit({ windowMs: 60000, limit: 120, standardHeaders: 'draft-8', legacyHeaders: false,
    message: { error: 'RATE_LIMITED' } }));
  router.use(requirePassenger({ repository: passengerRepository, config }));
  router.use(json({ limit: '1kb' }));
  router.use((req, res, next) => {
    if (req.headers['content-length'] && req.headers['content-length'] !== '0' && !req.is('application/json'))
      return res.status(415).json({ error: 'JSON_REQUIRED' });
    if (Object.keys(req.query).length || (req.body !== undefined && !z.object({}).strict().safeParse(req.body).success))
      return res.status(400).json({ error: 'INVALID_FAVORITE_INPUT' });
    next();
  });
  router.get('/', async (req, res) => res.json({ data: await repository.list(req.passenger.id) }));
  router.param('routeId', (req, res, next, value) => {
    if (!z.string().uuid().safeParse(value).success) return res.status(400).json({ error: 'INVALID_ROUTE_ID' });
    req.routeId = value.toLowerCase(); next();
  });
  router.put('/:routeId', async (req, res) => {
    if (!await repository.save(req.passenger.id, req.routeId)) return res.status(409).json({ error: 'ROUTE_UNAVAILABLE' });
    res.sendStatus(204);
  });
  router.delete('/:routeId', async (req, res) => {
    await repository.remove(req.passenger.id, req.routeId);
    res.sendStatus(204);
  });
  return router;
}
