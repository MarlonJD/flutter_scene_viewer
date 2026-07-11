# Experimental Material Extension Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox syntax for tracking.

## Goal

Build an opt-in, in-repository material extension backend with separate base
material families for opaque PBR, masked cutout, translucent blend
transparency, and realistic glass, plus an opaque-family material/effect mask
path for channel-packed regional material controls. Prove a real
transmission/glass path without waiting for upstream `flutter_scene` importer
support, while keeping the default v1 API honest: unsupported
transmission/glass and clearcoat requests still return diagnostics unless the
selected base material family can actually render them.

## Architecture

The default viewer path remains adapter-backed and diagnostic-only for
`KHR_materials_transmission`, `KHR_materials_ior`, `KHR_materials_volume`, and
`KHR_materials_clearcoat`. A new opt-in material extension policy enables an
internal backend that uses public `flutter_scene` primitives:
`ShaderMaterial`, `RenderTexture`, `RenderView.layerMask`, `Node.layers`, and
Flutter GPU shader bundles.

The first shippable slice locks the material family split before adding more
features. A primitive is assigned to exactly one base material family at a
time:

- opaque base material: core PBR with no alpha discard and no alpha blend;
- material/effect mask: an opaque-family data map, not a base material family,
  used to drive regional color, roughness, coat, dirt, paint, or similar
  material parameters from packed texture channels;
- masked cutout base material: alpha-test/discard for authored cutout use only,
  not for material/effect masks, part visibility, or partial object hiding;
- translucent blend base material: current alpha-blended transparency, with no
  refraction or IOR claim;
- realistic glass base material: transmission/refraction/Fresnel/IOR/volume
  behavior, implemented as a separate shader/render-texture path.

Opaque, masked cutout, translucent blend, and realistic glass behavior must not
live inside one viewer material family or be switched by mutating one material
instance in place. If a patch changes the family, the adapter restores the
original family state and creates the destination family material explicitly.
Material/effect masks stay inside the opaque family because they do not discard
pixels or blend; they only route packed channel values to material parameters.
Transmission becomes a real screen-space refraction implementation: render the
opaque/background scene to a `RenderTexture`, exclude realistic-glass
primitives from that background view via layers, and bind the render texture to
a glass material that uses transmission, IOR, thickness, attenuation,
roughness, and normal inputs. Clearcoat uses the same backend boundary but does
not fall back to roughness tweaks; it becomes supported only when a shader
implements a second clearcoat specular lobe.

## Tech Stack

- Dart and Flutter package code in `lib/src`.
- `flutter_scene` 0.18.1 public APIs: `ShaderMaterial`, `RenderTexture`,
  `RenderView`, `Node.layers`, `RenderView.layerMask`, and
  `gpu.loadShaderLibraryAsync`.
- Flutter GPU shader asset pipeline through `flutter_scene/build_hooks.dart`
  and `.fmat` or `.shaderbundle` output, verified before visual claims.
- Existing repo test harness: `flutter test`, `bash tools/run_checks.sh`, and
  `python3 tools/repo_lint.py`.

## Assumptions

- This plan does not replace `flutter_scene` with a custom renderer. It adds a
  targeted material-extension backend above public `flutter_scene` scene,
  material, view, and render-texture APIs.
- Opaque, masked cutout, translucent blend, and realistic glass are separate
  base material families. They may share source factors and texture assets, but
  they must not share one mutable runtime material object or one mixed pipeline
  contract.
- Masked cutout may be backed by alpha-test/discard behavior in `flutter_scene`,
  but the viewer treats it as a separate family because it has different shader
  behavior, quality risks, and performance characteristics from opaque PBR. It
  is not a visibility system; object or part show/hide must use node/part
  visibility or authored geometry splits.
- Material/effect masks are not alpha cutout. They are opaque-family packed
  data maps for regional material parameter selection, such as paint regions,
  dirt, roughness variation, coat intensity, or other shader inputs. V1 handles
  the material data model and runtime validation; KTX2 / `KHR_texture_basisu`
  compression and authoring workflow tooling remain a separate V2 optimization
  track.
- The current installed `flutter_scene` importer does not preserve or render
  the required material extensions, so authored extension data must be read
  from GLB JSON by this package before it can be applied.
- `flutter_scene` preserves GLB node names, node hierarchy, mesh primitive
  order, and primitive material assignment closely enough that a GLB extension
  index can map authored material extension data to `PartAddress`.
- Texture-bearing runtime and authored extension inputs require
  `TEXCOORD_0` / UV0. UV1 is not used and UVs are never generated.
- The experimental backend is allowed to require Flutter GPU / Impeller and to
  report `unsupportedMaterialFeature` on unsupported platforms or missing
  shader assets.
- The first transmission implementation can be screen-space refraction with
  documented limits. It must visibly sample the scene behind the glass and use
  IOR/thickness/attenuation inputs; base alpha alone is not sufficient.

## Non-goals

- No alpha-only glass claim.
- No mixed opaque/masked/translucent/glass material instance that changes GPU
  pipeline behavior by toggling alpha fields in place.
- No alpha-mask use as a shortcut for object-part visibility, partial hiding,
  clipping, or configurator show/hide behavior.
- No treating material/effect masks as visibility masks. They must not discard
  pixels, switch render pipeline family, or hide parts.
- No clearcoat approximation by lowering roughness, raising environment
  intensity, or changing base PBR constants.
- No full path tracing, caustics, multi-bounce refraction, nested glass
  correctness, order-independent transparency, or CAD/UV/tangent generation.
- No VR, AR, OpenXR, WebXR, ARKit, or ARCore work.
- No removal of existing HDR/EXR or Poly Haven environment code.
- No public production-ready claim from local visual smoke alone; broader
  backend/platform evidence is still required.

## File structure

- Modify `lib/src/material_patch.dart`
  - Add `MaterialAlphaMode` and serializable `alphaMode` / `alphaCutoff`.
  - Make validation capability-aware so the default path rejects glass and
    clearcoat, while an opt-in backend can accept supported fields.
- Create `lib/src/internal/material_base_family.dart`
  - Defines internal `MaterialBaseFamily.opaque`,
    `MaterialBaseFamily.maskedCutout`,
    `MaterialBaseFamily.translucentBlend`, and
    `MaterialBaseFamily.realisticGlass`.
  - Contains the resolver that maps a `MaterialPatch` and authored material
    extension intent to exactly one destination family.
- Create `lib/src/material_effect_mask.dart`
  - Public value types for opaque-family packed channel masks.
  - Defines channel mappings such as red, green, blue, and alpha to regional
    material parameters.
- Create `lib/src/internal/material_effect_mask_resolver.dart`
  - Validates effect-mask channel use, UV0 requirements, and opaque-family-only
    semantics before the adapter sees a patch.
- Export `lib/src/material_effect_mask.dart` from `lib/flutter_scene_viewer.dart`.
- Create `lib/src/material_extension_policy.dart`
  - Public opt-in policy, defaulting to diagnostics-only behavior.
  - Exposes the support matrix that controller validation uses.
- Export `lib/src/material_extension_policy.dart` from
  `lib/flutter_scene_viewer.dart`.
- Modify `lib/src/viewer_widget.dart`
  - Add `materialExtensionPolicy` to `FlutterSceneViewer` and
    `FlutterSceneViewer.test`.
  - Pass the policy into `ModelLoader` and `FlutterSceneRuntimeAdapter`.
- Modify `lib/src/viewer_controller.dart`
  - Ask the attached sink for material extension support before validating a
    `MaterialPatch`.
  - Preserve current non-persistence behavior when a feature is unsupported.
- Modify `lib/src/model_loader.dart`
  - Parse GLB material extension metadata before adapter import when policy
    requests authored extension handling.
  - Merge authored extension diagnostics into `ModelLoadResult.diagnostics`.
- Create `lib/src/internal/glb_material_extension_reader.dart`
  - Bounded GLB JSON reader for material extension intent.
  - Supports only binary `.glb` JSON chunk parsing in this slice.
  - Produces a `Map<PartAddress, MaterialPatch>` and diagnostics.
- Modify `lib/src/internal/flutter_scene_adapter.dart`
  - Route opaque, masked cutout, translucent blend, and realistic glass patches
    through separate material-family construction paths.
  - Apply alpha `opaque` only to opaque-family materials.
  - Apply alpha `mask` only by constructing/restoring a masked cutout family
    material; do not treat it as object visibility.
  - Apply alpha `blend` only by constructing/restoring a translucent blend
    family material; do not mutate an existing opaque material into blend mode
    in place.
  - Apply material/effect masks only on opaque-family materials and keep them
    separate from alpha cutout, alpha blend, and glass routing.
  - Route accepted glass/clearcoat patches to the extension backend.
  - Keep direct guards returning diagnostics when the backend is disabled or
    cannot render the requested feature.
- Create `lib/src/internal/flutter_scene_material_extension_backend.dart`
  - Runtime bridge from `MaterialPatch` intent to `flutter_scene` custom
    materials.
  - Owns shader loading, render-texture setup, layer allocation, and restore.
- Create `assets/materials/fsviewer_transmission.fmat`
  - First custom material source for transmission/glass.
  - Uses a background render texture sampler and extension uniform block.
- Create `assets/materials/fsviewer_clearcoat.fmat`
  - Clearcoat material source only after the backend can bind a real second
    specular lobe.
- Create or modify `hook/build.dart`
  - Calls `buildMaterials(...)` so `.fmat` materials are packaged.
- Add tests:
  - `test/material_effect_mask_test.dart`
  - `test/material_patch_test.dart`
  - `test/viewer_controller_material_test.dart`
  - `test/material_extension_policy_test.dart`
  - `test/glb_material_extension_reader_test.dart`
  - `test/flutter_scene_material_extension_backend_test.dart`
- Update docs:
  - `docs/PUBLIC_API.md`
  - `docs/MATERIALS_AND_LIGHTING.md`
  - `docs/RUNTIME_GLB_PIPELINE.md`
  - `docs/references/flutter_scene_capability_notes.md`
  - `docs/generated/capability_matrix.md`
  - `README.md` only if the top-level scope wording changes.

## Steps

### Task 1: Lock base material families before feature work

**Files:**

- Create `lib/src/internal/material_base_family.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/material_extension_policy_test.dart`
- Test `test/viewer_controller_material_test.dart`

- [x] Add the internal enum:

```dart
enum MaterialBaseFamily {
  opaque,
  maskedCutout,
  translucentBlend,
  realisticGlass,
}
```

- [x] Add a resolver function with this behavior:
  - any transmission, IOR, thickness, attenuation, or volume request resolves
    to `MaterialBaseFamily.realisticGlass`;
  - `MaterialAlphaMode.mask` resolves to `MaterialBaseFamily.maskedCutout`
    only when no glass field is present;
  - `MaterialAlphaMode.blend` or a base color alpha below `1.0` resolves to
    `MaterialBaseFamily.translucentBlend` only when no glass field is present
    and no explicit mask request is present;
  - `MaterialAlphaMode.opaque` and opaque base color resolve to
    `MaterialBaseFamily.opaque`;
  - clearcoat without glass stays in the opaque family until the clearcoat
    shader task provides an explicit coated family path.
- [x] Add tests proving one patch resolves to one family and that glass wins
  over alpha mask or alpha blend when both are present.
- [x] Add adapter tests proving a patch that changes family replaces/restores a
  material through a family transition path instead of mutating one existing
  material instance across opaque, masked cutout, and translucent blend
  behavior.
- [x] Run:

```sh
flutter test test/material_extension_policy_test.dart test/viewer_controller_material_test.dart
```

Expected: all tests pass.

### Task 2: Add alpha API as masked cutout and translucent blend families

**Files:**

- Modify `lib/src/material_patch.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Modify `docs/PUBLIC_API.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Test `test/material_patch_test.dart`
- Test `test/viewer_controller_material_test.dart`

- [x] Write failing JSON and merge tests for:
  - `MaterialAlphaMode.opaque`
  - `MaterialAlphaMode.mask`
  - `MaterialAlphaMode.blend`
  - `alphaCutoff`
- [x] Add the enum and fields:

```dart
enum MaterialAlphaMode {
  opaque,
  mask,
  blend,
}

final class MaterialPatch {
  const MaterialPatch({
    this.alphaMode,
    this.alphaCutoff,
    // existing fields remain unchanged
  });

  final MaterialAlphaMode? alphaMode;
  final double? alphaCutoff;
}
```

- [x] Validate `alphaCutoff` with the same invalid material diagnostic pattern
  used by metallic, roughness, and occlusion strength.
- [x] Map alpha in the runtime adapter by family:
  - `MaterialAlphaMode.opaque` -> `flutter_scene.AlphaMode.opaque`
  - `MaterialAlphaMode.mask` -> a newly constructed masked cutout family
    material using `flutter_scene.AlphaMode.mask` only for PBR materials with
    shader discard support
  - `MaterialAlphaMode.blend` -> a newly constructed translucent blend family
    material using `flutter_scene.AlphaMode.blend`
  - `alphaCutoff` -> `material.alphaCutoff`
- [x] Add a diagnostic for `MaterialAlphaMode.mask` on unlit materials while
  the installed `flutter_scene` unlit path treats mask like blend.
- [x] Add docs stating that alpha mask is for authored cutout/discard use, not
  for object visibility or partial configurator show/hide behavior.
- [x] Add a test proving `MaterialAlphaMode.mask` does not mutate an existing
  opaque family material in place.
- [x] Add a test proving `MaterialAlphaMode.blend` does not mutate an existing
  opaque family material in place.
- [x] Add a controller test proving alpha patches apply and persist because
  they are supported translucent blend behavior, not glass.
- [x] Update docs to say alpha transparency is supported separately from
  transmission/glass.
- [x] Run:

```sh
flutter test test/material_patch_test.dart test/viewer_controller_material_test.dart
```

Expected: all tests pass.

### Task 3: Add opaque material/effect mask support

**Files:**

- Create `lib/src/material_effect_mask.dart`
- Create `lib/src/internal/material_effect_mask_resolver.dart`
- Modify `lib/flutter_scene_viewer.dart`
- Modify `lib/src/material_patch.dart`
- Modify `lib/src/viewer_controller.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Modify `docs/PUBLIC_API.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Test `test/material_effect_mask_test.dart`
- Test `test/material_patch_test.dart`
- Test `test/viewer_controller_material_test.dart`

- [x] Add public channel and target enums:

```dart
enum MaterialMaskChannel {
  red,
  green,
  blue,
  alpha,
}

enum MaterialEffectTarget {
  baseColorRegion,
  roughness,
  metallic,
  clearcoat,
  dirt,
  paintRegion,
}
```

- [x] Add the public effect-mask value type:

```dart
final class MaterialEffectMask {
  const MaterialEffectMask({
    required this.texture,
    required this.channels,
  });

  final TextureSource texture;
  final Map<MaterialMaskChannel, MaterialEffectTarget> channels;
}
```

- [x] Add `MaterialPatch.effectMask` and JSON round-trip tests. The field is a
  V1 opaque-family feature and must not imply alpha discard, blend, glass, or
  part visibility.
- [x] Add resolver validation:
  - effect masks require authored UV0;
  - effect masks are accepted only when the resolved base family is
    `MaterialBaseFamily.opaque`;
  - effect masks combined with `MaterialAlphaMode.mask`,
    `MaterialAlphaMode.blend`, or glass fields return
    `unsupportedMaterialFeature`;
  - duplicate target mappings in one mask return `invalidMaterialOverride`;
  - unsupported channel names in JSON return `invalidMaterialOverride`.
- [x] Add adapter behavior for the first V1 slice:
  - preserve and persist the effect-mask intent;
  - do not send the mask to a fake shader path unless a real opaque shader
    consumes it;
  - if the installed `flutter_scene` standard PBR shader cannot consume the
    requested channel mapping, return `unsupportedMaterialFeature` rather than
    pretending the mask changed material output.
- [x] Add docs with the exact distinction:
  - material/effect mask: packed data inside opaque material, used for regional
    material parameters;
  - alpha cutout / masked cutout: separate family using discard;
  - visibility: node/part visibility, not mask textures.
- [x] Run:

```sh
flutter test test/material_effect_mask_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart
```

Expected: all tests pass.

### Task 4: Introduce material extension policy and capability-aware validation

**Files:**

- Create `lib/src/material_extension_policy.dart`
- Modify `lib/flutter_scene_viewer.dart`
- Modify `lib/src/material_patch.dart`
- Modify `lib/src/viewer_widget.dart`
- Modify `lib/src/viewer_controller.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/material_extension_policy_test.dart`
- Test `test/viewer_controller_material_test.dart`

- [x] Add this public policy shape:

```dart
enum ViewerMaterialExtensionMode {
  diagnosticsOnly,
  experimentalFlutterSceneShaders,
}

final class ViewerMaterialExtensionPolicy {
  const ViewerMaterialExtensionPolicy.diagnosticsOnly()
      : mode = ViewerMaterialExtensionMode.diagnosticsOnly,
        enableTransmission = false,
        enableClearcoat = false;

  const ViewerMaterialExtensionPolicy.experimentalShaders({
    this.enableTransmission = true,
    this.enableClearcoat = false,
  }) : mode = ViewerMaterialExtensionMode.experimentalFlutterSceneShaders;

  final ViewerMaterialExtensionMode mode;
  final bool enableTransmission;
  final bool enableClearcoat;
}
```

- [x] Add an internal support value used by validation:

```dart
final class MaterialExtensionSupport {
  const MaterialExtensionSupport({
    this.transmission = false,
    this.ior = false,
    this.volume = false,
    this.clearcoat = false,
  });

  static const unsupported = MaterialExtensionSupport();

  final bool transmission;
  final bool ior;
  final bool volume;
  final bool clearcoat;
}
```

- [x] Change `MaterialPatch.validate` to accept support with a default:

```dart
List<ViewerDiagnostic> validate(
  PartAddress address, {
  MaterialExtensionSupport support = MaterialExtensionSupport.unsupported,
})
```

- [x] Preserve current default behavior: glass and clearcoat patches still
  return `unsupportedMaterialFeature` when support is omitted.
- [x] Add `MaterialExtensionSupport get materialExtensionSupport` to
  `ViewerCommandSink` so `FlutterSceneViewerController` can validate against
  the attached viewer's backend.
- [x] Add controller tests proving:
  - default policy rejects and does not persist glass and clearcoat;
  - experimental transmission policy allows transmission intent to reach the
    sink;
  - experimental policy does not allow clearcoat when `enableClearcoat` is
    false.
- [x] Run:

```sh
flutter test test/material_patch_test.dart test/viewer_controller_material_test.dart test/material_extension_policy_test.dart
```

Expected: all tests pass.

### Task 5: Parse authored GLB material extension intent

**Files:**

- Create `lib/src/internal/glb_material_extension_reader.dart`
- Modify `lib/src/model_loader.dart`
- Test `test/glb_material_extension_reader_test.dart`
- Test `test/model_loader_test.dart`

- [x] Write a unit test that builds a minimal binary GLB in memory with:
  - one node named `GlassPanel`;
  - one mesh primitive at primitive index `0`;
  - `TEXCOORD_0`;
  - a material containing `KHR_materials_transmission`,
    `KHR_materials_ior`, and `KHR_materials_volume`.
- [x] Implement a GLB JSON chunk reader that verifies:
  - magic is `glTF`;
  - version is `2`;
  - JSON chunk exists;
  - JSON is a map;
  - missing or malformed extension values produce diagnostics, not throws.
- [x] Map supported extension fields into `MaterialPatch`:
  - `transmissionFactor` -> `transmission`
  - `transmissionTexture` -> `transmissionTexture`
  - `ior` -> `ior`
  - `thicknessFactor` -> `thickness`
  - `thicknessTexture` -> `thicknessTexture`
  - `attenuationColor` -> `attenuationColor`
  - `attenuationDistance` -> `attenuationDistance`
  - `clearcoatFactor` -> `clearcoat`
  - `clearcoatTexture` -> `clearcoatTexture`
  - `clearcoatRoughnessFactor` -> `clearcoatRoughness`
  - `clearcoatRoughnessTexture` -> `clearcoatRoughnessTexture`
  - `clearcoatNormalTexture` -> `clearcoatNormalTexture`
- [x] Keep texture object parsing minimal in this slice: record texture-bearing
  extension intent and require UV0, but do not implement image extraction until
  the runtime texture loader path is wired to it.
- [x] Build `PartAddress` keys from GLB node names and mesh primitive indices.
  If duplicate paths make an authored extension address ambiguous, emit
  `ambiguousNodePath` and do not auto-apply that authored extension.
- [x] Merge reader diagnostics into `ModelLoadResult.diagnostics`.
- [x] Run:

```sh
flutter test test/glb_material_extension_reader_test.dart test/model_loader_test.dart
```

Expected: all tests pass.

### Task 6: Wire authored extension patches through the controller lifecycle

**Files:**

- Modify `lib/src/model_loader.dart`
- Modify `lib/src/viewer_controller.dart`
- Modify `lib/src/viewer_widget.dart`
- Test `test/viewer_controller_material_test.dart`
- Test `test/viewer_widget_test.dart`

- [x] Extend `ModelLoadResult.success` with an internal authored extension
  patch list. Keep the public `PartTree` API stable.
- [x] After a successful load and part-tree creation, apply authored extension
  patches through the same validation and adapter path as runtime patches.
- [x] Do not add rejected authored patches to
  `controller.materialOverrides`; authored GLB material state is source data,
  not user override state.
- [x] Add tests proving:
  - default policy records unsupported diagnostics for authored glass;
  - experimental transmission policy sends authored glass to the adapter;
  - missing UV0 on an authored texture-bearing extension records `missingUvSet`;
  - rejected authored patches do not appear in persisted override snapshots.
- [x] Run:

```sh
flutter test test/viewer_controller_material_test.dart test/viewer_widget_test.dart
```

Expected: all tests pass.

### Task 7: Verify custom material packaging with a minimal shader

**Files:**

- Create `assets/materials/fsviewer_debug_tint.fmat`
- Create or modify `hook/build.dart`
- Modify `pubspec.yaml` only when the shader asset path needs explicit listing.
- Test `test/flutter_scene_material_extension_backend_test.dart`

- [x] Add a minimal `.fmat` material that returns a visible tint and consumes a
  scalar uniform.
- [x] Add `hook/build.dart`:

```dart
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsRequired,
      materials: const <String>[
        'assets/materials/fsviewer_debug_tint.fmat',
      ],
    );
  });
}
```

- [x] Add a GPU-gated smoke test that loads the generated material through the
  documented `flutter_scene` material path. Skip with a clear message unless
  `FLUTTER_SCENE_GPU_TESTS=true`.
- [x] Record the exact shader build/load evidence in
  `docs/references/flutter_scene_capability_notes.md`.
- [x] Run:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Expected: the GPU-gated shader smoke passes on a compatible Flutter master.

### Task 8: Implement experimental realistic glass backend

**Files:**

- Create `assets/materials/fsviewer_transmission.fmat`
- Create `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify `lib/src/internal/flutter_scene_adapter.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Update `docs/MATERIALS_AND_LIGHTING.md`
- Update `docs/RUNTIME_GLB_PIPELINE.md`

- [x] Allocate one internal render layer bit for transmissive primitives and
  one background layer mask that excludes that bit.
- [x] When a transmission patch is accepted:
  - capture the original material and node layer state;
  - assign the node to include the transmissive layer;
  - create or reuse a background `RenderTexture`;
  - create or reuse a background `RenderView` with a layer mask that excludes
    transmissive primitives;
  - replace the primitive material with a realistic glass family
    `ShaderMaterial`.
- [x] Bind the transmission shader inputs:
  - opaque/background render texture;
  - base color factor/texture where available;
  - normal texture and normal scale when provided;
  - transmission factor/texture;
  - IOR;
  - thickness/texture;
  - attenuation color/distance;
  - roughness;
  - viewport size or inverse viewport size.
- [x] The shader must sample the background texture with a normal/IOR-derived
  offset. With transmission `0.0`, output behaves like the base material; with
  transmission `1.0`, the background contribution is visibly refracted and
  attenuated.
- [x] The glass material must use its own realistic-glass shader and
  `isOpaqueOverride = false`; it must not reuse the translucent blend family
  material or treat alpha blending as refraction.
- [x] Reset restores the original material and node layers.
- [x] Add unit tests around backend state transitions using adapter-test fakes
  where possible, and GPU-gated smoke for the real shader path.
- [x] Add a visual smoke fixture or generated runtime scene with an obvious
  striped/checker object behind glass. The screenshot must make refraction
  readable without relying on alpha alone.
- [x] Run:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Expected: CPU tests pass, and GPU-gated smoke passes on a compatible Flutter
master.

### Task 9: Add experimental clearcoat only after a real shader lobe exists

**Files:**

- Create `assets/materials/fsviewer_clearcoat.fmat`
- Modify `lib/src/internal/flutter_scene_material_extension_backend.dart`
- Modify `lib/src/material_extension_policy.dart`
- Test `test/flutter_scene_material_extension_backend_test.dart`
- Update `docs/MATERIALS_AND_LIGHTING.md`
- Update `docs/generated/capability_matrix.md`

- [x] Keep `ViewerMaterialExtensionPolicy.experimentalShaders()` defaulting to
  `enableClearcoat: false` and keep clearcoat support disabled until a real
  clearcoat shader backend exists.
- [x] Add `assets/materials/fsviewer_clearcoat.fmat` only after implementing a
  real second dielectric specular lobe. The shader samples environment
  specular separately from the base material and consumes:
  - `clearcoat`;
  - `clearcoatTexture`;
  - `clearcoatRoughness`;
  - `clearcoatRoughnessTexture`;
  - `clearcoatNormalTexture`;
  - `clearcoatNormalScale`.
- [x] Bind environment IBL for clearcoat through
  `ShaderMaterial.useEnvironment = true`.
- [x] Prove with tests that clearcoat fields are rejected by default and are
  accepted only when `experimentalShaders(enableClearcoat: true)` advertises
  clearcoat support.
- [x] Add a clearcoat visual smoke comparing:
  - base glossy material;
  - clearcoat `0.0`;
  - clearcoat `1.0` with lower clearcoat roughness.
- [x] Run the clearcoat verification:

```sh
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart test/viewer_controller_material_test.dart test/flutter_scene_material_extension_backend_test.dart
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "clearcoat shader renders distinct second specular lobe smoke" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Expected: default clearcoat remains diagnostic-only, opt-in experimental
clearcoat routes through a real shader path, and local GPU visual evidence is
recorded without making a production-ready claim.

### Task 10: Final docs, capability matrix, and PR-ready notes

**Files:**

- Modify `docs/PUBLIC_API.md`
- Modify `docs/MATERIALS_AND_LIGHTING.md`
- Modify `docs/RUNTIME_GLB_PIPELINE.md`
- Modify `docs/references/flutter_scene_capability_notes.md`
- Modify `docs/generated/capability_matrix.md`
- Modify `README.md` only if top-level scope wording is stale.
- Modify this plan's progress and verification logs.

- [x] Document the material categories:
  - opaque base material: core PBR with no alpha discard or blend;
  - material/effect mask: opaque-family packed data map for regional material
    parameters, not visibility;
  - masked cutout base material: alpha-test/discard for authored cutout only;
  - translucent blend base material: current transparency, not glass;
  - realistic glass base material: opt-in screen-space refraction backend;
  - clearcoat: opt-in experimental clearcoat shader backend; diagnostic-only
    by default.
- [x] Document platform gates and fallback diagnostics.
- [x] Document that authored extension texture slots require UV0 and that UV1
  is never substituted.
- [x] Record exact `flutter_scene` PR candidates:
  - importer support for `KHR_materials_transmission`;
  - importer support for `KHR_materials_ior`;
  - importer support for `KHR_materials_volume`;
  - importer support for `KHR_materials_clearcoat`;
  - first-class PBR extension material fields or a stable material-extension
    hook that avoids package-local GLB parsing.
- [x] Run:

```sh
flutter test test/material_effect_mask_test.dart test/material_patch_test.dart test/viewer_controller_material_test.dart test/material_base_family_test.dart test/material_extension_policy_test.dart test/glb_material_extension_reader_test.dart test/flutter_scene_material_extension_backend_test.dart test/flutter_scene_adapter_material_test.dart
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

Expected: all non-GPU checks pass. GPU-gated material-extension smoke evidence
is recorded when available.

## Acceptance criteria

- [x] Opaque base material, masked cutout base material, translucent blend base
  material, and realistic glass base material are represented as separate
  internal material families.
- [x] Material/effect masks are represented as opaque-family packed channel
  data, require UV0, never discard pixels, and are not usable for visibility.
- [x] Alpha behavior is represented explicitly in `MaterialPatch`; mask maps to
  the masked cutout family, blend maps to the translucent blend family, and
  both are documented separately from glass.
- [x] Default policy keeps current honest behavior: unsupported glass and
  clearcoat return `unsupportedMaterialFeature`, are not applied, and are not
  persisted.
- [x] Experimental policy is public, opt-in, and capability-aware.
- [x] GLB-authored material extension metadata is read from binary GLB JSON and
  mapped to `PartAddress` without using UV1 or generating UVs.
- [x] Texture-bearing transmission, volume, and clearcoat extension fields
  require authored UV0 before they can be applied.
- [x] Transmission has GPU-gated visual evidence showing the realistic glass
  family performing real background sampling/refraction behavior, not
  alpha-only transparency or the translucent blend family.
- [x] Clearcoat remains diagnostic-only by default and becomes available only
  through `experimentalShaders(enableClearcoat: true)` after a shader
  implements real clearcoat behavior; tests prove it does not fall back to
  roughness changes.
- [x] Docs and capability matrix reflect default support, experimental support,
  platform gates, and upstream `flutter_scene` PR candidates.

## Progress log

- 2026-07-03: Created this plan after the diagnostic-only advanced PBR blocker
  work in active plan 009 proved that installed `flutter_scene` 0.18.1 lacks
  importer/material support for transmission, IOR, volume, and clearcoat. User
  direction: transmission/glass and clearcoat remain v1-critical, and the repo
  should attempt an in-repository Flutter GPU / `flutter_scene` custom material
  backend before waiting on an upstream PR.
- 2026-07-03: Audited local `flutter_scene` 0.18.1 public custom-material
  surface. `ShaderMaterial` supports caller-supplied fragment shaders,
  uniform blocks, texture bindings, `RenderTexture` samplers, environment IBL
  bindings, and translucent-pass routing through `isOpaqueOverride = false`.
  `RenderView.layerMask` and `Node.layers` are public enough to build a
  background render view that excludes transmissive primitives.
- 2026-07-03: Revised the plan per user architecture feedback: opaque and
  translucent blend materials must not be combined in one runtime material or
  switched by mutating one material instance in place. The implementation now
  starts by defining explicit base material families instead of mutating one
  material instance across pipeline behavior.
- 2026-07-03: Revised the plan again after user feedback on masked alpha.
  Masked cutout is now a fourth internal material family, not part of opaque
  base. It is allowed only for authored cutout/discard behavior and must not
  be used for object-part visibility or configurator show/hide behavior.
- 2026-07-03: Added V1 material/effect mask planning to active plan 010.
  Material/effect masks now stay in the opaque family as packed data maps for
  regional material parameters, while KTX2 / `KHR_texture_basisu` compression
  and authoring optimization tooling remain a V2 track.
- 2026-07-03: Implemented Task 1 first slice. Added internal base material
  family resolution for opaque, masked cutout, translucent blend, and
  realistic glass without adding public alpha API, shader backend, effect
  masks, compression, or clearcoat rendering. Assumption: until Task 2 adds
  public alpha patch fields, alpha mask/blend intent is represented by an
  internal resolver input and visibility remains separate node/part state.
- 2026-07-03: Implemented Task 2 alpha API slice. Added public
  `MaterialAlphaMode`, `MaterialPatch.alphaMode`, and
  `MaterialPatch.alphaCutoff`; wired JSON, merge, validation, resolver
  mapping, controller persistence, and runtime adapter alpha routing for
  supported PBR alpha behavior. Assumption: unlit alpha mask remains
  diagnostic-only because installed `flutter_scene` treats unlit mask like
  blend, and the viewer must not fake mask by falling back to blend.
- 2026-07-03: Implemented Task 3 material/effect mask API slice. Added public
  `MaterialEffectMask`, `MaterialMaskChannel`, and `MaterialEffectTarget`;
  exported the model; added `MaterialPatch.effectMask` JSON, merge,
  validation, UV0 checks, and opaque-family-only diagnostics. Runtime adapter
  behavior remains honest: the standard `flutter_scene` PBR shader cannot
  consume effect-mask channels, so the adapter reports
  `unsupportedMaterialFeature` instead of faking rendered output.
- 2026-07-03: Implemented Task 4 material extension policy slice. Added public
  `ViewerMaterialExtensionPolicy` and `MaterialExtensionSupport`; made
  `MaterialPatch.validate` capability-aware with a default unsupported support
  matrix; wired `ViewerCommandSink.materialExtensionSupport` into controller
  validation; and added `FlutterSceneViewer.materialExtensionPolicy` so
  experimental transmission/IOR/volume intent can reach an attached backend
  while default glass and clearcoat remain diagnostic-only.
- 2026-07-03: Implemented Task 5 authored GLB material extension reader slice.
  Added a bounded binary GLB JSON chunk reader for transmission, IOR, volume,
  and clearcoat intent; mapped authored material extension fields into
  `MaterialPatch` values; reported malformed extension values as diagnostics;
  rejected texture-bearing authored extension intent without UV0; skipped
  ambiguous duplicate node paths; and merged reader diagnostics into
  `ModelLoadResult.diagnostics`.
- 2026-07-03: Implemented Task 6 authored extension lifecycle slice. Extended
  `ModelLoadResult.success` with internal authored material patches, applied
  accepted authored patches after load through the same controller validation
  and adapter diagnostic path as runtime patches, and kept authored source
  material state out of `controller.materialOverrides`.
- 2026-07-03: Implemented Task 7 packaging scaffold. Added
  `assets/materials/fsviewer_debug_tint.fmat`, `hook/build.dart` with
  `buildMaterials(...)`, and a GPU-gated `.fmat` material load smoke test.
  After the initial GPU-gated run exposed that Dart DataAssets were not
  enabled locally, enabled `enable-dart-data-assets`, required DataAssets in
  the build hook, listed the generated shaderbundle and sidecar as test
  assets, and verified the debug material through the
  `PreprocessedMaterial` shaderbundle path. Assumption: this proves minimal
  `.fmat` build/load packaging only; it is not production glass support.
- 2026-07-03: Implemented the Task 8 experimental transmission backend core.
  Added `assets/materials/fsviewer_transmission.fmat` and
  `FlutterSceneMaterialExtensionBackend`; routed supported experimental glass
  patches from `FlutterSceneRuntimeAdapter` into a separate
  `ShaderMaterial`/`RenderTexture`/`RenderView.layerMask` path; bound
  background, base color, normal, transmission, thickness, IOR, attenuation,
  roughness, and inverse-viewport inputs; and restored original material and
  node layers on reset. Assumption: the current public `flutter_scene` layer
  API is node-level, so one glass primitive on a multi-primitive node moves
  the node for background-capture exclusion.
- 2026-07-03: Resolved the Task 8 visual evidence blocker. Root cause was not
  PNG/readback itself: the visual smoke initially replaced
  `MeshPrimitive.material` after the node was mounted, but `flutter_scene`
  `RenderItem.material` is captured when the mesh component registers render
  items. The backend now refreshes the mounted mesh wrapper after replacing or
  restoring the primitive material so render items see the glass
  `ShaderMaterial`. The visual smoke now uses direct `Scene.render` /
  `PictureRecorder` capture instead of `SceneView` widget teardown, which hung
  locally after producing the screenshot. The opt-in GPU visual smoke writes a
  readable striped-behind-glass screenshot to
  `tools/out/fsviewer_transmission_smoke.png`.
- 2026-07-03: Completed Task 9 with an experimental clearcoat shader/backend
  instead of leaving it diagnostic-only. Root cause for the earlier blocked
  assessment was that the standard `flutter_scene` lit fmat path exposes only
  core `MaterialInputs` and cannot add a clearcoat field to engine
  `EvaluateLighting`; however, public `ShaderMaterial.useEnvironment` can bind
  the active environment specular textures to a package-local shader. Added
  `assets/materials/fsviewer_clearcoat.fmat`, routed
  `experimentalShaders(enableClearcoat: true)` clearcoat-only patches through
  `FlutterSceneMaterialExtensionBackend`, kept default clearcoat
  diagnostic-only, and kept combined glass+clearcoat unsupported until a
  combined shader exists. Local visual evidence writes
  `tools/out/fsviewer_clearcoat_smoke.png`.

## Verification log

- 2026-07-03: verified locally for the plan-only change:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified locally after base-material-family revision:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified locally after masked-cutout family revision:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified locally after V1 material/effect mask planning update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified red: `flutter test
  test/material_base_family_test.dart` failed before implementation because
  `lib/src/internal/material_base_family.dart`, `MaterialBaseFamily`, and
  `resolveMaterialBaseFamily` did not exist.
- 2026-07-03: verified locally: `flutter test
  test/material_base_family_test.dart` passed 6 tests.
- 2026-07-03: verified locally: `flutter test
  test/material_base_family_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` passed 24 tests.
- 2026-07-03: verified locally before this log update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-03: verified locally: `bash tools/run_checks.sh` passed after the
  first sandboxed attempt was blocked by Flutter SDK cache writes. Output
  stages: repo lint passed; Dart format check reported 43 files with 0
  changed; `flutter pub get` completed; `flutter analyze` reported no issues;
  `flutter test` passed 119 tests with 3 GPU-gated skips.
- 2026-07-03: verified red for Task 2:
  `flutter test test/material_base_family_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` failed before implementation
  because `MaterialAlphaMode`, `MaterialPatch.alphaMode`, and
  `MaterialPatch.alphaCutoff` did not exist. The first sandboxed attempt was
  blocked by Flutter SDK cache writes and was rerun with escalation.
- 2026-07-03: verified locally for Task 2:
  `flutter test test/material_base_family_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` passed 34 tests after the first
  sandboxed attempt was blocked by Flutter SDK cache writes and was rerun with
  escalation.
- 2026-07-03: verified locally for expanded Task 2 adapter-facing coverage:
  `flutter test test/flutter_scene_adapter_material_test.dart
  test/material_base_family_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` passed 36 tests after the first
  sandboxed attempt was blocked by Flutter SDK cache writes and was rerun with
  escalation.
- 2026-07-03: verified red for Task 3:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` failed before implementation
  because `MaterialEffectMask`, `MaterialMaskChannel`,
  `MaterialEffectTarget`, and `MaterialPatch.effectMask` did not exist. The
  first sandboxed attempt was blocked by Flutter SDK cache writes and was rerun
  with escalation.
- 2026-07-03: verified locally for Task 3:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart` passed 36 tests after the first
  sandboxed attempt was blocked by Flutter SDK cache writes and was rerun with
  escalation.
- 2026-07-03: verified red for Task 4:
  `flutter test test/material_extension_policy_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/viewer_widget_test.dart`
  failed before implementation because `ViewerMaterialExtensionPolicy`,
  `ViewerMaterialExtensionMode`, `MaterialExtensionSupport`,
  `MaterialPatch.validate(... support:)`, and
  `FlutterSceneViewer.materialExtensionPolicy` did not exist. The first
  sandboxed attempt was blocked by Flutter SDK cache writes and was rerun with
  escalation.
- 2026-07-03: verified locally for Task 4:
  `flutter test test/material_extension_policy_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/viewer_widget_test.dart`
  passed 67 tests after the first sandboxed attempt was blocked by Flutter SDK
  cache writes and was rerun with escalation.
- 2026-07-03: verified red for Task 5:
  `flutter test test/glb_material_extension_reader_test.dart
  test/model_loader_test.dart` failed before implementation because
  `lib/src/internal/glb_material_extension_reader.dart` and
  `readGlbMaterialExtensionIntent` did not exist. The model-loader test also
  exposed a missing `dart:typed_data` import in the new test helper.
- 2026-07-03: verified locally for Task 5:
  `flutter test test/glb_material_extension_reader_test.dart
  test/model_loader_test.dart` passed 16 tests with 3 GPU-gated skips after
  rerunning with escalation for Flutter SDK cache access.
- 2026-07-03: verified red for Task 6:
  `flutter test test/viewer_controller_material_test.dart
  test/viewer_widget_test.dart` failed before implementation because
  `ModelLoadResult.success` had no `authoredMaterialPatches` argument and
  authored patches were not applied during widget/controller load.
- 2026-07-03: verified locally for Task 6:
  `flutter test test/viewer_controller_material_test.dart
  test/viewer_widget_test.dart` passed 52 tests after rerunning with
  escalation for Flutter SDK cache access.
- 2026-07-03: verified locally for Task 7 non-GPU path:
  `flutter test test/flutter_scene_material_extension_backend_test.dart`
  passed with 1 GPU-gated skip after rerunning with escalation for Flutter SDK
  cache/build access.
- 2026-07-03: verified locally for Task 7 GPU-gated shader load:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 1 test after enabling Dart DataAssets with
  `flutter config --enable-dart-data-assets`. The first GPU-gated attempt
  failed because `flutter_scene.loadFmatMaterial` could not find a
  DataAssets-backed `.fmat` index while `flutter config --list` reported
  `enable-dart-data-assets: (Not set)`. After the config change, the hook
  generated `build/shaderbundles/materials.shaderbundle`,
  `build/shaderbundles/materials.fmat.json`, and
  `build/shaderbundles/materials.index.json`; the test loads the generated
  shader bundle and sidecar through `PreprocessedMaterial`. No production
  glass support is claimed from this packaging smoke. Re-run before starting
  Task 8 passed after the first sandboxed attempt was blocked by Flutter SDK
  cache writes and was rerun with escalation.
- 2026-07-03: verified red for Task 8 backend state transitions:
  `flutter test test/flutter_scene_material_extension_backend_test.dart`
  failed because
  `lib/src/internal/flutter_scene_material_extension_backend.dart` and
  `FlutterSceneMaterialExtensionBackend` did not exist. The first sandboxed
  attempt was blocked by Flutter SDK cache writes and was rerun with
  escalation.
- 2026-07-03: verified locally for Task 8 backend state transitions:
  `flutter test test/flutter_scene_material_extension_backend_test.dart`
  passed 2 CPU tests with 3 GPU-gated skips after rerunning with escalation.
- 2026-07-03: verified red for Task 8 adapter routing:
  `flutter test test/flutter_scene_adapter_material_test.dart` failed because
  `debugUsesMaterialExtensionBackendFor` did not exist.
- 2026-07-03: verified locally for Task 8 adapter routing:
  `flutter test test/flutter_scene_adapter_material_test.dart` passed 3 tests.
- 2026-07-03: verified red for Task 8 transmission shader packaging:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` failed because the generated shader bundle did not
  contain `FSViewerTransmission`.
- 2026-07-03: verified locally for Task 8 transmission shader packaging:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 4 tests with 1 visual-smoke skip after adding
  `assets/materials/fsviewer_transmission.fmat` to the build hook and
  verifying the generated shader bundle entry.
- 2026-07-03: verified red for Task 8 mounted material replacement:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "refreshes mounted render items when replacing and restoring
  material"` failed because the mounted `RenderItem` still referenced the
  original material after `MeshPrimitive.material` was replaced.
- 2026-07-03: verified locally for Task 8 mounted material replacement:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "refreshes mounted render items when replacing and restoring
  material"` passed after rerunning with escalation. The backend refreshes the
  node mesh wrapper after material replace/restore so mounted render items
  re-register with the current primitive material.
- 2026-07-03: verified locally for Task 8 visual screenshot evidence:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused visual-smoke test after rerunning with
  escalation. The direct `Scene.render` capture wrote
  `tools/out/fsviewer_transmission_smoke.png`, and the test verified color
  spread plus red/green/blue dominant samples through the glass panel.
- 2026-07-03: re-verified locally after Task 8 cleanup:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 6 tests with 3
  GPU-gated skips, and `flutter test
  test/flutter_scene_material_extension_backend_test.dart --plain-name
  "transmission shader renders readable background refraction smoke"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused opt-in visual smoke after rerunning
  with escalation.
- 2026-07-03: verified red for Task 9 clearcoat backend:
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/viewer_controller_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart` failed before
  implementation because `createClearcoatMaterial`, `applyClearcoatPatch`,
  `resetClearcoatPatch`, and `clearcoatShaderName` did not exist, and the
  policy still returned `support.clearcoat == false` when
  `enableClearcoat: true` was requested.
- 2026-07-03: verified locally for Task 9 CPU/controller/adapter coverage:
  `flutter test test/material_extension_policy_test.dart
  test/flutter_scene_adapter_material_test.dart
  test/viewer_controller_material_test.dart
  test/flutter_scene_material_extension_backend_test.dart` passed 38 tests
  with 4 GPU-gated skips after rerunning with escalation for Flutter SDK cache
  access.
- 2026-07-03: verified locally for Task 9 GPU-gated shader load:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller
  --enable-flutter-gpu` passed 8 tests with 2 opt-in visual-smoke skips after
  rerunning with escalation. The generated shader bundle contains and loads
  `FSViewerClearcoat`.
- 2026-07-03: verified locally for Task 9 clearcoat visual evidence:
  `flutter test test/flutter_scene_material_extension_backend_test.dart
  --plain-name "clearcoat shader renders distinct second specular lobe smoke"
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
  --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller
  --enable-flutter-gpu` passed 1 focused opt-in visual smoke after rerunning
  with escalation and wrote `tools/out/fsviewer_clearcoat_smoke.png`.
- 2026-07-03: verified locally for final focused suite:
  `flutter test test/material_effect_mask_test.dart test/material_patch_test.dart
  test/viewer_controller_material_test.dart test/material_base_family_test.dart
  test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart
  test/flutter_scene_material_extension_backend_test.dart
  test/flutter_scene_adapter_material_test.dart` passed 68 tests with 5
  GPU-gated skips after the first sandboxed attempt was blocked by Flutter SDK
  cache writes and was rerun with escalation.
- 2026-07-03: verified locally for final repo checks:
  `bash tools/run_checks.sh` passed after the first sandboxed attempts were
  blocked by Flutter SDK cache writes and after one intermediate run formatted
  three existing files and one analyzer run exposed dependency/hygiene fixes.
  Final output: repo lint passed; Dart format changed 0 files; `flutter pub
  get` completed; `flutter analyze` reported no issues; `flutter test` passed
  166 tests with 8 GPU-gated skips.
- 2026-07-03: verified locally after final docs update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
