import { Router, json } from 'express';
import { rateLimit } from 'express-rate-limit';
import { randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
import { z } from 'zod';
import { adminJeepneyRouter } from './admin-jeepneys.js';
import { hashToken, passwordOptions, passwordWork } from './passenger-auth.js';

export const adminCredentials = z.object({
  email: z.string().trim().max(254).email().transform(v => v.toLowerCase()),
  password: z.string().min(15).max(128).refine(v => /\S/u.test(v) && !/^(.)\1+$/u.test(v)
    && !['passwordpassword', '123456789012345', '12345678901234567890'].includes(v.toLowerCase())),
}).strict();
const loginInput = adminCredentials.extend({ password: z.string().min(1).max(128) });
let dummyHash;
export function adminRouter({ repository, jeepneyRepository, config, clock = Date.now }) {
  const router = Router();
  const secure = config.NODE_ENV === 'production';
  const cookieName = secure ? '__Host-abangque_admin' : 'abangque_admin';
  const cookieOptions = { httpOnly: true, secure, sameSite: config.ADMIN_COOKIE_SAME_SITE ?? 'strict', path: '/' };
  const origins = (config.ADMIN_WEB_ORIGINS ?? 'http://127.0.0.1:5173').split(',');
  const readToken = req => {
    const values = (req.headers.cookie ?? '').split(';').map(v => v.trim()).filter(v => v.startsWith(cookieName + '='));
    if (values.length !== 1) return null;
    const token = values[0].slice(cookieName.length + 1);
    return /^aqa_[A-Za-z0-9_-]{43}$/.test(token) ? hashToken(token) : null;
  };
  router.use((req, res, next) => {
    if (secure && !req.secure) return res.status(403).json({ error: 'HTTPS_REQUIRED' });
    const origin = req.headers.origin;
    if (origin && !origins.includes(origin)) return res.status(403).json({ error: 'ORIGIN_REJECTED' });
    if (origin) {
      res.set('Access-Control-Allow-Origin', origin); res.vary('Origin');
      res.set('Access-Control-Allow-Credentials', 'true');
    }
    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,OPTIONS');
      res.set('Access-Control-Allow-Headers', 'Content-Type,X-AbangQue-Admin');
      return res.sendStatus(204);
    }
    // Exact Origin + non-simple custom header protects login/logout against CSRF.
    // Reject missing/null origins for writes; JSON forms cannot bypass this.
    if (!['GET', 'HEAD'].includes(req.method) && (!origin || req.get('X-AbangQue-Admin') !== '1'))
      return res.status(403).json({ error: 'CSRF_REJECTED' });
    next();
  });
  const limiter = extra => rateLimit({ windowMs: 15 * 60 * 1000,
    limit: config.ADMIN_AUTH_RATE_LIMIT ?? 10, standardHeaders: 'draft-8', legacyHeaders: false,
    message: { error: 'AUTH_RATE_LIMITED' }, ...extra });
  const byIP = limiter({});
  const byEmail = limiter({ keyGenerator: req => hashToken(req.body.email) });
  router.post('/login', byIP,
    (req, res, next) => req.is('application/json') ? next() : res.status(415).json({ error: 'JSON_REQUIRED' }),
    json({ limit: '4kb' }), (req, res, next) => {
      const parsed = loginInput.safeParse(req.body);
      if (!parsed.success) return res.status(400).json({ error: 'INVALID_AUTH_INPUT' });
      req.body = parsed.data; next();
    }, byEmail, async (req, res) => {
      const user = await repository.findByEmail(req.body.email);
      const valid = await passwordWork(async () => {
        dummyHash ??= argon2.hash(randomBytes(32).toString('hex'), passwordOptions);
        return argon2.verify(user?.password_hash ?? await dummyHash, req.body.password);
      });
      if (!valid || !user || user.role !== 'ADMIN') return res.status(401).json({ error: 'INVALID_LOGIN' });
      const token = 'aqa_' + randomBytes(32).toString('base64url');
      const session = await repository.login(user, hashToken(token), config.ADMIN_SESSION_TTL_SECONDS ?? 28800);
      if (!session) return res.status(401).json({ error: 'INVALID_LOGIN' });
      const previous = readToken(req);
      if (previous) await repository.revoke(previous);
      res.cookie(cookieName, token, { ...cookieOptions, expires: session.expires_at });
      res.json({ data: { user: { id: user.id, email: user.email, role: 'ADMIN' }, expiresAt: session.expires_at.toISOString() } });
    });
  router.post('/logout', async (req, res) => {
    const token = readToken(req);
    if (token) await repository.revoke(token);
    res.clearCookie(cookieName, cookieOptions); res.sendStatus(204);
  });
  router.use(async (req, res, next) => {
    const token = readToken(req);
    const session = token && await repository.session(token);
    if (!session || session.role !== 'ADMIN' || session.expires_at.getTime() <= clock())
      return res.status(401).json({ error: 'SESSION_INVALID' });
    req.admin = session; next();
  });
  router.get('/session', (req, res) => res.json({ data: {
    user: { id: req.admin.id, email: req.admin.email, role: 'ADMIN' }, expiresAt: req.admin.expires_at.toISOString(),
  } }));
  router.get('/dashboard', async (_req, res) => res.json({ data: await repository.dashboard(new Date(clock()), config.STALE_AFTER_SECONDS) }));
  if (jeepneyRepository) router.use(adminJeepneyRouter({ repository: jeepneyRepository, config, clock }));
  return router;
}
