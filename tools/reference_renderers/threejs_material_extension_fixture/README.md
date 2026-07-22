# three.js Material Extension Fixture

This harness renders the shared GLB written by the Flutter visual smoke:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Inputs:

- `tools/out/fsviewer_material_extension_reference_fixture.glb`

Outputs:

- `tools/out/reference_threejs_glass_matrix.png`
- `tools/out/reference_threejs_clearcoat_matrix.png`
- `tools/out/material_extension_reference_metrics.json`

For Task 012 real-asset visual recovery, render the user-supplied GLBs with:

```sh
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture -- --real-assets /private/tmp/WaterBottle.glb /private/tmp/ClearCoatCarPaint.glb
```

Real-asset outputs:

- `tools/out/reference_threejs_water_bottle.png`
- `tools/out/reference_threejs_clearcoat_car_paint_real_asset.png`
- `tools/out/reference_threejs_real_asset_metrics.json`

For A1B32 textile debugging, render the required Draco asset with:

```sh
node tools/reference_renderers/threejs_material_extension_fixture/render_a1b32_reference.mjs /Users/marlonjd/Downloads/A1B32.glb
```

A1B32 outputs:

- `tools/out/reference_threejs_a1b32_front_all.png`
- `tools/out/reference_threejs_a1b32_front_repaired_back.png`
- `tools/out/reference_threejs_a1b32_front_repaired_body_culled.png`
- `tools/out/reference_threejs_a1b32_metrics.json`

Those historical filter/repair variants are diagnostics only. They are not
Plan 014 acceptance evidence and must not be used to justify material,
renderer, target, or release support.

For the Plan 014 authored-data reference, first stage the exact approved
A1B32 bytes, then run the contract test and four-view capture:

```sh
python3 tools/stage_material_extension_fixtures.py \
  --stage-a1b32 path/to/A1B32.glb
npm run test:plan014-capture \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run capture:a1b32-plan014 \
  --prefix tools/reference_renderers/threejs_material_extension_fixture
```

The Plan 014 harness verifies the source hash before launch and renders the
unmodified authored scene at the fixed front/left/right/back views. It records
the exact Three.js npm integrity and source commit, browser/host, reference
state, viewport, artifact hashes, and pass criteria in
`tools/out/material_extension_acceptance/a1b32_threejs_reference/evidence.json`.
All outputs stay ignored because A1B32 redistribution is not established.
This is a Three.js directional reference only; all flutter_scene target rows
remain `not run` and it does not establish runtime capability, release
maturity, or production readiness.

The real-asset mode uses `GLTFLoader`, fixed camera presets, neutral lighting,
and a simple neutral backdrop so authored glass/transmission and clearcoat cues
are visible in a repeatable screenshot.

The comparison is trend-based. It checks that transmission, IOR, clearcoat
factor, and clearcoat roughness move in the same visible direction as the
Flutter visual matrices; it is not a pixel-perfect renderer comparison.

## Plan 015 Controlled Clearcoat Comparison

Plan 015 adds a stricter reference that uses the exact same generated HDR
bytes, canonical per-model camera frames, analytic directional light,
exposure, PBR Neutral tone mapping, and sRGB output in Three.js and the iOS
Simulator harness:

```sh
npm run test:plan015-controlled
npm run capture:plan015-controlled
npm run record:plan015-controlled-ios
npm run capture:plan015-controlled-board
```

The state is tracked at
`tools/material_extension_acceptance/fixtures/plan015_controlled_comparison_state.json`.
The Three.js harness applies one Z mirror to the camera, directional-light
travel direction, and HDR longitude so those inputs represent the same world
as flutter_scene's mirrored imported-glTF root. Applying that correction to
only the HDR is invalid and is rejected by the contract.

Outputs live under the ignored
`tools/out/material_extension_acceptance/plan015_controlled_comparison/`
directory. `threejs/evidence.json` and `ios_simulator/evidence.json` retain the
state, renderer mapping, source hashes, artifact hashes, and diagnostics. The
comparison board is `clearcoat_car_paint_comparison_board.png`.

The direct-only point highlight is colocated in both renderers. IBL panel
orientation also aligns, but small differences in panel center, blur, and
brightness are not a camera-state failure: Three.js and flutter_scene retain
independent rough-reflection and PMREM/GGX prefilter implementations. The
result is controlled stock-renderer comparison evidence, not a pixel-parity
claim.

## Plan 018 Sheen State and Loader Audit

Plan 018 freezes its four-model comparison state at
`tools/material_extension_acceptance/fixtures/plan018_controlled_comparison_state.json`.
Before accepting a Three.js reference image, run the fixed-state and real
GLTFLoader consumption contract:

```sh
npm run test:plan018-controlled
```

The test launches pinned `three@0.167.1` in headless Chrome with a unique
temporary profile and a local-only fixture server. It checks every authored
sheen material against the resulting `MeshPhysicalMaterial`, including both
SheenCloth maps, their shared source, distinct RGB+sRGB and alpha+linear roles,
texture transforms, texture channels, and frozen whole/sheened bounds. The
ignored `threejs_loader_audit.json` records the actual loaded-material audit.
This is importer direction/conformance evidence only; it is not a Flutter
load, target capture, reference render, pixel-parity, release, or
production-readiness claim.

After that loader contract is current, produce and validate the controlled
reference captures with:

```sh
npm run test:plan018-capture
```

The focused capture test writes 27 ignored PNGs and `threejs/evidence.json`
under
`tools/out/material_extension_acceptance/plan018_controlled_comparison/`.
Every model has explicit close and grazing views in direct-only, IBL-only, and
combined passes. ToyCar also has all three passes at its full-scene context
view. The evidence keeps authored sheen indices, loaded material dependencies,
and the subset used by each default scene separate; a dependency that is not
used by the default scene is audited but not described as pictured. Each PNG
is required to be `1206 x 2622` with a valid signature and recorded hash.

These captures are pinned Three.js reference direction/conformance evidence,
`verified locally`. Flutter/iOS remains `not run`; the captures do not establish
pixel parity, a physical target, renderer-native sheen, release maturity, or
production readiness.

Before any Flutter/iOS image is accepted, freeze and run the renderer-local
health contract against those 27 Three.js captures:

```sh
npm run test:plan018-analysis
```

The test decodes each full frame in an isolated local-only headless browser.
It rejects missing, blank, flat, or lighting-inert output with conservative
thresholds that were frozen before an iOS comparison image existed. The
ignored `threejs/health_baseline.json` records the observed minima and exact
source/capture hashes. It creates no crop, alignment, overlay, difference
heatmap, or board, and contains no cross-renderer pixel threshold. This is
Three.js renderer-local direction/conformance health evidence only; Flutter
and iOS remain `not run`, and package-local sheen maturity remains
`candidate-only`.
