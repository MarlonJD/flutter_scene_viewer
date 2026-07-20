import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
import 'package:flutter_scene_viewer/src/internal/glb_meshopt_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/meshopt_decoder.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

const _meshoptFixtureRoot = 'test/fixtures/meshopt/MeshoptCubeTest/glTF';

void main() {
  test('rewrites meshopt-compressed bufferViews into embedded BIN bytes',
      () async {
    final encoded = _attributeStreamV0(<int>[1, 2, 3, 4]);
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['EXT_meshopt_compression'],
        'extensionsRequired': <Object?>['EXT_meshopt_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': encoded.lengthInBytes},
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
                'byteLength': encoded.lengthInBytes,
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
      encoded,
    );

    final result = await rewriteMeshoptCompressedGlb(
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
    final decodedOffset = rewrittenView['byteOffset'] as int;
    expect(
      chunks.bin.sublist(decodedOffset, decodedOffset + 4),
      <int>[1, 2, 3, 4],
    );
  });

  test('commits decoded bytes to a shared tracker exactly once on success',
      () async {
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveDecodedBytes(3, stage: 'seed');

    final result = await rewriteMeshoptCompressedGlb(
      _meshoptGlb(count: 1),
      debugName: 'meshopt-success-accounting.glb',
      budgetTracker: tracker,
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(tracker.totalDecodedBytes, 7);
  });

  test('rejects EXT ATTRIBUTES v1 before decode budget reservation', () async {
    final source = _meshoptGlb(
      count: 1,
      encodedStream: _attributeStreamV1(<int>[1, 2, 3, 4]),
    );
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveDecodedBytes(3, stage: 'seed');

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'ext-meshopt-v1.glb',
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(diagnostic.details['limitation'], 'meshoptBitstreamVersion');
    expect(diagnostic.details['status'], 'unsupportedBitstreamVersion');
    expect(diagnostic.details['stage'], 'meshoptPreflight');
    expect(diagnostic.details['field'], 'attributesBitstreamVersion');
    expect(diagnostic.details['limit'], 0);
    expect(diagnostic.details['actual'], 1);
    expect(tracker.totalDecodedBytes, 3);
    final sourceCapabilities = readGlbAssetCapabilities(source);
    expect(sourceCapabilities.meshoptCompressedBufferViewCount, 1);
    expect(
      sourceCapabilities.extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
  });

  test('rewrites an official v0 quantized primitive derivative', () async {
    final fixture = _officialMesh26ExtFixture();
    final source = _readGlb(fixture.glb);
    expect(source.bin[0], 0xa0);
    expect(source.bin[124], 0xa0);

    final result = await rewriteMeshoptCompressedGlb(
      fixture.glb,
      debugName: 'official-mesh26-ext-derivative.glb',
    );

    expect(result.diagnostics, isEmpty);
    final rewritten = _readGlb(result.bytes!);
    expect(
      rewritten.json['extensionsUsed'],
      <Object?>['KHR_mesh_quantization'],
    );
    expect(
      rewritten.json['extensionsRequired'],
      <Object?>['KHR_mesh_quantization'],
    );
    expect(rewritten.json['buffers'], hasLength(1));

    final views = rewritten.json['bufferViews'] as List<Object?>;
    expect(views, hasLength(2));
    for (final rawView in views) {
      final view = rawView as Map<String, Object?>;
      expect(view['buffer'], 0);
      expect(view['extensions'], isNull);
    }
    final positionView = views[0] as Map<String, Object?>;
    final normalView = views[1] as Map<String, Object?>;
    expect(
      rewritten.bin.sublist(
        positionView['byteOffset'] as int,
        (positionView['byteOffset'] as int) +
            (positionView['byteLength'] as int),
      ),
      orderedEquals(fixture.positionFallback),
    );
    expect(
      rewritten.bin.sublist(
        normalView['byteOffset'] as int,
        (normalView['byteOffset'] as int) + (normalView['byteLength'] as int),
      ),
      orderedEquals(fixture.normalFallback),
    );

    final accessors = rewritten.json['accessors'] as List<Object?>;
    expect(accessors, <Object?>[
      <String, Object?>{
        'bufferView': 0,
        'byteOffset': 0,
        'componentType': 5126,
        'count': 24,
        'type': 'VEC3',
        'min': <Object?>[-0.5, -0.5, -0.5],
        'max': <Object?>[0.5, 0.5, 0.5],
      },
      <String, Object?>{
        'bufferView': 1,
        'byteOffset': 0,
        'componentType': 5120,
        'count': 24,
        'type': 'VEC3',
        'normalized': true,
      },
    ]);
    final meshes = rewritten.json['meshes'] as List<Object?>;
    final mesh = meshes.single as Map<String, Object?>;
    final primitives = mesh['primitives'] as List<Object?>;
    final primitive = primitives.single as Map<String, Object?>;
    expect(
      primitive['attributes'],
      <String, Object?>{'POSITION': 0, 'NORMAL': 1},
    );
  });

  test('rejects declared output over budget before decode or allocation',
      () async {
    final source = _meshoptGlb(count: 2);

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'oversized-meshopt.glb',
      budget: const GlbDecodeBudget(maxTotalDecodedBytes: 4),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(diagnostic.details['limitation'], 'decodeBudget');
    expect(diagnostic.details['status'], 'budgetExceeded');
    expect(diagnostic.details['stage'], 'meshoptDeclaredOutput');
    expect(diagnostic.details['limit'], 4);
    expect(diagnostic.details['actual'], 8);
    expect(
      diagnostic.details['reason'],
      isNot(contains('decoder failed')),
    );
    expect(
      readGlbAssetCapabilities(source).extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
  });

  test('rejects a JSON chunk over the configured decode budget', () async {
    final result = await rewriteMeshoptCompressedGlb(
      _meshoptGlb(count: 1),
      debugName: 'json-budget.glb',
      budget: const GlbDecodeBudget(maxJsonBytes: 8),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details['limitation'], 'decodeBudget');
    expect(result.diagnostics.single.details['status'], 'budgetExceeded');
    expect(result.diagnostics.single.details['stage'], 'glbJsonRead');
    expect(result.diagnostics.single.details['limit'], 8);
    expect(
      result.diagnostics.single.details['actual'],
      greaterThan(8),
    );
  });

  test('accepts a JSON chunk exactly at the configured budget', () async {
    final source = _meshoptGlb(count: 1);
    final jsonLength =
        ByteData.sublistView(source).getUint32(12, Endian.little);

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'exact-json-budget.glb',
      budget: GlbDecodeBudget(maxJsonBytes: jsonLength),
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
  });

  test('rejects declared embedded BIN length before padding allocation',
      () async {
    final source = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['EXT_meshopt_compression'],
        'extensionsRequired': <Object?>['EXT_meshopt_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 8},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': 4,
                'byteStride': 4,
                'count': 1,
                'mode': 'ATTRIBUTES',
              },
            },
          },
        ],
      },
      Uint8List.fromList(<int>[0xa1, 0, 0, 0]),
    );

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'declared-bin-too-large.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details['status'], 'malformedAsset');
    expect(
      result.diagnostics.single.details['limitation'],
      'embeddedBinDeclaredLength',
    );
    expect(result.diagnostics.single.details['stage'], 'meshoptPreflight');
    expect(result.diagnostics.single.details['limit'], 4);
    expect(result.diagnostics.single.details['actual'], 8);
  });

  test('rejects negative and unsafe meshopt operands before decoder entry',
      () async {
    final unsafeInteger = int.parse('9007199254740992');
    for (final entry in <({int count, int stride})>[
      (count: -1, stride: 4),
      (count: unsafeInteger, stride: 4),
      (count: 1, stride: -1),
      (count: 1, stride: unsafeInteger),
    ]) {
      final result = await rewriteMeshoptCompressedGlb(
        _meshoptGlb(count: entry.count, byteStride: entry.stride),
        debugName: 'invalid-meshopt-operand.glb',
      );

      expect(result.bytes, isNull);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.details['status'], 'invalidMetadata');
      expect(
        result.diagnostics.single.details['stage'],
        'meshoptDeclaredOutput',
      );
      expect(
        result.diagnostics.single.details['reason'],
        isNot(contains('decoder failed')),
      );
    }
  });

  test('aggregate failure returns no partially rewritten GLB', () async {
    final source = _twoViewMeshoptGlb();

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'aggregate-budget.glb',
      budget: const GlbDecodeBudget(maxTotalDecodedBytes: 4),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details['status'], 'budgetExceeded');
    expect(result.diagnostics.single.details['actual'], 8);
    final originalCapabilities = readGlbAssetCapabilities(source);
    expect(originalCapabilities.meshoptCompressedBufferViewCount, 2);
    expect(
      originalCapabilities.extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
    final originalViews = _readGlb(source).json['bufferViews'] as List<Object?>;
    for (final rawView in originalViews) {
      final view = rawView as Map<String, Object?>;
      expect(
        (view['extensions'] as Map<String, Object?>)
            .containsKey('EXT_meshopt_compression'),
        isTrue,
      );
    }
  });

  test('timeout returns a typed diagnostic and rolls back tracker state',
      () async {
    final source = _twoViewMeshoptGlb();
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveDecodedBytes(3, stage: 'seed');
    var elapsedReads = 0;

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'meshopt-timeout.glb',
      budgetTracker: tracker,
      decodeControl: MeshoptDecodeControl(
        timeout: const Duration(milliseconds: 1),
        checkInterval: 4,
        elapsed: () => elapsedReads++ < 3
            ? Duration.zero
            : const Duration(milliseconds: 2),
      ),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(
      diagnostic.details,
      <String, Object?>{
        'source': 'meshopt-timeout.glb',
        'extension': 'EXT_meshopt_compression',
        'decoder': 'meshopt',
        'required': true,
        'limitation': 'meshoptDecodeDeadline',
        'status': 'timedOut',
        'stage': 'meshoptDecodeStart',
        'timeoutMilliseconds': 1,
        'timeoutMicroseconds': 1000,
        'decoderWork': 'notStartedForBufferView',
        'dartResourceRelease': 'collectibleAfterStackUnwind',
        'deterministicResourceRelease': 'notGuaranteed',
        'cancellation': 'notAvailable',
        'bufferViewIndex': 1,
        'fallback': 'diagnosticOnly',
      },
    );
    expect(elapsedReads, 4);
    expect(tracker.totalDecodedBytes, 3);
    final sourceCapabilities = readGlbAssetCapabilities(source);
    expect(sourceCapabilities.meshoptCompressedBufferViewCount, 2);
    expect(
      sourceCapabilities.extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
  });

  test('mid-decode timeout maps started work and rolls back tracker state',
      () async {
    final source = _meshoptGlb(count: 1);
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveDecodedBytes(3, stage: 'seed');
    var elapsedReads = 0;

    final result = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'meshopt-mid-decode-timeout.glb',
      budgetTracker: tracker,
      decodeControl: MeshoptDecodeControl(
        timeout: const Duration(microseconds: 500),
        checkInterval: 1,
        elapsed: () => elapsedReads++ == 0
            ? Duration.zero
            : const Duration(milliseconds: 1),
      ),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(diagnostic.details['stage'], 'meshoptAttributes');
    expect(diagnostic.details['status'], 'timedOut');
    expect(diagnostic.details['timeoutMilliseconds'], 0);
    expect(diagnostic.details['timeoutMicroseconds'], 500);
    expect(diagnostic.details['decoderWork'], 'started');
    expect(
      diagnostic.details['dartResourceRelease'],
      'collectibleAfterStackUnwind',
    );
    expect(
      diagnostic.details['deterministicResourceRelease'],
      'notGuaranteed',
    );
    expect(diagnostic.details['cancellation'], 'notAvailable');
    expect(diagnostic.details['bufferViewIndex'], 0);
    expect(elapsedReads, 2);
    expect(tracker.totalDecodedBytes, 3);
    final sourceCapabilities = readGlbAssetCapabilities(source);
    expect(sourceCapabilities.meshoptCompressedBufferViewCount, 1);
    expect(
      sourceCapabilities.extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
  });

  test('cancellation on a later bufferView rolls back bytes and tracker',
      () async {
    final source = _twoViewMeshoptGlb();
    final sourceSnapshot = Uint8List.fromList(source);
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveDecodedBytes(3, stage: 'seed');
    final cancellation = ModelLoadCancellationController();

    final rewrite = rewriteMeshoptCompressedGlb(
      source,
      debugName: 'meshopt-cancelled.glb',
      budgetTracker: tracker,
      decodeControl: MeshoptDecodeControl(
        timeout: const Duration(hours: 1),
        checkInterval: 4,
        elapsed: () => Duration.zero,
      ),
      cancellationToken: cancellation.token,
    );
    Timer.run(() => cancellation.cancel('later-buffer-view'));
    final result = await rewrite;

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(diagnostic.details['source'], 'meshopt-cancelled.glb');
    expect(diagnostic.details['extension'], 'EXT_meshopt_compression');
    expect(diagnostic.details['stage'], 'meshoptAttributes');
    expect(diagnostic.details['reason'], 'later-buffer-view');
    expect(diagnostic.details['status'], 'cancelled');
    expect(diagnostic.details['bufferViewIndex'], 1);
    expect(tracker.totalDecodedBytes, 3);
    expect(source, orderedEquals(sourceSnapshot));
    final capabilities = readGlbAssetCapabilities(source);
    expect(capabilities.meshoptCompressedBufferViewCount, 2);
    expect(
      capabilities.extensionsRequired,
      contains('EXT_meshopt_compression'),
    );
  });
}

({
  Uint8List glb,
  Uint8List positionFallback,
  Uint8List normalFallback,
}) _officialMesh26ExtFixture() {
  final compressed =
      File('$_meshoptFixtureRoot/MeshoptCubeTest.bin').readAsBytesSync();
  final fallback = File('$_meshoptFixtureRoot/MeshoptCubeTestFallback.bin')
      .readAsBytesSync();

  // KHR ATTRIBUTES v0 uses the same bitstream as EXT ATTRIBUTES v0. This
  // test-only derivative embeds the official mesh 26 POSITION and NORMAL
  // streams without adding KHR_meshopt_compression runtime support.
  final embedded = Uint8List.fromList(compressed.sublist(7144, 7328));
  final positionFallback = Uint8List.fromList(fallback.sublist(5544, 5832));
  final normalFallback = Uint8List.fromList(fallback.sublist(5832, 5928));

  return (
    glb: _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>[
          'EXT_meshopt_compression',
          'KHR_mesh_quantization',
        ],
        'extensionsRequired': <Object?>[
          'EXT_meshopt_compression',
          'KHR_mesh_quantization',
        ],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': embedded.lengthInBytes},
          <String, Object?>{
            'byteLength': 384,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{'fallback': true},
            },
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 1,
            'byteOffset': 0,
            'byteLength': 288,
            'target': 34962,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': 121,
                'byteStride': 12,
                'count': 24,
                'mode': 'ATTRIBUTES',
                'filter': 'EXPONENTIAL',
              },
            },
          },
          <String, Object?>{
            'buffer': 1,
            'byteOffset': 288,
            'byteLength': 96,
            'byteStride': 4,
            'target': 34962,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 124,
                'byteLength': 60,
                'byteStride': 4,
                'count': 24,
                'mode': 'ATTRIBUTES',
                'filter': 'OCTAHEDRAL',
              },
            },
          },
        ],
        'accessors': <Object?>[
          <String, Object?>{
            'bufferView': 0,
            'byteOffset': 0,
            'componentType': 5126,
            'count': 24,
            'type': 'VEC3',
            'min': <Object?>[-0.5, -0.5, -0.5],
            'max': <Object?>[0.5, 0.5, 0.5],
          },
          <String, Object?>{
            'bufferView': 1,
            'byteOffset': 0,
            'componentType': 5120,
            'count': 24,
            'type': 'VEC3',
            'normalized': true,
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
                'mode': 4,
              },
            ],
          },
        ],
      },
      embedded,
    ),
    positionFallback: positionFallback,
    normalFallback: normalFallback,
  );
}

Uint8List _meshoptGlb({
  required int count,
  int byteStride = 4,
  Uint8List? encodedStream,
}) {
  final encoded = encodedStream ?? _attributeStreamV0(<int>[1, 2, 3, 4]);
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['EXT_meshopt_compression'],
      'extensionsRequired': <Object?>['EXT_meshopt_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': encoded.lengthInBytes},
        <String, Object?>{
          'byteLength': 4,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{'fallback': true},
          },
        },
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 1,
          'byteOffset': 0,
          'byteLength': 4,
          'byteStride': byteStride,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{
              'buffer': 0,
              'byteOffset': 0,
              'byteLength': encoded.lengthInBytes,
              'byteStride': byteStride,
              'count': count,
              'mode': 'ATTRIBUTES',
            },
          },
        },
      ],
    },
    encoded,
  );
}

Uint8List _twoViewMeshoptGlb() {
  final encoded = _attributeStreamV0(<int>[1, 2, 3, 4]);
  final views = <Object?>[];
  for (var index = 0; index < 2; index += 1) {
    views.add(<String, Object?>{
      'buffer': 1,
      'byteOffset': 0,
      'byteLength': 4,
      'byteStride': 4,
      'extensions': <String, Object?>{
        'EXT_meshopt_compression': <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': encoded.lengthInBytes,
          'byteStride': 4,
          'count': 1,
          'mode': 'ATTRIBUTES',
        },
      },
    });
  }
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['EXT_meshopt_compression'],
      'extensionsRequired': <Object?>['EXT_meshopt_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': encoded.lengthInBytes},
        <String, Object?>{
          'byteLength': 8,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{'fallback': true},
          },
        },
      ],
      'bufferViews': views,
    },
    encoded,
  );
}

Uint8List _attributeStreamV0(List<int> values) {
  final byteStride = values.length;
  final bytes = Uint8List(1 + byteStride * 17 + 32);
  bytes[0] = 0xa0;
  var offset = 1;
  for (final value in values) {
    bytes[offset] = 0x03;
    bytes[offset + 1] = value * 2;
    offset += 17;
  }
  return bytes;
}

Uint8List _attributeStreamV1(List<int> values) {
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
