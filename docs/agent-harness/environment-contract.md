# Agent environment contract

This is a Flutter library workspace. The default isolation model is one
single-writer Git working tree with task-local processes and temporary output.
Parallel read-only inspection is safe; concurrent writers must not edit the
same tree.

## Isolation model

| Concern | Contract | Evidence |
| --- | --- | --- |
| Workspace isolation | Inspect `git status --short --branch`, preserve unrelated paths, and use one writer for this tree | The adoption plan records the unrelated untracked Plan 028 and leaves it untouched |
| Dependency/cache isolation | `.dart_tool/`, `.pub-cache/`, build output, and `tools/out/` are generated/ignored state; do not treat them as durable evidence | `.gitignore`, output contract, and deterministic setup command |
| Port/process allocation | N/A for ordinary library tests; no server or fixed port is owned | No runtime-start command exists in the capability registry |
| Data/state isolation | Tests use checked-in fixtures and in-process state; target capture tools use plan-specific disposable directories | Fixture paths in `test/`, tool README files, and plan-specific capture commands |
| Artifact and log location | Temporary logs use `tools/out/` or `/private/tmp`; durable fixtures/reports require plan acceptance rationale | [`output-contract.md`](output-contract.md) |

## Lifecycle commands

| Stage | Exact command | Expected signal | Safe retry or cleanup | Status |
| --- | --- | --- | --- | --- |
| Setup | `flutter pub get` | Dependencies resolve at pinned revisions | Retry after network/toolchain recovery; do not rewrite pins silently | candidate until current run evidence is recorded |
| Start | N/A | No standalone process | Use a focused widget test or plan-owned example | N/A for this library |
| Seed or reproduce | `flutter test test/<focused_test>.dart` | Named fixture behavior passes or emits a focused failure | Retry after restoring the fixture or correcting the implementation | verified command shape |
| Reset | N/A | Each test process owns state | Stop the test process and remove only task-owned temporary output | N/A for persistent state |
| Stop and teardown | Test/capture process exits; check task-owned processes only when GUI automation was used | No task-owned process remains | Terminate only the exact task-owned process; never reset user profiles | verified policy |

## Agent-readable surfaces

| Surface | Access path | Useful actions | Expected evidence | Status |
| --- | --- | --- | --- | --- |
| Widget behavior | Flutter widget tests under `test/` | Pump the viewer, inspect state, gestures, diagnostics, and rendered widget structure | Named test assertions and scoped failure output | verified |
| Public library behavior | Unit tests plus [`../PUBLIC_API.md`](../PUBLIC_API.md) | Invoke controllers, loaders, policies, stores, and diagnostics | Return values, exceptions, diagnostics, and serialized state | verified |
| Target rendering | Plan-specific iOS Simulator capture runners and recorded fixtures | Exercise the exact model, camera, lighting, and material control | Screenshot/metrics plus target and revision identity | candidate outside a selected rendering plan |
| Logs | `tools/out/*.log` and command stdout/stderr | Correlate a failing check with its named section | Exact command, exit code, and concise active-plan evidence | verified |
| Metrics | N/A | No deployed service metrics are owned | A plan may define bounded render metrics for one experiment | N/A for repository-wide telemetry |
| Traces | N/A | No distributed or service trace surface exists | A future runtime must add a project-specific contract before use | N/A |

## Concurrency and cleanup

Use one writer per working tree. Do not create or change branches unless the
user explicitly requests it. GUI or browser automation must use an isolated
profile when practical and clean only task-owned leftover processes. Tests may
overwrite ignored logs; they must not delete checked-in fixtures or unrelated
user work. Native decoder builds and target capture commands are plan-scoped
because they may require toolchains, simulators, or large local artifacts.
