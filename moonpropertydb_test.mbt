// Blackbox tests run against the package's public API. Use `@moonpropertydb` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "scalar property values retain their type and payload" {
  assert_eq(
    @moonpropertydb.PropertyValue::Bool(true),
    @moonpropertydb.PropertyValue::Bool(true),
  )
  assert_not_eq(
    @moonpropertydb.PropertyValue::Bool(true),
    @moonpropertydb.PropertyValue::Bool(false),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::Int64(1),
    @moonpropertydb.PropertyValue::Int64(1),
  )
  assert_not_eq(
    @moonpropertydb.PropertyValue::Int64(1),
    @moonpropertydb.PropertyValue::Float64(1.0),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::Float64(1.0),
    @moonpropertydb.PropertyValue::Float64(1.0),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::String("Alice"),
    @moonpropertydb.PropertyValue::String("Alice"),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::Bytes(b"graph"),
    @moonpropertydb.PropertyValue::Bytes(b"graph"),
  )
}

///|
test "node and edge values retain ids, labels, direction, and properties" {
  let properties : @moonpropertydb.Properties = {
    "name": @moonpropertydb.PropertyValue::String("Alice"),
    "age": @moonpropertydb.PropertyValue::Int64(28),
  }
  let node = @moonpropertydb.Node(
    id=@moonpropertydb.NodeId(1),
    labels=["User", "Developer"],
    properties~,
  )
  let same_node = @moonpropertydb.Node(
    id=@moonpropertydb.NodeId(1),
    labels=["User", "Developer"],
    properties={
      "name": @moonpropertydb.PropertyValue::String("Alice"),
      "age": @moonpropertydb.PropertyValue::Int64(28),
    },
  )
  assert_eq(node, same_node)

  let edge = @moonpropertydb.Edge(
    id=@moonpropertydb.EdgeId(2),
    from=@moonpropertydb.NodeId(1),
    to=@moonpropertydb.NodeId(3),
    edge_type="FOLLOWS",
    properties={},
  )
  let reversed = @moonpropertydb.Edge(
    id=@moonpropertydb.EdgeId(2),
    from=@moonpropertydb.NodeId(3),
    to=@moonpropertydb.NodeId(1),
    edge_type="FOLLOWS",
    properties={},
  )
  assert_not_eq(edge, reversed)
}
