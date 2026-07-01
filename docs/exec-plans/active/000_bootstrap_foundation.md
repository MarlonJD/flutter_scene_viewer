# Exec plan: bootstrap foundation

## Goal

Make the starter repository mechanically healthy and ready for feature work.

## Assumptions

- Flutter master or a compatible Flutter toolchain may be required by `flutter_scene`.
- If Flutter is unavailable in the environment, repo lints can still run.

## Non-goals

- Do not implement GLB rendering yet.
- Do not add features beyond making the skeleton verify.

## Steps

1. Change: run `flutter pub get` and inspect dependency/toolchain errors.
   Verify: record output in this plan.
2. Change: run `dart format .` and fix formatting only.
   Verify: `dart format --set-exit-if-changed .` passes.
3. Change: run analyzer/tests and fix skeleton-level issues.
   Verify: `flutter analyze` and `flutter test` pass or toolchain limitation is logged.
4. Change: run repo tooling checks.
   Verify: `bash tools/run_checks.sh` completes or logs missing Flutter.

## Acceptance criteria

- [x] repository checks attempted;
- [x] no unrelated feature work added;
- [x] this progress log updated with exact command results.

## Progress log

- 2026-07-01: Plan created in starter repo.
- 2026-07-01: Assumption: license selection is repository metadata work under
  the bootstrap foundation plan, not product behavior. Replaced the MIT license
  with MPL-2.0 and added a README license summary explaining commercial use and
  source-file copyleft expectations.
- 2026-07-01: Added a Flutter/Dart package `.gitignore` before the initial
  commit so generated local state (`.dart_tool/`, `build/`, `tools/out/`,
  `.DS_Store`, and root `pubspec.lock`) stays out of source control.
- 2026-07-01: Executed only
  `docs/exec-plans/active/000_bootstrap_foundation.md`. Assumptions/constraints:
  keep changes to skeleton health, formatting, public export hygiene, and plan
  evidence; do not implement rendering, loading, material, adapter, or scheduler
  features.
- 2026-07-01: Fixed skeleton analyzer/test issues only: made `PartAddress`
  runtime-validated instead of `const`, updated the public API example and test
  to use non-const construction, hid internal `ViewerCommandSink` from the
  package export, removed an unnecessary library name, removed a redundant
  `meta` import, and used `nodePath.isNotEmpty` in the assert.
- 2026-07-01: User-requested repo surface cleanup: moved repo verification
  scripts from top-level `harness/` to `tools/`, removed the redundant top-level
  `prompts/` folder, renamed `docs/HARNESS_ENGINEERING.md` to
  `docs/REPO_TOOLING.md`, and updated current docs to point at
  `bash tools/run_checks.sh`.

## Verification log

- 2026-07-01: Not run yet.
- 2026-07-01: `bash harness/run_checks.sh` first failed in sandbox because the
  Flutter tool attempted to update SDK cache files under
  `/Users/marlonjd/Developer/flutter/bin/cache`.
- 2026-07-01: `bash harness/run_checks.sh` passed when rerun with approved
  sandbox escalation: repo lint passed; `dart format --set-exit-if-changed lib
  test` reported 14 files formatted and 0 changed; `flutter pub get` completed;
  `flutter analyze` reported no issues; `flutter test` passed 4 tests.
- 2026-07-01: Final pre-commit `bash harness/run_checks.sh` first failed in the
  sandbox on the Flutter SDK cache write limitation, then passed with approved
  sandbox escalation: repo lint passed; format check changed 0 files; `flutter
  pub get` completed; `flutter analyze` reported no issues; `flutter test`
  passed 4 tests.
- 2026-07-01: `flutter pub get` first exited 1 in the sandbox because Flutter
  could not write
  `/Users/marlonjd/Developer/flutter/bin/cache/engine.stamp.tmp.*` and
  `/Users/marlonjd/Developer/flutter/bin/cache/engine.realm`. Rerun with
  approved sandbox escalation exited 0: dependencies resolved/downloaded,
  47 dependencies changed, and 5 packages reported newer versions incompatible
  with current constraints.
- 2026-07-01: `dart format .` first exited 1 in the sandbox for the same Flutter
  SDK cache write limitation. Rerun with approved sandbox escalation exited 0:
  formatted 14 files, 5 changed.
- 2026-07-01: `dart format --set-exit-if-changed .` first exited 1 in the
  sandbox for the same Flutter SDK cache write limitation. Rerun with approved
  sandbox escalation exited 0: formatted 14 files, 0 changed.
- 2026-07-01: Initial `flutter analyze` exited 1 with 4 issues:
  `unnecessary_library_name` in `lib/flutter_scene_viewer.dart`,
  `invalid_export_of_internal_element` for `ViewerCommandSink`,
  `unnecessary_import` in `lib/src/viewer_controller.dart`, and
  `const_eval_property_access` in `test/part_address_test.dart`.
- 2026-07-01: Initial `flutter test` exited 1: `test/part_address_test.dart`
  failed to load because `PartAddress` used `nodePath.length` in a const
  constructor assert; other loaded tests reached 3 passing checks before the
  failing load summary.
- 2026-07-01: Post-fix `dart format --set-exit-if-changed .` exited 0:
  formatted 14 files, 0 changed.
- 2026-07-01: Post-fix `flutter analyze` exited 0: no issues found.
- 2026-07-01: Post-fix `flutter test` exited 0: 4 tests passed.
- 2026-07-01: Final `bash harness/run_checks.sh` exited 0: repo lint passed;
  `dart format --set-exit-if-changed lib test` formatted 14 files, 0 changed;
  `flutter pub get` got dependencies and reported the same 5 constrained newer
  packages; `flutter analyze` found no issues; `flutter test` passed 4 tests;
  harness printed `== done ==`.
- 2026-07-01: Repeated `bash harness/run_checks.sh` after updating this plan
  log. It exited 0: repo lint passed; `dart format --set-exit-if-changed lib
  test` formatted 14 files, 0 changed; `flutter pub get` got dependencies and
  reported the same 5 constrained newer packages; `flutter analyze` found no
  issues; `flutter test` passed 4 tests; harness printed `== done ==`.
- 2026-07-01: After repo-surface cleanup, `python3 tools/repo_lint.py` exited
  0 with `repo lint passed`.
- 2026-07-01: After repo-surface cleanup, `bash tools/run_checks.sh` exited 0:
  repo lint passed; `dart format --set-exit-if-changed lib test` formatted
  14 files, 0 changed; `flutter pub get` got dependencies and reported the same
  5 constrained newer packages; `flutter analyze` found no issues; `flutter
  test` passed 4 tests; tooling script printed `== done ==`.
