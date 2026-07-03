# Exec plan: environment controls and debug evidence

## Goal

Expose the existing `flutter_scene` environment/skybox capabilities through the
viewer API and add opt-in debug evidence snapshots that help inspect viewer
state without making benchmark or performance superiority claims.

## Assumptions

- `flutter_scene` 0.18.1 already provides `EnvironmentMap.studio()`,
  `EnvironmentMap.empty()`, `EnvironmentMap.fromAssets(...)`,
  `EnvironmentMap.fromUIImages(...)`, `EnvironmentMap.fromEquirectHdr(...)`,
  `Scene.environment`, `Scene.environmentIntensity`,
  `Scene.environmentTransform`, and `Scene.skybox`.
- The smallest v1 environment slice should expose the already-supported
  studio/empty/equirectangular asset environment path and optional environment
  skybox background. It should not require a custom shader, skymesh, or custom
  material pipeline.
- `.hdr` and `.exr` file decoding is separate from assigning an already decoded
  HDR environment. `EnvironmentMap.fromEquirectHdr(...)` accepts linear RGBA
  float pixels, not a raw file path. V1 can include a narrow environment-only
  decoder path that converts local/app-provided HDRI files into that pixel
  format without turning the viewer into a general texture decoder.
- Runtime Poly Haven download support is acceptable for V1 only as an explicit
  opt-in environment source with timeout/cache/diagnostic behavior. The studio
  default must remain local and deterministic.
- Debug evidence snapshots are local observability for development and smoke
  verification. They must not be described as benchmark results.
- 2026-07-03 first-slice assumption: runtime `flutter_scene` environment
  application remains deferred to step 3. This slice carries an
  adapter-neutral environment frame through the existing render-surface
  boundary so fake widget tests can verify studio defaults and asset changes.
- 2026-07-03 first-slice assumption: `ViewerEnvironment.empty()` exposes only
  `showSkybox`; its inherited intensity, rotation, and blur fields are fixed to
  zero because there is no image-based environment to tune.

## Non-goals

- Do not implement benchmark or comparison work. The benchmark harness remains
  deferred under `docs/exec-plans/deferred/benchmark_and_comparison.md`.
- Do not use `.hdr` or `.exr` decoding for runtime material texture overrides;
  the V1 decoder path is environment-only.
- Do not make external HDRI downloads implicit. Runtime Poly Haven support must
  be requested explicitly by the caller and must fail with diagnostics rather
  than changing the viewer default.
- Do not add cubemap-face asset sets unless `flutter_scene` exposes that path
  directly.
- Do not add custom sky shaders, world-aligned textures, parallax,
  displacement, or a custom material pipeline.
- Do not sample platform CPU, RAM, GPU memory, thermal state, or power in this
  slice; those require platform-specific diagnostics.
- Do not claim performance, power, or competitive superiority.

## Steps

1. Change: add public environment configuration values.
   Verify: unit tests cover equality/defaults and JSON-free construction.
   Suggested files:
   - Create `lib/src/viewer_environment.dart`.
   - Export it from `lib/flutter_scene_viewer.dart`.
   - Add `environment` to `FlutterSceneViewer`, defaulting to
     `ViewerEnvironment.studio()`.
   Suggested API shape:
   ```dart
   sealed class ViewerEnvironment {
     const ViewerEnvironment({
       this.intensity = 1.0,
       this.rotationRadians = 0.0,
       this.showSkybox = false,
       this.skyboxBlur = 0.0,
     });

     const factory ViewerEnvironment.studio({
       double intensity,
       double rotationRadians,
       bool showSkybox,
       double skyboxBlur,
     }) = ViewerStudioEnvironment;

     const factory ViewerEnvironment.empty({
       bool showSkybox,
     }) = ViewerEmptyEnvironment;

     const factory ViewerEnvironment.asset(
       String radianceImageAsset, {
       double intensity,
       double rotationRadians,
       bool showSkybox,
       double skyboxBlur,
     }) = ViewerAssetEnvironment;

     final double intensity;
     final double rotationRadians;
     final bool showSkybox;
     final double skyboxBlur;
   }
   ```

2. Change: pass environment configuration through the widget/adapter boundary
   without exposing concrete `flutter_scene` classes.
   Verify: widget tests with a fake adapter observe the default studio
   environment and a changed asset environment.
   Suggested files:
   - Modify `lib/src/internal/render_surface.dart` to add an
     adapter-neutral `RenderEnvironmentFrame`.
   - Modify `lib/src/internal/flutter_scene_adapter.dart` to add an adapter
     method such as `configureEnvironment(RenderEnvironmentFrame frame)`.
   - Modify `lib/src/viewer_widget.dart` to call the adapter when the
     environment changes and to request a render frame after successful
     configuration.
   Expected adapter-neutral shape:
   ```dart
   enum RenderEnvironmentKind { studio, empty, asset }

   final class RenderEnvironmentFrame {
     const RenderEnvironmentFrame({
       required this.kind,
       this.assetPath,
       this.intensity = 1.0,
       this.rotationRadians = 0.0,
       this.showSkybox = false,
       this.skyboxBlur = 0.0,
     });

     final RenderEnvironmentKind kind;
     final String? assetPath;
     final double intensity;
     final double rotationRadians;
     final bool showSkybox;
     final double skyboxBlur;
   }
   ```

3. Change: apply the environment in the runtime adapter.
   Verify: focused adapter tests compile, and GPU-gated smoke verifies an asset
   environment lights a representative GLB when an asset is available.
   Expected runtime mapping:
   - `studio` maps to `flutter_scene.EnvironmentMap.studio()`.
   - `empty` maps to `flutter_scene.EnvironmentMap.empty()`.
   - `asset` maps to `flutter_scene.EnvironmentMap.fromAssets(...)`.
   - `intensity` maps to `scene.environmentIntensity`.
   - `rotationRadians` maps to `scene.environmentTransform`.
   - `showSkybox` maps to `scene.skybox =
     flutter_scene.Skybox(flutter_scene.EnvironmentSkySource(...))`.
   - `skyboxBlur` maps to `EnvironmentSkySource(blurriness: skyboxBlur)`.
   - Asset load failures return diagnostics and preserve the previous
     environment.

3a. Change: add V1 HDR/EXR environment source support.
   Verify: unit tests cover construction/equality for the public source values,
   decoder tests cover small known `.hdr` / `.exr` fixtures when fixtures are
   added, and adapter tests verify decoded pixel environments are passed through
   without exposing `flutter_scene` classes.
   Notes:
   - Scope this to equirectangular environment lighting/skybox inputs.
   - Convert decoded pixels to the linear RGBA float data shape expected by
     `EnvironmentMap.fromEquirectHdr(...)`.
   - Unsupported file encodings, invalid dimensions, and decode failures must
     produce diagnostics and preserve the previous valid environment.
   - Do not add material texture HDR/EXR override support in this slice.

3b. Change: add explicit Poly Haven environment download support.
   Verify: network behavior is covered by fake HTTP/cache tests, not live
   downloads; one optional manual smoke may use a real downloaded HDRI when
   network access is intentionally available.
   Notes:
   - Verify the current Poly Haven API/URL shape before implementation.
   - Require an explicit caller-provided asset id or descriptor plus resolution
     choice; do not fetch anything as part of the studio default.
   - Apply the same byte limits, timeout, cancellation, cache, and diagnostics
     policy used by model/texture loading.
   - Downloaded HDRIs feed the same environment-only decoder path from step 3a.

4. Change: add an opt-in `ViewerStatsSnapshot` and callback for debug evidence.
   Verify: widget tests advance fake time and observe a snapshot without
   requiring GPU.
   Suggested files:
   - Create `lib/src/viewer_stats.dart`.
   - Export it from `lib/flutter_scene_viewer.dart`.
   - Add `ValueChanged<ViewerStatsSnapshot>? onStats` to
     `FlutterSceneViewer`.
   Minimum snapshot fields:
   ```dart
   final class ViewerStatsSnapshot {
     const ViewerStatsSnapshot({
       required this.framesPerSecond,
       required this.frameIntervalAverageMs,
       required this.frameIntervalMinMs,
       required this.frameIntervalMaxMs,
       required this.renderPolicyActive,
       required this.autoTick,
       required this.autoOrbit,
       required this.cameraDistance,
       required this.cameraPosition,
       required this.diagnosticsCount,
       this.lastDiagnosticCode,
       this.modelLoadDuration,
       this.modelByteSize,
       this.nodeCount,
       this.meshCount,
       this.materialCount,
       this.primitiveCount,
     });

     final int framesPerSecond;
     final double frameIntervalAverageMs;
     final double frameIntervalMinMs;
     final double frameIntervalMaxMs;
     final bool renderPolicyActive;
     final bool autoTick;
     final bool autoOrbit;
     final double cameraDistance;
     final List<double> cameraPosition;
     final int diagnosticsCount;
     final String? lastDiagnosticCode;
     final Duration? modelLoadDuration;
     final int? modelByteSize;
     final int? nodeCount;
     final int? meshCount;
     final int? materialCount;
     final int? primitiveCount;
   }
   ```

5. Change: feed the debug overlay from `ViewerStatsSnapshot`.
   Verify: existing overlay tests still pass and new tests assert frame-time
   and load/model counters appear when known.
   Notes:
   - Keep the overlay opt-in via `debugShowStatsOverlay`.
   - Label the values as debug evidence in docs.
   - Do not add CPU/RAM/GPU values until a platform-specific diagnostics plan
     exists.

6. Change: record load/model counters at the viewer boundary.
   Verify: model-loader tests assert load duration and byte size are captured
   for asset/network/bytes sources without changing load success semantics.
   Notes:
   - `ModelLoadResult` can carry optional evidence metadata such as
     `byteSize`, `loadDuration`, and adapter-provided primitive/material
     counts.
   - Missing counters should remain `null`, not fabricated.

7. Change: update docs and smoke harness.
   Verify: docs describe environment support accurately and the temporary
   harness can toggle `showSkybox`, `environmentIntensity`, and
   `debugShowStatsOverlay` without benchmark language.
   Suggested docs:
   - `docs/PUBLIC_API.md`
   - `docs/MATERIALS_AND_LIGHTING.md`
   - `docs/RUNTIME_GLB_PIPELINE.md`
   - `docs/exec-plans/deferred/benchmark_and_comparison.md`

8. Change: run verification.
   Verify:
   - `flutter test test/viewer_widget_test.dart`
   - targeted new environment/stats tests
   - `bash tools/run_checks.sh`
   - iPhone 17 Simulator smoke with a representative GLB and a visible
     environment/skybox when the asset path is configured

## Acceptance criteria

- [x] public API can select studio, empty, or equirectangular asset environment
      without exposing concrete `flutter_scene` classes;
- [x] public API can optionally show the active environment as a skybox
      background;
- [x] environment intensity and rotation are viewer-controlled and documented
      as lighting/presentation controls, not benchmark controls;
- [x] raw `.hdr` / `.exr` environment files are decoded only for environment
      lighting/skybox use, with diagnostics for unsupported inputs;
- [x] runtime Poly Haven environment downloads are explicit opt-in sources with
      timeout/cache/diagnostics and no implicit network default;
- [x] asset environment failures produce diagnostics and preserve the previous
      valid environment;
- [x] debug stats snapshots report FPS, frame interval samples, scheduler/tick
      state, camera state, diagnostics count, and known model/load counters;
- [x] debug stats are explicitly documented as smoke/debug evidence, not
      benchmark results;
- [x] CPU/RAM/GPU/power metrics remain out of this v1 slice unless a separate
      platform diagnostics plan is created;
- [x] benchmark comparison work remains deferred.

## Progress log

- 2026-07-02: Created after verifying that `flutter_scene` 0.18.1 already
  exposes environment and skybox primitives. Corrected the earlier assumption
  that HDR/skybox support necessarily required a custom shader or skymesh.
- 2026-07-03: Implemented the smallest verifiable first slice of steps 1 and 2:
  added public `ViewerEnvironment` studio/empty/asset variants, exported the
  API, added `environment` to `FlutterSceneViewer`, added adapter-neutral
  `RenderEnvironmentKind`/`RenderEnvironmentFrame`, threaded the frame through
  `AdapterRenderScene.buildView`, and requested a render frame when the
  environment value changes. Left runtime environment-map application,
  decoders, downloads, benchmark work, and debug stats for later plan steps.
- 2026-07-03: Implemented step 3 runtime environment mapping inside the
  `flutter_scene` adapter. `RenderEnvironmentFrame` now configures
  `Scene.environment`, `Scene.environmentIntensity`,
  `Scene.environmentTransform`, and optional `Scene.skybox` through
  `EnvironmentMap.studio()`, `EnvironmentMap.empty()`, and
  `EnvironmentMap.fromAssets(...)`; asset/runtime failures return diagnostics
  without replacing the previous scene environment. The viewer configures the
  environment after load success and after environment changes, then requests a
  render frame after successful configuration.
- 2026-07-03: Scope update after product discussion: V1 may include a narrow
  environment-only raw `.hdr` / `.exr` decoder and explicit Poly Haven HDRI
  download path. This does not change the renderer boundary, does not add
  material texture HDR/EXR overrides, and does not make network HDRI fetching
  part of the default studio environment.
- 2026-07-03: Verified the current Poly Haven API shape before implementation:
  the public API page points to `https://api.polyhaven.com`, the asset-list
  endpoint accepts `assets?t=hdris`, and `files/{assetId}` returns HDRI file
  descriptors under `hdri[resolution][hdr|exr]` with `url`, `size`, and hash
  metadata. Implemented raw environment source values, adapter-neutral
  raw/Poly Haven render frames, an environment-only Radiance RGBE `.hdr`
  decoder, a narrow uncompressed scanline OpenEXR decoder, explicit Poly Haven
  descriptor/download loading with User-Agent, timeout, byte-limit,
  cancellation, and cache behavior, and runtime adapter mapping to
  `EnvironmentMap.fromEquirectHdr(...)`. Failed raw/Poly Haven environment
  loads return typed diagnostics and do not replace the previous valid scene
  environment.
- 2026-07-03: Implemented structured debug evidence: public
  `ViewerStatsSnapshot`, `FlutterSceneViewer.onStats`, snapshot-fed
  `debugShowStatsOverlay`, frame interval/FPS samples, render-policy/tick
  state, auto-orbit state, camera state, diagnostics count/last code, and
  known model load/counter fields on `ModelLoadResult`. The docs describe
  these values as smoke/debug evidence only, not benchmark results.
- 2026-07-03: Acceptance criteria and verification are complete; archived this
  completed plan with the other finished v1 active plans.

## Verification log

- 2026-07-02: Not run yet; this plan records future implementation work only.
- 2026-07-02: Documentation/plan update verified with
  `bash tools/run_checks.sh`: repo lint, Dart format check, `flutter pub get`,
  `flutter analyze`, and `flutter test` passed; GPU-gated GLB import tests
  remained skipped in normal mode as documented.
- 2026-07-03: TDD red check: `flutter test test/viewer_environment_test.dart
  test/viewer_widget_test.dart` first hit sandbox-denied Flutter SDK cache
  writes; rerun with approval failed as expected because `ViewerEnvironment`,
  `RenderEnvironmentFrame`, `RenderEnvironmentKind`, and the widget
  `environment` parameter did not exist yet.
- 2026-07-03: Focused verification after implementation: `flutter test
  test/viewer_environment_test.dart test/viewer_widget_test.dart` passed with
  23 tests.
- 2026-07-03: Full verification: non-escalated `bash tools/run_checks.sh`
  passed repo lint then hit sandbox-denied Flutter SDK cache writes during Dart
  format. Rerun with approval initially failed `flutter analyze` with three
  `use_super_parameters` infos in `lib/src/viewer_environment.dart`; after
  fixing those constructors, `bash tools/run_checks.sh` passed: repo lint,
  Dart format check, `flutter pub get`, `flutter analyze` with no issues, and
  `flutter test` with 81 passed and 2 GPU-gated tests skipped.
- 2026-07-03: Step 3 red check: `flutter test test/viewer_widget_test.dart
  test/model_loader_test.dart` failed as expected because
  `FlutterSceneRuntimeAdapter.configureEnvironment`, test-only `debugScene`,
  and widget-side configuration calls did not exist yet; new widget assertions
  also observed that no environment frames were configured.
- 2026-07-03: Focused verification after runtime mapping: `flutter test
  test/viewer_widget_test.dart test/model_loader_test.dart` passed with 29
  tests and 3 GPU-gated skips.
- 2026-07-03: GPU-gated smoke verification:
  `flutter test --enable-impeller --enable-flutter-gpu
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true test/model_loader_test.dart`
  passed with 11 tests. The runtime adapter test loaded `Box.glb`, applied
  `packages/flutter_scene/assets/royal_esplanade.png` as an asset environment,
  set environment intensity, rotation, and `EnvironmentSkySource` skybox blur,
  and verified the resulting `Scene` state.
- 2026-07-03: Full verification after step 3:
  `bash tools/run_checks.sh` passed: repo lint, Dart format check,
  `flutter pub get`, `flutter analyze` with no issues, and `flutter test` with
  83 passed and 3 GPU-gated tests skipped in the default non-GPU run.
- 2026-07-03: Scope-update verification after adding V1 HDR/EXR/Poly Haven
  environment-source planning and V1 metadata/resolver notes:
  `python3 tools/repo_lint.py` passed; `bash tools/run_checks.sh` passed:
  repo lint, Dart format check with 0 changed files, `flutter pub get`,
  `flutter analyze` with no issues, and `flutter test` with 83 passed and
  3 GPU-gated tests skipped in the default non-GPU run.
- 2026-07-03: Step 3a/3b/4/5/6 red check: non-escalated `flutter test
  test/viewer_environment_test.dart test/environment_source_decoder_test.dart
  test/environment_source_loader_test.dart test/model_loader_test.dart
  test/viewer_widget_test.dart` first hit sandbox-denied Flutter SDK cache
  writes; rerun with approval failed as expected because raw environment
  constructors, decoder/loader classes, environment diagnostic codes,
  `AdapterModelStats`, `ModelLoadResult` evidence fields,
  `ViewerStatsSnapshot`, and `FlutterSceneViewer.onStats` did not exist yet.
- 2026-07-03: Focused verification after implementation and formatting:
  `flutter test test/viewer_environment_test.dart
  test/environment_source_decoder_test.dart
  test/environment_source_loader_test.dart test/model_loader_test.dart
  test/viewer_widget_test.dart` passed with 52 tests and 3 GPU-gated skips.
- 2026-07-03: Full verification after completing plan 006:
  non-escalated `bash tools/run_checks.sh` passed repo lint then hit
  sandbox-denied Flutter SDK cache writes during Dart format; rerun with
  approval initially failed `flutter analyze` with unnecessary imports and one
  unused test helper; after cleanup, `bash tools/run_checks.sh` passed: repo
  lint, Dart format check with 0 changed files, `flutter pub get`,
  `flutter analyze` with no issues, and `flutter test` with 102 passed and
  3 GPU-gated tests skipped in the default non-GPU run.
- 2026-07-03: Final post-log verification: `bash tools/run_checks.sh` passed
  after the active-plan audit/log update: repo lint passed, Dart format check
  reported 0 changed files, `flutter pub get` completed, `flutter analyze`
  reported no issues, and `flutter test` passed with 102 tests and
  3 GPU-gated skips.
- 2026-07-03: Archive audit confirmed all acceptance criteria are checked and
  no unchecked checklist items remain in this plan.
- 2026-07-03: Post-archive full harness: `bash tools/run_checks.sh` passed
  after moving completed active plans to `docs/exec-plans/completed/`: repo
  lint passed; Dart format check reported 41 files with 0 changed;
  `flutter pub get` completed; `flutter analyze` reported no issues; and
  `flutter test` passed 108 tests with 3 existing GPU-gated skips.
