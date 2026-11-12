import * as argon2 from 'argon2';
import { adminCredentials } from './admin-auth.js';
import { passwordOptions } from './passenger-auth.js';

export async function provisionFirstAdmin({ repository, config, input }) {
  const host = new URL(config.DATABASE_URL).hostname;
  if (config.NODE_ENV !== 'development' || config.HOST !== '127.0.0.1' || !['127.0.0.1', 'localhost', '[::1]'].includes(host))
    throw new Error('Provisioning requires a local development database');
  const credentials = adminCredentials.parse(input);
  await repository.provisionFirst(credentials.email, await argon2.hash(credentials.password, passwordOptions));
}
