-- Add registration metadata without changing vehicle IDs, provenance or telemetry.
ALTER TABLE jeepneys
  ADD COLUMN active boolean NOT NULL DEFAULT true,
  ADD COLUMN plate_number varchar(20),
  ADD COLUMN description varchar(500) NOT NULL DEFAULT '',
  ADD COLUMN administrative_notes varchar(2000) NOT NULL DEFAULT '',
  ADD COLUMN route_id uuid REFERENCES registered_routes(id) ON DELETE RESTRICT,
  ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now(),
  ADD CONSTRAINT jeepney_plate_format CHECK (plate_number IS NULL OR
    (plate_number = upper(btrim(plate_number)) AND plate_number ~ '^[A-Z0-9][A-Z0-9 -]{1,19}$')),
  ADD CONSTRAINT jeepney_real_route_only CHECK (route_id IS NULL OR source = 'device');
-- No plate uniqueness rule is assumed without verified registration policy.
CREATE INDEX jeepneys_route ON jeepneys(route_id);
CREATE INDEX jeepneys_active_id ON jeepneys(active, id);
