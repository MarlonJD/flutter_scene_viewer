# Runtime GLB pipeline

## MVP flow

```text
ModelSource
  ↓
ModelLoader downloads/reads bytes
  ↓
FlutterSceneAdapter.loadGlbBytes
  ↓
flutter_scene Node.fromGlbBytes
  ↓
Viewer builds PartRegistry from node hierarchy
  ↓
Viewer applies initial overrides
  ↓
Scene is rendered through SceneView
```

## What the viewer must not do

- no tessellation of STEP/DWG/IGES/CAD;
- no UV unwrap;
- no tangent generation in v1;
- no custom shader generation;
- no imported glTF light/camera handling in v1.

## Diagnostics

Report these explicitly:

- missing UVs when a texture override is requested;
- unsupported material/extension;
- ambiguous node path;
- missing primitive index;
- model exceeds configured size limits;
- network timeout or cache failure.

## Security and resource limits

Network models can be hostile or simply too large. MVP should support:

- maximum GLB byte size;
- timeout;
- optional allowed hostnames;
- cancellation;
- texture dimension limit;
- memory-budget-aware texture cache.

## Current adapter assumptions

The runtime adapter boundary expects `flutter_scene` to provide
`Node.fromGlbBytes(Uint8List)`. The concrete import is intentionally kept behind
`FlutterSceneAdapter.loadGlbBytes` so public APIs and loader tests do not depend
on `flutter_scene` symbols.

As of 2026-07-02, local verification with `flutter_scene` 0.18.1 found a
Flutter SDK compatibility blocker on Flutter 3.45.0-1.0.pre-38 because the
installed Flutter GPU API lacked symbols used by `flutter_scene`, including
`gpu.VertexLayout`, texture compression family types, and mip-level texture
APIs.

That blocker is resolved when using Flutter master 3.46.0-1.0.pre-403 or newer
with engine hash `6bef0a77783127874e0aedefe6aaf5abd42b63ed`. The concrete
runtime adapter imports `package:flutter_scene/scene.dart` and calls
`Node.fromGlbBytes(bytes)` after initializing the `flutter_scene` shader library
and material static resources.

Valid GLB import verification uses `test/fixtures/Box.glb` from Khronos glTF
Sample Models. Because native `flutter_scene` import constructs GPU-backed
geometry/material resources, this success-path test is opt-in and requires:

```sh
flutter test test/model_loader_test.dart \
  --plain-name 'imports a valid GLB fixture through the flutter_scene adapter' \
  --enable-impeller \
  --enable-flutter-gpu \
  --dart-define=FLUTTER_SCENE_GPU_TESTS=true
```
