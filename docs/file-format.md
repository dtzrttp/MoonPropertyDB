# File format status

Persistent file formats are designed but not implemented in the current
snapshot. The current public database constructor is explicitly
`Database::new_in_memory()`.

The approved v0.1 format plan uses versioned records with a magic value,
format version, record length, monotonically increasing transaction ID,
operation count, operation payload, and CRC32 checksum. A complete corrupt
record must be reported; an incomplete final record may be treated as a
truncated log tail during recovery.

Snapshots are planned to contain the database format version, last included
transaction ID, next IDs, canonical nodes and edges, and property-index
definitions. Derived in-memory indexes will be rebuilt on open. Temporary
files, synchronization, and atomic publication must be verified on each
supported native platform before persistence is claimed.
