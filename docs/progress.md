# Development progress

This document is the source of truth for the local code status. A design
statement is not evidence that a feature is implemented.

## Current snapshot

The preserved baseline contains 53 real development commits from 2026-09-20
through 2026-09-22. The formal `main` branch now also contains the reviewed
submission-readiness PR. The active Issue #8 branch is a tested in-memory graph
foundation plus private WAL codec and stream-scanning primitives:

- typed IDs and scalar property values;
- structured error categories;
- node and directed-edge CRUD;
- adjacency, label, edge-type, and equality indexes;
- strict/cascade node deletion;
- detached-candidate single-writer transactions;
- atomic commit publication and rollback;
- versioned WAL v1 framing, deterministic encoding, CRC32/ISO-HDLC checks, and
  corruption/truncation classification;
- sequential WAL scanning after a snapshot boundary, including duplicate/gap
  detection and final-tail handling;
- 41 native tests and a runnable in-memory example.

All current commit author and committer metadata belongs to `dtzrttp`.

## Verification evidence

The current toolchain is Moon `0.1.20260915` / `moonc` `0.10.13+cbb11c36f`.
The following commands pass locally on the native target:

```text
moon check --target native
moon test --target native   # 41 passed
moon build --target native
moon fmt --check
moon info --target native
git diff --check
```

The public interface is reviewed through the generated `pkg.generated.mbti`.
The installed toolchain's `moon ide doc` verified the exact `Bytes`, `BytesView`,
`Byte`, `UInt64`, `Array::append`, `Array::set`, and `Array::iter2` APIs used by
the codec. The codec record and decode-result types remain private.

## Planned v0.1 work

Persistent database paths, WAL append/synchronization, graph operation replay,
database reopen/recovery, snapshots/checkpoints, cross-process writer locking,
the bounded query pipeline, the full CLI, JSONL import/export, and the complete
dependency-graph demo are not implemented. The current WAL work is only the
tested in-memory codec and scanner; these capabilities must not be described
as delivered until their code and integration tests land.

## Repository tracking note

The code history was reconstructed into the formal public repository without
changing its final tree or commit messages. The formal repository now has the
`v0.1` milestone and Issues #1 through #15 for the approved work breakdown.
Historical PRs are not fabricated: future pull requests must represent real
branch changes and include implementation evidence, tests, and limitations.
