-- Empty administrator-registered catalog. No operating routes are seeded here.
CREATE TABLE registered_routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  origin text NOT NULL CHECK (origin IN ('Boac','Mogpog','Gasan','Buenavista','Santa Cruz','Torrijos')),
  destination text NOT NULL CHECK (destination IN ('Boac','Mogpog','Gasan','Buenavista','Santa Cruz','Torrijos')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (origin <> destination)
);
CREATE TABLE passenger_favorite_routes (
  passenger_id uuid NOT NULL REFERENCES passenger_accounts(id) ON DELETE CASCADE,
  route_key uuid NOT NULL,
  route_id uuid REFERENCES registered_routes(id) ON DELETE SET NULL,
  -- Server-copied labels retain a useful unavailable entry after route deletion.
  origin text NOT NULL,
  destination text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (passenger_id, route_key),
  CHECK (route_id IS NULL OR route_id = route_key)
);
CREATE INDEX passenger_favorite_route_reference ON passenger_favorite_routes(route_id);
