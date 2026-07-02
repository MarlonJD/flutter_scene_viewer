# Public API draft

## Widget

```dart
FlutterSceneViewer(
  source: ModelSource.network(Uri.parse('https://cdn.example.com/chair.glb')),
  controller: controller,
  lighting: ViewerLighting.studio(),
  renderPolicy: RenderPolicy.adaptive,
  initialOverrides: savedOverrides,
  onPartTapped: (part) {},
)
```

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
```

`loadState.status` reports `idle`, `loading`, `success`, or `error`.
Failed loads attach a `ViewerDiagnostic` to `loadState.diagnostic` and also add
that diagnostic to `controller.diagnostics`.

`controller.partTree` exposes the last successfully loaded assembly hierarchy
as immutable `PartTree`, `PartNode`, and `PartRecord` values. Geometry-less
nodes remain in the tree as assembly/dummy nodes, and renderable mesh primitives
are addressed by `PartAddress(nodePath, primitiveIndex)`.

## Camera fit

`controller.fitCamera()` asks the attached viewer widget to frame the currently
loaded model and then requests a fresh render frame. The method is intentionally
adapter-backed: callers do not pass or receive concrete `flutter_scene` camera
types. If model bounds are unavailable in the current adapter slice, the widget
keeps the request on the viewer side and does not expose renderer internals.

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

## Material patch

Core patch fields:

- `baseColorFactor`
- `baseColorTexture`
- `metallic`
- `roughness`
- `emissiveFactor`
- `visible`

Unsupported fields must be rejected with diagnostics, not silently ignored.

## Material override persistence

`controller.materialOverrides` returns a serializable `MaterialOverrideSnapshot`
of the current sparse override state. Persist `snapshot.toJson()` and restore it
with `MaterialOverrideSnapshot.fromJson(json)` followed by
`controller.applyMaterialOverrides(snapshot)` after loading the matching model.
