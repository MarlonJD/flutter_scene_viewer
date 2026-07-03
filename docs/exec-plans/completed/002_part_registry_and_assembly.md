# Exec plan: part registry and assembly tree

## Goal

Build a registry that maps `flutter_scene` node hierarchy to assembly,
sub-assembly, and part addresses.

## Non-goals

- Do not flatten hierarchy to entity names.
- Do not resolve duplicate names by guessing silently.

## Steps

1. Change: define internal `PartNode`/`PartRecord` model.
   Verify: pure Dart tests for assembly and primitive records.
2. Change: traverse adapter-provided node snapshots.
   Verify: fixture tree tests including dummy parent nodes.
3. Change: detect duplicate/ambiguous paths.
   Verify: diagnostics tests.
4. Change: expose read-only part tree API.
   Verify: controller/widget API tests.

## Acceptance criteria

- [x] geometry-less dummy nodes are preserved;
- [x] `PartAddress(nodePath, primitiveIndex)` resolves correctly;
- [x] ambiguous paths emit diagnostics;
- [x] tests cover nested assembly/sub-assembly/part structures.

## Progress log

- 2026-07-01: Plan created.
- 2026-07-02: Implemented the smallest part registry slice: immutable
  `PartTree`/`PartNode`/`PartRecord` values, adapter-provided
  `AdapterNodeSnapshot`, snapshot traversal that preserves geometry-less
  assembly/dummy nodes, primitive `PartAddress(nodePath, primitiveIndex)`
  records, duplicate node-path diagnostics, and controller `partTree`
  exposure. Verified targeted red/green tests with
  `flutter test test/part_registry_test.dart test/viewer_controller_load_test.dart test/part_address_test.dart`.
- 2026-07-02: Verified locally with `bash tools/run_checks.sh`: repo lint
  passed, Dart format check passed, `flutter analyze` reported no issues, and
  `flutter test` passed 17 tests with 1 expected GPU fixture skip.
- 2026-07-03: Acceptance criteria and verification are complete; archived this
  completed plan with the other finished v1 active plans.

## Verification log

- 2026-07-03: Archive audit confirmed all acceptance criteria are checked and
  no unchecked checklist items remain in this plan.
- 2026-07-03: Post-archive full harness: `bash tools/run_checks.sh` passed
  after moving completed active plans to `docs/exec-plans/completed/`: repo
  lint passed; Dart format check reported 41 files with 0 changed;
  `flutter pub get` completed; `flutter analyze` reported no issues; and
  `flutter test` passed 108 tests with 3 existing GPU-gated skips.
