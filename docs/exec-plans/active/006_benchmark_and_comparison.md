# Exec plan: benchmark and comparison harness

## Status

Deferred / not ready until the viewer can render the loaded GLB on screen.

## Goal

Create a benchmark harness to compare `flutter_scene_viewer`, `interactive_3d`,
and WebView/BabylonJS fairly before any performance claims.

## Why deferred

Benchmarking before render surface integration would only measure a partial
pipeline: GLB loading, load state transitions, and `ViewerLoadStatus.success`.
That is not a viewer benchmark. This plan should resume after
`005_render_surface_integration.md` proves that `FlutterSceneViewer` displays
the loaded model.

## Steps

1. Change: define benchmark metrics and fixture requirements.
   Verify: docs reviewed.
2. Change: add benchmark app skeleton.
   Verify: builds when Flutter toolchain is available.
3. Change: record load-to-first-frame, texture-swap latency, idle GPU behavior,
   frame time percentiles, and peak memory.
   Verify: benchmark report template filled for at least one local run.

## Acceptance criteria

- [ ] render surface integration is complete before benchmark collection starts;
- [ ] no marketing claims without benchmark evidence;
- [ ] metrics include P50/P95/P99, not just FPS;
- [ ] output report template exists.

## Progress log

- 2026-07-01: Plan created as 005.
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
  render surface integration is complete. Benchmark collection should measure a
  visible viewer, not only a successful GLB load state.
