import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import 'glb_decode_budget.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxGlbUint32 = 0xffffffff;
const String _basisuExtension = 'KHR_texture_basisu';

final class GlbDecodedBasisuMipLevel {
  const GlbDecodedBasisuMipLevel({
    required this.level,
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });

  final int level;
  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

final class GlbBasisuSamplerIntent {
  const GlbBasisuSamplerIntent({
    required this.magFilter,
    required this.minFilter,
    required this.wrapS,
    required this.wrapT,
  });

  final int magFilter;
  final int minFilter;
  final int wrapS;
  final int wrapT;
}

final class GlbDecodedBasisuTextureBinding {
  const GlbDecodedBasisuTextureBinding({
    required this.textureIndex,
    required this.sampler,
    this.samplerIndex,
  });

  final int textureIndex;
  final int? samplerIndex;
  final GlbBasisuSamplerIntent sampler;
}

final class GlbDecodedBasisuImage {
  const GlbDecodedBasisuImage({
    required this.imageIndex,
    this.contentRole = 'structuralOnly',
    this.levels = const <GlbDecodedBasisuMipLevel>[],
    this.textureBindings = const <GlbDecodedBasisuTextureBinding>[],
    String? mimeType,
    int? width,
    int? height,
    Uint8List? bytes,
  })  : _mimeType = mimeType,
        _width = width,
        _height = height,
        _bytes = bytes;

  final int imageIndex;
  final String contentRole;
  final List<GlbDecodedBasisuMipLevel> levels;
  final List<GlbDecodedBasisuTextureBinding> textureBindings;
  final String? _mimeType;
  final int? _width;
  final int? _height;
  final Uint8List? _bytes;

  /// Legacy single-level compatibility payload. Authored mip output uses
  /// [levels] and is never PNG-flattened into these fields.
  String get mimeType => _mimeType ?? '';
  int get width => _width ?? -1;
  int get height => _height ?? -1;
  Uint8List get bytes => _bytes ?? Uint8List(0);
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
  GlbDecodeBudget budget = const GlbDecodeBudget(),
  GlbDecodeBudgetTracker? budgetTracker,
  void Function(Uint8List bytes)? debugAfterOutputBuilt,
}) {
  final tracker = budgetTracker ?? GlbDecodeBudgetTracker(budget);
  final readResult = _readGlb(
    bytes,
    debugName: debugName,
    budgetTracker: tracker,
  );
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

  final diagnostics = <ViewerDiagnostic>[];
  final sourceBin = readResult.bin ?? Uint8List(0);
  final rawBuffers = json['buffers'];
  final buffers = _list(rawBuffers);
  if (rawBuffers != null && buffers == null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _typedFailure(
          debugName,
          json,
          'BasisU GLB buffers metadata must be an array.',
          limitation: 'basisuAssetSchema',
          status: 'malformedAsset',
          field: 'buffers',
          limit: 'array',
          actual: rawBuffers.runtimeType.toString(),
        ),
      ],
    );
  }
  final rawFirstBuffer = buffers?.isNotEmpty ?? false ? buffers![0] : null;
  final firstBuffer = _map(rawFirstBuffer);
  if ((buffers?.isNotEmpty ?? false) &&
      (firstBuffer == null || firstBuffer['uri'] != null)) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'BasisU GLB rewrite requires an embedded BIN buffer at buffers[0].',
          json: json,
        ),
      ],
    );
  }

  final declaredBinLengthValue = firstBuffer?['byteLength'];
  final declaredBinLength = _intValue(declaredBinLengthValue);
  if ((declaredBinLengthValue != null && declaredBinLength == null) ||
      (declaredBinLength != null &&
          (declaredBinLength < 0 ||
              declaredBinLength > kGlbMaxSafeInteger ||
              declaredBinLength > sourceBin.lengthInBytes))) {
    return GlbBasisuRewriteResult(
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

  final images = _list(json['images']);
  if (images == null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _rewriteFailure(
          debugName,
          'BasisU GLB rewrite requires an images array.',
          json: json,
        ),
      ],
    );
  }
  final rawBufferViews = json['bufferViews'];
  if (rawBufferViews != null && _list(rawBufferViews) == null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _typedFailure(
          debugName,
          json,
          'BasisU GLB bufferViews metadata must be an array.',
          limitation: 'basisuAssetSchema',
          status: 'malformedAsset',
          field: 'bufferViews',
          limit: 'array',
          actual: rawBufferViews.runtimeType.toString(),
        ),
      ],
    );
  }

  final basisuImageIndices = _basisuImageIndices(
    json,
    imageCount: images.length,
    diagnostics: diagnostics,
    debugName: debugName,
  );
  if (diagnostics.isNotEmpty) {
    return GlbBasisuRewriteResult(
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }
  final decodedByImageIndex = <int, GlbDecodedBasisuImage>{};
  for (var decodedIndex = 0;
      decodedIndex < decodedImages.length;
      decodedIndex += 1) {
    final decoded = decodedImages[decodedIndex];
    if (decodedByImageIndex.containsKey(decoded.imageIndex)) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned one image target more than once.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages',
          limit: 'unique imageIndex values',
          actual: decoded.imageIndex,
          details: <String, Object?>{
            'decodedImageIndex': decodedIndex,
            'imageIndex': decoded.imageIndex,
          },
        ),
      );
      continue;
    }
    decodedByImageIndex[decoded.imageIndex] = decoded;
    if (decoded.imageIndex < 0 || decoded.imageIndex >= images.length) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Decoded BasisU image target is outside the images array.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].imageIndex',
          limit: images.isEmpty ? 'no images' : images.length - 1,
          actual: decoded.imageIndex,
          details: <String, Object?>{
            'decodedImageIndex': decodedIndex,
            'imageIndex': decoded.imageIndex,
          },
        ),
      );
      continue;
    }
    if (_map(images[decoded.imageIndex]) == null) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Decoded BasisU image target is not an image object.',
          limitation: 'basisuAssetSchema',
          status: 'malformedAsset',
          field: 'images[${decoded.imageIndex}]',
          limit: 'object',
          actual: images[decoded.imageIndex].runtimeType.toString(),
          details: <String, Object?>{'imageIndex': decoded.imageIndex},
        ),
      );
    }
    if (!basisuImageIndices.contains(decoded.imageIndex)) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned an image not referenced by a BasisU texture.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].imageIndex',
          limit: 'referenced by KHR_texture_basisu',
          actual: decoded.imageIndex,
          details: <String, Object?>{
            'decodedImageIndex': decodedIndex,
            'imageIndex': decoded.imageIndex,
          },
        ),
      );
      continue;
    }
    if (decoded.levels.isNotEmpty) {
      final issue = _decodedMipChainIssue(decoded, decodedIndex);
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          issue == null
              ? 'Raw authored BasisU mip levels require the mip-aware importer.'
              : 'Native BasisU decoder returned a malformed mip chain.',
          limitation:
              issue == null ? 'authoredMipImporter' : 'decodedPayloadSchema',
          status:
              issue == null ? 'mipAwareImporterRequired' : 'malformedOutput',
          field: issue?.field ?? 'decodedImages[$decodedIndex].levels',
          limit: issue?.limit ??
              'repo-local authored-mip upload and material binding',
          actual: issue?.actual ?? decoded.levels.length,
          details: <String, Object?>{
            'decodedImageIndex': decodedIndex,
            'imageIndex': decoded.imageIndex,
            'contentRole': decoded.contentRole,
          },
        ),
      );
      continue;
    }
    if (!_isSupportedDecodedMimeType(decoded.mimeType)) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned an unsupported decoded image MIME type.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].mimeType',
          limit: 'image/png',
          actual: decoded.mimeType,
          details: <String, Object?>{
            'imageIndex': decoded.imageIndex,
            'mimeType': decoded.mimeType,
          },
        ),
      );
    }
    if (decoded.bytes.isEmpty) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned an empty decoded image payload.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].bytes',
          limit: 'non-empty payload',
          actual: decoded.bytes.lengthInBytes,
          details: <String, Object?>{'imageIndex': decoded.imageIndex},
        ),
      );
    }
    if (decoded.width <= 0 || decoded.width > kGlbMaxSafeInteger) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned an invalid decoded image width.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].width',
          limit: 'positive web-safe integer',
          actual: decoded.width,
          details: <String, Object?>{'imageIndex': decoded.imageIndex},
        ),
      );
    }
    if (decoded.height <= 0 || decoded.height > kGlbMaxSafeInteger) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU decoder returned an invalid decoded image height.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].height',
          limit: 'positive web-safe integer',
          actual: decoded.height,
          details: <String, Object?>{'imageIndex': decoded.imageIndex},
        ),
      );
    }
    final pngDimensions = _readPngDimensions(decoded.bytes);
    if (decoded.mimeType == 'image/png' &&
        decoded.bytes.isNotEmpty &&
        decoded.width > 0 &&
        decoded.height > 0 &&
        (pngDimensions == null ||
            pngDimensions.$1 != decoded.width ||
            pngDimensions.$2 != decoded.height)) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'Native BasisU PNG metadata does not match its PNG IHDR.',
          limitation: 'decodedPayloadSchema',
          status: 'malformedOutput',
          field: 'decodedImages[$decodedIndex].bytes.IHDR',
          limit: <String, Object?>{
            'width': decoded.width,
            'height': decoded.height,
          },
          actual: pngDimensions == null
              ? 'valid PNG signature and IHDR'
              : <String, Object?>{
                  'width': pngDimensions.$1,
                  'height': pngDimensions.$2,
                },
          details: <String, Object?>{'imageIndex': decoded.imageIndex},
        ),
      );
    }
  }
  for (final imageIndex in basisuImageIndices) {
    if (!decodedByImageIndex.containsKey(imageIndex)) {
      diagnostics.add(
        _rewriteFailure(
          debugName,
          'Native BasisU decoder did not return every referenced image.',
          json: json,
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

  final plans = <_BasisuImageWrite>[];
  var logicalBinLength = declaredBinLength ?? sourceBin.lengthInBytes;
  for (final imageIndex in basisuImageIndices) {
    final decoded = decodedByImageIndex[imageIndex]!;
    final offset = _alignedLength(logicalBinLength);
    final end = offset == null
        ? null
        : _checkedLengthSum(offset, decoded.bytes.lengthInBytes);
    if (offset == null || end == null) {
      return GlbBasisuRewriteResult(
        diagnostics: <ViewerDiagnostic>[
          _typedFailure(
            debugName,
            json,
            'BasisU decoded image output exceeds the GLB length range.',
            limitation: 'glbOutputSize',
            status: 'rewriteFailed',
            stage: 'basisuPreflight',
            field: 'buffers[0].byteLength',
            limit: _maxGlbUint32,
            actual: '$logicalBinLength + ${decoded.bytes.lengthInBytes}',
            details: <String, Object?>{'imageIndex': imageIndex},
          ),
        ],
      );
    }
    plans.add(
      _BasisuImageWrite(
        imageIndex: imageIndex,
        decoded: decoded,
        byteOffset: offset,
      ),
    );
    logicalBinLength = end;
  }
  final paddedBinLength = _alignedLength(logicalBinLength);
  if (paddedBinLength == null) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[
        _typedFailure(
          debugName,
          json,
          'BasisU decoded image output exceeds the GLB length range.',
          limitation: 'glbOutputSize',
          status: 'rewriteFailed',
          stage: 'basisuPreflight',
          field: 'buffers[0].byteLength',
          limit: _maxGlbUint32,
          actual: logicalBinLength,
        ),
      ],
    );
  }

  final shadow = GlbDecodeBudgetTracker(tracker.budget);
  try {
    _copyBasisuBudgetReservations(tracker, shadow);
    for (final plan in plans) {
      shadow.reserveTexturePixels(
        width: plan.decoded.width,
        height: plan.decoded.height,
        stage: 'basisuDecodedImage',
      );
      shadow.reserveNativeOutputBytes(
        plan.decoded.bytes.lengthInBytes,
        stage: 'basisuDecodedOutput',
      );
    }
  } on GlbDecodeBudgetExceeded catch (error) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[_budgetFailure(debugName, json, error)],
    );
  }
  final payloadByteLength =
      shadow.nativeOutputBytes - tracker.nativeOutputBytes;
  final payloadTexturePixels = shadow.texturePixels - tracker.texturePixels;

  Uint8List rewrittenBytes;
  try {
    final bin = Uint8List(paddedBinLength);
    bin.setRange(
      0,
      sourceBin.lengthInBytes.clamp(0, bin.lengthInBytes),
      sourceBin,
    );
    for (final plan in plans) {
      bin.setRange(
        plan.byteOffset,
        plan.byteOffset + plan.decoded.bytes.lengthInBytes,
        plan.decoded.bytes,
      );
    }

    final mutableBuffers = _ensureList(json, 'buffers');
    if (mutableBuffers.isEmpty) {
      mutableBuffers.add(<String, Object?>{'byteLength': 0});
    }
    final mutableFirstBuffer = _map(mutableBuffers[0])!;
    final bufferViews = _ensureList(json, 'bufferViews');
    for (final plan in plans) {
      final bufferViewIndex = bufferViews.length;
      bufferViews.add(<String, Object?>{
        'buffer': 0,
        'byteOffset': plan.byteOffset,
        'byteLength': plan.decoded.bytes.lengthInBytes,
      });
      final image = _map(images[plan.imageIndex])!;
      image
        ..remove('uri')
        ..['mimeType'] = plan.decoded.mimeType
        ..['bufferView'] = bufferViewIndex;
    }
    _rewriteBasisuTextureReferences(json);
    if (!_hasBasisuTexture(json)) {
      _removeTopLevelExtension(json, 'extensionsUsed');
      _removeTopLevelExtension(json, 'extensionsRequired');
    }
    mutableFirstBuffer['byteLength'] = paddedBinLength;
    rewrittenBytes = _writeGlb(json, bin);
    debugAfterOutputBuilt?.call(rewrittenBytes);
  } on Object catch (error) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[_outputFailure(debugName, json, error)],
    );
  }

  try {
    if (payloadTexturePixels != 0) {
      tracker.reserveTexturePixels(
        width: payloadTexturePixels,
        height: 1,
        stage: 'basisuDecodedImage',
      );
    }
    tracker.reserveNativeOutputBytes(
      payloadByteLength,
      stage: 'basisuDecodedOutput',
    );
  } on GlbDecodeBudgetExceeded catch (error) {
    return GlbBasisuRewriteResult(
      diagnostics: <ViewerDiagnostic>[_budgetFailure(debugName, json, error)],
    );
  }
  return GlbBasisuRewriteResult(bytes: rewrittenBytes);
}

Set<int> _basisuImageIndices(
  Map<String, Object?> json, {
  required int imageCount,
  required List<ViewerDiagnostic> diagnostics,
  required String? debugName,
}) {
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
    if (imageIndex == null || imageIndex < 0 || imageIndex >= imageCount) {
      diagnostics.add(
        _typedFailure(
          debugName,
          json,
          'BasisU texture extension does not reference an in-range image source.',
          limitation: 'basisuAssetSchema',
          status: 'malformedAsset',
          field: 'textures[$textureIndex].extensions.KHR_texture_basisu.source',
          limit: imageCount == 0 ? 'no images' : imageCount - 1,
          actual: basisu['source'],
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
  return mimeType == 'image/png';
}

(int, int)? _readPngDimensions(Uint8List bytes) {
  const signature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.lengthInBytes < 24) {
    return null;
  }
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) {
      return null;
    }
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13 || data.getUint32(12) != 0x49484452) {
    return null;
  }
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) {
    return null;
  }
  return (width, height);
}

void _copyBasisuBudgetReservations(
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
      stage: 'basisuBudgetSnapshot',
    );
  }
  if (source.nativeOutputBytes != 0) {
    destination.reserveNativeOutputBytes(
      source.nativeOutputBytes,
      stage: 'basisuBudgetSnapshot',
    );
  }
  if (source.accessors != 0) {
    destination.reserveAccessors(
      source.accessors,
      stage: 'basisuBudgetSnapshot',
    );
  }
  if (source.vertices != 0) {
    destination.reserveVertices(
      source.vertices,
      stage: 'basisuBudgetSnapshot',
    );
  }
  if (source.indices != 0) {
    destination.reserveIndices(
      source.indices,
      stage: 'basisuBudgetSnapshot',
    );
  }
  if (source.texturePixels != 0) {
    destination.reserveTexturePixels(
      width: source.texturePixels,
      height: 1,
      stage: 'basisuBudgetSnapshot',
    );
  }
}

int? _alignedLength(int value) {
  if (value < 0 || value > _maxGlbUint32 - 3) {
    return null;
  }
  return (value + 3) & ~3;
}

int? _checkedLengthSum(int left, int right) {
  if (left < 0 ||
      right < 0 ||
      left > _maxGlbUint32 ||
      right > _maxGlbUint32 - left) {
    return null;
  }
  return left + right;
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
  final paddedJsonLength = _alignedLength(jsonBytes.length);
  final paddedBinLength = _alignedLength(bin.length);
  if (paddedJsonLength == null || paddedBinLength == null) {
    throw const FormatException('GLB chunk length exceeds uint32.');
  }
  final chunkLengths = _checkedLengthSum(paddedJsonLength, paddedBinLength);
  final totalLength =
      chunkLengths == null ? null : _checkedLengthSum(28, chunkLengths);
  if (totalLength == null) {
    throw const FormatException('GLB total length exceeds uint32.');
  }
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

ViewerDiagnostic _rewriteFailure(
  String? debugName,
  String reason, {
  Map<String, Object?> json = const <String, Object?>{},
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final extensionsRequired = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not rewrite BasisU/KTX2 textures in GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _basisuExtension,
      'decoder': 'basisu',
      'required': extensionsRequired?.contains(_basisuExtension) ?? true,
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
  String stage = 'basisuPreflight',
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final extensionsRequired = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not rewrite BasisU/KTX2 textures in GLB.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _basisuExtension,
      'decoder': 'basisu',
      'required': extensionsRequired?.contains(_basisuExtension) ?? true,
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

ViewerDiagnostic _budgetFailure(
  String? debugName,
  Map<String, Object?> json,
  GlbDecodeBudgetExceeded error,
) {
  final extensionsRequired = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'BasisU rewrite exceeded the configured GLB decode budget.',
    details: <String, Object?>{
      'source': debugName,
      'extension': _basisuExtension,
      'decoder': 'basisu',
      'required': extensionsRequired?.contains(_basisuExtension) ?? true,
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

ViewerDiagnostic _outputFailure(
  String? debugName,
  Map<String, Object?> json,
  Object error,
) {
  return _typedFailure(
    debugName,
    json,
    'BasisU GLB output construction did not complete successfully.',
    limitation: 'glbOutputConstruction',
    status: 'rewriteFailed',
    stage: 'basisuOutput',
    field: 'glbBytes',
    limit: 'successful GLB output construction',
    actual: error.toString(),
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

_DecodedMipChainIssue? _decodedMipChainIssue(
  GlbDecodedBasisuImage image,
  int decodedIndex,
) {
  if (image.contentRole != 'color' &&
      image.contentRole != 'nonColor' &&
      image.contentRole != 'structuralOnly') {
    return _DecodedMipChainIssue(
      'decodedImages[$decodedIndex].contentRole',
      'color, nonColor, or structuralOnly',
      image.contentRole,
    );
  }
  final base = image.levels.first;
  if (base.level != 0 || base.width <= 0 || base.height <= 0) {
    return _DecodedMipChainIssue(
      'decodedImages[$decodedIndex].levels[0]',
      'level 0 with positive dimensions',
      <String, Object?>{
        'level': base.level,
        'width': base.width,
        'height': base.height,
      },
    );
  }
  for (var index = 0; index < image.levels.length; index += 1) {
    final level = image.levels[index];
    final expectedWidth = base.width >> index == 0 ? 1 : base.width >> index;
    final expectedHeight = base.height >> index == 0 ? 1 : base.height >> index;
    final expectedBytes = expectedWidth * expectedHeight * 4;
    if (level.level != index ||
        level.width != expectedWidth ||
        level.height != expectedHeight ||
        level.rgbaBytes.lengthInBytes != expectedBytes) {
      return _DecodedMipChainIssue(
        'decodedImages[$decodedIndex].levels[$index]',
        <String, Object?>{
          'level': index,
          'width': expectedWidth,
          'height': expectedHeight,
          'rgbaBytes': expectedBytes,
        },
        <String, Object?>{
          'level': level.level,
          'width': level.width,
          'height': level.height,
          'rgbaBytes': level.rgbaBytes.lengthInBytes,
        },
      );
    }
  }
  return null;
}

final class _DecodedMipChainIssue {
  const _DecodedMipChainIssue(this.field, this.limit, this.actual);

  final String field;
  final Object limit;
  final Object actual;
}

final class _GlbReadResult {
  const _GlbReadResult({this.json, this.bin}) : diagnostic = null;
  const _GlbReadResult.diagnostic(this.diagnostic)
      : json = null,
        bin = null;

  final Map<String, Object?>? json;
  final Uint8List? bin;
  final ViewerDiagnostic? diagnostic;
}

final class _BasisuImageWrite {
  const _BasisuImageWrite({
    required this.imageIndex,
    required this.decoded,
    required this.byteOffset,
  });

  final int imageIndex;
  final GlbDecodedBasisuImage decoded;
  final int byteOffset;
}
