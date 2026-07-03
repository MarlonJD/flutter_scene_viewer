# Exec plan: picking and part hits

## Goal

Wire viewer taps to `flutter_scene` render-geometry raycasts and report stable
viewer `PartAddress` values through the existing `onPartTapped` callback.

## Source material

Promoted from the archived v2 planning source task T304 `raycast_to_part_hit`
and the MVP user story:

```text
Given user taps a primitive
When a raycast hit occurs
Then the callback returns a stable PartAddress
```

## Assumptions

- `flutter_scene` 0.18.1 provides `PerspectiveCamera.screenPointToRay(...)`,
  `Scene.raycast(...)`, and `SceneRaycastHit.primitiveIndex`.
- Picking should use render geometry, not physics colliders.
- The public v1 callback can continue to return `PartAddress` directly through
  the existing `FlutterSceneViewer.onPartTapped`.
- Duplicate node paths remain covered by existing part-registry diagnostics.
  This slice does not invent a new disambiguated public address format.

## Non-goals

- Do not add selection/focus visuals.
- Do not add marquee, lasso, hover, drag-select, editor, or game-engine
  interaction modes.
- Do not implement imported glTF cameras/lights.
- Do not add physics picking or colliders.
- Do not add a custom raycaster.

## Steps

1. Change: add an adapter-neutral picking method that accepts local pointer
   position, viewport size, and the current render camera.
   Verify: fake adapter widget test observes a tap request and receives a
   `PartAddress`.
2. Change: implement runtime adapter picking via `flutter_scene` camera
   `screenPointToRay(...)` and `Scene.raycast(...)`.
   Verify: focused adapter tests compile; GPU-gated smoke can exercise a real
   GLB hit when enabled later.
3. Change: make `FlutterSceneViewer` distinguish taps from orbit/pan/zoom
   gestures and invoke `onPartTapped` only for successful hits.
   Verify: widget tests cover tap callback and drag not firing a tap.
4. Change: update public docs and this plan log.
   Verify: docs identify picking as render-geometry raycast evidence, not
   physics or selection UI.

## Acceptance criteria

- [x] `onPartTapped` is invoked with `PartAddress(nodePath, primitiveIndex)`
      for a successful render-geometry hit;
- [x] taps without a hit do not invoke the callback;
- [x] orbit/drag gestures do not invoke the tap callback;
- [x] concrete `flutter_scene` raycast/camera types stay behind the internal
      adapter boundary;
- [x] picking remains scoped to static render geometry and does not add
      physics/editor scope.

## Progress log

- 2026-07-03: Created after completing plan 006 and auditing active plans
  001-005. All existing active-plan acceptance boxes were checked, but broader
  v1 scope still listed picking and `onPartTapped` existed without an
  implementation. Promoted the narrow v2 raycast-to-part-hit story into this
  active plan before coding, per repo routing rules.
- 2026-07-03: Added `FlutterSceneAdapter.pickPart(...)` with adapter-neutral
  local position, viewport size, and render camera inputs. The runtime adapter
  builds a concrete `flutter_scene.PerspectiveCamera`, uses
  `screenPointToRay(...)` and `Scene.raycast(...)`, and maps hit nodes back to
  `PartAddress(nodePath, primitiveIndex)`. `FlutterSceneViewer` now treats only
  tap slop gestures as pick candidates and cancels picking for orbit/drag,
  multitouch, scroll, and pan-zoom. Public/runtime docs were updated to label
  this as static render-geometry picking, not physics or selection UI.
- 2026-07-03: Acceptance criteria and verification are complete; archived this
  completed plan with the other finished v1 active plans.

## Verification log

- 2026-07-03: Red check before implementation:
  `flutter test test/viewer_widget_test.dart` failed as expected because tap
  tests never invoked the fake adapter picking method.
- 2026-07-03: Focused check after implementation:
  `flutter test test/viewer_widget_test.dart` passed, 27 tests.
- 2026-07-03: Focused check after updating the adapter fake used by model
  loading tests: `flutter test test/model_loader_test.dart
  test/viewer_widget_test.dart` passed, 37 tests and 3 existing GPU-gated
  skips.
- 2026-07-03: Full harness: `bash tools/run_checks.sh` passed. Output stages:
  repo lint passed; dart format check formatted 39 files with 0 changed;
  `flutter pub get` succeeded; `flutter analyze` reported no issues;
  `flutter test` passed 105 tests with 3 existing GPU-gated skips.
- 2026-07-03: Archive audit confirmed all acceptance criteria are checked and
  no unchecked checklist items remain in this plan.
- 2026-07-03: Post-archive full harness: `bash tools/run_checks.sh` passed
  after moving completed active plans to `docs/exec-plans/completed/`: repo
  lint passed; Dart format check reported 41 files with 0 changed;
  `flutter pub get` completed; `flutter analyze` reported no issues; and
  `flutter test` passed 108 tests with 3 existing GPU-gated skips.
