CREATE TABLE jeepneys (
  id varchar(64) PRIMARY KEY CHECK (id ~ '^[A-Z0-9][A-Z0-9_-]{0,63}$'),
  name varchar(120) NOT NULL,
  source text NOT NULL CHECK (source IN ('demo', 'device')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, source)
);
CREATE TABLE device_credentials (
  id uuid PRIMARY KEY,
  jeepney_id varchar(64) NOT NULL,
  source text NOT NULL DEFAULT 'device' CHECK (source = 'device'),
  secret_hash char(64) NOT NULL CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  FOREIGN KEY (jeepney_id, source) REFERENCES jeepneys(id, source),
  UNIQUE (id, jeepney_id)
);
CREATE TABLE location_status_updates (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  jeepney_id varchar(64) NOT NULL,
  source text NOT NULL CHECK (source IN ('demo', 'device')),
  credential_id uuid,
  latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  status text NOT NULL CHECK (status IN ('FULL', 'AVAILABLE')),
  recorded_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK ((source = 'demo' AND credential_id IS NULL) OR (source = 'device' AND credential_id IS NOT NULL)),
  FOREIGN KEY (jeepney_id, source) REFERENCES jeepneys(id, source),
  FOREIGN KEY (credential_id, jeepney_id) REFERENCES device_credentials(id, jeepney_id),
  UNIQUE (credential_id, recorded_at)
);
CREATE INDEX updates_latest ON location_status_updates(jeepney_id, recorded_at DESC, id DESC);
CREATE INDEX updates_seen ON location_status_updates(jeepney_id, received_at DESC);
CREATE INDEX credentials_vehicle ON device_credentials(jeepney_id);

