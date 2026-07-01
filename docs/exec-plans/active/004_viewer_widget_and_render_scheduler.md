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

- [ ] loading/error states visible;
- [ ] no permanent frame loop when idle under adaptive policy;
- [ ] material changes trigger a visible update path;
- [ ] camera fit API exists and is documented.

## Progress log

- 2026-07-01: Plan created.
