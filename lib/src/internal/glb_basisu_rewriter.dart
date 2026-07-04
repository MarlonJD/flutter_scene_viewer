import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;
const String _basisuExtension = 'KHR_texture_basisu';

final class GlbDecodedBasisuImage {
  const GlbDecodedBasisuImage({
    required this.imageIndex,
    required this.mimeType,
    required this.bytes,
  });

  final int imageIndex;
  final String mimeType;
  final Uint8List bytes;
}

final class GlbBasisuRewriteResult {
  const GlbBasisuRewriteResult({
    this.bytes,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Uint8List? bytes;
  final List<ViewerDiagnostic> diagnostics;
}

GlbBasisuRewriteResult rewriteBasisuTexturesInGlb(
  Uint8List bytes, {
  required List<GlbDecodedBasisuImage> decodedImages,
  String? debugName,
}) {
  final readResult = _readGlb(bytes, debugName: debugName);
  final readDiagnostic = readResult.diagnostic;
  if (readDiagnostic != null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[readDiagnostic],
    );
  }
  final json = readResult.json;
  if (json == null) {
    return const GlbBasisuRewriteResult(bytes: null);
  }

  final decodedByImageIndex = <int, GlbDecodedBasisuImage>{
    for (final image in decodedImages) image.imageIndex: image,
  };
  final diagnostics = <ViewerDiagnostic>[];
  final basisuImageIndices = _basisuImageIndices(json, diagnostics, debugName);
  for (final imageIndex in basisuImageIndices) {
    final decoded = decodedByImageIndex[imageIndex];
    if (decoded == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Native BasisU decoder did not return every referenced image.',
          details: <String, Object?>{'imageIndex': imageIndex},
        ),
      );
      continue;
    }
    if (!_isSupportedDecodedMimeType(decoded.mimeType)) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Native BasisU decoder returned an unsupported decoded image MIME type.',
          details: <String, Object?>{
            'imageIndex': imageIndex,
            'mimeType': decoded.mimeType,
          },
        ),
      );
    }
    if (decoded.bytes.isEmpty) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Native BasisU decoder returned an empty decoded image payload.',
          details: <String, Object?>{'imageIndex': imageIndex},
        ),
      );
    }
  }
  if (diagnostics.isNotEmpty) {
    return GlbBasisuRewriteResult(
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }

  var bin = Uint8List.fromList(readResult.bin ?? const <int>[]);
  final buffers = _ensureList(json, 'buffers');
  if (buffers.isEmpty) {
    buffers.add(<String, Object?>{'byteLength': 0});
  }
  final firstBuffer = _map(buffers[0]);
  if (firstBuffer == null || firstBuffer['uri'] != null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'BasisU GLB rewrite requires an embedded BIN buffer at buffers[0].',
        ),
      ],
    );
  }
  final images = _list(json['images']);
  if (images == null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'BasisU GLB rewrite requires an images array.',
        ),
      ],
    );
  }
  final bufferViews = _ensureList(json, 'bufferViews');
  var logicalBinLength = _intValue(firstBuffer['byteLength']) ?? bin.length;
  if (logicalBinLength > bin.length) {
    bin = _appendPadding(bin, logicalBinLength - bin.length);
  }

  for (final imageIndex in basisuImageIndices) {
    final decoded = decodedByImageIndex[imageIndex]!;
    if (imageIndex < 0 || imageIndex >= images.length) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Decoded BasisU image target is outside the images array.',
          details: <String, Object?>{'imageIndex': imageIndex},
        ),
      );
      continue;
    }
    final image = _map(images[imageIndex]);
    if (image == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Decoded BasisU image target is not an image object.',
          details: <String, Object?>{'imageIndex': imageIndex},
        ),
      );
      continue;
    }
    final write = _appendBufferView(
      bin,
      logicalBinLength,
      bufferViews,
      decoded.bytes,
    );
    bin = write.bin;
    logicalBinLength = write.logicalLength;
    image
      ..remove('uri')
      ..['mimeType'] = decoded.mimeType
      ..['bufferView'] = write.bufferViewIndex;
  }
  if (diagnostics.isNotEmpty) {
    return GlbBasisuRewriteResult(
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }

  _rewriteBasisuTextureReferences(json);
  if (!_hasBasisuTexture(json)) {
    _removeTopLevelExtension(json, 'extensionsUsed');
    _removeTopLevelExtension(json, 'extensionsRequired');
  }

  final paddedBinLength = _align4(logicalBinLength);
  if (bin.length < paddedBinLength) {
    bin = _appendPadding(bin, paddedBinLength - bin.length);
  } else if (bin.length > paddedBinLength) {
    bin = Uint8List.sublistView(bin, 0, paddedBinLength);
  }
  firstBuffer['byteLength'] = paddedBinLength;
  return GlbBasisuRewriteResult(bytes: _writeGlb(json, bin));
}

Set<int> _basisuImageIndices(
  Map<String, Object?> json,
  List<ViewerDiagnostic> diagnostics,
  String? debugName,
) {
  final textures = _list(json['textures']);
  if (textures == null) {
    return const <int>{};
  }
  final imageIndices = <int>{};
  for (var textureIndex = 0;
      textureIndex < textures.length;
      textureIndex += 1) {
    final texture = _map(textures[textureIndex]);
    final basisu = _map(_map(texture?['extensions'])?[_basisuExtension]);
    if (basisu == null) {
      continue;
    }
    final imageIndex = _intValue(basisu['source']);
    if (imageIndex == null) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'BasisU texture extension does not reference an image source.',
          details: <String, Object?>{'textureIndex': textureIndex},
        ),
      );
      continue;
    }
    imageIndices.add(imageIndex);
  }
  return imageIndices;
}

void _rewriteBasisuTextureReferences(Map<String, Object?> json) {
  final textures = _list(json['textures']);
  if (textures == null) {
    return;
  }
  for (final rawTexture in textures) {
    final texture = _map(rawTexture);
    final extensions = _map(texture?['extensions']);
    final basisu = _map(extensions?[_basisuExtension]);
    final imageIndex = _intValue(basisu?['source']);
    if (texture == null || extensions == null || basisu == null) {
      continue;
    }
    if (imageIndex != null) {
      texture['source'] = imageIndex;
    }
    extensions.remove(_basisuExtension);
    if (extensions.isEmpty) {
      texture.remove('extensions');
    }
  }
}

bool _hasBasisuTexture(Map<String, Object?> json) {
  final textures = _list(json['textures']);
  if (textures == null) {
    return false;
  }
  for (final rawTexture in textures) {
    final extensions = _map(_map(rawTexture)?['extensions']);
    if (extensions?.containsKey(_basisuExtension) ?? false) {
      return true;
    }
  }
  return false;
}

bool _isSupportedDecodedMimeType(String mimeType) {
  return mimeType == 'image/png' || mimeType == 'image/jpeg';
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

void _removeTopLevelExtension(Map<String, Object?> json, String field) {
  final values = _list(json[field]);
  if (values == null) {
    return;
  }
  values.removeWhere((value) => value == _basisuExtension);
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
    message: 'Could not rewrite BasisU/KTX2 textures in GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _basisuExtension,
      'decoder': 'basisu',
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
