import 'package:flutter/foundation.dart';

/// Stable address for a renderable material slot inside a GLB node hierarchy.
@immutable
final class PartAddress {
  PartAddress({
    required List<String> nodePath,
    required this.primitiveIndex,
  })  : assert(nodePath.isNotEmpty, 'nodePath must not be empty'),
        assert(primitiveIndex >= 0, 'primitiveIndex must be non-negative'),
        nodePath = List<String>.unmodifiable(nodePath);

  /// Path of node names from model root to the node that owns the mesh.
  final List<String> nodePath;

  /// Index into the mesh primitive list for the node.
  final int primitiveIndex;

  String get debugPath => '${nodePath.join('/')}#$primitiveIndex';

  Map<String, Object?> toJson() => <String, Object?>{
        'nodePath': nodePath,
        'primitiveIndex': primitiveIndex,
      };

  static PartAddress fromJson(Map<String, Object?> json) {
    final rawPath = json['nodePath'];
    final rawPrimitive = json['primitiveIndex'];
    if (rawPath is! List || rawPrimitive is! int) {
      throw ArgumentError.value(json, 'json', 'Invalid PartAddress JSON');
    }
    return PartAddress(
      nodePath: rawPath.cast<String>(),
      primitiveIndex: rawPrimitive,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartAddress &&
      listEquals(other.nodePath, nodePath) &&
      other.primitiveIndex == primitiveIndex;

  @override
  int get hashCode => Object.hash(Object.hashAll(nodePath), primitiveIndex);

  @override
  String toString() => 'PartAddress($debugPath)';
}
