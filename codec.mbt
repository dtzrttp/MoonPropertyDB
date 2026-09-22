///|
/// Convert the low 16 bits of a value to a little-endian byte sequence.
#warnings("-unused_value")
fn wal_u16_bytes(value : UInt64) -> Bytes {
  Bytes::from_array([
    value.land(0xFFUL).to_byte(),
    (value >> 8).land(0xFFUL).to_byte(),
  ])
}

///|
/// Convert the low 32 bits of a value to a little-endian byte sequence.
#warnings("-unused_value")
fn wal_u32_bytes(value : UInt64) -> Bytes {
  Bytes::from_array([
    value.land(0xFFUL).to_byte(),
    (value >> 8).land(0xFFUL).to_byte(),
    (value >> 16).land(0xFFUL).to_byte(),
    (value >> 24).land(0xFFUL).to_byte(),
  ])
}

///|
fn wal_crc32_bits(crc : UInt64, remaining : Int) -> UInt64 {
  if remaining == 0 {
    crc
  } else {
    let next = if crc.land(1UL) == 1UL {
      (crc >> 1).lxor(0xEDB88320UL)
    } else {
      crc >> 1
    }
    wal_crc32_bits(next, remaining - 1)
  }
}

///|
/// Compute CRC32/ISO-HDLC over a byte sequence.
#warnings("-unused_value")
fn wal_crc32(bytes : Bytes) -> UInt64 {
  let mut crc = 0xFFFFFFFFUL
  for byte in bytes.iter() {
    crc = wal_crc32_bits(crc.lxor(byte.to_uint64()), 8)
  }
  crc.lxor(0xFFFFFFFFUL)
}

///|
priv struct WalOperation {
  tag : Byte
  payload : Bytes
}

///|
priv struct WalRecord {
  transaction_id : UInt64
  operations : Array[WalOperation]
}

///|
fn wal_append_bytes(target : Array[Byte], bytes : Bytes) -> Unit {
  target.append(bytes.to_array())
}

///|
fn wal_patch_u64(target : Array[Byte], offset : Int, value : UInt64) -> Unit {
  for index, byte in value.to_le_bytes().iter2() {
    target[offset + index] = byte
  }
}

///|
/// Encode one complete version-one WAL record.
#warnings("-unused_value")
fn wal_encode(record : WalRecord) -> Bytes raise DatabaseError {
  for operation in record.operations.iter() {
    if !wal_known_operation_tag(operation.tag) {
      raise DatabaseError::CorruptLogRecord(
        file="<memory>",
        offset=0UL,
        transaction_id=Some(record.transaction_id),
        reason="unknown WAL operation tag",
      )
    }
  }
  let prefix : Array[Byte] = []
  wal_append_bytes(prefix, b"MPDBWAL\x00")
  wal_append_bytes(prefix, wal_u16_bytes(1UL))
  wal_append_bytes(prefix, wal_u16_bytes(0UL))
  wal_append_bytes(prefix, Bytes::make(8, 0))
  wal_append_bytes(prefix, record.transaction_id.to_le_bytes())
  wal_append_bytes(
    prefix,
    wal_u32_bytes(record.operations.length().to_uint64()),
  )
  for operation in record.operations.iter() {
    prefix.push(operation.tag)
    wal_append_bytes(
      prefix,
      operation.payload.length().to_uint64().to_le_bytes(),
    )
    wal_append_bytes(prefix, operation.payload)
  }
  if prefix.length() > 2147483643 {
    raise DatabaseError::CorruptLogRecord(
      file="<memory>",
      offset=0UL,
      transaction_id=Some(record.transaction_id),
      reason="WAL record is too large",
    )
  }
  let total_length = (prefix.length() + 4).to_uint64()
  wal_patch_u64(prefix, 12, total_length)
  let checksum = wal_crc32(Bytes::from_array(prefix))
  wal_append_bytes(prefix, wal_u32_bytes(checksum))
  Bytes::from_array(prefix)
}

///|
#warnings("-unused_constructor")
priv enum WalDecode {
  Complete(WalRecord, Int)
  Truncated
}

///|
fn wal_has_range(bytes : Bytes, start : Int, length : Int) -> Bool {
  start >= 0 && length >= 0 && start <= bytes.length() - length
}

///|
fn wal_read_u64(bytes : Bytes, start : Int) -> UInt64 {
  let mut value = 0UL
  for index, byte in bytes[start:start + 8].iter2() {
    value = value.lor(byte.to_uint64() << (index * 8))
  }
  value
}

///|
fn wal_read_u16(bytes : Bytes, start : Int) -> UInt64 {
  wal_read_u64(
    Bytes::add(bytes[start:start + 2].to_owned(), Bytes::make(6, 0)),
    0,
  )
}

///|
fn wal_read_u32(bytes : Bytes, start : Int) -> UInt64 {
  wal_read_u64(
    Bytes::add(bytes[start:start + 4].to_owned(), Bytes::make(4, 0)),
    0,
  )
}

///|
fn wal_corrupt(
  file : String,
  offset : UInt64,
  transaction_id : UInt64?,
  reason : String,
) -> DatabaseError {
  DatabaseError::CorruptLogRecord(file~, offset~, transaction_id~, reason~)
}

///|
fn wal_known_operation_tag(tag : Byte) -> Bool {
  tag == b"\x01".at(0) || tag == b"\x02".at(0)
}

///|
fn wal_decode_operations(
  bytes : Bytes,
  cursor : Int,
  end : Int,
  remaining : Int,
  file : String,
  offset : UInt64,
  transaction_id : UInt64,
  operations : Array[WalOperation],
) -> Int raise DatabaseError {
  if remaining == 0 {
    cursor
  } else {
    if end - cursor < 9 {
      raise wal_corrupt(
        file,
        offset + cursor.to_uint64(),
        Some(transaction_id),
        "operation header exceeds WAL payload",
      )
    }
    let tag = bytes.at(cursor)
    if !wal_known_operation_tag(tag) {
      raise wal_corrupt(
        file,
        offset + cursor.to_uint64(),
        Some(transaction_id),
        "unknown WAL operation tag",
      )
    }
    let payload_length = wal_read_u64(bytes, cursor + 1)
    let available = (end - cursor - 9).to_uint64()
    if payload_length > available {
      raise wal_corrupt(
        file,
        offset + cursor.to_uint64(),
        Some(transaction_id),
        "operation payload exceeds WAL record",
      )
    }
    let payload_length_int = payload_length.to_int()
    let payload_start = cursor + 9
    operations.push(WalOperation::{
      tag,
      payload: bytes[payload_start:payload_start + payload_length_int].to_owned(),
    })
    wal_decode_operations(
      bytes,
      payload_start + payload_length_int,
      end,
      remaining - 1,
      file,
      offset,
      transaction_id,
      operations,
    )
  }
}

///|
/// Decode one WAL record, distinguishing an incomplete final tail from corruption.
#warnings("-unused_value")
fn wal_decode(
  bytes : Bytes,
  file~ : String,
  offset~ : UInt64,
) -> WalDecode raise DatabaseError {
  if !wal_has_range(bytes, 0, 32) {
    return Truncated
  }
  if !bytes[0:8].equal_to_bytes(b"MPDBWAL\x00") {
    raise wal_corrupt(file, offset, None, "invalid WAL magic")
  }
  let version = wal_read_u16(bytes, 8)
  if version != 1UL {
    raise DatabaseError::IncompatibleDatabaseFormat(version=version.to_uint16())
  }
  if wal_read_u16(bytes, 10) != 0UL {
    raise wal_corrupt(file, offset, None, "WAL flags are not zero")
  }
  let declared_length = wal_read_u64(bytes, 12)
  if declared_length < 36UL {
    raise wal_corrupt(file, offset, None, "WAL record length is too short")
  }
  if declared_length > bytes.length().to_uint64() {
    return Truncated
  }
  let declared_length_int = declared_length.to_int()
  let transaction_id = wal_read_u64(bytes, 20)
  let operation_count = wal_read_u32(bytes, 28)
  let max_operation_count = (declared_length - 36UL) / 9UL
  if operation_count > max_operation_count {
    raise wal_corrupt(
      file,
      offset,
      Some(transaction_id),
      "WAL operation count exceeds record length",
    )
  }
  let checksum_start = declared_length_int - 4
  let operations : Array[WalOperation] = []
  let cursor = wal_decode_operations(
    bytes,
    32,
    checksum_start,
    operation_count.to_int(),
    file,
    offset,
    transaction_id,
    operations,
  )
  if cursor != checksum_start {
    raise wal_corrupt(
      file,
      offset + cursor.to_uint64(),
      Some(transaction_id),
      "WAL operation payloads do not fill record",
    )
  }
  let expected_checksum = wal_read_u32(bytes, checksum_start)
  let actual_checksum = wal_crc32(bytes[0:checksum_start].to_owned())
  if expected_checksum != actual_checksum {
    raise DatabaseError::LogChecksumFailed(
      file~,
      offset~,
      transaction_id=Some(transaction_id),
    )
  }
  Complete(WalRecord::{ transaction_id, operations, }, declared_length_int)
}

///|
#warnings("-unused_field")
priv struct WalScanResult {
  records : Array[WalRecord]
  last_transaction_id : UInt64
}

///|
fn wal_scan_from(
  bytes : Bytes,
  cursor : Int,
  file : String,
  offset : UInt64,
  snapshot_transaction_id : UInt64,
  records : Array[WalRecord],
  last_transaction_id : UInt64,
) -> WalScanResult raise DatabaseError {
  if cursor >= bytes.length() {
    { records, last_transaction_id, }
  } else {
    let record_offset = offset + cursor.to_uint64()
    match
      wal_decode(
        bytes[cursor:bytes.length()].to_owned(),
        file~,
        offset=record_offset,
      ) {
      WalDecode::Truncated => { records, last_transaction_id, }
      WalDecode::Complete(record, consumed) => {
        let mut next_last_transaction_id = last_transaction_id
        if record.transaction_id > snapshot_transaction_id {
          if record.transaction_id != last_transaction_id + 1UL {
            raise DatabaseError::CorruptLogRecord(
              file~,
              offset=record_offset,
              transaction_id=Some(record.transaction_id),
              reason="non-sequential WAL transaction ID",
            )
          }
          records.push(record)
          next_last_transaction_id = record.transaction_id
        }
        wal_scan_from(
          bytes,
          cursor + consumed,
          file,
          offset,
          snapshot_transaction_id,
          records,
          next_last_transaction_id,
        )
      }
    }
  }
}

///|
/// Scan complete sequential WAL records after a snapshot boundary.
#warnings("-unused_value")
fn wal_scan(
  bytes : Bytes,
  file~ : String,
  offset~ : UInt64,
  snapshot_transaction_id~ : UInt64,
) -> WalScanResult raise DatabaseError {
  wal_scan_from(
    bytes,
    0,
    file,
    offset,
    snapshot_transaction_id,
    [],
    snapshot_transaction_id,
  )
}
