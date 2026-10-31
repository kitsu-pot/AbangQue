export function presentJeepney(row, now, staleSeconds) {
  const timestamp = row.recorded_at ? new Date(row.recorded_at).toISOString() : null;
  const lastSeenAt = row.last_seen_at ? new Date(row.last_seen_at).toISOString() : null;
  const demo = row.source === 'demo';
  const offline = !timestamp || !lastSeenAt ||
    now - Date.parse(timestamp) >= staleSeconds * 1000 ||
    now - Date.parse(lastSeenAt) >= staleSeconds * 1000;
  return {
    id: row.id, name: row.name, source: row.source, isDemo: demo,
    connectionStatus: demo ? 'DEMO' : offline ? 'OFFLINE' : 'ONLINE',
    lastSeenAt, timestamp, isStale: offline,
    position: timestamp ? { latitude: row.latitude, longitude: row.longitude } : null,
    // Retain the historical measurement without presenting stale seats as current.
    status: offline ? null : row.status,
    lastReportedStatus: row.status ?? null,
    eta: null,
  };
}

