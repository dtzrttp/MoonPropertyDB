///|
/// Require an active transaction before inspecting or mutating its candidate.
fn WriteTransaction::require_active(
  self : WriteTransaction,
) -> Unit raise DatabaseError {
  match self.status.val {
    Active => ()
    Failed => raise DatabaseError::TransactionFailed
    Committed => raise DatabaseError::TransactionAlreadyCommitted
    RolledBack => raise DatabaseError::TransactionAlreadyRolledBack
  }
}

///|
/// Create a node in the detached candidate graph.
pub fn WriteTransaction::create_node(
  self : WriteTransaction,
  labels : Array[String],
  properties : Properties,
) -> NodeId raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.create_node(labels, properties)
}

///|
/// Read a detached node from the candidate graph.
pub fn WriteTransaction::get_node(
  self : WriteTransaction,
  id : NodeId,
) -> Node raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.get_node(id)
}

///|
/// Return candidate node IDs carrying a label.
pub fn WriteTransaction::node_ids_with_label(
  self : WriteTransaction,
  label : String,
) -> Array[NodeId] raise DatabaseError {
  self.require_active()
  self.candidate.node_ids_with_label(label)
}

///|
/// Add a label to a candidate node.
pub fn WriteTransaction::add_label(
  self : WriteTransaction,
  id : NodeId,
  label : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.add_label(id, label)
}

///|
/// Remove a label from a candidate node.
pub fn WriteTransaction::remove_label(
  self : WriteTransaction,
  id : NodeId,
  label : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.remove_label(id, label)
}

///|
/// Set or replace a candidate node property.
pub fn WriteTransaction::set_node_property(
  self : WriteTransaction,
  id : NodeId,
  key : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.set_node_property(id, key, value)
}

///|
/// Remove a candidate node property.
pub fn WriteTransaction::remove_node_property(
  self : WriteTransaction,
  id : NodeId,
  key : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.remove_node_property(id, key)
}

///|
/// Create a directed edge in the detached candidate graph.
pub fn WriteTransaction::create_edge(
  self : WriteTransaction,
  from : NodeId,
  to : NodeId,
  edge_type : String,
  properties : Properties,
) -> EdgeId raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.create_edge(from, to, edge_type, properties)
}

///|
/// Read a detached edge from the candidate graph.
pub fn WriteTransaction::get_edge(
  self : WriteTransaction,
  id : EdgeId,
) -> Edge raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.get_edge(id)
}

///|
/// Return detached candidate edges leaving a node.
pub fn WriteTransaction::outgoing_edges(
  self : WriteTransaction,
  node_id : NodeId,
) -> Array[Edge] raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.outgoing_edges(node_id)
}

///|
/// Return detached candidate edges entering a node.
pub fn WriteTransaction::incoming_edges(
  self : WriteTransaction,
  node_id : NodeId,
) -> Array[Edge] raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.incoming_edges(node_id)
}

///|
/// Return candidate edge IDs carrying an edge type.
pub fn WriteTransaction::edge_ids_with_type(
  self : WriteTransaction,
  edge_type : String,
) -> Array[EdgeId] raise DatabaseError {
  self.require_active()
  self.candidate.edge_ids_with_type(edge_type)
}

///|
/// Set or replace a candidate edge property.
pub fn WriteTransaction::set_edge_property(
  self : WriteTransaction,
  id : EdgeId,
  key : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.set_edge_property(id, key, value)
}

///|
/// Remove a candidate edge property.
pub fn WriteTransaction::remove_edge_property(
  self : WriteTransaction,
  id : EdgeId,
  key : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.remove_edge_property(id, key)
}

///|
/// Delete a candidate edge.
pub fn WriteTransaction::delete_edge(
  self : WriteTransaction,
  id : EdgeId,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.delete_edge(id)
}

///|
/// Delete a candidate node only when it has no incident edges.
pub fn WriteTransaction::delete_node(
  self : WriteTransaction,
  id : NodeId,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.delete_node(id)
}

///|
/// Delete a candidate node and its incident edges.
pub fn WriteTransaction::delete_node_cascade(
  self : WriteTransaction,
  id : NodeId,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.delete_node_cascade(id)
}

///|
/// Define a candidate node-property equality index.
pub fn WriteTransaction::create_node_property_index(
  self : WriteTransaction,
  label : String,
  property : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.create_node_property_index(label, property)
}

///|
/// Return IDs from a candidate node-property equality index.
pub fn WriteTransaction::node_ids_by_property_index(
  self : WriteTransaction,
  label : String,
  property : String,
  value : PropertyValue,
) -> Array[NodeId]? raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.node_ids_by_property_index(label, property, value)
}

///|
/// Define a candidate edge-property equality index.
pub fn WriteTransaction::create_edge_property_index(
  self : WriteTransaction,
  edge_type : String,
  property : String,
) -> Unit raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.create_edge_property_index(edge_type, property)
}

///|
/// Return IDs from a candidate edge-property equality index.
pub fn WriteTransaction::edge_ids_by_property_index(
  self : WriteTransaction,
  edge_type : String,
  property : String,
  value : PropertyValue,
) -> Array[EdgeId]? raise DatabaseError {
  self.require_active()
  errdefer self.status.update(fn(_) { Failed })
  self.candidate.edge_ids_by_property_index(edge_type, property, value)
}
