# KHR_materials_variants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. Activate Plan 020 only after the user selects this configurator
> slice.

**Goal:** Expose asset-authored material variants as one atomic, persistent
configurator selection without adding a new shader or confusing variants with
runtime material overrides.

**Architecture:** `flutter_scene_viewer` owns parsing, stable variant IDs,
primitive mappings, selection, persistence, precedence, diagnostics, and
rollback. `flutter_scene` only needs a renderer hook that can replace a
primitive's source material deterministically while retaining imported
material instances and texture resources. The selected variant establishes the
source material; the viewer's `MaterialPatch` layer applies afterward.

**Tech Stack:** Dart, Flutter, GLB/glTF 2.0,
`KHR_materials_variants`, existing `PartAddress`, `PartRegistry`,
`MaterialOverrideStore`, and `flutter_scene` material instances.

## Global Constraints

- Exactly one asset variant may be active per loaded asset. `null` means the
  original glTF materials.
- Do not introduce a BRDF, shader permutation, variant-specific material
  authoring API, or arbitrary multi-select behavior.
- Do not edit pub-cache or change the dependency pin without separate
  authorization. This plan authorizes no branch, commit, push, or remote write.
- Selection must be transactional across every affected primitive. Failure on
  one mapping restores all source materials, runtime overrides, persisted
  state, and render-request count.

---

## Normative Contract

- [ ] Pin the ratified
  [KHR_materials_variants](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_variants/README.md)
  revision used by fixtures and tests.
- [ ] Parse root `variants` and primitive `mappings`. Each mapping identifies
  one material index and one or more global variant indices.
- [ ] Reject a primitive whose mappings use the same variant index more than
  once. Validate all root/material/variant indices before publishing a model.
- [ ] When no variant is active, or an active variant has no mapping for a
  primitive, use that primitive's original glTF material.
- [ ] Keep one active global variant for the asset, applied in unison across
  all mapped primitives.
- [ ] Use Filament gltfio's variant/instance behavior as a lifecycle reference.
  Three.js does not provide built-in variants in `GLTFLoader`; its official docs
  point to the external
  [three-gltf-extensions plugin](https://github.com/takahirox/three-gltf-extensions).
  Any Three.js reference capture must pin both compatible revisions and prove
  the plugin selection changed the mapped materials.

## Planned Interface and Files

- Create `lib/src/material_variant.dart` with immutable
  `MaterialVariant { id, name }` and `MaterialVariantSelection { variantId }`.
  The stable `id` is the validated root-array index encoded as a string; names
  are display labels and are not identity.
- Create `lib/src/internal/glb_material_variant_reader.dart` containing root
  definitions, per-`PartAddress` original material index, and variant-to-
  material mappings.
- Modify `lib/src/model_loader.dart` to carry `availableMaterialVariants` and
  mappings in the loaded result.
- Modify `lib/src/part_registry.dart` to retain primitive/source-material
  identity needed for atomic replacement.
- Modify `lib/src/viewer_controller.dart` with getters
  `availableMaterialVariants`, `selectedMaterialVariantId` and methods
  `selectMaterialVariant(String id)` / `clearMaterialVariant()`.
- Modify `lib/src/material_override_store.dart` so serialized viewer state
  records the selected variant separately from per-part `MaterialPatch` data.
- Modify `lib/src/internal/flutter_scene_adapter.dart` to apply source material
  replacements first and reapply stored runtime patches second.
- Modify `lib/flutter_scene_viewer.dart`, `docs/PUBLIC_API.md`, and
  `docs/RUNTIME_GLB_PIPELINE.md`.
- Add `test/glb_material_variant_reader_test.dart`,
  `test/viewer_controller_variant_test.dart`, and extend
  `test/material_override_store_test.dart`, `test/part_registry_test.dart`,
  and `test/flutter_scene_adapter_material_test.dart`.

## Task 1: Write RED Schema and Identity Tests

- [ ] Add fixtures for named variants, multiple primitives, one variant mapped
  to several primitives, unmapped primitives, shared materials, duplicate
  names, duplicate per-primitive indices, invalid material/variant indices,
  malformed extension objects, and required-extension failure.
- [ ] Prove identity uses root index rather than non-unique names and ordering
  is the root array's ordering.
- [ ] Prove optional unsupported/malformed intent emits typed diagnostics and
  required invalid intent blocks load before the live model changes.
- [ ] Run `flutter test test/glb_material_variant_reader_test.dart`; expect RED
  failures for missing parser and model types only.

## Task 2: Implement Parsing and Loaded-Model Metadata

- [ ] Implement bounded parsing with deterministic diagnostics that name the
  primitive `PartAddress`, mapping index, material index, and variant index.
- [ ] Attach immutable definitions/mappings to the load result without
  mutating renderer materials or claiming application support.
- [ ] Export the public read-only variant list and document duplicate-name
  behavior.
- [ ] Re-run `flutter test test/glb_material_variant_reader_test.dart
  test/model_loader_test.dart`; expect all new parsing tests to pass.

## Task 3: Write RED Transaction and Precedence Tests

- [ ] Test selection across multiple primitives, switching A→B, clear-to-
  original, unknown ID, repeated selection, unload/reload, and state restore.
- [ ] Freeze precedence: original/selected source material → authored
  extension state attached to that source → viewer runtime `MaterialPatch`.
  Resetting a runtime patch reveals the selected source, not always the
  original source.
- [ ] Inject failure on the last mapped primitive and prove no primitive,
  selected ID, persisted state, or render count changes.
- [ ] Run `flutter test test/viewer_controller_variant_test.dart
  test/flutter_scene_adapter_material_test.dart`; expect failures only at the
  missing selection transaction.

## Task 4: Implement Atomic Selection and Persistence

- [ ] Add a two-phase adapter operation: preflight every mapped material and
  retained runtime patch, then swap all primitives, then publish controller
  state and request exactly one render.
- [ ] Cache original imported material handles and variant material handles
  with model-lifetime ownership; dispose neither while referenced.
- [ ] Serialize only the selected stable ID. On restore against a different
  asset or missing ID, retain the original materials and emit a diagnostic.
- [ ] Reapply runtime overrides after every successful source change and prove
  reset/persistence semantics with tests.
- [ ] Re-run focused tests; expect all transaction and precedence cases to
  pass.

## Task 5: Upstream Hook Only If the Adapter Cannot Swap Safely

- [ ] First verify whether the pinned renderer can replace primitive material
  references without resource leaks or scene rebuilds. Record the source audit
  in the progress log.
- [ ] If not, modify the separate upstream checkout's
  `packages/flutter_scene/lib/src/mesh.dart`,
  `packages/flutter_scene/lib/src/material/material.dart`,
  `packages/flutter_scene/lib/src/runtime_importer/material_builder.dart`, and
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`
  to expose a transactional source-material swap primitive and retained
  importer material cache.
- [ ] Add upstream lifecycle tests for shared material instances, repeated
  swaps, texture ownership, render scheduling, and disposal.
- [ ] Obtain separate authorization before any upstream commit, publication,
  or viewer pin change.

## Task 6: Fixture and UI-Neutral Acceptance Evidence

- [ ] Stage hash/license-pinned Khronos MaterialsVariantsShoe and one
  multi-primitive configurator fixture.
- [ ] Verify original/A/B states, unmapped primitives, runtime override
  precedence, and restored state through deterministic material IDs and
  captures. Pixel parity is not required because no shading model changes.
- [ ] Add reference-harness contract tests for original/A/B material-index maps;
  a screenshot without verified plugin selection is invalid evidence.
- [ ] Record target/backend, fixture hash, selected ID, material-index map,
  screenshot hash, and diagnostics for each exercised target.

## Task 7: Close Documentation and Verification

- [ ] Update public API, runtime pipeline, roadmap status, capability notes,
  fixture provenance, and example code without expanding the viewer into a
  variant editor.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass before completion.
- [ ] Move the plan to completed only when parsing, atomic application,
  persistence, and at least the selected release-target evidence are recorded.

## Acceptance Criteria

- [ ] One stable-ID selection applies across every mapped primitive, with
  original-material fallback where no mapping exists.
- [ ] Variant source selection and viewer runtime overrides have the tested
  precedence and reset behavior.
- [ ] Invalid mappings and any runtime failure are atomic and diagnostic.
- [ ] Duplicate names are harmless; invalid duplicate variant indices per
  primitive are rejected.
- [ ] The implementation adds no shader path and makes no material-extension
  rendering claim.

## Progress Log

- 2026-07-16: Created as deferred in the user-approved extension sequence.
  Implementation and target evidence are `not run`.

## Verification Log

- 2026-07-16: Plan content checked against the ratified Khronos extension and
  current controller/material override architecture.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
