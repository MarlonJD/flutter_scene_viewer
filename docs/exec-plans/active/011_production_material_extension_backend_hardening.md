# Production Material Extension Backend Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

## Goal

Promote the in-repository glass and clearcoat shader backend from experimental
candidate to production-supported V1 material extension support on iOS
Simulator first, without waiting for upstream `flutter_scene` extension
support. Android, Web, macOS, and physical-device hardening are deferred until
the iOS Simulator path is solved end-to-end.

## Architecture

Keep `flutter_scene` as the scene graph, renderer, GPU, and widget integration
layer. Harden the existing package-local material extension backend around
public `flutter_scene` APIs, add production policy/capability gates, and
support only bounded, documented production behavior with typed diagnostics for
unsupported cases. Production support means measured shader load, lifecycle,
reset/reload, visual fixture, and iOS Simulator evidence, not a marketing
rename of the experimental path.

Use glTF KHR material-extension semantics and public PBR material-model
literature as design references for the package-local `.fmat` shader behavior.
Do not port external renderer source wholesale; implement repo-owned shaders
and record any deliberate approximation. Use three.js as the external visual
reference renderer for the same fixture GLB. Use Apple platform renderer API
checks only to understand target scope, not as the glass parity target.

## Tech Stack

Dart, Flutter, `flutter_scene` 0.18.1, Flutter GPU/Impeller, `.fmat` shader
bundles through `flutter_scene/build_hooks.dart`, public glTF/PBR material
semantics as the clearcoat/transmission design reference, three.js `GLTFLoader`
and `MeshPhysicalMaterial` reference renders, `flutter test`, `bash
tools/run_checks.sh`, `python3 tools/repo_lint.py`.

---

## Current State

- Task 010 implemented alpha families, material/effect mask intent, authored
  GLB extension reading, an experimental transmission/glass backend, and an
  experimental clearcoat backend.
- `assets/materials/fsviewer_transmission.fmat` has local GPU visual smoke
  evidence for screen-space refraction.
- `assets/materials/fsviewer_clearcoat.fmat` has local GPU visual smoke
  evidence for a separate clearcoat environment specular lobe.
- `ViewerMaterialExtensionPolicy.experimentalShaders(...)` can opt into these
  candidate paths.
- Default behavior remains diagnostic-only for glass and clearcoat.
- Combined glass + clearcoat on one material is unsupported.
- The current clearcoat shader is candidate-only and must be upgraded before it
  is called production.

## Production Definition

This plan defines production support as:

- Supported on explicitly verified targets only. The only production target
  for this plan is iOS Simulator.
- Shader assets are preflighted before a production policy advertises support.
- Runtime failures produce typed diagnostics and do not silently downgrade to
  alpha blend, lower roughness, or ordinary opaque PBR.
- Shader behavior is traceable to reference notes: glTF extension semantics
  plus public PBR material-model concepts for clearcoat, clearcoat roughness,
  clearcoat normal, transmission, IOR, thickness, absorption, and refraction
  mode. Any local screen-space or `flutter_scene` limitation must be
  documented as an approximation.
- The implementation plan must be executable without knowing the names of
  external engines used during research. Task requirements should describe the
  visible material behavior, input mapping, diagnostics, and evidence gates in
  glTF/PBR terms.
- Visual production evidence compares the same GLB fixture rendered by
  `flutter_scene_viewer` and three.js. The comparison is trend-based, not
  pixel-perfect: transmission, IOR, thickness, clearcoat factor, clearcoat
  roughness, and clearcoat normal must move in the same visible direction as
  the three.js reference render.
- Glass production scope is screen-space refraction/transmission with
  documented limits: no nested glass correctness, no caustics, no path tracing,
  and no order-independent transparency claim.
- Clearcoat production scope is a real second coating lobe layered on top of
  core PBR, with clearcoat factor, roughness, texture, and normal inputs.
- Unsupported authoring shapes, such as mixed glass and opaque primitives on
  the same node when node-layer isolation would hide the opaque primitive from
  the background pass, return diagnostics or require authored node separation.
- macOS, Android, Web, and physical iOS device work must remain marked
  `not run` or deferred in this plan unless the user explicitly broadens scope
  after the iOS Simulator path is complete.

## Non-goals

- Do not wait for upstream `flutter_scene` PRs.
- Do not build a general renderer or shader graph.
- Do not support nested glass, multiple refraction bounces, caustics, OIT, or
  path-traced transmission.
- Do not treat alpha blending as glass.
- Do not treat low roughness as clearcoat.
- Do not generate UVs or substitute UV1 for UV0.
- Do not make production support claims on targets without evidence.
- Do not require a second external reference harness for V1. three.js is the
  primary external reference renderer for this plan.
- Do not copy external renderer shader/runtime source wholesale. Their role is
  reference and verification; the shipped backend remains package-local.
- Do not mention external engine names in shipped Dart code, shader code,
  generated artifacts, public API names, diagnostics, or public marketing copy.
  The code should describe behavior in glTF/PBR terms instead.
- Do not make the implementation depend on private knowledge of which external
  engines informed the research. If a future worker reads only this public plan,
  the required behavior must still be clear from glTF/PBR descriptions and the
  three.js visual reference harness.
- Do not treat Apple platform transparency APIs as production glTF
  transmission. Platform renderer API checks can validate iOS
  clearcoat/transparency scope, but they are not the glass reference renderer
  for this plan.
- Do not harden Android, Web, macOS, or physical iOS device support in this
  plan. Record those targets as deferred/not run and move them to a later plan
  if the iOS Simulator implementation is accepted.

## File Structure

- Modify `lib/src/material_extension_policy.dart`
  - Add a production policy mode and keep diagnostics-only as a safe explicit
    option.
- Modify `lib/src/internal/flutter_scene_adapter.dart`
  - Advertise production support only after backend preflight and platform
    support checks.
  - Emit diagnostics for unsupported material/platform combinations.
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
  - Add backend preflight, shader cache, production capability state,
    viewport/render-texture lifecycle hardening, reset/reload cleanup, and
    production diagnostics.
- Modify `assets/materials/fsviewer_transmission.fmat`
  - Harden glass shader parameters and visual behavior without changing it into
    alpha blend.
- Modify `assets/materials/fsviewer_clearcoat.fmat`
  - Upgrade clearcoat from candidate environment-only output to a lit material
    that preserves base PBR lighting and adds a separate clearcoat lobe.
- Modify `lib/src/viewer_widget.dart`
  - Pass viewport size/pixel ratio or render-frame data needed by the backend.
- Modify `lib/src/viewer_controller.dart`
  - Keep production validation capability-aware and non-persistent on failure.
- Create `docs/references/material_extension_shader_reference.md`
  - Record which public glTF/PBR material concepts guide the local shader
    implementation.
  - Record every known approximation, including screen-space glass limits and
    any clearcoat lighting simplifications.
  - Record license/attribution boundaries: external renderer source is not
    copied, three.js is a test/reference-renderer dependency only, and
    package-local shader code is the implementation.
- Create `tools/reference_renderers/threejs_material_extension_fixture/`
  - Render the same material-extension fixture GLB with three.js
    `GLTFLoader` and `MeshPhysicalMaterial`.
  - Write reference screenshots and a metrics JSON file into `tools/out/`.
- Add or modify tests:
  - `test/material_extension_policy_test.dart`
  - `test/flutter_scene_adapter_material_test.dart`
  - `test/flutter_scene_material_extension_backend_test.dart`
  - `test/viewer_controller_material_test.dart`
  - `test/viewer_widget_test.dart`
- Update docs:
  - `docs/PUBLIC_API.md`
  - `docs/MATERIALS_AND_LIGHTING.md`
  - `docs/RUNTIME_GLB_PIPELINE.md`
  - `docs/references/flutter_scene_capability_notes.md`
  - `docs/generated/capability_matrix.md`
  - `README.md`
  - this plan's progress and verification logs.

## Steps

## Task 1: Add Production Policy And Capability Contract

**Files:**

- Modify `lib/src/material_extension_policy.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/material_extension_policy_test.dart`
- Test `test/flutter_scene_adapter_material_test.dart`
- Update `docs/PUBLIC_API.md`

- [x] Add failing tests for production policy shape:

```dart
test('production shader policy requests glass and clearcoat by default', () {
  const policy = ViewerMaterialExtensionPolicy.productionShaders();

  expect(
    policy.mode,
    ViewerMaterialExtensionMode.productionFlutterSceneShaders,
  );
  expect(policy.enableTransmission, isTrue);
  expect(policy.enableClearcoat, isTrue);
});

test('production support is not advertised without backend preflight', () {
  expect(
    debugUsesMaterialExtensionBackendFor(
      const ViewerMaterialExtensionPolicy.productionShaders(),
      const MaterialPatch(transmission: 1.0, ior: 1.45),
    ),
    isFalse,
  );
});
```

- [x] Run the tests red:

```sh
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: failure because `productionShaders` and
`productionFlutterSceneShaders` do not exist.

- [x] Implement the policy surface:

```dart
enum ViewerMaterialExtensionMode {
  diagnosticsOnly,
  experimentalFlutterSceneShaders,
  productionFlutterSceneShaders,
}

final class ViewerMaterialExtensionPolicy {
  const ViewerMaterialExtensionPolicy.productionShaders({
    this.enableTransmission = true,
    this.enableClearcoat = true,
  }) : mode = ViewerMaterialExtensionMode.productionFlutterSceneShaders;
}
```

- [x] Add an internal production backend gate:

```dart
final class MaterialExtensionSupport {
  const MaterialExtensionSupport({
    this.transmission = false,
    this.ior = false,
    this.volume = false,
    this.clearcoat = false,
    this.productionReady = false,
  });

  final bool productionReady;
}
```

- [x] Update adapter debug routing so production mode requires
  `support.productionReady == true`, while experimental mode can still route
  candidate support.

- [x] Run:

```sh
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: tests pass.

- [x] Update `docs/PUBLIC_API.md` to document:
  - `diagnosticsOnly`;
  - `experimentalShaders`;
  - `productionShaders`;
  - production policy reports diagnostics until backend preflight passes.

## Task 2: Backend Preflight And Target Support Diagnostics

**Files:**

- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Test `test/viewer_widget_test.dart`
- Update `docs/generated/capability_matrix.md`

- [x] Add failing tests for backend preflight:

```dart
test('production preflight reports unavailable shaders', () async {
  final backend = FlutterSceneMaterialExtensionBackend(
    loadShaderLibrary: (_) async => null,
  );

  final result = await backend.preflightProductionSupport();

  expect(result.support.productionReady, isFalse);
  expect(result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature);
  expect(result.diagnostics.single.details['stage'], 'shaderPreflight');
});

test('production preflight keeps local shaders candidate-only', () async {
  final backend = FlutterSceneMaterialExtensionBackend(
    loadShaderLibrary: (_) async => _FakeShaderLibrary(
      entries: <String>{
        FlutterSceneMaterialExtensionBackend.transmissionShaderName,
        FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
      },
    ),
  );

  final result = await backend.preflightProductionSupport();

  expect(result.support.productionReady, isFalse);
  expect(result.support.transmission, isFalse);
  expect(result.support.clearcoat, isFalse);
  expect(result.diagnostics.single.details['status'], 'candidate-only');
});
```

- [x] Run the tests red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name production
```

Expected: failure because `preflightProductionSupport` and test injection for
shader loading do not exist.

- [x] Implement:
  - `MaterialExtensionPreflightResult`;
  - injectable shader-library loader for tests;
  - cached preflight result;
  - diagnostics with details:
    - `stage: shaderPreflight`;
    - `shader`;
    - `assetPath`;
    - `platform`;
    - `status`.

- [x] Wire the preflight result into the adapter/viewer sink support so a
  production policy cannot advertise support before preflight.

- [x] Run:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart test/viewer_widget_test.dart
```

Expected: tests pass.

- [x] Update `docs/generated/capability_matrix.md` with target status labels:
  - `verified locally`;
  - `candidate-only`;
  - `unsupported`;
  - `blocked`.

## Task 3: Render Texture Lifecycle And Viewport Resize Hardening

**Files:**

- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Modify `lib/src/viewer_widget.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Test `test/viewer_widget_test.dart`

- [x] Add failing tests for viewport-driven render texture sizing:

```dart
test('production glass resizes background render texture from viewport',
    () async {
  final backend = FlutterSceneMaterialExtensionBackend(
    renderTextureWidth: 128,
    renderTextureHeight: 128,
  );

  backend.updateViewport(width: 640, height: 480, pixelRatio: 2.0);

  expect(backend.debugBackgroundTextureSize, (1280, 960));
});
```

- [x] Add failing tests for cleanup:

```dart
test('clear removes render views, cached states, and preflight state', () {
  final backend = FlutterSceneMaterialExtensionBackend();
  final sceneViews = <flutter_scene.RenderView>[flutter_scene.RenderView()];

  backend.clear(sceneViews: sceneViews);

  expect(sceneViews, isEmpty);
  expect(backend.debugActivePatchCount, 0);
});
```

- [x] Run red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name viewport
```

Expected: failure because viewport API/debug size does not exist.

- [x] Implement:
  - `updateViewport({required double width, required double height, required double pixelRatio})`;
  - bounded render texture allocation;
  - max texture size guard with diagnostic;
  - texture recreation only when size actually changes;
  - cleanup on model reload and widget dispose path.

- [x] Run:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart test/viewer_widget_test.dart
```

Expected: tests pass.

## Task 4: Production Glass Limit Diagnostics And Multiple Glass Support

**Files:**

- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Test `test/flutter_scene_adapter_material_test.dart`
- Update `docs/MATERIALS_AND_LIGHTING.md`

- [x] Add failing tests for multiple glass primitives:

```dart
test('multiple glass primitives share one background view and restore state',
    () async {
  final backend = FlutterSceneMaterialExtensionBackend(
    createTransmissionMaterial: (_) async =>
        flutter_scene.ShaderMaterial(isOpaqueOverride: false),
  );
  final sceneViews = <flutter_scene.RenderView>[];

  final first = _glassNode('first');
  final second = _glassNode('second');

  await backend.applyTransmissionPatch(
    sceneViews: sceneViews,
    node: first.node,
    primitive: first.primitive,
    address: first.address,
    patch: const MaterialPatch(transmission: 1.0),
  );
  await backend.applyTransmissionPatch(
    sceneViews: sceneViews,
    node: second.node,
    primitive: second.primitive,
    address: second.address,
    patch: const MaterialPatch(transmission: 1.0),
  );

  expect(sceneViews.where((view) => view.target != null), hasLength(1));
  expect(first.node.layers, FlutterSceneMaterialExtensionBackend.transmissiveLayer);
  expect(second.node.layers, FlutterSceneMaterialExtensionBackend.transmissiveLayer);
});
```

- [x] Add failing tests for mixed-node diagnostics:

```dart
test('glass on one primitive of a multi-primitive node reports limitation',
    () {
  final diagnostic = debugGlassNodeIsolationDiagnostic(
    primitiveCount: 2,
    selectedPrimitiveIndex: 0,
  );

  expect(diagnostic.code, ViewerDiagnosticCode.unsupportedMaterialFeature);
  expect(diagnostic.details['limitation'], 'nodeLayerIsolation');
});
```

- [x] Run red:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: failure because diagnostics and helper behavior do not exist.

- [x] Implement:
  - multiple active glass patch state with one background render view;
  - restore all original node layer/material states on reset, reload, and clear;
  - diagnostic for mixed-node glass when node-level layer isolation would remove
    non-glass primitives from the background capture;
  - documentation that authored GLB should separate glass parts into distinct
    nodes for production glass.

- [x] Run:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: tests pass.

## Task 5: Production Glass Shader Fixture Matrix

**Files:**

- Modify `assets/materials/fsviewer_transmission.fmat`
- Modify `test/flutter_scene_material_extension_backend_test.dart`
- Create or modify `docs/references/material_extension_shader_reference.md`
- Update `docs/references/flutter_scene_capability_notes.md`

- [x] Add GPU-gated visual tests for glass values:

```dart
test('production glass visual matrix responds to transmission and IOR',
    () async {
  if (!_runFlutterSceneGpuTests || !_runFlutterSceneVisualSmoke) {
    markTestSkipped(_flutterSceneVisualSmokeSkipReason);
    return;
  }

  final evidence = await renderGlassMatrixEvidence(
    transmissionValues: <double>[0.0, 0.5, 1.0],
    iorValues: <double>[1.0, 1.45, 1.85],
  );

  expect(evidence.refractionSpreadForTransmission1,
      greaterThan(evidence.refractionSpreadForTransmission0 + 20));
  expect(evidence.iorOffsetDelta, greaterThan(5));
});
```

- [x] Run red or skipped without GPU:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production glass visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Expected: failure until the fixture helper and stronger shader behavior exist.

- [x] Harden the glass shader:
  - use glTF KHR material-extension semantics and public PBR material concepts
    as the behavior reference for transmission, IOR, thickness, absorption,
    and refraction mode;
  - transmission `0.0` stays close to base material;
  - transmission `1.0` visibly samples background;
  - IOR changes offset magnitude;
  - thickness changes attenuation/refraction strength;
  - roughness softens/mixes background;
  - normal texture changes offset direction.

- [x] Document the glass reference mapping in
  `docs/references/material_extension_shader_reference.md`:
  - `MaterialPatch.transmission` maps to the glTF transmission concept, but
    the local backend uses a bounded screen-space background texture rather
    than full multi-bounce refraction;
  - `MaterialPatch.ior` changes the screen-space sample offset and Fresnel-like
    response;
  - `MaterialPatch.thickness` and attenuation fields affect absorption and
    offset strength where local shader inputs permit;
  - nested glass, caustics, path tracing, and order-independent transparency
    remain out of scope.

- [x] The test writes:

```text
tools/out/fsviewer_glass_matrix.png
```

- [x] Run the focused visual test again.

Expected: pass on the local verified GPU environment.

## Task 6: Production Clearcoat Lit Shader Parity

**Files:**

- Modify `assets/materials/fsviewer_clearcoat.fmat`
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Create or modify `docs/references/material_extension_shader_reference.md`
- Update `docs/references/flutter_scene_capability_notes.md`

- [x] Add failing CPU tests for clearcoat parameter binding:

```dart
test('production clearcoat binds all texture slots and factors', () async {
  final material = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
  final backend = FlutterSceneMaterialExtensionBackend(
    bindFallbackTextures: false,
    createClearcoatMaterial: (_) async => material,
  );

  await backend.applyClearcoatPatch(
    node: _paintNode.node,
    primitive: _paintNode.primitive,
    address: _paintNode.address,
    patch: const MaterialPatch(
      baseColorFactor: <double>[0.2, 0.1, 0.05, 1.0],
      metallic: 0.0,
      roughness: 0.7,
      clearcoat: 1.0,
      clearcoatRoughness: 0.05,
      clearcoatNormalScale: 0.8,
    ),
  );

  expect(material.useEnvironment, isTrue);
  expect(material.textureNames, containsAll(<String>[
    'baseColorTexture',
    'metallicRoughnessTexture',
    'normalTexture',
    'clearcoatTexture',
    'clearcoatRoughnessTexture',
    'clearcoatNormalTexture',
  ]));
});
```

- [x] Add GPU-gated visual tests:

```dart
test(
    'production clearcoat visual matrix responds to factor roughness texture and normal',
    () async {
  if (!_runFlutterSceneGpuTests || !_runFlutterSceneVisualSmoke) {
    markTestSkipped(_flutterSceneVisualSmokeSkipReason);
    return;
  }

  final evidence = await renderClearcoatMatrixEvidence(
    clearcoatValues: <double>[0.0, 0.5, 1.0],
    roughnessValues: <double>[0.02, 0.35, 0.8],
    includeNormalVariant: true,
  );

  expect(evidence.fullClearcoatHighlight,
      greaterThanOrEqualTo(evidence.zeroClearcoatHighlight));
  expect(evidence.roughClearcoatPeak,
      lessThanOrEqualTo(evidence.smoothClearcoatPeak));
  expect(evidence.clearcoatTextureFrameDelta, greaterThan(0.25));
  expect(evidence.normalVariantHighlightPositionDelta, greaterThan(0.1));
});
```

- [x] Run red or skipped without GPU:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production clearcoat visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Expected: failure until the fixture helper and shader upgrade exist.

- [x] Upgrade `fsviewer_clearcoat.fmat`:
  - use glTF KHR material-extension semantics and public PBR material concepts
    as the behavior reference for clearcoat strength, clearcoat roughness, and
    clearcoat normal;
  - use `shading_model: lit`;
  - fill `material.base_color`, `material.metallic`, `material.roughness`,
    `material.normal`, and `material.occlusion` for base PBR;
  - compute a separate clearcoat lobe from `clearcoat`,
    `clearcoatRoughness`, and `clearcoatNormal`;
  - add the clearcoat lobe through `material.emissive` so engine
    `EvaluateLighting(material)` still handles base PBR lighting;
  - never fake clearcoat by only lowering base roughness.

- [x] Document the clearcoat reference mapping in
  `docs/references/material_extension_shader_reference.md`:
  - `MaterialPatch.clearcoat` maps to a separate coating lobe, not base
    roughness mutation;
  - `MaterialPatch.clearcoatRoughness` controls only the coating lobe width;
  - `MaterialPatch.clearcoatNormalTexture` and
    `MaterialPatch.clearcoatNormalScale` perturb the coating lobe independently
    from the base normal where shader inputs permit;
  - any local approximation from routing the clearcoat contribution through
    `material.emissive` is recorded with visual evidence.

- [x] The test writes:

```text
tools/out/fsviewer_clearcoat_matrix.png
```

- [x] Run the CPU and GPU-gated visual tests again.

Expected: pass on the local verified GPU environment.

## Task 7: Production Texture Slot And UV0 Coverage

**Files:**

- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Modify `lib/src/internal/glb_material_extension_reader.dart`
- Test `test/glb_material_extension_reader_test.dart`
- Test `test/viewer_controller_material_test.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`

- [x] Add failing tests for every production texture-bearing extension slot:

```dart
test('authored clearcoat texture slots require UV0', () {
  final result = readGlbMaterialExtensionIntent(
    _glbWithClearcoatTextures(),
    partTree: _partTreeWithoutUv0,
  );

  expect(
    result.diagnostics.map((diagnostic) => diagnostic.code),
    everyElement(ViewerDiagnosticCode.missingUvSet),
  );
});

test('runtime production clearcoat texture patch is not persisted without UV0',
    () async {
  final controller = FlutterSceneViewerController();
  final sink = MaterialSink(
    partTree: _treeFor(address, hasTexCoords: false),
    materialExtensionSupport: const MaterialExtensionSupport(
      clearcoat: true,
      productionReady: true,
    ),
  );
  controller.attach(sink);

  await controller.setPartMaterial(
    address,
    const MaterialPatch(
      clearcoatTexture: TextureSource.asset('assets/clearcoat.png'),
    ),
  );

  expect(sink.materialCalls, isEmpty);
  expect(controller.materialOverrides.patchFor(address), isNull);
  expect(controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
});
```

- [x] Run red:

```sh
flutter test test/glb_material_extension_reader_test.dart test/viewer_controller_material_test.dart
```

Expected: failure where coverage is missing.

- [x] Implement missing UV0 validation for:
  - `transmissionTexture`;
  - `thicknessTexture`;
  - `clearcoatTexture`;
  - `clearcoatRoughnessTexture`;
  - `clearcoatNormalTexture`.

- [x] Run:

```sh
flutter test test/glb_material_extension_reader_test.dart test/viewer_controller_material_test.dart
```

Expected: tests pass.

## Task 8: three.js Reference Renderer Fixture Comparison

**Files:**

- Create `tools/reference_renderers/threejs_material_extension_fixture/package.json`
- Create `tools/reference_renderers/threejs_material_extension_fixture/render_reference.mjs`
- Create `tools/reference_renderers/threejs_material_extension_fixture/README.md`
- Modify `test/flutter_scene_material_extension_backend_test.dart`
- Create `docs/references/material_extension_visual_reference.md`
- Update `docs/references/flutter_scene_capability_notes.md`

- [x] Add failing tests for a shared fixture export path:

```dart
test('production visual fixture writes shared GLB for reference renderers',
    () async {
  if (!_runFlutterSceneGpuTests || !_runFlutterSceneVisualSmoke) {
    markTestSkipped(_flutterSceneVisualSmokeSkipReason);
    return;
  }

  final evidence = await renderProductionMaterialExtensionVisualMatrix(
    writeSharedFixture: true,
  );

  expect(evidence.sharedFixtureGlbPath, isNotNull);
  expect(File(evidence.sharedFixtureGlbPath!).existsSync(), isTrue);
  expect(evidence.flutterSceneGlassImagePath, endsWith('.png'));
  expect(evidence.flutterSceneClearcoatImagePath, endsWith('.png'));
});
```

- [x] Run red or skipped without GPU:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "shared GLB for reference renderers" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Expected: failure until the visual smoke fixture writes a reusable GLB and
reports the path.

- [x] Implement shared fixture output:
  - write `tools/out/fsviewer_material_extension_reference_fixture.glb`;
  - use the same geometry, camera framing, lights, material factors, textures,
    and UV0 data as the Flutter visual matrix;
  - include cases for transmission `0.0`, `0.5`, `1.0`, IOR variation,
    thickness/attenuation variation, clearcoat `0.0`, `0.5`, `1.0`,
    clearcoat roughness variation, and clearcoat normal variation.

- [x] Create the three.js reference harness:

```json
{
  "name": "fsviewer-threejs-reference-fixture",
  "private": true,
  "type": "module",
  "scripts": {
    "render": "node render_reference.mjs"
  },
  "dependencies": {
    "three": "^0.167.0",
    "puppeteer": "^23.0.0"
  }
}
```

- [x] Implement `render_reference.mjs` so it:
  - loads `tools/out/fsviewer_material_extension_reference_fixture.glb`;
  - uses three.js `GLTFLoader`;
  - relies on three.js `MeshPhysicalMaterial` handling for
    `KHR_materials_transmission`, `KHR_materials_ior`,
    `KHR_materials_volume`, and `KHR_materials_clearcoat`;
  - renders the same camera views as the Flutter visual matrix;
  - writes:

```text
tools/out/reference_threejs_glass_matrix.png
tools/out/reference_threejs_clearcoat_matrix.png
tools/out/material_extension_reference_metrics.json
```

- [x] Add trend metrics, not pixel-perfect image equality:
  - three.js transmission `1.0` must reveal/distort the background more than
    transmission `0.0`;
  - three.js IOR variation must move the refraction sample offset;
  - Flutter glass metrics must have the same monotonic direction as the
    three.js glass metrics;
  - three.js clearcoat `1.0` must produce a stronger second highlight than
    clearcoat `0.0`;
  - three.js higher clearcoat roughness must broaden or reduce peak highlight;
  - Flutter clearcoat metrics must have the same monotonic direction as the
    three.js clearcoat metrics.

- [x] Run the reference harness:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Expected: the three.js screenshots and metrics JSON are written under
`tools/out/`.

- [x] Update `docs/references/material_extension_visual_reference.md` with:
  - exact command lines;
  - generated artifact paths;
  - metric thresholds;
  - note that three.js is the primary external reference renderer;
  - note that no second external reference renderer is required for V1
    production evidence.

## Task 9: iOS Simulator Evidence And Deferred Platform Notes

**Files:**

- Modify `test/flutter_scene_material_extension_backend_test.dart`
- Create `docs/references/material_extension_platform_evidence.md`
- Update `docs/generated/capability_matrix.md`
- Update `docs/references/flutter_scene_capability_notes.md`

- [x] Create an evidence document that makes iOS Simulator the only 011
  production target:

```markdown
# Material Extension Platform Evidence

## 011 target

| Target | Flutter renderer | Glass shader load | Glass visual matrix | Clearcoat shader load | Clearcoat visual matrix | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iOS Simulator | Impeller + Flutter GPU | verified locally | verified locally | verified locally | verified locally | verified locally | Primary 011 target |

## Deferred targets

| Target | Renderer | Status | Notes |
| --- | --- | --- | --- |
| macOS local | Impeller + Flutter GPU | not run | Deferred from 011; prior experimental smoke is development evidence only |
| iOS physical device | Impeller + Flutter GPU | not run | Later device evidence plan |
| Android emulator/device | Impeller + Flutter GPU or platform backend | not run | Later platform hardening plan |
| Web | WebGL2 or future web backend | not run | Later platform hardening plan |
```

- [x] Add a single test target that can run all iOS Simulator production
  material visual evidence:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

- [x] Add test output artifacts:

```text
tools/out/fsviewer_ios_simulator_glass_matrix.png
tools/out/fsviewer_ios_simulator_clearcoat_matrix.png
tools/out/fsviewer_ios_simulator_material_extension_matrix.json
```

- [x] Update docs with exact command results. Use only:
  - `verified locally`;
  - `not run`;
  - `blocked`;
  - `candidate-only`;
  - `production-ready`.

- [x] Do not mark iOS Simulator production-ready until its row has shader load
  and visual matrix evidence.

- [x] Do not evaluate macOS, Android, Web, or iOS physical device in this plan.
  Keep those rows `not run` with notes that they are deferred from 011.

## Task 10: Public Production API And Default V1 Behavior

**Files:**

- Modify `lib/src/material_extension_policy.dart`
- Modify `lib/src/viewer_widget.dart`
- Modify `docs/PUBLIC_API.md`
- Modify `README.md`
- Test `test/viewer_widget_test.dart`
- Test `test/material_extension_policy_test.dart`

- [x] Add failing tests for V1 default policy decision:

```dart
test('FlutterSceneViewer default policy remains diagnostics-only until release flip',
    () {
  const viewer = FlutterSceneViewer.test(
    source: ModelSource.bytes(<int>[1]),
  );

  expect(
    viewer.materialExtensionPolicy,
    const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
  );
});

test('production shaders policy is the documented V1 opt-in', () {
  const policy = ViewerMaterialExtensionPolicy.productionShaders();

  expect(policy.enableTransmission, isTrue);
  expect(policy.enableClearcoat, isTrue);
});
```

- [x] Run:

```sh
flutter test test/viewer_widget_test.dart test/material_extension_policy_test.dart
```

Expected: tests pass while production remains opt-in.

- [x] After the iOS Simulator evidence table contains the required V1 target
  evidence, add a follow-up patch that flips the default only for the approved
  release scope if the user explicitly approves that change:

```dart
materialExtensionPolicy:
    const ViewerMaterialExtensionPolicy.productionShaders(),
```

- [x] Until that release flip is approved, docs must describe production
  backend support as opt-in and iOS Simulator-scoped:

```dart
FlutterSceneViewer(
  source: source,
  materialExtensionPolicy:
      const ViewerMaterialExtensionPolicy.productionShaders(),
)
```

## Task 11: Final Production Docs And Release Notes

**Files:**

- Modify `docs/PUBLIC_API.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Modify `docs/references/flutter_scene_capability_notes.md`
- Modify `docs/references/material_extension_shader_reference.md`
- Modify `docs/references/material_extension_platform_evidence.md`
- Modify `docs/generated/capability_matrix.md`
- Modify `README.md`
- Modify this plan.

- [x] Update docs to state:
  - glass production scope and limits;
  - clearcoat production scope and limits;
  - iOS Simulator as the only 011 production target;
  - macOS, Android, Web, and physical iOS device as not evaluated in 011;
  - glTF/PBR material concepts used as implementation references;
  - local shader approximations and why they are bounded;
  - three.js visual reference comparison method and thresholds;
  - unsupported or not-run targets;
  - shader load failure diagnostics;
  - no alpha-only glass fallback;
  - no low-roughness clearcoat fallback;
  - UV0 requirement;
  - combined glass + clearcoat status.

- [x] Run final non-GPU verification:

```sh
flutter test test/material_effect_mask_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart test/material_base_family_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

Expected: all pass. If Flutter SDK cache writes are blocked by the sandbox,
rerun the Flutter/Dart commands with required escalation.

- [x] Run GPU-gated production evidence locally:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Expected: pass on the compatible iOS Simulator environment and update
`docs/references/material_extension_platform_evidence.md` with exact iOS
Simulator results. If the command only runs a host macOS smoke, record that as
development evidence and keep iOS Simulator `not run` or `blocked`.

- [x] Run three.js reference comparison after the shared fixture GLB exists:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Expected: pass and update
`tools/out/material_extension_reference_metrics.json` with trend metrics that
match the Flutter visual matrix directionally.

- [x] Update this plan's progress log and verification log before stopping.

---

## Acceptance criteria

- [x] `ViewerMaterialExtensionPolicy.productionShaders()` exists and is
  documented.
- [x] Production support is not advertised by package-local shaders; preflight
  reports `candidate-only` until real production-quality capability exists.
- [x] Shader load failures produce diagnostics and do not persist overrides.
- [x] Glass supports multiple glass primitives and restores all state on reset,
  reload, and clear.
- [x] Glass reports diagnostics for unsupported node isolation or nested glass
  cases instead of producing misleading output.
- [x] Glass visual matrix proves candidate transmission, IOR, thickness,
  roughness, and normal influence on fixtures.
- [x] Clearcoat shader preserves base PBR lighting and adds a separate coating
  lobe.
- [x] Clearcoat visual matrix proves candidate factor, roughness, texture, and
  normal influence on fixtures.
- [x] `docs/references/material_extension_shader_reference.md` documents
  glTF/PBR behavior references, local shader approximations, and
  license/attribution boundaries.
- [x] The same fixture GLB renders through three.js, and Flutter visual metrics
  move in the same direction as the three.js reference metrics.
- [x] No second external reference renderer is required for V1 production
  evidence.
- [x] UV0 is required for all texture-bearing glass and clearcoat slots.
- [x] iOS Simulator evidence uses literal labels and does not overclaim.
- [x] macOS, Android, Web, and physical iOS device are explicitly marked
  `not run` or deferred from 011.
- [x] Docs keep package-local glass and clearcoat `candidate-only` and do not
  advertise production support.

## Progress log

- 2026-07-03: Created plan after user decision to make glass and clearcoat
  production inside this repository instead of waiting for upstream
  `flutter_scene` extension support. Assumption: production means verified,
  bounded, diagnostic-backed support on documented platforms, not perfect
  offline/path-traced glTF material parity.
- 2026-07-03: Updated plan to use three.js as the primary external visual
  reference renderer for the same fixture GLB. No second external reference
  renderer is required for V1 production evidence.
- 2026-07-03: Updated plan to use glTF/PBR material semantics as the primary
  implementation reference for package-local glass and clearcoat shaders,
  while keeping three.js as the visual reference renderer and Apple platform
  API checks as scope checks only.
- 2026-07-03: Narrowed 011 to iOS Simulator-first production hardening.
  macOS, Android, Web, and physical iOS device evidence are deferred/not run
  in this plan and should move to a later plan only after the iOS Simulator
  path is solved end-to-end.
- 2026-07-03: Implemented Task 1 production policy contract. Added
  `ViewerMaterialExtensionPolicy.productionShaders()`,
  `ViewerMaterialExtensionMode.productionFlutterSceneShaders`, and
  `MaterialExtensionSupport.productionReady`. Production policy requests
  glass and clearcoat by default, but adapter routing does not advertise the
  backend until production support is marked ready by later preflight work.
- 2026-07-03: Implemented Task 2 backend preflight. Added cached production
  shader preflight, injectable shader-library loading for tests, typed
  `shaderPreflight` diagnostics, and runtime adapter/viewer sink support so
  production policy stays unsupported until preflight succeeds. Updated the
  capability matrix to use literal `candidate-only` status for the preflight
  path until iOS Simulator visual evidence exists.
- 2026-07-03: Implemented Task 3 render-texture lifecycle hardening. Added
  viewport and pixel-ratio propagation from the widget render surface into the
  material extension backend, bounded background render texture sizing,
  resize-on-change behavior, debug lifecycle counters, and `clear()` cleanup
  for render views, active patch state, background texture, and cached
  production preflight state.
- 2026-07-03: Implemented Task 4 glass backend state and isolation
  hardening. Multiple glass primitives on separate nodes now share one
  background render view, transmission state is tracked separately from
  clearcoat state, `clear()` restores saved node layers and primitive
  materials, and glass on a single primitive of a multi-primitive node reports
  an explicit `nodeLayerIsolation` diagnostic.
- 2026-07-03: Implemented Task 5 production glass visual matrix. Added a
  GPU-gated matrix helper and evidence type, wrote
  `tools/out/fsviewer_glass_matrix.png`, tightened the visual metric to sample
  panel interiors, and increased the shader's bounded IOR/thickness
  screen-space offset so IOR changes are visibly measurable. Added
  `docs/references/material_extension_shader_reference.md` with glass mapping,
  local screen-space approximation limits, and source/license boundaries.
- 2026-07-03: Implemented Task 6 production clearcoat lit shader parity. Added
  CPU binding coverage for all clearcoat texture slots and factors, switched
  the production clearcoat runtime loader to lit `.fmat` metadata through
  `PreprocessedMaterial`, filled base `MaterialInputs` fields, and added a
  separate clearcoat lobe through `material.emissive`. Debugging found that
  rendering a lit `.fmat` through `ShaderMaterial` crashed the local Flutter
  tester because the lit engine uniform block is not bound by that wrapper.
  Added `tools/out/fsviewer_clearcoat_matrix.png` visual evidence for
  clearcoat factor, roughness, and normal trends on the local host GPU path.
- 2026-07-03: Implemented Task 7 UV0 coverage for production material
  extension texture slots. Authored GLB diagnostics and runtime controller
  diagnostics now include exact `textureSlots` for UV0 failures covering
  `transmissionTexture`, `thicknessTexture`, `clearcoatTexture`,
  `clearcoatRoughnessTexture`, and `clearcoatNormalTexture`. `TEXCOORD_1`
  does not satisfy the requirement.
- 2026-07-03: Implemented Task 8 shared visual reference fixture. Added a
  GPU-gated Flutter fixture helper that writes
  `tools/out/fsviewer_material_extension_reference_fixture.glb`, created the
  three.js reference harness, and wrote reference screenshots plus trend
  metrics. The GLB carries UV0-bearing material-extension cases; the three.js
  clearcoat view reuses the loaded GLB clearcoat materials on sphere geometry
  so clearcoat highlight trends are measurable.
- 2026-07-03: Implemented Task 9 platform evidence gating. Added the iOS
  Simulator visual-matrix test target and
  `docs/references/material_extension_platform_evidence.md`. The local run
  skipped because the current Flutter test target reported `android`, so iOS
  Simulator remains `candidate-only`/`not run`. macOS, Android, Web, and
  physical iOS device evidence remain deferred/not run for 011.
- 2026-07-03: Implemented Task 10 public production API/default behavior
  updates. The viewer default remains diagnostics-only; production shaders are
  documented as an explicit opt-in through
  `ViewerMaterialExtensionPolicy.productionShaders()` and are scoped to
  verified targets.
- 2026-07-03: Implemented Task 11 documentation pass. Public API, material
  scope, runtime pipeline, shader reference, platform evidence, capability
  matrix, README, and visual-reference docs now describe glass and clearcoat
  production policy scope, bounded shader approximations, UV0 requirements,
  shader preflight diagnostics, three.js trend comparison, combined material
  status, and deferred/non-run platform evidence without overclaiming iOS
  Simulator readiness.
- 2026-07-03: Added the missing clearcoat texture visual-matrix assertion
  before final verification. The GPU-gated clearcoat matrix now checks
  clearcoat factor, clearcoat roughness, clearcoat texture influence, and
  clearcoat normal movement.
- 2026-07-03: Added root `.gitignore` coverage for local Node/npm dependency
  directories and logs after `npm install` made the reference harness
  `node_modules/` tree appear as thousands of untracked files. The tracked
  harness remains the small package/lockfile/readme/render script set.
- 2026-07-03: Collected actual iOS Simulator evidence with a temporary
  Flutter `integration_test` app under `/private/tmp/fsviewer_ios_evidence_app`
  after confirming package-level `flutter test -d` still runs in the host
  tester. The `iPhone 17` iOS Simulator run passed, wrote iOS glass/clearcoat
  PNGs and metrics JSON under `tools/out/`, and keeps macOS, Android, Web, and
  physical iOS evidence deferred/not run.
- 2026-07-03: Follow-up real-model visual inspection found that the clearcoat
  backend overclaimed readiness for textured production GLBs. Khronos
  ready-authored clearcoat samples were mostly material spheres/test fixtures,
  and `DamagedHelmet` manual-clearcoat iOS Simulator evidence showed source PBR
  detail loss. Hardened the clearcoat path by bounding the additive coating
  lobe's clipped highlight area and preserving source PBR occlusion/emissive
  slots in the `.fmat` clearcoat backend. The focused tests now cover both
  regressions. The real-model `DamagedHelmet` output is still
  `candidate-only`, not `production-ready`, because visual inspection still
  shows overly stylized/striped clearcoat behavior on that GLB.
- 2026-07-03: Installed and verified Pillow 12.3.0 in
  `/private/tmp/fsviewer_pillow_env` for local image inspection. Updated public
  docs, the generated capability matrix, and reference evidence notes to keep
  clearcoat honest: shader-load and synthetic visual-matrix evidence pass on
  iOS Simulator, but real textured GLB clearcoat remains `candidate-only` and
  not `production-ready`. Glass iOS Simulator evidence remains verified
  locally. macOS, Android, Web, and physical iOS evidence remain deferred/not
  run for 011.
- 2026-07-03: Reworked the clearcoat coating lobe after real-model inspection.
  The `.fmat` shader no longer uses a fixed synthetic highlight direction; it
  computes the coating contribution from engine lighting inputs, IBL
  prefiltered radiance, BRDF LUT data, directional light, and shadow state.
  The backend now marks whether an explicit clearcoat normal texture is bound,
  and the shader falls back to the base material normal when no clearcoat
  normal texture exists. This reduces the white veil on `DamagedHelmet`, but
  the real textured GLB result still remains `candidate-only` because visual
  inspection shows clearcoat/detail artifacts rather than production-quality
  coated material behavior.
- 2026-07-03: Final real-asset review rejected the package-local glass and
  clearcoat paths as production visuals. Root cause: the current `flutter_scene`
  material surface does not expose real transmission or clearcoat material
  inputs, so package-local glass is bounded screen-space approximation and
  package-local clearcoat must route a coating approximation through emissive.
  The fix is to stop advertising production support from package-local shader
  preflight. `productionShaders()` remains a production-intent policy, but
  preflight now returns `candidate-only` diagnostics and unsupported support
  until real upstream material-extension capability or a better renderer
  contract exists.
- 2026-07-04: Follow-up visual-quality hardening after real-model review. Root
  cause evidence showed clearcoat replacement was overwriting the source GLB
  material instead of preserving authored PBR detail. The backend now keeps the
  source primitive material in place, adds a shared-geometry translucent
  clearcoat overlay primitive, and restores that overlay on reset/clear. The
  clearcoat `.fmat` changed from opaque replacement to alpha overlay. Glass
  shader material setup now preserves `doubleSided` source culling by disabling
  back-face culling only when the source material requests it. ToyCar iOS
  Simulator evidence now renders authored glass and clearcoat together in one
  diagonal real-asset view while keeping production support `candidate-only`.

## Verification log

- 2026-07-03: verified locally for plan-only creation:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified locally after adding the three.js reference-renderer
  quality gate: `python3 tools/repo_lint.py` passed and `git diff --check`
  reported no whitespace errors.
- 2026-07-03: verified locally after adding the glTF/PBR implementation
  reference strategy: `python3 tools/repo_lint.py` passed and
  `git diff --check` reported no whitespace errors.
- 2026-07-03: verified locally after narrowing 011 to iOS Simulator-first
  production hardening and deferring macOS, Android, Web, and physical iOS
  device evidence: `python3 tools/repo_lint.py` passed and `git diff --check`
  reported no whitespace errors.
- 2026-07-03: verified locally after removing restricted external engine names
  from the public implementation-reference wording: a targeted name scan found
  no matches, `python3 tools/repo_lint.py` passed, and `git diff --check`
  reported no whitespace errors.
- 2026-07-03: verified red for Task 1:
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart` failed before implementation
  because `ViewerMaterialExtensionPolicy.productionShaders()` and
  `ViewerMaterialExtensionMode.productionFlutterSceneShaders` did not exist.
  The first sandboxed attempt was blocked by Flutter SDK cache writes and was
  rerun with escalation.
- 2026-07-03: verified locally for Task 1:
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 11 tests after
  rerunning with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 2 backend preflight:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name production` failed before implementation because
  `loadShaderLibrary`, `MaterialExtensionShaderLibrary`, and
  `preflightProductionSupport` did not exist.
- 2026-07-03: verified red for Task 2 viewer sink support:
  `flutter test test/viewer_widget_test.dart --plain-name "production
  material extension policy waits for preflight support"` failed because
  production policy still let transmission intent reach the adapter without
  preflight-backed support.
- 2026-07-03: verified locally for Task 2:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  test/viewer_widget_test.dart` passed 37 tests with 5 GPU-gated skips after
  rerunning with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 3 backend lifecycle:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name viewport` failed before implementation because
  `updateViewport`, `debugBackgroundTextureSize`, `debugActivePatchCount`, and
  `debugHasProductionPreflight` did not exist.
- 2026-07-03: verified red for Task 3 widget viewport forwarding:
  `flutter test test/viewer_widget_test.dart --plain-name "viewer passes
  viewport size and pixel ratio"` failed before implementation because the
  render-surface boundary did not pass viewport size or device pixel ratio.
- 2026-07-03: verified locally for Task 3:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  test/viewer_widget_test.dart` passed 40 tests with 5 GPU-gated skips after
  rerunning with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 4:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart` failed before implementation
  because `debugGlassNodeIsolationDiagnostic` did not exist and backend
  `clear()` left glass nodes on the transmissive layer instead of restoring
  original layers/materials.
- 2026-07-03: verified locally for Task 4:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 15 tests with 5
  GPU-gated skips after rerunning with escalation for Flutter SDK cache
  access.
- 2026-07-03: verified red for Task 5:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production glass visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` failed before implementation because
  `renderGlassMatrixEvidence` did not exist. An intermediate run then exposed
  that the first metric sampled adjacent background outside the
  `transmission: 0.0` panel; after tightening the metric, a second run exposed
  insufficient IOR movement in the shader.
- 2026-07-03: verified locally for Task 5 GPU visual evidence:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production glass visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused visual-smoke test and wrote
  `tools/out/fsviewer_glass_matrix.png`.
- 2026-07-03: verified locally for Task 5 non-GPU compile/skip path:
  `flutter test test/flutter_scene_material_extension_backend_test.dart`
  passed 10 tests with 6 GPU-gated skips after rerunning with escalation for
  Flutter SDK cache access.
- 2026-07-03: verified red for Task 6:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` failed before implementation because
  `renderClearcoatMatrixEvidence` did not exist. A second compile red exposed
  a const-list assertion issue in the new CPU test, which was corrected before
  implementation.
- 2026-07-03: recorded Task 6 debugging evidence:
  `clearcoat fmat shader loads through generated shader bundle` passed, while
  rendering the initial `shading_model: lit` shader through `ShaderMaterial`
  crashed the Flutter tester with a segmentation fault during finalization.
  Switching the production loader to `PreprocessedMaterial` fixed the crash by
  using the wrapper that binds `FragInfo` and engine lighting resources for lit
  `.fmat` materials.
- 2026-07-03: verified locally for Task 6 non-GPU compile/skip path:
  `flutter test test/flutter_scene_material_extension_backend_test.dart`
  passed 11 tests with 8 GPU-gated skips after rerunning with escalation for
  Flutter SDK cache access.
- 2026-07-03: verified locally for Task 6 GPU visual evidence:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused visual-smoke test and wrote
  `tools/out/fsviewer_clearcoat_matrix.png`.
- 2026-07-03: verified red for Task 7:
  `flutter test test/glb_material_extension_reader_test.dart
  test/viewer_controller_material_test.dart` failed before implementation
  because authored and runtime missing-UV diagnostics did not include
  `textureSlots`.
- 2026-07-03: verified locally for Task 7:
  `flutter test test/glb_material_extension_reader_test.dart
  test/viewer_controller_material_test.dart` passed 31 tests after rerunning
  with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 8:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "shared GLB for reference renderers"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` failed before implementation because
  `renderProductionMaterialExtensionVisualMatrix` did not exist.
- 2026-07-03: verified locally for Task 8 Flutter fixture generation:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "shared GLB for reference renderers"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused visual-smoke test and wrote the
  shared GLB plus Flutter matrix image paths.
- 2026-07-03: verified locally for Task 8 reference harness:
  `npm install --prefix
  tools/reference_renderers/threejs_material_extension_fixture` passed with no
  vulnerabilities. The first `npm run render --prefix
  tools/reference_renderers/threejs_material_extension_fixture` failed because
  Puppeteer's bundled Chrome for Testing could not spawn on this host
  (`spawn Unknown system error -88`); the harness was updated to use an
  installed Chrome binary with a temporary profile under `tools/out/`.
  Follow-up runs fixed browser module CORS/import-map issues and clearcoat
  metric framing. The final `npm run render --prefix
  tools/reference_renderers/threejs_material_extension_fixture` passed and
  wrote `tools/out/reference_threejs_glass_matrix.png`,
  `tools/out/reference_threejs_clearcoat_matrix.png`, and
  `tools/out/material_extension_reference_metrics.json`.
- 2026-07-03: verified locally for Task 9 test target:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "ios simulator production material extension visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` completed with the test skipped. Evidence status is
  `not run` for iOS Simulator because the current Flutter test target reported
  `android`, not iOS.
- 2026-07-03: verified locally for Task 10:
  `flutter test test/viewer_widget_test.dart
  test/material_extension_policy_test.dart` passed 39 tests after rerunning
  with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 11 clearcoat texture matrix coverage:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` failed before implementation because
  `ClearcoatMatrixEvidence.clearcoatTextureHighlightDelta` did not exist.
- 2026-07-03: verified locally for Task 11 clearcoat texture matrix coverage:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused visual-smoke test after adding the
  texture influence comparison.
- 2026-07-03: verified locally for final focused test bundle:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/material_base_family_test.dart
  test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart
  test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart`
  passed 111 tests with 10 GPU-gated skips after rerunning with escalation for
  Flutter SDK cache access.
- 2026-07-03: verified final harness:
  `bash tools/run_checks.sh` first failed at `flutter analyze` on one
  `prefer_const_constructors` lint and two unnecessary null checks in
  `test/flutter_scene_material_extension_backend_test.dart`; after cleanup,
  `bash tools/run_checks.sh` passed repo lint, Dart format check, `flutter pub
  get`, `flutter analyze`, and full `flutter test` with 180 passing tests and
  13 GPU-gated skips.
- 2026-07-03: verified final repo lint and whitespace:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors after the `.gitignore` update.
- 2026-07-03: verified final iOS Simulator evidence command:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "ios simulator production material extension visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` completed with the test skipped. Evidence status
  remains `not run` for iOS Simulator because the current Flutter test target
  reported `android`, not iOS.
- 2026-07-03: verified actual iOS Simulator evidence with a temporary
  `integration_test` app:
  `flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059
  --driver=test_driver/ios_material_extension_evidence_test.dart
  --target=integration_test/ios_material_extension_evidence_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed on the `iPhone 17` iOS Simulator. It wrote
  `tools/out/fsviewer_ios_simulator_glass_matrix.png`,
  `tools/out/fsviewer_ios_simulator_clearcoat_matrix.png`, and
  `tools/out/fsviewer_ios_simulator_material_extension_matrix.json`. Metrics:
  glass transmission spread increased from `14` to `239`, IOR delta was
  `5.111805555555556`, clearcoat highlight increased from `242` to `254`, and
  rough clearcoat peak `250` stayed below smooth peak `254`.
- 2026-07-03: verified final three.js reference comparison:
  `npm install --prefix tools/reference_renderers/threejs_material_extension_fixture`
  reported `up to date`, and `npm run render --prefix
  tools/reference_renderers/threejs_material_extension_fixture` exited 0 and
  regenerated the reference outputs. Browser process hygiene check found no
  leftover `python3 -m http.server 4173`, Playwright/Puppeteer/webdriver,
  `HeadlessChrome`, or Chrome remote-debugging processes beyond the check
  command itself.
- 2026-07-03: verified local dependency hygiene:
  after adding `node_modules/` to `.gitignore`,
  `git status --short --untracked-files=all | wc -l` reported 51 entries
  instead of thousands from the reference harness dependency tree; only the
  harness source files and `package-lock.json` remain visible under
  `tools/reference_renderers/threejs_material_extension_fixture/`.
- 2026-07-03: verified red for follow-up real-model clearcoat hardening:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat shader renders distinct second specular lobe smoke"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` failed before the shader energy change because
  `clearcoatFullClippedFraction` was `0.0398943971839249`, above the new
  `<0.02` clipping guard.
- 2026-07-03: verified locally for follow-up clearcoat highlight hardening:
  after lowering the clearcoat lobe energy and regenerating
  `build/shaderbundles/materials.shaderbundle`, the same focused command
  passed.
- 2026-07-03: verified red for source PBR preservation:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat loader configures lit fmat parameters"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` failed before implementation because
  `occlusionTexture` was `null` on the clearcoat `PreprocessedMaterial`.
- 2026-07-03: verified locally after preserving source occlusion/emissive slots:
  the same focused loader command passed, and the clearcoat visual-smoke command
  above also passed.
- 2026-07-03: verified actual iOS Simulator real-model candidate evidence with
  a temporary `integration_test` app:
  `flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059
  --driver=test_driver/ios_material_extension_evidence_test.dart
  --target=integration_test/ios_material_extension_evidence_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed on the `iPhone 17` iOS Simulator for the
  `DamagedHelmet` manual-clearcoat demo and wrote
  `tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_baseline.png`,
  `tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_enhanced.png`,
  `tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_diff.png`,
  and `tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat.json`.
  Pillow 12.3.0 was installed in `/private/tmp/fsviewer_pillow_env` for local
  image inspection. Metrics after the source-slot fix: frame delta
  `9.24758616255144`, enhanced luma mean `170.0`, bright `>240` fraction
  `0.004`, bright `>250` fraction `0.0016`. Visual status remains
  `candidate-only` rather than `production-ready`.
- 2026-07-03: verified local Pillow installation for image inspection:
  `/private/tmp/fsviewer_pillow_env/bin/python - <<'PY' ... from PIL import
  Image ... PY` printed `Pillow OK 12.3.0`.
- 2026-07-03: verified documentation claim narrowing after the real-model
  clearcoat finding: a targeted `rg` scan found no remaining clearcoat row
  claiming `Supported on iOS Simulator`; remaining `production-ready` matches
  are negated or release-blocker wording. `python3 tools/repo_lint.py` passed
  and `git diff --check` reported no whitespace errors.
- 2026-07-03: verified red for clearcoat normal fallback hardening:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production clearcoat binds all texture slots and factors"`
  failed before implementation because the clearcoat-normal-present flag in
  `normalFactors.z` was `0.0` even when `clearcoatNormalTexture` was bound.
- 2026-07-03: verified locally after the engine-lighting clearcoat lobe and
  normal fallback changes: `production clearcoat binds all texture slots and
  factors`, `production clearcoat loader configures lit fmat parameters`,
  `clearcoat fmat uses engine lighting inputs for coating lobe`, `clearcoat
  shader renders distinct second specular lobe smoke`, and `production
  clearcoat visual matrix` passed with the documented Flutter GPU/visual-smoke
  defines where required.
- 2026-07-03: verified actual iOS Simulator real-model candidate evidence after
  reducing the coating lobe energy and using base normal fallback:
  `flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059
  --driver=test_driver/ios_material_extension_evidence_test.dart
  --target=integration_test/ios_material_extension_evidence_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed on the `iPhone 17` iOS Simulator. The
  `DamagedHelmet` manual-clearcoat metrics were frame delta
  `6.942640817901235`, color spread `220`, and highlight `235`. The current
  side-by-side artifact is
  `tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_side_by_side.png`.
  Visual status remains `candidate-only`, not `production-ready`.
- 2026-07-03: verified red for final production-support downgrade:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "production preflight keeps local shaders candidate-only"`
  failed before implementation because shader preflight still returned
  `productionReady == true`.
- 2026-07-03: verified locally after disabling package-local production
  advertisement: the same focused preflight command passed, and
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart
  test/viewer_controller_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "production"` passed with five GPU-gated skips.
- 2026-07-04: verified red for clearcoat overlay hardening: `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat"` failed before implementation because
  `assets/materials/fsviewer_clearcoat.fmat` still used `blending: opaque` and
  `clearcoat adds translucent overlay without replacing source material`
  observed only one mesh primitive.
- 2026-07-04: verified locally after clearcoat overlay hardening: `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "clearcoat"` passed with four GPU-gated skips.
- 2026-07-04: verified red for glass double-sided culling hardening: `flutter
  test test/flutter_scene_material_extension_backend_test.dart --plain-name
  "preserves double-sided source culling"` failed before implementation because
  the glass `ShaderMaterial` still used `CullMode.backFace`.
- 2026-07-04: verified locally after glass double-sided culling hardening:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "preserves double-sided source culling"` passed.
- 2026-07-04: verified locally for focused backend behavior after the visual
  quality changes: `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "experimental"` passed with one GPU-gated skip.
- 2026-07-04: attempted iOS Simulator ToyCar evidence once and rejected the
  result as invalid because Xcode failed to build the updated integration test
  (`RenderCameraFrame` import missing) and the previously installed
  DamagedHelmet test app ran. After importing the internal render-frame type,
  re-ran `flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059
  --driver=test_driver/ios_material_extension_evidence_test.dart
  --target=integration_test/ios_material_extension_evidence_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu`; the `iOS Simulator ToyCar glass and clearcoat demo`
  passed on the `iPhone 17` iOS Simulator. Metrics were frame delta
  `0.8378311471193416`, color spread `249`, and highlight `248`. Artifacts:
  `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_baseline.png`,
  `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_enhanced.png`,
  `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_side_by_side.png`,
  and `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json`.
- 2026-07-04: verified final focused material regression bundle after the
  visual-quality hardening: `flutter test test/material_effect_mask_test.dart
  test/material_patch_test.dart test/viewer_controller_material_test.dart
  test/material_base_family_test.dart test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart
  test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart test/viewer_widget_test.dart`
  passed 114 tests with 10 GPU-gated skips after rerunning with escalation for
  Flutter SDK cache access.
- 2026-07-04: verified final repository checks after the visual-quality
  hardening: `bash tools/run_checks.sh` passed repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and full `flutter test` with 183
  passing tests and 13 GPU-gated skips; `python3 tools/repo_lint.py` passed;
  `git diff --check` reported no whitespace errors.
- 2026-07-04: ran the exact host-side GPU smoke command from this plan:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "ios simulator production material extension visual matrix"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu`. It completed with the test skipped because the
  package test runner reported `current target is android`; the valid iOS
  Simulator evidence for this follow-up remains the `flutter drive` ToyCar run
  above.
- 2026-07-04: verified final three.js reference comparison after the shared
  fixture GLB existed: `npm install --prefix
  tools/reference_renderers/threejs_material_extension_fixture` reported
  `up to date`; the first sandboxed `npm run render --prefix
  tools/reference_renderers/threejs_material_extension_fixture` failed with
  `listen EPERM: operation not permitted 127.0.0.1`, then the escalated rerun
  exited 0 and regenerated
  `tools/out/reference_threejs_glass_matrix.png`,
  `tools/out/reference_threejs_clearcoat_matrix.png`, and
  `tools/out/material_extension_reference_metrics.json`. Final reference
  metrics: glass transmission spread `24 -> 37`, IOR delta
  `32.43768240567021`, clearcoat highlight `242 -> 244`, and rough clearcoat
  peak `242` below smooth peak `244`.
- 2026-07-04: verified browser-driven test hygiene after the three.js run:
  `ps -axo pid,ppid,stat,command | egrep
  'threejs-reference-chrome-profile|puppeteer|HeadlessChrome|Google
  Chrome.*remote-debugging|webdriver'` showed no leftover test browser,
  Puppeteer, webdriver, HeadlessChrome, or remote-debugging Chrome processes
  beyond the check command itself.
