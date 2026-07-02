import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as flutter_scene;

import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';

/// Internal boundary for direct `flutter_scene` API calls.
///
/// Keep this file and nearby adapter files as the only place where concrete
/// `flutter_scene` classes leak into implementation details. Public API should
/// stay stable even when `flutter_scene` changes.
abstract interface class FlutterSceneAdapter {
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName});

  AdapterNodeSnapshot? get nodeSnapshot;

  Future<void> applyMaterialPatch(PartAddress address, MaterialPatch patch);

  Future<void> resetMaterial(PartAddress address);

  List<ViewerDiagnostic> collectDiagnostics();
}

/// Runtime adapter backed by the installed `flutter_scene` package.
final class FlutterSceneRuntimeAdapter implements FlutterSceneAdapter {
  flutter_scene.Node? _rootNode;

  flutter_scene.Node? get rootNode => _rootNode;

  @override
  AdapterNodeSnapshot? get nodeSnapshot {
    final rootNode = _rootNode;
    if (rootNode == null) {
      return null;
    }
    return _snapshotNode(rootNode);
  }

  @override
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName}) async {
    await flutter_scene.loadBaseShaderLibrary();
    await flutter_scene.Material.initializeStaticResources();
    _rootNode = await flutter_scene.Node.fromGlbBytes(bytes);
  }

  @override
  Future<void> applyMaterialPatch(PartAddress address, MaterialPatch patch) {
    throw UnsupportedError('Material overrides are not implemented yet.');
  }

  @override
  List<ViewerDiagnostic> collectDiagnostics() => const <ViewerDiagnostic>[];

  @override
  Future<void> resetMaterial(PartAddress address) {
    throw UnsupportedError('Material reset is not implemented yet.');
  }

  AdapterNodeSnapshot _snapshotNode(flutter_scene.Node node) {
    return AdapterNodeSnapshot(
      name: node.name,
      primitiveCount: node.mesh?.primitives.length ?? 0,
      children: <AdapterNodeSnapshot>[
        for (final child in node.children) _snapshotNode(child),
      ],
    );
  }
}

/// Adapter-owned snapshot of the scene graph fields needed by PartRegistry.
final class AdapterNodeSnapshot {
  AdapterNodeSnapshot({
    required this.name,
    this.primitiveCount = 0,
    Iterable<AdapterNodeSnapshot> children = const <AdapterNodeSnapshot>[],
  })  : assert(primitiveCount >= 0, 'primitiveCount must be non-negative'),
        children = List<AdapterNodeSnapshot>.unmodifiable(children);

  final String name;
  final int primitiveCount;
  final List<AdapterNodeSnapshot> children;
}

final class FlutterSceneAdapterUnavailableException implements Exception {
  const FlutterSceneAdapterUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
