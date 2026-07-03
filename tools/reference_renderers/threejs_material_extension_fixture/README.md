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

The comparison is trend-based. It checks that transmission, IOR, clearcoat
factor, and clearcoat roughness move in the same visible direction as the
Flutter visual matrices; it is not a pixel-perfect renderer comparison.
