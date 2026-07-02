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
