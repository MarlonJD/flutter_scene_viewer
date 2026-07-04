import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_basisu_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rewrites BasisU texture images into ordinary GLB image bufferViews',
      () {
    final source = _basisuGlb();
    final pngBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2]);

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          bytes: pngBytes,
        ),
      ],
      debugName: 'basisu.glb',
    );

    expect(result.diagnostics, isEmpty);
    final rewritten = result.bytes!;
    final capabilities = readGlbAssetCapabilities(rewritten);
    expect(capabilities.basisuTextureCount, 0);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.extensionsUsed, isEmpty);
    expect(capabilities.diagnostics, isEmpty);

    final chunks = _readGlb(rewritten);
    final texture = (chunks.json['textures'] as List<Object?>).single
        as Map<String, Object?>;
    expect(texture['source'], 0);
    expect(texture['extensions'], isNull);

    final image =
        (chunks.json['images'] as List<Object?>).single as Map<String, Object?>;
    expect(image['mimeType'], 'image/png');
    expect(image['bufferView'], 1);
    expect(image['uri'], isNull);

    final bufferViews = chunks.json['bufferViews'] as List<Object?>;
    expect(bufferViews, hasLength(2));
    expect((bufferViews[1] as Map<String, Object?>)['byteLength'],
        pngBytes.length);
    expect(
      chunks.bin.sublist(4, 4 + pngBytes.length),
      pngBytes,
    );
  });

  test('reports missing decoded BasisU image payloads', () {
    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: const <GlbDecodedBasisuImage>[],
      debugName: 'basisu.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(
        result.diagnostics.single.details['extension'], 'KHR_texture_basisu');
    expect(result.diagnostics.single.details['decoder'], 'basisu');
    expect(result.diagnostics.single.details['status'], 'rewriteFailed');
    expect(result.diagnostics.single.details['imageIndex'], 0);
  });
}

Uint8List _basisuGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': 0},
          },
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

_GlbChunks _readGlb(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  Map<String, Object?>? json;
  Uint8List? bin;
  while (offset + 8 <= bytes.lengthInBytes) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkType == 0x4E4F534A) {
      json = (jsonDecode(
        utf8.decode(bytes.sublist(offset, offset + chunkLength)),
      ) as Map)
          .cast<String, Object?>();
    } else if (chunkType == 0x004E4942) {
      bin = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + chunkLength),
      );
    }
    offset += chunkLength;
  }
  return _GlbChunks(json!, bin!);
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

int _align4(int value) => (value + 3) & ~3;

final class _GlbChunks {
  const _GlbChunks(this.json, this.bin);

  final Map<String, Object?> json;
  final Uint8List bin;
}
