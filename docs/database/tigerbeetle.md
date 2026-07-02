# TigerBeetle Mapping

TigerBeetle is the specialized ledger store for balances and transfers. It is
not a relational SQL database, and this document does not define SQL tables,
foreign keys, or relational guarantees.

## Storage Boundary

- SQLite owns application metadata, lifecycle state, and future relational
  finance records.
- TigerBeetle owns ledger balances and transfers.
- The API connects to TigerBeetle through the approved C adapter and uses a
  harmless lookup as the health probe.
- SQLite identifiers may be linked to TigerBeetle identifiers by deterministic
  conversion, but the current implemented SQLite schema contains only the
  migration ledger.

## Account Identifiers

Future finance records use application-generated UUIDv7 values stored
canonically in SQLite. When an account must be represented in TigerBeetle, the
canonical UUID big-endian bytes are converted to TigerBeetle's `u128` account
identifier.

Account classification is immutable once created. The deferred finance model
assigns stable class codes for future TigerBeetle metadata:

| Class | Deferred class code |
| --- | ---: |
| Asset | 1 |
| Liability | 2 |
| Equity | 3 |
| Revenue | 4 |
| Expense | 5 |
| Dividend | 6 |

## Transfer Identifiers and Metadata

Future transfers use application-generated UUIDv7 values. The canonical UUID
big-endian bytes are converted to TigerBeetle `u128` transfer identifiers.

The deferred design reserves TigerBeetle user-data fields as follows:

| TigerBeetle field | Deferred use |
| --- | --- |
| `ledger` | Domain-separated BLAKE3-derived `u32` ledger assignment. |
| `code` | RED ALE class code from the table above. |
| `user_data_64` | Effective epoch-day for ordering and period behavior. |
| remaining user-data fields | Reserved until a reviewed finance task assigns them. |

Reversal identifiers are deferred and will be derived through a documented XOR
namespace in the same reviewed task that implements reversals.

## Non-Implemented Finance Scope

The first v2 slice does not implement finance tables, transaction rows, account
history, reports, budgets, or reconciliation. Proposed relational structures
belong in `docs/database/proposed/` until a future task adds executable SQLite
migrations and updates `docs/database/sqlite.dbml` in the same review unit.
