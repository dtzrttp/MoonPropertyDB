///|
/// A source location. Offset is a zero-based UTF-8 byte count, line is one-based,
/// and column is a one-based Unicode scalar-value count (not grapheme clusters).
pub(all) struct SourcePosition {
  offset : UInt64
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Construct a source location value.
pub fn SourcePosition::SourcePosition(
  offset~ : UInt64,
  line~ : Int,
  column~ : Int,
) -> SourcePosition {
  { offset, line, column, }
}

///|
/// A typed, inspectable failure from a MoonPropertyDB public operation.
pub(all) suberror DatabaseError {
  DatabaseDirectoryNotFound(path~ : String)
  DatabaseNotInitialized(path~ : String)
  DatabaseClosed
  IncompatibleDatabaseFormat(version~ : UInt16)
  WriterLockOccupied(path~ : String)
  NodeNotFound(NodeId)
  EdgeNotFound(EdgeId)
  EndpointNodeNotFound(NodeId)
  NodeHasIncidentEdges(NodeId)
  InvalidPropertyValue(property~ : String, reason~ : String)
  IndexAlreadyExists(name~ : String)
  IndexNotFound(name~ : String)
  QueryLexicalError(position~ : SourcePosition, reason~ : String)
  QuerySyntaxError(position~ : SourcePosition, reason~ : String)
  QuerySemanticError(position~ : SourcePosition, reason~ : String)
  IncompleteLogRecord(
    file~ : String,
    offset~ : UInt64,
    transaction_id~ : UInt64?
  )
  LogChecksumFailed(file~ : String, offset~ : UInt64, transaction_id~ : UInt64?)
  CorruptLogRecord(
    file~ : String,
    offset~ : UInt64,
    transaction_id~ : UInt64?,
    reason~ : String
  )
  SnapshotChecksumFailed(
    file~ : String,
    offset~ : UInt64,
    transaction_id~ : UInt64?
  )
  CorruptSnapshot(
    file~ : String,
    offset~ : UInt64,
    transaction_id~ : UInt64?,
    reason~ : String
  )
  IoError(file~ : String, operation~ : String, reason~ : String)
  TransactionAlreadyCommitted
  TransactionAlreadyRolledBack
  CommitOutcomeUnknown
} derive(Eq, Debug)
