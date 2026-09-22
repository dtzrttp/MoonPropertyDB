// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "wal codec uses crc32 iso hdlc and little endian fields" {
  assert_eq(wal_crc32(b"123456789"), 3421780262UL)
  assert_eq(wal_u16_bytes(0x1234UL), b"\x34\x12")
  assert_eq(wal_u32_bytes(0x78563412UL), b"\x12\x34\x56\x78")
}

///|
test "graph candidate copy detaches graph and every index collection" {
  let original = GraphState::new()
  let first = try! original.create_node(["User"], {
    "name": PropertyValue::String("A"),
  })
  let second = try! original.create_node(["User"], {
    "name": PropertyValue::String("B"),
  })
  let edge = try! original.create_edge(first, second, "KNOWS", {
    "weight": PropertyValue::Int64(1),
  })
  try! original.create_node_property_index("User", "name")
  try! original.create_edge_property_index("KNOWS", "weight")
  let copy = original.copy_detached()
  assert_eq(try! copy.create_node([], {}), NodeId(3))
  assert_eq(try! copy.create_edge(first, second, "KNOWS", {}), EdgeId(2))
  match copy.nodes.get(first) {
    Some(node) => {
      node.labels.push("Changed")
      node.properties.set("name", PropertyValue::String("copy"))
    }
    None => fail("expected copied node")
  }
  match copy.edges.get(edge) {
    Some(copied_edge) =>
      copied_edge.properties.set("weight", PropertyValue::Int64(2))
    None => fail("expected copied edge")
  }
  match copy.node_ids_by_label.get("User") {
    Some(ids) => ids.push(NodeId(99))
    None => fail("expected copied label posting")
  }
  match copy.edge_ids_by_type.get("KNOWS") {
    Some(ids) => ids.push(EdgeId(99))
    None => fail("expected copied type posting")
  }
  match copy.node_property_indexes.get(NodePropertyIndex::new("User", "name")) {
    Some(values) =>
      match values.get(PropertyValue::String("A")) {
        Some(ids) => ids.push(NodeId(99))
        None => fail("expected copied node property bucket")
      }
    None => fail("expected copied node property index")
  }
  match
    copy.edge_property_indexes.get(EdgePropertyIndex::new("KNOWS", "weight")) {
    Some(values) =>
      match values.get(PropertyValue::Int64(1)) {
        Some(ids) => ids.push(EdgeId(99))
        None => fail("expected copied edge property bucket")
      }
    None => fail("expected copied edge property index")
  }
  match copy.outgoing_edge_ids.get(first) {
    Some(ids) => ids.push(EdgeId(99))
    None => fail("expected copied outgoing adjacency")
  }
  match copy.incoming_edge_ids.get(second) {
    Some(ids) => ids.push(EdgeId(99))
    None => fail("expected copied incoming adjacency")
  }
  copy.set_node_property(first, "name", PropertyValue::String("changed"))
  copy.delete_edge(edge)
  assert_eq(
    (try! original.get_node(first)).properties.get("name"),
    Some(PropertyValue::String("A")),
  )
  assert_eq((try! original.get_node(first)).labels, ["User"])
  assert_eq(
    try! original.get_edge(edge),
    Edge::Edge(id=edge, from=first, to=second, edge_type="KNOWS", properties={
      "weight": PropertyValue::Int64(1),
    }),
  )
  assert_eq((try! original.outgoing_edges(first)).length(), 1)
  assert_eq((try! original.incoming_edges(second)).length(), 1)
  assert_eq(original.node_ids_with_label("User"), [first, second])
  assert_eq(original.edge_ids_with_type("KNOWS"), [edge])
  assert_eq(
    try! original.node_ids_by_property_index(
      "User",
      "name",
      PropertyValue::String("A"),
    ),
    Some([first]),
  )
  assert_eq(
    try! original.edge_ids_by_property_index(
      "KNOWS",
      "weight",
      PropertyValue::Int64(1),
    ),
    Some([edge]),
  )
  assert_eq(try! original.create_node([], {}), NodeId(3))
  assert_eq(try! original.create_edge(first, second, "KNOWS", {}), EdgeId(2))
}

///|
test "staged data is invisible and only one writer is active" {
  let database = Database::new_in_memory()
  let transaction = try! database.begin_write()
  let staged_node = try! transaction.candidate.create_node(["Staged"], {})
  try database.get_node(staged_node) catch {
    DatabaseError::NodeNotFound(id) => assert_eq(id, staged_node)
    _ => fail("committed reads must not inspect the transaction candidate")
  } noraise {
    _ => fail("staged node read must return a structured error")
  }
  let shared_database = database
  try shared_database.begin_write() catch {
    DatabaseError::WriterTransactionActive => ()
    _ => fail("a second writer must be rejected while the first is active")
  } noraise {
    _ => fail("second writer rejection must return a structured error")
  }
}

///|
fn assert_graph_state_equal(
  expected : GraphState,
  actual : GraphState,
) -> Unit raise {
  assert_true(actual.nodes == expected.nodes)
  assert_true(actual.edges == expected.edges)
  assert_true(actual.node_ids_by_label == expected.node_ids_by_label)
  assert_true(actual.node_property_indexes == expected.node_property_indexes)
  assert_true(actual.edge_ids_by_type == expected.edge_ids_by_type)
  assert_true(actual.edge_property_indexes == expected.edge_property_indexes)
  assert_true(actual.outgoing_edge_ids == expected.outgoing_edge_ids)
  assert_true(actual.incoming_edge_ids == expected.incoming_edge_ids)
  assert_true(actual.next_node_id == expected.next_node_id)
  assert_true(actual.next_edge_id == expected.next_edge_id)
}

///|
fn assert_transaction_failed(transaction : WriteTransaction) -> Unit raise {
  match transaction.status.val {
    Failed => ()
    _ => fail("the graph error must poison the shared transaction status")
  }
}

///|
test "failed write poisons transaction without partial candidate mutation" {
  let non_finite_database = Database::new_in_memory()
  let non_finite = try! non_finite_database.begin_write()
  let non_finite_node = try! non_finite.create_node(["User"], {
    "age": PropertyValue::Int64(1),
  })
  try! non_finite.create_node_property_index("User", "age")
  let non_finite_before = non_finite.candidate.copy_detached()
  try
    non_finite.set_node_property(
      non_finite_node,
      "age",
      PropertyValue::Float64(@double.infinity),
    )
  catch {
    DatabaseError::InvalidPropertyValue(
      property="age",
      reason="Float64 properties must be finite"
    ) => ()
    _ => fail("non-finite node property update must re-raise its graph error")
  } noraise {
    _ => fail("non-finite node property update must raise")
  }
  assert_graph_state_equal(non_finite_before, non_finite.candidate)
  assert_transaction_failed(non_finite)

  let missing_endpoint_database = Database::new_in_memory()
  let missing_endpoint = try! missing_endpoint_database.begin_write()
  let source = try! missing_endpoint.create_node([], {})
  let missing_endpoint_before = missing_endpoint.candidate.copy_detached()
  try missing_endpoint.create_edge(source, NodeId(99), "MISSING", {}) catch {
    DatabaseError::EndpointNodeNotFound(id) => assert_eq(id, NodeId(99))
    _ => fail("missing edge endpoint must re-raise its graph error")
  } noraise {
    _ => fail("missing edge endpoint must raise")
  }
  assert_graph_state_equal(missing_endpoint_before, missing_endpoint.candidate)
  assert_transaction_failed(missing_endpoint)

  let duplicate_index_database = Database::new_in_memory()
  let duplicate_index = try! duplicate_index_database.begin_write()
  let _indexed_node = try! duplicate_index.create_node(["User"], {
    "name": PropertyValue::String("Alice"),
  })
  try! duplicate_index.create_node_property_index("User", "name")
  let duplicate_index_before = duplicate_index.candidate.copy_detached()
  try duplicate_index.create_node_property_index("User", "name") catch {
    DatabaseError::IndexAlreadyExists(name="node:User.name") => ()
    _ => fail("duplicate node index must re-raise its graph error")
  } noraise {
    _ => fail("duplicate node index must raise")
  }
  assert_graph_state_equal(duplicate_index_before, duplicate_index.candidate)
  assert_transaction_failed(duplicate_index)

  let strict_delete_database = Database::new_in_memory()
  let strict_delete = try! strict_delete_database.begin_write()
  let connected = try! strict_delete.create_node(["Center"], {})
  let other = try! strict_delete.create_node([], {})
  let connected_edge = try! strict_delete.create_edge(
    connected,
    other,
    "LINK",
    {},
  )
  let strict_delete_before = strict_delete.candidate.copy_detached()
  try strict_delete.delete_node(connected) catch {
    DatabaseError::NodeHasIncidentEdges(id) => assert_eq(id, connected)
    _ => fail("strict deletion must re-raise the incident-edge error")
  } noraise {
    _ => fail("strict deletion must raise for a connected node")
  }
  assert_graph_state_equal(strict_delete_before, strict_delete.candidate)
  assert_eq(
    try! strict_delete.candidate.get_edge(connected_edge),
    try! strict_delete.candidate.get_edge(connected_edge),
  )
  assert_transaction_failed(strict_delete)

  let stale_database = Database::new_in_memory()
  let stale = try! stale_database.begin_write()
  let stale_node = try! stale.create_node([], {})
  let stale_other = try! stale.create_node([], {})
  let stale_edge = try! stale.create_edge(stale_node, stale_other, "STALE", {})
  match stale.candidate.outgoing_edge_ids.get(stale_node) {
    Some(ids) => ids.push(EdgeId(99))
    None => fail("expected the source adjacency entry")
  }
  let stale_before = stale.candidate.copy_detached()
  try stale.delete_node_cascade(stale_node) catch {
    DatabaseError::EdgeNotFound(id) => assert_eq(id, EdgeId(99))
    _ => fail("stale cascade adjacency must re-raise its graph error")
  } noraise {
    _ => fail("stale cascade adjacency must raise")
  }
  assert_graph_state_equal(stale_before, stale.candidate)
  assert_eq(
    try! stale.candidate.get_edge(stale_edge),
    try! stale.candidate.get_edge(stale_edge),
  )
  assert_transaction_failed(stale)
}

///|
test "terminal transaction states release the writer slot" {
  let database = Database::new_in_memory()
  let committed = try! database.begin_write()
  let committed_node = try! committed.create_node(["User"], {
    "name": PropertyValue::String("Alice"),
  })
  try! committed.create_node_property_index("User", "name")
  try! committed.commit()
  assert_eq(
    try! database.state.val.committed.node_ids_by_property_index(
      "User",
      "name",
      PropertyValue::String("Alice"),
    ),
    Some([committed_node]),
  )
  match committed.status.val {
    Committed => ()
    _ => fail("commit must mark the shared transaction status")
  }
  match database.state.val.active {
    None => ()
    Some(_) => fail("commit must release the database writer slot")
  }

  let rolled_back = try! database.begin_write()
  let _ = try! rolled_back.create_node([], {})
  try! rolled_back.rollback()
  match rolled_back.status.val {
    RolledBack => ()
    _ => fail("rollback must mark the shared transaction status")
  }
  match database.state.val.active {
    None => ()
    Some(_) => fail("rollback must release the database writer slot")
  }

  let failed = try! database.begin_write()
  try failed.get_node(NodeId(99)) catch {
    DatabaseError::NodeNotFound(id) => assert_eq(id, NodeId(99))
    _ => fail("missing candidate reads must preserve their graph error")
  } noraise {
    _ => fail("missing candidate reads must raise")
  }
  match failed.status.val {
    Failed => ()
    _ => fail("failed operations must poison the shared status")
  }
  try! failed.rollback()
  match failed.status.val {
    RolledBack => ()
    _ => fail("rollback must recover a failed transaction")
  }
}

///|
test "closing a database rolls back its active transaction" {
  let database = Database::new_in_memory()
  let transaction = try! database.begin_write()
  let node = try! transaction.create_node([], {})
  try! database.close()
  match transaction.status.val {
    RolledBack => ()
    _ => fail("closing must roll back its active transaction")
  }
  match database.state.val.active {
    None => ()
    Some(_) => fail("closing must clear the active writer slot")
  }
  if database.state.val.closed != true {
    fail("closing must mark the database closed")
  }
  try database.get_node(node) catch {
    DatabaseError::DatabaseClosed => ()
    _ => fail("closed databases must reject reads")
  } noraise {
    _ => fail("closed databases must reject reads")
  }
}

///|
test "database committed reads return detached node and edge values" {
  let database = Database::new_in_memory()
  let node_id = try! database.state.val.committed.create_node(["User"], {
    "name": PropertyValue::String("Alice"),
  })
  let other_id = try! database.state.val.committed.create_node([], {})
  let edge_id = try! database.state.val.committed.create_edge(
    node_id,
    other_id,
    "KNOWS",
    { "weight": PropertyValue::Int64(1) },
  )
  let node = try! database.get_node(node_id)
  node.labels.push("Mutated")
  node.properties.set("name", PropertyValue::String("Mallory"))
  let edge = try! database.get_edge(edge_id)
  edge.properties.set("weight", PropertyValue::Int64(2))
  assert_eq(
    try! database.get_node(node_id),
    Node::Node(id=node_id, labels=["User"], properties={
      "name": PropertyValue::String("Alice"),
    }),
  )
  assert_eq(
    try! database.get_edge(edge_id),
    Edge::Edge(id=edge_id, from=node_id, to=other_id, edge_type="KNOWS", properties={
      "weight": PropertyValue::Int64(1),
    }),
  )
}

///|
test "graph state creates nodes with monotonic ids and isolated values" {
  let graph = GraphState::new()
  let invalid_values = [
    @double.not_a_number, @double.infinity, @double.neg_infinity,
  ]
  for invalid in invalid_values.iter() {
    try
      graph.create_node([], { "score": PropertyValue::Float64(invalid) })
    catch {
      DatabaseError::InvalidPropertyValue(..) => ()
      _ => fail("expected a structured invalid-property error")
    } noraise {
      _ => fail("database state must reject non-finite floats")
    }
  }

  let labels = ["User", "Developer", "User"]
  let properties : Properties = {
    "name": PropertyValue::String("Alice"),
    "zero": PropertyValue::Float64(-0.0),
  }
  let id = try! graph.create_node(labels, properties)
  assert_eq(id, NodeId(1))

  labels.push("LateMutation")
  properties.set("name", PropertyValue::String("Mallory"))
  let first_read = try! graph.get_node(id)
  assert_eq(first_read.labels, ["User", "Developer"])
  assert_eq(first_read.properties, {
    "name": PropertyValue::String("Alice"),
    "zero": PropertyValue::Float64(0.0),
  })
  match first_read.properties.get("zero") {
    Some(PropertyValue::Float64(value)) =>
      assert_eq(value.reinterpret_as_int64(), 0)
    _ => fail("expected normalized Float64 zero")
  }

  first_read.labels.push("ReadMutation")
  first_read.properties.set("name", PropertyValue::String("Eve"))
  let second_read = try! graph.get_node(id)
  assert_eq(second_read.labels, ["User", "Developer"])
  assert_eq(second_read.properties, {
    "name": PropertyValue::String("Alice"),
    "zero": PropertyValue::Float64(0.0),
  })

  let next_id = try! graph.create_node([], {})
  assert_eq(next_id, NodeId(2))

  let exhausted = GraphState::new()
  exhausted.next_node_id = Some(18446744073709551615UL)
  let final_id = try! exhausted.create_node([], {})
  assert_eq(final_id, NodeId(18446744073709551615UL))
  try exhausted.create_node([], {}) catch {
    DatabaseError::NodeIdExhausted => ()
    _ => fail("expected a structured node-ID exhaustion error")
  } noraise {
    _ => fail("node ID allocation must not wrap after the maximum UInt64")
  }
}

///|
test "graph state updates node labels and properties idempotently" {
  let graph = GraphState::new()
  let id = try! graph.create_node(["User"], {})
  graph.add_label(id, "User") catch {
    _ => fail("adding a label failed")
  }
  graph.add_label(id, "Admin") catch {
    _ => fail("adding a label failed")
  }
  graph.add_label(id, "Admin") catch {
    _ => fail("adding a label failed")
  }
  graph.remove_label(id, "Missing") catch {
    _ => fail("removing a label failed")
  }
  graph.set_node_property(id, "age", PropertyValue::Int64(28)) catch {
    _ => fail("setting a node property failed")
  }
  graph.set_node_property(id, "age", PropertyValue::Int64(29)) catch {
    _ => fail("replacing a node property failed")
  }
  for
    invalid in [@double.not_a_number, @double.infinity, @double.neg_infinity].iter() {
    try
      graph.set_node_property(id, "age", PropertyValue::Float64(invalid))
    catch {
      DatabaseError::InvalidPropertyValue(..) => ()
      _ => fail("expected a structured invalid-property error")
    } noraise {
      _ => fail("database state must reject non-finite floats")
    }
  }

  let updated = try! graph.get_node(id)
  assert_eq(updated.labels, ["User", "Admin"])
  assert_eq(updated.properties, { "age": PropertyValue::Int64(29) })

  graph.remove_node_property(id, "age") catch {
    _ => fail("removing a node property failed")
  }
  graph.remove_node_property(id, "age") catch {
    _ => fail("removing an absent property should be idempotent")
  }
  graph.remove_label(id, "Admin") catch {
    _ => fail("removing a label failed")
  }
  graph.remove_label(id, "Admin") catch {
    _ => fail("repeating label removal should be idempotent")
  }
  let cleaned = try! graph.get_node(id)
  assert_eq(cleaned.labels, ["User"])
  assert_eq(cleaned.properties, {})

  try graph.get_node(NodeId(99)) catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected a structured NodeNotFound error")
  } noraise {
    _ => fail("expected get_node to reject a missing ID")
  }
  try graph.add_label(NodeId(99), "Missing") catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected a missing-node mutation to report NodeNotFound")
  } noraise {
    _ => fail("expected add_label to reject a missing node")
  }
}

///|
fn node_label_ids_by_scan(graph : GraphState, label : String) -> Array[NodeId] {
  let ids : Array[NodeId] = []
  for node_id, node in graph.nodes {
    let mut matched = false
    for node_label in node.labels.iter() {
      if node_label == label {
        matched = true
      }
    }
    if matched {
      ids.push(node_id)
    }
  }
  ids.sort_by((left, right) => {
    match (left, right) {
      (NodeId(left_raw), NodeId(right_raw)) => left_raw.compare(right_raw)
    }
  })
  ids
}

///|
fn assert_node_label_index_matches_scan(
  graph : GraphState,
  label : String,
) -> Unit raise {
  assert_eq(
    graph.node_ids_with_label(label),
    node_label_ids_by_scan(graph, label),
  )
}

///|
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
        Some(stored) => if stored == canonical { ids.push(node_id) }
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

///|
fn assert_node_property_index_matches_scan(
  graph : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Unit raise {
  assert_eq(
    graph.node_ids_by_property_index(label, property, value),
    Some(node_property_ids_by_scan(graph, label, property, value)),
  )
}

///|
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
        Some(stored) => if stored == canonical { ids.push(edge_id) }
        None => ()
      }
    }
  }
  ids.sort_by((left, right) => compare_edge_ids(left, right))
  ids
}

///|
fn assert_edge_property_index_matches_scan(
  graph : GraphState,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Unit raise {
  assert_eq(
    graph.edge_ids_by_property_index(edge_type, property, value),
    Some(edge_property_ids_by_scan(graph, edge_type, property, value)),
  )
}

///|
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
    DatabaseError::NodeHasIncidentEdges(missing) =>
      assert_eq(missing, connected)
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
  match
    graph.node_property_indexes.get(NodePropertyIndex::new("Admin", "age")) {
    Some(values) => assert_eq(values.get(PropertyValue::Int64(1)), None)
    None => fail("removing the final matching label must retain the definition")
  }
}

///|
fn edge_type_ids_by_scan(
  graph : GraphState,
  edge_type : String,
) -> Array[EdgeId] {
  let ids : Array[EdgeId] = []
  for edge_id, edge in graph.edges {
    if edge.edge_type == edge_type {
      ids.push(edge_id)
    }
  }
  ids.sort_by((left, right) => {
    match (left, right) {
      (EdgeId(left_raw), EdgeId(right_raw)) => left_raw.compare(right_raw)
    }
  })
  ids
}

///|
fn assert_edge_type_index_matches_scan(
  graph : GraphState,
  edge_type : String,
) -> Unit raise {
  assert_eq(
    graph.edge_ids_with_type(edge_type),
    edge_type_ids_by_scan(graph, edge_type),
  )
}

///|
fn edge_ids(edges : Array[Edge]) -> Array[EdgeId] {
  let ids : Array[EdgeId] = []
  for edge in edges.iter() {
    ids.push(edge.id)
  }
  ids
}

///|
test "graph state stores directed edges and deterministic adjacency" {
  let graph = GraphState::new()
  let alice = try! graph.create_node(["User"], {})
  let bob = try! graph.create_node(["User"], {})
  let carol = try! graph.create_node(["User"], {})
  let follows = try! graph.create_edge(alice, bob, "FOLLOWS", {
    "since": PropertyValue::Int64(2025),
  })
  let parallel = try! graph.create_edge(alice, bob, "FOLLOWS", {})
  let self_loop = try! graph.create_edge(alice, alice, "SELF", {})
  let next = try! graph.create_edge(bob, carol, "FOLLOWS", {})

  assert_eq(follows, EdgeId(1))
  assert_eq(parallel, EdgeId(2))
  assert_eq(self_loop, EdgeId(3))
  assert_eq(next, EdgeId(4))
  assert_eq(
    try! graph.get_edge(follows),
    Edge::Edge(id=follows, from=alice, to=bob, edge_type="FOLLOWS", properties={
      "since": PropertyValue::Int64(2025),
    }),
  )
  assert_eq(edge_ids(try! graph.outgoing_edges(alice)), [
    follows, parallel, self_loop,
  ])
  assert_eq(edge_ids(try! graph.incoming_edges(alice)), [self_loop])
  assert_eq(edge_ids(try! graph.incoming_edges(bob)), [follows, parallel])
  assert_eq(edge_ids(try! graph.outgoing_edges(bob)), [next])
  assert_eq(edge_ids(try! graph.incoming_edges(carol)), [next])
  assert_eq(edge_ids(try! graph.outgoing_edges(carol)), [])

  let detached = try! graph.outgoing_edges(alice)
  detached.push(try! graph.get_edge(next))
  assert_eq(edge_ids(try! graph.outgoing_edges(alice)), [
    follows, parallel, self_loop,
  ])
}

///|
test "graph state rejects missing edge endpoints without consuming ids" {
  let graph = GraphState::new()
  let node = try! graph.create_node([], {})

  try graph.create_edge(NodeId(99), node, "LINK", {}) catch {
    DatabaseError::EndpointNodeNotFound(missing) =>
      assert_eq(missing, NodeId(99))
    _ => fail("expected a structured missing-source error")
  } noraise {
    _ => fail("expected missing source node to be rejected")
  }
  try graph.create_edge(node, NodeId(100), "LINK", {}) catch {
    DatabaseError::EndpointNodeNotFound(missing) =>
      assert_eq(missing, NodeId(100))
    _ => fail("expected a structured missing-destination error")
  } noraise {
    _ => fail("expected missing destination node to be rejected")
  }
  assert_eq(edge_ids(try! graph.outgoing_edges(node)), [])
  assert_eq(edge_ids(try! graph.incoming_edges(node)), [])

  let edge = try! graph.create_edge(node, node, "SELF", {})
  assert_eq(edge, EdgeId(1))
}

///|
test "graph state copies edge properties and validates edge property changes" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  try
    graph.create_edge(from, to, "LINK", {
      "score": PropertyValue::Float64(@double.not_a_number),
    })
  catch {
    DatabaseError::InvalidPropertyValue(
      property="score",
      reason="Float64 properties must be finite"
    ) => ()
    _ => fail("expected invalid edge property creation to be rejected")
  } noraise {
    _ => fail("expected invalid edge properties to be rejected")
  }
  let properties : Properties = {
    "name": PropertyValue::String("original"),
    "score": PropertyValue::Float64(-0.0),
  }
  let edge = try! graph.create_edge(from, to, "LINK", properties)
  assert_eq(edge, EdgeId(1))
  properties.set("name", PropertyValue::String("caller"))

  let first_read = try! graph.get_edge(edge)
  assert_eq(first_read.properties, {
    "name": PropertyValue::String("original"),
    "score": PropertyValue::Float64(0.0),
  })
  first_read.properties.set("name", PropertyValue::String("reader"))
  graph.set_edge_property(edge, "score", PropertyValue::Int64(7)) catch {
    _ => fail("setting an edge property failed")
  }
  for
    invalid in [@double.not_a_number, @double.infinity, @double.neg_infinity].iter() {
    try
      graph.set_edge_property(edge, "score", PropertyValue::Float64(invalid))
    catch {
      DatabaseError::InvalidPropertyValue(..) => ()
      _ => fail("expected a structured invalid-property error")
    } noraise {
      _ => fail("database state must reject non-finite edge properties")
    }
  }
  assert_eq(try! graph.get_edge(edge).properties, {
    "name": PropertyValue::String("original"),
    "score": PropertyValue::Int64(7),
  })
  graph.remove_edge_property(edge, "score") catch {
    _ => fail("removing an edge property failed")
  }
  graph.remove_edge_property(edge, "score") catch {
    _ => fail("removing an absent edge property should be idempotent")
  }
  assert_eq(try! graph.get_edge(edge).properties, {
    "name": PropertyValue::String("original"),
  })
}

///|
test "graph state deletes edges from lookup and both adjacency directions" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  let edge = try! graph.create_edge(from, to, "LINK", {})

  graph.delete_edge(edge) catch {
    _ => fail("deleting an edge failed")
  }
  assert_eq(edge_ids(try! graph.outgoing_edges(from)), [])
  assert_eq(edge_ids(try! graph.incoming_edges(to)), [])
  try graph.get_edge(edge) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge)
    _ => fail("expected deleted edge lookup to report EdgeNotFound")
  } noraise {
    _ => fail("expected deleted edge lookup to fail")
  }
}

///|
test "graph state exhausts edge ids without wrapping" {
  let graph = GraphState::new()
  let node = try! graph.create_node([], {})
  graph.next_edge_id = Some(18446744073709551615UL)
  let final_edge = try! graph.create_edge(node, node, "SELF", {})
  assert_eq(final_edge, EdgeId(18446744073709551615UL))
  try graph.create_edge(node, node, "SELF", {}) catch {
    DatabaseError::EdgeIdExhausted => ()
    _ => fail("expected a structured edge-ID exhaustion error")
  } noraise {
    _ => fail("edge ID allocation must not wrap after maximum UInt64")
  }
}

///|
test "strict node deletion rejects incident edges without changing graph state" {
  let graph = GraphState::new()
  let from = try! graph.create_node(["From"], {})
  let center = try! graph.create_node(["Center"], {})
  let to = try! graph.create_node(["To"], {})
  let isolated = try! graph.create_node(["Isolated"], {})
  let incoming = try! graph.create_edge(from, center, "IN", {})
  let outgoing = try! graph.create_edge(center, to, "OUT", {})
  let self_loop = try! graph.create_edge(center, center, "SELF", {})
  let before = try! graph.get_node(center)

  try graph.delete_node(center) catch {
    DatabaseError::NodeHasIncidentEdges(missing) => assert_eq(missing, center)
    _ => fail("expected strict deletion to reject incident edges")
  } noraise {
    _ => fail("strict deletion must fail while incident edges exist")
  }

  assert_eq(try! graph.get_node(center), before)
  assert_eq(try! graph.get_edge(incoming).id, incoming)
  assert_eq(try! graph.get_edge(outgoing).id, outgoing)
  assert_eq(try! graph.get_edge(self_loop).id, self_loop)
  assert_eq(edge_ids(try! graph.incoming_edges(center)), [incoming, self_loop])
  assert_eq(edge_ids(try! graph.outgoing_edges(center)), [outgoing, self_loop])
  assert_eq(try! graph.get_node(from).id, from)
  assert_eq(try! graph.get_node(to).id, to)

  graph.delete_node(isolated) catch {
    _ => fail("deleting an isolated node failed")
  }
  try graph.get_node(isolated) catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, isolated)
    _ => fail("expected deleted isolated node to be missing")
  } noraise {
    _ => fail("expected deleted isolated node lookup to fail")
  }
  try graph.delete_node(NodeId(99)) catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected missing-node deletion to report NodeNotFound")
  } noraise {
    _ => fail("expected deletion of a missing node to fail")
  }
}

///|
test "cascade node deletion removes incident edges once and preserves unrelated data" {
  let graph = GraphState::new()
  let left = try! graph.create_node(["Left"], {})
  let center = try! graph.create_node(["Center"], {})
  let right = try! graph.create_node(["Right"], {})
  let unrelated_from = try! graph.create_node(["Other"], {})
  let unrelated_to = try! graph.create_node(["Other"], {})
  let incoming = try! graph.create_edge(left, center, "IN", {})
  let parallel = try! graph.create_edge(left, center, "IN", {})
  let outgoing = try! graph.create_edge(center, right, "OUT", {})
  let self_loop = try! graph.create_edge(center, center, "SELF", {})
  let unrelated = try! graph.create_edge(unrelated_from, unrelated_to, "KEEP", {})

  graph.delete_node_cascade(center) catch {
    _ => fail("cascade node deletion failed")
  }

  try graph.get_node(center) catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, center)
    _ => fail("expected cascaded node to be missing")
  } noraise {
    _ => fail("expected cascaded node lookup to fail")
  }
  for edge_id in [incoming, parallel, outgoing, self_loop].iter() {
    try graph.get_edge(edge_id) catch {
      DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge_id)
      _ => fail("expected each incident edge to be removed")
    } noraise {
      _ => fail("expected incident edge lookup to fail")
    }
  }
  assert_eq(graph.outgoing_edge_ids.get(center), None)
  assert_eq(graph.incoming_edge_ids.get(center), None)
  assert_eq(edge_ids(try! graph.outgoing_edges(left)), [])
  assert_eq(edge_ids(try! graph.incoming_edges(right)), [])
  assert_eq(try! graph.get_edge(unrelated).id, unrelated)
  assert_eq(edge_ids(try! graph.outgoing_edges(unrelated_from)), [unrelated])
  assert_eq(edge_ids(try! graph.incoming_edges(unrelated_to)), [unrelated])

  let next_node = try! graph.create_node([], {})
  let next_edge = try! graph.create_edge(left, right, "AFTER", {})
  assert_eq(next_node, NodeId(6))
  assert_eq(next_edge, EdgeId(6))
  assert_eq(edge_ids(try! graph.outgoing_edges(left)), [next_edge])
  assert_eq(edge_ids(try! graph.incoming_edges(right)), [next_edge])
}

///|
test "cascade validates every incident edge before mutating graph state" {
  let graph = GraphState::new()
  let left = try! graph.create_node(["Left"], {})
  let center = try! graph.create_node(["Center"], {})
  let right = try! graph.create_node(["Right"], {})
  let valid_edge = try! graph.create_edge(left, center, "VALID", {})
  let valid_outgoing = try! graph.create_edge(center, right, "VALID_OUT", {})
  let stale_edge = EdgeId(99)
  match graph.outgoing_edge_ids.get(center) {
    Some(edge_ids) => edge_ids.push(stale_edge)
    None => fail("expected the center node to have an outgoing adjacency entry")
  }

  try graph.delete_node_cascade(center) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, stale_edge)
    _ => fail("expected cascade to report the stale edge reference")
  } noraise {
    _ => fail("expected cascade to reject the stale edge reference")
  }

  assert_eq(try! graph.get_node(center).id, center)
  assert_eq(try! graph.get_edge(valid_edge).id, valid_edge)
  assert_eq(try! graph.get_edge(valid_outgoing).id, valid_outgoing)
  assert_eq(graph.node_ids_with_label("Center"), [center])
  assert_node_label_index_matches_scan(graph, "Center")
  assert_eq(graph.edge_ids_with_type("VALID"), [valid_edge])
  assert_edge_type_index_matches_scan(graph, "VALID")
  assert_eq(graph.edge_ids_with_type("VALID_OUT"), [valid_outgoing])
  assert_edge_type_index_matches_scan(graph, "VALID_OUT")
  assert_eq(graph.edge_ids_with_type("STALE"), [])
  assert_eq(graph.edge_ids_by_type.get("STALE"), None)
  assert_edge_type_index_matches_scan(graph, "STALE")
  assert_eq(graph.incoming_edge_ids.get(center), Some([valid_edge]))
  assert_eq(
    graph.outgoing_edge_ids.get(center),
    Some([valid_outgoing, stale_edge]),
  )
  assert_eq(edge_ids(try! graph.outgoing_edges(left)), [valid_edge])
  assert_eq(try! graph.create_node([], {}), NodeId(4))
  let next_edge = try! graph.create_edge(left, right, "AFTER", {})
  assert_eq(next_edge, EdgeId(3))
  assert_eq(edge_ids(try! graph.outgoing_edges(left)), [valid_edge, next_edge])
}

///|
test "graph state keeps node-label index consistent and ordered" {
  let graph = GraphState::new()
  let first = try! graph.create_node(["User", "User"], {})
  let second = try! graph.create_node(["User", "Admin"], {})
  assert_eq(graph.node_ids_with_label("User"), [first, second])
  assert_node_label_index_matches_scan(graph, "User")
  assert_node_label_index_matches_scan(graph, "Admin")
  assert_eq(graph.node_ids_with_label("Missing"), [])

  graph.add_label(first, "User") catch {
    _ => fail("adding a duplicate label failed")
  }
  graph.add_label(first, "Editor") catch {
    _ => fail("adding a new label failed")
  }
  assert_node_label_index_matches_scan(graph, "User")
  assert_node_label_index_matches_scan(graph, "Editor")

  graph.remove_label(first, "Absent") catch {
    _ => fail("removing an absent label failed")
  }
  graph.remove_label(first, "User") catch {
    _ => fail("removing an existing label failed")
  }
  assert_eq(graph.node_ids_with_label("User"), [second])
  assert_node_label_index_matches_scan(graph, "User")

  graph.add_label(first, "User") catch {
    _ => fail("re-adding a removed label failed")
  }
  assert_eq(graph.node_ids_with_label("User"), [first, second])
  assert_node_label_index_matches_scan(graph, "User")

  graph.set_node_property(first, "age", PropertyValue::Int64(28)) catch {
    _ => fail("setting a node property failed")
  }
  graph.remove_node_property(first, "age") catch {
    _ => fail("removing a node property failed")
  }
  assert_node_label_index_matches_scan(graph, "User")

  let detached = graph.node_ids_with_label("User")
  detached.push(NodeId(99))
  assert_eq(graph.node_ids_with_label("User"), [first, second])

  graph.remove_label(first, "User") catch {
    _ => fail("removing the first indexed label failed")
  }
  graph.remove_label(second, "User") catch {
    _ => fail("removing the final indexed label failed")
  }
  assert_eq(graph.node_ids_with_label("User"), [])
  assert_eq(graph.node_ids_by_label.get("User"), None)
  assert_node_label_index_matches_scan(graph, "User")

  try graph.add_label(NodeId(99), "User") catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected a structured missing-node error")
  } noraise {
    _ => fail("adding a label to a missing node should fail")
  }
  try graph.remove_label(NodeId(99), "User") catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected a structured missing-node error")
  } noraise {
    _ => fail("removing a label from a missing node should fail")
  }
  assert_node_label_index_matches_scan(graph, "User")
  assert_node_label_index_matches_scan(graph, "Editor")

  let invalid_graph = GraphState::new()
  try
    invalid_graph.create_node(["Rejected"], {
      "score": PropertyValue::Float64(@double.infinity),
    })
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("expected invalid node properties to be rejected")
  } noraise {
    _ => fail("invalid node creation should fail")
  }
  assert_eq(invalid_graph.node_ids_with_label("Rejected"), [])
  assert_eq(try! invalid_graph.create_node(["Accepted"], {}), NodeId(1))
  assert_node_label_index_matches_scan(invalid_graph, "Accepted")
}

///|
test "node-label index is cleaned by strict and cascade deletion" {
  let graph = GraphState::new()
  let isolated = try! graph.create_node(["Isolated"], {})
  graph.delete_node(isolated) catch {
    _ => fail("deleting an isolated node failed")
  }
  assert_eq(graph.node_ids_with_label("Isolated"), [])
  assert_node_label_index_matches_scan(graph, "Isolated")

  let left = try! graph.create_node(["Neighbor"], {})
  let center = try! graph.create_node(["Center"], {})
  let right = try! graph.create_node(["Neighbor"], {})
  let incoming = try! graph.create_edge(left, center, "IN", {})
  let outgoing = try! graph.create_edge(center, right, "OUT", {})
  let self_loop = try! graph.create_edge(center, center, "LOOP", {})
  try graph.delete_node(center) catch {
    DatabaseError::NodeHasIncidentEdges(missing) => assert_eq(missing, center)
    _ => fail("expected strict deletion of a connected node to fail")
  } noraise {
    _ => fail("strict deletion of a connected node should fail")
  }
  assert_node_label_index_matches_scan(graph, "Center")
  assert_eq(graph.node_ids_with_label("Center"), [center])

  graph.delete_node_cascade(center) catch {
    _ => fail("cascade deletion failed")
  }
  assert_node_label_index_matches_scan(graph, "Center")
  assert_eq(graph.node_ids_with_label("Center"), [])
  assert_eq(graph.node_ids_by_label.get("Center"), None)
  assert_node_label_index_matches_scan(graph, "Neighbor")
  for edge_id in [incoming, outgoing, self_loop].iter() {
    try graph.get_edge(edge_id) catch {
      DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge_id)
      _ => fail("expected each cascaded edge to be absent")
    } noraise {
      _ => fail("cascaded edge lookup should fail")
    }
  }
}

///|
test "graph state keeps edge-type index consistent through mutations" {
  let graph = GraphState::new()
  let left = try! graph.create_node([], {})
  let center = try! graph.create_node([], {})
  let right = try! graph.create_node([], {})
  let first = try! graph.create_edge(left, center, "LINKS", {})
  let parallel = try! graph.create_edge(left, center, "LINKS", {})
  let distinct = try! graph.create_edge(center, right, "MENTIONS", {})
  assert_eq(graph.edge_ids_with_type("LINKS"), [first, parallel])
  assert_edge_type_index_matches_scan(graph, "LINKS")
  assert_edge_type_index_matches_scan(graph, "MENTIONS")
  assert_eq(graph.edge_ids_with_type("MISSING"), [])

  graph.set_edge_property(first, "weight", PropertyValue::Int64(2)) catch {
    _ => fail("setting an edge property failed")
  }
  graph.remove_edge_property(first, "weight") catch {
    _ => fail("removing an edge property failed")
  }
  assert_edge_type_index_matches_scan(graph, "LINKS")
  assert_edge_type_index_matches_scan(graph, "MENTIONS")

  let detached = graph.edge_ids_with_type("LINKS")
  detached.push(EdgeId(99))
  assert_eq(graph.edge_ids_with_type("LINKS"), [first, parallel])

  try graph.create_edge(NodeId(99), right, "REJECTED", {}) catch {
    DatabaseError::EndpointNodeNotFound(missing) =>
      assert_eq(missing, NodeId(99))
    _ => fail("expected a missing-endpoint error")
  } noraise {
    _ => fail("edge creation with a missing endpoint should fail")
  }
  try graph.delete_edge(EdgeId(99)) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, EdgeId(99))
    _ => fail("expected a structured missing-edge error")
  } noraise {
    _ => fail("deleting a missing edge should fail")
  }
  assert_eq(graph.edge_ids_with_type("REJECTED"), [])
  assert_edge_type_index_matches_scan(graph, "LINKS")

  graph.delete_edge(first) catch {
    _ => fail("deleting the first parallel edge failed")
  }
  assert_eq(graph.edge_ids_with_type("LINKS"), [parallel])
  assert_edge_type_index_matches_scan(graph, "LINKS")
  graph.delete_edge(parallel) catch {
    _ => fail("deleting the last edge of a type failed")
  }
  assert_eq(graph.edge_ids_with_type("LINKS"), [])
  assert_eq(graph.edge_ids_by_type.get("LINKS"), None)
  assert_edge_type_index_matches_scan(graph, "LINKS")
  assert_eq(try! graph.get_edge(distinct).id, distinct)

  let incoming = try! graph.create_edge(left, center, "IN", {})
  let second_incoming = try! graph.create_edge(left, center, "IN", {})
  let outgoing = try! graph.create_edge(center, right, "OUT", {})
  let surviving_out = try! graph.create_edge(left, right, "OUT", {})
  let self_loop = try! graph.create_edge(center, center, "LOOP", {})
  assert_eq(graph.edge_ids_with_type("IN"), [incoming, second_incoming])
  assert_edge_type_index_matches_scan(graph, "IN")
  graph.delete_node_cascade(center) catch {
    _ => fail("cascade node deletion failed")
  }
  for edge_type in ["IN", "MENTIONS", "LOOP"] {
    assert_eq(graph.edge_ids_with_type(edge_type), [])
    assert_eq(graph.edge_ids_by_type.get(edge_type), None)
    assert_edge_type_index_matches_scan(graph, edge_type)
  }
  assert_eq(graph.edge_ids_with_type("OUT"), [surviving_out])
  assert_edge_type_index_matches_scan(graph, "OUT")
  for edge_id in [distinct, incoming, second_incoming, outgoing, self_loop] {
    try graph.get_edge(edge_id) catch {
      DatabaseError::EdgeNotFound(missing) => assert_eq(missing, edge_id)
      _ => fail("expected every cascaded incident edge to be absent")
    } noraise {
      _ => fail("cascaded incident edge lookup should fail")
    }
  }
  assert_eq(try! graph.get_edge(surviving_out).id, surviving_out)

  let invalid_graph = GraphState::new()
  let invalid_from = try! invalid_graph.create_node([], {})
  let invalid_to = try! invalid_graph.create_node([], {})
  try
    invalid_graph.create_edge(invalid_from, invalid_to, "REJECTED", {
      "score": PropertyValue::Float64(@double.infinity),
    })
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("expected invalid edge properties to be rejected")
  } noraise {
    _ => fail("invalid edge creation should fail")
  }
  assert_eq(invalid_graph.edge_ids_with_type("REJECTED"), [])
  let accepted = try! invalid_graph.create_edge(
    invalid_from,
    invalid_to,
    "ACCEPTED",
    {},
  )
  assert_eq(accepted, EdgeId(1))
  assert_edge_type_index_matches_scan(invalid_graph, "ACCEPTED")
}

///|
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

///|
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

///|
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

///|
fn task3_one_bytes() -> Bytes {
  Bytes::makei(3, index => {
    match index {
      0 => b'o'
      1 => b'n'
      _ => b'e'
    }
  })
}

///|
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
    "v": PropertyValue::Bytes(task3_one_bytes()),
  })
  let same_bytes_node = try! graph.create_node(["Value"], {
    "v": PropertyValue::Bytes(task3_one_bytes()),
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
    "v": PropertyValue::Bytes(task3_one_bytes()),
  })
  let same_bytes_edge = try! graph.create_edge(from, to, "VALUE", {
    "v": PropertyValue::Bytes(task3_one_bytes()),
  })
  let zero_edge = try! graph.create_edge(from, to, "VALUE", {
    "zero": PropertyValue::Float64(-0.0),
  })

  try! graph.create_node_property_index("Value", "v")
  try! graph.create_node_property_index("Value", "zero")
  try! graph.create_edge_property_index("VALUE", "v")
  try! graph.create_edge_property_index("VALUE", "zero")

  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Bool(true),
    ),
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
  let node_bytes_lookup = task3_one_bytes()
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Bytes(node_bytes_lookup),
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
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::Bool(true),
  )
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::Int64(1),
  )
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::Float64(1.0),
  )
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::String("one"),
  )
  assert_node_property_index_matches_scan(
    graph,
    "Value",
    "v",
    PropertyValue::Bytes(node_bytes_lookup),
  )
  let detached_node_ids = match
    (try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Bool(true),
    )) {
    Some(ids) => ids
    None => fail("expected a declared node index")
  }
  detached_node_ids.push(NodeId(999))
  assert_eq(
    try! graph.node_ids_by_property_index(
      "Value",
      "v",
      PropertyValue::Bool(true),
    ),
    Some([bool_node]),
  )

  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Bool(true),
    ),
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
  let edge_bytes_lookup = task3_one_bytes()
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Bytes(edge_bytes_lookup),
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
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::Bool(true),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::Int64(1),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::Float64(1.0),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::String("one"),
  )
  assert_edge_property_index_matches_scan(
    graph,
    "VALUE",
    "v",
    PropertyValue::Bytes(edge_bytes_lookup),
  )
  let detached_edge_ids = match
    (try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Bool(true),
    )) {
    Some(ids) => ids
    None => fail("expected a declared edge index")
  }
  detached_edge_ids.push(EdgeId(999))
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "VALUE",
      "v",
      PropertyValue::Bool(true),
    ),
    Some([bool_edge]),
  )
}

///|
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
    try! graph.edge_ids_by_property_index(
      "IN",
      "weight",
      PropertyValue::Int64(1),
    ),
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
    try! graph.edge_ids_by_property_index(
      "KEEP",
      "weight",
      PropertyValue::Int64(1),
    ),
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

///|
test "failed graph mutations preserve property index state" {
  let graph = GraphState::new()
  let from = try! graph.create_node([], {})
  let to = try! graph.create_node([], {})
  try! graph.create_edge_property_index("LINK", "weight")
  let edge = try! graph.create_edge(from, to, "LINK", {
    "weight": PropertyValue::Int64(1),
  })
  assert_eq(edge, EdgeId(1))
  let definition = EdgePropertyIndex::new("LINK", "weight")

  let before_missing_endpoint_edge = try! graph.get_edge(edge)
  let before_missing_endpoint_index = try! graph.edge_ids_by_property_index(
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  let before_missing_endpoint_definition = match
    graph.edge_property_indexes.get(definition) {
    Some(values) => values.copy()
    None => fail("expected declared LINK index")
  }
  let before_missing_endpoint_outgoing = match
    graph.outgoing_edge_ids.get(from) {
    Some(ids) => ids.copy()
    None => fail("expected source adjacency entry")
  }
  let before_missing_endpoint_incoming = match graph.incoming_edge_ids.get(to) {
    Some(ids) => ids.copy()
    None => fail("expected destination adjacency entry")
  }
  try
    graph.create_edge(NodeId(99), to, "LINK", {
      "weight": PropertyValue::Int64(1),
    })
  catch {
    DatabaseError::EndpointNodeNotFound(missing) =>
      assert_eq(missing, NodeId(99))
    _ => fail("missing endpoint should be rejected")
  } noraise {
    _ => fail("missing endpoint should be rejected")
  }
  assert_eq(try! graph.get_edge(edge), before_missing_endpoint_edge)
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    before_missing_endpoint_index,
  )
  assert_eq(
    graph.edge_property_indexes.get(definition),
    Some(before_missing_endpoint_definition),
  )
  assert_eq(
    graph.outgoing_edge_ids.get(from),
    Some(before_missing_endpoint_outgoing),
  )
  assert_eq(
    graph.incoming_edge_ids.get(to),
    Some(before_missing_endpoint_incoming),
  )

  let before_non_finite_create_edge = try! graph.get_edge(edge)
  let before_non_finite_create_index = try! graph.edge_ids_by_property_index(
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  let before_non_finite_create_definition = match
    graph.edge_property_indexes.get(definition) {
    Some(values) => values.copy()
    None => fail("expected declared LINK index")
  }
  let before_non_finite_create_outgoing = match
    graph.outgoing_edge_ids.get(from) {
    Some(ids) => ids.copy()
    None => fail("expected source adjacency entry")
  }
  let before_non_finite_create_incoming = match
    graph.incoming_edge_ids.get(to) {
    Some(ids) => ids.copy()
    None => fail("expected destination adjacency entry")
  }
  try
    graph.create_edge(from, to, "LINK", {
      "weight": PropertyValue::Float64(@double.infinity),
    })
  catch {
    DatabaseError::InvalidPropertyValue(..) => ()
    _ => fail("non-finite edge property should be rejected")
  } noraise {
    _ => fail("non-finite edge property should be rejected")
  }
  assert_eq(try! graph.get_edge(edge), before_non_finite_create_edge)
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    before_non_finite_create_index,
  )
  assert_eq(
    graph.edge_property_indexes.get(definition),
    Some(before_non_finite_create_definition),
  )
  assert_eq(
    graph.outgoing_edge_ids.get(from),
    Some(before_non_finite_create_outgoing),
  )
  assert_eq(
    graph.incoming_edge_ids.get(to),
    Some(before_non_finite_create_incoming),
  )
  let next_edge_after_rejected_creates = try! graph.create_edge(
    from,
    to,
    "LINK",
    { "weight": PropertyValue::Int64(1) },
  )
  assert_eq(next_edge_after_rejected_creates, EdgeId(2))
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    Some([edge, next_edge_after_rejected_creates]),
  )

  let before_duplicate_index_edge = try! graph.get_edge(edge)
  let before_duplicate_index = try! graph.edge_ids_by_property_index(
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  let before_duplicate_definition = match
    graph.edge_property_indexes.get(definition) {
    Some(values) => values.copy()
    None => fail("expected declared LINK index")
  }
  let before_duplicate_outgoing = match graph.outgoing_edge_ids.get(from) {
    Some(ids) => ids.copy()
    None => fail("expected source adjacency entry")
  }
  let before_duplicate_incoming = match graph.incoming_edge_ids.get(to) {
    Some(ids) => ids.copy()
    None => fail("expected destination adjacency entry")
  }
  try graph.create_edge_property_index("LINK", "weight") catch {
    DatabaseError::IndexAlreadyExists(..) => ()
    _ => fail("duplicate edge index should be rejected")
  } noraise {
    _ => fail("duplicate edge index should be rejected")
  }
  assert_eq(try! graph.get_edge(edge), before_duplicate_index_edge)
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    before_duplicate_index,
  )
  assert_eq(
    graph.edge_property_indexes.get(definition),
    Some(before_duplicate_definition),
  )
  assert_eq(graph.outgoing_edge_ids.get(from), Some(before_duplicate_outgoing))
  assert_eq(graph.incoming_edge_ids.get(to), Some(before_duplicate_incoming))

  let before_non_finite_update_edge = try! graph.get_edge(edge)
  let before_non_finite_update_index = try! graph.edge_ids_by_property_index(
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  let before_non_finite_update_definition = match
    graph.edge_property_indexes.get(definition) {
    Some(values) => values.copy()
    None => fail("expected declared LINK index")
  }
  let before_non_finite_update_outgoing = match
    graph.outgoing_edge_ids.get(from) {
    Some(ids) => ids.copy()
    None => fail("expected source adjacency entry")
  }
  let before_non_finite_update_incoming = match
    graph.incoming_edge_ids.get(to) {
    Some(ids) => ids.copy()
    None => fail("expected destination adjacency entry")
  }
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
  assert_eq(try! graph.get_edge(edge), before_non_finite_update_edge)
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    before_non_finite_update_index,
  )
  assert_eq(
    graph.edge_property_indexes.get(definition),
    Some(before_non_finite_update_definition),
  )
  assert_eq(
    graph.outgoing_edge_ids.get(from),
    Some(before_non_finite_update_outgoing),
  )
  assert_eq(
    graph.incoming_edge_ids.get(to),
    Some(before_non_finite_update_incoming),
  )

  let before_missing_delete_edge = try! graph.get_edge(edge)
  let before_missing_delete_index = try! graph.edge_ids_by_property_index(
    "LINK",
    "weight",
    PropertyValue::Int64(1),
  )
  let before_missing_delete_definition = match
    graph.edge_property_indexes.get(definition) {
    Some(values) => values.copy()
    None => fail("expected declared LINK index")
  }
  let before_missing_delete_outgoing = match graph.outgoing_edge_ids.get(from) {
    Some(ids) => ids.copy()
    None => fail("expected source adjacency entry")
  }
  let before_missing_delete_incoming = match graph.incoming_edge_ids.get(to) {
    Some(ids) => ids.copy()
    None => fail("expected destination adjacency entry")
  }
  try graph.delete_edge(EdgeId(99)) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, EdgeId(99))
    _ => fail("missing edge deletion should be rejected")
  } noraise {
    _ => fail("missing edge deletion should be rejected")
  }
  assert_eq(try! graph.get_edge(edge), before_missing_delete_edge)
  assert_eq(
    try! graph.edge_ids_by_property_index(
      "LINK",
      "weight",
      PropertyValue::Int64(1),
    ),
    before_missing_delete_index,
  )
  assert_eq(
    graph.edge_property_indexes.get(definition),
    Some(before_missing_delete_definition),
  )
  assert_eq(
    graph.outgoing_edge_ids.get(from),
    Some(before_missing_delete_outgoing),
  )
  assert_eq(
    graph.incoming_edge_ids.get(to),
    Some(before_missing_delete_incoming),
  )
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
  try cascade_graph.get_edge(EdgeId(99)) catch {
    DatabaseError::EdgeNotFound(missing) => assert_eq(missing, EdgeId(99))
    _ => fail("stale adjacency reference must not name an edge")
  } noraise {
    _ => fail("stale adjacency reference must not name an edge")
  }
  let next_edge = try! cascade_graph.create_edge(left, right, "AFTER", {})
  assert_eq(next_edge, EdgeId(3))
}
