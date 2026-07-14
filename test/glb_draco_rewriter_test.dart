import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
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

  test('refreshes only decoded accessor bounds that were already declared', () {
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
            'count': 2,
            'type': 'VEC3',
            'min': <Object?>[99, 99, 99],
            'max': <Object?>[100, 100, 100],
          },
          <String, Object?>{
            'componentType': 5126,
            'count': 2,
            'type': 'VEC3',
            'min': <Object?>[99, 99, 99],
          },
          <String, Object?>{
            'componentType': 5126,
            'count': 2,
            'type': 'VEC4',
          },
          <String, Object?>{
            'componentType': 5123,
            'count': 3,
            'type': 'SCALAR',
            'min': <Object?>[99],
            'max': <Object?>[100],
          },
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'mode': 4,
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                  'TANGENT': 2,
                },
                'indices': 3,
                'extensions': <String, Object?>{
                  'KHR_draco_mesh_compression': <String, Object?>{
                    'bufferView': 0,
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'NORMAL': 1,
                      'TANGENT': 2,
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
            'POSITION': _float32Bytes(<double>[-2, 0.5, 3, 4, -5, 1]),
            'NORMAL': _float32Bytes(<double>[1, 2, 3, -1, -2, -3]),
            'TANGENT': _float32Bytes(
              <double>[1, 0, 0, 1, 0, 1, 0, -1],
            ),
          },
          indices: _uint16Bytes(<int>[1, 0, 1]),
        ),
      ],
      debugName: 'draco-bounds.glb',
    );

    expect(result.diagnostics, isEmpty);
    final accessors =
        _readGlb(result.bytes!).json['accessors'] as List<Object?>;
    final position = accessors[0] as Map<String, Object?>;
    final normal = accessors[1] as Map<String, Object?>;
    final tangent = accessors[2] as Map<String, Object?>;
    final indices = accessors[3] as Map<String, Object?>;
    expect(position['min'], <Object?>[-2.0, -5.0, 1.0]);
    expect(position['max'], <Object?>[4.0, 0.5, 3.0]);
    expect(normal['min'], <Object?>[-1.0, -2.0, -3.0]);
    expect(normal.containsKey('max'), isFalse);
    expect(tangent.containsKey('min'), isFalse);
    expect(tangent.containsKey('max'), isFalse);
    expect(indices['min'], <Object?>[0]);
    expect(indices['max'], <Object?>[1]);
  });

  test('rejects non-finite decoded floats before output or budget commit', () {
    final accessor = _accessor()
      ..['min'] = <Object?>[0, 0, 0]
      ..['max'] = <Object?>[1, 1, 1];
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[accessor],
        primitives: <Object?>[
          _dracoPrimitive(attributes: <String, Object?>{'POSITION': 0}),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    for (final nonFinite in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final tracker = GlbDecodeBudgetTracker(
        const GlbDecodeBudget(
          maxTotalDecodedBytes: 12,
          maxAccessors: 1,
          maxVertices: 1,
        ),
      );
      final result = rewriteDracoCompressedGlb(
        source,
        decodedPrimitives: <GlbDecodedDracoPrimitive>[
          GlbDecodedDracoPrimitive(
            meshIndex: 0,
            primitiveIndex: 0,
            attributes: <String, Uint8List>{
              'POSITION': _float32Bytes(<double>[nonFinite, 0, 0]),
            },
          ),
        ],
        budgetTracker: tracker,
        debugName: 'non-finite-draco.glb',
      );

      expect(result.bytes, isNull, reason: '$nonFinite');
      expect(result.diagnostics, hasLength(1), reason: '$nonFinite');
      expect(
        result.diagnostics.single.details,
        containsPair('limitation', 'decodedPayloadValues'),
        reason: '$nonFinite',
      );
      expect(
        result.diagnostics.single.details,
        containsPair('status', 'malformedOutput'),
        reason: '$nonFinite',
      );
      expect(
        result.diagnostics.single.details,
        containsPair('stage', 'dracoPreflight'),
        reason: '$nonFinite',
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', 'decodedBytes'),
        reason: '$nonFinite',
      );
      expect(tracker.totalDecodedBytes, 0, reason: '$nonFinite');
      expect(tracker.nativeOutputBytes, 0, reason: '$nonFinite');
      expect(tracker.accessors, 0, reason: '$nonFinite');
      expect(tracker.vertices, 0, reason: '$nonFinite');
    }
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
    expect(result.diagnostics.single.details['status'], 'malformedOutput');
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

  test('enforces the GLB JSON budget before Draco rewrite', () {
    final source = _singleAttributeDracoGlb();

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
      budget: const GlbDecodeBudget(maxJsonBytes: 1),
      debugName: 'json-budget.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('limitation', 'decodeBudget'));
    expect(result.diagnostics.single.details,
        containsPair('status', 'budgetExceeded'));
    expect(result.diagnostics.single.details,
        containsPair('stage', 'glbJsonRead'));
    expect(
        result.diagnostics.single.details, containsPair('field', 'jsonBytes'));
    expect(result.diagnostics.single.details, containsPair('limit', 1));
    expect(result.diagnostics.single.details['actual'], greaterThan(1));
  });

  test('rejects invalid embedded BIN declarations before padding', () {
    for (final byteLength in <Object?>[-1, 5, '4']) {
      final source = _singleAttributeDracoGlb(
        declaredBinByteLength: byteLength,
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
        debugName: 'bad-bin-length.glb',
      );

      expect(result.bytes, isNull, reason: 'byteLength=$byteLength');
      expect(result.diagnostics, hasLength(1));
      expect(
        result.diagnostics.single.details,
        containsPair('limitation', 'embeddedBinDeclaredLength'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('status', 'malformedAsset'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('stage', 'dracoPreflight'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', 'buffers[0].byteLength'),
      );
      expect(result.diagnostics.single.details, containsPair('limit', 4));
      expect(result.diagnostics.single.details, contains('actual'));
    }
  });

  test('rejects malformed and web-unsafe Draco accessor schemas', () {
    final unsafeInteger = int.parse('9007199254740992');
    final cases =
        <({Object? componentType, Object? count, Object? type, String field})>[
      (
        componentType: 5126,
        count: -1,
        type: 'VEC3',
        field: 'accessors[0].count'
      ),
      (
        componentType: 5126,
        count: unsafeInteger,
        type: 'VEC3',
        field: 'accessors[0].count',
      ),
      (
        componentType: 5126,
        count: kGlbMaxSafeInteger,
        type: 'VEC3',
        field: 'accessors[0].count',
      ),
      (
        componentType: 9999,
        count: 1,
        type: 'VEC3',
        field: 'accessors[0].componentType'
      ),
      (componentType: 5126, count: 1, type: 'BAD', field: 'accessors[0].type'),
    ];

    for (final schema in cases) {
      final source = _singleAttributeDracoGlb(
        componentType: schema.componentType,
        count: schema.count,
        type: schema.type,
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
        debugName: 'bad-schema.glb',
      );

      expect(result.bytes, isNull, reason: schema.field);
      expect(result.diagnostics, hasLength(1));
      expect(
        result.diagnostics.single.details,
        containsPair('limitation', 'dracoAccessorSchema'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('status', 'invalidMetadata'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('stage', 'dracoPreflight'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', schema.field),
      );
      expect(result.diagnostics.single.details, contains('limit'));
      expect(result.diagnostics.single.details, contains('actual'));
    }
  });

  test('rejects truncated and oversized decoded Draco payloads', () {
    for (final payloadLength in <int>[11, 13]) {
      final result = rewriteDracoCompressedGlb(
        _singleAttributeDracoGlb(),
        decodedPrimitives: <GlbDecodedDracoPrimitive>[
          GlbDecodedDracoPrimitive(
            meshIndex: 0,
            primitiveIndex: 0,
            attributes: <String, Uint8List>{
              'POSITION': Uint8List(payloadLength),
            },
          ),
        ],
        debugName: 'bad-payload.glb',
      );

      expect(result.bytes, isNull, reason: 'payloadLength=$payloadLength');
      expect(result.diagnostics, hasLength(1));
      expect(
        result.diagnostics.single.details,
        containsPair('limitation', 'decodedPayloadSize'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('status', 'malformedOutput'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('stage', 'dracoPreflight'),
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', 'decodedBytes'),
      );
      expect(result.diagnostics.single.details, containsPair('limit', 12));
      expect(
        result.diagnostics.single.details,
        containsPair('actual', payloadLength),
      );
    }
  });

  test('rejects inconsistent vertex counts across compressed attributes', () {
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[
          _accessor(count: 1),
          _accessor(count: 2),
        ],
        primitives: <Object?>[
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0, 'NORMAL': 1},
          ),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'POSITION': Uint8List(12),
            'NORMAL': Uint8List(24),
          },
        ),
      ],
      debugName: 'mismatched-vertices.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('limitation', 'dracoAccessorSchema'),
    );
    expect(result.diagnostics.single.details,
        containsPair('field', 'vertexCount'));
    expect(result.diagnostics.single.details, containsPair('limit', 1));
    expect(result.diagnostics.single.details, containsPair('actual', 2));
  });

  test('validates untouched authored attribute counts before rewrite', () {
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[
          _accessor(count: 1),
          _accessor(count: 2),
        ],
        primitives: <Object?>[
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0, 'NORMAL': 1},
            compressedAttributeNames: const <String>['POSITION'],
          ),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
      ],
      debugName: 'untouched-count.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('limitation', 'dracoAccessorSchema'));
    expect(result.diagnostics.single.details,
        containsPair('status', 'invalidMetadata'));
    expect(result.diagnostics.single.details,
        containsPair('field', 'vertexCount'));
    expect(result.diagnostics.single.details, containsPair('limit', 1));
    expect(result.diagnostics.single.details, containsPair('actual', 2));
    expect(
        result.diagnostics.single.details, containsPair('attribute', 'NORMAL'));
    expect(_dracoExtensions(_readGlb(source).json), hasLength(1));
  });

  test('rejects an empty Draco attribute map without decoded payload', () {
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[_accessor(count: 1)],
        primitives: <Object?>[
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0},
            compressedAttributeNames: const <String>[],
          ),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: const <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{},
        ),
      ],
      debugName: 'empty-draco-attributes.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('limitation', 'dracoAccessorSchema'));
    expect(result.diagnostics.single.details,
        containsPair('status', 'invalidMetadata'));
    expect(
      result.diagnostics.single.details,
      containsPair(
        'field',
        'primitive.extensions.KHR_draco_mesh_compression.attributes',
      ),
    );
    expect(result.diagnostics.single.details,
        containsPair('limit', 'a non-empty attribute map'));
    expect(result.diagnostics.single.details, containsPair('actual', 0));
    expect(_dracoExtensions(_readGlb(source).json), hasLength(1));
  });

  test('accepts exact Draco accessor vertex index and byte budgets', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 18,
        maxAccessors: 2,
        maxVertices: 1,
        maxIndices: 3,
      ),
    );

    final result = rewriteDracoCompressedGlb(
      _singleAttributeDracoGlb(includeIndices: true),
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'POSITION': Uint8List(12),
          },
          indices: Uint8List(6),
        ),
      ],
      budgetTracker: tracker,
      debugName: 'exact-budget.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(tracker.totalDecodedBytes, 18);
    expect(tracker.nativeOutputBytes, 18);
    expect(tracker.accessors, 2);
    expect(tracker.vertices, 1);
    expect(tracker.indices, 3);
  });

  test('enforces Draco accessor vertex and index budgets independently', () {
    final cases =
        <({GlbDecodeBudget budget, String field, int limit, int actual})>[
      (
        budget: const GlbDecodeBudget(maxAccessors: 1),
        field: 'accessors',
        limit: 1,
        actual: 2,
      ),
      (
        budget: const GlbDecodeBudget(maxVertices: 0),
        field: 'vertices',
        limit: 0,
        actual: 1,
      ),
      (
        budget: const GlbDecodeBudget(maxIndices: 2),
        field: 'indices',
        limit: 2,
        actual: 3,
      ),
    ];

    for (final limits in cases) {
      final tracker = GlbDecodeBudgetTracker(limits.budget);
      final result = rewriteDracoCompressedGlb(
        _singleAttributeDracoGlb(includeIndices: true),
        decodedPrimitives: <GlbDecodedDracoPrimitive>[
          GlbDecodedDracoPrimitive(
            meshIndex: 0,
            primitiveIndex: 0,
            attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
            indices: Uint8List(6),
          ),
        ],
        budgetTracker: tracker,
        debugName: 'dimension-budget.glb',
      );

      expect(result.bytes, isNull, reason: limits.field);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.details,
          containsPair('limitation', 'decodeBudget'));
      expect(result.diagnostics.single.details,
          containsPair('field', limits.field));
      expect(result.diagnostics.single.details,
          containsPair('limit', limits.limit));
      expect(result.diagnostics.single.details,
          containsPair('actual', limits.actual));
      expect(tracker.totalDecodedBytes, 0);
      expect(tracker.accessors, 0);
      expect(tracker.vertices, 0);
      expect(tracker.indices, 0);
    }
  });

  test('counts a reused Draco accessor once and writes it once', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 24,
        maxAccessors: 1,
        maxVertices: 1,
      ),
    );
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[_accessor(count: 1)],
        primitives: <Object?>[
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0, 'NORMAL': 0},
          ),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );
    final payload = Uint8List(12);

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'POSITION': payload,
            'NORMAL': Uint8List.fromList(payload),
          },
        ),
      ],
      budgetTracker: tracker,
      debugName: 'reused-accessor.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(tracker.accessors, 1);
    expect(tracker.totalDecodedBytes, 24);
    expect(tracker.nativeOutputBytes, 24);
    final rewritten = _readGlb(result.bytes!);
    expect(rewritten.json['bufferViews'] as List<Object?>, hasLength(2));
  });

  test('counts a cross-primitive shared accessor vertex once', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 24,
        maxAccessors: 1,
        maxVertices: 1,
      ),
    );
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[_accessor(count: 1)],
        primitives: <Object?>[
          _dracoPrimitive(attributes: <String, Object?>{'POSITION': 0}),
          _dracoPrimitive(attributes: <String, Object?>{'POSITION': 0}),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 1,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
      ],
      budgetTracker: tracker,
      debugName: 'cross-primitive-shared-accessor.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(tracker.totalDecodedBytes, 24);
    expect(tracker.accessors, 1);
    expect(tracker.vertices, 1);
    expect(_dracoExtensions(_readGlb(result.bytes!).json), isEmpty);
  });

  test('counts cross-primitive shared index and vertex accessors once', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 36,
        maxNativeOutputBytes: 36,
        maxAccessors: 2,
        maxVertices: 1,
        maxIndices: 3,
      ),
    );
    final source = _glbWithBin(
      _dracoJson(
        accessors: <Object?>[
          _accessor(count: 1),
          _accessor(componentType: 5123, count: 3, type: 'SCALAR'),
        ],
        primitives: <Object?>[
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0},
            indices: 1,
          ),
          _dracoPrimitive(
            attributes: <String, Object?>{'POSITION': 0},
            indices: 1,
          ),
        ],
      ),
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
          indices: Uint8List(6),
        ),
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 1,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
          indices: Uint8List(6),
        ),
      ],
      budgetTracker: tracker,
      debugName: 'cross-primitive-shared-index.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(tracker.totalDecodedBytes, 36);
    expect(tracker.nativeOutputBytes, 36);
    expect(tracker.accessors, 2);
    expect(tracker.vertices, 1);
    expect(tracker.indices, 3);
  });

  test('later invalid primitive returns no rewrite and preserves declarations',
      () {
    final source = _twoPrimitiveDracoGlb();
    final sourceJsonBefore = _readGlb(source).json;

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 1,
          attributes: <String, Uint8List>{'POSITION': Uint8List(11)},
        ),
      ],
      debugName: 'later-invalid.glb',
    );

    expect(result.bytes, isNull);
    final sourceJsonAfter = _readGlb(source).json;
    expect(sourceJsonAfter, sourceJsonBefore);
    expect(sourceJsonAfter['extensionsUsed'],
        <Object?>['KHR_draco_mesh_compression']);
    expect(sourceJsonAfter['extensionsRequired'],
        <Object?>['KHR_draco_mesh_compression']);
    expect(_dracoExtensions(sourceJsonAfter), hasLength(2));
  });

  test('aggregate Draco budget failure returns no partial rewrite', () {
    final source = _twoPrimitiveDracoGlb();
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(maxTotalDecodedBytes: 23),
    );

    final result = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 1,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
      ],
      budgetTracker: tracker,
      debugName: 'aggregate-budget.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('limitation', 'decodeBudget'));
    expect(result.diagnostics.single.details,
        containsPair('field', 'totalDecodedBytes'));
    expect(result.diagnostics.single.details, containsPair('limit', 23));
    expect(result.diagnostics.single.details, containsPair('actual', 24));
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.accessors, 0);
    expect(tracker.vertices, 0);
    expect(tracker.indices, 0);
    final sourceJson = _readGlb(source).json;
    expect(sourceJson['extensionsRequired'],
        <Object?>['KHR_draco_mesh_compression']);
    expect(_dracoExtensions(sourceJson), hasLength(2));
  });

  test('late output failure leaves the shared tracker unchanged', () {
    final tracker = GlbDecodeBudgetTracker(
      const GlbDecodeBudget(
        maxTotalDecodedBytes: 12,
        maxAccessors: 1,
        maxVertices: 1,
      ),
    );
    var observedBuiltOutput = false;

    final result = rewriteDracoCompressedGlb(
      _singleAttributeDracoGlb(),
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': Uint8List(12)},
        ),
      ],
      budgetTracker: tracker,
      debugName: 'late-output-failure.glb',
      debugAfterOutputBuilt: (bytes) {
        observedBuiltOutput = true;
        final builtJson = _readGlb(bytes).json;
        expect(_dracoExtensions(builtJson), isEmpty);
        expect(builtJson['extensionsUsed'], isNull);
        expect(builtJson['extensionsRequired'], isNull);
        throw StateError('forced post-build failure');
      },
    );

    expect(observedBuiltOutput, isTrue);
    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('limitation', 'glbOutputConstruction'));
    expect(result.diagnostics.single.details,
        containsPair('status', 'rewriteFailed'));
    expect(result.diagnostics.single.details,
        containsPair('stage', 'dracoOutput'));
    expect(result.diagnostics.single.details['actual'],
        contains('forced post-build failure'));
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.accessors, 0);
    expect(tracker.vertices, 0);
    expect(tracker.indices, 0);
  });
}

Uint8List _singleAttributeDracoGlb({
  Object? declaredBinByteLength = 4,
  Object? componentType = 5126,
  Object? count = 1,
  Object? type = 'VEC3',
  bool includeIndices = false,
}) {
  final accessors = <Object?>[
    _accessor(componentType: componentType, count: count, type: type),
    if (includeIndices)
      _accessor(componentType: 5123, count: 3, type: 'SCALAR'),
  ];
  return _glbWithBin(
    _dracoJson(
      declaredBinByteLength: declaredBinByteLength,
      accessors: accessors,
      primitives: <Object?>[
        _dracoPrimitive(
          attributes: <String, Object?>{'POSITION': 0},
          indices: includeIndices ? 1 : null,
        ),
      ],
    ),
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _twoPrimitiveDracoGlb() {
  return _glbWithBin(
    _dracoJson(
      accessors: <Object?>[
        _accessor(count: 1),
        _accessor(count: 1),
      ],
      primitives: <Object?>[
        _dracoPrimitive(attributes: <String, Object?>{'POSITION': 0}),
        _dracoPrimitive(attributes: <String, Object?>{'POSITION': 1}),
      ],
    ),
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Map<String, Object?> _dracoJson({
  Object? declaredBinByteLength = 4,
  required List<Object?> accessors,
  required List<Object?> primitives,
}) {
  return <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
    'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
    'buffers': <Object?>[
      <String, Object?>{'byteLength': declaredBinByteLength},
    ],
    'bufferViews': <Object?>[
      <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
    ],
    'accessors': accessors,
    'meshes': <Object?>[
      <String, Object?>{'primitives': primitives},
    ],
  };
}

Map<String, Object?> _dracoPrimitive({
  required Map<String, Object?> attributes,
  int? indices,
  List<String>? compressedAttributeNames,
}) {
  final compressedNames = compressedAttributeNames ?? attributes.keys.toList();
  return <String, Object?>{
    'mode': 4,
    'attributes': attributes,
    if (indices != null) 'indices': indices,
    'extensions': <String, Object?>{
      'KHR_draco_mesh_compression': <String, Object?>{
        'bufferView': 0,
        'attributes': <String, Object?>{
          for (final name in compressedNames)
            name: compressedNames.indexOf(name),
        },
      },
    },
  };
}

Map<String, Object?> _accessor({
  Object? componentType = 5126,
  Object? count = 1,
  Object? type = 'VEC3',
}) {
  return <String, Object?>{
    'componentType': componentType,
    'count': count,
    'type': type,
  };
}

List<Object?> _dracoExtensions(Map<String, Object?> json) {
  final meshes = json['meshes'] as List<Object?>;
  final primitives =
      (meshes.single as Map<String, Object?>)['primitives'] as List<Object?>;
  return primitives
      .map((raw) => (raw as Map<String, Object?>)['extensions'])
      .where((value) => value != null)
      .toList();
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
