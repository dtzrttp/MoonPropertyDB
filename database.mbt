///|
/// The private state shared by copies of an in-memory database handle.
priv struct DatabaseState {
  mut committed : GraphState
  mut active : Ref[TransactionStatus]?
  mut closed : Bool
}

///|
/// The private transaction lifecycle shared by the database and its writer.
priv enum TransactionStatus {
  Active
  Failed
  Committed
  RolledBack
}

///|
/// An in-memory database handle over one committed graph state.
pub struct Database {
  priv state : Ref[DatabaseState]
}

///|
/// A write transaction over one detached candidate graph.
pub struct WriteTransaction {
  priv database : Ref[DatabaseState]
  priv candidate : GraphState
  priv status : Ref[TransactionStatus]
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
  { database: self.state, candidate, status, }
}

///|
/// Close the handle and discard the constructor-facing active transaction.
pub fn Database::close(self : Database) -> Unit raise DatabaseError {
  if self.state.val.closed {
    raise DatabaseError::DatabaseClosed
  }
  match self.state.val.active {
    Some(status) => status.update(fn(_) { RolledBack })
    None => ()
  }
  self.state.val.active = None
  self.state.val.closed = true
}
