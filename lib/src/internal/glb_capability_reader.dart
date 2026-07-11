import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import 'ktx2_header_reader.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;
const String _dracoExtension = 'KHR_draco_mesh_compression';
const String _meshoptExtension = 'EXT_meshopt_compression';
const String _basisuExtension = 'KHR_texture_basisu';
const String _textureTransformExtension = 'KHR_texture_transform';

final class GlbPrimitiveTextureContext {
  const GlbPrimitiveTextureContext({
    required this.meshIndex,
    required this.primitiveIndex,
    required this.materialIndex,
    required this.availableTexCoords,
    required this.textureTransformRequired,
  });

  final int meshIndex;
  final int primitiveIndex;
  final int? materialIndex;
  final Set<int> availableTexCoords;
  final bool textureTransformRequired;
}

GlbPrimitiveTextureContext readGlbPrimitiveTextureContext({
  required Map<String, Object?> primitive,
  required Set<String> extensionsRequired,
  int meshIndex = -1,
  int primitiveIndex = -1,
}) {
  final availableTexCoords = <int>{};
  void collect(Object? rawAttributes) {
    final attributes = _map(rawAttributes);
    if (attributes == null) {
      return;
    }
    for (final name in attributes.keys) {
      if (!name.startsWith('TEXCOORD_')) {
        continue;
      }
      final texCoord = int.tryParse(name.substring('TEXCOORD_'.length));
      if (texCoord != null && texCoord >= 0) {
        availableTexCoords.add(texCoord);
      }
    }
  }

  collect(primitive['attributes']);
  final extensions = _map(primitive['extensions']);
  collect(_map(extensions?[_dracoExtension])?['attributes']);
  return GlbPrimitiveTextureContext(
    meshIndex: meshIndex,
    primitiveIndex: primitiveIndex,
    materialIndex: _intValue(primitive['material']),
    availableTexCoords: Set<int>.unmodifiable(availableTexCoords),
    textureTransformRequired:
        extensionsRequired.contains(_textureTransformExtension),
  );
}

final class GlbDecoderCapabilities {
  const GlbDecoderCapabilities({
    this.dracoMeshCompression = false,
    this.meshoptCompression = false,
    this.textureBasisu = false,
  });

  final bool dracoMeshCompression;
  final bool meshoptCompression;
  final bool textureBasisu;

  GlbDecoderCapabilities merge(GlbDecoderCapabilities other) {
    return GlbDecoderCapabilities(
      dracoMeshCompression: dracoMeshCompression || other.dracoMeshCompression,
      meshoptCompression: meshoptCompression || other.meshoptCompression,
      textureBasisu: textureBasisu || other.textureBasisu,
    );
  }
}

enum GlbTextureRole {
  color,
  normal,
  data,
}

final class GlbTextureSlot {
  const GlbTextureSlot({
    required this.materialIndex,
    required this.slot,
    required this.textureIndex,
    required this.role,
    required this.texCoord,
  });

  final int materialIndex;
  final String slot;
  final int textureIndex;
  final GlbTextureRole role;
  final int texCoord;
}

final class GlbAssetStatistics {
  const GlbAssetStatistics({
    this.nodeCount = 0,
    this.meshCount = 0,
    this.primitiveCount = 0,
    this.materialCount = 0,
    this.textureCount = 0,
    this.imageCount = 0,
  });

  final int nodeCount;
  final int meshCount;
  final int primitiveCount;
  final int materialCount;
  final int textureCount;
  final int imageCount;
}

final class GlbAssetCapabilityResult {
  const GlbAssetCapabilityResult({
    this.extensionsUsed = const <String>{},
    this.extensionsRequired = const <String>{},
    this.statistics = const GlbAssetStatistics(),
    this.compressedPrimitiveCounts = const <String, int>{},
    this.meshoptCompressedBufferViewCount = 0,
    this.basisuTextureCount = 0,
    this.materialExtensionCounts = const <String, int>{},
    this.textureSlots = const <GlbTextureSlot>[],
    this.primitiveTextureContexts = const <GlbPrimitiveTextureContext>[],
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Set<String> extensionsUsed;
  final Set<String> extensionsRequired;
  final GlbAssetStatistics statistics;
  final Map<String, int> compressedPrimitiveCounts;
  final int meshoptCompressedBufferViewCount;
  final int basisuTextureCount;
  final Map<String, int> materialExtensionCounts;
  final List<GlbTextureSlot> textureSlots;
  final List<GlbPrimitiveTextureContext> primitiveTextureContexts;
  final List<ViewerDiagnostic> diagnostics;
}

GlbAssetCapabilityResult readGlbAssetCapabilities(
  Uint8List bytes, {
  String? debugName,
  GlbDecoderCapabilities decoderCapabilities = const GlbDecoderCapabilities(),
}) {
  final jsonResult = _readJsonChunk(bytes, debugName: debugName);
  final diagnostic = jsonResult.diagnostic;
  if (diagnostic != null) {
    return GlbAssetCapabilityResult(
      diagnostics: <ViewerDiagnostic>[diagnostic],
    );
  }
  final json = jsonResult.json;
  if (json == null) {
    return const GlbAssetCapabilityResult();
  }

  final extensionsUsed = _stringSet(json['extensionsUsed']);
  final extensionsRequired = _stringSet(json['extensionsRequired']);
  final nodes = _list(json['nodes']) ?? const <Object?>[];
  final meshes = _list(json['meshes']) ?? const <Object?>[];
  final materials = _list(json['materials']) ?? const <Object?>[];
  final textures = _list(json['textures']) ?? const <Object?>[];
  final images = _list(json['images']) ?? const <Object?>[];
  final bufferViews = _list(json['bufferViews']) ?? const <Object?>[];
  final bin = jsonResult.bin;

  var primitiveCount = 0;
  final primitiveTextureContexts = <GlbPrimitiveTextureContext>[];
  final compressedPrimitiveCounts = <String, int>{};
  for (var meshIndex = 0; meshIndex < meshes.length; meshIndex += 1) {
    final rawMesh = meshes[meshIndex];
    final primitives = _list(_map(rawMesh)?['primitives']);
    if (primitives == null) {
      continue;
    }
    primitiveCount += primitives.length;
    for (var primitiveIndex = 0;
        primitiveIndex < primitives.length;
        primitiveIndex += 1) {
      final primitive = _map(primitives[primitiveIndex]);
      if (primitive != null) {
        primitiveTextureContexts.add(
          readGlbPrimitiveTextureContext(
            primitive: primitive,
            extensionsRequired: extensionsRequired,
            meshIndex: meshIndex,
            primitiveIndex: primitiveIndex,
          ),
        );
      }
      final extensions = _map(primitive?['extensions']);
      if (extensions?.containsKey(_dracoExtension) ?? false) {
        compressedPrimitiveCounts[_dracoExtension] =
            (compressedPrimitiveCounts[_dracoExtension] ?? 0) + 1;
      }
    }
  }

  var meshoptCompressedBufferViewCount = 0;
  for (final rawBufferView in bufferViews) {
    final extensions = _map(_map(rawBufferView)?['extensions']);
    if (extensions?.containsKey(_meshoptExtension) ?? false) {
      meshoptCompressedBufferViewCount += 1;
    }
  }

  var basisuTextureCount = 0;
  for (final rawTexture in textures) {
    final extensions = _map(_map(rawTexture)?['extensions']);
    if (extensions?.containsKey(_basisuExtension) ?? false) {
      basisuTextureCount += 1;
    }
  }

  final materialExtensionCounts = <String, int>{};
  final textureSlots = <GlbTextureSlot>[];
  for (var materialIndex = 0;
      materialIndex < materials.length;
      materialIndex += 1) {
    final material = _map(materials[materialIndex]);
    if (material == null) {
      continue;
    }
    final pbr = _map(material['pbrMetallicRoughness']);
    _addTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      owner: pbr,
      slot: 'baseColorTexture',
      role: GlbTextureRole.color,
    );
    _addTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      owner: pbr,
      slot: 'metallicRoughnessTexture',
      role: GlbTextureRole.data,
    );
    _addTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      owner: material,
      slot: 'normalTexture',
      role: GlbTextureRole.normal,
    );
    _addTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      owner: material,
      slot: 'occlusionTexture',
      role: GlbTextureRole.data,
    );
    _addTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      owner: material,
      slot: 'emissiveTexture',
      role: GlbTextureRole.color,
    );

    final extensions = _map(material['extensions']);
    if (extensions == null) {
      continue;
    }
    for (final extensionName in extensions.keys) {
      materialExtensionCounts[extensionName] =
          (materialExtensionCounts[extensionName] ?? 0) + 1;
    }
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_specular',
      slot: 'specularTexture',
      role: GlbTextureRole.data,
    );
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_specular',
      slot: 'specularColorTexture',
      role: GlbTextureRole.color,
    );
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_transmission',
      slot: 'transmissionTexture',
      role: GlbTextureRole.data,
    );
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_clearcoat',
      slot: 'clearcoatTexture',
      role: GlbTextureRole.data,
    );
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_clearcoat',
      slot: 'clearcoatRoughnessTexture',
      role: GlbTextureRole.data,
    );
    _addExtensionTextureSlot(
      textureSlots,
      materialIndex: materialIndex,
      extensions: extensions,
      extensionName: 'KHR_materials_clearcoat',
      slot: 'clearcoatNormalTexture',
      role: GlbTextureRole.normal,
    );
  }

  final diagnostics = <ViewerDiagnostic>[];
  final dracoPrimitiveCount = compressedPrimitiveCounts[_dracoExtension] ?? 0;
  _addUnsupportedDecoderDiagnostic(
    diagnostics,
    debugName: debugName,
    extension: _dracoExtension,
    decoder: 'draco',
    featureCount: dracoPrimitiveCount,
    extensionsUsed: extensionsUsed,
    extensionsRequired: extensionsRequired,
    supported: decoderCapabilities.dracoMeshCompression,
    details: <String, Object?>{'primitiveCount': dracoPrimitiveCount},
  );
  _addUnsupportedDecoderDiagnostic(
    diagnostics,
    debugName: debugName,
    extension: _meshoptExtension,
    decoder: 'meshopt',
    featureCount: meshoptCompressedBufferViewCount,
    extensionsUsed: extensionsUsed,
    extensionsRequired: extensionsRequired,
    supported: decoderCapabilities.meshoptCompression,
    details: <String, Object?>{
      'bufferViewCount': meshoptCompressedBufferViewCount,
    },
  );
  _addUnsupportedDecoderDiagnostic(
    diagnostics,
    debugName: debugName,
    extension: _basisuExtension,
    decoder: 'basisu',
    featureCount: basisuTextureCount,
    extensionsUsed: extensionsUsed,
    extensionsRequired: extensionsRequired,
    supported: decoderCapabilities.textureBasisu,
    details: <String, Object?>{
      'status': 'basisuTranscodeUnavailable',
      'textureCount': basisuTextureCount,
      ..._basisuKtx2Details(
        textures: textures,
        images: images,
        bufferViews: bufferViews,
        bin: bin,
      ),
    },
  );

  return GlbAssetCapabilityResult(
    extensionsUsed: Set<String>.unmodifiable(extensionsUsed),
    extensionsRequired: Set<String>.unmodifiable(extensionsRequired),
    statistics: GlbAssetStatistics(
      nodeCount: nodes.length,
      meshCount: meshes.length,
      primitiveCount: primitiveCount,
      materialCount: materials.length,
      textureCount: textures.length,
      imageCount: images.length,
    ),
    compressedPrimitiveCounts:
        Map<String, int>.unmodifiable(compressedPrimitiveCounts),
    meshoptCompressedBufferViewCount: meshoptCompressedBufferViewCount,
    basisuTextureCount: basisuTextureCount,
    materialExtensionCounts:
        Map<String, int>.unmodifiable(materialExtensionCounts),
    textureSlots: List<GlbTextureSlot>.unmodifiable(textureSlots),
    primitiveTextureContexts:
        List<GlbPrimitiveTextureContext>.unmodifiable(primitiveTextureContexts),
    diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
  );
}

void _addExtensionTextureSlot(
  List<GlbTextureSlot> textureSlots, {
  required int materialIndex,
  required Map<String, Object?> extensions,
  required String extensionName,
  required String slot,
  required GlbTextureRole role,
}) {
  _addTextureSlot(
    textureSlots,
    materialIndex: materialIndex,
    owner: _map(extensions[extensionName]),
    slot: '$extensionName.$slot',
    rawSlot: slot,
    role: role,
  );
}

void _addTextureSlot(
  List<GlbTextureSlot> textureSlots, {
  required int materialIndex,
  required Map<String, Object?>? owner,
  required String slot,
  String? rawSlot,
  required GlbTextureRole role,
}) {
  final textureInfo = _map(owner?[rawSlot ?? slot]);
  final textureIndex = _intValue(textureInfo?['index']);
  if (textureIndex == null) {
    return;
  }
  textureSlots.add(
    GlbTextureSlot(
      materialIndex: materialIndex,
      slot: slot,
      textureIndex: textureIndex,
      role: role,
      texCoord: _intValue(textureInfo?['texCoord']) ?? 0,
    ),
  );
}

Map<String, Object?> _basisuKtx2Details({
  required List<Object?> textures,
  required List<Object?> images,
  required List<Object?> bufferViews,
  required Uint8List? bin,
}) {
  final imageDetails = <Map<String, Object?>>[];
  String? reason;
  String? nextStep;
  for (var textureIndex = 0;
      textureIndex < textures.length;
      textureIndex += 1) {
    final texture = _map(textures[textureIndex]);
    final basisu = _map(_map(texture?['extensions'])?[_basisuExtension]);
    if (basisu == null) {
      continue;
    }
    final imageIndex =
        _intValue(basisu['source']) ?? _intValue(texture?['source']);
    final unsupported = _ktx2ImageDetails(
      imageIndex,
      images: images,
      bufferViews: bufferViews,
      bin: bin,
    );
    reason ??= unsupported['reason'] as String?;
    nextStep ??= unsupported['nextStep'] as String?;
    final detail = unsupported['ktx2'];
    if (detail is Map<String, Object?>) {
      imageDetails.add(<String, Object?>{
        'textureIndex': textureIndex,
        ...detail,
      });
    }
  }
  if (imageDetails.isEmpty) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    if (reason != null) 'reason': reason,
    if (nextStep != null) 'nextStep': nextStep,
    'ktx2Images': List<Map<String, Object?>>.unmodifiable(imageDetails),
  };
}

Map<String, Object?> _ktx2ImageDetails(
  int? imageIndex, {
  required List<Object?> images,
  required List<Object?> bufferViews,
  required Uint8List? bin,
}) {
  if (imageIndex == null) {
    return const <String, Object?>{
      'ktx2': <String, Object?>{
        'headerStatus': 'unavailable',
        'reason': 'Texture does not reference a KTX2 image source.',
      },
    };
  }
  if (imageIndex < 0 || imageIndex >= images.length) {
    return <String, Object?>{
      'ktx2': <String, Object?>{
        'headerStatus': 'unavailable',
        'imageIndex': imageIndex,
        'reason': 'Image index is outside the glTF images array.',
      },
    };
  }
  final image = _map(images[imageIndex]);
  final bufferViewIndex = _intValue(image?['bufferView']);
  if (bufferViewIndex == null) {
    return <String, Object?>{
      'ktx2': <String, Object?>{
        'headerStatus': 'unavailable',
        'imageIndex': imageIndex,
        'reason': 'KTX2 image is not stored in a GLB bufferView.',
      },
    };
  }
  final bytes = _bufferViewBytes(
    bufferViewIndex,
    bufferViews: bufferViews,
    bin: bin,
  );
  if (bytes == null) {
    return <String, Object?>{
      'ktx2': <String, Object?>{
        'headerStatus': 'unavailable',
        'imageIndex': imageIndex,
        'bufferViewIndex': bufferViewIndex,
        'reason': 'KTX2 image bufferView bytes are unavailable.',
      },
    };
  }
  return ktx2UnsupportedDetails(
    bytes,
    imageIndex: imageIndex,
    bufferViewIndex: bufferViewIndex,
  );
}

Uint8List? _bufferViewBytes(
  int bufferViewIndex, {
  required List<Object?> bufferViews,
  required Uint8List? bin,
}) {
  if (bufferViewIndex < 0 || bufferViewIndex >= bufferViews.length) {
    return null;
  }
  final bufferView = _map(bufferViews[bufferViewIndex]);
  final byteOffset = _intValue(bufferView?['byteOffset']) ?? 0;
  final byteLength = _intValue(bufferView?['byteLength']);
  if (bin == null ||
      byteLength == null ||
      byteOffset < 0 ||
      byteLength < 0 ||
      byteOffset + byteLength > bin.lengthInBytes) {
    return null;
  }
  return Uint8List.sublistView(bin, byteOffset, byteOffset + byteLength);
}

ViewerDiagnostic _unsupportedDecoderDiagnostic({
  required String? debugName,
  required String extension,
  required String decoder,
  required bool required,
  required Map<String, Object?> details,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'GLB requires a decoder that is not available.',
    details: <String, Object?>{
      'source': debugName,
      'extension': extension,
      'decoder': decoder,
      'required': required,
      'status': 'unsupported',
      ...details,
    },
  );
}

void _addUnsupportedDecoderDiagnostic(
  List<ViewerDiagnostic> diagnostics, {
  required String? debugName,
  required String extension,
  required String decoder,
  required int featureCount,
  required Set<String> extensionsUsed,
  required Set<String> extensionsRequired,
  required bool supported,
  required Map<String, Object?> details,
}) {
  if (featureCount <= 0 || supported) {
    return;
  }
  final required = extensionsRequired.contains(extension);
  if (!required && !extensionsUsed.contains(extension)) {
    return;
  }
  diagnostics.add(
    _unsupportedDecoderDiagnostic(
      debugName: debugName,
      extension: extension,
      decoder: decoder,
      required: required,
      details: details,
    ),
  );
}

_JsonChunkReadResult _readJsonChunk(
  Uint8List bytes, {
  required String? debugName,
}) {
  if (bytes.lengthInBytes < 12) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB header is shorter than 12 bytes.'),
    );
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB magic must be glTF.'),
    );
  }
  if (data.getUint32(4, Endian.little) != 2) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB version must be 2.'),
    );
  }
  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength > bytes.lengthInBytes || declaredLength < 20) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB declared length is invalid.'),
    );
  }

  var offset = 12;
  Uint8List? jsonBytes;
  Uint8List? bin;
  while (offset + 8 <= declaredLength) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkLength > _maxJsonChunkBytes) {
      return _JsonChunkReadResult.diagnostic(
        _glbFailure(debugName, 'GLB JSON chunk exceeds the reader limit.'),
      );
    }
    if (offset + chunkLength > declaredLength) {
      return _JsonChunkReadResult.diagnostic(
        _glbFailure(debugName, 'GLB chunk length exceeds declared file size.'),
      );
    }
    if (chunkType == _jsonChunkType) {
      jsonBytes = Uint8List.sublistView(bytes, offset, offset + chunkLength);
    } else if (chunkType == _binChunkType) {
      bin = Uint8List.sublistView(bytes, offset, offset + chunkLength);
    }
    offset += chunkLength;
  }

  if (jsonBytes == null) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB JSON chunk was not found.'),
    );
  }
  try {
    final decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is Map) {
      return _JsonChunkReadResult.json(_objectMap(decoded), bin: bin);
    }
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB JSON chunk must decode to an object.'),
    );
  } on Object catch (error) {
    return _JsonChunkReadResult.diagnostic(
      _glbFailure(
        debugName,
        'GLB JSON chunk could not be decoded.',
        error: error,
      ),
    );
  }
}

final class _JsonChunkReadResult {
  const _JsonChunkReadResult.json(this.json, {this.bin}) : diagnostic = null;
  const _JsonChunkReadResult.diagnostic(this.diagnostic)
      : json = null,
        bin = null;

  final Map<String, Object?>? json;
  final Uint8List? bin;
  final ViewerDiagnostic? diagnostic;
}

ViewerDiagnostic _glbFailure(
  String? debugName,
  String message, {
  Object? error,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.adapterFailure,
    message: 'Could not read GLB capability metadata.',
    details: <String, Object?>{
      'source': debugName,
      'reason': message,
      if (error != null) 'error': error.toString(),
    },
  );
}

Set<String> _stringSet(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return <String>{
    for (final item in value)
      if (item is String) item,
  };
}

Map<String, Object?> _objectMap(Map<Object?, Object?> value) {
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

Map<String, Object?>? _map(Object? value) {
  if (value is Map) {
    return _objectMap(value);
  }
  return null;
}

List<Object?>? _list(Object? value) {
  if (value is List) {
    return value;
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}
