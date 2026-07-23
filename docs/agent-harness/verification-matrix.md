# Verification matrix

Use the narrowest deterministic proof first, then the broader gate required by
the change. Record exact observed results in the active managed plan.

| Change surface | Fast check | Broader check | Behavioral evidence | Fallback or blocker | Owner/update trigger |
| --- | --- | --- | --- | --- | --- |
| Documentation or harness | `python3 tools/harness_gate.py` and `git diff --check` | `python3 tools/repo_lint.py` plus external adaptive verifier | Configured routes, plan registry, coverage, and project-owned links resolve | Keep plan active and name unsupported whole-tree verifier findings | Repository maintainers on route/schema changes |
| Dart library/core logic | `flutter test test/<focused_test>.dart` | `bash tools/run_checks.sh` | Fixture return values, diagnostics, controller state, or widget behavior | If Flutter is unavailable, run Python gates and label Dart checks `blocked` | Change author for every behavior change |
| Public API | Focused controller/model/material tests and docs review | Full root gate | Exported type behavior, serialization, and diagnostics match `PUBLIC_API.md` | Public API naming requires docs/tests and maintainer judgment | Repository maintainers on exported changes |
| GLB parsing or rewrite | Focused reader/rewriter/budget test | Full root gate plus relevant validator package tests | Malformed or supported fixture produces the expected typed result | Missing decoder/toolchain stays explicit | Ingestion owner on format changes |
| Native decoder/provenance | Provenance and bridge-focused tests | Package-native build/test selected by its managed plan | Exact source hash, license, symbol, and fixture behavior | Platform toolchain or device may be `blocked`/`not run` | Decoder maintainers on vendored source changes |
| Widget/mobile rendering | `flutter test test/viewer_widget_test.dart` or named material widget test | Plan-specific simulator/device capture | Widget state or screenshot with target, pin, fixture, camera, and lighting identity | Do not infer physical-device or cross-platform evidence | Feature owner when rendering behavior changes |
| Generated capability matrix | `python3 tools/generate_capability_matrix.py` then diff review | `flutter test test/capability_matrix_generation_test.dart` | Generated output matches source facts | Missing toolchain is recorded; never hand-edit output | Repository maintainers on capability changes |
| Security-sensitive loading boundary | Focused budget, cancellation, malformed-input, and provenance tests | Full root gate | Untrusted input fails boundedly with typed diagnostics | Security review/compliance remains `not run` without authorized evidence | Repository maintainers on trust-boundary changes |
| Repository harness | `python3 tools/harness_gate.py` | External `harness.py check --root . --warnings-as-errors` | Authority map, strict plans, 31 rows, and claim boundary are current | Whole-tree third-party/ignored-output mismatch is tracked as HDEBT-001 | Repository maintainers on harness changes |
| Harness-ready attestation | `python3 tools/harness_gate.py --require-harness-ready` with external key environment | External `harness.py certify` against trusted clean attestation commit | Fresh HMAC records and exact source/direct-child Git boundary | Fail closed; require `CERT000` before using `harness-ready` | Repository maintainers after every source or evidence change |
| API/service | N/A | N/A | No server API is owned | Add a contract only if a service is introduced | Future service owner |
| Data migration | N/A | N/A | No persistent datastore is owned | Add reconciliation and rollback before introducing persistence | Future data owner |
| Hosted CI/build policy | N/A in this adoption | N/A | No workflow was added because CI automation was not requested | Explicit user authorization required before hosted workflow changes | Repository maintainers |
| Production attestation | N/A | Only an explicitly requested provider-backed verifier | Provider-authenticated approval, rollback, artifact, freshness, and revocation | Current package has no production verifier or target | Future release/production owner |

Flaky, unavailable, stale, or untrusted checks are gaps, not passes.
