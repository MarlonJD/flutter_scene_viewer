# KHR_lights_punctual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. Promote this file to `docs/exec-plans/active/` only after the user
> explicitly selects Plan 019.

**Goal:** Import and render authored glTF directional, point, and spot lights
with Khronos semantics while keeping viewer-controlled studio lighting as a
separate, predictable mode.

**Architecture:** The viewer owns the public lighting-source choice,
diagnostics, persistence, and authored-intent inspection. A separately approved
`flutter_scene` checkout owns light objects/components, glTF importer mapping,
world transforms, the bounded direct-light loop, shadows, GPU packing, and
shader evaluation. Every standard material lobe consumes the same resolved
light list.

**Tech Stack:** Dart, Flutter, `flutter_scene`, Flutter GPU/Impeller, WebGL2,
glTF 2.0, `KHR_lights_punctual`, GLSL, Khronos Sample Assets, Three.js reference
captures.

## Global Constraints

- Do not edit pub-cache. Upstream changes belong in a separate
  `flutter_scene` checkout and are integrated only through a reachable pinned
  revision after separate authorization.
- This plan does not authorize branch changes, commits, pushes, dependency-pin
  changes, or remote writes.
- Unsupported required intent blocks publication before live-scene mutation.
  Unsupported optional intent keeps only the valid fallback and emits a typed
  diagnostic.
- Freeze camera, model transform, HDRI bytes/orientation, exposure, tone
  mapping, output color space, viewport, fixture hashes, and renderer revisions
  for comparisons.
- Keep capability, runtime application, visual verification, target evidence,
  and release maturity as separate claims.

---

## Normative Contract

- [ ] Pin the exact
  [KHR_lights_punctual](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_lights_punctual/README.md)
  revision used for implementation evidence.
- [ ] Support `directional`, `point`, and `spot` only. Do not add area lights,
  IES profiles, authored cameras, or a general light editor.
- [ ] Preserve linear RGB `color` default `[1, 1, 1]` and `intensity` default
  `1`. Interpret point/spot intensity as candela and directional intensity as
  lux.
- [ ] Resolve point/spot position from the node world transform. Resolve
  directional/spot direction from local `-Z` rotated by the node. Ignore node
  scale for light properties.
- [ ] Treat absent `range` as infinite; require a present range to be greater
  than zero. Use inverse-square falloff and the Khronos recommended bounded
  range cutoff rather than a linear fade.
- [ ] Enforce `0 <= innerConeAngle < outerConeAngle <= pi/2`, with defaults
  `0` and `pi/4`, and smooth interpolation in cosine space.
- [ ] Do not infer authored shadow flags: glTF does not define shadows for this
  extension. Shadow controls remain viewer/renderer policy and evidence must
  say when they are disabled.
- [ ] Use the version-pinned
  [Three.js GLTFLoader](https://threejs.org/docs/pages/GLTFLoader.html) punctual
  import and its point/spot/directional shader loops as a controlled reference,
  and Filament gltfio as a second implementation reference. Record their
  exposure/unit policy; neither reference is pixel-parity authority.

## Planned Interface and Files

Viewer repository:

- Modify `lib/src/viewer_lighting.dart`: add
  `ViewerLightingKind.importedPunctual` without changing existing `studio` and
  `none` defaults.
- Create `lib/src/imported_punctual_light.dart`: immutable public metadata
  (`name`, type, linear color, intensity, optional range, cone angles,
  `nodePath`) for inspection and serialization; it is not a shader API.
- Create `lib/src/internal/glb_punctual_light_reader.dart`: bounded JSON/GLB
  validation and extension-required diagnostics.
- Modify `lib/src/model_loader.dart` and `lib/src/viewer_controller.dart`: carry
  imported-light metadata and apply lighting mode atomically.
- Modify `lib/src/internal/flutter_scene_adapter.dart`: select studio or
  renderer-imported lighting without duplicating authored lights.
- Modify `lib/flutter_scene_viewer.dart` and `docs/PUBLIC_API.md`: export and
  document the source-selection/inspection surface.
- Add `test/glb_punctual_light_reader_test.dart`,
  `test/viewer_controller_lighting_test.dart`, and extend
  `test/viewer_lighting_test.dart` and `test/flutter_scene_adapter_material_test.dart`.

Paths relative to the separate upstream `flutter_scene` checkout:

- Modify `packages/flutter_scene/lib/src/light.dart` and
  `packages/flutter_scene/lib/src/scene.dart`: bounded lists of resolved
  directional/point/spot lights and lifecycle ownership.
- Add `packages/flutter_scene/lib/src/components/point_light_component.dart`
  and `packages/flutter_scene/lib/src/components/spot_light_component.dart`;
  extend the directional component instead of bypassing scene transforms.
- Modify `packages/flutter_scene/lib/src/importer/src/gltf/types.dart`,
  `packages/flutter_scene/lib/src/importer/src/gltf/parser.dart`,
  `packages/flutter_scene/lib/src/importer/src/fscene_emitter/fscene_emitter.dart`,
  and `packages/flutter_scene/lib/src/runtime_importer/runtime_importer.dart` to
  map the root light table and node references in offline and runtime import.
- Modify `packages/flutter_scene/lib/src/material/engine_lighting.dart`,
  `packages/flutter_scene/shaders/material_engine_lighting.glsl`, and
  `packages/flutter_scene/shaders/material_lighting.glsl` to pack and evaluate
  the same bounded light array for every lit material.
- Modify `packages/flutter_scene/lib/src/render/render_scene.dart` and
  `packages/flutter_scene/lib/src/scene.dart` so culling, transform resolution,
  and render scheduling observe imported lights.
- Add upstream tests under `packages/flutter_scene/test/` for parser defaults,
  component transforms, attenuation, cones, bounded capacity, and shader
  packing.

## Task 1: Freeze RED Parsing and Fallback Tests

- [ ] Add minimal GLB fixtures for each light type, defaults, node transforms,
  finite/infinite range, valid cones, invalid indices, duplicate node
  references, malformed objects, and `extensionsRequired`.
- [ ] Write RED tests proving optional unsupported lights preserve the scene
  and emit feature-specific diagnostics, while required unsupported lights fail
  before the current model is replaced.
- [ ] Write RED tests proving `ViewerLighting.studio()` remains the default and
  does not accidentally combine with imported lights.
- [ ] Run `flutter test test/glb_punctual_light_reader_test.dart
  test/viewer_controller_lighting_test.dart`; expect failures only for the new
  missing contracts.

## Task 2: Preserve Intent and Add Source Selection

- [ ] Implement bounded reader validation, immutable imported-light metadata,
  JSON round-trip, equality, and deterministic ordering by light-table index
  then node path.
- [ ] Add `ViewerLighting.importedPunctual()` and define the source rule:
  imported mode disables the studio key but retains the selected IBL;
  studio mode does not instantiate authored direct lights.
- [ ] Make load, source switch, reset, and persisted-state restore atomic. A
  validation or backend failure leaves the old source, scene, state, and render
  request count unchanged.
- [ ] Re-run the Task 1 tests; expect them to pass without renderer-availability
  claims.

## Task 3: Implement Renderer-Owned Light Import and Evaluation

- [ ] Add upstream parser/materialized light types and node components with
  exact defaults, units, transform semantics, range, and cone validation.
- [ ] Replace the single-directional-light shader contract with a documented
  bounded list chosen from measured backend uniform/storage limits. Overflow
  must diagnose deterministically; it must not silently discard lights.
- [ ] Evaluate direct light through one shared function so core PBR,
  specular/IOR, clearcoat, sheen, anisotropy, iridescence, and later lobes see
  the same light sample and shadow term.
- [ ] Preserve the zero-imported-light and single-studio-directional paths
  byte-for-byte where practical and visually within the recorded tolerance.
- [ ] Run upstream focused tests from the checkout with `flutter test
  test/gltf_punctual_light_import_test.dart test/punctual_light_test.dart
  test/material_lighting_test.dart`; expect all to pass.

## Task 4: Integrate the Reachable Upstream Revision

- [ ] Obtain separate authorization before creating/publishing an upstream
  commit or changing `pubspec.yaml`/`pubspec.lock`.
- [ ] After publication, pin the exact reachable revision and update
  `lib/src/internal/material_extension_native_capability.dart` or a dedicated
  lighting-capability type so availability requires importer, scene, uniform,
  and shader contracts together.
- [ ] Add adapter tests for studio/imported/none transitions, reload, failure,
  and disposal; ensure no duplicated components or stale GPU resources.
- [ ] Run `flutter test test/viewer_lighting_test.dart
  test/viewer_controller_lighting_test.dart
  test/flutter_scene_adapter_material_test.dart`; expect all to pass.

## Task 5: Produce Controlled Visual Evidence

- [ ] Stage hash- and license-pinned Khronos `DirectionalLight`,
  `LightsPunctualLamp`, `PointLightIntensityTest`, and `PlaysetLightTest`
  fixtures, plus a minimal cone/range fixture where the official corpus lacks
  one isolated boundary.
- [ ] Capture direct-only and combined direct+IBL views in this viewer and
  Three.js with identical state. Include close crops where falloff and cone
  edges are measurable.
- [ ] Pin the Three.js package exactly and add a contract test proving all
  authored light kinds, transforms, ranges, and cones exist after GLTFLoader
  import before accepting a capture.
- [ ] Verify a core dielectric, metal, clearcoat, sheen, anisotropic, and
  iridescent material when those renderer-native lobes exist; otherwise record
  the dependent rows as `not run` rather than fabricating coverage.
- [ ] Record target/backend, commands, revisions, fixture hashes, state hash,
  images, metrics, and literal evidence labels.

## Task 6: Close Documentation and Verification

- [ ] Update `docs/MATERIALS_AND_LIGHTING.md`, `docs/RUNTIME_GLB_PIPELINE.md`,
  `docs/PUBLIC_API.md`, `docs/references/flutter_scene_capability_notes.md`,
  and the generated capability matrix.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass before checking completion criteria.
- [ ] Move this plan to completed only when every checked claim has matching
  target evidence and the pinned revision is externally reachable.

## Acceptance Criteria

- [ ] All three Khronos light types, defaults, units, transforms, attenuation,
  range, and cones pass parser and renderer tests.
- [ ] Studio and imported sources are explicit, mutually exclusive for direct
  light, serializable, resettable, and atomically applied.
- [ ] Every supported lit lobe uses the same resolved direct-light loop; no
  material family carries a private point/spot implementation.
- [ ] Required unsupported/malformed intent blocks atomically; optional
  fallback is typed and never advertised as rendered support.
- [ ] No production claim exists without a reachable pin and matching target
  captures under the fixed comparison state.

## Progress Log

- 2026-07-16: Created as deferred in the user-approved extension sequence.
  Implementation, upstream work, and target evidence are `not run`.

## Verification Log

- 2026-07-16: Plan content checked against the ratified Khronos extension and
  the pinned renderer's current single-directional-light implementation.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
