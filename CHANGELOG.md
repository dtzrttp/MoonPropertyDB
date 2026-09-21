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
- On the stacked, unmerged Issue #13 branch, added a private in-memory node
  state with create/get, id allocation, label and property updates, detached
  collection copies, and scalar validation. It adds the `NodeIdExhausted`
  error (25 categories on this branch) and passes 5/5 native tests locally.

### Not included

- The Issue #13 branch currently implements only private node-state behavior;
  public Database APIs, edge CRUD, node deletion, adjacency and secondary
  indexes, transactions, persistence, recovery, snapshots, queries, and CLI
  remain unimplemented.
