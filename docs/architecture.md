# Architecture overview

MoonPropertyDB is an embedded MoonBit property-graph library. The current
snapshot is the tested in-memory foundation; persistent storage and the query
and CLI layers remain planned v0.1 work.

## Current package boundary

The repository currently uses one root MoonBit package while the implementation
is split into cohesive source files:

```text
model.mbt          scalar values, node/edge IDs, detached records
errors.mbt         structured public error categories
graph.mbt          private graph state, adjacency and secondary indexes
database.mbt       public in-memory database boundary
transaction.mbt    detached candidate and commit/rollback lifecycle
*_test.mbt         public and white-box behavior tests
examples/          runnable in-memory example
```

The public generated interface is reviewed through `pkg.generated.mbti`.
Private graph and index representations do not cross the `Database` boundary.

## Implemented foundation

The current code supports typed IDs, scalar properties, node and directed-edge
CRUD, endpoint validation, incoming/outgoing adjacency, node-label and
edge-type indexes, node/edge equality-index maintenance, structured failures,
and a single active writer over a detached candidate graph. Commit publishes
the candidate atomically to the in-memory committed state; rollback discards
it. A failed transaction is poisoned until rollback.

The implementation is intentionally not described as a persistent database.
`Database::new_in_memory()` is the only constructor currently available.

## Planned v0.1 layers

```text
Application / CLI
        |
        v
Public Database API
        |
  +-----+------------------+
  |                        |
  v                        v
Transaction manager    Lexer -> Parser/AST -> Validator
  |                                      -> Planner -> Executor
  v                        |
Candidate graph state <----+
  |
  +-- ID maps, adjacency, label/type indexes, equality indexes
  |
  v
Versioned commit log + snapshots/checkpoints
```

The planned storage layer must append one versioned, checksummed transaction
record before publishing committed state. Startup will validate a compatible
snapshot and replay later complete records. The planned query layer is a
bounded read-only graph subset, not full openCypher. The CLI and dependency
graph example are still to be implemented.

## Correctness boundaries

The design excludes multi-writer concurrency, MVCC, distributed transactions,
range/composite/full-text/vector indexes, network serving, and browser/Wasm
persistence. No durability, recovery, snapshot, locking, query, or CLI claim
should be made until its implementation and integration tests exist.
