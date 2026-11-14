-- Stable registrations are separate from credential versions, not duplicate credentials.
CREATE TABLE iot_devices (
  id varchar(96) PRIMARY KEY CHECK(id ~ '^[A-Z0-9][A-Z0-9_-]{0,95}$'),
  label varchar(120), model varchar(120), description varchar(500), administrative_notes varchar(2000),
  source text NOT NULL DEFAULT 'device' CHECK(source IN ('device','simulated')),
  legacy boolean NOT NULL DEFAULT false,
  enabled boolean NOT NULL DEFAULT true,
  jeepney_id varchar(64),
  version integer NOT NULL DEFAULT 1 CHECK(version>0),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(jeepney_id,source) REFERENCES jeepneys(id,source)
);
CREATE UNIQUE INDEX one_enabled_device_per_jeepney ON iot_devices(jeepney_id) WHERE enabled AND jeepney_id IS NOT NULL;
ALTER TABLE device_credentials ADD COLUMN device_id varchar(96) REFERENCES iot_devices(id);
-- Old tooling identified vehicles, not individual hardware. Preserve all keys as
-- versions of a labeled legacy registration per vehicle, without asserting hardware identity.
INSERT INTO iot_devices(id,label,source,legacy,jeepney_id,created_at)
 SELECT 'LEGACY-'||jeepney_id,'Legacy vehicle-bound registration',source,true,jeepney_id,min(created_at)
 FROM device_credentials GROUP BY jeepney_id,source;
UPDATE device_credentials SET device_id='LEGACY-'||jeepney_id;
ALTER TABLE device_credentials ALTER COLUMN device_id SET NOT NULL;
CREATE INDEX credentials_device ON device_credentials(device_id);
CREATE FUNCTION bind_device_credential() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d iot_devices;
BEGIN
  IF NEW.device_id IS NULL THEN
    NEW.device_id := 'LEGACY-'||NEW.jeepney_id;
    INSERT INTO iot_devices(id,label,source,legacy,jeepney_id)
      VALUES(NEW.device_id,'Legacy vehicle-bound registration',NEW.source,true,NEW.jeepney_id)
      ON CONFLICT(id) DO NOTHING;
  END IF;
  SELECT * INTO d FROM iot_devices WHERE id=NEW.device_id FOR SHARE;
  IF NOT FOUND OR NOT d.enabled OR d.jeepney_id IS DISTINCT FROM NEW.jeepney_id OR d.source<>NEW.source THEN
    RAISE EXCEPTION 'Device binding rejected' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER credential_binding BEFORE INSERT ON device_credentials FOR EACH ROW EXECUTE FUNCTION bind_device_credential();
CREATE FUNCTION preserve_credential_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id<>OLD.id OR NEW.device_id<>OLD.device_id OR NEW.jeepney_id<>OLD.jeepney_id OR NEW.source<>OLD.source OR NEW.secret_hash<>OLD.secret_hash THEN
    RAISE EXCEPTION 'Credential binding is immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER credential_identity BEFORE UPDATE ON device_credentials FOR EACH ROW EXECUTE FUNCTION preserve_credential_identity();
CREATE TABLE admin_device_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id varchar(96) NOT NULL REFERENCES iot_devices(id),
  admin_id uuid REFERENCES admin_accounts(id) ON DELETE SET NULL,
  action text NOT NULL CHECK(action IN ('REGISTER','EDIT','ASSIGN','ENABLE','DISABLE','PROVISION','ROTATE','REVOKE')),
  previous_jeepney_id varchar(64), jeepney_id varchar(64), version integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX device_events_latest ON admin_device_events(device_id,id DESC);
