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
- no imported glTF light/camera application in v1.

V1 may still report that authored glTF cameras or lights were present as
metadata/diagnostics. Rendering remains controlled by the viewer's camera and
studio lighting.

## Diagnostics

Report these explicitly:

- missing `TEXCOORD_0` / UV0 when a texture override is requested;
- unsupported material/extension;
- unsupported transmission/glass material requests when the adapter target does
  not expose real `KHR_materials_transmission`, `KHR_materials_ior`, and
  `KHR_materials_volume` behavior;
- unsupported clearcoat material requests when the adapter target does not
  expose real `KHR_materials_clearcoat` behavior;
- ambiguous node path;
- missing primitive index;
- model exceeds configured size limits;
- network timeout or cache failure;
- environment source exceeds configured size limits;
- unsupported raw environment encoding or invalid equirectangular dimensions;
- raw environment asset/network/decode failures.

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

Single-file GLB remains the primary V1 path. A multi-file `.gltf` resolver is
acceptable in V1 only when target assets require external `.bin` and image
files; it should be a bounded loader feature with relative URI resolution,
source replacement/cancellation safety, byte limits, timeout behavior, and
diagnostics. It must not also pull in compression extensions, progressive mesh
streaming, or virtual texturing.

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

Runtime material texture override diagnostics are based on the availability of
UV0 / `TEXCOORD_0`. Later UV channels may exist for authored uses such as
lightmaps, but the viewer must not substitute them for runtime albedo, normal,
metallic-roughness, emissive, or occlusion texture overrides.

Tap picking stays behind the adapter boundary. `FlutterSceneViewer` sends local
tap position, viewport size, and the current viewer-owned render camera to the
adapter; the runtime adapter builds a `flutter_scene.PerspectiveCamera`, calls
`screenPointToRay(...)`, then uses `Scene.raycast(...)` against render
geometry. Successful hits are mapped back to `PartAddress(nodePath,
primitiveIndex)`. This is not physics picking, imported camera playback,
selection UI, or a custom raycaster.

The part registry also records imported material shading mode per primitive.
`PhysicallyBasedMaterial` is reported as `lit`, `UnlitMaterial` as `unlit`, and
other material classes as `unknown`. Scene lights are only expected to affect
`lit` primitives. `MaterialShadingPolicy` is passed into the adapter at load
time so callers can preserve authored material shader behavior or force
supported imported materials onto a lit or unlit base material. Runtime
`MaterialPatch` updates do not change shader mode.

As of 2026-07-03, the installed `flutter_scene` 0.18.1 target does not expose
real transmission/glass or clearcoat support. The local audit found no public
`PhysicallyBasedMaterial` fields for transmission, IOR, thickness,
attenuation, clearcoat factor, or clearcoat roughness, and the runtime glTF
material importer parses core PBR plus `KHR_materials_unlit`, but not
`KHR_materials_transmission`, `KHR_materials_ior`, `KHR_materials_volume`, or
`KHR_materials_clearcoat`. The viewer therefore records transmission/glass and
clearcoat as v1 release blockers and rejects current runtime glass and
clearcoat patches with `unsupportedMaterialFeature`; alpha blending is not
accepted as a glass substitute and low roughness is not accepted as a clearcoat
substitute.

The current lighting adapter maps direct lighting to one
`flutter_scene.DirectionalLight` and indirect/sky lighting to the scene
environment / image-based lighting intensity. `flutter_scene` also exposes
`Scene.environment`, `Scene.environmentTransform`, `Scene.skybox`,
`EnvironmentMap.fromAssets(...)`, and `EnvironmentMap.fromEquirectHdr(...)`.
The viewer exposes studio, empty, sRGB asset, raw HDR/EXR asset/byte, and
explicit Poly Haven environment sources without exposing concrete
`flutter_scene` types in the public API. Raw `.hdr` / `.exr` decoding is
environment-only and produces linear RGBA float pixels for
`EnvironmentMap.fromEquirectHdr(...)`.

Poly Haven support resolves the current descriptor shape from
`https://api.polyhaven.com/files/{assetId}` and reads the explicit
`hdri[resolution][hdr|exr]` entry supplied by the caller's environment
configuration. The viewer does not implicitly fetch Poly Haven data for the
default studio environment.

`ModelLoadResult` carries optional debug evidence for the viewer stats
surface: load duration, byte size, and known model counters. Adapter-provided
counters are preferred; otherwise node, mesh, and primitive counts may be
derived from the adapter snapshot. Missing counters remain `null`.

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
