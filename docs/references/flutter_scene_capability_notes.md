# flutter_scene capability notes

This file records assumptions that the adapter must verify against the installed
`flutter_scene` version.

Known target capabilities:

- runtime GLB import through `Node.fromGlbBytes`;
- PBR material class with base color, metallic, roughness, normal, emissive,
  occlusion, alpha, and double-sided controls;
- SceneView widget for rendering;
- raycasting through scene geometry;
- Flutter GPU/Impeller native rendering and WebGL2 web backend.

V1 release-blocker capability to verify:

- real glTF glass support through `KHR_materials_transmission`,
  `KHR_materials_ior`, and `KHR_materials_volume`, including transmission or
  refraction behavior, Fresnel/IOR behavior, and volume attenuation. Alpha
  blending alone is not sufficient.
- real glTF clearcoat support through `KHR_materials_clearcoat`, including
  clearcoat factor, roughness, and texture/normal inputs where available.
  Lowering base roughness alone is not sufficient.

Adapter implementation must keep direct `flutter_scene` imports isolated so API
breakage is easy to repair.

## Local verification note

On 2026-07-02, `flutter_scene` 0.18.1 was present in the local pub cache and
documents `Node.fromGlbBytes(Uint8List)` in `lib/src/node.dart`.

Importing `package:flutter_scene/scene.dart` failed on Flutter
3.45.0-1.0.pre-38 because the local Flutter GPU API did not expose newer
symbols required by `flutter_scene` 0.18.1, including `gpu.VertexLayout`,
texture compression family types, and mip-level texture APIs.

The import compiles on Flutter master 3.46.0-1.0.pre-403 with engine hash
`6bef0a77783127874e0aedefe6aaf5abd42b63ed`; the runtime adapter now calls
`Node.fromGlbBytes(bytes)` after initializing the shader library and material
static resources.

The valid import path was verified with `test/fixtures/Box.glb` from Khronos
glTF Sample Models using `--enable-impeller`, `--enable-flutter-gpu`, and
`--dart-define=FLUTTER_SCENE_GPU_TESTS=true`.

On 2026-07-03, a local source audit of `flutter_scene` 0.18.1 from
`.dart_tool/package_config.json` found that
`lib/src/material/physically_based_material.dart` exposes core
metallic-roughness PBR fields, alpha mode/cutoff, double-sided behavior through
the base material, and per-material environment overrides. It does not expose
transmission, IOR, thickness, attenuation, clearcoat factor, clearcoat
roughness, or clearcoat normal fields.

The runtime material path in `lib/src/runtime_importer/material_builder.dart`
maps core PBR textures/factors, normal, occlusion, emissive, alpha,
double-sided, and `KHR_materials_unlit`. The glTF parser in
`lib/src/importer/src/gltf/parser.dart` only checks material extensions for
`KHR_materials_unlit`, and `lib/src/importer/src/gltf/types.dart` has no fields
for `KHR_materials_transmission`, `KHR_materials_ior`,
`KHR_materials_volume`, or `KHR_materials_clearcoat`.

Current `flutter_scene_viewer` glass and clearcoat patch fields are therefore
diagnostic-only, and v1.0 remains blocked on upstream renderer/importer support
for those extensions rather than something the viewer should fake.
