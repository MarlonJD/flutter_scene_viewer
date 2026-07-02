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

- [x] original material can be restored;
- [x] texture override requires UV capability;
- [x] metallic/roughness values are validated 0..1;
- [x] patch state can persist and reapply.

## Progress log

- 2026-07-01: Plan created.
- 2026-07-01: README v1 non-goal wording updated to remove "VR-specific material features"; assumed this is copy-only and runtime material scope remains unchanged.
- 2026-07-01: Added material documentation note that texture overrides require authored UV coordinates and the viewer does not generate UV unwraps.
- 2026-07-01: Replaced vague "complex VR materials" charter wording with advanced shader/material effects and documented subsurface scattering as outside the v1 viewer core.
- 2026-07-02: Implemented the runtime material override slice on the current `main` branch, assuming the user's explicit implementation request plus "do not create or switch branches" instruction authorizes working in place.
- 2026-07-02: Added `MaterialOverrideStore` and immutable snapshots with sparse patch merge, per-part reset, all-reset, JSON serialization, and persisted snapshot reapply through the controller.
- 2026-07-02: Added diagnostics-first validation for metallic and roughness values outside 0..1; invalid patches are not sent to the adapter or stored.
- 2026-07-02: Added adapter-facing material calls that return diagnostics, core PBR factor application, base-color texture loading for asset/bytes/network texture sources, original PBR/visibility restoration, and missing-UV diagnostics without generating UVs.
- 2026-07-02: Assumption: runtime UV capability is derived at the adapter boundary from retained `flutter_scene` interleaved texture-coordinate data; absent or all-zero coordinates are treated as missing UVs for texture override purposes.
- 2026-07-02: verified locally: `flutter test test/material_patch_test.dart test/material_override_store_test.dart`.
- 2026-07-02: verified locally: `flutter test test/viewer_controller_material_test.dart`.
- 2026-07-02: verified locally: `flutter test test/part_registry_test.dart test/viewer_controller_material_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart`.
- 2026-07-02: verified locally: `flutter analyze`.
- 2026-07-02: verified locally: `flutter test`.
- 2026-07-02: verified locally: `python3 tools/repo_lint.py`.
- 2026-07-02: verified locally: `bash tools/run_checks.sh`.
