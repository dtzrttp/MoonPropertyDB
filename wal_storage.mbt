///|
/// Append one encoded WAL record and synchronize its data before returning.
async fn wal_append_record(
  path : String,
  record : WalRecord,
) -> Unit raise DatabaseError {
  let bytes = try! wal_encode(record)
  let file = @fs.open(
    path,
    mode=@fs.Mode::WriteOnly,
    sync=@fs.SyncMode::NoSync,
    append=true,
    create_mode=@fs.CreateMode::OpenOrCreate,
  ) catch {
    _ =>
      raise DatabaseError::IoError(
        file=path,
        operation="open",
        reason="failed to open WAL for append",
      )
  }
  file.write(bytes) catch {
    _ => {
      file.close()
      raise DatabaseError::IoError(
        file=path,
        operation="append",
        reason="failed to append WAL record",
      )
    }
  }
  file.sync(only_data=true) catch {
    _ => {
      file.close()
      raise DatabaseError::IoError(
        file=path,
        operation="sync",
        reason="failed to synchronize WAL record",
      )
    }
  }
  file.close()
}
