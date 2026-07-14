import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_basisu_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'reserves exact texture pixels and rejects a PNG IHDR mismatch atomically',
      () {
    final exactBudget = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTexturePixels: 6),
    );
    final exact = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          width: 2,
          height: 3,
          bytes: _pngBytes(width: 2, height: 3),
        ),
      ],
      budgetTracker: exactBudget,
    );
    expect(exact.diagnostics, isEmpty);
    expect(exactBudget.texturePixels, 6);

    final overBudget = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTexturePixels: 6),
    )..reserveTexturePixels(width: 1, height: 1, stage: 'priorDecoder');
    final over = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          width: 2,
          height: 3,
          bytes: _pngBytes(width: 2, height: 3),
        ),
      ],
      budgetTracker: overBudget,
    );
    expect(over.bytes, isNull);
    expect(over.diagnostics.single.details,
        containsPair('field', 'texturePixels'));
    expect(over.diagnostics.single.details, containsPair('actual', 7));
    expect(overBudget.texturePixels, 1);
    expect(overBudget.nativeOutputBytes, 0);
    expect(overBudget.totalDecodedBytes, 0);

    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTexturePixels: 100),
    )..reserveTexturePixels(width: 1, height: 1, stage: 'priorDecoder');
    final mismatch = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          width: 2,
          height: 3,
          bytes: _pngBytes(width: 3, height: 2),
        ),
      ],
      budgetTracker: tracker,
    );
    expect(mismatch.bytes, isNull);
    expect(mismatch.diagnostics.single.details,
        containsPair('status', 'malformedOutput'));
    expect(mismatch.diagnostics.single.details,
        containsPair('field', 'decodedImages[0].bytes.IHDR'));
    expect(tracker.texturePixels, 1);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);
  });

  test('rewrites BasisU texture images into ordinary GLB image bufferViews',
      () {
    final source = _basisuGlb();
    final pngBytes = _pngBytes(width: 1, height: 1);

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          width: 1,
          height: 1,
          bytes: pngBytes,
        ),
      ],
      debugName: 'basisu.glb',
      budget: const GlbDecodeBudget(),
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

  test('accepts exact JSON budget and rejects one byte below it', () {
    final source = _basisuGlb();
    final jsonBytes = _jsonChunkLength(source);
    final decoded = <GlbDecodedBasisuImage>[_decodedImage(0, 3)];

    final exact = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: decoded,
      budget: GlbDecodeBudget(maxJsonBytes: jsonBytes),
    );
    expect(exact.diagnostics, isEmpty);

    final over = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: decoded,
      budget: GlbDecodeBudget(maxJsonBytes: jsonBytes - 1),
    );
    expect(over.bytes, isNull);
    expect(over.diagnostics, hasLength(1));
    expect(over.diagnostics.single.details, containsPair('field', 'jsonBytes'));
    expect(
        over.diagnostics.single.details, containsPair('stage', 'glbJsonRead'));
    expect(
        over.diagnostics.single.details, containsPair('limit', jsonBytes - 1));
    expect(over.diagnostics.single.details, containsPair('actual', jsonBytes));
  });

  test('rejects declared embedded BIN length beyond the actual chunk', () {
    final source = _basisuGlb(
      mutateJson: (json) {
        final buffers = json['buffers']! as List<Object?>;
        (buffers.single as Map<String, Object?>)['byteLength'] = 8;
      },
    );

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[_decodedImage(0, 3)],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('limitation', 'embeddedBinDeclaredLength'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'buffers[0].byteLength'),
    );
    expect(result.diagnostics.single.details, containsPair('limit', 4));
    expect(result.diagnostics.single.details, containsPair('actual', 8));
  });

  test('accepts exact aggregate decoded and native-output budgets', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 48,
        maxNativeOutputBytes: 48,
        maxTexturePixels: 2,
      ),
    );

    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(imageCount: 2),
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(1, 4),
      ],
      budgetTracker: tracker,
    );

    expect(result.diagnostics, isEmpty);
    expect(tracker.totalDecodedBytes, 48);
    expect(tracker.nativeOutputBytes, 48);
    expect(tracker.texturePixels, 2);
  });

  test('rejects aggregate decoded payload bytes without tracker consumption',
      () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 47,
        maxNativeOutputBytes: 48,
      ),
    );

    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(imageCount: 2),
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(1, 4),
      ],
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'totalDecodedBytes'),
    );
    expect(result.diagnostics.single.details, containsPair('limit', 47));
    expect(result.diagnostics.single.details, containsPair('actual', 48));
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);
  });

  test('maxNativeOutputBytes is aggregate across referenced images', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 48,
        maxNativeOutputBytes: 47,
      ),
    );

    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(imageCount: 2),
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(1, 4),
      ],
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'nativeOutputBytes'),
    );
    expect(result.diagnostics.single.details, containsPair('limit', 47));
    expect(result.diagnostics.single.details, containsPair('actual', 48));
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);
  });

  test('late second-image budget failure preserves prior tracker state', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 49,
        maxNativeOutputBytes: 49,
      ),
    )..reserveNativeOutputBytes(2, stage: 'priorDecoder');

    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(imageCount: 2),
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 4),
        _decodedImage(1, 5),
      ],
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details, containsPair('actual', 50));
    expect(tracker.totalDecodedBytes, 2);
    expect(tracker.nativeOutputBytes, 2);
  });

  test('rejects duplicate decoded image targets before mutation', () {
    final source = _basisuGlb();
    final before = _basisuDeclarations(source);

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(0, 4),
      ],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('status', 'malformedOutput'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'decodedImages'),
    );
    expect(_basisuDeclarations(source), before);
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

  test('rejects empty decoded image payloads', () {
    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[_decodedImage(0, 0)],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'decodedImages[0].bytes'),
    );
    expect(result.diagnostics.single.details, containsPair('actual', 0));
  });

  test('rejects unsupported decoded image MIME types', () {
    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/webp',
          width: 1,
          height: 1,
          bytes: Uint8List.fromList(<int>[1]),
        ),
      ],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'decodedImages[0].mimeType'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('actual', 'image/webp'),
    );
  });

  test('rejects decoded image targets outside the images array', () {
    final result = rewriteBasisuTexturesInGlb(
      _basisuGlb(),
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(4, 3),
      ],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'decodedImages[1].imageIndex'),
    );
    expect(result.diagnostics.single.details, containsPair('limit', 0));
    expect(result.diagnostics.single.details, containsPair('actual', 4));
  });

  test('rejects decoded images not referenced by a BasisU texture', () {
    final source = _basisuGlb(imageCount: 2, textureCount: 1);
    final before = _basisuDeclarations(source);
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 100,
        maxNativeOutputBytes: 100,
      ),
    )..reserveNativeOutputBytes(2, stage: 'priorDecoder');

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(1, 4),
      ],
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('limitation', 'decodedPayloadSchema'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('status', 'malformedOutput'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'decodedImages[1].imageIndex'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('limit', 'referenced by KHR_texture_basisu'),
    );
    expect(result.diagnostics.single.details, containsPair('actual', 1));
    expect(_basisuDeclarations(source), before);
    expect(tracker.totalDecodedBytes, 2);
    expect(tracker.nativeOutputBytes, 2);
  });

  test('rejects BasisU extension sources outside the images array', () {
    final source = _basisuGlb(
      mutateJson: (json) {
        final texture =
            (json['textures']! as List<Object?>).single as Map<String, Object?>;
        final extensions = texture['extensions']! as Map<String, Object?>;
        final basisu =
            extensions['KHR_texture_basisu']! as Map<String, Object?>;
        basisu['source'] = 9;
      },
    );

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[_decodedImage(9, 3)],
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'textures[0].extensions.KHR_texture_basisu.source'),
    );
    expect(result.diagnostics.single.details, containsPair('actual', 9));
  });

  test('late output failure preserves extensions and tracker reservations', () {
    final source = _basisuGlb(imageCount: 2);
    final before = _basisuDeclarations(source);
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 100,
        maxNativeOutputBytes: 100,
      ),
    )..reserveNativeOutputBytes(2, stage: 'priorDecoder');

    final result = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        _decodedImage(0, 3),
        _decodedImage(1, 4),
      ],
      budgetTracker: tracker,
      debugAfterOutputBuilt: (_) => throw StateError('deterministic late fail'),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('limitation', 'glbOutputConstruction'),
    );
    expect(_basisuDeclarations(source), before);
    expect(tracker.totalDecodedBytes, 2);
    expect(tracker.nativeOutputBytes, 2);
  });
}

GlbDecodedBasisuImage _decodedImage(int imageIndex, int byteLength) {
  return GlbDecodedBasisuImage(
    imageIndex: imageIndex,
    mimeType: 'image/png',
    width: 1,
    height: 1,
    bytes: byteLength == 0 ? Uint8List(0) : _pngBytes(width: 1, height: 1),
  );
}

Uint8List _basisuGlb({
  int imageCount = 1,
  int? textureCount,
  void Function(Map<String, Object?> json)? mutateJson,
}) {
  final json = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>['KHR_texture_basisu'],
    'extensionsRequired': <Object?>['KHR_texture_basisu'],
    'buffers': <Object?>[
      <String, Object?>{'byteLength': 4},
    ],
    'bufferViews': <Object?>[
      <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
    ],
    'images': List<Object?>.generate(
      imageCount,
      (_) => <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
    ),
    'textures': List<Object?>.generate(
      textureCount ?? imageCount,
      (index) => <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_texture_basisu': <String, Object?>{'source': index},
        },
      },
    ),
    'materials': <Object?>[
      <String, Object?>{
        'pbrMetallicRoughness': <String, Object?>{
          'baseColorTexture': <String, Object?>{'index': 0},
        },
      },
    ],
  };
  mutateJson?.call(json);
  return _glbWithBin(json, Uint8List.fromList(<int>[9, 9, 9, 9]));
}

Map<String, Object?> _basisuDeclarations(Uint8List bytes) {
  final json = _readGlb(bytes).json;
  return <String, Object?>{
    'extensionsUsed': json['extensionsUsed'],
    'extensionsRequired': json['extensionsRequired'],
    'textures': json['textures'],
  };
}

int _jsonChunkLength(Uint8List bytes) {
  return ByteData.sublistView(bytes).getUint32(12, Endian.little);
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

Uint8List _pngBytes({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setRange(
      0, 8, const <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(8, 13)
    ..setUint32(12, 0x49484452)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}
