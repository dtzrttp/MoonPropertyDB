# Node-Label and Edge-Type Indexes — Issue #12 Design Addendum

**Status:** Focused design addendum for maintainer review. On 2026-09-21 the maintainer confirmed the proposed sorted-ID-array representation by saying “继续”. This written addendum remains a gate: implementation and its detailed plan wait for review of this document.

## Goal and scope

Complete the missing part of Issue #12 by maintaining node-label and edge-type inverted indexes in the existing private `GraphState`. The current graph store already maintains incoming- and outgoing-edge adjacency indexes; this change must preserve them and does not redesign them.

The indexes are derived in-memory state. They support deterministic label/type lookups and later query planning, but do not change the public `Database` API or make any persistence, transaction, query, or CLI capability part of this issue.

## Data structures and invariants

Add two private fields to `GraphState`:

- `node_ids_by_label : Map[String, Array[NodeId]]`
- `edge_ids_by_type : Map[String, Array[EdgeId]]`

Each map is an inverted index. A bucket contains IDs, not graph records. IDs in every bucket are unique and strictly ascending by their wrapped unsigned numeric value. Empty buckets are absent. A lookup for a missing key returns an empty array. Lookup results are detached copies so caller mutation cannot alter index state.

The graph/index consistency invariants are:

1. A node ID occurs in the bucket for each and only each label on that node.
2. An edge ID occurs in the bucket for exactly its stored edge type.
3. No bucket contains a duplicate or an ID absent from the primary node/edge map.
4. Every bucket remains numerically ordered; this must also hold if a lower existing node ID regains a label after a higher ID is already in that bucket.
5. Deleting the last member removes the bucket.
6. Existing adjacency maps and their behavior remain unchanged.

Node labels are already canonicalized as unique values by `GraphState`; index helpers must nevertheless be idempotent so repeated add/remove calls cannot create duplicate IDs or false failures. Edge type is immutable in the current model.

## Lookup behavior

Add private `GraphState` lookups with these conceptual signatures:

```text
node_ids_with_label(label : String) -> Array[NodeId]
edge_ids_with_type(edge_type : String) -> Array[EdgeId]
```

They return IDs in ascending numeric order, return `[]` for an absent key, and return copies. They do not expose the maps, bucket arrays, or any new public type. The exact MoonBit declaration style follows the existing `GraphState` methods.

## Mutation integration

| Graph mutation | Node-label index | Edge-type index | Existing adjacency |
|---|---|---|---|
| Create node | Add its ID once to every canonical label bucket | No change | No change |
| Add label | Insert only when the label is newly present | No change | No change |
| Remove label | Remove that node ID; remove an emptied bucket | No change | No change |
| Set/remove node property | No change | No change | No change |
| Strict node delete | After incident-edge validation, remove the node ID from all of its label buckets | No change | Keep the existing validated cleanup behavior |
| Cascade node delete | Remove labels for the node as part of deletion | Incident edges are removed through the existing `delete_edge` path | Continue to use the existing adjacency-maintaining edge deletion path |
| Create edge | No change | Add its ID to the bucket for its immutable type | Keep current in/out insertion behavior |
| Set/remove edge property | No change | No change | No change |
| Delete edge | No change | Remove its ID; remove an emptied bucket | Keep current in/out cleanup behavior |

Perform caller-data, endpoint, node-existence, and incident-edge validations before changing the affected primary record or secondary index. Existing operations that reject an input must leave the primary graph and both new index maps unchanged. Index maintenance is synchronous with the existing graph mutation; there is no separate post-commit index update.

## Deterministic ordering

Do not rely on `Map` iteration order for lookup output. Maintain each bucket in numeric ID order, including insertion of a smaller ID into a bucket that already contains larger IDs. Removal preserves the order of remaining entries. This ordering is independent of the string ordering used for labels and independent of physical map iteration.

## Tests and evidence

Add whitebox tests in `moonpropertydb_wbtest.mbt` because `GraphState` and its index maps are private. Tests use the primary `nodes` and `edges` maps to build a scan oracle, explicitly sort oracle IDs numerically, and compare the indexed lookup with the scan after each meaningful mutation.

Coverage must include:

- Multiple labels on a node, duplicate labels at creation, two nodes sharing a label, missing-key lookup, duplicate label addition, absent-label removal, actual removal, and re-adding a lower ID after a higher ID is already indexed.
- Multiple edge types, parallel edges of one type, missing-type lookup, property changes that leave the type index unchanged, edge deletion, and deletion of the last member of a type bucket.
- Strict node deletion of an unconnected indexed node and cascade deletion of an indexed node with incoming, outgoing, parallel, and self-loop edges; verify both label and edge-type buckets after cleanup.
- Failed changes leave both the indexes and allocation state consistent: adding/removing a label on a missing node, deleting a missing edge, strict deletion of a node with incident edges, invalid non-finite properties during node/edge creation, and edge creation with a missing endpoint must not partially add/remove index entries. After invalid creation, the next valid allocation still gets the expected first ID.
- Returned ID arrays are detached: mutating one lookup result does not affect a later lookup.
- Repeated indexed lookup produces the same ordered ID array, and all tested index results match their scan oracle after create, update, and delete sequences.

The implementation phase must first add a failing behavior test, run it to confirm the missing index behavior is the cause, implement the smallest change, and rerun the full native test suite. Then run `moon check --target native`, `moon fmt --check`, `moon info --target native`, and `git diff --check`; inspect the generated `.mbti` to confirm the new GraphState details did not leak into the public API.

`moon ide doc` currently fails with `Fail to load core: no metadata is available for any backend` on the installed toolchain. The maintainer has authorized use of the installed toolchain's generated `.mbti` plus compiler checks/tests as the fallback. Record the `moon ide doc` failure honestly; do not report it as a successful API lookup.

## Explicit exclusions and follow-up boundaries

- User-declared property equality indexes (Issue #6), index persistence, WAL/snapshot encoding, transaction cloning/rollback, and recovery rebuilding are not implemented here. The approved v0.1 design treats these indexes as derived state; transaction/recovery issues must deep-copy or rebuild their buckets so candidate mutations cannot leak into committed state.
- Query-planner consumption of these lookups belongs to the query issues.
- No public `Database`/transaction API, CLI command, new dependency, range/compound/full-text/vector index, or adjacency redesign is part of this slice.
- No new performance claim is made. Bucket insertion may shift array elements; this simple representation is chosen for deterministic results and modest v0.1 scope. Revisit only with measured workload evidence.
