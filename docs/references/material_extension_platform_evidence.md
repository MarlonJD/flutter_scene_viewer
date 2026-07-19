# Material Extension Platform Evidence

## Plan 016 renderer-native transmission and volume

The complete selected `KHR_materials_transmission`, `KHR_materials_volume`,
and glass `KHR_materials_ior` contract was verified locally on the `iPhone 17`
iOS 26.5 Simulator (`10C2CF77-CBA8-4948-ADD5-24C49D375059`) through Impeller
Metal. The harness used this package by path while the viewer resolved
published `flutter_scene` revision
`5dcf6fce7dc36719e64e536faba9538fe9fa1022` from its immutable Git dependency.
The viewer and harness have no `flutter_scene` path override. This is target
evidence for that exact renderer revision; it is not physical iOS, Android,
Web, packaging, or production-ready evidence.

The fixed state is
`tools/material_extension_acceptance/fixtures/plan016_controlled_comparison_state.json`
with SHA-256
`3fce01a715f596c513ee7d0f527638c3928cb44aeae32262e7dad16a912c9c96`.
It pins 16 synthetic and Khronos models, three `directOnly`/`iblOnly`/`combined`
passes, canonical per-model camera frames, exact HDR bytes, directional light,
exposure `1`, disabled AO and shadows, PBR Neutral tone mapping, sRGB output,
viewport/DPR, and the complete coordinate mapping. Stock Three.js r167 rendered
the same 48-state matrix and passed threshold calibration before the native
captures were analyzed.

Evidence is under
`tools/out/material_extension_acceptance/plan016_controlled_comparison/`:

- `threejs/evidence.json` records the exact Three.js version, source state,
  model/HDR hashes, renderer mapping, and 48 reference capture hashes;
- `ios_simulator/immutable-pin-5dcf6fce/evidence.json` records the immutable
  renderer SHA, Impeller Metal target facts, capture contract, diagnostics, and
  48 native capture hashes;
- `ios_simulator/immutable-pin-5dcf6fce/comparison_metrics.json` records every
  calibrated result and generated visual-artifact hash;
- the `visuals/` directory contains aligned crops, overlays, 4x difference
  heatmaps, and the inspected synthetic/Khronos comparison boards.

The capture completed all 48 stages at 1206 x 2622 and 60 fps. Synthetic
controls, AttenuationTest, GlassVaseFlowers, and ToyCar emitted no new
diagnostics. Khronos TransmissionTest emitted nine `ambiguousNodePath`
diagnostics from duplicate authored public node paths; the native importer
still supplied the model material state, and no shader, renderer, capability,
or material-adapter error occurred.

Every unchanged calibrated gate passed. Camera silhouette IoU was
`0.9804384077693391`. The iOS transmission, IOR, thickness, attenuation,
roughness, normal-map, and world-scale signals were respectively
`0.08125705944273869`, `0.0633010968406289`, `0.04963780634417499`,
`0.029937201205387957`, `0.046247913469156146`,
`0.018541633515716117`, and `0.05460480645429076`, each above the fixed
`0.015` gate. Cross-renderer mean/p95 color differences, IOR displacement,
attenuation chromaticity, and roughness blur also passed. The boards were
inspected locally and show coherent refraction, attenuation, roughness, normal,
texture-channel, node-scale, and clearcoat-composition trends without banding
or scene-color corruption. Independent BRDF, rasterization, and HDR-prefilter
implementations make this directional comparison, not pixel parity.

Evidence validation commands:

```sh
PLAN016_FLUTTER_SCENE_REVISION=5dcf6fce7dc36719e64e536faba9538fe9fa1022 \
PLAN016_DEPENDENCY_REACHABILITY=published-and-ls-remote-verified \
node tools/reference_renderers/threejs_material_extension_fixture/record_plan016_ios_simulator_evidence.mjs \
  tools/out/material_extension_acceptance/plan016_controlled_comparison/ios_simulator/immutable-pin-5dcf6fce
node tools/reference_renderers/threejs_material_extension_fixture/analyze_plan016_controlled_comparison.mjs \
  tools/out/material_extension_acceptance/plan016_controlled_comparison/ios_simulator/immutable-pin-5dcf6fce
```

Literal status: runtime capability is renderer-native and available at the
published immutable Git pin; iOS Simulator evidence is `verified locally`;
release maturity is `release pending`; production readiness is `false`;
physical iOS, Android, and Web are `not run`. Nested glass and order-independent
transparency remain explicit non-goals.

## Plan 015 renderer-native clearcoat

The complete `KHR_materials_clearcoat` contract was verified locally on the
`iPhone 17` iOS 26.5 Simulator (`10C2CF77-CBA8-4948-ADD5-24C49D375059`)
through Impeller Metal. The temporary harness used this package by path while
the viewer resolved published `flutter_scene` revision
`ccf7372428961ebe0abb053727fe443150547a74` from its immutable Git dependency.
This is target evidence for that exact renderer revision; it is not evidence
for a physical iOS device, Android, Web, packaging, or release readiness.

The fixed state used authored material shading, the repository's studio
lighting and environment defaults, environment intensity `1`, exposure `1`,
no ambient occlusion, and no shadow-casting key light, matching
`tools/material_extension_acceptance/fixtures/reference_state.json`. No
asset-specific material patch, forced roughness, extra highlight, environment
boost, texture bake, or generated UV was applied.

Reproduction commands:

```sh
python3 tools/stage_material_extension_fixtures.py --fetch-plan015-clearcoat
cd /private/tmp/plan015_clearcoat_harness
flutter run -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --enable-impeller --dart-define=MODEL_ID=clearcoat_test
flutter run -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --enable-impeller --dart-define=MODEL_ID=clearcoat_car_paint
flutter run -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --enable-impeller --dart-define=MODEL_ID=toycar
xcrun simctl io 10C2CF77-CBA8-4948-ADD5-24C49D375059 screenshot <capture-path>
```

The temporary app also set `FLTEnableFlutterGPU=true` in its iOS
`Info.plist`. ClearCoatTest and ClearCoatCarPaint used the adapter's asset-bounds
fit. ToyCar's authored root scale exposed a separate bounds-fit framing defect,
so its four views used the fixed target `[0, 0, 0]` and distance `0.085`; this
changed framing only, not the material, lighting, environment, or renderer
state. All three assets loaded and rendered without an exception or a
clearcoat diagnostic:

| Asset | Runtime facts | Result |
| --- | --- | --- |
| ClearCoatTest | 33 nodes, 27 meshes, 19 materials, 27 addressable parts, 0 diagnostics | Factor zero/full, factor texture, roughness texture, and independent coat-normal matrix rendered through the native contract. |
| ClearCoatCarPaint | 1 node, 1 mesh, 1 material, 1 addressable part, 0 diagnostics | Rough microflake base remained visible beneath the smoother coat response. |
| ToyCar | 11 nodes, 3 meshes, 3 materials, 1 diagnostic | Coated paint and transformed core textures rendered together. The sole diagnostic was the asset's optional unsupported `KHR_materials_transmission` request on `Glass#0`; it used the permitted core fallback and was not a clearcoat failure. |

The source GLBs are pinned in the manifest to Khronos Sample Assets commit
`2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf`. Captures are 1206 × 2622 PNGs
under
`tools/out/material_extension_acceptance/plan015_renderer_native_clearcoat/ios_simulator/`:

| Capture | SHA-256 |
| --- | --- |
| `clearcoat_test_front.png` | `528a6cb8c110c84aaa8a320cbd9615137750dcc5987984a3f8886b4207344364` |
| `clearcoat_test_left.png` | `528a6cb8c110c84aaa8a320cbd9615137750dcc5987984a3f8886b4207344364` |
| `clearcoat_test_right.png` | `91b1d7180c9c1997faee42c7a01fcef5e74cccb37a644fe3c1852581f63f1769` |
| `clearcoat_test_back.png` | `91b1d7180c9c1997faee42c7a01fcef5e74cccb37a644fe3c1852581f63f1769` |
| `clearcoat_car_paint_front.png` | `e8e2db36a139325f59bf19efe458d43a23da90f6196718d5c41fa98f56cf7123` |
| `clearcoat_car_paint_left.png` | `e8e2db36a139325f59bf19efe458d43a23da90f6196718d5c41fa98f56cf7123` |
| `clearcoat_car_paint_right.png` | `7dfe32cf3619e99c93a58d76dfd7dc72999fd1624878d1376bab7fcc25bde77c` |
| `clearcoat_car_paint_back.png` | `7dfe32cf3619e99c93a58d76dfd7dc72999fd1624878d1376bab7fcc25bde77c` |
| `toycar_front.png` | `7459fcaecf08597407f009d9021df0fd653c47de1b44069ec6dec347d6b8c3b3` |
| `toycar_left.png` | `659db951f770c3bf71f966c053453e2bb7f33689d19b93b969467340e51747d3` |
| `toycar_right.png` | `1f95e7ecbf42c1a94c33873d6f0ddd009b257c8920ccfe08946ceaa3d76aa529` |
| `toycar_back.png` | `5b9da53e8a2d8c4cbf6a7bdb0dfdc447c4b0d81c6b24d1948ae096030be02840` |

Literal status: renderer capability at the published immutable Git pin is
`verified locally` on the iOS Simulator; release maturity is `release
pending`; production readiness is `false`; physical iOS, Android, and Web are
`not run`.

### Controlled Three.js comparison

A follow-up audit froze the stricter
`tools/material_extension_acceptance/fixtures/plan015_controlled_comparison_state.json`
and rendered all three assets in `directOnly`, `iblOnly`, and `combined`
passes with both stock Three.js r167 and the iPhone 17 Simulator. Both sides
used the same model bytes, canonical per-model bounding sphere, 60° vertical
FOV, yaw `pi/4`, pitch `pi/12`, generated Radiance HDR bytes, directional
light, exposure `1`, disabled AO and shadows, PBR Neutral, and sRGB output.

flutter_scene mirrors imported glTF roots on Z. The Three.js reference
therefore mirrors the camera, directional-light travel direction, and HDR
longitude together. The audit rejected two earlier invalid comparisons: a
Three.js fit padding of `1.0` instead of the viewer's `1.15`, and an HDR-only
handedness correction. ToyCar also exposed the viewer's known authored-root-
scale bounds-fit defect; the final comparison supplies the same canonical
frame directly to both renderers instead of accepting their independent
automatic bounds calculations.

The resulting ClearCoatCarPaint `directOnly` highlight is colocated and has
the same lobe trend. The three synthetic HDR panels have the same orientation
and ordering in `iblOnly` and remain consistent in `combined`. Their centers,
blur, and brightness are not pixel-identical because stock Three.js uses a
roughness-dependent reflection-vector bend plus PMREM, while flutter_scene
uses its own reflection direction and GGX prefilter. That boundary is recorded
as controlled directional evidence, not hidden as a pixel-parity claim.

Evidence and the zoomed board are under
`tools/out/material_extension_acceptance/plan015_controlled_comparison/`:

- `threejs/evidence.json`: Three.js source state, renderer mapping, model and
  HDR hashes, and nine capture hashes.
- `ios_simulator/evidence.json`: Impeller Metal target facts, the same state,
  nine capture hashes, and exact diagnostics.
- `clearcoat_car_paint_comparison_board.png`: direct/IBL/combined comparison.

ClearCoatTest and ClearCoatCarPaint retained zero diagnostics in every pass.
ToyCar retained exactly one explicit unsupported
`KHR_materials_transmission` diagnostic on `Glass#0`; it remains useful for
clearcoat composition and camera framing, but it is not a clean transmission-
parity reference.

## 011 Target

| Target | Flutter renderer | Glass shader load | Glass visual matrix | Clearcoat shader load | Clearcoat visual matrix | Real-asset status | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iOS Simulator | Impeller + Flutter GPU | verified locally | verified locally | verified locally | verified locally | verified locally | candidate-only; evidence verified locally | Primary 011 target evidence ran on the `iPhone 17` iOS Simulator through a temporary `integration_test` app that depends on this package by path. Fixture evidence, ToyCar real-asset evidence, and Task 012 acceptance metrics are durable local evidence for the repo-owned custom shader candidate; simulator evidence is not physical-device release readiness. |

## Deferred Targets

| Target | Renderer | Status | Notes |
| --- | --- | --- | --- |
| macOS local | Impeller + Flutter GPU | not run | Deferred from 011; local host visual smokes are development evidence only and are not production target evidence. |
| iOS physical device | Impeller + Flutter GPU | not run | Deferred to a later device evidence plan. |
| Android emulator/device | Impeller + Flutter GPU or platform backend | not run | Deferred to a later platform hardening plan. |
| Web | WebGL2 or future web backend | not run | Deferred to a later platform hardening plan. |

## Commands

The package-level focused test still documents the expected evidence case, but
it runs in the host Flutter tester in this repository and reports
`TargetPlatform.android` even when `-d` points at a simulator:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Actual iOS Simulator evidence was collected with a temporary Flutter
`integration_test` app under `/private/tmp/fsviewer_ios_evidence_app`:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator for the glass and synthetic
clearcoat visual matrices. Follow-up ToyCar evidence passed on the same
simulator with authored glass and clearcoat in one real GLB. These runs make
the iOS Simulator evidence `verified locally`; the repo-owned custom shader
path remains `candidate-only`. Physical iOS, Android material rendering, and
Web material rendering remain `not run`.

Shader preflight and the evidence record answer different questions. Preflight
proves that required package shader entries are available and routable. It does
not prove Khronos correctness or physical-device release readiness, and it does
not promote maturity or write target evidence into the static policy.

Artifacts:

```text
tools/out/fsviewer_ios_simulator_glass_matrix.png
tools/out/fsviewer_ios_simulator_clearcoat_matrix.png
tools/out/fsviewer_ios_simulator_material_extension_matrix.json
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_baseline.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_enhanced.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_diff.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat.json
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_side_by_side.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_baseline.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_enhanced.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_side_by_side.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json
```

Recorded metrics:

```json
{
  "target": "iOS Simulator",
  "backendKind": "flutterSceneCustomShader",
  "status": "verified locally",
  "platform": "iOS",
  "glass": {
    "transmission0Spread": 14,
    "transmission1Spread": 239,
    "iorDelta": 5.111805555555556
  },
  "clearcoat": {
    "zeroHighlight": 242,
    "fullHighlight": 254,
    "smoothPeak": 254,
    "roughPeak": 250,
    "baseMaterialPreserved": true
  },
  "realModelClearcoat": {
    "fixture": "DamagedHelmet",
    "status": "historical candidate-only",
    "fullFrameMeanAbsoluteDelta": 6.942640817901235,
    "colorRegionSpread": 220,
    "clearcoatRegionHighlight": 235,
    "note": "Manual-clearcoat iOS Simulator evidence passes the smoke thresholds but still shows overly stylized/striped behavior on a real textured GLB, so it is not production-ready."
  },
  "realModelGlassAndClearcoat": {
    "fixture": "ToyCar",
    "status": "verified locally",
    "sourceAuthoredClearcoatExtension": true,
    "sourceAuthoredTransmissionExtension": true,
    "fullFrameMeanAbsoluteDelta": 0.8378311471193416,
    "colorRegionSpread": 249,
    "highlight": 248,
    "note": "The follow-up iOS Simulator run preserves the ToyCar source PBR body material, adds a clearcoat overlay primitive, and applies the glass shader to the authored Glass node. This is durable verified-locally evidence for a candidate-only repo-owned custom shader path."
  }
}
```
