# Write Transactions — Issue #7 Design

**Status:** Proposed implementation design for the unmerged `codex/7-write-transactions` branch. This slice implements transaction lifecycle and committed-state publication over the existing private in-memory graph/index state. WAL, filesystem locking, recovery, snapshots, and durable `Database.open` remain separate storage work and are not claimed here.

## Goal and boundary

Add a single-writer atomic batch layer that can stage graph and equality-index changes privately, expose only the last committed state to ordinary reads, and provide explicit terminal `commit` and `rollback` operations. A failed write operation leaves the candidate unchanged for that operation and marks the transaction failed; a failed transaction cannot commit and must be rolled back.

This slice covers:

- one active write transaction per database handle;
- candidate-state isolation from committed reads;
- node and edge CRUD, labels, properties, strict/cascade deletion, and property-index creation through a transaction;
- operation-level failure atomicity and structured transaction-state errors;
- successful in-memory publication on commit;
- terminal transaction states and close-time rollback of an active transaction.

This slice does not cover WAL encoding/appending, durable synchronization, OS process locks, crash recovery, snapshots, query execution, CLI commands, or a claim that `Database.open(path)` persists data. Those belong to storage/recovery and later integration issues.

## Chosen representation

Use copy-on-write at transaction begin by making a deep detached copy of `GraphState`, including:

- node and edge records with copied labels and property maps;
- node/edge ID maps;
- incoming/outgoing adjacency arrays;
- label and edge-type postings;
- node and edge property-index definitions and value buckets;
- next node and edge ID counters.

The database keeps the committed `GraphState` untouched while a transaction mutates its candidate. This is preferred over an undo journal because the existing graph operations already maintain several coupled maps; one deep copy gives rollback and failed-operation isolation a simple, testable boundary. The transaction candidate is discarded on rollback or failed terminal cleanup. IDs allocated only in the candidate are therefore reusable by a later transaction; callers must discard IDs from a rolled-back transaction.

## Lifecycle and ownership

`Database` owns the committed state, a closed flag, and at most one active `WriteTransaction`. `Database::begin_write` rejects a second active transaction with a structured error. Ordinary `get_node`, `get_edge`, adjacency, and index reads use only the committed state. The public database boundary does not expose `GraphState` or index maps.

`WriteTransaction` owns its candidate and has four internal states:

- `Active`: operations are allowed;
- `Failed`: a write operation returned an error; reads may be used for diagnostics, but commit is rejected and rollback is required;
- `Committed`: commit published the candidate and released the database's active-writer slot;
- `RolledBack`: rollback discarded the candidate and released the slot.

Every public transaction method checks the state before touching the candidate. Commit and rollback are terminal; repeated use returns `TransactionAlreadyCommitted` or `TransactionAlreadyRolledBack`. A failed transaction returns a distinct structured transaction-failed error for commit and cannot be reused for additional writes. Closing a database rolls back its active transaction before marking the handle closed.

## Commit semantics

For this in-memory slice, commit performs the final candidate validation, publishes the candidate as the database's committed state, releases the writer slot, and marks the transaction `Committed`. Publication is one state replacement; no ordinary read can observe an intermediate operation. A later storage issue will wrap this publication with one WAL record and required synchronization before the same swap.

If a transaction operation fails, graph/index state and ID counters in the candidate remain unchanged for that operation, then the transaction becomes `Failed`. Rollback remains available and restores the database handle to its pre-transaction committed state. A failed endpoint create, invalid property update, duplicate index definition, strict connected-node delete, or stale-adjacency cascade must be tested for this invariant.

## Testing strategy

Use whitebox tests for candidate/committed identity and index invariants, plus blackbox tests for the documented `Database` and `WriteTransaction` boundary. Required cases:

1. committed reads do not see staged nodes, edges, labels, properties, or index definitions;
2. commit publishes a multi-operation batch atomically;
3. rollback exposes no staged data and allows candidate-only IDs to be reused;
4. every expected failed operation preserves candidate graph, indexes, adjacency, and counters before poisoning the transaction;
5. a poisoned transaction cannot commit or continue writing, but can roll back;
6. commit and rollback are terminal and release the single-writer slot;
7. a second active writer is rejected while the first remains active;
8. close rolls back an active transaction and rejects subsequent operations;
9. committed node/edge property equality indexes match scan oracles after commit.

The branch must pass the installed MoonBit checks, tests, formatter, info generation, and generated-interface audit. No dependency is added.
