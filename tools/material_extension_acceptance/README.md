# Material Extension Acceptance Corpus

This folder defines source, fixture, comparison, and target-evidence contracts
for selected glTF material extensions. Historical package-local glass,
clearcoat, and sheen runs remain `candidate-only`; renderer-native evidence is
recorded separately and does not imply release or `production-ready` status.

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
- Plan 018 additionally records SheenChair and SheenCloth for sheen-only
  coverage, GlamVelvetSofa for sheen plus specular, and ToyCar for separate
  Fabric sheen, body clearcoat, and Glass transmission materials.

## Source And License

The initial corpus points to Khronos glTF Sample Models entries:

- `GlassVaseFlowers` for alpha-blend versus transmission/volume behavior.
- `ClearCoatCarPaint` for clearcoat over a rougher car-paint base material.
- `ToyCar` for combined glass and clearcoat.
- `ClearCoatTest` for clearcoat-only behavior.
- `TransmissionTest` for glass/transmission behavior.
- `SheenChair`, `SheenCloth`, and `GlamVelvetSofa` for scalar, textured, and
  specular-composed sheen behavior.

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

Plan 015's stricter cross-renderer audit uses
`fixtures/plan015_controlled_comparison_state.json`. It freezes one canonical
per-model bounding sphere, a generated hash-pinned Radiance HDR, three
lighting passes (`directOnly`, `iblOnly`, and `combined`), PBR Neutral tone
mapping, sRGB output, and the Z-mirror coordinate conversion between
flutter_scene's imported-glTF world and Three.js. This state exists because
independent automatic bounds fits and numerically identical yaw values are not
enough when the renderers use different world handedness.

## Evidence Rules

Passing the manifest coverage test only proves the corpus roles are defined.
It does not establish runtime application, visual evidence, target evidence,
release maturity, or production readiness. Each evidence record must state its
application (`rendererNative`, `packageLocalCandidate`, or `none`), runtime
availability, visual result, target result, and maturity independently.
Physical iOS remains `not run` until device evidence is collected.

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

## Plan 015 Controlled Three.js Comparison

After staging the Plan 015 assets, generate and verify the Three.js reference,
record the iOS Simulator artifacts, and build the zoomed comparison board:

```sh
npm run test:plan015-controlled \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run capture:plan015-controlled \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run record:plan015-controlled-ios \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run capture:plan015-controlled-board \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
```

The ignored output root is
`tools/out/material_extension_acceptance/plan015_controlled_comparison/`.
Both renderer evidence files hash every source and capture. The
ClearCoatCarPaint board shows that the analytic-light highlight and HDR panel
orientation align after the shared coordinate mapping. Small IBL panel-center,
blur, and brightness differences remain expected because stock Three.js bends
rough reflections toward the normal and uses its own PMREM implementation,
while flutter_scene uses its own GGX prefilter and reflection-direction path.
This is controlled directional evidence, not pixel parity.

## Plan 018 Sheen Evidence

Plan 018 deliberately retains two independent histories:

- `fixtures/plan018_controlled_comparison_state.json` and
  `tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-14/`
  describe the 27-image SheenChair,
  SheenCloth, GlamVelvetSofa, and ToyCar run at `flutter_scene`
  `8e2e2221405b04c517189428d0faf8474cf7f708`. It remains
  `candidate-only`; candidate images are never relabeled renderer-native.
- `fixtures/plan018_renderer_native_scalar_sheen_control_state.json` and
  `tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/renderer-native-run-05/`
  describe a separate scalar sheen on/off control at
  `766351c865c621e8720c726f9aa51173ce76e786`. Sheen-on application is
  `rendererNative`, sheen-off is `none`, runtime is available, and iOS
  Simulator target plus visual evidence are `verified locally`. Maturity is
  `release pending`. The final `evidence.json` SHA-256 is
  `9f4d3e1b2c561174c9426ad0da653f09c8c3d8ab7494bdfa7dcdf06d121f74da`.

The native control fixes one grazing camera and three lighting passes. Its six
frames must pass structural-health checks, and each same-pass on/off pair must
pass the frozen renderer-local mean absolute sRGB delta threshold. This proves
a local visual response, not external-reference agreement, physical
correctness, or general pixel parity.

The package-authored reader remains UV0-only. A pure runtime renderer-native
sheen binding may select UV1 only when the primitive exposes the exact
`texture_coords_1` semantic; no evidence workflow may invent or substitute
UVs. Package-owned nonidentity core transforms, specular, and opaque IOR remain
on one coherent `FSViewerExtendedPbr` candidate. Renderer-native
transmission/volume must not be replaced by that material.

Physical iOS, Android, Web, external-reference comparison, physical
correctness, general pixel parity, release, and `production-ready` evidence are
`not run` or `release pending` as applicable.
