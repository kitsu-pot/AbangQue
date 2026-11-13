# Thesis appendix: database ERD

**Figure caption:** Entity-relationship diagram of the AbangQue PostgreSQL schema
implemented through migration 006 (13 November 2026).

- [`ERD.svg`](ERD.svg) is the vector diagram for insertion into the thesis.
- [`ERD.mmd`](ERD.mmd) is the editable Mermaid source.

The diagram reflects tables and declared relationships in migrations 001–006,
plus the `schema_migrations` ledger created by the migration runner. It does not
show runtime-only data, API payloads, indexes, every validation constraint, or
planned hardware. `location_status_updates.credential_id` is nullable for DEMO
records. A favorite keeps its copied route label when a route is deleted, while
its optional `route_id` becomes null. Jeepney-to-route assignment is optional
and stores the current assignment only. Device credentials and telemetry use
composite vehicle/source foreign keys; the diagram summarizes these as vehicle
and source relationships.

Before submission, align the caption/date with the thesis' final database
version if later migrations change the schema.
