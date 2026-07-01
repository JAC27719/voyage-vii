# Database Schema Documentation

`services/api/migrations/*.sql` is the executable source of truth for the
implemented SQLite schema. `docs/database/sqlite.dbml` is the matching
dbdiagram.io-compatible representation and must change in the same reviewed
task as any migration that changes tables, columns, types, constraints,
indexes, triggers, or relations.

API-005 introduces only the `schema_migrations` table. The synchronized review
checks compare that migration with the DBML table, primary key, unique
constraint, column type affinities, nullability, default, index, and SHA-256
metadata. API-002 and `docs/database/postgresql.dbml` are retained only as
superseded PostgreSQL history.

To inspect visually, import `sqlite.dbml` into dbdiagram.io. The file must not
contain credentials, connection strings, local paths, or production data.
