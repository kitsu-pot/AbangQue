export function presentJeepney(row, now, staleSeconds) {
  const timestamp = row.recorded_at ? new Date(row.recorded_at).toISOString() : null;
  const lastSeenAt = row.last_seen_at ? new Date(row.last_seen_at).toISOString() : null;
  const simulated = row.source === 'simulated';
  const demo = row.source === 'demo';
  const offline = !timestamp || !lastSeenAt ||
    now - Date.parse(timestamp) >= staleSeconds * 1000 ||
    now - Date.parse(lastSeenAt) >= staleSeconds * 1000;
  return {
    id: row.id, name: row.name, source: row.source, isDemo: demo || simulated, isSimulated: simulated,
    connectionStatus: demo ? 'DEMO' : offline ? 'OFFLINE' : 'ONLINE',
    lastSeenAt, timestamp, isStale: offline,
    position: timestamp ? { latitude: row.latitude, longitude: row.longitude } : null,
    // Retain the historical measurement without presenting stale availability as current.
    status: offline || demo ? null : row.status,
    lastReportedStatus: row.status ?? null,
    eta: null,
  };
}

