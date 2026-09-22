# Query language status

The bounded read-only graph query language is part of the approved v0.1
design, but it is not implemented in the current snapshot. No query string
should be treated as executable yet.

The planned subset supports node variables and labels, directed edges and edge
types, explicit paths of at most three hops, equality predicates joined by
`AND`, node/edge IDs and scalar properties in projections, deterministic result
ordering, and `LIMIT`.

It explicitly excludes full openCypher compatibility, `OR`, aggregation,
grouping, optional matches, subqueries, unbounded paths, mutations inside a
query, user functions, and distributed execution.

Implementation order is lexer, parser/AST, semantic validation, planner, and
executor. Each stage must have independent tests; invalid queries must fail
before execution and must not mutate the database.
