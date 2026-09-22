# Source, generated files, and license notes

MoonPropertyDB is an original MoonBit implementation for this repository. It
is not a port of a third-party database and no upstream source file or fixture
is included in the current tree.

The only imported package is `moonbitlang/core/double` for tests. It is supplied
by the MoonBit toolchain rather than bundled as a project runtime dependency.
If a Mooncakes package or copied fixture is added later, its exact name,
version, source URL, license, and redistribution scope must be recorded in
`THIRD_PARTY.md` before use.

AI assistance may be used during development, but every accepted change must
remain explainable, testable, maintainable, and license-compliant. The source
of generated files must remain clear: `pkg.generated.mbti` is produced by
`moon info` and is a public-interface review artifact, not handwritten source.

The project is distributed under Apache-2.0; the complete license is the root
`LICENSE` file and the module metadata declares the same SPDX identifier.
