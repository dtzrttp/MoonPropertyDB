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
