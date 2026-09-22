# Changelog

Not yet released. This changelog records repository changes; planned features
are not listed as delivered.

## [0.1.0] - Unreleased

### Added

- Initialized the MoonBit module and project metadata.
- Added the least-privilege Ubuntu GitHub Actions workflow for native MoonBit checks.
- Added the Apache-2.0 license and baseline project, architecture, contribution,
  security, and third-party documentation.
- On the unmerged Issue #1 feature branch, added typed node/edge IDs, scalar
  property values, detached node/edge records, source locations, and structured
  database error categories for uninitialized databases, corrupt WAL records,
  and corrupt snapshots. That branch has 24 error categories and passes 3/3
  native tests.
- On the stacked, unmerged Issue #13 branch, added private in-memory node and
  edge state with create/get/delete, endpoint validation, incoming/outgoing
  adjacency, property updates, detached collection copies, scalar validation,
  and explicit strict/cascade node deletion with self-loop deduplication and
  failure-atomic prevalidation. It adds `NodeIdExhausted` and
  `EdgeIdExhausted` (26 categories on this branch) and passes 13/13 native
  tests locally; the hosted native check passed on the initial PR head
  `693f4fb`.
- On the unmerged Issue #12 feature branch, added private node-label and
  edge-type inverted indexes with ascending numeric ID buckets, mutation
  maintenance, copied lookups, and scan-oracle coverage. The full native suite
  passes 16/16 locally; hosted CI is pending. These indexes are in-memory only;
  public index APIs, property equality indexes, transactions, persistence,
  query, and CLI integration remain unimplemented.
- On the unmerged `codex/6-property-equality-indexes` branch, added private
  in-memory node and edge equality-index definitions, backfill and lookups.
  Node postings are maintained on node create, label add/remove, property
  set/remove, strict delete, and cascade delete. Edge postings are maintained
  across create, property replacement/removal/reinsertion, direct deletion,
  and cascade deletion, with failure-atomic validation coverage. The latest
  native suite passes 23/23. This remains a partial Issue #6 implementation,
  not a closable issue: public APIs/CLI, Issue #7 rollback atomicity, and
  persistence/snapshot integration remain outstanding.
- On the unmerged Issue #7 branch, added an in-memory single-writer transaction
  boundary. Transactions stage graph and index changes on detached candidates,
  poison themselves after graph errors, commit atomically into committed reads,
  and roll back without publishing staged state. Closing an active database
  rolls back its writer. This remains an in-memory transaction slice; WAL,
  persistence, recovery, snapshots, queries, and CLI behavior are not included.

### Not included

- The Issue #13 base branch implements private in-memory node/edge state. The
  Issue #12 candidate adds private label/type indexes on top. The Issue #6
  branch adds private node/edge equality-index definitions and lookups, with
  node and edge lifecycle posting maintenance. Persistent storage, recovery,
  snapshots, queries, CLI integration, and public index APIs remain
  unimplemented or outstanding.
