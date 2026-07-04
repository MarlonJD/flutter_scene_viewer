# Deferred exec plan: V2 configurator polish

## Goal

Mature the static GLB viewer into a production configurator surface without
expanding into game-engine or CAD-authoring work.

## Source material

- `docs/ROADMAP.md`
- `docs/MATERIALS_AND_LIGHTING.md`
- `docs/PUBLIC_API.md`
- completed v1 plans under `docs/exec-plans/completed/`

## Assumptions

- V1.0 has already resolved the real transmission/glass and clearcoat release
  blockers or explicitly deferred the release.
- Existing raw HDR/EXR and Poly Haven code stays in place. If the implementation
  is already present and remains bounded, tested, and low-maintenance, it may be
  completed as an advanced opt-in environment source.
- A1B32-style textile/fashion GLBs are real V2 target assets, not optional
  showcase files. Local inspection of `/Users/marlonjd/Downloads/A1B32.glb`
  found `KHR_draco_mesh_compression` in `extensionsRequired`, 20 Draco-backed
  primitives, `KHR_materials_specular`, and `KHR_materials_ior`.
- V2 work should be promoted into `docs/exec-plans/active/` one small slice at
  a time before implementation.

## Non-goals

- No VR/AR/OpenXR/WebXR/ARKit/ARCore work.
- No parallax, displacement, terrain, custom shader graph, or custom renderer.
- No skeletal, morph target, blend shape, rig editing, or animation authoring.
- No CAD tessellation or OCCT work in this plan.

## Candidate slices

1. Add curated environment presets as the recommended public workflow.
   Verify: docs, widget tests, and adapter-neutral environment frames cover the
   preset names and fallback behavior.
2. Finish or harden raw HDR/EXR and Poly Haven as advanced opt-in environment
   sources when the existing implementation is close enough to justify it.
   Verify: decoder tests, fake HTTP tests, byte limits, timeouts, cancellation,
   cache behavior, and diagnostics pass without making network HDRI downloads
   implicit.
3. Add curated material preset descriptors for common configurator materials:
   glass, car paint, clearcoat paint, fabric, plastic, and metal.
   Verify: serialization tests and capability diagnostics prevent unsupported
   preset fields from being silently applied.
4. Improve model-authoring diagnostics and guidance for missing UVs,
   unsupported material extensions, ambiguous node paths, and oversized assets.
   Verify: focused unit tests and documentation examples.
5. Harden cache, memory-budget, and large-model behavior.
   Verify: bounded loader/cache tests and `bash tools/run_checks.sh`.
6. Add role-aware imported texture mipmaps for GLB textures. Normal maps must
   be rebuilt with vector-renormalized mips, metallic-roughness/occlusion/data
   maps with linear data mips, and base-color/emissive textures with color mips.
   Verify: a fixture with high-frequency normal and data textures shows the
   assigned imported texture sources use the expected content roles; CarConcept
   wheel/tire evidence no longer reads as smeared tiled-normal noise.
7. Add `KHR_draco_mesh_compression` support for V2 target assets.
   Verify: A1B32 loads without preprocessing, reports the expected node/mesh
   and primitive counts, renders in iOS Simulator, and picks/addresses parts
   through the existing `PartAddress(nodePath, primitiveIndex)` path.
8. Add `EXT_meshopt_compression` support or typed unsupported diagnostics if the
   current target runtime cannot decode it.
   Verify: a meshopt fixture either loads and renders, or produces one clear
   `unsupportedMaterialFeature`/adapter diagnostic without crashing or
   placeholder geometry.
9. Add KTX2 / `KHR_texture_basisu` texture compression support.
   Verify: compressed base-color, normal, data, and emissive texture slots load
   with the correct texture role and without a fake decompression path; missing
   decoder support reports typed diagnostics.
10. Add imported `KHR_materials_specular` support and keep `KHR_materials_ior`
    mapped for non-glass PBR assets as well as glass assets.
    Verify: A1B32 materials preserve specular/IOR intent in capability
    diagnostics or renderer-native material fields; unsupported renderer fields
    do not silently collapse to plain metallic-roughness.
11. Add bounded multi-file `.gltf` resolution only if target assets require it.
   Verify: relative URI resolution, source replacement, cancellation, byte
   limits, timeout behavior, and diagnostics.
12. Add simple rigid/node animation for product interactions such as doors,
   exploded views, or mechanical movement.
   Verify: authored node transform playback tests and adaptive render scheduler
   interaction.

## Acceptance criteria

- [ ] curated environment presets are the documented primary environment path;
- [ ] raw HDR/EXR and Poly Haven are either completed as bounded advanced
      opt-in sources or explicitly left as already-safe existing capability;
- [ ] material presets fail with diagnostics when backend capabilities are
      missing;
- [ ] diagnostics guide app developers toward asset authoring fixes;
- [ ] cache and large-model behavior have bounded tests;
- [ ] imported GLB texture mipmaps are role-aware for color, normal, and data
      textures;
- [ ] `KHR_draco_mesh_compression` is supported for A1B32-style target assets;
- [ ] `EXT_meshopt_compression` is either supported or produces a typed
      unsupported diagnostic without crashing;
- [ ] KTX2 / `KHR_texture_basisu` compression is supported for target texture
      slots or produces typed decoder diagnostics without fake support;
- [ ] `KHR_materials_specular` and non-glass `KHR_materials_ior` are preserved
      through import diagnostics or renderer-native material fields;
- [ ] A1B32 loads and renders in iOS Simulator without manual preprocessing;
- [ ] any multi-file `.gltf` support stays bounded and does not pull in
      streaming scope beyond the explicit V2 compression work;
- [ ] simple rigid/node animation works without introducing skeletal or game
      engine behavior.

## Progress log

- 2026-07-03: Deferred plan created from product roadmap discussion.
- 2026-07-03: Product direction update: raw HDR/EXR and Poly Haven should not
  be removed. They remain non-default, advanced opt-in environment sources and
  may be completed if the existing bounded implementation is low-maintenance.
- 2026-07-03: Product direction update: V1 active plan 010 owns the
  material/effect mask data model for opaque-family channel-packed regional
  material controls. V2 keeps KTX2 / `KHR_texture_basisu` compression and
  packed-mask authoring workflow as a later optimization track.
- 2026-07-04: Product direction update from A1B32 review: V2 must support the
  compression and material-extension features used by real textile/fashion
  assets. `/Users/marlonjd/Downloads/A1B32.glb` and the evidence copy at
  `/private/tmp/fsviewer_ios_evidence_app/assets/a1b32.glb` both declare
  `KHR_draco_mesh_compression` in `extensionsRequired`, use Draco on all 20
  mesh primitives, and also use `KHR_materials_specular` plus
  `KHR_materials_ior`. V2 scope now includes Draco, meshopt, KTX2 /
  `KHR_texture_basisu`, role-aware imported texture mipmaps, and specular/IOR
  preservation as acceptance-gated work rather than optional investigation.

## Verification log

- 2026-07-03: Not run; deferred plan only.
- 2026-07-03: verified locally after V1/V2 material-mask scope update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
- 2026-07-04: verified locally after the A1B32/compression V2 scope update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
