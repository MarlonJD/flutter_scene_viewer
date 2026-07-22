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

The [generated capability matrix](generated/capability_matrix.md) is generated
from the stable live capability source. Completed Plan 014 rows remain
fingerprinted historical context. Plan 014 iOS Simulator evidence is `verified locally`
for `KHR_texture_transform`, `KHR_materials_specular`, opaque
`KHR_materials_ior`, and the A1B32 Draco load, while physical iOS, Android,
and Web remain `not run`. The extended material path remains `candidate-only`,
and host parsing, intent preservation, codec output, rewrite validation,
simulator runs, or Three.js captures alone do not establish exact target
rendering. Plan 017's tracked
[decoder/mip evidence contract](../tools/decoder_mip_acceptance/README.md)
records content role (`color`, `data`, or `normal`), native storage role
(`color` or `nonColor`), exact material slots, samplers, and mip levels without
changing renderer behavior. It contains no runtime or package record yet, so
release remains `release pending`.

Plan 018 rows keep application, runtime availability, visual evidence, target
evidence, and maturity separate. The native scalar sheen-on control is
`rendererNative`, sheen-off is `none`, runtime is available, and iOS Simulator
target plus visual evidence are `verified locally`; maturity remains `release
pending`. The earlier textile/ToyCar record remains `candidate-only`.

Supported lit materials automatically route through one internal
`FSViewerExtendedPbr` material when they contain a nonidentity UV0 transform on
a core PBR slot, specular intent, or opaque-IOR intent. Combined triggers stay
on that one material instance. Core-only identity materials remain native
`flutter_scene.PhysicallyBasedMaterial`. The routed fragment owns core
sampling, transformed normal-map derivatives, dielectric specular/IOR, direct
studio lighting, IBL through `flutter_scene` resources, generated shadows,
fog, and HDR-premultiplied output. It does not replace the engine's scene
graph, geometry, camera, rasterization, picking, environment generation, tone
mapping, resolve, or scheduling.

That route is primitive-local, not model-name or asset-wide routing. An
existing extended material keeps its transformed/specular/opaque-IOR state when
sheen or scalar clearcoat is added. Clearcoat may therefore compose with
the coherent extended state. Renderer-native transmission/volume must not be
replaced by `FSViewerExtendedPbr`; a combination that would lose glass state
fails atomically. In ToyCar, the `Fabric` material uses the extended sheen path
because its own base-color and normal slots have nonidentity transforms; the
separate body material owns clearcoat and the separate `Glass` material owns
transmission. Their presence elsewhere in the same asset does not determine the
Fabric route.

Transmission/glass is required before v1.0 release. It must mean real
glTF-style transmission/refraction behavior with IOR and volume attenuation
where requested, not an alpha-blended approximation. Published and pinned
`flutter_scene` revision
`766351c865c621e8720c726f9aa51173ce76e786` retains the selected native
material, importer, scene-color, refraction, positive-volume, attenuation, and
variable-IOR contract. The production policy stages and applies factor/red
texture, thickness/green texture, UV transforms, node/world scale,
attenuation, roughness, and `ior == 0` atomically through that renderer-owned
path. The Plan 016 evidence was collected at exact immutable revision
`5dcf6fce7dc36719e64e536faba9538fe9fa1022` on an iPhone 17 iOS 26.5
Simulator through Impeller Metal against stock Three.js r167 under its fixed
state; the current pin retains that contract. Release maturity is `release
pending`; production readiness is `false`; nested glass and order-independent
transparency remain out of scope; physical iOS, Android, and Web remain `not
run`. The repository-owned screen-space shader is retained only as a
historical `candidate-only` path.

Clearcoat is also required before v1.0 release. It covers two-layer coated
materials such as automotive paint, varnished wood, carbon fiber under gloss
coat, and other premium product surfaces. It must mean real clearcoat behavior
such as `KHR_materials_clearcoat`, not a fake fallback that only lowers base
roughness or boosts environment intensity. Clearcoat remains diagnostic-only
by default. Task 011 added a lit package-local clearcoat candidate that
preserves base PBR lighting and adds a bounded coating lobe from clearcoat
factor, clearcoat roughness, clearcoat textures, and clearcoat normal inputs.
It has historical local iOS Simulator shader-load and synthetic visual-matrix
evidence, follow-up ToyCar evidence, and candidate acceptance metrics for the
`flutterSceneCustomShader` backend. The overlay keeps the source material in
place, adds the coating response on top, and attenuates the visible base layer
with a clearcoat Fresnel energy-loss term so the result behaves more like a
thin coat over the base material rather than an unrelated highlight pass.
Plan 015 now has a complete renderer-native implementation in published,
Git-pinned `flutter_scene` revision
`5dcf6fce7dc36719e64e536faba9538fe9fa1022`. It maps the Khronos factors,
red/green texture channels, independent coat normal/scale, and UV metadata into
an energy-aware second dielectric lobe inside the standard renderer lighting
path. The viewer adapter and combined transformed-core shader path are verified
locally on the iOS Simulator. The stable viewer dependency now resolves
`766351c865c621e8720c726f9aa51173ce76e786`, which retains that published
clearcoat contract without a path override and adds renderer-native sheen.
Release maturity remains `release pending`, production readiness is `false`,
and physical iOS, Android, and Web remain `not run`.

Sheen is post-v1 material-extension work and is not a v1 release blocker. The
public patch preserves `KHR_materials_sheen` color factor/texture and roughness
factor/texture intent, including sRGB RGB for color and linear alpha for
roughness. With `productionShaders(enableSheen: true)`, a pure standard-PBR
patch can use the current renderer-native material. The pinned renderer owns
the Charlie direct and image-based lighting lobes, real DFG-B
directional-albedo data, lazy Charlie environment prefiltering, authored UV and
transform metadata, portable sampler limits, shader variants, and layering
below clearcoat. Those BRDF, lookup, prefilter, sampler, and shader choices stay
renderer-internal; the viewer exposes no renderer-internal BRDF API.

The viewer owns import intent, public validation and serialization, policy,
diagnostics, reset/persistence, atomic composition, and evidence labels. A
material that already needs package-owned nonidentity core transforms,
specular, or opaque IOR stays on one coherent `FSViewerExtendedPbr` candidate;
it is not downgraded to the standard material merely because native sheen is
available. Scalar clearcoat can compose there, while native transmission or
volume cannot be replaced. Active transmission plus active sheen plus textured
clearcoat exceeds the selected portable fragment-sampler contract and is
blocked before decode or mutation; the native scalar-clearcoat combination is
supported.

The separate scalar sheen on/off control at
`766351c865c621e8720c726f9aa51173ce76e786` records application
`rendererNative` for sheen-on and `none` for sheen-off, runtime availability,
and iOS Simulator target plus visual evidence `verified locally`. Maturity is
`release pending`. The earlier SheenChair, SheenCloth, GlamVelvetSofa, and
ToyCar captures at `8e2e2221405b04c517189428d0faf8474cf7f708` remain
historical `candidate-only` evidence because their routed materials require the
package-owned path; they are not relabeled renderer-native. Physical iOS,
Android, Web, external-reference comparison, physical correctness, general
pixel parity, release, and `production-ready` evidence are `not run` or
`release pending` as applicable.

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
diagnostics-only, so unsupported glass, clearcoat, and sheen requests are
rejected before persistence. Experimental policy may let transmission/glass
intent reach an attached candidate backend, and may let clearcoat intent reach
the candidate clearcoat shader when `enableClearcoat: true` is set. Sheen
remains disabled by default; `enableSheen: true` permits the capability-gated
native or bounded package-local route selected by the material state. The
source-compatible `productionShaders()` policy is an explicit opt-in for the
complete pinned renderer-native contract and reports
`backendKind: rendererNative`. Its native
feature records keep iOS Simulator `releasePending` maturity and
`verifiedLocally` evidence separate, with no claimed production release target.
Package-local shader preflight remains only a compatibility fallback and does
not promote its `candidate-only` maturity. Experimental policy still uses
`backendKind: packageLocalCandidate`.
The backend must still report diagnostics rather than fall back to alpha blend
or roughness changes when it cannot render the requested feature.

Historical package-local realistic-glass evidence is verified locally for iOS
Simulator only; it is not Plan 016's renderer-native evidence. The repository
retains an experimental transmission backend that uses a background
`RenderTexture` and `RenderView.layerMask` separation for bounded screen-space
refraction. Local GPU-gated verification loads the generated transmission
shader bundle entry and captures a visual matrix for transmission, IOR,
thickness, roughness, and normal trends against a striped-behind-glass
fixture. The shader keeps surface reflection separate from transmitted
background energy with an IOR-based Fresnel term, applies attenuation as
`attenuationColor^(thickness / attenuationDistance)`, and outputs
premultiplied RGB for the alpha-blended pass. The same fixture GLB is compared
directionally against a three.js reference render. The package-local backend
remains `candidate-only` while that historical iOS Simulator evidence is
`verified locally`;
physical iOS, Android material rendering, and Web material rendering remain
`not run`.

Plan 016 supersedes that package-local conclusion for the production policy.
The renderer-native path owns its scene-color target, double-sided back-face
prepass, private depth boundary, standard lit base response, rough refraction,
volume scale, and attenuation. The controlled immutable-pin evidence covers 16
synthetic/Khronos models across direct-only, IBL-only, and combined passes; all
calibrated metrics pass without lowering thresholds or boosting authored
materials or lighting.

The current background-capture path isolates glass at node layer granularity.
For production glass evidence, authored GLB assets should place glass geometry
on separate nodes from opaque geometry. A glass override targeting one
primitive on a multi-primitive node reports an `unsupportedMaterialFeature`
diagnostic with `limitation: nodeLayerIsolation` rather than hiding the
node's other primitives from the background pass and producing misleading
output.

The repository-owned custom shader clearcoat path remains `candidate-only`.
The repository contains
`assets/materials/fsviewer_clearcoat.fmat` and a production-policy-gated path
that loads `FSViewerClearcoat` through generated `.fmat` metadata as a lit,
translucent `PreprocessedMaterial` overlay. The backend keeps the source
primitive material in place, adds a shared-geometry clearcoat overlay, and
uses the coat Fresnel term to attenuate base-layer energy before adding the
clearcoat lobe. Local GPU-gated verification captures a
visual matrix for clearcoat factor, clearcoat roughness, texture influence, and
clearcoat normal highlight movement. The same fixture GLB is compared
directionally against a three.js reference render. Historical follow-up ToyCar
iOS Simulator evidence shows authored glass and clearcoat in one real GLB while
preserving the base material. GlassVaseFlowers and ClearCoatCarPaint are now
required corpus references for visual acceptance against Khronos/three.js
rendering direction. That historical iOS Simulator evidence is
`verified locally`;
physical iOS, Android material rendering, and Web material rendering remain
`not run`.

## Texture UV requirement

Texture override requires authored `TEXCOORD_0` / UV0 coordinates;
`flutter_scene_viewer` does not generate UV unwraps. If the target primitive
lacks UV0, the viewer reports diagnostics and preserves the current material.
Additional UV sets such as `TEXCOORD_1` are not used for runtime material
texture overrides in the package-owned reader or extended-PBR path; those
channels remain available for authored asset uses such as lightmaps. A narrow
renderer-native sheen exception is described below.

`MaterialPatch` currently exposes runtime override slots for base color,
metallic-roughness, normal, emissive, occlusion, and material/effect mask
textures, plus normal scale and occlusion strength where `flutter_scene`
exposes matching PBR material fields. Transmission and volume texture requests
also require UV0; the default adapter reports them as unsupported first unless
an opt-in backend advertises glass support. Clearcoat texture, clearcoat
roughness texture, and clearcoat normal texture requests likewise require UV0;
the default policy reports them as unsupported first unless an opt-in backend
advertises clearcoat support. Specular texture and specular color texture
requests also require UV0. On a supported extended-PBR target they route
automatically, with the strength texture sampled from linear alpha and the
color texture decoded from sRGB RGB. An unavailable shader contract or an
unsupported target returns diagnostics before live material mutation.

Sheen color and roughness texture requests also require UV0 on the authored
package-reader and package-owned extended-PBR paths. One narrow runtime-only
exception exists for a pure renderer-native sheen patch: a binding may select
UV1 only when the target primitive exposes the exact `texture_coords_1`
semantic. The adapter validates that attribute before decode and fails
atomically if it is absent. This exception does not make the authored
package-reader UV1-capable and does not permit UV substitution or generation.

Authored GLB extension texture slots handled by the package reader follow the
same UV0 rule. UV1 is never substituted for `transmissionTexture`,
`thicknessTexture`, clearcoat textures, specular textures, sheen textures, or
material/effect masks, and the viewer never generates UVs. When those authored
extension textures reference GLB binary image
bufferViews, V2 preserves the encoded bytes in the authored material patch so
the adapter can load them through the appropriate color, normal, or data
texture path. If an imported textureInfo requests `texCoord` 1 or higher, the
viewer reports a capability diagnostic instead of applying the texture through
UV0. External image URIs and KTX2/BasisU texture sources remain decoder work
and produce capability diagnostics rather than placeholder textures. For
GLB-embedded KTX2 image bufferViews, the diagnostic includes the parsed KTX2
header summary where available so the missing BasisU transcode path is
actionable, including a reason and next step. The installed `flutter_scene`
KTX2 utilities do not decode Khronos Basis Universal ETC1S/UASTC payloads for
glTF `KHR_texture_basisu`. The root loader can now hand KTX2 image bytes to an
optional native BasisU/KTX2 transcoder and rewrite returned PNG/JPEG bytes into
ordinary GLB texture sources, but a real optional transcoder or upstream
importer path is still required before those assets render instead of
diagnosing the missing decoder.

## Excluded from v1

- sheen, with post-v1 diagnostic, candidate, and renderer-native work owned by
  completed [Plan 018](exec-plans/completed/018_khr_materials_sheen.md);
- subsurface scattering;
- parallax mapping;
- displacement mapping;
- world-aligned textures;
- custom network shader code.

Plan 018 does not make sheen part of the v1 release gate. Its diagnostic,
candidate, renderer-native, and iOS Simulator control slices are present, but
the feature remains opt-in and `release pending`. An unavailable or
incompatible route reports a feature-specific diagnostic rather than inventing
a fallback. This is not a release, `production-ready`, physical-correctness, or
general pixel-parity claim.

The remaining modern-glTF gaps are assigned to deferred Plans 019-027 in the
[roadmap](ROADMAP.md). Those plans cover punctual lights, variants, emissive
strength, anisotropy, iridescence, diffuse transmission, dispersion, subsurface
research, and archived specular-glossiness compatibility. Their existence does
not change v1 scope or capability claims.

Hardware-assisted ray/path tracing is separate from those material-extension
plans and from the production raster path. Deferred
[Plan 028](exec-plans/deferred/028_adaptive_ray_path_tracing_feasibility.md)
starts with an unpublished fork-free lab under `tools/`, creates no permanent
viewer ray-tracing package, and requires measured physical-device GO before a
direct-upstream `flutter_scene` seam can be proposed. It does not change Plan
016 transmission support, V1/V2 release gates, or current capability labels.

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
