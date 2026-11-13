import { FavoriteRepository } from './favorite-repository.js';
import { AdminRepository } from './admin-repository.js';
import { AdminJeepneyRepository } from './admin-jeepney-repository.js';
import { loadConfig } from './config.js';
import { createPool } from './db.js';
import { PostgresRepository } from './repository.js';
import { createApp } from './app.js';
import { PassengerRepository } from './passenger-repository.js';
const config = loadConfig();
const pool = createPool(config);
const app = createApp({ adminJeepneyRepository: new AdminJeepneyRepository(pool), adminRepository: new AdminRepository(pool), favoriteRepository: new FavoriteRepository(pool), repository: new PostgresRepository(pool), passengerRepository: new PassengerRepository(pool), config });
const server = app.listen(config.PORT, config.HOST, () => console.log('AbangQue API listening on ' + config.HOST + ':' + config.PORT));
server.on('error', async () => { console.error('Unable to start API listener'); await pool.end(); process.exitCode = 1; });
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => {
  const deadline = setTimeout(() => process.exit(1), 10000).unref();
  server.close(async () => { await pool.end(); clearTimeout(deadline); });
});

