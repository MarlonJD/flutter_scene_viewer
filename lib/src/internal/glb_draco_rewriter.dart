import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../diagnostics.dart';
import 'glb_decode_budget.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const String _dracoExtension = 'KHR_draco_mesh_compression';

final class GlbDecodedDracoPrimitive {
  const GlbDecodedDracoPrimitive({
    required this.meshIndex,
    required this.primitiveIndex,
    required this.attributes,
    this.indices,
  });

  final int meshIndex;
  final int primitiveIndex;
  final Map<String, Uint8List> attributes;
  final Uint8List? indices;
}

final class GlbDracoRewriteResult {
  const GlbDracoRewriteResult({
    this.bytes,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Uint8List? bytes;
  final List<ViewerDiagnostic> diagnostics;
}

GlbDracoRewriteResult rewriteDracoCompressedGlb(
  Uint8List bytes, {
  required List<GlbDecodedDracoPrimitive> decodedPrimitives,
  String? debugName,
  GlbDecodeBudget budget = const GlbDecodeBudget(),
  GlbDecodeBudgetTracker? budgetTracker,
  @visibleForTesting void Function(Uint8List bytes)? debugAfterOutputBuilt,
}) {
  final tracker = budgetTracker ?? GlbDecodeBudgetTracker(budget);
  final readResult = _readGlb(
    bytes,
    debugName: debugName,
    budgetTracker: tracker,
  );
  final diagnostic = readResult.diagnostic;
  if (diagnostic != null) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[diagnostic],
    );
  }
  final json = readResult.json;
  if (json == null) {
    return const GlbDracoRewriteResult(bytes: null);
  }

  final sourceBin = readResult.bin ?? Uint8List(0);
  final buffers = _ensureList(json, 'buffers');
  if (buffers.isEmpty) {
    buffers.add(<String, Object?>{'byteLength': 0});
  }
  final firstBuffer = _map(buffers[0]);
  if (firstBuffer == null || firstBuffer['uri'] != null) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'Draco GLB rewrite requires an embedded BIN buffer at buffers[0].',
        ),
      ],
    );
  }
  final accessors = _list(json['accessors']);
  final meshes = _list(json['meshes']);
  if (accessors == null || meshes == null) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'Draco GLB rewrite requires accessors and meshes arrays.',
        ),
      ],
    );
  }
  final declaredBinLengthValue = firstBuffer['byteLength'];
  final declaredBinLength = _intValue(declaredBinLengthValue);
  if ((declaredBinLengthValue != null && declaredBinLength == null) ||
      (declaredBinLength != null &&
          (declaredBinLength < 0 ||
              declaredBinLength > kGlbMaxSafeInteger ||
              declaredBinLength > sourceBin.lengthInBytes))) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _embeddedBinLengthFailure(
          debugName,
          json,
          declaredBinLengthValue,
          sourceBin.lengthInBytes,
        ),
      ],
    );
  }

  final diagnostics = <ViewerDiagnostic>[];
  final writesByAccessor = <int, _DracoAccessorWrite>{};
  final primitivesToRewrite = <Map<String, Object?>>[];
  final seenPrimitiveTargets = <(int, int)>{};
  final vertexCountsByAccessor = <int, int>{};
  final indexCountsByAccessor = <int, int>{};
  final decodedPayloadLengths = <int>[];

  for (final decoded in decodedPrimitives) {
    final target = (decoded.meshIndex, decoded.primitiveIndex);
    if (!seenPrimitiveTargets.add(target)) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Decoded Draco primitive target was returned more than once.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedPrimitives',
          limit: 'unique meshIndex/primitiveIndex pairs',
          actual: '${decoded.meshIndex}/${decoded.primitiveIndex}',
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
      continue;
    }
    final primitive = _primitiveFor(meshes, decoded);
    if (primitive == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Decoded Draco primitive target is outside the meshes array.',
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
      continue;
    }
    final attributes = _map(primitive['attributes']);
    if (attributes == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Draco primitive does not have an attributes map.',
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
      continue;
    }
    final dracoExtension =
        _map(_map(primitive['extensions'])?[_dracoExtension]);
    final compressedAttributes = _map(dracoExtension?['attributes']);
    if (compressedAttributes == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Draco primitive extension does not have an attributes map.',
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
      continue;
    }
    if (compressedAttributes.isEmpty) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Draco primitive extension must declare at least one compressed attribute.',
          limitation: 'dracoAccessorSchema',
          status: 'invalidMetadata',
          field: 'primitive.extensions.KHR_draco_mesh_compression.attributes',
          limit: 'a non-empty attribute map',
          actual: 0,
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
    }
    final extraDecodedAttributes = decoded.attributes.keys
        .where((name) => !compressedAttributes.containsKey(name))
        .toList(growable: false);
    if (extraDecodedAttributes.isNotEmpty) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native Draco decoder returned attributes not declared compressed.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedAttributes',
          limit: compressedAttributes.keys.toList(growable: false),
          actual: extraDecodedAttributes,
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
    }

    final attributeSchemas = <String, _PrimitiveAttributeSchema>{};
    int? primitiveVertexCount;
    int? representativeVertexAccessor;
    for (final entry in attributes.entries) {
      final attributeName = entry.key;
      final accessorIndex = _intValue(entry.value);
      if (accessorIndex == null ||
          accessorIndex < 0 ||
          accessorIndex >= accessors.length) {
        diagnostics.add(
          _typedFailure(
            debugName,
            json,
            'Decoded Draco attribute does not map to a valid accessor.',
            limitation: 'dracoAccessorSchema',
            status: 'invalidMetadata',
            field: 'primitive.attributes.$attributeName',
            limit: 'an accessor index in [0, ${accessors.length})',
            actual: entry.value,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
            },
          ),
        );
        continue;
      }
      final schema = _readAccessorSchema(
        accessors[accessorIndex],
        accessorIndex: accessorIndex,
        debugName: debugName,
        json: json,
        indices: false,
      );
      if (schema.diagnostic != null) {
        diagnostics.add(schema.diagnostic!);
        continue;
      }
      final accessorSchema = schema.schema!;
      attributeSchemas[attributeName] = _PrimitiveAttributeSchema(
        accessorIndex: accessorIndex,
        schema: accessorSchema,
      );
      if (primitiveVertexCount == null) {
        primitiveVertexCount = accessorSchema.count;
      } else if (accessorSchema.count != primitiveVertexCount) {
        diagnostics.add(
          _typedFailure(
            debugName,
            json,
            'Authored attributes in one Draco primitive have inconsistent counts.',
            limitation: 'dracoAccessorSchema',
            status: 'invalidMetadata',
            field: 'vertexCount',
            limit: primitiveVertexCount,
            actual: accessorSchema.count,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
              'accessorIndex': accessorIndex,
            },
          ),
        );
      }
      if (representativeVertexAccessor == null || attributeName == 'POSITION') {
        representativeVertexAccessor = accessorIndex;
      }
    }
    if (attributes.isEmpty) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Draco primitive must contain authored attributes.',
          limitation: 'dracoAccessorSchema',
          status: 'invalidMetadata',
          field: 'primitive.attributes',
          limit: 'a non-empty attribute map',
          actual: 0,
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
    }
    if (primitiveVertexCount != null && representativeVertexAccessor != null) {
      vertexCountsByAccessor.putIfAbsent(
        representativeVertexAccessor,
        () => primitiveVertexCount!,
      );
    }

    for (final attributeName in compressedAttributes.keys) {
      final attributeSchema = attributeSchemas[attributeName];
      if (attributeSchema == null) {
        if (!attributes.containsKey(attributeName)) {
          diagnostics.add(
            _typedFailure(
              debugName,
              json,
              'Decoded Draco attribute does not map to a valid accessor.',
              limitation: 'dracoAccessorSchema',
              status: 'invalidMetadata',
              field: 'primitive.attributes.$attributeName',
              limit: 'an accessor index in [0, ${accessors.length})',
              actual: null,
              details: <String, Object?>{
                'meshIndex': decoded.meshIndex,
                'primitiveIndex': decoded.primitiveIndex,
                'attribute': attributeName,
              },
            ),
          );
        }
        continue;
      }
      final accessorIndex = attributeSchema.accessorIndex;
      final accessorSchema = attributeSchema.schema;

      final payload = decoded.attributes[attributeName];
      if (payload == null) {
        diagnostics.add(
          _typedFailure(
            debugName,
            json,
            'Native Draco decoder did not return every compressed attribute.',
            limitation: 'decodedPayloadSize',
            status: 'malformedOutput',
            field: 'decodedBytes',
            limit: accessorSchema.byteLength,
            actual: null,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
              'accessorIndex': accessorIndex,
              'expectedByteLength': accessorSchema.byteLength,
              'actualByteLength': null,
            },
          ),
        );
        continue;
      }
      if (payload.lengthInBytes != accessorSchema.byteLength) {
        diagnostics.add(
          _decodedPayloadSizeFailure(
            debugName,
            json,
            accessorIndex: accessorIndex,
            expectedByteLength: accessorSchema.byteLength,
            actualByteLength: payload.lengthInBytes,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
            },
          ),
        );
        continue;
      }
      final nonFinite = _firstNonFiniteFloat(payload, accessorSchema);
      if (nonFinite != null) {
        diagnostics.add(
          _typedFailure(
            debugName,
            json,
            'Native Draco decoder returned a non-finite float value.',
            limitation: 'decodedPayloadValues',
            status: 'malformedOutput',
            field: 'decodedBytes',
            limit: 'finite IEEE-754 float values',
            actual: <String, Object?>{
              'componentIndex': nonFinite.$1,
              'value': nonFinite.$2,
            },
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
              'accessorIndex': accessorIndex,
            },
          ),
        );
        continue;
      }
      decodedPayloadLengths.add(payload.lengthInBytes);
      _recordAccessorWrite(
        writesByAccessor,
        accessorIndex: accessorIndex,
        payload: payload,
        debugName: debugName,
        json: json,
        diagnostics: diagnostics,
        details: <String, Object?>{
          'meshIndex': decoded.meshIndex,
          'primitiveIndex': decoded.primitiveIndex,
          'attribute': attributeName,
        },
      );
    }

    final rawIndexAccessorIndex = primitive['indices'];
    final indexAccessorIndex = _intValue(rawIndexAccessorIndex);
    final indices = decoded.indices;
    if (rawIndexAccessorIndex != null && indexAccessorIndex == null) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Draco primitive indices do not map to an integer accessor index.',
          limitation: 'dracoAccessorSchema',
          status: 'invalidMetadata',
          field: 'primitive.indices',
          limit: 'an accessor index in [0, ${accessors.length})',
          actual: rawIndexAccessorIndex,
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
    } else if (indexAccessorIndex != null) {
      if (indexAccessorIndex < 0 || indexAccessorIndex >= accessors.length) {
        diagnostics.add(
          _typedFailure(
            debugName,
            json,
            'Decoded Draco indices do not map to a valid accessor.',
            limitation: 'dracoAccessorSchema',
            status: 'invalidMetadata',
            field: 'primitive.indices',
            limit: 'an accessor index in [0, ${accessors.length})',
            actual: indexAccessorIndex,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
            },
          ),
        );
      } else {
        final schema = _readAccessorSchema(
          accessors[indexAccessorIndex],
          accessorIndex: indexAccessorIndex,
          debugName: debugName,
          json: json,
          indices: true,
        );
        if (schema.diagnostic != null) {
          diagnostics.add(schema.diagnostic!);
        } else if (indices == null) {
          diagnostics.add(
            _typedFailure(
              debugName,
              json,
              'Native Draco decoder did not return primitive indices.',
              limitation: 'decodedPayloadSize',
              status: 'malformedOutput',
              field: 'decodedIndices',
              limit: schema.schema!.byteLength,
              actual: null,
              details: <String, Object?>{
                'meshIndex': decoded.meshIndex,
                'primitiveIndex': decoded.primitiveIndex,
                'primitive': 'indices',
                'accessorIndex': indexAccessorIndex,
                'expectedByteLength': schema.schema!.byteLength,
                'actualByteLength': null,
              },
            ),
          );
        } else if (indices.lengthInBytes != schema.schema!.byteLength) {
          diagnostics.add(
            _decodedPayloadSizeFailure(
              debugName,
              json,
              accessorIndex: indexAccessorIndex,
              expectedByteLength: schema.schema!.byteLength,
              actualByteLength: indices.lengthInBytes,
              details: <String, Object?>{
                'meshIndex': decoded.meshIndex,
                'primitiveIndex': decoded.primitiveIndex,
                'primitive': 'indices',
              },
            ),
          );
        } else {
          indexCountsByAccessor.putIfAbsent(
            indexAccessorIndex,
            () => schema.schema!.count,
          );
          decodedPayloadLengths.add(indices.lengthInBytes);
          _recordAccessorWrite(
            writesByAccessor,
            accessorIndex: indexAccessorIndex,
            payload: indices,
            debugName: debugName,
            json: json,
            diagnostics: diagnostics,
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'primitive': 'indices',
            },
          );
        }
      }
    } else if (indices != null) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native Draco decoder returned indices for a non-indexed primitive.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedIndices',
          limit: 0,
          actual: indices.lengthInBytes,
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
          },
        ),
      );
    }
    primitivesToRewrite.add(primitive);
  }

  if (diagnostics.isNotEmpty) {
    return GlbDracoRewriteResult(
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }

  final vertexCounts = vertexCountsByAccessor.values.toList(growable: false);
  final indexCounts = indexCountsByAccessor.values.toList(growable: false);
  try {
    _validateDracoBudget(
      tracker,
      accessorCount: writesByAccessor.length,
      vertexCounts: vertexCounts,
      indexCounts: indexCounts,
      decodedPayloadLengths: decodedPayloadLengths,
    );
  } on GlbDecodeBudgetExceeded catch (error) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _budgetFailure(debugName, json, error),
      ],
    );
  }

  late Uint8List rewrittenBytes;
  try {
    var bin = Uint8List.fromList(sourceBin);
    var logicalBinLength = declaredBinLength ?? sourceBin.lengthInBytes;
    final bufferViews = _ensureList(json, 'bufferViews');
    for (final writePlan in writesByAccessor.values) {
      final write = _appendBufferView(
        bin,
        logicalBinLength,
        bufferViews,
        writePlan.payload,
      );
      bin = write.bin;
      logicalBinLength = write.logicalLength;
      _bindAccessor(
        accessors[writePlan.accessorIndex],
        write.bufferViewIndex,
        writePlan.payload,
      );
    }
    for (final primitive in primitivesToRewrite) {
      final extensions = _map(primitive['extensions']);
      extensions?.remove(_dracoExtension);
      if (extensions != null && extensions.isEmpty) {
        primitive.remove('extensions');
      }
    }

    final paddedBinLength = _align4(logicalBinLength);
    if (bin.length < paddedBinLength) {
      bin = _appendPadding(bin, paddedBinLength - bin.length);
    } else if (bin.length > paddedBinLength) {
      bin = Uint8List.sublistView(bin, 0, paddedBinLength);
    }
    firstBuffer['byteLength'] = paddedBinLength;
    if (!_hasDracoPrimitive(json)) {
      _removeTopLevelExtension(json, 'extensionsUsed');
      _removeTopLevelExtension(json, 'extensionsRequired');
    }

    rewrittenBytes = _writeGlb(json, bin);
    debugAfterOutputBuilt?.call(rewrittenBytes);
  } on Object catch (error) {
    return GlbDracoRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _outputFailure(debugName, json, error),
      ],
    );
  }

  _reserveDracoBudget(
    tracker,
    accessorCount: writesByAccessor.length,
    vertexCounts: vertexCounts,
    indexCounts: indexCounts,
    decodedPayloadLengths: decodedPayloadLengths,
  );
  return GlbDracoRewriteResult(
    bytes: rewrittenBytes,
  );
}

void _validateDracoBudget(
  GlbDecodeBudgetTracker tracker, {
  required int accessorCount,
  required List<int> vertexCounts,
  required List<int> indexCounts,
  required List<int> decodedPayloadLengths,
}) {
  final shadow = GlbDecodeBudgetTracker(tracker.budget);
  _copyTrackerReservations(tracker, shadow);
  _reserveDracoBudget(
    shadow,
    accessorCount: accessorCount,
    vertexCounts: vertexCounts,
    indexCounts: indexCounts,
    decodedPayloadLengths: decodedPayloadLengths,
  );
}

void _copyTrackerReservations(
  GlbDecodeBudgetTracker source,
  GlbDecodeBudgetTracker destination,
) {
  final nonNativeDecodedBytes =
      source.totalDecodedBytes - source.nativeOutputBytes;
  if (nonNativeDecodedBytes < 0) {
    throw StateError(
      'Native output accounting exceeds total decoded-byte accounting.',
    );
  }
  if (nonNativeDecodedBytes != 0) {
    destination.reserveDecodedBytes(
      nonNativeDecodedBytes,
      stage: 'dracoBudgetSnapshot',
    );
  }
  if (source.nativeOutputBytes != 0) {
    destination.reserveNativeOutputBytes(
      source.nativeOutputBytes,
      stage: 'dracoBudgetSnapshot',
    );
  }
  destination
    ..reserveAccessors(source.accessors, stage: 'dracoBudgetSnapshot')
    ..reserveVertices(source.vertices, stage: 'dracoBudgetSnapshot')
    ..reserveIndices(source.indices, stage: 'dracoBudgetSnapshot');
  if (source.texturePixels != 0) {
    destination.reserveTexturePixels(
      width: source.texturePixels,
      height: 1,
      stage: 'dracoBudgetSnapshot',
    );
  }
}

void _reserveDracoBudget(
  GlbDecodeBudgetTracker tracker, {
  required int accessorCount,
  required List<int> vertexCounts,
  required List<int> indexCounts,
  required List<int> decodedPayloadLengths,
}) {
  tracker.reserveAccessors(accessorCount, stage: 'dracoPreflight');
  for (final count in vertexCounts) {
    tracker.reserveVertices(count, stage: 'dracoPreflight');
  }
  for (final count in indexCounts) {
    tracker.reserveIndices(count, stage: 'dracoPreflight');
  }
  for (final byteLength in decodedPayloadLengths) {
    tracker.reserveNativeOutputBytes(
      byteLength,
      stage: 'dracoDecodedOutput',
    );
  }
}

Map<String, Object?>? _primitiveFor(
  List<Object?> meshes,
  GlbDecodedDracoPrimitive decoded,
) {
  if (decoded.meshIndex < 0 || decoded.meshIndex >= meshes.length) {
    return null;
  }
  final primitives = _list(_map(meshes[decoded.meshIndex])?['primitives']);
  if (primitives == null ||
      decoded.primitiveIndex < 0 ||
      decoded.primitiveIndex >= primitives.length) {
    return null;
  }
  return _map(primitives[decoded.primitiveIndex]);
}

_BufferWrite _appendBufferView(
  Uint8List bin,
  int logicalLength,
  List<Object?> bufferViews,
  Uint8List payload,
) {
  final offset = _align4(logicalLength);
  final paddedEnd = _align4(offset + payload.length);
  final next = Uint8List(paddedEnd);
  next.setRange(0, bin.length.clamp(0, next.length), bin);
  next.setRange(offset, offset + payload.length, payload);
  final bufferViewIndex = bufferViews.length;
  bufferViews.add(<String, Object?>{
    'buffer': 0,
    'byteOffset': offset,
    'byteLength': payload.length,
  });
  return _BufferWrite(
    bin: next,
    logicalLength: offset + payload.length,
    bufferViewIndex: bufferViewIndex,
  );
}

_AccessorSchemaReadResult _readAccessorSchema(
  Object? rawAccessor, {
  required int accessorIndex,
  required String? debugName,
  required Map<String, Object?> json,
  required bool indices,
}) {
  final accessor = _map(rawAccessor);
  if (accessor == null) {
    return _AccessorSchemaReadResult.diagnostic(
      _typedFailure(
        debugName,
        json,
        'Draco accessor metadata must be an object.',
        limitation: 'dracoAccessorSchema',
        status: 'invalidMetadata',
        field: 'accessors[$accessorIndex]',
        limit: 'object',
        actual: rawAccessor.runtimeType.toString(),
        details: <String, Object?>{'accessorIndex': accessorIndex},
      ),
    );
  }
  final rawComponentType = accessor['componentType'];
  final componentType = _intValue(rawComponentType);
  final componentBytes = switch (componentType) {
    5120 || 5121 => 1,
    5122 || 5123 => 2,
    5125 || 5126 => 4,
    _ => null,
  };
  if (componentBytes == null ||
      (indices &&
          componentType != 5121 &&
          componentType != 5123 &&
          componentType != 5125)) {
    return _AccessorSchemaReadResult.diagnostic(
      _typedFailure(
        debugName,
        json,
        indices
            ? 'Draco index accessor component type must be unsigned.'
            : 'Draco attribute accessor component type is unsupported.',
        limitation: 'dracoAccessorSchema',
        status: 'invalidMetadata',
        field: 'accessors[$accessorIndex].componentType',
        limit: indices
            ? const <int>[5121, 5123, 5125]
            : const <int>[5120, 5121, 5122, 5123, 5125, 5126],
        actual: rawComponentType,
        details: <String, Object?>{'accessorIndex': accessorIndex},
      ),
    );
  }

  final type = accessor['type'];
  final componentCount = switch (type) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    _ => null,
  };
  if (componentCount == null || (indices && type != 'SCALAR')) {
    return _AccessorSchemaReadResult.diagnostic(
      _typedFailure(
        debugName,
        json,
        indices
            ? 'Draco index accessor type must be SCALAR.'
            : 'Draco attribute accessor type is unsupported.',
        limitation: 'dracoAccessorSchema',
        status: 'invalidMetadata',
        field: 'accessors[$accessorIndex].type',
        limit: indices
            ? 'SCALAR'
            : const <String>['SCALAR', 'VEC2', 'VEC3', 'VEC4'],
        actual: type,
        details: <String, Object?>{'accessorIndex': accessorIndex},
      ),
    );
  }

  final rawCount = accessor['count'];
  final count = _intValue(rawCount);
  if (count == null || count <= 0 || count > kGlbMaxSafeInteger) {
    return _AccessorSchemaReadResult.diagnostic(
      _typedFailure(
        debugName,
        json,
        'Draco accessor count must be a positive web-safe integer.',
        limitation: 'dracoAccessorSchema',
        status: 'invalidMetadata',
        field: 'accessors[$accessorIndex].count',
        limit: kGlbMaxSafeInteger,
        actual: rawCount,
        details: <String, Object?>{'accessorIndex': accessorIndex},
      ),
    );
  }

  final bytesPerElement = componentBytes * componentCount;
  if (count > kGlbMaxSafeInteger ~/ bytesPerElement) {
    return _AccessorSchemaReadResult.diagnostic(
      _typedFailure(
        debugName,
        json,
        'Draco accessor byte length exceeds the web-safe integer range.',
        limitation: 'dracoAccessorSchema',
        status: 'invalidMetadata',
        field: 'accessors[$accessorIndex].count',
        limit: kGlbMaxSafeInteger ~/ bytesPerElement,
        actual: count,
        details: <String, Object?>{
          'accessorIndex': accessorIndex,
          'componentCount': componentCount,
          'componentBytes': componentBytes,
        },
      ),
    );
  }
  return _AccessorSchemaReadResult(
    _AccessorSchema(
      count: count,
      byteLength: count * bytesPerElement,
      componentType: componentType!,
    ),
  );
}

(int, String)? _firstNonFiniteFloat(
  Uint8List payload,
  _AccessorSchema schema,
) {
  if (schema.componentType != 5126) {
    return null;
  }
  final data = ByteData.sublistView(payload);
  for (var componentIndex = 0;
      componentIndex < payload.lengthInBytes ~/ 4;
      componentIndex += 1) {
    final value = data.getFloat32(componentIndex * 4, Endian.little);
    if (!value.isFinite) {
      return (componentIndex, value.toString());
    }
  }
  return null;
}

void _recordAccessorWrite(
  Map<int, _DracoAccessorWrite> writesByAccessor, {
  required int accessorIndex,
  required Uint8List payload,
  required String? debugName,
  required Map<String, Object?> json,
  required List<ViewerDiagnostic> diagnostics,
  required Map<String, Object?> details,
}) {
  final existing = writesByAccessor[accessorIndex];
  if (existing == null) {
    writesByAccessor[accessorIndex] = _DracoAccessorWrite(
      accessorIndex: accessorIndex,
      payload: payload,
    );
    return;
  }
  if (!_bytesEqual(existing.payload, payload)) {
    diagnostics.add(
      _typedFailure(
        debugName,
        json,
        'One Draco accessor received conflicting decoded payloads.',
        limitation: 'decodedPayloadSchema',
        status: 'malformedOutput',
        field: 'accessors[$accessorIndex]',
        limit: 'one identical decoded payload per accessor',
        actual: 'conflicting decoded payloads',
        details: <String, Object?>{
          'accessorIndex': accessorIndex,
          ...details,
        },
      ),
    );
  }
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

void _bindAccessor(
  Object? rawAccessor,
  int bufferViewIndex,
  Uint8List payload,
) {
  final accessor = _map(rawAccessor);
  if (accessor == null) {
    return;
  }
  accessor['bufferView'] = bufferViewIndex;
  accessor.remove('byteOffset');
  _refreshAccessorBounds(accessor, payload);
}

void _refreshAccessorBounds(
  Map<String, Object?> accessor,
  Uint8List payload,
) {
  final hasMin = accessor.containsKey('min');
  final hasMax = accessor.containsKey('max');
  if (!hasMin && !hasMax) {
    return;
  }

  final componentType = _intValue(accessor['componentType']);
  final componentCount = switch (accessor['type']) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    _ => null,
  };
  final componentBytes = switch (componentType) {
    5120 || 5121 => 1,
    5122 || 5123 => 2,
    5125 || 5126 => 4,
    _ => null,
  };
  if (componentCount == null || componentBytes == null) {
    return;
  }

  final data = ByteData.sublistView(payload);
  final elementCount =
      payload.lengthInBytes ~/ (componentBytes * componentCount);
  final minimum = List<num?>.filled(componentCount, null);
  final maximum = List<num?>.filled(componentCount, null);
  for (var element = 0; element < elementCount; element += 1) {
    for (var component = 0; component < componentCount; component += 1) {
      final offset = (element * componentCount + component) * componentBytes;
      final value = switch (componentType) {
        5120 => data.getInt8(offset),
        5121 => data.getUint8(offset),
        5122 => data.getInt16(offset, Endian.little),
        5123 => data.getUint16(offset, Endian.little),
        5125 => data.getUint32(offset, Endian.little),
        5126 => data.getFloat32(offset, Endian.little),
        _ => throw StateError('Unsupported accessor component type.'),
      };
      if (minimum[component] == null || value < minimum[component]!) {
        minimum[component] = value;
      }
      if (maximum[component] == null || value > maximum[component]!) {
        maximum[component] = value;
      }
    }
  }
  if (hasMin) {
    accessor['min'] = minimum.cast<num>();
  }
  if (hasMax) {
    accessor['max'] = maximum.cast<num>();
  }
}

bool _hasDracoPrimitive(Map<String, Object?> json) {
  final meshes = _list(json['meshes']);
  if (meshes == null) {
    return false;
  }
  for (final rawMesh in meshes) {
    final primitives = _list(_map(rawMesh)?['primitives']);
    if (primitives == null) {
      continue;
    }
    for (final rawPrimitive in primitives) {
      final extensions = _map(_map(rawPrimitive)?['extensions']);
      if (extensions?.containsKey(_dracoExtension) ?? false) {
        return true;
      }
    }
  }
  return false;
}

void _removeTopLevelExtension(Map<String, Object?> json, String field) {
  final values = _list(json[field]);
  if (values == null) {
    return;
  }
  values.removeWhere((value) => value == _dracoExtension);
  if (values.isEmpty) {
    json.remove(field);
  }
}

_GlbReadResult _readGlb(
  Uint8List bytes, {
  required String? debugName,
  required GlbDecodeBudgetTracker budgetTracker,
}) {
  if (bytes.lengthInBytes < 12) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(debugName, 'GLB header is shorter than 12 bytes.'),
    );
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(debugName, 'GLB magic must be glTF.'),
    );
  }
  if (data.getUint32(4, Endian.little) != 2) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(debugName, 'GLB version must be 2.'),
    );
  }
  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength > bytes.lengthInBytes || declaredLength < 20) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(debugName, 'GLB declared length is invalid.'),
    );
  }

  var offset = 12;
  Map<String, Object?>? json;
  Uint8List? bin;
  while (offset + 8 <= declaredLength) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkType == _jsonChunkType) {
      try {
        budgetTracker.checkJsonBytes(chunkLength, stage: 'glbJsonRead');
      } on GlbDecodeBudgetExceeded catch (error) {
        return _GlbReadResult.diagnostic(
          _budgetFailure(
            debugName,
            const <String, Object?>{},
            error,
          ),
        );
      }
    }
    if (offset + chunkLength > declaredLength) {
      return _GlbReadResult.diagnostic(
        _rewriteFailure(
          debugName,
          'GLB chunk length exceeds declared file size.',
        ),
      );
    }
    if (chunkType == _jsonChunkType && json == null) {
      try {
        final decoded = jsonDecode(
          utf8.decode(bytes.sublist(offset, offset + chunkLength)),
        );
        if (decoded is Map) {
          json = _objectMap(decoded);
        } else {
          return _GlbReadResult.diagnostic(
            _rewriteFailure(
              debugName,
              'GLB JSON chunk must decode to an object.',
            ),
          );
        }
      } on Object catch (error) {
        return _GlbReadResult.diagnostic(
          _rewriteFailure(
            debugName,
            'GLB JSON chunk could not be decoded.',
            details: <String, Object?>{'error': error.toString()},
          ),
        );
      }
    } else if (chunkType == _binChunkType && bin == null) {
      bin = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + chunkLength),
      );
    }
    offset += chunkLength;
  }
  if (json == null) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(debugName, 'GLB JSON chunk was not found.'),
    );
  }
  return _GlbReadResult(json: json, bin: bin);
}

Uint8List _writeGlb(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final paddedBinLength = _align4(bin.length);
  final totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, _glbMagic, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, _jsonChunkType, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length;
      index < 20 + paddedJsonLength;
      index += 1) {
    bytes[index] = 0x20;
  }
  final binHeaderOffset = 20 + paddedJsonLength;
  data
    ..setUint32(binHeaderOffset, paddedBinLength, Endian.little)
    ..setUint32(binHeaderOffset + 4, _binChunkType, Endian.little);
  bytes.setRange(
    binHeaderOffset + 8,
    binHeaderOffset + 8 + bin.length,
    bin,
  );
  return bytes;
}

List<Object?> _ensureList(Map<String, Object?> owner, String field) {
  final existing = _list(owner[field]);
  if (existing != null) {
    return existing;
  }
  final created = <Object?>[];
  owner[field] = created;
  return created;
}

Uint8List _appendPadding(Uint8List bytes, int length) {
  if (length <= 0) {
    return bytes;
  }
  final next = Uint8List(bytes.length + length);
  next.setRange(0, bytes.length, bytes);
  return next;
}

ViewerDiagnostic _rewriteFailure(
  String? debugName,
  String reason, {
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not rewrite Draco-compressed GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _dracoExtension,
      'decoder': 'draco',
      'required': true,
      'status': 'rewriteFailed',
      'reason': reason,
      ...details,
    },
  );
}

ViewerDiagnostic _typedFailure(
  String? debugName,
  Map<String, Object?> json,
  String reason, {
  required String limitation,
  required String status,
  required String field,
  required Object? limit,
  required Object? actual,
  String stage = 'dracoPreflight',
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final requiredExtensions = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not rewrite Draco-compressed GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _dracoExtension,
      'decoder': 'draco',
      'required': requiredExtensions?.contains(_dracoExtension) ?? true,
      'limitation': limitation,
      'status': status,
      'stage': stage,
      'field': field,
      'limit': limit,
      'actual': actual,
      'reason': reason,
      ...details,
    },
  );
}

ViewerDiagnostic _outputFailure(
  String? debugName,
  Map<String, Object?> json,
  Object error,
) {
  return _typedFailure(
    debugName,
    json,
    'Draco GLB output construction did not complete successfully.',
    limitation: 'glbOutputConstruction',
    status: 'rewriteFailed',
    stage: 'dracoOutput',
    field: 'glbBytes',
    limit: 'successful GLB output construction',
    actual: error.toString(),
  );
}

ViewerDiagnostic _decodedPayloadSizeFailure(
  String? debugName,
  Map<String, Object?> json, {
  required int accessorIndex,
  required int expectedByteLength,
  required int actualByteLength,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return _typedFailure(
    debugName,
    json,
    'Decoded Draco payload byte length does not match accessor metadata.',
    limitation: 'decodedPayloadSize',
    status: 'malformedOutput',
    field: 'decodedBytes',
    limit: expectedByteLength,
    actual: actualByteLength,
    details: <String, Object?>{
      'accessorIndex': accessorIndex,
      'expectedByteLength': expectedByteLength,
      'actualByteLength': actualByteLength,
      ...details,
    },
  );
}

ViewerDiagnostic _budgetFailure(
  String? debugName,
  Map<String, Object?> json,
  GlbDecodeBudgetExceeded error,
) {
  final requiredExtensions = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Draco rewrite exceeded the configured GLB decode budget.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _dracoExtension,
      'decoder': 'draco',
      'required': requiredExtensions?.contains(_dracoExtension) ?? true,
      'limitation': 'decodeBudget',
      'status': error.status,
      'stage': error.stage,
      'field': error.field,
      'limit': error.limit,
      'actual': error.actual,
      'actualExact': error.actualExact,
      'actualExceedsMaxSafeInteger': error.actualExceedsMaxSafeInteger,
      if (error.actualLowerBound != null)
        'actualLowerBound': error.actualLowerBound,
      if (error.operands.isNotEmpty) 'operands': error.operands,
      'reason': error.toString(),
    },
  );
}

ViewerDiagnostic _embeddedBinLengthFailure(
  String? debugName,
  Map<String, Object?> json,
  Object? actual,
  int actualBinCapacity,
) {
  final actualInt = actual is int ? actual : null;
  final actualIsSafe =
      actualInt != null && actualInt >= 0 && actualInt <= kGlbMaxSafeInteger;
  return _typedFailure(
    debugName,
    json,
    'buffers[0].byteLength must fit the existing embedded BIN chunk.',
    limitation: 'embeddedBinDeclaredLength',
    status: 'malformedAsset',
    field: 'buffers[0].byteLength',
    limit: actualBinCapacity,
    actual: actualIsSafe ? actualInt : 'byteLength=$actual',
    details: <String, Object?>{
      'actualExact': actualIsSafe,
      'actualExceedsMaxSafeInteger':
          actualInt != null && actualInt > kGlbMaxSafeInteger,
      if (actualInt != null && actualInt > kGlbMaxSafeInteger)
        'actualLowerBound': kGlbMaxSafeInteger,
    },
  );
}

Map<String, Object?> _objectMap(Map<Object?, Object?> value) {
  return value.cast<String, Object?>();
}

Map<String, Object?>? _map(Object? value) {
  if (value is Map<Object?, Object?>) {
    return _objectMap(value);
  }
  return null;
}

List<Object?>? _list(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

int _align4(int value) => (value + 3) & ~3;

final class _GlbReadResult {
  const _GlbReadResult({this.json, this.bin}) : diagnostic = null;
  const _GlbReadResult.diagnostic(this.diagnostic)
      : json = null,
        bin = null;

  final Map<String, Object?>? json;
  final Uint8List? bin;
  final ViewerDiagnostic? diagnostic;
}

final class _BufferWrite {
  const _BufferWrite({
    required this.bin,
    required this.logicalLength,
    required this.bufferViewIndex,
  });

  final Uint8List bin;
  final int logicalLength;
  final int bufferViewIndex;
}

final class _AccessorSchema {
  const _AccessorSchema({
    required this.count,
    required this.byteLength,
    required this.componentType,
  });

  final int count;
  final int byteLength;
  final int componentType;
}

final class _AccessorSchemaReadResult {
  const _AccessorSchemaReadResult(this.schema) : diagnostic = null;
  const _AccessorSchemaReadResult.diagnostic(this.diagnostic) : schema = null;

  final _AccessorSchema? schema;
  final ViewerDiagnostic? diagnostic;
}

final class _DracoAccessorWrite {
  const _DracoAccessorWrite({
    required this.accessorIndex,
    required this.payload,
  });

  final int accessorIndex;
  final Uint8List payload;
}

final class _PrimitiveAttributeSchema {
  const _PrimitiveAttributeSchema({
    required this.accessorIndex,
    required this.schema,
  });

  final int accessorIndex;
  final _AccessorSchema schema;
}
