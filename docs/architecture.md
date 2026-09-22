# Architecture overview

**Status:** this is the approved design for v0.1, not a description of
implemented database behavior. The repository currently has only its project
and MoonBit module scaffold. The detailed, maintainer-approved specification is
[`superpowers/specs/2026-09-20-moonpropertydb-design.md`](superpowers/specs/2026-09-20-moonpropertydb-design.md).

## Intended layers

The application and CLI use a documented `database` API. A single MoonBit
module is divided into acyclic packages so the graph model, indexes, codecs,
storage, transactions, and query stages can be tested independently.

```text
Application / CLI
        |
        v
Public database API
        |
  +-----+------------------+
  |                        |
  v                        v
Transaction manager    Read-only query pipeline
  |                    Lexer -> Parser/AST -> Semantic validation
  |                                      -> Planner -> Executor
  v                        |
Candidate graph state <----+
  |
  +-- node and edge ID maps
  +-- label and edge-type indexes
  +-- incoming and outgoing adjacency
  +-- declared property equality indexes
  |
  v
Versioned commit log + snapshots/checkpoints
```

The intended dependency direction is `cmd -> database`, with `database`
coordinating `transaction`, `query`, `storage`, and `graph`; model and errors
remain foundational. The query pipeline reads committed graph state. Storage
code owns durable formats and recovery, while internal index and log-record
types do not escape the public API.

## Data and indexes

Nodes have immutable database-assigned IDs, string labels, and scalar
properties. Directed edges have immutable IDs, endpoints, one string type, and
scalar properties. The planned scalar variants are Bool, Int64, finite Float64,
String, and Bytes. Nested values, arrays, and object references are excluded
from v0.1.

The graph maintains ID, label, edge-type, and incoming/outgoing adjacency
indexes. User-declared equality indexes are scoped by entity kind and label or
edge type; definitions persist and derived index contents are rebuilt during
recovery. Index changes are part of a transaction's candidate state so a
failure or rollback cannot publish partial index updates.

## Transactions and durable state

The v0.1 design allows one writer per database directory. A write transaction
modifies a private candidate graph/index state; ordinary reads continue to see
the last committed state. Commit validates the candidate, appends one complete
versioned and checksummed transaction record, synchronizes the log, and only
then publishes the candidate in memory. Rollback discards it. A failed write
poisons the transaction, which must be rolled back.

Startup selects and validates a snapshot, rebuilds derived indexes, and replays
subsequent complete WAL records. An incomplete final record is treated as a
truncated tail; a complete record with invalid framing or checksum is reported
as corruption, not silently skipped. Checkpoint writes and synchronizes a
temporary snapshot before publishing its generation through a versioned
manifest.

These are design invariants only. The current implementation has no graph
state, transaction manager, WAL, snapshot, checkpoint, or recovery path.
Locking, durable sync, atomic replacement, and directory synchronization must
be verified for each supported native platform before those guarantees can be
claimed. Windows and Linux durability remain unverified gates.

## Query pipeline

The planned read-only language supports directed paths with up to three hops,
labels, edge types, equality predicates joined by `AND`, property/ID/label
projections, and `LIMIT`. It is not full openCypher. The lexer, parser, semantic
validator, planner, and executor are separate testable stages. Planning prefers
node-ID equality, applicable property equality indexes, label indexes, then a
full node scan; result ordering is deterministic.

No query parser, planner, executor, or CLI command is implemented yet. The
planned grammar and explicit exclusions are recorded in the
[approved design](superpowers/specs/2026-09-20-moonpropertydb-design.md).
