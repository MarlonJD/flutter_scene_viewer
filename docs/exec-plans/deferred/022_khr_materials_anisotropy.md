# KHR_materials_anisotropy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. Plan 019 should establish the shared direct-light loop before Plan
> 022 is promoted.

**Goal:** Render authored directional highlights for brushed metal, machined
finishes, carbon fiber, silk, and satin with complete Khronos factor, rotation,
texture, tangent-frame, direct-light, and IBL semantics.

**Architecture:** The viewer owns glTF fields, texture/UV metadata, tangent
preflight, serialization, diagnostics, and capability truth. A separate
`flutter_scene` checkout owns anisotropic GGX evaluation, tangent-frame
handling, IBL approximation, energy behavior, shader permutations, and resource
budgets. Sampler anisotropic filtering is unrelated and cannot satisfy this
plan.

**Tech Stack:** Dart, Flutter, `flutter_scene`, GLSL, Flutter GPU/Impeller,
WebGL2, glTF `KHR_materials_anisotropy`, Khronos Sample Assets, Filament
standard-material anisotropy as a renderer reference.

## Global Constraints

- Prerequisites: Plan 015 complete and reachable; Plan 019 direct-light loop
  complete. If clearcoat or sheen is not yet reachable, their composition rows
  remain `not run` rather than being skipped silently.
- Do not generate tangents, reinterpret UV sets, lower ordinary roughness, or
  rotate an environment map to fake anisotropy.
- Do not edit pub-cache. This plan authorizes no branch, commit, push, pin, or
  remote operation.
- Package-local parsing may land as diagnostics, but rendered availability
  requires the pinned native importer/material/shader/IBL contract.

---

## Normative and Filament Reference Contract

- [ ] Pin the ratified
  [KHR_materials_anisotropy](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_anisotropy/README.md)
  revision used for implementation.
- [ ] Preserve `anisotropyStrength` default `0` in `[0,1]` and
  `anisotropyRotation` default `0` radians, counter-clockwise in tangent space.
- [ ] Decode the linear anisotropy texture: remap RG from `[0,1]` to the
  tangent-space direction `[-1,1]`; multiply B by the scalar strength. The
  default sample `(1, 0.5, 1)` means +tangent and full texture strength.
- [ ] Reject use with `KHR_materials_unlit` or archived
  `KHR_materials_pbrSpecularGlossiness`.
- [ ] Use [Filament Materials: Anisotropy](https://google.github.io/filament/main/materials.html#materialsystem/standardmodel/anisotropy)
  figures and [Filament anisotropic IBL](https://google.github.io/filament/main/filament.html#lighting/imagebasedlights/anisotropy)
  as implementation/performance references. Filament's current glTF feature
  list does not advertise `KHR_materials_anisotropy`; therefore it is not a
  glTF importer-conformance oracle for this plan.
- [ ] Use the version-pinned
  [Three.js GLTFLoader](https://threejs.org/docs/pages/GLTFLoader.html), which
  advertises `KHR_materials_anisotropy`, as the primary controlled importer/
  shader reference. A harness test must verify strength, rotation, texture, and
  tangent-dependent material state before capture.

## Planned Interface and Files

- Modify `lib/src/material_patch.dart`: add `anisotropyStrength`,
  `anisotropyRotation`, `anisotropyTexture`, and binding metadata.
- Modify `lib/src/texture_binding.dart` and internal texture-role handling for
  a linear RGB data texture; never select sRGB decode.
- Modify `lib/src/material_extension_policy.dart` and
  `lib/src/internal/material_extension_patch_group.dart` with an independent
  anisotropy feature/group.
- Modify `lib/src/internal/glb_material_extension_reader.dart` and
  `lib/src/internal/glb_texture_binding_reader.dart` for factor, rotation,
  texture, sampler, UV0 transform, and tangent requirements.
- Modify native capability/applier/adapter files under `lib/src/internal/`.
- Extend material/reader/policy/applier/adapter tests and add
  `test/anisotropy_tangent_contract_test.dart` and
  `test/renderer_native_anisotropy_corpus_test.dart`.

Paths relative to the separate upstream checkout:

- Modify `packages/flutter_scene/lib/src/material/physically_based_material.dart`.
- Modify `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`.
- Modify `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/pbr.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag` for tangent-
  oriented anisotropic direct and IBL evaluation.
- Modify `packages/flutter_scene/lib/src/importer/src/gltf/primitive_packer.dart`
  and `packages/flutter_scene/lib/src/runtime_importer/geometry_builder.dart`
  only to expose/validate existing tangent presence; do not synthesize
  authoring data in this plan.
- Add upstream importer, material, shader, and visual regression tests.

## Task 1: Write RED Field, Texture, and Tangent Tests

- [ ] Cover absent/default, strength 0/1/out-of-range, rotations including
  wrap-equivalent angles, default texture sample, RG direction, B strength,
  factor multiplication, malformed vectors, UV0 transform, UV1+, and missing
  tangent frames.
- [ ] Prove a base normal texture or valid NORMAL+TANGENT data gives the
  renderer a defined tangent frame; otherwise return a typed capability
  diagnostic under the renderer's documented derivation rules.
- [ ] Cover unlit/specGloss exclusions and required-extension atomic failure.
- [ ] Run `flutter test test/glb_material_extension_reader_test.dart
  test/material_patch_test.dart test/anisotropy_tangent_contract_test.dart`;
  expect RED failures only for missing anisotropy contracts.

## Task 2: Implement Viewer Intent and Diagnostics

- [ ] Add validated fields, binding, merge/reset, JSON, equality, feature
  classification, and independent patch grouping.
- [ ] Preserve linear RGB bytes, sampler state, and UV0 transform. Diagnose
  external/unsupported sources and UV1+ without substituting coordinates.
- [ ] Add a mesh/tangent preflight result that names the affected
  `PartAddress`; do not mutate a live material if any requested field cannot be
  consumed.
- [ ] Keep availability diagnostic-only until native capability probing sees
  all requested fields and renderer paths.
- [ ] Re-run focused viewer tests; expect all wrapper cases to pass.

## Task 3: Add Renderer-Native Direct Anisotropy

- [ ] Add upstream fields/defaults/copying/import mapping and construct the
  rotated tangent/bitangent direction from scalar rotation and texture RG.
- [ ] Implement anisotropic microfacet NDF/visibility for directional, point,
  and spot light samples from Plan 019's shared loop. Preserve isotropic output
  at effective strength zero.
- [ ] Keep the base lobe's Fresnel/IOR/specular and energy compensation intact;
  clearcoat remains an isotropic layer above the anisotropic base.
- [ ] Test tangent and bitangent highlight orientation, positive rotation,
  mirrored transforms, double-sided normals, normal maps, shadows, and no-light
  behavior.
- [ ] Run upstream `flutter test test/gltf_anisotropy_import_test.dart
  test/anisotropic_pbr_test.dart test/material_lighting_test.dart`; expect all
  to pass.

## Task 4: Add Reviewed Anisotropic IBL

- [ ] Implement and document the selected IBL method. Filament's bent-
  reflection-vector technique is an allowed starting reference, not an
  automatic conformance result.
- [ ] Test direction rotation under a fixed HDRI, roughness/strength sweeps,
  tangent vs bitangent alignment, and zero-strength equivalence.
- [ ] Measure ALU, sampler, uniform, precision, and shader-variant impact on
  iOS Simulator, physical iOS, Android, and Web where claimed. Exceeding a
  backend budget must diagnose rather than fall back to isotropic shading.
- [ ] Run upstream shader/resource tests; expect no regression for materials
  without anisotropy.

## Task 5: Integrate and Prove Composition

- [ ] Obtain authorization before upstream commit/publication or viewer pin
  changes, then pin only an externally reachable revision.
- [ ] Add capability probing and atomic application for all fields/textures.
- [ ] Cover base textures, specular/IOR, sheen, clearcoat, alpha/mask,
  double-sided state, emission, shadows, fog, reset, persistence, and disposal.
- [ ] Prove clearcoat remains above the anisotropic base and does not inherit
  base anisotropy unless a future glTF contract explicitly says so.

## Task 6: Controlled Corpus and Verification

- [ ] Stage hash/license-pinned Khronos AnisotropyBarnLamp,
  AnisotropyDiscTest, AnisotropyRotationTest, and a carbon-fiber/brushed-metal
  fixture.
- [ ] Capture close direct-only, IBL-only, and combined views against Khronos
  Sample Viewer and Three.js. Use Filament figures/builds as a qualitative
  renderer reference with its version and mapping differences recorded.
- [ ] Update docs/capability evidence, then run `bash tools/run_checks.sh`,
  `python3 tools/repo_lint.py`, and `git diff --check`; expect all to pass.

## Acceptance Criteria

- [ ] Field defaults/ranges, rotation, texture channels, multiplication,
  color space, samplers, UV0, and tangent handling match Khronos.
- [ ] Direct and IBL highlights rotate predictably and collapse to the
  isotropic native result at zero strength.
- [ ] Missing tangents/resources/UV support are atomic diagnostics, never a
  roughness or environment fake.
- [ ] Clearcoat/specular/IOR/normal/double-sided/shadow composition is covered.
- [ ] A reachable native pin and fixed-state target evidence back every release
  claim.

## Progress Log

- 2026-07-16: Created as deferred. Implementation and target evidence are
  `not run`; Plan 019 is the direct-light prerequisite.

## Verification Log

- 2026-07-16: Plan checked against Khronos semantics, current tangent/texture
  boundaries, and Filament anisotropy examples. Filament is recorded only as a
  renderer reference.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
