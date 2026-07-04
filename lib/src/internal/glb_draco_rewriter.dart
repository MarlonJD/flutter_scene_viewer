import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;
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
}) {
  final readResult = _readGlb(bytes, debugName: debugName);
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

  final diagnostics = <ViewerDiagnostic>[];
  var bin = Uint8List.fromList(readResult.bin ?? const <int>[]);
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
  final bufferViews = _ensureList(json, 'bufferViews');
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

  var logicalBinLength = _intValue(firstBuffer['byteLength']) ?? bin.length;
  if (logicalBinLength > bin.length) {
    bin = _appendPadding(bin, logicalBinLength - bin.length);
  }

  for (final decoded in decodedPrimitives) {
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
    var primitiveComplete = true;
    for (final attributeName in compressedAttributes.keys) {
      if (!decoded.attributes.containsKey(attributeName)) {
        primitiveComplete = false;
        diagnostics.add(
          _rewriteFailure(
            debugName,
            'Native Draco decoder did not return every compressed attribute.',
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': attributeName,
            },
          ),
        );
      }
    }
    final indexAccessorIndex = _intValue(primitive['indices']);
    if (indexAccessorIndex != null && decoded.indices == null) {
      primitiveComplete = false;
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Native Draco decoder did not return primitive indices.',
          details: <String, Object?>{
            'meshIndex': decoded.meshIndex,
            'primitiveIndex': decoded.primitiveIndex,
            'primitive': 'indices',
            'accessorIndex': indexAccessorIndex,
          },
        ),
      );
    }
    if (!primitiveComplete) {
      continue;
    }

    for (final entry in decoded.attributes.entries) {
      final accessorIndex = _intValue(attributes[entry.key]);
      if (accessorIndex == null ||
          accessorIndex < 0 ||
          accessorIndex >= accessors.length) {
        diagnostics.add(
          _rewriteFailure(
            debugName,
            'Decoded Draco attribute does not map to a valid accessor.',
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': entry.key,
            },
          ),
        );
        continue;
      }
      final expectedByteLength = _accessorByteLength(accessors[accessorIndex]);
      if (expectedByteLength == null ||
          expectedByteLength != entry.value.lengthInBytes) {
        diagnostics.add(
          _rewriteFailure(
            debugName,
            'Decoded Draco attribute byte length does not match accessor metadata.',
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
              'attribute': entry.key,
              'accessorIndex': accessorIndex,
              'expectedByteLength': expectedByteLength,
              'actualByteLength': entry.value.lengthInBytes,
            },
          ),
        );
        continue;
      }
      final write = _appendBufferView(
        bin,
        logicalBinLength,
        bufferViews,
        entry.value,
      );
      bin = write.bin;
      logicalBinLength = write.logicalLength;
      _bindAccessor(accessors[accessorIndex], write.bufferViewIndex);
    }

    final indices = decoded.indices;
    if (indices != null && indexAccessorIndex != null) {
      if (indexAccessorIndex < 0 || indexAccessorIndex >= accessors.length) {
        diagnostics.add(
          _rewriteFailure(
            debugName,
            'Decoded Draco indices do not map to a valid accessor.',
            details: <String, Object?>{
              'meshIndex': decoded.meshIndex,
              'primitiveIndex': decoded.primitiveIndex,
            },
          ),
        );
      } else {
        final expectedByteLength = _accessorByteLength(
          accessors[indexAccessorIndex],
        );
        if (expectedByteLength == null ||
            expectedByteLength != indices.lengthInBytes) {
          diagnostics.add(
            _rewriteFailure(
              debugName,
              'Decoded Draco index byte length does not match accessor metadata.',
              details: <String, Object?>{
                'meshIndex': decoded.meshIndex,
                'primitiveIndex': decoded.primitiveIndex,
                'accessorIndex': indexAccessorIndex,
                'expectedByteLength': expectedByteLength,
                'actualByteLength': indices.lengthInBytes,
              },
            ),
          );
          continue;
        }
        final write = _appendBufferView(
          bin,
          logicalBinLength,
          bufferViews,
          indices,
        );
        bin = write.bin;
        logicalBinLength = write.logicalLength;
        _bindAccessor(accessors[indexAccessorIndex], write.bufferViewIndex);
      }
    }

    final extensions = _map(primitive['extensions']);
    extensions?.remove(_dracoExtension);
    if (extensions != null && extensions.isEmpty) {
      primitive.remove('extensions');
    }
  }

  if (diagnostics.isNotEmpty) {
    return GlbDracoRewriteResult(
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
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

  return GlbDracoRewriteResult(
    bytes: _writeGlb(json, bin),
  );
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

int? _accessorByteLength(Object? rawAccessor) {
  final accessor = _map(rawAccessor);
  final componentType = _intValue(accessor?['componentType']);
  final count = _intValue(accessor?['count']);
  final type = accessor?['type'];
  final componentBytes = switch (componentType) {
    5120 || 5121 => 1,
    5122 || 5123 => 2,
    5125 || 5126 => 4,
    _ => null,
  };
  final componentCount = switch (type) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    'MAT2' => 4,
    'MAT3' => 9,
    'MAT4' => 16,
    _ => null,
  };
  if (componentBytes == null || componentCount == null || count == null) {
    return null;
  }
  return componentBytes * componentCount * count;
}

void _bindAccessor(Object? rawAccessor, int bufferViewIndex) {
  final accessor = _map(rawAccessor);
  if (accessor == null) {
    return;
  }
  accessor['bufferView'] = bufferViewIndex;
  accessor.remove('byteOffset');
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
    if (chunkLength > _maxJsonChunkBytes && chunkType == _jsonChunkType) {
      return _GlbReadResult.diagnostic(
        _rewriteFailure(debugName, 'GLB JSON chunk exceeds the reader limit.'),
      );
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
