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
  on Ubuntu; both `native` runs for [`PR #16`](https://github.com/dtzrttp/MoonPropertyDB/pull/16)
  passed on the then-current head `df9c089`.
- Native scaffold check and test commands exit successfully; the test command
  currently reports **0 tests** and `no test entry found`. This is not evidence
  that graph behavior has been tested.

The foundation work is being prepared for review; it has not yet been merged as
a v0.1 release. The feature list below is planned and not implemented.

## Issue #1 feature branch — not merged

The dependent branch `codex/1-graph-model-errors` currently contains typed
`NodeId`/`EdgeId`, the supported scalar `PropertyValue` variants, a string-keyed
`Properties` map, detached `Node`/directed `Edge` records, `SourcePosition`, and
24 distinct structured `DatabaseError` cases, including separate categories for
uninitialized databases, checksum failures, and complete-but-corrupt WAL and
snapshot content. `SourcePosition` documents UTF-8 byte offsets and
Unicode-scalar columns. `Float64` values may be represented before validation,
but database write boundaries must reject non-finite values and normalize
negative zero. Public signatures were checked in the current-toolchain-generated
`pkg.generated.mbti`; `moon test --target native` passes 3/3 and `moon check
--target native` passes on the branch.

`moon ide doc` is unavailable in the installed toolchain (`Fail to load core: no
metadata is available for any backend`). With maintainer authorization, the
generated `.mbti` plus compiler checks/tests are used as the fallback; this does
not mean `moon ide doc` succeeded. No graph CRUD, index, transaction, query,
storage, recovery, snapshot, or CLI behavior has been implemented by this
branch yet. Independent review approved the complete branch through `4d0aff4`.
[PR #17](https://github.com/dtzrttp/MoonPropertyDB/pull/17) is open against
`codex/4-project-foundation`; its latest hosted native check passed on head
`7d5646c`.
It has not been merged. The reviewer noted that the current
non-ASCII position test checks the documented value representation rather than
calculating a location from query text; a true lexer-position test is deferred
to Issue #3, where the lexer will exist.

## Issue #13 feature branch — not merged

The stacked branch `codex/13-in-memory-graph-store` contains the node-state
slice committed locally as `5304d3a`: monotonic node ID allocation with
explicit exhaustion, node create/get, unique and deterministic labels,
idempotent label changes, explicit node-property set/remove, finite-Float64
validation, negative-zero normalization, and input/output collection isolation.
The edge/adjacency slice adds directed create/get/delete, endpoint validation,
in/out adjacency, edge-property set/remove, detached results, and max edge-ID
exhaustion. The strict/cascade deletion slice rejects deleting connected nodes
unless cascade is explicit; cascades deduplicate self-loops, remove adjacency
entries, and prevalidate all incident edges before mutation. Tests also exercise
failure atomicity with a stale adjacency reference. The aggregate native suite
passes 13/13; native check, format check, info generation and diff check pass
locally. Generated `pkg.generated.mbti` adds `DatabaseError::NodeIdExhausted`
and `DatabaseError::EdgeIdExhausted`; `GraphState` remains private. Independent
review approved all three slices; the final deletion-atomicity test was added
after its coverage note and independently confirmed. [PR #18](https://github.com/dtzrttp/MoonPropertyDB/pull/18)
is open against the Issue #1 feature branch and closes Issue #13. The hosted
native check passed on implementation head `693f4fb` ([run](https://github.com/dtzrttp/MoonPropertyDB/actions/runs/35575788324)).
The PR is unmerged. Label/type index work is isolated on the separate Issue #12
branch; property equality indexes remain unimplemented.

The same installed-toolchain `.mbti` plus compiler/test fallback applies because
`moon ide doc` still reports no backend metadata; the command itself has not
succeeded.

## Issue #12 feature branch — not merged

The local branch `codex/12-label-type-indexes` is stacked on Issue #13 base
commit `9e003a7`. Commits `54c57fd` and `ae350b1` add private node-label and
edge-type inverted indexes to `GraphState`; follow-up commit `7af2f6e` records
TDD diagnostics and strengthens cascade/stale-adjacency coverage. Numeric ID
buckets are sorted and unique, empty buckets are removed, and lookups return
copies. Existing node create/label-change/delete/cascade and edge create/delete
paths maintain them.
Property mutations do not affect membership. Scan-oracle whitebox tests cover
creation, duplicate/idempotent labels, lower-ID re-add ordering, parallel edges,
property no-ops, failed operations, strict/cascade deletion, empty-bucket
cleanup, copied results, and invalid-property ID allocation. `GraphState` and
the index implementations remain private; no public API changed.

TDD evidence from the development session: before node-label implementation,
the observed diagnostics reported missing `GraphState::node_ids_with_label`
and `node_ids_by_label`; the later node slice passed 15/15. Before edge-type
implementation, the observed diagnostics reported missing
`GraphState::edge_ids_with_type` and `edge_ids_by_type`; the later full edge
slice passed 16/16.

Local verification on Moon `0.1.20260915`: `moon check --target native` passed;
`moon test --target native` passed 16/16; `moon fmt --check` passed;
`moon info --target native` passed; generated `pkg.generated.mbti` has no diff
from the Issue #13 base; and `git diff --check 9e003a7..HEAD` passed. Independent
reviews of `9e003a7..7af2f6e` and the exact final range `9e003a7..696fe2a`
found no actionable findings. [PR #19](https://github.com/dtzrttp/MoonPropertyDB/pull/19)
is open against `codex/13-in-memory-graph-store` and closes Issue #12. Its
hosted native check passed on head `696fe2a`
([run 35585875220](https://github.com/dtzrttp/MoonPropertyDB/actions/runs/35585875220)).
`moon ide doc` still fails with the no-backend-metadata error; current-toolchain
`.mbti` plus compiler/tests are
the maintainer-authorized fallback, not a successful `moon ide doc` run.

## Issue #6 feature branch — partial, unmerged

The issue-specific branch `codex/6-property-equality-indexes` is unmerged.
It contains private in-memory node indexes by `(label, property)` and edge
indexes by `(edge type, property)`, with typed-scalar backfill, deterministic
lookups and detached ID arrays. Node postings are maintained on node creation,
label addition/removal, property set/removal, strict deletion, and cascade
deletion. Edge postings are only built when the index is created; edge create,
property change/removal, direct deletion, and cascade cleanup maintain the
corresponding buckets, including empty-bucket cleanup while retaining index
definitions. Failed endpoint/property/index operations and stale-adjacency
cascade rejection are covered for failure atomicity and ID preservation. Task
4 is complete locally in commits `297452d` and `4689f43`; the latest native
suite passes **23/23**. These are internal graph-state capabilities and add no
public index API or CLI.

Issue #6 is not complete or closable. Issue #7 rollback atomicity must verify
that transaction rollback leaves both index definitions and contents
unchanged; transactions are not implemented here. Persistence and snapshot
integration for index definitions and contents also remain outstanding, as do
public APIs/CLI integration. The approved design addendum is
`docs/superpowers/specs/2026-09-21-property-equality-indexes-design.md`.

### Windows checkout status note

Git reports CRLF/filter-only worktree status flags for `errors.mbt`,
`model.mbt`, `moon.mod`, `moon.pkg`, `moonpropertydb.mbt`,
`moonpropertydb_test.mbt`, and `pkg.generated.mbti`. Their index and worktree
object IDs match, and they have no content diff; they were not staged. Do not
change Git configuration or stage these files to clear the flags.

## P0/P1 status

| Area | Status |
|---|---|
| Module and project foundation | Present on the foundation branch; both PR #16 Linux `native` runs on `df9c089` passed |
| Public graph model and structured errors | Present on unmerged Issue #1 branch; reviewed/CI pending |
| In-memory graph store | Private node/edge CRUD, adjacency, and strict/cascade node deletion on unmerged Issue #13 PR #18; local tests pass 13/13; hosted native check passed on `693f4fb` |
| Label/type secondary indexes | Implemented privately on unmerged PR #19; local tests pass 16/16; hosted native check passed on `696fe2a` |
| Property equality indexes | Partial/private: node and edge definitions, backfill, lookups, and node/edge lifecycle postings are implemented and tested; public API/CLI, Issue #7 rollback atomicity, and persistence/snapshot integration remain outstanding; latest native suite 23/23 |
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
