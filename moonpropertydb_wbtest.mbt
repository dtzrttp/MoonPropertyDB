// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

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
