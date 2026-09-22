# Development progress

This document is the source of truth for the local code status. A design
statement is not evidence that a feature is implemented.

## Current snapshot

The current `main` history contains 53 real development commits from
2026-09-20 through 2026-09-22. The active implementation is a tested,
in-memory graph foundation:

- typed IDs and scalar property values;
- structured error categories;
- node and directed-edge CRUD;
- adjacency, label, edge-type, and equality indexes;
- strict/cascade node deletion;
- detached-candidate single-writer transactions;
- atomic commit publication and rollback;
- 34 native tests and a runnable in-memory example.

All current commit author and committer metadata belongs to `dtzrttp`.

## Verification evidence

The current toolchain is Moon `0.1.20260915` / `moonc` `0.10.13+cbb11c36f`.
The following commands pass locally on the native target:

```text
moon check --deny-warn
moon test --deny-warn       # 34 passed
moon build --target native
moon fmt --check
moon info --target native
git diff --check
```

The public interface is reviewed through the generated `pkg.generated.mbti`.
`moon ide doc` remains unavailable in this environment because the toolchain
reports missing backend metadata; compiler, generated-interface, and test
evidence are used instead.

## Planned v0.1 work

Persistent database paths, WAL/commit-log encoding, corruption detection,
recovery, snapshots/checkpoints, cross-process writer locking, the bounded
query pipeline, the full CLI, JSONL import/export, and the dependency-graph
example are not implemented. They must not be described as delivered until
their code and integration tests land.

## Repository tracking note

The code history was reconstructed into the formal public repository without
changing its final tree or commit messages. GitHub Issues, PRs, and milestones
must be recreated or linked separately if the project requires remote tracking;
this local document intentionally does not invent remote issue numbers.
