# flutter_scene capability notes

This file records assumptions that the adapter must verify against the installed
`flutter_scene` version.

Known target capabilities:

- runtime GLB import through `Node.fromGlbBytes`;
- PBR material class with base color, metallic, roughness, normal, emissive,
  occlusion, alpha, and double-sided controls;
- SceneView widget for rendering;
- raycasting through scene geometry;
- Flutter GPU/Impeller native rendering and WebGL2 web backend.

V1 release-blocker capability to verify:

- real glTF glass support through `KHR_materials_transmission`,
  `KHR_materials_ior`, and `KHR_materials_volume`, including transmission or
  refraction behavior, Fresnel/IOR behavior, and volume attenuation. Alpha
  blending alone is not sufficient.
- real glTF clearcoat support through `KHR_materials_clearcoat`, including
  clearcoat factor, roughness, and texture/normal inputs where available.
  Lowering base roughness alone is not sufficient.

Adapter implementation must keep direct `flutter_scene` imports isolated so API
breakage is easy to repair.

## Local verification note

On 2026-07-02, `flutter_scene` 0.18.1 was present in the local pub cache and
documents `Node.fromGlbBytes(Uint8List)` in `lib/src/node.dart`.

Importing `package:flutter_scene/scene.dart` failed on Flutter
3.45.0-1.0.pre-38 because the local Flutter GPU API did not expose newer
symbols required by `flutter_scene` 0.18.1, including `gpu.VertexLayout`,
texture compression family types, and mip-level texture APIs.

The import compiles on Flutter master 3.46.0-1.0.pre-403 with engine hash
`6bef0a77783127874e0aedefe6aaf5abd42b63ed`; the runtime adapter now calls
`Node.fromGlbBytes(bytes)` after initializing the shader library and material
static resources.

The valid import path was verified with `test/fixtures/Box.glb` from Khronos
glTF Sample Models using `--enable-impeller`, `--enable-flutter-gpu`, and
`--dart-define=FLUTTER_SCENE_GPU_TESTS=true`.

On 2026-07-03, a local source audit of `flutter_scene` 0.18.1 from
`.dart_tool/package_config.json` found that
`lib/src/material/physically_based_material.dart` exposes core
metallic-roughness PBR fields, alpha mode/cutoff, double-sided behavior through
the base material, and per-material environment overrides. It does not expose
transmission, IOR, thickness, attenuation, clearcoat factor, clearcoat
roughness, or clearcoat normal fields.

The runtime material path in `lib/src/runtime_importer/material_builder.dart`
maps core PBR textures/factors, normal, occlusion, emissive, alpha,
double-sided, and `KHR_materials_unlit`. The glTF parser in
`lib/src/importer/src/gltf/parser.dart` only checks material extensions for
`KHR_materials_unlit`, and `lib/src/importer/src/gltf/types.dart` has no fields
for `KHR_materials_transmission`, `KHR_materials_ior`,
`KHR_materials_volume`, or `KHR_materials_clearcoat`.

Current `flutter_scene_viewer` glass and clearcoat patch fields are therefore
diagnostic-only by default, and the viewer does not pretend upstream
`flutter_scene` exposes native extension fields. Task 012 accepts the
repo-owned custom shader backend as the current production route for verified
targets: production policy can route opted-in glass and clearcoat intent
through package-local custom shader paths after shader preflight, while
upstream renderer/importer support remains a future PR path.

## 2026-07-03 `.fmat` packaging smoke

Task 7 added `assets/materials/fsviewer_debug_tint.fmat` and
`hook/build.dart` with `buildMaterials(...)` for the debug tint material.
Local non-GPU verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart
```

Result: passed with 1 GPU-gated skip. The skip is expected unless
`FLUTTER_SCENE_GPU_TESTS=true`, Impeller, Flutter GPU, and build-hook
generated `.fmat` DataAssets are available.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Initial result before the local config fix: failed.
`flutter_scene.loadFmatMaterial` failed with
`No DataAssets-backed .fmat material for source
"assets/materials/fsviewer_debug_tint.fmat" was found`. `flutter config
--list` reported `enable-dart-data-assets: (Not set)`.

Follow-up: Dart DataAssets were enabled with:

```sh
flutter config --enable-dart-data-assets
```

The hook then generated:

- `build/shaderbundles/materials.shaderbundle`
- `build/shaderbundles/materials.fmat.json`
- `build/shaderbundles/materials.index.json`

`flutter test` still did not expose the generated DataAssets index through the
unit-test root asset manifest, so the smoke was switched to the documented
`PreprocessedMaterial` shaderbundle + sidecar path and the generated
shaderbundle/sidecar were listed as test assets. Local GPU-gated verification
then passed:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 test. This proves minimal `.fmat` shader build/load evidence.
At the time it was not production glass support. Task 012 supersedes that
status for the verified iOS Simulator scope by accepting the repo-owned custom
shader backend after shader preflight and real-asset/reference evidence.

## 2026-07-03 experimental transmission backend smoke

Task 8 added `assets/materials/fsviewer_transmission.fmat` and the internal
`FlutterSceneMaterialExtensionBackend`. The backend uses public
`flutter_scene` APIs: `ShaderMaterial`, `RenderTexture`, `RenderView.layerMask`,
and `Node.layers`. Supported experimental transmission patches are routed into
a separate shader-material path with `isOpaqueOverride = false`; alpha blend is
not used as a glass fallback.

Local CPU verification ran:

```sh
flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 6 tests with 3 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 8 tests with 2 visual-smoke skips. This proves that the debug
tint, transmission, and clearcoat `.fmat` shaders compile into the generated
shader bundle, that `FSViewerTransmission` and `FSViewerClearcoat` load, and
that CPU state transitions assign a transmissive layer, background render view,
background render texture, non-opaque glass `ShaderMaterial`, and opaque
clearcoat `ShaderMaterial`; it also verifies mounted render items are refreshed
when the backend replaces or restores the primitive material.

Task 8 visual evidence was verified locally with:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_transmission_smoke.png`. The screenshot shows a
striped-behind-glass fixture through the experimental transmission shader; the
test asserts channel spread plus red/green/blue dominant samples so the evidence
does not rely on alpha alone. During debugging, the root issue was a mounted
render-layer refresh bug in the viewer backend: replacing
`MeshPrimitive.material` after mount did not update `flutter_scene`'s retained
`RenderItem.material` until the node mesh wrapper was refreshed. A direct
`Scene.render` / `PictureRecorder` capture is used for the smoke because local
`SceneView` widget teardown hung after producing the screenshot.

## 2026-07-03 experimental clearcoat backend smoke

Task 9 added `assets/materials/fsviewer_clearcoat.fmat` and extended the
internal `FlutterSceneMaterialExtensionBackend`. The backend uses public
`flutter_scene` APIs: `ShaderMaterial`, generated shader bundles, and
`ShaderMaterial.useEnvironment = true` for environment IBL bindings. Supported
experimental clearcoat patches are routed into an opaque shader-material path;
lowering base roughness is not used as a clearcoat fallback.

Local CPU verification ran:

```sh
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart test/viewer_controller_material_test.dart test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 38 tests with 4 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 8 tests with 2 visual-smoke skips. This proves that
`FSViewerClearcoat` compiles into the generated shader bundle, loads through
`loadShaderLibraryAsync`, and is configured as an opaque environment-using
`ShaderMaterial`.

Task 9 visual evidence was verified locally with:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "clearcoat shader renders distinct second specular lobe smoke" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_clearcoat_smoke.png`. The screenshot compares a base glossy
sphere, clearcoat `0.0`, and clearcoat `1.0` with low clearcoat roughness. The
test masks out background pixels and verifies that the clearcoat `1.0` object
has a stronger object highlight than clearcoat `0.0`, so the evidence does not
come from a skybox/background sample.

## 2026-07-03 production glass visual matrix candidate

Task 011 added a GPU-gated glass visual matrix for the package-local
transmission shader. The matrix renders transmission `0.0`, `0.5`, and `1.0`
against the same striped background and compares IOR `1.0` with a higher IOR
scene using trend metrics rather than pixel-perfect equality.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production glass visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_glass_matrix.png`. This is local host visual evidence for
the package-local shader behavior. iOS Simulator evidence is recorded
separately; Task 012 uses that evidence plus acceptance metrics for the
`flutterSceneCustomShader` production scope.

## 2026-07-03 production clearcoat visual matrix candidate

Task 011 upgraded `FSViewerClearcoat` to a lit `.fmat` material. Follow-up
visual-quality hardening changed it from an opaque replacement material into a
translucent shared-geometry overlay that preserves the source primitive's PBR
material and adds a separate clearcoat lobe through `material.emissive`. The
runtime path loads the shader and sidecar metadata into
`PreprocessedMaterial`; direct `ShaderMaterial` rendering of a lit `.fmat`
shader crashed the local Flutter tester because the lit engine uniform block is
not bound by that wrapper.

Local non-GPU verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 11 tests with 8 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production clearcoat visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_clearcoat_matrix.png`. The matrix verifies clearcoat
factor, clearcoat roughness, clearcoat texture influence, and clearcoat normal
trends on the local host GPU path. This is still local host candidate evidence;
iOS Simulator evidence is recorded separately and is the scoped production
evidence used by Task 012 for `backendKind: flutterSceneCustomShader`.

## 2026-07-04 ToyCar iOS Simulator real-asset evidence

Follow-up visual-quality hardening used the Khronos ToyCar GLB because the same
asset has authored clearcoat and transmission materials. The backend applies
clearcoat to the ToyCar body through the translucent overlay path and applies
transmission to the authored `Glass` node. This validates that the source PBR
body material remains visible while the custom shader glass path is active in
the same diagonal real-asset view.

Actual iOS Simulator verification ran through the temporary
`/private/tmp/fsviewer_ios_evidence_app` integration test:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator and wrote
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_baseline.png`,
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_enhanced.png`,
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_side_by_side.png`,
and `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json`. Metrics:
frame delta `0.8378311471193416`, color spread `249`, highlight `248`.
Task 011 recorded this as candidate evidence; Task 012 supersedes that status
for the verified iOS Simulator scope.

## 2026-07-03 shared GLB and three.js reference fixture candidate

Task 011 added a shared material-extension GLB and a three.js reference
renderer harness. Flutter visual smoke writes
`tools/out/fsviewer_material_extension_reference_fixture.glb` alongside the
Flutter glass and clearcoat matrix screenshots. The reference harness loads the
same GLB through three.js `GLTFLoader` and records trend metrics in
`tools/out/material_extension_reference_metrics.json`.

Local Flutter fixture generation ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "shared GLB for reference renderers" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote the shared GLB plus
Flutter matrix image paths.

Local three.js reference verification ran:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Result: install passed with no vulnerabilities; render passed and wrote
`tools/out/reference_threejs_glass_matrix.png`,
`tools/out/reference_threejs_clearcoat_matrix.png`, and
`tools/out/material_extension_reference_metrics.json`. Metrics recorded
three.js transmission spread increasing from `24` to `37`, IOR delta
`32.43768240567021`, clearcoat highlight increasing from `242` to `244`, and
rough clearcoat peak `242` below smooth peak `244`.

## 2026-07-03 iOS Simulator candidate evidence status

The package-level focused test was run locally and still skipped because it
executes in the host Flutter tester:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: skipped with `iOS Simulator evidence requires an iOS test target;
current target is android.`

Actual iOS Simulator evidence was then collected with a temporary Flutter
`integration_test` app depending on this package by path:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator and wrote
`tools/out/fsviewer_ios_simulator_glass_matrix.png`,
`tools/out/fsviewer_ios_simulator_clearcoat_matrix.png`, and
`tools/out/fsviewer_ios_simulator_material_extension_matrix.json`.
Recorded iOS Simulator metrics: glass transmission spread increased from `14`
to `239`, IOR delta was `5.111805555555556`, clearcoat highlight increased
from `242` to `254`, and rough clearcoat peak `250` stayed below smooth peak
`254`.

Follow-up real-asset review initially kept the package-local glass and
clearcoat paths as candidate visuals. Task 012 supersedes that decision by
accepting the repo-owned custom shader backend as the production path for the
verified iOS Simulator scope.

macOS, Android, Web, and physical iOS device evidence are deferred/not run for
Task 011.

## 2026-07-04 transmission shader source hardening

Task 012 reviewed public renderer material models before promoting the
repo-owned custom shader route. Filament's PBR/material documentation supports
the same direction used for glass: separate surface reflection from transmitted
energy through IOR/Fresnel behavior, and treat transparent-surface blending as
premultiplied output. SceneKit's public SDK headers do not expose a
`KHR_materials_transmission` equivalent material field, but they do expose
transparent material/blend controls, shader-surface `view`, `normal`,
`transparent`, and `fresnel` fields, and clearcoat surface fields. SceneKit is
therefore useful as a public surface-shader reference, not as a native
transmission backend.

`assets/materials/fsviewer_transmission.fmat` now derives normal-incidence
reflectance from IOR, computes a `TransmissionViewFresnel` term, reduces
transmitted background energy by that Fresnel term, applies
`BeerLambertAttenuation` as `attenuationColor^(thickness /
attenuationDistance)`, and writes premultiplied RGB through
`PremultipliedTransmissionColor`. This remains bounded screen-space glass, not
path-traced volume transport or order-independent transparency.

Focused verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "separates Fresnel"
```

Result: the first non-escalated run failed because Flutter tried to write SDK
cache files outside the workspace. The escalated red run failed as expected
because the transmission shader did not yet contain the Fresnel/absorption
helpers. After the shader update, the focused test passed.
