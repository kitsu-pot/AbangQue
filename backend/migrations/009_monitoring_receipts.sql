-- Latest communication per credential, including out-of-order measurements.
-- Complements the existing (credential_id, recorded_at) unique index.
CREATE INDEX updates_credential_received ON location_status_updates(credential_id, received_at DESC);
