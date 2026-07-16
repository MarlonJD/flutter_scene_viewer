# Modern glTF Extension Sequence Design

**Status:** User-approved on 2026-07-16. Individual deferred Plans 019-027 were
created from this design. Plan 015 subsequently completed; no successor plan is
activated until the user explicitly starts it.

## Purpose

Define the ownership, dependency order, maturity gates, and evidence model for
nine deferred follow-ups after Plan 018. Each follow-up must stay independently
reviewable and testable. The sequence must not turn `flutter_scene_viewer` into
a replacement renderer or imply that parsing an extension proves rendered
support.

## Chosen approach

Create one deferred exec plan per independent capability:

1. Plan 019 — `KHR_lights_punctual`;
2. Plan 020 — `KHR_materials_variants`;
3. Plan 021 — `KHR_materials_emissive_strength`;
4. Plan 022 — `KHR_materials_anisotropy`;
5. Plan 023 — `KHR_materials_iridescence`;
6. Plan 024 — `KHR_materials_diffuse_transmission`;
7. Plan 025 — `KHR_materials_dispersion`;
8. Plan 026 — `KHR_materials_subsurface`;
9. Plan 027 — archived `KHR_materials_pbrSpecularGlossiness` compatibility.

The plans are stored in `docs/exec-plans/deferred/`. Plan 015 is complete and
no successor is active. Creating these documents did not authorize
implementation, branch changes, commits, publication, dependency-pin changes,
or remote writes.

## Alternatives considered

### One umbrella implementation plan

Rejected. Lights, asset-native variants, emissive range, surface BRDF lobes,
transmission effects, draft transport, and legacy conversion have different
owners and acceptance evidence. A single plan would make partial completion
ambiguous and encourage unsupported features to share false maturity labels.

### Only plan ratified extensions

Rejected as incomplete. Release-candidate diffuse transmission, draft
subsurface, and archived specular-glossiness still need explicit disposition so
assets cannot be silently misrepresented. Their plans will be research- or
compatibility-gated rather than treated as ordinary implementation work.

### Independent plans with shared gates

Selected. Each plan has one product capability, its own prerequisites and test
corpus, and literal evidence labels. Cross-cutting renderer and release rules
remain common so implementations cannot redefine color space, lighting, or
maturity independently.

## Activation order and dependencies

Plan numbers identify documents, not unconditional activation order. Exactly
one exec plan may be active.

1. Plan 015 is complete at its published renderer-native clearcoat revision.
   Activate the next plan only with explicit user direction.
2. Complete Plan 016 before any feature that depends on native refractive
   transport, especially dispersion. Plan 017 remains the owner of decoder,
   authored-mip, physical-target, packaging, and release-evidence closure.
3. Execute Plan 018 sheen under its diagnostic → package-local candidate →
   renderer-native gates.
4. Plan 019 adds the shared punctual direct-light foundation before new
   directional BRDF lobes are promoted.
5. Plans 020 and 021 deliver high-return product behavior with bounded renderer
   scope: asset-native variants and HDR emissive strength.
6. Plans 022 and 023 add renderer-owned anisotropy and iridescence after the
   shared direct-light and evidence paths are stable.
7. Plan 024 may advance beyond research only when the Khronos
   `KHR_materials_diffuse_transmission` contract is stable enough to freeze a
   public API and the renderer can support backside direct and indirect light.
8. Plan 025 requires completed native transmission/volume from Plan 016 before
   dispersion can render or claim evidence.
9. Plan 026 remains research-only until `KHR_materials_subsurface` is suitably
   stable, product demand exists, and renderer transport is feasible.
10. Plan 027 is last because it supports archived input compatibility, not new
    authoring or a strategic renderer capability.

## Common architecture

### Wrapper layer

`flutter_scene_viewer` owns stable glTF-oriented APIs, validation,
serialization, authored-intent preservation, part addressing, variant
selection, reset/persistence behavior, diagnostics, and per-target capability
labels. Unsupported required intent blocks atomically. Optional material intent
may use a valid core fallback only with an actionable diagnostic.

The wrapper must not expose BRDF distribution, visibility, Fresnel, spectral
sampling, LUT, probe convolution, precision, shader permutation, or render-pass
implementation choices.

### Renderer and importer layer

`flutter_scene` owns importer mappings, first-class material/light fields,
shader integration, direct-light evaluation, IBL, energy compensation,
spectral approximations, shadows, transparency/refraction compositing, tone
mapping, and backend resource limits. Production claims require an externally
reachable pinned upstream revision. Package-local full fragments may be used
only as explicitly bounded `candidate-only` evidence when the individual plan
allows it.

### Evidence layer

Every plan separates:

- intent parsed and preserved;
- runtime application;
- visual verification;
- runtime capability;
- release maturity;
- exact target evidence.

The allowed labels remain `verified locally`, `not run`, `blocked`,
`candidate-only`, `release pending`, and `production-ready`. Three.js and the
Khronos Sample Viewer are controlled references, not proof that the Flutter
renderer applied a feature.

Controlled comparisons freeze camera, model transform, HDRI bytes and
orientation, direct lights, exposure, tone mapping, output color space,
viewport, renderer revisions, fixture hashes, and direct/IBL/combined passes.

### Filament and Three.js reference policy

Filament examples and shader documentation are implementation references for
cloth/sheen, clearcoat, anisotropy, HDR emission, punctual lights,
transmission/volume, dispersion, subsurface research, variants, and legacy
specular-glossiness where its pinned gltfio version supports the feature.
Filament is not the renderer used by this package and is not glTF conformance
evidence for extensions its gltfio support list does not advertise.

The repository's existing Three.js harness resolves `three@0.167.1`. Each plan
must pin an exact Three.js revision before evidence, add a contract test proving
that GLTFLoader (or a separately pinned variants/RC plugin) consumed every
tested field, and record its shader/backend. Current Three.js supports the
ratified lights, emissive strength, anisotropy, iridescence, and dispersion
paths used here; variants require an external plugin, diffuse transmission and
subsurface have no built-in path, and specular-glossiness was removed in r147.

## Individual plan boundaries

### Plan 019 — KHR_lights_punctual

Import and expose authored directional, point, and spot lights with Khronos
color, intensity, range, cone, node-transform, and default semantics. Feed them
through one renderer-owned direct-light loop used by core PBR and every enabled
extension lobe. Preserve viewer-controlled studio lighting as a separate mode.
Area lights, IES profiles, arbitrary light editors, and authored-camera playback
are excluded.

### Plan 020 — KHR_materials_variants

Import root variant definitions and primitive material mappings. Add controller
APIs for listing, selecting, clearing, serializing, and restoring one active
asset variant atomically across affected primitives. Runtime `MaterialPatch`
overrides remain a separate layer with an explicit precedence rule: selected
variant establishes the source material, then viewer overrides apply. No new
BRDF or shader path is introduced.

### Plan 021 — KHR_materials_emissive_strength

Preserve and apply emissive strength without clamping authored HDR emission to
the core emissive-factor range. Verify interaction with emissive textures,
exposure, tone mapping, alpha, clearcoat layering, and reset/persistence.
Bloom remains a separate post-processing capability; absence of bloom must not
be confused with missing emissive-strength application.

### Plan 022 — KHR_materials_anisotropy

Add factors, direction/rotation texture semantics, tangent-frame validation,
and renderer-native anisotropic direct and IBL response. Diagnose missing
tangents or unsupported UV sets rather than synthesizing orientation data.
Texture-sampler anisotropic filtering is unrelated and must not be presented as
material anisotropy support.

### Plan 023 — KHR_materials_iridescence

Add factor, IOR, thickness range, factor texture, and thickness texture
semantics with renderer-native thin-film response for direct and environment
lighting. Compose with metallic-roughness, specular/IOR, and clearcoat without
double-counting energy. Do not substitute a view-dependent rainbow texture or
screen-space color effect.

### Plan 024 — KHR_materials_diffuse_transmission

Start with schema/status monitoring, fixture provenance, diagnostic behavior,
and renderer feasibility. Public API and persistence fields may freeze only
after the extension contract is stable enough for the plan's recorded source
revision. A renderable slice requires backside diffuse direct lighting, diffuse
environment transmission, correct alpha independence, and honest thin-surface
limits. It must not reuse ordinary alpha blend or specular transmission.

### Plan 025 — KHR_materials_dispersion

Depend on Plan 016's native transmission/volume/IOR path. Add the authored
dispersion parameter and a renderer-owned wavelength approximation with
bounded performance and resource tests. Preserve zero-dispersion equivalence
and volume/transmission requirements. RGB edge offsets or an unbounded spectral
renderer are excluded.

### Plan 026 — KHR_materials_subsurface

Remain research-gated while the Khronos extension is draft. Record schema and
fixture revisions, product use cases, transport options, performance budgets,
and unsupported diagnostics. No stable public API, renderer availability, or
production claim is permitted before the plan records a sufficiently stable
specification and an approved renderer design. Screen-space blur and emissive
color are not acceptable substitutes for subsurface transport.

### Plan 027 — KHR_materials_pbrSpecularGlossiness compatibility

Treat the archived extension as legacy input. Prefer a deterministic importer
conversion to metallic-roughness only where the conversion preserves stated
limits and produces validation evidence; otherwise retain a typed diagnostic
and valid core fallback. Do not add a new public authoring workflow or a
permanent second production BRDF family without a separate product decision.

## Error and fallback model

- Malformed extension objects produce field-specific diagnostics.
- Unsupported required intent blocks publication before live scene mutation.
- Unsupported optional material intent may retain the valid core material and
  must report the exact lost feature.
- Partial texture/shader/light construction cannot mutate the live material,
  variant selection, persisted state, or render-request count.
- Missing UVs, tangents, renderer resources, scene-color inputs, or target
  support are reported; the viewer never generates authoring data or invents a
  visual approximation.
- Reset restores the exact selected source material and extension state before
  runtime viewer overrides.

## Test and evidence strategy

Each implementation plan will require RED-first tests for schema defaults,
range validation, texture channels and color space, serialization, grouped
intent isolation, atomic failure, reset/persistence, and capability labels.
Renderer plans additionally require direct-only, IBL-only, combined-lighting,
zero-feature equivalence, composition with existing extension lobes, shader
resource limits, and selected-target captures.

Ratified features use official Khronos fixtures where available. Release-
candidate and draft plans pin the exact specification and fixture revisions
used by research. Archived compatibility uses old-format fixtures plus
round-trip/conversion error metrics. Every fixture records provenance, license,
hash, and validator disposition.

## Roadmap representation

The roadmap will add a compact ordered table linking Plans 018–027, their
prerequisites, specification maturity, and activation gate. The individual
plans will remain deferred until explicitly promoted. Plan 018's adjacent-gap
inventory will link to the newly assigned plans rather than leaving the items
as unowned recommendations.

## Success criteria for the planning slice

- Nine independent deferred exec-plan files exist with exact ownership,
  prerequisites, non-goals, tasks, acceptance criteria, progress logs, and
  verification logs.
- The roadmap shows both numeric order and real activation dependencies.
- The PBR/glTF boundary reference links every relevant official extension and
  distinguishes ratified, release-candidate, draft, and archived status.
- No plan claims implementation, target evidence, or production readiness that
  has not occurred.
- Repository lint and Markdown/diff checks pass; any unrelated active-plan
  analysis blocker remains recorded separately.
