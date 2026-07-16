# KHR_materials_sheen Diagnostic, Candidate, and Renderer-Native Plan

> **Status (2026-07-16): deferred.** Plan 015 is complete and no successor is
> active. This plan records the user-approved sheen follow-up without treating
> the current silent fallback as support; activation still requires the user
> to select Plan 018 explicitly.

## Goal

Add a complete `KHR_materials_sheen` contract to the viewer, first as an honest
diagnostic and package-local evaluation path comparable to the existing
`FSViewerExtendedPbr` specular path, then promote it to release capability only
after the pinned `flutter_scene` importer and renderer own the full direct-light
and IBL behavior.

The implementation must render a distinct cloth/fiber sheen lobe. It must not
imitate sheen by changing base color, lowering material roughness, increasing
environment intensity, or adding an unrelated rim-light term.

## Source-backed baseline

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
- The stable viewer dependency remains `flutter_scene` revision
  `ccf7372428961ebe0abb053727fe443150547a74`. Its material model, glTF
  importer, standard PBR shader, and DFG lookup expose native clearcoat but do
  not expose sheen.
- The current viewer has no sheen fields in `MaterialPatch`, no
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

Normative and implementation references, accessed 2026-07-16:

- [Khronos glTF extension registry](https://github.com/KhronosGroup/glTF/blob/main/extensions/README.md)
- [KHR_materials_sheen](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_materials_sheen/README.md)
- [Khronos glTF Sample Assets](https://github.com/KhronosGroup/glTF-Sample-Assets)
- [Filament cloth model](https://google.github.io/filament/main/filament.html#material-system/clothmodel)
- [Filament material sheen examples](https://google.github.io/filament/main/materials.html#materialsystem/standardmodel/sheencolor)
- [Three.js r167 GLTFLoader](https://github.com/mrdoob/three.js/blob/r167/examples/jsm/loaders/GLTFLoader.js)

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

## Tasks

### Task 1: Freeze RED contracts and silent-drop diagnostics

- [ ] Add failing tests for authored optional and required
  `KHR_materials_sheen`, malformed extension objects, invalid factor ranges,
  invalid vector lengths, missing UV0, unsupported UV sets, and invalid
  unlit/specular-glossiness combinations.
- [ ] Require an optional unsupported sheen material to use only its valid core
  fallback while emitting a typed, non-blocking capability diagnostic.
- [ ] Require unsupported sheen listed in `extensionsRequired` to block
  publication atomically with the original bytes and live model state
  unchanged.
- [ ] Add capability tests proving that absent shader/importer fields never
  advertise sheen availability.

### Task 2: Add the wrapper contract and authored GLB mapping

- [ ] Add sheen fields, bindings, merge/reset, equality, JSON round-trip,
  validation, and empty/feature classification to `MaterialPatch`.
- [ ] Parse factors and embedded-GLB textures into an independent sheen patch
  group so invalid sheen cannot discard valid specular, clearcoat, or core
  intent on the same material.
- [ ] Preserve sampler and `KHR_texture_transform` metadata. Apply only authored
  UV0; diagnose UV1+ instead of substituting coordinates or generating UVs.
- [ ] Decode sheen color as sRGB RGB and sheen roughness as linear alpha. Prove
  factor/sample multiplication and default behavior with CPU tests.
- [ ] Add `MaterialExtensionFeature.sheen` and keep default capability
  diagnostic-only until an attached backend consumes every requested field.

### Task 3: Implement the package-local sheen candidate

- [ ] Add RED shader/material tests for factor zero, saturated colors,
  independent roughness, grazing-angle movement, direct-only, IBL-only, and
  combined lighting.
- [ ] Implement a Charlie/Conty-Kulla-style sheen lobe with energy-aware base
  attenuation. Do not map sheen onto ordinary GGX specular or base roughness.
- [ ] Select and document a package-local sheen IBL and directional-albedo
  strategy. Any approximation must remain explicitly `candidate-only` and must
  preserve the zero-sheen native-equivalent path.
- [ ] Bind the two sheen textures and uniforms atomically. Preflight every
  reflected slot, sampler, shader bundle, and backend resource limit before
  replacing a live material.
- [ ] Keep all requested data and the live material unchanged if texture load,
  shader load, reflection, material construction, or resource preflight fails.

### Task 4: Compose sheen with existing material features

- [ ] Prove combined core textures, normal map, UV transforms, specular, opaque
  IOR, sheen, and clearcoat do not create multiple competing base materials or
  lose retained extension state.
- [ ] Apply clearcoat above sheen. Verify that clearcoat attenuation affects
  the composed base-plus-sheen response rather than leaving an unattenuated
  sheen highlight above the coat.
- [ ] Cover double-sided orientation, alpha/mask behavior, emission layering,
  shadows, fog, reset, persistence, repeated deltas, and render scheduling.
- [ ] Prove no-sheen materials retain the existing native or extended path
  without a visual or resource regression.

### Task 5: Produce controlled candidate evidence

- [ ] Stage hash-pinned Khronos `SheenChair`, `SheenCloth`,
  `GlamVelvetSofa`, and `ToyCar` fixtures with license/provenance records.
- [ ] Freeze one comparison-state schema covering canonical bounds/camera,
  coordinate transforms, HDRI bytes and orientation, directional light,
  direct/IBL/combined passes, exposure, tone mapping, output color space,
  viewport, and renderer revisions.
- [ ] Compare against Three.js and, where practical, Khronos Sample Viewer.
  Treat the reference as direction/conformance evidence, not pixel-parity.
- [ ] Add a Three.js contract test that fails unless the pinned loader consumes
  factor, color texture, roughness, and roughness texture before capture.
- [ ] Record close and grazing views that distinguish sheen from base roughness
  and ordinary specular. ToyCar must show the red fabric sheen independently
  from body clearcoat and glass transmission.
- [ ] Record exact capture hashes, commands, diagnostics, target/backend, and
  pass criteria. Initial iOS Simulator output may be `verified locally` while
  maturity remains `candidate-only`; other targets remain `not run`.

### Task 6: Promote to renderer-native sheen

- [ ] Add first-class sheen fields, texture slots, UV metadata, importer
  mapping, copying, and serialization to a separate `flutter_scene` checkout.
- [ ] Extend renderer-owned PBR lighting with direct and IBL sheen plus the
  reviewed base-energy scaling. Extend or replace the DFG/prefilter contract
  with tests proving the data is real and sampled with the correct axes.
- [ ] Exercise every renderer-supported direct-light kind through the shared
  standard path; absence of imported point/spot light support remains a
  separate capability and must not be hidden inside sheen.
- [ ] Run upstream unit, shader, native, and WebGL2 tests. Produce a concrete
  upstream commit, then update the viewer pin only after publication is
  authorized and the commit is externally reachable.
- [ ] Advertise `rendererNative` sheen only when the pinned importer, material,
  shader, IBL data, and all requested texture fields are present. Preserve
  `candidate-only` or diagnostic-only labels otherwise.

### Task 7: Close docs and capability evidence

- [ ] Add per-target sheen rows to the generated capability matrix and keep
  application, visual verification, runtime availability, maturity, and target
  evidence separate.
- [ ] Update public API, material/lighting, runtime pipeline, renderer notes,
  fixture provenance, and platform-evidence documents.
- [ ] Run focused tests, upstream tests, `bash tools/run_checks.sh`,
  `python3 tools/repo_lint.py`, `git diff --check`, and each claimed target or
  package build.
- [ ] Move this plan to completed only when every checked acceptance criterion
  has matching evidence and all remaining target/release boundaries are
  explicit.

## Acceptance criteria

- [ ] No authored or runtime sheen request is silently dropped; optional and
  required extension behavior is typed and atomic.
- [ ] Factor defaults/ranges, color RGB+sRGB handling, roughness alpha+linear
  handling, multiplication, samplers, UV0 transforms, and unsupported UV sets
  match Khronos semantics.
- [ ] Direct-only and IBL-only tests show a distinct grazing cloth lobe with
  energy-aware base attenuation and no base-roughness/environment hack.
- [ ] Combined specular/IOR/sheen/clearcoat materials preserve one coherent
  layering order, with clearcoat above sheen.
- [ ] Package-local evidence is labeled `candidate-only`; no target is
  `production-ready` without a reachable pinned renderer-native revision,
  matching runtime/packaging evidence, and all applicable release gates.
- [ ] The fixed-state Khronos/Three.js corpus is durable and hash-recorded for
  every claimed target; physical iOS, Android, and Web remain `not run` until
  actually exercised.

## Adjacent material-extension inventory

These are not part of Plan 018. The inventory prevents sheen work from being
mistaken for full modern-glTF material coverage.

| Extension or capability | Current viewer status | Product relevance | Recommended disposition |
| --- | --- | --- | --- |
| `KHR_materials_anisotropy` | absent | brushed metal, machined finishes, carbon fiber, directional highlights | [Plan 022](022_khr_materials_anisotropy.md): renderer-native tangent, direct, and IBL work after Plan 019. |
| `KHR_materials_iridescence` | absent | thin-film coatings, automotive paint, coated glass/plastic | [Plan 023](023_khr_materials_iridescence.md): renderer-native thin-film response and composition. |
| `KHR_materials_emissive_strength` | absent | LEDs, displays, lamps, bright emissive product accents | [Plan 021](021_khr_materials_emissive_strength.md): HDR emission, exposure, tone mapping, and independent bloom evidence. |
| `KHR_materials_dispersion` | absent | wavelength-separated refractive glass/gems | [Plan 025](025_khr_materials_dispersion.md), blocked by Plan 016 native transmission/volume. |
| `KHR_materials_variants` | absent | named product color/material configurations | [Plan 020](020_khr_materials_variants.md): atomic source-material selection and persistence, no BRDF. |
| `KHR_materials_diffuse_transmission` | absent; Khronos release candidate | thin translucent cloth, paper, leaves | [Plan 024](024_khr_materials_diffuse_transmission.md): spec-gated feasibility, diagnostics, then native BTDF. |
| `KHR_materials_subsurface` | absent; Khronos initial draft | skin, wax, thick scattering materials | [Plan 026](026_khr_materials_subsurface.md): research-only until explicit promotion gates pass. |
| `KHR_materials_pbrSpecularGlossiness` | absent; archived | compatibility with older assets | [Plan 027](027_khr_materials_pbr_specular_glossiness_compatibility.md): bounded legacy conversion/fallback only. |
| `KHR_materials_unlit` | imported by pinned `flutter_scene` and surfaced as lit/unlit state | labels, UI-like meshes, baked-looking assets | Not a missing material lobe; retain tests and improve any remaining alpha-mask limitations separately. |
| `KHR_materials_transmission` / `KHR_materials_volume` | package-local candidate; native work deferred to Plan 016 | glass and transparent product parts | Continue Plan 016; do not describe the current candidate as production-ready. |
| `KHR_materials_clearcoat` | renderer-native published implementation; stable pin `release pending` in completed Plan 015 | automotive/product coatings | Completed prerequisite. |
| `KHR_materials_specular` / opaque `KHR_materials_ior` | package-local `candidate-only`; iOS Simulator `verified locally` | dielectric reflectance and material matching | Preserve existing Plan 014 labels; physical iOS, Android, and Web remain `not run`. |
| `KHR_lights_punctual` | imported playback absent; viewer has one directional studio key | point/spot/directional authored-light parity | [Plan 019](019_khr_lights_punctual.md): shared standard-material direct-light loop for every lobe. |

## Progress log

- 2026-07-16: Created as deferred at the user's direction. The plan separates
  immediate silent-drop diagnostics, a specular-like package-local candidate,
  and renderer-native release support. Current implementation and target
  evidence are `not run`.

## Verification log

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
