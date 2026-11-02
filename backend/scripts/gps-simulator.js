import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { loadConfig } from '../src/config.js';
import { requireSimulation } from '../src/simulation.js';
import { GpsSimulator } from './gps-simulator-core.js';

requireSimulation(loadConfig());
const interval = Number(process.env.GPS_SIMULATOR_INTERVAL_MS ?? 5000);
if (!Number.isInteger(interval) || interval < 1000 || interval > 3600000) throw new Error('Simulator interval must be 1000–3600000 ms');
let timer, input;
try {
  const credential = JSON.parse(await readFile(new URL('../.local/gps-simulator.json', import.meta.url), 'utf8'));
  const simulator = new GpsSimulator({ credential, url: process.env.GPS_SIMULATOR_URL ?? 'http://127.0.0.1:3000' });
  await simulator.verify();
  console.log('SIMULATED GPS test path only — not real traffic or an operating route.');
  console.log('Commands: available | full (choose status and start), pause, resume, quit. No update is sent until you choose a status.');
  const send = async () => {
    try { if (await simulator.tick()) console.log('SIMULATED update accepted at ' + new Date().toISOString()); }
    catch { console.error('SIMULATED update failed. Check backend, credential and enable flag. No fallback data sent.'); }
  };
  timer = setInterval(send, interval);
  input = createInterface({ input: process.stdin, output: process.stdout });
  input.on('line', command => {
    switch (command.trim().toLowerCase()) {
      case 'full': case 'available': simulator.setStatus(command.trim().toUpperCase()); simulator.paused = false; void send(); break;
      case 'pause': simulator.paused = true; console.log('Paused. No new updates; the last accepted report will age to STALE/OFFLINE.'); break;
      case 'resume': simulator.paused = false; if (!simulator.status) console.log('Choose full or available first.'); else void send(); break;
      case 'quit': input.close(); break;
      default: console.log('Commands: full, available, pause, resume, quit.');
    }
  });
  input.on('close', () => { simulator.paused = true; clearInterval(timer); });
  process.once('SIGINT', () => input.close());
} catch {
  clearInterval(timer); input?.close();
  console.error('Simulator could not start. Provision the test device and enable the local backend. No credentials were logged.');
  process.exitCode = 1;
}
