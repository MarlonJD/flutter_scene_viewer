# flutter_scene_viewer

Flutter-native GLB product viewing and configuration.

`flutter_scene_viewer` is a WebView-free viewer/configurator SDK built on top of
[`flutter_scene`](https://pub.dev/packages/flutter_scene). It turns
`flutter_scene` into a production-oriented Flutter widget and controller API for:

- runtime GLB loading from network, assets, or bytes;
- assembly/sub-assembly/part hierarchy preservation;
- node-path + primitive-index part addressing;
- runtime base-color texture and core PBR material overrides;
- original material reset and serializable override state;
- orbit/pan/zoom, auto camera fit, picking, visibility, and diagnostics;
- viewer-controlled studio lighting and adaptive/on-demand rendering.

Through `flutter_scene`, the package is designed around Flutter's own
GPU-backed rendering path: Flutter GPU / Impeller on native platforms and
WebGL2 on web. The goal is a Flutter-first product viewer, not a WebView-hosted
JavaScript configurator or a separate per-platform native viewer.

## Why This Exists

Flutter already has ways to display 3D content, but product viewers need more
than "draw this model." A configurator needs loading state, camera fitting,
stable part selection, material and texture overrides, reset behavior,
serialized state, diagnostics, and a render policy that can stop work while the
scene is idle.

`flutter_scene` provides the lower-level scene graph, material, rendering, GLB
import, raycast, and Flutter GPU/Impeller integration. `flutter_scene_viewer`
exists to package those capabilities into a higher-level SDK for static GLB
product, medical, and industrial models. The full rationale is in
[docs/WHY.md](docs/WHY.md).

## What Makes It Different

- It is Flutter-native and WebView-free.
- It builds on one `flutter_scene` scene/material model instead of splitting the
  viewer across Android Filament, iOS SceneKit, and a web-only JavaScript stack.
- It preserves assembly/sub-assembly/part hierarchy instead of flattening a GLB
  into anonymous meshes.
- It uses stable `nodePath` + `primitiveIndex` part addresses for picking,
  visibility, and material overrides.
- It reports capability diagnostics when a material or texture requirement is
  unsupported instead of faking support.
- It treats performance as an architecture goal: direct Flutter rendering
  integration, adaptive/on-demand frames, and caches first; raw "faster than X"
  claims only after benchmark evidence.

## MVP scope

The first implementation targets **static GLB product/medical/industrial models**.
It does not tessellate CAD formats, unwrap UVs, write custom shaders, or implement
Unity/Unreal-style animation systems.

MVP core material support:

- base color factor/texture;
- normal texture;
- metallic/roughness factor and texture;
- occlusion texture;
- emissive factor/texture;
- alpha mode and double-sided handling where supported by `flutter_scene`.

Explicit non-goals for v1:

- skeletal animation and interactive posing;
- morph targets / blend shapes;
- Draco/meshopt/KTX2 compression;
- imported glTF lights/cameras/full authored scene playback;
- advanced shader techniques like subsurface scattering, parallax, and displacement.

## Product Boundary

This package is **not** a new 3D engine. It adapts `flutter_scene` into a stable
public Flutter API for app developers. It does not tessellate CAD files, unwrap
UVs, invent missing texture coordinates, implement custom PBR rendering, or
claim performance superiority over Filament, `interactive_3d`, BabylonJS, or
other viewers without benchmark evidence.

## Development Status

`flutter_scene_viewer` is in early development. The public API shape,
documentation, tooling, and validation checks are in place; the
`flutter_scene` adapter is still being implemented. Treat the package as
pre-release until the runtime adapter and benchmark reports are complete.

## Development

```sh
flutter pub get
bash tools/run_checks.sh
```

`flutter_scene` currently depends on Flutter GPU/Impeller preview capabilities;
use the Flutter channel/version required by `flutter_scene`.

## Project Docs

- [Why this package exists](docs/WHY.md)
- [Project charter](docs/PROJECT_CHARTER.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Public API](docs/PUBLIC_API.md)
- [Runtime GLB pipeline](docs/RUNTIME_GLB_PIPELINE.md)
- [Materials and lighting](docs/MATERIALS_AND_LIGHTING.md)

## License

`flutter_scene_viewer` is licensed under the Mozilla Public License 2.0
(`MPL-2.0`). You can use it in commercial Flutter applications, including
closed-source larger works. Changes to this package's covered source files that
you distribute must remain available under the MPL-2.0, so improvements to the
viewer layer can keep flowing back to the community.
