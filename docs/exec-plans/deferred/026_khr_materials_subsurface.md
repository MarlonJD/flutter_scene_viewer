# KHR_materials_subsurface Research Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to execute this research plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred, research-only, and specification-gated.**
> Khronos lists `KHR_materials_subsurface` as Initial Draft. Plan 015 is
> complete and no successor is active. This file does not authorize a stable
> public API or renderer implementation.

**Goal:** Determine whether a future stable Khronos subsurface contract can be
supported within `flutter_scene`'s architecture and mobile budgets for wax,
skin/leather, and thick scattering materials, while providing honest
diagnostics today.

**Architecture:** The viewer may recognize the extension name, record the exact
draft revision, and issue required/optional diagnostics without freezing draft
fields. Research compares renderer-native transport options and performance.
No implementation/promotion occurs until the spec, product need, and renderer
design pass explicit gates.

**Tech Stack:** Khronos glTF extension registry and PR #1928, Dart diagnostics,
`flutter_scene` render architecture, Filament subsurface model as a renderer
research reference, Khronos/Three.js ecosystem audit.

## Global Constraints

- Do not expose draft field names in `MaterialPatch`, persistence JSON, public
  API, capability availability, or production docs during the research phase.
- Do not use screen-space blur, wrapped diffuse alone, emissive tint, thickness
  color, alpha blend, or diffuse transmission as a claim of subsurface
  transport.
- Do not edit pub-cache. No branch, commit, push, pin, dependency, or remote
  action is authorized by this plan.
- Three.js has no current built-in `KHR_materials_subsurface` loader contract;
  it can only be used to confirm ecosystem absence or to host custom research,
  never as extension conformance evidence.

---

## Promotion Gates

- [ ] Khronos status and schema are sufficiently stable to pin a contract; the
  plan records the exact commit, status, validator, and fixture revisions.
- [ ] A product decision identifies concrete target assets and quality needs
  that diffuse transmission/volume cannot satisfy.
- [ ] A renderer design review selects a transport method compatible with the
  project's “do not build a replacement renderer” boundary.
- [ ] Measured physical-iOS, Android, and Web budgets show acceptable frame
  time, memory, bandwidth, precision, and fallback behavior.
- [ ] The user approves an amended implementation plan containing the then-
  current fields and acceptance corpus.

All five gates are mandatory before any renderer or stable-API task is added.

## Planned Research and Diagnostic Files

- Create `docs/references/subsurface_feasibility.md` with pinned draft status,
  use cases, renderer options, budgets, risks, and decision.
- Create `lib/src/internal/draft_material_extension_registry.dart` containing
  only extension name/status/source revision metadata, not draft fields.
- Modify `lib/src/internal/glb_capability_reader.dart` and diagnostics so
  optional/required `KHR_materials_subsurface` intent names the feature and
  points to the research boundary.
- Add `test/draft_material_extension_registry_test.dart` and extend
  `test/glb_capability_reader_test.dart` / `test/model_loader_test.dart` for
  atomic required behavior.
- No upstream `flutter_scene` source file is modified in the research phase.

## Task 1: Pin the Draft and Ecosystem Baseline

- [ ] Record the registry status and exact commit/PR head for
  `KHR_materials_subsurface`; archive links to schema, discussions, validator,
  fixtures, and reference implementations.
- [ ] Compare Khronos draft intent with `KHR_materials_diffuse_transmission`,
  `KHR_materials_volume`, OpenPBR-style subsurface, and existing product use
  cases. List overlap and non-equivalence.
- [ ] Audit Three.js, Khronos Sample Viewer, Filament/gltfio, Blender exporter,
  and other primary implementations; label each as absent, experimental, or
  shipping at the pinned revision.
- [ ] Re-run this audit at any activation attempt; a stale draft audit blocks
  promotion.

## Task 2: Add RED Diagnostic-Only Tests

- [ ] Add minimal GLBs with optional and required extension-name presence,
  malformed extension container, and valid core fallback.
- [ ] Prove optional intent loads only the valid core material and emits a
  typed `draft/unsupported` diagnostic containing status/revision/next step.
- [ ] Prove required intent blocks publication before model, state, resources,
  or render count changes.
- [ ] Prove capability queries return unavailable/diagnostic-only on every
  target and no `MaterialPatch` field is serialized.
- [ ] Run `flutter test test/glb_capability_reader_test.dart
  test/model_loader_test.dart test/draft_material_extension_registry_test.dart`;
  expect RED failures only for feature-specific diagnostics.

## Task 3: Implement Only the Diagnostic Boundary

- [ ] Add registry metadata, bounded extension-name recognition, diagnostics,
  atomic required behavior, and documentation links.
- [ ] Keep unknown draft payload bytes untouched for provenance but do not
  interpret fields into stable state.
- [ ] Re-run Task 2 tests; expect all diagnostic-only cases to pass and every
  target to remain unavailable.

## Task 4: Evaluate Renderer Options Without Shipping One

- [ ] Compare at least: screen-space diffusion, separable diffusion profiles,
  thickness-based single scattering, transmission/volume integration, and an
  explicit “not feasible” option.
- [ ] For each option record required buffers/passes, light/IBL behavior,
  shadows, thickness/topology needs, temporal artifacts, alpha/transparency
  interaction, lobe composition, and mobile cost.
- [ ] Use [Filament's subsurface model](https://google.github.io/filament/main/filament.html#materialsystem/subsurfacemodel)
  as one renderer reference, including its documented limitations; do not map
  its API onto the Khronos draft without a field-by-field review.
- [ ] Produce prototype captures only in an isolated research harness. Label
  them `candidate-only` and do not connect them to public capability.

## Task 5: Make the Research Decision

- [ ] Write a GO/NO-GO recommendation with product value, spec stability,
  chosen/declined renderer approach, performance data, visual failure modes,
  upstream scope, and maintenance burden.
- [ ] If NO-GO, keep diagnostics and record the re-evaluation trigger.
- [ ] If GO, amend this plan with exact stable fields, file paths, RED/GREEN
  implementation steps, reference corpus, and release gates; obtain user
  approval before code work.

## Task 6: Verify and Close the Research Slice

- [ ] Update roadmap/material docs and capability notes with literal draft and
  diagnostic-only labels.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass for the diagnostic slice.
- [ ] Completion of research means a documented decision, not renderer or
  production support.

## Acceptance Criteria

- [ ] Exact draft status/revision and ecosystem support are reproducible.
- [ ] Optional/required assets receive typed, atomic diagnostics without draft
  fields entering public state.
- [ ] Feasibility compares real transport options and measured target budgets;
  no blur/emissive/alpha fake is promoted.
- [ ] No availability or production claim exists.
- [ ] Renderer implementation requires all promotion gates and a separately
  approved amended plan.

## Progress Log

- 2026-07-16: Created as research-only while Khronos status is Initial Draft.
  Research, diagnostics, prototypes, and target measurements are `not run`.

## Verification Log

- 2026-07-16: Plan status checked against the Khronos extension registry and
  current Filament/Three.js reference boundaries.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
