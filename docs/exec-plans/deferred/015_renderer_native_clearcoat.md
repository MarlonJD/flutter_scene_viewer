# Exec plan: renderer-native clearcoat follow-up

> **Status (2026-07-13): deferred.** This is the explicit conditional
> disposition from active
> [Plan 014 Task 8](../active/014_selected_gltf_extension_support.md). It does
> not make the current package-local shader production-ready and does not
> unblock the v1 release gate.

## Goal

Add a first-class `KHR_materials_clearcoat` contract to `flutter_scene`, then
integrate it through the viewer only after the renderer, importer, and selected
target evidence satisfy the Khronos layering semantics.

## Assumptions

- Khronos defines the glTF factor, texture-channel, normal, and layering
  semantics.
- The pinned `flutter_scene` revision
  `cd6760912fa38beb55f63e388655a1aeabd32fe4` defines current renderer
  capability and has no native clearcoat fields, texture slots, importer
  mapping, or integrated second-lobe shader path.
- The repository-owned translucent overlay remains target-scoped
  `candidate-only` evidence. Availability, maturity, and target evidence stay
  separate.

## Non-goals

- Do not build a replacement PBR renderer or general shader graph in
  `flutter_scene_viewer`.
- Do not lower base roughness, boost environment intensity, bake textures,
  generate UVs, or add asset-specific material fixes to imitate clearcoat.
- Do not treat simulator-only, skipped, or historical candidate evidence as a
  physical-device or production-ready result.

## Steps

1. Add an upstream `flutter_scene` material/importer contract for clearcoat
   factor, red-channel factor texture, roughness factor, green-channel
   roughness texture, and an independent tangent-space normal texture/scale.
   Verify with upstream unit tests and a concrete upstream commit.
2. Integrate an energy-aware second dielectric lobe inside the renderer-owned
   standard PBR path. Preserve base material, emission, alpha, shadows,
   double-sided state, direct lighting, and IBL without double-counting the
   directional highlight or manipulating base roughness.
3. Update the viewer dependency pin and advertise runtime capability only
   after the pinned material, importer, and shader consume every requested
   field. Keep unsupported combinations atomic and diagnostic until then.
4. Run the fixed-state Khronos clearcoat corpus and focused wrapper tests on
   each selected target. Record runtime capability, release maturity, and
   target evidence independently.

## Acceptance criteria

- [ ] A concrete upstream commit and viewer dependency pin expose the complete
  selected clearcoat contract.
- [ ] Factor zero/full, red-channel texture multiplication, roughness/green
  trend, independent coat normal, base attenuation, combined base-plus-coat,
  double-sided, shadow, direct-light, and IBL tests pass without an extra
  heuristic highlight.
- [ ] Khronos `ClearCoatTest`, `ClearCoatCarPaint`, and combined `ToyCar`
  evidence is captured under the fixed reference state for every claimed
  target.
- [ ] No target is labeled `production-ready` without matching local target
  evidence and the Plan 014 release gates.

## Progress log

- 2026-07-13: Created from Plan 014 Task 8 because the pinned renderer lacks a
  native clearcoat contract and the package-local alpha overlay remains
  `candidate-only`.

## Verification log

- 2026-07-13: Upstream implementation and selected-target evidence are
  `not run`; this deferred plan records the blocker and required closure gates
  only.
