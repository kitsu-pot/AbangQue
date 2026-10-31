import { createHash, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
export const hashSecret = secret => createHash('sha256').update(secret).digest('hex');
export function issueCredential() {
  const id = randomUUID();
  const secret = randomBytes(32).toString('hex');
  return { id, token: id + '.' + secret, secretHash: hashSecret(secret) };
}
export function parseToken(header) {
  const match = /^Bearer ([0-9a-f-]{36})\.([0-9a-f]{64})$/i.exec(header ?? '');
  return match ? { id: match[1].toLowerCase(), secret: match[2] } : null;
}
export function matchesSecret(secret, hash) {
  const expected = Buffer.from(hash ?? '0'.repeat(64), 'hex');
  const actual = Buffer.from(hashSecret(secret), 'hex');
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

