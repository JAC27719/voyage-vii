# Database Schema Documentation

`services/api/migrations/*.sql` is the executable source of truth for the
implemented PostgreSQL schema. `docs/database/postgresql.dbml` is the matching
dbdiagram.io-compatible representation and must change in the same reviewed
task as any migration that changes tables, columns, types, constraints, indexes,
or relations.

API-002 introduces only the `schema_migrations` table. The synchronized review
checks compare that migration with the DBML table, primary key, unique
constraint, column types, nullability, default, and SHA-256 metadata.

To inspect visually, import `postgresql.dbml` into dbdiagram.io. The file must
not contain credentials, connection strings, local paths, or production data.
