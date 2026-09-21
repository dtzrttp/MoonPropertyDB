# Contributing to MoonPropertyDB

MoonPropertyDB is in early development. Please check the
[v0.1.0 milestone](https://github.com/dtzrttp/MoonPropertyDB/milestone/1) and
open or use a focused issue before starting a substantial change.

## Branches and pull requests

- Use an issue-specific branch such as `codex/4-project-foundation` or
  `codex/<issue>-<topic>`.
- Keep each pull request focused on one issue and link it with `Fixes #<number>`
  when it fully resolves that issue.
- Describe what changed, exact commands and results used to verify it, and any
  known limitations. Do not describe planned work as complete.
- Update `CHANGELOG.md` and `docs/progress.md` when project status or delivered
  capabilities change.

## MoonBit changes

- For behavior changes, write focused tests first and verify the failing case
  before implementing the behavior.
- Verify the installed MoonBit version with `moon version`. Confirm every
  unfamiliar standard-library or package API with `moon ide doc`; do not infer
  signatures from another language or an outdated example.
- Before adding a Mooncakes dependency, inspect its exact registry version,
  source, license, and API. Record the decision in `THIRD_PARTY.md`.
- Keep packages acyclic, document public APIs, use structured errors for
  expected failures, and keep internal storage/index details private.
- Review generated `.mbti` files after `moon info --target native`; include
  interface changes only when intentional.

## Checks

From the repository root, run:

```sh
moon check --target native
moon test --target native
moon fmt --check
moon info --target native
git diff --check
```

Report the actual output and any command that could not be run. An empty test
suite is not evidence that a planned feature works.
