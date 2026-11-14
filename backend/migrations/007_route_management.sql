-- Fail transactionally if legacy duplicate directions need owner reconciliation.
CREATE UNIQUE INDEX registered_route_direction ON registered_routes(origin,destination);
ALTER TABLE registered_routes
  ADD COLUMN display_name varchar(120),
  ADD COLUMN description varchar(1000),
  ADD COLUMN origin_terminal varchar(200),
  ADD COLUMN destination_terminal varchar(200),
  ADD COLUMN boarding_notes varchar(1000),
  ADD COLUMN administrative_notes varchar(2000),
  ADD COLUMN operations_verified boolean NOT NULL DEFAULT false,
  ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK(version > 0),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
-- IDs and directions anchor favorites and vehicle assignments permanently.
CREATE FUNCTION protect_route_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id OR NEW.origin IS DISTINCT FROM OLD.origin OR NEW.destination IS DISTINCT FROM OLD.destination THEN
    RAISE EXCEPTION 'Route identity is immutable' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER route_identity BEFORE UPDATE ON registered_routes FOR EACH ROW EXECUTE FUNCTION protect_route_identity();
