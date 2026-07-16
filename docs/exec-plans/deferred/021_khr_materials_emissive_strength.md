# KHR_materials_emissive_strength Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. Activate Plan 021 only after an explicit user selection.

**Goal:** Preserve and render authored emissive radiance above the core
`[0,1]` emissive-factor range, with honest tone-mapping evidence and no false
dependency on bloom.

**Architecture:** The viewer owns the glTF field, validation, serialization,
authored-intent grouping, runtime patch behavior, diagnostics, and evidence.
`flutter_scene` owns importer mapping, HDR material storage, shader emission,
frame precision, exposure, tone mapping, and optional bloom. The strength is a
multiplier on the existing linear emissive result, not a post-process effect.

**Tech Stack:** Dart, Flutter, `flutter_scene`, Flutter GPU/Impeller, WebGL2,
GLSL, `KHR_materials_emissive_strength`, HDR render targets, tone mapping.

## Global Constraints

- Do not clamp authored or runtime emissive strength to `1`; reject negative or
  non-finite values.
- Bloom is separate. A bright tone-mapped material without glow can still be a
  correct emissive-strength implementation.
- Do not edit pub-cache. Branch, commit, push, pin, and remote operations need
  separate authorization.
- Required unsupported intent is atomic; optional unsupported intent keeps the
  valid core emissive material and reports the lost multiplier.

---

## Normative Contract

- [ ] Pin the ratified
  [KHR_materials_emissive_strength](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_emissive_strength/README.md)
  revision used by implementation and evidence.
- [ ] Preserve `emissiveStrength` as a non-negative unitless number with
  default `1` when the extension exists or is absent.
- [ ] Compute linear emission as
  `emissiveFactor * sRGBToLinear(emissiveTexture.rgb) * emissiveStrength`.
- [ ] Keep alpha coverage, metallic/dielectric classification, clearcoat, and
  direct/IBL terms independent from emitted radiance.
- [ ] Use version-pinned Three.js GLTFLoader and Filament gltfio/emissive HDR
  paths as controlled importer/renderer references. For each, verify the loaded
  multiplier and pre-tone-map behavior; visible bloom alone is invalid proof.

## Planned Interface and Files

- Modify `lib/src/material_patch.dart`: add nullable `double emissiveStrength`
  with validation, merge, reset, equality, hash, JSON, and feature detection.
- Modify `lib/src/material_extension_policy.dart`: add
  `MaterialExtensionFeature.emissiveStrength` and per-target capability rows.
- Modify `lib/src/internal/material_extension_patch_group.dart`: add an
  independent `emissiveStrength` group so a bad multiplier cannot discard
  clearcoat/specular/transmission intent.
- Modify `lib/src/internal/glb_material_extension_reader.dart` and
  `lib/src/internal/material_extension_native_applier.dart`.
- Modify `lib/src/internal/flutter_scene_adapter.dart` and capability probing;
  do not route to a package-local shader if the pinned native material already
  supports the complete field.
- Extend `test/material_patch_test.dart`,
  `test/glb_material_extension_reader_test.dart`,
  `test/material_extension_policy_test.dart`,
  `test/material_extension_native_applier_test.dart`,
  `test/viewer_controller_material_test.dart`, and adapter/backend tests.

Paths relative to the separate upstream checkout:

- Modify `packages/flutter_scene/lib/src/material/physically_based_material.dart`.
- Modify `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and
  `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`.
- Modify `packages/flutter_scene/shaders/material_inputs.glsl` and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag` only as needed
  to keep emission in HDR linear space before tone mapping.
- Add upstream parser/material/shader tests under
  `packages/flutter_scene/test/`.

## Task 1: Write RED Wrapper and Schema Tests

- [ ] Cover absent/default `1`, `0`, `1`, values above `1`, large finite
  values, negative, NaN/infinity, malformed object, and required/optional
  fallback.
- [ ] Cover `MaterialPatch` merge, JSON round-trip, reset, persistence,
  equality, empty classification, and combination with emissive factor/texture.
- [ ] Verify grouped failure leaves other valid extension groups intact and a
  required unsupported request leaves live model bytes/state unchanged.
- [ ] Run `flutter test test/material_patch_test.dart
  test/glb_material_extension_reader_test.dart
  test/material_extension_policy_test.dart`; expect RED failures only for the
  new contract.

## Task 2: Implement Intent Preservation and Capability Truth

- [ ] Parse the scalar without clamping, attach it to its patch group, preserve
  it through load/restore, and emit field-specific diagnostics.
- [ ] Add capability probing that requires the pinned importer, material field,
  and standard shader consumption. Host parsing alone remains diagnostic-only.
- [ ] Apply/reset atomically through the native applier; request one render
  only after a successful change.
- [ ] Re-run Task 1 plus
  `flutter test test/material_extension_native_applier_test.dart
  test/viewer_controller_material_test.dart`; expect all new wrapper tests to
  pass.

## Task 3: Add Upstream Renderer-Native Strength

- [ ] Add first-class field default `1`, copy/clone behavior, finite/range
  validation, runtime and offline importer mapping, and shader uniform packing.
- [ ] Multiply strength after sRGB emissive texture decode and emissive factor,
  while the value is still linear HDR. Do not multiply alpha or apply exposure
  twice.
- [ ] Prove zero strength contributes no emission, one matches the old path,
  and values above one survive until exposure/tone mapping.
- [ ] Test premultiplied output, opaque/mask/blend modes, double-sided state,
  clearcoat layering, no-light/IBL/direct scenes, and frame precision.
- [ ] Run upstream `flutter test test/gltf_emissive_strength_import_test.dart
  test/physically_based_material_test.dart test/emissive_render_test.dart`;
  expect all to pass.

## Task 4: Integrate a Reachable Revision

- [ ] Obtain authorization before creating/publishing an upstream commit or
  changing the viewer dependency pin.
- [ ] Pin the reachable revision, remove any redundant candidate routing, and
  advertise renderer-native availability only when reflection/probing sees the
  complete contract.
- [ ] Add adapter regression tests for factor+texture+strength, reset,
  persistence, clearcoat, alpha, backend failure, and disposal.
- [ ] Run focused viewer tests; expect all to pass with the stable pin.

## Task 5: Produce HDR/Tone-Mapping Evidence

- [ ] Stage hash/license-pinned Khronos `EmissiveStrengthTest` and
  `CompareEmissiveStrength`, plus an LED/display fixture with strengths `0`,
  `1`, `5`, and `50`.
- [ ] Capture linear probe values or pre-tone-map metrics where the backend
  exposes them, then fixed exposure/tone-map output. Record saturation rather
  than judging correctness only by visible color.
- [ ] Capture bloom disabled first. If bloom is later enabled, record it as an
  independent post-process row.
- [ ] Compare against Three.js or Khronos Sample Viewer under identical camera,
  HDRI, direct lights, exposure, tone mapping, color space, and viewport.
- [ ] Pin Three.js exactly and assert the loaded material's emissive intensity
  before capture; record the Filament version and bloom/tone-map settings for
  any Filament capture.

## Task 6: Close Documentation and Verification

- [ ] Update API, materials/lighting, runtime pipeline, capability matrix,
  fixture provenance, and platform evidence with literal maturity labels.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass before plan completion.
- [ ] Move the plan to completed only with a reachable renderer pin and
  matching evidence for each claimed target.

## Acceptance Criteria

- [ ] Defaults, non-negative range, factor/texture multiplication, color-space
  order, and values above one match Khronos semantics.
- [ ] Emission remains independent from alpha, clearcoat, lighting, and bloom;
  strength `1` is native-equivalent.
- [ ] Parsing or candidate output alone never advertises renderer-native
  availability.
- [ ] Required/malformed failure is atomic and optional fallback names the lost
  feature.
- [ ] Evidence records HDR/pre-tone-map behavior or a documented proxy plus
  fixed exposure/tone mapping on every claimed target.

## Progress Log

- 2026-07-16: Created as deferred in the user-approved extension sequence.
  Implementation, upstream work, and target evidence are `not run`.

## Verification Log

- 2026-07-16: Plan content checked against the ratified Khronos field and the
  pinned renderer's current emissive factor/texture path.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
