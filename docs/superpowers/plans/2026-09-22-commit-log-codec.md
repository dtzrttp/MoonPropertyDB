# Commit Log Codec Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Each task ends with its own tests, review gate, and meaningful commit.

**Goal:** Implement and test the in-memory WAL v1 record codec required to serialize one complete transaction record with deterministic framing and CRC32 validation.

**Architecture:** Add a private codec layer in the existing root package. A private `WalRecord` contains a transaction ID and tagged operation payloads; encoding produces one self-framed little-endian record, while decoding returns either a complete record with consumed length, an incomplete-tail result, or a structured corruption/format error. The codec does not append files, acquire locks, replay graph operations, or change the public `Database` API; those concerns remain in later storage and recovery issues.

**Tech Stack:** Moon `0.1.20260915`, native target, built-in `Bytes`, `Array`, `Byte`, and `UInt64` APIs verified with `moon ide doc`; no new dependency.

## Global Constraints

- Use the approved WAL v1 framing: `MPDBWAL\0` magic, little-endian fields, version `1`, zero flags, total record length, transaction ID, operation count, explicit operation lengths, payload, and CRC32/ISO-HDLC.
- Keep codec record and operation types private; do not expose log records or codec implementation through the public `.mbti` boundary.
- Reject invalid magic, unsupported version, nonzero flags, invalid record lengths, unknown operation tags, and checksum mismatches with structured `DatabaseError` values.
- Treat only an incomplete final byte sequence as `IncompleteLogRecord`; a complete frame with invalid content is corruption.
- Bound every length and count before converting it to an `Int` or slicing bytes; malformed input must not panic or allocate from an unchecked length.
- Use deterministic operation order supplied by the transaction layer; this issue does not invent transaction recording or graph replay semantics.
- Do not claim durable append, `fsync`, recovery, snapshots, process locking, or persistent `Database.open` until their code and tests exist.

---

### Task 1: Fixed-width encoding helpers and CRC32

**Files:**
- Create: `codec.mbt`
- Test: `moonpropertydb_wbtest.mbt`

**Interfaces:**
- Produces private helpers for appending little-endian `u16`, `u32`, and `u64` fields, reading checked fields from `Bytes`, and computing CRC32/ISO-HDLC.
- Consumes only verified core APIs: `UInt64::to_le_bytes`, `Byte::to_uint64`, `Bytes::makei`, `Bytes::get`, `Bytes::length`, and `Bytes::from_array`.

- [ ] **Step 1: Write the failing CRC test.** Add a whitebox test for the standard ASCII vector and fixed-width byte order:

```moonbit
test "wal codec uses crc32 iso hdlc and little endian fields" {
  inspect(wal_crc32(b"123456789"), content="3421780262")
  inspect(wal_u16_bytes(0x1234UL), content="b\"4\\x12\"")
  inspect(wal_u32_bytes(0x78563412UL), content="b\"\\x12\\x34\\x56x\"")
}
```

- [ ] **Step 2: Run the focused test to verify RED.** Run `moon test --target native --filter "wal codec uses crc32 iso hdlc and little endian fields"`. Expected: failure because the private codec helpers do not exist.

- [ ] **Step 3: Implement the helpers.** Use verified little-endian conversions for `u64`, take the low bytes for `u16` and `u32`, and implement CRC32 with the ISO-HDLC polynomial `0xEDB88320`, initial value `0xFFFFFFFF`, and final XOR `0xFFFFFFFF`. Keep all arithmetic in `UInt64` and return the low 32 bits as a `UInt64` so the frame code can append them without introducing a guessed `UInt32` type.

- [ ] **Step 4: Verify and commit.** Run the focused test, `moon check --target native`, and `moon fmt --check`. Commit only `codec.mbt` and the focused test with `feat(codec): add wal byte and checksum primitives`.

### Task 2: WAL v1 frame encoding

**Files:**
- Modify: `codec.mbt`
- Test: `moonpropertydb_wbtest.mbt`

**Interfaces:**
- Produces private `WalOperation { tag : Byte, payload : Bytes }`, `WalRecord { transaction_id : UInt64, operations : Array[WalOperation] }`, and `wal_encode(record : WalRecord) -> Bytes`.
- The encoded frame layout is fixed: 8-byte magic, 2-byte version, 2-byte flags, 8-byte total length, 8-byte transaction ID, 4-byte operation count, repeated 1-byte tag + 8-byte payload length + payload, and 4-byte CRC.

- [ ] **Step 1: Write the failing frame test.** Construct a record with transaction ID `7` and two tagged payloads, assert the magic, header fields, operation count, explicit payload lengths, and checksum. Assert that encoding the same record twice returns byte-equal results.

- [ ] **Step 2: Run RED.** Run `moon test --target native --filter "wal record encoding is deterministic"`. Expected: failure because `WalRecord`, `WalOperation`, and `wal_encode` are absent.

- [ ] **Step 3: Implement minimal framing.** Build the prefix in an `Array[Byte]`, append each operation in supplied order, compute total length including the trailing four-byte checksum, patch the length field before calculating CRC, and append the checksum. Reject an operation payload whose length cannot be represented safely by the frame helper with `DatabaseError::CorruptLogRecord` using a codec offset of zero.

- [ ] **Step 4: Verify and commit.** Run the focused test and the full native test suite. Commit only codec and test changes with `feat(codec): encode versioned wal records`.

### Task 3: WAL v1 decoding and corruption classification

**Files:**
- Modify: `codec.mbt`, `errors.mbt`
- Test: `moonpropertydb_wbtest.mbt`, `moonpropertydb_test.mbt`

**Interfaces:**
- Produces private `WalDecode::Complete(record~ : WalRecord, consumed~ : Int)`, `WalDecode::Truncated`, and `wal_decode(bytes : Bytes, file~ : String, offset~ : UInt64) -> WalDecode raise DatabaseError`.
- Uses `IncompleteLogRecord`, `LogChecksumFailed`, `CorruptLogRecord`, and `IncompatibleDatabaseFormat` without exposing codec-specific types publicly.

- [ ] **Step 1: Write failing decoder tests.** Cover round-trip, truncated fixed header, truncated declared frame, checksum mismatch, bad magic, unsupported version, nonzero flags, impossible short length, unknown operation tag, and trailing bytes after one complete frame. Assert the structured error variant and byte offset for complete corruption cases; assert `Truncated` only for an incomplete tail.

- [ ] **Step 2: Run RED.** Run `moon test --target native --filter "wal record decoder"`. Expected: compilation failure until the decode result and decoder exist.

- [ ] **Step 3: Implement checked decoding.** Check the fixed header before every access. Read the declared length, reject values below the fixed header plus checksum, return `Truncated` when the available byte count is smaller than the declared frame, and slice only after the length has been proven to fit in the available `Int` range. Validate magic, version, flags, operation count, operation payload boundaries, required operation tags, and CRC in that order. Return `consumed` so a future log scanner can continue after one frame and report the exact offset of the next record.

- [ ] **Step 4: Verify and commit.** Run focused decoder tests, the full native suite, and `git diff --check`. Commit with `test(codec): classify wal truncation and corruption` after confirming no public interface changes.

### Task 4: Documentation, progress record, and delivery validation

**Files:**
- Modify: `CHANGELOG.md`, `docs/file-format.md`, `docs/progress.md`
- Test/verification: repository checks and generated interface inspection

- [ ] **Step 1: Update truthful records.** Mark only the in-memory WAL record codec and its tests as implemented. State explicitly that file append, synchronization, recovery, and replay remain open work under Issues #8 and #9.

- [ ] **Step 2: Run the complete validation set.** Run:

```powershell
moon check --target native
moon test --target native
moon build --target native
moon fmt --check
moon info --target native
git diff --check
```

Expected: all commands exit zero and the test count increases only by the codec coverage actually added.

- [ ] **Step 3: Inspect and commit records.** Confirm `pkg.generated.mbti` exposes no private `WalRecord`, `WalOperation`, or `WalDecode` type. Commit documentation with `docs: record wal codec progress`.

- [ ] **Step 4: Review and delivery.** Request review of the complete branch, push `codex/7-commit-log-codec`, create a PR linked to Issue #7, wait for CI, and do not merge if checks fail.

## Self-review checklist

- The codec is pure in-memory code and does not silently imply durable storage.
- Lengths and counts are bounds-checked before slicing or allocation.
- Truncation is distinct from checksum/content corruption.
- Unknown operation tags are rejected rather than preserved as unvalidated input.
- Exact MoonBit byte and numeric APIs are backed by `moon ide doc` queries.
- No internal codec type reaches the public API or generated interface.
- The plan does not add dependencies or expand into recovery, snapshots, query, or CLI work.
