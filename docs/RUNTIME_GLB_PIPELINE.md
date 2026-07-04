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
- unsupported alpha mask requests on unlit materials while the installed
  `flutter_scene` unlit shader path treats mask like blend;
- unsupported material/effect mask requests when no opaque-family shader
  backend can consume the packed channel data;
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

The loader also performs a bounded package-local read of the binary `.glb`
JSON chunk to preserve authored material extension intent that the installed
`flutter_scene` importer does not expose. This reader verifies the GLB magic,
version 2 header, declared length, and JSON chunk shape, then maps
`KHR_materials_transmission`, `KHR_materials_ior`, `KHR_materials_volume`, and
`KHR_materials_clearcoat` fields to internal `MaterialPatch` intent. V2 also
preserves `KHR_materials_specular` scalar, color, and texture intent for
assets whose renderer cannot yet consume those fields. BufferView-backed GLB
images referenced by transmission, thickness, clearcoat, clearcoat roughness,
clearcoat normal, specular, and specular color textureInfo fields are copied
into the authored patch instead of using placeholder texture bytes. Malformed
extension values report `invalidMaterialOverride` diagnostics instead of
throwing.
Authored extension texture slots require `TEXCOORD_0`; UV1 is not substituted
and UVs are never generated. Missing-UV diagnostics name the texture slots that
triggered the requirement. If an authored extension texture explicitly requests
a non-zero `textureInfo.texCoord`, the reader reports
`unsupportedModelFeature` and does not create a runtime patch for that texture,
because the current adapter override path cannot bind non-UV0 texture
coordinates. Duplicate node paths are reported as
`ambiguousNodePath`, and authored extension intent for that ambiguous address
is not auto-applied.

V2 compression preflight uses the same bounded GLB JSON read before adapter
import. The reader records `extensionsUsed`, `extensionsRequired`,
`KHR_draco_mesh_compression` primitive counts, `EXT_meshopt_compression`
bufferView counts, `KHR_texture_basisu` texture counts, imported texture-slot
roles, textureInfo UV-set requirements, primitive UV evidence, and material
extension counts. Missing imported texture UV sets produce `missingUvSet`
diagnostics with mesh, primitive, material, UV set, and affected texture-slot
details. If a required decoder is unavailable, the loader returns
`unsupportedModelFeature` before calling `flutter_scene`, so unsupported
compressed assets do not silently become placeholder or partially imported
geometry. Unsupported compression extensions listed only in `extensionsUsed`
emit the same diagnostic shape with `required: false`; these diagnostics are
reported on successful loads when the GLB still has a valid fallback path.

`EXT_meshopt_compression` is handled in Dart before adapter import for
single-file GLB assets whose compressed data is stored in the embedded BIN
buffer. The decoder covers the glTF meshopt modes `ATTRIBUTES`, `TRIANGLES`,
and `INDICES`, and the `NONE`, `OCTAHEDRAL`, `QUATERNION`, and `EXPONENTIAL`
post-decode filters. The loader expands each compressed bufferView into
standard BIN bytes, updates the parent bufferView to point at the decoded data,
removes bufferView and top-level `EXT_meshopt_compression` declarations once no
compressed bufferViews remain, drops unreferenced fallback buffers when all
remaining bufferViews reference `buffers[0]`, and re-runs capability preflight
before calling `flutter_scene`. Malformed meshopt metadata, unsupported mode or
filter names, compressed data stored in non-embedded/external buffers, and
decoder failures return `unsupportedModelFeature` rewrite diagnostics. Required
meshopt assets fail before adapter import if rewrite is impossible; optional
meshopt assets may continue only when the original GLB still has a valid
fallback path and the diagnostic remains non-blocking.

For imported core material textures, V2 also reads GLB binary image
bufferViews and returns authored texture patches keyed by `PartAddress`. The
controller applies those patches immediately after adapter import, without
persisting them as user overrides. This deliberately routes imported
base-color/emissive maps through the color texture path, normal maps through
the normal texture path, and metallic-roughness/occlusion maps through the data
texture path, using the existing `flutter_scene` `TextureContent`-aware mipmap
pipeline. Authored material extension texture bytes flow through the same
patch mechanism, with transmission, thickness, clearcoat factor, clearcoat
roughness, and specular factor as data textures; clearcoat normal as a normal
texture; and specular color as preserved specular intent.

Imported texture patching also has one narrow repair for malformed textile GLBs
observed in A1B32-style exports: when a back-side material authors an `R_0*`
PNG data/mask map as `baseColorTexture`, the patch reader replaces that slot
with neutral white and emits an `unsupportedModelFeature` diagnostic containing
`repair: neutralWhiteBaseColor`. This keeps double-sided back fabric from
leaking black data maps into the front view while making the repair explicit.
The heuristic is limited to PNG `baseColorTexture` images named like `R_0*` on
materials named like back-side textile materials.

Imported texture
patches are created only for `textureInfo.texCoord` 0. Non-zero texCoord values
produce diagnostics instead of being applied through the UV0 override path.
External image URIs remain resolver work. GLB-embedded compressed KTX2/BasisU
images use the optional native BasisU path described below; when that path is
missing, disabled, or unable to transcode the payload, the loader reports
diagnostics instead of silently treating compressed data as ordinary color
textures. For GLB-embedded KTX2 images, those diagnostics include bounded
container header details such as `vkFormat`, mip `levelCount`, and
`supercompression` when the image bufferView is available, plus a `reason` and
`nextStep` naming the missing or failed Khronos Basis Universal ETC1S/UASTC
transcode path. The installed `flutter_scene` KTX2 utilities are for its own
`universal/1` block payload and do not make glTF `KHR_texture_basisu`
renderable by themselves.

The root package now has the same optional-decoder shape for BasisU/KTX2 that
Draco uses: apps may add the sibling `flutter_scene_viewer_basisu` native
transcoder plugin without turning the main viewer package into a platform
plugin. When the plugin advertises `textureBasisu`, the loader sends a
`basisuImages` manifest containing the texture index, image index, image
bufferView bytes, MIME type, and URI metadata to the native channel before
adapter import. The plugin vendors Basis Universal plus Zstd, transcodes
supported GLB-embedded KTX2 payloads to RGBA32, encodes them as standard PNG,
and returns structured `decodedImages` entries with `imageIndex`, decoded PNG
bytes, and MIME type. Root Dart owns the GLB rewrite: it appends decoded
images as ordinary GLB image bufferViews, rewrites
`textures[*].extensions.KHR_texture_basisu.source` into normal `source`
references, removes top-level `KHR_texture_basisu` declarations when no
compressed texture references remain, and re-runs preflight before calling
`flutter_scene`. If the plugin is absent, disabled, unlinked, receives
malformed input, or sees an unsupported KTX2 layout, the loader keeps the
blocking diagnostic path.

Draco native decoding is intentionally optional. The root package remains a
pure Dart package; apps that need `KHR_draco_mesh_compression` add the sibling
`packages/flutter_scene_viewer_draco` plugin. The plugin is enabled per app
with `FlutterSceneViewerDracoEnabled` in iOS `Info.plist` or
`flutter_scene_viewer_draco_enabled` Android manifest metadata. When the plugin
is missing, disabled, or built without the C++ Draco decoder linked, the loader
reports an actionable `unsupportedModelFeature` diagnostic naming the plugin
package, platform configuration key, extension, decoder, and status. The
optional sibling plugin vendors Google Draco 1.5.7 and links a decoder-only
source set through Android CMake and the iOS podspec; the Android NDK/CMake and
iOS ObjC++/C++ requirements are therefore carried only by the optional sibling
plugin, not by the main viewer package. iOS has a candidate bridge that maps
the `dracoPrimitives` manifest through Google Draco into `decodedPrimitives`;
local CocoaPods/Xcode iOS Simulator build verification now covers A1B32
rendering through that path. Android has the matching C++ primitive decode
bridge plus JNI result marshaling to MethodChannel `decodedPrimitives`; Android
NDK/SDK native app build verification is still pending.
When native Draco support is available,
the loader calls
the plugin `decodeGlb` MethodChannel
method before adapter import. The call includes a `dracoPrimitives` manifest
so native code does not need a full glTF JSON parser: each entry carries the
mesh index, primitive index, compressed bufferView bytes, Draco attribute-id
mapping, and target accessor schema for every attribute and optional index
accessor. The method may return already rewritten importer-ready GLB `bytes`,
or structured `decodedPrimitives` payloads containing mesh index, primitive
index, decoded attribute byte arrays, and optional decoded index bytes.
Structured primitive payloads are rewritten in Dart by appending GLB
bufferViews, binding the existing glTF accessors, removing primitive
`KHR_draco_mesh_compression` entries, and dropping the top-level Draco
required/used extension only after no compressed primitives remain. The Dart
rewrite requires native output to include every compressed attribute declared
by the Draco extension plus decoded index bytes when the primitive references
an index accessor. Decoded attribute and index payload sizes are checked
against the referenced accessor `componentType`, `type`, and `count`; missing
payloads or size mismatches produce `unsupportedModelFeature` rewrite
diagnostics instead of binding corrupt or partial geometry. The loader then
re-runs capability preflight on the rewritten GLB bytes. The adapter only
receives importer-ready GLB; if the decode method returns diagnostics or leaves
required compression in the GLB, loading fails loudly instead of passing
compressed geometry into `flutter_scene`.

After a successful load, authored extension patches are applied through the
same controller validation and adapter diagnostic path as runtime material
patches. Accepted authored patches are source material state, not user override
state, so they are not stored in `controller.materialOverrides`. Rejected
authored patches record diagnostics and likewise do not appear in persisted
override snapshots.

Alpha mode is runtime material state, not visibility. Opaque, masked cutout,
and translucent blend requests are routed as material alpha behavior; only
`MaterialPatch.visible` / `setPartVisibility` updates node or part visibility.
Masked cutout is accepted for supported lit PBR materials through
`flutter_scene.AlphaMode.mask`; translucent blend maps to
`flutter_scene.AlphaMode.blend`; alpha cutoff maps to the PBR material cutoff.

Material/effect masks are also material state, not visibility. They are
opaque-family packed texture inputs and require UV0 like other runtime texture
overrides. They are rejected when combined with alpha cutout, alpha blend, or
glass-family fields. Until an opaque-family shader backend consumes those
channels, the runtime adapter reports `unsupportedMaterialFeature` instead of
pretending the mask affected output.

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

`FlutterSceneViewer.materialExtensionPolicy` is the viewer-side capability
gate for advanced material extension validation. The default diagnostics-only
policy reports unsupported glass and clearcoat before those patches reach the
adapter or persistence store. `productionShaders()` opts into the
repo-owned custom shader backend for transmission, IOR, volume, and clearcoat
support. After shader preflight passes, the adapter routes supported patches
through `backendKind: flutterSceneCustomShader`; the adapter/backend must still
return diagnostics for any feature it cannot honestly render.

The `.fmat` material packaging path uses `hook/build.dart` and
`flutter_scene/build_hooks.dart` `buildMaterials(...)`. Task 011 hardens the
package-local material extension backend. Transmission uses a bounded
screen-space background render texture, IOR-derived Fresnel energy splitting,
Beer-Lambert-style attenuation, premultiplied alpha output, and reports
diagnostics for unsupported node-isolation shapes. Clearcoat uses a lit `.fmat`
`PreprocessedMaterial`,
draws as a translucent shared-geometry overlay, and adds a separate coating
lobe without replacing the source PBR material or lowering base roughness.
Local host visual matrices and three.js reference trends exist, and ToyCar
iOS Simulator evidence shows authored glass and clearcoat in one real GLB.
The package-local glass and clearcoat paths are the accepted production route
for the current verified iOS Simulator scope.
macOS, Android, Web, and physical iOS evidence remain deferred/not run.

As of 2026-07-03, the installed `flutter_scene` 0.18.1 target does not expose
real transmission/glass or clearcoat support. The local audit found no public
`PhysicallyBasedMaterial` fields for transmission, IOR, thickness,
attenuation, clearcoat factor, or clearcoat roughness, and the runtime glTF
material importer parses core PBR plus `KHR_materials_unlit`, but not
`KHR_materials_transmission`, `KHR_materials_ior`, `KHR_materials_volume`, or
`KHR_materials_clearcoat`. The viewer therefore keeps runtime glass and
clearcoat diagnostic-only by default. The default policy rejects runtime glass
and clearcoat patches with
`unsupportedMaterialFeature`; the production shader policy can route supported
intent through package-local shader paths after preflight on documented
verified targets. Task 012 production evidence is verified locally on iOS
Simulator only; other targets remain deferred/not run. Alpha blending is not
accepted as a glass substitute,
and low roughness is not accepted as a clearcoat substitute. Upstream
renderer-native material fields remain useful future PR candidates rather than
the active production gate.

Upstream `flutter_scene` PR candidates:

- importer support for `KHR_materials_transmission`;
- importer support for `KHR_materials_ior`;
- importer support for `KHR_materials_volume`;
- importer support for `KHR_materials_clearcoat`;
- stable material-extension hooks or first-class PBR extension fields so this
  package does not need package-local GLB JSON parsing for authored extension
  intent.

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
