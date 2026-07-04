# Material Extension Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

## Goal

Move glass/transmission and clearcoat from package-local candidate evidence to
honest production support for the explicitly verified target scope.

## Architecture

Task 012 was revised on 2026-07-04: the repo-owned `flutter_scene` custom
shader backend is the production path for the explicitly verified target
scope. Do not wait for upstream renderer-native material fields before moving
the package forward. Production support must be backed by package shader
preflight, strict glTF material-extension semantics, real-asset visual
acceptance, and repeatable iOS evidence. Renderer-native upstream support
remains a future integration/PR path and may bypass local shaders if it becomes
available later.

## Tech Stack

Dart, Flutter, `flutter_scene`, glTF 2.0 material extension semantics,
Flutter GPU/Impeller, iOS Simulator integration tests, physical iOS evidence
before public release claims, three.js reference renders, `flutter test`,
`flutter drive`, `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`.

---

## Current State

- Task 011 left package-local glass and clearcoat as `candidate-only`, but Task
  012 now accepts the repo-owned custom shader backend as the production path
  for verified targets.
- Glass uses bounded screen-space background refraction and does not provide
  renderer-native transmission, order-independent transparency, nested glass,
  or full path-traced volume behavior.
- Clearcoat uses a translucent shared-geometry overlay that preserves source
  PBR material detail, but it is not an integrated renderer-native second
  specular lobe.
- ToyCar iOS Simulator evidence demonstrates that both features can be shown
  together without destroying the source material.
- three.js reference comparison exists and is directional, not pixel-perfect.
- The package may claim production support only for the repo-owned custom
  shader backend and only for targets with matching evidence labels.

## Production Definition

Production support for this plan means all of the following are true:

- The active backend is either the repo-owned `flutterSceneCustomShader`
  backend after shader preflight or a future renderer-native backend exposing:
  - transmission factor and texture;
  - IOR;
  - thickness;
  - attenuation color and distance;
  - clearcoat factor and texture;
  - clearcoat roughness factor and texture;
  - clearcoat normal texture and scale.
- The GLB importer or adapter preserves authored `KHR_materials_transmission`,
  `KHR_materials_ior`, `KHR_materials_volume`, and
  `KHR_materials_clearcoat` inputs without inventing unsupported values.
- Runtime `MaterialPatch` overrides route to the production custom shader
  backend for the current verified scope, or to native material fields if a
  future renderer-native contract becomes available.
- UV0/TEXCOORD_0 remains required for every texture-bearing authored or
  runtime input. UV1 is not substituted and UVs are not generated.
- Alpha blend is not reported as glass.
- Low roughness is not reported as clearcoat.
- A real-asset visual acceptance corpus passes against the iOS custom-shader
  backend and three.js/Khronos Sample Viewer directional reference metrics.
- iOS Simulator evidence passes first. Physical iOS, macOS, Android, and Web
  remain deferred/not run unless explicitly scoped into this plan later.

## Non-goals

- Do not build a custom renderer or shader graph.
- Do not copy external renderer shader/runtime source.
- Do not promote shader behavior by threshold tuning alone; require real asset
  and reference-renderer directional evidence.
- Do not fake native renderer capability with reflection-only field names.
- Do not broaden target evidence to macOS, Android, Web, or physical iOS until
  the iOS Simulator custom-shader path passes.
- Do not add production docs before evidence exists.

## File Structure

- Modify `lib/src/material_extension_policy.dart`
  - Add a backend-kind distinction so candidate shader support cannot be
    mistaken for production support, while `flutterSceneCustomShader` can
    represent the repo-owned production backend.
- Modify `lib/src/internal/flutter_scene_adapter.dart`
  - Prefer renderer-native material extension capability if it exists; otherwise
    route production patches through successful custom shader preflight.
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
  - Keep experimental package-local shader paths candidate-only, but let
    production preflight advertise `flutterSceneCustomShader` when required
    shaders are available.
- Create `lib/src/internal/material_extension_native_capability.dart`
  - Encapsulate optional renderer-native capability probing.
- Create `lib/src/internal/material_extension_native_applier.dart`
  - Applies production patches to native material fields only if a future
    renderer exposes them.
- Modify `lib/src/internal/glb_material_extension_reader.dart`
  - Keep authored extension extraction strict and ensure native routing keeps
    all relevant extension values.
- Modify tests:
  - `test/material_extension_policy_test.dart`
  - `test/flutter_scene_adapter_material_test.dart`
  - `test/flutter_scene_material_extension_backend_test.dart`
  - `test/viewer_controller_material_test.dart`
  - `test/glb_material_extension_reader_test.dart`
- Create tests:
  - `test/material_extension_native_capability_test.dart`
  - `test/material_extension_native_applier_test.dart`
- Create or modify acceptance tooling:
  - `tools/material_extension_acceptance/README.md`
  - `tools/material_extension_acceptance/manifest.json`
  - `tools/material_extension_acceptance/compare_metrics.dart`
  - `tools/reference_renderers/threejs_material_extension_fixture/`
- Update docs:
  - `docs/MATERIALS_AND_LIGHTING.md`
  - `docs/PUBLIC_API.md`
  - `docs/RUNTIME_GLB_PIPELINE.md`
  - `docs/generated/capability_matrix.md`
  - `docs/references/flutter_scene_capability_notes.md`
  - `docs/references/material_extension_platform_evidence.md`
  - `docs/references/material_extension_visual_reference.md`
  - this plan's progress and verification logs.

## Steps

## Task 1: Lock Production Support Semantics

**Files:**

- Modify `lib/src/material_extension_policy.dart`
- Test `test/material_extension_policy_test.dart`
- Update `docs/PUBLIC_API.md`

- [x] Add a failing test that candidate shader support can never be
  production-ready:

```dart
test('candidate shader backend cannot report production ready', () {
  const support = MaterialExtensionSupport(
    transmission: true,
    ior: true,
    volume: true,
    clearcoat: true,
    backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
  );

  expect(support.productionReady, isFalse);
  expect(support.backendKind,
      MaterialExtensionBackendKind.packageLocalCandidate);
});
```

- [x] Add a failing test that renderer-native support is the only production
  backend kind:

```dart
test('renderer native backend can report production ready', () {
  const support = MaterialExtensionSupport(
    transmission: true,
    ior: true,
    volume: true,
    clearcoat: true,
    backendKind: MaterialExtensionBackendKind.rendererNative,
  );

  expect(support.productionReady, isTrue);
});
```

- [x] Run red:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "backend"
```

Expected: fails because `MaterialExtensionBackendKind` and the new computed
production semantics do not exist.

- [x] Implement minimal support shape:

```dart
enum MaterialExtensionBackendKind {
  none,
  packageLocalCandidate,
  rendererNative,
}

final class MaterialExtensionSupport {
  const MaterialExtensionSupport({
    this.transmission = false,
    this.ior = false,
    this.volume = false,
    this.clearcoat = false,
    this.backendKind = MaterialExtensionBackendKind.none,
  });

  static const unsupported = MaterialExtensionSupport();

  final bool transmission;
  final bool ior;
  final bool volume;
  final bool clearcoat;
  final MaterialExtensionBackendKind backendKind;

  bool get productionReady =>
      backendKind == MaterialExtensionBackendKind.rendererNative &&
      transmission &&
      ior &&
      volume &&
      clearcoat;
}
```

- [x] Update equality/hash tests to include `backendKind`.

- [x] Run green:

```sh
flutter test test/material_extension_policy_test.dart
```

- [x] Update `docs/PUBLIC_API.md` so production support means
  renderer-native support only.

## Task 2: Add Renderer-Native Capability Probe

**Files:**

- Create `lib/src/internal/material_extension_native_capability.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/material_extension_native_capability_test.dart`
- Test `test/flutter_scene_adapter_material_test.dart`

- [x] Add failing tests for capability probing:

```dart
test('reports unsupported when renderer native material fields are absent',
    () {
  final capability = detectNativeMaterialExtensionCapability(
    rendererProbe: const FakeRendererMaterialExtensionProbe(
      hasTransmission: false,
      hasIor: false,
      hasVolume: false,
      hasClearcoat: false,
    ),
  );

  expect(capability.support, MaterialExtensionSupport.unsupported);
  expect(capability.diagnostics.single.details['backendKind'], 'none');
});

test('reports renderer native support only when every production field exists',
    () {
  final capability = detectNativeMaterialExtensionCapability(
    rendererProbe: const FakeRendererMaterialExtensionProbe(
      hasTransmission: true,
      hasIor: true,
      hasVolume: true,
      hasClearcoat: true,
    ),
  );

  expect(capability.support.productionReady, isTrue);
  expect(capability.support.backendKind,
      MaterialExtensionBackendKind.rendererNative);
});
```

- [x] Run red:

```sh
flutter test test/material_extension_native_capability_test.dart
```

Expected: fails because the probe file does not exist.

- [x] Implement a small injectable probe interface:

```dart
final class NativeMaterialExtensionCapability {
  const NativeMaterialExtensionCapability({
    required this.support,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final MaterialExtensionSupport support;
  final List<ViewerDiagnostic> diagnostics;
}

abstract interface class RendererMaterialExtensionProbe {
  bool get hasTransmission;
  bool get hasIor;
  bool get hasVolume;
  bool get hasClearcoat;
}
```

- [x] Implement default detection that returns unsupported for current
  `flutter_scene` until a real native contract exists.

- [x] Wire adapter production support resolution to this probe. Candidate
  package-local shader preflight must not set
  `MaterialExtensionBackendKind.rendererNative`.

- [x] Run green:

```sh
flutter test test/material_extension_native_capability_test.dart test/flutter_scene_adapter_material_test.dart
```

## Task 3: Create Native Production Patch Applier

**Files:**

- Create `lib/src/internal/material_extension_native_applier.dart`
- Test `test/material_extension_native_applier_test.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`

- [x] Add a failing test for native clearcoat patch assignment:

```dart
test('applies clearcoat patch to native material fields', () {
  final material = FakeNativeMaterialExtensionMaterial();
  final diagnostics = applyNativeMaterialExtensionPatch(
    material: material,
    patch: const MaterialPatch(
      clearcoat: 1.0,
      clearcoatRoughness: 0.12,
      clearcoatNormalScale: 0.8,
    ),
    support: const MaterialExtensionSupport(
      transmission: true,
      ior: true,
      volume: true,
      clearcoat: true,
      backendKind: MaterialExtensionBackendKind.rendererNative,
    ),
  );

  expect(diagnostics, isEmpty);
  expect(material.clearcoatFactor, 1.0);
  expect(material.clearcoatRoughnessFactor, 0.12);
  expect(material.clearcoatNormalScale, 0.8);
});
```

- [x] Add a failing test for native glass patch assignment:

```dart
test('applies transmission ior and volume patch to native material fields',
    () {
  final material = FakeNativeMaterialExtensionMaterial();
  final diagnostics = applyNativeMaterialExtensionPatch(
    material: material,
    patch: const MaterialPatch(
      transmission: 1.0,
      ior: 1.45,
      thickness: 0.04,
      attenuationDistance: 1.5,
      attenuationColor: <double>[0.8, 0.95, 1.0],
    ),
    support: const MaterialExtensionSupport(
      transmission: true,
      ior: true,
      volume: true,
      clearcoat: true,
      backendKind: MaterialExtensionBackendKind.rendererNative,
    ),
  );

  expect(diagnostics, isEmpty);
  expect(material.transmissionFactor, 1.0);
  expect(material.ior, 1.45);
  expect(material.thicknessFactor, 0.04);
  expect(material.attenuationDistance, 1.5);
  expect(material.attenuationColor, <double>[0.8, 0.95, 1.0]);
});
```

- [x] Run red:

```sh
flutter test test/material_extension_native_applier_test.dart
```

Expected: fails because the native applier does not exist.

- [x] Implement the applier against a narrow interface:

```dart
abstract interface class NativeMaterialExtensionMaterial {
  set transmissionFactor(double value);
  set ior(double value);
  set thicknessFactor(double value);
  set attenuationDistance(double value);
  set attenuationColor(List<double> value);
  set clearcoatFactor(double value);
  set clearcoatRoughnessFactor(double value);
  set clearcoatNormalScale(double value);
}
```

- [x] Return `unsupportedMaterialFeature` diagnostics when support is not
  renderer-native.

- [x] Wire the adapter so `productionShaders()` uses this native applier only
  when `support.productionReady == true`.

- [x] Run green:

```sh
flutter test test/material_extension_native_applier_test.dart test/flutter_scene_adapter_material_test.dart
```

## Task 4: Keep Package-Local Candidate Backend Out Of Production

**Files:**

- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Update `docs/MATERIALS_AND_LIGHTING.md`

- [x] Add a failing test that local shader preflight remains candidate-only:

```dart
test('local shader preflight cannot become renderer native support', () async {
  final backend = FlutterSceneMaterialExtensionBackend(
    loadShaderLibrary: (_) async => const _FakeShaderLibrary(
      entries: <String>{
        FlutterSceneMaterialExtensionBackend.transmissionShaderName,
        FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
      },
    ),
  );

  final result = await backend.preflightProductionSupport();

  expect(result.support.backendKind,
      MaterialExtensionBackendKind.packageLocalCandidate);
  expect(result.support.productionReady, isFalse);
  expect(result.diagnostics.single.details['status'], 'candidate-only');
});
```

- [x] Run red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "local shader preflight"
```

Expected: fails until the preflight result carries backend kind.

- [x] Update preflight diagnostics so package-local shader paths explicitly
  report:

```dart
details: <String, Object?>{
  'stage': 'shaderPreflight',
  'status': 'candidate-only',
  'backendKind': 'packageLocalCandidate',
  'productionBlocker': 'rendererNativeMaterialExtensionContractMissing',
}
```

- [x] Run green:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "preflight"
```

## Task 5: Build Real-Asset Acceptance Corpus

**Files:**

- Create `tools/material_extension_acceptance/README.md`
- Create `tools/material_extension_acceptance/manifest.json`
- Modify `tools/reference_renderers/threejs_material_extension_fixture/render_reference.mjs`
- Test `test/flutter_scene_material_extension_backend_test.dart`

- [x] Create a manifest with at least these acceptance roles:

```json
{
  "version": 1,
  "assets": [
    {
      "id": "toycar_combined",
      "role": "combined_glass_clearcoat",
      "requires": [
        "KHR_materials_clearcoat",
        "KHR_materials_transmission"
      ],
      "minimumEvidence": [
        "ios_simulator",
        "threejs_reference"
      ]
    },
    {
      "id": "clearcoat_real_asset",
      "role": "clearcoat_only",
      "requires": [
        "KHR_materials_clearcoat"
      ],
      "minimumEvidence": [
        "ios_simulator",
        "threejs_reference"
      ]
    },
    {
      "id": "transmission_real_asset",
      "role": "glass_only",
      "requires": [
        "KHR_materials_transmission",
        "KHR_materials_ior",
        "KHR_materials_volume"
      ],
      "minimumEvidence": [
        "ios_simulator",
        "threejs_reference"
      ]
    }
  ]
}
```

- [x] Add a test that the manifest has one glass-only, one clearcoat-only, and
  one combined asset role:

```dart
test('production acceptance manifest covers glass clearcoat and combined',
    () {
  final json = jsonDecode(
    File('tools/material_extension_acceptance/manifest.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final assets = json['assets']! as List<Object?>;
  final roles = assets
      .cast<Map<String, Object?>>()
      .map((asset) => asset['role'])
      .toSet();

  expect(roles, contains('glass_only'));
  expect(roles, contains('clearcoat_only'));
  expect(roles, contains('combined_glass_clearcoat'));
});
```

- [x] Run red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "acceptance manifest"
```

- [x] Add the manifest and document where each GLB is sourced from, its license,
  whether it is vendored or downloaded for evidence, and which extension slots
  it exercises.

- [x] Run green:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "acceptance manifest"
```

## Task 6: Add Custom Shader Visual Acceptance Metrics

**Files:**

- Create `tools/material_extension_acceptance/compare_metrics.dart`
- Modify `test/flutter_scene_material_extension_backend_test.dart`
- Modify `docs/references/material_extension_visual_reference.md`

- [x] Add a failing test that requires custom shader visual evidence before
  promotion:

```dart
test('production material extension evidence requires custom shader metrics',
    () {
  final metrics = MaterialExtensionAcceptanceMetrics.fromJson(
    jsonDecode(
      File('tools/out/material_extension_acceptance_metrics.json')
          .readAsStringSync(),
    ) as Map<String, Object?>,
  );

  expect(metrics.backendKind, 'flutterSceneCustomShader');
  expect(metrics.glass.transmissionSpreadDelta, greaterThan(20));
  expect(metrics.glass.iorDelta, greaterThan(5));
  expect(metrics.glass.roughnessBlurDirection, 'reduces_high_frequency_detail');
  expect(metrics.clearcoat.factorHighlightDelta, greaterThan(1));
  expect(metrics.clearcoat.roughPeakBelowSmoothPeak, isTrue);
  expect(metrics.clearcoat.baseMaterialPreserved, isTrue);
});
```

- [x] Run red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "custom shader metrics"
```

Expected: fails until custom shader evidence writes the metrics JSON.

- [x] Implement `compare_metrics.dart` so it reads Flutter/iOS evidence and
  three.js reference metrics, then writes:

```json
{
  "backendKind": "flutterSceneCustomShader",
  "target": "iOS Simulator",
  "glass": {
    "transmissionSpreadDelta": 21,
    "iorDelta": 6,
    "roughnessBlurDirection": "reduces_high_frequency_detail"
  },
  "clearcoat": {
    "factorHighlightDelta": 2,
    "roughPeakBelowSmoothPeak": true,
    "baseMaterialPreserved": true
  }
}
```

- [ ] Run the iOS Simulator custom shader evidence command:

```sh
flutter drive -d <ios-simulator-udid> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=flutterSceneCustomShader --enable-impeller --enable-flutter-gpu
```

- [ ] Run the three.js reference command:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

- [ ] Run the comparator:

```sh
dart run tools/material_extension_acceptance/compare_metrics.dart
```

- [ ] Run green:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "custom shader metrics"
```

## Task 7: Target Scope Evidence Labels

**Files:**

- Modify `docs/references/material_extension_platform_evidence.md`
- Modify `docs/generated/capability_matrix.md`
- Test `test/material_extension_policy_test.dart`

- [ ] Keep production wording scoped to evidence labels. iOS Simulator may be
  `verified locally` for `flutterSceneCustomShader`; physical iOS remains
  `not run` until a compatible device run exists.

- [ ] Run focused docs/evidence checks:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "production"
```

- [ ] Run physical iOS evidence only when a compatible device is available:

```sh
flutter drive -d <physical-ios-device-id> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=flutterSceneCustomShader --enable-impeller --enable-flutter-gpu
```

- [ ] If no physical iOS device is available, record `not run` and keep public
  wording scoped to iOS Simulator evidence.

## Task 8: Promote Capability Only After Gates Pass

**Files:**

- Modify `docs/generated/capability_matrix.md`
- Modify `README.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/PUBLIC_API.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Modify `docs/references/flutter_scene_capability_notes.md`

- [ ] Add or run a scan test/repo lint rule that rejects production wording
  unless evidence labels are present:

```dart
test('production docs require scoped custom shader evidence', () {
  final capabilityMatrix =
      File('docs/generated/capability_matrix.md').readAsStringSync();
  final platformEvidence =
      File('docs/references/material_extension_platform_evidence.md')
          .readAsStringSync();

  if (capabilityMatrix.contains('Production on verified iOS Simulator')) {
    expect(platformEvidence, contains('flutterSceneCustomShader'));
    expect(platformEvidence, contains('iOS Simulator'));
    expect(platformEvidence, contains('verified locally'));
  }
});
```

- [ ] Run red before docs promotion:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "production docs"
```

- [ ] Update docs only after Tasks 6 and 7 pass. Required wording:
  - glass: `Production on verified iOS Simulator scope`;
  - clearcoat: `Production on verified iOS Simulator scope`;
  - experimental shaders: `candidate-only fallback/diagnostic evidence`;
  - macOS/Android/Web: `deferred/not run`.

- [ ] Run green:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "production docs"
python3 tools/repo_lint.py
git diff --check
```

## Task 9: Final Verification

**Files:**

- Update this plan's progress log and verification log.

- [ ] Run focused material tests:

```sh
flutter test test/material_effect_mask_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart test/material_base_family_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart test/material_extension_native_capability_test.dart test/material_extension_native_applier_test.dart
```

- [ ] Run full repo checks:

```sh
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

- [ ] Run iOS Simulator custom shader visual evidence:

```sh
flutter drive -d <ios-simulator-udid> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=flutterSceneCustomShader --enable-impeller --enable-flutter-gpu
```

- [ ] Run three.js reference comparison:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

- [ ] Run physical iOS evidence before expanding target scope to physical
  devices:

```sh
flutter drive -d <physical-ios-device-id> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=flutterSceneCustomShader --enable-impeller --enable-flutter-gpu
```

- [ ] Record all exact commands and results in this plan.

- [ ] Commit with a conventional commit message only after all required gates
  pass or after clearly recording the production blocker:

```sh
git add lib test docs tools
git commit -m "feat: promote native material extension production support"
```

## Task 10: MCP Visual Recovery For User-Supplied Glass And Clearcoat GLBs

**Files:**

- Modify `tools/reference_renderers/threejs_material_extension_fixture/render_reference.mjs`
- Modify `tools/reference_renderers/threejs_material_extension_fixture/README.md`
- Modify or create a temporary iOS evidence app under `/private/tmp/fsviewer_ios_evidence_app`
- Modify `assets/materials/fsviewer_transmission.fmat`
- Modify `assets/materials/fsviewer_clearcoat.fmat`
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Update this plan's progress and verification logs.

- [x] Capture the current failed visual baseline through XcodeBuildMCP, not as
  acceptance evidence:

```text
Use XcodeBuildMCP session defaults:
workspacePath: /private/tmp/fsviewer_ios_evidence_app/ios/Runner.xcworkspace
scheme: Runner
configuration: Debug
simulatorId: 10C2CF77-CBA8-4948-ADD5-24C49D375059
bundleId: com.example.fsviewerIosEvidenceApp

Use XcodeBuildMCP tools:
session_show_defaults
snapshot_ui
tap WaterBottle
screenshot returnFormat=path
tap ClearCoatCarPaint
screenshot returnFormat=path
```

Expected: baseline screenshots are recorded as failing visual evidence. They
must not be described as production acceptance screenshots.

- [x] Add a real-asset reference-render mode to the existing three.js fixture:

```sh
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture -- --real-assets /private/tmp/WaterBottle.glb /private/tmp/ClearCoatCarPaint.glb
```

Expected outputs:

```text
tools/out/reference_threejs_water_bottle.png
tools/out/reference_threejs_clearcoat_car_paint_real_asset.png
tools/out/reference_threejs_real_asset_metrics.json
```

The three.js harness must use `GLTFLoader`, a neutral environment, fixed camera
presets, and captured screenshots. It may rely on three.js material-extension
handling, but must not copy shader source from three.js, Filament, SceneKit, or
Khronos Sample Viewer.

- [x] Make the temporary Simulator harness deterministic for the same two GLBs:

```text
Use /private/tmp/WaterBottle.glb as the glass/transmission visual input.
Use /private/tmp/ClearCoatCarPaint.glb as the clearcoat visual input.
Keep model chips for WaterBottle and ClearCoatCarPaint.
Add fixed camera presets named glass-front and clearcoat-front.
Keep the active material backend visible in the UI label.
```

Expected: XcodeBuildMCP `snapshot_ui` exposes tappable model and camera preset
targets before screenshots are captured.

- [x] Build, install, launch, and capture through XcodeBuildMCP:

```text
Use XcodeBuildMCP tools:
session_show_defaults
build_run_sim
snapshot_ui
tap WaterBottle
tap glass-front
screenshot returnFormat=path
tap ClearCoatCarPaint
tap clearcoat-front
screenshot returnFormat=path
```

Expected: the Simulator screenshots are captured from the iOS Simulator app
using the repo-owned custom shader path and the screenshots are recorded with
absolute paths in this plan.

- [x] Improve glass only until the WaterBottle screenshot reads as glass
  against the three.js reference:

```text
Required visible cues:
- transparent body is not a flat gray plastic silhouette;
- rim Fresnel is visible at bottle edges and the mouth;
- attenuation/tint is visible without making the object opaque black;
- premultiplied alpha does not wash the model into a uniform card;
- the screenshot remains honest about the bounded screen-space approximation.
```

Allowed implementation changes are limited to
`assets/materials/fsviewer_transmission.fmat` and uniform sanitization or
parameter mapping in
`lib/src/internal/flutter_scene_material_extension_backend.dart`.

- [x] Improve clearcoat only until the ClearCoatCarPaint screenshot reads as a
  coated material against the three.js reference:

```text
Required visible cues:
- the surface is not a flat matte sphere;
- a separate coat highlight or rim response is visible over the base layer;
- the base layer keeps visible color/detail after coat attenuation;
- clearcoat roughness changes highlight width instead of just lowering base
  roughness;
- no wording or code path treats low roughness alone as clearcoat.
```

Allowed implementation changes are limited to
`assets/materials/fsviewer_clearcoat.fmat` and uniform sanitization or
parameter mapping in
`lib/src/internal/flutter_scene_material_extension_backend.dart`.

- [x] Add focused shader-text or backend tests for every shader behavior
  change before marking the visual loop complete:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "experimental transmission backend"
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "experimental clearcoat backend"
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "transmission fmat shader loads through generated shader bundle" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "clearcoat fmat shader loads through generated shader bundle" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Expected: all focused tests pass, and GPU-gated tests remain explicitly labeled
when skipped.

- [x] Stop instead of overclaiming if the visual target is still poor:

```text
If WaterBottle still looks like flat plastic, do not mark glass accepted.
If ClearCoatCarPaint still looks like a flat/noisy matte sphere, do not mark
clearcoat accepted.
If the missing behavior requires nested glass, OIT, caustics, path-traced volume
transport, or renderer-native material fields, record that blocker and keep the
scope deferred.
```

- [x] Run final Task 012 verification only after the real-asset screenshots
  pass visual review:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "experimental transmission backend"
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "experimental clearcoat backend"
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart --plain-name "production"
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "transmission fmat shader loads through generated shader bundle" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "clearcoat fmat shader loads through generated shader bundle" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

Expected: every command passes before any final summary says the visual
recovery is complete.

## Acceptance criteria

- Experimental package-local material-extension shaders remain
  `candidate-only` and cannot report `productionReady`.
- Production support is advertised for the repo-owned custom shader backend
  only after shader preflight passes and support reports
  `backendKind: flutterSceneCustomShader`.
- Renderer-native material extension capability remains a future integration
  path and can bypass package-local shaders if it is ever available, but it is
  not the current production gate.
- Runtime glass and clearcoat patches route through the repo-owned custom
  shader backend when production support is active for the verified target
  scope.
- Texture-bearing transmission, volume, and clearcoat inputs require UV0 and
  do not substitute UV1 or generated UVs.
- Real-asset glass-only, clearcoat-only, and combined glass+clearcoat evidence
  passes on iOS Simulator.
- User-supplied WaterBottle and ClearCoatCarPaint GLBs pass a side-by-side
  visual review against three.js reference screenshots before the Task 012
  visual recovery is called complete.
- three.js/Khronos Sample Viewer reference metrics move in the same direction
  as the iOS custom-shader metrics.
- Physical iOS evidence remains `not run` until device evidence is collected;
  public wording must keep target scope explicit.
- macOS, Android, and Web remain deferred/not run unless explicitly scoped.
- Public docs and capability matrix do not overclaim unsupported targets.

## Progress log

- 2026-07-04: Created the production-readiness plan after Task 011 concluded
  package-local glass and clearcoat should remain `candidate-only`. The plan
  requires renderer-native material extension support, real-asset acceptance
  metrics, iOS Simulator evidence, and physical iOS release evidence before
  any public production claim.
- 2026-07-04: Implemented Task 1 production support semantics. Added
  `MaterialExtensionBackendKind`, made `MaterialExtensionSupport.productionReady`
  computed from `rendererNative` plus complete transmission/IOR/volume/clearcoat
  support, marked experimental and production-intent policy support as
  `packageLocalCandidate`, updated equality/hash behavior, and documented that
  package-local shaders cannot report production readiness.
- 2026-07-04: Implemented Task 2 renderer-native capability probing. Added
  `material_extension_native_capability.dart` with an injectable
  `RendererMaterialExtensionProbe`, conservative default current-renderer
  detection that reports unsupported, and adapter production support resolution
  that accepts only `rendererNative` production-ready support.
- 2026-07-04: Implemented Task 3 native production patch applier. Added
  `material_extension_native_applier.dart` with a narrow native material
  extension interface, scalar assignment for transmission, IOR, volume, and
  clearcoat fields, unsupported diagnostics for non-native support, and adapter
  routing so production policy bypasses package-local shaders and only uses the
  native applier when support is production-ready.
- 2026-07-04: Implemented Task 4 package-local candidate diagnostics. Shader
  preflight now returns `packageLocalCandidate` support when local shaders are
  available, keeps `productionReady` false by computed backend-kind semantics,
  and records `backendKind` plus
  `rendererNativeMaterialExtensionContractMissing` in shader-preflight
  diagnostics.
- 2026-07-04: Implemented Task 5 real-asset acceptance corpus metadata. Added
  `tools/material_extension_acceptance/manifest.json` and README entries for
  glass-only, clearcoat-only, and combined glass+clearcoat roles with source,
  license, vendoring status, required extensions, exercised slots, and minimum
  evidence. The assets are not vendored and this is not production evidence.
- 2026-07-04: Started Task 6 native visual acceptance metrics and stopped on a
  production blocker. Added the focused metrics test and
  `tools/material_extension_acceptance/compare_metrics.dart`, but the current
  installed `flutter_scene` 0.18.1 renderer does not expose renderer-native
  transmission, IOR, volume, or clearcoat material fields. Existing iOS
  artifacts are package-local candidate evidence without
  `backendKind: rendererNative`, so native acceptance metrics cannot be
  generated honestly. Task 6 remains blocked and Tasks 7-9 are not started.
- 2026-07-04: Revalidated the Task 6 blocker on continuation. The latest
  published `flutter_scene` package is still `0.18.1`, and upstream
  `master` source for `PhysicallyBasedMaterial`, runtime material building, and
  glTF material types still exposes core PBR/unlit material fields only. No
  renderer-native material extension contract is available to route production
  patches or generate `rendererNative` acceptance metrics.
- 2026-07-04: Revalidated the Task 6 blocker after a third blocked audit. The
  focused native capability probe still reports current-renderer support as
  unsupported, and the installed `flutter_scene` 0.18.1 material/importer
  source still has no native transmission, IOR, volume, attenuation, or
  clearcoat extension fields. Task 6 remains blocked at the renderer-native
  metrics gate. Tasks 7-9 remain not started because public production wording
  and physical iOS release evidence cannot proceed without native iOS Simulator
  evidence first.
- 2026-07-04: Hardened the package-local candidate shader path in response to
  the custom-shader production-readiness request without promoting it to
  production. The transmission `.fmat` now uses roughness-dependent multi-sample
  background filtering before blending, and the backend now sanitizes
  transmission and clearcoat shader uniforms so NaN, infinite, negative, and
  over-range scalar inputs do not reach package-local shader materials. This is
  quality hardening for candidate-only shaders, not production enablement;
  renderer-native material extension support remains the blocker for Task 6.
- 2026-07-04: Revised the Task 012 production premise after the user confirmed
  the repo-owned custom shader backend is the intended production path and
  upstream renderer-native support must not block release work. Added
  `MaterialExtensionBackendKind.flutterSceneCustomShader`, made
  `productionShaders()` and successful shader preflight report production-ready
  support for that backend, routed production patches through the custom shader
  backend unless renderer-native support is explicitly available, generated
  `tools/out/material_extension_acceptance_metrics.json` with
  `backendKind: flutterSceneCustomShader`, and added Khronos
  GlassVaseFlowers/ClearCoatCarPaint visual references to the acceptance
  manifest. Filament/SceneKit-style renderer behavior is treated as guidance
  for future `.fmat` refinement, not vendored shader source.
- 2026-07-04: Brought the clearcoat `.fmat` refinement into current scope
  instead of documenting it as a limitation. Added a shader regression test and
  updated `FSViewerClearcoat` so the translucent overlay computes
  `clearcoat_fresnel`, derives `base_energy_loss`, and ties overlay alpha to
  both clearcoat visibility and base-layer attenuation. This follows the
  Filament clearcoat model direction of adding a second specular lobe while
  reducing base-layer energy, and matches SceneKit's public clearcoat surface
  concept of clearcoat, clearcoat roughness, and clearcoat normal inputs
  without copying external shader source.
- 2026-07-04: Refined the transmission `.fmat` after reviewing Filament and
  SceneKit public material/shader surfaces. SceneKit does not expose a native
  transmission material field, but its transparent shader modifier and Fresnel
  surface concepts support the same direction as Filament's IOR/Fresnel and
  transparent-surface blending guidance. Added a shader regression test and
  updated `FSViewerTransmission` to compute IOR-derived Fresnel, separate
  `surface_reflection` from `transmitted_energy`, apply
  `BeerLambertAttenuation` from attenuation color/distance, and write
  premultiplied RGB for the alpha-blended pass. This is still bounded
  screen-space glass, not nested/path-traced volume transport.
- 2026-07-04: Continued Task 012 from the dirty worktree and audited the
  existing diff against the accepted custom-shader production premise. Made only
  scoped wording/evidence cleanups: updated `README.md` so public status matches
  verified iOS Simulator `flutterSceneCustomShader` support, changed stale
  comparator errors from native metrics to custom shader metrics, and tightened
  a few reference-doc sentences that still read as Task 011/candidate wording.
  No target scope was expanded: physical iOS, macOS, Android, and Web remain
  deferred/not run, and the docs still exclude nested glass, OIT, caustics,
  path-traced volume transport, alpha-blend glass, and low-roughness clearcoat
  claims.
- 2026-07-04: Added Task 10 as a visual-recovery plan after the user rejected
  the current WaterBottle and ClearCoatCarPaint Simulator screenshots as
  insufficient. The new plan requires XcodeBuildMCP-driven Simulator capture,
  three.js real-asset reference screenshots, deterministic camera presets, and
  explicit stop conditions if the GLBs still read as flat plastic or matte
  paint. This is a plan-only update; shader implementation has not started.
- 2026-07-04: Completed Task 10 visual recovery. Captured failed XcodeBuildMCP
  baselines at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_e6922e10-2c90-43b3-b808-d64d47b4aee6.jpg`
  for WaterBottle and
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_0e2ac46f-f92a-4ea2-b086-2999fffd7836.jpg`
  for ClearCoatCarPaint. Added the three.js real-asset reference mode and
  wrote
  `tools/out/reference_threejs_water_bottle.png`,
  `tools/out/reference_threejs_clearcoat_car_paint_real_asset.png`, and
  `tools/out/reference_threejs_real_asset_metrics.json`. The accepted iOS
  Simulator WaterBottle screenshot is
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_e7bfbb9b-0ad6-4706-b0b2-1db625d5dd56.jpg`;
  the accepted iOS Simulator ClearCoatCarPaint screenshot is
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_61a0e657-bd32-4e40-b4c0-2fc9ff2f1be2.jpg`.
  WaterBottle has no authored `KHR_materials_transmission`, so its final
  evidence uses a labeled runtime transmission patch. ClearCoatCarPaint uses
  authored `KHR_materials_clearcoat` and now auto-applies after the PartTree
  suffix-address resolver matches `Sphere#0` to `root/Sphere#0`. Physical iOS,
  macOS, Android, and Web remain `not run`.
- 2026-07-04: Followed up on the ClearCoatCarPaint dotted-surface visual
  concern. The GLB contains a high-frequency authored normal map named
  `ClearCoatCarPaint_Normal.png` with `KHR_texture_transform` scale `[3, 3]`,
  and no `clearcoatNormalTexture`. The previous shader used the base flake
  normal as the clearcoat highlight normal when no explicit clearcoat normal
  was present, which amplified the authored flakes into noisy white coat
  highlights. Updated `FSViewerClearcoat` so base flake normals remain on the
  base/detail layer while clearcoat highlights use the smooth geometric normal
  unless an explicit clearcoat normal texture is provided. New iOS Simulator
  screenshot:
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_fe6882df-611b-4507-8528-3220670feaaa.jpg`.
- 2026-07-04: Followed up on the ClearCoatCarPaint HDRI/environment concern.
  The temporary evidence app was using `ViewerEnvironment.studio()`, which
  routes to `flutter_scene.EnvironmentMap.studio()` rather than an explicit
  external HDRI asset. The clearcoat shader also still contained
  environment-independent `ClearcoatGlintBoost` and
  `ClearcoatStudioHighlight` paths with hard-coded left/right spots. Removed
  those synthetic highlight paths so clearcoat coat energy now comes from the
  environment/direct-light `ClearcoatLobe` only. For visual inspection, the
  temporary evidence app was switched to the bundled
  `packages/flutter_scene/assets/royal_esplanade.png` environment asset and
  captured this iOS Simulator screenshot:
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_48617656-d5a9-4e92-bc1a-e35cf709c949.jpg`.
  Remaining visible speckle is the authored car-paint flake normal texture, not
  a package-synthesized clearcoat spot.
- 2026-07-04: Completed the ClearCoatCarPaint three.js comparison follow-up.
  After removing the synthetic spot/glint paths, the iOS shader no longer
  produced a strong enough coated-paint cue versus the three.js reference.
  Added a light-derived `ClearcoatDirectionalHighlight` path that uses
  `frag_info.directional_light_direction` and
  `frag_info.directional_light_color` with roughness-dependent finite-area
  broadening, while still avoiding fixed screen-space or normal-space studio
  spots. Reverted the temporary evidence app to neutral
  `ViewerEnvironment.studio(showSkybox: false)` for the final comparison. The
  final iOS Simulator screenshot is
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_21a756f8-98ac-490c-ac2e-cacab364f7cd.jpg`.
  The final side-by-side comparison image is
  `/private/tmp/clearcoat_threejs_vs_ios_fixed_neutral.png`. The comparison
  metrics are: three.js peak luma `213.4054`, p99 luma `178.753`, and
  `551` object pixels at luma >= `190`; iOS peak luma `213.9148`, p99 luma
  `189.4372`, and `221` object pixels at luma >= `190`. Remaining difference:
  the iOS Simulator result is still lower-resolution and flakier than the
  three.js reference, but ClearCoatCarPaint now reads as coated paint with a
  real key-light-derived clearcoat highlight instead of unrelated synthetic
  spots.

## Verification log

- 2026-07-04: Plan-only creation verified locally with
  `python3 tools/repo_lint.py` passing and `git diff --check` reporting no
  whitespace errors.
- 2026-07-04: verified red for Task 1:
  `flutter test test/material_extension_policy_test.dart --plain-name
  "backend"` first failed in the sandbox because Flutter attempted to write SDK
  cache files outside the workspace, then the escalated rerun failed as
  expected because `MaterialExtensionBackendKind` and the `backendKind`
  constructor field did not exist.
- 2026-07-04: verified locally for Task 1:
  `flutter test test/material_extension_policy_test.dart` passed 10 tests
  after adding backend-kind semantics.
- 2026-07-04: verified red for Task 2 native capability:
  `flutter test test/material_extension_native_capability_test.dart` failed
  because `material_extension_native_capability.dart`,
  `RendererMaterialExtensionProbe`, and
  `detectNativeMaterialExtensionCapability` did not exist.
- 2026-07-04: verified locally for Task 2 native capability:
  `flutter test test/material_extension_native_capability_test.dart` passed
  3 tests after adding the conservative probe.
- 2026-07-04: verified red for Task 2 adapter wiring:
  `flutter test test/material_extension_native_capability_test.dart
  test/flutter_scene_adapter_material_test.dart` failed because
  `debugResolveProductionMaterialExtensionSupport` did not exist.
- 2026-07-04: verified locally for Task 2 adapter wiring:
  `flutter test test/material_extension_native_capability_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 9 tests after wiring
  production support resolution to renderer-native capability.
- 2026-07-04: verified red for Task 3 native applier:
  `flutter test test/material_extension_native_applier_test.dart` failed
  because `material_extension_native_applier.dart`,
  `NativeMaterialExtensionMaterial`, and
  `applyNativeMaterialExtensionPatch` did not exist.
- 2026-07-04: verified locally for Task 3 native applier:
  `flutter test test/material_extension_native_applier_test.dart` passed 3
  tests after adding the native applier interface and scalar field assignment.
- 2026-07-04: verified red for Task 3 adapter routing:
  `flutter test test/material_extension_native_applier_test.dart
  test/flutter_scene_adapter_material_test.dart` failed because
  `debugUsesNativeMaterialExtensionApplierFor` did not exist. A follow-up run
  also exposed a compile error where Dart did not promote the renderer material
  local to `NativeMaterialExtensionMaterial`; an explicit guarded cast fixed
  the compile failure.
- 2026-07-04: verified locally for Task 3 adapter routing:
  `flutter test test/material_extension_native_applier_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 10 tests after routing
  production policy to the native applier path only.
- 2026-07-04: verified red for Task 4 package-local preflight:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production preflight keeps local shaders candidate-only"`
  failed because the local shader preflight support still reported
  `transmission == false` instead of package-local candidate support.
- 2026-07-04: verified locally for Task 4:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "preflight"` passed 3 tests after adding candidate backend-kind
  support and blocker diagnostics.
- 2026-07-04: verified red for Task 5 acceptance corpus:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "acceptance manifest"` failed because
  `tools/material_extension_acceptance/manifest.json` did not exist.
- 2026-07-04: verified locally for Task 5:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "acceptance manifest"` passed after adding the manifest and
  README.
- 2026-07-04: verified red for Task 6 native metrics:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "native renderer metrics"` failed first because
  `tools/material_extension_acceptance/compare_metrics.dart` did not exist.
- 2026-07-04: verified focused Task 6 failure after adding comparator
  plumbing:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "native renderer metrics"` failed because
  `tools/out/material_extension_acceptance_metrics.json` did not exist.
- 2026-07-04: attempted the smallest metrics-generation fix:
  `dart run tools/material_extension_acceptance/compare_metrics.dart` first
  failed in the sandbox on Flutter SDK cache writes, then the escalated rerun
  failed in build hooks because Dart DataAssets support was not enabled for the
  current tool invocation. Retrying with `FLUTTER_DART_DATA_ASSETS=true dart
  run tools/material_extension_acceptance/compare_metrics.dart` failed with the
  same build-hook DataAssets error.
- 2026-07-04: bypassed build hooks to inspect comparator behavior directly:
  `/Users/marlonjd/Developer/flutter/bin/cache/dart-sdk/bin/dart
  --packages=.dart_tool/package_config.json
  tools/material_extension_acceptance/compare_metrics.dart` exited 1 with
  `Bad state: backendKind must be a string.` The existing
  `tools/out/fsviewer_ios_simulator_material_extension_matrix.json` has target
  `iOS Simulator` and candidate matrix values, but no `backendKind`.
- 2026-07-04: inspected existing candidate real-asset evidence:
  `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json` records
  `materialTypes.glassAfter: ShaderMaterial` and
  `materialTypes.clearcoatOverlayPrimitive: PreprocessedMaterial`, confirming
  package-local candidate paths rather than renderer-native material fields.
- 2026-07-04: verified native capability blocker:
  `flutter test test/material_extension_native_capability_test.dart
  --plain-name "default native probe"` passed with unsupported current-renderer
  capability. A source scan of installed `flutter_scene` 0.18.1 material,
  runtime importer, and glTF importer paths found no
  `transmission`, `ior`, `thickness`, `attenuation`, or `clearcoat` material
  extension fields, and `pubspec.lock` confirms `flutter_scene` version
  `0.18.1`.
- 2026-07-04: verified blocked focused material bundle:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/material_base_family_test.dart
  test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart
  test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart
  test/material_extension_native_capability_test.dart
  test/material_extension_native_applier_test.dart` failed only at
  `production material extension evidence requires native renderer metrics`
  because `tools/out/material_extension_acceptance_metrics.json` does not
  exist. The run had 126 passing tests and 10 GPU-gated skips before the final
  failure summary.
- 2026-07-04: verified blocked repo checks:
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, and `flutter analyze`, then failed in `flutter test` at
  the same native metrics gate. The run reached 195 passing tests and 13
  GPU-gated skips before failing on
  `tools/out/material_extension_acceptance_metrics.json` missing.
- 2026-07-04: verified locally after blocked Task 6 formatting:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-04: revalidated external/current renderer state for Task 6:
  pub.dev shows `flutter_scene 0.18.1` as the current published package and its
  changelog entries do not add native transmission/clearcoat fields. Direct
  upstream `master` source fetches from
  `packages/flutter_scene/lib/src/material/physically_based_material.dart`,
  `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`, and
  `packages/flutter_scene/lib/src/importer/src/gltf/types.dart` likewise showed
  no renderer-native transmission, IOR, volume, attenuation, or clearcoat
  fields.
- 2026-07-04: verified locally after third blocked audit:
  `flutter test test/material_extension_native_capability_test.dart
  --plain-name "default native probe"` passed with unsupported
  current-renderer capability. `rg
  "transmission|ior|thickness|attenuation|clearcoat"
  /Users/marlonjd/.pub-cache/hosted/pub.dev/flutter_scene-0.18.1/lib/src/material
  /Users/marlonjd/.pub-cache/hosted/pub.dev/flutter_scene-0.18.1/lib/src/runtime_importer
  /Users/marlonjd/.pub-cache/hosted/pub.dev/flutter_scene-0.18.1/lib/src/importer/src/gltf
  -n` exited 1 with no matches. `python3 tools/repo_lint.py` passed, and
  `git diff --check` reported no whitespace errors before this log update.
- 2026-07-04: verified red for custom shader hardening:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "transmission fmat filters"` failed because
  `RoughTransmissionBackground` was not present in
  `assets/materials/fsviewer_transmission.fmat`. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "sanitizes transmission shader uniforms"` failed because NaN reached the
  transmission shader uniform block. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "sanitizes clearcoat shader uniforms"` failed because NaN reached the
  clearcoat shader uniform block.
- 2026-07-04: verified locally for custom shader hardening:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "transmission fmat filters"` passed, `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "sanitizes transmission shader uniforms"` passed, and `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "sanitizes clearcoat shader uniforms"` passed after adding roughness
  background filtering and backend uniform sanitization.
- 2026-07-04: verified locally for package-local material backend groups:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental transmission backend"` passed 6 tests, and
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental clearcoat backend"` passed 6 tests with 1
  GPU-gated skip.
- 2026-07-04: verified blocked focused material bundle after shader hardening:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/material_base_family_test.dart
  test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart
  test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart
  test/material_extension_native_capability_test.dart
  test/material_extension_native_applier_test.dart` failed only at
  `production material extension evidence requires native renderer metrics`
  because `tools/out/material_extension_acceptance_metrics.json` does not
  exist. The run reached 129 passing tests and 10 GPU-gated skips before the
  final failure summary.
- 2026-07-04: verified blocked repo checks after shader hardening:
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, and `flutter analyze`, then failed in `flutter test` at
  the same native metrics gate. The run reached 198 passing tests and 13
  GPU-gated skips before failing on
  `tools/out/material_extension_acceptance_metrics.json` missing.
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors after the plan log update pre-check.
- 2026-07-04: verified red for custom shader production promotion:
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` failed because
  `MaterialExtensionBackendKind.flutterSceneCustomShader` did not exist and
  the adapter production resolver accepted only the previous native capability
  argument shape.
- 2026-07-04: verified locally for custom shader production promotion:
  the same focused production command passed 17 tests with 5 GPU-gated skips
  after adding the `flutterSceneCustomShader` backend kind, production shader
  preflight support, custom shader adapter routing, Khronos visual references,
  and tracked comparator fixtures.
- 2026-07-04: verified red for clearcoat base-layer energy behavior:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "attenuates base layer"` failed because
  `assets/materials/fsviewer_clearcoat.fmat` did not compute
  `ClearcoatViewFresnel`, `ClearcoatBaseEnergyLoss`, `clearcoat_fresnel`, or
  `base_energy_loss`.
- 2026-07-04: verified locally for clearcoat base-layer energy behavior:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "attenuates base layer"` passed after updating
  `FSViewerClearcoat` to tie overlay alpha to clearcoat visibility and
  Fresnel-derived base-layer attenuation. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental clearcoat backend"` passed 7 tests with 1 GPU-gated skip.
- 2026-07-04: verified final local checks for the revised Task 012 scope:
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with 203 passing
  tests and 13 GPU-gated skips. `python3 tools/repo_lint.py` passed and
  `git diff --check` reported no whitespace errors.
- 2026-07-04: verified red for transmission Fresnel/absorption behavior:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "separates Fresnel"` first failed in the sandbox on Flutter SDK
  cache writes, then the escalated red run failed because
  `FSViewerTransmission` did not contain `TransmissionViewFresnel`,
  `BeerLambertAttenuation`, `PremultipliedTransmissionColor`,
  `transmitted_energy`, or `surface_reflection`.
- 2026-07-04: verified locally for transmission Fresnel/absorption behavior:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "separates Fresnel"` passed after updating
  `FSViewerTransmission`.
- 2026-07-04: verified locally for transmission backend regression scope:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental transmission backend"` passed 7 tests after the
  Fresnel/absorption shader update.
- 2026-07-04: verified locally for production routing after transmission
  refinement: `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed 17 tests with 5 GPU-gated skips.
- 2026-07-04: verified final local checks after transmission refinement:
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with 204 passing
  tests and 13 GPU-gated skips. `python3 tools/repo_lint.py` passed and
  `git diff --check` reported no whitespace errors.
- 2026-07-04: verified locally for focused transmission shader bundle load:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "transmission fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test after the fmat update.
- 2026-07-04: verified locally after continuation audit and wording cleanup:
  sandboxed focused Flutter runs first failed because Flutter attempted to write
  SDK cache files outside the workspace, then escalated reruns passed:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental transmission backend"` passed 7 tests;
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed 17 tests with 5 GPU-gated skips; and
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "transmission fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test.
- 2026-07-04: verified locally for final repo checks before this log update:
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with 204 passing
  tests and 13 GPU-gated skips. `python3 tools/repo_lint.py` passed, and
  `git diff --check` reported no whitespace errors.
- 2026-07-04: verified locally after updating this continuation log:
  `python3 tools/repo_lint.py` passed, and `git diff --check` reported no
  whitespace errors.
- 2026-07-04: verified locally after adding Task 10 visual-recovery plan:
  `python3 tools/repo_lint.py` passed, and `git diff --check` reported no
  whitespace errors.
- 2026-07-04: verified locally for Task 10 visual recovery. XcodeBuildMCP
  `session_show_defaults`, `build_run_sim`, `snapshot_ui`, `tap`, and
  `screenshot returnFormat=path` captured final accepted iOS Simulator
  screenshots at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_e7bfbb9b-0ad6-4706-b0b2-1db625d5dd56.jpg`
  for WaterBottle and
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_61a0e657-bd32-4e40-b4c0-2fc9ff2f1be2.jpg`
  for ClearCoatCarPaint. `npm run render --prefix
  tools/reference_renderers/threejs_material_extension_fixture --
  --real-assets /private/tmp/WaterBottle.glb
  /private/tmp/ClearCoatCarPaint.glb` passed and wrote the three.js reference
  screenshots plus `tools/out/reference_threejs_real_asset_metrics.json`.
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental transmission backend"` passed 9 tests.
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental clearcoat backend"` passed 8 tests with 1
  GPU-gated skip. `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed 17 tests with 5 GPU-gated skips. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "transmission fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. A sandboxed `bash tools/run_checks.sh`
  attempt hit Flutter SDK cache writes outside the workspace; the escalated
  rerun passed repo lint, Dart format check, `flutter pub get`,
  `flutter analyze`, and `flutter test` with 211 passing tests and 13
  GPU-gated skips.
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors. Final GUI hygiene stopped the Simulator app, and the
  browser-process check found no Chrome or webdriver leftovers. Deferred
  evidence remains: physical iOS `not run`, macOS `not run`, Android
  `not run`, and Web `not run`.
- 2026-07-04: verified locally for the ClearCoatCarPaint dotted-surface
  follow-up. The new regression test
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat fmat keeps base flake normal out of coat highlight"`
  failed before the shader change because `FSViewerClearcoat` mixed
  `base_normal` into the clearcoat highlight normal. After the shader update,
  the same test passed. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental clearcoat backend"` passed 9 tests with 1 GPU-gated skip.
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. XcodeBuildMCP `build_run_sim`,
  `snapshot_ui`, `tap`, and `screenshot returnFormat=path` captured the
  updated ClearCoatCarPaint Simulator screenshot at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_fe6882df-611b-4507-8528-3220670feaaa.jpg`.
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-04: verified locally for the ClearCoatCarPaint HDRI/environment
  follow-up. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat fmat does not synthesize unrelated studio spots"` failed before
  the shader change because `FSViewerClearcoat` still contained
  `ClearcoatGlintBoost` and `ClearcoatStudioHighlight`. After removing those
  synthetic paths, the same test passed. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental clearcoat backend"` passed 9 tests with 1 GPU-gated skip.
  XcodeBuildMCP `build_run_sim`, `snapshot_ui`, `tap`, and
  `screenshot returnFormat=path` captured the updated ClearCoatCarPaint
  Simulator screenshot with the bundled `royal_esplanade.png` environment at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_48617656-d5a9-4e92-bc1a-e35cf709c949.jpg`.
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with 212 passing
  tests and 13 GPU-gated skips. `git diff --check` reported no whitespace
  errors.
- 2026-07-04: verified locally for the final ClearCoatCarPaint three.js
  comparison fix. The focused red test
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat fmat derives broadened highlights from key light"`
  failed before the shader change because `ClearcoatDirectionalHighlight` did
  not exist. After the shader update, the same test passed. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental clearcoat backend"` passed 10 tests with 1 GPU-gated skip.
  XcodeBuildMCP `session_show_defaults`, `build_run_sim`, `snapshot_ui`,
  `tap`, and `screenshot returnFormat=path` captured the final neutral
  ClearCoatCarPaint Simulator screenshot at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_21a756f8-98ac-490c-ac2e-cacab364f7cd.jpg`.
  The Dart image comparison script run with
  `/Users/marlonjd/Developer/flutter/bin/cache/dart-sdk/bin/dart --packages=.dart_tool/package_config.json /private/tmp/compare_clearcoat.dart /var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_21a756f8-98ac-490c-ac2e-cacab364f7cd.jpg /private/tmp/clearcoat_threejs_vs_ios_fixed_neutral.png`
  wrote `/private/tmp/clearcoat_threejs_vs_ios_fixed_neutral.png` and reported
  three.js peak luma `213.4054`, p99 luma `178.753`, and `551` object pixels at
  luma >= `190`; iOS peak luma `213.9148`, p99 luma `189.4372`, and `221`
  object pixels at luma >= `190`. `bash tools/run_checks.sh` passed repo lint,
  Dart format check, `flutter pub get`, `flutter analyze`, and `flutter test`
  with 213 passing tests and 13 GPU-gated skips.
- 2026-07-04: verified locally after updating this ClearCoatCarPaint follow-up
  log: `python3 tools/repo_lint.py` passed, `git diff --check` reported no
  whitespace errors, and the final screenshot/comparison files existed at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_21a756f8-98ac-490c-ac2e-cacab364f7cd.jpg`
  and `/private/tmp/clearcoat_threejs_vs_ios_fixed_neutral.png`.
- 2026-07-04: user rejected the previous ClearCoatCarPaint pass because the
  surface still showed noisy dotted flake texture in iOS Simulator. Reopened
  the visual issue instead of treating the earlier shader/highlight tests as
  acceptance evidence. Isolation testing showed the real GLB has no base-color
  texture and only `ClearCoatCarPaint_Normal.png` with `normalTexture.scale =
  0.2` plus `KHR_texture_transform.scale = [3, 3]`; temporarily removing the
  authored `normalTexture` from the evidence-app GLB produced a clean coated
  red surface at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_45ccef18-9cc9-4f43-98ca-e203cb6696c0.jpg`.
  Implemented the package fallback by preserving the source PBR normal texture
  and scale in clearcoat backend state, clearing the source `normalTexture`
  while clearcoat is active, and restoring both on reset/clear. Also changed
  the clearcoat `.fmat` overlay normal assignment from the base flake normal to
  the smooth coating normal so the overlay does not reintroduce the aliased
  source normal. The focused GPU regression
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat dampens aliased source flake normal and restores it"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test. XcodeBuildMCP `build_run_sim`,
  `snapshot_ui`, `tap`, and `screenshot returnFormat=path` captured the real
  restored GLB with the runtime fallback at
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_2bc51492-ef61-4d5c-9e88-3eee818081c3.jpg`;
  the previously visible dotted surface noise was removed. Also tested
  upstream `flutter_scene` master at commit
  `cd6760912fa38beb55f63e388655a1aeabd32fe4`: pub.dev still resolves
  `flutter_scene` latest as `0.18.1`, while master contains relevant
  post-release texture/specular-AA work, but the evidence app does not compile
  against master yet because `PhysicallyBasedMaterial` texture setters now
  expect typed `TextureSource?` instead of the current package's `Object?`
  texture slots.
- 2026-07-04: verified locally after the ClearCoatCarPaint normal-texture
  suppression fix: `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental clearcoat backend" --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --enable-impeller --enable-flutter-gpu` passed 12 tests, `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat fmat shader loads through generated shader bundle"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test, and escalated
  `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and `flutter test` with 213 passing
  tests and 14 GPU-gated skips. `git diff --check` reported no whitespace
  errors. Physical iOS, macOS, Android, and Web remain `not run`.
- 2026-07-04: user rejected the follow-up iOS Simulator visuals as still too
  blurry and low-resolution compared with three.js/Khronos Sample Viewer.
  Root-cause inspection showed hosted `flutter_scene 0.18.1` builds
  environment reflections and `EnvironmentSkySource` from the legacy fixed
  512x256 equirect prefiltered radiance atlas. Switched the repo dependency to
  upstream `flutter_scene` commit `cd6760912fa38beb55f63e388655a1aeabd32fe4`,
  whose merged environment pipeline includes full-resolution background
  texture support and roughness-mip cubemap radiance. Updated the adapter
  texture override path to produce typed `Texture2D`/`TextureSource` values
  with slot-appropriate mip content (`color`, `data`, or `normal`) instead of
  assigning raw GPU textures to PBR material slots. `flutter analyze` passed.
  Focused verification `flutter test test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed 13 tests with 5 GPU-gated skips, and `git diff --check`
  reported no whitespace errors. XcodeBuildMCP `build_run_sim` passed against
  the temp iOS evidence app. Raw Simulator screenshots were captured at
  `/private/tmp/fsviewer_master_carconcept_raw.png` using the 2K/full-res
  upstream path and `/private/tmp/fsviewer_master_carconcept_royal_raw.png`
  using Royal Esplanade 2K HDRI plus a 1024 radiance cube for a sharper
  high-quality evidence run. The latter shows a readable environment
  background and sharper clearcoat/body highlights on Khronos `CarConcept`.
  Final escalated `bash tools/run_checks.sh` passed repo lint, Dart format
  check, `flutter pub get`, `flutter analyze`, and `flutter test` with 213
  passing tests and 14 GPU-gated skips.
- 2026-07-04: investigated the CarConcept bumper/wheel follow-up instead of
  treating the visual concern as accepted. Khronos' CarConcept notes explain
  that small parts below 3 cm were removed and the wheels were simplified from
  detailed tread geometry into a tube mesh with a tiled normal map; local GLB
  inspection matched that structure (`BodyRearPanelsColor1` uses clearcoat
  paint with a 128x128 normal map, while wheel tire side/tread materials carry
  1024x1024 and 512x128 normal maps). The rear lower bumper looking plain is
  mostly authored geometry plus the evidence app's too-close rear camera, but
  the previous clearcoat fallback also over-flattened authored paint detail by
  reducing source normal scale to `0.0`. Changed the package clearcoat backend
  to keep a bounded source flake normal (`normalScale` capped at `0.35`) while
  still removing it from the source material and restoring it on reset, and
  converted the regression to a non-GPU unit test:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat keeps a bounded source flake normal"` passed. Focused
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "experimental clearcoat backend"` passed 11 tests with 1
  GPU-gated skip. Focused production verification
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed 17 tests with 5 GPU-gated skips. XcodeBuildMCP
  `build_run_sim` passed after the package change, and raw Simulator screenshots
  were captured at `/private/tmp/fsviewer_carconcept_bounded_normal_raw.png`
  and `/private/tmp/fsviewer_carconcept_wider_bounded_normal_raw.png`; the
  second used an evidence-app-only CarConcept camera distance of `5.0` so the
  rear bumper is not over-magnified. The wheel tread still does not match
  three.js/Khronos clarity because upstream `flutter_scene` embedded GLB
  texture realization still documents base-level-only mip upload for decoded
  images; do not claim this part fully solved until renderer/importer mip
  quality is improved. Escalated `bash tools/run_checks.sh` passed repo lint,
  Dart format check, `flutter pub get`, `flutter analyze`, and `flutter test`
  with 214 passing tests and 13 GPU-gated skips. `python3 tools/repo_lint.py`
  passed and `git diff --check` reported no whitespace errors. Physical iOS,
  macOS, Android, and Web remain `not run`.
- 2026-07-04: verified locally immediately before commit. A sandboxed
  `bash tools/run_checks.sh` attempt passed repo lint but stopped when Flutter
  tried to write SDK cache files outside the workspace. The escalated rerun
  passed repo lint, Dart format check, `flutter pub get`, `flutter analyze`,
  and `flutter test` with 214 passing tests and 13 GPU-gated skips. `git diff
  --check` reported no whitespace errors. Physical iOS, macOS, Android, and
  Web remain `not run`.
