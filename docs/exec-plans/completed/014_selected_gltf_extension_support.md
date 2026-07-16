# Selected glTF Material, Texture, and Compression Extension Support Implementation Plan

> **Status (2026-07-15): completed for the bounded Plan 014 scope.** The
> accepted implementation covers the verified `FSViewerExtendedPbr`
> UV-transform/specular/opaque-IOR path, bounded compression rewrites,
> diagnostics, and durable iOS Simulator evidence. Physical iOS, Android, Web,
> release packaging, and aggregate `production-ready` evidence remain `not run`
> or `release pending`; this closure does not promote those claims.
>
> Unchecked Task 8-11 steps are retained as historical disposition, not hidden
> completion. Renderer-native clearcoat is owned by
> [Plan 015](015_renderer_native_clearcoat.md), renderer-native
> transmission/volume by
> [Plan 016](../deferred/016_renderer_native_transmission_volume.md), and
> native decoder cancellation/resource control, authored KTX2 mip chains,
> physical-target, packaging, and release evidence by
> [Plan 017](../deferred/017_decoder_control_mip_chains_and_release_evidence.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Use the
> repo-local `pbr-materials` skill for every material, shader, IBL, lighting,
> or renderer-boundary decision. Steps use checkbox (`- [ ]`) syntax for
> tracking.

## Goal

Support the selected glTF material, texture, sampler, and compression
extensions required by production configurator assets as honest runtime
behavior, without texture baking, asset-specific material mutation, an
unbounded second renderer, or false capability claims.

## Architecture

Keep `flutter_scene_viewer` as the high-level viewer/configurator wrapper.
The wrapper owns GLB preflight, decoder rewrites, stable public texture-binding
data, persistence, validation, diagnostics, and evidence. Core-only standard
PBR materials remain native `flutter_scene.PhysicallyBasedMaterial` instances.
A supported lit material routes automatically through one internal,
material-scoped `FSViewerExtendedPbr` path when it has a nonidentity UV0
transform on a supported core texture slot, `KHR_materials_specular` intent,
or opaque `KHR_materials_ior` intent. Combined triggers use that same material;
fragment shaders are never stacked and requested behavior is never silently
dropped.

For routed materials, the bounded package-local fragment owns the five core
PBR texture/factor inputs, independent supported UV0 transforms, specular,
opaque IOR, alpha mask/cutoff, direct studio-light evaluation, IBL consumption
using `flutter_scene` resources, shadow-map sampling, fog, and the existing HDR
premultiplied output contract. `flutter_scene` continues to own scene graph,
geometry and vertex processing, rasterization, picking, camera, shadow-map
generation, environment decoding/convolution/resources, DFG/BRDF LUTs, tone
mapping/final resolve, and render scheduling outside material replacement.
This is an upstream-ready prototype for the selected extension seam, not a
general renderer or public shader graph.

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
- Do not add a Filament backend, general shader graph, unbounded custom PBR
  renderer, texture bake, UV generation, CAD repair, or asset-name-based
  material fix. The approved `FSViewerExtendedPbr` boundary is the sole bounded
  package-local PBR exception.
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

## Closure status and lineage

This file is the completed closure snapshot for the selected extension work.
No successor is active at closure; future work must be promoted from the
linked deferred plans before implementation.

- Completed Plan 013 supplies the bounded ingestion/compression baseline:
  [`013_v2_production_glb_pipeline.md`](../completed/013_v2_production_glb_pipeline.md).
  Its checked boxes do not complete this plan.
- Deferred Plan 012 preserves historical package-local shader work and iOS
  Simulator evidence:
  [`012_material_extension_production_readiness.md`](../deferred/012_material_extension_production_readiness.md).
  Its bounded implementation and evidence were reconciled here; remaining
  renderer-native and release work is explicitly owned by Plans 015-017.
- Deferred Plan 015 owns renderer-native clearcoat, Plan 016 owns
  renderer-native transmission/volume, and Plan 017 owns decoder lifecycle,
  authored mip-chain, target, packaging, and release evidence. Their open work
  is not claimed complete by this snapshot.
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
| Core BRDF, per-slot shader sampling, IBL, direct light, shadow sampling, fog, and HDR premultiplied output for routed UV/specular/opaque-IOR materials | Bounded package-local `FSViewerExtendedPbr`, structured for later upstreaming |
| Geometry, vertex processing, rasterization, picking, camera, shadow generation, environment/DFG resources, tone mapping, final resolve, render scheduling | Pinned `flutter_scene` |
| Refraction compositing and BTDF work | Upstream `flutter_scene` or an explicitly separated future backend; out of the Task 6/7 slice |
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
- The official live Glorvia product page supplies C28 at runtime rather than
  authoring it into A1B32. Its current contract is front/reverse-side albedo
  repeat `2.5 × 2.5` and crepe-normal repeat `1.0 × 1.0`. The configurator,
  not this package or the GLB, owns those URLs and values. Runtime binding
  metadata must express them without generated tiled image bytes.
- The same image may be bound to multiple slots with different UV sets,
  transforms, or sampler state.
- The pinned `flutter_scene` PBR path already provides GGX/Smith/Schlick and
  split-sum IBL lineage, but it does not expose the selected glTF material
  extension inputs as first-class runtime fields.
- Do not edit the pub cache or dependency pin for this implementation. On
  2026-07-14 the user approved one bounded package-local extended-PBR material
  for Tasks 6 and 7. It activates automatically only for supported lit
  UV/specular/opaque-IOR intent and consumes the pinned renderer's existing
  engine resources. Core-only identity materials remain native. The extended
  path must preserve source material state, renderer lifecycle contracts, and
  native-equivalent defaults while owning the selected fragment-lighting seam.

## Milestones and execution order

Plan 014 was reviewed through five independent milestones so unrelated
renderer and decoder work did not share a single acceptance decision:

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: truthful baseline | 1, 2, then 5 | Capability/evidence claims are honest, authored patch families are isolated, asset-specific mutation is removed, and the fixed lighting state exists. |
| M2: texture binding | 3, 4, then 6 | Public bindings preserve slot, UV, transform, and sampler intent; automatic `FSViewerExtendedPbr` routing applies the official Glorvia albedo 2.5/normal 1.0 contract through a real renderer path or the milestone remains `blocked`. |
| M3: A1B32 material gate | 7 | The same bounded extended path renders Draco-backed A1B32 specular and opaque IOR without material hacks under the fixed state. |
| M4: layered and transmissive materials | 8 and 9 | Candidate paths were audited and the renderer-native remainder was explicitly deferred to Plans 015 and 016 without a production claim. |
| M5: decoder and release evidence | 10 and 11 | Bounded wrapper budgets/conformance, rewritten-GLB validation, and durable Simulator evidence were accepted; codec-internal control, authored mips, physical targets, packaging, and release evidence were explicitly deferred to Plan 017. |

Do not start M2 renderer integration before M1 is complete. Tasks 3 and 4 may
prepare the wrapper model before renderer work, but Task 6 cannot be accepted
on parsing, compiler, or persistence evidence alone. Task 7 cannot be accepted
on semantic CPU tests alone.

Closure disposition:

| Milestone | Plan 014 disposition |
| --- | --- |
| M1 | Complete: capability truth, patch-family isolation, fixed lighting state, and removal of asset-specific production mutation are verified locally. |
| M2 | Complete: slot-aware bindings and automatic `FSViewerExtendedPbr` routing apply the Glorvia 2.5/1.0 UV contract with durable iOS Simulator evidence. |
| M3 | Complete: A1B32 loads through Draco, preserves hierarchy/picking/material intent, and applies specular plus opaque IOR with durable iOS Simulator evidence. |
| M4 | Dispositioned: candidate-only clearcoat and transmission paths remain non-production; renderer-native completion is deferred to Plans 015 and 016. |
| M5 | Dispositioned: bounded host/plugin conformance and validator gates are verified locally; native in-codec control, authored KTX2 mip chains, physical targets, packaging, and release maturity are deferred to Plan 017. |

## Closure and release gates

This completed bounded plan and `production-ready` remain different claims:

| Gate | Required to move Plan 014 to `completed` | Required for a `production-ready` feature/target claim |
| --- | --- | --- |
| A1B32 | Specular and opaque IOR are applied through `FSViewerExtendedPbr` with iOS Simulator evidence `verified locally`; hierarchy, picking, authored metallic/material intent, and fixed-state response invariants pass. Until real application evidence exists, Plan 014 remains `blocked`. | The exact physical iOS, Android, or Web row being claimed has real runtime evidence, release packaging evidence, and no open correctness blocker. |
| Glorvia | Base-color applies repeat 2.5 and normal applies repeat 1.0 without generated image bytes through automatic `FSViewerExtendedPbr` routing, with iOS Simulator evidence `verified locally`. If the path is unavailable or silently degrades to identity, Plan 014 remains `blocked`. | Each claimed physical target applies the sampler/transform contract and has durable target evidence. |
| Clearcoat and transmission/volume | Tasks 8 and 9 either integrate a conformant renderer path or move the remaining candidate work to an explicit deferred plan. Candidate-only completion keeps the v1 release gate blocked and must not be described as feature support. | Every claimed feature/target row passes normative, visual, packaging, and physical-runtime gates. |
| Meshopt, Draco, and BasisU | Bounded wrapper budgets, declared conformance cases, addressing, rewritten-GLB validation, and honest platform labels pass. Codec-internal cancellation/working-allocation control and authored KTX2 mip chains may close only by explicit deferral to Plan 017. | Only targets with real decoder/runtime evidence may be labeled `production-ready`; other rows remain `not run`, `candidate-only`, or `release pending`. |
| Target and release evidence | Durable host and iOS Simulator records exist, while every unexecuted physical iOS, Android, Web, and packaging row is explicitly `not run` or `release pending` and owned by Plan 017. | The exact physical/runtime target and packaged artifact being claimed must pass Plan 017; Simulator or host evidence is insufficient. |

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
- Clearcoat or transmission implementation inside `FSViewerExtendedPbr` in
  this Task 6/7 slice.
- Custom shader source fetched from the network.

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
- Create `shaders/fsviewer_extended_pbr.frag` and
  `shaders/fsviewer_extended_pbr.shaderbundle.json` for the package-built full
  fragment entry proven against the pinned Flutter GPU build hook.
- Create `lib/src/internal/flutter_scene_extended_pbr_material.dart` for the
  internal `PhysicallyBasedMaterial` subclass, deterministic parameter
  packing, shader contract preflight, and immutable library/metadata cache.
- Modify `hook/build.dart` and `pubspec.yaml` only as required to package and
  load the separate extended bundle; do not edit the dependency cache.
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

- Create: `shaders/fsviewer_extended_pbr.frag`
- Create: `shaders/fsviewer_extended_pbr.shaderbundle.json`
- Create: `lib/src/internal/flutter_scene_extended_pbr_material.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify: `hook/build.dart`
- Modify: `pubspec.yaml`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Test: `test/flutter_scene_extended_pbr_backend_test.dart`
- Test: `test/flutter_scene_extended_pbr_material_test.dart`
- Test: `test/flutter_scene_uv_transform_material_test.dart`
- Test: `test/viewer_controller_material_test.dart`
- Document: `docs/references/flutter_scene_capability_notes.md`

**Interfaces:**

- Convert `MaterialTextureBinding` sampler intent to the active renderer's
  sampler representation.
- Keep core-only identity materials on native
  `flutter_scene.PhysicallyBasedMaterial`.
- Route a lit material with a nonidentity UV0 binding on a supported core PBR
  slot through the same bounded `FSViewerExtendedPbr` path used by Task 7 for
  specular and opaque IOR. Combined triggers use one material instance.
- Keep non-UV0 bindings and material-extension texture slots diagnostic-only
  until their vertex-varying and renderer contracts exist.

- [x] **Step 1: Add failing adapter tests**

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

- [x] **Step 2: Audit the pinned renderer**

Record that the pinned `TextureSampling` exposes one address mode for both axes
even though its low-level sampler supports separate width/height modes; the
runtime importer `texture_builder.dart` constructs imported textures with
default sampling; and the standard material API has no per-slot
`KHR_texture_transform` fields. Do not edit the pub cache.

- [x] **Step 3: Implement the supported sampler subset**

For equal `wrapS`/`wrapT` values, construct the corresponding upstream
`TextureSampling` when the public API exposes it. For asymmetric wrapping or
unrepresentable filter intent, return a typed backend diagnostic until the
pinned renderer exposes separate axes. Pass binding sampler intent through
every wrapper-created `Texture2D.fromAsset`, `fromImage`, and `fromPixels` path.
Any current or future texture cache key must include content role and sampler
state; transform remains per material slot and must never be stored as mutable
state on a shared image object.

- [x] **Step 4: Establish RED and integrate the combined extended-PBR foundation**

The dependency pin and pub cache remain unchanged. Before production changes,
add and run a fresh focused failing test proving all three missing seams:

- the pinned generated lit `.fmat` path always invokes the fixed native
  `EvaluateLighting`, whose `MaterialInputs` and fixed dielectric F0 cannot
  consume requested specular or opaque-IOR intent;
- the package-built full fragment entry and reflected contract do not exist;
- shader, entry, or contract unavailability causes no primitive replacement,
  persisted override, or render request.

Record the exact RED command and failure below. Historical failures and skipped
renderer tests do not satisfy this RED gate. Then package the separate full
fragment entry, implement the internal `PhysicallyBasedMaterial` subclass and
deterministic parameter packing, and preflight the bundle entry, uniform
layout, texture slots, and samplers before material mutation. First prove
native-equivalent defaults: `specularFactor = 1`,
`specularColor = [1, 1, 1]`, `ior = 1.5`, and identity UV transforms.

#### Approved combined Task 6/7 material design

**Ownership and activation**

- The caller/configurator supplies each texture URL or bytes, slot, sampler,
  UV set, and transform through `MaterialTextureBinding`. The material never
  infers C28, A1B32, or repeat `2.5` from asset names.
- Core-only identity materials remain native. The extended path is eligible
  only for a lit `PhysicallyBasedMaterial` and at least one supported trigger:
  a nonidentity UV0 transform on base color, metallic-roughness, normal,
  occlusion, or emissive; specular intent; or opaque-IOR intent.
- Unlit materials, `texCoord > 0`, extension slots, unavailable shaders, and
  unsupported mixed states return typed diagnostics before texture decode,
  material replacement, persistence, or render requests. There is no silent
  identity fallback.
- UV, specular, and opaque IOR on one material compose through exactly one
  extended instance. No opt-in flag, fragment stacking, or asset/product
  branch is allowed.

**Material and shader boundary**

- Add one internal material subclass of
  `flutter_scene.PhysicallyBasedMaterial`. It copies and preserves the source
  texture sources, base/emissive factors, metallic/roughness factors, normal
  scale, occlusion strength, environment, alpha mode/cutoff, double-sided
  state, specular antialiasing controls, opacity classification, and inherited
  reflection-roughness prepass behavior.
- Package one full Flutter GPU fragment entry through the package build hook.
  Do not use the lit `.fmat` emitter for this entry: its mandatory fixed
  `EvaluateLighting(material)` call cannot express the approved seam.
- The subclass reuses the native PBR binding path for `FragInfo`, the five core
  textures/samplers, engine lighting, IBL, shadow, fog, and render state, then
  binds only deterministic extended parameters and specular textures required
  by the reflected contract.
- For routed materials the fragment owns core sampling, alpha mask, normal
  preparation, the selected dielectric specular/IOR equations, direct studio
  light, IBL using `flutter_scene` environment/DFG resources, generated-shadow
  sampling, fog, and HDR premultiplied output. It preserves the pinned
  renderer's geometry, vertex-varying, rasterization, picking, camera,
  environment-generation, tone-mapping, final-resolve, and scheduling
  contracts.
- Re-express Khronos and public PBR equations and record applicable source and
  license attribution. Do not blindly copy third-party shader source.

**Normative transform behavior**

- Compute each slot independently as
  `offset + rotationMatrix(rotation) * (uv * scale)`, matching ratified
  `KHR_texture_transform` order and defaults. Finite negative scale remains
  valid. Precompute cosine and sine on the CPU and pack each slot as two
  std140 `vec4` values so shader layout is deterministic.
- Use the transformed normal-slot coordinates both for the normal texture read
  and derivative-derived tangent frame. Never store transform state on a
  shared image or sampler object.
- Preserve separately created per-slot texture sources and samplers. The first
  bridge slice supports the already-verified equal-axis sampler subset;
  asymmetric axes remain typed diagnostic-only until an explicit low-level
  per-binding sampler route is separately accepted.

**Atomicity and lifecycle**

- Preflight the generated shader entry and metadata, validate every requested
  binding, load all required texture sources, construct and configure the
  replacement material, and only then replace the addressed primitive.
- A failure leaves the live primitive, controller override store, encoded
  bytes, UV buffers, geometry, visibility, and render-request count unchanged.
  Reset restores the exact captured source material through the existing
  adapter lifecycle.
- Cache the immutable shader library/metadata only. Material transform state
  remains per primitive and per slot. Any future texture cache includes
  content role and sampler state and never includes mutable transform state.

**Capability and evidence labels**

- Successful local application is an automatic
  `flutterSceneExtendedPbr`/`candidate-only` runtime capability, not
  renderer-native support and not a production-ready claim.
- Acceptance requires RED/GREEN CPU and compiler tests for independent
  base-color/normal transforms, offset/rotation/negative scale, same-source
  distinct bindings, native-equivalent defaults, combined routing,
  shader-unavailable atomicity, reset, and no generated bytes. GPU-gated
  binding tests plus fixed-state iPhone 17 Simulator and Three.js evidence must
  show C28 albedo `2.5 × 2.5` and crepe normal `1.0 × 1.0` without the current
  identity fallback.

- [x] **Step 5: Add Glorvia runtime evidence**

Accepted on 2026-07-14: the official external texture URLs, response metadata,
byte hashes, Three.js reference, and real iPhone 17 Simulator extended-path
artifacts are recorded. The current run applies the caller-provided transforms
without `perSlotUvTransformContractMissing` diagnostics.

Apply front/reverse-side albedo at repeat `2.5 × 2.5` and crepe normal at
repeat `1.0 × 1.0` through the slot-aware `setPartTextureBinding` API. Assert
the original encoded bytes are unchanged and capture transform differences
under the fixed reference state. The caller supplies these values; the package
must contain no A1B32/C28 conditional.

- [x] **Step 6: Verify Task 6**

```sh
flutter test --no-pub test/flutter_scene_uv_transform_material_test.dart test/flutter_scene_extended_pbr_material_test.dart test/flutter_scene_extended_pbr_backend_test.dart test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart
bash tools/run_checks.sh
```

Expected: automatic extended routing applies transformed UVs and sampler state
on supported targets; other targets emit diagnostics. No tiled image bytes are
generated. This task remains `blocked` rather than accepted if the Glorvia gate
has no real renderer application. Candidate evidence does not change any
physical-target or production-ready row.

### Task 7: Integrate KHR_materials_specular and opaque IOR through FSViewerExtendedPbr

**Files:**

- Modify: `lib/src/material_patch.dart`
- Modify: `lib/src/material_extension_policy.dart`
- Modify: `lib/src/internal/glb_material_extension_reader.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify: `lib/src/internal/material_extension_native_capability.dart`
- Modify: `lib/src/internal/material_extension_native_applier.dart`
- Modify: `lib/src/internal/flutter_scene_extended_pbr_material.dart`
- Modify: `shaders/fsviewer_extended_pbr.frag`
- Test: `test/material_patch_test.dart`
- Test: `test/material_extension_policy_test.dart`
- Test: `test/glb_material_extension_reader_test.dart`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Test: `test/material_extension_native_applier_test.dart`
- Test: `test/flutter_scene_extended_pbr_material_test.dart`

**Interfaces:**

- Preserve `specularFactor`, `specularTexture`, `specularColorFactor`,
  `specularColorTexture`, and opaque `ior` through the wrapper.
- Automatic extended routing must apply them to the dielectric response; do
  not map them to metallic, roughness, clearcoat, alpha, or transmission.

- [x] **Step 1: Add failing semantic tests**

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

Current status: public and authored-data validation/parsing semantics are
covered, including invalid-group isolation and opaque classification for
`ior == 0`. The existing skipped renderer assertions are a RED inventory, not
acceptance evidence; remove only skips satisfied by the real implementation
and retain their meaningful assertions.

- [x] **Step 2: Run focused tests and confirm renderer red**

```sh
flutter test test/material_patch_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_adapter_material_test.dart test/material_extension_native_applier_test.dart
```

Expected before implementation: parsing passes where already present, while
the fresh extended-fragment contract/material-replacement test fails. Record
that current failure as the new RED; historical validation failures and a skip
do not satisfy this step.

- [x] **Step 3: Implement the extended specular and opaque-IOR contract**

Add specular factor/color factors and textures plus opaque IOR to the internal
extended material and fragment. The specular factor texture samples alpha in
linear space; the color texture samples sRGB RGB and decodes it; samples and
factors multiply. Specular modifies only the dielectric response. Apply
Khronos diffuse/specular energy sharing and keep metallic response isolated.
For ordinary finite IOR greater than or equal to 1, use
`((ior - 1) / (ior + 1))^2`; verify 1.5 maps to 0.04. Treat exactly `ior == 0`
as the Khronos compatibility mode whose Fresnel is always 1, not as IOR 1 or a
clamped denominator. Opaque IOR remains in the ordinary opaque PBR family.
Do not expose GGX, Smith, Schlick, DFG, precision, or roughness-remap choices
in viewer APIs.

- [x] **Step 4: Wire automatic routing and atomic capability**

Keep core-only identity materials native. Route any supported UV-transform,
specular, or opaque-IOR trigger to exactly one extended material; compose
combined patches without group loss. Preflight validation, shader contract,
every required texture, and full material construction before replacing the
primitive. Only then persist the override and request a frame. Any failure
leaves the live material, override store, encoded bytes, UVs, geometry,
visibility, and render-request count unchanged. Set per-feature runtime support
available only when the active extended path consumes every requested field;
record `candidate-only` maturity and target evidence independently.

- [x] **Step 5: Run the A1B32 intermediate gate**

Verify Draco load, 20 primitives, hierarchy, picking, unmodified material
intent, metallic remaining authored, no forced clearcoat/roughness/alpha, and
visible specular/IOR trends under the fixed reference state.

- [x] **Step 6: Verify Task 7**

```sh
flutter test --no-pub test/material_patch_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_adapter_material_test.dart test/material_extension_native_applier_test.dart
bash tools/run_checks.sh
```

Expected: all commands pass and A1B32 evidence is labeled for the exact target.
If specular or opaque IOR is not applied by the full fragment, Task 7 and Plan
014 remain `blocked`; a green parsing, compiler, or CPU suite alone does not
satisfy the A1B32 closure gate. The fresh RED, real implementation, A1B32 iOS
Simulator evidence, and passing final repository harness were recorded on
2026-07-14. Other targets and production readiness remain `not run`.

#### Task 6/7 required test layers

- CPU/Khronos semantics: per-slot transform order/defaults, negative scale,
  transformed normal derivatives, specular factor/color validation and
  multiplication, linear alpha versus sRGB RGB sampling, IOR values 1, 1.5,
  greater than 1, and 0, dielectric F0, compatibility full Fresnel,
  diffuse/specular energy sharing, and metallic isolation.
- Routing and atomicity: core identity stays native; UV, specular, and opaque
  IOR each route extended; combined UV/specular/IOR produces one extended
  material; shader, texture, metadata, uniform, or sampler failure causes zero
  live-material, persistence, byte, UV, geometry, visibility, and render-count
  mutation; reset restores the exact captured source material.
- Shader/compiler/GPU: the raw bundle entry compiles, its reflected
  uniform/sampler contract matches deterministic packing, native-equivalent
  defaults hold, independent core-slot transforms render, factor/color and IOR
  trend matrices are visible, shadows/IBL/fog/HDR-premultiplied output remain
  intact, and the retained source reflection-roughness prepass behavior is
  unchanged.
- Real gates: Glorvia uses the caller-provided C28 albedo repeat 2.5 and normal
  repeat 1.0 without generated bytes; A1B32 preserves 20 primitives,
  hierarchy, picking, authored metallic/material intent, and visibly applies
  specular/opaque IOR under fixed camera, lighting, environment, and renderer
  metadata. The iPhone Simulator and Three.js artifacts require paths and
  hashes. Physical iOS, Android, and Web remain `not run` until executed.

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

Safe-slice status: RED-first CPU tests now cover the generated `.fmat`
lighting boundary, factor-zero overlay behavior, independent base and coat
normals, double-sided diagnostic atomicity, combined/later core normal
patches, and failed overlay reconfiguration. The existing factor/roughness/
normal visual matrix remains explicitly GPU/Impeller-gated and was not rerun
after the shader audit, so Step 1 remains partial and unchecked.

- [x] **Step 2: Classify the current shader**

Audit heuristic directional highlight, emissive overlay, alpha behavior,
source-normal suppression, shadows, and indirect-specular occlusion. Preserve
the result as `candidate-only` unless every selected target gate passes.

Audit result: the first source-only audit missed that pinned `flutter_scene`
always appends `EvaluateLighting(material)` for a lit `.fmat`; independent
review caught the resulting manual-lobe plus engine-lobe double count. The
remediated material compiles to exactly one engine lighting evaluation and no
longer authors a heuristic direct highlight, BRDF/IBL/shadow calculation, or
coat-emissive lighting path. Engine lighting owns the candidate coat's direct
light, IBL, shadows, roughness, independent coat normal, and occlusion. A
second independent review caught source PBR normal suppression; that
suppression, `.35` scale attenuation, restore state, and adapter
synchronization are removed, so the base normal stays on the retained PBR
primitive while the overlay uses only its coat normal. The alpha overlay still
cannot weight coat-lobe energy independently from base Fresnel attenuation,
and its fixed alpha/culling path cannot preserve double-sided source material.
Double-sided clearcoat therefore returns a typed pre-mutation diagnostic. The
remaining overlay is explicitly non-conformant `candidate-only` behavior.

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

Safe-slice status: the bounded audit is independently approved with no
Important findings after two RED-first remediations. Focused CPU suites and the
exact three-file Task 8 command pass, but 12 GPU/Impeller tests are explicit
skips and no post-change Khronos/target capture exists. Renderer-native work is
deferred to
[Plan 015](015_renderer_native_clearcoat.md). Step 3, Step 4, Step
5, Task 8, M4, the v1 clearcoat release gate, and production-ready target rows
remain `blocked`/`not run`.

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

Safe-slice status: RED-first source/compiler and adapter/backend tests now
cover red/green channels, factor-zero passthrough and active reset, alpha
independence, zero-thickness refraction, positive-thickness/node-transform
diagnostics, `ior == 0`, candidate texture/base-PBR isolation, missing
scene-view diagnostics, and decode/mutation atomicity. Metal isolation,
opaque-behind-glass rendering, positive node-scaled volume, and the live
scene-color contract remain explicit renderer/GPU acceptance gaps, so Step 1
is partial and remains unchecked.

- [x] **Step 2: Audit the bounded candidate shader**

Flag or remove hard-coded glint/contour color, red-channel thickness sampling,
thin-surface macro refraction, arbitrary alpha caps, and assumptions that
conflict with Khronos semantics. Do not relabel the bounded screen-space path
as nested or full volume transport.

Audit result: transmission/thickness use red/green; thin transmission has no
macroscopic offset; alpha remains source coverage; authored glint/contour/
studio cues, arbitrary alpha caps, roughness base mixing, synthetic reflection
tint, HDR clamping, and attenuation-color flooring are removed. Factor zero
bypasses the unlit candidate and composes core PBR through the standard path.
Positive transmission textures, positive thickness, `ior == 0`, and missing
scene-view contracts preserve intent through typed pre-decode diagnostics.
The remaining scalar thin screen-space path is explicitly non-conformant
`candidate-only` behavior.

- [ ] **Step 3: Prefer renderer-owned compositing**

Integrate upstream scene-color sampling/refraction and material fields when
available. If unavailable, retain candidate-only behavior and typed
diagnostics.

Blocked status: pinned `flutter_scene`
`cd6760912fa38beb55f63e388655a1aeabd32fe4` exposes scene-color render targets
but no standard-material transmission, volume, attenuation, or variable-IOR
contract. No separate upstream checkout/commit is available and the dependency
pin is unchanged.

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
diagnostic, moves remaining renderer work to an explicit deferred glass
follow-up, keeps target rows unchecked, marks the conditional disposition
acceptance item only after the deferred link is recorded, and keeps the v1
release gate blocked.

Safe-slice status: the bounded audit is independently approved with no
Important findings after three RED-first remediation cycles. Focused CPU suites
and the exact three-file Task 9 command pass, but 13 GPU/Impeller, generated-
shader, visual, and renderer tests are explicit skips and no post-change
Khronos/target capture exists. Renderer-native work is deferred to
[Plan 016](../deferred/016_renderer_native_transmission_volume.md). Steps 3-4,
Step 5, Task 9, M4, the v1 glass release gate, and production-ready target rows
remain `blocked`/`not run`.

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

Safe-slice status: RED-first VM and Chrome tests now cover web-safe checked
products/accumulation, negative and greater-than-max-exact operands, exact
limits, Meshopt declared output and aggregate decoded-byte budgets, JSON
budget, malformed embedded-BIN length before padding allocation, a two-view
second-budget-failure with no partial output, and ModelLoader native decoded-
GLB output limits before capability re-read/import. The independently approved
Draco Dart-boundary slice additionally covers malformed accessor schemas,
decoded payload length mismatch, all authored attribute-count coherence, empty
Draco attribute maps, duplicate/reused accessor accounting, exact and exceeded
accessor/vertex/index/decoded-byte limits, malformed embedded-BIN declarations,
and preflight/post-build failures with no output, source mutation, or caller-
tracker consumption. The independently approved BasisU Dart-boundary slice
adds exact/over JSON, decoded-byte, and aggregate native-output budgets;
malformed embedded-BIN declarations; duplicate, missing, empty, unsupported,
out-of-range, and unreferenced decoded-image outputs; shared-image request
deduplication; and late failure with no partial output, source-intent mutation,
or tracker consumption. Root integration tests additionally cover exact and
one-byte-below final-output envelopes for component Draco, component BasisU,
and opaque native GLB responses, plus malformed output-accounting metadata and
mixed sequential decoder stages. The independently approved Draco native-
preflight slice additionally covers exact/exceeded/aggregate native limits,
web-safe overflow, missing/wrong-type/negative/32-bit-alias component metadata,
malformed additional authored accessors before channel invocation, and a later
missing Draco attribute with zero output-vector allocations or partial output.
The independently approved BasisU native-preflight slice covers exact/exceeded
and cumulative texture-pixel/native/decoded budgets, KTX2 fixed-header and
declared Level Index truncation, 2D layout, checked PNG envelope arithmetic,
missing/mismatched decoded dimensions, malformed platform request types, and
second-image all-or-nothing failure. The independently approved structural-
profile slice now also covers bounded DFD/KVD parsing, malformed range/
structure precedence, valid BOM-free UTF-8 keys, strict Unicode-code-point
ordering, global key uniqueness, zero value padding, codec/supercompression
pairs, dimensions, channel shapes, structural color-space pairs, orientation,
swizzle, and premultiplication before output reservation or codec entry. The
independently approved usage-role slice additionally covers exact selected
core/specular/clearcoat/transmission/volume texture-slot roles, texture-to-
shared-image aggregation, unused structural-only requests, ambiguous color/
non-color sharing, exact platform metadata parsing, and role/DFD mismatch
diagnostics before output reservation or codec entry. The independently
approved channel-aware follow-up matches the exact selected-channel envelope
for each supported slot, preserves the valid packed specular-color RGB plus
linear specular-factor alpha case, rejects only color/non-color overlap in RGB,
and validates the derived `r`/`rg`/`rgb`/`rgba` layout against the KTX2 DFD
before output reservation or codec entry. Only exact `MASK` and `BLEND`
base-color intent requires alpha; malformed alpha-mode values do not invent
alpha semantics during this bounded preflight. The actual Draco validator
follow-up additionally rejects decoded NaN and positive/negative infinity as a
typed `decodedPayloadValues`/`malformedOutput` diagnostic during Draco
preflight, before output construction or tracker commit. Official conformance
is now closed by Step 2. Cancellation and codec-internal allocation limits
remain uncovered, so Step 1 is partial and remains unchecked.

The independently approved decoder-control audit records an exact
machine-readable blocker for Meshopt, Draco, and BasisU without promoting any
capability. Full-file SHA-256 fingerprints cover the synchronous Dart decoder,
root MethodChannel probe, pinned codec headers, C++ bridges, Android Java/JNI
adapters, and iOS Flutter plugin handlers. Mutation tests reject alternative
`deadline`, `timeoutMs`, `shouldCancel`, and `cancelToken` contracts until the
blocker is deliberately reassessed. Current sources expose no cooperative
cancellation or codec-internal bounded allocator, so this evidence does not
satisfy the missing cancellation behavior test and Step 1 remains unchecked.

The independently approved native-timeout partial slice now adds behavior
coverage at the Dart MethodChannel result boundary. One shared monotonic
deadline covers sequential Draco then BasisU waits. An expired deadline returns
a typed `modelLoadTimeout` diagnostic before channel dispatch; an in-flight
timeout records `nativeDispatch: started`,
`nativeResourceRelease: notGuaranteed`, and `lateResult: discardedByDart`.
Delayed native responses cannot enter GLB rewrite, commit tracker state, reach
adapter import, or start a later decoder stage. This covers Dart-side timeout
consumption only. The Meshopt follow-up below covers its pure-Dart deadline;
cooperative external cancellation, native resource release, and codec-internal
allocation limits remain uncovered, so Step 1 is still partial and unchecked.

The independently approved Meshopt timeout follow-up adds one monotonic
deadline across all compressed bufferViews, checks it before decode allocation
and at approximate decoded-byte intervals across every claimed mode and
filter, and maps expiry to typed `modelLoadTimeout` diagnostics. A shadow
tracker commits decoded bytes exactly once only after complete rewrite
success. Mid-decode and later-bufferView timeout tests prove null output,
unchanged caller accounting, preserved source extension intent, and honest
`started` versus `notStartedForBufferView` work labels. Timed-out Dart buffers
become garbage-collectible after stack unwind, but collection is not
deterministic. There is still no external cancellation signal or codec-internal
allocation budget, so Step 1 remains partial and unchecked.

A post-timeout cancellation audit confirms that no existing model-load signal
can safely close the remaining behavior gate. `ModelLoader.load` and
`FlutterSceneViewerController.load` expose no cancellation token or generation
callback, while the similarly named `isCanceled` path is scoped only to
environment configuration. Meshopt decode and rewrite remain synchronous in
the caller isolate, so an event-loop-driven source replacement could not be
observed by merely adding a synchronous callback inside the decoder. Real
external cancellation would require a broader loader/controller contract plus
interruptible worker execution or another cross-isolate signal. Adding a local
callback would therefore fake cancellation and is intentionally not done.
Draco 1.5.7 and the pinned BasisU transcoder still expose no cooperative poll,
cancel endpoint, deadline, or bounded allocator. Step 1 remains partial and
unchecked on these exact blockers.

- [x] **Step 2: Add conformance fixtures**

Meshopt: every claimed mode/filter plus legal placeholder buffers and
`KHR_mesh_quantization` interaction.

Draco: bitstream 2.2, TRIANGLES and TRIANGLE_STRIP, attribute-ID mapping,
accessor schemas, untouched extra attributes, and official decoder comparison.

BasisU: ETC1S/BasisLZ, UASTC none/Zstd, RGB/RGBA/R/RG layouts, DFD transfer and
primaries, orientation/swizzle/premultiplication restrictions, mips, and
unsupported layout diagnostics.

Safe-slice status: the independently approved Meshopt conformance slice pins
the official Khronos `MeshoptCubeTest` corpus with immutable source, SHA-256,
and license records. Fifty-four claimed direct-decoder cases cover
`ATTRIBUTES`, `TRIANGLES`, and `INDICES` plus `NONE`, `OCTAHEDRAL`,
`QUATERNION`, and `EXPONENTIAL`; six KHR-only `COLOR` cases remain explicitly
excluded. `ATTRIBUTES` and `INDICES` match official fallback bytes exactly,
while `TRIANGLES` preserves triangle order and winding with only cyclic index
rotation. The corpus proves both ATTRIBUTES bitstream versions, but only
official v0 bytes count toward the runtime `EXT_meshopt_compression` claim.
The EXT rewrite now rejects KHR-only v1 before decoder entry or budget
reservation, and an official-v0 embedded-GLB derivative proves exact
POSITION/NORMAL rewrite while retaining quantized accessor schemas and
`KHR_mesh_quantization`. Placeholder-buffer rules are covered in both
reference directions. The ModelLoader integration fixture also uses a coherent
EXT v0 literal stream and proves exact `[1, 2, 3, 4]` output after a broader
verification run exposed its stale KHR-only v1 helper. This is direct-codec/
wrapper host evidence only; it adds
no `.gltf`, KHR Meshopt, `COLOR`, or target runtime support. The independently
approved Draco conformance slice pins the official Khronos `Box/glTF-Draco`
fixture with immutable source, corrected SHA-256 records, CC-BY-4.0
attribution, and a reproducible fetch script. Its 118-byte Draco 2.2 payload is
decoded through `FsvDracoDecodePrimitives` and independently through the pinned
Google Draco 1.5.7 decoder; NORMAL unique ID 0, POSITION unique ID 1, 24
vertices per attribute, 36 unsigned-short indices, and all 648 output bytes
match exactly. Default and explicit `TRIANGLES` reach the native channel, while
`TRIANGLE_STRIP` now returns a typed `dracoPrimitiveMode`/
`unsupportedLayout` diagnostic before channel invocation because the bridge
emits triangle face-list indices and cannot preserve authored strip topology.
Additional uncompressed accessor intent remains on the normal glTF path. This
is host direct-codec/wrapper evidence only; it adds no Android/iOS runtime,
device, packaging, release, or production-readiness claim. `TRIANGLE_STRIP`
remains diagnostic-only and BasisU conformance remains open, so Step 2 remains
partial and unchecked. The independently approved BasisU positive/direct-codec
slice pins an Apache-2.0 Khronos KTX-Software-CTS corpus with immutable source,
12 verified SHA-256 records, and a reproducible fetch script. Nine official
single-level cases cover ETC1S/BasisLZ, UASTC without supercompression, UASTC
with Zstandard, and RGBA/RGB/RG/R source layouts; bridge PNG level-0 pixels
match an independently invoked pinned transcoder byte-for-byte. The UASTC
`R8G8` fixture reports generic `UASTC_DATA` channel 0 rather than the
`UASTC_RG` channel 6 required by `KHR_texture_basisu`, so it is explicitly a
codec/source-layout oracle only; ETC1S `RRR + GGG` supplies the conformant RG
case. Two official authored-mip fixtures now return typed
`unsupportedKtx2Layout`/`ktx2MipLevels` diagnostics after Level Index
overflow/truncation validation but before transcoder initialization or output
allocation, because the PNG bridge cannot preserve an authored mip pyramid.
This is host direct-codec/wrapper evidence only. DFD transfer/primaries and
usage-role validation, orientation, swizzle, premultiplication, compliant
UASTC-RG evidence, and unsupported-profile diagnostics remain open, so Step 2
remains partial and unchecked.

The independently approved BasisU structural-profile slice expands the pinned
Khronos KTX-Software-CTS corpus to 21 hash-verified artifacts including the
license and nine official profile-negative KTX2 files. Fourteen profile
negatives, three accepted structural cases, and seven malformed-container/KVD
cases now return typed diagnostics before output reservation, transcoder
initialization, or pixel allocation. Coverage includes permitted codec/
supercompression pairs, 2D/multiple-of-four layout, ETC1S/UASTC channel shapes,
R/RG linear-only transfer, structural RGB/RGBA color-space pairs, allowed or
omitted orientation and swizzle, premultiplied-alpha rejection, valid BOM-free
UTF-8 keys, strict KVD ordering/uniqueness, and zero value padding. The UASTC R
rule uses an official pinned source. UASTC_RG(6) has narrowly labelled
synthetic DFD branch coverage only; its payload remains the R source, so it is
not compliant codec-fixture evidence. The independently approved usage-role
slice now matches selected glTF material use without filenames, pixels, alpha
heuristics, or renderer assumptions. Core base-color/emissive and specular-
color RGB require BT709+sRGB; core data-map RGB channels plus specular-factor
alpha, all three clearcoat RGB components, transmission red, and volume-
thickness green require linear interpretation. Khronos sRGB transfer does not
apply to alpha, so one image carrying specular-color RGB and specular-factor
alpha is valid and remains a color `rgba` request. Only color RGB sharing a
linear R, G, or B channel is ambiguous and returns typed
`unsupportedKtx2Usage`; valid roles or derived channel layouts with wrong DFD
metadata return typed `unsupportedKtx2Profile`. Texture transform does not
change the role, IOR has no texture, and channel requirements are OR-aggregated
through texture indices to each shared BasisU image. Unused images retain the
structural-only path. Android and iOS require exact case-sensitive role and
channel-layout metadata, while direct host calls explicitly default to
structural-only. A compliant UASTC-RG fixture and official evidence for the
accepted UASTC DATA(0)/RGB(0) alias remain open. This is host-only structural/
direct-codec evidence and adds no target runtime, packaging, release, or
production-readiness claim; Step 2 remains partial and unchecked.

The current UASTC-RG closure slice pins the official 304-byte Khronos CTS
`valid_R8G8_UNORM_2D_UASTC` source at SHA-256
`318f68b48970fcdf76fbc407bfdc83a8afef6f611382f1283ff8106345b4a5d9`.
That generic KTX source contains an R8G8-authored UASTC payload but uses BT709
primaries and `UASTC_RRRG(5)`. A deterministic repository tool derives the
selected glTF profile by changing only DFD offsets 117 and 135 to UNSPECIFIED
primaries and `UASTC_RG(6)`; the resulting 304 bytes have SHA-256
`602fcde544d7bb6c9272bea35f420c9fc9e76e2f7b182d7849dfa5d5bdde8bbd`.
The actual native bridge and independently invoked pinned transcoder agree on
the derived payload, exact `rg` selected usage accepts it, an `rgb` request
rejects it, and an sRGB mutation returns the profile diagnostic. Numeric UASTC
channel 0 is retained as the KHR RGB category only when the UASTC model and
selected `rgb` layout supply that context; it cannot stand in for channel-6 RG.
The derived fixture is explicitly not represented as an unmodified official
CTS file. Review initially found one Important mutation-safety gap because the
UASTC channel-0 RGB interpretation was exercised only under structural layout.
Official UASTC RGB channel-0 now passes selected `rgb` and rejects selected
`rg`; the generic UASTC R8G8/DATA(0) source also rejects selected `rg`. An
intentional Android/iOS `kRgb` to `kRg` fallback mutation failed the exact new
case before the correct branch behavior was restored. Final independent
rereview returned `APPROVE` and confirmed that all listed Meshopt, Draco, and
BasisU conformance bullets are satisfied, with Draco `TRIANGLE_STRIP` still
honestly diagnostic-only. This closes Step 2 as host codec/profile evidence
only and adds no target, renderer, packaging, release, or production-readiness
claim. Task 10 and M5 remain open.

- [ ] **Step 3: Implement shared budget enforcement**

Apply checked arithmetic before allocation and validate native output before
GLB rewrite. Cancellation and timeout must release native/Dart resources.

Safe-slice status: `GlbDecodeBudget` and a per-load tracker now centralize the
declared JSON, decoded-byte, accessor, vertex/index, texture-pixel, native-
output, timeout, and cancellation-check limits. This slice enforces JSON and
decoded output for Meshopt plus decoded-GLB output at ModelLoader's native
boundary. The Draco Dart rewriter now performs checked two-pass validation
before rewrite allocation or mutation, charges each returned native payload,
deduplicates accessor/vertex reservations, builds the complete GLB before
atomically committing the shared tracker, and returns typed diagnostics on
malformed or over-budget input. Cancellation and timeout fields remain explicit
metadata and are not claimed as enforced. The BasisU Dart rewriter now applies
the same shadow-
tracker/two-pass/commit-after-output discipline, aggregates native image bytes,
and rejects ignored native output; the probe also emits one native request per
shared image. The user-selected budget and one per-load tracker now pass through
ModelLoader and the native probe into both rewriters. Required result metadata
distinguishes opaque final bytes from already-accounted component payloads:
component GLB containers receive a non-mutating envelope check, opaque stages
are reserved exactly once, and sequential mixed stages settle before the next
decoder starts. Draco now receives the exact limits plus current tracker state
as presence-aware 64-bit metadata on
both platform bridges; shared checked preflight runs before codec entry for all
declared accessor/output failures, and complete decoded mesh metadata is
validated before any bridge-owned output vector is allocated. The pinned
Google Draco `Decoder` still exposes no pre-decode point/face/memory,
cancellation, or timeout control, so allocations internal to
`DecodeMeshFromBuffer` remain unbounded. BasisU now receives the same exact
limit/state contract; a narrow KTX2 fixed-header/Level-Index extent and 2D
dimension/output-envelope preflight runs before `ktx2_transcoder::init`, the
post-init dimensions must match before pixel allocation, and returned PNG
width/height/IHDR plus pixel/native/decoded reservations are checked atomically
at the Dart rewrite boundary. KTX2 validity beyond the bounded fixed-header,
Level Index, DFD, and KVD structural-profile preflight remains delegated to the
pinned transcoder and is not claimed as complete container conformance. Every
request completes that structural-profile validation before bridge-owned
output reservation, transcoder initialization/start, or pixel allocation. The
channel-aware follow-up then validates every request's exact selected-channel
layout and usage role, across the complete batch, before those same allocation
and codec-entry boundaries. Actual Draco rewrite validation exposed stale
authored accessor bounds after quantized decode; the rewriter now refreshes
only already-declared `min`/`max` keys from the checked decoded payload while
preserving absent keys, and rejects non-finite float payloads before output or
budget commit. The pinned transcoder also exposes no allocator
budget, cancellation, or timeout
control inside init/start/transcode. Codec-internal allocation limits,
cancellation/resource release, timeout propagation, and complete conformance
remain open, so Step 3 is partial and unchecked.

The current source-backed control audit narrows that blocker precisely. The
Meshopt decoder remains synchronous Dart; it now accepts an internal
cooperative deadline control but no external cancellation signal. The
pinned Draco 1.5.7 `DecodeMeshFromBuffer` and BasisU `init`,
`start_transcoding`, and `transcode_image_level` APIs are synchronous and
expose no cooperative callback, deadline, or allocator budget. Their Android
and iOS MethodChannel adapters are one request/response call with no request ID
or cancel endpoint. The Dart boundary now discards a late MethodChannel result
without rewrite or tracker mutation, but cannot prove that native work stopped
or that native resources were released.
The generated decoder-control table fingerprints every source that supports
this conclusion. Independent review returned `APPROVE` only for the blocker-
evidence slice; Step 3 and its resource-release gate remain unchecked.

The independently approved timeout follow-up computes the remaining shared
deadline before dispatch, preventing zero/expired calls from starting native
work. In-flight Draco/BasisU timeouts return typed diagnostics, block later
stages, and ignore eventual results; a sequential test proves the second stage
receives only the first stage's remaining time. Pre-dispatch diagnostics use
`notStarted`/`notApplicable`, while in-flight diagnostics retain the exact
`notGuaranteed` native-release boundary. This does not add a native deadline,
cancel endpoint, cooperative codec poll, or bounded allocator. Therefore it is
a safe partial enforcement slice only; Step 3 remains unchecked.

The independently approved Meshopt timeout follow-up enforces the shared
budget's timeout inside the pure-Dart decoder without changing its synchronous
API boundary. Checkpoints cover `ATTRIBUTES`, `TRIANGLES`, `INDICES`, and the
`OCTAHEDRAL`, `QUATERNION`, and `EXPONENTIAL` filters. Timeout discards all
partial rewrite state and leaves temporary Dart allocations eligible for
garbage collection, but does not provide deterministic collection or an
external cancellation signal. Native codec resource release and allocator
control are unchanged. Step 3 and its full resource-release gate therefore
remain partial and unchecked.

The subsequent cancellation-boundary audit found no safe adapter-only
implementation. Model loads carry no cancellation signal through
`lib/src/viewer_controller.dart` or `lib/src/model_loader.dart`; Meshopt runs
synchronously in the same isolate; and the native codec requests remain
single MethodChannel calls without request identifiers or cancel endpoints.
Consequently a callback added only at the rewriter boundary would not observe
UI/source changes during decode, and a Dart timeout still cannot prove native
resource release. Closing Step 3 requires an explicit interruptible execution
architecture and upstream/native allocator or cancellation contracts, not a
wrapper-local claim. Step 3 remains unchecked.

- [x] **Step 4: Preserve honest platform labels**

Keep iOS Simulator evidence `verified locally`. Android bridge compilation is
`candidate-only` until a real app/runtime test passes. Do not claim Web support
for native-only codecs.

Safe-slice status: the Draco and BasisU budget/preflight C++ plus platform
adapters compile, and the pure/fake-codec/real-fixture runners execute locally
for byte-identical Android/iOS sources. This is host evidence only. The
generated capability source now preserves the 2026-07-04 Draco and 2026-07-05
BasisU iPhone 17 Simulator runs from completed Plan 013 as historical
`verified locally` candidate context whose original `/private/tmp` artifacts
are explicitly `not durable`. That history does not alter current Plan 014
target rows: iOS Simulator, physical iOS, and Android remain `not run` for
application, visual, and target evidence, with runtime capability
`candidate-only native plugin` and release maturity `candidate-only`; Web
remains `unsupported`/`diagnostic-only`/`not run`. Generator validation locks
those boundaries, and aggregation reads current rows only. Independent review
rejected 34 history/current-row mutations and returned `APPROVE` with no
Critical or Important findings. This closes Step 4 only. No post-change target
runtime, physical-device, packaging, or release evidence was produced; Task 10
and M5 remain open.

- [x] **Step 5: Verify Task 10**

```sh
flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/glb_draco_rewriter_test.dart test/glb_basisu_rewriter_test.dart test/model_loader_test.dart
bash tools/run_checks.sh
```

Then run `flutter test` with
`packages/flutter_scene_viewer_draco` as the working directory, and repeat
with `packages/flutter_scene_viewer_basisu` as the working directory.

Expected: every command passes; malformed or oversized decoder output fails
with typed diagnostics before adapter import.

Verification status: the exact focused root command passes 89 tests with the
three adapter GPU/Impeller cases explicitly skipped. The Draco package passes
7/7 and the BasisU package passes 12/12, including their real pinned native
bridge runners. `bash tools/run_checks.sh` passes repository lint, formatting,
dependency resolution, analysis, and the 480-pass root suite with 16 explicit
skips. The skips are the renderer-native specular/opaque-IOR acceptance test;
three ModelLoader GPU imports/environment tests; and these twelve
`flutter_scene_material_extension_backend_test.dart` GPU/visual cases:
preprocessed TextureSource binding, raw GPU texture binding, production
clearcoat loader, debug-tint shader load, transmission shader load, clearcoat
shader load, transmission refraction smoke, glass visual matrix, clearcoat
second-lobe smoke, clearcoat visual matrix, shared visual fixture, and iOS
Simulator material-extension visual matrix. This closes Step 5 only. Steps 1
and 3, Task 10, and M5 remain open on cancellation, deterministic resource
release, and codec-internal allocator control.

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

Safe-slice status: an independently approved provenance harness now pins five
official Khronos Sample Assets to commit
`2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf`, verifies each GLB and license by
byte length plus SHA-256, and reproducibly stages TextureTransformMultiTest,
SpecularTest, IORTestGrid, ClearCoatTest, and AttenuationTest under ignored
`tools/out/` paths. The user-supplied A1B32 file is accepted only for current
Plan 014 repository-local use: its 2,809,824 bytes, SHA-256
`a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592`,
GLB structure, and exact pinned-validator result are verified before local
staging. Its six severity-1 warnings retain code, message, pointer, and an
explicit target/visual disposition. Redistribution, SPDX identity, copyright
holder, and a reproducible public source remain unestablished, so A1B32 is not
vendored and Step 1 remains partial and unchecked. This establishes fixture
provenance on the host only; renderer/runtime capability, target evidence,
release maturity, and production readiness remain unestablished or `not run`.
On 2026-07-14 the user explicitly confirmed that A1B32 may be used and that
licensing is not a concern for this work; that authorization removes the
current repository-local use blocker but does not itself establish an SPDX
identifier, copyright/redistribution record, or reproducible public source.

- [ ] **Step 2: Run deterministic reference and target captures**

Capture front/left/right/back views with the fixed state. Record
reference-renderer direction separately from target evidence.

Safe-slice status: an independently approved Plan 014 harness now verifies the
exact local A1B32 bytes before rendering the unmodified authored scene through
Three.js `0.167.1` / npm `gitHead`
`42a2f6aac8cffebb29524d68eb7136a756f15960` / WebGL. It consumes fixed-state
SHA-256 `774fb35234176d4d949ac84cf6ba16fb05ee7afd7e8d1b70d42c00521f9db8ff`,
captures front/left/right/back at 640x960, and binds the source, renderer npm
integrity, Chrome `150.0.7871.115`, Darwin `25.5.0` arm64 / Apple M2 host,
viewport, pass criteria, artifact paths, byte lengths, and PNG hashes back to
the tracked manifest. No material, texture, geometry, UV, visibility, or
asset-specific repair mutation exists in this capture path. The images and
full report remain ignored because A1B32 redistribution is not established;
the tracked hash metadata is Three.js reference direction only. Runtime
capability and release maturity remain `not established`; iOS Simulator,
physical iOS, Android, and Web target captures remain `not run`. The pinned
flutter_scene renderer still exposes no specular/IOR application contract, so
target capture cannot satisfy the A1B32 gate and Step 2 remains partial and
unchecked.

- [x] **Step 3: Validate rewritten GLBs**

Run glTF Validator on Meshopt, Draco, and BasisU rewrite output. Record zero
new errors attributable to rewrite; warnings require explicit disposition.

Safe-slice status: the independently approved Meshopt validator slice derives
an attached-scene GLB from the pinned official EXT-v0 stream, runs the actual
Dart rewriter, and validates the rewritten bytes with the official Khronos
`gltf-validator` npm package pinned exactly to prerelease
`2.0.0-dev.3.10` / commit
`bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1` / Apache-2.0. The exact npm lock
records registry integrity. Its normalized host report contains the validator
identity, rewritten-byte SHA-256, deterministic issue counts/messages, and no
timestamp or absolute path; the current Meshopt derivative returns zero errors,
warnings, infos, and hints. Runner contract tests require nonzero exit after
printing JSON for any error or undisposed warning, preserve pointer and/or byte
offset locations, reject malformed arguments, and require an exact complete
warning allow-list when warnings are intentionally disposed. Independent
review found three Important runner-contract issues and approved their RED-
first remediation; one Minor duplicated-fixture-literal concern remains
mitigated by the repository's separate pinned fixture hash verification. This
is host-only structural acceptance of the actual Meshopt rewrite output, not
decoder conformance, rendering, target runtime, device, packaging, release, or
production-readiness evidence. Draco and BasisU actual rewrite validation plus
durable normalized reports remain open, so Step 3 remains unchecked.

The independently approved Draco validator slice reuses one tracked native
runner for both package conformance and root rewrite validation. It compares
the official Box Draco 2.2 payload directly with pinned Google Draco 1.5.7 and
with `FsvDracoDecodePrimitives`, then feeds the byte-equal bridge outputs
(NORMAL 288 bytes, POSITION 288 bytes, indices 72 bytes) into the actual Dart
rewriter. The first official-validator run exposed twelve accessor min/max
errors because Draco quantization changed decoded extrema while the rewrite
retained authored bounds. A general RED-first remediation refreshes only bounds
keys already present from the validated decoded payload; absent keys stay
absent, integer indices keep raw component values, and NaN or positive/negative
infinity now returns a typed preflight diagnostic with no bytes or tracker
commit. The final official report has zero errors and warnings, one exact
`UNUSED_OBJECT` info at `/bufferViews/0`, and three exact
`BUFFER_VIEW_TARGET_MISSING` hints for NORMAL, POSITION, and indices. The
orphan compressed bufferView and hints are explicitly recorded rather than
silently compacted or changed. Independent review returned `APPROVE` with no
findings. This is host direct-codec/bridge plus structural rewrite evidence;
Android/iOS runtime, devices, rendering, packaging, release, and production
readiness remain `not run`. BasisU actual rewrite validation and durable
normalized reports remain open, so Step 3 remains unchecked.

The independently approved BasisU validator slice transcodes the unmodified
official 442-byte Khronos KTX-Software-CTS UASTC+Zstd RGBA/sRGB fixture through
the actual `FsvBasisuTranscodeImages` bridge with exact `color`/`rgba` intent
and bounded 256-pixel/1,108-byte envelopes. One tracked native output runner is
shared by the package and root tests. Its actual 16x16 RGBA PNG is 1,108 bytes
with SHA-256
`e4df96db13158a2722ad9aad3ec8dd84dcfb9bc248b0c6721261b4777e41366b`;
both consumers hash the emitted file and assert that exact identity. The root
test embeds the official KTX2 in an attached textured-triangle GLB, feeds the
actual bridge PNG to the actual Dart rewriter, and obtains an official report
with zero errors/warnings/hints plus one exact `UNUSED_OBJECT` info at
`/bufferViews/2`. The orphan KTX2 bufferView is explicitly recorded rather
than compacted. Independent review found one Important missing PNG byte-
identity gate; a mutation RED changed the final digest nibble and failed both
focused tests before the exact digest was restored. Final review returned
`APPROVE`; one Minor opaque native-runner exit-code diagnostic remains and
does not affect evidence correctness. This proves host bridge output and core
GLB structural validity only, not texture baking, renderer sampling, authored
mip preservation, Android/iOS runtime, devices, packaging, release, or
production readiness. All three actual rewrite outputs now pass the host
validator gate, but durable normalized report/provenance records remain open,
so Step 3 remains unchecked.

The independently approved durable-report closure slice stores normalized,
timestamp-free official-validator reports for all three actual rewrite chains
and compares them exactly in the default read-only test mode. Report refresh
requires the explicit exact environment value
`FSV_UPDATE_GLTF_REWRITE_REPORTS=1`; a subsequent default run must still pass.
The manifest pins validator prerelease/commit/license/npm integrity, fixture
and license hashes, rewritten-byte hashes, exact issue dispositions, and the
intentional Draco and BasisU orphan bufferViews. Meshopt reports zero issues;
Draco reports zero errors/warnings, one disposed orphan info, and three exact
missing-target hints; BasisU reports zero errors/warnings, one disposed orphan
info, and zero hints. Review found one Important provenance gap because the
vendored BasisU codec was locally patched relative to its declared upstream
commit. RED-first remediation now records that commit as an upstream base,
hashes the official and vendored source separately, carries the prominent
Apache-2.0 modification notice beside the exact dimension-guard hunk, and
verifies a deterministic 28-file compiled/include source manifest. Final
independent rereview returned `APPROVE` with no findings. This satisfies Step
3's structural-validation and warning-disposition gate only. Runtime
capability and release maturity remain `not established`; iOS Simulator,
physical iOS, Android, and Web target evidence remain `not run`; Task 11 and
M5 remain open.

- [x] **Step 4: Update the capability matrix per feature and target**

Separate parsed, preserved, decoded, applied, visually verified, release
maturity, and target evidence for iOS Simulator, physical iOS, Android, and
Web. Generate aggregate claims only from an explicit feature set and target
set; never copy a backend-wide boolean into every row.

Safe-slice status: an independently approved generated matrix now covers the
explicit nine-feature Plan 014 set across iOS Simulator, physical iOS, Android,
and Web. Host parser/preservation/decoder evidence is isolated from all 36
target rows; every current visual and target-evidence cell remains `not run`,
and no row or aggregate is production-ready. Runtime capability, release
maturity, application, visual verification, target evidence, and exact blocker
remain separate fields. Meshopt's zero-issue host validator result is retained
only as host decode/rewrite evidence and cannot promote a target row. Native-
only Draco and BasisU remain unsupported/diagnostic-only on Web; pinned
flutter_scene texture-transform, specular, and opaque-IOR blockers are exact.
The generator accepts only explicit feature/target selections and enforces
status vocabularies, cross-field production gates, current target-evidence
locks, native-only Web boundaries, and all twelve upstream blocker texts.
Public API, materials/lighting, runtime-pipeline, and quality documentation link
to the generated truth while labeling older simulator evidence as historical
candidate context. This closes Step 4 only; Task 11 and M5 remain open because
Steps 1 and 2 plus the A1B32/Glorvia renderer gates remain incomplete.

- [x] **Step 5: Run final verification**

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

Verification status: `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`,
and `git diff --check` all pass on 2026-07-14. The root suite result is 480
passes with the same 16 renderer/GPU/visual skips enumerated in Task 10 Step 5;
those cases remain `not run` and provide no target or production-readiness
evidence. This closes the command-and-skip-accounting gate only. Task 11 and M5
remain open because Steps 1 and 2, the A1B32/Glorvia renderer gates, and target
evidence remain incomplete.

## Acceptance criteria

- [x] Current docs and runtime support objects separate per-feature runtime
      capability, release maturity, and per-target evidence. A feature can be
      both `candidate-only` and `verified locally` without contradiction.
- [x] Core imported textures apply even when selected material extensions are
      unsupported.
- [x] Unsupported authored specular, clearcoat, opaque IOR, or
      transmission/volume intent does not discard a different supported
      authored extension group on the same material.
- [x] IOR-only opaque materials stay in the standard PBR family.
- [x] No asset-name, texture-name, PNG-alpha, forced material-value, visibility,
      or generated-tiling repair remains in the production path.
- [x] Public runtime bindings use an explicit `MaterialTextureSlot`, are
      defensively immutable, and preserve source, UV set, sampler, offset,
      scale, rotation, and extension UV override per texture slot.
- [x] `KHR_texture_transform` uses normative math/defaults and sampler state is
      preserved or diagnosed without byte baking. Finite negative scale is
      accepted; malformed optional transform data uses core fallback, while
      malformed required data blocks import.
- [x] `KHR_materials_specular` changes dielectric response with correct channel
      and color-space handling.
- [x] Opaque `KHR_materials_ior` changes dielectric F0 without classifying the
      material as glass.
- [x] Clearcoat runtime support, when claimed, is a second authored lobe with
      independent normal and base attenuation. Otherwise it remains explicitly
      `candidate-only`/diagnostic, has a linked deferred plan, and keeps the v1
      release gate blocked.
- [x] Transmission runtime support, when claimed, is not alpha blending;
      volume thickness uses green and attenuation/IOR behavior passes normative
      tests. Otherwise it remains explicitly deferred and keeps the v1 release
      gate blocked.
- [x] BasisU/KTX2 layout, color-role, mip, budget, and platform boundaries are
      explicit for the bounded single-level compatibility path. Authored mip
      preservation, codec-internal control, physical targets, and packaging
      remain open under Plan 017 and are not claimed by this checkbox.
- [x] Meshopt and Draco rewrites pass the bounded conformance, wrapper-budget,
      addressing, and validator gates. Externally observable cancellation,
      codec working-allocation enforcement, physical targets, and packaging
      remain open under Plan 017 and are not claimed by this checkbox.
- [x] A1B32 loads, renders, picks, preserves hierarchy, applies specular and
      opaque IOR, and does not receive material hacks.
- [x] Glorvia applies base-color repeat 2.5 and normal repeat 1.0 through
      slot-aware bindings without changing or generating encoded image bytes.
- [x] Lighting/reference state is fixed before material visual comparison.
- [x] Durable evidence exists outside temporary directories with asset,
      renderer, platform, camera, lighting, and pass metadata.
- [x] Capability claims are target-specific; `not run` targets remain
      `not run`.
- [x] Plan closure follows the explicit gate table: blocked A1B32 or Glorvia
      renderer work prevents completion, and deferred clearcoat/glass work
      prevents a v1 `production-ready` release claim.
- [x] `bash tools/run_checks.sh` passes.
- [x] `python3 tools/repo_lint.py` passes.
- [x] `git diff --check` passes.

## Progress log

- 2026-07-15: At the user's explicit direction, closed Plan 014 at its verified
  bounded scope and recorded the remaining work rather than treating missing
  physical evidence as an implementation failure. M1-M3 are complete with
  focused/full test and durable iOS Simulator evidence. M4 is dispositioned to
  deferred Plans 015 and 016; M5's codec-internal cancellation/resource
  control, authored KTX2 mip chains, physical iOS, Android, Web, packaging,
  and release evidence are dispositioned to deferred Plan 017. Physical iOS,
  Android, and Web remain `not run`; packaging and production readiness remain
  `release pending` or unclaimed. The unchecked Task 8-11 steps remain visible
  as historical open work. No physical-target or aggregate
  `production-ready` claim is made by moving this plan to `completed`.

- 2026-07-14: Commit/push handoff authorized by the user for the current Plan
  014 follow-up diff on `main`. The intended scope is the eight tracked files
  covering face-oriented extended-PBR normals, clean acceptance-state
  isolation, load-gated initial material overrides, their regression tests,
  public documentation, and this plan log. The pre-existing untracked
  `tools/__pycache__/` directory remains excluded. Fresh verification before
  staging is `bash tools/run_checks.sh` at `+505 ~16`, clean
  `python3 tools/repo_lint.py`, clean `git diff --check`, successful iPhone 17
  Simulator build/run, and cold-launch visual evidence `verified locally`.
- 2026-07-14: Completed the RED-first first-visible-frame follow-up without
  changing A1B32, its textures, or shader semantics. `FlutterSceneViewer` now
  accepts an `initialMaterialOverrides` snapshot and keeps controller status at
  `loading` while every patch and texture finishes. The ready render surface is
  exposed only after the complete snapshot succeeds; ordinary controller
  material calls remain incremental after load. The disposable A1B32 harness
  now supplies its four Glorvia patches through this load-time path instead of
  post-frame mutation. A fresh iPhone 17 Simulator cold launch showed loading
  frames at `1/4`, `2/4`, and `3/4` with no model visible, followed by the first
  model frame at `SUCCESS · 20 parts · 4/4 applied`; automatic orbit was left
  running for user inspection. This target result is `verified locally`; the
  extended material remains `candidate-only`, and physical iOS, Android, Web,
  release, and `production-ready` evidence remain `not run`.
- 2026-07-14: Cold-relaunch video isolated the remaining first-load flash to
  non-atomic runtime override restoration. The disposable harness exposes the
  ready render surface before its four caller-supplied Glorvia patches finish,
  then awaits `setPartMaterial` once per primitive. Captured frames show the
  exact mixed states: at `1/4 applied` the upper primitive uses C28 while the
  skirt still shows the authored white/black state; at `3/4 applied` one final
  garment primitive remains authored; `4/4 applied` is clean. This is not
  shader warm-up, a GLB defect, or evidence for clamping glTF optical values.
  The RED-first follow-up will allow a persisted initial override snapshot to
  finish while load status remains `loading`, expose the ready surface only
  afterward, and keep ordinary post-load edits incremental.
- 2026-07-14: At the user's request, relaunched and foregrounded the corrected
  disposable A1B32 acceptance harness on the already-booted iPhone 17
  Simulator. The live UI again reached `SUCCESS · 20 parts · 4/4 applied` and
  reported `Glorvia UV 2.5/1.0 + consistent optical state`. A fresh visual
  capture showed the clean garment state, and automatic orbit was left running
  for continued manual inspection.
- 2026-07-14: Controlled Simulator isolation identified the remaining visual
  defect as acceptance-state contamination, not a GLB requirement. Without
  changing A1B32, C28 textures, the normal map, shader, camera, lighting, or
  orbit, the disposable harness changed only the four simultaneous optical
  overrides from divergent comparison extremes to one Glorvia-like state:
  `specularFactor=1`, `specularColorFactor=[1,1,1]`, and `IOR=1.45` on every
  garment primitive. Six fresh front/side/back orbit captures no longer showed
  the moving white waist/skirt regions. `IOR=0` is intentionally full Fresnel
  and the other extreme values are valid conformance inputs, so production
  shader semantics must not clamp them. They belong in isolated one-variable
  evidence captures, never as the persistent interactive garment state. The
  material-acceptance contract now requires non-target primitives to retain
  baseline and requires baseline restoration before interactive review. The
  foreground Simulator is now running the consistent state for user review.
- 2026-07-14: User review of the foreground Simulator run rejected the prior
  white-patch closure. Six fresh live auto-orbit captures reproduced
  angle-dependent white regions across the front waist/skirt while the
  acceptance harness applied divergent extreme optical values to the four
  garment primitives (`IOR 1.1`, `1.5`, `2`, and `0`). The face-oriented
  normal change remains a normative glTF correction, but it is insufficient
  evidence for this visual defect and is no longer considered the complete
  fix. The earlier “without reproducing” statement below is superseded by this
  entry. No second production change is accepted until a same-camera
  controlled comparison separates consistent Glorvia-like optical state from
  normal-map/specular aliasing and primitive/depth interaction.
- 2026-07-14: At the user's request, rebuilt and launched the corrected
  disposable A1B32 acceptance harness on the already-booted iPhone 17
  Simulator through the Runner workspace. The build completed without errors,
  the runtime UI reached `SUCCESS · 20 parts · 4/4 applied`, and automatic
  orbit is active for manual inspection. Simulator.app was brought to the
  foreground and the application was intentionally left running.
- 2026-07-14: Completed the camera-dependent A1B32 white-patch follow-up with
  a generic, specification-owned fix in `FSViewerExtendedPbr`. Back-facing
  fragments now reverse the geometric normal before normal-map tangent-frame,
  Fresnel/IBL energy, direct-light, and shadow evaluation. The same unchanged
  A1B32 GLB and the original extreme four-primitive specular/IOR comparison
  matrix ran on iPhone 17 Simulator with Impeller/Metal; automatic orbit
  captures covered front, side, and back views without reproducing the white
  flash regions. The implementation adds no asset/material-name branch,
  parameter clamp, public API, GLB mutation, or depth offset. The repo-local
  `pbr-materials` source hierarchy kept Khronos semantics normative; live
  Glorvia/Babylon and pinned Three.js behavior were used only as renderer
  evidence. The extended path remains `candidate-only`; physical iOS,
  Android, Web, release, and `production-ready` evidence remain `not run`.
- 2026-07-14: Began a RED-first follow-up for camera-dependent white patches
  reported on A1B32 while the accepted extended-PBR comparison state was
  active. The unchanged GLB remains authoritative and will not be repaired or
  mutated. Live Glorvia inspection confirmed that the product page uses
  Babylon Viewer 5.16, not Three.js, and renders all four garment materials
  with two-sided lighting, IOR approximately `1.45`, roughness approximately
  `0.83`, and no depth offset. The pinned Three.js r167 reference flips the
  normal and derivative tangent frame on back-facing fragments; the current
  `FSViewerExtendedPbr` fragment preserves disabled culling but does not flip
  its geometric or perturbed normals. The working assumption for the smallest
  renderer-owned fix is therefore glTF `doubleSided` back-face lighting
  semantics, applied generically through `gl_FrontFacing` with no asset-name
  branch, IOR clamp, or GLB change. This assumption must first fail a focused
  shader-contract test and then pass compiler plus real Simulator evidence.
- 2026-07-14: At the user's explicit request, staged only the Plan 014
  extended-PBR handoff files and created a local conventional commit with
  message `feat(materials): add extended PBR material path`. The pre-existing
  untracked `tools/__pycache__/` directory was excluded. The staged diff check
  passed; no push was performed.
- 2026-07-14: Completed the authoritative extended-PBR Task 6/7 handoff and
  accepted the independently testable M2 texture-binding and M3 A1B32 material
  gates. The legacy Task 6 test path now protects the sole combined build
  route rather than restoring the removed UV-only material. Its final focused
  command passed 150 tests with 13 existing, explicitly labelled
  Impeller/Flutter-GPU skips; the Task 7 command passed 122 tests with no
  skips. The full repository harness passed repo lint, formatting of 88 files
  with zero changes, dependency resolution, analysis with no issues, and 503
  tests with 16 explicitly labelled GPU skips. A new Three.js r167 directional
  reference uses the unchanged A1B32, C28 front/back, and crepe-normal hashes
  with the same six UV/specular/IOR values as the iOS Simulator run; all six
  captures were visually inspected and retain distinct hashes. Its durable
  record is under
  `tools/out/material_extension_acceptance/plan014_extended_pbr_threejs_reference/`
  and is cross-linked from the iOS evidence. Post-run process inspection found
  no Chrome, automation, or temporary HTTP-server process. This closes only
  the approved Task 6/7 slice: the extended path remains `candidate-only`, iOS
  Simulator remains `verified locally`, and physical iOS, Android, Web,
  release packaging, and `production-ready` evidence remain `not run`. Other
  active Plan 014 tasks remain open. No commit or push was performed.
- 2026-07-14: Accepted the real Task 6 Glorvia and Task 7 A1B32 intermediate
  gates for the bounded extended-PBR path. A disposable app ran on the already
  booted iPhone 17 Simulator (`iOS 26.5`) with Impeller/Metal, Flutter GPU, and
  the native Draco plugin enabled. The unchanged
  `a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592`
  A1B32 GLB loaded as 20 renderable primitives. Four combined patches applied
  and persisted with zero new extended-PBR diagnostics: albedo repeat
  `2.5 × 2.5`, normal repeat `1 × 1`, specular variants, tinted IOR 2, and
  exact IOR zero. Picking returned `root/A1B32#0` and `root/A1B32#2`; authored
  metallic/material intent remained unchanged and no clearcoat, roughness,
  alpha, visibility, geometry, UV, or encoded-byte repair was forced. Fixed
  captures produced 37,067 changed pixels for UV identity versus 2.5, 34,453
  for specular 0.1 versus 1.0, and 37,579 for tinted IOR 2 versus full-Fresnel
  IOR zero in the isolated model region. The existing Three.js Glorvia
  reference independently retains the same caller-supplied albedo 2.5/normal
  1.0 contract. Evidence, capture hashes, input hashes, packaged bundle hash,
  run log, and reproduction snapshots are under
  `tools/out/material_extension_acceptance/plan014_extended_pbr_ios_simulator/`.
  This accepts only iOS Simulator `verified locally` / `candidate-only`
  evidence. Physical iOS, Android, Web, release packaging, and production
  readiness remain `not run`.
- 2026-07-14: Consolidated the implementation on the single combined route.
  Removed the obsolete UV-only `.fmat`, bridge helper, and build-hook entry;
  migrated the legacy Task 6 test path to guard the combined route after moving
  transform, transformed-normal, asset-agnostic, packaging, and state-copy
  assertions to the extended material suite. Added the complete
  pinned `flutter_scene` MIT notice and source attribution; the attribution-only
  shader header change rebuilt to the identical
  `641585ac20b5ac1563bc91f349bcaf64e7c039754a13d886191809067bf2604b`
  bundle. The capability matrix now accepts exactly the evidence-backed iOS
  Simulator rows for texture transform, specular, opaque IOR, and Draco while
  preserving physical iOS, Android, and Web as `not run`. Reader-facing docs
  describe the automatic material-scoped route and retain `candidate-only`
  boundaries. At this checkpoint Task 6 Step 6 and Task 7 Step 6 remained open
  until the final repository harness pass recorded above.
- 2026-07-14: Implemented the bounded CPU/compiler and atomic-routing slice of
  the authoritative extended-PBR architecture without accepting Task 6, Task
  7, M2, or M3. Added the raw `FSViewerExtendedPbr` bundle manifest/fragment,
  hook packaging, deterministic 48-float transform/specular/IOR block, complete
  reflected sampler contract, package-local material/backend, and automatic
  adapter routing. The routed fragment now owns the five core texture reads,
  transformed normal derivatives, specular factor/color sampling, opaque IOR,
  direct light, IBL resources, shadows, SSAO, fog, and HDR premultiplied output
  while retaining the pinned renderer's surrounding pipeline. A new retained
  state interface keeps transformed UV, specular, and IOR state across later
  core-only deltas; backend results lacking that contract fail before live
  replacement. Core identity texture patches stay native, combined
  UV/specular/IOR produces one replacement, failed construction leaves live
  material/geometry/visibility unchanged, and reset restores the exact captured
  source. The GPU shader-reflection test and visual trend assertion remain
  explicitly gated because the plain Flutter test process has no Impeller.
  Glorvia transformed rendering and A1B32 specular/IOR application are still
  `not run`, so no physical-target or production-ready claim changes.
- 2026-07-14: Established the fresh Task 6/7 RED required by the authoritative
  handoff before extended-PBR production code. Added one focused shader-seam
  assertion to `test/flutter_scene_uv_transform_material_test.dart` and one
  real controller/adapter atomicity assertion to
  `test/viewer_controller_material_test.dart`. The former confirms the pinned
  lit `.fmat` output contains exactly one fixed
  `EvaluateLighting(material)` and no specular-factor, specular-color, or IOR
  inputs, then requires the absent raw `FSViewerExtendedPbr` manifest/fragment
  contract. The latter passed while proving unavailable transformed-UV intent
  leaves the live primitive material, override persistence, factors, and
  render-request count unchanged. Task 6 Step 4 and Task 7 remain open; shader
  compilation, GPU rendering, Glorvia application, and A1B32 specular/IOR are
  still `not run`.
- 2026-07-14: Applied the authoritative extended-PBR handoff amendment before
  production code. The current contract now supersedes the older narrow
  UV-only/fixed-`EvaluateLighting` Task 6 design and the upstream-only Task 7
  blocker language retained later in this log as historical evidence.
  Core-only identity PBR remains native; supported nonidentity UV0,
  specular, and opaque-IOR intent automatically routes through one bounded,
  material-scoped `FSViewerExtendedPbr`. The full fragment owns routed core
  sampling, selected extension equations, direct studio light, IBL resource
  consumption, generated-shadow sampling, fog, and HDR premultiplied output,
  while the pinned renderer retains geometry/vertex/rasterization, picking,
  camera, shadow and environment resource generation, DFG LUT, tone mapping,
  final resolve, and scheduling ownership. Task 6 still requires real Glorvia
  transformed-UV application; Task 7 still requires real A1B32
  specular/opaque-IOR application. Both remain open, the extended capability
  is `candidate-only`, and physical iOS, Android, and Web remain `not run`.
  This amendment changed only
  `docs/exec-plans/active/014_selected_gltf_extension_support.md`; no
  production step, milestone, target gate, release, or `production-ready`
  claim is accepted.
- 2026-07-14: The user rejected a `flutter_scene` fork and approved a narrow,
  fork-free Task 6 design amendment; no implementation step is accepted yet.
  The canonical plan now assigns the caller/configurator ownership of runtime
  texture URLs and transforms, records that A1B32 does not contain C28 or its
  `2.5` scale, and corrects the official Glorvia contract to albedo
  `2.5 × 2.5` plus crepe normal `1.0 × 1.0`. The selected internal material
  bridge activates only for non-identity UV0 bindings on the five standard
  core PBR slots, subclasses the pinned `PhysicallyBasedMaterial`, preserves
  native material/render-prepass state, and delegates lighting to the pinned
  engine-generated `EvaluateLighting` path. Its package-local shader may own
  only per-slot UV calculation and the five standard texture reads; authored
  BRDF/IBL/light/shadow/fog logic, asset-specific branches, byte baking, UV
  generation, geometry mutation, and silent identity fallback remain
  prohibited. Unsupported states must fail atomically with typed diagnostics.
  Successful evidence will be `flutterSceneCustomShader`/`candidate-only`,
  not renderer-native or production-ready. This turn changed documentation
  only; RED tests and production code are intentionally pending written-design
  review.
- 2026-07-14: Added bounded Glorvia C28 diagnosis without accepting Task 6
  Step 5, Task 6, or M2. The user-supplied official product page exposes the
  exact A1B32 runtime call: front albedo `C28.jpg`, reverse-side albedo
  `C28-back.jpg`, crepe normal `crepe-normal.jpg`, albedo repeat
  `2.50 × 2.50`, and normal repeat `1.00 × 1.00`. The three CDN responses were
  staged under ignored `tools/out/` evidence with HTTP 200 `image/jpeg`
  metadata and SHA-256 identities
  `d01c111ea23e8fbbefbba8058cb2841f6b48ab6d58224d0e270c659e31dbe1eb`,
  `7e7a245d16ceec39d2b2f87be9913d7b7a24cb50cf107ef0672fd5a54fcaa308`,
  and `9cd6e7f5d968fb424070b8605f852b8ab95bfea40dcd887aae5b2f378f1060c5`.
  A disposable iPhone 17 Simulator harness addressed A1B32 primitives 0-3
  through the public slot-aware API. All four exact albedo-repeat requests
  were rejected before mutation with typed
  `perSlotUvTransformContractMissing` diagnostics, proving the pinned
  `flutter_scene` blocker on the real target path. The harness then applied a
  clearly labelled identity-transform fallback using the unchanged real
  front/reverse albedos and 1× normal solely to show texture identity. It
  generated no image bytes or UVs and changed no geometry or visibility. The
  centered front capture is
  `tools/out/material_extension_acceptance/glorvia_c28/ios_c28_front.png`
  (`215c2fdac78a18ae9932afae1ce3f1a334c1938790cdd8322943302f044b3ab2`).
  A separate Three.js r167 directional reference applied the live-page
  albedo 2.5/normal 1.0 contract to the same four named materials and produced
  four fixed-state views without geometry, UV, visibility, or byte changes.
  Its front artifact is
  `tools/out/material_extension_acceptance/a1b32_threejs_glorvia_c28/front.png`
  (`93404852a9872ed0cf00cfe15e871d50012757459218cb7b2aca36d6d776f9ec`).
  The comparison removes the raw GLB's black garment speckling and isolates
  the remaining iOS-versus-reference print-size difference to the unavailable
  per-slot transform. This is iOS Simulator and Three.js reference evidence
  only, not transformed-UV renderer acceptance, physical-iOS, Android, Web,
  release, or production evidence. This run exposed the then-current
  both-slots-at-2.5 plan mismatch; the user-approved design amendment above
  corrects the gate to the live albedo-2.5/normal-1.0 contract, while the step
  remains blocked pending actual bridge rendering.
- 2026-07-14: Ran the user-authorized A1B32 bytes on the open iPhone 17
  Simulator with the local native Draco plugin and the pinned renderer. The
  unmodified authored asset
  (`a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592`)
  reached `SUCCESS` with 20 renderable parts, but the centered front capture
  failed visual acceptance: the garment contains severe black speckling. A
  fresh fixed-state Three.js r167 capture of the same source SHA reproduced
  the authoring defect. The front `beyaz_*` base-color images are solid white,
  while the double-sided back materials incorrectly bind solid-black `R_0_*`
  data/mask images as base color; internal `MAT_Body` / `MAT_Legs` geometry can
  also intersect the opaque garment. The embedded `C` image is a Glorvia logo,
  not a garment albedo, and no C28 fabric texture is embedded. Therefore this
  run verifies native Draco decoding and byte preservation only; it does not
  verify acceptable core-texture rendering. Specular and opaque IOR remain
  diagnostic-only because the pinned renderer exposes no application
  contract. The run exposed two false `adapterFailure` diagnostics after
  native decode: both GLB readers applied their 8 MiB JSON limit to the larger
  decoded BIN chunk. Two RED regressions reproduced the failure before the
  minimal JSON-chunk-type guard made them GREEN. The rerun retained only the
  typed `unsupportedModelFeature` and `unsupportedMaterialFeature` code
  families and removed both metadata-reader failures. An on-demand frame was
  lost after an iOS status-bar repaint; the disposable evidence harness now
  uses the public `RenderPolicy.always` policy, but both that policy and an
  immersive system-UI retry still lost the surface on a later repaint. The
  pinned Flutter GPU / flutter_scene compositing boundary therefore remains a
  target blocker. Runtime logs contain 44 non-blocking typed diagnostics: four
  `unsupportedModelFeature` records for the two back-side data-map bindings
  and the two internal-mannequin intersection risks, plus 40
  `unsupportedMaterialFeature` records because all 20 primitives author both
  unsupported specular and opaque-IOR intent. No Task 7, M3, A1B32,
  target-release, or production-readiness gate is accepted.
- 2026-07-14: Closed Task 10 Step 5 and Task 11 Step 5 without accepting
  either task or M5. The exact Task 10 root command passed 89 tests with three
  explicit GPU/Impeller skips; the Draco package passed 7/7 and BasisU passed
  12/12. The full repository gate passed lint, format, dependency resolution,
  analysis, and 480 root tests with 16 explicit renderer/GPU/visual skips;
  standalone repo lint and diff whitespace checks also passed. A final
  cancellation audit found no model-load cancellation signal in the
  controller/loader, no way for synchronous same-isolate Meshopt work to
  observe event-loop-driven replacement, and no native request IDs, cancel
  endpoints, cooperative codec polls, or bounded allocators. No fake callback
  was added. The user separately authorized A1B32 for current repository-local
  work; redistribution identity and target renderer evidence remain
  unestablished. Task 10 Steps 1/3, Task 11 Steps 1/2, both tasks, M5, A1B32,
  and Glorvia remain open, blocked, or `not run` exactly as scoped above.
- 2026-07-14: Completed and independently approved a Task 10 Steps 1/3
  Meshopt cooperative-timeout partial slice without accepting either step,
  Task 10, or M5. The initial RED failed compilation on the absent control API;
  five mode/filter mutation REDs then failed at `meshoptDecodeComplete`, a zero-
  deadline RED proved allocation started before the required start checkpoint,
  and a success-accounting RED observed `3` instead of the expected `7` bytes
  without atomic commit. The GREEN adds one Stopwatch-backed deadline across
  every bufferView, approximate decoded-byte checkpoints across all claimed
  modes/filters, typed timeout diagnostics, and a shadow tracker that commits
  once only after complete output construction. Capability generation now
  fingerprints the exact deadline implementation while retaining external
  cancellation as `not enforced`, deterministic Dart collection as `not
  guaranteed`, and every target/release row unchanged. Review found one
  Important test gap in the `decoderWork: started` mapping. A mutation-sensitive
  RED failed that branch before a one-view mid-decode timeout test locked typed
  diagnostics, sub-millisecond reporting, null output, tracker rollback, and
  source-intent preservation. Final rereview returned `APPROVE`. External
  cancellation, deterministic resource release, and codec-internal allocator
  control remain open, so Steps 1/3, Task 10, and M5 remain unchecked.
- 2026-07-14: Completed and independently approved a Task 10 Steps 1/3 native-
  timeout partial slice without accepting either step, Task 10, or M5. Two
  delayed-channel REDs showed Draco timing out as generic unsupported behavior
  and BasisU accepting a late decoded GLB. The first GREEN added one shared
  monotonic deadline, typed `modelLoadTimeout`, late-result discard, unchanged
  tracker state, and later-stage suppression. Review found an Important
  evaluation-order bug: a zero deadline dispatched MethodChannel work before
  calculating the remaining duration. An exact RED observed one call instead
  of zero; the deadline is now checked before dispatch. A sequential test locks
  aggregate Draco-to-BasisU timing and late-result atomicity. Review then found
  pre-dispatch expiry incorrectly claimed a discarded late result and
  unguaranteed native release. An exact diagnostic RED separated
  `notStarted`/`notApplicable` from in-flight
  `started`/`notGuaranteed`/`discardedByDart`. Final rereview returned
  `APPROVE`; cooperative cancellation, native release, Meshopt deadline checks,
  and codec-internal allocation limits remain blocked.
- 2026-07-14: Completed and independently approved a Task 10 Steps 1/3
  blocker-evidence slice without accepting either step, Task 10, or M5. The
  focused RED failed because no structured decoder-control records existed.
  The first GREEN documented Meshopt, Draco, and BasisU allocation, timeout,
  cancellation, resource-release, API, and bridge boundaries without changing
  any target row. Review found an Important staleness gap because literal
  markers could miss alternative control names. A second RED failed on the
  absent injectable source validator; full-file SHA-256 fingerprints then
  rejected `deadline`, `timeoutMs`, `shouldCancel`, and `cancelToken` mutations.
  Rereview found the actual Android Java/JNI and iOS plugin adapters were not
  fingerprinted. A third RED failed those platform mutations before all six
  adapter files were added. Final rereview returned `APPROVE`. The exact
  upstream/in-process blocker remains: no cooperative codec cancellation,
  bounded allocator, or timeout-triggered native resource-release contract.
- 2026-07-14: Completed and independently approved Task 10 Step 4 without
  accepting Task 10 or M5. The focused RED retained five baseline passes but
  failed two groups because the capability source lacked historical candidate
  context and accepted unsupported native-codec target promotion. The GREEN
  records the completed Plan 013 Draco and BasisU iPhone 17 Simulator runs as
  historical `verified locally` evidence with `not durable` artifacts, current
  Plan 014 target evidence `not run`, and release maturity `candidate-only`.
  It also locks every current Draco/BasisU native target row to `not run` for
  application, visual, and target evidence, `candidate-only native plugin` for
  runtime capability, and `candidate-only` for release maturity; Web remains
  `unsupported`/`diagnostic-only`/`not run`. Aggregates consume current rows
  only. Independent review rejected 34 history/current-row mutations and
  returned `APPROVE` with no Critical or Important findings. Step 4 is closed;
  Task 10 Steps 1 and 3, Task 10, and M5 remain open.
- 2026-07-14: Completed and independently approved Task 10 Step 2 without
  accepting Task 10 or M5. The UASTC-RG closure RED failed three of the focused
  native tests because the new source, deterministic derived fixture, and
  runner cases were absent. The fetch harness pins the official 304-byte CTS
  R8G8 UASTC source at SHA-256
  `318f68b48970fcdf76fbc407bfdc83a8afef6f611382f1283ff8106345b4a5d9`;
  a checked tool changes only zero-based DFD offsets 117 and 135 and produces
  SHA-256
  `602fcde544d7bb6c9272bea35f420c9fc9e76e2f7b182d7849dfa5d5bdde8bbd`.
  The first GREEN passed the 11-test native suite and matched the actual bridge
  to the independently invoked pinned transcoder. Review found one Important
  selected-layout gap for UASTC numeric channel 0. An intentional `kRgb` to
  `kRg` Android/iOS mutation then failed the exact official UASTC RGB selected-
  `rgb` case before restoration; selected `rgb`/`rg`, generic DATA(0), and
  derived channel-6 RG behavior are now mutation-protected. Final BasisU
  package verification passed 12/12 and rereview returned `APPROVE`. All
  explicit Meshopt, Draco, and BasisU Step 2 conformance bullets are now
  satisfied, while target/runtime/release evidence remains `not run` and Task
  10/M5 remain open.
- 2026-07-14: Completed and independently approved Task 11 Step 4 without
  accepting Task 11 or M5. A RED-first focused test failed because no
  structured nine-feature/four-target source or deterministic generator
  existed. The first GREEN produced 36 explicit target rows and updated the
  public API, material/lighting, runtime-pipeline, and quality docs while
  retaining every current target/visual claim as `not run`. Independent review
  found two Important mutation-safety gaps: runtime capability could become
  production-ready without the row gates, and native-only Web or host-only
  facts could be promoted by editing the source. The meaningful remediation
  RED passed only the baseline and failed all four mutation-test groups. The
  final 5/5 GREEN constrains applied/runtime vocabularies, requires all five
  production gates together, locks current target application/evidence,
  preserves native-only Web rows and twelve exact upstream blockers, and keeps
  Meshopt host-validator success out of target claims. Rereview exercised 17
  unsafe mutations and returned `APPROVE` with no Critical or Important
  findings. Step 4 is closed; Task 11/M5 and every current target capture remain
  open or `not run`.
- 2026-07-14: Completed and independently approved the first Task 11 Step 2
  safe slice without accepting Step 2, Task 11, or M5. RED-first Node tests
  established a fixed A1B32 reference contract, exact source-byte rejection,
  complete four-view hashing, and tracked-record projection. A separate
  Flutter RED failed 1/2 until the manifest durably separated reference
  renderer direction from every `not run` Flutter target. The final harness
  rendered the unmodified authored scene through a separate headless Chrome
  profile and reproduced all four manifest-bound hashes across repeated runs.
  The initial Three.js tag commit assumption was corrected by RED to the npm
  package's actual `gitHead`; a second RED replaced a generic host label with
  the exact Apple M2 identity. Independent review returned `APPROVE` with no
  Critical or Important findings. Its one Minor missing same-length SHA-drift
  assertion was added and the Node suite stayed green. No automation Chrome
  process remained. The artifacts cannot be vendored while redistribution is
  unestablished, and target renderer evidence remains blocked/not run by the
  pinned flutter_scene specular/IOR capability gap, so Step 2 remains open.
- 2026-07-14: Completed and independently approved the first Task 11 Step 1
  safe slice without accepting Step 1, Task 11, or M5. A RED-first fixture
  provenance test initially failed 0/1 because immutable source, license, and
  authorization records plus a staging tool were absent. Five official
  Khronos material-extension GLBs now have commit-pinned URLs, exact asset and
  license hashes, and reproducible ignored staging. The user-supplied A1B32 is
  hash/structure checked and may be staged only for current Plan 014 local use.
  Review found two Important evidence-boundary issues: the first wording
  overclaimed redistribution permission and summarized source validation only
  by counts; a remediation RED failed 0/1 before the manifest constrained the
  permission and recorded all six warning codes/pointers/dispositions. Rereview
  found one remaining Important omission of the validator messages; a second
  RED failed 0/1 before all six exact severity/code/message/pointer identities
  were pinned and enforced. Final rereview returned `APPROVE` with no Critical
  or Important findings. A1B32 redistribution/SPDX/copyright/public-source
  provenance remains unestablished, so Step 1 stays open; all renderer,
  runtime, target, release, and production-readiness claims also remain
  unestablished or `not run`.
- 2026-07-14: Completed and independently approved the fourth Task 11 Step 3
  safe slice, closing Step 3 without accepting Task 11 or M5. The initial RED
  failed 0/4 because the three durable reports and manifest provenance were
  absent. Explicit refresh and default read-only runs then passed 4/4 across
  the actual Meshopt, Draco, and BasisU rewrite chains. Normalized reports pin
  rewritten SHA-256 values and exact issue dispositions without timestamps or
  absolute paths; the manifest keeps host structural evidence separate from
  runtime capability, release maturity, and target evidence. Independent
  review found one Important BasisU provenance issue: the compiled vendored
  source contained a local dimension guard absent from the declared upstream
  commit. A provenance RED failed 3/4; remediation distinguishes the upstream
  base and official source hash from the vendored source, adds the Apache-2.0
  modification notice, documents the exact hunk, and verifies a deterministic
  28-file source manifest. A final cleanup RED again failed 3/4 while restoring
  an unnecessary terminal-whitespace delta, leaving only the noticed guard
  hunk relative to upstream. Final rereview returned `APPROVE` with no
  findings. This is host-only structural evidence. Runtime/rendering/device/
  packaging/release claims remain unestablished or `not run`; Task 11 and M5
  remain open.
- 2026-07-13: Completed and independently approved the third Task 11 Step 3
  safe slice for official validation of the actual BasisU bridge and Dart
  rewrite output without accepting Step 3, Task 11, or M5. The focused RED
  failed 0/1 because the tracked output runner did not exist. The implementation
  reuses one tracked runner in the package and root tests, transcodes the
  pinned official CTS UASTC+Zstd RGBA/sRGB fixture with exact color/RGBA intent,
  and feeds the actual 1,108-byte PNG into the actual rewriter. The official
  validator returns zero errors/warnings/hints and one exact orphan-bufferView
  info. Independent review reproduced the correct PNG but found one Important
  missing byte-identity gate; an intentionally wrong final SHA nibble then
  failed both focused tests 0/1 before exact emitted-file hash assertions made
  them green. Final review returned `APPROVE` with only a Minor native-runner
  error-message concern. All three actual rewritten codec outputs are now
  validator-green on this host. Durable normalized reports/provenance and all
  renderer/runtime/device/packaging/release evidence remain open or `not run`,
  so Step 3, Task 11, and M5 remain open.
- 2026-07-13: Completed and independently approved the second Task 11 Step 3
  safe slice for official validation of the actual Draco bridge and Dart
  rewrite output without accepting Step 3, Task 11, or M5. The initial root
  RED failed 0/1 because no tracked reusable bridge runner existed. After
  extracting the existing conformance runner, its actual 648-byte bridge
  output matched a direct pinned Draco 1.5.7 decode, but the official validator
  exposed twelve stale accessor min/max errors. The general remediation
  refreshes only authored bounds keys from checked decoded payloads. A focused
  follow-up RED also exposed a late generic `jsonEncode` diagnostic for NaN;
  NaN and positive/negative infinity now fail typed Draco preflight with no
  output or tracker commit. The final report records zero errors/warnings, one
  exact orphan-bufferView info, and three exact missing-target hints. Final
  independent review returned `APPROVE` with no findings. BasisU actual rewrite
  validation and durable normalized reports remain open, and no Android/iOS
  runtime, device, rendering, packaging, release, or production-readiness
  evidence was added; Step 3, Task 11, and M5 remain open.
- 2026-07-13: Completed and independently approved the first Task 11 Step 3
  safe slice for official validation of the actual Meshopt rewrite output
  without accepting Step 3, Task 11, or M5. The RED first ran the actual Dart
  rewriter over a pinned official EXT-v0 stream derivative and failed 0/1 at
  the deliberately absent Node runner. The implementation pins the official
  Khronos validator prerelease exactly, records npm integrity, normalizes
  deterministic reports, and produced a Meshopt report with zero errors,
  warnings, infos, and hints. Independent review found three Important harness
  issues: error reports exited zero, offset-only issues lost their location or
  crashed sorting, and malformed CLI values were accepted. Three Node REDs
  failed as expected; remediation made error/undisposed-warning exit status
  nonzero after JSON output, retained pointer/offset locations, added exact
  warning disposition, and made argument parsing strict. Final review returned
  `APPROVE` with only a Minor duplicated fixture-literal concern mitigated by
  separate pinned hash verification. Durable normalized reports and actual
  Draco/BasisU rewrite validation remain open, as do all renderer/runtime/
  device/packaging/release claims, Task 11, and M5.
- 2026-07-13: Completed and independently approved the thirteenth Task 10 safe
  slice for BasisU channel-aware material-role and DFD-layout matching without
  accepting Task 10 or M5. The packed-specular Dart RED proved the prior binary
  color/non-color model rejected a Khronos-valid image carrying sRGB
  specular-color RGB plus linear specular-factor alpha; the native runner RED
  then failed compilation because channel-layout metadata did not exist. Dart
  now derives exact selected-channel masks per supported core and extension
  slot, aggregates them by shared source image, and sends exact
  `r`/`rg`/`rgb`/`rgba`/`structuralOnly` metadata. Native profile parsing
  validates the requested layout against the ETC1S/UASTC DFD category before
  output reservation or codec entry. Independent review found one Important
  issue: unknown or malformed alpha modes widened base color to RGBA and could
  preempt normal asset validation. A RED-first remediation restricted alpha to
  exact `MASK`/`BLEND` and added malformed string/non-string regressions; final
  independent review returned `APPROVE` with no remaining Important or
  blocking findings. Compliant UASTC-RG and official DATA/RGB alias evidence,
  codec-internal allocation control, cancellation/timeouts, rewritten-GLB
  validator evidence, target runtime, packaging, release, Task 10, and M5
  remain open or `not run`.
- 2026-07-13: Completed and independently approved the twelfth Task 10 safe
  slice for BasisU material usage-role matching without accepting Task 10 or
  M5. The Dart RED showed native image requests had no `usageRole`; the native
  runner RED then failed compilation on the absent role enum/request field.
  The implementation derives only normative selected material texture roles,
  aggregates texture roles by shared BasisU source image, keeps unused images
  structural-only, and initially marked shared color/non-color use ambiguous.
  The following channel-aware slice narrows that wording to overlapping RGB
  channels and preserves valid color-RGB plus linear-alpha packing. Android and
  iOS require exact present case-sensitive metadata, while direct host calls
  explicitly default to structural-only. Ambiguity and authored DFD mismatch
  remain distinct typed diagnostics, and every request completes profile plus
  usage preflight before output reservation or codec entry. Independent review
  returned `APPROVE` with no Important or blocking findings. Compliant UASTC-
  RG, official DATA/RGB alias evidence, codec-internal allocation control,
  cancellation/timeouts, validator, target runtime, packaging, release, Task
  10, and M5 remain open or `not run`.
- 2026-07-13: Completed and independently approved the eleventh Task 10 safe
  slice for BasisU `KHR_texture_basisu` structural-profile enforcement without
  accepting Task 10 or M5. Four initial REDs covered the missing official CTS
  negatives, a generic `decodeFailed` UASTC+ZLIB result instead of a typed
  profile diagnostic, generic UNORM CTS metadata conflicting with the selected
  glTF profile, and profile validation occurring after output-vector reserve.
  Independent review then found R/RG sRGB acceptance plus incomplete KVD
  ordering/uniqueness/padding enforcement; remediation RED reported all five
  missing cases, followed by a separate invalid-UTF-8 RED. A second review
  found leading-BOM acceptance and missing UASTC R branch coverage; the final
  RED isolated BOM acceptance while official UASTC R and explicitly synthetic
  UASTC_RG(6) sRGB branches already rejected correctly. The bounded parser now
  emits typed structural/profile diagnostics before output reservation or
  codec entry, and the 21-artifact corpus records immutable hashes and license.
  Final independent review returned `APPROVE` with no Important or blocking
  findings. RGB/RGBA material usage-role matching, compliant UASTC-RG codec
  evidence, cancellation/timeouts, validator, target runtime, packaging,
  release, Task 10, and M5 remain open or `not run`.
- 2026-07-13: Completed and independently approved the tenth Task 10 safe
  slice as a cross-slice Meshopt ModelLoader fixture remediation without
  accepting Task 10 or M5. The broader BasisU verification exposed the only
  failing integration helper: it still emitted KHR-only ATTRIBUTES v1 after
  the EXT runtime boundary correctly became v0-only. The existing failure is
  the RED. The helper now emits a coherent 101-byte EXT v0 stream, derives both
  compressed lengths from that stream, and asserts the exact rewritten
  `[1, 2, 3, 4]` bytes plus removed extension declarations and no diagnostic.
  Production code and the v0 guard were untouched. Independent review returned
  `APPROVE`; this adds no KHR runtime or target claim and does not close Task
  10 or M5.
- 2026-07-13: Completed and independently approved the ninth Task 10 safe
  slice for BasisU positive/direct-codec conformance and authored-mip
  diagnostics without accepting Task 10 or M5. A pinned, licensed Khronos
  KTX-Software-CTS corpus now drives nine real single-level bridge/direct
  transcoder comparisons with exact RGBA pixel equality and two official mip
  diagnostics. RED first failed on the absent pinned license, then showed the
  bridge silently returning a level-0 PNG for a valid authored pyramid; a
  follow-up precedence RED showed a truncated two-level Level Index being
  masked by the capability diagnostic. Remediation validates declared Level
  Index extent first and rejects valid multi-level input before codec entry or
  output allocation. Independent review returned `APPROVE` with no Important
  or blocking findings. UASTC `R8G8` remains explicitly generic-DATA codec
  evidence rather than KHR `UASTC_RG` support. DFD usage roles, orientation,
  swizzle, premultiplication, compliant UASTC-RG, cancellation/timeouts,
  validator, target runtime, packaging, release, Task 10, and M5 remain open or
  `not run`. The broader verification command also exposed a pre-existing
  Meshopt ModelLoader helper that still emits now-rejected EXT ATTRIBUTES v1;
  that cross-slice regression is recorded for immediate separate remediation.
- 2026-07-13: Completed and independently approved the eighth Task 10 safe
  slice for Draco conformance without accepting Task 10 or M5. The pinned,
  licensed Khronos `Box/glTF-Draco` fixture now supplies real bitstream 2.2,
  reversed semantic-to-attribute-ID ordering, accessor schemas, and a byte-
  exact bridge comparison against the independently invoked vendored Google
  Draco 1.5.7 decoder. The fixture-missing test provided the first RED; the
  separate strip test then showed one native-channel call before remediation.
  The supplied Box JSON digest was found to contain 65 hex characters and was
  rejected; the fetch/provenance records use the independently verified
  64-character official digest ending in `d1b`. Default and explicit
  `TRIANGLES` remain accepted, while `TRIANGLE_STRIP` now preserves honest
  intent through a typed pre-channel capability diagnostic instead of
  rewriting a face list under strip topology. Independent review returned
  `APPROVE` with no Important or blocking findings. Evidence is host-only;
  `TRIANGLE_STRIP`, BasisU conformance, validator, cancellation/timeouts,
  target runtime, packaging, release, Task 10, and M5 remain open, unsupported,
  or `not run` as applicable.
- 2026-07-13: Completed and independently approved the seventh Task 10 safe
  slice for Meshopt conformance without accepting Task 10 or M5. A pinned,
  licensed, hash-verified Khronos `MeshoptCubeTest` corpus now covers 54 claimed
  mode/filter bufferViews plus six explicitly excluded KHR-only `COLOR` views,
  legal placeholder buffers, and real quantized primitive semantics. Initial
  RED reached the official corpus and exposed that triangle-list decoding may
  cyclically rotate each triple; the accepted comparison preserves triangle
  order and winding and separately rejects reversed winding. Independent review
  then rejected the first GREEN because the EXT runtime accepted KHR-only v1
  ATTRIBUTES streams, the quantization assertion was superficial, and one
  placeholder reference direction was unchecked. RED-first remediation now
  requires EXT v0 before decoder entry/reservation, uses coherent v0 synthetic
  streams, proves every claimed filter has official v0 coverage, rewrites an
  official-v0 POSITION/NORMAL embedded-GLB derivative byte-exactly while
  retaining `KHR_mesh_quantization`, and covers both fallback-reference rules.
  The KHR corpus remains a direct-codec oracle only; no KHR/`COLOR`/external
  `.gltf` runtime or platform evidence is claimed. Draco/BasisU conformance,
  validator, cancellation/timeouts, target runtime, packaging, release, Task
  10, and M5 remain open.
- 2026-07-13: Completed and independently approved the sixth Task 10 safe
  slice for BasisU native texture/output-envelope preflight without accepting
  Task 10 or M5. Root now forwards exact budget/state, requires native width/
  height, validates PNG signature/IHDR, and atomically reserves texture pixels
  plus native/decoded bytes. Byte-identical Android/iOS preflight applies
  checked 2D KTX2 dimensions, cumulative current-state budgets, and exact
  stored-deflate PNG size before transcode/pixel/output allocation; post-init
  level-0 dimensions and final PNG length must match. The real `kodim23.ktx2`
  fixture is 768x512 (393,216 pixels) and produces the predicted 1,573,564-byte
  PNG. Independent review rejected the first GREEN because a 40-byte pseudo-
  KTX2 header passed preflight and Android JNI used map/byte-array operations on
  unchecked types. Remediation rejects 40/79/103-byte truncations using the
  checked 80-byte fixed header plus `24 * max(1, levelCount)` declared Level
  Index extent, replaces the pseudo fixture with a coherent 105-byte envelope
  fixture, and preserves malformed Android/iOS entries for typed no-output
  rejection. The claim is deliberately limited to dimension/layout/output-
  envelope preflight; full container/DFD/mip validity remains delegated to the
  pinned transcoder and conformance is open. Its init/start/transcode APIs also
  expose no allocator budget, cancellation, or timeout control. Physical
  targets, full conformance, validator, packaging, and release evidence remain
  open. Task 10 Steps 1 and 3 are partial, Step 4 is unchecked, and Task 10/M5
  remain open.
- 2026-07-13: Completed and independently approved the fifth Task 10 safe
  slice for Draco native declared-output preflight without accepting Task 10
  or M5. Root now sends exact limits and current shared-tracker state; Android
  Java/JNI and iOS Objective-C++ retain presence-aware web-safe integers into
  byte-identical shared C++ preflight. RED-first host runners cover exact and
  exceeded limits, multi-request aggregates, reused accessors, malformed
  numeric metadata, overflow aliases, and complete post-decode schema checks
  before bridge-owned output allocation. Independent review rejected the first
  GREEN because malformed uncompressed extra accessors were silently dropped,
  requested attribute IDs were checked after earlier output allocations, and
  component types could truncate into legal 32-bit values. Remediation rejects
  malformed authored schemas before any channel call, validates all decoded
  meshes/requested IDs before output conversion, and preserves 64-bit metadata
  until legal-enum validation. A compiled fake-codec case proves a missing later
  attribute produces typed diagnostics, zero decoded primitives, and zero
  output-vector allocations on both platform copies. The pinned Google Draco
  API has no pre-decode internal memory/point/face/cancel/timeout control, so
  codec-internal allocations remain a genuine upstream blocker. Target runtime,
  BasisU native limits, conformance, cancellation/timeouts, validator, and
  release evidence remain open. Task 10 Steps 1 and 3 are partial, Step 4 is
  unchecked, and Task 10/M5 remain open.
- 2026-07-13: Completed and independently approved the fourth Task 10 safe
  slice by threading the exact user-selected budget and one per-load tracker
  through ModelLoader and the native probe into both component rewriters,
  without accepting Task 10 or M5. Initial RED failed compilation because the
  internal decode contract lacked required budget/tracker parameters. The first
  GREEN passed 71 focused tests, but independent review rejected it because
  component payloads were reserved in the rewriter and their containing final
  GLB was then added again by ModelLoader, while opaque final bytes were counted
  once. Remediation introduced required output-accounting metadata, non-mutating
  component-container envelope checks, exactly-once opaque final/intermediate
  reservations, typed inconsistent-result diagnostics, and mixed sequential
  stage settlement. Exact and one-byte-below integration tests now cover Draco
  components, BasisU components, and opaque final bytes. Native bridges still
  do not receive/enforce these limits before allocation; texture dimensions,
  cancellation/timeouts, official conformance, validator, and target evidence
  remain open. Task 10 Steps 1 and 3 remain partial and unchecked; Task 10 and
  M5 remain open.
- 2026-07-13: Completed and independently approved the third Task 10 safe
  slice at the BasisU Dart rewrite boundary without accepting Task 10 or M5.
  RED-first tests added JSON, embedded-BIN, aggregate decoded/native-output,
  duplicate/missing/empty/unsupported/out-of-range image, and atomic late-
  failure coverage. The first GREEN passed 23 focused tests plus probe/loader
  regressions, but independent review rejected it: valid textures sharing one
  BasisU image produced duplicate native requests/outputs, while valid-looking
  unreferenced native images bypassed all budgets. Remediation deduplicates
  requests by image index, preserves deterministic first-texture metadata,
  rewrites every sharing texture to the same core source, retains strict
  duplicate-output rejection, and rejects unreferenced output before planning,
  allocation, mutation, or tracker reservation. Texture-pixel enforcement is
  still unavailable because the pinned plugin returns no trusted dimensions;
  native allocation prevention, user-budget propagation into the probe,
  official BasisU/KTX2 conformance, cancellation/timeouts, validator, and
  target evidence remain open. Task 10 Steps 1 and 3 remain partial and
  unchecked; Task 10 and M5 remain open.
- 2026-07-13: Completed and independently approved the second Task 10 safe
  slice at the Draco Dart rewrite boundary without accepting Task 10 or M5.
  RED-first tests now enforce coherent counts across every authored primitive
  attribute, reject empty Draco attribute maps, validate decoded accessor
  payload lengths and embedded-BIN declarations, and exercise exact/exceeded
  shared accessor, vertex, index, JSON, and aggregate decoded-byte budgets.
  Independent review rejected the first GREEN because untouched attributes
  escaped count validation, cross-primitive accessor reuse double-charged
  vertices, and the caller tracker committed before final GLB construction.
  The remediation validates all authored attributes, charges every returned
  native payload while reserving reused accessors/vertices once, constructs
  final bytes before the real commit, and proves deterministic post-build
  failure leaves all counters unchanged. Native plugin allocation prevention,
  official Draco conformance, cancellation/timeouts, BasisU enforcement,
  validator, packaging, and target evidence remain open. Task 10 Steps 1 and 3
  remain partial and unchecked; Task 10 and M5 remain open.
- 2026-07-13: Completed and independently approved the first Task 10 shared-
  budget slice without accepting Task 10 or M5. A new immutable
  `GlbDecodeBudget` and per-load tracker use the JavaScript max-exact integer
  boundary and checked product/accumulation before Meshopt decode allocation.
  Review caught a VM-only large-shift test, unsafe failure-path arithmetic,
  invalid-limit/operand gaps, and attacker-controlled embedded-BIN padding
  before budget checks. RED-first remediation now reports non-exact overflow
  with explicit metadata without forming the unsafe sum/product, rejects
  negative or greater-than-max-exact Meshopt operands before decoder entry,
  validates runtime budget values, and rejects declared BIN length beyond the
  existing chunk before allocation. Exact JSON/product/aggregate/native limits
  pass; a second-view aggregate failure returns no bytes and leaves source
  extension declarations unchanged. ModelLoader rejects an oversized native
  decoded GLB before capability re-read or adapter import, but this does not
  prevent allocation inside the plugin. Draco/BasisU schema/native enforcement,
  accessor and texture budgets, cancellation/timeouts, conformance fixtures,
  validator, and target evidence remain open. Task 10 Steps 1 and 3 are
  partial and unchecked; Task 10 and M5 remain open.
- 2026-07-13: Independent review approved the bounded Task 9 transmission/
  volume audit after three RED-first remediation cycles. The shader now uses
  the normative red/green channels, leaves source alpha independent, produces
  no thin-surface macroscopic offset, and contains none of the prior authored
  studio/contour/glint, alpha-cap, roughness-color, synthetic-reflection, HDR-
  clamp, or attenuation-floor heuristics. Review found that source-only tests
  missed factor-zero unlit replacement, positive volume without node scale,
  `ior == 0` coercion, and adapter-side allocation/order bugs. The final
  boundary treats factor zero as a standard-PBR bypass/reset, applies combined
  core intent only after successful loads, skips irrelevant extension binding
  validation/decode, and preserves active state on failure. Positive runtime
  transmission textures, positive thickness, `ior == 0`, and missing scene-
  view contracts now return typed pre-decode diagnostics with backend defense
  in depth. The exact Task 9 suite passed 110 CPU tests with 13 explicit skips;
  those GPU/Impeller, visual, renderer, and target rows remain `not run`.
  Renderer-native transport is
  [deferred Plan 016](../deferred/016_renderer_native_transmission_volume.md).
  Only Task 9 Step 2 and the conditional deferred-disposition acceptance item
  are complete; Task 9, M4, the v1 glass release gate, and Plan completion
  remain open.
- 2026-07-13: Independent review approved the bounded Task 8 clearcoat audit
  slice after two Important findings were remediated RED-first. The first
  source-only audit had removed a heuristic highlight but missed that the
  pinned lit `.fmat` emitter adds `EvaluateLighting(material)` after the
  authored `Surface`, so the remaining manual coat BRDF/IBL/direct/shadow path
  still double-counted lighting through emissive. The candidate now compiles
  to one engine lighting evaluation and passes coat roughness, independent coat
  normal, and occlusion through `MaterialInputs`; authored heuristic, BRDF,
  IBL, shadow, and coat-emissive lighting are removed. The second review found
  that positive clearcoat suppressed the retained source PBR normal even
  though the overlay did not consume it. Source-normal suppression, `.35`
  attenuation, restore state, and adapter synchronization are removed;
  successful combined/later core patches retain the latest base normal and
  scale exactly once, while failed overlay reconfiguration remains atomic.
  Double-sided candidate clearcoat returns a typed diagnostic before shader
  creation, source mutation, state, or overlay attachment. The alpha overlay
  still cannot independently weight coat energy and base Fresnel attenuation,
  so it remains non-conformant `candidate-only`; post-change GPU/visual and
  target evidence is `not run`. The explicit renderer-native follow-up is
  [Plan 015](015_renderer_native_clearcoat.md). Only Task
  8 Step 2 and the conditional deferred-disposition acceptance item are
  complete; Task 8, M4, the v1 release gate, and Plan completion remain open.
- 2026-07-13: Independent review approved the complete safe in-repo Task 7
  slice, including the final opaque-IOR diagnostic wording cleanup, with no
  Important findings. Intrinsic public and authored-data validation now
  precedes unavailable-capability routing, malformed authored IOR no longer
  discards valid transmission/volume siblings, and unavailable non-native
  specular or package-local opaque-IOR intent fails before texture loading,
  material mutation, persistence, or render requests. A genuinely
  renderer-native opaque-IOR contract retains its setter path, and candidate
  transmissive IOR is unchanged. The post-review milestone harness passed,
  but this is not Task 7 or M3 acceptance: the pinned renderer still exposes
  no specular or opaque-IOR fields, texture slots, importer mapping, shader
  inputs, or variable dielectric F0. The renderer acceptance skip, A1B32
  runtime/visual gate, GPU/Impeller, simulator, physical iOS, Android material,
  Web, packaging, and release evidence remain `not run`; Steps 1-2 remain
  partial and unchecked, while Steps 3-6, Task 7, M3, and Plan completion
  remain `blocked` on upstream renderer support.
- 2026-07-13: Applied the approved Task 7 diagnostic-only review cleanup. A
  focused RED test proved valid opaque IOR-only intent under default/unavailable
  support still received transmission/glass wording without an opaque-IOR
  feature or limitation. Public validation now returns an opaque-IOR-specific
  unsupported diagnostic when `KHR_materials_ior` is the only missing
  capability and no transmission/volume intent exists. Glass intent retains
  the combined transmission/IOR/volume diagnostic. Routing, capability
  availability, upstream support, and all Task 7/M3/A1B32 gates are unchanged.
- 2026-07-13: Remediated three Important findings from the first Task 7
  safe-slice review without accepting Task 7 or M3. Five new RED regressions
  proved that intrinsic specular/IOR domain errors lost precedence to
  unavailable-capability diagnostics, invalid glass IOR discarded otherwise
  valid transmission/volume intent, non-native specular bypasses returned
  success, and package-local opaque IOR `0`/`1.45` silently succeeded and
  persisted through the real controller/adapter boundary. The bounded fix now
  reports intrinsic `invalidMaterialOverride` diagnostics first for direct and
  deserialized patches; invalid authored IOR removes only IOR while preserving
  valid transmission, thickness, attenuation, and sibling groups; and the
  adapter returns pinned-standard-PBR contract diagnostics before texture
  loading, material mutation, persistence, or render requests for non-native
  specular/opaque-IOR intent. Candidate transmissive IOR remains available,
  and an actual renderer-native material/support pair retains the opaque-IOR
  setter path. No wrapper BRDF, overlay, clamp/coercion, dependency change, or
  release claim was added. Steps 1-2 remain partial and unchecked; Steps 3-6,
  Task 7, M3, A1B32, and Plan completion remain `blocked`/`not run`.
- 2026-07-13: Began the smallest safe Task 7 slice without claiming renderer
  support. Khronos `KHR_materials_specular` and `KHR_materials_ior` text and
  schemas were used as the normative contract. RED-first public/GLB tests
  exposed four missing behaviors: public specular-color domain/shape and IOR
  validation returned no typed diagnostics, while authored specular factor
  `1.01` and IOR `0.5` incorrectly survived in their extension groups. The
  bounded fix accepts specular strength `[0, 1]`, non-negative finite
  three-component linear specular color including values above `1`, and IOR
  exactly `0` or finite `>= 1`; it rejects invalid values without clamping and
  invalidates only the malformed authored group. Valid opaque-IOR/specular
  sibling groups and separately delivered core material intent remain intact.
  Adapter classification verifies IOR `0` and ordinary opaque IOR remain in
  the standard PBR family. Current policies keep specular unavailable with
  `diagnosticOnly` maturity and `notRun` evidence per target, and existing
  native diagnostics reject scalar/texture specular intent before mutation.
  A pinned renderer audit found no specular/IOR PBR fields, standard texture
  slots, importer mapping, or shader inputs, with dielectric F0 fixed at
  `0.04`; consequently the required texture roles, factor multiplication,
  dielectric energy conservation, metal isolation, IOR BRDF trends, and A1B32
  runtime gate remain `blocked`/`not run`. No upstream checkout, dependency-pin
  change, wrapper BRDF, overlay, texture bake, generated UV, or asset-specific
  fix was added. Task 7 Steps 1-2 are partial and unchecked; Steps 3-6, Task 7,
  M3, and Plan 014 remain blocked.

- 2026-07-13: Independent review approved the complete safe in-repo Task 6
  slice after the ninth remediation with no Important findings. Equal-axis
  sampler/filter intent reaches every wrapper-created texture path; unsupported
  asymmetric axes, non-identity transforms, and non-UV0 bindings remain typed
  diagnostic-only; renderer-native application is preflighted atomically; and
  the package-local clearcoat candidate now composes only the core inputs its
  shader actually consumes without diverging live renderer state from
  controller persistence. The post-review milestone harness passed, but this
  is not Task 6 or M2 acceptance: Steps 4-6 remain `blocked` because there is
  no upstream per-slot transform contract/commit and no durable Glorvia runtime
  evidence. GPU/Impeller, visual, simulator, physical iOS, Android material,
  and Web evidence remains `not run`; package-local clearcoat remains
  `candidate-only` and no production-ready or release claim changed.
- 2026-07-13: Remediated the ninth Task 6 re-review without accepting Task 6
  or M2. A package-local clearcoat shader audit separated the core inputs that
  the current candidate overlay actually consumes from fields that are merely
  declared or configured: it reads base-color texture/factor alpha,
  occlusion-texture red, and the base normal, but does not consume
  metallic/roughness or emissive values. Under an active coat, a later
  core-only delta for those consumed inputs now merges the active clearcoat
  patch, uses each newly loaded base-color, occlusion, or normal texture while
  retaining the other active texture representations, and creates/configures
  a replacement overlay before any base-material or controller-store mutation.
  Replacement failure therefore emits the existing typed clearcoat
  `shaderUnavailable` diagnostic and preserves the prior base material,
  overlay, logical state, and persisted intent. Successful base-alpha and
  occlusion changes remain composed through a later sparse clearcoat-only
  update, consistent with Khronos base-color multiplication/alpha and
  occlusion red-channel semantics. This is bounded wrapper composition for the
  package-local candidate, not a metallic/emissive capability claim or a
  custom general-PBR renderer. Task 6 Steps 4-6 and M2 remain `blocked`;
  runtime capability, release maturity, and target evidence are unchanged.
- 2026-07-13: Remediated the eighth Task 6 re-review without accepting Task 6
  or M2. Package-local clearcoat now snapshots the unattenuated logical source
  normal scale before suppressing the base pass. A first combined normal plus
  positive-clearcoat patch that omits `normalScale` therefore derives both the
  overlay and base suppression from the prior PBR scale/default exactly once.
  Under an active coat, a later core-only normal delta with omitted scale
  changes the logical texture but retains the prior logical scale instead of
  copying the already attenuated live material value. Factor zero restores the
  new logical normal/scale, and a later positive factor attenuates it once.
  Sparse clearcoat replacements now merge `activeClearcoatConfig.patch` before
  material creation and retain prior loaded base/coat texture representations
  unless the incoming delta supplies a replacement. Controller persistence and
  the live overlay consequently preserve the same clearcoat roughness,
  clearcoat/roughness/normal textures, normal scale, and sampler-bearing
  `TextureSource` identities across factor-only zero/positive updates. Shader
  creation/configuration still precedes state or renderer mutation, and reset
  still restores immutable model state A. Task 6 Steps 4-6 and M2 remain
  `blocked`; runtime capability, release maturity, and target evidence are
  unchanged.
- 2026-07-13: Remediated the seventh Task 6 re-review without accepting Task 6
  or M2. Package-local clearcoat state now separates the immutable model
  normal/scale used by `resetPart` from the mutable logical source normal/scale
  used by later runtime deltas. A combined normal B/scale `0.5` plus positive
  clearcoat therefore restores B/`0.5` when factor becomes zero and supplies
  B/`0.5` to a later positive clearcoat-only replacement instead of regressing
  to model normal A. While a coat is active, a later core-only normal C/scale
  delta first creates and configures a replacement overlay, then updates the
  logical source and re-suppresses the base normal; shader/configuration
  failure returns the existing typed `shaderUnavailable` diagnostic before
  any material, overlay, or logical state mutation. The existing
  `@visibleForTesting` adapter helper gained only an optional reusable-adapter
  argument so a literal controller `resetPart` regression can prove that reset
  still restores immutable A while factor-zero uses logical B/C. Task 6 Steps
  4-6 and M2 remain `blocked`; GPU `MaterialParameters`, Glorvia, UV
  transforms, visual runs, simulator, physical-device, Android material, and
  Web evidence remain `not run` or `blocked` as previously recorded.
- 2026-07-13: Remediated the sixth Task 6 re-review without accepting Task 6
  or M2. Stateful package-local clearcoat updates now resolve a deliberately
  suppressed base/source normal and its unattenuated scale from the backend's
  preserved primitive state when constructing a replacement overlay. A
  successful later `clearcoat: 0` patch restores the legitimate source normal
  and scale before the current-normal-null early return, matching Khronos'
  factor-zero disabled-layer semantics. Shader creation and configuration
  still complete before either restoration or suppression mutates the renderer
  material, so backend failure remains atomic. Fresh factor-zero combined core
  normals, positive suppression, reset restoration, and exactly-once normal
  scaling remain covered and green. Controller store inspection confirmed that
  runtime updates already deliver delta patches, so no controller change was
  needed. Task 6 Steps 4-6 and M2 remain `blocked`; GPU
  `MaterialParameters`, Glorvia, UV transforms, visual runs, simulator,
  physical-device, Android material, and Web evidence remain `not run` or
  `blocked` as previously recorded.
- 2026-07-13: Remediated the fifth Task 6 re-review without accepting Task 6
  or M2. Explicit authored alpha-mode core patches now preserve the identity
  and scalar extension contract of a PBR material that implements the pinned
  renderer-native boundary while still refreshing the mounted mesh for the
  alpha pipeline change. CPU controller-to-adapter integration proves alpha
  mask/cutoff applies before an unsupported specular group and that later
  supported native clearcoat and transmission/IOR setters still reach the same
  material; the existing ordinary-PBR replacement test remains green.
  Package-local clearcoat now re-synchronizes source-normal suppression after
  successful overlay creation and standard core mutation. The overlay receives
  the incoming raw normal and its scale once, positive clearcoat keeps the base
  normal suppressed, zero clearcoat preserves a legitimate combined core
  normal, and reset restores the original source normal and scale. Task 6 Steps
  4-6 and M2 remain `blocked`; GPU `MaterialParameters`, Glorvia, UV transforms,
  visual runs, and all target evidence remain `not run`/`blocked` as previously
  recorded.
- 2026-07-13: Remediated the fourth Task 6 re-review without accepting Task 6
  or M2. Authored core is still applied first, but the controller now sends
  each authored extension group to the sink independently instead of merging
  prior core/groups into a direct cumulative patch; the dead cumulative state
  was removed. CPU controller-to-adapter integration proves an unsupported
  specular group does not discard valid core or supported renderer-native
  clearcoat and transmission/IOR groups. Package-local clearcoat now continues
  into base PBR core mutation only after overlay success, while overlay failure
  leaves core unchanged. Package-local transmission rejects incoming and
  source alpha-mask intent before loading, and package-local extension patches
  reject combined visibility before geometry mutation. Normal scale remains
  exactly once and the prior native specular/mixed-patch diagnostics remain
  intact. Task 6 Steps 4-6 and M2 remain `blocked`; GPU `MaterialParameters`,
  Glorvia, UV transforms, visual runs, and all target evidence remain
  `not run`/`blocked` as previously recorded.
- 2026-07-13: Remediated the third Task 6 re-review without accepting Task 6
  or M2. Package-local transmission and clearcoat now load incoming normal-map
  bytes raw and consume normal scale once in their per-material shader
  parameters; standard PBR retains its existing scaled-pixel path and upstream
  scale of `1`. Transmission also falls back to an existing PBR source normal
  scale when the incoming patch omits it. Advertised renderer-native support
  now rejects scalar specular/specular-color intent until a real native
  contract exists, and rejects direct mixed core-plus-native-extension patches
  before texture loading, setters, or target mutation. Task 6 Steps 4-6 and M2
  remain `blocked`; GPU `MaterialParameters`, Glorvia, UV transforms, visual
  runs, and all target evidence remain `not run`/`blocked` as previously
  recorded.
- 2026-07-13: Remediated the second Task 6 re-review without accepting Task 6
  or M2. Candidate transmission preflight now examines both incoming patches
  and existing PBR source state, preserves supported base-color/normal intent,
  and atomically rejects metallic/roughness, metallic-roughness texture,
  occlusion, or emissive state that the bounded shader would discard. The
  diagnostic identifies each field's patch/source origin and directs callers
  to a renderer contract that consumes combined core-plus-transmission intent.
  Renderer-native preflight and application now share one capability check and
  reject all extension texture bindings before any scalar setter runs. The
  preprocessed clearcoat test seam now exercises the real resolver/setter and
  diagnostic mapping; its assignment record is private and the redundant
  diagnostic-factory hook was removed. Task 6 Steps 4-6 and M2 remain
  `blocked`; GPU `MaterialParameters`, Glorvia, UV transforms, visual runs, and
  target evidence remain `not run`/`blocked` as previously recorded.
- 2026-07-13: Remediated Task 6 review findings without accepting Task 6 or
  M2. Preprocessed clearcoat now binds a ready `TextureSource` with both its
  sampled GPU texture and sampler, preserves raw GPU texture support, and
  emits typed `preprocessedTextureSampleUnavailable` diagnostics before target
  mutation when no sampled texture exists. Binding-only transmission and
  thickness now participate in capability checks. Clearcoat receives loaded
  occlusion and emissive sources. Package-local transmission rejects
  metallic-roughness, occlusion, and emissive core intent atomically instead
  of silently dropping it. CPU tests verify distinct resulting sampler state
  on standard PBR slots; actual clearcoat `MaterialParameters` texture/sampler
  assignment remains GPU-gated and was `not run`. Task 6 Steps 4-6 and M2 stay
  `blocked`; Glorvia renderer application is still `not run`.
- 2026-07-13: Completed the safe in-repo Task 6 slice without accepting Task 6
  or M2. Added RED-first adapter/backend coverage for symmetric and asymmetric
  wrap, all public min/mag/mip modes, color/data/normal creation paths,
  per-slot transforms, same-source independent bindings, existing all-slot
  controller routing, and no-decode/no-byte-generation rejection. Equal wrap
  axes and representable filter intent now pass through every wrapper-created
  `Texture2D.fromAsset`, `fromImage`, and `fromPixels` path. Asymmetric axes,
  non-identity per-slot transforms, and non-UV0 runtime bindings preserve
  intent and emit typed renderer-boundary diagnostics. The pinned source audit
  is recorded in `docs/references/flutter_scene_capability_notes.md`. No pub
  cache, dependency pin, shader, generated UV, texture baking, or custom
  general-PBR renderer change was made. Task 6 Steps 4-6 and M2 remain
  `blocked`; Glorvia renderer application is `not run`.
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

- 2026-07-15: Bounded closure documentation passed the full repository
  harness. The first sandboxed `bash tools/run_checks.sh` attempt stopped at
  Flutter SDK cache stamp writes with `Operation not permitted`; the permitted
  rerun passed repo lint, formatted 88 files with zero changes, completed
  dependency resolution, reported `No issues found!`, and completed the full
  suite at `+503 ~16`. The skips remain the existing explicitly labelled
  plain-process Flutter-GPU/Impeller gates and do not establish physical iOS,
  Android, Web, packaging, or release evidence. Post-log
  `python3 tools/repo_lint.py` and `git diff --check` are recorded separately
  by the final repository audit; no device or release command was run.

- 2026-07-14: The initial-material regression was established RED-first. The
  focused widget test initially failed compilation because
  `initialMaterialOverrides` did not exist, then passed `+1` after the minimum
  load-order implementation. The disposable iOS app passed `flutter analyze`
  with no issues. XcodeBuildMCP rebuilt and ran it on iPhone 17 / iOS 26.5;
  build completed with no errors and only the two existing unknown Swift debug
  environment-variable warnings. A 30 fps cold-launch recording captured the
  full restore sequence: `1/4`, `2/4`, and `3/4` remained behind the loading
  surface, and the model appeared only at `SUCCESS · 20 parts · 4/4 applied`.
  The permitted full `bash tools/run_checks.sh` run passed repo lint, formatted
  88 files with zero changes, reported `No issues found!`, and completed at
  `+505 ~16`; skips remain the explicit plain-process Flutter-GPU gates.
  `python3 tools/repo_lint.py` and `git diff --check` also passed. No commit or
  push was performed.
- 2026-07-14: Same-runtime A/B isolation passed. The failing A state kept the
  four-primitives matrix `IOR=[1.1,1.5,2,0]`, including tinted specular on the
  front skirt, and reproduced the white regions in six orbit captures. The B
  state changed only those optical values to common Glorvia-like
  `specular=1`, neutral specular color, and `IOR=1.45`; it again reached
  `SUCCESS · 20 parts · 4/4 applied`, and six equivalent continuous-orbit
  captures were visually clean. This result does not justify a GLB edit,
  polygon offset, depth hack, or valid-value clamp. It corrects the interactive
  harness state while retaining isolated IOR/specular conformance trends.
- 2026-07-14: The user-visible rerun invalidated the earlier Simulator visual
  conclusion. The application still reached `SUCCESS · 20 parts · 4/4
  applied`, but six subsequent live auto-orbit screenshots visibly retained
  angle-dependent white regions. The RED/source/full-suite results below prove
  only the face-normal contract and regression safety; they do not prove this
  reported artifact fixed. Visual status is reopened and the current shader
  change remains a candidate component pending controlled runtime isolation.
- 2026-07-14: The face-orientation regression was established RED-first. The
  focused test failed at `+0 -1` because the fragment had no
  `ExtendedPbrGeometricNormal` contract, then passed at `+1` after the bounded
  implementation. The complete extended-material file passed `+12`; the exact
  Task 6 command passed `+151 ~13`, with the existing skips limited to explicit
  plain-process Impeller/Flutter-GPU gates. A disposable iPhone 17 Simulator
  harness logged `Using the Impeller rendering backend (Metal)`, loaded 20
  A1B32 primitives, applied all four unchanged extreme specular/IOR variants
  with zero new diagnostics, and completed continuous auto-orbit inspection at
  front, side, and back angles. The first sandboxed `bash tools/run_checks.sh`
  attempt was blocked only by Flutter SDK cache write permissions; the
  permitted rerun passed repo lint, formatted 88 files with zero changes,
  resolved dependencies, reported `No issues found!`, and completed the full
  suite at `+504 ~16`. `git diff --check` also passed.
  Post-run process inspection found no Flutter runner, Puppeteer, webdriver,
  remote-debugging Chrome, or temporary HTTP-server process; post-log repo lint
  and `git diff --check` passed.
- 2026-07-14: Final Task 6/7 verification passed. The exact Task 6 command,
  including the migrated legacy path and the combined material/backend suites,
  completed at `+150 ~13`; every skip is an existing plain-process
  Impeller/Flutter-GPU gate, while the real packaged shader path is covered by
  the recorded Simulator run. The exact Task 7 command completed at `+122`
  with no skips. `bash tools/run_checks.sh` then passed `repo lint`, formatted
  88 files with zero changes, resolved dependencies, reported `No issues
  found!`, and completed the full suite at `+503 ~16`. The additional six-stage
  Three.js r167 run logged `FSV_PLAN014_THREEJS success stages=6 meshes=20`;
  its evidence validates the exact input hashes, runtime values, fixed state,
  capture hashes, and reproduction-harness hash. All six images were visually
  inspected as directional evidence, not pixel-parity or target evidence.
  Browser-process inspection after capture found only the inspection command
  itself. Task 6 Step 6 and Task 7 Step 6 are accepted; physical-target,
  cross-platform, release, and production-readiness gates are unchanged.
  Post-log checks also passed repo lint, capability-matrix currency,
  `git diff --check`, and JSON parsing for both the iOS and Three.js evidence
  records.
- 2026-07-14: Real iOS Simulator acceptance passed. Flutter logged
  `Using the Impeller rendering backend (Metal)` and
  `FSV_PLAN014_STATUS success parts=20 diagnostics=4`; the four diagnostics
  were pre-existing authored A1B32 textile/body diagnostics, and every one of
  the four combined patches plus six isolated trend stages reported
  `diagnosticsDelta=0`. The final summary was `applied=4/4 parts=20
  overrides=4 diagnostics=4`. GUI picking logged primitives 0 and 2. All
  screenshot, source, input, bundle, and reproduction-snapshot hashes in
  `evidence.json` validate; its post-attribution source hash is
  `0be31724a00b2400280b1ef2141981f6c92af2103adec27daef99528a1a1a490`,
  while the executable bundle remained byte-identical. The disposable harness
  passed `flutter analyze` with no issues and was shut down after capture.
- 2026-07-14: Capability evidence was updated RED-first. The focused command
  `flutter test --no-pub test/capability_matrix_generation_test.dart
  --plain-name 'generated capability matrix has explicit feature-target
  truth'` exited 1 because the first expected iOS Simulator row was still
  `blocked`. After restricting verified rows to the four recorded features,
  updating the source and generated matrix, and correcting the three public
  evidence summaries, all 8 capability-matrix tests passed. The focused
  extended material/backend/adapter/controller command then passed 102 tests
  with one explicit plain-process Impeller preflight skip; the obsolete
  deliberately failing renderer-acceptance skip was removed because the real
  simulator gate now supplies that evidence. Full repository verification is
  still pending, so the two Task verification checkboxes remain open.
- 2026-07-14: Extended-PBR foundation and atomic-routing verification passed.
  RED `flutter test --no-pub test/flutter_scene_adapter_material_test.dart
  --name 'core-only delta keeps the active extended PBR state'` exited 1 because
  the second delta produced only one backend config; after replacing the
  concrete-class coupling with the retained-state contract, the same command
  passed. The focused atomic group passed 3/3, covering repeated composition
  plus exact reset, identity-core native retention, and invalid-backend zero
  mutation. The combined shader/material/backend/adapter/controller command
  passed 102 tests with two explicit Impeller gates. The required Task 7
  five-file command passed 122 tests with one explicit Impeller trend-matrix
  gate. The raw shader bundle compiled during those Flutter test hooks. These
  are CPU/compiler/routing results only: packaged GPU reflection, Glorvia 2.5
  versus 1.0 application, A1B32 specular/IOR trends, physical iOS, Android,
  Web, release, and production evidence remain `not run`; Task 6 Steps 4-6,
  Task 7 Steps 3-6, M2, M3, and Plan 014 remain open.
- 2026-07-14: Fresh RED command
  `flutter test test/flutter_scene_uv_transform_material_test.dart test/viewer_controller_material_test.dart --name 'extended PBR contract'`
  exited 1 with one pass and one expected failure. The atomicity test passed.
  The shader-seam test failed at
  `test/flutter_scene_uv_transform_material_test.dart:35` with
  `Expected: true`, `Actual: <false>`, and
  `A separate raw shader bundle is required to replace fixed EvaluateLighting.`
  This is the current RED, not historical evidence. No shader or material
  production implementation existed when it was captured.
- 2026-07-14: The authoritative extended-PBR plan amendment passed its required
  documentation gate. Self-review of the active architecture, assumptions,
  ownership table, planned files, Task 6/7 interfaces, routing/atomicity test
  layers, milestone gates, closure gates, and checklist found no current
  placeholder, asset/product branch, fragment stacking, silent feature drop,
  stale upstream-only blocker, or false completion claim. Older contradictory
  entries remain explicitly historical and are superseded by the new topmost
  progress entry. `python3 tools/repo_lint.py` exited 0 with
  `repo lint passed`; `git diff --check` exited 0 with no output. This is
  documentation-only verification. The fresh Task 6/7 RED, shader compilation,
  Flutter/GPU tests, Glorvia transformed rendering, and A1B32 specular/IOR
  rendering are `not run`; Task 6 Step 4, Task 7 Steps 1-6, M2, M3, and Plan
  014 remain open.
- 2026-07-14: The user-approved fork-free Task 6 design amendment passed its
  documentation self-review. The scan found no unresolved current-contract
  statement that assigns C28 or repeat 2.5 to A1B32; historical blocker entries
  remain historical evidence. The selected design explicitly separates caller
  data ownership, UV-transform sampling, pinned engine lighting, atomic
  failure, and candidate-only evidence; it contains no placeholder, asset-name
  branch, texture bake, generated UV, custom BRDF/IBL/light/shadow/fog path, or
  silent identity fallback. `python3 tools/repo_lint.py` passed and
  `git diff --check` passed. This was documentation-only verification: shader
  compilation, Flutter tests, GPU binding, and simulator rendering for the new
  bridge are `not run`, and Step 4/M2 remain open pending written-design review
  and RED-first implementation.
- 2026-07-14: Glorvia C28 focused evidence passed without changing production
  behavior. The official page download produced three HTTP 200 JPEGs:
  2028×2092 front/reverse albedos and a 1024×1024 crepe normal, with the exact
  hashes recorded in the progress entry. The disposable Flutter harness
  passed `flutter analyze` with no issues, loaded A1B32 on the open iPhone 17
  Simulator as `SUCCESS · 20 renderable parts`, displayed the unchanged real
  C28 files, and recorded four runtime
  `perSlotUvTransformContractMissing` blockers for the rejected 2.5 albedo
  intent. Its accepted visual state is explicitly labelled `albedo 1×
  fallback + normal 1×`; it is not transformed-UV acceptance. The Three.js
  evidence command completed four views and wrote
  `tools/out/material_extension_acceptance/a1b32_threejs_glorvia_c28/evidence.json`
  (`7115e0a9630b0345ead6d224475e25dc0c639a4398346c43a10d40482a20831c`).
  The existing capture-contract suite passed 4/4. The exact Task 6 focused
  Flutter command passed 129 tests with 13 explicit GPU/Impeller-gated skips;
  those skips remain `not run`. Post-capture process inspection found no
  headless Chrome, Puppeteer, Playwright, webdriver, or temporary HTTP-server
  process. Task 6 Step 5, Task 6 Step 6, M2, transformed iOS rendering,
  physical iOS, Android material rendering, Web, release, and production
  gates remain blocked or `not run`.
- 2026-07-14: Corrected the A1B32 visual classification after user review.
  `npm run test:plan014-capture --prefix
  tools/reference_renderers/threejs_material_extension_fixture` passed 4/4,
  and `npm run capture:a1b32-plan014 --prefix
  tools/reference_renderers/threejs_material_extension_fixture` reproduced all
  four fixed authored-data views with Three.js r167. The raw Three.js front
  capture SHA-256 is
  `e83a2fcaac4be1f8e22762c4729928ffdd99ad8ada27ad466e085a5eda14eab9`;
  it reproduces the same black garment failure direction as the iOS Simulator.
  Source inspection mapped `top_FRONT_2219.041` to white
  `beyaz_153968`, `skirt_FRONT_2234.014` to white `beyaz_153916`,
  `top_BACK_2219.040` to black `R_0_153975`, and
  `skirt_BACK_2234.013` to black `R_0_153923`; all four materials are opaque
  and double-sided. Simulator logs reported `SUCCESS`, 20 parts, and exactly
  44 diagnostics: four model-authoring diagnostics and two renderer-extension
  diagnostics for each of 20 primitives. The prior capture is retained as a
  failure artifact at
  `tools/out/material_extension_acceptance/a1b32_flutter_scene_ios_simulator/front_authored_failure.jpg`;
  it is not positive texture evidence. No headless Chrome/Puppeteer process
  remained after capture. A clean historical Three.js repair variant is
  diagnostic isolation only and cannot satisfy Plan 014 because it changes
  authored back base color and visibility.
- 2026-07-14: A1B32 iPhone 17 Simulator follow-up used iOS 26.5, Xcode 26.6,
  Flutter 3.47.0-0.1.pre, Impeller/Flutter GPU, and the debug harness at
  `/private/tmp/fsv_plan014_a1b32_sim`. The corrected focused reader command
  first failed both new cases: the capability reader emitted
  `adapterFailure`, and the material reader returned no patch. After guarding
  the 8 MiB limit by JSON chunk type, the same two-file command passed 30/30.
  The loader-inclusive command passed 58 tests with three explicit
  GPU/Impeller-gated skips, and focused analysis of the five affected source
  and test files reported no issues. Runtime UI inspection reported
  `SUCCESS · 20 renderable parts`; after the fix, its unique diagnostic codes
  were only `unsupportedModelFeature` and `unsupportedMaterialFeature`.
  The full post-change `bash tools/run_checks.sh` gate passed repo lint, zero
  formatting changes, dependency resolution, analysis, and 482 tests with 16
  explicit GPU/renderer/visual skips. Standalone repo lint and
  `git diff --check` also passed. The ignored evidence capture is
  `tools/out/material_extension_acceptance/a1b32_flutter_scene_ios_simulator/front_authored_failure.jpg`;
  its SHA-256 is
  `4eb6323864afd6675a085e5e16da14b9d8914a0da51dc70037a4764c09060820`.
  This is local simulator failure evidence, not accepted core-texture,
  physical-iOS, Android, Web, release, or production evidence. Specular/IOR
  application, acceptable garment rendering, picking, hierarchy invariants,
  sustained compositing, and the full A1B32 closure gate remain blocked or
  `not run`.
- 2026-07-14: Task 10/11 executable closure checks passed. The exact focused
  root command completed 89 passes and three explicit adapter GPU/Impeller
  skips. `packages/flutter_scene_viewer_draco` completed 7/7 and
  `packages/flutter_scene_viewer_basisu` completed 12/12, both including real
  pinned native bridge runners. The first sandboxed `bash tools/run_checks.sh`
  attempt stopped before formatting because Flutter could not write its SDK
  cache outside the workspace; the approved rerun passed repo lint, zero format
  changes, dependency resolution, `flutter analyze` with no issues, and 480
  tests with 16 explicit skips. The skips are the renderer-native
  specular/opaque-IOR acceptance case, three ModelLoader GPU cases, and twelve
  material-extension backend GPU/visual cases listed in Task 10 Step 5.
  `python3 tools/repo_lint.py` and `git diff --check` also passed. Read-only
  cancellation inspection confirmed that `ModelLoader.load` and
  `FlutterSceneViewerController.load` carry no cancellation signal, the only
  existing `isCanceled` route is environment-specific, Meshopt remains
  synchronous in the caller isolate, and Draco/BasisU MethodChannel/native
  boundaries expose no request ID, cancel endpoint, cooperative callback, or
  bounded allocator. These results close only both Step 5 command gates; all
  target, renderer, cancellation/resource-release, allocator, and provenance
  blockers retain their previous labels.
- 2026-07-14: Task 10 Meshopt cooperative-timeout RED first failed compilation
  because `MeshoptDecodeControl`, `control`, and the deadline exception did not
  exist. Initial GREEN passed the two-file 17-test set. Five deliberate
  checkpoint-removal REDs then reported `meshoptDecodeComplete` instead of the
  exact TRIANGLES, INDICES, and three filter stages; restoring the bounded
  checkpoints passed 13/13 decoder tests. Removing the start checkpoint made
  the zero-timeout test fail at completion, and removing success commit made
  tracker accounting remain `3` instead of `7`; both passed after the minimal
  behavior was restored. Capability RED rejected the old `not enforced`
  Meshopt row before exact source fingerprints and generated documentation were
  updated. Independent review found one Important untested
  `decoderWork: started` branch. Its mutation-sensitive remediation first
  failed on missing `timeoutMicroseconds`, then failed `started` versus
  `notStartedForBufferView`; the restored conditional mapping and exact
  sub-millisecond field passed, and rereview returned `APPROVE` with no
  Critical, Important, or Minor findings. Final
  `flutter test test/meshopt_decoder_test.dart
  test/glb_meshopt_rewriter_test.dart
  test/capability_matrix_generation_test.dart` passed 33/33. The expanded set
  across decode budget, Meshopt decoder/rewriter/conformance, actual rewritten-
  GLB validator, capability generation, and ModelLoader passed 78 tests with
  three explicit GPU/Impeller skips. Focused `flutter analyze` over six changed
  Dart files reported no issues; `python3
  tools/generate_capability_matrix.py --check`, `python3 tools/repo_lint.py`,
  and `git diff --check` passed. No target runtime, packaging, release, external
  cancellation, deterministic collection, or codec-internal allocation
  evidence was produced.
- 2026-07-14: Task 10 native-timeout RED first hung on never-completing channel
  futures, so the same failure was made finite with delayed responses. Draco
  then failed the typed-timeout assertion and BasisU returned rewritten bytes
  instead of timing out. After initial GREEN, the pre-dispatch ordering RED
  failed with `channelCalls: 1` for `Duration.zero`; moving remaining-time
  calculation before `invokeMapMethod` passed. The shared-deadline test then
  proved a successful first Draco stage consumes the same budget before BasisU
  times out, and the late BasisU response cannot change the legitimate Draco
  intermediate reservation. The diagnostic-honesty RED failed until
  pre-dispatch expiry reported `nativeDispatch: notStarted`,
  `nativeResourceRelease: notApplicable`, and `lateResult: notApplicable`,
  distinct from the in-flight values. Final combined
  `flutter test test/glb_native_decoder_probe_test.dart
  test/capability_matrix_generation_test.dart` passed 33/33. The generator
  freshness check, `python3 tools/repo_lint.py`, and `git diff --check` passed;
  independent review returned `APPROVE`. Native work/resource release after an
  in-flight timeout remains explicitly unguaranteed. The expanded Task 10 root
  regression set across decode budget, Meshopt, Draco, BasisU, native probe,
  and ModelLoader passed 114 tests with three explicit Flutter GPU skips.
- 2026-07-14: Task 10 decoder-control evidence RED initially passed seven
  existing capability tests and failed the new blocker group. The first GREEN
  passed 8/8, but review demonstrated that alternative control names could
  bypass literal source markers. Injectable source-text mutation RED then
  failed because the validator did not exist; exact full-file SHA-256 checks
  made all Meshopt, pinned codec, root probe, and C++ bridge mutations fail
  closed. A subsequent platform mutation RED exposed omitted adapters; Draco
  and BasisU Android Java handlers, JNI translation units, and iOS Flutter
  plugin handlers are now fingerprinted too. Final independent rereview
  confirmed every alternative-control mutation is rejected and returned
  `APPROVE`. `flutter test test/capability_matrix_generation_test.dart` passed
  8/8; `python3 tools/generate_capability_matrix.py --check`,
  `python3 tools/repo_lint.py`, and `git diff --check` passed. This is blocker
  evidence only; timeout/cancellation/resource release remain unenforced and
  Task 10 Steps 1/3 remain open.
- 2026-07-14: Task 10 Step 4 RED passed five baseline tests and failed the two
  new historical-context/platform-label groups. During implementation,
  `python3 -m py_compile tools/generate_capability_matrix.py` caught a missing
  closing parenthesis before behavioral verification; the corrected generator
  then passed `flutter test test/capability_matrix_generation_test.dart` 7/7.
  Draco-only and BasisU-only aggregates for iOS Simulator, Android, and Web
  remain false for application, visual, and current target evidence, with
  `productionReady: false`. Independent review cross-checked the two Plan 013
  simulator records, confirmed their temporary artifacts are not durable,
  rejected 34 unsafe mutations, and returned `APPROVE` with no Critical or
  Important findings. `python3 tools/generate_capability_matrix.py --check`,
  `python3 tools/repo_lint.py`, and `git diff --check` passed. No current target,
  physical-device, packaging, release, or production-ready evidence is claimed.
- 2026-07-14: Task 10 Step 2 UASTC-RG RED failed three focused native tests on
  the missing official source/derived fixture. The reproducible fetch verified
  the exact Khronos CTS source and all other pinned files, and the derivation
  check proved only one-based bytes 118 and 136 differ. Initial GREEN passed
  `flutter test test/native_bridge_symbol_test.dart` 11/11. Review remediation
  intentionally changed the Android and iOS UASTC channel-0 fallback from
  `kRgb` to `kRg`; the focused profile test failed 0/1 at exact case 40 with
  `unsupportedKtx2Profile`/`ktx2DfdChannels`. After restoring channel-6 RG to
  `kRg` and channel-0 to `kRgb`, the focused test passed 1/1 and full BasisU
  package verification passed 12/12. The exact derivation `--check`,
  `python3 tools/repo_lint.py`, and `git diff --check` passed. Final rereview
  confirmed all 23 non-README fixture files are inventoried, Android/iOS sources
  are byte-identical, all Step 2 bullets are satisfied, and returned `APPROVE`.
  This is host conformance evidence only; target/runtime/device/packaging/
  release claims remain `not run` or unestablished.
- 2026-07-14: Task 11 Step 4 RED initially failed on the absent structured
  matrix source/generator. The first focused GREEN passed 1/1 and generated the
  nine-feature by four-target matrix from explicit selections. Review
  remediation then produced a semantic RED in which the baseline passed but
  four unsafe-mutation groups failed because the validator accepted unsupported
  Web promotion, incomplete production runtime, host-to-target leakage,
  upstream-blocker erosion, and unconstrained statuses. Final
  `flutter test test/capability_matrix_generation_test.dart` passed 5/5.
  Independent rereview additionally rejected 17 unsafe mutations, verified all
  12 exact texture-transform/specular/IOR blockers, confirmed native-only Draco
  and BasisU Web rows, and returned `APPROVE`. The Meshopt-only iOS Simulator
  aggregate remains `allApplied: false`, `allVisuallyVerified: false`,
  `allTargetEvidenceVerified: false`, and `productionReady: false`.
  `python3 tools/generate_capability_matrix.py --check`,
  `python3 tools/repo_lint.py`, and `git diff --check` passed. All 36 target
  rows remain `not run` for visual and target evidence, so Task 11 and M5 remain
  open.
- 2026-07-14: Task 11 Step 2 contract RED initially failed because
  `plan014_capture_contract.mjs` was absent; its first GREEN passed 2/2. The
  complete-evidence RED then failed on the missing evidence export before 4/4
  passed. An npm-source correction RED failed 3/4 while replacing the Three.js
  `r167` tag commit with `three@0.167.1` registry `gitHead`
  `42a2f6aac8cffebb29524d68eb7136a756f15960`; GREEN returned to 4/4. The
  manifest RED failed the focused Flutter suite 1/2 until exact reference-only
  capture metadata was added; exact-host remediation also failed 1/2 before
  `darwin 25.5.0` / `arm64` / `Apple M2` was recorded. Final focused Flutter
  passed 2/2. Repeated real capture runs passed all 4 views with hashes front
  `e83a2fcaac4be1f8e22762c4729928ffdd99ad8ada27ad466e085a5eda14eab9`,
  left `36a89eb64369a36c1b2c00e03bcc4b6a8a9b5567bdbd11d2414c105f466e0203`,
  right `3af9c2ba3487f0aac818dcbde5cde04fb3ef8cf734df4ff86c2853a34f2cd99c`,
  and back `fde6520710a6f32aff4d4efaeaeeaefef40312e8fea5730698d1457ce1381e05`.
  Independent review reproduced those hashes, returned `APPROVE`, and its one
  Minor same-length SHA-drift coverage note was closed with Node still 4/4.
  `python3 tools/repo_lint.py` and `git diff --check` passed; no Puppeteer or
  remote-debugging Chrome process remained. These are local Three.js
  directional-reference results only. All Flutter target evidence remains
  `not run`, runtime/release evidence remains unestablished, and Step 2, Task
  11, and M5 remain open.
- 2026-07-14: Task 11 Step 1 provenance RED failed 0/1 before the immutable
  fixture records and staging tool existed. GREEN passed 1/1 in
  `test/material_extension_fixture_provenance_test.dart`; metadata verification
  passed all 6 records. `--fetch-khronos` fetched and verified all 5 official
  Khronos assets and license files at the pinned commit. A1B32 staging passed
  for the exact 2,809,824-byte local input with SHA-256
  `a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592`.
  Its fresh pinned-validator result contains 0 errors, 6 warnings, 26 infos,
  and 0 hints; the two `IMAGE_FEATURES_UNSUPPORTED` and four
  `MESH_PRIMITIVE_GENERATED_TANGENT_SPACE` warnings are pinned by exact
  severity/code/message/pointer and block acceptance pending target/visual
  evaluation. Permission/count-disposition remediation RED failed 0/1, then
  passed 1/1; exact-message remediation RED also failed 0/1, then passed 1/1.
  `python3 tools/repo_lint.py` and `git diff --check` passed. Final independent
  rereview reproduced the validator warning identities and returned `APPROVE`
  with no Critical or Important findings. This is host fixture-provenance and
  source-structure evidence only. A1B32 redistribution and reproducible public
  source remain unestablished; renderer/runtime/target/release evidence remains
  unestablished or `not run`, so Step 1, Task 11, and M5 remain open.
- 2026-07-14: Task 11 Step 3 durable-report RED failed 0/4 on three absent
  normalized reports plus absent manifest provenance. The exact-gated refresh
  `FSV_UPDATE_GLTF_REWRITE_REPORTS=1 flutter test
  test/rewritten_glb_validator_test.dart` and the default read-only rerun both
  passed 4/4. Durable report SHA-256 values are Meshopt
  `c1069c789c608030499a13138ba87f3b9991726901205c9e312c8349c91894cc`,
  Draco
  `baf1a623bdd7d08ce65b7f98204f686ecd68fc00891ba4d0f1b19351c07126bb`,
  and BasisU
  `e71a5632b9d5a45b0078d648224642b6269b82ff08aa753f64588789b1e6db5d`;
  rewritten GLB SHA-256 values are respectively
  `676271e50ce235f349c01749613e7bfade4f5720cff72d7803a272f8ef41e549`,
  `ed046b12e6be838c8702a631edfe6807bbc8380dc3d15ca31977ec930487842b`,
  and
  `3bbea2f9c2e67bd5cfc34df2c775675780d5c1c4d48b72cc46cc210453dc0ffb`.
  The Node validator contract passed 3/3, root analysis passed, repo lint and
  diff check passed, and `bash tools/run_checks.sh` passed 456 tests with 16
  explicit GPU/visual skips. Review remediation provenance RED failed 3/4
  before the BasisU codec record distinguished official upstream source SHA
  `27fda5a2330831704a7adcf254b852c6df5081258dcc1e42283a936030b6f01f`
  from noticed vendored source SHA
  `e7af01b01b33dbcfbbda9b9365be308347ee45e87b7fbd7bf65cd215b1e07ba5`.
  The 28-file source manifest SHA is
  `1d5514363ae26035bc28c9c324acef7100df87220f3511436e595b08257b145e`
  and its entries all passed; the local-modification record SHA is
  `a72fdacfac7653a4da386ac8340cf85587380252e77b42de781eb36e8845676d`.
  Focused GREEN passed 4/4 after both provenance remediation and the final
  whitespace cleanup. Final independent rereview returned `APPROVE` with no
  findings. Target runtime/rendering/device/packaging/release evidence remains
  `not run` or unestablished, so Task 11 and M5 remain open.
- 2026-07-13: Task 11 Step 3 BasisU RED failed the focused root test 0/1 on
  the absent tracked native output runner. GREEN evidence uses official CTS
  fixture SHA-256
  `27484bc9b6e062acf0d6478df1b3ad62f6b6f32b923539c93353e535b572b0e4`
  and actual PNG SHA-256
  `e4df96db13158a2722ad9aad3ec8dd84dcfb9bc248b0c6721261b4777e41366b`.
  The initial focused root and package output tests passed 1/1 each; full
  three-codec validator passed 3/3, root BasisU rewriter 16/16, Node harness
  3/3, and the full BasisU package 12/12. Review remediation intentionally
  expected digest suffix `3660`; both root and package focused tests failed
  0/1 against actual suffix `366b`, then passed 1/1 each after restoring the
  exact digest. Root/package analyses, repo lint, and diff check passed. Final
  independent re-review returned `APPROVE`. The official report records zero
  errors/warnings/hints and one severity-2 `UNUSED_OBJECT` at
  `/bufferViews/2`. Evidence is `verified locally` on the host only; durable
  reports and target/runtime/device/packaging/release rows remain open or
  `not run`, and Step 3, Task 11, and M5 remain open.
- 2026-07-13: Task 11 Step 3 Draco RED failed the focused root test 0/1 on the
  absent tracked native runner. The first implementation then reached the
  official validator and exposed twelve `ACCESSOR_MIN/MAX_MISMATCH` errors.
  Bounds remediation plus focused mutation tests cover float POSITION, uint16
  indices, presence-only min/max updates, and absent-key preservation. A
  separate non-finite RED failed 0/1 with late generic
  `glbOutputConstruction`/`jsonEncode` handling; the final focused test passes
  NaN and positive/negative infinity through typed preflight rejection with no
  output or tracker commit. Actual bridge hashes are NORMAL
  `d333eac0e6dc715b7d0c9aefcd8a4378f4057950b6e22b935b5650c305d55573`,
  POSITION
  `42c6d27d2b968d3239276935e625b7645e7701fe55333b18a7e51126768ca16a`,
  and indices
  `1edf321f5b700a33dbf218f1ef4b1c5b841d6b36aef4227f2bdd189719664cec`.
  Final focused/root evidence: Draco validator 1/1; combined Draco rewriter
  plus validator 22/22; package native 6/6 and full package 7/7; Node harness
  3/3; root/package analyses clean; repo lint and diff check passed. The
  milestone harness passed 454 tests with 16 explicit GPU/Impeller skips.
  Independent review also reran the combined root 22/22 and package native
  6/6 commands and returned `APPROVE`. Those skips and all target/runtime/
  device/packaging/release rows remain `not run`; BasisU validation, durable
  reports, Step 3, Task 11, and M5 remain open.
- 2026-07-13: Task 11 Step 3 Meshopt RED passed through the pinned fixture and
  actual rewriter, then failed the focused Flutter test 0/1 with Node
  `MODULE_NOT_FOUND` for the not-yet-created validator runner. After adding the
  exact `gltf-validator@2.0.0-dev.3.10` lock and runner, the focused Flutter
  test passed 1/1 and reported zero errors/warnings/infos/hints. Review
  remediation first failed all three new Node tests: validation errors exited
  zero, warnings exited zero, and an empty asset label was accepted. The final
  Node suite passed 3/3, covering error JSON plus nonzero exit, exact warning
  allow-list behavior, pointer/offset normalization, and eight malformed-
  argument cases. `npm ci --ignore-scripts --prefix
  tools/gltf_rewrite_validation` installed exactly one package from the lock;
  both Node syntax checks, `python3 tools/repo_lint.py`, Dart format, and
  `git diff --check` passed. Final independent re-review returned `APPROVE`.
  Evidence is `verified locally` on the host only. Draco/BasisU validator runs,
  durable reports, target/runtime/device/packaging/release evidence, Task 11,
  and M5 remain open or `not run`.
- 2026-07-13: Task 10 BasisU channel-layout RED first failed the packed
  specular-color/factor Dart regression because the request was reported
  ambiguous and lacked `channelLayout`; the native runner separately failed to
  compile on the absent layout enum and request field. After implementation,
  focused Dart matrix tests passed exact base-color RGB/RGBA selection,
  emissive/normal/metallic-roughness/specular-color/clearcoat RGB, occlusion
  and transmission R, thickness G-derived RG, specular-factor A-derived RGBA,
  valid packed specular RGB+A, RGB overlap ambiguity, shared-image aggregation,
  transform neutrality, and unused structural-only behavior. Review
  remediation added a failing malformed-alpha regression before restricting
  alpha widening to exact `MASK`/`BLEND`; malformed string and non-string values
  now remain color+RGB in this bounded preflight. Native tests passed actual
  ETC1S/UASTC DFD-category positives and mismatches, strict platform metadata,
  direct-host defaults, and profile-then-layout-then-usage ordering before any
  reserve/init/start/pixel work. Final evidence: BasisU package 12/12; combined
  root BasisU rewriter/probe 37/37; root and package `flutter analyze` clean;
  `python3 tools/repo_lint.py`, `git diff --check`, fetch-script syntax, all 21
  fixture hashes, and four Android/iOS source-parity comparisons passed. Final
  independent review returned `APPROVE`. No new simulator/device/runtime/
  packaging/release evidence was run; compliant UASTC-RG and official DATA/RGB
  alias evidence, cancellation/timeouts, rewritten-GLB validator evidence,
  Task 10, and M5 remain open or `not run`.
- 2026-07-13: Task 10 BasisU usage-role RED first failed the focused Dart slot
  test because every request omitted `usageRole`; the native profile runner
  separately failed compilation with ten missing-enum/request-field errors.
  Final focused tests passed exact selected-slot mapping, shared texture/image
  aggregation, unused structural-only behavior, typed Dart diagnostic
  propagation, native color/non-color positive and mismatch cases, ambiguous
  usage, strict platform metadata parsing, and pre-allocation ordering. The
  BasisU package passed 12 tests, the root native-probe suite passed 19, and
  the combined root BasisU rewriter/probe command passed 35. Root and package
  analysis reported no issues; repo lint, diff check, fetch-script syntax,
  all 21 fixture hashes, and Android/iOS bridge/header/budget source parity
  passed. Independent review also ran `bash tools/run_checks.sh`, which passed
  448 tests with 16 explicit GPU/Impeller skips. Those skips and all target/
  runtime/device/release rows remain `not run`; channel-layout-to-slot
  matching, compliant UASTC-RG, cancellation/timeouts, rewritten-GLB validator
  evidence, Task 10, and M5 remain open.
- 2026-07-13: Task 10 BasisU structural-profile RED first failed because the
  nine official negative fixtures were absent, then the profile runner exited
  67 with `decodeFailed`/`basisuNativeDecode`/`ktx2Payload` for official
  UASTC+ZLIB instead of the expected typed supercompression diagnostic. Strict
  parsing exposed generic CTS BT709+LINEAR metadata in the direct-codec suite;
  only in-memory test copies were normalized, leaving every pinned byte and
  hash unchanged. The allocation-order RED then found `decoded_images.reserve`
  before the batch profile pass. Review remediation exited 74 with five
  missing R/RG and KVD diagnostics, then exited 75 on invalid UTF-8. The second
  review remediation also exited 75 on the missing leading-BOM diagnostic;
  official UASTC R and synthetic DFD-only UASTC_RG(6) sRGB cases already
  returned `unsupportedKtx2Profile`/`basisuProfilePreflight`/
  `ktx2DfdColorSpace`. Final profile output reported 14 negatives, three
  positives, and seven malformed cases. The BasisU package passed 12 tests,
  the root BasisU rewriter/probe command passed 32 tests, root and package
  analysis reported no issues, explicit repo lint/diff/fetch-script checks
  passed, all 21 hashes matched, and Android/iOS bridge sources were byte-
  identical. Final independent review also ran `bash tools/run_checks.sh`,
  which passed 445 tests with 16 declared GPU/Impeller skips. Those skips and
  all target/runtime/device/release rows remain `not run`; usage-role matching,
  compliant UASTC-RG, cancellation/timeouts, official rewritten-GLB validator
  evidence, Task 10, and M5 remain open.
- 2026-07-13: Task 10 Meshopt ModelLoader integration RED was the previously
  recorded combined command with 58 passes, three existing GPU skips, and one
  failure carrying the typed EXT ATTRIBUTES-v0 diagnostic. After replacing the
  stale v1 test helper with coherent v0 bytes, the focused test passed, the
  full ModelLoader file passed 28 tests with the same three skips, the original
  combined regression command passed 59 tests with the same skips, and
  independent review expanded the Task 10 command to 77 passes with the same
  skips. Implementer `flutter analyze`, `python3 tools/repo_lint.py`, and
  `git diff --check` passed; reviewer scoped diff-check also passed, while its
  redundant analyzer rerun was sandbox-blocked and is not counted as new
  evidence. Independent review returned `APPROVE`. This is test-fixture
  remediation only; KHR Meshopt runtime, target, release, Task 10, and M5 gates
  remain unchanged and open.
- 2026-07-13: Task 10 BasisU positive-conformance RED first failed because the
  pinned CTS license/fixtures were absent; the authored-mip runner then exited
  66 because the bridge silently decoded level 0, and a malformed two-level
  precedence runner exited 8 before Level Index validation was restored ahead
  of the capability diagnostic. Final focused verification passed all 11
  BasisU package tests, all 10 native-bridge tests, and all 31 combined root
  BasisU-rewriter/probe tests. Root and package `flutter analyze` reported no
  issues, `python3 tools/repo_lint.py` passed, `git diff --check` passed,
  fetch-script syntax passed, all 12 pinned hashes matched, and Android/iOS
  budget sources remained byte-identical. Independent review repeated the
  package 11-test and root 31-test suites before returning `APPROVE`. A broader
  root command produced 58 passes and three existing GPU skips, then failed the
  pre-existing ModelLoader Meshopt helper because it still emits EXT
  ATTRIBUTES v1; no Meshopt file was changed in this BasisU slice. Evidence is
  host-only. DFD/profile rules, cancellation/timeouts, validator, target
  runtime, packaging, release, full Task 10, and M5 remain open or `not run`.
- 2026-07-13: Task 10 Draco-conformance RED first failed because the pinned
  Khronos Box fixture was absent; the separate `TRIANGLE_STRIP` RED then called
  the native channel once instead of stopping at preflight. Final focused
  verification passed 14 native-probe tests, 32 combined Draco-rewriter/probe
  tests, and all seven Draco package tests; the package's six native-bridge
  tests independently re-ran the real vendored-codec compile/link comparison.
  Root and package `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, `git diff --check` passed, fetch-script
  syntax passed, and the three tracked fixture SHA-256 values plus the exact
  118-byte payload digest matched. Independent review re-ran eight focused
  Draco probe tests, all 32 combined root tests, and all six native-bridge
  tests before returning `APPROVE`. This is host direct-codec/wrapper evidence
  only. `TRIANGLE_STRIP`, BasisU conformance, validator, cancellation/timeouts,
  Android/iOS runtime, devices, packaging, release, full Task 10, and M5 remain
  unsupported, open, or `not run` as applicable.
- 2026-07-13: Task 10 Meshopt-conformance RED first failed because the official
  fixture files were absent, then failed exact comparison on the first
  TRIANGLES view because the official decoder cyclically rotated a triple while
  preserving order and winding. The first focused GREEN passed 16 tests, but
  independent review found two Important gaps and one Minor gap: runtime EXT
  tests used KHR-only v1 streams, quantization was not tied to a real semantic,
  and placeholder source references were incomplete. Remediation RED reproduced
  an EXT v1 stream incorrectly returning rewritten bytes and an absent official
  derivative helper. Final focused verification passed all 18 tests in
  `meshopt_decoder_test.dart`, `meshopt_conformance_test.dart`, and
  `glb_meshopt_rewriter_test.dart`; `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, `git diff --check` passed, fetch-script
  syntax passed, and all five pinned SHA-256 values matched. Independent
  re-review returned `APPROVE`. This is host direct-codec/wrapper evidence only;
  Draco/BasisU conformance, validator, cancellation/timeouts, Android/iOS/Web
  runtime, packaging, release, full Task 10, and M5 remain open or `not run`.
- 2026-07-13: Task 10 BasisU-native RED first failed because decoded image
  results lacked required width/height; native RED later showed the channel
  omitted budget/state and the pure preflight/adapters did not exist. Initial
  focused GREEN passed 67 root tests with three existing GPU skips and eight
  BasisU plugin/native tests; `bash tools/run_checks.sh` passed 437 root tests
  with 16 explicit GPU/Impeller skips. Independent review then reproduced an
  invalid 40-byte pseudo-KTX2 container passing preflight and found unchecked
  Android JNI request types. Remediation RED made the native runner exit 8
  because 40/79/103-byte truncations were accepted. Final focused verification
  again passed 67 root tests with the same three skips and eight plugin/native
  tests; root and plugin analyses reported no issues,
  `python3 tools/repo_lint.py` passed, `git diff --check` passed, and Android/
  iOS bridge/budget parity checks passed. The previously recorded post-change
  full harness remains 437 passed with 16 explicit skips. A second independent
  review returned `APPROVE` with no edits. Host fixture/compile evidence does
  not satisfy Android, iOS Simulator, physical-device, Web, packaging, release,
  or M5 gates; all remain `not run`/open. Full KTX2/DFD/mip conformance,
  validator, codec-internal memory, cancellation, timeout, and full Task 10
  evidence remain open.
- 2026-07-13: Task 10 Draco-native RED first showed the root channel omitted
  budget/state metadata, the sibling Dart API lacked budget parameters, and
  the pure native preflight sources did not exist. Initial focused GREEN passed
  39 root tests, 28 ModelLoader tests with three existing GPU skips, and five
  plugin/native tests. Independent review then found three Important gaps; the
  remediation RED reproduced one native channel call for a malformed extra
  accessor and failed native compilation for missing 64-bit component metadata
  and post-decode validation types/counters. Final focused verification passed
  68 root tests with three existing GPU skips and six Draco plugin/native tests;
  the compiled Android/iOS fake-codec allocation test passed for both byte-
  identical bridge/budget copies. Root and plugin analyses reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. After the
  remediation, `bash tools/run_checks.sh` also passed: repository lint passed,
  formatting checked 79 files with zero changes, dependency resolution
  completed, whole-root analysis reported no issues, and 435 tests passed with
  16 explicit GPU/Impeller skips. The skips and all post-change native target
  runtime remain `not run`; host compilation/runners do not satisfy Android,
  iOS Simulator, physical-device, packaging, release, or M5 gates. Pinned Draco
  internal allocation, cancellation, timeout, conformance, validator, BasisU
  native, and full Task 10 evidence remain open.
- 2026-07-13: Task 10 root budget-threading RED failed at compile time first
  because `GlbNativeDecoderProbe.decodeGlb` had no required budget/tracker
  contract and again because ModelLoader omitted the new required values. The
  first focused GREEN passed 71 tests with three existing GPU skips, but review
  found representation-dependent double accounting. Remediation RED then
  failed for the missing non-mutating output check, missing required accounting
  metadata, incomplete result constructors, and finally the Draco component
  exact-limit integration case that ModelLoader incorrectly rejected. Final
  focused verification passed 79 tests with the same three existing GPU skips;
  focused `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. A second
  independent review returned `APPROVE` with no file edits. The skips remain
  `not run`; no native preallocation enforcement, cancellation/resource,
  timeout, conformance, validator, platform runtime, packaging, release, or
  full Task 10/M5 evidence was produced.
- 2026-07-13: Task 10 BasisU-budget RED failed to compile because the rewriter
  lacked budget/tracker, aggregate native-output, and deterministic late-output
  APIs. The first focused GREEN passed 23 budget/BasisU tests and 25 probe/
  ModelLoader regressions with three existing GPU skips. Independent review
  reproduced two Important integration gaps despite those passing tests: a
  legal shared-image asset generated two native requests, and an unreferenced
  decoded image returned success without consuming budgets. The two focused
  remediation tests failed for those exact reasons before the patch. Final
  focused verification passed 50 tests with the same three existing GPU skips;
  focused `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. A second
  independent review returned `APPROVE` with no file edits. The three GPU tests
  remain `not run`; texture dimensions, native allocation/resource limits,
  official KTX2/DFD/mip conformance, cancellation/timeouts, validator,
  platform runtime, packaging, release, and full Task 10/M5 verification remain
  open or `not run`.
- 2026-07-13: Task 10 Draco-budget RED first failed to compile because the
  rewriter did not accept the shared budget/tracker contract. The first GREEN
  passed 20 focused tests, but independent review found three unaccepted
  correctness gaps: untouched authored attributes were not count-validated,
  cross-primitive reused accessors double-consumed vertex budget, and the real
  tracker committed before output construction. Four focused remediation
  tests then failed for those exact behaviors before the patch. Final focused
  verification passed all 24 tests in `glb_decode_budget_test.dart` and
  `glb_draco_rewriter_test.dart` with zero skips/failures; focused
  `flutter analyze` reported no issues, `python3 tools/repo_lint.py` passed,
  and `git diff --check` passed. A second independent review returned
  `APPROVE` with no file edits. This is Dart-boundary evidence only: native
  allocation/resource limits, official fixtures/decoder comparison,
  cancellation/timeouts, validator, platform runtime, packaging, release, and
  full Task 10/M5 verification remain `not run` or open.
- 2026-07-13: Task 10 shared-budget RED first failed to compile because the
  budget types and Meshopt/ModelLoader parameters did not exist. The first VM
  GREEN exposed by independent review was not accepted: a Chrome run proved
  the large bit-shift test became zero on Web, and review identified unsafe
  failure arithmetic, unchecked runtime limits, pre-budget BIN padding, and
  missing exact/aggregate coverage. The remediation RED failed on the new
  max-exact/overflow APIs and malformed/invalid metadata expectations on both
  VM and Chrome. Final focused verification passed 43 VM tests with three
  existing GPU/Impeller skips and passed all seven budget tests on Chrome.
  `flutter analyze` reported no issues, `python3 tools/repo_lint.py` passed,
  `git diff --check` passed, and the post-Chrome process check found no leftover
  Chrome/test processes. The three GPU skips remain `not run`; no Draco/BasisU
  native bridge, conformance, validator, target, packaging, release, or full
  Task 10 evidence was produced. The full milestone harness is reserved for
  the M5 gate.
- 2026-07-13: After independent review approved the bounded Task 9 audit,
  `bash tools/run_checks.sh` passed from the current working tree: repository
  lint passed, Dart formatting checked 77 files with zero changes, dependency
  resolution completed, `flutter analyze` reported no issues, and the full
  Flutter suite passed 374 tests with 16 explicit skips. The skips are the
  pinned specular/opaque-IOR renderer blocker plus GPU/Impeller, generated-
  shader, visual, and target gates; all remain `not run` and none support a
  transmission/volume renderer or release claim. A separate
  `python3 tools/repo_lint.py` run passed, `git diff --check` passed, and
  `git status --short --branch` showed 17 modified Plan 014 implementation/
  documentation files plus deferred Plans 015 and 016 on `main`; nothing was
  staged. Task 9 Step 2 and the conditional deferred disposition are complete,
  while Step 1 and Steps 3-5, Task 9, M4, all post-change target evidence, and
  the v1 glass release gate remain partial/`blocked`/`not run`.
- 2026-07-13: After independent review approved the bounded Task 8 audit,
  `bash tools/run_checks.sh` passed from the current working tree: repository
  lint passed, Dart formatting checked 77 files with zero changes,
  `flutter analyze` reported no issues, and the full Flutter suite passed 356
  tests with 16 explicit skips. The skips are the pinned specular/opaque-IOR
  renderer blocker plus GPU/Impeller shader and visual gates; all remain
  `not run` and none support a clearcoat renderer or release claim. A separate
  `python3 tools/repo_lint.py` run passed, `git diff --check` passed, and
  `git status --short --branch` showed only the sixteen Plan 014 implementation/
  documentation files plus the new deferred Plan 015 on `main`; nothing was
  staged. Task 8 Step 2 and the conditional deferred disposition are complete,
  while Steps 1 and 3-5, Task 8, M4, all post-change target evidence, and the
  v1 clearcoat release gate remain partial/`blocked`/`not run`.
- 2026-07-13: Task 8 began with a two-test RED run: the candidate still
  contained `ClearcoatDirectionalHighlight`, and double-sided PBR clearcoat
  silently created an overlay. The first GREEN passed 2 tests, but independent
  review found the generated lit `.fmat` still double-counted its manual lobe
  and engine lighting. A compiler-backed four-test RED then failed on the
  manual BRDF/IBL/direct/shadow/emissive path and wrong coat inputs; the
  five-test GREEN proved one generated `EvaluateLighting(material)` and no
  authored lighting path. The second review found base-normal suppression. A
  ten-test RED failed on the unused base-normal calculation, nulled source
  normal, and `.35` scales; the same focused command then passed 10 tests after
  removal. Final independent re-review passed 19 focused tests with no
  Important findings. The exact Task 8 command
  `flutter test test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/material_extension_native_applier_test.dart`
  passed 59 tests with 12 explicit GPU/Impeller skips. Backend plus adapter
  suites passed 75 tests with 13 explicit skips; the controller material suite
  passed 36 tests. Focused analysis reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The skips
  and absent post-change reference/target captures remain `not run`; the
  milestone harness is reserved for the approved-slice gate below.
- 2026-07-13: After independent review approved the complete Task 7 safe
  slice, `bash tools/run_checks.sh` passed from the current working tree:
  repository lint passed, Dart formatting checked 77 files with zero changes,
  `flutter analyze` reported no issues, and the full Flutter suite passed 355
  tests with 16 expected skips. The skips are the explicit specular/opaque-IOR
  renderer blocker plus GPU/Impeller-gated shader and visual tests; they remain
  `not run` evidence and do not support a production claim. A separate
  `python3 tools/repo_lint.py` run passed, `git diff --check` passed, and
  `git status --short --branch` showed only the fifteen Plan 014 files already
  in scope on `main`; nothing was staged. Task 7 Steps 1-2 remain partial and
  unchecked; Steps 3-6, Task 7, M3, A1B32, and Plan completion remain
  `blocked`/`not run`.
- 2026-07-13: The approved Task 7 diagnostic cleanup RED command
  `flutter test test/material_patch_test.dart --name 'valid unsupported opaque IOR remains a capability diagnostic'`
  failed once because the diagnostic still used transmission/glass wording.
  After the bounded change, the same test passed; the full material-patch file
  passed 29 tests; and the exact Task 7 five-file command passed 109 tests with
  one explicit renderer-blocker skip. The skip remains `not run` renderer
  evidence. `python3 tools/repo_lint.py` and `git diff --check` passed.
  Routing/capability behavior and the Task 7/M3/A1B32 blocked status are
  unchanged.
- 2026-07-13: Task 7 first-review remediation RED used the four-file focused
  command filtered to five new regression names and produced five expected
  failures: two intrinsic-validation precedence failures, one transmission/
  volume group-loss failure, one non-native specular silent success, and one
  package-local opaque-IOR controller/adapter silent success. After the
  bounded fix, the same command passed five tests. The exact Task 7 five-file
  command passed 109 tests with the same one explicit renderer-blocker skip.
  `flutter test test/viewer_controller_material_test.dart` passed 36 tests,
  including no persistence/render request or PBR mutation for package-local
  opaque IOR, preserved candidate/native extension composition, and a positive
  renderer-native opaque-IOR setter path. The skipped acceptance remains
  `not run` and proves no rendering behavior. `flutter analyze` reported no
  issues, `python3 tools/repo_lint.py` passed, and `git diff --check` passed.
  The milestone harness remains reserved for post-review. Task 7 Steps 1-2
  remain partial and unchecked; Steps 3-6, Task 7, M3, and A1B32 remain
  `blocked`/`not run`.
- 2026-07-13: Task 7 safe-slice RED used
  `flutter test test/material_patch_test.dart test/glb_material_extension_reader_test.dart`
  and ended with 36 passes plus four expected failures: public validation
  returned no diagnostic for invalid specular-color shape/domain or invalid
  IOR, and the GLB reader retained range-invalid specular and opaque-IOR
  groups. After the bounded validation/parser change, the same two-file suite
  passed 40 tests. The final exact Task 7 command
  `flutter test test/material_patch_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_adapter_material_test.dart test/material_extension_native_applier_test.dart`
  passed 104 tests with one explicit skipped renderer-acceptance test. The skip
  records the unavailable pinned specular/IOR shader contract and supplies no
  runtime, visual, or target evidence. CPU coverage verifies the normative
  factor/color/IOR domains, typed rejection without clamping, invalid authored
  group isolation, opaque IOR family classification, per-target
  diagnostic-only/not-run policy labels, and existing pre-mutation native
  diagnostics. The first sandboxed `flutter analyze` attempt could not update
  Flutter SDK cache metadata outside the workspace; the authorized rerun
  reported no issues. `python3 tools/repo_lint.py` passed and
  `git diff --check` passed. `bash tools/run_checks.sh` is reserved for the M3
  gate after independent review and was not run by this safe slice. No A1B32,
  GPU, visual, iOS Simulator, physical iOS, Android material-rendering, Web,
  packaging, release, or production evidence was produced. Task 7 Steps 1-2
  remain partial and unchecked; Steps 3-6, Task 7, M3, and Plan 014 remain
  `blocked` on upstream renderer support.

- 2026-07-13: After independent review approved the post-fix9 Task 6 safe
  slice, the milestone-gate command `bash tools/run_checks.sh` was rerun from
  the current working tree and passed: repository lint passed, Dart formatting
  checked 77 files with zero changes, `flutter analyze` reported no issues,
  and the full Flutter suite passed 339 tests with 15 expected
  GPU/Impeller-gated skips. A separate `python3 tools/repo_lint.py` run passed,
  `git diff --check` passed, and `git status --short --branch` showed only the
  ten Task 6/Plan 014 files already in scope on `main`; nothing was staged.
  The first sandboxed harness attempt failed before formatting/tests because
  Flutter could not update its SDK cache outside the workspace; the authorized
  rerun is the passing evidence above. These CPU/local checks do not supply
  GPU `MaterialParameters`, Glorvia UV-transform, visual, simulator, physical
  device, Android material-rendering, Web, release, or production evidence.
  Task 6 Steps 4-6 and M2 therefore remain `blocked` despite the green safe
  slice.
- 2026-07-13: Task 6 ninth re-review added two controller-to-adapter RED
  regressions before production changes. The success case expected an active
  clearcoat replacement config containing new base-color alpha/texture and
  occlusion texture but observed only the original config; the forced
  replacement failure expected one typed diagnostic but observed none while
  the unguarded core path remained available. The exact focused command
  `flutter test test/viewer_controller_material_test.dart --name 'active clearcoat composes base alpha and occlusion core deltas|active clearcoat core input reconfiguration failure stays atomic'`
  first failed both tests, then passed two tests after the bounded
  pre-mutation reconfiguration fix. The clearcoat-focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart --plain-name 'clearcoat'`
  passed 34 tests with four GPU/Impeller-gated skips. The exact four-file
  command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 114 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies
  active-config merge, new base/occlusion texture identity, base-factor alpha
  uniform composition, later sparse-delta retention, controller-store/live-
  material agreement, and shader-failure atomicity. `flutter analyze` reported
  no issues, `python3 tools/repo_lint.py` passed, and `git diff --check` passed.
  The full post-fix9 `bash tools/run_checks.sh` harness remains pending review;
  no milestone or Task 6 closure is claimed. No GPU `MaterialParameters`,
  Glorvia, UV-transform, visual, simulator, physical iOS, Android material, or
  Web evidence was produced by this fix, and the package-local path remains
  `candidate-only`.
- 2026-07-13: Task 6 eighth re-review added three RED regressions before
  production changes. The first combined omitted-scale case expected the
  snapshotted source scale `0.8` but observed the twice-attenuated live value
  `0.098`; active B/`0.5` followed by core-only C with omitted scale restored
  `0.175` instead of logical `0.5`; and a sparse factor-zero delta lost prior
  clearcoat roughness (`null` instead of `0.25`) before later texture
  assertions. After the bounded logical-scale and active-config merge fix, the
  exact focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/viewer_controller_material_test.dart --name 'combined clearcoat normal without scale attenuates prior scale once|active clearcoat core normal without scale retains logical scale|sparse clearcoat deltas preserve live config and persisted intent'`
  passed three tests. The clearcoat-focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart --plain-name 'clearcoat'`
  passed 32 tests with four GPU/Impeller-gated skips. The exact four-file
  command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 112 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies
  omitted-scale single attenuation, logical C/`0.5` zero/positive behavior,
  sparse factor/roughness/normal-texture persistence, sampler-bearing texture
  identity, controller-store/live-overlay agreement, prior failure atomicity,
  and reset to A. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. An
  independent reviewer ran the full pre-fix8 `bash tools/run_checks.sh`
  harness at 334 passes with 15 gated skips; that earlier run is not post-fix8
  evidence, so the final harness remains pending. No GPU `MaterialParameters`,
  Glorvia, UV-transform, visual, simulator, physical iOS, Android material, or
  Web evidence was produced by this fix.
- 2026-07-13: Task 6 seventh re-review added three composition/atomicity
  regressions before production changes. The combined B/`0.5` then
  factor-zero test exposed restoration of model A, the active-coat core-only
  C/scale test exposed the baked `fromPixels` path instead of a second raw
  `fromImage` load, and forced replacement-shader failure returned no typed
  diagnostic. After separating reset-original and logical state and adding
  pre-mutation overlay reconfiguration, the exact focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/viewer_controller_material_test.dart --name 'clearcoat zero retains the latest combined logical source normal|active clearcoat composes a later core-only logical normal delta|active clearcoat core-normal reconfiguration failure stays atomic|resetPart restores model normal after clearcoat zero retains delta'`
  passed four tests. The prior command
  `flutter test test/flutter_scene_adapter_material_test.dart --plain-name 'candidate clearcoat'`
  passed four tests. The exact four-file command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 109 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies
  logical B/C composition, factor-zero restoration, literal controller reset
  to immutable A, and failure atomicity without changing candidate maturity.
  The 12 gated tests remain `not run`; no GPU `MaterialParameters`, Glorvia,
  UV-transform, visual, simulator, physical iOS, Android material, or Web
  evidence was produced. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The full
  milestone harness was not run because Task 6/M2 closure gates remain
  blocked.
- 2026-07-13: Task 6 sixth re-review added two sequential backend regressions
  before production changes. The focused positive-then-zero command failed
  because the expected preserved `RenderTexture` source normal was still
  `null`; the focused positive-then-positive replacement command failed for
  the same reason in the second overlay config. After the bounded state
  resolution and early-return reorder, each focused command passed one test,
  and `flutter test test/flutter_scene_adapter_material_test.dart --plain-name 'candidate clearcoat'`
  passed four prior positive, zero-factor, failure-atomicity, and exactly-once
  scaling tests. The exact four-file command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 105 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies
  stateful factor-zero source-normal/scale restoration and replacement-overlay
  reuse without double attenuation while retaining the fifth re-review
  invariants. The 12 gated tests remain `not run`; no GPU
  `MaterialParameters`, Glorvia, UV-transform, visual, simulator, physical iOS,
  Android material, or Web evidence was produced. `flutter analyze` reported
  no issues, `python3 tools/repo_lint.py` passed, and `git diff --check` passed.
  The full milestone harness was not run because Task 6/M2 closure gates remain
  blocked.
- 2026-07-13: Task 6 fifth re-review RED evidence used the plain-name
  controller-to-adapter test and showed an explicit authored alpha mask
  replacing the native PBR object, leaving the original core factors unchanged
  and breaking the later native contract. After correcting only a test-fixture
  sampler constructor, the combined clearcoat RED failed because standard core
  mutation restored a source normal that the active clearcoat invariant
  requires to remain suppressed. After the bounded implementation, the exact
  four-file command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 103 tests with 12 GPU/Impeller-gated skips. The focused reset command
  `flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name 'clearcoat keeps a bounded source flake normal and restores it'`
  passed one test. CPU coverage verifies native PBR identity across authored
  alpha then independently supported/unsupported extension groups, ordinary
  PBR alpha replacement, positive/zero clearcoat source-normal handling,
  exactly-once raw overlay normal scale, and original normal/scale restoration.
  The 12 gated tests remain `not run`; no GPU `MaterialParameters`, Glorvia,
  UV-transform, visual, simulator, physical iOS, Android material, or Web
  evidence was produced. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The full
  milestone harness was not run because Task 6/M2 closure gates remain
  blocked.
- 2026-07-13: Task 6 fourth re-review behavioral RED used
  `flutter test test/viewer_controller_material_test.dart test/flutter_scene_adapter_material_test.dart`.
  After correcting test-only fixture construction, it ended at 58 passes and
  five expected failures: an authored clearcoat call still contained prior
  IOR, the real controller-to-adapter renderer-native fixture received no
  clearcoat, clearcoat left the base factor unchanged, transmission returned no
  alpha diagnostic, and package-local clearcoat returned no visibility
  diagnostic. A separate plain-name RED then proved existing source alpha-mask
  state returned no `transmissionCoreInputsUnsupported` limitation. After the
  bounded implementation, the exact four-file command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`
  passed 102 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies
  independent authored group delivery through the real adapter path,
  unsupported-group isolation, clearcoat core application only after overlay
  success, incoming/source transmission alpha rejection before loading,
  visibility preflight before geometry mutation, prior exactly-once normal
  scaling, and prior native specular/mixed-patch rejection. The 12 gated tests
  remain `not run`; no GPU `MaterialParameters`, Glorvia, UV-transform, visual,
  simulator, physical iOS, Android material, or Web evidence was produced.
  `flutter analyze` reported no issues, `python3 tools/repo_lint.py` passed, and
  `git diff --check` passed. The full milestone harness was not run because
  Task 6/M2 closure gates remain blocked.
- 2026-07-13: Task 6 third re-review RED evidence used
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`.
  It reported the absent CPU scene-view injection seam and showed advertised
  native scalar specular/specular-color and direct mixed core/native patches
  returning success. After the bounded implementation, the first full run
  passed 95 tests, skipped 12, and failed only two tests because their setup
  constructed a real `flutter_scene.Scene`, which requires Impeller. Replacing
  that test-only setup with an injected empty `List<RenderView>` left the
  production loaded-scene path unchanged. The exact four-file command then
  passed 97 tests with 12 GPU/Impeller-gated skips. CPU coverage verifies raw
  candidate normal loading, exactly-once transmission and clearcoat uniform
  scaling, transmission source-scale fallback, typed native specular rejection,
  and mixed core/native atomicity with no texture load, setter, or target
  mutation. The 12 gated tests remain `not run`; no GPU `MaterialParameters`,
  Glorvia, UV-transform, visual, simulator, physical iOS, Android material, or
  Web evidence was produced. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The full
  milestone harness was not run because Task 6/M2 closure gates remain
  blocked.
- 2026-07-13: Task 6 second re-review RED evidence used
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart test/material_extension_native_applier_test.dart`.
  After correcting test-only setter instrumentation, it failed on advertised
  native extension texture bindings being accepted, the obsolete
  transmission next-step guidance, existing PBR state not being diagnosed,
  direct native application returning success, and the missing faithful
  preprocessed resolver outcome API. After minimal implementation, the same
  four-file command passed 90 tests with 12 GPU/Impeller-gated skips. CPU
  coverage verifies sequential/imported-shape source-state rejection with no
  target mutation, field-origin details, mixed native patch atomicity, zero
  native setter calls for all extension texture slots, shared native
  preflight/application behavior, and actual unavailable-source resolver/
  setter diagnostic mapping. The GPU `MaterialParameters` binding tests remain
  `not run`. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. No
  milestone harness or renderer/target capture was run because Task 6/M2
  closure gates remain blocked.
- 2026-07-13: Task 6 review-remediation RED evidence: after correcting only
  test construction, the exact focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart`
  failed at compile time on the missing injectable adapter debug arguments and
  missing preprocessed-texture binding/diagnostic helpers. After the minimal
  implementation, its first run reached the new tests and failed only because
  the plain test process could not create a real `flutter_gpu.Texture` without
  Impeller. Those two actual-`MaterialParameters` tests were retained behind
  the repository's existing GPU flag and classified `not run`. The final
  exact focused command passed 83 tests with 12 GPU/Impeller-gated skips.
  CPU-verified coverage includes every sampler filter (including linear
  magnification), resulting standard PBR slot sampler state, binding-only
  feature routing, clearcoat occlusion/emissive forwarding, atomic
  transmission-core rejection, and typed unavailable-sampled-texture
  diagnostics. Clearcoat `MaterialParameters` sampler binding is not claimed
  as `verified locally`. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The full
  milestone harness was not run because Task 6/M2 closure gates remain
  blocked.
- 2026-07-13: Task 6 safe-slice RED evidence: the exact focused command
  `flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart test/viewer_controller_material_test.dart`
  failed at compile time because `FlutterSceneTextureFactory`,
  `debugFlutterSceneTextureBindingPlan`, `debugLoadTextureBinding`, and
  `flutterSceneTextureBindingDiagnostic` did not exist. After the minimal
  implementation and a test-fixture PNG correction, the same exact command
  passed 77 tests with 10 existing GPU/Impeller-gated skips. The focused suite
  verifies sampler mapping and wrapper construction-path routing only; the 10
  skips remain `not run`, per-slot UV transform rendering is `blocked`, and no
  Glorvia, visual, physical iOS, Android material-rendering, or Web evidence
  was produced. `flutter analyze` reported no issues,
  `python3 tools/repo_lint.py` passed, and `git diff --check` passed. The full
  milestone harness is reserved for the controller's M2 gate and was not run
  by this safe slice.
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
