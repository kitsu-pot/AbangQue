-- Preserve provenance at every stored layer; existing demo/device rows are unchanged.
ALTER TABLE jeepneys DROP CONSTRAINT jeepneys_source_check;
ALTER TABLE jeepneys ADD CONSTRAINT jeepneys_source_check CHECK (source IN ('demo', 'device', 'simulated'));
ALTER TABLE device_credentials DROP CONSTRAINT device_credentials_source_check;
ALTER TABLE device_credentials ADD CONSTRAINT device_credentials_source_check CHECK (source IN ('device', 'simulated'));
ALTER TABLE location_status_updates DROP CONSTRAINT location_status_updates_source_check;
ALTER TABLE location_status_updates ADD CONSTRAINT location_status_updates_source_check CHECK (source IN ('demo', 'device', 'simulated'));
ALTER TABLE location_status_updates DROP CONSTRAINT location_status_updates_check;
ALTER TABLE location_status_updates ADD CONSTRAINT location_status_updates_check CHECK (
  (source = 'demo' AND credential_id IS NULL) OR
  (source IN ('device', 'simulated') AND credential_id IS NOT NULL)
);
