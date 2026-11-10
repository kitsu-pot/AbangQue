import { Router, json } from 'express';
import { rateLimit } from 'express-rate-limit';
import { createHash, randomBytes } from 'node:crypto';
import * as argon2 from 'argon2';
import { z } from 'zod';

export const passwordOptions = { type: argon2.argon2id, memoryCost: 65536, timeCost: 3, parallelism: 1 };
const email = z.string().trim().max(254).email().transform(v => v.toLowerCase());
const fullName = z.string().trim().min(1).max(120).refine(v => !/[\u0000-\u001f\u007f]/u.test(v));
const password = z.string().min(15).max(128).refine(v => /\S/u.test(v) && !/^(.)\1+$/u.test(v)
  && !['passwordpassword', '123456789012345', '12345678901234567890'].includes(v.toLowerCase()));
const registration = z.object({ fullName, email, password }).strict();
const loginInput = z.object({ email, password: z.string().min(1).max(128) }).strict();
const profileInput = z.object({ fullName }).strict();
const currentPassword = z.string().min(1).max(128);
const passwordInput = z.object({ currentPassword, newPassword: password, confirmPassword: z.string().max(128) }).strict()
  .refine(v => v.newPassword === v.confirmPassword && v.newPassword !== v.currentPassword);
const deletionInput = z.object({ currentPassword }).strict();
const tokenPattern = /^Bearer (aqp_[A-Za-z0-9_-]{43})$/;
export const hashToken = token => createHash('sha256').update(token).digest('hex');
const newToken = () => 'aqp_' + randomBytes(32).toString('base64url');
const publicUser = row => ({ id: row.id, fullName: row.full_name, email: row.email, role: row.role });
let dummyHash;
let activeHashes = 0;
async function passwordWork(action) {
  // Bound memory used by expensive hashes; reject excess work instead of queuing it.
  if (activeHashes >= 4) { const e = new Error('Busy'); e.authBusy = true; throw e; }
  activeHashes++;
  try { return await action(); } finally { activeHashes--; }
}

export function requirePassenger({ repository, config }) {
  return async (req, res, next) => {
    if (config.NODE_ENV === 'production' && !req.secure) return res.status(403).json({ error: 'HTTPS_REQUIRED' });
    const match = tokenPattern.exec(req.headers.authorization ?? '');
    if (!match) return res.status(401).json({ error: 'SESSION_INVALID' });
    req.tokenHash = hashToken(match[1]);
    const session = await repository.session(req.tokenHash);
    if (!session) return res.status(401).json({ error: 'SESSION_INVALID' });
    if (session.role !== 'PASSENGER') return res.status(403).json({ error: 'PASSENGER_REQUIRED' });
    req.passenger = session; next();
  };
}

export function passengerAuthRouter({ repository, config }) {
  const router = Router();
  const limit = max => rateLimit({ windowMs: 15 * 60 * 1000, limit: max,
    standardHeaders: 'draft-8', legacyHeaders: false, message: { error: 'AUTH_RATE_LIMITED' } });
  const attempts = limit(config.AUTH_RATE_LIMIT);
  const accountAttempts = rateLimit({ windowMs: 15 * 60 * 1000, limit: config.AUTH_RATE_LIMIT,
    keyGenerator: req => hashToken(String(req.body?.email ?? '').trim().toLowerCase()),
    standardHeaders: 'draft-8', legacyHeaders: false, message: { error: 'AUTH_RATE_LIMITED' } });
  router.use((req, res, next) => {
    if (config.NODE_ENV === 'production' && !req.secure) return res.status(403).json({ error: 'HTTPS_REQUIRED' });
    next();
  });
  router.use(limit(120));
  const body = [
    (req, res, next) => req.is('application/json') ? next() : res.status(415).json({ error: 'JSON_REQUIRED' }),
    json({ limit: '4kb' }),
  ];
  const validate = schema => (req, res, next) => {
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'INVALID_AUTH_INPUT' });
    req.input = parsed.data; next();
  };
  const token = (req, res, next) => {
    const match = tokenPattern.exec(req.headers.authorization ?? '');
    if (!match) return res.status(401).json({ error: 'SESSION_INVALID' });
    req.tokenHash = hashToken(match[1]); next();
  };
  const passenger = requirePassenger({ repository, config });
  // Shared by password changes/deletion, per IP and verified account (not token).
  const sensitiveIP = limit(config.AUTH_RATE_LIMIT);
  const sensitiveAccount = rateLimit({ windowMs: 15 * 60 * 1000, limit: config.AUTH_RATE_LIMIT,
    keyGenerator: req => req.passenger.id,
    standardHeaders: 'draft-8', legacyHeaders: false, message: { error: 'AUTH_RATE_LIMITED' } });
  const verifyCurrent = async (hash, value) => {
    if (!await argon2.verify(hash, value)) {
      throw Object.assign(new Error('Reauthentication failed'), { accountError: 'CURRENT_PASSWORD_INCORRECT' });
    }
  };
  router.post('/register', attempts, ...body, validate(registration), async (req, res) => {
    const token = newToken();
    const passwordHash = await passwordWork(() => argon2.hash(req.input.password, passwordOptions));
    try {
      const session = await repository.register({ ...req.input, passwordHash,
        tokenHash: hashToken(token), ttl: config.SESSION_TTL_SECONDS });
      res.status(201).json({ data: { user: publicUser(session.user), token, expiresAt: session.expires_at.toISOString() } });
    } catch (error) {
      if (error.code === '23505') return res.status(409).json({ error: 'REGISTRATION_UNAVAILABLE' });
      throw error;
    }
  });
  router.post('/login', attempts, ...body, validate(loginInput), accountAttempts, async (req, res) => {
    const user = await repository.findByEmail(req.input.email);
    const valid = await passwordWork(async () => {
      // Unknown email performs the same Argon2 verify work; never use a quick exit.
      dummyHash ??= argon2.hash(randomBytes(32).toString('hex'), passwordOptions);
      const fallback = await dummyHash;
      return argon2.verify(user?.password_hash ?? fallback, req.input.password);
    });
    if (!valid || !user || user.role !== 'PASSENGER') return res.status(401).json({ error: 'INVALID_LOGIN' });
    const token = newToken();
    const session = await repository.login(user.id, hashToken(token), config.SESSION_TTL_SECONDS, user.password_hash);
    if (!session) return res.status(401).json({ error: 'INVALID_LOGIN' });
    res.json({ data: { user: publicUser(session), token, expiresAt: session.expires_at.toISOString() } });
  });
  router.get('/me', token, passenger, (req, res) => res.json({ data: {
    user: publicUser(req.passenger), expiresAt: req.passenger.expires_at.toISOString(),
  } }));
  router.patch('/me', token, passenger, ...body, validate(profileInput), async (req, res) => {
    const user = await repository.updateProfile(req.tokenHash, req.input.fullName);
    if (!user) return res.status(401).json({ error: 'SESSION_INVALID' });
    res.json({ data: { user: publicUser(user) } });
  });
  router.post('/me/password', sensitiveIP, passenger, sensitiveAccount, ...body, validate(passwordInput), async (req, res) => {
    await passwordWork(() => repository.changePassword(req.tokenHash, async hash => {
      await verifyCurrent(hash, req.input.currentPassword);
      return argon2.hash(req.input.newPassword, passwordOptions);
    }));
    res.sendStatus(204);
  });
  router.delete('/me', sensitiveIP, passenger, sensitiveAccount, ...body, validate(deletionInput), async (req, res) => {
    await passwordWork(() => repository.deleteAccount(req.tokenHash, hash => verifyCurrent(hash, req.input.currentPassword)));
    res.sendStatus(204);
  });
  // Idempotent for expired/already revoked sessions. Only this token is revoked.
  router.post('/logout', token, async (req, res) => { await repository.revoke(req.tokenHash); res.sendStatus(204); });
  router.use((error, _req, res, next) => {
    if (error.accountError === 'SESSION_INVALID') return res.status(401).json({ error: 'SESSION_INVALID' });
    if (error.accountError === 'CURRENT_PASSWORD_INCORRECT') return res.status(403).json({ error: 'CURRENT_PASSWORD_INCORRECT' });
    if (error.authBusy) return res.status(503).json({ error: 'AUTH_BUSY' });
    next(error);
  });
  return router;
}
