# Contributing to MoonPropertyDB

MoonPropertyDB is in early development. Read the approved design and current
status before starting work, and keep the implementation boundary honest.

## Development workflow

- Use an issue-specific `codex/` branch when remote issue tracking is enabled.
- Keep each change focused and use meaningful commits; do not use empty,
  duplicate, or mechanical commits to inflate history.
- Add behavior tests before implementation changes when practical.
- Describe implementation, exact verification commands, and known limits in
  every review or merge request.
- Update `CHANGELOG.md`, `docs/progress.md`, and relevant design notes as
  verified behavior changes.

## MoonBit requirements

- Verify the installed toolchain with `moon version --all`.
- Confirm unfamiliar APIs against the current toolchain; do not infer MoonBit
  signatures from another language or an outdated example.
- Keep public concrete types at the public package boundary and internal graph,
  index, log, and storage representations private.
- Use structured errors for expected failures; do not panic on ordinary input.
- Review generated `pkg.generated.mbti` after `moon info`; include only
  intentional public interface changes.
- Record every dependency's exact registry name, version, source, API, and
  license in `THIRD_PARTY.md` before adding it.

## Required local checks

```sh
moon check --deny-warn
moon test --deny-warn
moon build --target native
moon fmt --check
moon info --target native
git diff --check
```

An empty test suite is not evidence that a planned database capability works.
