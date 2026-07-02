# Deferred plan: benchmark and comparison harness

## Status

Deferred. Do not treat this as active execution work until the viewer has a
credible static-model viewing baseline.

## Goal

Create a benchmark harness to compare `flutter_scene_viewer`, `interactive_3d`,
and WebView/BabylonJS fairly before any performance claims.

## Why deferred

Benchmarking now would measure a partial and misleading product surface. The
viewer can render a simple `Box.glb`, but it is not yet a credible viewer for
real model inspection: camera fit still uses a unit-sphere fallback, material
and lighting presentation is not validated with representative assets, and
more complex static models have not been smoke-tested.

This plan should resume only after the active viewer-baseline plan proves that
`FlutterSceneViewer` can display representative static GLBs with usable camera
fit, material visibility, and non-benchmark simulator evidence.

## Future steps

1. Change: define benchmark metrics and fixture requirements.
   Verify: docs reviewed.
2. Change: add benchmark app skeleton.
   Verify: builds when Flutter toolchain is available.
3. Change: record load-to-first-frame, texture-swap latency, idle GPU behavior,
   frame time percentiles, and peak memory.
   Verify: benchmark report template filled for at least one local run.

## Acceptance criteria before reactivation

- [ ] viewer has model-derived bounds and fit-camera behavior;
- [ ] viewer-controlled lighting/material presentation is validated with at
      least one representative static GLB beyond `Box.glb`;
- [ ] active smoke evidence shows the viewer surface, not only load success;
- [ ] no marketing claims are made without benchmark evidence.

## Progress log

- 2026-07-01: Plan created as active 005.
- 2026-07-01: Assumption: README positioning can mention the Flutter
  GPU/Impeller path exposed by `flutter_scene` and WebView-free architecture,
  but must not claim raw performance superiority before the benchmark harness
  exists. Added README positioning and `docs/WHY.md` to explain the difference
  from WebView-based viewers, per-platform native wrappers, raw `flutter_scene`,
  and full 3D engines.
- 2026-07-01: Updated GitHub repository metadata with the same bounded
  positioning; replaced generic `pbr` topic with `flutter-gpu` because GitHub
  allows at most 20 topics.
- 2026-07-01: Removed agent-facing README language and replaced it with
  professional public-facing development status and development commands.
- 2026-07-01: Removed root starter-pack artifacts `MANIFEST.md` and
  `SHA256SUMS.txt`.
- 2026-07-01: Removed root agent-specific instruction files and updated repo
  lint/tooling docs so `AGENTS.md` is the single root agent-facing entry point.
- 2026-07-01: Kept `docs/project-plan-v2/` as v2 planning source material and
  documented that selected v2 work must be promoted into
  `docs/exec-plans/active/` before implementation.
- 2026-07-01: Added explicit `docs/WHY.md` comparisons against
  `interactive_3d` and `babylonjs_viewer` based on current pub.dev package
  descriptions, while preserving the no-benchmark/no-superiority-claim boundary.
- 2026-07-02: Renumbered from 005 to 006 and marked deferred / not ready until
  render surface integration is complete.
- 2026-07-02: Moved out of `docs/exec-plans/active/` into
  `docs/exec-plans/deferred/`. Current viewer evidence is still too thin for a
  fair benchmark: it shows a simple box render, not a representative viewer.
