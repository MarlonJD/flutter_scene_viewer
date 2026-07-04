# Materials and lighting

## V1 material scope

Support core glTF metallic-roughness PBR:

- base color factor and texture;
- normal texture;
- metallic factor;
- roughness factor;
- metallic-roughness texture;
- occlusion texture;
- emissive factor and texture;
- alpha mode and double-sided where `flutter_scene` exposes them.

Transmission/glass is required before v1.0 release. It must mean real
glTF-style transmission/refraction behavior with IOR and volume attenuation
where requested, not an alpha-blended approximation. The current installed
`flutter_scene` 0.18.1 material/importer API does not expose
`KHR_materials_transmission`, `KHR_materials_ior`, or `KHR_materials_volume`,
so the default viewer policy keeps glass diagnostic-only. `MaterialPatch`
glass fields return `unsupportedMaterialFeature` diagnostics and are not
applied or persisted unless an opt-in material extension backend advertises
real transmission, IOR, and volume support. Production support is provided by
the repository-owned `flutterSceneCustomShader` backend after shader preflight
and target evidence checks pass. The current implementation is bounded
screen-space refraction with IOR-derived Fresnel energy splitting,
Beer-Lambert-style attenuation color/distance, thickness, and roughness
trends; it is not nested glass, order-independent transparency, or full
path-traced volume transport. Other targets remain deferred/not run.

Clearcoat is also required before v1.0 release. It covers two-layer coated
materials such as automotive paint, varnished wood, carbon fiber under gloss
coat, and other premium product surfaces. It must mean real clearcoat behavior
such as `KHR_materials_clearcoat`, not a fake fallback that only lowers base
roughness or boosts environment intensity. Clearcoat remains diagnostic-only
by default. Task 011 added a lit package-local clearcoat candidate that
preserves base PBR lighting and adds a bounded coating lobe from clearcoat
factor, clearcoat roughness, clearcoat textures, and clearcoat normal inputs.
It has local iOS Simulator shader-load and synthetic visual-matrix evidence,
follow-up ToyCar evidence, and production acceptance metrics for the
`flutterSceneCustomShader` backend. The overlay keeps the source material in
place, adds the coating response on top, and attenuates the visible base layer
with a clearcoat Fresnel energy-loss term so the result behaves more like a
thin coat over the base material rather than an unrelated highlight pass.
Upstream renderer-native `flutter_scene` clearcoat remains a future integration
path, not the current production gate. Other targets remain deferred/not run.

PBR and lit/unlit are separate concepts. PBR describes the material parameter
model and available inputs such as base color, metallic, roughness, normal,
occlusion, and emissive data. Lit/unlit describes whether the material shader
responds to scene lighting. A lit material can still use scalar metallic and
roughness values without texture maps, and an unlit material can still display
its authored texture without reacting to any light.

Alpha is supported as its own material behavior, not as glass. Opaque, masked
cutout, and translucent blend are separate base-material family intents in the
viewer. Masked cutout uses alpha discard for authored cutout surfaces such as
grilles, labels, or foliage-like product details; it must not be used as a
visibility system. Translucent blend is ordinary source-over alpha blending and
does not imply IOR, Fresnel, refraction, or volume attenuation. With the
current installed `flutter_scene` target, unlit alpha mask requests are
diagnostic-only because upstream unlit mask currently behaves like blend.

Material/effect masks are separate from alpha. They are opaque-family packed
texture data for regional material parameters such as paint regions, dirt,
roughness variation, metallic variation, or clearcoat masks once a real
clearcoat shader exists. They never discard pixels, never route a material into
the translucent family, and never hide parts. The current standard
`flutter_scene` PBR shader does not consume these packed channels, so the
viewer preserves the public intent and reports unsupported-feature diagnostics
rather than pretending the mask changed rendered output.

Material extension policy is capability-aware. The default policy is
diagnostics-only, so unsupported glass and clearcoat requests are rejected
before persistence. Experimental policy may let transmission/glass intent reach
an attached candidate backend, and may let clearcoat intent reach the candidate
clearcoat shader when `enableClearcoat: true` is set. Production policy is an
explicit opt-in for the repository-owned custom shader backend. Package-local
shader preflight reports `backendKind: flutterSceneCustomShader` when the
required shader bundle entries are available, and that backend kind can report
`productionReady` for the verified target scope. Experimental policy still uses
`backendKind: packageLocalCandidate` and cannot report production readiness.
The backend must still report diagnostics rather than fall back to alpha blend
or roughness changes when it cannot render the requested feature.

Realistic glass is verified locally for iOS Simulator only. The repository
contains a production-policy-gated transmission backend that uses a background
`RenderTexture` and `RenderView.layerMask` separation for bounded screen-space
refraction. Local GPU-gated verification loads the generated transmission
shader bundle entry and captures a visual matrix for transmission, IOR,
thickness, roughness, and normal trends against a striped-behind-glass
fixture. The shader keeps surface reflection separate from transmitted
background energy with an IOR-based Fresnel term, applies attenuation as
`attenuationColor^(thickness / attenuationDistance)`, and outputs
premultiplied RGB for the alpha-blended pass. The same fixture GLB is compared
directionally against a three.js reference render. Task 012 keeps production
scope to verified local iOS Simulator evidence for the bounded glass backend;
macOS, Android, Web, and physical iOS evidence remain deferred/not run.

The current background-capture path isolates glass at node layer granularity.
For production glass evidence, authored GLB assets should place glass geometry
on separate nodes from opaque geometry. A glass override targeting one
primitive on a multi-primitive node reports an `unsupportedMaterialFeature`
diagnostic with `limitation: nodeLayerIsolation` rather than hiding the
node's other primitives from the background pass and producing misleading
output.

Clearcoat production support for the current verified scope uses the
repository-owned custom shader backend. The repository contains
`assets/materials/fsviewer_clearcoat.fmat` and a production-policy-gated path
that loads `FSViewerClearcoat` through generated `.fmat` metadata as a lit,
translucent `PreprocessedMaterial` overlay. The backend keeps the source
primitive material in place, adds a shared-geometry clearcoat overlay, and
uses the coat Fresnel term to attenuate base-layer energy before adding the
clearcoat lobe. Local GPU-gated verification captures a
visual matrix for clearcoat factor, clearcoat roughness, texture influence, and
clearcoat normal highlight movement. The same fixture GLB is compared
directionally against a three.js reference render. Follow-up ToyCar iOS
Simulator evidence shows authored glass and clearcoat in one real GLB while
preserving the base material. GlassVaseFlowers and ClearCoatCarPaint are now
required corpus references for visual acceptance against Khronos/three.js
rendering direction.
macOS, Android, Web, and physical iOS evidence remain deferred/not run.

## Texture UV requirement

Texture override requires authored `TEXCOORD_0` / UV0 coordinates;
`flutter_scene_viewer` does not generate UV unwraps. If the target primitive
lacks UV0, the viewer reports diagnostics and preserves the current material.
Additional UV sets such as `TEXCOORD_1` are not used for runtime material
texture overrides; those channels are reserved for authored asset uses such as
lightmaps.

`MaterialPatch` currently exposes runtime override slots for base color,
metallic-roughness, normal, emissive, occlusion, and material/effect mask
textures, plus normal scale and occlusion strength where `flutter_scene`
exposes matching PBR material fields. Transmission and volume texture requests
also require UV0; the default adapter reports them as unsupported first unless
an opt-in backend advertises glass support. Clearcoat texture, clearcoat
roughness texture, and clearcoat normal texture requests likewise require UV0;
the default policy reports them as unsupported first unless an opt-in backend
advertises clearcoat support.

Authored GLB extension texture slots follow the same UV0 rule. UV1 is never
substituted for `transmissionTexture`, `thicknessTexture`, clearcoat textures,
or material/effect masks, and the viewer never generates UVs.

## Excluded from v1

- sheen;
- subsurface scattering;
- parallax mapping;
- displacement mapping;
- world-aligned textures;
- custom network shader code.

## Subsurface scattering note

Subsurface scattering models light traveling through translucent material and
taking on material-dependent color, such as skin appearing red when strong light
passes through it. That level of light transport belongs in dedicated 3D engines
or future opt-in extensions, not the v1 viewer core.

## Normal map note

Normal maps do not change silhouette or actual geometry. Advanced depth effects
may require parallax or displacement, but that belongs outside this v1 viewer
core.

`MaterialPatch.normalScale` is the normal-map intensity multiplier when a
`normalTexture` override is supplied in the same patch. The adapter bakes that
intensity into the override texture before handing it to `flutter_scene`, so
`1.0` preserves the authored map strength, `0.0` flattens the perturbation, and
values greater than `1.0` exaggerate the bump/readability effect. A
`normalScale`-only patch is reported as unsupported until the underlying
`flutter_scene` shader consumes its packed normal-scale uniform.

## Lighting policy

V1 uses viewer-controlled studio lighting. The goal is predictable product
viewing, not authored full-scene playback. Full imported glTF lights and
cameras remain future work, but V1 may report authored camera/light presence as
metadata/diagnostics while continuing to render with viewer-controlled lighting.
Screen-space ambient occlusion is available as an opt-in studio-lighting
setting and is not treated as benchmark evidence.

Scene lighting only affects lit materials. If an imported primitive's material
is unlit, changing environment intensity, key-light direction/color/intensity,
or ambient occlusion will not make that primitive respond to light.
`PartRecord.materialShadingMode` reports `lit`, `unlit`, or `unknown` so this
is visible to applications and smoke harnesses. `MaterialShadingPolicy` is the
import-time base-material choice: `authored` preserves the GLB, `forceLit`
converts supported imported materials to a lit base material during load, and
`forceUnlit` converts supported imported materials to an unlit base material
during load. This is intentionally not a `MaterialPatch` operation; shader and
blend behavior should not be flipped as an arbitrary runtime texture override.

Studio lighting has two terms in the current adapter. The direct dynamic term
is one viewer-controlled directional key light with direction, color, and
intensity. It can opt into upstream `flutter_scene` shadow maps with
`ViewerLighting.studio(keyLightCastsShadow: true)` when a visual smoke or app
experience needs cast-shadow readability. Shadow-map artifacts are expected
when the shadow atlas is too low resolution for the visible scene scale or
when a large `keyLightShadowMaxDistance` spreads cascades too far. Use
`keyLightShadowMapResolution`, `keyLightShadowMaxDistance`,
`keyLightShadowSoftness`, `keyLightShadowFadeRange`,
`keyLightShadowDepthBias`, `keyLightShadowNormalBias`,
`keyLightShadowCascadeCount`, and `keyLightShadowCascadeSplitLambda` to tune
quality for a given viewer scene. The indirect/sky-light-like term is the
scene environment / IBL intensity. There is no separate public `SkyLight`
component in this slice.
`flutter_scene` already exposes environment and skybox primitives, including
studio/empty environments, equirectangular asset environments, decoded linear
HDR pixel environments, environment intensity, environment rotation, and
environment-backed skyboxes. V1 exposes those through `ViewerEnvironment`:
studio, empty, sRGB asset, environment-only raw `.hdr` / `.exr` asset/byte
sources, and explicit Poly Haven HDRI sources. Raw HDRI decoding feeds
`EnvironmentMap.fromEquirectHdr(...)` with linear RGBA float pixels. It does
not add HDR/EXR runtime material texture overrides.

The raw environment decoder is intentionally narrow. Radiance RGBE `.hdr` is
supported, and `.exr` support is limited to uncompressed scanline RGB/RGBA half
or float channels. Unsupported EXR compression, unsupported channel layouts,
non-2:1 dimensions, missing files, byte-limit failures, timeouts, and decode
failures are reported as typed diagnostics. Failed environment source loads
preserve the last valid scene environment.

Poly Haven environments are explicit opt-in sources. Callers provide an asset
id, resolution, file type, and unique User-Agent; the default studio
environment remains local and deterministic. Fake HTTP tests cover descriptor
resolution, download byte limits, timeout handling, cancellation, and cache
reuse. Live downloads are optional smoke checks, not required verification.
Product apps should usually expose a curated set of environment choices such as
studio, forest, coast, and city as bundled assets or explicit descriptors
rather than asking users to provide arbitrary HDRI files at runtime. HDRI
authoring and capture is its own asset-pipeline concern.

Visual evidence should use the right scene for the claim being made. HDRI
reflection checks need a smooth metallic material, such as aluminum or steel
with `metallic: 1.0` and low roughness, so the environment tint can be seen on
the surface. Skylight or ambient-readability checks need actual spatial
occlusion: for example `SkylightTable.glb` contains a table, one object on top,
and one object underneath. With key-light shadows enabled, the lower object
should be darker but still visible from the environment/IBL contribution.
For that specific top-down smoke, do not use the default angled studio key
light. Use a directly overhead key light (`keyLightDirection: [0, -1, 0]`),
enable `keyLightCastsShadow`, keep `ambientOcclusion: false`, and choose a
tight `keyLightShadowMaxDistance` for the compact fixture. The expected visual
result is not a black hidden lower object; it is a slightly darker lower object
that remains readable because environment lighting still contributes.

Static baked lighting/lightmaps remain outside v1 core. If added later, they
should remain separate from runtime material texture override semantics so UV1
or later channels are not mistaken for UV0.
