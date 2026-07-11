# Material Extension Visual Reference

Task 011 uses a shared GLB fixture plus trend metrics rather than pixel-perfect
image equality.

## Shared Fixture

Flutter visual smoke writes:

```text
tools/out/fsviewer_material_extension_reference_fixture.glb
tools/out/fsviewer_glass_matrix.png
tools/out/fsviewer_clearcoat_matrix.png
```

The GLB contains UV0-bearing geometry and glTF material-extension cases for
transmission `0.0`, `0.5`, and `1.0`, IOR variation, thickness/attenuation
variation, clearcoat `0.0`, `0.5`, and `1.0`, and clearcoat roughness
variation.

## Reference Renderer

Run:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Outputs:

```text
tools/out/reference_threejs_glass_matrix.png
tools/out/reference_threejs_clearcoat_matrix.png
tools/out/material_extension_reference_metrics.json
```

The local harness loads the shared GLB with three.js `GLTFLoader` and relies on
three.js `MeshPhysicalMaterial` handling for the glTF material extensions.
For the clearcoat reference view, the harness reuses the loaded GLB materials
on sphere geometry with UV0 so highlight trends are measurable; the shared GLB
still carries the material-extension cases and UV0-bearing fixture data.

## Trend Gates

The reference metrics require:

- transmission `1.0` shows more background variation than transmission `0.0`;
- IOR variation changes the rendered glass sample;
- clearcoat `1.0` produces a stronger highlight than clearcoat `0.0`;
- higher clearcoat roughness reduces peak highlight compared with smooth
  clearcoat.

Flutter metrics are compared by direction, not exact pixel values:

- transmission and IOR move in the same direction as the reference render;
- clearcoat factor increases highlight strength;
- clearcoat roughness does not exceed the smooth peak;
- clearcoat texture input changes the frame;
- clearcoat normal input moves the coating highlight.

The synthetic clearcoat matrix is shader-wiring evidence, not proof that every
real textured asset is production-ready. The DamagedHelmet manual-clearcoat
iOS Simulator run remains candidate-only because visual inspection still shows
overly stylized/striped behavior in the older replacement path. A follow-up
ToyCar iOS Simulator run verifies authored clearcoat and transmission in one
real GLB after the clearcoat backend changed to a translucent shared-geometry
overlay that preserves the source PBR material. Task 012 adds
GlassVaseFlowers and ClearCoatCarPaint as Khronos/three.js visual references
for candidate acceptance direction.

## Custom Shader Candidate Status

The repo-owned custom shader backend remains `candidate-only`. Its iOS
Simulator visual evidence is separately labeled `verified locally`.
Real-asset candidate acceptance requires
`backendKind: flutterSceneCustomShader` metrics, Khronos/three.js reference
direction, and evidence labels scoped to the platform actually run.
GlassVaseFlowers is the required glass reference for alpha-blend versus
transmission/volume behavior, and ClearCoatCarPaint is the required clearcoat
reference for a smooth coat over a rougher car-paint base. These visual trends
do not establish Khronos correctness or physical-device release readiness.
