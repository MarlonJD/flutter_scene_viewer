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
await controller.setPartMaterial(address, patch);
await controller.setPartTexture(address, textureSource);
await controller.resetPart(address);
await controller.setPartVisibility(address, false);
await controller.fitCamera();
```

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
