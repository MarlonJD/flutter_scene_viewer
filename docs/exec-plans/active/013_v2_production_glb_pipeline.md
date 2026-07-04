# Exec plan: V2 production GLB pipeline

## Goal

Make the viewer production-load real V2 GLB configurator assets without manual
preprocessing by adding compression, texture-role, material-extension, and
diagnostic support around the `flutter_scene` runtime importer.

## Assumptions

- Work stays on the current branch because the user explicitly said not to
  create or switch branches.
- `flutter_scene` upstream `master` is pinned in `pubspec.yaml` at
  `cd6760912fa38beb55f63e388655a1aeabd32fe4`. The July 4 upstream audit found
  this is the current `master` head and that it adds runtime importer
  background primitive packing, `Scene.warmUp`, and loading-gate work.
- The pinned upstream has public `Texture2D` role-aware mipmap support for
  color, normal, and data content, plus internal KTX2 support for `.fscene`
  resources. Its runtime glTF importer still does not parse
  `KHR_draco_mesh_compression`, `EXT_meshopt_compression`,
  `KHR_texture_basisu`, `KHR_materials_specular`, or `KHR_materials_ior`.
- A1B32 at `/Users/marlonjd/Downloads/A1B32.glb` is a required V2 gate. Local
  inspection found one node, one mesh, 20 primitives, 20 materials, 24 textures,
  17 images, `KHR_draco_mesh_compression` in `extensionsRequired`, Draco on all
  20 primitives, and `KHR_materials_specular` plus `KHR_materials_ior` on all
  20 materials. A repeated local inspection found no `KHR_texture_basisu`
  textures and no KTX2 images in A1B32; KTX2/BasisU remains required for
  Khronos sample coverage, not for this specific asset.
- Until a real Draco, meshopt, or BasisU/KTX2 glTF decoder path is present, the
  viewer must report typed diagnostics and must not silently pass unsupported
  required-compressed assets into `flutter_scene`.
- The renderer direction remains Flutter GPU plus `flutter_scene`. The user
  explicitly does not want a Filament backend for this package; local shader
  work must stay targeted and upstream-compatible with `flutter_scene`.

## Non-goals

- No custom renderer or shader graph.
- No Filament backend.
- No CAD tessellation, mesh repair, UV generation, or texture baking.
- No fake decompression, placeholder geometry, alpha-only glass, or
  low-roughness clearcoat claims.
- No broad branch, package, or dependency churn unrelated to the active V2
  slice.

## Steps

1. Change: Add a bounded GLB capability preflight reader that extracts
   required/used extensions, compressed primitive counts, meshopt bufferView
   counts, KTX2/BasisU texture counts, material extension counts, texture-slot
   roles, UV requirements, and source statistics.
   Verify: focused tests cover A1B32-style Draco/specular/IOR metadata,
   meshopt, KTX2/BasisU, texture roles, invalid GLB headers, and bounded JSON.
2. Change: Wire the preflight into `ModelLoader` before adapter import so
   missing required decoders produce actionable diagnostics instead of adapter
   failures or silent placeholders.
   Verify: loader tests prove required Draco fails loudly when no decoder is
   available, optional meshopt/KTX2 produces diagnostics without crashing, and
   uncompressed fixtures keep loading.
3. Change: Preserve imported `KHR_materials_specular` and non-glass
   `KHR_materials_ior` as explicit authored material intent or capability
   diagnostics.
   Verify: tests prove A1B32-style material extension data is reported per
   material/part and unsupported renderer fields do not collapse silently to
   ordinary metallic-roughness.
4. Change: Rebuild imported GLB texture sources role-aware where the current
   `flutter_scene` importer exposes enough public hooks; otherwise emit an
   upstream-capability diagnostic naming the unsupported role.
   Verify: tests cover base color/emissive as color, normal/clearcoat normal as
   normal, and metallic-roughness/occlusion/specular/transmission/clearcoat
   maps as data.
5. Change: Add real decoder integration for Draco, meshopt, and glTF
   KTX2/BasisU only through an upstream-compatible `flutter_scene` adapter or a
   vetted decoder dependency.
   Verify: A1B32 imports, preserves hierarchy/primitive addresses, renders and
   picks in iOS Simulator, and compressed Khronos samples match diagnostics and
   visual expectations.
6. Change: Update public docs, capability matrix, and acceptance tooling for
   the verified V2 scope.
   Verify: `python3 tools/repo_lint.py`, `bash tools/run_checks.sh`, targeted
   Flutter tests, and iOS Simulator evidence for A1B32, CarConcept,
   WaterBottle, and Khronos clearcoat/glass samples.

## Acceptance criteria

- [x] Required decoder support is detected before adapter import and missing
      support produces typed diagnostics.
- [x] A1B32 loads without manual preprocessing once real Draco support is
      available.
- [x] A1B32 Draco primitives render, pick, and appear in hierarchy/diagnostics
      correctly.
- [x] `EXT_meshopt_compression` is supported or reports one typed unsupported
      decoder diagnostic without crashing.
- [x] KTX2 / `KHR_texture_basisu` is supported for glTF texture slots or
      reports one typed unsupported decoder diagnostic without fake support.
      Verified behavior includes header-aware diagnostics, a root-side optional
      native transcoder contract, GLB image rewrite, and a sibling
      `flutter_scene_viewer_basisu` plugin that vendors Basis Universal plus
      Zstd and transcodes GLB-embedded KTX2 to PNG for Dart-side rewrite.
      iOS Simulator evidence for a full KTX2 sample remains part of the final
      visual validation pass.
- [x] Imported texture roles drive correct color, normal, and data mipmap
      behavior where supported.
- [x] `KHR_materials_clearcoat`, `KHR_materials_transmission`,
      `KHR_materials_ior`, and `KHR_materials_specular` are preserved or mapped
      with explicit capability diagnostics.
- [x] Existing core glTF PBR overrides keep passing.
- [x] iOS Simulator visual evidence covers A1B32, CarConcept, WaterBottle, and
      Khronos clearcoat/glass samples.
- [x] Public API, docs, generated capability matrix, and tests are updated.

## Progress log

- 2026-07-04: Created the active V2 production GLB pipeline plan from the
  deferred V2 configurator polish plan and the user's full V2 acceptance
  request. Assumption recorded: work stays on current `main` because branch
  operations were explicitly disallowed. Upstream `flutter_scene` audit found
  `master` currently equals the pinned `cd6760912fa38beb55f63e388655a1aeabd32fe4`
  commit; useful additions are runtime importer background primitive packing,
  `Scene.warmUp`, loading gates, role-aware public `Texture2D` mips, and
  internal `.fscene` KTX2 resources. Runtime glTF import still lacks Draco,
  meshopt, `KHR_texture_basisu`, specular, and IOR parsing. A1B32 inspection
  found required Draco on all 20 primitives plus specular/IOR on all 20
  materials.
- 2026-07-04: Implemented the first diagnostic preflight slice. Added
  `glb_capability_reader.dart` with bounded GLB JSON parsing, required/used
  extension extraction, compressed primitive counts, meshopt bufferView counts,
  `KHR_texture_basisu` texture counts, material extension counts, and imported
  texture-slot role classification for color, normal, and data slots including
  specular, transmission, and clearcoat textures. Added
  `ViewerDiagnosticCode.unsupportedModelFeature` and wired `ModelLoader` so a
  required compressed asset reports a typed missing-decoder diagnostic before
  calling the `flutter_scene` adapter. This does not add Draco decode yet; it
  prevents silent fallback or generic adapter failures while the decoder path is
  selected.
- 2026-07-04: Added the optional native Draco decoder integration contract
  without converting the root package into a platform plugin. `ModelLoader`
  now probes the optional `flutter_scene_viewer_draco` MethodChannel when a
  required Draco asset is detected. Missing plugin, disabled platform opt-in,
  and unlinked native decoder states are surfaced as actionable
  `unsupportedModelFeature` diagnostics before adapter import. Added the
  sibling `packages/flutter_scene_viewer_draco` plugin scaffold with iOS
  ObjC++ and Android JNI/CMake bridge files. The bridge currently reports the
  C++ decoder as unlinked until real Draco sources/libraries are vendored; it
  does not fake decode support.
- 2026-07-04: Preserved imported `KHR_materials_specular` intent in the
  authored material extension path. Added serializable `MaterialPatch`
  specular fields for scalar strength, scalar texture, RGB color factor, and
  RGB color texture; added default unsupported diagnostics unless a backend
  explicitly advertises `MaterialExtensionSupport.specular`; and mapped
  `KHR_materials_specular` fields from bounded GLB JSON to authored material
  patches. This keeps A1B32-style `specularColorFactor` plus
  `KHR_materials_ior` intent visible without pretending the current renderer
  can render specular extension fields.
- 2026-07-04: Added imported texture UV-set preflight diagnostics. The GLB
  capability reader now preserves each textureInfo `texCoord` value, defaults
  absent textureInfo coordinates to UV0, and checks every primitive/material
  pairing that uses an imported texture slot. Missing UV sets now emit
  `missingUvSet` diagnostics with source, mesh index, primitive index,
  material index, UV set, and the affected texture slots. Draco primitive
  extension attributes are accepted as UV evidence so required-compressed
  assets do not get false-positive UV diagnostics before decode.
- 2026-07-04: Extended the optional native Draco contract from
  availability-only to pre-import GLB rewrite. `ModelLoader` now calls the
  optional native decoder when native capabilities are the reason a required
  Draco asset can proceed, sends the returned GLB bytes to the adapter, and
  re-runs capability preflight on those bytes so compressed geometry cannot
  silently pass through. The sibling plugin now exposes a `decodeGlb`
  MethodChannel method on Dart, iOS, and Android; current platform stubs return
  diagnostics and no fake geometry until real Google Draco decode plus GLB
  rewrite are implemented.
- 2026-07-04: Recorded the renderer direction decision: this package stays on
  Flutter GPU plus `flutter_scene`; the active plan explicitly excludes a
  Filament backend. Added a V3 roadmap research lane for Flutter GPU /
  `flutter_scene` material-rendering experiments, including path/ray-tracing
  reference work only as bounded validation research rather than a default
  interactive renderer.
- 2026-07-04: Added non-blocking diagnostics for unsupported optional
  compression extensions. Draco primitives, meshopt-compressed bufferViews, and
  BasisU/KTX2 texture slots now report `unsupportedModelFeature` with
  `required: false` when the extension is present in `extensionsUsed` but not
  `extensionsRequired`. Loader blocking still only uses `required: true`, so
  optional fallback assets can import while surfacing actionable capability
  diagnostics.
- 2026-07-04: Added the first role-aware imported texture reapply path for
  core GLB PBR textures. A new GLB imported texture patch reader extracts
  bufferView-backed image bytes for base color, metallic-roughness, normal,
  occlusion, and emissive texture slots and maps them to `PartAddress`
  material patches. `ModelLoader` merges those patches with authored material
  extension patches, so the controller reapplies imported core textures through
  the existing `TextureContent`-aware adapter path after `flutter_scene` import
  without persisting them as user overrides. This does not solve external image
  URI or KTX2/BasisU transcode yet.
- 2026-07-04: Replaced authored material-extension texture placeholders with
  real GLB bufferView-backed image bytes where available. The material
  extension reader now carries the BIN chunk, resolves textureInfo indices
  through textures/images/bufferViews, preserves clearcoat normal scale, and
  reports unsupported KTX2/BasisU extension texture sources instead of
  manufacturing empty texture bytes. This keeps extension texture intent
  role-aware for the existing adapter path while leaving KTX2 transcode as
  explicit decoder work.
- 2026-07-04: Added non-zero `textureInfo.texCoord` diagnostics for imported
  texture patching. Core PBR and material-extension texture readers now refuse
  to create runtime patches for UV1+ texture slots because the current
  `flutter_scene` override path binds UV0 only. These paths report
  `unsupportedModelFeature` with the slot/field and requested UV set instead of
  silently applying the texture with the wrong coordinates.
- 2026-07-04: Tightened core imported texture diagnostics for
  `KHR_texture_basisu`. Core PBR texture patching now reports
  `requiredExtension: KHR_texture_basisu` for BasisU texture references or KTX2
  images instead of a generic missing-image-source diagnostic. This remains
  diagnostic-only until a real KTX2/BasisU transcode path is wired.
- 2026-07-04: Added a testable Dart GLB rewrite path for native Draco decoded
  primitive payloads. The new rewriter appends decoded attribute/index bytes as
  GLB bufferViews, binds the existing glTF accessors, removes per-primitive
  `KHR_draco_mesh_compression`, and clears top-level Draco used/required
  declarations only when no compressed primitives remain. The MethodChannel
  decoder probe now accepts either fully rewritten `bytes` or structured
  `decodedPrimitives`, so the optional C++ plugin can focus on real Google
  Draco primitive decode while Dart owns JSON/BIN rewrite and preflight.
- 2026-07-04: Added decoded Draco payload size validation to the Dart GLB
  rewriter. Attribute and index payloads are checked against the referenced
  accessor `componentType`, `type`, and `count`; mismatches produce
  `unsupportedModelFeature` rewrite diagnostics instead of binding malformed
  native decoder output to glTF accessors.
- 2026-07-04: Tightened the Dart Draco rewrite contract so native decoded
  primitive output must include every compressed attribute declared by the
  Draco extension and decoded index bytes when the primitive references an
  index accessor. Missing payloads now produce rewrite diagnostics instead of
  emitting partial importer-ready GLB bytes.
- 2026-07-04: Added a Dart-built `dracoPrimitives` manifest to the optional
  native decode request. Each entry carries compressed bufferView bytes, Draco
  attribute ids, target accessor schemas, mesh index, and primitive index so
  the sibling plugin's C++ layer can focus on Google Draco primitive decode
  instead of owning a full glTF JSON parser. The root still owns GLB rewrite
  and post-decode capability preflight.
- 2026-07-04: Vendored Google Draco 1.5.7 source into the optional sibling
  plugin and wired decoder-only source sets into Android CMake and the iOS
  podspec. The bridge now distinguishes "Draco source linked" from "primitive
  decode implemented"; capabilities remain false and required assets receive
  `decodeUnavailable` until the C++ bridge maps decoded Draco meshes into
  `decodedPrimitives`.
- 2026-07-04: Added a candidate iOS Google Draco primitive decode bridge. The
  ObjC++ plugin parses the Dart `dracoPrimitives` manifest, calls the C++
  bridge, and returns structured `decodedPrimitives` for Dart-side GLB rewrite.
  The C++ bridge decodes triangular mesh payloads, extracts attributes by
  Draco unique id, writes attribute bytes according to target accessor schema,
  writes index bytes according to the index accessor component type, and
  reports typed diagnostics for malformed payloads. This remains
  `candidate-only` until CocoaPods/Xcode native build and A1B32 Simulator
  evidence are captured. Android JNI primitive decode remains pending.
- 2026-07-04: Added the matching Android C++ Draco primitive decode bridge
  symbol and implementation. Android still does not advertise decode
  capability because Java/JNI result marshaling to MethodChannel
  `decodedPrimitives` is not wired yet; required assets therefore keep failing
  loudly instead of receiving fake geometry.
- 2026-07-04: Wired Android JNI result marshaling for the optional Draco
  sibling plugin. The Java MethodChannel handler now calls a native
  `nativeDecodePrimitives` entrypoint when the app opt-in, native library, and
  primitive decode bridge are available. JNI converts the Dart
  `dracoPrimitives` List/Map/byte arrays into C++ requests and returns
  MethodChannel-compatible `decodedPrimitives` plus typed diagnostics. Native
  Android app build verification remains pending because the local Android SDK
  is unavailable.
- 2026-07-04: Re-checked the `/private/tmp/fsviewer_ios_evidence_app`
  evidence app. The app and A1B32 asset still exist and `FLTEnableFlutterGPU`
  is enabled, but the app has no Podfile, does not include the optional Draco
  sibling plugin, does not set `FlutterSceneViewerDracoEnabled`, and does not
  expose A1B32 in the model selector. CocoaPods is also unavailable locally, so
  native iOS evidence remains blocked until the app can be regenerated with the
  plugin dependency and CocoaPods installed.
- 2026-07-04: Unblocked local iOS evidence. Installed CocoaPods 1.15.2
  user-locally with Ruby 2.6-compatible gem pins and ran it with
  `RUBYOPT=-rlogger`. Updated the temporary evidence app with the optional
  Draco sibling plugin dependency, a standard Flutter Podfile,
  `FlutterSceneViewerDracoEnabled`, A1B32 in the model selector, and a
  dart-define initial-model selector for repeatable screenshots. Fixed the iOS
  plugin podspec so only the Objective-C plugin header is public, added a
  CocoaPods-visible Draco vendor source aggregator, and changed the package
  material build hook to use `MaterialAssetMode.dataAssetsIfAvailable` so the
  existing listed legacy shaderbundle assets work when the current build hook
  input lacks Dart data asset support.
- 2026-07-04: Core imported `KHR_texture_basisu` / KTX2 texture diagnostics now
  inspect the referenced GLB image bufferView when available and include KTX2
  header details such as `vkFormat`, `levelCount`, and
  `supercompression: basisLz` alongside the explicit
  `basisuTranscodeUnavailable` status. This remains diagnostic-only; no
  unsupported BasisU texture is handed to `flutter_scene`.
- 2026-07-04: Authored material-extension texture diagnostics now use the same
  KTX2 header detail path for `KHR_texture_basisu` sources, so specular,
  transmission, clearcoat, and other extension texture slots fail loudly with
  the unsupported transcode reason and concrete container metadata.
- 2026-07-04: Capability preflight now keeps the GLB BIN chunk long enough to
  inspect `KHR_texture_basisu` image bufferViews and attach bounded KTX2 header
  summaries to the unsupported BasisU decoder diagnostic before adapter import.

## Verification log

- 2026-07-04: verified red for GLB capability reader:
  `flutter test test/glb_capability_reader_test.dart` failed because
  `glb_capability_reader.dart`, `GlbDecoderCapabilities`,
  `GlbAssetCapabilityResult`, `GlbTextureRole`, and
  `ViewerDiagnosticCode.unsupportedModelFeature` did not exist.
- 2026-07-04: verified locally for GLB capability reader:
  `flutter test test/glb_capability_reader_test.dart` passed 5 tests after
  adding bounded preflight metadata and texture-role classification.
- 2026-07-04: verified red for ModelLoader decoder preflight:
  `flutter test test/model_loader_test.dart --plain-name Draco` failed because
  `ModelLoaderOptions.decoderCapabilities` did not exist.
- 2026-07-04: verified locally for ModelLoader decoder preflight:
  `flutter test test/model_loader_test.dart --plain-name Draco` passed 2 tests
  after wiring required decoder diagnostics before adapter import.
- 2026-07-04: verified locally for focused Draco slice:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart
  --plain-name Draco` passed 4 tests.
- 2026-07-04: verified locally for the current preflight slice:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart`
  passed 18 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after formatting:
  `bash tools/run_checks.sh` passed. It ran repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and the full Flutter test suite. Full
  suite result: 221 passed, 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified locally for native Draco probe routing:
  `flutter test test/model_loader_test.dart --plain-name Draco` passed 4 tests.
- 2026-07-04: verified locally for preflight plus loader after optional plugin
  contract work:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart`
  passed 20 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally for the sibling plugin Dart surface:
  `flutter pub get` and `flutter analyze` passed in
  `packages/flutter_scene_viewer_draco`.
- 2026-07-04: verified locally after the optional native Draco plugin contract:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  223 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for specular intent preservation:
  `flutter test test/material_patch_test.dart test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart --plain-name specular` failed
  because `MaterialPatch.specular`, specular texture/color fields, and
  `MaterialExtensionSupport.specular` did not exist.
- 2026-07-04: verified locally for specular intent preservation:
  `flutter test test/material_patch_test.dart test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart --plain-name specular` passed
  3 tests after adding public patch intent and GLB material extension mapping.
- 2026-07-04: verified locally for related material suites:
  `flutter test test/material_patch_test.dart test/material_extension_policy_test.dart
  test/glb_material_extension_reader_test.dart` passed 35 tests.
- 2026-07-04: verified locally after specular intent preservation:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  226 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for imported texture UV preflight:
  `flutter test test/glb_capability_reader_test.dart --plain-name UV` failed
  because `GlbTextureSlot.texCoord` did not exist.
- 2026-07-04: verified locally for imported texture UV preflight:
  `flutter test test/glb_capability_reader_test.dart --plain-name UV` passed
  3 tests after adding textureInfo `texCoord` capture and primitive/material
  missing-UV diagnostics.
- 2026-07-04: verified locally for the GLB capability reader after UV
  diagnostics:
  `flutter test test/glb_capability_reader_test.dart` passed 8 tests.
- 2026-07-04: verified locally for preflight plus loader after imported UV
  diagnostics:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart`
  passed 23 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after imported UV diagnostics:
  `python3 tools/repo_lint.py` and `git diff --check` passed.
- 2026-07-04: verified locally after imported UV diagnostics:
  `bash tools/run_checks.sh` passed. It ran repo lint, Dart format check,
  `flutter pub get`, `flutter analyze`, and the full Flutter test suite. Full
  suite result: 229 passed, 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for native Draco GLB rewrite contract:
  `flutter test test/model_loader_test.dart --plain-name "uses native Draco capability probe"`
  failed because `GlbNativeDecodeResult` did not exist.
- 2026-07-04: verified locally for native Draco GLB rewrite contract:
  `flutter test test/model_loader_test.dart --plain-name "uses native Draco capability probe"`
  passed after `ModelLoader` started sending native-decoded GLB bytes to the
  adapter.
- 2026-07-04: verified red for sibling plugin decode surface:
  `flutter test test/flutter_scene_viewer_draco_test.dart` in
  `packages/flutter_scene_viewer_draco` failed because
  `FlutterSceneViewerDraco.decodeGlb` did not exist.
- 2026-07-04: verified locally for sibling plugin decode surface:
  `flutter test test/flutter_scene_viewer_draco_test.dart` in
  `packages/flutter_scene_viewer_draco` passed 1 test after adding the
  MethodChannel wrapper and platform method stubs.
- 2026-07-04: verified locally for preflight plus loader after native decode
  contract:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart`
  passed 23 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally for the sibling plugin after native decode
  contract:
  `flutter analyze` and `flutter test test/flutter_scene_viewer_draco_test.dart`
  passed in `packages/flutter_scene_viewer_draco`.
- 2026-07-04: verified locally after native decode contract:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  229 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for optional compression diagnostics:
  `flutter test test/glb_capability_reader_test.dart --plain-name optional`
  failed because unsupported optional Draco/meshopt/BasisU features produced no
  diagnostics.
- 2026-07-04: verified locally for optional compression diagnostics:
  `flutter test test/glb_capability_reader_test.dart --plain-name optional`
  passed 1 test; `flutter test test/glb_capability_reader_test.dart` passed
  9 tests; and
  `flutter test test/model_loader_test.dart --plain-name Draco` passed
  5 tests.
- 2026-07-04: verified locally after optional compression diagnostics:
  `flutter test test/glb_capability_reader_test.dart test/model_loader_test.dart`
  passed 25 tests with 3 existing GPU-gated skips; `python3 tools/repo_lint.py`,
  `git diff --check`, and `bash tools/run_checks.sh` passed. The root full
  Flutter test suite reported 231 passed with 13 existing
  GPU/build-hook-gated skips.
- 2026-07-04: verified red for imported core texture patch reader:
  `flutter test test/glb_imported_texture_patch_reader_test.dart` failed
  because `glb_imported_texture_patch_reader.dart` and
  `readGlbImportedTexturePatches` did not exist.
- 2026-07-04: verified locally for imported core texture patch reader:
  `flutter test test/glb_imported_texture_patch_reader_test.dart` passed
  1 test after extracting bufferView-backed core texture bytes into
  `MaterialPatch` intent.
- 2026-07-04: verified red for ModelLoader imported texture patch merge:
  `flutter test test/model_loader_test.dart --plain-name "imported core texture"`
  failed because `authoredMaterialPatches` did not include imported core
  texture patches.
- 2026-07-04: verified locally for ModelLoader imported texture patch merge:
  `flutter test test/model_loader_test.dart --plain-name "imported core texture"`
  passed 1 test, and
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/model_loader_test.dart`
  passed 25 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after imported core texture patch merge:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  233 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for authored extension texture byte extraction:
  `flutter test test/glb_material_extension_reader_test.dart --plain-name "extension texture"`
  failed because extension texture fields still returned empty byte
  placeholders.
- 2026-07-04: verified locally for authored extension texture byte extraction:
  `flutter test test/glb_material_extension_reader_test.dart --plain-name "extension texture"`
  passed after resolving textureInfo references to GLB image bufferView bytes
  and carrying clearcoat normal scale.
- 2026-07-04: verified locally for material extension reader after texture byte
  extraction:
  `flutter test test/glb_material_extension_reader_test.dart` passed 9 tests,
  including unsupported `KHR_texture_basisu` extension texture diagnostics.
- 2026-07-04: verified locally for targeted material/texture/loader suites:
  `flutter test test/glb_material_extension_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/model_loader_test.dart`
  passed 27 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after authored extension texture byte
  extraction: `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  235 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for non-zero imported texture texCoord diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart --plain-name "non-zero texCoord"`
  failed because core and authored extension texture patch readers still
  produced runtime patches for `textureInfo.texCoord: 1`.
- 2026-07-04: verified locally for non-zero imported texture texCoord
  diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart --plain-name "non-zero texCoord"`
  passed 2 tests after adding `unsupportedModelFeature` diagnostics and
  suppressing incorrect UV0 patches.
- 2026-07-04: verified locally for targeted reader/loader suites after
  non-zero texCoord diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/model_loader_test.dart`
  passed 29 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after non-zero texCoord diagnostics:
  `python3 tools/repo_lint.py` and `git diff --check` passed. The first
  `bash tools/run_checks.sh` attempt stopped on an analyzer import-order issue
  in `test/glb_imported_texture_patch_reader_test.dart`; after sorting imports,
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  237 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for core imported BasisU texture diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart --plain-name BasisU`
  failed because the diagnostic did not include `requiredExtension:
  KHR_texture_basisu`.
- 2026-07-04: verified locally for core imported BasisU texture diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart --plain-name BasisU`
  passed after adding explicit BasisU/KTX2 diagnostics.
- 2026-07-04: verified locally for targeted reader/loader suites after core
  BasisU diagnostics:
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/model_loader_test.dart`
  passed 30 tests with 3 existing GPU-gated skips.
- 2026-07-04: verified locally after core imported BasisU diagnostics:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  238 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for Dart Draco GLB rewrite:
  `flutter test test/glb_draco_rewriter_test.dart` failed because
  `glb_draco_rewriter.dart`, `GlbDecodedDracoPrimitive`, and
  `rewriteDracoCompressedGlb` did not exist.
- 2026-07-04: verified locally for Dart Draco GLB rewrite:
  `flutter test test/glb_draco_rewriter_test.dart` passed after appending
  decoded primitive payloads to GLB bufferViews, rebinding accessors, and
  removing Draco extension declarations from the rewritten GLB.
- 2026-07-04: verified red for native decoded primitive MethodChannel
  contract:
  `flutter test test/glb_native_decoder_probe_test.dart` failed because
  `decodeGlb` results without rewritten `bytes` were treated as decode
  failures even when `decodedPrimitives` were returned.
- 2026-07-04: verified locally for native decoded primitive MethodChannel
  contract:
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart`
  passed 2 tests after the probe started rewriting `decodedPrimitives` through
  the Dart GLB rewriter.
- 2026-07-04: verified locally for focused Draco tests after Dart rewrite
  contract:
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/glb_capability_reader_test.dart test/model_loader_test.dart --plain-name Draco`
  passed 10 tests.
- 2026-07-04: verified locally after Dart Draco rewrite/probe contract:
  `python3 tools/repo_lint.py`, `git diff --check`,
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/glb_capability_reader_test.dart test/model_loader_test.dart`,
  and `bash tools/run_checks.sh` passed. The root full Flutter test suite
  reported 240 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for decoded Draco payload size validation:
  `flutter test test/glb_draco_rewriter_test.dart --plain-name accessor`
  failed because the rewriter accepted a 4-byte decoded POSITION payload for a
  12-byte `FLOAT VEC3` accessor.
- 2026-07-04: verified locally for decoded Draco payload size validation:
  `flutter test test/glb_draco_rewriter_test.dart` passed 2 tests after adding
  accessor byte-length validation and rewrite diagnostics.
- 2026-07-04: verified locally for focused Draco tests after payload
  validation:
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/glb_capability_reader_test.dart test/model_loader_test.dart --plain-name Draco`
  passed 11 tests.
- 2026-07-04: verified locally after decoded Draco payload validation:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  241 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for incomplete native Draco payload diagnostics:
  `flutter test test/glb_draco_rewriter_test.dart --plain-name incomplete`
  failed because the rewriter emitted GLB bytes even when the native payload
  omitted a compressed `NORMAL` attribute and primitive indices.
- 2026-07-04: verified locally for incomplete native Draco payload
  diagnostics:
  `flutter test test/glb_draco_rewriter_test.dart --plain-name incomplete`
  passed after adding required attribute/index completeness checks.
- 2026-07-04: verified locally for Draco rewrite and loader/probe coverage
  after incomplete payload diagnostics:
  `flutter test test/glb_draco_rewriter_test.dart` passed 3 tests, and
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/glb_capability_reader_test.dart test/model_loader_test.dart --plain-name Draco`
  passed 12 tests.
- 2026-07-04: verified red for native Draco primitive decode manifest:
  `flutter test test/glb_native_decoder_probe_test.dart` failed because the
  `decodeGlb` MethodChannel call did not include `dracoPrimitives`.
- 2026-07-04: verified locally for native Draco primitive decode manifest:
  `flutter test test/glb_native_decoder_probe_test.dart` passed after adding
  compressed bufferView bytes, Draco attribute ids, and accessor schemas to the
  `decodeGlb` request. `flutter test test/flutter_scene_viewer_draco_test.dart`
  also passed in `packages/flutter_scene_viewer_draco` after exposing the
  optional wrapper argument.
- 2026-07-04: verified locally for focused Draco coverage after native decode
  manifest:
  `flutter test test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/glb_capability_reader_test.dart test/model_loader_test.dart --plain-name Draco`
  passed 12 tests.
- 2026-07-04: verified locally for vendored Draco bridge includes:
  `clang++ -std=c++17 -Ipackages/flutter_scene_viewer_draco/third_party/draco/src -c packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc -o /private/tmp/fsv_draco_bridge_ios.o`
  passed, and the equivalent Android bridge compile command passed.
- 2026-07-04: blocked for full native Draco build verification:
  local `cmake` and `pod` CLIs are unavailable (`cmake not found`,
  `pod: command not found`). Next step is to verify the sibling plugin in an
  app environment with Android NDK/CMake and CocoaPods installed, then
  implement the C++ primitive decode bridge against the `dracoPrimitives`
  manifest.
- 2026-07-04: verified locally after vendored Draco source/link config:
  `python3 tools/repo_lint.py`, `git diff --check`, root `flutter analyze`,
  sibling plugin `flutter analyze`, focused Draco tests, and sibling plugin
  `flutter test test/flutter_scene_viewer_draco_test.dart` passed. The first
  `bash tools/run_checks.sh` attempt applied Dart format to
  `glb_draco_rewriter.dart`; the second `bash tools/run_checks.sh` passed with
  root full Flutter test suite result 242 passed and 13 existing
  GPU/build-hook-gated skips.
- 2026-07-04: verified locally for the candidate iOS Draco primitive bridge:
  `clang++ -std=c++17 -Ipackages/flutter_scene_viewer_draco/third_party/draco/src -c packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc -o /private/tmp/fsv_draco_bridge_ios.o`
  passed with one upstream Draco header warning. Focused root Draco tests and
  sibling plugin Dart tests passed. Full CocoaPods/Xcode native build remains
  blocked locally because `pod` is unavailable.
- 2026-07-04: verified locally after candidate iOS Draco primitive bridge:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `bash tools/run_checks.sh` passed. The root full Flutter test suite reported
  242 passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: verified red for Android Draco primitive bridge symbol:
  `flutter test test/native_bridge_symbol_test.dart` in
  `packages/flutter_scene_viewer_draco` failed because
  `FsvDracoDecodePrimitives` was not defined by the Android bridge object.
- 2026-07-04: verified locally for Android Draco primitive bridge symbol:
  `flutter test test/native_bridge_symbol_test.dart` passed after adding the
  Android C++ primitive decode implementation. Manual `clang++ -std=c++17`
  object compile checks passed for both Android and iOS bridge sources, with
  one upstream Draco header warning.
- 2026-07-04: verified red for Android Draco JNI result marshaling:
  `flutter test test/native_bridge_symbol_test.dart` in
  `packages/flutter_scene_viewer_draco` failed because the Android JNI object
  did not define
  `Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeDecodePrimitives`.
- 2026-07-04: verified locally for Android Draco JNI result marshaling:
  `flutter test test/native_bridge_symbol_test.dart` in
  `packages/flutter_scene_viewer_draco` passed after adding the JNI native
  decode entrypoint, Java MethodChannel call, and Android primitive decode
  capability advertisement.
- 2026-07-04: verified locally after Android Draco JNI result marshaling:
  sibling plugin `flutter analyze` passed, and
  `flutter test test/native_bridge_symbol_test.dart test/flutter_scene_viewer_draco_test.dart`
  passed 3 focused plugin tests.
- 2026-07-04: verified locally after KTX2 diagnostic and Android JNI slices:
  `python3 tools/repo_lint.py`, `git diff --check`, and
  `flutter test test/glb_capability_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_native_decoder_probe_test.dart test/glb_draco_rewriter_test.dart test/model_loader_test.dart`
  passed. The focused Flutter run reported 45 passed with 3 existing
  GPU-gated skips.
- 2026-07-04: verified locally after KTX2 diagnostic and Android JNI slices:
  root `flutter analyze` passed with no issues.
- 2026-07-04: verified locally after KTX2 diagnostic and Android JNI slices:
  `bash tools/run_checks.sh` passed. The full Flutter suite reported 243
  passed with 13 existing GPU/build-hook-gated skips.
- 2026-07-04: blocked for iOS Simulator A1B32 evidence:
  `/private/tmp/fsviewer_ios_evidence_app` exists with `assets/a1b32.glb` and
  `FLTEnableFlutterGPU`, but `pod` is not installed, the app has no Podfile,
  and the optional Draco plugin/Info.plist opt-in are not wired into that app.
  Next step is to install CocoaPods or use an environment with CocoaPods,
  regenerate the evidence app with `flutter_scene_viewer_draco`, set
  `FlutterSceneViewerDracoEnabled`, expose A1B32 in the selector, and rerun the
  iOS Simulator screenshot evidence.
- 2026-07-04: verified locally for iOS native Draco build linkage:
  initial `flutter build ios --simulator --debug` in
  `/private/tmp/fsviewer_ios_evidence_app` failed with undefined Google Draco
  symbols from the plugin pod. After adding the iOS vendor source aggregator and
  making `fsv_draco_bridge.h` private to the pod module, the same build passed
  and produced `build/ios/iphonesimulator/Runner.app`.
- 2026-07-04: verified locally for iOS Simulator visual evidence:
  installed and launched the evidence app on booted iPhone 17 simulator and
  captured screenshots at
  `/private/tmp/fsviewer_ios_evidence_app/v2_a1b32_draco_ios.png`,
  `/private/tmp/fsviewer_ios_evidence_app/v2_waterbottle_ios.png`,
  `/private/tmp/fsviewer_ios_evidence_app/v2_clearcoat_carpaint_ios.png`, and
  `/private/tmp/fsviewer_ios_evidence_app/v2_carconcept_ios.png`. A1B32 rendered
  with `Patch: none`, showing the native Draco path loaded the required Draco
  asset without manual preprocessing.
- 2026-07-04: verified locally after iOS native Draco evidence:
  `bash tools/run_checks.sh` passed with 243 tests and 13 existing
  GPU/build-hook-gated skips. In `packages/flutter_scene_viewer_draco`,
  `flutter analyze` passed and
  `flutter test test/native_bridge_symbol_test.dart test/flutter_scene_viewer_draco_test.dart`
  passed 3 focused plugin tests.
- 2026-07-04: verified red for core imported KTX2 diagnostic details:
  `flutter test test/glb_imported_texture_patch_reader_test.dart --plain-name BasisU`
  failed because the diagnostic did not include
  `basisuTranscodeUnavailable` or KTX2 header fields.
- 2026-07-04: verified locally for core imported KTX2 diagnostic details:
  `flutter test test/glb_imported_texture_patch_reader_test.dart --plain-name BasisU`
  passed after adding a bounded KTX2 header reader and wiring its details into
  the core imported texture diagnostic path.
- 2026-07-04: verified red for material-extension KTX2 diagnostic details:
  `flutter test test/glb_material_extension_reader_test.dart --plain-name BasisU`
  failed because the diagnostic did not include
  `basisuTranscodeUnavailable` or KTX2 header fields.
- 2026-07-04: verified locally for material-extension KTX2 diagnostic details:
  `flutter test test/glb_material_extension_reader_test.dart --plain-name BasisU`
  passed after wiring KTX2 header details into authored extension texture
  diagnostics.
- 2026-07-04: verified red for preflight KTX2 diagnostic details:
  `flutter test test/glb_capability_reader_test.dart --plain-name KTX2` failed
  because the BasisU decoder diagnostic still reported generic
  `status: unsupported` and had no KTX2 image header summary.
- 2026-07-04: verified locally for preflight KTX2 diagnostic details:
  `flutter test test/glb_capability_reader_test.dart --plain-name KTX2` passed
  after preserving the GLB BIN chunk and attaching bounded KTX2 header details
  to the BasisU unsupported decoder diagnostic.
- 2026-07-04: verified locally after KTX2 diagnostic detail slices:
  `dart format lib/src/internal/ktx2_header_reader.dart lib/src/internal/glb_imported_texture_patch_reader.dart lib/src/internal/glb_material_extension_reader.dart lib/src/internal/glb_capability_reader.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_capability_reader_test.dart`
  formatted the touched Dart files, and
  `flutter test test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_capability_reader_test.dart --plain-name BasisU`
  passed 4 focused tests.
- 2026-07-04: verified red for pure Dart meshopt import rewrite:
  `flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart`
  failed because `meshopt_decoder.dart`, `glb_meshopt_rewriter.dart`, and the
  public internal decode/rewrite entrypoints did not exist yet. This locks the
  next slice to a Flutter GPU / `flutter_scene`-compatible pre-import GLB
  rewrite path instead of introducing a renderer backend.
- 2026-07-04: verified red for ModelLoader meshopt integration:
  `flutter test test/model_loader_test.dart --plain-name meshopt` failed
  because required `EXT_meshopt_compression` still stopped at decoder preflight
  instead of being rewritten into standard bufferViews before adapter import.
- 2026-07-04: verified locally for pure Dart meshopt import rewrite:
  `flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart`
  passed after adding a Dart meshopt decoder for glTF `ATTRIBUTES`,
  `TRIANGLES`, and `INDICES` modes plus a GLB rewrite path that expands
  compressed bufferViews into embedded BIN bytes and removes
  `EXT_meshopt_compression` declarations.
- 2026-07-04: verified locally for ModelLoader meshopt integration:
  `flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/model_loader_test.dart --plain-name meshopt`
  passed after wiring the meshopt rewrite before blocking capability diagnostics
  and before `flutter_scene` adapter import.
- 2026-07-04: verified locally after meshopt rewrite integration:
  `flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/model_loader_test.dart`
  passed with 22 tests and 3 existing Flutter GPU-gated skips.
- 2026-07-04: verified locally for meshopt filter support:
  `flutter test test/meshopt_decoder_test.dart` passed 6 tests covering
  `ATTRIBUTES`, `TRIANGLES`, `INDICES`, and the `OCTAHEDRAL`, `QUATERNION`,
  and `EXPONENTIAL` post-decode filters.
- 2026-07-04: updated public and runtime documentation for the meshopt slice:
  `docs/RUNTIME_GLB_PIPELINE.md`, `docs/PUBLIC_API.md`, `docs/ROADMAP.md`, and
  `docs/generated/capability_matrix.md` now describe the Dart pre-import
  `EXT_meshopt_compression` rewrite path, its embedded-GLB boundary, supported
  modes/filters, and diagnostic behavior for unsupported paths.
- 2026-07-04: verified locally after meshopt docs and analyzer cleanup:
  `flutter test test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/model_loader_test.dart test/glb_capability_reader_test.dart`
  passed with 35 tests and 3 existing Flutter GPU-gated skips; `git diff
  --check` passed; `flutter analyze` passed with no issues.
- 2026-07-04: investigated KTX2 / `KHR_texture_basisu` transcode feasibility in
  the installed `flutter_scene` package. The runtime glTF texture importer uses
  `ui.instantiateImageCodec` for image bytes and falls back to a placeholder on
  decode failure; its KTX2 utilities are container plumbing plus a
  `flutter_scene`-specific `universal/1` block payload, not Khronos Basis
  Universal ETC1S/UASTC transcode. No local BasisU transcoder dependency is
  present. This acceptance item remains blocked for real rendering until an
  optional BasisU transcoder plugin or upstream `flutter_scene`
  `KHR_texture_basisu` import path is added. Current behavior remains
  header-aware, blocking diagnostics for required BasisU/KTX2 textures.
- 2026-07-04: verified locally for actionable KTX2/BasisU diagnostics:
  `flutter test test/glb_capability_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart --plain-name BasisU`
  passed 4 focused tests after adding `reason` and `nextStep` fields to
  KTX2/BasisU unsupported diagnostics and preserving them through preflight.
- 2026-07-04: updated KTX2/BasisU documentation in
  `docs/RUNTIME_GLB_PIPELINE.md`, `docs/MATERIALS_AND_LIGHTING.md`, and
  `docs/generated/capability_matrix.md` to state that the current behavior is
  header-aware diagnostics only, while real glTF Basis Universal transcode is
  blocked on an optional transcoder plugin or upstream `flutter_scene` import
  support.
- 2026-07-04: collected additional iOS Simulator evidence for A1B32 after
  wiring the optional Draco sibling plugin into the evidence app. XcodeBuildMCP
  runtime snapshots show `Load: success`, `Hierarchy: root=root parts=20`, and
  `Diagnostics: 2` for `assets/a1b32.glb`. A real Simulator window click via
  `cliclick` changed the overlay to `Pick: root/A1B32#2`, proving required
  Draco primitives render, appear in hierarchy, and participate in picking.
  Evidence screenshots are stored outside the repo at
  `/private/tmp/fsviewer_ios_evidence_app/v2_a1b32_hierarchy_mcp_ios.jpg` and
  `/private/tmp/fsviewer_ios_evidence_app/v2_a1b32_pick_ios.jpg`.
- 2026-07-04: verified locally before final status reporting:
  `python3 tools/repo_lint.py` passed; `git diff --check` passed;
  `flutter analyze` passed with no issues; targeted root tests for meshopt,
  Draco, capability preflight, imported textures, material extensions,
  material policy/patch behavior, model loading, and viewer picking passed
  with 112 tests and 3 existing Flutter GPU-gated skips; sibling plugin
  `flutter analyze` passed; sibling plugin
  `flutter test test/native_bridge_symbol_test.dart test/flutter_scene_viewer_draco_test.dart`
  passed with 3 tests; and `bash tools/run_checks.sh` passed end-to-end with
  251 tests and 13 existing Flutter GPU-gated skips.
- 2026-07-05: continued the remaining KTX2 / `KHR_texture_basisu` work without
  adding Filament or turning the root package into a plugin. Added
  `glb_basisu_rewriter.dart`, which rewrites native decoded PNG/JPEG image
  payloads into ordinary GLB image bufferViews, rewrites
  `KHR_texture_basisu` texture references into normal image `source`
  references, removes top-level `KHR_texture_basisu` declarations when no
  compressed texture references remain, and reports `unsupportedModelFeature`
  rewrite diagnostics for missing or malformed native output. Extended
  `MethodChannelGlbNativeDecoderProbe` with an optional
  `flutter_scene_viewer/basisu` channel and `basisuImages`/`decodedImages`
  contract, and taught `ModelLoader` to use native `textureBasisu`
  capability before adapter import. This is root-side integration only; the
  actual native Basis Universal ETC1S/UASTC transcoder sibling plugin is still
  pending.
- 2026-07-05: verified locally for the root BasisU/KTX2 contract:
  `flutter test test/glb_basisu_rewriter_test.dart` first failed because the
  rewriter entrypoint did not exist, then passed after implementation;
  `flutter test test/glb_native_decoder_probe_test.dart --plain-name BasisU`
  first failed because `basisuChannel` did not exist, then passed after adding
  the MethodChannel contract; `flutter test test/model_loader_test.dart --plain-name BasisU`
  first failed because loader decode gating only handled Draco, then passed
  after adding native `textureBasisu` gating. Final focused verification passed:
  `flutter test test/glb_basisu_rewriter_test.dart test/glb_native_decoder_probe_test.dart test/model_loader_test.dart test/glb_capability_reader_test.dart test/glb_imported_texture_patch_reader_test.dart test/glb_material_extension_reader_test.dart --plain-name BasisU`
  passed 8 tests; `flutter analyze`, `python3 tools/repo_lint.py`, and
  `git diff --check` passed.
- 2026-07-05: verified locally after the BasisU root-contract documentation
  updates: `bash tools/run_checks.sh` passed end-to-end with 255 tests and 13
  existing Flutter GPU-gated skips.
- 2026-07-05: implemented the optional sibling
  `packages/flutter_scene_viewer_basisu` native transcoder path without adding
  Filament or making the root package a platform plugin. Vendored the Basis
  Universal v2.10 snapshot transcoder and bundled Zstd decoder sources under
  the plugin's `third_party/basis_universal/`, wired Android CMake and the iOS
  podspec, and changed the shared C++ bridge to parse KTX2, transcode level 0
  to `cTFRGBA32`, encode the pixels as standard PNG, and return
  MethodChannel-compatible `decodedImages`. Android JNI and iOS ObjC++ now
  marshal `basisuImages` requests to the shared bridge when the app opt-in key
  is enabled; disabled, missing, malformed, oversized, or unsupported KTX2
  layouts still return typed diagnostics instead of fake texture output.
- 2026-07-05: verified locally for the real BasisU/KTX2 plugin slice:
  a temporary upstream probe compiled Basis Universal plus Zstd and decoded
  upstream `kodim23.ktx2` to 768x512 RGBA32; `dart format lib test` in
  `packages/flutter_scene_viewer_basisu` passed with no changes; `flutter test
  test/flutter_scene_viewer_basisu_test.dart test/native_bridge_symbol_test.dart`
  passed 4 tests, including a native host compile/run that transcodes
  `test/fixtures/kodim23.ktx2` into PNG bytes; `flutter analyze` in the
  BasisU plugin passed; and root BasisU contract tests
  `flutter test test/glb_basisu_rewriter_test.dart
  test/glb_native_decoder_probe_test.dart test/model_loader_test.dart
  --plain-name BasisU` passed 4 tests.
- 2026-07-05: re-inspected `/Users/marlonjd/Downloads/A1B32.glb` while working
  on KTX2. The asset still has `KHR_draco_mesh_compression` required plus
  `KHR_materials_specular` and `KHR_materials_ior`, but no
  `KHR_texture_basisu` texture references and no `image/ktx2` images; its 17
  images are PNG/JPEG. Therefore the new BasisU plugin is required for Khronos
  KTX2/BasisU sample coverage, not for the A1B32 fashion asset gate.
- 2026-07-05: updated BasisU/KTX2 public documentation after the native plugin
  slice: `docs/RUNTIME_GLB_PIPELINE.md`, `docs/PUBLIC_API.md`,
  `docs/ROADMAP.md`, `docs/generated/capability_matrix.md`, and
  `packages/flutter_scene_viewer_basisu/README.md` now describe the optional
  sibling plugin, vendored Basis Universal/Zstd sources, KTX2-to-PNG native
  transcode, Dart GLB rewrite, opt-in keys, and unsupported-path diagnostics.
- 2026-07-05: verified locally after the native BasisU plugin and docs slice:
  `python3 tools/repo_lint.py` passed; `git diff --check` passed; root
  focused BasisU tests
  `flutter test test/glb_basisu_rewriter_test.dart
  test/glb_native_decoder_probe_test.dart test/model_loader_test.dart
  --plain-name BasisU` passed 4 tests; sibling plugin tests
  `flutter test test/flutter_scene_viewer_basisu_test.dart
  test/native_bridge_symbol_test.dart` passed 4 tests; sibling plugin
  `flutter analyze` passed; and `bash tools/run_checks.sh` passed end-to-end
  with 255 tests and 13 existing Flutter GPU-gated skips.
- 2026-07-05: validated the optional BasisU sibling plugin in an iOS Simulator
  evidence app without adding Filament. Added the plugin as a temporary path
  dependency in `/private/tmp/fsviewer_ios_evidence_app`, enabled
  `FlutterSceneViewerBasisuEnabled` in the app `Info.plist`, generated
  `/private/tmp/fsviewer_ios_evidence_app/assets/basisu_quad.glb` with an
  embedded `image/ktx2` payload and required `KHR_texture_basisu`, and updated
  the app to load it first. CocoaPods was available only through the user's
  local gem path, so `ruby -rlogger /Users/marlonjd/.gem/ruby/2.6.0/bin/pod
  install` was used for the temporary app. XcodeBuildMCP
  `build_run_sim` then succeeded for the iPhone 17 simulator. Screenshot
  evidence is stored at
  `/private/tmp/fsviewer_ios_evidence_app/v2_basisu_quad_ios.jpg` and shows
  `Load: success`, `Hierarchy: root=root parts=1`, `Diagnostics: 0`, and the
  decoded KTX2 texture rendered on the quad.
- 2026-07-05: fixed the iOS BasisU pod integration found during simulator
  validation. The pod now keeps only `FlutterSceneViewerBasisuPlugin.h` public,
  compiles `ios/Classes/fsv_basisu_vendor_sources.cc` as a CocoaPods-visible
  source aggregator for Basis Universal plus Zstd, and keeps the C++ bridge
  header private so Objective-C umbrella imports do not expose C++ standard
  headers to `GeneratedPluginRegistrant.m`. Added a plugin test that compiles
  the iOS vendor source aggregator. Verified locally:
  `flutter test test/flutter_scene_viewer_basisu_test.dart
  test/native_bridge_symbol_test.dart` passed 5 tests,
  `flutter analyze` in the BasisU plugin passed, `python3 tools/repo_lint.py`
  passed, and `git diff --check` passed.
- 2026-07-05: fixed root analyzer scope for sibling plugin packages by adding
  `packages/flutter_scene_viewer_basisu/**` and
  `packages/flutter_scene_viewer_draco/**` to the root `analysis_options.yaml`
  exclude list; sibling plugins are verified in their own package contexts.
  Final local verification after that change: `bash tools/run_checks.sh`
  passed end-to-end with 255 tests and 13 existing Flutter GPU-gated skips.
- 2026-07-05: captured an additional iOS Simulator front-view screenshot for
  `/Users/marlonjd/Downloads/A1B32.glb` after the user asked to inspect whether
  the garment should be white. The GLB's top/skirt `beyaz_*` base-color PNGs
  are RGB white, while additional stitched/overlay PNGs are RGBA. Added
  imported material alpha handling so explicit glTF `alphaMode` values are
  preserved in authored material patches and alpha-capable base-color PNGs with
  omitted `alphaMode` are inferred as `blend`; this keeps exporter-authored
  transparent textile overlays from becoming opaque black when applied through
  the role-aware texture patch path. Verified locally with
  `flutter test test/glb_imported_texture_patch_reader_test.dart`. Simulator
  front evidence is stored at
  `/private/tmp/fsviewer_ios_evidence_app/v2_a1b32_front_alpha_repair_ios.jpg`.
