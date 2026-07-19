# Exec plan: renderer-native transmission and volume follow-up

> **Status (2026-07-17): completed.** Renderer-native implementation is
> published and pinned without a path override. The fixed Three.js r167 versus
> iOS Simulator Impeller Metal comparison is `verified locally`; release
> maturity remains `release pending`, production readiness is `false`, and
> physical iOS, Android, and Web remain `not run`.

## Goal

Add first-class `KHR_materials_transmission`, `KHR_materials_volume`, and glass
`KHR_materials_ior` contracts to `flutter_scene`, then integrate them through
the viewer only after renderer-owned transport/compositing and selected-target
evidence satisfy the Khronos semantics.

## Assumptions

- Khronos defines factor, texture-channel, alpha, thin-surface, volume,
  attenuation, transform, metal-isolation, and IOR semantics.
- The starting `flutter_scene` revision
  `ccf7372428961ebe0abb053727fe443150547a74` exposed native clearcoat and
  scene-color render targets but no standard-material transmission, volume,
  attenuation, or variable-IOR fields and no renderer-owned glTF
  refraction/compositing contract.
- The repository-owned screen-space material remains a narrow
  `candidate-only` path. Availability, release maturity, and target evidence
  stay separate.

## Non-goals

- Do not build a replacement PBR renderer, general shader graph, nested-glass
  system, or order-independent transparency system in
  `flutter_scene_viewer`.
- Do not represent optical transmission with alpha blending, bake textures,
  generate UVs, or add asset-specific glass colors, contours, glints, or
  refraction constants.
- Do not treat simulator-only, skipped, historical, or source-audit evidence
  as physical-device or production-ready evidence.

## Steps

1. Add upstream `flutter_scene` material/importer fields for transmission
   factor and red-channel texture, volume thickness and green-channel texture,
   attenuation color/distance, and material IOR including the exact `ior == 0`
   compatibility mode. Verify with upstream unit tests and a concrete upstream
   commit.
2. Add renderer-owned scene-color sampling and standard-material transport.
   Keep optical transmission separate from alpha-as-coverage, preserve the
   ordinary lit base response at zero factor/texture texels, prevent metallic
   response from transmitting, and keep zero-thickness surfaces free of
   macroscopic refraction.
3. Implement positive volume through mesh-space thickness transformed by node
   scale, world-space attenuation distance, valid entry/exit boundaries, IOR
   refraction, and opaque geometry visible behind the surface. Reject or
   diagnose unsupported topology/compositing cases atomically.
4. Update the viewer dependency pin and advertise runtime capability only
   after the pinned importer, material, render graph, and shader consume every
   requested field. Remove package-local limitations only when the native path
   covers their preserved intent.
5. Run the fixed-state Khronos transmission/volume corpus and focused wrapper
   tests on each selected target. Record runtime capability, release maturity,
   and target evidence independently.

## Acceptance criteria

- [x] A concrete upstream commit and viewer dependency pin expose the complete
  selected transmission, volume, attenuation, and glass-IOR contract.
- [x] Factor zero/full, red-channel texture multiplication, alpha independence,
  metal isolation, thin-surface behavior, and opaque-behind-glass tests pass
  without an unlit whole-material fallback.
- [x] Positive thickness uses the green channel and node/world scale;
  attenuation defaults/infinite distance, attenuation color, IOR interaction,
  and `ior == 0` compatibility pass normative tests.
- [x] Khronos WaterBottle/GlassVase-style evidence is captured under the fixed
  reference state for every claimed target, including behind-glass geometry
  and volume-specific metrics.
- [x] No target is labeled `production-ready` without matching local target
  evidence and the Plan 014 release gates.

## Progress log

- 2026-07-19: Closed final wrapper-routing review findings before committing
  the completed plan. A specular or transformed-core follow-up patch now
  rejects atomically when replacing an existing renderer-native
  transmission/volume material would lose glass state; material identity,
  textures, transforms, IOR, thickness, and attenuation remain unchanged.
  Supported extended-PBR routing now preserves opaque native IOR with the
  precedence `patch > retained extended state > native source`, including the
  exact `ior == 0` compatibility value. Public `MaterialPatch` comments and
  runtime renderer-revision diagnostics now match the capability-gated
  immutable-pin contract.
- 2026-07-17: Published the verified upstream commit
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022` to the externally reachable
  `MarlonJD/flutter_scene` branch `plan016-transmission-volume` after explicit
  user authorization. `git ls-remote` returned that exact SHA. No PR, issue,
  comment, review, or other remote write was created.
- 2026-07-17: Replaced the temporary viewer path override with the exact
  immutable Git pin. Both `pubspec.yaml` and `pubspec.lock` record
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022`, the lockfile's `resolved-ref`
  matches, `pubspec_overrides.yaml` is absent, and the final harness resolves
  `flutter_scene` from the Git-backed pub-cache checkout rather than the local
  upstream worktree. Native capability reporting now keeps availability,
  iOS Simulator `releasePending` maturity, and `verifiedLocally` target
  evidence separate; physical iOS, Android, and Web remain `not run`.
- 2026-07-16: Closed the last controlled-comparison gap without relaxing any
  threshold or boosting authored material/environment inputs. Stock Three.js
  r167 renders the far interface of a double-sided transmissive surface into
  its transmission target before the final front-interface pass. The upstream
  renderer now mirrors that behavior with an isolated back-face scene-color
  prepass and private depth attachment, preserving the immutable opaque target
  and final scene depth. This raised the iOS normal-map control signal from
  approximately `0.0103` to `0.018541633515716117` against the fixed `0.015`
  gate. The implementation remains local and unpublished; no remote write has
  occurred.
- 2026-07-16: Created the verified local upstream commit
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022` with conventional message
  `feat(materials): add renderer-native transmission and volume`. The upstream
  checkout is clean at that detached commit. Publication to
  `MarlonJD/flutter_scene` remains pending explicit user authorization; the
  viewer pin and removal of `pubspec_overrides.yaml` must wait until the exact
  commit is externally reachable.
- 2026-07-16: Promoted to active after reading the project charter,
  architecture, materials/lighting contract, completed Plan 015, the full Plan
  016 objective, and the required PBR and execution workflow references. Work
  stays on the current viewer `main` branch as explicitly requested. Upstream
  work starts from `ccf7372428961ebe0abb053727fe443150547a74` in a separate
  checkout; the pub cache remains read-only. Remote publication is separately
  approval-gated, so local implementation and evidence will proceed first and
  the minimum authorization will be requested only if publication is the sole
  remaining gate. Existing untracked `tools/__pycache__/` is preserved as
  user-owned workspace state.
- 2026-07-16: Established clean baselines before implementation. Viewer
  `bash tools/run_checks.sh` passed with 519 tests and 16 documented GPU-gated
  skips. The separate upstream checkout at the exact pinned revision passed
  `flutter analyze`, all 790 tests with 14 documented host/GPU skips, and
  `git diff --check`. Initial upstream RED/GREEN slices now cover normative
  transmission/volume/IOR defaults and ranges, authored `ior == 0`, red/green
  texture metadata, `KHR_texture_transform`, runtime mapping, FScene emission
  and realization, live parameter serialization, optional/required extension
  behavior, and typed rejection of unsupported UV sets. The focused upstream
  test currently passes 13 tests. No remote write has occurred.
- 2026-07-16: Completed the local upstream implementation slice. The standard
  material now imports, persists, and renders transmission, thickness,
  attenuation, and variable IOR through a renderer-owned opaque scene-color
  phase. Optical transmission remains independent of alpha coverage, thin and
  positive-volume paths are explicit, metallic response does not transmit,
  and positive thickness uses model scale for its world-space attenuation
  distance. A dedicated transmission shader avoids exceeding Metal's portable
  fragment-sampler ceiling: it binds 16 samplers and deliberately omits only
  secondary-environment crossfade while retaining primary IBL, direct light,
  shadows, SSAO, clearcoat, and emission. Nested transmission and
  order-independent transparency remain explicit non-goals. The local
  upstream checkout is still unpublished and no remote write has occurred.
- 2026-07-16: Completed the viewer integration slice against a temporary
  workspace-only path override to the upstream checkout. Native capability
  probing, texture binding, transforms, atomic staging, reset, persistence,
  and typed unsupported-specular diagnostics now cover the selected glass
  contract. The existing extended-PBR fallback uses the inherited native IOR
  property so the material has a single authoritative IOR state. The temporary
  `pubspec_overrides.yaml` is not publication evidence and must be removed
  before the immutable dependency pin is accepted.
- 2026-07-13: Created from Plan 014 Task 9 because the pinned renderer lacks a
  native transmission/volume/IOR contract. The package-local factor-only thin
  path remains `candidate-only`; positive thickness, runtime transmission
  textures, and `ior == 0` return typed diagnostics instead of losing intent.

## Verification log

- 2026-07-19: Independent final review approved both Plan 016 spec compliance
  and code quality after two RED/GREEN regression rounds for native glass and
  opaque-IOR follow-up patches. The closure `bash tools/run_checks.sh` passed
  repository lint, formatting, dependency resolution, analysis, and 524 tests
  with 16 documented GPU-gated skips. The Plan 016 Node contract and metric
  suites passed 8/8, and `git diff --check` passed. Physical iOS, Android, Web,
  packaging, and production readiness remain unchanged and are still owned by
  Plan 017.
- 2026-07-17: Post-archive `python3 tools/repo_lint.py` and
  `git diff --check` pass. The completed plan has no unchecked acceptance
  criteria, the active copy is absent, remote branch
  `plan016-transmission-volume` still resolves to the exact published SHA, and
  the browser-driven analyzer left no Chrome, Puppeteer, webdriver, or local
  fixture-server process behind.
- 2026-07-17: The immutable-pin iPhone 17 iOS 26.5 Simulator run completed all
  16 models x 3 passes through Impeller Metal at state hash
  `3fce01a715f596c513ee7d0f527638c3928cb44aeae32262e7dad16a912c9c96`.
  The evidence record is `verified locally`, names the exact published
  renderer SHA, records 48 capture hashes, and contains only the nine expected
  `ambiguousNodePath` diagnostics authored by Khronos `TransmissionTest`.
- 2026-07-17: Final immutable-pin analysis passes every unchanged calibrated
  gate. Camera silhouette IoU is `0.9804384077693391`; transmission, IOR,
  thickness, attenuation, roughness, normal-map, and world-scale signals are
  respectively `0.08125705944273869`, `0.0633010968406289`,
  `0.04963780634417499`, `0.029937201205387957`,
  `0.046247913469156146`, `0.018541633515716117`, and
  `0.05460480645429076`. Every cross-renderer mean/p95, displacement,
  chromaticity, and blur check passes. The regenerated synthetic and Khronos
  boards identify the immutable pin and were inspected locally: the target
  refraction, attenuation, roughness, normal, texture-channel, scale, and
  clearcoat-composition trends are coherent, with no banding or scene-color
  corruption. This is directional controlled evidence, not pixel parity.
- 2026-07-17: The pinned viewer dependency passed `bash tools/run_checks.sh`:
  repository lint, formatting, dependency resolution, and analysis were clean;
  522 tests passed with 16 documented GPU-gated skips. The focused native
  capability test also passed after recording iOS Simulator
  `releasePending`/`verifiedLocally` status independently. A fresh closure run
  after all implementation and documentation changes passed the same complete
  harness with 522 tests and 16 documented skips. Plan 016's Node contract and
  metric suites passed 8/8, the generated capability matrix was current, and
  `git diff --check` passed before archival.
- 2026-07-16: The exact stock Three.js r167 reference rendered all 16 models x
  3 passes and passed threshold calibration. The final local path-override
  candidate captured the matching 48-frame matrix on an iPhone 17 iOS 26.5
  Simulator with Impeller Metal. Evidence recording accepted the exact
  `3fce01a715f596c513ee7d0f527638c3928cb44aeae32262e7dad16a912c9c96`
  state hash, all expected artifacts, and only the nine pre-existing
  `ambiguousNodePath` diagnostics from Khronos `TransmissionTest`; status is
  correctly `candidate-only` until immutable publication/pinning.
- 2026-07-16: Controlled image analysis passes every calibrated gate. Selected
  iOS signals are transmission `0.08125705944273869`, IOR
  `0.0633010968406289`, thickness `0.04963780634417499`, attenuation
  `0.029937201205387957`, roughness `0.046247913469156146`, normal mapping
  `0.018541633515716117`, and world scale `0.05460480645429076`, each against
  the fixed `>= 0.015` threshold. Camera silhouette IoU is
  `0.9804384077693391`; every cross-renderer mean/p95, displacement,
  chromaticity, and blur bound passes. Synthetic and Khronos comparison boards
  were inspected locally and show no banding or scene-color corruption.
- 2026-07-16: Final upstream local verification after the back-face prepass
  passes CI-equivalent `dart analyze packages examples`, formatting across 478
  Dart files, `git diff --check`, and the full
  `flutter test --enable-impeller` suite with 820 passing tests and 14
  documented host/GPU skips. The native-asset hook compiles the expanded base
  shader manifest during the Impeller-enabled suite.
- 2026-07-16: Viewer `bash tools/run_checks.sh` also passes after the final
  renderer change against the temporary path override: repo lint, formatting,
  dependency resolution, and analysis are clean; 522 tests pass with 16
  documented GPU-gated skips. This remains local candidate verification, not
  immutable-pin evidence.
- 2026-07-16: `flutter test test/transmission_volume_material_test.dart`
  passes 13 focused importer/material/persistence tests after observing RED
  failures for missing fields, missing persistence, missing extension
  handling, and missing UV rejection. Renderer/shader and selected-target
  evidence remain `not run` at this checkpoint.
- 2026-07-16: Upstream `flutter analyze` and `git diff --check` pass. The full
  upstream `flutter test --reporter compact` run passes 814 tests with 14
  documented skips. Shader contract coverage includes the immutable opaque
  scene-color boundary, pass ordering, red/green channel semantics, thin versus
  positive-volume behavior, `ior == 0`, rough-transmission sampling, and the
  16-sampler transmission variant.
- 2026-07-16: Viewer `bash tools/run_checks.sh` passes against the temporary
  local upstream override: repo lint and formatting pass, `flutter analyze`
  reports no issues, and 521 tests pass with 16 documented GPU-gated skips.
  Simulator Metal captures and controlled Three.js comparison remain `not run`
  at this checkpoint.
- 2026-07-13: Upstream implementation and selected-target evidence are
  `not run`; this deferred plan records the exact blocker and required closure
  gates only.
