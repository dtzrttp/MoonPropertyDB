# Write Transactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Each task ends with its own tests, review gate, and meaningful commit.

**Goal:** Add a single-writer, failure-atomic in-memory transaction boundary that publishes graph and index changes only on commit and leaves no staged state visible to committed reads.

**Architecture:** `Database` owns a shared private `DatabaseState` containing the committed `GraphState`, closed flag, and active transaction handle. `WriteTransaction` owns a deep candidate copy and a shared terminal status reference. Begin-write rejects a second writer; reads use the committed graph; commit swaps the candidate into the shared database state; rollback discards it. The slice deliberately stops before WAL, filesystem locks, recovery, snapshots, query, and CLI integration.

**Tech Stack:** Moon `0.1.20260915`, native target, existing `GraphState`, `Map`, `Array`, and `Ref` APIs; no new dependencies.

## Global Constraints

- Use MoonBit as the implementation language and verify exact APIs with the installed `moon ide doc` plus compiler diagnostics.
- Keep `GraphState`, index definitions, `DatabaseState`, and transaction internals private; preserve the public `database` boundary.
- Use structured `DatabaseError` values for expected failures; do not use panic for ordinary input or lifecycle errors.
- Keep all five scalar property variants, finite-Float64 validation, negative-zero normalization, sorted unique detached indexes, and existing graph mutation semantics unchanged.
- A failed write operation must leave the candidate unchanged for that operation and poison the transaction; a poisoned transaction must roll back before reuse.
- Do not claim WAL durability, crash recovery, process locks, snapshots, query, CLI, or persistent `Database.open` in this branch.
- Before each commit stage only the paths named by that task; run `moon check --target native`, `moon test --target native`, `moon fmt --check`, `moon info --target native`, and `git diff --check` at the relevant boundary.

---

### Task 1: Deep candidate graph copy and invariant test fixture

**Files:**
- Modify: `graph.mbt` near `GraphState::new` and the existing private graph methods.
- Test: `moonpropertydb_wbtest.mbt`.

**Interfaces:**
- Consumes: existing private `GraphState`, `Node`, `Edge`, adjacency maps, label/type indexes, property indexes, and `Map::copy`/`Array::copy`.
- Produces: private `GraphState::copy_detached() -> GraphState` that copies every mutable collection and preserves ID counters for transaction candidates.

- [ ] **Step 1: Write the failing whitebox test.** Create two nodes, a labeled/property-indexed edge, parallel adjacency, and both property indexes. Copy the state, mutate the copy, and assert the original records, adjacency, index lookups, and next IDs remain unchanged.

```moonbit
test "graph candidate copy detaches graph and every index collection" {
  let original = GraphState::new()
  let first = original.create_node(["User"], { "name": PropertyValue::String("A") })
  let second = original.create_node(["User"], { "name": PropertyValue::String("B") })
  let edge = original.create_edge(first, second, "KNOWS", { "weight": PropertyValue::Int64(1) })
  original.create_node_property_index("User", "name")
  original.create_edge_property_index("KNOWS", "weight")
  let copy = original.copy_detached()
  copy.set_node_property(first, "name", PropertyValue::String("changed"))
  copy.delete_edge(edge)
  assert_eq(original.get_node(first).properties.get("name"), Some(PropertyValue::String("A")))
  assert_eq(original.outgoing_edges(first).length(), 1)
  assert_eq(original.node_ids_by_property_index("User", "name", PropertyValue::String("A")), Some([first]))
  assert_eq(original.edge_ids_by_property_index("KNOWS", "weight", PropertyValue::Int64(1)), Some([edge]))
  assert_eq(original.create_node([], {}), NodeId(3))
}
```

- [ ] **Step 2: Run the focused test to verify RED.** Run `moon test --target native --filter "graph candidate copy detaches graph and every index collection"`. Expected: compilation fails only because `GraphState::copy_detached` is absent.

- [ ] **Step 3: Implement the minimal deep copy.** Copy each node and edge record with copied labels/properties. Build new adjacency, label, type, and nested property-index maps with copied ID arrays and value buckets. Preserve `next_node_id` and `next_edge_id` exactly; expose no helper publicly.

```moonbit
fn copy_node(node : Node) -> Node {
  Node::Node(id=node.id, labels=node.labels.copy(), properties=node.properties.copy())
}

fn copy_edge(edge : Edge) -> Edge {
  Edge::Edge(id=edge.id, from=edge.from, to=edge.to, edge_type=edge.edge_type, properties=edge.properties.copy())
}

fn GraphState::copy_detached(self : GraphState) -> GraphState {
  // Construct fresh maps, copy every nested Array/map bucket, and preserve counters.
}
```

- [ ] **Step 4: Verify.** Run the focused test and then `moon test --target native`. Expected: focused test passes and the suite grows from 23 to 24 with zero failures.

- [ ] **Step 5: Commit.** Stage only `graph.mbt` and `moonpropertydb_wbtest.mbt`; commit `feat(graph): add detached transaction candidates`. Independently review this task and confirm no public `.mbti` change.

---

### Task 2: Database committed-state boundary and single active writer

**Files:**
- Create: `database.mbt`.
- Modify: `errors.mbt` only for a missing transaction-state error, if compiler/test evidence requires it.
- Test: `moonpropertydb_wbtest.mbt`, `moonpropertydb_test.mbt`.

**Interfaces:**
- Consumes: `GraphState::new`, `GraphState::copy_detached`, detached reads, and `DatabaseError`.
- Produces: documented `Database::new_in_memory`, `get_node`, `get_edge`, `begin_write`, and `close`; private `DatabaseState` and writer-slot ownership.

- [ ] **Step 1: Write failing tests.** Cover an empty database, committed reads, staged-data invisibility, and rejection of a second writer.

```moonbit
test "staged data is invisible and only one writer is active" {
  let database = @moonpropertydb.Database::new_in_memory()
  let transaction = database.begin_write()
  let node_id = transaction.create_node([], {})
  assert_raises(() => database.get_node(node_id), @moonpropertydb.DatabaseError::NodeNotFound(..))
  assert_raises(() => database.begin_write(), @moonpropertydb.DatabaseError::WriterTransactionActive)
}
```

If the existing error contract needs a new category, add one structured `DatabaseError` variant and document it; do not encode lifecycle failures as strings or panics.

- [ ] **Step 2: Run RED.** Run `moon test --target native --filter "staged data is invisible and only one writer is active"`. Expected: compilation fails only because the Database boundary is absent.

- [ ] **Step 3: Implement the boundary using the verified `Ref` API.** Keep all fields private and share state between the two public handles:

```moonbit
priv struct DatabaseState {
  mut committed : GraphState
  mut active : Ref[TransactionStatus]?
  mut closed : Bool
}

pub(all) struct Database { state : Ref[DatabaseState] }

pub fn Database::new_in_memory() -> Database
pub fn Database::get_node(self : Database, id : NodeId) -> Node raise DatabaseError
pub fn Database::get_edge(self : Database, id : EdgeId) -> Edge raise DatabaseError
pub fn Database::begin_write(self : Database) -> WriteTransaction raise DatabaseError
pub fn Database::close(self : Database) -> Unit raise DatabaseError
```

`begin_write` checks `closed` and `active`, creates a shared status handle, and copies the committed graph. Reads use only `committed`; no internal graph or index type appears in the public interface.

- [ ] **Step 4: Verify.** Run the focused test, `moon check --target native`, `moon test --target native`, and `moon info --target native`. Inspect generated `.mbti` and retain only intentional Database/error declarations.

- [ ] **Step 5: Commit.** Stage only `database.mbt`, `errors.mbt`, the two test files, and intentional `pkg.generated.mbti`; commit `feat(database): add committed-state write boundary`. Independently review read isolation, writer rejection, and closed-handle errors.

---

### Task 3: WriteTransaction operation delegation and failure poisoning

**Files:**
- Create: `transaction.mbt`.
- Modify: `database.mbt`, `errors.mbt` if the failed-state category is absent.
- Test: `moonpropertydb_wbtest.mbt`, `moonpropertydb_test.mbt`.

**Interfaces:**
- Consumes: the candidate/status handle, all existing `GraphState` mutation methods, and graph/index lookup methods.
- Produces: documented transaction methods for node/edge creation, reads, labels, properties, strict/cascade deletion, edge deletion, and property-index definitions.

- [ ] **Step 1: Write failing tests.** Cover all existing graph operations through a transaction. For each expected failure, snapshot candidate records/indexes/adjacency, assert the original structured error and exact unchanged state, and assert the private shared status becomes `Failed`. Public commit/rollback terminal behavior is tested in Task 4 after those methods exist.

```moonbit
test "failed write poisons transaction without partial candidate mutation" {
  let database = @moonpropertydb.Database::new_in_memory()
  let transaction = database.begin_write()
  let node = transaction.create_node(["User"], { "age": PropertyValue::Int64(1) })
  let before = transaction.get_node(node)
  let error = try transaction.set_node_property(node, "age", PropertyValue::Float64(Double::nan())) catch error { error }
  assert_eq(error, DatabaseError::InvalidPropertyValue(property="age", reason="non-finite float"))
  assert_eq(transaction.get_node(node), before)
  assert_eq(transaction.status.get(), Failed)
}
```

- [ ] **Step 2: Run RED.** Run `moon test --target native --filter "failed write poisons transaction without partial candidate mutation"`. Expected: compilation fails because transaction methods and the failed-state error are absent.

- [ ] **Step 3: Implement thin delegation.** Each operation checks `Active`, calls the corresponding candidate method, catches `DatabaseError`, changes the shared status to `Failed`, and re-raises the original error. Reads return detached candidate values. Do not add graph semantics here.

```moonbit
fn WriteTransaction::require_active(self : WriteTransaction) -> Unit raise DatabaseError {
  match self.status.get() {
    Active => ()
    Failed => raise DatabaseError::TransactionFailed
    Committed => raise DatabaseError::TransactionAlreadyCommitted
    RolledBack => raise DatabaseError::TransactionAlreadyRolledBack
  }
}

fn WriteTransaction::create_node(self : WriteTransaction, labels : Array[String], properties : Properties) -> NodeId raise DatabaseError {
  self.require_active()
  try { self.candidate.create_node(labels, properties) } catch error {
    self.status.update(fn(_) { Failed })
    raise error
  }
}
```

- [ ] **Step 4: Verify.** Run `moon test --target native`, then inspect every expected graph error and candidate ID counter after failure. Expected: all tests pass with no warning regressions.

- [ ] **Step 5: Commit.** Stage only the transaction/database/error/test/interface paths; commit `feat(transaction): stage graph writes and poison failures`. Independently verify no private map/index type escapes.

---

### Task 4: Commit, rollback, terminal states, and truthful records

**Files:**
- Modify: `transaction.mbt`, `database.mbt`.
- Test: `moonpropertydb_test.mbt`, `moonpropertydb_wbtest.mbt`.
- Modify: `CHANGELOG.md`, `docs/progress.md`.

**Interfaces:**
- Consumes: active candidate/status boundary and all transaction operations from Tasks 1–3.
- Produces: explicit `commit()` and `rollback()` with terminal-state enforcement and truthful documentation.

- [ ] **Step 1: Write failing lifecycle tests.** Cover multi-operation atomic commit, rollback with reusable candidate-only IDs, terminal commit/rollback errors, writer-slot release, close-time rollback, and committed property-index scan-oracle equality.

```moonbit
test "commit publishes a batch and rollback publishes nothing" {
  let database = @moonpropertydb.Database::new_in_memory()
  let first = database.begin_write()
  let first_id = first.create_node(["User"], {})
  first.commit()
  assert_eq(database.get_node(first_id).id, first_id)
  assert_raises(() => first.rollback(), @moonpropertydb.DatabaseError::TransactionAlreadyCommitted)
  let second = database.begin_write()
  let rolled_back_id = second.create_node(["User"], {})
  second.rollback()
  assert_raises(() => database.get_node(rolled_back_id), @moonpropertydb.DatabaseError::NodeNotFound(..))
  let third = database.begin_write()
  assert_eq(third.create_node(["User"], {}), rolled_back_id)
  third.commit()
}
```

- [ ] **Step 2: Run RED.** Run `moon test --target native --filter "commit publishes a batch and rollback publishes nothing"`. Expected: failure because publication and terminal handling are absent.

- [ ] **Step 3: Implement atomic publication.** Commit requires `Active`, validates candidate graph/index invariants, uses one `Ref::update` to replace `DatabaseState.committed`, clears the active handle, and marks the shared status `Committed`. Rollback clears the active handle without touching committed state and marks `RolledBack`; a failed transaction can only roll back. Close rolls back an active handle before setting `closed`.

- [ ] **Step 4: Run final checks.**

```powershell
moon check --target native
moon test --target native
moon fmt --check
moon info --target native
git diff --check 7abc1e6..HEAD
git diff --exit-code 7abc1e6..HEAD -- pkg.generated.mbti
```

Expected: all commands exit 0, all tests pass, and any `.mbti` additions are intentional public Database/transaction/error declarations.

- [ ] **Step 5: Update records and commit.** Record the exact test count and the remaining absence of WAL, persistence, recovery, snapshots, query, and CLI. Stage only the named code/test/docs/interface paths; commit `feat(transaction): publish and rollback atomic batches`. Request an independent review of the exact task range and then a whole-branch review before pushing an Issue #7 PR. Do not merge.

## Self-review checklist

- The design and plan keep Issue #7 limited to in-memory atomic transactions; WAL and persistence are explicitly deferred.
- Every task has a failing test, an expected RED result, a minimal implementation boundary, fresh verification, and a meaningful commit.
- The only intended public additions are a documented in-memory database/transaction boundary and structured transaction lifecycle errors; private graph/index maps never appear in `.mbti`.
- Existing property normalization and index maintenance are reused rather than reimplemented.
- The plan contains no unfinished-marker tokens and the names `Database`, `WriteTransaction`, `DatabaseState`, and `TransactionStatus` are consistent across tasks.
