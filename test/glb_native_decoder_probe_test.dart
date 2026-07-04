import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_native_decoder_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeGlb rewrites native decoded Draco primitive payloads', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/draco');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final compressed = _compressedGlb();
    final positionBytes = _float32Bytes(<double>[1, 2, 3]);
    final indexBytes = _uint16Bytes(<int>[0, 0, 0]);
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      final primitives = arguments['dracoPrimitives'] as List<Object?>;
      expect(primitives, hasLength(1));
      final primitive = primitives.single as Map<Object?, Object?>;
      expect(primitive['meshIndex'], 0);
      expect(primitive['primitiveIndex'], 0);
      expect(
          primitive['compressedBytes'], Uint8List.fromList(<int>[9, 9, 9, 9]));
      expect(primitive['attributes'], <String, Object?>{'POSITION': 0});
      expect(
        primitive['attributeAccessors'],
        <String, Object?>{
          'POSITION': <String, Object?>{
            'accessorIndex': 0,
            'componentType': 5126,
            'type': 'VEC3',
            'count': 1,
            'normalized': false,
          },
        },
      );
      expect(
        primitive['indicesAccessor'],
        <String, Object?>{
          'accessorIndex': 1,
          'componentType': 5123,
          'type': 'SCALAR',
          'count': 3,
          'normalized': false,
        },
      );
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedPrimitives': <Object?>[
          <String, Object?>{
            'meshIndex': 0,
            'primitiveIndex': 0,
            'attributes': <String, Object?>{
              'POSITION': positionBytes,
            },
            'indices': indexBytes,
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: compressed,
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      source: 'draco.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    final capabilities = readGlbAssetCapabilities(result.bytes!);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(
      capabilities.compressedPrimitiveCounts['KHR_draco_mesh_compression'] ?? 0,
      0,
    );
  });

  test('decodeGlb rewrites native decoded BasisU image payloads', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final compressed = _basisuGlb();
    final pngBytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1, 2]);
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages'] as List<Object?>;
      expect(images, hasLength(1));
      final image = images.single as Map<Object?, Object?>;
      expect(image['textureIndex'], 0);
      expect(image['imageIndex'], 0);
      expect(image['mimeType'], 'image/ktx2');
      expect(image['bytes'], Uint8List.fromList(<int>[9, 9, 9, 9]));
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'bytes': pngBytes,
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: compressed,
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      source: 'basisu.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    final capabilities = readGlbAssetCapabilities(result.bytes!);
    expect(capabilities.basisuTextureCount, 0);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.diagnostics, isEmpty);
  });
}

Uint8List _compressedGlb() {
  return _glbWithBin(
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
              'attributes': <String, Object?>{'POSITION': 0},
              'indices': 1,
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
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
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
