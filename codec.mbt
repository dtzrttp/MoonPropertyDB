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
