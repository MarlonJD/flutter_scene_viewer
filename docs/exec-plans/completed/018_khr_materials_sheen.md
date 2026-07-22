# KHR_materials_sheen Diagnostic, Candidate, and Renderer-Native Plan

> **Status (2026-07-22): completed.** Renderer-native viewer integration,
> bounded iOS Simulator evidence, documentation, and independent review are
> complete at the literal `verified locally` / `release pending` boundary.
> Physical iOS, Android, Web, physical correctness, general pixel parity,
> release, and `production-ready` remain `not run` or unclaimed. Plan 017
> remains deferred with its completed local BasisU 5E.1-5E.6/M3 evidence
> preserved and its physical/runtime/release boundaries still open.

## Goal

Add a complete `KHR_materials_sheen` contract to the viewer, first as an honest
diagnostic and package-local evaluation path comparable to the existing
`FSViewerExtendedPbr` specular path, then promote it to release capability only
after the pinned `flutter_scene` importer and renderer own the full direct-light
and IBL behavior.

The implementation must render a distinct cloth/fiber sheen lobe. It must not
imitate sheen by changing base color, lowering material roughness, increasing
environment intensity, or adding an unrelated rim-light term.

## Source-backed activation baseline

The dependency and viewer-state bullets in this section describe the
pre-implementation snapshot captured when Plan 018 was activated; current
milestone state is recorded in the progress log below.

- `KHR_materials_sheen` is a ratified Khronos glTF extension. The normative
  fields are `sheenColorFactor`, `sheenColorTexture`,
  `sheenRoughnessFactor`, and `sheenRoughnessTexture`.
- The color factor is linear RGB and defaults to `[0, 0, 0]`. The color texture
  contributes sRGB RGB converted to linear. The roughness factor defaults to
  `0`, and the roughness texture contributes its linear alpha channel. Factors
  and samples multiply.
- A zero sheen color disables the layer. Sheen roughness is independent from
  base material roughness.
- Sheen is layered over the metallic-roughness material. When clearcoat and
  sheen coexist, clearcoat is layered above sheen.
- Khronos describes a Charlie/Conty-Kulla-style sheen distribution and an
  albedo-scaling technique that prevents the sheen layer from adding energy
  without reducing the base response.
- At activation, the stable viewer dependency was `flutter_scene` revision
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Its material model, glTF
  importer, standard PBR shader, and DFG lookup expose native clearcoat plus
  transmission/volume/glass IOR but do not expose sheen.
- At activation, the viewer had no sheen fields in `MaterialPatch`, no
  `MaterialExtensionFeature.sheen`, no authored sheen patch group, no sheen
  texture roles, and no typed sheen capability row. An authored optional sheen
  extension therefore falls back to core material without an actionable
  feature-specific diagnostic.
- The existing package-local `FSViewerExtendedPbr` path applies UV transforms,
  `KHR_materials_specular`, and opaque `KHR_materials_ior`. Its iOS Simulator
  evidence is `verified locally`, but its release maturity remains
  `candidate-only`; physical iOS, Android, and Web are `not run`.
- The upstream DFG texture is RGBA16F but currently stores GGX scale and bias
  only in R/G, with B set to zero. A release sheen implementation must provide
  a reviewed directional-albedo/DFG strategy for both base attenuation and IBL;
  it may not treat the existing zero blue channel as sheen data.
- The current viewer-controlled direct light is one directional key light.
  Imported `KHR_lights_punctual` point/spot lights are a separate renderer and
  product capability.

Normative and implementation references, reverified 2026-07-21:

- [Khronos glTF extension registry](https://github.com/KhronosGroup/glTF/blob/main/extensions/README.md)
- [KHR_materials_sheen](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_sheen/README.md)
- [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
- [Filament cloth model](https://google.github.io/filament/main/filament.html#material-system/clothmodel)
- [Filament material sheen examples](https://google.github.io/filament/main/materials.html#materialsystem/standardmodel/sheencolor)
- [Three.js r167 GLTFLoader](https://github.com/mrdoob/three.js/blob/r167/examples/jsm/loaders/GLTFLoader.js)

The official sheen source is pinned for this plan to glTF commit
`3627d7e096eb95b89417a0968aa32b1f2e8f90cf` with README SHA-256
`e5129babb2e7a638aec7e96e7c099d9d3ead0f9bb9b1176f8d5a74111ef278e7`.
The registry source is pinned to commit
`1a41761d60c0d40a092db4681c0000acefdd8983` with SHA-256
`2ba1f0b27e2352c9e7c86027422c85832e36634bd20d3085aa1cd02500d26f8e`.

Filament is a BRDF/IBL implementation reference, not this package's renderer.
The repository's current comparison harness pins `three@0.167.1`, whose
`GLTFLoader` contains the sheen extension path. A future capture must pin the
exact Three.js version (no floating semver), assert that the loaded material
has non-default sheen fields, and record the reference shader/backend before
the image is accepted.

## Architecture and ownership

### Viewer wrapper

The root package owns public glTF-oriented fields, validation, serialization,
authored GLB intent preservation, UV0/texture-transform policy, reset and
persistence behavior, capability diagnostics, and evidence labels.

Expected public/internal vocabulary:

- `MaterialPatch.sheenColorFactor`;
- `MaterialPatch.sheenColorTexture` and texture binding;
- `MaterialPatch.sheenRoughness`;
- `MaterialPatch.sheenRoughnessTexture` and texture binding;
- `MaterialExtensionFeature.sheen`;
- `MaterialExtensionPatchGroup.sheen`;
- color/data texture roles and capability-matrix rows for
  `KHR_materials_sheen`.

### Package-local candidate

The existing full-fragment `FSViewerExtendedPbr` family may add a bounded sheen
variant to prove wrapper routing and shading direction. It must retain core PBR,
specular/IOR, texture transforms, double-sided behavior, shadows, fog,
premultiplied output, and the same viewer lighting/environment resources.

This path remains `candidate-only`. It must preflight its complete reflected
uniform/sampler contract and remain below the selected backend's fragment
sampler/resource floor, including combined specular, sheen, and clearcoat
materials. Shader compilation or a host render does not promote maturity.

### Upstream flutter_scene

Release capability belongs in the renderer-owned material/importer contract:

- first-class sheen factors, textures, UV metadata, copying, defaults, and
  validation;
- runtime and offline glTF importer mapping;
- Charlie-style direct-light response and energy-aware base attenuation;
- reviewed sheen IBL/prefiltering plus directional-albedo/DFG data;
- correct composition with clearcoat above sheen and with the ordinary
  metallic-roughness/specular/IOR response below it;
- shared shadows, alpha, double-sided state, fog, tone mapping, environment
  lifecycle, and every renderer-supported direct light.

Upstream work must happen in a separate checkout and produce a concrete commit.
Do not edit pub-cache files. Do not publish, push, or change the stable viewer
pin without separate authorization.

## Non-goals

- No subsurface scattering, diffuse transmission, anisotropy, iridescence, or
  dispersion implementation in this plan.
- No imported `KHR_lights_punctual` playback. Controlled comparisons use the
  same viewer-supported directional light and IBL on both renderers.
- No general shader graph, replacement renderer, asset-name special case,
  baked highlight, generated UV, or texture-channel reinterpretation.
- No production claim from parsing, serialization, shader compilation,
  Three.js output, Simulator-only evidence, or a package-local candidate.
- No support for the invalid combinations of sheen with
  `KHR_materials_unlit` or archived `KHR_materials_pbrSpecularGlossiness`.

## Milestones

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: intent truth | 1-2 | Authored and runtime sheen is preserved, validated, serialized, and never silently dropped. |
| M2: package-local candidate | 3-4 | A real sheen lobe renders under fixed directional light and IBL with atomic routing and `candidate-only` labels. |
| M3: controlled evidence | 5 | Khronos sheen assets and ToyCar produce durable same-state viewer/Three.js evidence. |
| M4: renderer-native promotion | 6 | A pinned upstream importer/material/shader owns complete sheen behavior and selected targets carry honest evidence. |
| M5: documentation closure | 7 | Public docs, capability matrix, fixture provenance, and the plan log match the exact shipped revision and targets. |

M1 may land while rendering remains diagnostic-only. M2 and M3 do not imply
M4. M4 cannot update the stable dependency pin until the upstream revision is
externally reachable and all pinned-source checks pass.

## Steps

### Task 1: Freeze RED contracts and silent-drop diagnostics

- [x] Add failing tests for authored optional and required
  `KHR_materials_sheen`, malformed extension objects, invalid factor ranges,
  invalid vector lengths, missing UV0, unsupported UV sets, and invalid
  unlit/specular-glossiness combinations.
- [x] Require an optional unsupported sheen material to use only its valid core
  fallback while emitting a typed, non-blocking capability diagnostic.
- [x] Require unsupported sheen listed in `extensionsRequired` to block
  publication atomically with the original bytes and live model state
  unchanged.
- [x] Add capability tests proving that absent shader/importer fields never
  advertise sheen availability.

### Task 2: Add the wrapper contract and authored GLB mapping

- [x] Add sheen fields, bindings, merge/reset, equality, JSON round-trip,
  validation, and empty/feature classification to `MaterialPatch`.
- [x] Parse factors and embedded-GLB textures into an independent sheen patch
  group so invalid sheen cannot discard valid specular, clearcoat, or core
  intent on the same material.
- [x] Preserve sampler and `KHR_texture_transform` metadata. Apply only authored
  UV0; diagnose UV1+ instead of substituting coordinates or generating UVs.
- [x] Decode sheen color as sRGB RGB and sheen roughness as linear alpha. Prove
  factor/sample multiplication and default behavior with CPU tests.
- [x] Add `MaterialExtensionFeature.sheen` and keep default capability
  diagnostic-only until an attached backend consumes every requested field.

### Task 3: Implement the package-local sheen candidate

- [x] Add RED shader/material tests for factor zero, saturated colors,
  independent roughness, grazing-angle movement, direct-only, IBL-only, and
  combined lighting.
- [x] Implement a Charlie/Conty-Kulla-style sheen lobe with energy-aware base
  attenuation. Do not map sheen onto ordinary GGX specular or base roughness.
- [x] Select and document a package-local sheen IBL and directional-albedo
  strategy. Any approximation must remain explicitly `candidate-only` and must
  preserve the zero-sheen native-equivalent path.
- [x] Bind the two sheen textures and uniforms atomically. Preflight every
  reflected slot, sampler, shader bundle, and backend resource limit before
  replacing a live material.
- [x] Keep all requested data and the live material unchanged if texture load,
  shader load, reflection, material construction, or resource preflight fails.

### Task 4: Compose sheen with existing material features

- [x] Prove combined core textures, normal map, UV transforms, specular, opaque
  IOR, sheen, and clearcoat do not create multiple competing base materials or
  lose retained extension state.
- [x] Apply clearcoat above sheen. Verify that clearcoat attenuation affects
  the composed base-plus-sheen response rather than leaving an unattenuated
  sheen highlight above the coat.
- [x] Cover double-sided orientation, alpha/mask behavior, emission layering,
  shadows, fog, reset, persistence, repeated deltas, and render scheduling.
- [x] Prove no-sheen materials retain the existing native or extended path
  without a visual or resource regression.

### Task 5: Produce controlled candidate evidence

- [x] Stage hash-pinned Khronos `SheenChair`, `SheenCloth`,
  `GlamVelvetSofa`, and `ToyCar` fixtures with license/provenance records.
- [x] Freeze one comparison-state schema covering canonical bounds/camera,
  coordinate transforms, HDRI bytes and orientation, directional light,
  direct/IBL/combined passes, exposure, tone mapping, output color space,
  viewport, and renderer revisions.
- [x] Compare against Three.js and, where practical, Khronos Sample Viewer.
  Treat the reference as direction/conformance evidence, not pixel-parity.
- [x] Add a Three.js contract test that fails unless the pinned loader consumes
  factor, color texture, roughness, and roughness texture before capture.
- [x] Record close and grazing views that distinguish sheen from base roughness
  and ordinary specular. ToyCar must show the red fabric sheen independently
  from body clearcoat and glass transmission.
- [x] Record exact capture hashes, commands, diagnostics, target/backend, and
  pass criteria. Initial iOS Simulator output may be `verified locally` while
  maturity remains `candidate-only`; other targets remain `not run`.

### Task 6: Promote to renderer-native sheen

- [x] Add first-class sheen fields, texture slots, UV metadata, importer
  mapping, copying, and serialization to a separate `flutter_scene` checkout.
- [x] Extend renderer-owned PBR lighting with direct and IBL sheen plus the
  reviewed base-energy scaling. Extend or replace the DFG/prefilter contract
  with tests proving the data is real and sampled with the correct axes.
- [x] Exercise every renderer-supported direct-light kind through the shared
  standard path; absence of imported point/spot light support remains a
  separate capability and must not be hidden inside sheen.
- [x] Run upstream unit, shader, native, and WebGL2 tests. Produce a concrete
  upstream commit, then update the viewer pin only after publication is
  authorized and the commit is externally reachable.
- [x] Advertise `rendererNative` sheen only when the pinned importer, material,
  shader, IBL data, and all requested texture fields are present. Preserve
  `candidate-only` or diagnostic-only labels otherwise.

### Task 7: Close docs and capability evidence

- [x] Add per-target sheen rows to the generated capability matrix and keep
  application, visual verification, runtime availability, maturity, and target
  evidence separate.
- [x] Update public API, material/lighting, runtime pipeline, renderer notes,
  fixture provenance, and platform-evidence documents.
- [x] Run focused tests, upstream tests, `bash tools/run_checks.sh`,
  `python3 tools/repo_lint.py`, `git diff --check`, and each claimed target or
  package build.
- [x] Move this plan to completed only when every checked acceptance criterion
  has matching evidence and all remaining target/release boundaries are
  explicit.

## Acceptance criteria

- [x] No authored or runtime sheen request is silently dropped; optional and
  required extension behavior is typed and atomic.
- [x] Factor defaults/ranges, color RGB+sRGB handling, roughness alpha+linear
  handling, multiplication, samplers, UV0 transforms, and unsupported UV sets
  match Khronos semantics.
- [x] Direct-only and IBL-only tests show a distinct grazing cloth lobe with
  energy-aware base attenuation and no base-roughness/environment hack.
- [x] Combined specular/IOR/sheen/clearcoat materials preserve one coherent
  layering order, with clearcoat above sheen.
- [x] Package-local evidence is labeled `candidate-only`; no target is
  `production-ready` without a reachable pinned renderer-native revision,
  matching runtime/packaging evidence, and all applicable release gates.
- [x] The fixed-state Khronos/Three.js corpus is durable and hash-recorded for
  every claimed target; physical iOS, Android, and Web remain `not run` until
  actually exercised.

## Adjacent material-extension inventory

These are not part of Plan 018. The inventory prevents sheen work from being
mistaken for full modern-glTF material coverage.

| Extension or capability | Current viewer status | Product relevance | Recommended disposition |
| --- | --- | --- | --- |
| `KHR_materials_anisotropy` | absent | brushed metal, machined finishes, carbon fiber, directional highlights | [Plan 022](../deferred/022_khr_materials_anisotropy.md): renderer-native tangent, direct, and IBL work after Plan 019. |
| `KHR_materials_iridescence` | absent | thin-film coatings, automotive paint, coated glass/plastic | [Plan 023](../deferred/023_khr_materials_iridescence.md): renderer-native thin-film response and composition. |
| `KHR_materials_emissive_strength` | absent | LEDs, displays, lamps, bright emissive product accents | [Plan 021](../deferred/021_khr_materials_emissive_strength.md): HDR emission, exposure, tone mapping, and independent bloom evidence. |
| `KHR_materials_dispersion` | absent | wavelength-separated refractive glass/gems | [Plan 025](../deferred/025_khr_materials_dispersion.md); Plan 016's native transport prerequisite is complete, but Plan 025 remains deferred pending explicit promotion. |
| `KHR_materials_variants` | absent | named product color/material configurations | [Plan 020](../deferred/020_khr_materials_variants.md): atomic source-material selection and persistence, no BRDF. |
| `KHR_materials_diffuse_transmission` | absent; Khronos release candidate | thin translucent cloth, paper, leaves | [Plan 024](../deferred/024_khr_materials_diffuse_transmission.md): spec-gated feasibility, diagnostics, then native BTDF. |
| `KHR_materials_subsurface` | absent; Khronos initial draft | skin, wax, thick scattering materials | [Plan 026](../deferred/026_khr_materials_subsurface.md): research-only until explicit promotion gates pass. |
| `KHR_materials_pbrSpecularGlossiness` | absent; archived | compatibility with older assets | [Plan 027](../deferred/027_khr_materials_pbr_specular_glossiness_compatibility.md): bounded legacy conversion/fallback only. |
| `KHR_materials_unlit` | imported by pinned `flutter_scene` and surfaced as lit/unlit state | labels, UI-like meshes, baked-looking assets | Not a missing material lobe; retain tests and improve any remaining alpha-mask limitations separately. |
| `KHR_materials_transmission` / `KHR_materials_volume` | renderer-native published implementation; iOS Simulator `verified locally`; release pending | glass and transparent product parts | Completed Plan 016; physical iOS, Android, Web, packaging, and production-ready evidence remain open. |
| `KHR_materials_clearcoat` | renderer-native published implementation; stable pin `release pending` in completed Plan 015 | automotive/product coatings | Completed prerequisite. |
| `KHR_materials_specular` / opaque `KHR_materials_ior` | package-local `candidate-only`; iOS Simulator `verified locally` | dielectric reflectance and material matching | Preserve existing Plan 014 labels; physical iOS, Android, and Web remain `not run`. |
| `KHR_lights_punctual` | imported playback absent; viewer has one directional studio key | point/spot/directional authored-light parity | [Plan 019](../deferred/019_khr_lights_punctual.md): shared standard-material direct-light loop for every lobe. |

## Progress log

- 2026-07-22: Renderer-native viewer integration and the dedicated iOS
  Simulator control are GREEN at their current evidence boundary. Strict
  focused RED/GREEN retained the coherent package-owned candidate route when a
  patch starts from `FlutterSceneExtendedPbrState`, while pure standard-PBR
  sheen stays `rendererNative`; this preserves transformed core/specular/
  opaque-IOR state and atomic candidate-construction failures. The stale
  combined scalar-clearcoat/transmission/sheen expectation was corrected only
  after the pinned renderer contract confirmed that combination is supported;
  textured clearcoat at the portable sampler limit remains `blocked` before
  decode. `flutter_scene_adapter_material_test.dart` passed `88/88`; the
  relevant viewer aggregate passed `466` tests with `17` explicit GPU-gated
  skips; `flutter analyze`, Dart formatting, repository lint, and
  `git diff --check` were clean at that source boundary. A separate strict
  RED/GREEN diagnostic contract updated the current authored-mip probe from
  the former renderer revision to
  `766351c865c621e8720c726f9aa51173ce76e786` without changing historical
  provenance.

  The generated iOS harness now resolves the same immutable renderer revision
  and validates `27` retained candidate stages plus `6` scalar native-control
  stages. The final harness/runner/fixture aggregate passed `32/32`; the
  standalone renderer-native analyzer passed `2/2`; its package-independent
  source freeze, exact run-root audit,
  model/backend binding, and six-frame/three-delta finalizer incorporate the
  previous independent review findings. The first native capture attempt is
  retained at `renderer-native-run-01` as failed after an exact Float32
  directional-light representation mismatch. Strict RED/GREEN changed only
  vector comparison tolerance within the already frozen schema/scalars. The
  next retry at `renderer-native-run-02` succeeded but was superseded after
  the frozen source set gained its dedicated analyzer entry point and exact
  source guards. `renderer-native-run-03` then passed finalization and an
  independent evidence rereview, but the repository-wide format/analyze gate
  exposed an unused test-helper binding and normalized two capture-contract
  test files. Because those byte changes are source-guarded, run-03 is retained
  as superseded rather than relabeled. The final-current clean capture at
  `renderer-native-run-04` produced evidence SHA-256
  `fd94aacc490902e88e8b1459dac0f21f91c31ed441dca34f2b7b7ac720c261f8`
  on iPhone 17 / iOS 26.5 / Impeller Metal. Finalization,
  execution, application, visual,
  target, and iOS Simulator evidence are `verified locally`; runtime is
  available; feature maturity is `release pending`. Sheen-on applied as
  `rendererNative`, sheen-off applied as `none`, and direct/IBL/combined mean
  absolute sRGB deltas were respectively `0.06705855727896012`,
  `0.04602201102311509`, and `0.06834645980655281` against the frozen
  renderer-local threshold `0.0009765625`. This establishes only a
  renderer-local scalar on/off visual effect and structural frame health.
  External reference comparison, physical iOS, Android, Web, physical
  correctness, general pixel parity, release, and `production-ready` evidence
  remain `not run` / `release pending` as applicable. The manifest provenance
  contract records these separate axes and passed `6/6`. The generated
  capability matrix records the live iOS Simulator row as `rendererNative` /
  `verified locally` / available / `release pending`, retains the earlier
  four-model viewer corpus as historical `candidate-only` evidence, and leaves
  physical iOS, Android, and Web as `not run`; its tests pass `17/17` and the
  generator check is current.

  Plan 028 remains byte-identical at SHA-256
  `b4318a167d06f31878e062be405150c43b761add49a20cc249327ad549e12066`.
  Two inherited Python bytecode files also remain byte-identical. During an
  earlier delegated harness import, the inherited
  `run_plan018_ios_capture.cpython-314.pyc` was unintentionally regenerated
  from SHA-256 `0742603217d92ff78bf670aa42c1ea180e1a5e70951e559e108297f6f38f9c7f`
  to `69f601eda8f21d30cddceeb6814b3badd99ace34b77fd631bf2c06c674139cb2`;
  the exact original bytes are unavailable, so the incident is preserved and
  disclosed rather than hidden or replaced. Every later Python-backed check
  uses `PYTHONDONTWRITEBYTECODE=1`. Narrative/API/runtime/platform documents
  are bound to run-04. The final post-capture `bash tools/run_checks.sh` gate
  passed repository lint, Dart format with `0` changes, dependency resolution,
  clean `flutter analyze`, and `792` tests with `17` explicit GPU-gated skips.
  The standalone native analyzer passed `2/2`, the matrix generator is current,
  and `git diff --check` is clean. Exact run-04 reconstruction was independently
  `APPROVED` with no finding. The first viewer-wide final review withheld
  approval on two Important atomicity/fallback gaps: reader-rejected optional
  authored UV1 sheen could survive through the native importer, and a
  factor-only native sheen failure on an unlit target could apply visibility
  before returning its material-contract diagnostic. Separate strict focused
  RED/GREEN remediations are active. Because they change source-guarded viewer
  bytes, run-04 will remain superseded evidence after a fresh capture. Final
  gates/review, stage, commit, and push remain open.

  The final-review remediation is now source-frozen after strict focused
  RED/GREEN and fresh independent rereviews. Factor-only native sheen rejects
  unlit targets before visibility/material mutation. Optional authored sheen
  rejected at either material or primitive-binding stage now produces an exact
  per-load core fallback for every resolvable primitive; duplicate ambiguous
  paths use a global fail-closed fallback so importer-native sheen cannot
  survive. Valid renderer-importable UV1, data-URI, numeric-sampler, and
  optional spec-gloss cases preserve non-sheen state while neutralizing sheen.
  Malformed sheen/unlit, wrong-type bindings, missing selected UV, and UV2+
  assets block before adapter publication with `malformedAsset` and
  `fallback: none`. Scene selection and node-name synthesis match the pinned
  importer (`scene` absent selects scene 0; empty names become
  `node_<index>`), and one rejected material referenced by multiple unique
  primitives maps every address. The focused rereview returned `APPROVED`
  with no Blocker, Important, or Minor finding.

  Root verification is `verified locally`: the combined adapter/loader/reader/
  binding/widget command passed `241` tests with `3` explicit GPU-gated skips;
  harness/runner/fixture tests passed `55/55`; the standalone native analyzer
  passed `2/2`; and a strict frozen-source RED/GREEN updated only hashes for
  the four changed viewer source files. The pre-capture repository gate ran as
  `PYTHONDONTWRITEBYTECODE=1 bash tools/run_checks.sh` and passed repository
  lint, Dart format with `0` changes, dependency resolution, clean analysis,
  and `806` tests with `17` explicit GPU-gated skips. Capability-matrix check
  and `git diff --check` are clean. `renderer-native-run-04` is superseded;
  run-05 and its evidence review are `not run`.

  One root-invoked Flutter harness test was run before applying the shell-level
  bytecode guard and regenerated the already inherited/untracked runner
  pycache from SHA-256 `69f601ed...` to
  `150915ffe7e8b8a3f099618f8b820685d908ada644d0620595ebf868f79afa94`.
  The bytecode is preserved and excluded from staging; it is not evidence.
  Plan 028 remains byte-identical. Release remains pending; physical iOS,
  Android, physical correctness, general pixel parity, and
  `production-ready` evidence are `not run`.

  A subsequent fresh whole-source freeze review withheld approval on two
  Important address-mapping gaps, so the `806`-test gate above is a retained
  pre-review checkpoint rather than final-current source evidence. First,
  valid sheen candidates discarded for duplicate node paths did not set the
  global ambiguous-sheen fallback used for rejected candidates; required
  intent could therefore be silently lost under a non-native policy. Second,
  reader addresses used raw glTF primitive indices while the pinned importer
  skips non-triangle (`mode != 4`) primitives and compacts the runtime
  primitive list, allowing exact fallback to reach the wrong runtime
  primitive. Separate strict RED/GREEN remediations and another fresh review
  are active. Run-05 remains `not run`; no stage, commit, or push has occurred.

  Both address-mapping findings are now remediated under strict focused
  RED/GREEN. A valid sheen candidate on a duplicate node path now contributes
  typed ambiguity metadata whether or not its binding was rejected. Optional
  intent selects one per-load global `coreMaterial` fallback and neutralizes
  every importer-native sheen instance; required intent returns a blocking
  `ambiguousNodePath` diagnostic before adapter import. The material reader now
  mirrors pinned renderer revision
  `766351c865c621e8720c726f9aa51173ce76e786`: it skips `mode != 4`
  primitives and increments the runtime address for every retained triangle
  before material/extension filtering. The compacted-address regression first
  failed with a typed adapter failure and then passed against primitive index
  zero; no `flutter_scene`, vendor, override, or pub-cache source was changed.

  Current focused evidence is `verified locally`: the reader/model-loader
  aggregate passed `108` tests with `3` explicit GPU-gated skips; the owning
  adapter/reader/binding/native-applier/model-loader aggregate passed `216`
  tests with the same `3` skips; and capture runner/harness/fixture tests passed
  `55/55`. The source-freeze test first failed on the two expected hashes and
  then passed with material-reader SHA-256
  `225476d7688e213447dc94d69238e7403e3e44baf3b0962c6cd7116378072c6f`
  and model-loader SHA-256
  `72493b77d005c637c5ca4b588320f2b3ffb2652b750b24f2399a25c1ff53ed61`.
  `git diff --check` is clean. The fresh independent frozen-source review is
  `APPROVED` with no Blocker, Important, or Minor finding and confirms both
  fixes match the pinned importer and the capture hashes. Run-05, its evidence
  review, the final-current full repository gate, stage, commit, and push
  remain `not run`. Plan 028 and all inherited
  `tools/**/__pycache__` bytes remain preserved. Release remains pending;
  physical iOS, Android, physical correctness, general pixel parity, and
  `production-ready` evidence are `not run`.

  Fresh renderer-native iOS Simulator evidence is `verified locally` at
  `tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/renderer-native-run-05/evidence.json`,
  SHA-256
  `9f4d3e1b2c561174c9426ad0da653f09c8c3d8ab7494bdfa7dcdf06d121f74da`.
  The run used iPhone 17 / iOS 26.5 / Impeller Metal; sheen-on applied as
  `rendererNative`, sheen-off as `none`, and all six direct/IBL/combined
  frames plus all three frozen on/off deltas passed. A fresh independent
  artifact review matched all `80` frozen source hashes, identical preflight
  and postflight state, both manifests, logs, READY payloads, Impeller
  sidecars, PNG bytes, `6/6` frame checks, `3/3` comparisons, and `33/33`
  aggregate checks. Verdict: `APPROVED`, with no Blocker, Important, or Minor
  finding. The live provenance and generated capability sources are bound to
  run-05; their combined focused Flutter verification passed `23/23`, and the
  matrix generator is current.

  The final-current repository gate ran with
  `PYTHONDONTWRITEBYTECODE=1 bash tools/run_checks.sh`: repository lint passed,
  Dart formatting checked `103` files with `0` changes, dependency resolution
  succeeded, `flutter analyze` reported no issues, and `flutter test` passed
  `810` tests with `17` explicit GPU-gated skips. The standalone
  renderer-native analyzer passed `2/2`; standalone repository lint,
  capability-matrix generation, and `git diff --check` are clean. Evidence is
  limited to the renderer-local scalar on/off control on iOS Simulator.
  Physical iOS, Android, Web, external-reference comparison, physical
  correctness, general pixel parity, release, and `production-ready` remain
  `not run` / `release pending` as applicable. Final documentation/diff
  rereview returned `APPROVED` with no Blocker, Important, or Minor finding.
  The reviewer independently passed the high-risk reader/loader/adapter set at
  `197` tests with `3` explicit GPU-gated skips and confirmed the source,
  documentation, matrix, run-05 provenance, dependency pin, claim boundaries,
  and staging scope. Plan 018 is therefore closed at this bounded local
  evidence boundary. Exact staging, commit, and push remain the final delivery
  actions; they do not promote any release or target claim.

  Exact staging selected only Plan 018 task paths plus the Plan 017
  active-to-deferred coordination move. The hash-pinned Khronos Sample
  Renderer bundle contains upstream trailing-space and CRLF formatting, so its
  exact SHA-256
  `ca863c37b8deb6fcaa456e2a59da46311867aab2baf0d15bac48f5239b3a4f4b`
  is preserved without editing and one exact-path `.gitattributes`
  `-whitespace` rule keeps repository whitespace checks focused on owned
  source. Staged `git diff --check` is clean. Plan 028, all three inherited
  `tools/**/__pycache__` files, `tools/out`, ignored progress/lock files, and
  generated dependency/build output remain unstaged.
  A fresh independent staged-diff rereview returned `APPROVED` with no
  Blocker, Important, or Minor finding; it confirmed all `110` staged paths,
  the exact vendor hash, the narrow attribute scope, completed/deferred plan
  links, exclusions, and unchanged evidence claims.

- 2026-07-22: The viewer-native adapter boundary remains GREEN through three
  independent review/remediation rounds. The first review returned two
  Important findings: authored native preflight skipped the portable sampler
  guard, and later package-owned composition could lose retained native sheen.
  Strict focused RED/GREEN remediation now runs the sampler guard first,
  carries exact-address authored core-fallback plans per import call,
  neutralizes complete imported sheen only on the failed staged material, and
  preserves valid shared-material siblings. Renderer-native sheen state now
  bridges factor, roughness, both textures, and both transforms into the
  coherent transformed-core/specular/opaque-IOR candidate route. Required
  authored failures still block before adapter import, and scalar clearcoat +
  transmission + active sheen remains supported while the renderer's textured
  clearcoat sampler-limit combination remains blocked before decode. The next
  review confirmed those findings closed and found one Important lifecycle
  gap. Three strict REDs now race the complete authored preflight against
  success, error, timeout, and cancellation; every non-success terminal is
  typed, none reaches publication, and late completion cannot advance to a
  second address. A third fresh review found two Important UV-routing gaps.
  Package-owned same-delta sheen UV1 now fails atomically because its shader has
  no per-sheen-slot UV1 contract. Pure renderer-native sheen UV1 now succeeds
  only when the pinned geometry draw layout contains the exact authored
  `texture_coords_1` semantic; a UV0-only primitive returns `missingUvSet` with
  `uvSet: 1` and `status: blocked` before texture decode or material mutation.
  This inspects renderer geometry state rather than material selectors or asset
  names and neither invents UVs nor reinterprets channels. The next fresh review
  found one Important fail-open lifecycle gap: an optional addressless/global
  sheen resource failure reported `coreMaterial` fallback but supplied no
  fallback addresses, allowing importer-native sheen to survive. Two strict
  REDs now require both a global LUT failure and a missing preflight adapter to
  pass every parsed sheen address to the staged import fallback. GREEN records
  the complete affected set for that load, keeps address-scoped failures scoped,
  and proves a later plain load receives an empty plan. The full adapter file
  passed `88/88`; the full model-loader file passed `66` tests with `3` explicit
  GPU-gated skips; viewer-widget passed `39/39`; Dart format reported `0
  changed`, and `git diff --check` passed. The fresh final independent rereview
  returned `APPROVED` with no Blocker, Important, or Minor findings. This is
  `verified locally` for the stated Dart host behavior. The first full
  `flutter analyze` gate is RED with `100` Plan018 dirty-state diagnostics; an
  isolated `HEAD` comparison is clean, so analyzer remediation is now active.
  Wider viewer suites and iOS Simulator renderer-native capture remain `not
  run`; physical iOS and Android remain `not run`; release remains `release
  pending`; no `production-ready` claim, stage, commit, or push has occurred.

- 2026-07-22: M4 upstream implementation is committed, pushed, independently
  approved, and `verified locally` at its stated boundaries. The existing
  upstream branch `plan016-transmission-volume` advanced from
  `8e2e2221405b04c517189428d0faf8474cf7f708` to externally reachable commit
  `766351c865c621e8720c726f9aa51173ce76e786`
  (`feat(materials): add renderer-native sheen lighting`). The implementation
  adds dedicated Charlie direct and IBL paths, real DFG-B directional albedo,
  demand-driven Charlie prefiltering, authored sheen texture UV/transform
  routing, portable sampler failure boundaries, and clearcoat-above-sheen
  composition without exporting a renderer-internal BRDF API. Strict focused
  TDD covered the implementation and three review remediations: same-lighting
  sheen-off Web controls, lazy Charlie allocation, and dynamic-sky source
  double buffering. Final upstream checks passed `50/50` focused tests and
  `877` full-package tests with `14` explicit GPU-gated skips; package analysis
  was clean, Dart formatting reported `0 changed`, and `git diff --check`
  passed. A fresh independent rereview returned `APPROVED` with no Blocker,
  Important, or Minor finding. Selected WebGL2 sheen control pairs passed; the
  full smoke harness remains `blocked` only by a legacy `pbr_metallic` luma
  threshold reproduced byte-identically at the upstream baseline. macOS smoke
  is `blocked` by the foreground/service harness, while physical iOS, Android,
  release, and `production-ready` evidence are `not run` / `release pending`.
  No physical-correctness, general pixel-parity, release, or production-ready
  claim is made.

  The viewer pin and resolved lock now use `766351c865c621e8720c726f9aa51173ce76e786`
  through normal `flutter pub get`; no override, vendor edit, or manual
  pub-cache edit was used. Viewer strict TDD is partially GREEN for the current
  native probe (`release pending`, iOS Simulator evidence still `not run`),
  the complete native sheen applier, authored sheen copy preservation,
  renderer-native routing with package-local bypass, pre-import native probe,
  non-native import neutralization, and same-delta/retained portable sampler
  rejection before texture decode. The focused individual tests for these
  slices pass, and the native applier file passes `10/10`. The first related
  aggregate run is not green: `flutter_scene_adapter_material_test.dart`
  currently has three failures that must be triaged and resolved with focused
  TDD before wider verification: authored combined scalar-clearcoat/glass/sheen
  preflight now returns `null` where the former candidate route expected a
  composition diagnostic, so the native-supported combination boundary versus
  stale candidate expectation must be established; native clearcoat
  transformed-state expectations now observe one candidate config instead of
  two; and the intentional failing second candidate construction is bypassed
  by the new native route. The latter two cases must preserve existing custom
  material state rather than blindly adopting or rejecting the new route. No
  viewer full suite, iOS Simulator native capture, capability-matrix regeneration,
  Task 7 closure, final review, or viewer commit/push has run. The viewer
  remains on `main` at HEAD/origin
  `af0568c11126904bbcfae72338ba51fb313cc9e9` with an empty index and the
  inherited dirty/untracked Plan 018 state. Plan 028 and
  `tools/**/__pycache__` remain preserved.

- 2026-07-22: M4 renderer-native implementation is `blocked` before the first
  RED test mutation by the workspace safety layer. The user explicitly
  authorized the required M4/upstream/pin work and later exact commit/push, and
  the separate upstream checkout remains clean at
  `8e2e2221405b04c517189428d0faf8474cf7f708`. Read-only design inspection
  selected dedicated Charlie-prefiltered radiance, real Charlie directional
  albedo in DFG B with `(NdotV, roughness)` axes, two independent sheen texture
  slots, clearcoat-above-sheen layering, and an explicit portable 16-sampler
  failure boundary. The attempted test-only patch was rejected because the
  safety layer still treated the superseded no-upstream/no-M4 instruction as
  active and requested a fresh direct confirmation after disclosure. No M4
  test or production file changed; viewer and upstream indexes remain empty.
  Renderer-native sheen, native/WebGL2 evidence, physical targets, release,
  and production readiness remain `not run` / `release pending`.
  A second test-only mutation attempt after automatic active-goal continuation
  was rejected for the same reason: the continuation was not accepted as a
  direct user statement lifting the earlier no-upstream/no-M4 restriction.
  Explicit user confirmation remains required before upstream M4 files can be
  changed.
  A third consecutive automatic goal continuation again supplied no direct
  confirmation. The same safety condition therefore satisfies the goal's
  repeated-blocker threshold and Plan 018 is `blocked` at the unchanged clean
  upstream revision until the user explicitly lifts the earlier restriction.

- 2026-07-22: M3 Task 5 is complete with final four-model iOS Simulator
  evidence, while sheen maturity remains `candidate-only`. User authorization
  allowed the minimum upstream/pin work needed to resolve the genuine authored
  AO `TEXCOORD_1` blocker before M4. The separate upstream checkout first
  passed focused RED/GREEN tests for retained UV1 geometry, authored AO
  coordinate/transform selection, and sheen metadata, then passed the full
  `flutter_scene` package suite (`858` passed, `14` existing skips) and clean
  analysis. Existing upstream branch `plan016-transmission-volume` was committed
  and pushed at externally reachable revision
  `8e2e2221405b04c517189428d0faf8474cf7f708` with tree
  `f4a25955cc7fe886a0addb476387eea40ec86742`; the viewer pin and resolved lock
  now use that exact revision, and the pub-cache checkout is clean at the same
  commit/tree. No override, vendor edit, manual pub-cache edit, branch switch,
  or viewer worktree was used.

  The first post-pin SheenChair runs exposed, in order, retained-state naming,
  UV1 shader-varying, and core-group routing gaps. Each behavior change began
  with a focused failing test. The final narrow route accepts only an occlusion
  binding whose effective coordinate is exactly `1` when the imported PBR
  material already retains `occlusionTextureTexCoord == 1`; the pinned importer
  establishes that metadata only after validating authored `TEXCOORD_1` on the
  primitive. Other UV1 slots and unsupported coordinate sets remain
  fail-closed. No UV was generated, no channel was reinterpreted, and no asset
  name controls routing. The final source-state SHA-256 is
  `385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843`.
  Final reference evidence is Three.js `27/27` at
  `f86291c540ea7023a26451ad551b4b6d66181ee92f566cd13e5a273b8aa5498b`
  plus Khronos Sample Renderer ToyCar/GlamVelvetSofa `15/15` at
  `575cdc0756d62160ef98a179f715924947c665388b586fc70d00aeefcb842ee9`
  and
  `2fc47c399bcf296ffca2d39dc202237a64bbd1354a52d51889b19a70119b9e47`.
  `candidate-run-14` retained SheenChair `6/6`, SheenCloth `6/6`,
  GlamVelvetSofa `6/6`, and ToyCar `9/9`, with zero blocking diagnostics and
  per-model Impeller Metal records. Final `evidence.json` SHA-256 is
  `87cb87f7ecce3b5916ae72896d1b7980ca6d950ef18a2aed2165734cb8d05cbb`.
  The first and second fresh M3 boundary reviews each returned
  `CHANGES_REQUESTED`. Strict focused TDD now preserves the exact source-hash
  key set while permitting value drift only for the runner and runner test;
  production and other source hashes remain fail-closed. The audit-bound iOS
  renderer-local health sidecar at SHA-256
  `34f3ecd2c856e6ebe1707f79e1ff28af61222281368f27030e760b5d4cd83868`
  applies the already frozen structural thresholds to all `candidate-run-14`
  pixels and passes `27/27` full frames plus `9/9` direct/IBL/combined pass
  triplets. Stored validation now decodes the exact hash-bound PNG bytes and
  recomputes every frame summary, check, and pass delta before comparing the
  complete sidecar. Fabricated stored metrics are rejected. The contract
  checks blank, flat, framing, and renderer-local render-delta health only; it
  defines no cross-renderer pixel threshold and makes no pixel-parity claim.
  The final audit requires this sidecar and reports `pixelHealthStatus:
  verified locally` before M3 can close. Runner tests pass `22/22`; the health
  contract passes `2/2`. Current runner/test hashes are
  `7549f586175ffcc50f3ddd4370a26edb8090371db17ed1cbe58eeb8f79afcfac`
  and
  `479638a87cef4b75966cfcb82835249a4a7bc5cd25d42c210e89edb59384d6e4`;
  health analyzer/test hashes are
  `1545af82cbe1fdbe458be076f1158a7a6860fc04cbfb51347052e3db297ede5c`
  and
  `14340d4c42da69276fe1068a88190569adc48687786e3150ea53b8aa72bf9d5b`.
  A new fresh independent M3 rereview returned `APPROVED` with no Blocker,
  Important, or Minor finding after independently passing runner `22/22`,
  health `2/2`, stored `27/27` / `9/9` recomputation, the real final audit,
  repo lint, and diff check. M3 is closed at this `candidate-only` boundary;
  M4 may now start.
  Physical iOS, Android, Web, renderer-native sheen, production readiness,
  and pixel parity remain `not run`; release is `release pending`.

- 2026-07-21: The remaining M3 path audit reconfirmed the same SheenChair
  blocker for a third consecutive active-goal turn after completing the
  independent reference row. Only the close/grazing viewer-capture and final
  capture-hash/diagnostic rows remain open in Task 5, and both require an
  accepted SheenChair viewer capture. The frozen default-scene fabric
  primitive authors `occlusionTexture.texCoord == 1` and
  `KHR_texture_transform.texCoord == 1` while providing `TEXCOORD_0` and
  `TEXCOORD_1`. The exact pinned `flutter_scene` revision
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022` packs only `TEXCOORD_0` into its
  single `texture_coords` vertex stream and explicitly describes the runtime
  layout as providing only `TEXCOORD_0`. The wrapper binding contract rejects
  every effective texture coordinate other than zero with
  `perSlotTextureCoordinateContractMissing`; this prevents the pinned importer
  from silently sampling the authored UV1 occlusion map through UV0. Therefore
  the current allowed scope has no honest SheenChair capture path: UV
  generation or UV1-to-UV0 substitution would violate the asset boundary;
  stripping the authored occlusion channel would change the accepted capture
  contract; and adding the missing renderer vertex/material contract requires
  M4/upstream/pin work that is explicitly forbidden in the current task.
  Amending Task 5 to accept blocker proof in place of capture would be a
  material acceptance change and requires explicit user direction. The active
  Plan 018 goal is consequently `blocked`, not complete. M3 remains blocked,
  final `evidence.json` is absent, SheenChair iOS capture remains `not run`,
  capability remains `candidate-only`, M4 remains not started, and release is
  `release pending`. No pin, pub-cache, upstream, branch, worktree, index,
  commit, push, GitHub, or unrelated-state action was performed.

- 2026-07-21: The Task 5 Three.js/Khronos reference row is now
  `verified locally` / complete through a strict focused TDD audit, while
  feature maturity remains `candidate-only`. RED changed the real M3 audit
  test to require complete reference status plus exact coverage and failed on
  the former unconditional `candidate-only` / partial record. GREEN now parses
  the retained reference evidence fail-closed and verifies schema, fixed-state
  hash, direction/conformance boundary, exact capture inventory, PNG
  containment, SHA-256, byte length, and `1206 x 2622` dimensions. Three.js
  covers all four frozen models with `27/27` captures. The pinned Khronos glTF
  Sample Renderer covers the two practical audited models, ToyCar (`9/9`) and
  GlamVelvetSofa (`6/6`), for `15/15` captures. Reference evidence SHA-256
  values remain Three.js
  `1e35873f061f85afcefb0218a2b60677eebd4731beb63e245e35e06983bda3a1`,
  Khronos ToyCar
  `3af60b5d090620df08c01698bc8e28b506750b6a85a018dae8545901f08a348d`,
  and Khronos GlamVelvetSofa
  `9ffcc341478d3ba3be7ad2a3c7994155f9e584006bd1d65e0f7f07cb929d3c64`.
  The targeted GREEN passed `1/1`, the full runner file passed `20/20`,
  bytecode-free Python AST parsing exited `0`, and the real read-only M3 audit
  reports `threeAndKhronosReferences: verified locally` / complete while
  retaining `task5OverallCompletion: partial`, `m3Status: blocked`, final
  evidence `absent`, and `canStartM4: false`. Current runner/test SHA-256
  values are
  `391f02aa7a1e240ffd21d0395b9996b56e90833336a59adce9f55e34a12e0be7`
  and
  `5e232ad74854af5c7a52efdf80d19117cff12d14d6b2204f7480825941617372`;
  retained partial iOS evidence remains unchanged at
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  SheenChair iOS capture is still `not run`; close/grazing viewer evidence and
  final capture hashes/diagnostics remain partial. No final `evidence.json`,
  M4, index, commit, push, branch, worktree, dependency-pin, pub-cache,
  upstream, or unrelated cleanup action was performed.

- 2026-07-21: Status/UI-plan synchronization reconfirmed the active Plan 018
  boundary without changing implementation or evidence. Tasks 1-4 remain
  complete; Task 5 remains partial with two unchecked evidence rows; Tasks
  6-7 remain unstarted with nine unchecked rows. This leaves three top-level
  tasks open and eleven unchecked task rows, plus two unchecked acceptance
  criteria. The current user constraint forbids starting M4, so only the M3
  Task 5 blocker/closure investigation is active. Branch `main`, HEAD and
  local `origin/main` remain
  `af0568c11126904bbcfae72338ba51fb313cc9e9`, and the index remains empty.
  M3 is `blocked` under the current acceptance contract, SheenChair iOS
  capture is `not run`, final four-model evidence is absent, the feature is
  `candidate-only`, and M4 remains not started. No source, evidence, index,
  commit, push, branch, worktree, dependency-pin, pub-cache, upstream, or
  unrelated-state action was performed.

- 2026-07-21: M3 closure-disposition audit slice is strict-focused TDD GREEN
  with one independent test-hardening remediation and clean final rereview.
  RED changed the real partial-summary audit
  test to require `m3Status: blocked` plus a structured
  `m3ClosureDisposition`; it failed on the former `incomplete` value. GREEN
  binds the blocked closure to Task 5, the `sheenChairIOSCapture` gate, required
  model `sheen_chair`, static blocker evidence `verified locally`, execution
  evidence `not run`, final evidence `absent`, Task 5 `partial`,
  `canCloseM3: false`, `canStartM4: false`, and M4 `not started`. The
  resolution boundary permits no automatic substitution: the frozen model
  must be captured without invented UVs or reinterpreted channels, or Task 5
  acceptance must be explicitly amended; this audit does neither. The three
  Task 5 rows already reported `complete` by the preceding read-only checklist
  audit are now checked in the plan: fixture provenance, comparison state, and
  the pinned Three.js loader-consumption contract. Reference coverage,
  close/grazing viewer coverage, and final capture hashes/diagnostics remain
  unchecked and `partial`. The focused GREEN passed `1/1`; the full runner
  file passed `20/20`; bytecode-free Python AST parsing exited `0`; and the
  real `--audit-m3-status` against `candidate-run-08` returned
  `m3Status: blocked`, `task5OverallCompletion: partial`, final evidence
  `absent`, and `canStartM4: false`. The focused Dart format check reported
  `0 changed`, `python3 tools/repo_lint.py` passed, and `git diff --check`
  exited `0`. The full `bash tools/run_checks.sh` gate passed repo lint, the
  101-file format check, and `flutter pub get`, then remained `blocked` at
  `flutter analyze` by the same seven existing Plan 018 analyzer issues; no
  cleanup was kept because it would change frozen Plan 018 source identities.
  `pubspec.yaml` / `pubspec.lock` remain at SHA-256 `dea2bde0...` /
  `58a4fe06...`, and the exact pub-cache checkout remains clean at
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Fresh independent review found
  no Blocker or Minor issue and one Important mutation-sensitivity gap: the
  test only required the plan-amendment substring and did not lock the no-UV-
  invention, no-channel-reinterpretation, or no-automatic-amendment clauses.
  The test now asserts the exact resolution and claim boundaries. A temporary
  automatic-amendment mutant failed on the resolution boundary, and a separate
  shortened-claim mutant failed on the M3/final-evidence/M4 boundary. After
  source restoration and formatting, the targeted test passed `1/1`, the full
  runner file passed `20/20`, the real audit returned the exact blocked
  disposition, format reported `0 changed`, repo lint passed, and diff check
  exited `0`. Final independent rereview returned PASS with no Blocker,
  Important, or Minor findings. Current runner/test SHA-256 values are
  `ab8de3435ec13057ebd16f1db2c7c4d4832c2649529307d0087ef58622858c01`
  and `4fb86012a7ef4cf43c9247a1c64fc2143343abb486bbcddf54186bd7a53c2c7c`;
  retained partial evidence remains
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  M3 is open and blocked under its current acceptance contract; the feature
  remains `candidate-only`. SheenChair iOS capture, final four-model evidence,
  physical iOS, Android, Web, and production readiness remain `not run` or
  absent. No final `evidence.json`, M4, index, commit, push, GitHub, branch,
  worktree, upstream, dependency-pin, pub-cache, or unrelated cleanup action
  was performed.

- 2026-07-21: M3 SheenChair static blocker proof slice is strict-focused TDD
  GREEN with one reviewed documentation remediation. RED extended the real
  partial-summary audit test to require `sheenChairStaticBlocker`; it failed
  because `--audit-m3-status` did not emit that field. GREEN added a read-only
  frozen-GLB JSON audit that verifies the hash-pinned SheenChair source model
  at SHA-256
  `f0af2a2b102d28d540236306ae19f8fb36842df76bd38cf76f063f9bd2853399`.
  The audit records authored sheen material indices `[0, 4]`, default-scene
  sheen material index `[0]`, and the default-scene
  `SheenChair_fabric` primitive with material `0`
  `fabric Mystere Mango Velvet`, attributes `NORMAL`, `POSITION`,
  `TEXCOORD_0`, and `TEXCOORD_1`, plus authored
  `occlusionTexture.index == 1`, `occlusionTexture.texCoord == 1`, and
  `KHR_texture_transform.texCoord == 1`. The record is explicitly
  `status: not run`, `executionEvidence: not run`,
  `blockerEvidence: verified locally`, `blockerType:
  unsupportedMaterialFeature`, `unsupportedFeature:
  occlusionTexture.texCoord_1`, `acceptedEvidence: false`, and
  `finalEvidence: false`; it is static blocker proof only and does not satisfy
  SheenChair iOS capture or final four-model M3 evidence. Focused checks
  passed: the targeted RED/GREEN audit test, `python3 -m py_compile
  tools/run_plan018_ios_capture.py`, `flutter test
  test/plan018_ios_capture_runner_test.dart` (`20/20`), the real
  `python3 tools/run_plan018_ios_capture.py --audit-m3-status --run-root
  tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08`,
  `dart format --output=none --set-exit-if-changed
  test/plan018_ios_capture_runner_test.dart`, `python3 tools/repo_lint.py`,
  and `git diff --check`. Current hashes: runner
  `042eba90519b50d0a990212fbc8158ac17324b5d91650104b768d5d481c4dfa2`,
  test `15428d64c83e6edf66dbcbbdcab0171717baa3639c91f932317a8df9d2e53ae8`,
  partial evidence
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  Fresh read-only review found no Blocker, one Important, and no Minor
  findings: Plan018/progress logs were stale for this new slice and recorded
  prior source hashes. This entry and the matching SDD progress entry are the
  documentation remediation. Final read-only rereview returned no Blocker,
  Important, or Minor findings. M3 remains open and `candidate-only`; final
  `evidence.json` remains `absent`; SheenChair iOS capture remains
  `not run`; physical iOS, Android, Web, and production readiness remain
  `not run`; M4 was not started, and no index, commit, push, GitHub, branch,
  worktree, upstream, dependency pin, pub-cache, or unrelated cleanup action
  was performed.

- 2026-07-21: M3 Task 5 checklist audit slice is strict-focused TDD GREEN with
  clean final rereview. RED extended the real partial-summary audit test to
  require a read-only `task5Checklist`; it failed because `--audit-m3-status`
  did not report the Task 5 item map. GREEN added `task5_checklist_audit`,
  recording six Task 5 rows without writing evidence: `fixtureProvenance` and
  `comparisonState` are `verified locally` / `complete`;
  `threeLoaderContract` is `verified locally` / `complete`;
  `threeAndKhronosReferences`, `closeGrazingViews`, and
  `captureHashesDiagnostics` remain `candidate-only` / `partial`. The audit
  keeps `task5OverallCompletion: partial`, M3 `incomplete`, final
  `evidence.json` `absent`, SheenChair `not run`, and M4 `not started`. Fresh
  read-only review found no Blocker, one Important, and one Minor: artifact
  records could follow symlinked ancestor directories outside expected roots,
  and the test did not assert the artifact records supporting complete rows.
  RED reproduced the symlinked-ancestor case by importing the runner helper
  directly; GREEN now requires an expected artifact root before hashing/stat
  and returns `status: not run` without `sha256` for out-of-root paths. The
  test now asserts exact `fixtureProvenance`, `comparisonState`, and
  `threeLoaderContract` artifact paths/statuses/hashes plus the frozen state
  SHA. Final checks passed: `python3 -m py_compile
  tools/run_plan018_ios_capture.py`, `flutter test
  test/plan018_ios_capture_runner_test.dart` (`20/20`), the real
  `python3 tools/run_plan018_ios_capture.py --audit-m3-status --run-root
  tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08`,
  `python3 tools/repo_lint.py`, and `git diff --check`. Current hashes: runner
  `94fe93bb0be8e15fadb51f122ddfd5cf8f3a36210a2f0d153d41c205073ff628`, test
  `acf7e56d5b899b130ae7f1f66b9b0596d898495ced9953d98a724de5b7485873`,
  partial evidence
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  Final read-only rereview returned no Blocker, Important, or Minor findings.
  M3 remains open and `candidate-only`; final four-model evidence and
  SheenChair iOS capture remain incomplete / `not run`; M4 was not started,
  and no index, commit, push, GitHub, branch, worktree, upstream, dependency
  pin, pub-cache, or unrelated cleanup action was performed.

- 2026-07-21: M3 GlamVelvetSofa visual-only crop board slice is strict-focused
  TDD GREEN with clean final rereview. The RED added a focused Node test
  requiring a new crop-board module and failed on the missing module. GREEN
  added `build_plan018_glam_close_crop_board.mjs`, which reads current
  GlamVelvetSofa Three.js, Khronos Sample Renderer, and viewer iOS
  `candidate-run-08` PNGs, verifies all 18 source images are `1206 x 2622`,
  applies crop box `x=60, y=1120, width=1086, height=760`, and writes two
  usable close/grazing visual boards under
  `tools/out/material_extension_acceptance/plan018_controlled_comparison/visual_boards/`.
  The generated JSON is explicitly `status: visual-only`,
  `evidenceStatus: not evidence`, `comparisonBoundary: visual-only close crop`,
  `m3Status: incomplete`, `m4Status: not started`, and `canStartM4: false`; it
  does not claim pixel parity, physical correctness, renderer-native sheen,
  final M3 evidence, or M4 readiness. Source evidence roots are recorded
  without rewriting them: Three.js evidence SHA
  `1e35873f061f85afcefb0218a2b60677eebd4731beb63e245e35e06983bda3a1`,
  Khronos Glam evidence SHA
  `9ffcc341478d3ba3be7ad2a3c7994155f9e584006bd1d65e0f7f07cb929d3c64`, and
  viewer iOS Glam manifest SHA
  `9d497431aa2a498bda31089a777bce1b2ab0cd878bd147315567c967630097cd`.
  Generated visual-only board hashes: close
  `c2b2b0a5f294df7ca627083bbe3317c679ecf38b82f73000220b3ed0bb40deef`,
  grazing `62bccfae9380d227b884bd1d6fb9aba5edeb9531df6a051f68d6ceeed1ae5444`;
  manifest hash
  `4f93f3f3004ca9b851f1fae6d3c0ca6791b02f41733d66f8df64038b501ac296`.
  Focused checks passed: `node --check` for the module/test, `node --test
  tools/reference_renderers/threejs_material_extension_fixture/build_plan018_glam_close_crop_board.test.mjs`
  (`2/2`), real board generation, visual inspection of both generated boards,
  browser-process hygiene, `python3 tools/repo_lint.py`, and
  `git diff --check`. Fresh read-only review found no Blocker/Important and
  one Minor to assert exact `evidenceSources`; the test now asserts all three
  renderer ids, paths, hashes, byte lengths, and recomputed hashes. Final
  rereview returned no Blocker, Important, or Minor findings. M3 remains open
  and `candidate-only`, final `evidence.json` remains absent, SheenChair iOS
  capture remains `not run`, M4 was not started, and no index, commit, push,
  GitHub, branch, worktree, upstream, dependency pin, pub-cache, or unrelated
  cleanup action was performed.

- 2026-07-21: M3 historical SheenChair audit slice is strict-TDD GREEN with
  clean final rereview. The first RED extended the real partial-summary audit
  test to require historical SheenChair failed-attempt diagnostics; it failed
  because `--audit-m3-status` did not expose those records. GREEN added a
  read-only sibling `candidate-run-*` sweep for
  `manifests/sheen_chair.failed.json` that records historical attempts as
  `executionEvidence: not verified`, `acceptedEvidence: false`, and
  `finalEvidence: false`, and keeps the SheenChair gate `status: not run`. The
  real audit against `candidate-run-08` now reports three historical SheenChair
  attempts: `candidate-run-01` timeout/not unsupportedMaterialFeature,
  `candidate-run-02` failed/not unsupportedMaterialFeature, and
  `candidate-run-03` failed with `unsupportedMaterialFeatureDetected: true`;
  all remain diagnostic only and do not satisfy final four-model M3 evidence.
  Fresh read-only review found no Blocker and two Important issues plus two
  Minor issues: symlinked manifest/log ancestry could escape the attempt root,
  malformed historical manifests could abort audit, gate counts were not tied
  to the emitted list, and log scanning was unbounded. REDs reproduced
  malformed-manifest abort and symlinked-manifest escape; GREEN now emits
  invalid diagnostic records for malformed/out-of-root historical attempts,
  resolves manifest/log paths within the attempt root before hashing/reading,
  bounds log scanning at 1 MiB, and asserts exact gate/list count agreement.
  Final focused checks passed: `python3 -m py_compile
  tools/run_plan018_ios_capture.py`, `flutter test
  test/plan018_ios_capture_runner_test.dart` (`19/19`), the real
  `python3 tools/run_plan018_ios_capture.py --audit-m3-status --run-root
  tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08`,
  `python3 tools/repo_lint.py`, and `git diff --check`. Current hashes:
  runner `d4bcfadc98f58dc9b59acd94765e56677115d5d60378af69341196de69a2124e`,
  test `8403f10bc25408dda8659839df9d70184d4b4ac6cd45353c7e23c227b5a500ff`,
  partial evidence
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  Final read-only rereview returned no Blocker, Important, or Minor findings.
  M3 remains open and `candidate-only`, final `evidence.json` remains absent,
  SheenChair iOS capture remains `not run` due the genuine authored
  `TEXCOORD_1` ambient-occlusion / `unsupportedMaterialFeature` boundary, M4
  was not started, and no index, commit, push, GitHub, branch, worktree,
  upstream, dependency pin, pub-cache, or unrelated cleanup action was
  performed.

- 2026-07-21: M3 status audit slice is strict-TDD GREEN with clean final
  rereview. A focused RED extended the real
  partial-summary runner test to
  require `--audit-m3-status`; it failed because the runner did not recognize
  the flag. GREEN added a read-only M3 audit mode that reuses the retained
  partial-evidence validator and reports `m3Status: incomplete`,
  `m4Status: not started`, `canStartM4: false`, `finalEvidenceStatus:
  absent`, completed models SheenCloth/GlamVelvetSofa/ToyCar, and open gates
  for final four-model M3 evidence, SheenChair iOS capture, physical targets,
  Android, Web, and production readiness. The real audit command against
  `candidate-run-08` returned `status: candidate-only`,
  `executionEvidence: verified locally`, `comparisonBoundary:
  direction/conformance-only`, and the retained partial evidence SHA-256
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  SheenChair remains `not run` because of the genuine authored `TEXCOORD_1`
  ambient-occlusion / `unsupportedMaterialFeature` boundary; no UVs were
  invented or reinterpreted. Focused checks passed: `python3 -m py_compile
  tools/run_plan018_ios_capture.py`, `python3
  tools/run_plan018_ios_capture.py --audit-m3-status --run-root
  tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08`,
  `flutter test test/plan018_ios_capture_runner_test.dart` (`19/19`),
  `python3 tools/repo_lint.py`, and `git diff --check`. The full
  `bash tools/run_checks.sh` gate was attempted with local Flutter/Dart SDK
  cache access; repo lint, format check, and `flutter pub get` ran, but the
  gate stopped at `flutter analyze` with seven existing Plan 018 analyzer
  issues. A brief attempted cleanup showed that making those analyzer issues
  pass would require changing frozen Plan 018 source/state hashes and would
  risk invalidating retained `candidate-run-08` evidence, so the cleanup was
  not kept. Fresh independent read-only review returned no Blocker or
  Important findings and one Minor: the audit test only sampled three open
  gates and did not assert the nested partial-evidence boundary fields. The
  test now asserts the exact six open gates and statuses plus nested
  `candidate-only`, `verified locally`, `partial`, and
  `direction/conformance-only` fields; focused reruns passed for `flutter test
  test/plan018_ios_capture_runner_test.dart`, the real `--audit-m3-status`
  command, `python3 tools/repo_lint.py`, and `git diff --check`. Final
  read-only rereview after the test hardening returned no Blocker, Important,
  or Minor findings; residual risk remains the open final four-model M3,
  SheenChair iOS, physical iOS, Android, Web, M4, release, production, and
  pixel-parity evidence. M3 remains open and `candidate-only`; M4 was not
  started, and no index, commit, push, GitHub, branch, worktree, upstream,
  dependency pin, pub-cache, or unrelated cleanup action was performed.

- 2026-07-21: M3 retained partial-evidence validation slice is strict-TDD
  GREEN with clean independent rereview. A focused RED extended the real partial
  summary test to require `--validate-partial-summary`; it failed because the
  runner did not recognize the flag. GREEN added a read-only validation mode
  that refuses final `evidence.json`, requires existing
  `partial_evidence.json`, rejects failed manifests, revalidates the three
  captured model roots and success manifests, verifies stored capture and
  summary guards while comparing current non-source dependency/branch/pin/
  reference boundaries, confirms SheenChair remains absent, and checks the
  stored JSON still matches the retained artifacts without rewriting it. The
  real validation command accepted
  `candidate-run-08/partial_evidence.json` with SHA-256
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`,
  `status: verified locally`, `evidenceStatus: candidate-only`,
  `evidenceCompleteness: partial`, `comparisonBoundary:
  direction/conformance-only`, `finalEvidenceStatus: absent`, and
  SheenCloth/GlamVelvetSofa/ToyCar `21/21` PNGs. SheenChair remains
  `executionEvidence: not run` because of the genuine authored `TEXCOORD_1`
  ambient-occlusion / `unsupportedMaterialFeature` boundary; no UVs were
  invented or reinterpreted. Focused checks passed: `python3 -m py_compile
  tools/run_plan018_ios_capture.py`, `flutter test
  test/plan018_ios_capture_runner_test.dart` (`19/19`), `python3
  tools/run_plan018_ios_capture.py --validate-partial-summary --run-root
  tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08`,
  `python3 tools/repo_lint.py`, and `git diff --check`. Fresh independent
  read-only rereview returned no Blocker, Important, or Minor findings and
  independently reran the read-only validation command, confirming the retained
  artifact hash/mtime/size were unchanged. Residual risk is that the reviewer
  did not rerun the full Flutter suite or `tools/run_checks.sh`. M3 remains
  open and `candidate-only`; M4 was not started, and no index, commit, push,
  GitHub, branch, worktree, upstream, dependency pin, pub-cache, or unrelated
  cleanup action was performed.

- 2026-07-21: M3 partial Flutter/iOS evidence summary slice is strict-TDD
  GREEN with clean independent rereview. The first focused RED proved
  `--summarize-partial` was not wired into
  `tools/run_plan018_ios_capture.py`; GREEN added a separate fixture and real
  partial-summary path without weakening the fail-closed four-model
  `--finalize` path. A second focused RED reproduced that valid historical
  `candidate-run-08` manifests were rejected after summary-tool source edits;
  GREEN now records captured model-manifest `sourceSha256` separately from
  `summarySourceSha256` while still requiring stable capture preflight/
  postflight, one shared capture guard across the three summarized models, and
  current non-source dependency/branch/pin/reference boundaries. The real
  summary command wrote
  `tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08/partial_evidence.json`
  at SHA-256
  `9e3e0c72c303b78678ff594f0e2b62f2a120ce7192d4fbec8905e1f178ee996c`.
  The artifact is `candidate-only`, `executionEvidence: verified locally`,
  `evidenceCompleteness: partial`, `comparisonBoundary:
  direction/conformance-only`, and records SheenCloth/GlamVelvetSofa/ToyCar
  `21/21` PNGs with three logs, three backend evidence files, and three
  manifests. SheenChair remains absent with `executionEvidence: not run`
  because of the genuine authored `TEXCOORD_1` ambient-occlusion /
  `unsupportedMaterialFeature` boundary; no UVs were invented or
  reinterpreted. Final `evidence.json` remains absent; physical iOS, Android,
  Web, production readiness, renderer-native sheen, release, and pixel parity
  remain `not run` / `release pending` / unclaimed. Focused checks passed:
  `python3 -m py_compile tools/run_plan018_ios_capture.py`, `flutter test
  test/plan018_ios_capture_runner_test.dart` (`19/19`), `python3
  tools/repo_lint.py`, and `git diff --check`. Fresh independent read-only
  rereview returned no Blocker, Important, or Minor findings; residual risk is
  that the reviewer did not rerun the tests or capture command, but did inspect
  the code, artifact SHA, PNG inventory/dimensions, manifest/hash separation,
  and docs. M3 remains open and `candidate-only`; M4 was not started, and no
  index, commit, push, GitHub, branch, worktree, upstream, dependency pin,
  pub-cache, or unrelated cleanup action was performed.

- 2026-07-21: Fresh independent read-only review of the Glam/Khronos boundary
  returned no Blocker and one Important documentation finding. The reviewer
  accepted the Khronos ToyCar `9/9` and GlamVelvetSofa `6/6`
  direction/conformance artifacts, pinned renderer/source identities, shader
  sheen binding, pass-distinct pixel checks, and disclosed E-LUT boundary, but
  found stale wording in
  `.superpowers/sdd/plan018-m3-toycar-sheen-difference-diagnosis.md` that still
  described post-clamp ToyCar Flutter pixels as `not run`. A focused RED
  doc-consistency check reproduced the stale section, and the diagnosis now
  records `candidate-run-08` as existing partial Flutter/iOS evidence for
  ToyCar, SheenCloth, and GlamVelvetSofa while keeping SheenChair/final
  four-model evidence absent. Focused rereview found one remaining stale
  sentence in the diagnosis's clamp-correction section; the sentence now
  records `candidate-run-08` as the current post-correction ToyCar evidence
  instead of saying no post-correction Flutter capture ran. M3 remains open and
  `candidate-only`. Final focused rereview accepted the remediation with no
  Blocker, Important, or Minor findings. No M4, source, fixture, artifact, pin,
  pub-cache, upstream, index, commit, push, GitHub, branch, worktree, or
  unrelated cleanup action was performed.

- 2026-07-21: Work paused again at the user's request for continuation in a
  new thread. A fresh independent read-only Glam/Khronos review agent was
  spawned after local hash and `node --check` verification, but it was closed
  before completion when the user requested the handoff prompt; therefore no
  new independent review result exists for this boundary. The active goal
  remains open. No source, evidence, fixture, index, commit, push, GitHub,
  branch, worktree, upstream, dependency pin, pub-cache, cleanup, or M4 action
  was performed after the previous local GREEN/hygiene boundary.

- 2026-07-21: Work paused at the user's request after the GlamVelvetSofa
  Khronos reference slice reached local GREEN. The active goal remains open
  because no goal-tool pause state is available and this is neither complete
  nor blocked. Latest established evidence before this pause: Glam focused
  browser `1/1`, ToyCar Khronos browser regression `1/1`, Glam inventory
  `1/1`, `node --check` for both Khronos source files, `python3
  tools/repo_lint.py`, and `git diff --check` passed. Independent rereview has
  not run for this new Glam/Khronos boundary. M3 remains open and
  `candidate-only`; SheenChair/final four-model evidence is incomplete, M4 was
  not started, and no index, commit, push, GitHub action, upstream edit,
  dependency pin, pub-cache checkout change, or unrelated cleanup was made.

- 2026-07-21: GlamVelvetSofa now has pinned current-Khronos Sample Renderer
  direction/conformance evidence at the local host/browser boundary. Strict
  TDD resumed from the paused RED: the missing six-record inventory export had
  already gone GREEN, the full capture RED failed on the missing run/validator
  export, GREEN added a GlamVelvetSofa run path, authored sheen/light
  inspector, pinned-input guard, renderer-facts assertion, and exported
  validator. A follow-up RED exposed that shader uniform `0.6` roughness must
  be compared with float tolerance rather than exact decimal equality; GREEN
  kept the field asserted with a `1e-7` tolerance. `node --check` passed for
  both Khronos source files. The focused local-only HTTP/headless-Chrome Glam
  test passed `1/1`, writing six `1206 x 2622` PNGs and
  `glam_velvet_sofa_evidence.json` SHA-256
  `9ffcc341478d3ba3be7ad2a3c7994155f9e584006bd1d65e0f7f07cb929d3c64`.
  The shared ToyCar Khronos browser contract was rerun and passed `1/1`,
  preserving nine pairwise-distinct ToyCar PNGs with refreshed ToyCar evidence
  JSON SHA-256
  `3af60b5d090620df08c01698bc8e28b506750b6a85a018dae8545901f08a348d`.
  Current Khronos harness source hashes are render module
  `1b5d266bf66bffa40228bcadbdff7e204bf527c3ad8ba23e5859a7bfe0cc539d` and
  test contract
  `4987d5d246304c7116dada9ff13988a2a0dfacad59d8daf73d7ac5367687ae7f`.
  Independent artifact inspection found ToyCar `9/9` and GlamVelvetSofa `6/6`
  captures, all `1206 x 2622`, with per-view pass triplets pairwise distinct.
  Targeted temp-profile checks found no `plan018-khronos-capture-*`
  leftovers; targeted process inspection found only the inspection command
  itself. Cropped `/tmp` visual previews were generated for user inspection
  only and are not evidence. A later stop-boundary check ran `python3
  tools/repo_lint.py` and `git diff --check` successfully; independent
  rereview remains pending. No index, commit, push, GitHub action, upstream
  edit, dependency pin, pub-cache checkout change, or M4 work has run at this
  new boundary. M3 remains open and `candidate-only`; SheenChair/final
  four-model evidence is still incomplete.

- 2026-07-21: Work paused at the user's request before the GlamVelvetSofa
  Khronos reference slice reached GREEN. A focused RED first required a
  `buildPlan018KhronosGlamVelvetSofaCaptureInventory` export, then the minimal
  inventory implementation passed `1/1` for the six fixed
  close/grazing direct-only, IBL-only, and combined records. A second focused
  RED required a full GlamVelvetSofa Khronos run/validator and failed on the
  missing export, as expected. Source edits then began generalizing the pinned
  Khronos runner and adding a GlamVelvetSofa capture entry point, but this is
  intentionally incomplete: the Glam validator, pinned-input helper, authored
  sheen inspector, and renderer-facts helper are not finished; no
  post-edit `node --check`, browser test, evidence JSON, PNG artifacts,
  visual audit, process-hygiene check, repo lint, diff check, independent
  review, index, commit, push, or GitHub action was performed after those
  partial GREEN edits. At that pause boundary, GlamVelvetSofa Khronos evidence
  remained `not run`, M3 remained open and `candidate-only`, and ToyCar-only
  Khronos evidence remained the latest verified Khronos slice; a later
  continuation added GlamVelvetSofa Khronos direction/conformance evidence.

- 2026-07-21: Continuation resumed on `main` with `HEAD` and `origin/main`
  both at `af0568c11126904bbcfae72338ba51fb313cc9e9`; the index had no
  staged changes. The hardened current-Khronos ToyCar harness source was
  reread at render/test SHA-256
  `4270a43434c07bac95ad08fa46dc0bea77f776a301f4a571b62432837e209618` and
  `adca88e685fe9ebaff11705eeba30d341cee6b11a677fd80b04650475f6cbccd`.
  Both `node --check` commands passed. The required focused local-only
  HTTP/headless-Chrome browser test then passed `1/1`, regenerated all nine
  `1206 x 2622` ToyCar PNGs, and wrote evidence JSON SHA-256
  `db8213802cdffb0dcbf7a843843c2aad9eb541e294686f276a8b3d7410cc2abb`.
  The exported validator independently accepted the retained evidence with
  nine captures, and all close/grazing/context direct-only, IBL-only, and
  combined pass triplets are pairwise distinct. Representative original-detail
  image inspection found nonblank, correctly framed close/combined,
  grazing/direct-only, and context/combined captures. Targeted process checks
  found no `plan018-khronos-capture`, test-runner, Puppeteer, webdriver,
  HeadlessChrome, or remote-debugging Chrome leftovers, and targeted temp
  profile checks under the harness temp roots returned no leftovers. A fresh
  independent read-only review returned PASS with no Blocker or Important
  findings. The evidence remains Khronos direction/conformance-only; the
  `renderer-native pow(linear, 1/2.2)` string records the Sample Renderer
  output-transfer behavior, not viewer `rendererNative` sheen capability.
  Post-clamp Flutter pixels remain `not run`, M3 remains open and
  `candidate-only`, and no source edit, fixture edit, pin, pub-cache,
  upstream, index, commit, push, or GitHub action was performed.

- 2026-07-21: Post-clamp Flutter/iOS Simulator evidence now exists for three
  of the four M3 models in `candidate-run-08`, but final M3 evidence remains
  incomplete. The live runs accepted ToyCar `9/9`, SheenCloth `6/6`, and
  GlamVelvetSofa `6/6` `1206 x 2622` PNGs with `captureExitCode: 0`,
  `executionEvidence: verified locally`, `featureMaturity: candidate-only`,
  `physicalTargets: not run`, `comparisonBoundary: direction/conformance-only`,
  exact preflight/postflight source hashes, and process-correlated Impeller
  Metal sidecars. Manifest SHA-256 values are ToyCar
  `965459c0a1cf7fb10aadab2710f2f2018cb7ce1e0a6a1aa91c6dbd7f2221f492`,
  SheenCloth
  `168193e60c8e16ec384c4f6405253594b1e518d2e4f7134925f2e607ead4bb6c`,
  and GlamVelvetSofa
  `9d497431aa2a498bda31089a777bce1b2ab0cd878bd147315567c967630097cd`.
  The finalizer remains fail-closed and returned
  `Plan018CaptureError: sheen_chair log or response is missing`; no final
  `evidence.json` exists for `candidate-run-08`. The SheenChair gap remains the
  genuine authored `TEXCOORD_1` ambient-occlusion/`unsupportedMaterialFeature`
  boundary from the pinned renderer path, and no UVs were invented or
  reinterpreted. Representative original-detail frames for ToyCar, SheenCloth,
  and GlamVelvetSofa were inspected; focused runner test, `python3
  tools/repo_lint.py`, `git diff --check`, targeted process checks, and
  temporary-profile checks passed. A fresh independent read-only review passed
  with no Blocker or Important findings. At that boundary Khronos evidence
  remained ToyCar-only and GlamVelvetSofa Khronos was `not run`; a later
  continuation added GlamVelvetSofa Khronos direction/conformance evidence
  while M3 still remained open.

- 2026-07-21: The source-pinned current Khronos ToyCar comparison reached an
  intermediate focused GREEN and exposed a harness-local light-uniform defect,
  not a package BRDF defect. Strict RED first proved that direct/combined
  reported an injected light while combined remained byte-identical to
  IBL-only. Runtime evidence then localized the loss: source and prepared light
  directions were exact, but GPU `u_Lights[0].direction` was `[0, 0, 0]`.
  Replacing Khronos's renderer-owned `Float32Array` with a plain JavaScript
  array made the pinned uniform helper route to nonexistent `direction[0]`;
  preserving the typed vector with `.set(...)` produced `1/1` GREEN and nine
  pairwise-distinct `1206 x 2622` captures. Intermediate evidence SHA-256 is
  `8d1bb436cc27f8738aadcb64c7ccc77fd7e1ca72bce4ec145609a034e9f5840c`.
  A fresh original-detail audit found no Blocker: Khronos also shows
  normal-map-aligned mottling and grazing dark patches, so Flutter's mottling
  is directionally closer to Khronos than the smoother Three.js response;
  Flutter `candidate-run-07` is nevertheless darker/more crushed with fewer
  bright red midtones. That Flutter run predates the direct-visibility clamp,
  and current Khronos pixels retain the disclosed E-LUT upload bug, so neither
  is a current-source physical or pixel oracle. A fresh independent harness
  review requested two Important evidence remediations: make the exported
  validator own runtime/pixel-distinctness checks and bind the proof to the
  actual Fabric shader instead of the last-drawn scene program. Both are now
  implemented with Fabric `MATERIAL_SHEEN`/pass defines, authored sheen
  uniforms, real GPU light uniforms, LUT initialization, visible-light count,
  and fail-closed triplet checks. A later continuation reran the final browser
  GREEN under local-only HTTP/headless-Chrome access; it passed `1/1` with
  evidence JSON SHA-256
  `db8213802cdffb0dcbf7a843843c2aad9eb541e294686f276a8b3d7410cc2abb`.
  Post-clamp Flutter pixels remain `not run`. M3 remains open and
  `candidate-only`; no branch, worktree, index, commit, push, GitHub, upstream,
  pin, override, or pub-cache action was performed. Plan028 and the original
  pycache state remain preserved.

- 2026-07-21: The ToyCar correctness follow-up no longer treats either
  Three.js or the current Khronos Sample Renderer pixels as an oracle. A
  focused RED (`0/1`) proved that both package-local runtime candidate sheen
  shaders lacked
  the current Sample Renderer direct `V_Sheen` `[0, 1]` robustness clamp; the
  minimal two-line GREEN passed the new contract and four adjacent fragment
  contracts (`1/1` each). The post-correction sheen and combined-shader hashes
  are `b9f747e1668479eb24f4879c2367046e58e55bee12f19d29ed2849e9bf9c8010`
  and `f33b84ed50bb9587af3df1fba54e0f5bc8675f9bc70c42b6e158748ef854b358`.
  A separate source audit and independently repeated real Chrome 150/WebGL2
  probe found that current Khronos `lut_sheen_E.png` contains sRGB-encoded E
  values but is marked/uploaded as linear `GL.RGBA` and sampled directly. At
  roughness `.5`, `NdotV=.5`, current Viewer behavior reads `.470588` while the
  intended decoded value is `.188630`; the package's linear half-float E is
  `.188179`. The package LUT remains unchanged because copying that current
  Viewer upload bug would not be conformance. Accepted `candidate-run-07`
  predates the shader correction and is now historical for these exact source
  hashes; at that boundary a post-correction Flutter capture was `not run`.
  A later continuation produced partial `candidate-run-08` Flutter/iOS
  evidence for ToyCar, SheenCloth, and GlamVelvetSofa, while final four-model
  M3 evidence remains incomplete. The
  source-pinned current Khronos nine-frame capture was later completed through
  the hardened evidence slice above. M3 remains open and
  `candidate-only`; no physical-target, renderer-native, release, or production
  claim is established. No branch, worktree, index, commit, push, GitHub,
  upstream, pin, override, or pub-cache action was performed.

- 2026-07-21: A source-level and official-golden diagnosis was completed for
  the accepted ToyCar Flutter-versus-Three cloth difference. ToyCar's `Fabric`
  material has saturated red sheen at roughness `0.5`, no sheen textures, and
  a repeated normal map. Three r167 applies a constant `0.843` base multiplier;
  the package candidate and current Khronos Sample Renderer instead use
  angle-dependent view/light directional-albedo attenuation. This makes the
  package's direct layering structurally closer to the Khronos full approach
  while explaining why perturbed-normal variation becomes darker and more
  mottled than Three. The package is not identical to Khronos: current Khronos
  clamps direct fitted visibility to `[0, 1]` and owns dedicated Charlie IBL
  resources, while the package follows the unclamped written equation and
  reuses GGX-prefiltered radiance as a documented `candidate-only`
  approximation. The official Render Fidelity ToyCar Sample Viewer thumbnail
  also contains visible cloth texture/mottling, but its different camera and
  lighting make it qualitative context only. SceneKit has no first-class
  sheen reference; RealityKit's separate public sheen surface does not expose
  the glTF roughness/BRDF contract. Exact same-state Khronos capture and the
  three attenuation/clamp/normal-map diagnostic A/Bs remain `not run`. No
  production source or accepted capture was changed. Detailed evidence is in
  `.superpowers/sdd/plan018-m3-toycar-sheen-difference-diagnosis.md` at
  SHA-256
  `5c582f72ecf029ea201a96769d3bf006719643b4cf5ad303ece1ed94310394a6`.

- 2026-07-21: The user reopened the target Simulator and the previously
  blocked application-management prerequisite cleared. A fresh live plan
  selected the exact booted iPhone 17 / iOS 26.5 Simulator at UDID
  `10C2CF77-CBA8-4948-ADD5-24C49D375059`; HEAD/origin, `main`, root
  dependency bytes, exact clean `5dcf6fce...` pub-cache checkout, current
  Three `27/27` evidence, generated harness, and frozen source hashes passed.
  Strict focused TDD replaced 1020-byte-truncated full READY stdout lines with
  bounded `{stage, sha256, byteLength}` markers bound to exact full UTF-8 READY
  strings in the integration response. Mutation coverage rejects raw-byte,
  order, count, type, length, schema, and embedded-marker drift. Harness tests
  passed `11/11`, runner tests passed `17/17`, generated validation passed 27
  stages, generated analyze was clean, repo lint/diff checks passed, and a
  fresh independent refreeze review returned PASS with no Blocker or Important
  finding. Historical `candidate-run-02` through `candidate-run-06` remain
  `failed` / `not verified`.

- 2026-07-21: Fresh `candidate-run-07` is the first accepted Plan 018 ToyCar
  Flutter/iOS Simulator set: `captureExitCode: 0`, `executionEvidence:
  verified locally`, nine exact READY markers/full records, nine valid
  `1206 x 2622` PNGs, one COMPLETE record, terminal Flutter test success, and
  an exact same-process/same-window Impeller Metal sidecar correlated to Runner
  PID `21296`. Preflight equals postflight. Manifest SHA-256 is
  `c2db5066588400a683d05088bf3e839dacbad90170d5e71e7d2164b2ba0fba92`;
  feature maturity remains `candidate-only`. The frozen renderer-local health
  contract passed all 18 Three/Flutter full frames, six view/pass triplets,
  and nine descriptive pairs without a cross-renderer pixel threshold. An
  independent original-detail audit of all nine matching
  `three@0.167.1`/Flutter pairs returned PASS for qualitative
  direction/conformance. Camera/silhouette, direct/IBL/combined direction, and
  separate red-fabric versus body-clearcoat/glass response agree; Flutter's
  stronger cloth mottling/near-black direct-only contrast is retained as a
  non-blocking renderer-output difference, not pixel parity. The exact
  nine-stage hashes, health observations, audits, failed-run boundaries, and
  remaining scope are recorded in
  `.superpowers/sdd/plan018-m3-task5-slice5b-attempt2-report.md` at SHA-256
  `686e6cc14c7092064f8bade08c2cd3fcbdab58f69080179260efb37920fc15fd`.
  M3 remains open: accepted SheenCloth/GlamVelvetSofa captures are not run,
  SheenChair retains the genuine authored `TEXCOORD_1` AO gap, and the final
  four-model 27-PNG evidence set does not exist. Physical targets,
  renderer-native sheen, release, and production readiness remain
  unestablished; M4 was not started.

- 2026-07-21: A final outside-sandbox, read-only
  `simctl get_app_container` probe again exited `124` after the exact
  10-second bound with no output. The same target-Simulator
  application-management/install-coordinator prerequisite has now persisted
  for three consecutive goal turns, no lifecycle authority was provided, and
  `candidate-run-02` remains absent. The active goal is therefore `blocked`
  pending either a user-performed Simulator restart or explicit authority for
  `simctl shutdown` then `simctl boot` on UDID
  `10C2CF77-CBA8-4948-ADD5-24C49D375059`. The goal is not complete: M3 remains
  open; Flutter/iOS pixels, ToyCar iOS, renderer-local iOS health, and the
  cross-renderer comparison remain `not run` / `not verified`. No reset,
  erase, uninstall, service termination, source, Git, pin, pub-cache, upstream,
  or external-write action was performed.

- 2026-07-21: Read-only follow-up narrowed the live-capture prerequisite to a
  target-Simulator `installcoordinationd` crash loop. Outside the sandbox,
  bounded device listing became responsive, but bounded
  `get_app_container` again exited `124`. The target MobileInstallation logs
  contain no 2026-07-21/Plan018 entry. An aggregate parse of all 19 host crash
  reports found the same Simulator coalition and one identical
  `EXC_BREAKPOINT` / `SIGTRAP`, `libdispatch` `Abort Cause 2`, and triggered
  `_dispatch_ios_simulator_memorypressure_init` frame less than 0.3 seconds
  after each `installcoordinationd` launch; the first/last captures were
  `07:35:04` and `08:17:38 +0300`, with the latter occurring during follow-up
  diagnosis rather than a capture run. Current process evidence has no
  surviving install coordinator or capture/install child. This is
  infrastructure evidence before app launch, not a Plan018 plist or app-code
  finding. No retry, source edit, or Simulator lifecycle/service action was
  performed; `candidate-run-02` remains absent. The live-capture prerequisite
  remains `blocked`, while the active goal and M3 remain open and ToyCar iOS /
  cross-renderer output remains `not run`.

- 2026-07-21: The first live M3 Task 5 iOS Simulator capture attempt is
  retained as `failed` / `not verified`. The reviewed runner selected the one
  available booted iPhone 17 / iOS 26.5 Simulator, passed plan-only and
  preflight guards, built SheenChair in 40.0 seconds, and then reached an
  unresponsive `simctl install`. At its exact 1800-second deadline it retained
  a typed `CaptureTimeoutError` with TERM/KILL/reap/process-group/EOF evidence.
  No READY/COMPLETE record or Flutter PNG was produced, and ToyCar was not run
  through Flutter/iOS. Preflight/postflight source, pin, clean pub-cache, and
  current Three `27/27` guards remained exact. A later outside-sandbox,
  10-second `simctl get_app_container` probe also timed out with exit `124`, so
  no second 30-minute capture was started and `candidate-run-02` was not
  created. No Simulator lifecycle or service action was taken. Live capture
  is currently `blocked` on responsive Simulator app management; M3 remains
  open and the cross-renderer comparison remains `not run`. Exact retained
  artifacts and boundaries are recorded in
  `.superpowers/sdd/plan018-m3-task5-slice5b-attempt1-report.md`.

- 2026-07-21: The M3 Task 5 pre-capture runner slice is strict-TDD GREEN,
  root-reverified, and independently `APPROVED` after one remediation cycle
  with no Blocker, Important, or Minor findings. The initial review found two
  Important gaps: unbounded child-process execution and under-grounded READY
  records. The final focused file passed `14/14` and now proves process-group
  timeout/TERM/KILL/reap/EOF/partial-log behavior plus exact frozen cameras,
  full lighting, generic GLB-derived authored/default inventories, installed
  sheen records, and source-derived separate extension factors/addresses with
  no asset-name routing. Runner SHA-256 is `7c3bf111993cf0b191a8b8c38529ec9e607b25b71dd4a5149a3dd6b6cb82baff`;
  test SHA-256 is `c34a797eb2eab725fc3c8d6f868572b11764c6adc981db5e4e2d7014b29d6ef0`.
  The complete dirty M2/harness/state/model/HDR/Three/pin guards remain exact.
  Live Simulator discovery, `flutter drive`, Flutter GPU pixels, and the
  cross-renderer comparison remain `not run`; maturity remains
  `candidate-only`.

- 2026-07-21: The pinned Three.js reference set was refrozen after the
  analysis-only package scripts changed its recorded source identity. Root
  `npm run test:plan018-capture` passed `3/3`, regenerated the exact `27/27`
  capture inventory including ToyCar `9/9`, and recorded current evidence
  SHA-256 `1e35873f061f85afcefb0218a2b60677eebd4731beb63e245e35e06983bda3a1`.
  The expected current-evidence RED then failed `8/9` on the former historical
  label; the minimum GREEN passed `9/9`, analyzed 27 full frames and nine
  renderer-local pass triplets, retained no cross-renderer threshold, and
  wrote current health baseline SHA-256
  `726435193cd56efafedb6414b610731b21cd2e19302ea5045fda9057a5d6eb32`.
  Root inspected all 27 refrozen frames and reopened the three darkest
  direct-only grazing views at original resolution. Process/profile checks
  were empty. Flutter/iOS capture and cross-renderer comparison remain
  `not run`; this is pinned-reference direction/conformance evidence only.

- 2026-07-21: The three deterministic iOS-harness pre-capture review findings
  are strict-TDD GREEN and independently `APPROVED` with no Blocker,
  Important, or Minor finding. The generated resolved lock and package config
  now hard-retain exact `flutter_scene` revision `5dcf6fce...`; both final
  compatible stats samples require positive FPS and active render policy; and
  generic ToyCar clearcoat/transmission installed factors must equal their
  authored reader patches without an asset-name branch. Root and reviewer
  focused suites each passed `8/8`, resolved-output validation passed 27
  stages, and generated analysis was clean. Simulator and capture remain
  `not run`; the result remains `candidate-only`.

- 2026-07-21: The M3 Task 5 deterministic iOS-harness slice is strict-TDD
  GREEN and root-reverified, but Simulator execution remains `not run` and M3
  remains open. The initial RED failed on the absent generator. Later focused
  REDs caught a four-run response-file collision, the wrong compile-time model
  selector and incomplete stable-stage proof, and a tautological controlled-
  state hash check. GREEN adds a tracked generator and seven templates for an
  ignored iOS-only app, hard-pins state SHA-256
  `7cb8850b3dfad0cf891e8e0190e51b2770d6d00ba349ff0e9a76d44821873a71`,
  preserves exact model/HDR/root/pin bytes, exposes the exact `27`-stage
  inventory, records model-scoped responses, and proves applied pass lighting,
  stable stats, installed sheen fields/textures/transforms, no extra runtime
  sheen, combined selection, and generic distinct ToyCar extension roles. The
  app depends only on the root package path; it has no direct `flutter_scene`
  dependency/import or override. Offline resolution retained exact transitive
  pin `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Root focused tests passed
  `4/4`, output validation passed `27` stages, and generated-app
  `flutter analyze --no-pub` was clean. Flutter GPU rendering, screenshots,
  comparison, and physical targets remain `not run`; maturity remains
  `candidate-only`.

- 2026-07-21: The M3 Task 5 pinned-Three.js capture slice is strict-TDD
  GREEN and root-reverified, but M3 remains open. The initial RED failed on
  the absent render module, later focused REDs exposed default-scene material
  scope, removal instead of intensity-zeroing for the frozen HDR/key-light
  resources, and cleanup that could skip server/profile teardown after a
  browser-close failure. GREEN keeps authored, loaded-dependency, and
  default-scene-used sheen indices separate; keeps the exact HDR and key light
  configured with environment intensities `0/1/1` and key intensities
  `3/0/3`; and attempts every cleanup action. The final isolated-browser run
  passed `3/3` and wrote exactly `27/27` valid `1206 x 2622` PNGs: six each
  for SheenChair, SheenCloth, and GlamVelvetSofa plus nine for ToyCar across
  close, grazing, and full-scene context views. All captures were inspected;
  framing remained accepted, and process/profile checks were empty. This is
  pinned Three.js reference direction/conformance evidence, `verified
  locally`. Flutter/iOS capture, cross-renderer comparison, physical targets,
  pixel parity, renderer-native sheen, release, and production readiness
  remain `not run` or unestablished.

- 2026-07-21: The M3 Task 5 fixed-state and loader-consumption slice is
  strict-TDD GREEN and root-reverified, but M3 remains open. The behavioral
  RED failed with `ERR_MODULE_NOT_FOUND` before the Plan 018 contract or state
  existed. GREEN freezes exact four-model bytes and licenses, the separately
  labeled SheenCloth container, whole/sheened bounds, explicit close/grazing
  cameras, a ToyCar full-scene context camera, the reused HDR/light/pass and
  complete mirror-Z state, package camera/adapter hashes, and exact
  `three@0.167.1` lock/source hashes. A real isolated-browser `GLTFLoader`
  audit loaded all nine authored sheen materials and consumed factor, color
  texture, roughness factor, and roughness texture; SheenCloth retained its
  shared source with distinct RGB+sRGB and alpha+linear roles. The root
  rerun first reproduced the managed-sandbox `listen EPERM`, then the approved
  local-only run passed `2/2`; no Plan 018 browser process or temporary profile
  remained. This is fixed-state and importer direction/conformance evidence
  only. Reference images, Flutter loading/rendering, Simulator evidence, and
  comparison remain `not run`; maturity remains `candidate-only`.

- 2026-07-21: The first M3 Task 5 fixture-provenance slice is strict-TDD
  GREEN, but M3 remains open. The focused RED failed because
  `plan018SheenCorpus` was absent; GREEN adds a separate four-fixture corpus
  without changing the historical six-fixture provenance list. A second RED
  proved four path-traversal mutations were accepted; GREEN requires safe
  relative POSIX source, license, staging, and derived-output paths. The
  complete provenance file passed `5/5`, metadata verification passed
  historical `6` + Plan 015 `3` + Plan 018 `4`, and root local-source staging
  passed all four fixtures. The official SheenCloth seven-file source is
  preserved and deterministically packaged as a separately labeled derived
  GLB of `4,176,696` bytes with SHA-256
  `bab89a56fe44396877f35fc794222b54f2107ba273634c6514c2a910cab61588`.
  This proves source/license/container identity only. Three.js and Flutter
  loader consumption, rendering, comparison captures, and target evidence
  remain `not run`; maturity remains `candidate-only`.
- 2026-07-21: M3 Task 5 began with a read-only audit of the retained Plan
  015/016 capture machinery and the four required fixture names. The exact
  Three.js pin remains `three@0.167.1`; the prior fixed HDR, three lighting
  passes, PBR Neutral, sRGB, and isolated Puppeteer-profile patterns are
  reusable. Primary-source verification at Khronos Sample Assets commit
  `2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf` found official GLBs for
  `SheenChair`, `GlamVelvetSofa`, and `ToyCar`, but no official SheenCloth GLB.
  SheenCloth exists only as a hash-pinned multi-file glTF source and is the
  corpus member that authors both sheen textures. The first strict TDD slice
  therefore covers immutable provenance, ignored-output staging, and a
  separately labeled deterministic GLB container that preserves the official
  source bytes and semantics. Three.js loading/capture, Flutter loading/GPU
  rendering, Simulator evidence, comparison, and all other targets remain
  `not run`; maturity remains `candidate-only`.
- 2026-07-21: M2 closed at the local host/source package-candidate boundary.
  The focused follow-up rereview returned `APPROVED` with no Critical,
  Important, or Minor findings. The owning aggregate added
  `viewer_controller_load_test.dart` to the historical seven-file M2 set and
  passed `260` tests with `5` explicit GPU-gated `not run` skips. Task 4 and
  the two M2 acceptance items are checked. Capability remains
  `candidate-only`; GPU rendering, physical iOS, Android, Web, controlled
  Three.js/ToyCar evidence, renderer-native sheen, release, and production
  readiness remain unestablished. M3 may now begin.
- 2026-07-21: Both focused-rereview follow-ups now have strict RED/GREEN
  remediations pending another independent rereview. Selected combined-shader
  failure remains request-scoped and no longer stops a valid sheen-only
  sibling; shared LUT/backend/preflight-unavailable failures remain global.
  Request-scoped diagnostics now carry loader-owned structured
  `PartAddress.toJson()` identity, while `part` is display-only. Controller
  suppression compares structural identity and fails closed for colliding
  display paths, malformed structured data, and display-only addressed
  diagnostics; only absence of both address fields is global. Root final
  checks passed loader `4/4`, controller `5/5`, and the complete narrow source
  set `23/23`. M2 remains open pending clean rereview; Three.js/ToyCar M3
  remains `not run`.
- 2026-07-21: The focused independent M2 rereview returned
  `CHANGES_REQUESTED` with no Critical or Minor findings and two Important
  follow-ups. First, `PartAddress.debugPath` is a non-injective display string
  and cannot prove exact suppression identity. Second, a selected combined
  shader failure does not prove the sheen-only shader is unavailable, so
  shader unavailable/contract diagnostics cannot be asset-global without an
  aggregate probe. Strict focused collision and mixed-variant RED/GREEN slices
  plus another rereview are required. M2 remains open; M3 Three.js/ToyCar
  evidence remains `not run`.
- 2026-07-21: All four fresh M2 review findings now have strict focused
  remediations pending independent rereview. The final address-scoped slice
  proved RED that one optional material incompatibility stopped sibling
  preflight and suppressed both controller groups; a separate RED proved a
  global LUT failure leaked the first material address. GREEN preflights valid
  siblings, retains the exact failing `part`, keeps global shader/LUT failure
  singular and addressless, and suppresses only the matching authored sheen
  group. Post-format loader/controller checks passed `5/5` and `2/2`; the final
  narrow four-finding matrix passed `21/21`. The broad `232` set remains the
  historical pre-review source freeze and has not been repeated. M2 remains
  open until focused rereview is clean and the owning closure gate runs.
- 2026-07-21: Review remediation paused at a safe handoff boundary for a new
  Codex task. Three Important findings are focused GREEN: outward sheen remains
  `packageLocalCandidate` while unrelated no-sheen native clearcoat/glass uses
  an internal sheen-stripped routing capability; same-delta
  sheen+clearcoat+transmission/volume reaches the selected combined typed
  preflight before decode/mutation; and both sheen variants now use perturbed
  base-normal `VdotN` for directional albedo while clearcoat keeps its separate
  geometric normal. Post-format focused results are `2/2`, `1/1`, and `1/1`.
  Address-scoped authored sheen diagnostic suppression is the one remaining
  review finding and has no RED or implementation yet. The broad `232` set was
  deliberately not repeated; M2 rereview has not run.
- 2026-07-21: The fresh independent M2 review returned
  `CHANGES_REQUESTED` with four Important findings and no Blocker findings:
  mixed capability could disable unrelated no-sheen native routes; same-delta
  glass state could bypass combined typed preflight; one authored
  request-specific failure could suppress valid sibling sheen; and sheen
  directional-albedo `VdotN` used the geometric rather than perturbed base
  normal. M2 remains open while each finding receives a strict focused
  RED/GREEN remediation and rereview.
- 2026-07-21: Task 4 and the M2 package-local source set are frozen pending one
  fresh independent M2 review. Strict continuation slices added early authored
  and retained transmission/volume selected-variant diagnostics, corrected the
  authored group order, proved one shared sheen LUT across variants, and added
  `FSViewerClearcoatSheenExtendedPbr`. The combined route owns an exact
  16-resource manifest, keeps specular/IOR uniform-only, binds two sheen plus
  two clearcoat textures, retains independent transforms, and applies
  clearcoat attenuation above base, sheen, and emission. The final focused M2
  command passed `232` tests with `5` explicit GPU-gated `not run` skips.
  Physical targets and controlled render capture remain `not run`; capability
  remains `candidate-only`. Task 4/M2 checkboxes remain open until the required
  review is clean.
- 2026-07-21: The user paused M2 and requested continuation in a new Codex
  task. Task 3 is source-frozen and independently re-run by the root agent.
  Task 4 is intentionally left partial, unstaged, and unreviewed at a safe TDD
  boundary: capability underclaim, exact-16 resource selection, typed
  incompatible-resource/state diagnostics, variant-specific preflight,
  native-clearcoat routing, two clearcoat transforms, manual two-slot coat
  binding, retained coat state, uniform-only specular/IOR construction, and
  defensive construction checks are locally green. Adapter-level
  transmission/volume diagnostic wiring and authored extension-group ordering
  are the next RED slices. The combined clearcoat-above-sheen shader has not
  been created, the bundle manifest has not been extended for it, the Task 4
  source set is not frozen, and the M2 repository gates and independent review
  have not run. Physical targets and render capture remain `not run`.
- 2026-07-21: Task 3 completed at the package-local `candidate-only` boundary.
  It adds the separate `FSViewerSheenExtendedPbr` entry, real Charlie direct
  lighting, fitted visibility, energy-aware base attenuation, distinct IBL,
  explicit zero-sheen equivalence, retained texture/transform state, atomic
  request preflight, and the deterministic combined RGBA16F DFG resource. The
  default LUT SHA-256 is
  `8d87845f620fe09ba0a7ac8d540229f4642036d98cce9d1a5d2160d70f8d691f`.
  Clearcoat-above-sheen remains Task 4; renderer-native and target-render
  evidence remain absent.
- 2026-07-21: M1 / Tasks 1-2 completed at the `verified locally` wrapper and
  loader boundary. The implementation now preserves and validates all sheen
  factors and bindings, maps authored GLB intent into an independent group,
  enforces the viewer's UV0-only boundary, applies exact CPU color/channel
  semantics, and distinguishes optional fallback from required atomic
  failure. Renderer application, shader output, and target evidence remain
  `not run`.
- 2026-07-21: The M1 independent review initially found two P1 requiredness and
  mixed-material diagnostic defects plus one P2 controller duplication defect.
  RED-first remediations preserved required `KHR_texture_transform` metadata,
  restored valid-intent capability diagnostics, and scoped controller
  suppression to the exact loader-authored optional diagnostic. Independent
  re-review returned `APPROVED` with no actionable findings.
- 2026-07-21: A subsequent M2 read-only surface audit found one M1 diagnostic
  completeness gap before M2 implementation: runtime missing-UV details did
  not name the four sheen texture source/binding fields. A focused RED-first
  fix added the exhaustive field mapping; the same independent reviewer
  returned `APPROVED` with no actionable findings.
- 2026-07-21: Activated at the user's explicit selection after Plan 017 was
  returned to deferred without erasing its completed local evidence or open
  physical/runtime/release boundaries. Implementation and target evidence for
  this plan remain `not run` at activation.

- 2026-07-17: Plan 016 updated the stable renderer pin with native
  transmission/volume/IOR but did not add sheen fields. This plan remains
  deferred and its implementation/evidence items remain `not run`.
- 2026-07-16: Created as deferred at the user's direction. The plan separates
  immediate silent-drop diagnostics, a specular-like package-local candidate,
  and renderer-native release support. Current implementation and target
  evidence are `not run`.

## Verification log

- 2026-07-21: M3 closure disposition is `verified locally` at the focused
  audit/test boundary with clean final independent rereview. The targeted RED
  failed because the audit returned `m3Status: incomplete`; the targeted GREEN
  passed `1/1`, the complete runner test file passed `20/20`, bytecode-free
  Python AST parsing exited `0`, and the real read-only audit returned
  `m3Status: blocked` with a structured `m3ClosureDisposition`. Focused format,
  repo lint, and diff checks passed. The full repository gate remains
  `blocked` at the seven existing Plan 018 analyzer issues after repo lint,
  format, and dependency resolution passed. Independent review's one Important
  test-hardening finding is remediated with exact boundary assertions; two
  focused mutants separately proved the resolution and claim contracts fail
  closed, followed by targeted `1/1` and full-file `20/20` GREEN. Final
  independent rereview returned PASS with no Blocker, Important, or Minor
  findings. This is a blocker classification, not SheenChair iOS capture, not
  final four-model M3 evidence, not pixel parity, not physical target coverage,
  not renderer-native sheen, not release evidence, and not production
  readiness.

- 2026-07-21: SheenChair static blocker proof verification is
  `verified locally` for frozen-source inspection only. The focused RED for
  `sheenChairStaticBlocker` failed on the missing field; the focused GREEN
  passed. `python3 -m py_compile tools/run_plan018_ios_capture.py` exited `0`,
  `flutter test test/plan018_ios_capture_runner_test.dart` passed `20/20`,
  and the real `--audit-m3-status` against `candidate-run-08` returned
  `status: candidate-only`, `m3Status: incomplete`, `finalEvidenceStatus:
  absent`, `canStartM4: false`, and a SheenChair static blocker with
  `blockerEvidence: verified locally`, material `0`, `occlusionTexture`
  `texCoord: 1`, texture-transform `texCoord: 1`, and no UV invention or
  channel reinterpretation. `dart format --output=none --set-exit-if-changed
  test/plan018_ios_capture_runner_test.dart`, `python3 tools/repo_lint.py`,
  and `git diff --check` exited `0`. The initial sandboxed Dart format-check
  failed because the Flutter SDK cache is outside the workspace, then the same
  format-check passed with approved SDK-cache access. The review found no
  Blocker and one Important stale-log finding; the matching plan/progress log
  update addresses it. Final read-only rereview returned no Blocker,
  Important, or Minor findings. This is not SheenChair iOS capture evidence,
  not final four-model M3 evidence, not pixel parity, not physical target
  coverage, not renderer-native sheen, not release evidence, and not
  production readiness.

- 2026-07-21: Continuation verification confirmed `HEAD` and `origin/main` at
  `af0568c11126904bbcfae72338ba51fb313cc9e9`, branch `main`, and an empty
  index. `node --check
  tools/reference_renderers/khronos_sample_viewer_fixture/render_plan018_toycar_controlled_comparison.mjs`
  exited `0`; `node --check
  tools/reference_renderers/khronos_sample_viewer_fixture/render_plan018_toycar_controlled_comparison.test.mjs`
  exited `0`. The focused browser command was later rerun with local-only
  HTTP/headless-Chrome access and passed `1/1`. The retained evidence JSON
  validates with nine captures; evidence SHA-256 is
  `db8213802cdffb0dcbf7a843843c2aad9eb541e294686f276a8b3d7410cc2abb`.
  `python3 tools/repo_lint.py` and `git diff --check` exited `0`. The fresh
  independent read-only review returned PASS with no Blocker or Important
  findings and two Minor wording/doc notes; this entry resolves the stale
  blocked wording. Khronos evidence is still direction/conformance-only and
  does not establish pixel parity, physical correctness, viewer
  `rendererNative` sheen capability, release, or production readiness.

- 2026-07-21: The ToyCar difference diagnosis inspected the accepted nine
  Three/Flutter pairs at original detail, the package and pinned Three shader
  sources, current Khronos Sample Renderer direct/IBL/LUT sources, the
  ratified non-normative implementation notes, Filament's gltfio sheen path,
  Apple public material surfaces, and eight official Khronos Render Fidelity
  ToyCar thumbnails. The current official Sample Viewer thumbnail is
  `512 x 213`, SHA-256
  `24d954ed66ba7b92f5b7acfe71bbbbc72e2d9e7ddca0ee3ee807e4037cda7fdf`.
  Numeric package-LUT and fitted-visibility scans are recorded as diagnostics,
  not Khronos pixel values or surface-weighted ToyCar measurements. The exact
  same-state Khronos run, physical targets, and attenuation/clamp/normal-map
  A/Bs remain `not run`; no source, fixture, dependency, pin, override,
  pub-cache, accepted artifact, Git, or external-write action was performed.
  The diagnosis report SHA-256 is
  `5c582f72ecf029ea201a96769d3bf006719643b4cf5ad303ece1ed94310394a6`.

- 2026-07-21: The final blocked-audit probe ran outside the sandbox with the
  reviewed 10-second read-only boundary and exited `124` without output. No
  capture/install/query child remained and no fresh run root was created. The
  three-turn recurrence threshold is met, so the active goal is `blocked`
  awaiting user authority or an external Simulator recovery; it is not
  complete. All Plan018 target-render and cross-renderer evidence boundaries
  remain literal.

- 2026-07-21: Follow-up diagnosis used only bounded/read-only device,
  container, log, crash-report, and process inspection. Device listing exited
  `0`; the app-container query exited `124` after 10 seconds. The target
  MobileInstallation logs contain no current Plan018 operation. All 19
  `installcoordinationd` reports match the target UDID coalition and exact
  SIGTRAP/memory-pressure-init signature; three representative SHA-256 values
  are recorded in the Slice 5B Attempt 1 report. No live
  install coordinator or capture/install/query child remained. No source,
  target, service, or lifecycle state was changed. Flutter/iOS evidence is
  still `not verified`, cross-renderer comparison is still `not run`, and M3
  remains open.

- 2026-07-21: Live M3 Slice 5B Attempt 1 passed the reviewed runner's plan and
  preflight guards, then failed before app launch. The retained failed manifest
  records `CaptureTimeoutError`, `1800.0` seconds, and exact termination/reap
  evidence; its SHA-256 is
  `55138dbeb8019e8ef1d240fc8e746c166e5d6a95bfb6f4a52135af76225090c1`.
  The 804-byte partial log SHA-256 is
  `a0cd66e815eab2e77f731e2bc48fae36c8fd8b1f72c54c08dff9e2869ff8d57b`.
  It contains no READY/COMPLETE marker, and the retained run root contains no
  PNG. The postflight guard passed with HEAD/origin, root dependency bytes,
  exact transitive pin/clean pub-cache, source hashes, and Three evidence
  unchanged. A bounded outside-sandbox container query subsequently exited
  `124` without output. No retry or lifecycle action was run. Flutter/iOS and
  cross-renderer output remain `not verified` / `not run`; M3 remains open.

- 2026-07-21: M3 pre-capture recorder verification is `verified locally` for
  source/fixture behavior only. Root and the independent rereviewer each ran
  `flutter test test/plan018_ios_capture_runner_test.dart` at `14/14`;
  `python3 tools/repo_lint.py` and `git diff --check` passed. The final review
  returned `APPROVED` with no Blocker, Important, or Minor findings after the
  timeout and READY-grounding remediations. Exact hashes and review boundaries
  are recorded in
  `.superpowers/sdd/plan018-m3-task5-slice5a-review.md`. No live `simctl`,
  Flutter device discovery, `flutter drive`, iOS app launch, or screenshot
  capture was run.

- 2026-07-21: Current pinned-Three.js evidence is `verified locally`. Root
  reran the capture contract at `3/3`, exact `27/27`, ToyCar `9/9`, then
  retained the historical-to-current health RED `8/9` and independently
  reran the current health contract at `9/9`. The health baseline records 27
  frames, nine pass triplets, zero capture-source drift, and no cross-renderer
  pixel threshold. All 27 frames were inspected; no browser/profile process
  remained. Flutter/iOS and cross-renderer comparison remain `not run`.

- 2026-07-21: Focused iOS-harness remediation rereview returned `APPROVED`
  with no Blocker, Important, or Minor finding. Root and reviewer each passed
  the eight-test generator suite; explicit resolved-output validation passed
  27 stages; generated `flutter analyze --no-pub` was clean. Exact hashes and
  boundaries are recorded in the Slice 4 remediation and rereview reports.
  No Simulator or Flutter GPU capture was run.

- 2026-07-21: M3 Task 5 deterministic iOS-harness verification is `verified
  locally` for generation, offline dependency resolution, contract tests, and
  source analysis only. Root independently reran the focused generator suite
  at `4/4`, validated the current generated output at `27` stages, and ran
  `flutter analyze --no-pub` with no issues. Root `pubspec.yaml` and
  `pubspec.lock` remain SHA-256 `dea2bde0...` and `58a4fe06...`; the generated
  lock is `1fb0c444...`; the exact pub-cache checkout remains clean at
  `5dcf6fce...`; and `git diff --check` passed. Exact source/generated hashes
  and RED/GREEN evidence are in
  `.superpowers/sdd/plan018-m3-task5-slice4-report.md`. No Simulator app was
  installed or run and no Flutter screenshot was captured in this slice.

- 2026-07-21: M3 Task 5 pinned-Three.js capture verification is `verified
  locally`. Root reran `npm run test:plan018-capture`: inventory `1/1`, actual
  browser capture/evidence `1/1`, cleanup mutation `1/1`; the run reported
  SheenChair `6`, SheenCloth `6`, GlamVelvetSofa `6`, and ToyCar `9`, for
  `27/27` exact PNGs. Every capture records the frozen camera, configured
  HDR/key resources, pass intensities, stock loaded material state, renderer
  facts, dimensions, bytes, and SHA-256. The current render module, test, and
  evidence hashes are recorded in
  `.superpowers/sdd/plan018-m3-task5-slice3-report.md`. The two images changed
  by the same-state intensity correction were reopened at original resolution;
  no camera change was needed. Post-run process and temporary-profile checks
  were empty, and `git diff --check` passed. Flutter/iOS and cross-renderer
  comparison remain `not run`; M3 remains open.

- 2026-07-21: M3 Task 5 fixed-state/loader verification is `verified locally`.
  `npm run test:plan018-controlled` passed `2/2` after an approved local-only
  rerun; the unapproved managed-sandbox attempt had passed the state case and
  failed only at `listen EPERM 127.0.0.1`. The ignored loader audit records
  exact Three revision `167`, WebGL 2 / ANGLE Metal runtime facts, all four
  models, all nine authored sheen materials, all four collective input fields,
  recomputed bounds, and state SHA-256
  `7cb8850b3dfad0cf891e8e0190e51b2770d6d00ba349ff0e9a76d44821873a71`.
  `git diff --check` passed; temporary profile and process checks were empty.
  No pixel was rendered in this slice, so Three.js reference captures,
  Flutter GPU output, iOS Simulator, and all physical targets remain `not run`.

- 2026-07-21: Final focused rereview: `APPROVED`, with no Critical,
  Important, or Minor findings. The owning eight-file M2 Flutter command
  exited `0` with `260` passed and `5` explicit GPU-gated skips. Those skips
  remain literal `not run`; the result is not target-render evidence. The
  exact command is recorded in `.superpowers/sdd/plan018-m2-rereview.md` and
  `.superpowers/sdd/plan018-m2-task4-report.md`.
- 2026-07-21: Focused rereview-follow-up REDs reproduced selected-variant
  over-globalization, missing structured loader identity, colliding display
  path suppression, malformed/display-only ambiguity, and addressless
  request-failure over-globalization. Final root post-format runs passed loader
  `4/4` and controller `5/5`. The complete current narrow remediation matrix
  passed adapter `7/7`, shader source/reflection `6/6`, backend `1/1`, loader
  `4/4`, and controller `5/5` (`23/23`). Updated production hashes are recorded
  in `.superpowers/sdd/plan018-m2-task4-report.md`. Independent rereview and
  the owning broad M2 closure gate remain `not run`.
- 2026-07-21: The fresh focused rereviewer inspected the exact dirty diff,
  confirmed the frozen source hashes and stable pin, and ran
  `git diff --check`. It ran no tests and made no edits. Verdict:
  `CHANGES_REQUESTED` for structured exact-address identity and
  selected-variant shader failure scope. Full details are in
  `.superpowers/sdd/plan018-m2-rereview.md`. The previous `21/21` focused
  matrix remains implementation evidence, not approval.
- 2026-07-21: Final address-scoped remediation evidence is `verified locally`
  at the focused host-test boundary. Loader REDs reproduced a skipped valid
  sibling and an addressed global LUT failure; controller RED reproduced both
  sibling groups being suppressed. Post-format root reruns passed loader
  `5/5` and controller `2/2`. The complete narrow remediation matrix passed
  adapter `7/7`, shader source/reflection `6/6`, backend state `1/1`, loader
  `5/5`, and controller `2/2` (`21/21`). Current post-remediation source hashes
  are recorded in `.superpowers/sdd/plan018-m2-task4-report.md`. Independent
  rereview and the owning broad M2 closure gate remain `not run`.
- 2026-07-21: Review-remediation RED/GREEN evidence: ready mixed capability
  initially rejected a no-sheen native clearcoat patch, then the new native
  clearcoat/glass regression passed `1/1`; same-delta combined glass initially
  returned `extendedPbrLayeredMaterialCombinationUnsupported`, then its typed
  selected-variant regression passed `1/1`; sheen directional albedo initially
  used geometric `n_dot_v_energy`, then its two-shader perturbed-normal contract
  passed `1/1`. Adjacent runs passed `ready sheen` `2/2`, disabled sheen `1/1`,
  native-clearcoat/local-sheen `1/1`, retained glass `1/1`, legacy no-sheen
  glass `1/1`, and fragment contracts `5/5`. After formatting, the three
  handoff checks passed `2/2`, `1/1`, and `1/1`. No broad suite or rereview is
  claimed for this in-progress remediation state.
- 2026-07-21: The Task 4 focused matrix passed `18/18`. The first M2 aggregate
  run exposed two no-sheen native-clearcoat regressions; a narrow correction
  restored native clearcoat routing independently of sheen, after which the
  two failures passed `2/2` and four adjacent regressions passed `4/4`. The
  final source-freeze command passed `232` tests with `5` explicit GPU-gated
  `not run` skips. Seven Task 4 Dart files were format-clean,
  `python3 tools/repo_lint.py` passed, and `git diff --check` exited `0`.
  Shader build/reflection names were verified through the Flutter test build
  hook and generated ignored bundle. Exact RED/GREEN evidence, formulas,
  hashes, and boundaries are in
  `.superpowers/sdd/plan018-m2-task4-report.md`.
- 2026-07-21: `python3 tools/generate_capability_matrix.py --check` is
  `blocked` by an unrelated baseline mismatch: the unchanged Plan 017 Draco
  request-registry source hashes to `46931fdb...`, while the generator expects
  stale fingerprint `30dfc6df...`. `bash tools/run_checks.sh`, controlled M3
  captures, and physical targets remain `not run`; no renderer-native,
  release, or production-ready claim is made.
- 2026-07-21: At the Task 3 source freeze, the focused seven-file M2 subset
  passed `214` tests with `5` explicit GPU-gated `not run` skips. The root
  agent independently repeated the same command with the same `214/5` result.
  Fourteen Task 3 Dart files were format-clean and the scoped
  `git diff --check` passed. Exact RED/GREEN commands, reflected slots, hashes,
  and boundaries are recorded in
  `.superpowers/sdd/plan018-m2-task3-report.md`.
- 2026-07-21: The pause boundary has a clean whole-worktree
  `git diff --check`. No Task 4 aggregate test result is claimed because the
  task was interrupted before its next adapter RED and before source freeze.
  `python3 tools/repo_lint.py`, the full M2 focused set, shader/generator gates,
  independent M2 review, `bash tools/run_checks.sh`, and physical targets have
  not been run for this partial Task 4 state.
- 2026-07-21: M1 source freeze is `verified locally`: the focused M1 command
  passed `168` tests with the same `3` pre-existing GPU-gated skips; the
  explicit texture-slot routing regression passed `1` test. The review-fix
  doubt set passed `8/8` reader/loader tests and `3/3` controller tests, with
  the exact controller case also passing `1/1`; no review test was skipped.
  Evidence is recorded in `.superpowers/sdd/plan018-m1-report.md` and
  `.superpowers/sdd/plan018-m1-review.md`.
- 2026-07-21: M1 closure intentionally did not run `bash tools/run_checks.sh`,
  shader/GPU evidence, or physical iOS, Android, and Web targets. Those gates
  belong to later milestones or final source freeze. M1 therefore makes no
  package-local candidate, renderer-native, release, or production-ready
  claim.
- 2026-07-21: After the M1 plan and SDD logs were updated,
  `python3 tools/repo_lint.py` passed and `git diff --check` exited `0` with no
  output.
- 2026-07-21: The post-review completeness test
  `supported sheen texture diagnostics name only requested fields` passed
  `1/1` with `0` skips and proves exact singleton field details, no adapter
  mutation, and no persistence for all four sheen source/binding cases. The
  focused independent re-review reran the same test and approved the fix. The
  `168`-test M1 set was deliberately not repeated for this narrow change.
- 2026-07-16: Planning baseline verified against the stable viewer pin,
  current wrapper extension vocabulary, active Plan 015, deferred Plan 016,
  the official Khronos extension registry, and the ratified sheen
  specification. No implementation tests were run because this change creates
  the deferred plan and supporting documentation only.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The full
  `bash tools/run_checks.sh` reaches `flutter analyze` and remains `blocked` by
  the already-recorded Plan 015 stable-pin boundary: the checked-in
  `cd6760912fa38beb55f63e388655a1aeabd32fe4` dependency lacks the unpublished
  clearcoat fields used by the active working tree, producing the same 81
  missing-contract issues. Plan 018 changes documentation only and introduces
  no additional Dart analysis failure.
