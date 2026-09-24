# File format status

The current public database constructor is explicitly
`Database::new_in_memory()`. A private native storage primitive now appends an
encoded WAL v1 frame and explicitly synchronizes the file's data before it
returns. It is not integrated with transaction commit and does not yet make
the public database persistent.

The current Issue #7 branch implements and tests the pure in-memory WAL v1
record codec. Its private frame layout is:

| Field | Encoding |
| --- | --- |
| Magic | 8 bytes: `MPDBWAL\0` |
| Format version | little-endian `u16`, currently `1` |
| Reserved flags | little-endian `u16`, currently `0` |
| Total record length | little-endian `u64`, including the checksum |
| Transaction ID | little-endian `u64` |
| Operation count | little-endian `u32` |
| Operations | repeated tag byte, `u64` payload length, payload bytes |
| Checksum | little-endian `u32` CRC32/ISO-HDLC over all preceding bytes |

The decoder checks every header and operation boundary before slicing bytes.
It distinguishes a short final byte sequence from a complete frame with a bad
magic, version, flags, length, operation tag, operation boundary, or checksum.
It returns the consumed length so a later log scanner can continue after one
complete frame. File names and byte offsets are carried into structured errors.

The codec and private appender do not yet replay operations or expose
log-record types through the public API. Transaction integration, recovery,
and crash-safe commit behavior remain unfinished. A failed append or sync is
reported as a structured I/O error; caller-level handling that prevents
subsequent commits after an ambiguous partial write is not implemented yet.

Snapshots are planned to contain the database format version, last included
transaction ID, next IDs, canonical nodes and edges, and property-index
definitions. Derived in-memory indexes will be rebuilt on open. Temporary
files, synchronization, and atomic publication must be verified on each
supported native platform before persistence is claimed.
