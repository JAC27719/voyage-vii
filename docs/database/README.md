# Database Schema Documentation

`services/api/migrations/*.sql` is the executable source of truth for the
implemented SQLite schema. `docs/database/sqlite.dbml` is the matching
dbdiagram.io-compatible representation and must change in the same reviewed
task as any migration that changes tables, columns, types, constraints,
indexes, triggers, or relations.

API-002 and `docs/database/postgresql.dbml` are retained only as superseded
PostgreSQL history. API-005 creates the active SQLite implemented schema and
DBML.

To inspect visually, import `sqlite.dbml` into dbdiagram.io after API-005
creates it. The file must not contain credentials, connection strings, local
paths, or production data.
