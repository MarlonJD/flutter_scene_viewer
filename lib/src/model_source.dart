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

  @override
  bool operator ==(Object other) {
    return other is NetworkModelSource &&
        uri == other.uri &&
        _stringMapEquals(headers, other.headers);
  }

  @override
  int get hashCode => Object.hash(uri, _stringMapHash(headers));
}

final class AssetModelSource extends ModelSource {
  const AssetModelSource(this.assetPath);

  final String assetPath;

  @override
  bool operator ==(Object other) {
    return other is AssetModelSource && assetPath == other.assetPath;
  }

  @override
  int get hashCode => assetPath.hashCode;
}

final class BytesModelSource extends ModelSource {
  const BytesModelSource(this.bytes, {this.debugName});

  final Uint8List bytes;
  final String? debugName;

  @override
  bool operator ==(Object other) {
    return other is BytesModelSource &&
        identical(bytes, other.bytes) &&
        debugName == other.debugName;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(bytes), debugName);
}

bool _stringMapEquals(Map<String, String> left, Map<String, String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _stringMapHash(Map<String, String> value) {
  final keys = value.keys.toList()..sort();
  return Object.hashAll(
    <Object?>[
      for (final key in keys) ...<Object?>[key, value[key]],
    ],
  );
}
