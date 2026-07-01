# flutter_scene_viewer

A Flutter-native, WebView-free GLB viewer/configurator SDK built on top of
[`flutter_scene`](https://pub.dev/packages/flutter_scene).

This package is **not** a new 3D engine. It is a high-level viewer layer that
turns `flutter_scene` into a production-oriented widget and controller API for:

- runtime GLB loading from network, assets, or bytes;
- assembly/sub-assembly/part hierarchy preservation;
- node-path + primitive-index part addressing;
- runtime base-color texture and core PBR material overrides;
- original material reset and serializable override state;
- orbit/pan/zoom, auto camera fit, picking, visibility, and diagnostics;
- viewer-controlled studio lighting and adaptive/on-demand rendering.

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

## Current status

This repository is a **Codex-ready starter skeleton**. The public API, tooling,
plans, and guardrails are in place. The actual `flutter_scene` adapter is a
stub and should be implemented by following `docs/exec-plans/active/`.

## Start for Codex

Give Codex this prompt:

```text
Read AGENTS.md, CODEX.md, docs/PROJECT_CHARTER.md, docs/ARCHITECTURE.md, and
then execute docs/exec-plans/active/000_bootstrap_foundation.md. Make the
smallest verifiable changes, run tools/run_checks.sh, and update the plan log.
```

## Human quick start

```sh
flutter pub get
bash tools/run_checks.sh
```

`flutter_scene` currently depends on Flutter GPU/Impeller preview capabilities;
use the Flutter channel/version required by `flutter_scene`.

## License

`flutter_scene_viewer` is licensed under the Mozilla Public License 2.0
(`MPL-2.0`). You can use it in commercial Flutter applications, including
closed-source larger works. Changes to this package's covered source files that
you distribute must remain available under the MPL-2.0, so improvements to the
viewer layer can keep flowing back to the community.
