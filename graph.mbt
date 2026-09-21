///|
/// Private mutable graph state. Database and transaction APIs will own this
/// implementation; callers receive detached model values from read operations.
priv struct GraphState {
  nodes : Map[NodeId, Node]
  mut next_node_id : UInt64?
}

///|
/// Create an empty graph state with the first database-assigned ID reserved.
#warnings("-unused_value")
fn GraphState::new() -> GraphState {
  { nodes: Map([]), next_node_id: Some(1UL), }
}

///|
/// Validate a scalar and canonicalize negative zero before it enters graph state.
fn normalize_property_value(
  property : String,
  value : PropertyValue,
) -> PropertyValue raise DatabaseError {
  match value {
    PropertyValue::Float64(number) => {
      if number.is_nan() || number.is_inf() {
        raise DatabaseError::InvalidPropertyValue(
          property~,
          reason="Float64 properties must be finite",
        )
      }
      if number == 0.0 {
        PropertyValue::Float64(0.0)
      } else {
        value
      }
    }
    _ => value
  }
}

///|
/// Copy a property map while validating every stored scalar.
fn copy_validated_properties(
  properties : Properties,
) -> Properties raise DatabaseError {
  let copied : Properties = Map([])
  for key, value in properties {
    copied.set(key, normalize_property_value(key, value))
  }
  copied
}

///|
/// Return the stored node or raise the structured missing-node error.
fn GraphState::require_node(
  self : GraphState,
  id : NodeId,
) -> Node raise DatabaseError {
  match self.nodes.get(id) {
    Some(node) => node
    None => raise DatabaseError::NodeNotFound(id)
  }
}

///|
/// Allocate an ID only after all caller data has been validated and copied.
#warnings("-unused_value")
fn GraphState::create_node(
  self : GraphState,
  labels : Array[String],
  properties : Properties,
) -> NodeId raise DatabaseError {
  let owned_labels = labels.copy()
  owned_labels.sort()
  owned_labels.dedup()
  let owned_properties = copy_validated_properties(properties)
  let id = match self.next_node_id {
    Some(id) => id
    None => raise DatabaseError::NodeIdExhausted
  }
  if id == 18446744073709551615UL {
    self.next_node_id = None
  } else {
    self.next_node_id = Some(id + 1UL)
  }
  let node_id = NodeId(id)
  self.nodes.set(
    node_id,
    Node::Node(id=node_id, labels=owned_labels, properties=owned_properties),
  )
  node_id
}

///|
/// Return a detached copy of a node without exposing graph-owned collections.
#warnings("-unused_value")
fn GraphState::get_node(
  self : GraphState,
  id : NodeId,
) -> Node raise DatabaseError {
  let node = self.require_node(id)
  Node::Node(
    id=node.id,
    labels=node.labels.copy(),
    properties=node.properties.copy(),
  )
}

///|
/// Add a node label. Re-adding an existing label is a no-op.
#warnings("-unused_value")
fn GraphState::add_label(
  self : GraphState,
  id : NodeId,
  label : String,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let labels = node.labels.copy()
  labels.push(label)
  labels.sort()
  labels.dedup()
  self.nodes.set(
    id,
    Node::Node(id~, labels~, properties=node.properties.copy()),
  )
}

///|
/// Remove a node label. Removing an absent label is a no-op.
#warnings("-unused_value")
fn GraphState::remove_label(
  self : GraphState,
  id : NodeId,
  label : String,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let labels : Array[String] = []
  for existing in node.labels.iter() {
    if existing != label {
      labels.push(existing)
    }
  }
  self.nodes.set(
    id,
    Node::Node(id~, labels~, properties=node.properties.copy()),
  )
}

///|
/// Set or replace a node property after validating its scalar value.
#warnings("-unused_value")
fn GraphState::set_node_property(
  self : GraphState,
  id : NodeId,
  key : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let normalized = normalize_property_value(key, value)
  let properties = node.properties.copy()
  properties.set(key, normalized)
  self.nodes.set(id, Node::Node(id~, labels=node.labels.copy(), properties~))
}

///|
/// Remove a node property. Removing an absent property is a no-op.
#warnings("-unused_value")
fn GraphState::remove_node_property(
  self : GraphState,
  id : NodeId,
  key : String,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let properties = node.properties.copy()
  properties.remove(key)
  self.nodes.set(id, Node::Node(id~, labels=node.labels.copy(), properties~))
}
