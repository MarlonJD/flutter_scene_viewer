# Exec plan: static viewer baseline

## Goal

Turn the render-surface slice into a credible static GLB viewer baseline:
visible model pixels, usable model-derived camera fit, viewer-controlled
lighting/material presentation, and simulator evidence beyond a simple Box face.

## Current status

The first render surface exists and `Box.glb` appears in Simulator, but this is
not yet enough to call the package a useful viewer. The current evidence is a
simple red cube shown from an oblique camera angle. Before benchmark work
returns, this plan must prove that the viewer can inspect representative static
GLBs rather than only show that the render surface is wired.

## Non-goals

- Do not implement benchmark or comparison work. Benchmarking is deferred under
  `docs/exec-plans/deferred/`.
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
6. Change: expose adapter-derived model bounds internally and use them for
   `controller.fitCamera()`.
   Verify: pure bounds math tests plus widget/controller fit tests.
7. Change: validate viewer-controlled lighting/material presentation with at
   least one non-trivial static GLB fixture.
   Verify: simulator smoke evidence shows readable shaded/materialed geometry,
   not only a flat debug-looking face.
8. Change: document unsupported asset features encountered during smoke.
   Verify: plan log records whether failures are supported diagnostics or
   deferred importer capabilities.

## Acceptance criteria

- [x] loaded GLB root is attached to a `flutter_scene.Scene` internally;
- [x] ready viewer hosts a `flutter_scene.SceneView` through the adapter;
- [x] concrete `flutter_scene` classes do not leak into public API;
- [x] adaptive/on-demand policies avoid a permanent `SceneView` frame ticker
      when idle;
- [x] `controller.fitCamera()` updates the rendered camera and requests a
      frame;
- [x] iPhone 17 Simulator smoke test shows `test/fixtures/Box.glb` in the
      viewer area;
- [x] `fitCamera()` uses model-derived bounds instead of the unit-sphere
      fallback;
- [ ] at least one representative static GLB beyond `Box.glb` renders with
      readable material/lighting presentation;
- [ ] unsupported static-asset features discovered during smoke are recorded as
      diagnostics or explicit deferred capabilities;
- [ ] benchmark work remains outside active plans until the above viewer
      baseline is complete.

## Progress log

- 2026-07-02: Plan created for the render-surface slice. Assumptions: the first
  integration slice can use `SceneView(autoTick: false)` for adaptive/on-demand
  policies and rely on widget rebuilds/requested frames from 004;
  `RenderPolicy.always` may keep `SceneView` ticking because it is explicitly a
  permanent-render policy; model bounds still fall back to the 004 unit sphere
  until adapter-derived bounds are added later.
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
- 2026-07-02: Kept render/viewer baseline work as active plan 005 because it
  must precede fair benchmark work. The previous active benchmark plan moved to
  `docs/exec-plans/deferred/benchmark_and_comparison.md` and is deferred / not
  ready until a credible viewer baseline exists.
- 2026-07-02: Continued the 005 smoke polish by changing the internal default
  orbit camera from a straight-on front view to an oblique inspection view
  (`yaw = pi/4`, `pitch = pi/6`). This keeps `flutter_scene` camera details
  inside the adapter/internal boundary while making `Box.glb` read as a 3D
  object in simulator smoke instead of a flat red face. Verification:
  red/green targeted tests covered the default inspection angle and
  `fitCamera()` preserving that rendered camera angle.
- 2026-07-02: Reframed this active plan from narrow render-surface integration
  to a static viewer baseline. Benchmark work was removed from active plans and
  moved to `docs/exec-plans/deferred/benchmark_and_comparison.md` because the
  current viewer evidence is still only a simple Box render. Remaining active
  work: model-derived bounds, readable material/lighting presentation on a
  representative static GLB, and explicit diagnostics/deferred capability notes
  for unsupported static asset features.
- 2026-07-02: Added adapter-derived model bounds for camera fitting. The
  runtime adapter now exposes an adapter-neutral `AdapterModelBounds` computed
  from the loaded `flutter_scene.Node` AABB, and `FlutterSceneViewer.fitCamera`
  uses those bounds before falling back to the unit sphere. Verification:
  red/green widget test covered a non-origin bounds center/radius affecting the
  rendered camera; the GPU-gated GLB import test now asserts runtime bounds are
  available when enabled. Focused tests passed for `test/viewer_widget_test.dart`,
  `test/model_loader_test.dart`, and `test/orbit_camera_controller_test.dart`.
