# Recovery status

Durable crash recovery is still a planned v0.1 capability. The current Issue
#8 branch adds a pure in-memory WAL stream scanner on top of the v1 codec. It
walks complete records, enforces sequential transaction IDs after a supplied
snapshot boundary, skips records already covered by that boundary, and stops
normally at an incomplete final tail. It raises structured corruption errors
for middle-record checksum failures and duplicate or gapped transaction IDs.

The storage package now has a private native WAL file appender that encodes
one record, opens in append mode, writes it, and explicitly synchronizes data
before returning. Tests check byte-for-byte ordered appends and structured
open errors. This primitive is not yet called by transaction commit, and does
not by itself provide database-level durability or recovery. Snapshot,
checkpoint, operation replay, persistent open/reopen, and process-lock
implementations are still absent.

The intended recovery sequence is to validate the newest compatible snapshot,
rebuild derived indexes, and replay complete log records after the snapshot's
transaction ID. A truncated final record is ignored as an incomplete tail;
interior framing, version, operation, or checksum corruption must return a
structured data-corruption error with file and byte-offset context.

Before this feature is declared complete, integration tests must cover reopen,
truncated tails, interior corruption, snapshot boundaries, replay of only new
transactions, exclusive writer ownership, and commit durability failure paths.
The scanner tests are a lower-level prerequisite; they do not prove those
database-level behaviors.
