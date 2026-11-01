CREATE TABLE passenger_accounts (
  id uuid PRIMARY KEY,
  full_name varchar(120) NOT NULL CHECK (length(btrim(full_name)) BETWEEN 1 AND 120),
  email varchar(254) NOT NULL UNIQUE CHECK (email = lower(btrim(email))),
  password_hash text NOT NULL CHECK (password_hash LIKE '$argon2id$%'),
  role text NOT NULL DEFAULT 'PASSENGER' CHECK (role = 'PASSENGER'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE passenger_sessions (
  token_hash char(64) PRIMARY KEY,
  passenger_id uuid NOT NULL REFERENCES passenger_accounts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  CHECK (expires_at > created_at)
);
CREATE INDEX passenger_sessions_account ON passenger_sessions(passenger_id);
CREATE INDEX passenger_sessions_expiry ON passenger_sessions(expires_at);
