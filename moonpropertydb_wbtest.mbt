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
  let cleaned = try! graph.get_node(id)
  assert_eq(cleaned.labels, ["User"])
  assert_eq(cleaned.properties, {})

  try graph.get_node(NodeId(99)) catch {
    DatabaseError::NodeNotFound(missing) => assert_eq(missing, NodeId(99))
    _ => fail("expected a structured NodeNotFound error")
  } noraise {
    _ => fail("expected get_node to reject a missing ID")
  }
}
