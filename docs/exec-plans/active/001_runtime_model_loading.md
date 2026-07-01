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

- [ ] network/asset/bytes sources have tests;
- [ ] adapter is isolated behind an interface;
- [ ] controller exposes loading diagnostics;
- [ ] no rendering implementation leaks into public API.

## Progress log

- 2026-07-01: Plan created.

## Verification log

- 2026-07-01: Not run yet.
