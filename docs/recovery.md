# Recovery status

Crash recovery is a planned v0.1 capability and is not present in the current
in-memory snapshot. There is no durable WAL, snapshot, checkpoint, or process
lock implementation yet.

The intended recovery sequence is to validate the newest compatible snapshot,
rebuild derived indexes, and replay complete log records after the snapshot's
transaction ID. A truncated final record is ignored as an incomplete tail;
interior framing, version, operation, or checksum corruption must return a
structured data-corruption error with file and byte-offset context.

Before this feature is declared complete, integration tests must cover reopen,
truncated tails, interior corruption, snapshot boundaries, replay of only new
transactions, exclusive writer ownership, and commit durability failure paths.
