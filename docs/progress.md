# Development progress

This log distinguishes code currently present on the foundation branch from
planned v0.1 work. A design item is not complete merely because it appears in
the approved specification.

- **Milestone:** [v0.1.0](https://github.com/dtzrttp/MoonPropertyDB/milestone/1)
- **Current foundation issue:** [#4 — Initialize project, license and CI](https://github.com/dtzrttp/MoonPropertyDB/issues/4)
- **Approved design:** [MoonPropertyDB v0.1 design](superpowers/specs/2026-09-20-moonpropertydb-design.md)

## Delivered on the foundation branch

- MoonBit module scaffold `dtzrttp/moonpropertydb`, configured for the native
  target.
- Apache-2.0 license and initial contributor, security, third-party, and
  architecture documentation.
- Least-privilege GitHub Actions workflow configured for native MoonBit checks
  on Ubuntu; both initial [`PR #16`](https://github.com/dtzrttp/MoonPropertyDB/pull/16)
  workflow runs passed.
- Native scaffold check and test commands exit successfully; the test command
  currently reports **0 tests** and `no test entry found`. This is not evidence
  that graph behavior has been tested.

The foundation work is being prepared for review; it has not yet been merged as
a v0.1 release. The feature list below is planned and not implemented.

## P0/P1 status

| Area | Status |
|---|---|
| Module and project foundation | Present on the foundation branch; both initial PR #16 Linux CI runs passed |
| Graph model, node/edge CRUD, adjacency and label/type indexes | Planned; not implemented |
| Property equality indexes | Planned; not implemented |
| Atomic write transactions | Planned; not implemented |
| Commit log, corruption detection and recovery | Planned; not implemented |
| Snapshots and checkpoint | Planned; not implemented |
| Query lexer/parser/planner/executor | Planned; not implemented |
| CLI and local dependency-graph example | Planned; not implemented |
| JSONL import/export | P1; planned, not implemented |
| Windows/Linux durable sync, locking and atomic replacement guarantees | Unverified design gates |

## Tracked issues

All issues are associated with the [v0.1.0 milestone](https://github.com/dtzrttp/MoonPropertyDB/milestone/1):

- [#1 Define graph data model and public errors](https://github.com/dtzrttp/MoonPropertyDB/issues/1)
- [#2 Implement recovery and corruption detection](https://github.com/dtzrttp/MoonPropertyDB/issues/2)
- [#3 Implement query lexer and parser](https://github.com/dtzrttp/MoonPropertyDB/issues/3)
- [#4 Initialize project, license and CI](https://github.com/dtzrttp/MoonPropertyDB/issues/4)
- [#5 Complete documentation and release preparation](https://github.com/dtzrttp/MoonPropertyDB/issues/5)
- [#6 Implement property equality indexes](https://github.com/dtzrttp/MoonPropertyDB/issues/6)
- [#7 Implement write transactions](https://github.com/dtzrttp/MoonPropertyDB/issues/7)
- [#8 Add dependency-graph example](https://github.com/dtzrttp/MoonPropertyDB/issues/8)
- [#9 Implement CLI](https://github.com/dtzrttp/MoonPropertyDB/issues/9)
- [#10 Implement snapshots and checkpoints](https://github.com/dtzrttp/MoonPropertyDB/issues/10)
- [#11 Implement query planner and executor](https://github.com/dtzrttp/MoonPropertyDB/issues/11)
- [#12 Implement adjacency and label indexes](https://github.com/dtzrttp/MoonPropertyDB/issues/12)
- [#13 Implement in-memory graph store](https://github.com/dtzrttp/MoonPropertyDB/issues/13)
- [#14 Define commit-log format and codec](https://github.com/dtzrttp/MoonPropertyDB/issues/14)
- [#15 Add JSONL import and export](https://github.com/dtzrttp/MoonPropertyDB/issues/15)

Issue order reflects GitHub's assigned IDs. Update this status table and the
changelog when verified work lands; do not mark an item complete without the
corresponding tests and CI evidence.
