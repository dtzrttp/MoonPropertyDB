# MoonPropertyDB agent and contributor rules

MoonPropertyDB is a MoonBit project. The approved v0.1 design is in
[`docs/superpowers/specs/2026-09-20-moonpropertydb-design.md`](docs/superpowers/specs/2026-09-20-moonpropertydb-design.md).
The design describes intended behavior; it is not evidence that a feature has
been implemented.

## Scope and correctness

- Do not claim a database capability is implemented unless its code and tests
  are present and the relevant checks pass. The current scaffold is not yet a
  usable graph database.
- Keep packages acyclic and preserve the public `database` boundary. Do not
  expose internal log records or index implementations.
- Use test-driven development for behavior changes. Cover expected failures
  with structured errors; do not use panic for ordinary user input.
- Preserve the v0.1 non-goals and P0/P1 boundary in the approved design.
- Keep `CHANGELOG.md` and `docs/progress.md` accurate as work lands.

## MoonBit API and tooling

- Never guess a MoonBit or Mooncakes API. Check the installed toolchain with
  `moon version`, use `moon ide doc` for the exact API, and verify package
  versions and licenses before adding dependencies.
- Do not add a dependency until its source, exact version, license, and API have
  been checked and recorded in `THIRD_PARTY.md`.
- Before a pull request, run `moon check --target native`,
  `moon test --target native`, `moon fmt --check`, and
  `moon info --target native`. Inspect generated `.mbti` changes and include
  only intentional interface updates.
- Follow the current MoonBit formatter and package conventions; do not copy
  syntax from another language or an outdated toolchain example.

## Collaboration

- Work from the issue-specific `codex/` branch and link each pull request to its
  issue. Keep each pull request focused and include implementation, test
  evidence, and known limitations.
- Do not put credentials, private account data, or unrelated local files in
  source, issues, commits, or pull requests.
