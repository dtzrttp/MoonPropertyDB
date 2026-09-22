# WAL Recovery Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Each task ends with its own tests, review gate, and meaningful commit.

**Goal:** Add a pure in-memory WAL stream scanner that replays only complete sequential records after a snapshot boundary and reports middle corruption without treating a final truncated record as corruption.

**Architecture:** Build on the private WAL v1 decoder from Issue #7. The scanner walks a `Bytes` stream by the decoder's consumed length, checks transaction-ID monotonicity, skips records at or below a supplied snapshot boundary, and returns decoded records plus the last applied transaction ID. A short final record ends scanning normally; any corruption or non-sequential transaction ID raises a structured error. The scanner does not read files, apply graph operations, or publish database state.

**Tech Stack:** Existing Moon `0.1.20260915` native package, private `WalRecord`/`WalDecode`, `Bytes::add`; no new dependency.

## Global Constraints

- Do not claim database recovery, file I/O, snapshots, or transaction replay until those layers exist.
- A complete corrupt record in the middle of a byte stream must raise; only the final incomplete record may be ignored.
- Transaction IDs must increase strictly above the selected snapshot boundary; duplicate or skipped IDs are corruption for this scanner.
- Keep scanner types private and preserve the public `.mbti` boundary.
- Use tests first and verify the full native suite before delivery.

---

### Task 1: Scanner result and sequential stream walk

**Files:**
- Modify: `codec.mbt`
- Test: `moonpropertydb_wbtest.mbt`

- [ ] Write failing tests for an empty stream, two complete records, snapshot-boundary skipping, a truncated final record, duplicate IDs, and a gap in transaction IDs.
- [ ] Run the focused tests and confirm the scanner symbols are missing.
- [ ] Implement private `WalScanResult { records : Array[WalRecord], last_transaction_id : UInt64 }` and `wal_scan(bytes, file~, offset~, snapshot_transaction_id~)`, walking with `consumed` and stopping only on `WalDecode::Truncated`.
- [ ] Raise `CorruptLogRecord` with the record offset for duplicate/gap IDs; return only records with IDs greater than the boundary.
- [ ] Run focused and full native tests; commit `feat(recovery): scan sequential wal records`.

### Task 2: Corruption and tail integration coverage

**Files:**
- Modify: `moonpropertydb_wbtest.mbt`

- [ ] Add a complete middle-record checksum mutation followed by a valid record and assert the scanner raises `LogChecksumFailed` instead of stopping early.
- [ ] Add a truncated final record after one complete record and assert the complete record remains returned with its transaction ID.
- [ ] Add an empty stream and a stream containing only a truncated header; assert an empty result with no error.
- [ ] Run `moon test --target native`, `moon check --target native`, and `moon fmt --check`; commit `test(recovery): cover wal middle corruption and tails`.

### Task 3: Documentation and delivery validation

**Files:**
- Modify: `docs/recovery.md`, `docs/progress.md`, `CHANGELOG.md`

- [ ] Document the scanner as an in-memory recovery primitive, not durable database recovery.
- [ ] Record that file append, synchronization, graph operation replay, snapshots, and process locking remain unimplemented.
- [ ] Run `moon check --target native`, `moon test --target native`, `moon build --target native`, `moon fmt --check`, `moon info --target native`, and `git diff --check`.
- [ ] Inspect generated `pkg.generated.mbti` to confirm scanner internals remain private; commit `docs: record wal recovery scan progress`.
- [ ] Push the issue-specific branch, create a PR linked to Issue #8, wait for CI, and do not merge failing work.

## Self-review checklist

- Truncated EOF and middle corruption are distinct.
- Snapshot-boundary skipping does not silently accept duplicate or non-sequential post-boundary IDs.
- The scanner consumes only decoder output and does not duplicate framing logic.
- No file or native API is guessed or added in this subtask.
