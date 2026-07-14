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

## 2026-07-14 Plan 014 extended-PBR amendment

This amendment supersedes the 2026-07-13 UV-transform, specular, and opaque-IOR
blocked conclusions below. Those sections remain as historical evidence of the
pinned standard-material seam; they no longer describe the package-local
candidate capability.

The dependency remains pinned at
`cd6760912fa38beb55f63e388655a1aeabd32fe4`. The package adds one bounded
`FSViewerExtendedPbr` material-scoped full fragment rather than changing the
pin or pub cache. A supported lit material routes automatically when it has a
nonidentity UV0 transform on a core PBR slot, `KHR_materials_specular` intent,
or opaque `KHR_materials_ior` intent. Core-only identity materials remain on
the pinned standard material. Combined triggers use one extended material; no
asset-name branch, opt-in flag, fragment stacking, image tiling, UV generation,
or byte rewrite is involved.

The routed fragment applies each core slot as
`offset + rotation * (uv * scale)` and uses the transformed normal UV for both
sampling and the derivative tangent frame. It samples the specular-strength
texture from linear alpha, decodes the specular-color texture from sRGB RGB,
multiplies texture and factor intent, isolates metallic response, shares
dielectric specular/diffuse energy, maps ordinary IOR through
`((ior - 1) / (ior + 1))^2`, and treats exact IOR zero as full Fresnel. It owns
the routed material's direct studio light, IBL, shadow, fog, and
HDR-premultiplied output while retaining `flutter_scene` geometry, vertex,
raster, picking, camera, environment-generation, tone-mapping, final-resolve,
and scheduling contracts.

On 2026-07-14 an iPhone 17 Simulator running iOS 26.5 with Impeller/Metal and
Flutter GPU loaded the Draco-backed A1B32 fixture as 20 renderable primitives.
Four combined UV/specular/IOR patches applied and persisted with zero new
extension diagnostics. Picking returned `root/A1B32#0` and
`root/A1B32#2`. Fixed-state captures verified the caller-supplied Glorvia C28
albedo repeat 2.5 versus normal repeat 1.0, specular 0.1 versus 1.0, and opaque
IOR 2/tinted versus exact IOR zero. The encoded model and texture hashes were
unchanged. Evidence and reproduction snapshots are recorded at
`tools/out/material_extension_acceptance/plan014_extended_pbr_ios_simulator/`.
This is `verified locally` and `candidate-only`; physical iOS, Android, Web,
release packaging, and production readiness remain `not run`.

The fragment's lighting/resource structure is adapted from the pinned
`flutter_scene` `material_lighting.glsl` and `flutter_scene_standard.frag`.
`flutter_scene` is Copyright (c) 2023 Brandon DeRosier and MIT licensed; the
complete notice is retained in `THIRD_PARTY_NOTICES.md`. Khronos extension
specifications remain normative for transform, channel, color-space, and IOR
semantics.

## 2026-07-13 pinned texture-binding audit (historical pre-amendment)

This audit is scoped to the dependency revision in `pubspec.lock`,
`cd6760912fa38beb55f63e388655a1aeabd32fe4`. It records renderer capability,
not glTF semantics or release maturity.

Verified from the pinned source:

- `lib/src/texture/texture2d.dart:53-99` exposes one public
  `TextureSampling.addressMode` and writes it to both the low-level
  `widthAddressMode` and `heightAddressMode`. The low-level sampler can carry
  independent axes, but the public `TextureSampling` constructor cannot.
- `Texture2D.fromPixels`, `Texture2D.fromImage`, and `Texture2D.fromAsset`
  accept `TextureSampling` at lines 135-196. Wrapper-created asset, decoded
  image, and scaled-normal pixel textures can therefore carry symmetric wrap
  plus minification, magnification, and mip intent without changing encoded
  source bytes.
- `lib/src/runtime_importer/texture_builder.dart:19-88` iterates glTF texture
  entries one-to-one, but `_decodeAndUpload` constructs every imported texture
  with default sampling. It does not read the glTF texture's sampler. The
  shared placeholder also has separate fixed default sampling and is not
  evidence of authored sampler import.
- `lib/src/material/physically_based_material.dart:47-136` exposes five core
  texture sources but no texture-coordinate or per-slot transform fields.
  `shaders/material_varyings.glsl:6-24` exposes only the primary UV varying,
  and `shaders/flutter_scene_standard.frag:10-59` samples every standard slot
  with that same untransformed `v_texture_coords` value, including the normal
  map path.

The wrapper-supported subset is `verified locally` by focused CPU tests:

- equal `wrapS` and `wrapT` map to repeat, clamp-to-edge, or mirrored-repeat;
- all six public glTF minification modes and both magnification modes map to
  the corresponding `TextureSampling` min/mag/mip fields; unspecified filters
  retain the pinned renderer defaults;
- sampler state is passed through every wrapper-created `fromAsset`,
  `fromImage`, and `fromPixels` path while color, data, and normal content roles
  remain separate;
- separate bindings of one encoded image create separate texture-source calls,
  so sampler state is not stored as mutable state on shared encoded bytes.
  There is no wrapper texture cache today. Any future cache key must include
  content role and sampler state.

Review remediation also verified the following CPU-safe boundary behavior:

- standard PBR base-color and normal slots retain their separately created
  `TextureSource` objects and therefore retain distinct resulting sampler
  state;
- clearcoat receives wrapper-loaded occlusion and emissive texture sources
  instead of silently falling back to the authored source material;
- binding-only transmission and thickness intent participates in capability
  routing. The scalar-only renderer-native material contract rejects every
  transmission, volume, clearcoat, and specular extension texture slot with a
  typed `rendererNativeExtensionTextureContractMissing` diagnostic before any
  native setter runs;
- the package-local transmission backend rejects metallic/roughness state,
  metallic-roughness textures, occlusion state/textures, or emissive
  factor/textures found in either the incoming patch or the existing source
  PBR material before texture loading or material mutation. Its bounded shader
  consumes base-color and normal inputs, but it cannot consume those combined
  core-plus-transmission inputs atomically;
- preprocessed clearcoat binding resolves a `TextureSource` to both its
  `sampledTexture` and `sampledSampler`; a source with no sampled GPU texture
  returns a typed `preprocessedTextureSampleUnavailable` diagnostic before
  the target material or clearcoat overlay is changed. Raw GPU textures remain
  accepted.
- package-local transmission and clearcoat load incoming normal-map bytes
  without baking `normalScale`; their per-material shader parameters apply the
  scale once. Transmission falls back to the existing PBR source material's
  normal scale when the patch omits it. The standard PBR path remains separate:
  it keeps the existing scaled-pixel texture creation and assigns upstream
  `normalScale` as `1`.
- scalar specular/specular-color overrides remain unsupported by the pinned
  renderer-native material contract and return
  `rendererNativeSpecularContractMissing`. Direct patches that combine core
  PBR fields with native scalar extension intent return
  `rendererNativeMixedCoreExtensionPatchUnsupported` before texture loading,
  native setters, or target mutation. These diagnostics preserve intent; they
  are not renderer support.
- imported authored core and each extension group are delivered independently
  to the adapter. The controller does not turn sequential authored groups into
  a direct cumulative mixed patch. CPU integration verifies valid core PBR and
  supported renderer-native clearcoat plus transmission/IOR still apply when
  an independently validated specular group is unsupported.
- a PBR material that implements the renderer-native scalar extension contract
  retains its object identity when an explicit core alpha mode requires a
  mounted-mesh refresh. CPU integration verifies alpha mask/cutoff applies
  first, an unsupported specular group stays isolated, and later native
  clearcoat plus transmission/IOR setters still reach the same material. Plain
  PBR materials retain the existing replacement behavior for alpha pipeline
  changes.
- after package-local clearcoat overlay setup succeeds, direct combined core
  factors and wrapper-loaded base-color, metallic-roughness, normal,
  occlusion, and emissive textures are applied to the source/base PBR
  primitive. Overlay failure leaves those core fields unchanged. This is
  wrapper behavior around a `candidate-only` overlay, not renderer-native or
  release evidence.
- after that combined core mutation, positive package-local clearcoat
  re-suppresses the base/source normal so the raw incoming normal is consumed
  once by the overlay rather than shaded in both passes. A zero clearcoat
  factor preserves the legitimate combined core normal, and clearcoat reset
  restores the original source normal and scale. This CPU invariant is not GPU
  or visual evidence for the candidate overlay.
- package-local transmission rejects incoming alpha mode/cutoff and existing
  source alpha-mask state before texture loading or mutation because its
  bounded shader does not implement core alpha-mode semantics. Package-local
  extension patches also reject combined visibility intent before backend or
  geometry mutation; visibility remains a separate successful patch.

The tests that assign a real `flutter_gpu.Texture` and sampler into actual
`MaterialParameters` are present but were `not run` by the plain focused CPU
command. They require Impeller, Flutter GPU, generated shader-bundle assets,
and `FLUTTER_SCENE_GPU_TESTS=true`. CPU verification proves the wrapper plan,
resulting standard-material `TextureSource` sampler state, clearcoat config
forwarding, and the typed unavailable-source path; it does not establish that
the clearcoat `MaterialParameters` sampler was bound by a live GPU run.

At the time of this audit, the following were `blocked` on a real upstream
contract. The 2026-07-14 amendment above supersedes the nonidentity UV-transform
conclusion for the package-local extended path:

- asymmetric `wrapS`/`wrapT` is preserved in the public binding and returned as
  a typed `independentWrapAxes` diagnostic;
- non-identity offset, scale, or rotation is preserved per material slot and
  returned as a typed `perSlotUvTransformContractMissing` diagnostic before
  image decode or texture creation;
- runtime application of Glorvia repeat `2.5` is `not run`. No separate
  upstream checkout/commit or durable Glorvia runtime fixture is available,
  so the dependency pin is unchanged and this is not renderer support.

No texture tiling, texture baking, generated UVs, shared mutable transform
state, pub-cache edits, or package-local replacement PBR renderer were added.

## 2026-07-13 pinned specular and opaque-IOR audit (historical pre-amendment)

This audit is scoped to `flutter_scene` revision
`cd6760912fa38beb55f63e388655a1aeabd32fe4`. Khronos remains the authority for
glTF semantics; the pinned source is the authority for current renderer
capability.

The ratified
[`KHR_materials_specular`](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_specular)
contract defines a `[0, 1]` linear strength factor, a data/linear alpha-channel
strength texture, a non-negative linear RGB color factor that may exceed `1`,
and an sRGB-encoded RGB color texture. Factors multiply their texture samples.
The dielectric response must conserve energy and these controls must not alter
the metal BRDF. The ratified
[`KHR_materials_ior`](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_ior)
contract accepts finite IOR values greater than or equal to `1` plus the exact
`0` compatibility value; opaque IOR remains part of the ordinary
metallic-roughness PBR family.

Verified from the pinned renderer source:

- `lib/src/material/physically_based_material.dart:47-227` exposes and binds
  the core five PBR texture slots and scalar factors, but no specular-strength,
  specular-color, or IOR material fields or texture slots.
- `lib/src/material/material_parameters.dart:46-139` is a generic reflected
  `.fmat` parameter container. It does not add semantic fields to the standard
  PBR material or prove that its shader consumes specular/IOR intent.
- `lib/src/runtime_importer/material_builder.dart:12-57` imports core
  metallic-roughness, normal, occlusion, emissive, alpha, and double-sided
  state only.
- `shaders/material_inputs.glsl:12-45` has no specular or IOR surface input,
  and `shaders/flutter_scene_standard.frag:10-61` declares only the five core
  texture samplers.
- `shaders/material_lighting.glsl:248` fixes dielectric reflectance at `0.04`
  before mixing with metallic base color. Both indirect and direct lighting use
  that reflectance; there is no authored specular/IOR input.

The wrapper validation/parser subset is `verified locally` by CPU tests:

- public patches accept specular strength in `[0, 1]`, non-negative finite
  three-component specular color including values above `1`, and IOR exactly
  `0` or finite `>= 1`;
- invalid values produce typed `invalidMaterialOverride` diagnostics without
  clamping or coercion; intrinsic domain diagnostics take precedence over
  capability diagnostics even when support is unavailable or the patch came
  from JSON;
- malformed or range-invalid authored specular/IOR data invalidates only its
  extension group, preserving a valid sibling group and the separately applied
  core material;
- malformed or range-invalid IOR on an otherwise valid transmission/volume
  material removes only IOR from that group. Transmission, thickness, and
  attenuation intent remain preserved so the renderer's absent-IOR default can
  apply; invalid transmission or volume data still invalidates its own group;
- IOR `0` and ordinary opaque IOR do not route into glass or trigger a PBR
  family replacement;
- current policy support keeps specular unavailable, maturity
  `diagnosticOnly`, and every target evidence row `notRun`. Renderer-native
  scalar specular still returns `rendererNativeSpecularContractMissing`, and
  specular texture bindings return
  `rendererNativeExtensionTextureContractMissing` before loading or mutation.
- the real adapter boundary rejects package-local/non-native specular and
  opaque-IOR intent with `pinnedStandardPbrSpecularContractMissing` or
  `pinnedStandardPbrOpaqueIorContractMissing` before texture loading,
  material mutation, controller persistence, or render requests. This does not
  disable candidate transmissive IOR, and an actual renderer-native material
  contract retains its opaque-IOR application path.

At the time of this audit, actual texture channel/color-space sampling,
factor-times-texture behavior,
dielectric energy conservation, metal isolation, and visible opaque-IOR BRDF
trends remain `blocked` on a first-class upstream renderer contract. A skipped
acceptance test records that exact blocker without pretending wrapper parsing
is rendering evidence. A1B32 visual/runtime evidence, iOS Simulator rendering,
physical iOS, Android material rendering, and Web material rendering are
`not run`. Runtime support remains unavailable/diagnostic-only; no release
maturity or `production-ready` claim changed.

The 2026-07-14 amendment above supersedes this conclusion for the bounded
package-local extended path, but not for renderer-native or release capability.

## 2026-07-13 pinned clearcoat audit

This audit uses ratified Khronos `KHR_materials_clearcoat` for semantics,
Filament only for second-lobe/energy audit direction, and pinned
`flutter_scene` revision `cd6760912fa38beb55f63e388655a1aeabd32fe4` for
renderer capability.

Khronos requires clearcoat factor multiplied by the factor texture's red
channel, roughness multiplied by the roughness texture's green channel, and an
independent tangent-space coat normal. The coat lobe attenuates the base by its
Fresnel weight; the coat normal affects the top layer, not the base material.
The pinned standard PBR material/importer/shader exposes no first-class
clearcoat fields, texture slots, importer mapping, or integrated second-lobe
contract.

The package-local candidate was re-audited against the pinned `.fmat` emitter:

- the first source-only audit missed that every lit `.fmat` appends
  `EvaluateLighting(material)` after its authored `Surface`; a manual coat
  lobe routed through emissive therefore double-counted direct and IBL
  lighting even after an older heuristic highlight was removed;
- the candidate now authors no BRDF, direct-light, IBL, shadow, Fresnel-lobe,
  or coat-emissive lighting. A CPU test compiles the material through pinned
  `flutter_scene` and verifies exactly one engine `EvaluateLighting(material)`
  call. Coat roughness, independent coat normal, and occlusion feed that engine
  lighting path; factor and roughness textures still use red and green;
- the old backend nulled the retained source PBR normal and attenuated its
  scale while positive clearcoat was active. That suppression and restore
  state are removed. The base primitive retains its latest successful normal
  texture and scale, while the overlay uses only the independent coat normal;
- the alpha-blended `.fmat` has fixed back-face culling and cannot preserve a
  double-sided source PBR contract. Such requests return typed
  `packageLocalClearcoatDoubleSidedCullingContractMissing` diagnostics before
  shader creation, material mutation, state persistence, or overlay creation;
- source-over alpha also couples visible coat-lobe energy to base attenuation,
  so the overlay cannot independently express the Khronos Fresnel weighting.
  This is an exact non-conformance blocker, not a threshold-tuning problem.

The bounded candidate remains `candidate-only`. The CPU audit is verified
locally; 12 GPU/Impeller tests, post-change Khronos sample captures, iOS
Simulator recapture, physical iOS, Android material rendering, Web material
rendering, packaging, and release evidence are `not run`. Renderer-native
clearcoat is deferred in
[`015_renderer_native_clearcoat.md`](../exec-plans/deferred/015_renderer_native_clearcoat.md),
and the v1 clearcoat release gate remains blocked.

## 2026-07-13 pinned transmission and volume audit

This audit uses ratified Khronos `KHR_materials_transmission`,
`KHR_materials_volume`, and `KHR_materials_ior` for semantics and pinned
`flutter_scene` revision `cd6760912fa38beb55f63e388655a1aeabd32fe4` for
renderer capability. Filament was consulted only as a real-time shading
reference and is not evidence of this backend's support.

Khronos requires transmission factor multiplied by the transmission texture's
linear red channel, while optical transmission remains separate from alpha-as-
coverage. A zero-thickness surface is thin-walled and has no macroscopic
refraction. Positive volume uses thickness factor multiplied by the thickness
texture's green channel, interprets thickness in mesh space under node
transforms, and applies attenuation distance in world space. Metallic response
does not transmit, and the exact `ior == 0` compatibility mode has effective
infinite IOR/Fresnel one.

The pinned standard PBR material, importer, surface inputs, lighting shader,
and standard fragment expose no first-class transmission, volume thickness,
attenuation, or variable-IOR fields. Its render graph can publish scene color,
but the standard material path does not consume that target for glTF
transmission/refraction. The wrapper therefore cannot infer renderer-native
support from the render texture API alone.

The package-local candidate was re-audited against that boundary:

- source/compiler tests verify transmission uses red, thickness uses green,
  zero thickness produces zero refraction offset, and source alpha remains
  independent; the pinned unlit `.fmat` emitter performs the final
  premultiplication exactly once;
- authored contour/rim, key/fill, glint, source-detail, arbitrary alpha caps,
  roughness-driven base-color blending, synthetic reflection tint, HDR output
  clamping, and the nonzero attenuation-color floor were removed;
- an effective transmission factor of zero bypasses the extension path. It
  skips transmission/thickness binding validation and decoding, restores any
  active candidate only after core texture loads succeed, and applies combined
  base/normal/roughness intent through the ordinary PBR path. Failed core loads
  preserve the active candidate atomically;
- a positive-factor runtime transmission texture returns typed
  `packageLocalTransmissionTextureBasePbrContractMissing` before decode or
  mutation because an unlit whole-material replacement cannot preserve the lit
  base response at zero-valued texels;
- every positive thickness returns typed
  `packageLocalVolumeTransformContractMissing` before decode or mutation
  because node/world scale, closed-volume boundaries, and entry/exit transport
  do not reach the candidate shader;
- valid `ior == 0` returns typed
  `packageLocalIorZeroCompatibilityContractMissing` instead of being coerced,
  and factor-zero IOR intent retains the pinned opaque-IOR diagnostic boundary;
- missing scene-view collections are diagnosed before texture decoding for
  both initial candidate application and active factor-zero reset. Backend
  preflight and later guards remain defense in depth.

Independent review approved the bounded CPU-safe slice after three RED-first
adapter/backend remediation cycles. The final exact Task 9 suite passed 110
tests with 13 explicit GPU/Impeller, shader-bundle, visual, or renderer skips.
Those skips, WaterBottle/GlassVase captures, opaque-behind-glass trends, iOS
Simulator, physical iOS, Android material rendering, Web material rendering,
packaging, and release evidence remain `not run`.

Only scalar factor-driven thin screen-space compositing remains
`candidate-only`. It is not renderer-owned reflection/transmission transport,
positive volume, nested glass, order-independent transparency, or a general
PBR renderer. Renderer-native work is deferred in
[`016_renderer_native_transmission_volume.md`](../exec-plans/deferred/016_renderer_native_transmission_volume.md),
and the v1 glass release gate remains blocked.

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
diagnostic-only by default, and the viewer does not pretend upstream
`flutter_scene` exposes native extension fields. Task 012 accepts the
repo-owned custom shader backend as a package-local candidate: the
source-compatible `productionShaders()` policy can route opted-in glass and
clearcoat intent through package-local custom shader paths after shader
preflight. Preflight proves availability and routing only; it does not establish
Khronos correctness, target evidence, or physical-device release readiness.
The candidate maturity and target evidence fields are separate. Historical iOS
Simulator evidence is `verified locally`, while the static policy records
evidence as `not run` and claims no release target. Upstream renderer/importer
support remains a future PR path.

## 2026-07-03 `.fmat` packaging smoke

Task 7 added `assets/materials/fsviewer_debug_tint.fmat` and
`hook/build.dart` with `buildMaterials(...)` for the debug tint material.
Local non-GPU verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart
```

Result: passed with 1 GPU-gated skip. The skip is expected unless
`FLUTTER_SCENE_GPU_TESTS=true`, Impeller, Flutter GPU, and build-hook
generated `.fmat` DataAssets are available.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Initial result before the local config fix: failed.
`flutter_scene.loadFmatMaterial` failed with
`No DataAssets-backed .fmat material for source
"assets/materials/fsviewer_debug_tint.fmat" was found`. `flutter config
--list` reported `enable-dart-data-assets: (Not set)`.

Follow-up: Dart DataAssets were enabled with:

```sh
flutter config --enable-dart-data-assets
```

The hook then generated:

- `build/shaderbundles/materials.shaderbundle`
- `build/shaderbundles/materials.fmat.json`
- `build/shaderbundles/materials.index.json`

`flutter test` still did not expose the generated DataAssets index through the
unit-test root asset manifest, so the smoke was switched to the documented
`PreprocessedMaterial` shaderbundle + sidecar path and the generated
shaderbundle/sidecar were listed as test assets. Local GPU-gated verification
then passed:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 test. This proves minimal `.fmat` shader build/load evidence.
It is shader availability/routing evidence, not production glass support.
Later iOS Simulator real-asset/reference runs are durable evidence `verified
locally`, but the repo-owned custom shader backend remains `candidate-only`.

## 2026-07-03 experimental transmission backend smoke

Task 8 added `assets/materials/fsviewer_transmission.fmat` and the internal
`FlutterSceneMaterialExtensionBackend`. The backend uses public
`flutter_scene` APIs: `ShaderMaterial`, `RenderTexture`, `RenderView.layerMask`,
and `Node.layers`. Supported experimental transmission patches are routed into
a separate shader-material path with `isOpaqueOverride = false`; alpha blend is
not used as a glass fallback.

Local CPU verification ran:

```sh
flutter test test/flutter_scene_adapter_material_test.dart test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 6 tests with 3 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 8 tests with 2 visual-smoke skips. This proves that the debug
tint, transmission, and clearcoat `.fmat` shaders compile into the generated
shader bundle, that `FSViewerTransmission` and `FSViewerClearcoat` load, and
that CPU state transitions assign a transmissive layer, background render view,
background render texture, non-opaque glass `ShaderMaterial`, and opaque
clearcoat `ShaderMaterial`; it also verifies mounted render items are refreshed
when the backend replaces or restores the primitive material.

Task 8 visual evidence was verified locally with:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_transmission_smoke.png`. The screenshot shows a
striped-behind-glass fixture through the experimental transmission shader; the
test asserts channel spread plus red/green/blue dominant samples so the evidence
does not rely on alpha alone. During debugging, the root issue was a mounted
render-layer refresh bug in the viewer backend: replacing
`MeshPrimitive.material` after mount did not update `flutter_scene`'s retained
`RenderItem.material` until the node mesh wrapper was refreshed. A direct
`Scene.render` / `PictureRecorder` capture is used for the smoke because local
`SceneView` widget teardown hung after producing the screenshot.

## 2026-07-03 experimental clearcoat backend smoke

Task 9 added `assets/materials/fsviewer_clearcoat.fmat` and extended the
internal `FlutterSceneMaterialExtensionBackend`. The backend uses public
`flutter_scene` APIs: `ShaderMaterial`, generated shader bundles, and
`ShaderMaterial.useEnvironment = true` for environment IBL bindings. Supported
experimental clearcoat patches are routed into an opaque shader-material path;
lowering base roughness is not used as a clearcoat fallback.

Local CPU verification ran:

```sh
flutter test test/material_extension_policy_test.dart test/flutter_scene_adapter_material_test.dart test/viewer_controller_material_test.dart test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 38 tests with 4 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --enable-impeller --enable-flutter-gpu
```

Result: passed 8 tests with 2 visual-smoke skips. This proves that
`FSViewerClearcoat` compiles into the generated shader bundle, loads through
`loadShaderLibraryAsync`, and is configured as an opaque environment-using
`ShaderMaterial`.

Task 9 visual evidence was verified locally with:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "clearcoat shader renders distinct second specular lobe smoke" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_clearcoat_smoke.png`. The screenshot compares a base glossy
sphere, clearcoat `0.0`, and clearcoat `1.0` with low clearcoat roughness. The
test masks out background pixels and verifies that the clearcoat `1.0` object
has a stronger object highlight than clearcoat `0.0`, so the evidence does not
come from a skybox/background sample.

## 2026-07-03 production glass visual matrix candidate

Task 011 added a GPU-gated glass visual matrix for the package-local
transmission shader. The matrix renders transmission `0.0`, `0.5`, and `1.0`
against the same striped background and compares IOR `1.0` with a higher IOR
scene using trend metrics rather than pixel-perfect equality.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production glass visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_glass_matrix.png`. This is local host visual evidence for
the package-local shader behavior. iOS Simulator evidence is recorded
separately; Task 012 uses that evidence plus acceptance metrics for the
`flutterSceneCustomShader` candidate scope.

## 2026-07-03 production clearcoat visual matrix candidate

Task 011 upgraded `FSViewerClearcoat` to a lit `.fmat` material. Follow-up
visual-quality hardening changed it from an opaque replacement material into a
translucent shared-geometry overlay that preserves the source primitive's PBR
material and adds a separate clearcoat lobe through `material.emissive`. The
runtime path loads the shader and sidecar metadata into
`PreprocessedMaterial`; direct `ShaderMaterial` rendering of a lit `.fmat`
shader crashed the local Flutter tester because the lit engine uniform block is
not bound by that wrapper.

Local non-GPU verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart
```

Result: passed 11 tests with 8 GPU-gated skips.

Local GPU-gated verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "production clearcoat visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote
`tools/out/fsviewer_clearcoat_matrix.png`. The matrix verifies clearcoat
factor, clearcoat roughness, clearcoat texture influence, and clearcoat normal
trends on the local host GPU path. This is still local host candidate evidence;
iOS Simulator evidence is recorded separately as `verified locally` for the
`candidate-only` `backendKind: flutterSceneCustomShader` path.

## 2026-07-04 ToyCar iOS Simulator real-asset evidence

Follow-up visual-quality hardening used the Khronos ToyCar GLB because the same
asset has authored clearcoat and transmission materials. The backend applies
clearcoat to the ToyCar body through the translucent overlay path and applies
transmission to the authored `Glass` node. This validates that the source PBR
body material remains visible while the custom shader glass path is active in
the same diagonal real-asset view.

Actual iOS Simulator verification ran through the temporary
`/private/tmp/fsviewer_ios_evidence_app` integration test:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator and wrote
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_baseline.png`,
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_enhanced.png`,
`tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_side_by_side.png`,
and `tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json`. Metrics:
frame delta `0.8378311471193416`, color spread `249`, highlight `248`.
Task 011 recorded this as candidate evidence; Task 012 supersedes that status
with additional acceptance metrics but not with physical-device or release
evidence. The maturity remains `candidate-only` and the simulator evidence is
`verified locally`.

## 2026-07-03 shared GLB and three.js reference fixture candidate

Task 011 added a shared material-extension GLB and a three.js reference
renderer harness. Flutter visual smoke writes
`tools/out/fsviewer_material_extension_reference_fixture.glb` alongside the
Flutter glass and clearcoat matrix screenshots. The reference harness loads the
same GLB through three.js `GLTFLoader` and records trend metrics in
`tools/out/material_extension_reference_metrics.json`.

Local Flutter fixture generation ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "shared GLB for reference renderers" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed 1 focused visual-smoke test and wrote the shared GLB plus
Flutter matrix image paths.

Local three.js reference verification ran:

```sh
npm install --prefix tools/reference_renderers/threejs_material_extension_fixture
npm run render --prefix tools/reference_renderers/threejs_material_extension_fixture
```

Result: install passed with no vulnerabilities; render passed and wrote
`tools/out/reference_threejs_glass_matrix.png`,
`tools/out/reference_threejs_clearcoat_matrix.png`, and
`tools/out/material_extension_reference_metrics.json`. Metrics recorded
three.js transmission spread increasing from `24` to `37`, IOR delta
`32.43768240567021`, clearcoat highlight increasing from `242` to `244`, and
rough clearcoat peak `242` below smooth peak `244`.

## 2026-07-03 iOS Simulator candidate evidence status

The package-level focused test was run locally and still skipped because it
executes in the host Flutter tester:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: skipped with `iOS Simulator evidence requires an iOS test target;
current target is android.`

Actual iOS Simulator evidence was then collected with a temporary Flutter
`integration_test` app depending on this package by path:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator and wrote
`tools/out/fsviewer_ios_simulator_glass_matrix.png`,
`tools/out/fsviewer_ios_simulator_clearcoat_matrix.png`, and
`tools/out/fsviewer_ios_simulator_material_extension_matrix.json`.
Recorded iOS Simulator metrics: glass transmission spread increased from `14`
to `239`, IOR delta was `5.111805555555556`, clearcoat highlight increased
from `242` to `254`, and rough clearcoat peak `250` stayed below smooth peak
`254`.

Follow-up real-asset review initially kept the package-local glass and
clearcoat paths as candidate visuals. Task 012 added acceptance evidence, but
the repo-owned custom shader backend remains `candidate-only`; the iOS
Simulator record is `verified locally`.

Physical iOS, Android material rendering, and Web material rendering remain
`not run`.

## 2026-07-04 transmission shader source hardening

Task 012 reviewed public renderer material models before promoting the
repo-owned custom shader route. Filament's PBR/material documentation supports
the same direction used for glass: separate surface reflection from transmitted
energy through IOR/Fresnel behavior, and treat transparent-surface blending as
premultiplied output. SceneKit's public SDK headers do not expose a
`KHR_materials_transmission` equivalent material field, but they do expose
transparent material/blend controls, shader-surface `view`, `normal`,
`transparent`, and `fresnel` fields, and clearcoat surface fields. SceneKit is
therefore useful as a public surface-shader reference, not as a native
transmission backend.

`assets/materials/fsviewer_transmission.fmat` now derives normal-incidence
reflectance from IOR, computes a `TransmissionViewFresnel` term, reduces
transmitted background energy by that Fresnel term, applies
`BeerLambertAttenuation` as `attenuationColor^(thickness /
attenuationDistance)`, and writes premultiplied RGB through
`PremultipliedTransmissionColor`. This remains bounded screen-space glass, not
path-traced volume transport or order-independent transparency.

Focused verification ran:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "separates Fresnel"
```

Result: the first non-escalated run failed because Flutter tried to write SDK
cache files outside the workspace. The escalated red run failed as expected
because the transmission shader did not yet contain the Fresnel/absorption
helpers. After the shader update, the focused test passed.
