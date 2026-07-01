# 05 — Public API Tasarım Sözleşmesi

Bu dosyadaki Dart örnekleri hedef semantiği gösterir. Upstream değişikliklerine göre isimler uyarlanabilir, fakat ürün davranışı korunmalıdır.

## Widget

```dart
class FlutterSceneViewer extends StatefulWidget {
  const FlutterSceneViewer({
    super.key,
    required this.source,
    this.controller,
    this.initialState,
    this.lighting = const ViewerLighting.studio(),
    this.camera = const ViewerCameraConfig(),
    this.renderPolicy = RenderPolicy.adaptive,
    this.limits = const ViewerLimits(),
    this.rootTransform,
    this.onLoadStateChanged,
    this.onPartTapped,
    this.onDiagnostics,
  });

  final ModelSource source;
  final FlutterSceneViewerController? controller;
  final ViewerState? initialState;
  final ViewerLighting lighting;
  final ViewerCameraConfig camera;
  final RenderPolicy renderPolicy;
  final ViewerLimits limits;
  final Matrix4? rootTransform;
  final ValueChanged<ViewerLoadState>? onLoadStateChanged;
  final ValueChanged<PartHit>? onPartTapped;
  final ValueChanged<ModelDiagnostics>? onDiagnostics;
}
```

## Model source

```dart
sealed class ModelSource {
  const ModelSource();

  const factory ModelSource.asset(String path) = AssetModelSource;
  const factory ModelSource.network(
    Uri uri, {
    Map<String, String> headers,
    ModelCachePolicy cachePolicy,
  }) = NetworkModelSource;
  const factory ModelSource.bytes(
    Uint8List bytes, {
    String? cacheKey,
  }) = BytesModelSource;
}
```

## Controller

```dart
abstract interface class FlutterSceneViewerController {
  Future<void> reload();
  Future<void> replaceSource(ModelSource source);

  Future<List<AssemblyInfo>> assemblies();
  Future<List<PartInfo>> parts();
  Future<PartInfo?> resolvePart(PartAddress address);

  Future<void> patchPartMaterial(
    PartAddress part,
    MaterialPatch patch,
  );

  Future<void> resetPartMaterial(PartAddress part);
  Future<void> resetAllMaterials();

  Future<void> setPartVisible(PartAddress part, bool visible);
  Future<void> setAssemblyVisible(NodeAddress assembly, bool visible);

  Future<void> fitCamera({PartAddress? part, NodeAddress? assembly});
  Future<void> setCameraState(ViewerCameraState state);
  ViewerCameraState get cameraState;

  Future<ViewerState> exportState();
  Future<StateApplyReport> applyState(ViewerState state);

  Future<ModelDiagnostics> diagnostics();
  Future<void> requestFrame();
}
```

## Part address

```dart
@immutable
class PartAddress {
  const PartAddress({
    required this.nodePath,
    required this.primitiveIndex,
    this.semanticPath = const [],
  });

  final List<int> nodePath;
  final int primitiveIndex;
  final List<String> semanticPath;
}
```

## Material patch

```dart
@immutable
class MaterialPatch {
  const MaterialPatch({
    this.baseColor,
    this.baseColorTexture,
    this.metallic,
    this.roughness,
    this.emissive,
    this.normalTexture,
    this.metallicRoughnessTexture,
    this.occlusionTexture,
  });

  final Vector4? baseColor;
  final TextureSource? baseColorTexture;
  final double? metallic;
  final double? roughness;
  final Vector4? emissive;
  final TextureSource? normalTexture;
  final TextureSource? metallicRoughnessTexture;
  final TextureSource? occlusionTexture;
}
```

Normal/MR/occlusion runtime slotları capability kontrolü olmadan uygulanmamalıdır.

## Texture source

```dart
sealed class TextureSource {
  const TextureSource();

  const factory TextureSource.asset(String path) = AssetTextureSource;
  const factory TextureSource.network(
    Uri uri, {
    Map<String, String> headers,
    String? cacheKey,
  }) = NetworkTextureSource;
  const factory TextureSource.bytes(
    Uint8List bytes, {
    String? cacheKey,
  }) = BytesTextureSource;
}
```

## Lighting

```dart
class ViewerLighting {
  const ViewerLighting({
    required this.environment,
    this.environmentIntensity = 1.0,
    this.directionalLight,
    this.exposure = 1.0,
    this.background = const ViewerBackground.transparent(),
  });

  const ViewerLighting.studio();

  final ViewerEnvironment environment;
  final double environmentIntensity;
  final ViewerDirectionalLight? directionalLight;
  final double exposure;
  final ViewerBackground background;
}
```

V1 API'si embedded GLB camera/light kullanmaz.

## Load states ve typed errors

```dart
sealed class ViewerLoadState {}
final class ViewerIdle extends ViewerLoadState {}
final class ViewerDownloading extends ViewerLoadState {
  final int receivedBytes;
  final int? totalBytes;
}
final class ViewerImporting extends ViewerLoadState {}
final class ViewerIndexing extends ViewerLoadState {}
final class ViewerApplyingState extends ViewerLoadState {}
final class ViewerReady extends ViewerLoadState {
  final ModelInfo model;
}
final class ViewerFailed extends ViewerLoadState {
  final ViewerException error;
}
```

Typed exception örnekleri:

- `ModelNetworkException`
- `ModelTooLargeException`
- `InvalidGlbException`
- `UnsupportedPrimitiveTopologyException`
- `MissingUvSetException`
- `UnsupportedMaterialException`
- `TextureDecodeException`
- `TextureTooLargeException`
- `StaleOperationException`
- `ViewerDisposedException`

## Diagnostics

```dart
class ModelDiagnostics {
  final List<ModelIssue> issues;
  final ModelCapabilities capabilities;
  final ModelStatistics statistics;
}
```

Diagnostics uygulama crash'i yerine model kalitesi ve capability farklarını görünür kılar.

## State

```dart
class ViewerState {
  final int schemaVersion;
  final String modelFingerprint;
  final ViewerCameraState camera;
  final Map<PartAddress, MaterialPatchDescriptor> materialOverrides;
  final Map<NodeAddress, bool> visibility;
}
```

GPU texture, `ui.Image`, Node veya Material serialize edilmez.
