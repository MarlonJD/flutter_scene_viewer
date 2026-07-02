import 'dart:convert';
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

  Map<String, Object?> toJson() => switch (this) {
        NetworkTextureSource(:final uri, :final headers) => <String, Object?>{
            'type': 'network',
            'uri': uri.toString(),
            'headers': headers,
          },
        AssetTextureSource(:final assetPath) => <String, Object?>{
            'type': 'asset',
            'assetPath': assetPath,
          },
        BytesTextureSource(:final encodedBytes, :final debugName) =>
          <String, Object?>{
            'type': 'bytes',
            'bytesBase64': base64Encode(encodedBytes),
            if (debugName != null) 'debugName': debugName,
          },
      };

  static TextureSource fromJson(Map<String, Object?> json) {
    return switch (json['type']) {
      'network' => TextureSource.network(
          _uri(json['uri']),
          headers: _stringMap(json['headers']),
        ),
      'asset' => TextureSource.asset(_string(json['assetPath'], 'assetPath')),
      'bytes' => TextureSource.bytes(
          base64Decode(_string(json['bytesBase64'], 'bytesBase64')),
          debugName: json['debugName'] as String?,
        ),
      _ =>
        throw ArgumentError.value(json, 'json', 'Invalid TextureSource JSON'),
    };
  }
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

Uri _uri(Object? value) {
  final text = _string(value, 'uri');
  return Uri.parse(text);
}

String _string(Object? value, String name) {
  if (value is String) {
    return value;
  }
  throw ArgumentError.value(value, name, 'Expected a string');
}

Map<String, String> _stringMap(Object? value) {
  if (value == null) {
    return const <String, String>{};
  }
  if (value is! Map) {
    throw ArgumentError.value(value, 'headers', 'Expected a map');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final mapValue = entry.value;
    if (key is! String || mapValue is! String) {
      throw ArgumentError.value(value, 'headers', 'Expected string headers');
    }
    result[key] = mapValue;
  }
  return result;
}
