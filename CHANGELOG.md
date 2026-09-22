# Changelog

Not yet released. This file records verified repository behavior; planned
features are explicitly marked as planned.

## [0.1.0] - Unreleased

### Added

- MoonBit module metadata for `dtzrttp/moonpropertydb` with native target
  configuration and Apache-2.0 licensing.
- Typed node and edge IDs, scalar property values, detached node/edge records,
  source positions, and structured database errors.
- In-memory node and directed-edge CRUD with endpoint validation, incoming and
  outgoing adjacency, strict/cascade node deletion, and detached reads.
- Deterministic node-label and edge-type indexes.
- Node- and edge-property equality-index definitions, backfill, lifecycle
  posting maintenance, and failure-atomic graph operations.
- A single-writer in-memory transaction boundary with detached candidates,
  atomic commit publication, rollback, terminal states, and failed-transaction
  poisoning.
- Public and white-box tests; the current native suite contains 34 passing
  tests.
- A runnable local in-memory example under `examples/in_memory_graph`.
- Native CI checks for check, build, test, formatting, and generated interface.
- Architecture, query, file-format, recovery, benchmark, source, security,
  contribution, and third-party documentation.

### Planned and not yet implemented

- Persistent open/close storage, append-only commit logs, checksums, crash
  recovery, snapshots, checkpoints, and process locking.
- Query lexer/parser/planner/executor and the `moonpropertydb query` CLI.
- Full CLI commands, JSONL import/export, and the dependency-graph demo.
- Mooncakes publication and Gitlink synchronization.
