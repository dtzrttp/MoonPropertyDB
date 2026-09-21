///|
/// An immutable database-assigned node identifier.
pub(all) struct NodeId(UInt64) derive(Eq, Hash, Debug)

///|
/// An immutable database-assigned edge identifier.
pub(all) struct EdgeId(UInt64) derive(Eq, Hash, Debug)

///|
/// A supported scalar stored in node and edge properties.
pub(all) enum PropertyValue {
  Bool(Bool)
  Int64(Int64)
  Float64(Double)
  String(String)
  Bytes(Bytes)
} derive(Eq, Hash, Debug)
