import 'dart:typed_data';

/// Describes where an override texture should be loaded from.
sealed class TextureSource {
  const TextureSource();

  const factory TextureSource.network(
    Uri uri, {
    Map<String, String> headers,
  }) = NetworkTextureSource;

  const factory TextureSource.asset(String assetPath) = AssetTextureSource;

  const factory TextureSource.bytes(
    Uint8List encodedBytes, {
    String? debugName,
  }) = BytesTextureSource;
}

final class NetworkTextureSource extends TextureSource {
  const NetworkTextureSource(this.uri, {this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;
}

final class AssetTextureSource extends TextureSource {
  const AssetTextureSource(this.assetPath);

  final String assetPath;
}

final class BytesTextureSource extends TextureSource {
  const BytesTextureSource(this.encodedBytes, {this.debugName});

  final Uint8List encodedBytes;
  final String? debugName;
}
