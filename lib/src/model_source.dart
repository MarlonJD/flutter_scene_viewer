import 'dart:typed_data';

/// Describes where a GLB model should be loaded from.
sealed class ModelSource {
  const ModelSource();

  const factory ModelSource.network(
    Uri uri, {
    Map<String, String> headers,
  }) = NetworkModelSource;

  const factory ModelSource.asset(String assetPath) = AssetModelSource;

  const factory ModelSource.bytes(
    Uint8List bytes, {
    String? debugName,
  }) = BytesModelSource;
}

final class NetworkModelSource extends ModelSource {
  const NetworkModelSource(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

final class AssetModelSource extends ModelSource {
  const AssetModelSource(this.assetPath);

  final String assetPath;
}

final class BytesModelSource extends ModelSource {
  const BytesModelSource(this.bytes, {this.debugName});

  final Uint8List bytes;
  final String? debugName;
}
