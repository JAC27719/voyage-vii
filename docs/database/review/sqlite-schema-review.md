# SQLite Implemented Schema Review

Reviewed API-005 migration state: `services/api/migrations/001_schema_migrations.sql`

Implemented DBML under review: `docs/database/sqlite.dbml`

Validation method:

```text
cd services/api
../../spikes/api-pg/toolchain/zig-x86_64-windows-0.15.2/zig.exe build test -Dsqlite-amalgamation=../../spikes/sqlite/source/sqlite-amalgamation-3530300
```

That aggregate test runs the coordinator-approved std-only SQLite DBML
compatibility check added with API-005. No unpinned DBML package or CLI is used.

## Migration Inventory

| Version | File | Effect |
| --- | --- | --- |
| 1 | `001_schema_migrations.sql` | Creates the migration ledger table and its name uniqueness index. |

## Reconstructed Schema

Table: `schema_migrations`

| Column | SQLite affinity | Nullability | Constraint/default | DBML match |
| --- | --- | --- | --- | --- |
| `version` | `INTEGER` | `NOT NULL` | `PRIMARY KEY` | Yes, `integer [pk, not null]`. |
| `name` | `TEXT` | `NOT NULL` | table-level `UNIQUE` through column declaration | Yes, `text [not null, unique]`. |
| `sha256` | `TEXT` | `NOT NULL` | `CHECK (length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*')` | Yes, note records the exact check. |
| `applied_at` | `TEXT` | `NOT NULL` | `DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))` | Yes, default is represented. |

Indexes:

| Index | Columns | Unique | DBML match |
| --- | --- | --- | --- |
| `schema_migrations_name_key` | `name` | Yes | Yes. |

Relationships:

- None implemented.

Triggers:

- None implemented.

## Result

The implemented SQLite migration and `sqlite.dbml` match for table names,
columns, type affinities, primary key, nullability, unique constraints, explicit
index, default expression, SHA-256 check constraint, relationships, and
triggers.

No credentials, connection strings, absolute local paths in schema content, or
production data are present in the implemented DBML.
