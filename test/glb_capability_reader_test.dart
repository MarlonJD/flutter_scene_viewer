import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects A1B32-style required Draco and specular IOR metadata', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>[
          'KHR_draco_mesh_compression',
          'KHR_materials_specular',
          'KHR_materials_ior',
        ],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'nodes': <Object?>[
          <String, Object?>{'name': 'A1B32', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              _dracoPrimitive(material: 0),
              _dracoPrimitive(material: 1),
            ],
          },
        ],
        'materials': <Object?>[
          _specularIorMaterial(baseColorTexture: 0, normalTexture: 2),
          _specularIorMaterial(baseColorTexture: 1),
        ],
        'textures': <Object?>[
          <String, Object?>{'source': 0},
          <String, Object?>{'source': 1},
          <String, Object?>{'source': 2},
        ],
        'images': <Object?>[
          <String, Object?>{'mimeType': 'image/jpeg', 'bufferView': 0},
          <String, Object?>{'mimeType': 'image/jpeg', 'bufferView': 1},
          <String, Object?>{'mimeType': 'image/png', 'bufferView': 2},
        ],
      }),
      debugName: 'a1b32-style.glb',
      decoderCapabilities: const GlbDecoderCapabilities(),
    );

    expect(result.statistics.nodeCount, 1);
    expect(result.statistics.meshCount, 1);
    expect(result.statistics.primitiveCount, 2);
    expect(result.statistics.materialCount, 2);
    expect(result.statistics.textureCount, 3);
    expect(result.compressedPrimitiveCounts['KHR_draco_mesh_compression'], 2);
    expect(result.materialExtensionCounts['KHR_materials_specular'], 2);
    expect(result.materialExtensionCounts['KHR_materials_ior'], 2);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(
      result.diagnostics.single.details['extension'],
      'KHR_draco_mesh_compression',
    );
    expect(result.diagnostics.single.details['required'], isTrue);
    expect(result.diagnostics.single.details['primitiveCount'], 2);
  });

  test('does not report required Draco when decoder capability is available',
      () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              _dracoPrimitive(material: 0),
            ],
          },
        ],
      }),
      decoderCapabilities: const GlbDecoderCapabilities(
        dracoMeshCompression: true,
      ),
    );

    expect(result.compressedPrimitiveCounts['KHR_draco_mesh_compression'], 1);
    expect(result.diagnostics, isEmpty);
  });

  test('classifies imported GLB texture slots by content role', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'materials': <Object?>[
          <String, Object?>{
            'pbrMetallicRoughness': <String, Object?>{
              'baseColorTexture': <String, Object?>{'index': 0},
              'metallicRoughnessTexture': <String, Object?>{'index': 1},
            },
            'normalTexture': <String, Object?>{'index': 2},
            'occlusionTexture': <String, Object?>{'index': 3},
            'emissiveTexture': <String, Object?>{'index': 4},
            'extensions': <String, Object?>{
              'KHR_materials_specular': <String, Object?>{
                'specularTexture': <String, Object?>{'index': 5},
                'specularColorTexture': <String, Object?>{'index': 6},
              },
              'KHR_materials_transmission': <String, Object?>{
                'transmissionTexture': <String, Object?>{'index': 7},
              },
              'KHR_materials_clearcoat': <String, Object?>{
                'clearcoatTexture': <String, Object?>{'index': 8},
                'clearcoatRoughnessTexture': <String, Object?>{'index': 9},
                'clearcoatNormalTexture': <String, Object?>{'index': 10},
              },
              'KHR_materials_sheen': <String, Object?>{
                'sheenColorTexture': <String, Object?>{'index': 11},
                'sheenRoughnessTexture': <String, Object?>{'index': 12},
              },
            },
          },
        ],
      }),
    );

    expect(_roleBySlot(result, 'baseColorTexture'), GlbTextureRole.color);
    expect(
      _roleBySlot(result, 'metallicRoughnessTexture'),
      GlbTextureRole.data,
    );
    expect(_roleBySlot(result, 'normalTexture'), GlbTextureRole.normal);
    expect(_roleBySlot(result, 'occlusionTexture'), GlbTextureRole.data);
    expect(_roleBySlot(result, 'emissiveTexture'), GlbTextureRole.color);
    expect(
      _roleBySlot(result, 'KHR_materials_specular.specularTexture'),
      GlbTextureRole.data,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_specular.specularColorTexture'),
      GlbTextureRole.color,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_transmission.transmissionTexture'),
      GlbTextureRole.data,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_clearcoat.clearcoatTexture'),
      GlbTextureRole.data,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_clearcoat.clearcoatRoughnessTexture'),
      GlbTextureRole.data,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_clearcoat.clearcoatNormalTexture'),
      GlbTextureRole.normal,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_sheen.sheenColorTexture'),
      GlbTextureRole.color,
    );
    expect(
      _roleBySlot(result, 'KHR_materials_sheen.sheenRoughnessTexture'),
      GlbTextureRole.data,
    );
  });

  test('records imported texture slot UV set requirements', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'materials': <Object?>[
          <String, Object?>{
            'pbrMetallicRoughness': <String, Object?>{
              'baseColorTexture': <String, Object?>{
                'index': 0,
                'texCoord': 1,
              },
            },
            'normalTexture': <String, Object?>{'index': 1},
          },
        ],
      }),
    );

    expect(_slotByName(result, 'baseColorTexture').texCoord, 1);
    expect(_slotByName(result, 'normalTexture').texCoord, 0);
  });

  test('leaves effective texture UV validation to the binding reader', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                  'TEXCOORD_0': 2,
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
            'normalTexture': <String, Object?>{'index': 1},
          },
        ],
      }),
      debugName: 'missing-uv1.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(_slotByName(result, 'baseColorTexture').texCoord, 1);
    final context = result.primitiveTextureContexts.single;
    expect(context.availableTexCoords, <int>{0});
    expect(context.textureTransformRequired, isFalse);
  });

  test('accepts Draco extension attributes as imported texture UV evidence',
      () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                },
                'material': 0,
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'bufferView': 0,
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'NORMAL': 1,
                      'TEXCOORD_0': 2,
                    },
                  },
                },
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
      }),
    );

    expect(result.diagnostics, isEmpty);
    expect(
      result.primitiveTextureContexts.single.availableTexCoords,
      <int>{0},
    );
  });

  test('supplies primitive UV availability and transform requiredness', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsRequired': <Object?>['KHR_texture_transform'],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'TEXCOORD_0': 1,
                },
                'material': 3,
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'attributes': <String, Object?>{'TEXCOORD_2': 4},
                  },
                },
              },
            ],
          },
        ],
      }),
      decoderCapabilities: const GlbDecoderCapabilities(
        dracoMeshCompression: true,
      ),
    );

    final context = result.primitiveTextureContexts.single;
    expect(context.meshIndex, 0);
    expect(context.primitiveIndex, 0);
    expect(context.materialIndex, 3);
    expect(context.availableTexCoords, <int>{0, 2});
    expect(context.textureTransformRequired, isTrue);
  });

  test('reports required meshopt and BasisU decoder gaps', () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>[
          'EXT_meshopt_compression',
          'KHR_texture_basisu',
        ],
        'extensionsRequired': <Object?>[
          'EXT_meshopt_compression',
          'KHR_texture_basisu',
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteLength': 64,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': 64,
                'byteStride': 12,
                'count': 3,
                'mode': 'ATTRIBUTES',
              },
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
          <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
        ],
      }),
      decoderCapabilities: const GlbDecoderCapabilities(),
    );

    expect(result.meshoptCompressedBufferViewCount, 1);
    expect(result.basisuTextureCount, 1);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['extension']),
      containsAll(<String>[
        'EXT_meshopt_compression',
        'KHR_texture_basisu',
      ]),
    );
  });

  test('reports KTX2 header details for BasisU decoder gaps', () {
    final result = readGlbAssetCapabilities(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_texture_basisu'],
          'extensionsRequired': <Object?>['KHR_texture_basisu'],
          'textures': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_texture_basisu': <String, Object?>{'source': 0},
              },
            },
          ],
          'images': <Object?>[
            <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
          ],
          'bufferViews': <Object?>[
            <String, Object?>{
              'buffer': 0,
              'byteLength': _basisuKtx2Header.length,
            },
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': _basisuKtx2Header.length},
          ],
        },
        <Uint8List>[_basisuKtx2Header],
      ),
      debugName: 'basisu-preflight.glb',
      decoderCapabilities: const GlbDecoderCapabilities(),
    );

    final diagnostic = result.diagnostics
        .where(
          (diagnostic) =>
              diagnostic.details['extension'] == 'KHR_texture_basisu',
        )
        .single;
    expect(diagnostic.details['status'], 'basisuTranscodeUnavailable');
    expect(
      diagnostic.details['reason'],
      contains('Basis Universal ETC1S/UASTC transcode support'),
    );
    expect(
      diagnostic.details['nextStep'],
      contains('optional BasisU transcoder plugin'),
    );
    expect(diagnostic.details['ktx2Images'], hasLength(1));
    expect(
      diagnostic.details['ktx2Images'],
      contains(
        allOf(
          containsPair('supercompression', 'basisLz'),
          containsPair('vkFormat', 0),
          containsPair('imageIndex', 0),
        ),
      ),
    );
  });

  test('reports optional compression decoder gaps as non-blocking diagnostics',
      () {
    final result = readGlbAssetCapabilities(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>[
          'KHR_draco_mesh_compression',
          'EXT_meshopt_compression',
          'KHR_texture_basisu',
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              _dracoPrimitive(material: 0),
            ],
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteLength': 64,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': 64,
                'byteStride': 12,
                'count': 3,
                'mode': 'ATTRIBUTES',
              },
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
      }),
      debugName: 'optional-compression.glb',
      decoderCapabilities: const GlbDecoderCapabilities(),
    );

    expect(result.diagnostics, hasLength(3));
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['extension']),
      containsAll(<String>[
        'KHR_draco_mesh_compression',
        'EXT_meshopt_compression',
        'KHR_texture_basisu',
      ]),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['required']),
      everyElement(isFalse),
    );
  });

  test('invalid GLB headers produce diagnostics instead of throwing', () {
    final result = readGlbAssetCapabilities(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      debugName: 'broken.glb',
    );

    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.adapterFailure);
  });

  test('JSON reader limit does not reject a larger decoded BIN chunk', () {
    final result = readGlbAssetCapabilities(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_materials_specular'],
          'materials': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_materials_specular': <String, Object?>{
                  'specularFactor': 0.8,
                },
              },
            },
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 8 * 1024 * 1024 + 4},
          ],
        },
        <Uint8List>[Uint8List(8 * 1024 * 1024 + 4)],
      ),
      debugName: 'decoded-large-bin.glb',
    );

    expect(
      result.diagnostics.where(
        (diagnostic) => diagnostic.code == ViewerDiagnosticCode.adapterFailure,
      ),
      isEmpty,
    );
    expect(result.materialExtensionCounts['KHR_materials_specular'], 1);
  });
}

GlbTextureRole? _roleBySlot(GlbAssetCapabilityResult result, String slot) {
  return _slotByName(result, slot).role;
}

GlbTextureSlot _slotByName(GlbAssetCapabilityResult result, String slot) {
  return result.textureSlots.where((texture) => texture.slot == slot).single;
}

Map<String, Object?> _dracoPrimitive({required int material}) {
  return <String, Object?>{
    'attributes': <String, Object?>{
      'POSITION': 0,
      'NORMAL': 1,
      'TEXCOORD_0': 2,
    },
    'material': material,
    'extensions': <String, Object?>{
      'KHR_draco_mesh_compression': <String, Object?>{
        'bufferView': 0,
        'attributes': <String, Object?>{
          'POSITION': 0,
          'NORMAL': 1,
          'TEXCOORD_0': 2,
        },
      },
    },
  };
}

Map<String, Object?> _specularIorMaterial({
  required int baseColorTexture,
  int? normalTexture,
}) {
  return <String, Object?>{
    'pbrMetallicRoughness': <String, Object?>{
      'baseColorTexture': <String, Object?>{'index': baseColorTexture},
    },
    if (normalTexture != null)
      'normalTexture': <String, Object?>{'index': normalTexture},
    'extensions': <String, Object?>{
      'KHR_materials_specular': <String, Object?>{
        'specularFactor': 0.8,
      },
      'KHR_materials_ior': <String, Object?>{'ior': 1.45},
    },
  };
}

Uint8List _glb(Map<String, Object?> json) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final totalLength = 12 + 8 + paddedJsonLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length; index < bytes.length; index += 1) {
    bytes[index] = 0x20;
  }
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

int _align4(int value) => (value + 3) & ~3;
