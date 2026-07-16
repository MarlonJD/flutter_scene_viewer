# KHR_materials_iridescence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. Plan 019 is a prerequisite for shared punctual-light evaluation.

**Goal:** Render physically grounded thin-film color shifts for coatings,
automotive paint, soap-film surfaces, and coated glass/plastic using the full
Khronos factor, IOR, thickness, texture, direct-light, and IBL contract.

**Architecture:** The viewer owns exact glTF fields, validation, texture
channels/color spaces, serialization, intent isolation, diagnostics, and
evidence. `flutter_scene` owns thin-film Fresnel math, spectral-to-RGB
approximation, direct/IBL integration, energy layering, shader variants, and
precision/performance limits.

**Tech Stack:** Dart, Flutter, `flutter_scene`, GLSL, Flutter GPU/Impeller,
WebGL2, `KHR_materials_iridescence`, Khronos Sample Assets, Khronos Sample
Viewer and Three.js reference captures.

## Global Constraints

- Prerequisites: Plans 015 and 019 complete. Plan 016 is required only for
  volume/transmission composition evidence, not for opaque thin-film support.
- Do not use a rainbow texture, screen-space hue shift, view-angle LUT without
  reviewed physical axes, or asset-specific color tuning.
- Do not edit pub-cache. This plan grants no branch, commit, push, pin, or
  remote authority.
- Filament's current glTF feature list does not advertise
  `KHR_materials_iridescence`; do not cite Filament as import/conformance
  evidence. General Filament Fresnel/energy practices may be design references
  only when the exact difference is recorded.

---

## Normative Contract

- [ ] Pin the ratified
  [KHR_materials_iridescence](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_iridescence/README.md)
  revision used by implementation and fixtures.
- [ ] Preserve `iridescenceFactor` default `0` in `[0,1]`, multiplied by the
  linear R channel of `iridescenceTexture`.
- [ ] Preserve `iridescenceIor` default `1.3` and validate the normative range.
- [ ] Preserve thickness minimum default `100 nm` and maximum default `400 nm`;
  validate `minimum <= maximum` and normative ranges.
- [ ] Sample linear G from `iridescenceThicknessTexture` and compute
  `mix(minimum, maximum, G)`; without a texture, use maximum thickness.
- [ ] Treat the effect as thin-film Fresnel at the material interface. Compose
  with metallic-roughness, `KHR_materials_specular`, `KHR_materials_ior`, and
  clearcoat using the Khronos layering rules.
- [ ] Use version-pinned Three.js GLTFLoader plus the official
  [Three.js iridescence example](https://threejs.org/examples/webgpu_loader_gltf_iridescence.html)
  as controlled references. Assert loaded factor, IOR, thickness range, and
  both maps before capture; do not accept the screenshot alone.

## Planned Interface and Files

- Modify `lib/src/material_patch.dart`: add factor, IOR, thickness minimum/
  maximum, factor texture, thickness texture, and bindings.
- Modify texture-role, extension-policy, patch-group, GLB reader, texture
  reader, native applier/capability, and adapter files under `lib/src/`.
- Add/extend tests for material patch, GLB extension reader, textures, policy,
  applier, controller, adapter, shader resources, and create
  `test/renderer_native_iridescence_corpus_test.dart`.

Paths relative to the separate upstream checkout:

- Modify `packages/flutter_scene/lib/src/material/physically_based_material.dart`.
- Modify `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`.
- Modify `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/pbr.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`.
- Add a reviewed thin-film helper/LUT file under
  `packages/flutter_scene/shaders/` only if its inputs, data generation,
  precision, license, and resource lifecycle are tested and documented.
- Add upstream importer, material, shader, precision, and visual tests.

## Task 1: Write RED Field and Texture Tests

- [ ] Cover absent/defaults, factor 0/1, R multiplication, IOR, fixed and ranged
  thickness, G=0/0.5/1 interpolation, no-texture=max, malformed vectors,
  invalid ranges, UV0 transform, UV1+, and color-space selection.
- [ ] Cover unlit/specGloss exclusions, optional fallback, required atomic
  failure, and isolation from valid clearcoat/specular/IOR groups.
- [ ] Cover merge/reset/JSON/equality/persistence for every field and binding.
- [ ] Run `flutter test test/material_patch_test.dart
  test/glb_material_extension_reader_test.dart
  test/glb_texture_binding_reader_test.dart`; expect RED failures only for the
  missing iridescence contract.

## Task 2: Implement Viewer Intent Preservation

- [ ] Parse/validate fields and embedded textures as independent intent;
  preserve samplers and UV0 transforms, diagnose UV1+ and unsupported sources.
- [ ] Use linear data sampling for both factor R and thickness G. Do not apply
  sRGB conversion.
- [ ] Add feature/group/capability vocabulary and atomic native application.
  Availability requires all scalar, texture, direct, and IBL contracts.
- [ ] Re-run wrapper tests; expect parsing, serialization, reset, and
  diagnostics to pass while renderer evidence remains `not run`.

## Task 3: Implement Renderer-Native Thin-Film Direct Lighting

- [ ] Add upstream fields/defaults/copy/import mapping and a reviewed thin-film
  Fresnel approximation that accounts for film IOR, base interface, thickness,
  angle, and spectral interference before RGB reconstruction.
- [ ] Integrate through Plan 019's shared directional/point/spot loop without
  adding emission or changing base roughness.
- [ ] Preserve exact native-equivalent output at effective factor zero and
  tested convergence across thickness/IOR boundaries.
- [ ] Compose dielectric and conductor cases, `KHR_materials_specular`/IOR, and
  clearcoat. Document the simplified top-interface rule when clearcoat is
  present and prevent double-counted Fresnel energy.
- [ ] Run upstream `flutter test test/gltf_iridescence_import_test.dart
  test/thin_film_fresnel_test.dart test/material_lighting_test.dart`; expect all
  to pass.

## Task 4: Add Iridescent IBL and Resource Bounds

- [ ] Define how thin-film Fresnel modifies split-sum IBL or a reviewed
  alternative. Any LUT must have generated-source tests, axes, format,
  interpolation, and zero-factor behavior documented.
- [ ] Test fixed HDRI rotations, roughness, factor, IOR, and thickness sweeps on
  metallic and dielectric fixtures.
- [ ] Measure precision/banding and shader ALU/sampler/uniform impact on each
  claimed backend. Resource failure diagnoses before material mutation.
- [ ] Prove non-iridescent materials keep the existing shader/resource path.

## Task 5: Integrate, Compose, and Capture Evidence

- [ ] Obtain authorization before upstream commit/publication or pin changes,
  then integrate only a reachable revision.
- [ ] Cover normal maps, specular/IOR, clearcoat, transmission/volume when
  available, alpha, double-sided, shadows, fog, reset, persistence, and
  disposal.
- [ ] Stage Khronos IridescenceDielectricSpheres,
  IridescenceMetallicSpheres, IridescenceLamp, and IridescenceSuzanne with
  provenance and hashes.
- [ ] Capture close direct-only, IBL-only, and combined views against Khronos
  Sample Viewer and Three.js under the fixed state. Record hue/order changes
  over angle and thickness rather than accepting a generic rainbow appearance.

## Task 6: Close Documentation and Verification

- [ ] Update public API, materials/lighting, runtime pipeline, capability
  matrix, renderer notes, fixtures, and platform evidence.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass before completion.

## Acceptance Criteria

- [ ] All defaults/ranges, R/G channels, multiplication/interpolation, no-
  texture behavior, UV, sampler, and linear-data semantics match Khronos.
- [ ] Direct and IBL response changes with view/light angle and nanometer
  thickness through reviewed thin-film physics, not a rainbow overlay.
- [ ] Effective factor zero is native-equivalent and combined Fresnel layers do
  not double-count energy.
- [ ] Unsupported required/malformed intent is atomic and typed.
- [ ] Every claimed target has a reachable native pin and fixed-state corpus
  evidence; Filament is not misrepresented as glTF iridescence evidence.

## Progress Log

- 2026-07-16: Created as deferred. Implementation and target evidence are
  `not run`; Plans 015 and 019 are prerequisites.

## Verification Log

- 2026-07-16: Plan checked against ratified Khronos semantics and current
  Filament glTF support boundaries.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
