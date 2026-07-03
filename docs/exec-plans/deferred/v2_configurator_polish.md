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
6. Investigate KTX2 / `KHR_texture_basisu` texture compression and packed
   material-mask authoring guidance after the V1 opaque-family effect-mask
   data model is in place.
   Verify: capability notes, fixture evidence, and diagnostics prove whether
   the installed `flutter_scene` target can import compressed textures without
   a fake decompression path.
7. Add bounded multi-file `.gltf` resolution only if target assets require it.
   Verify: relative URI resolution, source replacement, cancellation, byte
   limits, timeout behavior, and diagnostics.
8. Add simple rigid/node animation for product interactions such as doors,
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
- [ ] KTX2 / `KHR_texture_basisu` compression remains a separate V2
      investigation and does not block the V1 material/effect mask data model;
- [ ] any multi-file `.gltf` support stays bounded and does not pull in
      streaming scope or unrelated compression implementation;
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

## Verification log

- 2026-07-03: Not run; deferred plan only.
- 2026-07-03: verified locally after V1/V2 material-mask scope update:
  `python3 tools/repo_lint.py` passed and `git diff --check` reported no
  whitespace errors.
