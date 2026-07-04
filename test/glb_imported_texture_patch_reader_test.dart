import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_imported_texture_patch_reader.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_scene_viewer/src/texture_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads core imported GLB texture patches from binary image bufferViews',
      () {
    final baseColorBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final dataBytes = Uint8List.fromList(<int>[4, 5, 6, 7]);
    final normalBytes = Uint8List.fromList(<int>[8, 9]);
    final occlusionBytes = Uint8List.fromList(<int>[10, 11, 12]);
    final emissiveBytes = Uint8List.fromList(<int>[13, 14]);
    final imageBytes = <Uint8List>[
      baseColorBytes,
      dataBytes,
      normalBytes,
      occlusionBytes,
      emissiveBytes,
    ];
    final result = readGlbImportedTexturePatches(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'TextilePanel', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{
                    'POSITION': 0,
                    'TEXCOORD_0': 1,
                  },
                  'material': 0,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'pbrMetallicRoughness': <String, Object?>{
                'baseColorTexture': <String, Object?>{'index': 0},
                'metallicRoughnessTexture': <String, Object?>{'index': 1},
              },
              'normalTexture': <String, Object?>{'index': 2, 'scale': 0.75},
              'occlusionTexture': <String, Object?>{
                'index': 3,
                'strength': 0.5,
              },
              'emissiveTexture': <String, Object?>{'index': 4},
            },
          ],
          'textures': <Object?>[
            for (var index = 0; index < imageBytes.length; index += 1)
              <String, Object?>{'source': index},
          ],
          'images': <Object?>[
            for (var index = 0; index < imageBytes.length; index += 1)
              <String, Object?>{
                'mimeType': 'image/png',
                'bufferView': index,
              },
          ],
          'bufferViews': <Object?>[
            for (var index = 0, offset = 0;
                index < imageBytes.length;
                offset += imageBytes[index].length, index += 1)
              <String, Object?>{
                'buffer': 0,
                'byteOffset': offset,
                'byteLength': imageBytes[index].length,
              },
          ],
          'buffers': <Object?>[
            <String, Object?>{
              'byteLength': imageBytes.fold<int>(
                0,
                (sum, bytes) => sum + bytes.length,
              ),
            },
          ],
        },
        imageBytes,
      ),
      debugName: 'textures.glb',
    );

    expect(result.diagnostics, isEmpty);
    final patch = result.patches[PartAddress(
      nodePath: <String>['TextilePanel'],
      primitiveIndex: 0,
    )]!;
    expect(
      (patch.baseColorTexture! as BytesTextureSource).encodedBytes,
      baseColorBytes,
    );
    expect(
      (patch.metallicRoughnessTexture! as BytesTextureSource).encodedBytes,
      dataBytes,
    );
    expect(
      (patch.normalTexture! as BytesTextureSource).encodedBytes,
      normalBytes,
    );
    expect(patch.normalScale, 0.75);
    expect(
      (patch.occlusionTexture! as BytesTextureSource).encodedBytes,
      occlusionBytes,
    );
    expect(patch.occlusionStrength, 0.5);
    expect(
      (patch.emissiveTexture! as BytesTextureSource).encodedBytes,
      emissiveBytes,
    );
  });

  test('reports imported core texture slots that require non-zero texCoord',
      () {
    final imageBytes = <Uint8List>[
      Uint8List.fromList(<int>[1, 2, 3])
    ];
    final result = readGlbImportedTexturePatches(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'TexCoordPanel', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{
                    'POSITION': 0,
                    'TEXCOORD_0': 1,
                    'TEXCOORD_1': 2,
                  },
                  'material': 0,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'pbrMetallicRoughness': <String, Object?>{
                'baseColorTexture': <String, Object?>{
                  'index': 0,
                  'texCoord': 1,
                },
              },
            },
          ],
          'textures': <Object?>[
            <String, Object?>{'source': 0},
          ],
          'images': <Object?>[
            <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
          ],
          'bufferViews': <Object?>[
            <String, Object?>{'buffer': 0, 'byteLength': 3},
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 3},
          ],
        },
        imageBytes,
      ),
      debugName: 'texcoord1.glb',
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(
        result.diagnostics.single.details['textureSlot'], 'baseColorTexture');
    expect(result.diagnostics.single.details['uvSet'], 1);
  });

  test('reports imported core BasisU texture sources as unsupported', () {
    final result = readGlbImportedTexturePatches(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'BasisPanel', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{
                    'POSITION': 0,
                    'TEXCOORD_0': 1,
                  },
                  'material': 0,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'pbrMetallicRoughness': <String, Object?>{
                'baseColorTexture': <String, Object?>{'index': 0},
              },
            },
          ],
          'textures': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_texture_basisu': <String, Object?>{'source': 0},
              },
            },
          ],
          'images': <Object?>[
            <String, Object?>{
              'mimeType': 'image/ktx2',
              'bufferView': 0,
            },
          ],
          'bufferViews': <Object?>[
            <String, Object?>{
              'buffer': 0,
              'byteLength': _basisuKtx2Header.length,
            },
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 4},
          ],
        },
        <Uint8List>[_basisuKtx2Header],
      ),
      debugName: 'basisu-core.glb',
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(
      result.diagnostics.single.details['requiredExtension'],
      'KHR_texture_basisu',
    );
    expect(
      result.diagnostics.single.details['status'],
      'basisuTranscodeUnavailable',
    );
    expect(
      result.diagnostics.single.details['reason'],
      contains('Basis Universal ETC1S/UASTC transcode support'),
    );
    expect(
      result.diagnostics.single.details['nextStep'],
      contains('optional BasisU transcoder plugin'),
    );
    expect(
      result.diagnostics.single.details['ktx2'],
      containsPair('supercompression', 'basisLz'),
    );
    expect(
      result.diagnostics.single.details['ktx2'],
      containsPair('vkFormat', 0),
    );
  });
}

final Uint8List _basisuKtx2Header = _ktx2Header(
  vkFormat: 0,
  pixelWidth: 4,
  pixelHeight: 4,
  levelCount: 1,
  supercompressionScheme: 1,
);

Uint8List _ktx2Header({
  required int vkFormat,
  required int pixelWidth,
  required int pixelHeight,
  required int levelCount,
  required int supercompressionScheme,
}) {
  final bytes = Uint8List(80);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 12, const <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x32,
    0x30,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  data
    ..setUint32(12, vkFormat, Endian.little)
    ..setUint32(16, 1, Endian.little)
    ..setUint32(20, pixelWidth, Endian.little)
    ..setUint32(24, pixelHeight, Endian.little)
    ..setUint32(36, 1, Endian.little)
    ..setUint32(40, levelCount, Endian.little)
    ..setUint32(44, supercompressionScheme, Endian.little);
  return bytes;
}

Uint8List _glbWithBin(Map<String, Object?> json, List<Uint8List> chunks) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final binLength = chunks.fold<int>(0, (sum, bytes) => sum + bytes.length);
  final paddedBinLength = _align4(binLength);
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
  var binOffset = binHeaderOffset + 8;
  for (final chunk in chunks) {
    bytes.setRange(binOffset, binOffset + chunk.length, chunk);
    binOffset += chunk.length;
  }
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;
