# Deferred exec plan: V4 CAD import research

## Goal

Evaluate whether CAD import belongs in or beside `flutter_scene_viewer` through
a real OCCT FFI plus STEP/IGES import track.

## Source material

- `docs/ROADMAP.md`
- `docs/ARCHITECTURE.md`
- `docs/RUNTIME_GLB_PIPELINE.md`

## Assumptions

- The core viewer remains a GLB viewer/configurator.
- CAD tessellation is not attempted until a real CAD parser/kernel path exists.
- This work may become a separate importer package rather than core viewer
  code.

## Non-goals

- No ad hoc Dart tessellator.
- No UV unwrap, mesh repair, or DCC-specific surface authoring.
- No STEP/IGES support in V1, V2, or V3 release criteria.
- No custom renderer.

## Candidate slices

1. Research OCCT FFI packaging feasibility for supported Flutter platforms.
   Verify: native build notes, binary size notes, and platform gaps.
2. Prototype STEP and IGES parse outside the core viewer package.
   Verify: deterministic parse diagnostics for valid and invalid sample files.
3. Prototype tessellation settings and output handoff to GLB or an adapter
   boundary.
   Verify: simple CAD fixtures and documented tolerance/quality tradeoffs.
4. Decide package boundary.
   Verify: ADR records whether CAD remains separate or becomes an optional
   importer module.

## Acceptance criteria

- [ ] OCCT FFI feasibility is proven or rejected with evidence;
- [ ] STEP/IGES parsing is demonstrated before tessellation is promised;
- [ ] tessellation diagnostics are explicit about tolerance and failure modes;
- [ ] the core viewer remains usable without CAD dependencies;
- [ ] no CAD work is marketed before fixture and platform evidence exists.

## Progress log

- 2026-07-03: Deferred research plan created from product roadmap discussion.

## Verification log

- 2026-07-03: Not run; deferred plan only.
