import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PartAddress JSON round-trips', () {
    final address = PartAddress(
      nodePath: <String>['Vehicle', 'DoorAssembly', 'DoorLeft'],
      primitiveIndex: 2,
    );

    expect(PartAddress.fromJson(address.toJson()), address);
    expect(address.debugPath, 'Vehicle/DoorAssembly/DoorLeft#2');
  });

  test('PartAddress keeps nodePath immutable', () {
    final sourcePath = <String>['Vehicle', 'Wheel'];
    final address = PartAddress(nodePath: sourcePath, primitiveIndex: 0);

    sourcePath.add('Mutated');

    expect(address.nodePath, <String>['Vehicle', 'Wheel']);
    expect(() => address.nodePath.add('Mutated'), throwsUnsupportedError);
  });
}
