# 18 — Upstream Referanslar

Bu dosya implementation sırasında source audit başlangıç noktasıdır. Exact commit/revision notu repo içinde ayrıca tutulmalıdır.

## flutter_scene

- Repository: https://github.com/bdero/flutter_scene
- Package: https://pub.dev/packages/flutter_scene
- Runtime GLB loader: `packages/flutter_scene/lib/src/node.dart`
- Runtime importer: `packages/flutter_scene/lib/src/runtime_importer/`
- PBR material: `packages/flutter_scene/lib/src/material/physically_based_material.dart`
- Standard shader: `packages/flutter_scene/shaders/flutter_scene_standard.frag`
- SceneView: `packages/flutter_scene/lib/src/widgets/scene_view.dart`
- MeshComponent: `packages/flutter_scene/lib/src/components/mesh_component.dart`
- Material docs: repository `MATERIALS.md`

## Flutter GPU / Impeller

- Flutter GPU design/status: Flutter repository `docs/engine/impeller/Flutter-GPU.md`
- Impeller docs: https://docs.flutter.dev/perf/impeller

## interactive_3d

- Repository: https://github.com/AdnanKhan45/interactive_3d
- Android: Filament through Flutter Texture/SurfaceProducer
- iOS: SceneKit through UiKitView
- Runtime texture/PBR capability should be treated as current competitor baseline.

## glTF

- Specification: https://github.com/KhronosGroup/glTF/tree/main/specification/2.0
- Validator/reference assets: Khronos glTF repositories

## Source audit checklist

- Confirm actual package version/commit.
- Confirm runtime importer limitations.
- Confirm public texture helper APIs.
- Confirm material slots are mutable.
- Confirm material clone strategy.
- Confirm raycast and bounds APIs.
- Confirm SceneView external repaint/on-demand mechanism.
- Confirm web backend capability.
- Record findings in `docs/upstream_api_notes.md` in the implementation repo.
