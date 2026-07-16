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
