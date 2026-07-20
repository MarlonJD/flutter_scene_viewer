import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/meshopt_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureRoot = 'test/fixtures/meshopt/MeshoptCubeTest';

void main() {
  test('decodes every officially covered claimed mode and filter', () async {
    final fixture = _readJson('$_fixtureRoot/glTF/MeshoptCubeTest.gltf');
    final buffers = _maps(fixture['buffers']);
    final bufferBytes = <int, Uint8List>{
      for (final entry in buffers.indexed)
        entry.$1:
            File('$_fixtureRoot/glTF/${entry.$2['uri']}').readAsBytesSync(),
    };
    final bufferViews = _maps(fixture['bufferViews']);
    final observedModes = <String>{};
    final observedFilters = <String>{};
    final observedCases = <String, int>{};
    final exactMismatchCounts = <String, int>{};
    final decodedViewIndexes = <int>{};
    final attributeStreamVersions = <int>{};
    final attributeFilterVersions = <String, Set<int>>{};
    var comparedViewCount = 0;
    var colorViewCount = 0;

    for (final indexedView in bufferViews.indexed) {
      final view = indexedView.$2;
      final extensions = _nullableMap(view['extensions']);
      final compression = _nullableMap(extensions?['KHR_meshopt_compression']);
      if (compression == null) {
        continue;
      }

      final filterName = compression['filter'] as String? ?? 'NONE';
      if (filterName == 'COLOR') {
        colorViewCount += 1;
        expect(MeshoptCompressionFilter.fromJson(filterName), isNull);
        continue;
      }

      final modeName = compression['mode'] as String;
      final mode = MeshoptCompressionMode.fromJson(modeName);
      final filter = MeshoptCompressionFilter.fromJson(filterName);
      expect(mode, isNotNull, reason: 'bufferView ${indexedView.$1} mode');
      expect(filter, isNotNull, reason: 'bufferView ${indexedView.$1} filter');

      final encoded = _slice(
        bufferBytes[compression['buffer'] as int]!,
        compression['byteOffset'] as int? ?? 0,
        compression['byteLength'] as int,
      );
      final expected = _slice(
        bufferBytes[view['buffer'] as int]!,
        view['byteOffset'] as int? ?? 0,
        view['byteLength'] as int,
      );
      if (mode == MeshoptCompressionMode.attributes) {
        expect(encoded.first & 0xf0, 0xa0);
        final version = encoded.first & 0x0f;
        attributeStreamVersions.add(version);
        attributeFilterVersions
            .putIfAbsent(filterName, () => <int>{})
            .add(version);
      }
      final decoded = await decodeMeshoptGltfBuffer(
        encoded,
        count: compression['count'] as int,
        byteStride: compression['byteStride'] as int,
        mode: mode!,
        filter: filter!,
      );
      final caseName = '$modeName/$filterName';
      observedCases.update(caseName, (count) => count + 1, ifAbsent: () => 1);
      if (!_bytesEqual(decoded, expected)) {
        exactMismatchCounts.update(
          caseName,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      if (mode == MeshoptCompressionMode.triangles) {
        expect(
          _triangleListsMatchModuloCyclicRotation(
            decoded,
            expected,
            indexByteStride: compression['byteStride'] as int,
          ),
          isTrue,
          reason: 'bufferView ${indexedView.$1} $modeName/$filterName',
        );
      } else {
        expect(
          decoded,
          orderedEquals(expected),
          reason: 'bufferView ${indexedView.$1} $modeName/$filterName',
        );
      }
      observedModes.add(modeName);
      observedFilters.add(filterName);
      decodedViewIndexes.add(indexedView.$1);
      comparedViewCount += 1;
    }

    expect(comparedViewCount, 54);
    expect(
      observedModes,
      <String>{'ATTRIBUTES', 'TRIANGLES', 'INDICES'},
    );
    expect(
      observedFilters,
      <String>{'NONE', 'OCTAHEDRAL', 'QUATERNION', 'EXPONENTIAL'},
    );
    expect(colorViewCount, 6);
    expect(observedCases, <String, int>{
      'ATTRIBUTES/NONE': 24,
      'ATTRIBUTES/OCTAHEDRAL': 6,
      'ATTRIBUTES/QUATERNION': 2,
      'ATTRIBUTES/EXPONENTIAL': 6,
      'TRIANGLES/NONE': 12,
      'INDICES/NONE': 4,
    });
    expect(attributeStreamVersions, <int>{0, 1});
    for (final filterName in const <String>{
      'NONE',
      'OCTAHEDRAL',
      'QUATERNION',
      'EXPONENTIAL',
    }) {
      expect(
        attributeFilterVersions[filterName],
        contains(0),
        reason: '$filterName requires an official v0 stream before it can '
            'count as EXT_meshopt_compression runtime evidence.',
      );
    }
    expect(
      exactMismatchCounts,
      <String, int>{'TRIANGLES/NONE': 12},
      reason: 'TRIANGLES may cyclically rotate each index triple while '
          'preserving triangle order and winding; every other claimed case '
          'must remain byte-exact against the fallback.',
    );

    final extensionsUsed = (fixture['extensionsUsed'] as List<Object?>).toSet();
    expect(extensionsUsed, contains('KHR_mesh_quantization'));
    final accessors = _maps(fixture['accessors']);
    final decodedQuantizedSemantics = <String>{};
    for (final mesh in _maps(fixture['meshes'])) {
      for (final primitive in _maps(mesh['primitives'])) {
        final attributes = _nullableMap(primitive['attributes'])!;
        for (final attribute in attributes.entries) {
          final accessor = accessors[attribute.value as int];
          if (decodedViewIndexes.contains(accessor['bufferView']) &&
              const <int>{5120, 5121, 5122, 5123}
                  .contains(accessor['componentType'])) {
            decodedQuantizedSemantics.add(attribute.key);
          }
        }
      }
    }
    expect(
      decodedQuantizedSemantics.intersection(
        const <String>{'NORMAL', 'POSITION', 'TANGENT'},
      ),
      contains('NORMAL'),
    );
  });

  test('official placeholder fallback buffers satisfy the scoped contract', () {
    final fixture =
        _readJson('$_fixtureRoot/glTF-Meshopt/MeshoptCubeTest.gltf');
    final required = (fixture['extensionsRequired'] as List<Object?>).toSet();
    expect(required, contains('KHR_meshopt_compression'));

    final buffers = _maps(fixture['buffers']);
    final bufferViews = _maps(fixture['bufferViews']);
    final fallbackBufferIndexes = <int>[];
    for (final indexedBuffer in buffers.indexed) {
      final buffer = indexedBuffer.$2;
      final compression = _nullableMap(
        _nullableMap(buffer['extensions'])?['KHR_meshopt_compression'],
      );
      if (compression?['fallback'] != true) {
        continue;
      }
      fallbackBufferIndexes.add(indexedBuffer.$1);
      expect(indexedBuffer.$1, greaterThanOrEqualTo(1));
      expect(buffer.containsKey('uri'), isFalse);
      final declaredLength = buffer['byteLength'] as int;
      for (final view in bufferViews.where(
        (candidate) => candidate['buffer'] == indexedBuffer.$1,
      )) {
        expect(
          _nullableMap(
            _nullableMap(view['extensions'])?['KHR_meshopt_compression'],
          ),
          isNotNull,
        );
        final byteOffset = view['byteOffset'] as int? ?? 0;
        final byteLength = view['byteLength'] as int;
        expect(byteOffset + byteLength, lessThanOrEqualTo(declaredLength));
      }
    }

    expect(fallbackBufferIndexes, isNotEmpty);
    expect(
      bufferViews.where(
        (view) => fallbackBufferIndexes.contains(view['buffer']),
      ),
      isNotEmpty,
    );
    for (final view in bufferViews) {
      final compression = _nullableMap(
        _nullableMap(view['extensions'])?['KHR_meshopt_compression'],
      );
      if (compression != null) {
        expect(
          fallbackBufferIndexes,
          isNot(contains(compression['buffer'])),
        );
      }
    }
  });

  test('TRIANGLES fallback comparison rejects reversed winding', () {
    expect(
      _triangleListsMatchModuloCyclicRotation(
        Uint8List.fromList(<int>[0, 0, 1, 0, 2, 0]),
        Uint8List.fromList(<int>[0, 0, 2, 0, 1, 0]),
        indexByteStride: 2,
      ),
      isFalse,
    );
  });
}

Map<String, Object?> _readJson(String path) {
  return Map<String, Object?>.from(
    jsonDecode(File(path).readAsStringSync()) as Map,
  );
}

List<Map<String, Object?>> _maps(Object? value) {
  return (value! as List<Object?>)
      .map((entry) => Map<String, Object?>.from(entry! as Map))
      .toList(growable: false);
}

Map<String, Object?>? _nullableMap(Object? value) {
  return value == null ? null : Map<String, Object?>.from(value as Map);
}

Uint8List _slice(Uint8List source, int offset, int length) {
  return Uint8List.sublistView(source, offset, offset + length);
}

bool _triangleListsMatchModuloCyclicRotation(
  Uint8List actual,
  Uint8List expected, {
  required int indexByteStride,
}) {
  if ((indexByteStride != 2 && indexByteStride != 4) ||
      actual.lengthInBytes != expected.lengthInBytes ||
      actual.lengthInBytes % (indexByteStride * 3) != 0) {
    return false;
  }
  final actualData = ByteData.sublistView(actual);
  final expectedData = ByteData.sublistView(expected);
  for (var offset = 0;
      offset < actual.lengthInBytes;
      offset += indexByteStride * 3) {
    final actualTriangle = <int>[
      _readIndex(actualData, offset, indexByteStride),
      _readIndex(actualData, offset + indexByteStride, indexByteStride),
      _readIndex(actualData, offset + indexByteStride * 2, indexByteStride),
    ];
    final expectedTriangle = <int>[
      _readIndex(expectedData, offset, indexByteStride),
      _readIndex(expectedData, offset + indexByteStride, indexByteStride),
      _readIndex(expectedData, offset + indexByteStride * 2, indexByteStride),
    ];
    final matches = (actualTriangle[0] == expectedTriangle[0] &&
            actualTriangle[1] == expectedTriangle[1] &&
            actualTriangle[2] == expectedTriangle[2]) ||
        (actualTriangle[0] == expectedTriangle[1] &&
            actualTriangle[1] == expectedTriangle[2] &&
            actualTriangle[2] == expectedTriangle[0]) ||
        (actualTriangle[0] == expectedTriangle[2] &&
            actualTriangle[1] == expectedTriangle[0] &&
            actualTriangle[2] == expectedTriangle[1]);
    if (!matches) {
      return false;
    }
  }
  return true;
}

int _readIndex(ByteData data, int offset, int byteStride) {
  return byteStride == 2
      ? data.getUint16(offset, Endian.little)
      : data.getUint32(offset, Endian.little);
}

bool _bytesEqual(Uint8List left, Uint8List right) {
  if (left.lengthInBytes != right.lengthInBytes) {
    return false;
  }
  for (var index = 0; index < left.lengthInBytes; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
