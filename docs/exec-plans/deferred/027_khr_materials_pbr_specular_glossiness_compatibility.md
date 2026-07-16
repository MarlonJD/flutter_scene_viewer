# KHR_materials_pbrSpecularGlossiness Compatibility Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-16): deferred, archived-input compatibility only.** Plan
> 015 is complete and no successor is active. This plan is last in the
> extension sequence because it does not define a new strategic authoring
> workflow.

**Goal:** Load older specular-glossiness assets safely through deterministic,
measured conversion where bounded, or typed fallback diagnostics where faithful
runtime conversion is not possible, without adding a permanent second public
BRDF family.

**Architecture:** The viewer owns archived-extension detection, conversion
policy, diagnostics, provenance, atomicity, and evidence. Scalar-only or other
demonstrably bounded input may be converted into the existing metallic-
roughness source material. Texture conversion defaults to offline tooling
unless an approved bounded runtime path can preserve color space, channels,
alpha, UVs, memory, and error limits. `flutter_scene` should not gain a second
production BRDF solely for this archived workflow.

**Tech Stack:** Dart, GLB/glTF parsing, archived
`KHR_materials_pbrSpecularGlossiness`, Khronos conversion appendix/validator,
existing material pipeline, optional offline conversion tools, Filament legacy
import as comparison, historical/current Three.js behavior.

## Global Constraints

- The extension is archived and superseded by `KHR_materials_specular`; do not
  expose new public authoring fields or recommend it for new assets.
- Do not silently treat glossiness as roughness without inversion, ignore
  colored F0, or reuse spec/gloss texture RGB/A as metallic-roughness channels.
- Do not bake runtime textures unless a separately reviewed budget, cache,
  cancellation, color-space, mip, and fidelity contract exists.
- Do not edit pub-cache. This plan grants no branch, commit, push, pin, or
  remote authority.

---

## Archived Contract and Reference Policy

- [ ] Pin the archived
  [KHR_materials_pbrSpecularGlossiness](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Archived/KHR_materials_pbrSpecularGlossiness/README.md)
  text and conversion appendix used by tests.
- [ ] Preserve `diffuseFactor` default `[1,1,1,1]` linear RGBA;
  `diffuseTexture` is sRGB RGB plus linear alpha coverage.
- [ ] Preserve `specularFactor` default `[1,1,1]` linear RGB and
  `glossinessFactor` default `1` in `[0,1]`.
- [ ] Preserve `specularGlossinessTexture` as sRGB specular RGB and linear
  glossiness A. Roughness relation begins with `1 - glossiness`, but full
  metallic-roughness conversion must follow the archived appendix.
- [ ] Filament currently advertises legacy glTF import support and can be a
  compatibility comparison. Three.js removed GLTFLoader support in r147 and
  recommends conversion; current Three.js cannot serve as a direct import
  reference. If historical Three.js is used, pin it separately and label it
  legacy-only.

## Planned Interface and Files

- Create `lib/src/internal/glb_specular_glossiness_reader.dart` with archived
  field/channel/color-space validation and core-fallback metadata.
- Create `lib/src/internal/specular_glossiness_converter.dart` for bounded
  scalar conversion plus explicit conversion result/error metrics.
- Modify `lib/src/model_loader.dart` and
  `lib/src/internal/glb_capability_reader.dart` for conversion/fallback policy
  and required-extension atomicity.
- Add a policy enum in a focused public file,
  `lib/src/legacy_material_policy.dart`, with defaults
  `diagnoseAndUseCoreFallback` and opt-in `convertWhenBounded`; do not add
  spec/gloss authoring fields to `MaterialPatch`.
- Add reader/converter/model-loader/policy tests and
  `test/specular_glossiness_conversion_corpus_test.dart`.
- Add offline-tool guidance under
  `docs/references/specular_glossiness_migration.md`.

No upstream renderer file is planned. An upstream change requires a separate
product decision and amended plan.

## Task 1: Write RED Archived-Input and Fallback Tests

- [ ] Cover all defaults/factors, alpha, gloss inversion, colored dielectric
  F0, metals, mixed materials, both textures, UV0 transform, UV1+, malformed
  objects, optional fallback, required failure, and invalid coexistence with
  modern exclusive extensions.
- [ ] Prove the default policy does not author a second BRDF or claim rendered
  spec/gloss; it loads valid core fallback only when allowed and diagnoses the
  archived intent.
- [ ] Prove required unsupported input blocks publication before live model,
  state, resource, or render mutation.
- [ ] Run `flutter test test/glb_specular_glossiness_reader_test.dart
  test/model_loader_test.dart`; expect RED failures for missing archived-input
  policy only.

## Task 2: Implement Detection, Policy, and Core Fallback

- [ ] Parse/validate archived intent and retain provenance without mapping it
  into `MaterialPatch` authoring fields.
- [ ] Implement explicit policy selection and serialization. Changing policy
  applies only on reload; it does not reinterpret an already published model.
- [ ] Emit diagnostics containing extension status, affected material/parts,
  whether core fallback exists, lost fields, and recommended offline migration.
- [ ] Re-run Task 1 tests; expect detection/fallback/atomic cases to pass.

## Task 3: Write RED Scalar Conversion Tests

- [ ] Port the archived appendix reference equations into test vectors, not
  production code. Cover dielectric/metal extremes, achromatic/chromatic F0,
  opacity, glossiness 0/1, and numerical stability near boundaries.
- [ ] Define comparison metrics in linear color: base-color error, F0 error,
  roughness error, and rendered direct/IBL image error under fixed states.
- [ ] Define a conservative acceptance threshold. Inputs outside it return
  `notConvertible` with reasons rather than a visually tuned result.
- [ ] Run `flutter test test/specular_glossiness_converter_test.dart`; expect
  RED failures only for the missing bounded converter.

## Task 4: Implement Bounded Scalar Conversion

- [ ] Implement deterministic finite scalar conversion using the archived
  appendix, preserving alpha and avoiding NaN/negative outputs.
- [ ] Return the converted core metallic-roughness values plus measured
  reconstruction/error metadata; do not hide approximation.
- [ ] Apply conversion to all affected primitives atomically before runtime
  overrides. Reset returns to the converted source for the loaded session.
- [ ] Re-run converter/controller tests; expect accepted vectors to pass and
  rejected vectors to retain fallback/diagnostics.

## Task 5: Decide Texture Conversion Separately

- [ ] Audit required per-texel conversion, two input textures, sRGB/linear
  channels, alpha, UV/sampler transforms, resolution mismatch, mip generation,
  cache/memory/cancellation, and compressed sources.
- [ ] Default decision: recommend hash-pinned offline conversion and reject
  runtime texture conversion unless measured product need justifies an amended
  plan.
- [ ] If runtime conversion is proposed, stop and obtain approval for a new
  implementation slice with RED/GREEN decoder/resource tests; do not append it
  opportunistically.

## Task 6: Compatibility Corpus and References

- [ ] Stage archived Khronos scalar and textured fixtures with hashes,
  licenses, validator output, and known conversion results.
- [ ] Compare converted output against Filament legacy import, an approved
  offline converter, and optionally historical Three.js <r147. Record versions,
  tone mapping, HDRI, lights, and the fact that current Three.js removed direct
  support.
- [ ] Capture core fallback, converted output, and reference direct-only/
  IBL-only/combined views. Report quantitative error and rejected cases.

## Task 7: Documentation and Verification

- [ ] Update API, runtime pipeline, authoring guidance, diagnostics,
  capability matrix, fixture provenance, and roadmap with `archived-input`
  wording; do not list the extension as a new material capability.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all to pass.

## Acceptance Criteria

- [ ] Archived status, every factor/texture channel/color space, alpha, and
  exclusivity rule are validated and diagnosed.
- [ ] Default behavior is safe core fallback/diagnostic; required unsupported
  intent is atomic.
- [ ] Only bounded, metric-backed scalar cases convert at runtime; unbounded
  or textured cases do not silently approximate.
- [ ] No public spec/gloss authoring API or permanent second BRDF is added.
- [ ] Reference comparisons pin Filament/historical Three.js/offline-tool
  versions and never claim current Three.js direct support.

## Progress Log

- 2026-07-16: Created as the final deferred compatibility plan.
  Implementation, conversion evidence, and target evidence are `not run`.

## Verification Log

- 2026-07-16: Plan checked against the archived Khronos fields/status,
  Filament's advertised legacy support, and Three.js r147 removal.
- 2026-07-16: `python3 tools/repo_lint.py` and `git diff --check` pass. The
  escalated `bash tools/run_checks.sh` reaches `flutter analyze` and stops at
  the active Plan 015 stable-pin boundary with the same 81 missing clearcoat
  contract issues; this documentation-only plan adds no Dart analysis issue.
