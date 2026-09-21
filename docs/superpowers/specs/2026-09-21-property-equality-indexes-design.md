# Property Equality Indexes — Issue #6 Design Addendum

**Status:** Proposed implementation design. The v0.1 architecture is approved; this addendum narrows implementation to the in-memory graph layer. No property equality index implementation exists on this branch yet.

## Goal and boundary

Add explicit, private node and edge property equality indexes to `GraphState`. A node index is scoped by `(label, property key)`; an edge index is scoped by `(edge type, property key)`. Each lookup is for one exact typed scalar value and returns matching IDs in ascending numeric order. Index definitions and contents are private derived in-memory state; no public API, query, CLI, WAL, snapshot, or persistence behavior is added here.

Issue #6 also asks that indexes remain unchanged after transaction rollback. The transaction state machine is Issue #7 and does not exist on this base. This branch will cover operation-level failure atomicity and index consistency across all graph mutations, but will not claim or close Issue #6. A later Issue #7 integration must test rollback with node and edge property indexes before Issue #6 is considered complete. The PR for this slice should reference (`Refs #6`) rather than close the issue.

## Representation alternatives

1. **Nested typed maps per definition (recommended):** map `(label, property)` or `(edge type, property)` to a `PropertyValue`-to-sorted-ID map. This keeps definitions distinct from value buckets, uses the existing typed `Eq`/`Hash` model, makes duplicate detection direct, and lets a declared definition exist with no values.
2. **One flat composite key map:** key every posting by entity scope, property key, and scalar value. This reduces one level of map nesting, but definition existence must be tracked separately and index creation, deletion, and rebuild have more cross-map bookkeeping.
3. **Scan-only lookup:** avoid maintained buckets and filter primary graph records on every lookup. This is simpler but is not an equality index and does not satisfy the project's explicit index-maintenance requirement.

Choose the nested representation for clarity and testability. It is consistent with the existing label/type inverted-index design and adds no dependency or public surface.

## Data representation

Keep property indexes in the existing graph package and do not add dependencies. Define private, hashable index-definition keys:

```moonbit
priv struct NodePropertyIndex {
  label : String
  property : String
} derive(Eq, Hash)

priv struct EdgePropertyIndex {
  edge_type : String
  property : String
} derive(Eq, Hash)
```

Store each definition with its own value-to-ID buckets, including an empty inner map when the definition matches no current entity:

```moonbit
node_property_indexes : Map[NodePropertyIndex, Map[PropertyValue, Array[NodeId]]]
edge_property_indexes : Map[EdgePropertyIndex, Map[PropertyValue, Array[EdgeId]]]
```

`PropertyValue` already derives `Eq` and `Hash`; its enum tag keeps `Int64(1)` distinct from `Float64(1.0)`. Graph write boundaries already reject non-finite floats and normalize negative zero, so values used as index keys are canonical. Bytes equality is by byte contents. ID buckets are unique and sorted with the existing numeric ID comparators. Lookups return copies. Empty value buckets are removed, but the outer definition remains until a future explicit drop operation (not in this scope).

An internal lookup distinguishes an undeclared definition from a declared index with no matching value, so a future planner can fall back to a scan only for the former. Duplicate creation uses the existing structured `DatabaseError::IndexAlreadyExists`; names include the entity kind, scope and property key. No new public error or API is introduced.

## Maintenance rules

- Creating a node or edge inserts its current property values into every matching declared definition.
- Creating a node index scans existing nodes with the requested label; creating an edge index scans existing edges of the requested type. Missing properties create no value bucket.
- Adding/removing a node label adds/removes that node's current properties from definitions scoped to that label.
- Setting a property removes the old typed value posting, if present, and adds the normalized new value posting for every applicable definition. Removing an absent property is a no-op; removing a present property removes its posting.
- Deleting a node or edge removes all of its property postings. Cascade deletion continues through the existing edge deletion path.
- Edge type is immutable, so no edge-type mutation path is added.
- Validate entity existence, duplicate definitions, and property values before mutating graph/index state. A rejected graph operation leaves all indexes and ID allocation unchanged, matching existing graph guarantees.
- To avoid mutating an outer map during iteration, first collect applicable definition keys, then update their inner maps.

Every bucket must match a deterministic scan of primary graph state after each operation. Index creation is explicit; the indexes are not silently created by a lookup.

## Test plan

Use whitebox tests in `moonpropertydb_wbtest.mbt` with independent scan oracles for nodes and edges. Cover:

1. Building node and edge indexes over existing data, including absent properties and nonmatching labels/types; empty definitions remain present.
2. Duplicate definition errors and distinct definitions for different labels, edge types, and property keys.
3. Exact typed equality for Bool, Int64, finite Float64, String, and Bytes; no numeric coercion; byte arrays with equal contents match; negative zero is normalized.
4. Sorted unique copied ID results and missing-value behavior.
5. Membership updates on node/edge create, property replacement/removal/reinsertion, label add/remove, strict node/edge deletion, and node cascade deletion.
6. Index results matching scans after every transition, including properties changed before and after an index is created.
7. Missing-entity, invalid-float, and duplicate-index failures leave primary data, index definitions, buckets, and next IDs unchanged.

Real transaction rollback is intentionally reserved for Issue #7; a clone/discard simulation is not accepted as proof of transaction rollback.

## Verification and delivery

Run `moon test --target native` first for each RED/GREEN slice, then `moon check --target native`, `moon test --target native`, `moon fmt --check`, and `moon info --target native`. Verify the generated public `.mbti` remains unchanged. `moon ide doc` is still unavailable due to missing backend metadata; use the maintainer-authorized current-toolchain `.mbti` plus compiler/tests fallback and report the failure honestly. No external dependencies are expected.

The feature branch is stacked on `codex/12-label-type-indexes` while PR #19 remains open. Keep this slice isolated in its own worktree/branch and PR. State clearly that transaction rollback integration is outstanding; do not use `Fixes #6` until Issue #7 tests prove the rollback acceptance.
