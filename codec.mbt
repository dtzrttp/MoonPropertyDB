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
fn wal_encode(record : WalRecord) -> Bytes {
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
  let total_length = (prefix.length() + 4).to_uint64()
  wal_patch_u64(prefix, 12, total_length)
  let checksum = wal_crc32(Bytes::from_array(prefix))
  wal_append_bytes(prefix, wal_u32_bytes(checksum))
  Bytes::from_array(prefix)
}
