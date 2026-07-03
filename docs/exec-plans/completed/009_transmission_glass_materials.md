# Exec plan: advanced PBR release blockers

## Goal

Make v1 transmission/glass and clearcoat material support tracked release
blockers, expose unsupported intent through diagnostics where public fields
exist, and avoid fake material fallbacks.

## Assumptions

- The installed adapter target is `flutter_scene` 0.18.1 from the local pub
  cache.
- V1 glass means real glTF transmission/refraction behavior, not only
  `alphaMode: BLEND` or a low base-color alpha.
- V1 clearcoat means real two-layer coated material behavior, not only a lower
  base roughness value or brighter environment reflection.
- Runtime transmission and volume textures still require authored UV0 when the
  renderer can support them; the viewer must not generate UV unwraps.
- `flutter_scene_viewer` can expose request intent and diagnostics before
  upstream rendering support exists, but v1.0 remains blocked until real glass
  and clearcoat renderer support is available.

## Non-goals

- No custom PBR renderer, GLSL shader, refraction approximation, or alpha-only
  glass fallback.
- No fake clearcoat fallback that only lowers roughness, boosts environment
  intensity, or swaps to a different base material.
- No arbitrary stacked material system beyond proven glTF extension support.
- No VR, AR, OpenXR, WebXR, ARKit, or ARCore work.
- No morph targets, blend shapes, skeletal posing, or deformation work.
- No CAD tessellation, STEP/IGES import, OCCT FFI, UV unwrap, or tangent
  generation work.
- Do not remove or expand the existing raw HDR/EXR or Poly Haven environment
  code as part of this plan.

## Steps

1. Change: audit installed `flutter_scene` material/importer capabilities for
   `KHR_materials_transmission`, `KHR_materials_ior`, and
   `KHR_materials_volume`.
   Verify: record exact source observations in
   `docs/references/flutter_scene_capability_notes.md`.
2. Change: audit installed `flutter_scene` material/importer capabilities for
   `KHR_materials_clearcoat`.
   Verify: record exact source observations in
   `docs/references/flutter_scene_capability_notes.md`.
3. Change: add public `MaterialPatch` fields for transmission, IOR, and volume
   request intent while rejecting them with `unsupportedMaterialFeature` until
   upstream support exists.
   Verify: unit tests cover JSON round-trip and unsupported diagnostics.
4. Change: add public clearcoat patch intent fields (`clearcoat`,
   `clearcoatTexture`, `clearcoatRoughness`, `clearcoatRoughnessTexture`,
   `clearcoatNormalTexture`, `clearcoatNormalScale`) only when they can either
   bind to real upstream `KHR_materials_clearcoat` capability or return
   explicit unsupported-feature diagnostics without fake rendering.
   Verify: tests cover merge, JSON round-trip, diagnostics, and non-persistence
   for unsupported clearcoat requests.
5. Change: guard the runtime adapter against direct internal unsupported PBR
   extension patch calls.
   Verify: focused controller/material tests show unsupported glass is not
   applied or stored and unsupported clearcoat is not faked.
6. Change: update public scope docs to say transmission/glass and clearcoat are
   required for v1 and currently blocked by upstream capability.
   Verify: docs no longer list transmission/glass or clearcoat as v1 non-goals.
7. Change: after `flutter_scene` exposes real transmission/refraction/Fresnel,
   IOR, volume attenuation, and clearcoat support, map these patch fields to the
   adapter.
   Verify: add GPU-gated visual/material smoke coverage with representative
   glass and clearcoat GLBs and keep unsupported-extension diagnostics for
   unavailable renderer versions.

## Acceptance criteria

- [x] One active v1 advanced-PBR release blocker plan exists.
- [x] Installed `flutter_scene` glass audit is recorded.
- [x] Glass patch intent is serializable and rejected with a capability
  diagnostic instead of fake rendering.
- [x] Runtime controller calls do not apply or persist unsupported glass
  patches.
- [x] Installed `flutter_scene` clearcoat audit is recorded.
- [x] Clearcoat patch intent is serializable and rejected with a capability
  diagnostic instead of fake rendering, or is bound to real upstream support.
- [ ] V1 production glass rendering is supported through real upstream
  transmission/refraction/Fresnel, IOR, and volume attenuation behavior.
- [ ] V1 production clearcoat rendering is supported through real upstream
  clearcoat behavior.

## Progress log

- 2026-07-03: Created this active plan after finding no active plans in
  `docs/exec-plans/active/`. Existing plan moves under `completed/` were
  already present in the worktree and were left untouched.
- 2026-07-03: Assumption: user direction supersedes older docs that excluded
  transmission/glass from v1; glass is now a v1.0 release blocker.
- 2026-07-03: Audited local `flutter_scene` 0.18.1. `PhysicallyBasedMaterial`
  exposes core metallic-roughness PBR, alpha, double-sided behavior, and
  environment overrides, but no transmission, IOR, or volume fields. The
  runtime glTF material importer parses core PBR and `KHR_materials_unlit`,
  but not `KHR_materials_transmission`, `KHR_materials_ior`, or
  `KHR_materials_volume`.
- 2026-07-03: Added failing tests first for glass `MaterialPatch` intent,
  unsupported diagnostics, and controller rejection.
- 2026-07-03: Added serializable glass-intent fields to `MaterialPatch` and
  reject them with `unsupportedMaterialFeature`; added a matching runtime
  adapter guard so direct internal calls do not fall through to alpha or core
  PBR handling.
- 2026-07-03: Product roadmap update: clearcoat is now a v1.0 release blocker
  alongside transmission/glass. Local `flutter_scene` 0.18.1 source audit found
  no public clearcoat material fields and no `KHR_materials_clearcoat`
  parser/importer path. Updated this active plan to track clearcoat without
  faking it through roughness or environment tweaks.
- 2026-07-03: Added `docs/ROADMAP.md` as the current V1/V2/V3/V4 roadmap,
  added deferred V2 configurator polish, V3 lightweight animation, and V4 CAD
  import research exec plans, and aligned README/material/public API/runtime
  pipeline/risk/capability docs with the current scope decisions.
- 2026-07-03: Updated material, public API, runtime pipeline, capability,
  README, risk, and capability-matrix docs to treat transmission/glass and
  clearcoat as v1 release blockers that are currently blocked by upstream
  `flutter_scene` support.
- 2026-07-03: Re-audited local `flutter_scene` 0.18.1 source through
  `.dart_tool/package_config.json`. `PhysicallyBasedMaterial`,
  `runtime_importer/material_builder.dart`, `importer/src/gltf/parser.dart`,
  and `importer/src/gltf/types.dart` expose/import core PBR and
  `KHR_materials_unlit`, but not `KHR_materials_transmission`,
  `KHR_materials_ior`, `KHR_materials_volume`, or
  `KHR_materials_clearcoat`. Recorded the exact source observations in
  `docs/references/flutter_scene_capability_notes.md`.
- 2026-07-03: Added failing clearcoat tests first for JSON round-trip,
  unsupported diagnostics, merge behavior, and controller rejection. The red
  run failed on missing `MaterialPatch` clearcoat constructor fields/getters.
- 2026-07-03: Added serializable clearcoat intent fields to `MaterialPatch` and
  reject them with `unsupportedMaterialFeature`; added a matching runtime
  adapter guard so direct internal calls do not fall through to roughness,
  alpha, or other fake material handling.
- 2026-07-03: Updated public API, materials/lighting, runtime pipeline,
  capability notes, and generated capability matrix docs to reflect diagnostic
  intent fields for transmission/glass and clearcoat while preserving real
  upstream support as the v1 release blocker.

## Verification log

- 2026-07-03: verified locally: `flutter test test/material_patch_test.dart test/viewer_controller_material_test.dart` passed 15 tests after the red/green cycle.
- 2026-07-03: verified locally: `python3 tools/repo_lint.py` passed.
- 2026-07-03: verified locally: `bash tools/run_checks.sh` passed after the
  first sandboxed attempt was blocked by Flutter SDK cache writes. Output
  stages: repo lint passed; dart format check formatted 41 files with 0
  changed; `flutter pub get` succeeded; `flutter analyze` reported no issues;
  `flutter test` passed 110 tests with 3 GPU-gated skips.
- 2026-07-03: verified locally: `bash tools/run_checks.sh` passed; repo lint
  passed; Dart format check reported 41 files with 0 changed; `flutter pub get`
  completed; `flutter analyze` reported no issues; `flutter test` passed 110
  tests with 3 GPU-gated skips.
- 2026-07-03: verified locally after plan-log update:
  `python3 tools/repo_lint.py` passed.
- 2026-07-03: verified locally after roadmap edits:
  `python3 tools/repo_lint.py` passed and `git diff --check` passed.
- 2026-07-03: verified red: `flutter test test/material_patch_test.dart
  test/viewer_controller_material_test.dart` failed before implementation
  because `MaterialPatch` did not expose clearcoat named parameters/getters.
- 2026-07-03: verified locally: `flutter test test/material_patch_test.dart
  test/viewer_controller_material_test.dart` passed 18 tests.
- 2026-07-03: verified locally: `bash tools/run_checks.sh` passed; repo lint
  passed; Dart format check reported 41 files with 0 changed; `flutter pub get`
  completed; `flutter analyze` reported no issues; `flutter test` passed 113
  tests with 3 GPU-gated skips.
- 2026-07-03: verified locally: `python3 tools/repo_lint.py` passed.
