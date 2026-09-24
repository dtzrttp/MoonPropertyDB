# Third-party components and source provenance

## Runtime dependencies

| Component | Version | Source | License | Use |
| --- | --- | --- | --- | --- |
| `moonbitlang/async` | `0.22.1` | [moonbitlang/async](https://github.com/moonbitlang/async) | Apache-2.0 | Native WAL file open, append, and explicit data synchronization through `async/fs`; async test runtime for the storage tests. |

The dependency metadata and exact version were checked with `moon view`, and
the resolved dependency tree was checked with `moon tree`. The installed
toolchain's `moon ide doc` confirmed the `fs.open`, `File::write`,
`File::sync`, and `File::close` APIs used here. No dependency source is
vendored. `moonbitlang/core/double` is part of the MoonBit toolchain and is
used only by tests.

MoonPropertyDB is an original implementation for this repository. No upstream
database source, copied fixture, or external test dataset is included in the
current tree. Generated `pkg.generated.mbti` is produced by `moon info` and is
kept only for public-interface review.

Before adding a dependency or copied material, record its exact name and
version, source URL, API usage, license, attribution requirements, and
redistribution scope here. Test data and generated code require the same
provenance review.
