# MoonPropertyDB v0.1 Design

**Status:** Architecture and scope approved by the maintainer; this detailed specification is submitted for review before implementation planning or code.

## 1. Purpose and release boundary

MoonPropertyDB is an embedded, native MoonBit property-graph database. Applications use a documented MoonBit API; a local CLI provides database administration and the dependency-graph demonstration. The database runs in-process and stores its state in a user-selected directory.

The v0.1 P0 release covers scalar graph data, node and edge CRUD, derived graph indexes, single-writer atomic batch transactions, a versioned checksummed commit log, crash recovery, snapshots/checkpoints, the bounded read-only query language, the required P0 CLI commands, a fully local example, documentation and CI. JSONL import/export remains P1 and must not delay P0. This resolves the task brief's priority list in favor of its explicit P0/P1 designation even though the CLI overview also lists import/export.

The project does not claim openCypher compatibility or production-grade database replacement status. Multi-writer concurrency, MVCC, distributed operation, network serving, range/composite/full-text/vector indexes, schema constraints, log compaction, and browser/Wasm persistence are outside v0.1.

## 2. Architecture and package boundaries

Use one MoonBit module with acyclic packages, rather than either a single monolithic package or several separately versioned modules. This keeps the public boundary stable while allowing the lexer, parser, planner, storage codec and graph invariants to be tested independently.

Logical dependency direction:

```text
cmd -> database -> { transaction, query, storage, graph }
transaction -> { graph, storage, codec }
query -> { graph, model, errors }
storage -> { codec, model, errors, native-platform }
graph -> { index, model, errors }
codec -> { model, errors }
{ model, errors } -> no project packages
```

The intended package responsibilities are:

- `model` and `errors`: IDs, scalar values, nodes, edges and structured public/internal errors.
- `graph` and `index`: committed in-memory state, ID maps, labels, edge types, incoming/outgoing adjacency and declared equality-index definitions/data.
- `codec` and `storage`: versioned binary encodings, WAL append/replay, snapshots, checkpoint publication, locking and recovery.
- `transaction`: transaction lifecycle and private candidate state; it coordinates graph changes with durable commit.
- `query/{lexer,ast,parser,semantic,planner,executor}`: read-only query pipeline with separately testable stages.
- `database`: stable documented API; internal log records and index structures do not escape.
- `cmd/moonpropertydb`: CLI, depending on the public database boundary rather than storage internals.

The exact MoonBit directory/configuration layout will follow `moon new`, the installed toolchain, and `moon info`; this logical layout does not presume unverified package syntax.

## 3. Data and graph invariants

Nodes have database-assigned immutable IDs, a set of string labels and a map from string keys to scalar values. Edges have database-assigned immutable IDs, directed `from` and `to` node IDs, one string type and scalar properties. The supported property variants are Bool, Int64, Float64, String and Bytes; nested values and graph references are excluded.

The storage codec uses fixed-width 64-bit IDs and deterministic little-endian encoding. IDs are positive and monotonically allocated within a database; committed IDs are never reused. IDs allocated only in a rolled-back transaction are not committed and may be reused, so callers must discard IDs returned by rolled-back transactions. Map and set serialization order is canonical so equivalent committed states have stable encodings.

Labels are unique per node. Adding an existing label and removing an absent label are idempotent. Setting an existing property replaces its value; property deletion is explicit. Edge creation validates both endpoints. Ordinary node deletion fails when incident edges exist; cascade deletion is a distinct explicit API operation and removes all incident edges and their index entries.

Float values must be finite; negative zero is normalized to positive zero. This gives persistence, query equality and JSON-facing tools a stable scalar domain. If the maintainer wants IEEE NaN/infinity support, that changes query/index equality and serialization and should be decided during this spec review.

## 4. Public API and transaction semantics

`Database.init(path)` creates a new store and must refuse to overwrite an initialized database. `Database.open(path, options)` opens an existing store and returns a structured not-initialized/not-found error rather than silently creating one. The public API exposes close, committed node/edge reads, query, stats, verify and checkpoint. A write transaction exposes node/edge creation, lookup where appropriate, labels/properties changes, strict/cascade node deletion, edge deletion, equality-index creation, commit and rollback. The v0.1 open mode is read/write and holds the exclusive writer lock for the handle lifetime; an independent read-only handle is not promised. Closing with an active transaction rolls it back before releasing resources. Every public operation has API documentation and expected failures use structured errors, not panic for user input.

Only one writer may hold a database directory at a time, including across processes. The database acquires an OS-backed exclusive lock for its open lifetime. Only one write transaction may be active through a given database handle. Ordinary reads observe the latest published commit and never see a transaction's candidate state. Concurrent read thread-safety beyond that guarantee is not promised in v0.1.

Each transaction mutates a private candidate graph/index state and records a deterministic operation sequence. A failed write operation leaves the candidate unchanged for that operation and poisons the transaction; a poisoned transaction cannot commit and must be rolled back. Commit validates the candidate, encodes exactly one complete transaction record, appends it to the WAL and synchronizes the log before swapping the candidate into the database's committed state. Thus serialization or I/O failure cannot publish a partial in-memory graph. Rollback discards the candidate. Committed and rolled-back transactions are terminal.

If an append/sync failure cannot be proven rolled back to the old WAL length and synchronized, the database enters a recovery-required state and returns a distinct `CommitOutcomeUnknown` error. The caller must close/reopen and inspect the recovered state before retrying; an I/O error must not be misreported as a definite abort when durability is uncertain.

## 5. Indexes and verification

Always-maintained in-memory indexes include node ID, edge ID, node label, edge type, incoming adjacency and outgoing adjacency. User-declared equality indexes are keyed by entity kind, label/type scope, property name and typed scalar value. The required CLI form creates a node index scoped to a label and property; the API may also create an edge-type-scoped index. Index definitions persist; index contents are derived and rebuilt on open.

All index changes are part of candidate-state application, so failed operations and rollback cannot alter committed indexes. Creating an index builds it from the candidate graph and commits its definition atomically with the transaction. `verify` checks graph references and compares maintained/rebuilt indexes, and validates the selected snapshot and WAL framing/checksums.

## 6. WAL record and recovery

WAL v1 is a sequence of self-framed records. All integer fields are little-endian. A record is:

| Field | Encoding |
|---|---|
| Magic | 8 bytes: `MPDBWAL\0` |
| Format version | u16, initially 1 |
| Reserved flags | u16, must be zero in v1 |
| Total record length | u64, including header and trailing checksum |
| Transaction ID | u64, strictly increasing |
| Operation count | u32 |
| Operation payload | Deterministic tagged operations with explicit lengths |
| Checksum | u32 CRC-32/ISO-HDLC over every preceding record byte |

The decoder bounds-checks every length/count before allocation, rejects unknown required operation tags and unsupported versions, and applies a decoded record to a private candidate before publishing recovered state. Transaction IDs at or below the selected snapshot boundary are skipped; subsequent records must be strictly sequential and may not be applied twice.

At EOF, fewer bytes than a complete fixed header or a valid header whose declared record extends beyond EOF is an incomplete tail and is ignored. A complete record with a bad checksum, invalid magic/version/length, or invalid operation is corruption and stops open/verify with file and byte-offset context. A checksum error is never silently treated as a truncated tail.

The log is append-only and is not compacted in v0.1. Successful `commit()` is returned only after the platform's required synchronization succeeds. The exact standard-library or private native implementation for durable append must be verified against the installed MoonBit toolchain before code is written.

## 7. Snapshots and checkpoint publication

A snapshot contains the database format version, last included transaction ID, next node/edge IDs, canonical node/edge data and equality-index definitions, plus a CRC-32/ISO-HDLC checksum. Derived in-memory index contents are rebuilt on recovery.

Checkpoint writes a complete temporary snapshot in the database directory, synchronizes it, and publishes it as an immutable generation named from its transaction ID. It then writes and synchronizes a temporary `CURRENT` manifest and atomically replaces the formal manifest. The manifest identifies the selected generation and is itself versioned/checksummed. A crash before manifest replacement leaves the previous selection intact; orphan generations are harmless. Older generations and the complete WAL are retained in v0.1, so recovery can fall back to an older valid snapshot or replay from the beginning. Snapshot pruning and log compaction are deferred.

Open validates the selected snapshot and replays only later WAL records. If the manifest is damaged, it may choose the newest valid compatible generation; an unsupported newer format is reported as incompatible rather than silently downgraded. With no usable snapshot, full WAL replay is allowed only when the log provides a complete history from transaction 1. Snapshot generation publication, manifest replacement, directory synchronization and cross-process locking must be proven for the supported native platforms before those guarantees are claimed.

## 8. Query language

The query pipeline is Lexer -> Parser/AST -> Semantic Validator -> Planner -> Executor. The grammar supports `MATCH`, explicitly directed paths of zero to three hops, node variables, zero or more node labels (all listed labels must match), optional edge variables/types, `WHERE` with one or more equality predicates joined only by `AND`, `RETURN` projections and optional nonnegative integer `LIMIT`. It has no write clauses, OR, aggregation, optional match, subqueries, user functions or unbounded paths.

Property references use `variable.property`; node `id` and `labels` are built-in projections. Edge variables may project edge properties. Literals cover Bool, Int64, finite Float64, String and a documented hexadecimal Bytes literal (`0x` followed by an even number of hex digits). A missing property or type-mismatched equality predicate does not match. Keywords are case-insensitive; identifiers, labels, types and property keys are case-sensitive.

Planner access priority is node-ID equality, applicable declared equality index, label index, then full node scan. A deterministic tie-break chooses the anchor variable and stable ID iteration order. The executor emits one row per matched path, orders rows by the pattern's node IDs followed by edge IDs, then applies `LIMIT`; repeated executions over unchanged committed data return the same rows. Parse diagnostics include a zero-based UTF-8 byte offset and one-based line/column.

Lexer, parser, semantic validation, planner and executor have independent tests. Unsupported syntax and invalid references fail before execution and cannot mutate the database.

## 9. CLI, demo and error contract

The native `moonpropertydb` CLI provides `init`, `query`, `index create`, `stats`, `verify`, `checkpoint` and `--help`; `init` refuses an existing initialized store. `index create` persists its definition as a normal atomic write transaction. JSON output is supported for query, stats and verify. Normal results go to stdout, errors to stderr, with stable nonzero exit codes. Bytes in CLI JSON are represented as a single-key object `{"$bytes":"<base64>"}`. JSONL `import`/`export` are P1: import is all-or-nothing; export has deterministic order and uses the same byte representation.

The dependency-graph example is fully local and exercises database creation, fixture data, direct and two-hop dependency queries, stats, an equality index, checkpoint, close/reopen and verify. It must not rely on an external service.

Structured errors distinguish closed/uninitialized/incompatible database, writer lock, missing node/edge/endpoint, incident-edge deletion, invalid property value/type (including non-finite floats or unsupported imported/decoded types), duplicate/missing index, transaction terminal/failed states, query lexical/syntax/semantic failures with position, incomplete log tail (recovery diagnostic, not a fatal open error), WAL checksum/corruption, snapshot integrity, commit outcome unknown and I/O. Storage errors include file, byte offset and transaction ID when known.

## 10. Test and delivery strategy

Use test-first development. Unit tests cover scalar codecs, model invariants, graph/index maintenance, record/snapshot checksums, lexer/parser/planner/executor and transaction states. Integration tests cover reopen, atomic multi-operation commit, rollback, endpoint validation, strict/cascade deletion, index updates, adjacency cleanup, truncated tail, interior corruption, snapshot boundary replay, invalid-query non-mutation, deterministic results, second-writer rejection and verify. P1 adds failed-import atomicity and export/import equivalence.

Each major issue is implemented on a focused branch and reviewed in a PR linked to its issue. PR bodies record implementation, test evidence and known limitations. CI and final checks use the installed toolchain's verified equivalents of `moon check`, `moon test`, `moon fmt --check` and `moon info`. `CHANGELOG.md` and `docs/progress.md` are updated as work lands; no capability is marked complete until its tests and CI pass.

The approved milestone is `v0.1.0`. Work is sequenced as model/graph/indexes; transactions/WAL/recovery; snapshots; query pipeline; CLI; example/docs/CI. JSONL remains P1. The initial repository issues are linked from the milestone; their actual GitHub IDs are recorded in the project progress log.

## 11. Pre-implementation verification gates

No exact MoonBit API has been approved by inference. The empty repository's `moon ide doc '@json'` failed because no module/backend metadata exists. After this design is reviewed, module initialization must be followed by current-toolchain checks using `moon ide doc` for the actual JSON, bytes, collections, filesystem, file synchronization, locking/FFI, atomic replacement and CLI needs; `moon search`/`moon add`/`moon tree` must validate any chosen Mooncakes dependency and version. A package candidate surfaced by `moon search crc32` (`gmlewis/crc32@0.8.18`) is not selected; inspect its source, license and API before adoption. Prefer the smallest dependency set and record all third-party sources.

The initial runtime target is MoonBit native on Windows and Linux, subject to verifying the locking, durable append, atomic replacement and directory-sync guarantees on both. Use standard-library APIs where they meet the contract; otherwise isolate the smallest necessary platform shim behind private storage interfaces. If either platform cannot meet a stated guarantee, stop and revise this design with the maintainer rather than weakening the guarantee silently.
