import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_meshopt_rewriter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites meshopt-compressed bufferViews into embedded BIN bytes', () {
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['EXT_meshopt_compression'],
        'extensionsRequired': <Object?>['EXT_meshopt_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 30},
          <String, Object?>{
            'byteLength': 4,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'fallback': true,
              },
            },
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 1,
            'byteOffset': 0,
            'byteLength': 4,
            'byteStride': 4,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': 30,
                'byteStride': 4,
                'count': 1,
                'mode': 'ATTRIBUTES',
              },
            },
          },
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'componentType': 5121,
            'count': 4,
            'type': 'SCALAR',
          },
        ],
      },
      _attributeStream(<int>[1, 2, 3, 4]),
    );

    final result = rewriteMeshoptCompressedGlb(
      source,
      debugName: 'meshopt.glb',
    );

    expect(result.diagnostics, isEmpty);
    final rewritten = result.bytes!;
    final capabilities = readGlbAssetCapabilities(rewritten);
    expect(capabilities.extensionsUsed, isEmpty);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.meshoptCompressedBufferViewCount, 0);

    final chunks = _readGlb(rewritten);
    final json = chunks.json;
    final bufferViews = json['bufferViews'] as List<Object?>;
    final rewrittenView = bufferViews.single as Map<String, Object?>;
    expect(rewrittenView['extensions'], isNull);
    expect(rewrittenView['buffer'], 0);
    expect(rewrittenView['byteLength'], 4);
    expect((json['buffers'] as List<Object?>), hasLength(1));
    expect(chunks.bin.sublist(32, 36), <int>[1, 2, 3, 4]);
  });
}

Uint8List _attributeStream(List<int> values) {
  final bytes = Uint8List(30);
  bytes[0] = 0xa1;
  bytes[1] = 0xff;
  for (var index = 0; index < values.length; index += 1) {
    bytes[2 + index] = values[index] * 2;
  }
  return bytes;
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

({Map<String, Object?> json, Uint8List bin}) _readGlb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final jsonLength = data.getUint32(12, Endian.little);
  final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)));
  final binHeaderOffset = 20 + jsonLength;
  final binLength = data.getUint32(binHeaderOffset, Endian.little);
  final binOffset = binHeaderOffset + 8;
  return (
    json: (json as Map<Object?, Object?>).cast<String, Object?>(),
    bin: Uint8List.sublistView(bytes, binOffset, binOffset + binLength),
  );
}

int _align4(int value) => (value + 3) & ~3;
