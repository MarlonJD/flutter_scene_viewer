import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_source.dart';
import 'ktx2_header_reader.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;

final class GlbImportedTexturePatchResult {
  const GlbImportedTexturePatchResult({
    this.patches = const <PartAddress, MaterialPatch>{},
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  static const empty = GlbImportedTexturePatchResult();

  final Map<PartAddress, MaterialPatch> patches;
  final List<ViewerDiagnostic> diagnostics;
}

GlbImportedTexturePatchResult readGlbImportedTexturePatches(
  Uint8List bytes, {
  String? debugName,
}) {
  final chunkResult = _readGlbChunks(bytes, debugName: debugName);
  final diagnostic = chunkResult.diagnostic;
  if (diagnostic != null) {
    return GlbImportedTexturePatchResult(
      diagnostics: <ViewerDiagnostic>[diagnostic],
    );
  }
  final json = chunkResult.json;
  if (json == null) {
    return GlbImportedTexturePatchResult.empty;
  }
  return _GlbImportedTexturePatchMapper(
    json,
    bin: chunkResult.bin,
    debugName: debugName,
  ).map();
}

final class _GlbImportedTexturePatchMapper {
  _GlbImportedTexturePatchMapper(
    this.json, {
    required this.bin,
    required this.debugName,
  });

  final Map<String, Object?> json;
  final Uint8List? bin;
  final String? debugName;
  final List<ViewerDiagnostic> diagnostics = <ViewerDiagnostic>[];
  final Map<String, int> _nodePathCounts = <String, int>{};
  final List<_PatchCandidate> _candidates = <_PatchCandidate>[];

  GlbImportedTexturePatchResult map() {
    final materialPatches = _materialPatches();
    if (materialPatches.isEmpty) {
      return _result(const <PartAddress, MaterialPatch>{});
    }
    for (final nodeIndex in _sceneNodeIndices()) {
      _visitNode(
        nodeIndex,
        const <String>[],
        materialPatches: materialPatches,
        stack: <int>{},
      );
    }
    final patches = <PartAddress, MaterialPatch>{};
    final reportedAmbiguousPaths = <String>{};
    for (final candidate in _candidates) {
      final count = _nodePathCounts[candidate.nodePathKey] ?? 0;
      if (count > 1) {
        if (reportedAmbiguousPaths.add(candidate.nodePathKey)) {
          diagnostics.add(
            ViewerDiagnostic(
              code: ViewerDiagnosticCode.ambiguousNodePath,
              message:
                  'Imported texture patch target has an ambiguous node path.',
              details: <String, Object?>{
                'source': debugName,
                'nodePath': candidate.address.nodePath,
                'debugPath': candidate.address.nodePath.join('/'),
                'count': count,
              },
            ),
          );
        }
        continue;
      }
      final existing = patches[candidate.address];
      patches[candidate.address] =
          existing == null ? candidate.patch : existing.merge(candidate.patch);
    }
    return _result(patches);
  }

  Map<int, MaterialPatch> _materialPatches() {
    final materials = _list(json['materials']);
    if (materials == null) {
      return const <int, MaterialPatch>{};
    }
    final patches = <int, MaterialPatch>{};
    for (var index = 0; index < materials.length; index += 1) {
      final material = _map(materials[index]);
      if (material == null) {
        continue;
      }
      final patch = _patchForMaterial(index, material);
      if (patch != null && !patch.isEmpty) {
        patches[index] = patch;
      }
    }
    for (final materialIndex in _a1b32InternalBodyRepairMaterialIndices(
      materials,
    )) {
      final material = _map(materials[materialIndex]);
      final materialName = _stringValue(material?['name']);
      diagnostics.add(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedModelFeature,
          message:
              'Repaired imported GLB internal mannequin surface that intersects an opaque textile garment.',
          details: <String, Object?>{
            'source': debugName,
            'materialIndex': materialIndex,
            if (materialName != null) 'materialName': materialName,
            'repair': 'hideInternalMannequinBody',
            'reason':
                'The asset matches an A1B32-style textile export where internal body or leg geometry protrudes through opaque garment panels.',
          },
        ),
      );
      patches[materialIndex] = (patches[materialIndex] ?? const MaterialPatch())
          .merge(const MaterialPatch(visible: false));
    }
    return patches;
  }

  Set<int> _a1b32InternalBodyRepairMaterialIndices(List<Object?> materials) {
    var hasOpaqueGarmentFront = false;
    var hasBackDataBaseColorRepair = false;
    final internalBodyIndices = <int>{};
    for (var index = 0; index < materials.length; index += 1) {
      final material = _map(materials[index]);
      final materialName = _stringValue(material?['name']);
      final normalizedName = materialName?.toLowerCase();
      if (normalizedName == null) {
        continue;
      }
      if ((normalizedName.startsWith('top_front') ||
              normalizedName.startsWith('skirt_front')) &&
          _baseColorImageName(material)?.toLowerCase().startsWith('beyaz') ==
              true) {
        hasOpaqueGarmentFront = true;
      }
      if ((normalizedName.contains('_back') ||
              normalizedName.endsWith('back')) &&
          (_baseColorImageName(material)?.toLowerCase().startsWith('r_0') ??
              false)) {
        hasBackDataBaseColorRepair = true;
      }
      if (normalizedName.startsWith('mat_body') ||
          normalizedName.startsWith('mat_legs')) {
        internalBodyIndices.add(index);
      }
    }
    if (!hasOpaqueGarmentFront || !hasBackDataBaseColorRepair) {
      return const <int>{};
    }
    return internalBodyIndices;
  }

  MaterialPatch? _patchForMaterial(
    int materialIndex,
    Map<String, Object?> material,
  ) {
    final pbr = _map(material['pbrMetallicRoughness']);
    final materialName = _stringValue(material['name']);
    final baseColorTexture = _textureSource(
      _map(pbr?['baseColorTexture']),
      materialIndex: materialIndex,
      slot: 'baseColorTexture',
      materialName: materialName,
    );
    final alphaMode = _alphaMode(material['alphaMode']) ??
        _inferredBaseColorAlphaMode(baseColorTexture);
    final metallicRoughnessTexture = _textureSource(
      _map(pbr?['metallicRoughnessTexture']),
      materialIndex: materialIndex,
      slot: 'metallicRoughnessTexture',
    );
    final normalInfo = _map(material['normalTexture']);
    final normalTexture = _textureSource(
      normalInfo,
      materialIndex: materialIndex,
      slot: 'normalTexture',
    );
    final occlusionInfo = _map(material['occlusionTexture']);
    final occlusionTexture = _textureSource(
      occlusionInfo,
      materialIndex: materialIndex,
      slot: 'occlusionTexture',
    );
    final emissiveTexture = _textureSource(
      _map(material['emissiveTexture']),
      materialIndex: materialIndex,
      slot: 'emissiveTexture',
    );
    return MaterialPatch(
      baseColorTexture: baseColorTexture,
      metallicRoughnessTexture: metallicRoughnessTexture,
      normalTexture: normalTexture,
      normalScale:
          normalTexture == null ? null : _doubleValue(normalInfo?['scale']),
      occlusionTexture: occlusionTexture,
      occlusionStrength: occlusionTexture == null
          ? null
          : _doubleValue(occlusionInfo?['strength']),
      emissiveTexture: emissiveTexture,
      alphaMode: alphaMode,
      alphaCutoff: alphaMode == MaterialAlphaMode.mask
          ? _doubleValue(material['alphaCutoff'])
          : null,
    );
  }

  MaterialAlphaMode? _inferredBaseColorAlphaMode(TextureSource? texture) {
    if (texture is! BytesTextureSource) {
      return null;
    }
    return _pngDeclaresAlphaChannel(texture.encodedBytes)
        ? MaterialAlphaMode.blend
        : null;
  }

  TextureSource? _textureSource(
    Map<String, Object?>? textureInfo, {
    required int materialIndex,
    required String slot,
    String? materialName,
  }) {
    final textureIndex = _intValue(textureInfo?['index']);
    if (textureIndex == null) {
      return null;
    }
    final texCoord = _intValue(textureInfo?['texCoord']) ?? 0;
    if (texCoord != 0) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason:
              'Role-aware imported texture patches currently support only TEXCOORD_0.',
          uvSet: texCoord,
        ),
      );
      return null;
    }
    final textures = _list(json['textures']);
    if (textures == null ||
        textureIndex < 0 ||
        textureIndex >= textures.length) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'Texture index is outside the glTF textures array.',
        ),
      );
      return null;
    }
    final texture = _map(textures[textureIndex]);
    final basisu = _map(_map(texture?['extensions'])?['KHR_texture_basisu']);
    if (basisu != null) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason:
              'Texture uses KHR_texture_basisu and requires KTX2/BasisU transcode support.',
          requiredExtension: 'KHR_texture_basisu',
          details: _ktx2ImageDetails(
            _intValue(basisu['source']) ?? _intValue(texture?['source']),
          ),
        ),
      );
      return null;
    }
    final imageIndex = _intValue(texture?['source']);
    if (imageIndex == null) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'Texture does not reference an image source.',
        ),
      );
      return null;
    }
    final imageBytes = _imageBytes(
      imageIndex,
      materialIndex: materialIndex,
      textureIndex: textureIndex,
      slot: slot,
    );
    if (imageBytes == null) {
      return null;
    }
    if (_shouldRepairTextileDataBaseColor(
      slot: slot,
      materialName: materialName,
      imageIndex: imageIndex,
    )) {
      final imageName = _stringValue(_imageMap(imageIndex)?['name']);
      diagnostics.add(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedModelFeature,
          message:
              'Repaired imported GLB base-color texture that appears to be a textile data map.',
          details: <String, Object?>{
            'source': debugName,
            'materialIndex': materialIndex,
            if (materialName != null) 'materialName': materialName,
            'textureIndex': textureIndex,
            'imageIndex': imageIndex,
            if (imageName != null) 'imageName': imageName,
            'textureSlot': slot,
            'repair': 'neutralWhiteBaseColor',
            'reason':
                'The texture is named like an R_0 data/mask map but is authored in baseColorTexture on a back-side textile material.',
          },
        ),
      );
      return TextureSource.bytes(
        _neutralWhitePngBytes(),
        debugName: 'glb-texture:$textureIndex:$slot:neutral-white',
      );
    }
    return TextureSource.bytes(
      imageBytes,
      debugName: 'glb-texture:$textureIndex:$slot',
    );
  }

  bool _shouldRepairTextileDataBaseColor({
    required String slot,
    required String? materialName,
    required int imageIndex,
  }) {
    if (slot != 'baseColorTexture') {
      return false;
    }
    final image = _imageMap(imageIndex);
    final mimeType = _stringValue(image?['mimeType']);
    if (mimeType != 'image/png') {
      return false;
    }
    final imageName = _stringValue(image?['name'])?.toLowerCase();
    if (imageName == null || !imageName.startsWith('r_0')) {
      return false;
    }
    final normalizedMaterialName = materialName?.toLowerCase();
    if (normalizedMaterialName == null) {
      return false;
    }
    return normalizedMaterialName.contains('_back') ||
        normalizedMaterialName.endsWith('back');
  }

  Map<String, Object?>? _imageMap(int imageIndex) {
    final images = _list(json['images']);
    if (images == null || imageIndex < 0 || imageIndex >= images.length) {
      return null;
    }
    return _map(images[imageIndex]);
  }

  String? _baseColorImageName(Map<String, Object?>? material) {
    final pbr = _map(material?['pbrMetallicRoughness']);
    final textureIndex = _intValue(_map(pbr?['baseColorTexture'])?['index']);
    if (textureIndex == null) {
      return null;
    }
    final textures = _list(json['textures']);
    if (textures == null ||
        textureIndex < 0 ||
        textureIndex >= textures.length) {
      return null;
    }
    final imageIndex = _intValue(_map(textures[textureIndex])?['source']);
    if (imageIndex == null) {
      return null;
    }
    return _stringValue(_imageMap(imageIndex)?['name']);
  }

  Uint8List? _imageBytes(
    int imageIndex, {
    required int materialIndex,
    required int textureIndex,
    required String slot,
  }) {
    final images = _list(json['images']);
    if (images == null || imageIndex < 0 || imageIndex >= images.length) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'Image index is outside the glTF images array.',
        ),
      );
      return null;
    }
    final image = _map(images[imageIndex]);
    final mimeType = _stringValue(image?['mimeType']);
    final uri = _stringValue(image?['uri']);
    if (mimeType == 'image/ktx2' ||
        (uri?.toLowerCase().endsWith('.ktx2') ?? false)) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'KTX2 image transcode is not available for GLB textures.',
          requiredExtension: 'KHR_texture_basisu',
          details: _ktx2ImageDetails(imageIndex),
        ),
      );
      return null;
    }
    final bufferViewIndex = _intValue(image?['bufferView']);
    if (bufferViewIndex == null) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'Imported texture image is not stored in a GLB bufferView.',
        ),
      );
      return null;
    }
    final bufferViews = _list(json['bufferViews']);
    if (bufferViews == null ||
        bufferViewIndex < 0 ||
        bufferViewIndex >= bufferViews.length) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'Image bufferView index is outside the bufferViews array.',
        ),
      );
      return null;
    }
    final bin = this.bin;
    final bufferView = _map(bufferViews[bufferViewIndex]);
    final byteOffset = _intValue(bufferView?['byteOffset']) ?? 0;
    final byteLength = _intValue(bufferView?['byteLength']);
    if (bin == null || byteLength == null) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'GLB texture bufferView bytes are unavailable.',
        ),
      );
      return null;
    }
    if (byteOffset < 0 ||
        byteLength < 0 ||
        byteOffset + byteLength > bin.lengthInBytes) {
      diagnostics.add(
        _textureDiagnostic(
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          slot: slot,
          reason: 'GLB texture bufferView exceeds the binary chunk.',
        ),
      );
      return null;
    }
    return Uint8List.fromList(
      Uint8List.sublistView(bin, byteOffset, byteOffset + byteLength),
    );
  }

  Map<String, Object?> _ktx2ImageDetails(int? imageIndex) {
    if (imageIndex == null) {
      return const <String, Object?>{
        'status': 'basisuTranscodeUnavailable',
        'ktx2': <String, Object?>{
          'headerStatus': 'unavailable',
          'reason': 'Texture does not reference a KTX2 image source.',
        },
      };
    }
    final images = _list(json['images']);
    if (images == null || imageIndex < 0 || imageIndex >= images.length) {
      return <String, Object?>{
        'status': 'basisuTranscodeUnavailable',
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
        'status': 'basisuTranscodeUnavailable',
        'ktx2': <String, Object?>{
          'headerStatus': 'unavailable',
          'imageIndex': imageIndex,
          'reason': 'KTX2 image is not stored in a GLB bufferView.',
        },
      };
    }
    final bytes = _bufferViewBytes(bufferViewIndex);
    if (bytes == null) {
      return <String, Object?>{
        'status': 'basisuTranscodeUnavailable',
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

  Uint8List? _bufferViewBytes(int bufferViewIndex) {
    final bufferViews = _list(json['bufferViews']);
    if (bufferViews == null ||
        bufferViewIndex < 0 ||
        bufferViewIndex >= bufferViews.length) {
      return null;
    }
    final bin = this.bin;
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

  List<int> _sceneNodeIndices() {
    final scenes = _list(json['scenes']);
    final sceneIndex = _intValue(json['scene']) ?? 0;
    if (scenes != null && sceneIndex >= 0 && sceneIndex < scenes.length) {
      final scene = _map(scenes[sceneIndex]);
      final nodes = _intList(scene?['nodes']);
      if (nodes != null) {
        return nodes;
      }
    }
    return _rootNodeIndices();
  }

  List<int> _rootNodeIndices() {
    final nodes = _list(json['nodes']);
    if (nodes == null) {
      return const <int>[];
    }
    final childIndices = <int>{};
    for (final rawNode in nodes) {
      final node = _map(rawNode);
      final children = _intList(node?['children']);
      if (children != null) {
        childIndices.addAll(children);
      }
    }
    return <int>[
      for (var index = 0; index < nodes.length; index += 1)
        if (!childIndices.contains(index)) index,
    ];
  }

  void _visitNode(
    int nodeIndex,
    List<String> parentPath, {
    required Map<int, MaterialPatch> materialPatches,
    required Set<int> stack,
  }) {
    if (stack.contains(nodeIndex)) {
      return;
    }
    final nodes = _list(json['nodes']);
    if (nodes == null || nodeIndex < 0 || nodeIndex >= nodes.length) {
      return;
    }
    final node = _map(nodes[nodeIndex]);
    if (node == null) {
      return;
    }
    final name = _stringValue(node['name']) ?? 'node_$nodeIndex';
    final nodePath = List<String>.unmodifiable(<String>[...parentPath, name]);
    final nodePathKey = _pathKey(nodePath);
    _nodePathCounts[nodePathKey] = (_nodePathCounts[nodePathKey] ?? 0) + 1;

    final meshIndex = _intValue(node['mesh']);
    if (meshIndex != null) {
      _collectMeshPrimitives(
        meshIndex,
        nodePath,
        nodePathKey,
        materialPatches: materialPatches,
      );
    }

    final children = _intList(node['children']);
    if (children != null) {
      stack.add(nodeIndex);
      for (final childIndex in children) {
        _visitNode(
          childIndex,
          nodePath,
          materialPatches: materialPatches,
          stack: stack,
        );
      }
      stack.remove(nodeIndex);
    }
  }

  void _collectMeshPrimitives(
    int meshIndex,
    List<String> nodePath,
    String nodePathKey, {
    required Map<int, MaterialPatch> materialPatches,
  }) {
    final meshes = _list(json['meshes']);
    if (meshes == null || meshIndex < 0 || meshIndex >= meshes.length) {
      return;
    }
    final primitives = _list(_map(meshes[meshIndex])?['primitives']);
    if (primitives == null) {
      return;
    }
    for (var primitiveIndex = 0;
        primitiveIndex < primitives.length;
        primitiveIndex += 1) {
      final primitive = _map(primitives[primitiveIndex]);
      final materialIndex = _intValue(primitive?['material']);
      if (materialIndex == null) {
        continue;
      }
      final patch = materialPatches[materialIndex];
      if (patch == null) {
        continue;
      }
      _candidates.add(
        _PatchCandidate(
          address: PartAddress(
            nodePath: nodePath,
            primitiveIndex: primitiveIndex,
          ),
          nodePathKey: nodePathKey,
          patch: patch,
        ),
      );
    }
  }

  ViewerDiagnostic _textureDiagnostic({
    required int materialIndex,
    required int textureIndex,
    required String slot,
    required String reason,
    int? uvSet,
    String? requiredExtension,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message: 'Imported GLB texture cannot be loaded through role-aware path.',
      details: <String, Object?>{
        'source': debugName,
        'materialIndex': materialIndex,
        'textureIndex': textureIndex,
        'textureSlot': slot,
        'reason': reason,
        if (uvSet != null) 'uvSet': uvSet,
        if (requiredExtension != null) 'requiredExtension': requiredExtension,
        ...details,
      },
    );
  }

  GlbImportedTexturePatchResult _result(
    Map<PartAddress, MaterialPatch> patches,
  ) {
    return GlbImportedTexturePatchResult(
      patches: Map<PartAddress, MaterialPatch>.unmodifiable(patches),
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }
}

_GlbChunkReadResult _readGlbChunks(
  Uint8List bytes, {
  required String? debugName,
}) {
  if (bytes.lengthInBytes < 12) {
    return _GlbChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB header is shorter than 12 bytes.'),
    );
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic) {
    return _GlbChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB magic must be glTF.'),
    );
  }
  if (data.getUint32(4, Endian.little) != 2) {
    return _GlbChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB version must be 2.'),
    );
  }
  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength > bytes.lengthInBytes || declaredLength < 20) {
    return _GlbChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB declared length is invalid.'),
    );
  }

  Map<String, Object?>? json;
  Uint8List? bin;
  var offset = 12;
  while (offset + 8 <= declaredLength) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (offset + chunkLength > declaredLength) {
      return _GlbChunkReadResult.diagnostic(
        _glbFailure(debugName, 'GLB chunk length exceeds declared file size.'),
      );
    }
    if (chunkType == _jsonChunkType) {
      if (chunkLength > _maxJsonChunkBytes) {
        return _GlbChunkReadResult.diagnostic(
          _glbFailure(debugName, 'GLB JSON chunk exceeds the reader limit.'),
        );
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(bytes.sublist(offset, offset + chunkLength)),
        );
        if (decoded is Map) {
          json = _objectMap(decoded);
        } else {
          return _GlbChunkReadResult.diagnostic(
            _glbFailure(debugName, 'GLB JSON chunk must decode to an object.'),
          );
        }
      } on Object catch (error) {
        return _GlbChunkReadResult.diagnostic(
          _glbFailure(
            debugName,
            'GLB JSON chunk could not be decoded.',
            error: error,
          ),
        );
      }
    } else if (chunkType == _binChunkType) {
      bin = Uint8List.sublistView(bytes, offset, offset + chunkLength);
    }
    offset += chunkLength;
  }

  if (json == null) {
    return _GlbChunkReadResult.diagnostic(
      _glbFailure(debugName, 'GLB JSON chunk was not found.'),
    );
  }
  return _GlbChunkReadResult(json: json, bin: bin);
}

final class _GlbChunkReadResult {
  const _GlbChunkReadResult({required this.json, required this.bin})
      : diagnostic = null;
  const _GlbChunkReadResult.diagnostic(this.diagnostic)
      : json = null,
        bin = null;

  final Map<String, Object?>? json;
  final Uint8List? bin;
  final ViewerDiagnostic? diagnostic;
}

final class _PatchCandidate {
  const _PatchCandidate({
    required this.address,
    required this.nodePathKey,
    required this.patch,
  });

  final PartAddress address;
  final String nodePathKey;
  final MaterialPatch patch;
}

ViewerDiagnostic _glbFailure(
  String? debugName,
  String message, {
  Object? error,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.adapterFailure,
    message: 'Could not read imported GLB texture metadata.',
    details: <String, Object?>{
      'source': debugName,
      'reason': message,
      if (error != null) 'error': error.toString(),
    },
  );
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

MaterialAlphaMode? _alphaMode(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    return null;
  }
  return switch (value) {
    'OPAQUE' => MaterialAlphaMode.opaque,
    'MASK' => MaterialAlphaMode.mask,
    'BLEND' => MaterialAlphaMode.blend,
    _ => null,
  };
}

bool _pngDeclaresAlphaChannel(Uint8List bytes) {
  const signature = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];
  if (bytes.lengthInBytes < 33) {
    return false;
  }
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[index] != signature[index]) {
      return false;
    }
  }
  final data = ByteData.sublistView(bytes);
  final ihdrLength = data.getUint32(8, Endian.big);
  if (ihdrLength < 13 ||
      bytes[12] != 0x49 ||
      bytes[13] != 0x48 ||
      bytes[14] != 0x44 ||
      bytes[15] != 0x52) {
    return false;
  }
  final colorType = bytes[25];
  return colorType == 4 || colorType == 6;
}

Uint8List _neutralWhitePngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
  );
}

List<int>? _intList(Object? value) {
  if (value is! List) {
    return null;
  }
  final result = <int>[];
  for (final item in value) {
    if (item is int) {
      result.add(item);
    }
  }
  return List<int>.unmodifiable(result);
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

String? _stringValue(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

String _pathKey(List<String> nodePath) {
  return nodePath.map((segment) => '${segment.length}:$segment').join('|');
}
