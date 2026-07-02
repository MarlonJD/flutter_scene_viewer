# Exec plan: render surface integration

## Goal

Render the loaded GLB through `flutter_scene.SceneView` inside
`FlutterSceneViewer` so the ready viewer area shows model pixels, not only a
success state.

## Non-goals

- Do not implement benchmark or comparison work from 006.
- Do not implement picking.
- Do not add VR controls.
- Do not import glTF cameras or lights.
- Do not claim performance or power savings.

## Steps

1. Change: expose an adapter-owned opaque render scene/root handle for the
   widget.
   Verify: widget test with a fake adapter can observe render host creation
   without GPU resources.
2. Change: build a `flutter_scene.Scene` internally in the runtime adapter and
   attach the loaded GLB root node to it.
   Verify: targeted adapter/model-loader tests compile with concrete
   `flutter_scene` usage contained in `lib/src/internal/`.
3. Change: render the adapter-owned scene via `flutter_scene.SceneView` in the
   ready widget while preserving 004 scheduler behavior.
   Verify: widget tests for ready render host creation and explicit-frame
   rebuilds.
4. Change: convert the existing orbit camera state to the adapter render camera
   internally and apply it from gestures and `controller.fitCamera()`.
   Verify: pure Dart camera conversion tests plus existing controller fit test.
5. Change: run simulator smoke verification with `test/fixtures/Box.glb`.
   Verify: plan log records iPhone 17 Simulator evidence.

## Acceptance criteria

- [x] loaded GLB root is attached to a `flutter_scene.Scene` internally;
- [x] ready viewer hosts a `flutter_scene.SceneView` through the adapter;
- [x] concrete `flutter_scene` classes do not leak into public API;
- [x] adaptive/on-demand policies avoid a permanent `SceneView` frame ticker
      when idle;
- [x] `controller.fitCamera()` updates the rendered camera and requests a
      frame;
- [x] iPhone 17 Simulator smoke test shows `test/fixtures/Box.glb` in the
      viewer area.

## Progress log

- 2026-07-02: Plan created as 006. Assumptions: the first integration slice can
  use `SceneView(autoTick: false)` for adaptive/on-demand policies and rely on
  widget rebuilds/requested frames from 004; `RenderPolicy.always` may keep
  `SceneView` ticking because it is explicitly a permanent-render policy;
  model bounds still fall back to the 004 unit sphere until adapter-derived
  bounds are added later.
- 2026-07-02: Implemented the render surface slice. Added an internal
  `AdapterRenderScene`/`RenderCameraFrame` seam, kept concrete
  `flutter_scene.Scene`, `SceneView`, and `PerspectiveCamera` usage inside
  `lib/src/internal/flutter_scene_adapter.dart`, and attached the imported GLB
  root node to an adapter-owned `flutter_scene.Scene`. The ready widget now
  builds the adapter render view, passes orbit camera state into it, disables
  `SceneView.autoTick` for adaptive/on-demand policies, and still uses the 004
  scheduler for explicit frames after material changes, gestures, and
  `fitCamera()`. Simulator smoke first exposed that adaptive mode could paint
  once before `Scene.initializeStaticResources()` was ready and then stop; fixed
  by awaiting `flutter_scene.Scene.initializeStaticResources()` before load
  success. Verification: targeted red/green tests were run for
  `test/orbit_camera_controller_test.dart` and `test/viewer_widget_test.dart`;
  targeted focused tests passed for `test/orbit_camera_controller_test.dart`,
  `test/viewer_widget_test.dart`, and `test/model_loader_test.dart`; required
  full check `bash tools/run_checks.sh` passed repo lint, format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with the documented
  GPU-gated GLB fixture test skipped in normal mode. iPhone 17 Simulator
  (iOS 26.5, simulator id `10C2CF77-CBA8-4948-ADD5-24C49D375059`) smoke used a
  temporary harness at `/private/tmp/fsv_harness_20260702_render_surface`,
  launched with Impeller and Flutter GPU enabled, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_box_smoke.png`;
  verified locally that the viewer area contains the red rendered Box GLB face
  rather than only status UI.
- 2026-07-02: Renumbered from 006 to 005 because render surface integration
  must precede fair benchmark work. The previous 005 benchmark plan moved to
  `006_benchmark_and_comparison.md` and is deferred / not ready until this
  visible render path exists.
- 2026-07-02: Continued the 005 smoke polish by changing the internal default
  orbit camera from a straight-on front view to an oblique inspection view
  (`yaw = pi/4`, `pitch = pi/6`). This keeps `flutter_scene` camera details
  inside the adapter/internal boundary while making `Box.glb` read as a 3D
  object in simulator smoke instead of a flat red face. Verification:
  red/green targeted tests covered the default inspection angle and
  `fitCamera()` preserving that rendered camera angle.
