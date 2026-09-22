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
  assert_not_eq(
    node,
    @moonpropertydb.Node(
      id=@moonpropertydb.NodeId(4),
      labels=["User", "Developer"],
      properties~,
    ),
  )
  assert_not_eq(
    node,
    @moonpropertydb.Node(
      id=@moonpropertydb.NodeId(1),
      labels=["User"],
      properties~,
    ),
  )
  assert_not_eq(
    node,
    @moonpropertydb.Node(
      id=@moonpropertydb.NodeId(1),
      labels=["User", "Developer"],
      properties={ "name": @moonpropertydb.PropertyValue::String("Bob") },
    ),
  )

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
  assert_not_eq(
    edge,
    @moonpropertydb.Edge(
      id=@moonpropertydb.EdgeId(5),
      from=@moonpropertydb.NodeId(1),
      to=@moonpropertydb.NodeId(3),
      edge_type="FOLLOWS",
      properties={},
    ),
  )
  assert_not_eq(
    edge,
    @moonpropertydb.Edge(
      id=@moonpropertydb.EdgeId(2),
      from=@moonpropertydb.NodeId(1),
      to=@moonpropertydb.NodeId(3),
      edge_type="LIKES",
      properties={},
    ),
  )
  assert_not_eq(
    edge,
    @moonpropertydb.Edge(
      id=@moonpropertydb.EdgeId(2),
      from=@moonpropertydb.NodeId(1),
      to=@moonpropertydb.NodeId(3),
      edge_type="FOLLOWS",
      properties={ "since": @moonpropertydb.PropertyValue::Int64(2025) },
    ),
  )
}

///|
test "database errors preserve category and query location" {
  let position = @moonpropertydb.SourcePosition(offset=4, line=1, column=5)
  let same_position = @moonpropertydb.SourcePosition(offset=4, line=1, column=5)
  let next_position = @moonpropertydb.SourcePosition(offset=5, line=1, column=6)
  assert_eq(position, same_position)
  assert_not_eq(position, next_position)
  // One CJK Unicode scalar occupies three UTF-8 bytes but one source column.
  let after_cjk = @moonpropertydb.SourcePosition(offset=3, line=1, column=2)
  assert_eq(after_cjk.offset, 3)
  assert_eq(after_cjk.column, 2)

  assert_not_eq(
    @moonpropertydb.DatabaseError::DatabaseDirectoryNotFound(path="./data"),
    @moonpropertydb.DatabaseError::DatabaseNotInitialized(path="./data"),
  )

  assert_not_eq(
    @moonpropertydb.DatabaseError::NodeNotFound(@moonpropertydb.NodeId(1)),
    @moonpropertydb.DatabaseError::EdgeNotFound(@moonpropertydb.EdgeId(1)),
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::IncompleteLogRecord(
      file="graph.wal",
      offset=0,
      transaction_id=None,
    ),
    @moonpropertydb.DatabaseError::CorruptLogRecord(
      file="graph.wal",
      offset=12,
      transaction_id=None,
      reason="invalid magic",
    ),
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::LogChecksumFailed(
      file="graph.wal",
      offset=0,
      transaction_id=None,
    ),
    @moonpropertydb.DatabaseError::CorruptLogRecord(
      file="graph.wal",
      offset=12,
      transaction_id=None,
      reason="invalid operation",
    ),
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::SnapshotChecksumFailed(
      file="snapshot-1.bin",
      offset=256,
      transaction_id=None,
    ),
    @moonpropertydb.DatabaseError::CorruptSnapshot(
      file="snapshot-1.bin",
      offset=48,
      transaction_id=None,
      reason="invalid node record",
    ),
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::SnapshotChecksumFailed(
      file="snapshot-1.bin",
      offset=256,
      transaction_id=None,
    ),
    @moonpropertydb.DatabaseError::IoError(
      file="snapshot-1.bin",
      operation="read",
      reason="denied",
    ),
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::DatabaseClosed,
    @moonpropertydb.DatabaseError::TransactionAlreadyCommitted,
  )
  assert_not_eq(
    @moonpropertydb.DatabaseError::QueryLexicalError(
      position~,
      reason="unexpected character",
    ),
    @moonpropertydb.DatabaseError::QuerySyntaxError(
      position~,
      reason="expected node pattern",
    ),
  )
}

///|
test "in-memory database starts with committed reads only" {
  let database = @moonpropertydb.Database::new_in_memory()
  try database.get_node(@moonpropertydb.NodeId(1)) catch {
    @moonpropertydb.DatabaseError::NodeNotFound(id) =>
      assert_eq(id, @moonpropertydb.NodeId(1))
    _ => fail("empty database must report a missing node")
  } noraise {
    _ => fail("empty database read must return a structured error")
  }
  try database.get_edge(@moonpropertydb.EdgeId(1)) catch {
    @moonpropertydb.DatabaseError::EdgeNotFound(id) =>
      assert_eq(id, @moonpropertydb.EdgeId(1))
    _ => fail("empty database must report a missing edge")
  } noraise {
    _ => fail("empty database read must return a structured error")
  }
}

///|
test "closed database rejects reads, writers, and repeated close" {
  let database = @moonpropertydb.Database::new_in_memory()
  let _transaction = try! database.begin_write()
  try! database.close()
  try database.get_node(@moonpropertydb.NodeId(1)) catch {
    @moonpropertydb.DatabaseError::DatabaseClosed => ()
    _ => fail("closed database must reject node reads")
  } noraise {
    _ => fail("closed database read must return a structured error")
  }
  try database.get_edge(@moonpropertydb.EdgeId(1)) catch {
    @moonpropertydb.DatabaseError::DatabaseClosed => ()
    _ => fail("closed database must reject edge reads")
  } noraise {
    _ => fail("closed database read must return a structured error")
  }
  try database.begin_write() catch {
    @moonpropertydb.DatabaseError::DatabaseClosed => ()
    _ => fail("closed database must reject new writers")
  } noraise {
    _ => fail("closed database write must return a structured error")
  }
  try database.close() catch {
    @moonpropertydb.DatabaseError::DatabaseClosed => ()
    _ => fail("closing a closed database must return a structured error")
  } noraise {
    _ => fail("closing a closed database must return a structured error")
  }
}

///|
test "failed write poisons transaction without partial candidate mutation" {
  let database = @moonpropertydb.Database::new_in_memory()
  let transaction = try! database.begin_write()
  let node = try! transaction.create_node(["User"], {
    "age": @moonpropertydb.PropertyValue::Int64(1),
  })
  try
    transaction.set_node_property(
      node,
      "age",
      @moonpropertydb.PropertyValue::Float64(@double.not_a_number),
    )
  catch {
    @moonpropertydb.DatabaseError::InvalidPropertyValue(
      property="age",
      reason="Float64 properties must be finite"
    ) => ()
    _ => fail("invalid property must preserve its structured error")
  } noraise {
    _ => fail("invalid property must raise")
  }
  try transaction.get_node(node) catch {
    @moonpropertydb.DatabaseError::TransactionFailed => ()
    _ => fail("failed transactions must reject reads after the failure")
  } noraise {
    _ => fail("failed transactions must reject reads after the failure")
  }
  try transaction.create_node([], {}) catch {
    @moonpropertydb.DatabaseError::TransactionFailed => ()
    _ => fail("failed transactions must reject later writes")
  } noraise {
    _ => fail("failed transactions must raise on later writes")
  }
}

///|
test "transaction stages every graph operation over candidate reads" {
  let database = @moonpropertydb.Database::new_in_memory()
  let transaction = try! database.begin_write()
  let first = try! transaction.create_node(["User"], {
    "name": @moonpropertydb.PropertyValue::String("Alice"),
    "age": @moonpropertydb.PropertyValue::Int64(28),
  })
  let second = try! transaction.create_node(["User"], {})
  assert_eq(try! transaction.node_ids_with_label("User"), [first, second])

  try! transaction.add_label(first, "Admin")
  try! transaction.remove_label(first, "Admin")
  try! transaction.set_node_property(
    first,
    "age",
    @moonpropertydb.PropertyValue::Int64(29),
  )
  try! transaction.remove_node_property(first, "age")
  let node_read = try! transaction.get_node(first)
  node_read.labels.push("Detached")
  node_read.properties.set(
    "name",
    @moonpropertydb.PropertyValue::String("Mutated"),
  )
  assert_eq((try! transaction.get_node(first)).properties, {
    "name": @moonpropertydb.PropertyValue::String("Alice"),
  })

  let edge = try! transaction.create_edge(first, second, "KNOWS", {
    "weight": @moonpropertydb.PropertyValue::Int64(1),
  })
  assert_eq(try! transaction.outgoing_edges(first), [
    @moonpropertydb.Edge::Edge(
      id=edge,
      from=first,
      to=second,
      edge_type="KNOWS",
      properties={ "weight": @moonpropertydb.PropertyValue::Int64(1) },
    ),
  ])
  assert_eq(try! transaction.incoming_edges(second), [
    @moonpropertydb.Edge::Edge(
      id=edge,
      from=first,
      to=second,
      edge_type="KNOWS",
      properties={ "weight": @moonpropertydb.PropertyValue::Int64(1) },
    ),
  ])
  try! transaction.set_edge_property(
    edge,
    "weight",
    @moonpropertydb.PropertyValue::Int64(2),
  )
  try! transaction.remove_edge_property(edge, "weight")
  assert_eq((try! transaction.get_edge(edge)).properties, {})

  try! transaction.create_node_property_index("User", "name")
  try! transaction.create_edge_property_index("KNOWS", "weight")
  assert_eq(
    try! transaction.node_ids_by_property_index(
      "User",
      "name",
      @moonpropertydb.PropertyValue::String("Alice"),
    ),
    Some([first]),
  )
  assert_eq(
    try! transaction.edge_ids_by_property_index(
      "KNOWS",
      "weight",
      @moonpropertydb.PropertyValue::Int64(2),
    ),
    Some([]),
  )

  try! transaction.delete_edge(edge)
  try! transaction.delete_node(second)
  try! transaction.delete_node_cascade(first)
  try database.get_node(first) catch {
    @moonpropertydb.DatabaseError::NodeNotFound(id) => assert_eq(id, first)
    _ => fail("staged transaction data must not enter committed reads")
  } noraise {
    _ => fail("staged transaction data must remain uncommitted")
  }
}

///|
test "commit publishes a batch and rollback publishes nothing" {
  let database = @moonpropertydb.Database::new_in_memory()
  let first = try! database.begin_write()
  let first_id = try! first.create_node(["User"], {
    "name": @moonpropertydb.PropertyValue::String("Alice"),
  })
  try! first.create_node_property_index("User", "name")
  try! first.commit()
  assert_eq(
    try! database.get_node(first_id),
    @moonpropertydb.Node::Node(id=first_id, labels=["User"], properties={
      "name": @moonpropertydb.PropertyValue::String("Alice"),
    }),
  )
  try first.rollback() catch {
    @moonpropertydb.DatabaseError::TransactionAlreadyCommitted => ()
    _ => fail("a committed transaction must reject rollback")
  } noraise {
    _ => fail("a committed transaction must reject rollback")
  }

  let second = try! database.begin_write()
  let rolled_back_id = try! second.create_node(["User"], {})
  try! second.rollback()
  try database.get_node(rolled_back_id) catch {
    @moonpropertydb.DatabaseError::NodeNotFound(id) =>
      assert_eq(id, rolled_back_id)
    _ => fail("rollback must not publish candidate nodes")
  } noraise {
    _ => fail("rollback must not publish candidate nodes")
  }
  try second.commit() catch {
    @moonpropertydb.DatabaseError::TransactionAlreadyRolledBack => ()
    _ => fail("a rolled-back transaction must reject commit")
  } noraise {
    _ => fail("a rolled-back transaction must reject commit")
  }

  let third = try! database.begin_write()
  assert_eq(try! third.create_node(["User"], {}), rolled_back_id)
  try! third.commit()
}
