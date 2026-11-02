import { parseToken } from '../src/security.js';
import { simulatorId, simulatorRouteId } from '../src/simulation.js';

// Synthetic loop near Boac. Not a road trace, service, trip, or route geometry.
export const testPath = Object.freeze([
  [13.4460, 121.8400], [13.4463, 121.8403], [13.4466, 121.8405],
  [13.4468, 121.8402], [13.4465, 121.8399], [13.4462, 121.8398],
]);
export function localSimulatorUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.username || url.password
      || url.pathname !== '/' || url.search || url.hash) throw new Error('Simulator requires an HTTP loopback origin');
  return url;
}
export class GpsSimulator {
  constructor({ url, credential, fetchImpl = fetch, clock = Date.now }) {
    this.url = localSimulatorUrl(url);
    if (credential.jeepneyId !== simulatorId || !parseToken('Bearer ' + credential.token)) throw new Error('Invalid simulator credential');
    this.credential = credential;
    this.fetch = fetchImpl;
    this.clock = clock;
    this.status = null;
    this.paused = true;
    this.index = 0;
    this.lastTimestamp = 0;
    this.busy = false;
    this.verified = false;
  }
  async request(path, options = {}) {
    const response = await this.fetch(new URL(path, this.url), { ...options, redirect: 'error', signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('SIMULATED request rejected: HTTP ' + response.status);
    return response.json();
  }
  async verify() {
    const routes = await this.request('/api/routes');
    const vehicle = await this.request('/api/jeepneys/' + simulatorId);
    if (!routes.meta?.simulationEnabled || vehicle.data?.source !== 'simulated'
        || !routes.data?.routes?.some(r => r.id === simulatorRouteId && r.isDemo === true)
        || !routes.data?.assignments?.some(a => a.routeId === simulatorRouteId && a.jeepneyId === simulatorId)) {
      throw new Error('Local simulator setup is not enabled');
    }
    this.verified = true;
  }
  setStatus(status) {
    if (!['FULL', 'AVAILABLE'].includes(status)) throw new Error('Choose FULL or AVAILABLE manually');
    this.status = status;
  }
  async tick() {
    if (this.paused || !this.status || this.busy) return false;
    if (!this.verified) throw new Error('Verify the local simulator before sending');
    this.busy = true;
    try {
      const [latitude, longitude] = testPath[this.index];
      const timestamp = Math.max(this.clock(), this.lastTimestamp + 1);
      this.lastTimestamp = timestamp;
      const response = await this.request('/api/device-updates', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + this.credential.token },
        body: JSON.stringify({ jeepneyId: simulatorId, latitude, longitude, status: this.status, timestamp: new Date(timestamp).toISOString() }),
      });
      if (response.data?.source !== 'simulated' || response.data?.isSimulated !== true) throw new Error('Missing simulation provenance');
      this.index = (this.index + 1) % testPath.length;
      return true;
    } finally { this.busy = false; }
  }
}
