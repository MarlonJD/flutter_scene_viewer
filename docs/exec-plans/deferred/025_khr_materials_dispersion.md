# KHR_materials_dispersion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-17): deferred; native dependency satisfied.** Plans 015
> and 016 are complete. Activation still requires explicit promotion and the
> remaining Plan 025 feasibility/evidence gates; no implementation is implied.

**Goal:** Render wavelength-dependent separation through clear volumes using
the Khronos dispersion parameter, a bounded renderer-owned spectral
approximation, and measurable zero-dispersion equivalence.

**Architecture:** The viewer owns the scalar field, validation, serialization,
dependency diagnostics, atomic application, and evidence labels. A separate
`flutter_scene` checkout owns wavelength sampling, IOR reconstruction,
refraction/volume transport, compositing, noise/performance choices, and shader
resources. Plan 016 supplies the required native transmission/volume/IOR path.

**Tech Stack:** Dart, Flutter, `flutter_scene`, GLSL, Flutter GPU/Impeller,
WebGL2, `KHR_materials_dispersion`, `KHR_materials_volume`, Three.js dispersion
example, Filament refraction/dispersion implementation.

## Global Constraints

- Do not start rendering work without explicit Plan 025 promotion. Plan 016's
  reachable upstream pin satisfies only the native transport prerequisite;
  parsing-only work must remain diagnostic-only until this plan is active.
- Do not fake dispersion with post-process RGB edge offsets, screen-space
  chromatic aberration, or a rainbow texture.
- Do not build an unbounded spectral/path renderer. The selected wavelength
  approximation needs explicit sample count, quality tiers, error, and cost.
- Do not edit pub-cache. This plan authorizes no branch, commit, push, pin, or
  remote operation.

---

## Normative and Reference Contract

- [ ] Pin the ratified
  [KHR_materials_dispersion](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_dispersion/README.md)
  revision used by implementation.
- [ ] Preserve `dispersion` default `0`, require a finite value `>= 0`, and
  treat `[0,1]` as the ordinary realistic range without rejecting larger
  artist values.
- [ ] Interpret the stored value as `20 / AbbeNumber`; zero has the special
  meaning of no dispersion.
- [ ] Require `KHR_materials_volume` and a working refractive transport path.
  A dispersion request without volume is invalid/unsupported and never renders
  as a surface-only effect.
- [ ] Use [Three.js GLTFLoader dispersion example](https://threejs.org/examples/webgl_loader_gltf_dispersion.html)
  and its pinned loader/material implementation as one controlled reference.
- [ ] Use [Filament Materials: Dispersion](https://google.github.io/filament/main/materials.html#materialsystem/standardmodel/dispersion)
  as a renderer reference: it uses the same `20/Abbe` parameter and limits the
  effect to volume refraction. Neither renderer is pixel-parity authority.

## Planned Interface and Files

- Modify `lib/src/material_patch.dart`: add nullable `double dispersion`.
- Modify extension policy/patch group/GLB reader/native capability/applier and
  adapter files under `lib/src/`.
- Extend material, reader, policy, controller, applier, adapter, and
  transmission/volume tests; add
  `test/renderer_native_dispersion_corpus_test.dart`.
- Extend the Three.js harness under
  `tools/reference_renderers/threejs_material_extension_fixture/` with a
  version-pinned dispersion capture and contract test.

Paths relative to the separate upstream checkout:

- Modify `packages/flutter_scene/lib/src/material/physically_based_material.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`.
- Modify Plan 016's renderer-owned refraction/volume files, including
  `packages/flutter_scene/shaders/material_inputs.glsl`,
  `packages/flutter_scene/shaders/pbr.glsl`, and
  `packages/flutter_scene/shaders/flutter_scene_standard.frag`, rather than
  creating a disconnected surface shader.
- Add a documented dispersion helper and tests for wavelength reconstruction,
  sample integration, zero path, precision, noise, and resources.

## Task 1: Verify the Plan 016 Gate and Write RED Dependency Tests

- [ ] Record the reachable Plan 016 upstream revision, its native scene-color
  path, thickness/attenuation/IOR contract, and selected-target evidence.
- [ ] Stop as `blocked` if positive-volume refraction is not renderer-native;
  do not activate a parsing-only feature as support.
- [ ] Write RED tests for absent/default 0, representative values `0.1`,
  `0.36`, `0.625`, `1`, values above 1, negative/non-finite input,
  missing volume, unlit/specGloss exclusions, optional fallback, and required
  atomic failure.
- [ ] Run focused wrapper tests; expect RED failures only for the missing field
  and dependency diagnostics.

## Task 2: Implement Viewer Intent and Atomic Dependency Handling

- [ ] Add validation, merge/reset/JSON/equality/persistence, independent patch
  grouping, capability vocabulary, and typed diagnostics.
- [ ] Require dispersion, volume, transmission/IOR resources, and backend
  capability in one preflight transaction. Failure leaves all live material
  state and render scheduling unchanged.
- [ ] Preserve zero as a fast native-equivalent path and do not select a
  spectral shader variant for effective zero.
- [ ] Re-run wrapper tests; expect all intent/dependency cases to pass while
  visual evidence remains `not run`.

## Task 3: Implement Upstream Import and Spectral Approximation Tests

- [ ] Add first-class field/default/copy/import mapping and implement the
  Khronos Cauchy/Abbe IOR reconstruction at the selected wavelengths.
- [ ] Write numerical tests for the F/d/C reference wavelengths, IOR clamping,
  representative materials, zero, high artist values, and finite output.
- [ ] Select a bounded wavelength integration method and document why its
  RGB reconstruction, sample count, and stochastic/deterministic behavior fit
  mobile targets.
- [ ] Run upstream `flutter test test/gltf_dispersion_import_test.dart
  test/dispersion_math_test.dart`; expect all numerical/parser tests to pass.

## Task 4: Integrate with Native Volume Refraction

- [ ] Evaluate per-wavelength refracted rays through Plan 016's positive-volume
  path, including thickness, attenuation, IOR, node scale, entry/exit
  boundaries, opaque-behind-glass content, and compositing.
- [ ] Prove zero dispersion matches Plan 016 output, dispersion changes only
  refracted transport, and surface reflection/alpha remain stable.
- [ ] Test roughness, attenuation color/distance, normal maps, double-sided
  behavior, nested/unsupported topology diagnostics, camera motion, and render
  scheduling.
- [ ] Measure ALU, texture reads, render passes, bandwidth, precision, temporal
  noise, and memory on each claimed backend; enforce a documented limit.

## Task 5: Integrate Reachable Revision and Reference Harness

- [ ] Obtain authorization before upstream commit/publication or viewer pin
  changes and integrate only a reachable revision.
- [ ] Pin the exact Three.js package in `package.json`/lockfile for this corpus;
  do not compare against a floating `^` range. Add a contract test that
  confirms `GLTFMaterialsDispersionExtension` exists and the fixture material
  has nonzero dispersion after load.
- [ ] Record Filament version, material mapping, camera/exposure, and refraction
  mode for any Filament reference capture.
- [ ] Add viewer capability probing that requires the complete volume,
  refraction, spectral, and compositing contract.

## Task 6: Controlled Evidence and Closure

- [ ] Stage hash/license-pinned Khronos `DispersionTest`, `DragonDispersion`,
  and `CompareDispersion`, plus a zero-dispersion control with visible
  behind-glass geometry.
- [ ] Capture close direct-only, IBL-only, and combined reference views where
  lighting is relevant, plus camera angles that reveal angular separation.
- [ ] Record edge separation/color-order metrics, zero-path diff, noise, frame
  cost, state hash, revisions, targets, and maturity labels.
- [ ] Update docs/capability evidence and run upstream tests,
  `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass.

## Acceptance Criteria

- [ ] Plan 016's reachable native volume/refraction path is a satisfied
  prerequisite, not a mocked dependency.
- [ ] `20/Abbe`, zero semantics, range validation, and volume requirement match
  Khronos.
- [ ] The bounded spectral method has numerical tests, target budgets, stable
  output, and a zero-dispersion native-equivalence test.
- [ ] No screen-space RGB offset/rainbow fake exists and all failures are
  atomic.
- [ ] Three.js and Filament references are version/mapping-pinned; target
  release claims rest on this renderer's own reachable pin and evidence.

## Progress Log

- 2026-07-17: Plan 016's published immutable native transmission/volume/IOR
  pin and iOS Simulator evidence satisfy this plan's first dependency gate.
  Plan 025 remains deferred and all dispersion implementation/evidence items
  remain unchecked.
- 2026-07-16: Created as deferred behind Plan 016. Implementation and target
  evidence are `not run`.

## Verification Log

- 2026-07-16: Plan checked against the ratified Khronos `20/Abbe` contract,
  volume dependency, Three.js official example, and Filament dispersion model.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
