# Material Extension Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

## Goal

Move glass/transmission and clearcoat from package-local candidate evidence to
honest production support for the explicitly verified target scope.

## Architecture

Do not promote the package-local screen-space glass shader or translucent
clearcoat overlay to production. Production support must be backed by a
renderer-native glTF/PBR material-extension contract, a real-asset visual
acceptance corpus, and repeatable iOS evidence. The existing package-local
backend remains useful as candidate/debug evidence, but public production
support stays disabled until native capability and visual gates pass.

## Tech Stack

Dart, Flutter, `flutter_scene`, glTF 2.0 material extension semantics,
Flutter GPU/Impeller, iOS Simulator integration tests, physical iOS evidence
before public release claims, three.js reference renders, `flutter test`,
`flutter drive`, `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`.

---

## Current State

- Task 011 leaves package-local glass and clearcoat as `candidate-only`.
- Glass uses bounded screen-space background refraction and does not provide
  renderer-native transmission, order-independent transparency, nested glass,
  or real volume behavior.
- Clearcoat uses a translucent shared-geometry overlay that preserves source
  PBR material detail, but it is not an integrated renderer-native second
  specular lobe.
- ToyCar iOS Simulator evidence demonstrates that both features can be shown
  together without destroying the source material.
- three.js reference comparison exists and is directional, not pixel-perfect.
- The package must not claim production support until the renderer-native
  contract and visual acceptance gates below pass.

## Production Definition

Production support for this plan means all of the following are true:

- The active renderer exposes native material inputs for:
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
- Runtime `MaterialPatch` overrides route to native material fields, not to the
  package-local candidate shader path.
- UV0/TEXCOORD_0 remains required for every texture-bearing authored or
  runtime input. UV1 is not substituted and UVs are not generated.
- Alpha blend is not reported as glass.
- Low roughness is not reported as clearcoat.
- A real-asset visual acceptance corpus passes against the native renderer and
  three.js directional reference metrics.
- iOS Simulator evidence passes first. Physical iOS evidence is required before
  public production wording is shipped. macOS, Android, and Web remain
  deferred unless explicitly scoped into this plan later.

## Non-goals

- Do not build a custom renderer or shader graph.
- Do not copy external renderer shader/runtime source.
- Do not promote package-local candidate shaders to production by threshold
  tuning alone.
- Do not fake native renderer capability with reflection-only field names.
- Do not broaden target evidence to macOS, Android, Web, or physical iOS until
  the iOS Simulator native path passes. Physical iOS is a final release gate,
  not an early implementation target.
- Do not add production docs before evidence exists.

## File Structure

- Modify `lib/src/material_extension_policy.dart`
  - Add a backend-kind distinction so candidate shader support cannot be
    mistaken for renderer-native production support.
- Modify `lib/src/internal/flutter_scene_adapter.dart`
  - Probe renderer-native material extension capability and route production
    patches only through native support.
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
  - Keep package-local shader paths candidate-only and add diagnostics that
    explain why they are not production.
- Create `lib/src/internal/material_extension_native_capability.dart`
  - Encapsulate renderer-native capability probing.
- Create `lib/src/internal/material_extension_native_applier.dart`
  - Applies production patches to native material fields when the renderer
    exposes them.
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

## Task 6: Add Native Visual Acceptance Metrics

**Files:**

- Create `tools/material_extension_acceptance/compare_metrics.dart`
- Modify `test/flutter_scene_material_extension_backend_test.dart`
- Modify `docs/references/material_extension_visual_reference.md`

- [x] Add a failing test that requires native visual evidence before promotion:

```dart
test('production material extension evidence requires native renderer metrics',
    () {
  final metrics = MaterialExtensionAcceptanceMetrics.fromJson(
    jsonDecode(
      File('tools/out/material_extension_acceptance_metrics.json')
          .readAsStringSync(),
    ) as Map<String, Object?>,
  );

  expect(metrics.backendKind, 'rendererNative');
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
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "native renderer metrics"
```

Expected: fails until native renderer evidence writes the metrics JSON.

- [x] Implement `compare_metrics.dart` so it reads Flutter/iOS evidence and
  three.js reference metrics, then writes:

```json
{
  "backendKind": "rendererNative",
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

- [ ] Run the native iOS Simulator evidence command:

```sh
flutter drive -d <ios-simulator-udid> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=rendererNative --enable-impeller --enable-flutter-gpu
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
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "native renderer metrics"
```

## Task 7: Physical iOS Release Gate

**Files:**

- Modify `docs/references/material_extension_platform_evidence.md`
- Modify `docs/generated/capability_matrix.md`
- Test `test/material_extension_policy_test.dart`

- [ ] Add a failing test that public production wording is blocked without
  physical iOS release evidence:

```dart
test('production release evidence requires physical ios gate', () {
  const gate = MaterialExtensionProductionEvidenceGate(
    iosSimulatorVerified: true,
    physicalIosVerified: false,
  );

  expect(gate.canPublishProductionDocs, isFalse);
  expect(gate.statusLabel, 'candidate-only');
});
```

- [ ] Run red:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "physical ios gate"
```

- [ ] Implement the gate as an internal docs/test helper, not as a runtime
  platform restriction. Runtime support may be scoped to verified platforms,
  but public production wording must not ship until the physical iOS evidence
  row is filled.

- [ ] Run physical iOS evidence only when a compatible device is available:

```sh
flutter drive -d <physical-ios-device-id> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=rendererNative --enable-impeller --enable-flutter-gpu
```

- [ ] If no physical iOS device is available, stop the production promotion and
  record `blocked` with exact evidence in this plan. Do not mark production
  ready.

## Task 8: Promote Capability Only After Gates Pass

**Files:**

- Modify `docs/generated/capability_matrix.md`
- Modify `README.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/PUBLIC_API.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Modify `docs/references/flutter_scene_capability_notes.md`

- [ ] Add a failing scan test or repo lint rule that rejects production wording
  unless evidence labels are present:

```dart
test('production docs require renderer native and physical ios evidence',
    () {
  final capabilityMatrix =
      File('docs/generated/capability_matrix.md').readAsStringSync();
  final platformEvidence =
      File('docs/references/material_extension_platform_evidence.md')
          .readAsStringSync();

  if (capabilityMatrix.contains('Production on iOS')) {
    expect(platformEvidence, contains('rendererNative'));
    expect(platformEvidence, contains('physical iOS'));
    expect(platformEvidence, contains('verified locally'));
  }
});
```

- [ ] Run red before docs promotion:

```sh
flutter test test/material_extension_policy_test.dart --plain-name "production docs"
```

- [ ] Update docs only after Tasks 6 and 7 pass. Required wording:
  - glass: `Production on verified iOS targets`;
  - clearcoat: `Production on verified iOS targets`;
  - package-local shaders: `candidate-only fallback/diagnostic evidence`;
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

- [ ] Run iOS Simulator native visual evidence:

```sh
flutter drive -d <ios-simulator-udid> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=rendererNative --enable-impeller --enable-flutter-gpu
```

- [ ] Run three.js reference comparison:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

- [ ] Run physical iOS evidence before public production docs:

```sh
flutter drive -d <physical-ios-device-id> --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --dart-define=FLUTTER_SCENE_MATERIAL_BACKEND=rendererNative --enable-impeller --enable-flutter-gpu
```

- [ ] Record all exact commands and results in this plan.

- [ ] Commit with a conventional commit message only after all required gates
  pass or after clearly recording the production blocker:

```sh
git add lib test docs tools
git commit -m "feat: promote native material extension production support"
```

## Acceptance criteria

- Package-local material-extension shaders remain `candidate-only` and cannot
  report `productionReady`.
- Production support is advertised only when renderer-native material extension
  capability is detected.
- Runtime glass and clearcoat patches route to native material fields when
  production support is active.
- Texture-bearing transmission, volume, and clearcoat inputs require UV0 and
  do not substitute UV1 or generated UVs.
- Real-asset glass-only, clearcoat-only, and combined glass+clearcoat evidence
  passes on iOS Simulator.
- three.js reference metrics move in the same direction as the native iOS
  renderer metrics.
- Physical iOS evidence is recorded before any public production wording ships.
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
