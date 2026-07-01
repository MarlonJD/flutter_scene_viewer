# Exec plan: benchmark and comparison harness

## Goal

Create a benchmark harness to compare `flutter_scene_viewer`, `interactive_3d`,
and WebView/BabylonJS fairly before any performance claims.

## Steps

1. Change: define benchmark metrics and fixture requirements.
   Verify: docs reviewed.
2. Change: add benchmark app skeleton.
   Verify: builds when Flutter toolchain is available.
3. Change: record load-to-first-frame, texture-swap latency, idle GPU behavior,
   frame time percentiles, and peak memory.
   Verify: benchmark report template filled for at least one local run.

## Acceptance criteria

- [ ] no marketing claims without benchmark evidence;
- [ ] metrics include P50/P95/P99, not just FPS;
- [ ] output report template exists.

## Progress log

- 2026-07-01: Plan created.
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
