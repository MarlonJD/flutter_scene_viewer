# Public API draft

## Widget

```dart
FlutterSceneViewer(
  source: ModelSource.network(Uri.parse('https://cdn.example.com/chair.glb')),
  controller: controller,
  lighting: ViewerLighting.studio(),
  environment: const ViewerEnvironment.studio(),
  materialShadingPolicy: MaterialShadingPolicy.authored,
  renderPolicy: RenderPolicy.adaptive,
  debugShowStatsOverlay: false,
  onStats: (snapshot) {},
  autoOrbit: false,
  autoOrbitSpeedRadiansPerSecond: 0.35,
  allowCameraInsideModel: false,
  initialOverrides: savedOverrides,
  onPartTapped: (part) {},
)
```

`materialShadingPolicy` is an import-time choice. `authored` preserves the
GLB's material shader mode, `forceLit` converts supported imported materials to
a lit base material, and `forceUnlit` converts supported imported materials to
an unlit base material. This is intentionally not a runtime material patch.

`ViewerLighting.studio(ambientOcclusion: true)` enables flutter_scene's
screen-space ambient occlusion pass for viewer-controlled studio lighting.
The studio preset separates indirect/sky lighting from direct dynamic lighting:
`environmentIntensity` scales the environment / image-based lighting term,
while `keyLightIntensity`, `keyLightColor`, and `keyLightDirection` configure
the viewer's single directional key light. The current adapter does not expose
a separate `SkyLight` component; sky/indirect lighting is represented by the
scene environment.

`environment` selects the viewer-controlled environment source and presentation.
V1 supports `ViewerEnvironment.studio()`, `ViewerEnvironment.empty()`,
equirectangular sRGB asset environments through `ViewerEnvironment.asset(...)`,
environment-only raw `.hdr` / `.exr` sources through
`ViewerEnvironment.rawAsset(...)` and `ViewerEnvironment.rawBytes(...)`, and
explicit opt-in Poly Haven HDRI downloads through
`ViewerEnvironment.polyHaven(...)`. `showSkybox` displays the active
environment as an environment-backed skybox background. `intensity`,
`rotationRadians`, and `skyboxBlur` are viewer presentation controls, not
benchmark controls.

Raw `.hdr` / `.exr` support is for environment lighting/skybox input only; it
does not add HDR/EXR material texture overrides. The decoder accepts Radiance
RGBE `.hdr` files and a narrow uncompressed scanline OpenEXR subset with
RGB/RGBA half or float channels. Unsupported encodings, invalid dimensions,
missing assets, byte-limit failures, timeouts, and decode failures report
typed `ViewerDiagnostic` values and preserve the previous valid environment.

`ViewerEnvironment.polyHaven(...)` requires an explicit `assetId`,
`ViewerPolyHavenResolution`, file type (`hdr` or `exr`), and caller-provided
User-Agent string. The viewer resolves the current Poly Haven descriptor shape
from `https://api.polyhaven.com/files/{assetId}` and uses the returned
`hdri[resolution][fileType].url` and `size` fields. The default studio
environment never performs a network request.

`debugShowStatsOverlay` is an opt-in development overlay fed from
`ViewerStatsSnapshot`. `onStats` can collect the same snapshot without showing
the overlay. The snapshot reports viewer-managed FPS samples, frame interval
summary, scheduler/tick state, adapter `autoTick` state, auto-orbit state,
camera distance/position, diagnostics count/last code, and known model load
counters such as load duration, byte size, node count, mesh count, material
count, and primitive count. These values are smoke/debug evidence only, not
benchmark or performance claims.

`autoOrbit` enables a viewer-managed horizontal orbit animation using the
adaptive render scheduler. It is intended for smoke/debug presentation and
static model inspection, not imported glTF animation playback.

`onPartTapped` reports successful tap picks as `PartAddress` values. The
runtime adapter maps the viewer's current orbit camera and local tap position
to `flutter_scene` render-geometry raycasts, then converts the hit node and
primitive index back into the public stable-address format. Misses do not call
the callback, and orbit/pan/zoom gestures are not treated as taps. This is
static render-geometry picking only; it does not add selection visuals,
physics colliders, hover/lasso/editor interactions, or a custom raycaster.

`allowCameraInsideModel` defaults to `false`. By default, model-derived camera
fit keeps the orbit camera outside the model bounding sphere so zoom and
programmatic `setCameraOrbit(distance: ...)` calls do not place the camera
inside the model. Apps that intentionally need interior or extreme close-up
inspection can set it to `true`. This is a bounds-shell guard, not
triangle-level collision detection.

## Controller

```dart
await controller.load(ModelSource.network(modelUrl));
final loadState = controller.loadState;
final partTree = controller.partTree;
await controller.setPartMaterial(address, patch);
await controller.setPartTexture(address, textureSource);
await controller.resetPart(address);
await controller.setPartVisibility(address, false);
final savedOverrides = controller.materialOverrides;
await controller.applyMaterialOverrides(savedOverrides);
await controller.fitCamera();
await controller.setCameraOrbit(distance: 2.0, yawRadians: 0.8);
await controller.setCameraPosition(
  position: [2.0, 1.0, 3.0],
  target: [0.0, 0.0, 0.0],
);
```

`loadState.status` reports `idle`, `loading`, `success`, or `error`.
Failed loads attach a `ViewerDiagnostic` to `loadState.diagnostic` and also add
that diagnostic to `controller.diagnostics`.

`controller.partTree` exposes the last successfully loaded assembly hierarchy
as immutable `PartTree`, `PartNode`, and `PartRecord` values. Geometry-less
nodes remain in the tree as assembly/dummy nodes, and renderable mesh primitives
are addressed by `PartAddress(nodePath, primitiveIndex)`.
Each `PartRecord` exposes `materialShadingMode` (`lit`, `unlit`, or `unknown`)
so applications can tell whether scene lights are expected to affect that
primitive. The viewer does not promise runtime conversion between unlit and lit
material shader modes through `MaterialPatch`; use import-time
`materialShadingPolicy` for the base-material choice.

V1 rendering remains viewer-controlled even when an imported glTF contains
authored cameras or lights. A v1 metadata/diagnostic slice may report that such
authored scene inputs exist, but it should not switch to embedded camera
selection, `KHR_lights_punctual`, or authored full-scene playback.

## Camera fit

`controller.fitCamera()` asks the attached viewer widget to frame the currently
loaded model and then requests a fresh render frame. The method is intentionally
adapter-backed: callers do not pass or receive concrete `flutter_scene` camera
types. If model bounds are unavailable in the current adapter slice, the widget
keeps the request on the viewer side and does not expose renderer internals.

`controller.setCameraOrbit(...)` and `controller.setCameraPosition(...)` expose
plain Dart camera controls for repeatable inspection/test views. They update the
viewer-owned orbit camera and request a frame without exposing concrete
`flutter_scene` camera objects. Unless `allowCameraInsideModel` is enabled on
the widget, requested camera distances are clamped outside the fitted model
bounding sphere.

## Stable addressing

```dart
PartAddress(
  nodePath: ['Vehicle', 'DoorAssembly', 'DoorLeft'],
  primitiveIndex: 0,
)
```

Node names may be duplicated in real assets. Future work may add disambiguation
using index paths or importer-generated stable IDs. V1 should expose diagnostics
when a node path is ambiguous.

## Model sources

Single-file GLB remains the default v1 path. A multi-file `.gltf` resolver is a
bounded v1 candidate when target assets require external `.bin` and image files.
That resolver should reuse the loader's timeout, byte-limit, cancellation,
cache, and diagnostic policies, and should not imply Draco/meshopt/KTX2,
progressive streaming, or virtual texturing support.

## Material patch

Core patch fields:

- `baseColorFactor`
- `baseColorTexture`
- `metallicRoughnessTexture`
- `normalTexture`
- `normalScale`
- `metallic`
- `roughness`
- `emissiveFactor`
- `emissiveTexture`
- `occlusionTexture`
- `occlusionStrength`
- `visible`

Unsupported fields must be rejected with diagnostics, not silently ignored.
`normalScale` currently applies to a `normalTexture` override in the same patch;
`normalScale` without a normal texture override reports an unsupported-feature
diagnostic.

Runtime texture overrides require authored `TEXCOORD_0`/UV0 on the target
primitive. Additional UV channels such as `TEXCOORD_1` may be used by authored
assets for lightmaps or other data, but they are not treated as runtime material
override UVs.

## Material override persistence

`controller.materialOverrides` returns a serializable `MaterialOverrideSnapshot`
of the current sparse override state. Persist `snapshot.toJson()` and restore it
with `MaterialOverrideSnapshot.fromJson(json)` followed by
`controller.applyMaterialOverrides(snapshot)` after loading the matching model.
