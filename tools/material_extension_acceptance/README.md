# Material Extension Acceptance Corpus

This folder defines the real-asset acceptance corpus required before glass and
clearcoat can be treated as production support for the repo-owned custom shader
backend.

The manifest is intentionally metadata-first. The listed GLBs are not vendored
in this repository. Test or release tooling must explicitly stage each asset,
record its exact source, and write target evidence before expanding production
wording beyond the verified target scope.

## Required Roles

- `glass_only`: exercises `KHR_materials_transmission`,
  `KHR_materials_ior`, and `KHR_materials_volume`.
- `clearcoat_only`: exercises `KHR_materials_clearcoat`.
- `combined_glass_clearcoat`: exercises authored glass and clearcoat in one
  real asset.

## Source And License

The initial corpus points to Khronos glTF Sample Models entries:

- `GlassVaseFlowers` for alpha-blend versus transmission/volume behavior.
- `ClearCoatCarPaint` for clearcoat over a rougher car-paint base material.
- `ToyCar` for combined glass and clearcoat.
- `ClearCoatTest` for clearcoat-only behavior.
- `TransmissionTest` for glass/transmission behavior.

The manifest records the source URL, license, vendoring status, required glTF
extensions, reference viewer URL where applicable, and minimum evidence for
each asset. If a future run downloads or vendors any asset, update
`manifest.json` with the local path and exact revision or content hash before
using it as release evidence.

Plan 014's immutable source/license records live under the manifest's
`fixtureProvenance` key. Five official Khronos feature fixtures are pinned to
one full `glTF-Sample-Assets` commit with exact GLB and model-license hashes.
They remain metadata-only in git and can be downloaded plus verified into the
ignored `tools/out/` staging area with system `curl` and Python 3:

```sh
python3 tools/stage_material_extension_fixtures.py --fetch-khronos
```

A1B32 is recorded separately for the current Plan 014 task as a
user-authorized local fixture. No redistribution right, public source, SPDX
identifier, or copyright holder is invented, and the asset is not vendored.
Stage an explicitly provided copy only after its bytes and GLB contract pass
the pinned checks:

```sh
python3 tools/stage_material_extension_fixtures.py \
  --stage-a1b32 path/to/A1B32.glb
```

Fixture staging proves source/license identity only. It does not establish a
renderer path, runtime capability, target evidence, package/release maturity,
or production readiness. A1B32's two unsupported-image-feature warnings and
four generated-tangent-space portability warnings remain exact acceptance
blockers until target and visual evaluation disposes them.

The `fixtures/` files are small tracked inputs for the comparator unit test.
They mirror the reviewed iOS Simulator and reference-renderer metrics without
depending on ignored `tools/out/` artifacts being present in every checkout.

`fixtures/reference_state.json` is the required fixed camera, environment, and
lighting configuration for later material captures. Its schema is checked
against the `ViewerLighting.studio()` and `ViewerEnvironment.studio()` defaults
so evidence cannot drift silently. The complete ownership and visual-trend
contract is documented in
[`docs/references/pbr_material_acceptance.md`](../../docs/references/pbr_material_acceptance.md).

## Evidence Rules

Passing the manifest coverage test only proves the corpus roles are defined.
Production promotion for the current scope requires
`backendKind: flutterSceneCustomShader` iOS Simulator metrics, three.js or
Khronos Sample Viewer directional reference comparison, and clear evidence
labels for any target beyond iOS Simulator. Physical iOS remains not run until
device evidence is collected.

Every capture must record the reference-state schema version, camera view,
pinned `flutter_scene` revision, target, renderer backend, tone-mapping mode,
and source artifact. Comparisons with Khronos Sample Viewer or three.js are
directional and are never pixel-parity claims. A GPU or visual target that was
not executed remains `not run`.

## Plan 014 A1B32 Reference Capture

After local A1B32 staging, the Plan 014 Three.js harness can create the fixed
front/left/right/back directional reference without changing authored
materials, textures, geometry, UVs, or visibility:

```sh
npm run test:plan014-capture \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run capture:a1b32-plan014 \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
```

The manifest retains the exact source, renderer, browser/host, reference-state,
artifact-hash, and evidence-boundary metadata. PNGs and the full local report
remain under ignored `tools/out/` paths because redistribution is not
established. The captures are `verified locally` as Three.js reference
direction only. iOS Simulator, physical iOS, Android, and Web target evidence
remain `not run`; runtime capability and release maturity remain
`not established`.
