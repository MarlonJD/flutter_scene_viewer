import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_draco_rewriter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites Draco primitive accessors into GLB bufferViews', () {
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 4},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'componentType': 5126,
            'count': 1,
            'type': 'VEC3',
          },
          <String, Object?>{
            'componentType': 5123,
            'count': 3,
            'type': 'SCALAR',
          },
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'mode': 4,
                'attributes': <String, Object?>{'POSITION': 0},
                'indices': 1,
                'material': 0,
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'bufferView': 0,
                    'attributes': <String, Object?>{'POSITION': 0},
                  },
                },
              },
            ],
          },
        ],
      },
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );
    final positionBytes = _float32Bytes(<double>[1, 2, 3]);
    final indexBytes = _uint16Bytes(<int>[0, 0, 0]);

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': positionBytes},
          indices: indexBytes,
        ),
      ],
      debugName: 'draco.glb',
    );

    expect(result.diagnostics, isEmpty);
    final rewritten = result.bytes!;
    final capabilities = readGlbAssetCapabilities(
      rewritten,
      debugName: 'decoded.glb',
    );
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.extensionsUsed, isEmpty);
    expect(
      capabilities.compressedPrimitiveCounts['KHR_draco_mesh_compression'] ?? 0,
      0,
    );

    final chunks = _readGlb(rewritten);
    final json = chunks.json;
    final primitive = (((json['meshes'] as List<Object?>).single
            as Map<String, Object?>)['primitives'] as List<Object?>)
        .single as Map<String, Object?>;
    expect(primitive['extensions'], isNull);
    final accessors = json['accessors'] as List<Object?>;
    final positionAccessor = accessors[0] as Map<String, Object?>;
    final indexAccessor = accessors[1] as Map<String, Object?>;
    expect(positionAccessor['bufferView'], 1);
    expect(positionAccessor['byteOffset'], isNull);
    expect(indexAccessor['bufferView'], 2);
    expect(indexAccessor['byteOffset'], isNull);

    final bufferViews = json['bufferViews'] as List<Object?>;
    expect(bufferViews, hasLength(3));
    expect((bufferViews[1] as Map<String, Object?>)['byteLength'],
        positionBytes.length);
    expect((bufferViews[2] as Map<String, Object?>)['byteLength'],
        indexBytes.length);
    expect(
      ((json['buffers'] as List<Object?>).single
          as Map<String, Object?>)['byteLength'],
      chunks.bin.length,
    );
    expect(
      chunks.bin.sublist(4, 4 + positionBytes.length),
      positionBytes,
    );
    expect(
      chunks.bin.sublist(16, 16 + indexBytes.length),
      indexBytes,
    );
  });

  test('reports decoded Draco payloads that do not match accessor size', () {
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 4},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'componentType': 5126,
            'count': 1,
            'type': 'VEC3',
          },
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'POSITION': 0},
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'bufferView': 0,
                    'attributes': <String, Object?>{'POSITION': 0},
                  },
                },
              },
            ],
          },
        ],
      },
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'POSITION': Uint8List.fromList(<int>[1, 2, 3, 4]),
          },
        ),
      ],
      debugName: 'bad-draco.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostics.single.details['status'], 'rewriteFailed');
    expect(result.diagnostics.single.details['attribute'], 'POSITION');
    expect(result.diagnostics.single.details['expectedByteLength'], 12);
    expect(result.diagnostics.single.details['actualByteLength'], 4);
  });

  test('reports incomplete native Draco primitive payloads', () {
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 4},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'componentType': 5126,
            'count': 1,
            'type': 'VEC3',
          },
          <String, Object?>{
            'componentType': 5126,
            'count': 1,
            'type': 'VEC3',
          },
          <String, Object?>{
            'componentType': 5123,
            'count': 3,
            'type': 'SCALAR',
          },
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                },
                'indices': 2,
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'bufferView': 0,
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'NORMAL': 1,
                    },
                  },
                },
              },
            ],
          },
        ],
      },
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'POSITION': _float32Bytes(<double>[1, 2, 3]),
          },
        ),
      ],
      debugName: 'incomplete-draco.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(2));
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['attribute']),
      contains('NORMAL'),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['primitive']),
      contains('indices'),
    );
  });
}

Uint8List _glbWithBin(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final paddedBinLength = _align4(bin.length);
  final totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length;
      index < 20 + paddedJsonLength;
      index += 1) {
    bytes[index] = 0x20;
  }
  final binHeaderOffset = 20 + paddedJsonLength;
  data
    ..setUint32(binHeaderOffset, paddedBinLength, Endian.little)
    ..setUint32(binHeaderOffset + 4, 0x004E4942, Endian.little);
  bytes.setRange(binHeaderOffset + 8, binHeaderOffset + 8 + bin.length, bin);
  return bytes;
}

_GlbChunks _readGlb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  Map<String, Object?>? json;
  Uint8List? bin;
  while (offset + 8 <= bytes.length) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    final chunk = Uint8List.sublistView(bytes, offset, offset + chunkLength);
    if (chunkType == 0x4E4F534A) {
      json = (jsonDecode(utf8.decode(chunk)) as Map).cast<String, Object?>();
    } else if (chunkType == 0x004E4942) {
      bin = Uint8List.fromList(chunk);
    }
    offset += chunkLength;
  }
  return _GlbChunks(json: json!, bin: bin!);
}

Uint8List _float32Bytes(List<double> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setFloat32(index * 4, values[index], Endian.little);
  }
  return bytes;
}

Uint8List _uint16Bytes(List<int> values) {
  final bytes = Uint8List(values.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setUint16(index * 2, values[index], Endian.little);
  }
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;

final class _GlbChunks {
  const _GlbChunks({required this.json, required this.bin});

  final Map<String, Object?> json;
  final Uint8List bin;
}
