# Exec plan: viewer widget and adaptive render scheduler

## Goal

Implement the user-facing widget with camera controls and adaptive render policy.

## Non-goals

- Do not implement VR controls.
- Do not claim power savings without measurement.

## Steps

1. Change: implement viewer state machine: idle/loading/ready/error.
   Verify: widget tests.
2. Change: implement orbit/pan/zoom controller shell.
   Verify: pure math tests where possible.
3. Change: implement adaptive render policy using available Flutter APIs.
   Verify: tests for scheduler state transitions.
4. Change: force a render/update after material changes.
   Verify: controller-to-widget test.

## Acceptance criteria

- [x] loading/error states visible;
- [x] no permanent frame loop when idle under adaptive policy;
- [x] material changes trigger a visible update path;
- [x] camera fit API exists and is documented.

## Progress log

- 2026-07-01: Plan created.
- 2026-07-02: Implemented the smallest 004 slice. Assumptions: public
  `ViewerLoadStatus.success` remains the ready state named in `PUBLIC_API.md`;
  the first camera fit shell uses a unit fallback until adapter-provided model
  bounds are added in a later plan; the ready render host remains adapter-backed
  and does not expose concrete `flutter_scene` classes outside the internal
  adapter boundary. Added `AdaptiveRenderScheduler` with loading, interaction
  tail, animation, and explicit one-shot frame state; added pure Dart orbit,
  pan, zoom, and bounds-fit camera math; made the widget show visible loading
  and error states; and made successful material/reset/fit operations request a
  render frame. Verification: targeted red/green tests were run for
  `test/render_scheduler_test.dart`, `test/orbit_camera_controller_test.dart`,
  `test/viewer_widget_test.dart`, and `test/controller_unattached_test.dart`.
  Final full check `bash tools/run_checks.sh` passed: repo lint, dart format
  check, `flutter pub get`, `flutter analyze`, and `flutter test` all completed
  successfully, with the existing GPU-gated GLB fixture test skipped by its
  documented flag.
