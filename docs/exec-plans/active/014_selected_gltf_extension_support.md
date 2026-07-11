# Selected glTF Material, Texture, and Compression Extension Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Use the
> repo-local `pbr-materials` skill for every material, shader, IBL, lighting,
> or renderer-boundary decision. Steps use checkbox (`- [ ]`) syntax for
> tracking.

## Goal

Support the selected glTF material, texture, sampler, and compression
extensions required by production configurator assets as honest runtime
behavior, without texture baking, asset-specific material mutation, a second
general PBR renderer, or false capability claims.

## Architecture

Keep `flutter_scene_viewer` as the high-level viewer/configurator wrapper.
The wrapper owns GLB preflight, decoder rewrites, stable public texture-binding
data, persistence, validation, diagnostics, and evidence. BRDF/BTDF
integration, per-slot texture sampling, IBL, refraction compositing, and
precision choices belong in the pinned `flutter_scene` renderer or in an
explicitly separated, target-scoped candidate backend; a missing renderer
feature remains diagnostic until a real backend implements it.

Filament and Karis are shading references, not rendering backends. Khronos
glTF specifications are normative for fields, defaults, channels, color
spaces, and extension interactions. Frostbite informs coherent lighting-state
evidence only; atmosphere and cloud rendering remain out of scope.

## Tech Stack

Dart, Flutter, `flutter_scene` pinned at
`cd6760912fa38beb55f63e388655a1aeabd32fe4`, Flutter GPU/Impeller on native,
the pinned WebGL2 path on web, package-local GLB readers/rewriters, optional
Draco and BasisU sibling plugins, Khronos sample assets and validator, and
reproducible target evidence.

## Global Constraints

- Work on the current branch. Do not create or switch branches unless the user
  explicitly asks.
- Do not post GitHub issues, pull requests, comments, or reviews through a
  connector identity.
- Do not add a Filament backend, general shader graph, custom PBR renderer,
  texture bake, UV generation, CAD repair, or asset-name-based material fix.
- Keep `TextureSource` as source-location data. Sampler, UV-set, and transform
  metadata must be separate and reusable per material slot.
- Required unsupported extensions fail before adapter import with an
  actionable typed diagnostic.
- Optional unsupported extensions with valid core fallback load the fallback
  and report a non-blocking diagnostic.
- Malformed optional extension data with valid core fallback is ignored with a
  diagnostic; malformed required data fails.
- Remove an extension declaration after rewrite only when every use was
  decoded and rewritten successfully.
- Never let an unsupported material extension discard a valid core material or
  core texture patch.
- Never let one unsupported authored material-extension family discard a
  different supported authored extension family. Imported extension intent is
  isolated into `opaqueIor`, `specular`, `clearcoat`, and
  `transmissionVolume` groups before validation and application.
- Use these evidence labels literally: `verified locally`, `not run`,
  `blocked`, `candidate-only`, `release pending`, and `production-ready`.
- Treat evidence and release maturity as separate axes. `candidate-only` may
  coexist with target evidence labeled `verified locally`; neither label
  implies the other.
- Make runtime capability, evidence, and release claims per feature and target.
  A single aggregate `productionReady` value must not authorize an individual
  extension or an unverified platform.
- Simulator evidence may be `verified locally`; it is not physical-device or
  cross-platform `production-ready` evidence.
- Single-file GLB is this plan's container scope. Bounded multi-file `.gltf`
  resolution remains a separate deferred slice; no charter expansion is
  required merely to defer it.

---

## Status and lineage

This is the only canonical active plan for the selected extension work.

- Completed Plan 013 supplies the bounded ingestion/compression baseline:
  [`013_v2_production_glb_pipeline.md`](../completed/013_v2_production_glb_pipeline.md).
  Its checked boxes do not complete this plan.
- Deferred Plan 012 preserves historical package-local shader work and iOS
  Simulator evidence:
  [`012_material_extension_production_readiness.md`](../deferred/012_material_extension_production_readiness.md).
  Its unfinished correctness, ownership, and release work is absorbed here.
- The former parallel
  `docs/superpowers/plans/2026-07-05-full-gltf-extension-support.md` source was
  promoted into this file and removed to avoid two sources of truth.

No runtime acceptance item is inherited as complete. Existing behavior is
reclassified below and must pass this plan's stricter gates.

## Authority and ownership

| Claim or work | Authority / owner |
| --- | --- |
| glTF fields, defaults, channels, color space, transforms, and extension interactions | Khronos glTF 2.0 and ratified extension text |
| Current renderer capability | Pinned `flutter_scene` source, adapter path, tests, and target evidence |
| BRDF, clearcoat, and real-time IBL audit direction | Filament material-system documentation and Karis 2013 |
| Coherent background, IBL, key light, exposure, reflections, and shadows | Viewer lighting contract; Frostbite is reference context only |
| Public API, serialization, validation, persistence, diagnostics | `flutter_scene_viewer` |
| Core BRDF/BTDF, per-slot shader sampling, IBL, refraction compositing | Upstream `flutter_scene` or explicitly separated renderer backend |
| Draco and BasisU decoding | Optional sibling native plugins; the root package owns bounded GLB rewrite |

The repo-local reference package is
[`.agents/skills/pbr-materials/SKILL.md`](../../../.agents/skills/pbr-materials/SKILL.md).

## Current verified baseline

| Capability | Current label entering Plan 014 |
| --- | --- |
| GLB preflight and typed diagnostics | `verified locally` |
| Embedded-GLB `EXT_meshopt_compression` rewrite | `verified locally`; conformance and decode budgets still open |
| `KHR_draco_mesh_compression` | iOS Simulator A1B32 `verified locally`; Android runtime `not run` |
| `KHR_texture_basisu` / KTX2 | bounded level-0 iOS Simulator path `verified locally`; authored mip preservation and Android runtime open |
| Package-local clearcoat shader | `candidate-only`; iOS Simulator evidence `verified locally` |
| Package-local transmission/volume shader | `candidate-only`; bounded iOS Simulator evidence `verified locally` |
| `KHR_materials_specular` | parsed/preserved and diagnostic-only; renderer application absent |
| Opaque `KHR_materials_ior` | incorrect classification; IOR-only material currently enters glass handling |
| `KHR_texture_transform` and GLB samplers | unsupported in public binding and standard adapter paths |
| Physical iOS, Android material rendering, and Web material rendering | `not run` |

## Assumptions

- A1B32 remains the immediate real-asset gate. It requires Draco,
  `KHR_materials_specular`, and `KHR_materials_ior`.
- Glorvia runtime fabric uses repeat 2.5 for front/back albedo and normal
  textures. Runtime binding metadata must express that without generated tiled
  image bytes.
- The same image may be bound to multiple slots with different UV sets,
  transforms, or sampler state.
- The pinned `flutter_scene` PBR path already provides GGX/Smith/Schlick and
  split-sum IBL lineage, but it does not expose the selected glTF material
  extension inputs as first-class runtime fields.
- Upstream renderer work is an explicit dependency gate. Do not edit the pub
  cache or claim support while waiting for a pinned upstream capability.

## Milestones and execution order

Plan 014 remains the only active plan, but its tasks are reviewed through five
independent milestones so unrelated renderer and decoder work does not share a
single acceptance decision:

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: truthful baseline | 1, 2, then 5 | Capability/evidence claims are honest, authored patch families are isolated, asset-specific mutation is removed, and the fixed lighting state exists. |
| M2: texture binding | 3, 4, then 6 | Public bindings preserve slot, UV, transform, and sampler intent; Glorvia repeat 2.5 is applied by a real renderer path or the milestone remains `blocked`. |
| M3: A1B32 material gate | 7 | Draco, specular, and opaque IOR render without material hacks under the fixed state. |
| M4: layered and transmissive materials | 8 and 9 | Clearcoat and glass are renderer-native or remain explicitly deferred without a production claim. |
| M5: decoder and release evidence | 10 and 11 | Decoder budgets/conformance and durable target-specific evidence are complete. |

Do not start M2 renderer integration before M1 is complete. Tasks 3 and 4 may
prepare the wrapper model while upstream work is pending, but Task 6 cannot be
accepted on parsing or persistence evidence alone.

## Closure and release gates

Plan completion and `production-ready` are different claims:

| Gate | Required to move Plan 014 to `completed` | Required for a `production-ready` feature/target claim |
| --- | --- | --- |
| A1B32 | Specular and opaque IOR are applied on the pinned renderer with iOS Simulator evidence `verified locally`; hierarchy, picking, and authored material invariants pass. If upstream support is unavailable, Plan 014 remains `blocked`. | The exact physical iOS, Android, or Web row being claimed has real runtime evidence, release packaging evidence, and no open correctness blocker. |
| Glorvia | Base-color and normal bindings apply repeat 2.5 without generated image bytes on the pinned renderer with iOS Simulator evidence `verified locally`. If the transform contract is unavailable, Plan 014 remains `blocked`. | Each claimed physical target applies the sampler/transform contract and has durable target evidence. |
| Clearcoat and transmission/volume | Tasks 8 and 9 either integrate a conformant renderer path or move the remaining candidate work to an explicit deferred plan. Candidate-only completion keeps the v1 release gate blocked and must not be described as feature support. | Every claimed feature/target row passes normative, visual, packaging, and physical-runtime gates. |
| Meshopt, Draco, and BasisU | Shared budgets, declared conformance cases, rewritten-GLB validation, and honest platform labels pass. | Only targets with real decoder/runtime evidence may be labeled `production-ready`; other rows remain `not run` or `candidate-only`. |

An aggregate package or backend readiness claim is allowed only when every
feature in the claimed set is `production-ready` for every target in the
claimed target set. Simulator-only evidence never satisfies a physical-target
release row.

## Non-goals

- Supporting every extension in the Khronos registry.
- Filament, Unreal, Unity, or Three.js pixel parity.
- Dynamic atmosphere, aerial perspective, volumetric clouds, or imported glTF
  light/camera playback.
- Nested glass, order-independent transparency, caustics, path tracing, or
  full volumetric transport.
- External `.gltf` buffers/images, progressive streaming, virtual texturing,
  animation, morph targets, or skeletal posing.
- Baking UV transforms into image bytes or changing authored metallic,
  roughness, clearcoat, alpha, visibility, or base color to improve one asset.

## Planned file structure

- Create `lib/src/texture_binding.dart` for public immutable sampler,
  transform, and source-binding types.
- Create `lib/src/internal/glb_texture_binding_reader.dart` for shared glTF
  textureInfo, sampler, and `KHR_texture_transform` decoding.
- Create `lib/src/internal/material_extension_patch_group.dart` for isolated
  authored `opaqueIor`, `specular`, `clearcoat`, and `transmissionVolume`
  delivery.
- Create `lib/src/internal/glb_decode_budget.dart` for shared bounded decoder
  and rewrite limits.
- Create `docs/references/pbr_material_acceptance.md` for source hierarchy,
  renderer ownership, invariants, and evidence rules.
- Create
  `tools/material_extension_acceptance/fixtures/reference_state.json` for the
  fixed camera/environment/lighting state used by material comparisons.
- Modify `MaterialPatch` and `ViewerController` without removing existing
  `TextureSource` APIs; the new binding helper always takes an explicit
  `MaterialTextureSlot`.
- Modify imported core and extension readers to share binding semantics.
- Modify adapter/backend code only after the ownership gate identifies a real
  renderer path.
- Keep optional native codec work in the existing sibling plugin packages.

## Steps

### Task 1: Make capability and evidence labels truthful

**Files:**

- Modify: `lib/src/material_extension_policy.dart`
- Modify: `test/material_extension_policy_test.dart`
- Modify: `README.md`
- Modify: `docs/MATERIALS_AND_LIGHTING.md`
- Modify: `docs/PUBLIC_API.md`
- Modify: `docs/RUNTIME_GLB_PIPELINE.md`
- Modify: `docs/generated/capability_matrix.md`
- Modify: `docs/references/material_extension_platform_evidence.md`
- Modify: `docs/references/material_extension_visual_reference.md`
- Modify: `docs/references/material_extension_shader_reference.md`
- Modify: `docs/references/flutter_scene_capability_notes.md`

**Interfaces:**

- Preserve: `ViewerMaterialExtensionPolicy.productionShaders()` for source
  compatibility.
- Add: `MaterialExtensionFeature`, `MaterialExtensionMaturity`,
  `MaterialExtensionTarget`, `MaterialExtensionEvidenceStatus`, and
  `MaterialExtensionFeatureSupport`.
- Add: `MaterialExtensionSupport.supportFor(feature)` and
  `MaterialExtensionSupport.productionReadyFor(feature, target)`.
- Preserve the boolean feature getters and aggregate `productionReady` getter
  for source compatibility, but make the feature/target query authoritative.
  The aggregate getter is true only when every selected feature, including
  `specular`, is production-ready for every explicit release target.

- [x] **Step 1: Add failing capability-label tests**

Add tests equivalent to:

```dart
test('package-local shader policy is candidate-only without target release evidence', () {
  final support =
      const ViewerMaterialExtensionPolicy.productionShaders().support;

  expect(support.backendKind,
      MaterialExtensionBackendKind.flutterSceneCustomShader);
  expect(
    support
        .supportFor(MaterialExtensionFeature.clearcoat)
        .maturityFor(MaterialExtensionTarget.iosSimulator),
    MaterialExtensionMaturity.candidateOnly,
  );
  expect(
    support.supportFor(MaterialExtensionFeature.clearcoat)
        .evidenceFor(MaterialExtensionTarget.iosSimulator),
    MaterialExtensionEvidenceStatus.notRun,
  );
  expect(support.productionReady, isFalse);
});

test('candidate maturity can coexist with verified local target evidence', () {
  final feature = MaterialExtensionFeatureSupport(
    available: true,
    maturityByTarget: const <MaterialExtensionTarget,
        MaterialExtensionMaturity>{
      MaterialExtensionTarget.iosSimulator:
          MaterialExtensionMaturity.candidateOnly,
    },
    evidenceByTarget: const <MaterialExtensionTarget,
        MaterialExtensionEvidenceStatus>{
      MaterialExtensionTarget.iosSimulator:
          MaterialExtensionEvidenceStatus.verifiedLocally,
    },
  );

  expect(
    feature.maturityFor(MaterialExtensionTarget.iosSimulator),
    MaterialExtensionMaturity.candidateOnly,
  );
  expect(
    feature.evidenceFor(MaterialExtensionTarget.iosSimulator),
    MaterialExtensionEvidenceStatus.verifiedLocally,
  );
  expect(
    feature.productionReadyFor(MaterialExtensionTarget.iosSimulator),
    isFalse,
  );
});
```

- [x] **Step 2: Run the focused tests and confirm red**

Run:

```sh
flutter test test/material_extension_policy_test.dart
```

Expected: failure because the feature/maturity/target types do not exist and
the current policy reports `productionReady == true`.

- [x] **Step 3: Add per-target maturity and evidence status**

Implement this shape. `MaterialExtensionMaturity` describes release maturity;
`MaterialExtensionEvidenceStatus` records whether a particular target was
actually run. They are deliberately not one enum:

```dart
enum MaterialExtensionFeature {
  transmission,
  ior,
  volume,
  clearcoat,
  specular,
}

enum MaterialExtensionMaturity {
  diagnosticOnly,
  candidateOnly,
  releasePending,
  productionReady,
}

enum MaterialExtensionTarget {
  iosSimulator,
  iosPhysical,
  android,
  web,
}

enum MaterialExtensionEvidenceStatus {
  notRun,
  verifiedLocally,
}

@immutable
final class MaterialExtensionFeatureSupport {
  factory MaterialExtensionFeatureSupport({
    required bool available,
    Map<MaterialExtensionTarget, MaterialExtensionMaturity> maturityByTarget =
        const {},
    Map<MaterialExtensionTarget, MaterialExtensionEvidenceStatus>
        evidenceByTarget = const {},
  }) {
    return MaterialExtensionFeatureSupport._(
      available: available,
      maturityByTarget: Map.unmodifiable(maturityByTarget),
      evidenceByTarget: Map.unmodifiable(evidenceByTarget),
    );
  }

  const MaterialExtensionFeatureSupport._({
    required this.available,
    required this.maturityByTarget,
    required this.evidenceByTarget,
  });

  final bool available;
  final Map<MaterialExtensionTarget, MaterialExtensionMaturity>
      maturityByTarget;
  final Map<MaterialExtensionTarget, MaterialExtensionEvidenceStatus>
      evidenceByTarget;

  MaterialExtensionMaturity maturityFor(MaterialExtensionTarget target) =>
      maturityByTarget[target] ?? MaterialExtensionMaturity.diagnosticOnly;

  MaterialExtensionEvidenceStatus evidenceFor(
    MaterialExtensionTarget target,
  ) => evidenceByTarget[target] ?? MaterialExtensionEvidenceStatus.notRun;

  bool productionReadyFor(MaterialExtensionTarget target) =>
      available &&
      maturityFor(target) == MaterialExtensionMaturity.productionReady &&
      evidenceFor(target) == MaterialExtensionEvidenceStatus.verifiedLocally;

  static const unsupported = MaterialExtensionFeatureSupport._(
    available: false,
    maturityByTarget: {},
    evidenceByTarget: {},
  );
}

final class MaterialExtensionSupport {
  factory MaterialExtensionSupport({
    required MaterialExtensionBackendKind backendKind,
    Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport> features =
        const {},
    Set<MaterialExtensionTarget> claimedReleaseTargets = const {},
  }) {
    return MaterialExtensionSupport._(
      backendKind: backendKind,
      features: Map.unmodifiable(features),
      claimedReleaseTargets: Set.unmodifiable(claimedReleaseTargets),
    );
  }

  const MaterialExtensionSupport._({
    required this.backendKind,
    required this.features,
    required this.claimedReleaseTargets,
  });

  final MaterialExtensionBackendKind backendKind;
  final Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport> features;
  final Set<MaterialExtensionTarget> claimedReleaseTargets;

  MaterialExtensionFeatureSupport supportFor(
    MaterialExtensionFeature feature,
  ) => features[feature] ?? MaterialExtensionFeatureSupport.unsupported;

  bool get transmission =>
      supportFor(MaterialExtensionFeature.transmission).available;
  bool get ior => supportFor(MaterialExtensionFeature.ior).available;
  bool get volume => supportFor(MaterialExtensionFeature.volume).available;
  bool get clearcoat =>
      supportFor(MaterialExtensionFeature.clearcoat).available;
  bool get specular => supportFor(MaterialExtensionFeature.specular).available;

  bool productionReadyFor(
    MaterialExtensionFeature feature,
    MaterialExtensionTarget target,
  ) => supportFor(feature).productionReadyFor(target);

  bool get productionReady =>
      claimedReleaseTargets.isNotEmpty &&
      MaterialExtensionFeature.values.every(
        (feature) => claimedReleaseTargets.every(
          (target) => productionReadyFor(feature, target),
        ),
      );
}
```

The final concrete class must keep legacy boolean getters such as
`support.clearcoat` by delegating to `supportFor(...).available`, store an
immutable non-empty `claimedReleaseTargets` set only for an actual release
backend, and include all five selected features in the aggregate compatibility
getter. Maturity is stored per target, not once for the whole feature.
Feature application and diagnostics must use `supportFor` or
`productionReadyFor`, never the aggregate getter.

`ViewerMaterialExtensionPolicy.productionShaders().support` must set package-
local shader features to `MaterialExtensionMaturity.candidateOnly` for each
known target, leave all target evidence `notRun`, and leave
`claimedReleaseTargets` empty. Shader preflight proves availability/routing
only; it must not mutate maturity or target evidence. Historical iOS Simulator
runs are represented in durable evidence records and documentation, not
invented by the static policy constructor.

Update `==` and `hashCode` for both support types so backend kind, per-feature
availability, per-target maturity, per-target evidence, and claimed release
targets participate in value equality. Add an equality test where changing only
one target's evidence makes two support objects unequal.

- [x] **Step 4: Demote current documentation claims**

Describe package-local clearcoat and glass as `candidate-only` with iOS
Simulator evidence `verified locally`. State that shader preflight proves
availability and routing, not Khronos correctness or physical-device release
readiness. These two labels occupy separate maturity and target-evidence
fields. Keep physical iOS, Android material rendering, and Web material
rendering as `not run`.

- [x] **Step 5: Verify Task 1**

Run:

```sh
flutter test test/material_extension_policy_test.dart
python3 tools/repo_lint.py
git diff --check
```

Expected: all commands pass; no current public document calls simulator-only
package-local material evidence `production-ready`.

### Task 2: Separate core patches from extension intent and remove asset hacks

**Files:**

- Modify: `lib/src/material_patch.dart`
- Modify: `lib/src/model_loader.dart`
- Modify: `lib/src/viewer_controller.dart`
- Create: `lib/src/internal/material_extension_patch_group.dart`
- Modify: `lib/src/internal/material_base_family.dart`
- Modify: `lib/src/internal/glb_imported_texture_patch_reader.dart`
- Modify: `lib/src/internal/glb_material_extension_reader.dart`
- Test: `test/material_patch_test.dart`
- Test: `test/material_base_family_test.dart`
- Test: `test/model_loader_test.dart`
- Test: `test/viewer_controller_material_test.dart`
- Test: `test/glb_imported_texture_patch_reader_test.dart`
- Test: `test/glb_material_extension_reader_test.dart`

**Interfaces:**

- Add: `MaterialPatch.hasTransmissionOrVolumeOverride`.
- Add: `MaterialPatch.hasOpaqueIorOverride`.
- Keep `hasGlassOverride` as a compatibility getter whose meaning excludes
  IOR-only opaque materials.
- Add internal `MaterialExtensionPatchGroup` values `opaqueIor`, `specular`,
  `clearcoat`, and `transmissionVolume`.
- Replace one merged authored-patch map with a core map plus independently
  applicable extension-group maps in `ModelLoadResult`.

- [x] **Step 1: Add failing IOR and patch-isolation tests**

Cover these assertions:

```dart
expect(const MaterialPatch(ior: 1.5).hasGlassOverride, isFalse);
expect(const MaterialPatch(ior: 1.5).hasOpaqueIorOverride, isTrue);
expect(const MaterialPatch(transmission: 1, ior: 1.5).hasGlassOverride, isTrue);
```

Add a controller test proving an unsupported authored specular/IOR extension
patch cannot prevent a valid imported base-color or normal texture patch from
being applied to the same `PartAddress`. Add a second test proving unsupported
specular does not prevent supported clearcoat or opaque IOR on the same
material. Keep direct public `setPartMaterial` calls atomic; group splitting
applies to imported authored intent, where partial fallback is required by the
asset contract.

- [x] **Step 2: Run the focused tests and confirm red**

```sh
flutter test test/material_patch_test.dart test/material_base_family_test.dart test/model_loader_test.dart test/viewer_controller_material_test.dart test/glb_material_extension_reader_test.dart
```

Expected: IOR-only classification and merged-patch atomic validation fail.

- [x] **Step 3: Split authored patch delivery**

Use this result shape:

```dart
final class ModelLoadResult {
  final Map<PartAddress, MaterialPatch> authoredCoreMaterialPatches;
  final Map<PartAddress,
      Map<MaterialExtensionPatchGroup, MaterialPatch>>
      authoredExtensionMaterialPatches;
}
```

The extension reader assigns fields to this internal grouping:

```dart
enum MaterialExtensionPatchGroup {
  opaqueIor,
  specular,
  clearcoat,
  transmissionVolume,
}
```

- `opaqueIor`: IOR without transmission or volume intent;
- `specular`: specular factor/color and their textures;
- `clearcoat`: all clearcoat fields;
- `transmissionVolume`: transmission, transmissive IOR, thickness, and
  attenuation fields, which share one renderer dependency.

Apply the core patch first, then validate and apply each authored extension
group independently. One group failure records diagnostics for only that group
and cannot discard core state or a different supported group. If multiple
successfully applied groups interact in the renderer, merge their stored
override state only after each group succeeds.

- [x] **Step 4: Remove asset-specific material mutation**

Delete PNG-alpha inference when glTF omits `alphaMode`; glTF's authored/default
alpha mode remains authoritative. Delete name-based neutral-white base-color
replacement. Preserve asset-quality diagnostics without changing authored
material values or visibility.

- [x] **Step 5: Verify Task 2**

```sh
flutter test test/material_patch_test.dart test/material_base_family_test.dart test/model_loader_test.dart test/viewer_controller_material_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart
python3 tools/repo_lint.py
git diff --check
```

Expected: all tests pass; unsupported extension intent no longer blocks core
texture reapplication or a different supported extension group; no asset-name-
based repair remains.

### Task 3: Add the public texture binding, sampler, and transform model

**Files:**

- Create: `lib/src/texture_binding.dart`
- Modify: `lib/flutter_scene_viewer.dart`
- Modify: `lib/src/material_patch.dart`
- Modify: `lib/src/viewer_controller.dart`
- Test: `test/texture_binding_test.dart`
- Test: `test/material_patch_test.dart`
- Test: `test/viewer_controller_material_test.dart`

**Interfaces:**

- Add: `MaterialTextureSlot`, `TextureWrapMode`, `TextureMagFilter`,
  `TextureMinFilter`, `TextureSampler`, `TextureTransform`, and
  `MaterialTextureBinding`.
- Add per-slot `...TextureBinding` fields while retaining existing
  `TextureSource?` fields.
- Add:
  `Future<void> setPartTextureBinding(PartAddress, MaterialTextureSlot, MaterialTextureBinding)`.

- [x] **Step 1: Write failing JSON and compatibility tests**

Test the following public shape:

```dart
final binding = MaterialTextureBinding(
  source: TextureSource.asset('assets/fabric.png'),
  texCoord: 0,
  sampler: const TextureSampler(
    wrapS: TextureWrapMode.repeat,
    wrapT: TextureWrapMode.mirroredRepeat,
    magFilter: TextureMagFilter.linear,
    minFilter: TextureMinFilter.linearMipmapLinear,
  ),
  transform: TextureTransform(
    offset: <double>[0.1, 0.2],
    scale: <double>[2.5, 2.5],
    rotation: 0.5,
  ),
);
```

Assert JSON round-trip, non-finite rejection, non-negative UV-set validation,
defensive immutability after the caller mutates its input lists, slot-aware
controller routing, and unchanged serialization for old source-only patches.

- [x] **Step 2: Run the focused tests and confirm red**

```sh
flutter test test/texture_binding_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart
```

Expected: failure because the binding types and controller API do not exist.

- [x] **Step 3: Implement immutable binding types**

Use these semantics:

```dart
enum MaterialTextureSlot {
  baseColor,
  metallicRoughness,
  normal,
  occlusion,
  emissive,
  transmission,
  thickness,
  clearcoat,
  clearcoatRoughness,
  clearcoatNormal,
  specular,
  specularColor,
}

enum TextureWrapMode { clampToEdge, mirroredRepeat, repeat }
enum TextureMagFilter { nearest, linear }
enum TextureMinFilter {
  nearest,
  linear,
  nearestMipmapNearest,
  linearMipmapNearest,
  nearestMipmapLinear,
  linearMipmapLinear,
}

void _requireFinite(String field, double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, field, 'must be finite');
  }
}

void _requireFinitePair(String field, List<double> value) {
  if (value.length != 2) {
    throw ArgumentError.value(value, field, 'must contain exactly two values');
  }
  _requireFinite('$field[0]', value[0]);
  _requireFinite('$field[1]', value[1]);
}

@immutable
final class TextureSampler {
  const TextureSampler({
    this.wrapS = TextureWrapMode.repeat,
    this.wrapT = TextureWrapMode.repeat,
    this.magFilter,
    this.minFilter,
  });

  final TextureWrapMode wrapS;
  final TextureWrapMode wrapT;
  final TextureMagFilter? magFilter;
  final TextureMinFilter? minFilter;
}

@immutable
final class TextureTransform {
  factory TextureTransform({
    List<double> offset = const <double>[0, 0],
    List<double> scale = const <double>[1, 1],
    double rotation = 0,
    int? texCoordOverride,
  }) {
    _requireFinitePair('offset', offset);
    _requireFinitePair('scale', scale);
    _requireFinite('rotation', rotation);
    if (texCoordOverride != null && texCoordOverride < 0) {
      throw ArgumentError.value(
        texCoordOverride,
        'texCoordOverride',
        'must be non-negative',
      );
    }
    return TextureTransform._(
      offsetX: offset[0],
      offsetY: offset[1],
      scaleX: scale[0],
      scaleY: scale[1],
      rotation: rotation,
      texCoordOverride: texCoordOverride,
    );
  }

  const TextureTransform._({
    required this.offsetX,
    required this.offsetY,
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
    required this.texCoordOverride,
  });

  static const identity = TextureTransform._(
    offsetX: 0,
    offsetY: 0,
    scaleX: 1,
    scaleY: 1,
    rotation: 0,
    texCoordOverride: null,
  );

  final double offsetX;
  final double offsetY;
  final double scaleX;
  final double scaleY;
  final double rotation;
  final int? texCoordOverride;

  List<double> get offset =>
      List<double>.unmodifiable(<double>[offsetX, offsetY]);
  List<double> get scale =>
      List<double>.unmodifiable(<double>[scaleX, scaleY]);
}

@immutable
final class MaterialTextureBinding {
  factory MaterialTextureBinding({
    required TextureSource source,
    int texCoord = 0,
    TextureSampler sampler = const TextureSampler(),
    TextureTransform transform = TextureTransform.identity,
  }) {
    if (texCoord < 0) {
      throw ArgumentError.value(texCoord, 'texCoord', 'must be non-negative');
    }
    return MaterialTextureBinding._(
      source: source,
      texCoord: texCoord,
      sampler: sampler,
      transform: transform,
    );
  }

  const MaterialTextureBinding._({
    required this.source,
    required this.texCoord,
    required this.sampler,
    required this.transform,
  });

  final TextureSource source;
  final int texCoord;
  final TextureSampler sampler;
  final TextureTransform transform;
  int get effectiveTexCoord => transform.texCoordOverride ?? texCoord;
}
```

Keep absent min/mag filter values nullable so unspecified glTF intent is not
invented. `wrapS` and `wrapT` default to repeat. Use the private throwing
validators above; do not rely on `assert` because release builds must reject
malformed persisted input. Finite negative scale is valid glTF intent and must
be preserved.

- [x] **Step 4: Add binding fields without breaking source-only callers**

Add binding siblings for base color, metallic-roughness, normal, occlusion,
emissive, transmission, thickness, clearcoat, clearcoat roughness, clearcoat
normal, specular, and specular color. Reject simultaneous source-only and
binding values for the same slot. Internally normalize a source-only field to a
default binding. Keep `setPartTexture(address, source)` as the base-color
compatibility helper. Implement `setPartTextureBinding` by mapping the explicit
`MaterialTextureSlot` to exactly one `MaterialPatch` binding field; it must not
guess a slot from the image or debug name.

Keep the existing `const MaterialPatch` constructor. Enforce simultaneous
source-and-binding conflicts in `MaterialPatch.validate` with a typed
diagnostic, and reject the same conflict in `MaterialPatch.fromJson` with
`FormatException`; do not rely on constructor asserts. Binding JSON uses these
stable keys:

```json
{
  "source": {"kind": "asset", "assetPath": "assets/fabric.png"},
  "texCoord": 0,
  "sampler": {
    "wrapS": "repeat",
    "wrapT": "mirroredRepeat",
    "magFilter": "linear",
    "minFilter": "linearMipmapLinear"
  },
  "transform": {
    "offset": [0.1, 0.2],
    "scale": [2.5, 2.5],
    "rotation": 0.5
  }
}
```

Omit `texCoordOverride` when absent. Old source-only patch JSON must remain
structurally unchanged; do not normalize it to binding JSON during
serialization.

- [x] **Step 5: Verify Task 3**

```sh
flutter test test/texture_binding_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart
flutter analyze
git diff --check
```

Expected: all commands pass and existing public source-only calls compile.

### Task 4: Decode glTF samplers and KHR_texture_transform once

**Files:**

- Create: `lib/src/internal/glb_texture_binding_reader.dart`
- Modify: `lib/src/internal/glb_imported_texture_patch_reader.dart`
- Modify: `lib/src/internal/glb_material_extension_reader.dart`
- Modify: `lib/src/internal/glb_capability_reader.dart`
- Test: `test/glb_texture_binding_reader_test.dart`
- Test: `test/glb_imported_texture_patch_reader_test.dart`
- Test: `test/glb_material_extension_reader_test.dart`
- Test: `test/glb_capability_reader_test.dart`

**Interfaces:**

- Add one shared reader that consumes textureInfo, `textures[]`,
  `samplers[]`, primitive UV availability, `KHR_texture_transform` requiredness,
  and a resolved `TextureSource`. It returns a binding plus blocking or
  non-blocking typed diagnostics.
- Core and extension readers must not reimplement transform/sampler decoding.
- `glb_capability_reader.dart` remains responsible for deriving the primitive's
  available `TEXCOORD_n` set and whether `KHR_texture_transform` appears in
  top-level `extensionsRequired`; the shared reader consumes those facts.

- [x] **Step 1: Add failing normative fixtures**

Cover:

- absent sampler with repeat wrapping and unspecified filter intent;
- all two mag and six min filters;
- independent `wrapS` and `wrapT`;
- transform defaults;
- `offset + rotation * (scale * uv)` in radians, counter-clockwise around the
  origin;
- extension `texCoord` overriding parent `textureInfo.texCoord` only when the
  extension is processed;
- finite negative scale accepted unchanged, including the normative T-axis
  inversion shape;
- non-finite values, missing `TEXCOORD_n`, and invalid texture/sampler indices;
- malformed optional transform data falling back to the parent `textureInfo`
  with a non-blocking diagnostic;
- the same malformed transform becoming blocking when
  `KHR_texture_transform` is required;
- the same image used by two slots with distinct bindings.

- [x] **Step 2: Run the focused tests and confirm red**

```sh
flutter test test/glb_texture_binding_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_capability_reader_test.dart
```

Expected: transform and sampler metadata is absent.

- [x] **Step 3: Implement the shared reader**

Expose this internal contract:

```dart
GlbTextureBindingReadResult readGlbTextureBinding({
  required Map<String, Object?> textureInfo,
  required List<Object?> textures,
  required List<Object?> samplers,
  required TextureSource source,
  required Set<int> availableTexCoords,
  required bool textureTransformRequired,
  required String slot,
  required String debugName,
});
```

Map glTF integer enums exactly; do not collapse separate wrap axes or invent
filter values. The result contract is:

- valid core data and valid/absent transform: return the binding;
- malformed optional transform: ignore the whole transform object, use the
  parent `textureInfo.texCoord`, return the core binding, and add a non-blocking
  diagnostic;
- malformed required transform: return no binding and a blocking diagnostic;
- missing effective `TEXCOORD_n`: return no binding and a typed `missingUvSet`
  diagnostic;
- malformed core texture or sampler indices: return no binding and a blocking
  malformed-asset diagnostic.

Do not reject finite negative scale. Khronos explicitly permits unbounded
transform values and uses negative scale for axis inversion.

- [x] **Step 4: Replace duplicate reader logic**

Route every core and selected extension texture slot through the shared reader.
Pass the primitive's UV set and top-level extension-required context from the
capability/import traversal. Keep color/data/normal role selection outside this
reader. Add an integration test proving an optional unsupported transform uses
the valid core fallback, while the required form fails before adapter import.

- [x] **Step 5: Verify Task 4**

```sh
flutter test test/glb_texture_binding_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_capability_reader_test.dart
bash tools/run_checks.sh
```

Expected: all commands pass; transformed binding metadata reaches authored
patches without changing encoded image bytes.

### Task 5: Freeze the PBR ownership and lighting reference state

**Files:**

- Create: `docs/references/pbr_material_acceptance.md`
- Create:
  `tools/material_extension_acceptance/fixtures/reference_state.json`
- Modify: `tools/material_extension_acceptance/README.md`
- Modify: `tools/material_extension_acceptance/manifest.json`
- Modify: `test/viewer_lighting_test.dart`
- Modify: `test/viewer_environment_test.dart`

**Interfaces:**

- The acceptance state is evidence configuration, not new viewer API.
- Khronos is normative; Filament/Karis define audit direction; pinned
  `flutter_scene` proves implementation; Frostbite does not define glTF
  materials.

- [x] **Step 1: Add the fixed reference-state fixture**

Record the existing deterministic defaults:

```json
{
  "schemaVersion": 1,
  "environment": {
    "kind": "studio",
    "intensity": 1.0,
    "rotationRadians": 0.0,
    "showSkybox": false,
    "skyboxBlur": 0.0
  },
  "lighting": {
    "kind": "studio",
    "exposure": 1.0,
    "ambientOcclusion": false,
    "environmentIntensity": 1.0,
    "keyLightIntensity": 3.0,
    "keyLightColor": [1.0, 1.0, 1.0],
    "keyLightDirection": [-0.45, -0.85, -0.35],
    "keyLightCastsShadow": false
  },
  "camera": {
    "fit": "assetBounds",
    "views": ["front", "left", "right", "back"]
  }
}
```

- [x] **Step 2: Document renderer ownership and invariants**

For each material phase, require:

- stable camera, environment, exposure, tone mapping, and renderer backend;
- dielectric F0/IOR trend and metallic/specular separation;
- roughness broadening without arbitrary brightness thresholds;
- clearcoat second-lobe/base-attenuation trend;
- direct and split-sum IBL consistency;
- source screenshots and metrics labeled directional, never pixel parity.

- [x] **Step 3: Add fixture-schema tests**

Assert the JSON values equal `ViewerLighting.studio()` and
`ViewerEnvironment.studio()` defaults so evidence cannot drift silently.

- [x] **Step 4: Verify Task 5**

```sh
flutter test test/viewer_lighting_test.dart test/viewer_environment_test.dart
python3 tools/repo_lint.py
git diff --check
```

Expected: all commands pass and later visual tasks reference the same fixture.

### Task 6: Apply sampler and UV transform through a real renderer boundary

**Files:**

- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify: `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify: `pubspec.yaml` and `pubspec.lock` only after an upstream commit is
  available
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/texture/texture2d.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/material/physically_based_material.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/runtime_importer/texture_builder.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/material_varyings.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Test: `test/flutter_scene_material_extension_backend_test.dart`
- Test: `test/viewer_controller_material_test.dart`
- Document: `docs/references/flutter_scene_capability_notes.md`

**Interfaces:**

- Convert `MaterialTextureBinding` sampler intent to the active renderer's
  sampler representation.
- Require renderer-native per-slot UV transform support for standard PBR
  materials.
- Do not replace the standard PBR material with a package-local full-PBR
  shader merely to obtain transformed UVs.

- [ ] **Step 1: Add failing adapter tests**

Cover:

- symmetric repeat/clamp/mirror mapping;
- independent wrap axes;
- min/mag/mip intent;
- per-slot offset/scale/rotation;
- color, data, and normal slots;
- the same image source bound to two slots with distinct sampler/transform
  state, without shared-state mutation;
- `setPartTextureBinding` routing through every `MaterialTextureSlot`;
- unsupported target diagnostics without byte baking.

- [ ] **Step 2: Audit the pinned renderer**

Record that the pinned `TextureSampling` exposes one address mode for both axes
even though its low-level sampler supports separate width/height modes; the
runtime importer `texture_builder.dart` constructs imported textures with
default sampling; and the standard material API has no per-slot
`KHR_texture_transform` fields. Do not edit the pub cache.

- [ ] **Step 3: Implement the supported sampler subset**

For equal `wrapS`/`wrapT` values, construct the corresponding upstream
`TextureSampling` when the public API exposes it. For asymmetric wrapping or
unrepresentable filter intent, return a typed backend diagnostic until the
pinned renderer exposes separate axes. Pass binding sampler intent through
every wrapper-created `Texture2D.fromAsset`, `fromImage`, and `fromPixels` path.
Any current or future texture cache key must include content role and sampler
state; transform remains per material slot and must never be stored as mutable
state on a shared image object.

- [ ] **Step 4: Integrate an upstream per-slot transform contract**

Implement the minimal change in the actual `flutter_scene` repository, obtain
an explicit commit, then update this repo's dependency pin. The upstream
contract must keep transform data per material texture slot and apply it in
both direct texture sampling and IBL-relevant normal sampling. If no upstream
commit is available, mark this step `blocked` and keep runtime application
diagnostic-only. If upstream owns authored sampler import, update
`runtime_importer/texture_builder.dart` to construct one texture object per glTF
`texture` entry using that entry's sampler; do not key only by image index.

- [ ] **Step 5: Add Glorvia runtime evidence**

Apply front/back albedo and crepe normal at repeat 2.5 through
the slot-aware `setPartTextureBinding` API. Assert the original encoded bytes
are unchanged and capture transform differences under the fixed reference
state.

- [ ] **Step 6: Verify Task 6**

```sh
flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart
bash tools/run_checks.sh
```

Expected: supported targets apply transformed UVs and sampler state; other
targets emit diagnostics. No tiled image bytes are generated. This task remains
`blocked` rather than accepted if the Glorvia gate has no real renderer
application.

### Task 7: Integrate KHR_materials_specular and opaque IOR upstream-first

**Files:**

- Modify: `lib/src/material_patch.dart`
- Modify: `lib/src/material_extension_policy.dart`
- Modify: `lib/src/internal/glb_material_extension_reader.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify: `lib/src/internal/material_extension_native_capability.dart`
- Modify: `lib/src/internal/material_extension_native_applier.dart`
- Modify dependency pin only after a real upstream renderer commit
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/material/physically_based_material.dart`,
  `packages/flutter_scene/lib/src/material/material_parameters.dart`, and
  `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/shaders/pbr.glsl`,
  `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`
- Test: `test/material_patch_test.dart`
- Test: `test/material_extension_policy_test.dart`
- Test: `test/glb_material_extension_reader_test.dart`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Test: `test/material_extension_native_applier_test.dart`

**Interfaces:**

- Preserve `specularFactor`, `specularTexture`, `specularColorFactor`,
  `specularColorTexture`, and opaque `ior` through the wrapper.
- Renderer support must apply them to the standard dielectric response; do not
  map them to metallic or clearcoat.

- [ ] **Step 1: Add failing semantic tests**

Cover these semantics separately so factor and texture color spaces cannot be
conflated:

- `specularFactor` is a linear scalar in `[0, 1]`;
- `specularTexture` samples the alpha channel without an sRGB transfer;
- `specularColorFactor` is linear RGB and may exceed `1` as allowed by the
  extension;
- `specularColorTexture` samples RGB encoded with sRGB and decodes it to linear;
- factor and texture values multiply;
- defaults, opaque IOR, the `ior == 0` compatibility mode, dielectric energy
  conservation, and metallic materials not gaining dielectric transmission.

- [ ] **Step 2: Run focused tests and confirm renderer red**

```sh
flutter test test/material_patch_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_adapter_material_test.dart test/material_extension_native_applier_test.dart
```

Expected: parsing passes where already present, but renderer application and
opaque IOR classification tests fail.

- [ ] **Step 3: Implement or pin the renderer contract**

Add first-class specular and IOR material fields in upstream `flutter_scene`,
including texture roles and per-slot bindings. Do not expose GGX, Smith,
Schlick, DFG, precision, or roughness-remap choices in viewer APIs. If the
upstream work is unavailable, keep support diagnostic-only and mark this task
`blocked` rather than adding a wrapper overlay.

- [ ] **Step 4: Wire adapter capability after real support exists**

Set `supportFor(MaterialExtensionFeature.specular).available` only when the
active renderer consumes all requested specular fields, and record maturity and
evidence independently. Do the same for opaque IOR. Keep IOR-only materials in
the ordinary PBR family.

- [ ] **Step 5: Run the A1B32 intermediate gate**

Verify Draco load, 20 primitives, hierarchy, picking, unmodified material
intent, metallic remaining authored, no forced clearcoat/roughness/alpha, and
visible specular/IOR trends under the fixed reference state.

- [ ] **Step 6: Verify Task 7**

```sh
flutter test test/material_patch_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_adapter_material_test.dart test/material_extension_native_applier_test.dart
bash tools/run_checks.sh
```

Expected: all commands pass and A1B32 evidence is labeled for the exact target.
If specular or opaque IOR is still diagnostic-only, Task 7 and Plan 014 remain
`blocked`; a green parsing suite alone does not satisfy the A1B32 closure gate.

### Task 8: Re-audit and integrate clearcoat

**Files:**

- Modify: `assets/materials/fsviewer_clearcoat.fmat` only if the
  target-scoped candidate backend remains useful
- Modify: `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify dependency pin after real upstream clearcoat support
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/material/physically_based_material.dart` and
  `packages/flutter_scene/lib/src/material/material_parameters.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`
- Test: `test/glb_material_extension_reader_test.dart`
- Test: `test/flutter_scene_material_extension_backend_test.dart`
- Test: `test/material_extension_native_applier_test.dart`
- Modify:
  `tools/material_extension_acceptance/fixtures/material_extension_reference_metrics.json`

**Interfaces:**

- Red channel: clearcoat factor texture.
- Green channel: clearcoat roughness texture.
- Independent tangent-space clearcoat normal and normal scale.
- Base attenuation plus a second coat lobe; no base roughness manipulation.

- [ ] **Step 1: Add failing Khronos and Filament audit tests**

Test factor zero/full, roughness trend, independent normal response, base
attenuation, double-sided preservation, combined base-plus-coat patches,
direct/IBL response, and no double-counted directional highlight.

- [ ] **Step 2: Classify the current shader**

Audit heuristic directional highlight, emissive overlay, alpha behavior,
source-normal suppression, shadows, and indirect-specular occlusion. Preserve
the result as `candidate-only` unless every selected target gate passes.

- [ ] **Step 3: Prefer renderer-native clearcoat**

Integrate a real upstream second-lobe contract when available. A
package-local overlay may remain target-scoped evidence but must not become the
default standard PBR path.

- [ ] **Step 4: Capture reference evidence**

Use Khronos ClearCoat samples and the fixed lighting state. Compare invariant
trends, not Filament or Three.js pixels.

- [ ] **Step 5: Verify Task 8**

```sh
flutter test test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/material_extension_native_applier_test.dart
bash tools/run_checks.sh
```

Expected: renderer-native support passes, or the completed audit records the
feature as `candidate-only`/diagnostic with no production overclaim. In the
latter case, create or update an explicit deferred clearcoat follow-up before
Plan 014 closes, do not check any `production-ready` clearcoat target row, mark
the conditional disposition acceptance item only after the deferred link is
recorded, and keep the v1 release gate blocked.

### Task 9: Re-audit and integrate transmission, volume, and glass IOR

**Files:**

- Modify: `assets/materials/fsviewer_transmission.fmat` only for the bounded
  candidate backend
- Modify: `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify dependency pin after real upstream support
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/lib/src/material/physically_based_material.dart`,
  `packages/flutter_scene/lib/src/material/material_parameters.dart`,
  `packages/flutter_scene/lib/src/render/scene_pass.dart`, and
  `packages/flutter_scene/lib/src/render/render_scene.dart`
- Upstream, separate `flutter_scene` checkout:
  `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`
- Test: `test/glb_material_extension_reader_test.dart`
- Test: `test/flutter_scene_material_extension_backend_test.dart`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Modify:
  `tools/material_extension_acceptance/fixtures/material_extension_reference_metrics.json`

**Interfaces:**

- Transmission texture uses red.
- Volume thickness texture uses green.
- Transmission is separate from alpha mode.
- Volume requires transmission and applies thickness in mesh space, scaled by
  node transforms; attenuation distance is world-space and may be infinite.

- [ ] **Step 1: Add failing normative tests**

Cover transmission factor/texture multiplication, alpha independence, metal
transmitting zero, thin transmission without macroscopic refraction, opaque
objects visible through the surface, volume dependency, thickness green
channel, node scale, attenuation color/distance defaults, IOR interaction, and
missing scene-color-buffer diagnostics.

- [ ] **Step 2: Audit the bounded candidate shader**

Flag or remove hard-coded glint/contour color, red-channel thickness sampling,
thin-surface macro refraction, arbitrary alpha caps, and assumptions that
conflict with Khronos semantics. Do not relabel the bounded screen-space path
as nested or full volume transport.

- [ ] **Step 3: Prefer renderer-owned compositing**

Integrate upstream scene-color sampling/refraction and material fields when
available. If unavailable, retain candidate-only behavior and typed
diagnostics.

- [ ] **Step 4: Capture Khronos evidence**

Use WaterBottle and GlassVase-style samples under the fixed state. Include
behind-glass geometry and volume-specific metrics; do not treat alpha blend as
success.

- [ ] **Step 5: Verify Task 9**

```sh
flutter test test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart
bash tools/run_checks.sh
```

Expected: supported targets satisfy normative trends. If no conformant renderer
path exists, the completed audit keeps the feature `candidate-only` or
diagnostic, moves remaining renderer work to an explicit deferred glass follow-
target rows unchecked, marks the conditional disposition acceptance item only
after the deferred link is recorded, and keeps the v1 release gate blocked.

### Task 10: Harden Meshopt, Draco, and BasisU boundaries

**Files:**

- Create: `lib/src/internal/glb_decode_budget.dart`
- Modify: `lib/src/internal/meshopt_decoder.dart`
- Modify: `lib/src/internal/glb_meshopt_rewriter.dart`
- Modify: `lib/src/internal/glb_draco_rewriter.dart`
- Modify: `lib/src/internal/glb_basisu_rewriter.dart`
- Modify: `lib/src/model_loader.dart`
- Modify: `packages/flutter_scene_viewer_draco/lib/flutter_scene_viewer_draco.dart`
- Modify: `packages/flutter_scene_viewer_draco/android/src/main/cpp/flutter_scene_viewer_draco_jni.cc`
- Modify: `packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc`
- Modify: `packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.h`
- Modify: `packages/flutter_scene_viewer_draco/ios/Classes/FlutterSceneViewerDracoPlugin.mm`
- Modify: `packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc`
- Modify: `packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.h`
- Test: `packages/flutter_scene_viewer_draco/test/flutter_scene_viewer_draco_test.dart`
- Test: `packages/flutter_scene_viewer_draco/test/native_bridge_symbol_test.dart`
- Modify: `packages/flutter_scene_viewer_basisu/lib/flutter_scene_viewer_basisu.dart`
- Modify: `packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc`
- Modify: `packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.cc`
- Modify: `packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.h`
- Modify: `packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm`
- Modify: `packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.cc`
- Modify: `packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.h`
- Test: `packages/flutter_scene_viewer_basisu/test/flutter_scene_viewer_basisu_test.dart`
- Test: `packages/flutter_scene_viewer_basisu/test/native_bridge_symbol_test.dart`
- Test: `test/meshopt_decoder_test.dart`
- Test: `test/glb_meshopt_rewriter_test.dart`
- Test: `test/glb_draco_rewriter_test.dart`
- Test: `test/glb_basisu_rewriter_test.dart`
- Test: `test/model_loader_test.dart`

**Interfaces:**

- Add one shared decode budget for JSON bytes, total decoded bytes, accessors,
  vertices/indices, texture pixels, native output bytes, and timeout/cancel
  behavior.
- Keep codec plugins responsible only for decode/transcode.

- [ ] **Step 1: Add failing budget and malformed-stream tests**

Cover integer overflow, declared output larger than budget, accessor/count
mismatch, truncated output, excessive texture dimensions, cancellation,
native output-size mismatch, and extension declarations remaining after
partial rewrite.

- [ ] **Step 2: Add conformance fixtures**

Meshopt: every claimed mode/filter plus legal placeholder buffers and
`KHR_mesh_quantization` interaction.

Draco: bitstream 2.2, TRIANGLES and TRIANGLE_STRIP, attribute-ID mapping,
accessor schemas, untouched extra attributes, and official decoder comparison.

BasisU: ETC1S/BasisLZ, UASTC none/Zstd, RGB/RGBA/R/RG layouts, DFD transfer and
primaries, orientation/swizzle/premultiplication restrictions, mips, and
unsupported layout diagnostics.

- [ ] **Step 3: Implement shared budget enforcement**

Apply checked arithmetic before allocation and validate native output before
GLB rewrite. Cancellation and timeout must release native/Dart resources.

- [ ] **Step 4: Preserve honest platform labels**

Keep iOS Simulator evidence `verified locally`. Android bridge compilation is
`candidate-only` until a real app/runtime test passes. Do not claim Web support
for native-only codecs.

- [ ] **Step 5: Verify Task 10**

```sh
flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/glb_draco_rewriter_test.dart test/glb_basisu_rewriter_test.dart test/model_loader_test.dart
bash tools/run_checks.sh
```

Then run `flutter test` with
`packages/flutter_scene_viewer_draco` as the working directory, and repeat
with `packages/flutter_scene_viewer_basisu` as the working directory.

Expected: every command passes; malformed or oversized decoder output fails
with typed diagnostics before adapter import.

### Task 11: Produce durable final evidence and publish capability truth

**Files:**

- Modify: `tools/material_extension_acceptance/manifest.json`
- Modify: `tools/material_extension_acceptance/compare_metrics.dart`
- Modify: `tools/material_extension_acceptance/README.md`
- Modify: `docs/generated/capability_matrix.md`
- Modify: `docs/PUBLIC_API.md`
- Modify: `docs/MATERIALS_AND_LIGHTING.md`
- Modify: `docs/RUNTIME_GLB_PIPELINE.md`
- Modify: `docs/QUALITY_SCORE.md`
- Modify this plan's progress and verification logs

**Interfaces:**

- Evidence records asset source/hash, renderer commit, platform/device,
  backend, fixed reference state, camera view, pass criteria, and artifact
  location.
- Every feature/target row stores runtime capability, release maturity, and
  target evidence separately; `candidate-only` plus `verified locally` is a
  valid combination.
- Rewritten GLBs must pass the official glTF Validator.

- [ ] **Step 1: Vendor or reproducibly fetch licensed fixtures**

Record hashes and licenses for A1B32 (when redistribution permits), Khronos
texture-transform, specular, IOR, clearcoat, transmission/volume, BasisU,
Meshopt, and Draco samples. Do not depend on `/private/tmp` artifacts.

- [ ] **Step 2: Run deterministic reference and target captures**

Capture front/left/right/back views with the fixed state. Record
reference-renderer direction separately from target evidence.

- [ ] **Step 3: Validate rewritten GLBs**

Run glTF Validator on Meshopt, Draco, and BasisU rewrite output. Record zero
new errors attributable to rewrite; warnings require explicit disposition.

- [ ] **Step 4: Update the capability matrix per feature and target**

Separate parsed, preserved, decoded, applied, visually verified, release
maturity, and target evidence for iOS Simulator, physical iOS, Android, and
Web. Generate aggregate claims only from an explicit feature set and target
set; never copy a backend-wide boolean into every row.

- [ ] **Step 5: Run final verification**

```sh
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

Expected: all commands pass. Any skipped GPU/visual test remains explicitly
listed and cannot support a `production-ready` claim. Before moving the plan to
`completed`, enforce the closure table: A1B32 and Glorvia renderer gates must
pass, while any candidate-only clearcoat/glass remainder must have an explicit
deferred plan and must keep the v1 release gate blocked.

## Acceptance criteria

- [ ] Current docs and runtime support objects separate per-feature runtime
      capability, release maturity, and per-target evidence. A feature can be
      both `candidate-only` and `verified locally` without contradiction.
- [ ] Core imported textures apply even when selected material extensions are
      unsupported.
- [ ] Unsupported authored specular, clearcoat, opaque IOR, or
      transmission/volume intent does not discard a different supported
      authored extension group on the same material.
- [ ] IOR-only opaque materials stay in the standard PBR family.
- [ ] No asset-name, texture-name, PNG-alpha, forced material-value, visibility,
      or generated-tiling repair remains in the production path.
- [ ] Public runtime bindings use an explicit `MaterialTextureSlot`, are
      defensively immutable, and preserve source, UV set, sampler, offset,
      scale, rotation, and extension UV override per texture slot.
- [ ] `KHR_texture_transform` uses normative math/defaults and sampler state is
      preserved or diagnosed without byte baking. Finite negative scale is
      accepted; malformed optional transform data uses core fallback, while
      malformed required data blocks import.
- [ ] `KHR_materials_specular` changes dielectric response with correct channel
      and color-space handling.
- [ ] Opaque `KHR_materials_ior` changes dielectric F0 without classifying the
      material as glass.
- [ ] Clearcoat runtime support, when claimed, is a second authored lobe with
      independent normal and base attenuation. Otherwise it remains explicitly
      `candidate-only`/diagnostic, has a linked deferred plan, and keeps the v1
      release gate blocked.
- [ ] Transmission runtime support, when claimed, is not alpha blending;
      volume thickness uses green and attenuation/IOR behavior passes normative
      tests. Otherwise it remains explicitly deferred and keeps the v1 release
      gate blocked.
- [ ] BasisU/KTX2 layout, color-role, mip, budget, and platform boundaries are
      explicit.
- [ ] Meshopt and Draco rewrites pass conformance, budget, addressing, and
      validator gates.
- [ ] A1B32 loads, renders, picks, preserves hierarchy, applies specular and
      opaque IOR, and does not receive material hacks.
- [ ] Glorvia applies base-color and normal repeat 2.5 through slot-aware
      bindings without changing or generating encoded image bytes.
- [ ] Lighting/reference state is fixed before material visual comparison.
- [ ] Durable evidence exists outside temporary directories with asset,
      renderer, platform, camera, lighting, and pass metadata.
- [ ] Capability claims are target-specific; `not run` targets remain
      `not run`.
- [ ] Plan closure follows the explicit gate table: blocked A1B32 or Glorvia
      renderer work prevents completion, and deferred clearcoat/glass work
      prevents a v1 `production-ready` release claim.
- [ ] `bash tools/run_checks.sh` passes.
- [ ] `python3 tools/repo_lint.py` passes.
- [ ] `git diff --check` passes.

## Progress log

- 2026-07-11: Paused at the user's request before Task 6 implementation and
  pushed a verified checkpoint. Task 6's pinned-renderer audit confirms that
  public `TextureSampling` collapses both wrap axes, runtime importer textures
  use default sampling, and standard material slots expose no per-slot
  `KHR_texture_transform` contract. No separate upstream checkout/commit or
  durable Glorvia runtime fixture was found, so Task 6 Steps 1-6 remain
  unchecked and M2 remains open. A partial Task 6 red-test draft was removed
  before the checkpoint so the committed tree stays green.
- 2026-07-11: Completed Task 4. Added one shared glTF texture-binding reader
  for exact core sampler enums/defaults and ratified `KHR_texture_transform`
  semantics; routed core and selected extension texture slots through it at
  primitive traversal; supplied ordinary and Draco-authored `TEXCOORD_n`
  availability plus top-level transform requiredness from the capability
  reader; preserved optional malformed-transform core fallback while blocking
  the required form before adapter import; and kept image-byte resolution and
  color/data/normal role selection outside the shared reader. Authored image
  bytes remain unchanged, finite negative scale is preserved, missing
  effective UV sets are typed diagnostics, and no UV generation or wrong-set
  fallback was added. Independent review found and verified fixes for two
  ownership details: missing UV is explicitly non-blocking, and capability
  traversal only supplies UV-set and requiredness context instead of
  duplicating transform interpretation. Task 6 remains the renderer
  application gate for M2.
- 2026-07-11: Completed Task 3. Added the immutable public texture sampler,
  transform, slot, and binding model; added all twelve per-slot binding
  siblings while preserving the const `MaterialPatch` constructor and legacy
  `TextureSource` fields/JSON; normalized source-only fields through default
  bindings; rejected source-and-binding conflicts through typed validation and
  persisted-input `FormatException`; and routed controller binding calls only
  by explicit `MaterialTextureSlot`. Independent task review approved the
  slice with no findings. This slice adds no renderer behavior, byte baking,
  UV generation, or inferred texture slots. Task 6 remains the renderer
  application gate for M2.
- 2026-07-11: M1 truthful-baseline milestone passed. Tasks 1, 2, and 5 are
  independently reviewed and approved; the milestone harness passed. This
  closes the wrapper capability/evidence, authored-patch isolation,
  asset-repair removal, and fixed-reference-state slices only. GPU/visual and
  physical iOS, Android, and Web evidence remain `not run`.
- 2026-07-11: Completed Task 5. Added the schema-versioned fixed camera,
  environment, and lighting evidence fixture; documented Khronos as normative,
  Filament/Karis as audit direction, the pinned `flutter_scene` source as
  implementation evidence, and Frostbite as outside glTF material ownership;
  linked the fixture from the acceptance manifest; and added schema tests that
  bind its values to existing studio defaults. Independent task review approved
  the slice with no findings. This slice adds no viewer API or renderer
  behavior. Physical iOS, Android material rendering, and Web material
  rendering remain `not run`.
- 2026-07-11: Completed Task 2. Split imported authored core material patches
  from independently validated opaque-IOR, specular, clearcoat, and
  transmission/volume groups; kept direct public material patches atomic;
  reclassified opaque IOR outside the glass base family; and removed PNG-alpha
  inference and neutral-white asset mutation while preserving asset-quality
  diagnostics. Independent task review approved the slice with no findings.
  Package-local material features remain `candidate-only` and skipped GPU
  targets remain `not run`.
- 2026-07-11: Completed Task 1. Added per-feature/per-target runtime
  capability, release-maturity, and evidence modeling; kept package-local
  shader support `candidate-only`; migrated runtime authorization away from
  aggregate readiness; demoted simulator-only documentation claims; and
  migrated all repository callers to the new support shape. Independent
  task review approved the slice with no remaining findings. Physical iOS,
  Android material rendering, and Web material rendering remain `not run`.
- 2026-07-05: Captured the expanded no-bake selected-extension requirement in
  a parallel planning document after the bounded Plan 013 baseline.
- 2026-07-10: Promoted the work into canonical active Plan 014. Moved completed
  Plan 013 to `completed` and unfinished Plan 012 to `deferred` without
  claiming its open work was complete.
- 2026-07-10: Integrated the repo-local `pbr-materials` source hierarchy,
  upstream-first renderer ownership gate, early fixed lighting baseline,
  normative material acceptance, fallback state machine, decoder budgets, and
  durable target-evidence requirements.
- 2026-07-10: Corrected the plan contract after review: split release maturity
  from per-target evidence, replaced aggregate feature authorization with
  feature/target queries, added authored extension-group isolation, made the
  texture API slot-aware and defensively immutable, supplied UV/requiredness
  context to the shared reader, accepted normative negative scale, and added
  explicit A1B32, Glorvia, deferral, and release closure gates.

## Verification log

- 2026-07-11: Pause checkpoint verification: after removing the incomplete
  Task 6 red-test draft, `bash tools/run_checks.sh` passed repo lint, formatting
  with zero changes, dependency resolution, `flutter analyze` with no issues,
  and 297 tests with 13 existing GPU/Impeller-gated skips. Those skips remain
  `not run` and provide no renderer, visual, physical iOS, Android, or Web
  evidence. Task 6 renderer application and Glorvia evidence were not run.
- 2026-07-11: Task 4 red evidence: the exact four-file focused command failed
  at compile time because `glb_texture_binding_reader.dart` and
  `readGlbTextureBinding` did not exist. After implementation, the same exact
  focused suite initially passed 40 tests. After review remediation, the exact
  focused suite passed 39 tests and the loader-inclusive suite passed 60 tests
  with 3 existing GPU-gated skips. This proves malformed required transform
  data fails before adapter import, the optional form imports its valid core
  fallback, and missing UV remains non-blocking with exactly one diagnostic.
  The pre-review full `bash tools/run_checks.sh` harness passed
  repo lint, formatting, dependency resolution, analysis, and 297 tests with
  13 existing GPU/Impeller-gated skips. The required follow-up
  `python3 tools/repo_lint.py` and `git diff --check` commands passed. The
  skipped GPU/visual/physical-device rows remain `not run`; this task adds
  binding metadata only and does not establish renderer application evidence.
- 2026-07-11: Task 3 red evidence: the exact three-file focused command failed
  at compile time because `MaterialTextureBinding`, sampler/transform/slot
  types, binding fields, and `setPartTextureBinding` did not exist. After
  implementation, the same focused suite passed 57 tests; `flutter analyze`
  reported no issues; and `git diff --check` passed. Tests cover stable binding
  JSON, nullable unspecified filters, finite and non-negative validation,
  defensive transform-list immutability, finite negative scale, all twelve
  patch binding fields, legacy source-only JSON, typed/JSON conflict rejection,
  source-only normalization, and explicit all-slot controller routing. This
  model/controller slice ran no GPU or visual checks, so renderer application,
  physical iOS, Android material rendering, and Web material rendering remain
  `not run`.
- 2026-07-11: Task 5 M1 milestone gate passed after the sandbox-blocked first
  `bash tools/run_checks.sh` attempt was rerun with Flutter SDK cache access.
  The harness reported repo lint passed, zero Dart formatting changes,
  successful dependency resolution, no analyzer issues, and 273 passing tests
  with 13 existing GPU/Impeller-gated skips. The required follow-up
  `python3 tools/repo_lint.py` and `git diff --check` commands passed. The 13
  skips remain `not run` and do not establish GPU, visual, physical-device,
  Android material-rendering, or Web material-rendering evidence.
- 2026-07-11: Task 5 focused verification passed. The two-file Flutter suite
  passed 11 tests; `python3 tools/repo_lint.py` passed; and
  `git diff --check` passed. This configuration-and-documentation slice ran no
  GPU or visual captures, so physical iOS, Android material rendering, and Web
  material rendering remain `not run` and gain no release evidence.
- 2026-07-11: Task 2 red evidence: the required focused command failed because
  the opaque-IOR classifiers, grouped result shape, and extension-group enum did
  not exist, while the base-family test showed IOR-only material resolving to
  realistic glass. After implementation, the six-file focused suite passed 91
  tests with 3 existing GPU-gated skips; `flutter analyze` reported no issues;
  `python3 tools/repo_lint.py` passed; and `git diff --check` passed. The full
  `bash tools/run_checks.sh` integration harness passed 271 tests with 13
  existing GPU/Impeller-gated skips. Those skips remain `not run` evidence.
- 2026-07-11: Task 1 red evidence: the initial focused policy test failed at
  compile time because the feature, maturity, target, evidence, and
  `supportFor` APIs did not exist. After implementation and review fixes,
  `flutter test test/material_extension_policy_test.dart` passed 15 tests;
  the affected adapter/backend/native/controller suite passed 71 tests with
  10 existing GPU-gated skips; `flutter analyze` reported no issues;
  `python3 tools/repo_lint.py` passed; and `git diff --check` passed. The GPU
  skips remain `not run` and do not provide release evidence.
- 2026-07-10: After the contract correction,
  `python3 tools/repo_lint.py`, `git diff --check`, and an explicit trailing-
  whitespace scan of this untracked plan passed. This was a documentation-only
  revision; Flutter tests were `not run`, and the earlier 261-test baseline
  below remains the latest full-suite evidence.
- 2026-07-10: `python3 tools/repo_lint.py` and `git diff --check` passed after
  canonical promotion and self-review.
- 2026-07-10: `bash tools/run_checks.sh` passed after sandbox escalation for
  Flutter SDK cache writes. Dart format changed zero files, `flutter analyze`
  reported no issues, and the root suite finished with 261 passing tests and
  13 expected Flutter GPU/Impeller-gated skips. Those skips remain `not run`
  evidence and do not close any Plan 014 runtime acceptance item.
