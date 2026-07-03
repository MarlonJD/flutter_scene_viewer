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
- [x] at least one representative static GLB beyond `Box.glb` renders with
      readable material/lighting presentation;
- [x] unsupported static-asset features discovered during smoke are recorded as
      diagnostics or explicit deferred capabilities;
- [x] benchmark work remains outside active plans until the above viewer
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
- 2026-07-02: Added the next viewer-baseline slice for representative static
  GLB presentation. Assumptions: a synthetic in-repo fixture is acceptable for
  this baseline because the goal is viewer readability rather than third-party
  asset coverage; core glTF PBR factors, authored normals, authored UVs, and
  multiple nodes/materials are enough to prove the viewer is more than a
  diagonal single-material box; benchmark work remains deferred. Added
  `test/fixtures/MultiMaterialAssembly.glb`, generated by
  `tools/generate_multi_material_fixture.py`, with one assembly root, three
  mesh child nodes, and blue/gold/red metallic-roughness materials. Added an
  adapter-neutral `RenderLightingFrame` and passed `ViewerLighting` through the
  internal render boundary so the runtime adapter applies viewer-controlled
  studio exposure, environment intensity, and a single directional key light
  without leaking concrete `flutter_scene` classes into public API. Verification:
  red/green focused tests covered the new widget lighting handoff and the
  GPU-gated representative GLB import. Focused suites passed for
  `test/viewer_widget_test.dart`, `test/model_loader_test.dart`, and
  `test/orbit_camera_controller_test.dart`; the GPU-gated fixture import passed
  with `--enable-impeller --enable-flutter-gpu
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true`, logging `nodes: 4, meshes: 3,
  materials: 3, skins: 0, animations: 0`. iPhone 17 Simulator
  (iOS 26.5, simulator id `10C2CF77-CBA8-4948-ADD5-24C49D375059`) smoke reused
  the temporary harness at `/private/tmp/fsv_harness_20260702_render_surface`,
  retargeted it to `assets/MultiMaterialAssembly.glb`, launched with Impeller
  and Flutter GPU enabled, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_multimaterial_smoke.jpg`;
  verified locally that the viewer area contains visible blue, red, and gold
  shaded geometry rather than only status UI. No unsupported static asset
  extensions were encountered in this fixture; `flutter_scene` still exposes a
  synthetic runtime `root` wrapper above the real `SampleAssembly` node, which
  is recorded here as current importer shape rather than unwrapped in this
  slice.
- 2026-07-02: Extended the camera/readability smoke after trying network-hosted
  Khronos sample assets. Duck.glb loaded successfully over `ModelSource.network`
  in the iPhone 17 Simulator and logged `nodes: 3, meshes: 1, materials: 1,
  skins: 0, animations: 0`, but the screenshot showed the model cropped in the
  narrow phone viewport. Fixed that by making `OrbitCameraController.fitBounds`
  account for horizontal FOV when the viewport aspect ratio is narrow, adding a
  small viewer-side fit padding, and deferring `controller.fitCamera()` calls
  made from load-success listeners until the ready render surface has real
  layout constraints. Verification: red/green tests covered narrow-aspect fit
  math and early load-listener `fitCamera()` behavior; focused suites passed for
  `test/orbit_camera_controller_test.dart`, `test/viewer_widget_test.dart`, and
  `test/model_loader_test.dart`. DamagedHelmet.glb then loaded successfully from
  the Khronos raw GitHub URL in the same iPhone 17 Simulator and logged
  `nodes: 1, meshes: 1, materials: 1, skins: 0, animations: 0`; captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_network_smoke.jpg`
  and verified locally that the helmet is fully framed with readable textured
  PBR material detail. The earlier cropped Duck evidence is saved at
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_duck_network_cropped.jpg`
  as the regression prompt for the aspect-fit fix.
- 2026-07-02: Fixed simulator/trackpad camera interaction after manual smoke
  showed the DamagedHelmet viewer did not move reliably from the Simulator
  window. Root cause: the widget only used `GestureDetector.onScale*`, which
  covers touch drags in widget tests but does not handle pointer scroll /
  pan-zoom event paths used by desktop trackpads and some Simulator gestures.
  The ready viewer now uses raw pointer handling for single-pointer orbit,
  multi-pointer pan/zoom, pointer scroll orbit/zoom, and pointer pan-zoom.
  Verification: red/green widget tests now cover single pointer drag and
  pointer scroll changing the rendered camera; the DamagedHelmet harness was
  rebuilt and relaunched on the iPhone 17 Simulator for manual interaction.
- 2026-07-02: Follow-up manual interaction exposed that vertical drag felt
  inverted while horizontal orbit felt correct. Root cause: the pointer `dy`
  screen convention was still being negated before applying orbit pitch, so an
  upward drag increased the camera's world Y position. Fixed the sign for
  single-pointer drag and pointer pan-zoom while leaving horizontal orbit,
  pan, zoom, and fit math unchanged. Added an opt-in
  `debugShowStatsOverlay` development overlay that reports viewer-managed FPS,
  scheduler tick state, and `SceneView.autoTick` state in the temporary smoke
  harness. This is debug/smoke instrumentation only and does not reintroduce
  benchmark work or performance claims. Verification: red/green widget tests
  covered upward drag lowering the rendered camera and the debug stats overlay
  showing FPS/tick/autoTick state.
- 2026-07-02: Triaged the normal-map / ambient concern raised during
  DamagedHelmet and A1B32 smoke. `flutter_scene` already exposes/imports core
  PBR texture slots, so the missing viewer-side piece was runtime override
  plumbing rather than a renderer rewrite. Extended `MaterialPatch` with
  metallic-roughness, normal, emissive, and occlusion texture slots plus
  normal scale and occlusion strength, updated controller UV diagnostics to
  cover every texture override, and wired the runtime adapter to the matching
  `flutter_scene.PhysicallyBasedMaterial` setters while preserving reset
  behavior. Added opt-in `ViewerLighting.studio(ambientOcclusion: true)` to
  enable `Scene.ambientOcclusion` for studio lighting. Verification:
  red/green tests covered patch merge/JSON/range behavior, missing-UV
  diagnostics for normal texture overrides, and ambient-occlusion handoff
  through the render-lighting frame. This remains viewer-baseline support, not
  benchmark work, and does not add imported glTF lights/cameras.
- 2026-07-02: Rebuilt the temporary DamagedHelmet harness with
  `debugShowStatsOverlay: true` and
  `ViewerLighting.studio(ambientOcclusion: true)`, relaunched it on the
  iPhone 17 Simulator with Impeller and Flutter GPU enabled, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_fps_ao_smoke.jpg`.
  Verified locally that DamagedHelmet remains visible and fully framed, the
  development overlay appears in the viewer area, and adaptive rendering idles
  with `autoTick: off` once static. The overlay is smoke instrumentation only;
  FPS values here are not benchmark evidence.
- 2026-07-02: Added model-derived zoom distance limits after manual zoom
  discussion. `fitBounds` now derives an active minimum camera distance from
  the model radius to avoid zooming deep into the fitted model, and an active
  maximum distance from the fitted camera distance to avoid losing the model by
  zooming excessively far away. Verification: red/green camera-controller test
  covers clamping both extreme zoom-in and extreme zoom-out after fitting model
  bounds.
- 2026-07-02: Revisited normal-map intensity after simulator comparison showed
  `normalScale: 0.0` and `normalScale: 3.0` were visually almost identical
  when only the material scalar was changed. Root cause: `flutter_scene`
  currently packs `normalScale` into material uniforms but the standard
  fragment shader does not consume that value when perturbing normals. Updated
  the adapter so normal intensity is baked into runtime `normalTexture`
  overrides by scaling the raw normal-map XY channels and reconstructing Z
  before creating the GPU texture; `normalScale` without a normal texture
  override now reports an unsupported-feature diagnostic instead of silently
  doing nothing. Verification: added pure tests for normal-map RGBA scaling,
  rebuilt the DamagedHelmet harness with a runtime `- / text box / +`
  normalScale control, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_normal_comparison.jpg`.
  The baked comparison changed 27.08% of sampled model-area pixels between
  scale `0.0` and `3.0`, making the normal-map effect visibly stronger.
- 2026-07-02: Added repeatable camera/debug controls for comparing close-up
  material changes. `debugShowStatsOverlay` now includes auto-orbit state,
  camera distance, and camera position; `FlutterSceneViewer` has an opt-in
  viewer-managed horizontal `autoOrbit`; and
  `FlutterSceneViewerController` exposes `setCameraOrbit(...)` and
  `setCameraPosition(...)` without leaking concrete `flutter_scene` camera
  classes. Verification: red/green tests covered pure orbit camera set
  operations, controller forwarding/render requests, widget render-camera
  updates, and auto-orbit advancing the rendered camera.
- 2026-07-02: Locked runtime texture override semantics to UV0 /
  `TEXCOORD_0`. Adapter snapshots now carry texture coordinate channel
  metadata and `hasTexCoords` only reports true when channel 0 is available;
  a primitive with only channel 1 is not considered valid for runtime material
  texture override. This preserves room for future lightmap/static-lighting
  UV channels without accidentally using UV1 for albedo/normal/MR/emissive/
  occlusion overrides. Verification: red/green registry tests cover channel 1
  only returning false and channels 0+1 returning true.
- 2026-07-02: Fixed a reload trap found in the temporary normalScale harness.
  Root cause: the viewer treated any newly constructed `ModelSource` instance
  as a new source, so parent rebuilds for runtime material controls could
  reload the GLB if the app recreated `ModelSource.network(...)`. `ModelSource`
  now has value equality for network/asset sources and byte-list identity
  equality for bytes sources, and `FlutterSceneViewer.didUpdateWidget` uses
  equality rather than object identity. Verification: red/green tests covered
  source equality and an equivalent-source widget rebuild not reloading the
  model.
- 2026-07-02: Updated the temporary DamagedHelmet harness with stable
  `ModelSource`, runtime normalScale controls, auto-orbit toggle/speed controls,
  a close-camera button backed by `controller.setCameraOrbit(...)`, and the
  expanded debug overlay. iPhone 17 Simulator smoke launched
  `/private/tmp/fsv_harness_20260702_render_surface` with Impeller and Flutter
  GPU enabled, logged `Unpacking glTF (nodes: 1, meshes: 1, materials: 1,
  skins: 0, animations: 0)`, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_camera_debug_autoplay_smoke.png`.
  Verified locally that DamagedHelmet is visible, the overlay reports
  `FPS: 60`, `tick: active`, `autoTick: off`, `autoOrbit: on`, camera distance,
  and camera position while auto-orbit is running. Fresh required verification
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with the documented
  GPU-gated fixture import tests skipped in normal mode.
- 2026-07-02: Clarified the lit/unlit material boundary after review feedback.
  `flutter_scene` imports glTF unlit materials as `UnlitMaterial`, which does
  not respond to scene lights, and non-unlit glTF materials as
  `PhysicallyBasedMaterial`, which uses image-based lighting plus the scene
  directional light. The viewer now exposes `PartRecord.materialShadingMode`
  (`lit`, `unlit`, or `unknown`) through the part registry and the temporary
  DamagedHelmet harness displays the first primitive's shading mode. Studio
  lighting was made tunable with environment intensity and key-light
  direction/color/intensity for lit/PBR materials; runtime unlit-to-lit shader
  conversion remains out of this slice. Verification: red/green tests covered
  material shading mode propagation and lighting parameter handoff.
- 2026-07-02: Relaunched the DamagedHelmet harness on iPhone 17 Simulator with
  Impeller and Flutter GPU enabled after adding shading-mode display and
  stronger lit studio lighting (`environmentIntensity: 0.25`,
  `keyLightIntensity: 8`). Captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_shading_lit_smoke.png`.
  Verified locally that the model is visible and the harness reports
  `shading: lit`, confirming the sample is not imported as an unlit material;
  its readability is therefore controlled by lit PBR material inputs plus
  environment/key-light settings rather than by unlit-to-lit conversion.
- 2026-07-02: Incorporated the PBR-vs-lit review note. PBR is documented as
  the material parameter/texture model, while lit/unlit is the shader behavior
  that determines whether scene light affects a primitive. Added
  `MaterialShadingPolicy` as an import-time choice (`authored`, `forceLit`,
  `forceUnlit`) and wired it through `FlutterSceneViewer`, `ModelLoader`, and
  the internal adapter without exposing concrete `flutter_scene` material
  classes. The adapter converts only supported PBR/unlit material classes and
  preserves unknown material classes. Also documented the current lighting
  split: direct lighting is one directional key light; sky/indirect lighting is
  the scene environment/IBL intensity, not a separate public `SkyLight`
  component. Environment/HDRI viewer sources are now tracked by active plan
  `006_environment_and_debug_evidence.md`; imported GLB-authored HDRI remains
  out of scope.
- 2026-07-02: Verification after the material shading policy and lighting
  documentation updates: targeted `flutter test test/model_loader_test.dart
  test/viewer_widget_test.dart test/part_registry_test.dart` passed, then fresh
  required `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test`. The GPU-gated GLB
  fixture import tests remained skipped in normal test mode as documented.
- 2026-07-02: Tightened the default camera zoom bound after simulator evidence
  showed the debug close-camera preset entering the DamagedHelmet model. The
  orbit camera now uses a model-entry guard by default, clamping fitted camera
  distances outside the model bounding sphere (`radius * 1.05`). Added
  `allowCameraInsideModel` for applications that intentionally need interior or
  extreme close-up inspection; when enabled, the previous relaxed close
  inspection minimum (`radius * 0.25`) is used. Verification followed TDD:
  the new camera/widget tests failed first with the old `radius * 0.25`
  behavior and missing public widget parameter, then passed after the minimal
  implementation.
- 2026-07-02: iPhone 17 Simulator smoke after the camera-entry guard: relaunched
  `/private/tmp/fsv_harness_20260702_render_surface` with Impeller and Flutter
  GPU enabled, using the local package path. The harness logged the
  DamagedHelmet GLB import, rendered the model visibly, and captured
  `/private/tmp/fsv_harness_20260702_render_surface/iphone17_damaged_helmet_camera_entry_guard_smoke.png`.
  The overlay showed `FPS: 60`, `autoOrbit: on`, `dist: 2.64`, and
  `shading: lit`; the model was framed outside the geometry rather than inside
  the dark interior view from the prior screenshot. Cleaned up the leftover
  `flutter run` process after capture.
- 2026-07-02: Created follow-up active plan
  `006_environment_and_debug_evidence.md` for the next v1 slices discovered
  during material/lighting review: exposing `flutter_scene` environment/skybox
  primitives through the viewer API, and adding structured debug evidence
  snapshots. Benchmark comparison remains deferred and outside active
  implementation work.
