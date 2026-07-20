# Public API draft

## Widget

```dart
FlutterSceneViewer(
  source: ModelSource.network(Uri.parse('https://cdn.example.com/chair.glb')),
  controller: controller,
  lighting: ViewerLighting.studio(),
  environment: const ViewerEnvironment.studio(),
  materialShadingPolicy: MaterialShadingPolicy.authored,
  materialExtensionPolicy:
      const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
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

`materialExtensionPolicy` controls whether advanced material extension fields
are kept diagnostic-only or may be validated against an available renderer or
package-local shader backend. The default
`ViewerMaterialExtensionPolicy.diagnosticsOnly()` rejects unsupported
transmission/glass and clearcoat fields before they are applied or persisted.
`ViewerMaterialExtensionPolicy.experimentalShaders()` opts into candidate
transmission, IOR, and volume intent where the attached backend can honestly
render it. `enableClearcoat` defaults to `false`; setting it to `true` permits
the pinned renderer-native clearcoat contract.
`ViewerMaterialExtensionPolicy.productionShaders()` opts into the
renderer-native route, with the repository-owned custom shader retained only
as a compatibility fallback, while preserving the existing constructor name
for source compatibility. At pinned `flutter_scene` commit
`5dcf6fce7dc36719e64e536faba9538fe9fa1022`, transmission, glass IOR, volume,
and clearcoat report `backendKind: rendererNative`.
Availability and routing do not prove Khronos correctness or physical-device
release readiness. Per-feature release maturity and per-target evidence remain
separate: these native features are `release pending` with iOS Simulator
evidence `verified locally`; the static policy claims no production release
target. The policy does not permit fake fallbacks: if the backend cannot render
the requested feature, it must report `unsupportedMaterialFeature`. Physical
iOS, Android material rendering, and Web material rendering remain `not run`.

The [generated capability matrix](generated/capability_matrix.md) is generated
from the stable live capability source. Its completed Plan 014 rows remain
fingerprinted historical context. Plan 014 iOS Simulator evidence is `verified locally`
for `KHR_texture_transform`, `KHR_materials_specular`, opaque
`KHR_materials_ior`, and the A1B32 Draco load, while physical iOS, Android,
and Web remain `not run`. These are `candidate-only` rows, not release or
`production-ready` claims. Plan 017's tracked
[decoder/mip evidence contract](../tools/decoder_mip_acceptance/README.md)
requires durable evidence for the exact feature and target before a live row
can advance. Its current discovery records do not prove runtime or packaging;
the aggregate remains `release pending`.

`MaterialExtensionSupport.supportFor(MaterialExtensionFeature)` is the
authoritative feature query. Each `MaterialExtensionFeatureSupport` keeps
availability, `MaterialExtensionMaturity`, and
`MaterialExtensionEvidenceStatus` per `MaterialExtensionTarget` as distinct
values. `productionReadyFor(feature, target)` is true only when that feature is
available, its maturity is `productionReady`, and that target's evidence is
`verifiedLocally`. The legacy boolean getters report availability only. The
legacy aggregate `productionReady` getter additionally requires a non-empty
claimed release-target set and every selected feature, including `specular`,
to be production-ready on every claimed target.

```dart
FlutterSceneViewer(
  source: source,
  materialExtensionPolicy:
      const ViewerMaterialExtensionPolicy.productionShaders(),
)
```

`ViewerLighting.studio(ambientOcclusion: true)` enables flutter_scene's
screen-space ambient occlusion pass for viewer-controlled studio lighting.
The studio preset separates indirect/sky lighting from direct dynamic lighting:
`environmentIntensity` scales the environment / image-based lighting term,
while `keyLightIntensity`, `keyLightColor`, and `keyLightDirection` configure
the viewer's single directional key light. `keyLightCastsShadow` opts into
upstream directional-light shadow maps for visual smoke scenes where an
occluder should make another object darker. Shadow quality can be tuned with
`keyLightShadowMapResolution`, `keyLightShadowMaxDistance`,
`keyLightShadowSoftness`, `keyLightShadowFadeRange`,
`keyLightShadowDepthBias`, `keyLightShadowNormalBias`,
`keyLightShadowCascadeCount`, and `keyLightShadowCascadeSplitLambda`. The
current adapter does not expose a separate `SkyLight` component; sky/indirect
lighting is represented by the scene environment.

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
environment never performs a network request. Production apps should normally
offer a curated set of bundled or explicitly described environments such as
studio, forest, coast, and city; arbitrary HDRI authoring/import is an asset
pipeline concern, not a default runtime workflow.

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

Pass a `ModelLoadCancellationToken` to a load when the caller owns its
lifecycle:

```dart
final cancellation = ModelLoadCancellationController();
final load = controller.load(
  ModelSource.network(modelUrl),
  cancellationToken: cancellation.token,
);
// For example, when the surrounding route is dismissed.
cancellation.cancel('route-dismissed');
await load;
```

`cancel` is idempotent and retains its first reason until the adapter accepts
its one live-publication commit. That acceptance atomically closes the token,
so a later `cancel` returns `false` and the accepted load finishes normally,
including authored and initial material application. Earlier cancellation emits
one `modelLoadCancelled` diagnostic with `status: cancelled`; it is distinct
from a timeout or a load failure. A cancelled initial load leaves the
controller empty. A cancelled replacement keeps the previously published part
tree and persisted overrides, and does not request a render frame for the
cancelled load. Asset acquisition races cancellation without allowing late
values or errors to publish. Network acquisition uses a request-scoped abort
and cancels only that response subscription; a shared HTTP client remains
usable by later loads. Whichever source result, caller cancellation, or load
timeout is observed first owns the terminal result.

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
cache, and diagnostic policies, and should not imply progressive streaming or
virtual texturing support. Compression support is scoped to the runtime GLB
pipeline: `EXT_meshopt_compression` is rewritten in Dart for embedded GLB
bufferViews before adapter import, `KHR_draco_mesh_compression` requires the
optional sibling decoder plugin, and KTX2 / `KHR_texture_basisu` requires the
optional `flutter_scene_viewer_basisu` sibling transcoder plugin when a GLB
contains compressed texture image payloads. The root loader has a
MethodChannel contract for that optional transcoder and rewrites decoded KTX2
images back into ordinary GLB image bufferViews before calling
`flutter_scene`; missing, disabled, unlinked, malformed, oversized, or
unsupported BasisU paths remain typed diagnostics rather than silent fallback.

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
- `alphaMode`
- `alphaCutoff`
- `effectMask`
- `transmission`
- `transmissionTexture`
- `ior`
- `thickness`
- `thicknessTexture`
- `attenuationColor`
- `attenuationDistance`
- `clearcoat`
- `clearcoatTexture`
- `clearcoatRoughness`
- `clearcoatRoughnessTexture`
- `clearcoatNormalTexture`
- `clearcoatNormalScale`
- `specular`
- `specularTexture`
- `specularColorFactor`
- `specularColorTexture`
- `visible`

Unsupported fields must be rejected with diagnostics, not silently ignored.
`normalScale` currently applies to a `normalTexture` override in the same patch;
`normalScale` without a normal texture override reports an unsupported-feature
diagnostic.

`MaterialAlphaMode.opaque`, `MaterialAlphaMode.mask`, and
`MaterialAlphaMode.blend` expose glTF-style alpha intent separately from
glass. `mask` is masked cutout/discard behavior for authored cutout materials;
it is not part visibility and is not a partial configurator hide mechanism.
`blend` is ordinary translucent alpha blending and must not be described as
transmission or glass. `alphaCutoff` is valid only in the `0..1` range and is
reported as an invalid material override outside that range. With the current
`flutter_scene` target, unlit material mask requests report diagnostics because
the upstream unlit shader path treats mask like blend.

`MaterialPatch.visible` is part visibility for the addressed `PartAddress`.
When a GLB stores several primitives under one node, the runtime adapter keeps
the node visible and hides only the addressed primitive slot, preserving sibling
primitives and primitive indices. It is separate from alpha cutout/blend and
does not change material opacity.

`MaterialEffectMask` is an opaque-family packed data map. Its red, green, blue,
and alpha channels can be assigned to material-effect targets such as
`paintRegion`, `roughness`, `metallic`, `dirt`, or future clearcoat masks.
Effect masks require authored UV0 and cannot be combined with alpha mask,
alpha blend, or glass material families. The current standard `flutter_scene`
PBR shader does not consume these packed channels, so runtime adapter paths
return `unsupportedMaterialFeature` until an honest opaque-family shader backend
is selected. Effect masks are not alpha cutout and do not affect
`MaterialPatch.visible`.

Runtime texture overrides require authored `TEXCOORD_0`/UV0 on the target
primitive. Additional UV channels such as `TEXCOORD_1` may be used by authored
assets for lightmaps or other data, but they are not treated as runtime material
override UVs.

Transmission/glass fields are v1 release-blocker API intent for
`KHR_materials_transmission`, `KHR_materials_ior`, and
`KHR_materials_volume`. With the default diagnostics-only policy, requests
using those fields return `unsupportedMaterialFeature` diagnostics and are not
applied or persisted. Experimental policy retains the historical package-local
candidate when its shader preflight succeeds. The source-compatible
`productionShaders()` policy now routes the complete selected contract through
the pinned renderer-native material/importer/render-graph path. Alpha blending
or base-color alpha alone must not be presented as glass, and texture forms
still require authored UV0. The native path consumes factor and red-channel
texture, exact glass IOR including `ior == 0`, thickness and green-channel
texture, node/world scale, attenuation color/distance, roughness, and opaque
scene color behind glass. Its iPhone 17 iOS 26.5 Simulator Impeller Metal
evidence is `verified locally` against stock Three.js r167 under one fixed
state; release maturity is `release pending`, production readiness is `false`,
and physical iOS, Android material rendering, and Web material rendering
remain `not run`. The older package-local screen-space backend remains only as
historical `candidate-only` evidence.

Clearcoat is a v1 release blocker for coated product materials such as car
paint, varnished wood, and carbon fiber gloss coat. The clearcoat patch fields
are serializable request intent for `KHR_materials_clearcoat`. The stable Git
dependency now pins published `flutter_scene` commit
`5dcf6fce7dc36719e64e536faba9538fe9fa1022`, whose importer, serialized scene
path, material slots, and shared PBR lighting implement the complete native
factor, red/green texture-channel, independent normal/scale, reset, and
combined-core contract. The source-compatible `productionShaders()` policy
routes clearcoat through `backendKind: rendererNative`; the default
diagnostics-only policy remains opt-in safe. Lowering base roughness is never a
clearcoat substitute, and texture forms still require authored UV0. iOS
Simulator evidence is `verified locally`; release maturity remains `release
pending`, production readiness is `false`, and physical iOS, Android material
rendering, and Web material rendering remain `not run`. The older translucent
package-local overlay is retained only as historical `candidate-only` evidence.

Specular fields are serializable request intent for `KHR_materials_specular`.
Authored GLB imports preserve `specularFactor`, `specularTexture`,
`specularColorFactor`, and `specularColorTexture` so assets such as A1B32 do
not collapse silently to ordinary metallic-roughness. Texture forms require
authored UV0. When the complete package shader contract is available, the
adapter automatically exposes `candidate-only` support and composes specular,
opaque IOR, and core UV0 transforms through exactly one
`FSViewerExtendedPbr` material. It performs shader/metadata, binding, texture,
and construction preflight before replacing the primitive or persisting the
patch. Unsupported targets and unavailable contracts remain diagnostic-only;
no renderer-native or production-ready support is implied.

## Material override persistence

`controller.materialOverrides` returns a serializable `MaterialOverrideSnapshot`
of the current sparse override state. Persist `snapshot.toJson()` and restore it
with `MaterialOverrideSnapshot.fromJson(json)`. Pass the restored snapshot to
`FlutterSceneViewer.initialMaterialOverrides` when it must be present on the
first visible frame. The viewer keeps load status at `loading` while those
patches and textures are applied, then exposes the ready render surface after
the complete snapshot finishes. This avoids showing a partially restored model
when one persisted snapshot spans several primitives. Use
`controller.applyMaterialOverrides(snapshot)` for intentional incremental
post-load changes.
Authored GLB extension material state is source data, not user override state,
so accepted or rejected authored extension patches are not added to this
snapshot.
