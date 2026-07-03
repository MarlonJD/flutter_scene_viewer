# Exec plan: runtime model loading MVP

## Goal

Implement model loading for bytes, assets, and network using an isolated
`flutter_scene` adapter.

## Assumptions

- `flutter_scene` provides runtime GLB import.
- Network loading uses `http` with timeout and optional headers.

## Non-goals

- No multi-file `.gltf` in the first slice unless trivial.
- No compression support.
- No imported lights/cameras.

## Steps

1. Change: add `ModelLoader` service with `ModelSource` handling and size limits.
   Verify: unit tests for source dispatch, timeout config, and invalid URLs.
2. Change: add `FlutterSceneAdapter.loadGlbBytes` boundary.
   Verify: adapter compiles and is covered by a fake adapter test.
3. Change: wire `FlutterSceneViewerController.load` to the loader.
   Verify: controller test observes loading/success/error states.
4. Change: document current `flutter_scene` API assumptions.
   Verify: docs updated.

## Acceptance criteria

- [x] network/asset/bytes sources have tests;
- [x] adapter is isolated behind an interface;
- [x] controller exposes loading diagnostics;
- [x] no rendering implementation leaks into public API.

## Progress log

- 2026-07-01: Plan created.
- 2026-07-02: Added `ModelLoader` with bytes, asset, and network dispatch;
  configured byte limits and timeouts; optional network headers; invalid URL,
  timeout, size-limit, asset, network, and adapter diagnostics.
- 2026-07-02: Added controller load state (`idle`, `loading`, `success`,
  `error`) and wired `FlutterSceneViewer` command loading through
  `ModelLoader`.
- 2026-07-02: Initially kept `flutter_scene` behind
  `FlutterSceneAdapter.loadGlbBytes` without a concrete import because Flutter
  3.45.0-1.0.pre-38 lacked Flutter GPU symbols required by `flutter_scene`
  0.18.1. The expected upstream call remained `Node.fromGlbBytes(Uint8List)`.
- 2026-07-02: Switched the local Flutter SDK to master
  3.46.0-1.0.pre-403 / engine
  `6bef0a77783127874e0aedefe6aaf5abd42b63ed`, resolving the
  `flutter_scene` 0.18.1 Flutter GPU API mismatch.
- 2026-07-02: Replaced the temporary adapter-unavailable path with the concrete
  `package:flutter_scene/scene.dart` import and `Node.fromGlbBytes(bytes)`.
- 2026-07-02: Added a small valid `Box.glb` fixture from Khronos glTF Sample
  Models and verified the real successful `flutter_scene` import path with
  Flutter GPU and Impeller enabled.
- 2026-07-03: Acceptance criteria and verification are complete; archived this
  completed plan with the other finished v1 active plans.

## Verification log

- 2026-07-01: Not run yet.
- 2026-07-02: Red check: `flutter test test/model_loader_test.dart
  test/viewer_controller_load_test.dart` failed as expected for missing
  `ModelLoader`, loader result, diagnostics, and controller load state.
- 2026-07-02: Focused tests passed: `flutter test test/model_loader_test.dart
  test/viewer_controller_load_test.dart`.
- 2026-07-02: `dart format lib test` passed.
- 2026-07-02: `bash tools/run_checks.sh` passed: repo lint, format check,
  `flutter pub get`, `flutter analyze`, and `flutter test`.
- 2026-07-02: Red check after SDK switch: `flutter test
  test/model_loader_test.dart` failed as expected because
  `FlutterSceneRuntimeAdapter` still reported `adapterUnavailable`.
- 2026-07-02: Focused adapter check passed after concrete import:
  `flutter test test/model_loader_test.dart`.
- 2026-07-02: `bash tools/run_checks.sh` passed on Flutter master
  3.46.0-1.0.pre-403: repo lint, format check, `flutter pub get`,
  `flutter analyze`, and `flutter test`.
- 2026-07-02: Red check for valid import fixture: `flutter test
  test/model_loader_test.dart` failed because `test/fixtures/Box.glb` was
  missing.
- 2026-07-02: After downloading `Box.glb`, valid import initially failed until
  adapter resource initialization called `loadBaseShaderLibrary()` and
  `Material.initializeStaticResources()`.
- 2026-07-02: Opt-in real GLB import passed:
  `flutter test test/model_loader_test.dart --plain-name 'imports a valid GLB
  fixture through the flutter_scene adapter' --enable-impeller
  --enable-flutter-gpu --dart-define=FLUTTER_SCENE_GPU_TESTS=true`.
- 2026-07-02: `bash tools/run_checks.sh` passed after adding the valid GLB
  fixture. The opt-in Flutter GPU test is skipped in the default suite and
  verified separately with the flags above.
- 2026-07-03: Archive audit confirmed all acceptance criteria are checked and
  no unchecked checklist items remain in this plan.
- 2026-07-03: Post-archive full harness: `bash tools/run_checks.sh` passed
  after moving completed active plans to `docs/exec-plans/completed/`: repo
  lint passed; Dart format check reported 41 files with 0 changed;
  `flutter pub get` completed; `flutter analyze` reported no issues; and
  `flutter test` passed 108 tests with 3 existing GPU-gated skips.
