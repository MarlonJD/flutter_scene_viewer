# Deferred exec plan: V3 lightweight authored animation

## Goal

Add optional authored GLB animation playback for lightweight interactive scenes
while keeping runtime authoring and game-engine systems out of scope.

## Source material

- `docs/ROADMAP.md`
- `docs/ARCHITECTURE.md`
- completed render scheduler and adapter plans

## Assumptions

- V1/V2 static viewer and configurator behavior remain stable.
- Upstream `flutter_scene` animation support must be audited before public API
  names are committed.
- Skeletal animation is allowed as playback-only future work, not runtime
  posing or editing.

## Non-goals

- No V1/V2 dependency on animation.
- No runtime rig editing, inverse kinematics, ragdoll, cloth, or animation
  authoring tools.
- No physics-driven character system or full game-engine animation stack.
- No morph target or blend shape work unless a later slice proves a concrete
  product need and backend support.

## Candidate slices

1. Audit upstream authored animation capabilities.
   Verify: record exact `flutter_scene` APIs and gaps in capability notes.
2. Add read-only clip metadata reporting.
   Verify: loader tests expose clip names/durations without starting playback.
3. Add playback controls: play, pause, stop, loop, and speed.
   Verify: fake adapter tests plus scheduler tests for continuous rendering
   while animation is active and idle behavior when stopped.
4. Add skeletal playback if upstream support is real and fixtures are
   available.
   Verify: fixture-based smoke and diagnostics for unsupported assets.
5. Revisit morph targets and blend shapes only as V3+ work.
   Verify: product need, upstream support, and fixture evidence must be
   recorded before implementation.

## Acceptance criteria

- [ ] animation APIs are playback-oriented and optional;
- [ ] animation playback does not change static viewer defaults;
- [ ] scheduler behavior renders only while playback needs frames;
- [ ] unsupported skeletal/morph assets produce diagnostics rather than fake
      support;
- [ ] no runtime authoring or engine-style animation tooling is added.

## Progress log

- 2026-07-03: Deferred plan created from product roadmap discussion.

## Verification log

- 2026-07-03: Not run; deferred plan only.
