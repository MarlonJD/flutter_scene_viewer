# Exec plan: runtime material overrides

## Goal

Apply, merge, persist, and reset core PBR material overrides.

## Non-goals

- No custom GLSL.
- No parallax/displacement/subsurface.
- No fake support for unsupported material features.

## Steps

1. Change: implement `MaterialOverrideStore` snapshots and patch merge semantics.
   Verify: unit tests for merge/reset/all-reset.
2. Change: implement adapter calls for PBR factor changes.
   Verify: fake adapter tests.
3. Change: implement runtime base-color texture flow.
   Verify: Missing UV diagnostic test and successful fake texture application.
4. Change: add JSON serialization for override state.
   Verify: round-trip tests.

## Acceptance criteria

- [ ] original material can be restored;
- [ ] texture override requires UV capability;
- [ ] metallic/roughness values are validated 0..1;
- [ ] patch state can persist and reapply.

## Progress log

- 2026-07-01: Plan created.
