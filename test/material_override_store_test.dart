import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final address = PartAddress(
    nodePath: <String>['Root', 'Body'],
    primitiveIndex: 0,
  );

  test('MaterialOverrideStore merges sparse patches for one part', () {
    final store = MaterialOverrideStore();

    store.applyPatch(address, const MaterialPatch(metallic: 0.2));
    store.applyPatch(address, const MaterialPatch(roughness: 0.8));

    final patch = store.snapshot.patchFor(address);
    expect(patch?.metallic, 0.2);
    expect(patch?.roughness, 0.8);
  });

  test('MaterialOverrideStore reset removes one part override', () {
    final other = PartAddress(
      nodePath: <String>['Root', 'Wheel'],
      primitiveIndex: 0,
    );
    final store = MaterialOverrideStore();

    store.applyPatch(address, const MaterialPatch(metallic: 0.2));
    store.applyPatch(other, const MaterialPatch(roughness: 0.8));
    store.resetPart(address);

    expect(store.snapshot.patchFor(address), isNull);
    expect(store.snapshot.patchFor(other)?.roughness, 0.8);
  });

  test('MaterialOverrideStore resetAll removes every override', () {
    final store = MaterialOverrideStore();

    store.applyPatch(address, const MaterialPatch(metallic: 0.2));
    store.resetAll();

    expect(store.snapshot.isEmpty, isTrue);
  });

  test('MaterialOverrideSnapshot serializes to JSON and back', () {
    final store = MaterialOverrideStore();
    store.applyPatch(
      address,
      const MaterialPatch(metallic: 0.2, roughness: 0.8),
    );

    final roundTripped = MaterialOverrideSnapshot.fromJson(
      store.snapshot.toJson(),
    );

    expect(roundTripped.patchFor(address)?.metallic, 0.2);
    expect(roundTripped.patchFor(address)?.roughness, 0.8);
  });
}
