// Local test fixtures only, never administrator-registered operating routes.
export const simulatorId = 'SIM-GPS-001';
export const simulatorRouteId = 'DEMO-PATH-BOAC-MOGPOG';
export const simulationEnabled = config => config.ENABLE_GPS_SIMULATOR === 'true'
  && config.NODE_ENV === 'development' && config.HOST === '127.0.0.1';
export function requireSimulation(config) {
  if (!simulationEnabled(config)) throw new Error('Enable local development GPS simulation explicitly.');
}
export function simulatorCatalog() {
  return {
    routes: [{ id: simulatorRouteId, origin: 'Boac', destination: 'Mogpog', isDemo: true,
      label: 'DEMO test direction — not an operating route' }],
    assignments: [{ routeId: simulatorRouteId, jeepneyId: simulatorId }],
  };
}
