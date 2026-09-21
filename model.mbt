///|
/// An immutable database-assigned node identifier.
pub(all) struct NodeId(UInt64) derive(Eq, Hash, Debug)

///|
/// An immutable database-assigned edge identifier.
pub(all) struct EdgeId(UInt64) derive(Eq, Hash, Debug)

///|
/// A supported scalar stored in node and edge properties. Database write boundaries
/// must reject non-finite `Float64` values and normalize negative zero; this enum
/// itself can represent values that are invalid for storage.
pub(all) enum PropertyValue {
  Bool(Bool)
  Int64(Int64)
  Float64(Double)
  String(String)
  Bytes(Bytes)
} derive(Eq, Hash, Debug)

///|
/// A string-keyed map of supported scalar properties.
pub type Properties = Map[String, PropertyValue]

///|
/// A detached node value. Graph/database operations own relationship invariants.
/// The constructor retains the supplied labels and properties collections by reference.
pub(all) struct Node {
  id : NodeId
  labels : Array[String]
  properties : Properties
} derive(Eq, Debug)

///|
/// Construct a detached node value.
pub fn Node::Node(
  id~ : NodeId,
  labels~ : Array[String],
  properties~ : Properties,
) -> Node {
  { id, labels, properties, }
}

///|
/// A detached directed edge value. The constructor retains the supplied properties by reference.
pub(all) struct Edge {
  id : EdgeId
  from : NodeId
  to : NodeId
  edge_type : String
  properties : Properties
} derive(Eq, Debug)

///|
/// Construct a detached directed edge value.
pub fn Edge::Edge(
  id~ : EdgeId,
  from~ : NodeId,
  to~ : NodeId,
  edge_type~ : String,
  properties~ : Properties,
) -> Edge {
  { id, from, to, edge_type, properties, }
}
