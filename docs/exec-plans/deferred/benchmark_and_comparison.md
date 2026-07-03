# Deferred plan: benchmark and comparison harness

## Status

Deferred. Do not treat this as active execution work until the viewer has a
credible static-model viewing baseline.

## Goal

Create a benchmark harness to compare `flutter_scene_viewer` with
representative Flutter-native, split-native, and WebView-hosted viewer
alternatives fairly before any performance claims.

## Why deferred

Benchmarking now would measure a partial and misleading product surface. The
viewer can render a simple `Box.glb`, but it is not yet a credible viewer for
real model inspection: camera fit still uses a unit-sphere fallback, material
and lighting presentation is not validated with representative assets, and
more complex static models have not been smoke-tested.

This plan should resume only after the active viewer-baseline plan proves that
`FlutterSceneViewer` can display representative static GLBs with usable camera
fit, material visibility, and non-benchmark simulator evidence.

Active debug/evidence work may add opt-in raw stats snapshots for local
inspection, such as FPS samples, frame interval summaries, scheduler state,
camera state, load duration, GLB byte size, and model counters. Those snapshots
are allowed as smoke/debug evidence in v1, but they are not benchmark results
and must not be used for product or competitive performance claims until this
deferred plan is reactivated. They also intentionally do not sample CPU, RAM,
GPU memory, thermals, or power; those require a separate platform diagnostics
plan before they can be reported responsibly.

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
- 2026-07-01: Kept the v2 planning source material and documented that
  selected v2 work must be promoted into `docs/exec-plans/active/` before
  implementation.
- 2026-07-03: Removed the old planning source directory after current direction
  moved into `docs/ROADMAP.md` and deferred exec plans.
- 2026-07-01: Added explicit `docs/WHY.md` comparison categories for
  WebView-hosted and split-native viewer packages, while preserving the
  no-benchmark/no-superiority-claim boundary.
- 2026-07-02: Renumbered from 005 to 006 and marked deferred / not ready until
  render surface integration is complete.
- 2026-07-02: Moved out of `docs/exec-plans/active/` into
  `docs/exec-plans/deferred/`. Current viewer evidence is still too thin for a
  fair benchmark: it shows a simple box render, not a representative viewer.
- 2026-07-02: Clarified that future v1 debug stats snapshots can feed this
  benchmark harness later, but collecting local debug evidence does not
  reactivate benchmarking and does not authorize performance claims.
