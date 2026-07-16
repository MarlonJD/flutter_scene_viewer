# Exec plan: renderer-native transmission and volume follow-up

> **Status (2026-07-13): deferred.** This is the explicit conditional
> disposition from completed
> [Plan 014 Task 9](../completed/014_selected_gltf_extension_support.md). It does
> not make the package-local screen-space candidate production-ready and does
> not unblock the v1 release gate.

## Goal

Add first-class `KHR_materials_transmission`, `KHR_materials_volume`, and glass
`KHR_materials_ior` contracts to `flutter_scene`, then integrate them through
the viewer only after renderer-owned transport/compositing and selected-target
evidence satisfy the Khronos semantics.

## Assumptions

- Khronos defines factor, texture-channel, alpha, thin-surface, volume,
  attenuation, transform, metal-isolation, and IOR semantics.
- The pinned `flutter_scene` revision
  `ccf7372428961ebe0abb053727fe443150547a74` defines current renderer
  capability. It exposes native clearcoat and scene-color render targets but no standard-material
  transmission, volume, attenuation, or variable-IOR fields and no renderer-
  owned glTF refraction/compositing contract.
- The repository-owned screen-space material remains a narrow
  `candidate-only` path. Availability, release maturity, and target evidence
  stay separate.

## Non-goals

- Do not build a replacement PBR renderer, general shader graph, nested-glass
  system, or order-independent transparency system in
  `flutter_scene_viewer`.
- Do not represent optical transmission with alpha blending, bake textures,
  generate UVs, or add asset-specific glass colors, contours, glints, or
  refraction constants.
- Do not treat simulator-only, skipped, historical, or source-audit evidence
  as physical-device or production-ready evidence.

## Steps

1. Add upstream `flutter_scene` material/importer fields for transmission
   factor and red-channel texture, volume thickness and green-channel texture,
   attenuation color/distance, and material IOR including the exact `ior == 0`
   compatibility mode. Verify with upstream unit tests and a concrete upstream
   commit.
2. Add renderer-owned scene-color sampling and standard-material transport.
   Keep optical transmission separate from alpha-as-coverage, preserve the
   ordinary lit base response at zero factor/texture texels, prevent metallic
   response from transmitting, and keep zero-thickness surfaces free of
   macroscopic refraction.
3. Implement positive volume through mesh-space thickness transformed by node
   scale, world-space attenuation distance, valid entry/exit boundaries, IOR
   refraction, and opaque geometry visible behind the surface. Reject or
   diagnose unsupported topology/compositing cases atomically.
4. Update the viewer dependency pin and advertise runtime capability only
   after the pinned importer, material, render graph, and shader consume every
   requested field. Remove package-local limitations only when the native path
   covers their preserved intent.
5. Run the fixed-state Khronos transmission/volume corpus and focused wrapper
   tests on each selected target. Record runtime capability, release maturity,
   and target evidence independently.

## Acceptance criteria

- [ ] A concrete upstream commit and viewer dependency pin expose the complete
  selected transmission, volume, attenuation, and glass-IOR contract.
- [ ] Factor zero/full, red-channel texture multiplication, alpha independence,
  metal isolation, thin-surface behavior, and opaque-behind-glass tests pass
  without an unlit whole-material fallback.
- [ ] Positive thickness uses the green channel and node/world scale;
  attenuation defaults/infinite distance, attenuation color, IOR interaction,
  and `ior == 0` compatibility pass normative tests.
- [ ] Khronos WaterBottle/GlassVase-style evidence is captured under the fixed
  reference state for every claimed target, including behind-glass geometry
  and volume-specific metrics.
- [ ] No target is labeled `production-ready` without matching local target
  evidence and the Plan 014 release gates.

## Progress log

- 2026-07-13: Created from Plan 014 Task 9 because the pinned renderer lacks a
  native transmission/volume/IOR contract. The package-local factor-only thin
  path remains `candidate-only`; positive thickness, runtime transmission
  textures, and `ior == 0` return typed diagnostics instead of losing intent.

## Verification log

- 2026-07-13: Upstream implementation and selected-target evidence are
  `not run`; this deferred plan records the exact blocker and required closure
  gates only.
