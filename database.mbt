///|
/// The private state shared by copies of an in-memory database handle.
priv struct DatabaseState {
  committed : GraphState
  mut active : Ref[TransactionStatus]?
  mut closed : Bool
}

///|
/// The only transaction lifecycle state needed by this boundary slice.
priv enum TransactionStatus {
  Active
}

///|
/// An in-memory database handle over one committed graph state.
pub struct Database {
  priv state : Ref[DatabaseState]
}

///|
/// A constructor-facing transaction handle. Transaction operations are added
/// by the write-transaction implementation; its candidate remains private to
/// the package until then.
#warnings("-unused_field")
pub struct WriteTransaction {
  priv candidate : GraphState
}

///|
/// Create an empty in-memory database.
pub fn Database::new_in_memory() -> Database {
  {
    state: Ref::Ref({
      committed: GraphState::new(),
      active: None,
      closed: false,
    }),
  }
}

///|
/// Read a detached node from the last committed state.
pub fn Database::get_node(
  self : Database,
  id : NodeId,
) -> Node raise DatabaseError {
  if self.state.val.closed {
    raise DatabaseError::DatabaseClosed
  }
  self.state.val.committed.get_node(id)
}

///|
/// Read a detached edge from the last committed state.
pub fn Database::get_edge(
  self : Database,
  id : EdgeId,
) -> Edge raise DatabaseError {
  if self.state.val.closed {
    raise DatabaseError::DatabaseClosed
  }
  self.state.val.committed.get_edge(id)
}

///|
/// Begin the one constructor-facing write transaction allowed by this handle.
pub fn Database::begin_write(
  self : Database,
) -> WriteTransaction raise DatabaseError {
  if self.state.val.closed {
    raise DatabaseError::DatabaseClosed
  }
  match self.state.val.active {
    Some(_) => raise DatabaseError::WriterTransactionActive
    None => ()
  }
  let status = Ref::Ref(Active)
  let candidate = self.state.val.committed.copy_detached()
  self.state.val.active = Some(status)
  { candidate, }
}

///|
/// Close the handle and discard the constructor-facing active transaction.
pub fn Database::close(self : Database) -> Unit raise DatabaseError {
  if self.state.val.closed {
    raise DatabaseError::DatabaseClosed
  }
  self.state.val.active = None
  self.state.val.closed = true
}
