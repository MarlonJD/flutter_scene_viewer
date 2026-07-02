import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_scene_viewer/src/part_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PartRegistry preserves assemblies and maps mesh primitives', () {
    final registry = PartRegistry.fromSnapshot(
      AdapterNodeSnapshot(
        name: 'Vehicle',
        children: <AdapterNodeSnapshot>[
          AdapterNodeSnapshot(
            name: 'Cabin',
            children: <AdapterNodeSnapshot>[
              AdapterNodeSnapshot(name: 'DoorLeft', primitiveCount: 2),
            ],
          ),
          AdapterNodeSnapshot(name: 'Locator'),
        ],
      ),
    );

    expect(registry.diagnostics, isEmpty);
    final root = registry.tree.root!;
    expect(root.name, 'Vehicle');
    expect(root.nodePath, <String>['Vehicle']);
    expect(root.records, isEmpty);
    expect(root.children.map((node) => node.name), <String>[
      'Cabin',
      'Locator',
    ]);

    final cabin = root.children.first;
    expect(cabin.records, isEmpty);
    final locator = root.children.last;
    expect(locator.children, isEmpty);
    expect(locator.records, isEmpty);

    final door = cabin.children.single;
    expect(door.isRenderable, isTrue);
    expect(
      door.records.map((record) => record.address.debugPath),
      <String>[
        'Vehicle/Cabin/DoorLeft#0',
        'Vehicle/Cabin/DoorLeft#1',
      ],
    );
    expect(
      registry.tree
          .resolvePart(PartAddress(
            nodePath: <String>['Vehicle', 'Cabin', 'DoorLeft'],
            primitiveIndex: 1,
          ))
          ?.address
          .debugPath,
      'Vehicle/Cabin/DoorLeft#1',
    );
  });

  test('PartRegistry reports ambiguous duplicate node paths', () {
    final registry = PartRegistry.fromSnapshot(
      AdapterNodeSnapshot(
        name: 'Vehicle',
        children: <AdapterNodeSnapshot>[
          AdapterNodeSnapshot(name: 'Wheel', primitiveCount: 1),
          AdapterNodeSnapshot(name: 'Wheel', primitiveCount: 1),
        ],
      ),
    );

    expect(registry.diagnostics, hasLength(1));
    expect(
      registry.diagnostics.single.code,
      ViewerDiagnosticCode.ambiguousNodePath,
    );
    expect(
      registry.diagnostics.single.details['nodePath'],
      <String>['Vehicle', 'Wheel'],
    );
    expect(registry.diagnostics.single.details['count'], 2);

    final ambiguousAddress = PartAddress(
      nodePath: <String>['Vehicle', 'Wheel'],
      primitiveIndex: 0,
    );
    expect(registry.tree.resolvePart(ambiguousAddress), isNull);
    expect(
      registry.tree.records
          .where((record) => record.address == ambiguousAddress),
      hasLength(2),
    );
  });
}
