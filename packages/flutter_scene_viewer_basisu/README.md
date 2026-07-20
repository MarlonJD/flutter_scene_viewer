# flutter_scene_viewer_basisu

Optional native BasisU/KTX2 transcoder plugin for `flutter_scene_viewer`.

This package is intentionally separate from the main viewer package so apps
that do not need `KHR_texture_basisu` do not inherit native transcoder build
requirements.

Current status: optional native transcoder. The plugin vendors the Basis
Universal transcoder plus bundled Zstd decoder sources, accepts GLB-embedded
KTX2 image payloads over the `flutter_scene_viewer/basisu` MethodChannel, and
transcodes supported ETC1S/UASTC mip chains to ordered raw RGBA8888 levels.
Each level retains its exact dimensions, bytes, content role, image identity,
and consuming texture sampler intents for the root package's repo-local
authored-mip binding seam. The bounded single-level PNG path remains a separate
compatibility route; multi-level output is never flattened to level 0.

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

Each decode carries a unique request id. `cancelDecode`, background request
ownership, cooperative pinned BasisU/Zstd checkpoints, and exactly-once
terminal delivery prevent cancelled output from escaping. Retained decoded
levels, the maximum live Zstd Level Index buffer, and the heap-backed Zstd
context are request-budgeted. Broader transcoder container allocation
interception is still `blocked`, so this is not a complete bounded-allocator
claim.

The tracked [Plan 017 decoder/mip evidence contract](../../tools/decoder_mip_acceptance/README.md)
keeps `color`, `data`, and `normal` content roles distinct from native `color`
and `nonColor` storage, and retains exact material slots and samplers. Current
package/runtime evidence is `not run`, Android capture is `blocked` by the
unavailable device/build environment, and release remains `release pending`.

Third-party notices for the vendored Basis Universal and Zstd sources are kept
under `third_party/basis_universal/`.

The upstream base commit is
`882abb5320400ab650c1be33f9152e4955e83af3`; it is not the exact identity of
the locally modified vendored source. The upstream/vendored source hashes,
local guard hunk, purpose, and Apache-2.0 modification notice are recorded in
`third_party/basis_universal/FSV_LOCAL_MODIFICATIONS.md`. Separately, the
deterministic `third_party/basis_universal/VENDORED_SOURCES.sha256` manifest
pins the exact local state of all 28 files in the compiled transcoder/Zstd
source set. Verify that manifest from the third-party directory with:

```sh
shasum -a 256 -c VENDORED_SOURCES.sha256
```
