# Output contract

The repository is the durable source of truth. Raw command output is useful, but
it is not automatically durable evidence.

## Temporary output

These outputs may be overwritten and should usually stay untracked:

- `tools/out/*.log`;
- local Flutter, Dart, and package caches;
- simulator screenshots or videos produced under `/private/tmp`;
- ad hoc smoke-test harness directories.

Use temporary output for local diagnosis and for copying the relevant result
into the active plan log.

## Durable evidence

Durable evidence belongs in one of these places:

- the active exec plan's progress or verification log;
- a focused doc that is linked from `AGENTS.md` or `docs/REPO_TOOLING.md`;
- a committed fixture, report, or artifact when reviewers need to reproduce or
  inspect it without local machine state.

Plan logs should summarize command, result, date, and any important flags. They
should not paste entire long logs unless the raw text is the product of the
task.

## Artifact rule

Commit an output artifact only when at least one of these is true:

- it is an input fixture used by tests;
- it is a stable report that reviewers need;
- it documents a visual regression or smoke result that cannot be summarized
  safely in text;
- a plan explicitly names it as an acceptance artifact.

Otherwise, leave raw output in `tools/out/` or `/private/tmp` and record the
important evidence in the plan log.

## Naming

Use stable, descriptive names for durable artifacts:

```text
reports/<plan-id>-<short-scenario>.md
test/fixtures/<descriptive-fixture-name>.glb
```

Avoid machine-local paths in public docs except inside plan logs that describe
local verification already completed.
