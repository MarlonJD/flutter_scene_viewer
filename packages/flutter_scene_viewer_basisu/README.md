# flutter_scene_viewer_basisu

Optional native BasisU/KTX2 transcoder plugin for `flutter_scene_viewer`.

This package is intentionally separate from the main viewer package so apps
that do not need `KHR_texture_basisu` do not inherit native transcoder build
requirements.

Current status: optional native transcoder. The plugin vendors the Basis
Universal transcoder plus bundled Zstd decoder sources, accepts GLB-embedded
KTX2 image payloads over the `flutter_scene_viewer/basisu` MethodChannel,
transcodes supported ETC1S/UASTC KTX2 level 0 payloads to RGBA32, encodes the
result as PNG, and returns `decodedImages` for the root Dart package to rewrite
into ordinary GLB image bufferViews.

The plugin is disabled by default. When disabled, unregistered, unlinked, or
unable to decode an image, `flutter_scene_viewer` reports typed diagnostics
instead of passing compressed texture bytes to `flutter_scene`.

Opt-in keys:

- iOS `Info.plist`: `FlutterSceneViewerBasisuEnabled`
- Android manifest metadata: `flutter_scene_viewer_basisu_enabled`

Boundaries:

- This plugin does not add a renderer backend.
- The root package remains a Dart/Flutter package and does not require native
  build tooling unless the app opts into this sibling plugin.
- External `.ktx2` URIs are still resolver work; the current native bridge
  consumes KTX2 bytes supplied by the root GLB pipeline.

Third-party notices for the vendored Basis Universal and Zstd sources are kept
under `third_party/basis_universal/`.
