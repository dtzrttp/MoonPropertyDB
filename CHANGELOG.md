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
  tests locally; hosted CI is pending.

### Not included

- The Issue #13 branch currently implements private in-memory node/edge state;
  public Database APIs, secondary indexes, transactions, persistence, recovery,
  snapshots, queries, and CLI remain unimplemented.
