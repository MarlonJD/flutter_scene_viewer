import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SkylightTable fixture contains table, upper, and lower objects', () {
    final gltf = _readGlbJson('test/fixtures/SkylightTable.glb');

    final nodes = (gltf['nodes'] as List<Object?>).cast<Map<String, Object?>>();
    expect(
      nodes.map((node) => node['name']),
      containsAll(<String>[
        'SkylightSmokeAssembly',
        'Table',
        'UpperObject',
        'LowerObject',
      ]),
    );
    expect(nodes[0]['children'], <Object?>[1, 2, 3]);
    expect(nodes[1]['scale'], <Object?>[3.0, 0.12, 1.6]);
    expect(nodes[2]['translation'], <Object?>[-0.75, 0.36, 0.0]);
    expect(nodes[3]['translation'], <Object?>[0.75, -0.38, 0.0]);

    final materials =
        (gltf['materials'] as List<Object?>).cast<Map<String, Object?>>();
    expect(
      materials.map((material) => material['name']),
      <Object?>[
        'Matte warm table',
        'Upper matte object',
        'Lower matte object',
      ],
    );
    for (final material in materials) {
      final pbr = material['pbrMetallicRoughness']! as Map<String, Object?>;
      expect(pbr['metallicFactor'], 0.0);
      expect(pbr['roughnessFactor'], greaterThan(0.4));
    }
  });
}

Map<String, Object?> _readGlbJson(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(0, Endian.little), 0x46546C67);
  expect(data.getUint32(4, Endian.little), 2);

  final jsonChunkLength = data.getUint32(12, Endian.little);
  final jsonChunkType = data.getUint32(16, Endian.little);
  expect(jsonChunkType, 0x4E4F534A);
  final jsonBytes = bytes.sublist(20, 20 + jsonChunkLength);
  return jsonDecode(utf8.decode(jsonBytes).trimRight()) as Map<String, Object?>;
}
