# MoonPropertyDB

MoonPropertyDB is planned as an embedded, native MoonBit property-graph
database for applications that need local graph storage without a separate
database server.

> **Development status:** this repository currently contains the project and
> MoonBit module scaffold only. It is not yet a usable graph database. Node or
> edge operations, indexes, transactions, persistence, recovery, queries, and
> the CLI are planned, not implemented.

## Scope

The approved v0.1 plan prioritizes a small, documented MoonBit API; scalar node
and edge data; in-memory graph indexes; single-writer atomic transactions; a
checksummed commit log; crash recovery and snapshots; a bounded read-only graph
query language; and a local CLI and dependency-graph example. JSONL import and
export are P1 and will not delay the P0 release.

The project does not target full Neo4j/openCypher compatibility or claim to be a
production-grade database replacement. Multi-writer concurrency, MVCC,
distributed operation, a database server, range/composite/full-text/vector
indexes, and browser/Wasm persistence are outside v0.1.

See the [approved v0.1 design](docs/superpowers/specs/2026-09-20-moonpropertydb-design.md)
and the [architecture overview](docs/architecture.md).

## Development setup

The library and CLI are not published yet. Install the MoonBit CLI using the
[official download instructions](https://www.moonbitlang.com/download/) for
your operating system. Then clone the repository and run the current native
checks from its root:

```sh
git clone https://github.com/dtzrttp/MoonPropertyDB.git
cd MoonPropertyDB
moon check --target native
moon test --target native
moon fmt --check
moon info --target native
```

The scaffold was initialized with Moon `0.1.20260915`. At this stage
`moon test --target native` reports zero tests and `no test entry found`; this
means behavior tests have not been added yet, not that database behavior is
validated.

## Minimal library example

There is no public `Database` API yet, so the repository cannot provide a
runnable library example without inventing an unimplemented interface. A
verified example will be added with the first public API.

## CLI and query examples

The following illustrates the intended direction only. The command and query
are **not executable yet** because the CLI and query engine are not implemented:

```text
moonpropertydb query ./data 'MATCH (a:Package)-[:DEPENDS_ON]->(b:Package)
WHERE a.name = "example"
RETURN b.id, b.name
LIMIT 50'
```

Planned CLI commands include `init`, `query`, `index create`, `stats`, `verify`,
and `checkpoint`. The command examples will become runnable only after their
implementation and tests land.

## Persistence and recovery

The design uses an append-only transaction log and versioned, checksummed
snapshots, with recovery by loading a valid snapshot and replaying later
commits. None of that storage behavior exists in the current scaffold; do not
store application data with this project yet. Locking, durable synchronization,
atomic replacement, and directory-sync guarantees on Windows and Linux remain
verification gates.

## Tracking and roadmap

Development is tracked in the [v0.1.0 milestone](https://github.com/dtzrttp/MoonPropertyDB/milestone/1)
and the [project issues](https://github.com/dtzrttp/MoonPropertyDB/issues).
Current foundation work is tracked by [Issue #4](https://github.com/dtzrttp/MoonPropertyDB/issues/4).
The [progress log](docs/progress.md) distinguishes delivered work from planned
features.

## License

MoonPropertyDB is distributed under the [Apache License 2.0](LICENSE).
