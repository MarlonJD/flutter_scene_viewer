# KHR_materials_diffuse_transmission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred and specification-gated.** The extension is a
> Khronos Release Candidate, not ratified. Plan 015 is complete and no
> successor is active. A stable public API still requires the activation audit
> below.

**Goal:** Preserve and eventually render thin-surface diffuse transmission for
paper, leaves, thin fabric, and bounded wax-like approximations without
confusing it with alpha blending or specular glass transmission.

**Architecture:** The viewer first owns a revision-pinned schema monitor,
diagnostics, fixture provenance, and feasibility record. Only after the
extension contract is stable enough does it expose public fields and
persistence. `flutter_scene` owns backside diffuse BRDF/BTDF integration,
direct and environment transport, interaction with volume/specular
transmission, energy allocation, and performance.

**Tech Stack:** Dart, Flutter, `flutter_scene`, GLSL, Flutter GPU/Impeller,
WebGL2, release-candidate `KHR_materials_diffuse_transmission`, Khronos Sample
Assets/Sample Viewer, Three.js.

## Global Constraints

- Pin the exact Khronos commit at activation and re-audit status/schema before
  writing public Dart API. If fields or semantics changed, update this plan and
  obtain user approval before implementation.
- Do not use ordinary alpha blend, two-sided diffuse reflection, emissive
  color, screen-space blur, or `KHR_materials_transmission` as a substitute.
- Do not edit pub-cache. This plan authorizes no branch, commit, push, pin, or
  remote write.
- Filament's current glTF feature list does not advertise this extension.
  Filament translucency/subsurface code may inform renderer tradeoffs only; it
  is not conformance evidence.
- Three.js `GLTFLoader` also does not currently advertise this Release
  Candidate. Unless a separately pinned and tested plugin adds it, Three.js is
  not a reference renderer for Plan 024; use Khronos Sample Viewer instead.

---

## Activation Audit and Current RC Contract

- [ ] Record the activation-date extension registry status and exact commit of
  [KHR_materials_diffuse_transmission](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_diffuse_transmission/README.md).
- [ ] Compare schema, validator, sample assets, and Sample Viewer implementation
  with this 2026-07-16 baseline before freezing any API.
- [ ] Current baseline: `diffuseTransmissionFactor` default `0` in `[0,1]`;
  multiply by linear A from `diffuseTransmissionTexture`.
- [ ] Current baseline: `diffuseTransmissionColorFactor` default `[1,1,1]`;
  multiply by sRGB-decoded RGB from
  `diffuseTransmissionColorTexture`.
- [ ] Current baseline: energy moves between diffuse reflection and a diffuse
  BTDF after interface Fresnel; it does not alter the specular reflection term.
- [ ] Current baseline: if specular `KHR_materials_transmission` is also active,
  that effect overrides diffuse transmission. With `KHR_materials_volume`, the
  diffuse BTDF describes the boundary while volume owns internal transport.

The plan remains research-only if the activation audit cannot freeze these
semantics or if renderer feasibility cannot meet the acceptance gates.

## Planned Interface and Files After the Activation Gate

- Modify `lib/src/material_patch.dart`: add factor, color factor, both textures,
  and bindings using the activation-audited Khronos names.
- Modify texture roles, extension policy, patch groups, GLB reader, texture
  reader, native capability/applier, and adapter files under `lib/src/`.
- Add `lib/src/internal/diffuse_transmission_spec_revision.dart` containing the
  pinned Khronos commit/status and a test that forces intentional review when
  updated.
- Extend wrapper tests and add
  `test/diffuse_transmission_spec_revision_test.dart` and
  `test/renderer_native_diffuse_transmission_corpus_test.dart`.

Paths relative to the separate upstream checkout:

- Modify `packages/flutter_scene/lib/src/material/physically_based_material.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`.
- Modify `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/pbr.glsl`,
  `packages/flutter_scene/shaders/material_lighting.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag` for standard
  material direct and IBL integration.
- Add upstream backside-direct, environment-transmission, composition,
  precision, and performance tests.
- Do not create viewer-local full-fragment production shading for this RC
  extension.

## Task 1: Complete the Revision and Feasibility Gate

- [ ] Pin/read the official spec, JSON schema, validator rules, sample fixtures,
  and Khronos Sample Viewer code at one commit.
- [ ] Produce `docs/references/diffuse_transmission_feasibility.md` covering
  direct backside lighting, diffuse environment transmission, normal/
  double-sided handling, volume interaction, mobile cost, and target limits.
- [ ] Audit whether `flutter_scene` can evaluate opposite-hemisphere direct
  light and environment irradiance without a replacement renderer.
- [ ] Stop with literal `blocked` status if the spec is unstable or the renderer
  design exceeds project boundaries; do not expose speculative public fields.

## Task 2: Write RED Schema and Fallback Tests

- [ ] After the gate, cover defaults, 0/1, factor×A, color×sRGB RGB, invalid
  ranges/vectors, malformed objects, samplers, UV0 transform, UV1+, external
  sources, unlit/specGloss exclusions, optional fallback, and required atomic
  failure.
- [ ] Prove alpha/alphaMode remain coverage controls and are not changed by the
  diffuse transmission factor or texture A channel.
- [ ] Prove independent grouping prevents one invalid field from discarding
  valid clearcoat/specular/transmission intent.
- [ ] Run focused wrapper tests; expect RED failures only for the gated missing
  contracts.

## Task 3: Implement Intent Preservation

- [ ] Add fields, bindings, validation, merge/reset/JSON/equality/persistence,
  feature/group classification, texture decode roles, and atomic diagnostics.
- [ ] Preserve factor texture as linear A and color texture as sRGB RGB. Never
  reuse the same alpha value for material coverage.
- [ ] Keep capability diagnostic-only until pinned renderer-native direct and
  indirect paths consume all requested fields.
- [ ] Re-run wrapper tests; expect all intent/fallback cases to pass.

## Task 4: Implement Renderer-Native Direct Diffuse BTDF

- [ ] Add upstream fields/defaults/copy/import mapping and evaluate a diffuse
  BTDF only when view and light lie on opposite hemispheres.
- [ ] Allocate the non-specular interface-transmitted energy between diffuse
  BRDF and BTDF using the factor; leave specular Fresnel/reflection unchanged.
- [ ] Handle directional, point, and spot lights through Plan 019's shared loop,
  including shadows/occlusion with an explicitly documented thin-surface
  policy.
- [ ] Test one-/double-sided meshes, normal maps, mirrored transforms,
  backlighting, same-side lighting, zero factor, alpha modes, and shadowed
  emitters.

## Task 5: Implement Diffuse Environment Transmission and Composition

- [ ] Define opposite-hemisphere environment irradiance sampling without
  reusing specular radiance/refraction.
- [ ] Test color attenuation, environment rotation, factor sweeps, direct-only,
  IBL-only, and combined passes.
- [ ] Implement audited precedence with `KHR_materials_transmission` and
  boundary behavior with volume. Cover clearcoat/specular/IOR and emission
  without double-counted energy.
- [ ] Measure shader/resource cost and preserve the old path for materials with
  zero effective diffuse transmission.

## Task 6: Integrate and Capture Evidence

- [ ] Obtain authorization before upstream commit/publication or dependency-pin
  changes; integrate only a reachable revision.
- [ ] Stage hash/license-pinned Khronos `DiffuseTransmissionPlant`,
  `DiffuseTransmissionTeacup`, and `DiffuseTransmissionTest` from the activation
  revision, plus bounded paper/currency and candle/volume composition fixtures.
- [ ] Capture close frontlit/backlit, direct-only, IBL-only, and combined views
  against Khronos Sample Viewer. Three.js may be added only through a pinned
  plugin whose loaded fields and shader path are contract-tested. Filament may
  appear only in a separately labeled renderer-research comparison.
- [ ] Record spec commit, validator version, fixture hashes, fixed state,
  renderer revisions, target/backend, metrics, and literal evidence labels.

## Task 7: Close Documentation and Verification

- [ ] Update API/docs/capability matrix only after the activation and native
  gates. Keep Release Candidate wording until the registry says otherwise.
- [ ] Run upstream tests, `bash tools/run_checks.sh`,
  `python3 tools/repo_lint.py`, and `git diff --check`; expect all to pass.

## Acceptance Criteria

- [ ] Activation records one exact, sufficiently stable Khronos contract; no
  speculative API ships before that gate.
- [ ] Factor×A, color×sRGB RGB, alpha independence, energy transfer, backside
  direct lighting, and environment transmission match the pinned contract.
- [ ] Specular transmission override and volume-boundary interaction are
  explicitly tested.
- [ ] No alpha/two-sided/emissive/blur fake exists and all failures are atomic.
- [ ] Release claims require a reachable native pin and fixed-state evidence;
  Filament is not cited as extension conformance.

## Progress Log

- 2026-07-16: Created as deferred and Release-Candidate-gated. Implementation,
  feasibility review, and target evidence are `not run`.

## Verification Log

- 2026-07-16: Current baseline checked against the official RC text, including
  A-channel factor, sRGB color, energy allocation, transmission precedence, and
  volume interaction.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
