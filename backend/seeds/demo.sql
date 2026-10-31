-- Optional, fixed historical fixtures. Never impersonate connected hardware.
INSERT INTO jeepneys(id, name, source) VALUES
 ('DEMO-01', 'DEMO jeepney 01', 'demo'),
 ('DEMO-02', 'DEMO jeepney 02', 'demo')
ON CONFLICT (id) DO NOTHING;
INSERT INTO location_status_updates(jeepney_id, source, latitude, longitude, status, recorded_at, received_at)
SELECT v.id, 'demo', v.lat, v.lon, v.status, '2026-01-01T00:00:00Z'::timestamptz, '2026-01-01T00:00:00Z'::timestamptz
FROM (VALUES
 ('DEMO-01', 13.4490, 121.8374, 'AVAILABLE'),
 ('DEMO-02', 13.4433, 121.8423, 'FULL')
) AS v(id, lat, lon, status)
WHERE NOT EXISTS (SELECT 1 FROM location_status_updates u WHERE u.jeepney_id = v.id);

