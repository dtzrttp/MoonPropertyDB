///|
/// Private mutable graph state. Database and transaction APIs will own this
/// implementation; callers receive detached model values from read operations.
priv struct GraphState {
  nodes : Map[NodeId, Node]
  edges : Map[EdgeId, Edge]
  node_ids_by_label : Map[String, Array[NodeId]]
  node_property_indexes : Map[
    NodePropertyIndex,
    Map[PropertyValue, Array[NodeId]],
  ]
  edge_ids_by_type : Map[String, Array[EdgeId]]
  outgoing_edge_ids : Map[NodeId, Array[EdgeId]]
  incoming_edge_ids : Map[NodeId, Array[EdgeId]]
  mut next_node_id : UInt64?
  mut next_edge_id : UInt64?
}

///|
priv struct NodePropertyIndex {
  label : String
  property : String
} derive(Eq, Hash)

///|
/// Create an empty graph state with the first database-assigned ID reserved.
#warnings("-unused_value")
fn GraphState::new() -> GraphState {
  {
    nodes: Map([]),
    edges: Map([]),
    node_ids_by_label: Map([]),
    node_property_indexes: Map([]),
    edge_ids_by_type: Map([]),
    outgoing_edge_ids: Map([]),
    incoming_edge_ids: Map([]),
    next_node_id: Some(1UL),
    next_edge_id: Some(1UL),
  }
}

///|
fn NodePropertyIndex::new(
  label : String,
  property : String,
) -> NodePropertyIndex {
  { label, property, }
}

///|
fn node_property_index_name(label : String, property : String) -> String {
  String::add(String::add("node:", label), String::add(".", property))
}

///|
fn add_node_property_index_value(
  values : Map[PropertyValue, Array[NodeId]],
  value : PropertyValue,
  node_id : NodeId,
) -> Unit {
  let ids = match values.get(value) {
    Some(ids) => ids.copy()
    None => []
  }
  ids.push(node_id)
  ids.sort_by((left, right) => compare_node_ids(left, right))
  ids.dedup()
  values.set(value, ids)
}

///|
fn GraphState::create_node_property_index(
  self : GraphState,
  label : String,
  property : String,
) -> Unit raise DatabaseError {
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(_) =>
      raise DatabaseError::IndexAlreadyExists(
        name=node_property_index_name(label, property),
      )
    None => ()
  }
  let values : Map[PropertyValue, Array[NodeId]] = Map([])
  for node_id, node in self.nodes {
    let mut has_label = false
    for node_label in node.labels.iter() {
      if node_label == label {
        has_label = true
      }
    }
    if has_label {
      match node.properties.get(property) {
        Some(value) => add_node_property_index_value(values, value, node_id)
        None => ()
      }
    }
  }
  self.node_property_indexes.set(definition, values)
}

///|
fn GraphState::node_ids_by_property_index(
  self : GraphState,
  label : String,
  property : String,
  value : PropertyValue,
) -> Array[NodeId]? raise DatabaseError {
  let canonical = normalize_property_value(property, value)
  let definition = NodePropertyIndex::new(label, property)
  match self.node_property_indexes.get(definition) {
    Some(values) =>
      Some(
        match values.get(canonical) {
          Some(ids) => ids.copy()
          None => []
        },
      )
    None => None
  }
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
/// Compare node IDs by their wrapped unsigned numeric value.
fn compare_node_ids(left : NodeId, right : NodeId) -> Int {
  match (left, right) {
    (NodeId(left_raw), NodeId(right_raw)) => left_raw.compare(right_raw)
  }
}

///|
/// Add a node to one label bucket and keep its IDs unique and ordered.
fn GraphState::add_node_label_index_entry(
  self : GraphState,
  label : String,
  node_id : NodeId,
) -> Unit {
  let ids = match self.node_ids_by_label.get(label) {
    Some(ids) => ids.copy()
    None => []
  }
  ids.push(node_id)
  ids.sort_by((left, right) => compare_node_ids(left, right))
  ids.dedup()
  self.node_ids_by_label.set(label, ids)
}

///|
/// Remove a node from one label bucket and delete empty buckets.
fn GraphState::remove_node_label_index_entry(
  self : GraphState,
  label : String,
  node_id : NodeId,
) -> Unit {
  match self.node_ids_by_label.get(label) {
    Some(ids) => {
      let remaining : Array[NodeId] = []
      for existing_id in ids.iter() {
        if existing_id != node_id {
          remaining.push(existing_id)
        }
      }
      if remaining.length() == 0 {
        self.node_ids_by_label.remove(label)
      } else {
        self.node_ids_by_label.set(label, remaining)
      }
    }
    None => ()
  }
}

///|
#warnings("-unused_value")
fn GraphState::node_ids_with_label(
  self : GraphState,
  label : String,
) -> Array[NodeId] {
  match self.node_ids_by_label.get(label) {
    Some(ids) => ids.copy()
    None => []
  }
}

///|
/// Compare edge IDs by their wrapped unsigned numeric value.
fn compare_edge_ids(left : EdgeId, right : EdgeId) -> Int {
  match (left, right) {
    (EdgeId(left_raw), EdgeId(right_raw)) => left_raw.compare(right_raw)
  }
}

///|
/// Add an edge to one type bucket and keep its IDs unique and ordered.
fn GraphState::add_edge_type_index_entry(
  self : GraphState,
  edge_type : String,
  edge_id : EdgeId,
) -> Unit {
  let ids = match self.edge_ids_by_type.get(edge_type) {
    Some(ids) => ids.copy()
    None => []
  }
  ids.push(edge_id)
  ids.sort_by((left, right) => compare_edge_ids(left, right))
  ids.dedup()
  self.edge_ids_by_type.set(edge_type, ids)
}

///|
/// Remove an edge from one type bucket and delete empty buckets.
fn GraphState::remove_edge_type_index_entry(
  self : GraphState,
  edge_type : String,
  edge_id : EdgeId,
) -> Unit {
  match self.edge_ids_by_type.get(edge_type) {
    Some(ids) => {
      let remaining : Array[EdgeId] = []
      for existing_id in ids.iter() {
        if existing_id != edge_id {
          remaining.push(existing_id)
        }
      }
      if remaining.length() == 0 {
        self.edge_ids_by_type.remove(edge_type)
      } else {
        self.edge_ids_by_type.set(edge_type, remaining)
      }
    }
    None => ()
  }
}

///|
#warnings("-unused_value")
fn GraphState::edge_ids_with_type(
  self : GraphState,
  edge_type : String,
) -> Array[EdgeId] {
  match self.edge_ids_by_type.get(edge_type) {
    Some(ids) => ids.copy()
    None => []
  }
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
  for label in owned_labels.iter() {
    self.add_node_label_index_entry(label, node_id)
  }
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
  self.add_node_label_index_entry(label, id)
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
  self.remove_node_label_index_entry(label, id)
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

///|
/// Return the stored edge or raise the structured missing-edge error.
fn GraphState::require_edge(
  self : GraphState,
  id : EdgeId,
) -> Edge raise DatabaseError {
  match self.edges.get(id) {
    Some(edge) => edge
    None => raise DatabaseError::EdgeNotFound(id)
  }
}

///|
/// Create a directed edge after checking both endpoints and validating properties.
/// Its ID is appended to each endpoint's adjacency in increasing allocation order.
#warnings("-unused_value")
fn GraphState::create_edge(
  self : GraphState,
  from : NodeId,
  to : NodeId,
  edge_type : String,
  properties : Properties,
) -> EdgeId raise DatabaseError {
  match self.nodes.get(from) {
    Some(_) => ()
    None => raise DatabaseError::EndpointNodeNotFound(from)
  }
  match self.nodes.get(to) {
    Some(_) => ()
    None => raise DatabaseError::EndpointNodeNotFound(to)
  }
  let owned_properties = copy_validated_properties(properties)
  let id = match self.next_edge_id {
    Some(id) => id
    None => raise DatabaseError::EdgeIdExhausted
  }
  if id == 18446744073709551615UL {
    self.next_edge_id = None
  } else {
    self.next_edge_id = Some(id + 1UL)
  }
  let edge_id = EdgeId(id)
  self.edges.set(
    edge_id,
    Edge::Edge(id=edge_id, from~, to~, edge_type~, properties=owned_properties),
  )
  let outgoing = match self.outgoing_edge_ids.get(from) {
    Some(edge_ids) => edge_ids
    None => []
  }
  outgoing.push(edge_id)
  self.outgoing_edge_ids.set(from, outgoing)
  let incoming = match self.incoming_edge_ids.get(to) {
    Some(edge_ids) => edge_ids
    None => []
  }
  incoming.push(edge_id)
  self.incoming_edge_ids.set(to, incoming)
  self.add_edge_type_index_entry(edge_type, edge_id)
  edge_id
}

///|
/// Return a detached copy of an edge and its property map.
#warnings("-unused_value")
fn GraphState::get_edge(
  self : GraphState,
  id : EdgeId,
) -> Edge raise DatabaseError {
  let edge = self.require_edge(id)
  Edge::Edge(
    id=edge.id,
    from=edge.from,
    to=edge.to,
    edge_type=edge.edge_type,
    properties=edge.properties.copy(),
  )
}

///|
/// Return detached edges from one adjacency index in deterministic ID order.
fn GraphState::edges_from_index(
  self : GraphState,
  node_id : NodeId,
  index : Map[NodeId, Array[EdgeId]],
) -> Array[Edge] raise DatabaseError {
  match self.nodes.get(node_id) {
    Some(_) => ()
    None => raise DatabaseError::NodeNotFound(node_id)
  }
  let result : Array[Edge] = []
  match index.get(node_id) {
    Some(edge_ids) =>
      for edge_id in edge_ids.iter() {
        result.push(self.get_edge(edge_id))
      }
    None => ()
  }
  result
}

///|
/// Return a detached, deterministic list of edges leaving a node.
#warnings("-unused_value")
fn GraphState::outgoing_edges(
  self : GraphState,
  node_id : NodeId,
) -> Array[Edge] raise DatabaseError {
  self.edges_from_index(node_id, self.outgoing_edge_ids)
}

///|
/// Return a detached, deterministic list of edges entering a node.
#warnings("-unused_value")
fn GraphState::incoming_edges(
  self : GraphState,
  node_id : NodeId,
) -> Array[Edge] raise DatabaseError {
  self.edges_from_index(node_id, self.incoming_edge_ids)
}

///|
/// Remove an edge ID from one adjacency entry, deleting empty entries.
fn remove_edge_from_index(
  index : Map[NodeId, Array[EdgeId]],
  node_id : NodeId,
  edge_id : EdgeId,
) -> Unit {
  match index.get(node_id) {
    Some(current) => {
      let remaining : Array[EdgeId] = []
      for current_id in current.iter() {
        if current_id != edge_id {
          remaining.push(current_id)
        }
      }
      if remaining.length() == 0 {
        index.remove(node_id)
      } else {
        index.set(node_id, remaining)
      }
    }
    None => ()
  }
}

///|
/// Delete an edge from lookup and both adjacency directions.
#warnings("-unused_value")
fn GraphState::delete_edge(
  self : GraphState,
  id : EdgeId,
) -> Unit raise DatabaseError {
  let edge = self.require_edge(id)
  self.remove_edge_type_index_entry(edge.edge_type, id)
  remove_edge_from_index(self.outgoing_edge_ids, edge.from, id)
  remove_edge_from_index(self.incoming_edge_ids, edge.to, id)
  self.edges.remove(id)
}

///|
/// Set or replace an edge property after validating its scalar value.
#warnings("-unused_value")
fn GraphState::set_edge_property(
  self : GraphState,
  id : EdgeId,
  key : String,
  value : PropertyValue,
) -> Unit raise DatabaseError {
  let edge = self.require_edge(id)
  let normalized = normalize_property_value(key, value)
  let properties = edge.properties.copy()
  properties.set(key, normalized)
  self.edges.set(
    id,
    Edge::Edge(
      id=edge.id,
      from=edge.from,
      to=edge.to,
      edge_type=edge.edge_type,
      properties~,
    ),
  )
}

///|
/// Remove an edge property. Removing an absent property is a no-op.
#warnings("-unused_value")
fn GraphState::remove_edge_property(
  self : GraphState,
  id : EdgeId,
  key : String,
) -> Unit raise DatabaseError {
  let edge = self.require_edge(id)
  let properties = edge.properties.copy()
  properties.remove(key)
  self.edges.set(
    id,
    Edge::Edge(
      id=edge.id,
      from=edge.from,
      to=edge.to,
      edge_type=edge.edge_type,
      properties~,
    ),
  )
}

///|
/// Collect a node's incoming and outgoing edges without counting self-loops twice.
fn GraphState::incident_edge_ids(
  self : GraphState,
  node_id : NodeId,
) -> Array[EdgeId] raise DatabaseError {
  match self.nodes.get(node_id) {
    Some(_) => ()
    None => raise DatabaseError::NodeNotFound(node_id)
  }
  let seen : Map[EdgeId, Unit] = Map([])
  let incident : Array[EdgeId] = []
  match self.incoming_edge_ids.get(node_id) {
    Some(edge_ids) =>
      for edge_id in edge_ids.iter() {
        match seen.get(edge_id) {
          Some(_) => ()
          None => {
            seen.set(edge_id, ())
            incident.push(edge_id)
          }
        }
      }
    None => ()
  }
  match self.outgoing_edge_ids.get(node_id) {
    Some(edge_ids) =>
      for edge_id in edge_ids.iter() {
        match seen.get(edge_id) {
          Some(_) => ()
          None => {
            seen.set(edge_id, ())
            incident.push(edge_id)
          }
        }
      }
    None => ()
  }
  incident
}

///|
/// Delete an unconnected node, rejecting the operation while any edge is incident.
#warnings("-unused_value")
fn GraphState::delete_node(
  self : GraphState,
  id : NodeId,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let incident = self.incident_edge_ids(id)
  if incident.length() > 0 {
    raise DatabaseError::NodeHasIncidentEdges(id)
  }
  for label in node.labels.iter() {
    self.remove_node_label_index_entry(label, id)
  }
  self.nodes.remove(id)
  self.outgoing_edge_ids.remove(id)
  self.incoming_edge_ids.remove(id)
}

///|
/// Delete a node and explicitly cascade to each unique incoming/outgoing edge.
/// All referenced edges are checked before mutation so expected failures are atomic.
#warnings("-unused_value")
fn GraphState::delete_node_cascade(
  self : GraphState,
  id : NodeId,
) -> Unit raise DatabaseError {
  let node = self.require_node(id)
  let incident = self.incident_edge_ids(id)
  for edge_id in incident.iter() {
    match self.edges.get(edge_id) {
      Some(_) => ()
      None => raise DatabaseError::EdgeNotFound(edge_id)
    }
  }
  for edge_id in incident.iter() {
    self.delete_edge(edge_id)
  }
  for label in node.labels.iter() {
    self.remove_node_label_index_entry(label, id)
  }
  self.nodes.remove(id)
  self.outgoing_edge_ids.remove(id)
  self.incoming_edge_ids.remove(id)
}
