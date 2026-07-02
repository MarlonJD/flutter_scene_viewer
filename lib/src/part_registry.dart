import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'part_address.dart';

/// Read-only assembly tree built from the loaded scene graph.
final class PartTree {
  factory PartTree({
    PartNode? root,
    Iterable<PartRecord> records = const <PartRecord>[],
    Iterable<PartAddress> ambiguousAddresses = const <PartAddress>[],
  }) {
    final recordList = List<PartRecord>.unmodifiable(records);
    final ambiguousSet = Set<PartAddress>.unmodifiable(ambiguousAddresses);
    return PartTree._(
      root: root,
      records: recordList,
      ambiguousAddresses: ambiguousSet,
      recordsByAddress: _indexRecords(recordList, ambiguousSet),
    );
  }

  const PartTree.empty()
      : root = null,
        records = const <PartRecord>[],
        _ambiguousAddresses = const <PartAddress>{},
        _recordsByAddress = const <PartAddress, PartRecord>{};

  const PartTree._({
    required this.root,
    required this.records,
    required Set<PartAddress> ambiguousAddresses,
    required Map<PartAddress, PartRecord> recordsByAddress,
  })  : _ambiguousAddresses = ambiguousAddresses,
        _recordsByAddress = recordsByAddress;

  final PartNode? root;
  final List<PartRecord> records;
  final Set<PartAddress> _ambiguousAddresses;
  final Map<PartAddress, PartRecord> _recordsByAddress;

  PartRecord? resolvePart(PartAddress address) {
    if (_ambiguousAddresses.contains(address)) {
      return null;
    }
    return _recordsByAddress[address];
  }

  bool isAmbiguous(PartAddress address) =>
      _ambiguousAddresses.contains(address);

  static Map<PartAddress, PartRecord> _indexRecords(
    List<PartRecord> records,
    Set<PartAddress> ambiguousAddresses,
  ) {
    final recordsByAddress = <PartAddress, PartRecord>{};
    for (final record in records) {
      if (!ambiguousAddresses.contains(record.address)) {
        recordsByAddress[record.address] = record;
      }
    }
    return Map<PartAddress, PartRecord>.unmodifiable(recordsByAddress);
  }
}

/// A scene node in the preserved assembly hierarchy.
final class PartNode {
  factory PartNode({
    required String name,
    required Iterable<String> nodePath,
    Iterable<PartNode> children = const <PartNode>[],
    Iterable<PartRecord> records = const <PartRecord>[],
  }) {
    return PartNode._(
      name: name,
      nodePath: List<String>.unmodifiable(nodePath),
      children: List<PartNode>.unmodifiable(children),
      records: List<PartRecord>.unmodifiable(records),
    );
  }

  const PartNode._({
    required this.name,
    required this.nodePath,
    required this.children,
    required this.records,
  });

  final String name;
  final List<String> nodePath;
  final List<PartNode> children;
  final List<PartRecord> records;

  bool get isRenderable => records.isNotEmpty;
}

/// A renderable mesh primitive address owned by a [PartNode].
final class PartRecord {
  const PartRecord({
    required this.address,
    this.hasTexCoords = true,
  });

  final PartAddress address;

  final bool hasTexCoords;

  List<String> get nodePath => address.nodePath;

  int get primitiveIndex => address.primitiveIndex;
}

/// Internal registry result built from adapter snapshots.
final class PartRegistry {
  const PartRegistry.empty()
      : tree = const PartTree.empty(),
        diagnostics = const <ViewerDiagnostic>[];

  factory PartRegistry.fromSnapshot(AdapterNodeSnapshot snapshot) {
    final builder = _PartRegistryBuilder();
    final root = builder.build(snapshot, const <String>[]);
    return PartRegistry._(
      tree: PartTree(
        root: root,
        records: builder.records,
        ambiguousAddresses: builder.ambiguousAddresses,
      ),
      diagnostics: builder.diagnostics,
    );
  }

  const PartRegistry._({
    required this.tree,
    required this.diagnostics,
  });

  final PartTree tree;
  final List<ViewerDiagnostic> diagnostics;
}

final class _PartRegistryBuilder {
  final List<PartRecord> records = <PartRecord>[];
  final Map<String, _PathCount> _nodePathCounts = <String, _PathCount>{};
  final Map<PartAddress, int> _addressCounts = <PartAddress, int>{};

  PartNode build(AdapterNodeSnapshot snapshot, List<String> parentPath) {
    final nodePath = List<String>.unmodifiable(
      <String>[...parentPath, snapshot.name],
    );
    final key = _pathKey(nodePath);
    final pathCount = _nodePathCounts[key];
    if (pathCount == null) {
      _nodePathCounts[key] = _PathCount(nodePath);
    } else {
      pathCount.count += 1;
    }

    final nodeRecords = <PartRecord>[];
    for (var primitiveIndex = 0;
        primitiveIndex < snapshot.primitives.length;
        primitiveIndex += 1) {
      final primitive = snapshot.primitives[primitiveIndex];
      final address = PartAddress(
        nodePath: nodePath,
        primitiveIndex: primitiveIndex,
      );
      final record = PartRecord(
        address: address,
        hasTexCoords: primitive.hasTexCoords,
      );
      nodeRecords.add(record);
      records.add(record);
      _addressCounts[address] = (_addressCounts[address] ?? 0) + 1;
    }

    return PartNode(
      name: snapshot.name,
      nodePath: nodePath,
      records: nodeRecords,
      children: <PartNode>[
        for (final child in snapshot.children) build(child, nodePath),
      ],
    );
  }

  List<ViewerDiagnostic> get diagnostics {
    final diagnostics = <ViewerDiagnostic>[];
    for (final entry in _nodePathCounts.entries) {
      final pathCount = entry.value;
      if (pathCount.count > 1) {
        diagnostics.add(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.ambiguousNodePath,
            message: 'Multiple scene nodes share the same node path.',
            details: <String, Object?>{
              'nodePath': pathCount.nodePath,
              'debugPath': pathCount.nodePath.join('/'),
              'count': pathCount.count,
            },
          ),
        );
      }
    }
    return List<ViewerDiagnostic>.unmodifiable(diagnostics);
  }

  Set<PartAddress> get ambiguousAddresses {
    final addresses = <PartAddress>{};
    for (final entry in _addressCounts.entries) {
      if (entry.value > 1) {
        addresses.add(entry.key);
      }
    }
    return Set<PartAddress>.unmodifiable(addresses);
  }

  String _pathKey(List<String> nodePath) {
    return nodePath.map((segment) => '${segment.length}:$segment').join('|');
  }
}

final class _PathCount {
  _PathCount(this.nodePath);

  final List<String> nodePath;
  int count = 1;
}
