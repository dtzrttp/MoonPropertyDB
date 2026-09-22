# Benchmark status

No performance benchmark has been published yet. The current implementation
is an in-memory correctness slice, and no throughput or latency claim should be
inferred from the unit-test suite.

When storage and query execution exist, benchmarks should record the MoonBit
version, target backend, operating system, dataset shape, node/edge counts,
transaction sizes, index selectivity, warm-up policy, and repeat count. The
first useful comparisons are graph mutation, indexed equality lookup, scan
lookup, commit, reopen/recovery, and bounded query execution.
