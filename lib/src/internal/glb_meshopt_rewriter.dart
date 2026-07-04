import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import 'meshopt_decoder.dart';

const String kMeshoptCompressionExtension = 'EXT_meshopt_compression';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;

final class GlbMeshoptRewriteResult {
  const GlbMeshoptRewriteResult({
    this.bytes,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Uint8List? bytes;
  final List<ViewerDiagnostic> diagnostics;
}

GlbMeshoptRewriteResult rewriteMeshoptCompressedGlb(
  Uint8List bytes, {
  String? debugName,
}) {
  final readResult = _readGlb(bytes, debugName: debugName);
  final diagnostic = readResult.diagnostic;
  if (diagnostic != null) {
    return GlbMeshoptRewriteResult(
      diagnostics: <ViewerDiagnostic>[diagnostic],
    );
  }
  final json = readResult.json;
  if (json == null) {
    return const GlbMeshoptRewriteResult(bytes: null);
  }

  final diagnostics = <ViewerDiagnostic>[];
  var bin = Uint8List.fromList(readResult.bin ?? const <int>[]);
  final buffers = _ensureList(json, 'buffers');
  if (buffers.isEmpty) {
    buffers.add(<String, Object?>{'byteLength': 0});
  }
  final firstBuffer = _map(buffers[0]);
  if (firstBuffer == null || firstBuffer['uri'] != null) {
    return GlbMeshoptRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          json,
          'Meshopt GLB rewrite requires an embedded BIN buffer at buffers[0].',
        ),
      ],
    );
  }
  var logicalBinLength = _intValue(firstBuffer['byteLength']) ?? bin.length;
  if (logicalBinLength > bin.length) {
    bin = _appendPadding(bin, logicalBinLength - bin.length);
  }

  final bufferViews = _ensureList(json, 'bufferViews');
  for (var viewIndex = 0; viewIndex < bufferViews.length; viewIndex += 1) {
    final bufferView = _map(bufferViews[viewIndex]);
    final extension = _map(
      _map(bufferView?['extensions'])?[kMeshoptCompressionExtension],
    );
    if (bufferView == null || extension == null) {
      continue;
    }

    final sourceBufferIndex = _intValue(extension['buffer']);
    final sourceByteOffset = _intValue(extension['byteOffset']) ?? 0;
    final sourceByteLength = _intValue(extension['byteLength']);
    final byteStride = _intValue(extension['byteStride']);
    final count = _intValue(extension['count']);
    final mode = MeshoptCompressionMode.fromJson(extension['mode']);
    final filter = MeshoptCompressionFilter.fromJson(extension['filter']);
    if (sourceBufferIndex != 0 ||
        sourceByteLength == null ||
        byteStride == null ||
        count == null ||
        mode == null ||
        filter == null ||
        sourceByteOffset < 0 ||
        sourceByteLength < 0 ||
        sourceByteOffset + sourceByteLength > bin.lengthInBytes) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          json,
          'Meshopt bufferView extension metadata is unsupported or invalid.',
          details: <String, Object?>{'bufferViewIndex': viewIndex},
        ),
      );
      continue;
    }

    try {
      final decoded = decodeMeshoptGltfBuffer(
        Uint8List.sublistView(
          bin,
          sourceByteOffset,
          sourceByteOffset + sourceByteLength,
        ),
        count: count,
        byteStride: byteStride,
        mode: mode,
        filter: filter,
      );
      final expectedByteLength = count * byteStride;
      if (decoded.lengthInBytes != expectedByteLength) {
        diagnostics.add(
          _rewriteFailure(
            debugName,
            json,
            'Decoded meshopt bufferView byte length does not match metadata.',
            details: <String, Object?>{
              'bufferViewIndex': viewIndex,
              'expectedByteLength': expectedByteLength,
              'actualByteLength': decoded.lengthInBytes,
            },
          ),
        );
        continue;
      }
      final write = _appendPayload(bin, logicalBinLength, decoded);
      bin = write.bin;
      logicalBinLength = write.logicalLength;
      bufferView
        ..['buffer'] = 0
        ..['byteOffset'] = write.byteOffset
        ..['byteLength'] = decoded.lengthInBytes;
      if (mode == MeshoptCompressionMode.attributes) {
        bufferView['byteStride'] = byteStride;
      } else {
        bufferView.remove('byteStride');
      }
      final extensions = _map(bufferView['extensions']);
      extensions?.remove(kMeshoptCompressionExtension);
      if (extensions != null && extensions.isEmpty) {
        bufferView.remove('extensions');
      }
    } on MeshoptDecodeException catch (error) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          json,
          'Meshopt decoder failed for bufferView.',
          details: <String, Object?>{
            'bufferViewIndex': viewIndex,
            'error': error.message,
          },
        ),
      );
    } on Object catch (error) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          json,
          'Meshopt decoder failed for bufferView.',
          details: <String, Object?>{
            'bufferViewIndex': viewIndex,
            'error': error.toString(),
          },
        ),
      );
    }
  }

  if (diagnostics.isNotEmpty) {
    return GlbMeshoptRewriteResult(
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
  _dropUnreferencedFallbackBuffers(json);
  if (!_hasMeshoptBufferView(json)) {
    _removeTopLevelExtension(json, 'extensionsUsed');
    _removeTopLevelExtension(json, 'extensionsRequired');
  }

  return GlbMeshoptRewriteResult(bytes: _writeGlb(json, bin));
}

_BufferWrite _appendPayload(
  Uint8List bin,
  int logicalLength,
  Uint8List payload,
) {
  final offset = _align4(logicalLength);
  final paddedEnd = _align4(offset + payload.length);
  final next = Uint8List(paddedEnd);
  next.setRange(0, bin.length.clamp(0, next.length), bin);
  next.setRange(offset, offset + payload.length, payload);
  return _BufferWrite(
    bin: next,
    logicalLength: offset + payload.length,
    byteOffset: offset,
  );
}

void _dropUnreferencedFallbackBuffers(Map<String, Object?> json) {
  final bufferViews = _list(json['bufferViews']) ?? const <Object?>[];
  final referencedBuffers = <int>{};
  for (final rawBufferView in bufferViews) {
    final bufferIndex = _intValue(_map(rawBufferView)?['buffer']);
    if (bufferIndex != null) {
      referencedBuffers.add(bufferIndex);
    }
  }
  if (referencedBuffers.length == 1 && referencedBuffers.single == 0) {
    final buffers = _list(json['buffers']);
    if (buffers != null && buffers.isNotEmpty) {
      json['buffers'] = <Object?>[buffers[0]];
    }
  }
}

bool _hasMeshoptBufferView(Map<String, Object?> json) {
  final bufferViews = _list(json['bufferViews']);
  if (bufferViews == null) {
    return false;
  }
  for (final rawBufferView in bufferViews) {
    final extensions = _map(_map(rawBufferView)?['extensions']);
    if (extensions?.containsKey(kMeshoptCompressionExtension) ?? false) {
      return true;
    }
  }
  return false;
}

void _removeTopLevelExtension(Map<String, Object?> json, String field) {
  final values = _list(json[field]);
  if (values == null) {
    return;
  }
  values.removeWhere((value) => value == kMeshoptCompressionExtension);
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
      _rewriteFailure(debugName, const <String, Object?>{},
          'GLB header is shorter than 12 bytes.'),
    );
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(
        debugName,
        const <String, Object?>{},
        'GLB magic must be glTF.',
      ),
    );
  }
  if (data.getUint32(4, Endian.little) != 2) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(
        debugName,
        const <String, Object?>{},
        'GLB version must be 2.',
      ),
    );
  }
  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength > bytes.lengthInBytes || declaredLength < 20) {
    return _GlbReadResult.diagnostic(
      _rewriteFailure(
        debugName,
        const <String, Object?>{},
        'GLB declared length is invalid.',
      ),
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
        _rewriteFailure(
          debugName,
          const <String, Object?>{},
          'GLB JSON chunk exceeds the reader limit.',
        ),
      );
    }
    if (offset + chunkLength > declaredLength) {
      return _GlbReadResult.diagnostic(
        _rewriteFailure(
          debugName,
          const <String, Object?>{},
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
              const <String, Object?>{},
              'GLB JSON chunk must decode to an object.',
            ),
          );
        }
      } on Object catch (error) {
        return _GlbReadResult.diagnostic(
          _rewriteFailure(
            debugName,
            const <String, Object?>{},
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
      _rewriteFailure(
        debugName,
        const <String, Object?>{},
        'GLB JSON chunk was not found.',
      ),
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
  Map<String, Object?> json,
  String reason, {
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final extensionsRequired = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not rewrite meshopt-compressed GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': kMeshoptCompressionExtension,
      'decoder': 'meshopt',
      'required':
          extensionsRequired?.contains(kMeshoptCompressionExtension) ?? true,
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
    required this.byteOffset,
  });

  final Uint8List bin;
  final int logicalLength;
  final int byteOffset;
}
