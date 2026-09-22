# Third-party components and source provenance

The current runtime implementation has no third-party Mooncakes dependency.
The test package imports `moonbitlang/core/double`, which is part of the
MoonBit toolchain rather than a vendored runtime component.

MoonPropertyDB is an original implementation for this repository. No upstream
database source, copied fixture, or external test dataset is included in the
current tree. Generated `pkg.generated.mbti` is produced by `moon info` and is
kept only for public-interface review.

Before adding a dependency or copied material, record its exact name and
version, source URL, API usage, license, attribution requirements, and
redistribution scope here. Test data and generated code require the same
provenance review.
