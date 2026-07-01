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
