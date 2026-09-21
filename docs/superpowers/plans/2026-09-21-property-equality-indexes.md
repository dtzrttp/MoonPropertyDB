# Property Equality Indexes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement private in-memory node `(label, property)` and edge `(edge type, property)` equality indexes in `GraphState`, with deterministic typed-value lookups and consistent maintenance across graph mutations.

**Architecture:** Add definition-keyed nested maps to the existing private `GraphState`; each definition owns a typed `PropertyValue` to sorted, unique ID bucket map. Index creation builds from current graph records, later mutations update matching definitions, and lookups distinguish an undeclared index (`None`) from a declared index with no matching value (`Some([])`). Keep query, public Database API, transactions, persistence, and snapshot integration out of this branch; Issue #7 must later prove actual rollback.

**Tech Stack:** MoonBit module `dtzrttp/moonpropertydb`; current toolchain Moon `0.1.20260915`; native target; existing core `Map`, `Array`, scalar Eq/Hash implementations; whitebox tests in the root package.

## Global Constraints

- Use MoonBit as the main implementation language; do not add a dependency for this slice.
- Supported property scalar variants are `Bool`, `Int64`, `Float64`, `String` and `Bytes`.
- Float values must be finite; negative zero is normalized to positive zero.
- User-declared equality indexes are scoped by entity kind, label/type, property name and typed scalar value.
- Keep the graph and index implementation private; do not change the public `.mbti` interface.
- Keep packages acyclic and preserve the public `database` boundary.
- Index IDs are unique and sorted by their wrapped unsigned numeric ID; returned lookup arrays are detached copies.
- A declared index definition remains present when it has no values; empty value buckets are removed.
- No transaction rollback claim is allowed in this slice. Issue #6 remains open until Issue #7 integration proves rollback leaves graph and indexes unchanged.
- Keep `CHANGELOG.md` and `docs/progress.md` accurate; state that this branch is unmerged and that rollback/persistence/query/CLI integration is outstanding.
- Do not claim `moon ide doc` succeeded. It reproducibly fails because no backend metadata is available; use installed generated `.mbti` and compiler/test output as the maintainer-authorized fallback.
- Run native build/test commands from this managed worktree with narrowly scoped elevated execution if the sandbox returns Windows OS error 5; build outputs must stay in this worktree.
- Do not force-push or merge. The eventual PR must target the current Issue #12 branch and say `Refs #6`, not `Fixes #6`, until rollback acceptance is met.

---

## Files and ownership

- Modify `graph.mbt`: private index-definition key structs; `GraphState` index fields and initialization; index creation, lookup and posting helpers; hooks at the existing node/edge mutation paths.
- Modify `moonpropertydb_wbtest.mbt`: independent scan oracles, node/edge index behavior tests, typed scalar and failure-atomicity regressions.
- Modify `CHANGELOG.md`: record only locally verified implementation on the unmerged Issue #6 branch and preserve the unreleased status.
- Modify `docs/progress.md`: distinguish the new local Issue #6 candidate from its base; report local test totals and review/CI only after those actually pass; keep rollback explicitly outstanding.
- Do not modify `model.mbt`, `errors.mbt`, `pkg.generated.mbti`, module metadata, public API, transaction code, query code, storage code, or CLI for this slice. `DatabaseError::IndexAlreadyExists` already exists.

## Interfaces between tasks

The private key records are:

```moonbit
priv struct NodePropertyIndex {
  label : String
  property : String
} derive(Eq, Hash)

priv struct EdgePropertyIndex {
  edge_type : String
  property : String
} derive(Eq, Hash)

fn NodePropertyIndex::new(
  label : String,
  property : String,
) -> NodePropertyIndex

fn EdgePropertyIndex::new(
  edge_type : String,
  property : String,
) -> EdgePropertyIndex
```

`GraphState` will own:

```moonbit
node_property_indexes : Map[NodePropertyIndex, Map[PropertyValue, Array[NodeId]]]
edge_property_indexes : Map[EdgePropertyIndex, Map[PropertyValue, Array[EdgeId]]]
```

Create and lookup signatures are private package methods:

```moonbit
fn GraphState::create_node_property_index(
  self : GraphState,
  label : String,
  property : String,
) -> Unit raise DatabaseError

fn GraphState::node_ids_by_property_index(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Array[NodeId]? raise DatabaseError

fn GraphState::create_edge_property_index(
  self : GraphState,
  edge_type : String,
  property : String,
) -> Unit raise DatabaseError

fn GraphState::edge_ids_by_property_index(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Array[EdgeId]? raise DatabaseError

fn GraphState::add_node_property_posting(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
  node_id : NodeId,
) -> Unit

fn GraphState::remove_node_property_posting(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
  node_id : NodeId,
) -> Unit

fn GraphState::add_edge_property_posting(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit

fn GraphState::remove_edge_property_posting(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit
```

`None` means the exact `(scope, property)` definition is undeclared; `Some([])` means it exists but the exact typed value has no postings. Lookup validates/canonicalizes the supplied value with the existing `normalize_property_value` before using it as a hash key. No query planner or public API consumes these methods in this branch.

## Task 1: Node index definitions, build and lookup

**Files:** `graph.mbt`, `moonpropertydb_wbtest.mbt`.

**Consumes:** `GraphState.nodes`, `Node.labels`, `Node.properties`, `PropertyValue`, `DatabaseError::IndexAlreadyExists`, and the existing `compare_node_ids` helper.

**Produces:** `NodePropertyIndex`, `node_property_indexes`, a definition constructor/name helper, sorted posting helpers, `create_node_property_index`, `node_ids_by_property_index`, and node scan-oracle test helpers. This task tests indexes built over existing nodes; future-node and mutation maintenance are Task 2.

- [ ] **Step 1: Add RED tests for build, scope, duplicate definitions and absent results.** Add tests named `node property index builds from existing nodes and distinguishes absent definitions` and `node property index definitions are scoped and duplicates are rejected`. The first creates two matching `User` nodes with the same `email`, a matching node without `email`, and a non-`User` node with that value before creating the index. Assert that the lookup returns the matching IDs in numeric order, a missing value returns `Some([])`, and an undeclared property definition returns `None`. The second creates a second property index and a second label-scoped index, then repeats one exact definition and asserts `DatabaseError::IndexAlreadyExists(..)` without changing any earlier lookup.

```moonbit
test "node property index builds from existing nodes and distinguishes absent definitions" {
  let graph = GraphState::new()
  let first = try! graph.create_node(["User"], {
    "email": PropertyValue::String("a@example.test"),
  })
  let second = try! graph.create_node(["User"], {
    "email": PropertyValue::String("a@example.test"),
  })
  let no_email = try! graph.create_node(["User"], {})
  let other_label = try! graph.create_node(["Admin"], {
    "email": PropertyValue::String("a@example.test"),
  })

  try! graph.create_node_property_index("User", "email")
  try! graph.create_node_property_index("Ghost", "email")
  assert_eq(
    try! graph.node_ids_by_property_index(
      "User",
      "email",
      PropertyValue::String("a@example.test"),
    ),
    Some([first, second]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "User",
      "email",
      PropertyValue::String("missing@example.test"),
    ),
    Some([]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Admin",
      "email",
      PropertyValue::String("a@example.test"),
    ),
    None,
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Ghost",
      "email",
      PropertyValue::String("a@example.test"),
    ),
    Some([]),
  )
  assert_eq(try! graph.get_node(no_email).id, no_email)
  assert_eq(try! graph.get_node(other_label).id, other_label)
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "email",
    PropertyValue::String("a@example.test"),
  )
}
```

The second RED test has this exact scope/error shape:

```moonbit
test "node property index definitions are scoped and duplicates are rejected" {
  let graph = GraphState::new()
  let user = try! graph.create_node(["User"], {
    "email": PropertyValue::String("u@example.test"),
    "name": PropertyValue::String("User"),
  })
  let admin = try! graph.create_node(["Admin"], {
    "email": PropertyValue::String("a@example.test"),
  })
  try! graph.create_node_property_index("User", "email")
  try! graph.create_node_property_index("User", "name")
  try! graph.create_node_property_index("Admin", "email")

  try graph.create_node_property_index("User", "email") catch {
    DatabaseError::IndexAlreadyExists(..) => ()
    _ => fail("expected duplicate node property index to be rejected")
  } noraise {
    _ => fail("duplicate node property index must fail")
  }
  assert_eq(
    try! graph.node_ids_by_property_index(
      "User",
      "email",
      PropertyValue::String("u@example.test"),
    ),
    Some([user]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Admin",
      "email",
      PropertyValue::String("a@example.test"),
    ),
    Some([admin]),
  )
}
```

Add these complete scan-oracle helpers next to the existing label/type scan helpers in `moonpropertydb_wbtest.mbt`; each scans primary records and sorts by numeric ID, never by the index under test:

```moonbit
fn node_property_ids_by_scan(
  graph : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Array[NodeId] raise DatabaseError {
  let canonical = normalize_property_value(property, value)
  let ids : Array[NodeId] = []
  for node_id, node in graph.nodes {
    let mut has_label = false
    for node_label in node.labels.iter() {
      if node_label == label {
        has_label = true
      }
    }
    if has_label {
      match node.properties.get(property) {
        Some(stored) =>
          if stored == canonical {
            ids.push(node_id)
          }
        None => ()
      }
    }
  }
  ids.sort_by((left, right) => {
    match (left, right) {
      (NodeId(left_raw), NodeId(right_raw)) => left_raw.compare(right_raw)
    }
  })
  ids
}

fn assert_node_property_index_matches_scan(
  graph : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  assert_eq(
    graph.node_ids_by_property_index(label, property, value),
    Some(node_property_ids_by_scan(graph, label, property, value)),
  )
}
```

- [ ] **Step 2: Run the focused RED test before adding production declarations.** Run `moon test --target native`. Expected: compiler diagnostics identify the missing `NodePropertyIndex`/`node_property_indexes`, `create_node_property_index`, and `node_ids_by_property_index`; do not accept unrelated syntax, import, or package errors as RED evidence.
- [ ] **Step 3: Implement the node definition and lookup surface in `graph.mbt`.** Add the private record and outer map; initialize it to `Map([])` in `GraphState::new`. Add private insertion/removal helpers that copy the existing ID bucket, add/remove exactly one ID, sort with `compare_node_ids`, deduplicate, and remove a value key when its last posting disappears. The index-creation method must check the exact definition for duplication before scanning, build a local inner map from nodes whose labels contain `label` and whose property map contains `property`, then install the completed definition once. Its error name must identify node kind, label and property using the verified `String::add(String, String) -> String` API. Lookup canonicalizes the value with `normalize_property_value`, returns `None` for an undeclared definition, and otherwise returns a copied bucket or `Some([])`.

```moonbit
fn GraphState::node_ids_by_property_index(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Array[NodeId]? raise DatabaseError {
  let canonical = normalize_property_value(property, value)
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(values) =>
      Some(match values.get(canonical) {
        Some(ids) => ids.copy()
        None => []
      })
    None => None
  }
}
```

The node definition constructor, diagnostic name, sorted posting insertion and scan-build method must follow this exact contract; retain an empty inner map when the definition has no matching nodes. Add the removal helper only in Task 2 when its first caller is introduced, so Task 1 does not add an unused declaration.

```moonbit
fn NodePropertyIndex::new(
  label : String,
  property : String,
) -> NodePropertyIndex {
  { label, property }
}

fn node_property_index_name(label : String, property : String) -> String {
  String::add(
    String::add("node:", label),
    String::add(".", property),
  )
}

fn add_node_property_index_value(
  values : Map[PropertyValue, Array[NodeId]],
  value : PropertyValue,
  node_id : NodeId,
) -> Unit {
  let ids = match values.get(value) {
    Some(ids) => ids.copy()
    None => []
  }
  ids.push(node_id)
  ids.sort_by((left, right) => compare_node_ids(left, right))
  ids.dedup()
  values.set(value, ids)
}

fn GraphState::create_node_property_index(
  self : GraphState,
  label : String,
  property : String,
) -> Unit raise DatabaseError {
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(_) =>
      raise DatabaseError::IndexAlreadyExists(
        name=node_property_index_name(label, property),
      )
    None => ()
  }
  let values : Map[PropertyValue, Array[NodeId]] = Map([])
  for node_id, node in self.nodes {
    let mut has_label = false
    for node_label in node.labels.iter() {
      if node_label == label {
        has_label = true
      }
    }
    if has_label {
      match node.properties.get(property) {
        Some(value) => add_node_property_index_value(values, value, node_id)
        None => ()
      }
    }
  }
  self.node_property_indexes.set(definition, values)
}
```

- [ ] **Step 4: Run RED/GREEN and inspect only the intended files.** Run `moon test --target native`; expected GREEN is the two new node-definition tests plus the existing 16 tests passing. Run `git diff --check` and confirm `git status --short` contains only `graph.mbt` and `moonpropertydb_wbtest.mbt` (apart from known generated build artifacts, which must not be staged).
- [ ] **Step 5: Self-review and commit the node definition slice.** Confirm duplicate creation leaves the first index intact, a declared empty lookup differs from `None`, buckets are copied and sorted, and no posting maintenance is claimed yet. Stage only `graph.mbt` and `moonpropertydb_wbtest.mbt`; commit as `feat(graph): add node property equality indexes` with command-scoped `dtzrttp` author identity. The final whole-branch review will cover this commit.

## Task 2: Maintain node postings across every node mutation

**Files:** `graph.mbt`, `moonpropertydb_wbtest.mbt`.

**Consumes:** Task 1's `NodePropertyIndex`, node create/lookup methods, `PropertyValue` normalization and independent node scan oracle.

**Produces:** node postings that remain equal to primary graph scans after create, label changes, property set/remove, strict delete and cascade delete.

- [ ] **Step 1: Add a RED lifecycle test before changing graph mutation methods.** Add `node property postings match scans across node lifecycle`. Create a `User` with `age=Int64(1)`, build the `User.age` index, then create another `User` and verify its posting. Declare `Admin.age`, add/remove that label, replace age with `Int64(2)`, remove/reinsert it, and compare old/new values with the scan oracle after every operation. Add a connected `User`, prove strict delete returns `NodeHasIncidentEdges` without changing postings, then cascade-delete it and verify the definition remains while its value bucket is removed. Include a node without `age` to prove it has no posting.

```moonbit
test "node property postings match scans across node lifecycle" {
  let graph = GraphState::new()
  let first = try! graph.create_node(["User"], {
    "age": PropertyValue::Int64(1),
  })
  try! graph.create_node_property_index("User", "age")
  try! graph.create_node_property_index("Admin", "age")
  let second = try! graph.create_node(["User"], {
    "age": PropertyValue::Int64(1),
  })
  let without_age = try! graph.create_node(["User"], {})
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "age",
    PropertyValue::Int64(1),
  )

  graph.add_label(second, "Admin") catch {
    _ => fail("adding indexed label failed")
  }
  assert_node_property_index_matches_scan(
    graph,
    "Admin",
    "age",
    PropertyValue::Int64(1),
  )
  graph.set_node_property(second, "age", PropertyValue::Int64(2)) catch {
    _ => fail("replacing indexed node property failed")
  }
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "age",
    PropertyValue::Int64(1),
  )
  assert_node_property_index_matches_scan(
    graph,
    "Admin",
    "age",
    PropertyValue::Int64(2),
  )
  graph.remove_node_property(second, "age") catch {
    _ => fail("removing indexed node property failed")
  }
  graph.remove_node_property(second, "age") catch {
    _ => fail("repeating removal of an absent property should be idempotent")
  }
  graph.set_node_property(second, "age", PropertyValue::Int64(1)) catch {
    _ => fail("reinserting indexed node property failed")
  }
  try
    graph.set_node_property(
      second,
      "age",
      PropertyValue::Float64(@double.infinity),
    )
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("non-finite indexed property update should be rejected")
  } noraise {
    _ => fail("non-finite indexed property update should be rejected")
  }
  assert_eq(
    (try! graph.get_node(second)).properties.get("age"),
    Some(PropertyValue::Int64(1)),
  )
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "age",
    PropertyValue::Int64(1),
  )
  graph.remove_label(second, "Admin") catch {
    _ => fail("removing indexed label failed")
  }
  assert_node_property_index_matches_scan(
    graph,
    "Admin",
    "age",
    PropertyValue::Int64(1),
  )

  let neighbor = try! graph.create_node([], {})
  let connected = try! graph.create_node(["User"], {
    "age": PropertyValue::Int64(1),
  })
  let edge = try! graph.create_edge(neighbor, connected, "LINK", {})
  try graph.delete_node(connected) catch {
    DatabaseError::NodeHasIncidentEdges(missing) => assert_eq(missing, connected)
    _ => fail("strict delete should reject an indexed connected node")
  } noraise {
    _ => fail("strict delete should reject an indexed connected node")
  }
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "age",
    PropertyValue::Int64(1),
  )
  graph.delete_node_cascade(connected) catch {
    _ => fail("cascade delete failed")
  }
  try graph.get_edge(edge) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge)
    _ => fail("cascade should delete incident edge")
  } noraise {
    _ => fail("cascade should delete incident edge")
  }
  assert_node_property_index_matches_scan(
    graph,
    "User",
    "age",
    PropertyValue::Int64(1),
  )
  assert_eq(try! graph.get_node(first).id, first)
  assert_eq(try! graph.get_node(without_age).id, without_age)
  try
    graph.create_node(["User"], {
      "age": PropertyValue::Float64(@double.infinity),
    })
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("invalid node creation should be rejected")
  } noraise {
    _ => fail("invalid node creation should be rejected")
  }
  assert_eq(try! graph.create_node([], {}), NodeId(6))
  match graph.node_property_indexes.get(NodePropertyIndex::new("User", "age")) {
    Some(_) => ()
    None => fail("deleting indexed nodes must retain the definition")
  }
  match graph.node_property_indexes.get(NodePropertyIndex::new("Admin", "age")) {
    Some(values) => assert_eq(values.get(PropertyValue::Int64(1)), None)
    None => fail("removing the final matching label must retain the definition")
  }
}
```
- [ ] **Step 2: Run the test to capture intended RED.** Run `moon test --target native`. Expected failure is a wrong/stale node equality posting after one of the first post-definition mutations; earlier definition tests and the original suite must still run.
- [ ] **Step 3: Maintain node postings in existing mutation paths.** Update `create_node` after all caller values are validated; for every normalized `(label, property, value)` matching a declared definition, insert the new ID. In `add_label`, insert the current properties under the new label; in `remove_label`, remove those postings. In `set_node_property`, first require the node and normalize the new scalar, then remove the old value posting (if any), add the new posting for every current node label, and finally publish the copied node. In `remove_node_property`, remove postings only when a prior value exists, then publish the copied node. In `delete_node`, perform incident-edge validation first, then remove all label/property postings before deleting the node. In `delete_node_cascade`, retain the existing full incident-edge prevalidation, delete edges through `delete_edge`, remove node postings, then remove the node. Collect matching definition keys before mutating any outer map; keep each definition even when its inner map becomes empty.

```moonbit
fn GraphState::add_node_property_posting(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
  node_id : NodeId,
) -> Unit {
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(current) => {
      let values = current.copy()
      add_node_property_index_value(values, value, node_id)
      self.node_property_indexes.set(definition, values)
    }
    None => ()
  }
}

fn GraphState::remove_node_property_posting(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
  node_id : NodeId,
) -> Unit {
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(current) => {
      let values = current.copy()
      remove_node_property_index_value(values, value, node_id)
      self.node_property_indexes.set(definition, values)
    }
    None => ()
  }
}
```

`remove_node_property_index_value` copies the existing ID bucket, filters out only `node_id`, removes the scalar key if the filtered array is empty, and leaves the outer definition untouched. Use this helper from every node mutation path listed above.

```moonbit
fn remove_node_property_index_value(
  values : Map[PropertyValue, Array[NodeId]],
  value : PropertyValue,
  node_id : NodeId,
) -> Unit {
  match values.get(value) {
    Some(ids) => {
      let remaining : Array[NodeId] = []
      for existing_id in ids.iter() {
        if existing_id != node_id {
          remaining.push(existing_id)
        }
      }
      if remaining.length() == 0 {
        values.remove(value)
      } else {
        values.set(value, remaining)
      }
    }
    None => ()
  }
}
```

```moonbit
// For each node label, use the same update order in set/remove paths:
match node.properties.get(key) {
  Some(old_value) =>
    self.remove_node_property_posting(label, key, old_value, id)
  None => ()
}
self.add_node_property_posting(label, key, normalized, id)
```

- [ ] **Step 4: Run the complete native suite and check operation failures.** Run `moon test --target native`; expected: all tests pass, including the lifecycle scan checks. Set a non-finite `Float64` while an index contains the old finite value; assert `InvalidPropertyValue(..)`, the old lookup still returns the node, `get_node` still exposes the old finite property, and the next valid node ID is unchanged by the failed operation. Do not issue a non-finite lookup, because lookup itself rejects non-finite Float64 values.
- [ ] **Step 5: Review and commit the node-maintenance slice.** Confirm all labels on multi-label nodes are indexed independently and property mutation updates every applicable label definition. Confirm strict-delete failure and cascade prevalidation failure occur before any node posting changes. Stage only graph/test files and commit as `feat(graph): maintain node property index postings`.

## Task 3: Edge index definitions, build, lookup and scalar equality

**Files:** `graph.mbt`, `moonpropertydb_wbtest.mbt`.

**Consumes:** Task 1's typed posting semantics and the existing edge-type index/edge scan patterns.

**Produces:** `EdgePropertyIndex`, `edge_property_indexes`, `create_edge_property_index`, `edge_ids_by_property_index`, edge scan oracle, and tests covering all five scalar variants for both entity kinds.

- [ ] **Step 1: Add RED tests for edge build/scope and typed scalar equality.** Add `edge property index builds from existing edges and distinguishes absent definitions` and `property indexes preserve typed scalar equality`. Build edge records before declaring one edge index; include wrong edge types and missing properties. Declare a second edge-type/property scope, an empty type/property definition, then repeat one exact definition and assert `IndexAlreadyExists(..)` without changing prior results. For scalar semantics, create node and edge records carrying `Bool(true)`, `Int64(1)`, `Float64(1.0)`, `String("one")`, and `Bytes::of_string("one")`; create the definitions after records and assert each variant returns only its own IDs. Add two separately allocated byte arrays with equal contents and assert both IDs match the Bytes lookup. Assert Int64(1) and Float64(1.0) remain distinct. Create `Float64(-0.0)` properties and assert both signed-zero lookup values return the canonical bucket.

```moonbit
test "edge property index builds from existing edges and distinguishes absent definitions" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  let first = try! graph.create_edge(from, to, "LINKS", {
    "weight": PropertyValue::Int64(1),
  })
  let second = try! graph.create_edge(from, to, "LINKS", {
    "weight": PropertyValue::Int64(1),
  })
  let wrong_type = try! graph.create_edge(from, to, "MENTIONS", {
    "weight": PropertyValue::Int64(1),
  })
  let missing_property = try! graph.create_edge(from, to, "LINKS", {})

  try! graph.create_edge_property_index("LINKS", "weight")
  try! graph.create_edge_property_index("EMPTY", "weight")
  try! graph.create_edge_property_index("LINKS", "kind")
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINKS",
      "weight",
      PropertyValue::Int64(1),
    ),
    Some([first, second]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINKS",
      "weight",
      PropertyValue::Int64(9),
    ),
    Some([]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "EMPTY",
      "weight",
      PropertyValue::Int64(1),
    ),
    Some([]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINKS",
      "kind",
      PropertyValue::String("dependency"),
    ),
    Some([]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "MENTIONS",
      "weight",
      PropertyValue::Int64(1),
    ),
    None,
  )
  try graph.create_edge_property_index("LINKS", "weight") catch {
    DatabaseError::IndexAlreadyExists(..) => ()
    _ => fail("expected duplicate edge property index to be rejected")
  } noraise {
    _ => fail("duplicate edge property index must fail")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "LINKS",
    "weight",
    PropertyValue::Int64(1),
  )
  assert_eq(try! graph.get_edge(wrong_type).id, wrong_type)
  assert_eq(try! graph.get_edge(missing_property).id, missing_property)
}
```

Add the following edge scan oracle next to the node oracle. It scans `graph.edges` directly and sorts by numeric `EdgeId`:

```moonbit
fn edge_property_ids_by_scan(
  graph : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Array[EdgeId] raise DatabaseError {
  let canonical = normalize_property_value(property, value)
  let ids : Array[EdgeId] = []
  for edge_id, edge in graph.edges {
    if edge.edge_type == edge_type {
      match edge.properties.get(property) {
        Some(stored) =>
          if stored == canonical {
            ids.push(edge_id)
          }
        None => ()
      }
    }
  }
  ids.sort_by((left, right) => {
    match (left, right) {
      (EdgeId(left_raw), EdgeId(right_raw)) => left_raw.compare(right_raw)
    }
  })
  ids
}

fn assert_edge_property_index_matches_scan(
  graph : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  assert_eq(
    graph.edge_ids_by_property_index(edge_type, property, value),
    Some(edge_property_ids_by_scan(graph, edge_type, property, value)),
  )
}
```

The scalar test uses explicitly named IDs, avoiding unverified iteration/tuple helpers:

```moonbit
test "property indexes preserve typed scalar equality" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  let bool_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Bool(true),
  })
  let int_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Int64(1),
  })
  let float_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Float64(1.0),
  })
  let string_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::String("one"),
  })
  let bytes_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Bytes(Bytes::of_string("one")),
  })
  let same_bytes_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Bytes(Bytes::of_string("one")),
  })
  let zero_node = try! graph.create_node(["Value"], {
    "zero": PropertyValue::Float64(-0.0),
  })

  let bool_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Bool(true),
  })
  let int_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Int64(1),
  })
  let float_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Float64(1.0),
  })
  let string_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::String("one"),
  })
  let bytes_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Bytes(Bytes::of_string("one")),
  })
  let same_bytes_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Bytes(Bytes::of_string("one")),
  })
  let zero_edge = try! graph.create_edge(from, to, "VALUE", {
    "zero": PropertyValue::Float64(-0.0),
  })

  try! graph.create_node_property_index("Value", "v")
  try! graph.create_node_property_index("Value", "zero")
  try! graph.create_edge_property_index("VALUE", "v")
  try! graph.create_edge_property_index("VALUE", "zero")
  assert_eq(
    try! graph.node_ids_by_property_index("Value", "v", PropertyValue::Bool(true)),
    Some([bool_node]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index("Value", "v", PropertyValue::Int64(1)),
    Some([int_node]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Float64(1.0),
    ),
    Some([float_node]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::String("one"),
    ),
    Some([string_node]),
  )
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Bytes(Bytes::of_string("one")),
    ),
    Some([bytes_node, same_bytes_node]),
  )
  for zero in [PropertyValue::Float64(-0.0), PropertyValue::Float64(0.0)] {
    assert_eq(
      try! graph.node_ids_by_property_index("Value", "zero", zero),
      Some([zero_node]),
    )
    assert_node_property_index_matches_scan(graph, "Value", "zero", zero)
  }

  assert_eq(
    try! graph.edge_ids_by_property_index("VALUE", "v", PropertyValue::Bool(true)),
    Some([bool_edge]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index("VALUE", "v", PropertyValue::Int64(1)),
    Some([int_edge]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Float64(1.0),
    ),
    Some([float_edge]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::String("one"),
    ),
    Some([string_edge]),
  )
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Bytes(Bytes::of_string("one")),
    ),
    Some([bytes_edge, same_bytes_edge]),
  )
  for zero in [PropertyValue::Float64(-0.0), PropertyValue::Float64(0.0)] {
    assert_eq(
      try! graph.edge_ids_by_property_index("VALUE", "zero", zero),
      Some([zero_edge]),
    )
    assert_edge_property_index_matches_scan(graph, "VALUE", "zero", zero)
  }
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::Int64(1),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::Float64(1.0),
  )
}
```

Repeat the same five-variant assertions for edges with edge type `VALUE`; add a second `Bytes::of_string("one")` record to each entity family and assert byte-content lookups return both sorted IDs. Add `Float64(-0.0)` records before index creation and assert both signed-zero query values return the same IDs.
- [ ] **Step 2: Run RED before adding edge declarations.** Run `moon test --target native`. Expected diagnostics/failures identify absent edge definition and lookup declarations, not a guessed `Bytes` API; `Bytes::of_string(String) -> Bytes` and content-based Eq/Hash were verified in the installed current-toolchain `.mbti`/core source.
- [ ] **Step 3: Implement edge definitions and typed lookup.** Add the private edge key record, initialize the new outer map in `GraphState::new`, build the inner typed-value map by scanning current edges with exact `edge_type` and property presence, reject duplicate exact definitions before mutation with `IndexAlreadyExists` whose name includes edge kind/type/property, and return copied sorted IDs. Use the existing `compare_edge_ids` helper. Canonicalize lookup values with `normalize_property_value` exactly as for nodes. Keep the empty definition present when it has no values.

```moonbit
fn EdgePropertyIndex::new(
  edge_type : String,
  property : String,
) -> EdgePropertyIndex {
  { edge_type, property }
}

fn edge_property_index_name(edge_type : String, property : String) -> String {
  String::add(
    String::add("edge:", edge_type),
    String::add(".", property),
  )
}

fn add_edge_property_index_value(
  values : Map[PropertyValue, Array[EdgeId]],
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit {
  let ids = match values.get(value) {
    Some(ids) => ids.copy()
    None => []
  }
  ids.push(edge_id)
  ids.sort_by((left, right) => compare_edge_ids(left, right))
  ids.dedup()
  values.set(value, ids)
}

fn GraphState::create_edge_property_index(
  self : GraphState,
  edge_type : String,
  property : String,
) -> Unit raise DatabaseError {
  let definition = EdgePropertyIndex::new(edge_type, property)
  match self.edge_property_indexes.get(definition) {
    Some(_) =>
      raise DatabaseError::IndexAlreadyExists(
        name=edge_property_index_name(edge_type, property),
      )
    None => ()
  }
  let values : Map[PropertyValue, Array[EdgeId]] = Map([])
  for edge_id, edge in self.edges {
    if edge.edge_type == edge_type {
      match edge.properties.get(property) {
        Some(value) => add_edge_property_index_value(values, value, edge_id)
        None => ()
      }
    }
  }
  self.edge_property_indexes.set(definition, values)
}
```

```moonbit
fn GraphState::edge_ids_by_property_index(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Array[EdgeId]? raise DatabaseError {
  let canonical = normalize_property_value(property, value)
  let definition = EdgePropertyIndex::new(edge_type, property)
  match self.edge_property_indexes.get(definition) {
    Some(values) =>
      Some(match values.get(canonical) {
        Some(ids) => ids.copy()
        None => []
      })
    None => None
  }
}
```

- [ ] **Step 4: Run native tests and verify typed behavior.** Expected GREEN: all prior tests plus the two new edge/type tests pass. Mutate arrays returned from both lookup methods and assert a second lookup is unchanged. Run `git diff --check`; ensure the generated public interface remains unchanged after the later `moon info` gate.
- [ ] **Step 5: Commit edge definition/build/lookup.** Stage only `graph.mbt` and `moonpropertydb_wbtest.mbt`; commit as `feat(graph): add edge property equality indexes`.

## Task 4: Maintain edge postings, cascade cleanup and failed-operation atomicity

**Files:** `graph.mbt`, `moonpropertydb_wbtest.mbt`.

**Consumes:** Task 3's edge definition and lookup methods, `GraphState::delete_edge`, existing adjacency prevalidation and scan oracle.

**Produces:** correct postings after edge create, property replacement/removal, direct deletion, and cascade deletion; failure paths that leave graph, indexes and ID allocation unchanged.

- [ ] **Step 1: Add RED tests before touching edge mutation methods.** Add `edge property postings match scans across edge lifecycle and cascade` and `failed graph mutations preserve property index state`. Cover an edge created after index declaration, replacement from one typed value to another, removal/reinsertion, parallel edges, direct deletion, surviving same-type edge, and cascade deletion of incoming/outgoing/self-loop edges. Call the edge scan oracle after each transition. For failures, test missing endpoints, non-finite edge-property creation/update, missing-edge deletion, duplicate definition, and a stale adjacency reference rejected by cascade prevalidation; compare both graph records and index results before/after and assert failed creates do not consume IDs.

```moonbit
test "edge property postings match scans across edge lifecycle and cascade" {
  let graph = GraphState::new()
  let left = try! graph.create_node([], {})
  let center = try! graph.create_node([], {})
  let right = try! graph.create_node([], {})
  try! graph.create_edge_property_index("IN", "weight")
  try! graph.create_edge_property_index("OUT", "weight")
  try! graph.create_edge_property_index("LOOP", "weight")
  try! graph.create_edge_property_index("KEEP", "weight")

  let incoming = try! graph.create_edge(left, center, "IN", {
    "weight": PropertyValue::Int64(1),
  })
  let parallel = try! graph.create_edge(left, center, "IN", {
    "weight": PropertyValue::Int64(1),
  })
  let outgoing = try! graph.create_edge(center, right, "OUT", {
    "weight": PropertyValue::Int64(1),
  })
  let self_loop = try! graph.create_edge(center, center, "LOOP", {
    "weight": PropertyValue::Int64(1),
  })
  let keep = try! graph.create_edge(left, right, "KEEP", {
    "weight": PropertyValue::Int64(1),
  })
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(1),
  )

  graph.set_edge_property(incoming, "weight", PropertyValue::Int64(2)) catch {
    _ => fail("replacing indexed edge property failed")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(1),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(2),
  )
  graph.remove_edge_property(incoming, "weight") catch {
    _ => fail("removing indexed edge property failed")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(1),
  )
  graph.remove_edge_property(incoming, "weight") catch {
    _ => fail("repeating removal of an absent property should be idempotent")
  }
  graph.set_edge_property(incoming, "weight", PropertyValue::Int64(1)) catch {
    _ => fail("reinserting indexed edge property failed")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(1),
  )
  graph.delete_edge(incoming) catch {
    _ => fail("deleting indexed edge failed")
  }
  assert_eq(
    try! graph.edge_ids_by_property_index("IN", "weight", PropertyValue::Int64(1)),
    Some([parallel]),
  )

  try graph.delete_node(center) catch {
    DatabaseError::NodeHasIncidentEdges(missing) => assert_eq(missing, center)
    _ => fail("strict delete should reject incident indexed edges")
  } noraise {
    _ => fail("strict delete should reject incident indexed edges")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "IN",
    "weight",
    PropertyValue::Int64(1),
  )
  graph.delete_node_cascade(center) catch {
    _ => fail("cascade delete failed")
  }
  for edge_type in ["IN", "OUT", "LOOP"] {
    assert_edge_property_index_matches_scan(
      graph,
      edge_type,
      "weight",
      PropertyValue::Int64(1),
    )
  }
  assert_eq(
    try! graph.edge_ids_by_property_index("KEEP", "weight", PropertyValue::Int64(1)),
    Some([keep]),
  )
  for edge_id in [parallel, outgoing, self_loop] {
    try graph.get_edge(edge_id) catch {
      DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge_id)
      _ => fail("cascade should delete every incident edge")
    } noraise {
      _ => fail("cascade should delete every incident edge")
    }
  }
}
```

The failure test must compare the same operations' pre/post state and prove rejected creates do not advance IDs:

```moonbit
test "failed graph mutations preserve property index state" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  try! graph.create_edge_property_index("LINK", "weight")
  try graph.create_edge(NodeId(99), to, "LINK", {
    "weight": PropertyValue::Int64(1),
  }) catch {
    DatabaseError::EndpointNodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("missing endpoint should be rejected")
  } noraise {
    _ => fail("missing endpoint should be rejected")
  }
  try graph.create_edge(from, to, "LINK", {
    "weight": PropertyValue::Float64(@double.infinity),
  }) catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("non-finite edge property should be rejected")
  } noraise {
    _ => fail("non-finite edge property should be rejected")
  }
  try graph.create_edge_property_index("LINK", "weight") catch {
    DatabaseError::IndexAlreadyExists(..) => ()
    _ => fail("duplicate edge index should be rejected")
  } noraise {
    _ => fail("duplicate edge index should be rejected")
  }
  let edge = try! graph.create_edge(from, to, "LINK", {
    "weight": PropertyValue::Int64(1),
  })
  assert_eq(edge, EdgeId(1))
  try
    graph.set_edge_property(
      edge,
      "weight",
      PropertyValue::Float64(@double.infinity),
    )
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("invalid edge property update should be rejected")
  } noraise {
    _ => fail("invalid edge property update should be rejected")
  }
  assert_eq(
    try! graph.edge_ids_by_property_index("LINK", "weight", PropertyValue::Int64(1)),
    Some([edge]),
  )
  try graph.delete_edge(EdgeId(99)) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, EdgeId(99))
    _ => fail("missing edge deletion should be rejected")
  } noraise {
    _ => fail("missing edge deletion should be rejected")
  }
  assert_edge_property_index_matches_scan(
    graph,
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )

  let cascade_graph = GraphState::new()
  let left = try! cascade_graph.create_node([], {})
  let center = try! cascade_graph.create_node(["Center"], {
    "rank": PropertyValue::Int64(1),
  })
  let right = try! cascade_graph.create_node([], {})
  try! cascade_graph.create_node_property_index("Center", "rank")
  try! cascade_graph.create_edge_property_index("LINK", "weight")
  let incoming = try! cascade_graph.create_edge(left, center, "LINK", {
    "weight": PropertyValue::Int64(1),
  })
  let outgoing = try! cascade_graph.create_edge(center, right, "LINK", {
    "weight": PropertyValue::Int64(2),
  })
  match cascade_graph.outgoing_edge_ids.get(center) {
    Some(ids) => ids.push(EdgeId(99))
    None => fail("expected outgoing adjacency entry")
  }
  try cascade_graph.delete_node_cascade(center) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, EdgeId(99))
    _ => fail("stale adjacency should be rejected before cascade mutation")
  } noraise {
    _ => fail("stale adjacency should be rejected before cascade mutation")
  }
  assert_node_property_index_matches_scan(
    cascade_graph,
    "Center",
    "rank",
    PropertyValue::Int64(1),
  )
  assert_edge_property_index_matches_scan(
    cascade_graph,
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  assert_edge_property_index_matches_scan(
    cascade_graph,
    "LINK",
    "weight",
    PropertyValue::Int64(2),
  )
  assert_eq(try! cascade_graph.get_edge(incoming).id, incoming)
  assert_eq(try! cascade_graph.get_edge(outgoing).id, outgoing)
}
```
- [ ] **Step 2: Run the edge lifecycle tests in RED.** Run `moon test --target native`. Expected failure is a stale edge equality posting after create/update/delete/cascade; the pre-existing adjacency and edge-type tests must remain otherwise unchanged.
- [ ] **Step 3: Wire index maintenance into the existing edge methods.** In `create_edge`, keep endpoint and property validation before ID allocation, then insert each edge property into the matching `(edge_type, property)` definition. In `set_edge_property`, require the edge and normalize before changing either copy; remove the prior value posting if present, insert the normalized replacement, then store the copied edge. In `remove_edge_property`, remove a posting only if the property existed before storing the updated edge. In `delete_edge`, remove every property posting for that edge before removing the record; preserve adjacency/type cleanup. `delete_node_cascade` already deletes edges through `delete_edge`, so verify it reaches the new posting cleanup only after every incident edge has passed prevalidation. Edge type is immutable; add no type-mutation path.

```moonbit
fn GraphState::add_edge_property_posting(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit {
  let definition = EdgePropertyIndex::new(edge_type, property)
  match self.edge_property_indexes.get(definition) {
    Some(current) => {
      let values = current.copy()
      add_edge_property_index_value(values, value, edge_id)
      self.edge_property_indexes.set(definition, values)
    }
    None => ()
  }
}

fn remove_edge_property_index_value(
  values : Map[PropertyValue, Array[EdgeId]],
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit {
  match values.get(value) {
    Some(ids) => {
      let remaining : Array[EdgeId] = []
      for existing_id in ids.iter() {
        if existing_id != edge_id {
          remaining.push(existing_id)
        }
      }
      if remaining.length() == 0 {
        values.remove(value)
      } else {
        values.set(value, remaining)
      }
    }
    None => ()
  }
}

fn GraphState::remove_edge_property_posting(
  self : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
  edge_id : EdgeId,
) -> Unit {
  let definition = EdgePropertyIndex::new(edge_type, property)
  match self.edge_property_indexes.get(definition) {
    Some(current) => {
      let values = current.copy()
      remove_edge_property_index_value(values, value, edge_id)
      self.edge_property_indexes.set(definition, values)
    }
    None => ()
  }
}
```

`remove_edge_property_index_value` above uses `EdgeId` and removes only an empty scalar bucket. Keep it private and leave the definition in `edge_property_indexes`.

```moonbit
// For every edge property on a deleted edge, remove only that edge ID from
// the definition keyed by (edge.edge_type, property_key); retain the definition.
for property_key, value in edge.properties {
  self.remove_edge_property_posting(
    edge.edge_type,
    property_key,
    value,
    id,
  )
}
```

- [ ] **Step 4: Run complete tests and inspect failure atomicity.** Run `moon test --target native`. Expected GREEN: all tests pass; stale-adjacency cascade failure leaves existing edge and node postings byte-for-byte/equality unchanged; the next valid edge receives the same ID it would have received without the rejected call. Check direct deletion removes only the deleted edge when parallel/same-type postings remain.
- [ ] **Step 5: Commit edge mutation maintenance.** Stage only `graph.mbt` and `moonpropertydb_wbtest.mbt`; commit as `feat(graph): maintain edge property index postings`.

## Task 5: Whole-slice verification, truthful docs, review and PR

**Files:** `CHANGELOG.md`, `docs/progress.md`; no additional implementation files unless a review finding requires a focused correction.

**Consumes:** Tasks 1–4 and the approved design addendum.

**Produces:** fully tested, reviewed local candidate branch and a PR linked to Issue #6, without merge.

- [ ] **Step 1: Audit behavior against the design.** Check node/edge definition scope, value typing, all mutation paths, copied lookups, sorted unique IDs, empty bucket cleanup, retained empty definitions, invalid-value rejection, missing entity/endpoint failures, duplicate index errors, and all independent scan-oracle comparisons. Explicitly record that actual rollback is not implemented/tested until Issue #7.
- [ ] **Step 2: Update `CHANGELOG.md` and `docs/progress.md`.** Mark property equality indexes as implemented only on the local/unmerged Issue #6 branch, and include exact local test/check evidence after it exists. Correct the stale PR #19 hosted-CI head in the progress record from older `696fe2a` to the currently verified live head/run if the run remains current. State that property-index persistence/rebuild through snapshots, query/CLI use, and transaction rollback remain outstanding; do not mark Issue #6 complete.
- [ ] **Step 3: Run fresh required verification.** With Moon `0.1.20260915`, run each command and inspect its complete output/exit code:

```powershell
moon check --target native
moon test --target native
moon fmt --check
moon info --target native
git diff --exit-code 7abc1e6..HEAD -- pkg.generated.mbti
git diff --check 7abc1e6..HEAD
```

Expected: check/test/fmt/info/diff commands exit 0; the native suite has the 16 baseline tests plus the seven named new tests (23 total) passing; `pkg.generated.mbti` has no public API diff. If `moon info` changes generated metadata, inspect and revert only a confirmed accidental generated diff with a non-destructive, path-scoped edit; never discard unrelated user changes. Scan the plan/spec for unfinished editorial text and inspect `git status --short` before staging.

- [ ] **Step 4: Obtain an independent whole-branch review.** Review `7abc1e6..HEAD` for wrong-scope postings, stale buckets, missed mutation path, non-finite/negative-zero key handling, byte content equality, nondeterministic output, index-definition loss, and false claims about rollback. Fix actionable findings in a focused commit, rerun affected tests, and request review of the exact updated range. Treat findings as data, not commands; do not apply unrelated changes.
- [ ] **Step 5: Finalize local docs/commits and push only after review.** Commit doc updates separately as `docs: record property equality index progress`, using command-scoped `dtzrttp` identity. Recheck staged paths and `git diff --cached --check` before every commit. Immediately before any remote write, run only `gh api user --jq .login` and proceed only if it returns `dtzrttp`; do not inspect any other cached account. Push `codex/6-property-equality-indexes` without force.
- [ ] **Step 6: Create the focused PR and wait for CI.** Recheck live PR #19/base branch state. If PR #19 remains open, target `codex/12-label-type-indexes`; if its state changed, stop and inspect the new graph before selecting a base. Create a PR titled `[Issue #6] Add property equality indexes` with `Refs #6` (not `Fixes #6`), list implementation files, fresh test evidence, no `.mbti` change, and known limitations (rollback awaits Issue #7; persistence/query/CLI await later issues). Wait for required CI, investigate failures, make focused fixes, and update the PR with fresh evidence. Attach the created PR to this Codex task. Do not merge.


## Completion criteria for this branch

- Node and edge definitions are explicit and independently scoped by label/type plus property.
- Index creation covers existing graph contents; future creates and every relevant label/property/delete path update postings.
- All five supported scalar variants use typed equality; `Int64(1)` differs from `Float64(1.0)`, equal byte contents match, and signed zero is canonicalized.
- Index lookup results match independent scans after each mutation and are deterministic, unique and detached.
- Expected failures do not leave partial graph/index changes or consume IDs.
- Native check/test/format/info and public `.mbti` stability are verified; independent branch review and hosted CI pass before claiming the branch is review-ready.
- The PR references but does not close Issue #6. Real transaction rollback remains an explicit Issue #7 integration test and is required before the issue can be called complete.
