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

The real-asset mode uses `GLTFLoader`, fixed camera presets, neutral lighting,
and a simple neutral backdrop so authored glass/transmission and clearcoat cues
are visible in a repeatable screenshot.

The comparison is trend-based. It checks that transmission, IOR, clearcoat
factor, and clearcoat roughness move in the same visible direction as the
Flutter visual matrices; it is not a pixel-perfect renderer comparison.
