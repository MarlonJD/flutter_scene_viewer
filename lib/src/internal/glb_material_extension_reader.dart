import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_binding.dart';
import '../texture_source.dart';
import 'glb_capability_reader.dart';
import 'glb_texture_binding_reader.dart';
import 'ktx2_header_reader.dart';
import 'material_extension_patch_group.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;

final class GlbMaterialExtensionReaderResult {
  const GlbMaterialExtensionReaderResult({
    this.patches =
        const <PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  static const empty = GlbMaterialExtensionReaderResult();

  final Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>
      patches;
  final List<ViewerDiagnostic> diagnostics;
}

bool isBinaryGlb(Uint8List bytes) {
  if (bytes.lengthInBytes < 12) {
    return false;
  }
  final data = ByteData.sublistView(bytes);
  return data.getUint32(0, Endian.little) == _glbMagic;
}

GlbMaterialExtensionReaderResult readGlbMaterialExtensionIntent(
  Uint8List bytes, {
  String? debugName,
}) {
  final jsonResult = _readJsonChunk(bytes, debugName: debugName);
  final diagnostic = jsonResult.diagnostic;
  if (diagnostic != null) {
    return GlbMaterialExtensionReaderResult(
      diagnostics: <ViewerDiagnostic>[diagnostic],
    );
  }
  final json = jsonResult.json;
  if (json == null) {
    return GlbMaterialExtensionReaderResult.empty;
  }
  return _GlbMaterialExtensionMapper(
    json,
    bin: jsonResult.bin,
    debugName: debugName,
  ).map();
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
  Map<String, Object?>? json;
  Uint8List? bin;
  while (offset + 8 <= declaredLength) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkType == _jsonChunkType && chunkLength > _maxJsonChunkBytes) {
      return _JsonChunkReadResult.diagnostic(
        _glbFailure(debugName, 'GLB JSON chunk exceeds the reader limit.'),
      );
    }
    if (offset + chunkLength > declaredLength) {
      return _JsonChunkReadResult.diagnostic(
        _glbFailure(debugName, 'GLB chunk length exceeds declared file size.'),
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
          return _JsonChunkReadResult.diagnostic(
            _glbFailure(debugName, 'GLB JSON chunk must decode to an object.'),
          );
        }
      } on Object catch (error) {
        return _JsonChunkReadResult.diagnostic(
          _glbFailure(debugName, 'GLB JSON chunk could not be decoded.',
              error: error),
        );
      }
    } else if (chunkType == _binChunkType && bin == null) {
      bin = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + chunkLength),
      );
    }
    offset += chunkLength;
  }

  if (json != null) {
    return _JsonChunkReadResult.json(json, bin: bin);
  }

  return _JsonChunkReadResult.diagnostic(
    _glbFailure(debugName, 'GLB JSON chunk was not found.'),
  );
}

final class _GlbMaterialExtensionMapper {
  _GlbMaterialExtensionMapper(
    this.json, {
    required this.bin,
    required this.debugName,
  });

  final Map<String, Object?> json;
  final Uint8List? bin;
  final String? debugName;
  final List<ViewerDiagnostic> diagnostics = <ViewerDiagnostic>[];
  final Map<String, int> _nodePathCounts = <String, int>{};
  final Map<String, List<String>> _nodePathsByKey = <String, List<String>>{};
  final List<_AuthoredPatchCandidate> _candidates = <_AuthoredPatchCandidate>[];

  GlbMaterialExtensionReaderResult map() {
    final materialPatches = _materialPatches();
    if (materialPatches.isEmpty) {
      return _result(const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{});
    }
    final sceneNodeIndices = _sceneNodeIndices();
    for (final nodeIndex in sceneNodeIndices) {
      _visitNode(
        nodeIndex,
        const <String>[],
        materialPatches: materialPatches,
        stack: <int>{},
      );
    }

    final patches =
        <PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>{};
    final reportedAmbiguousPaths = <String>{};
    for (final candidate in _candidates) {
      final count = _nodePathCounts[candidate.nodePathKey] ?? 0;
      if (count > 1) {
        if (reportedAmbiguousPaths.add(candidate.nodePathKey)) {
          diagnostics.add(
            ViewerDiagnostic(
              code: ViewerDiagnosticCode.ambiguousNodePath,
              message:
                  'Authored material extension target has an ambiguous node path.',
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
      (patches[candidate.address] ??=
              <MaterialExtensionPatchGroup, MaterialPatch>{})[candidate.group] =
          candidate.patch;
    }
    return _result(patches);
  }

  Map<int, _MaterialPatchGroupsIntent> _materialPatches() {
    final materials = _list(json['materials']);
    if (materials == null) {
      return const <int, _MaterialPatchGroupsIntent>{};
    }
    final result = <int, _MaterialPatchGroupsIntent>{};
    for (var index = 0; index < materials.length; index += 1) {
      final material = _map(materials[index]);
      if (material == null) {
        continue;
      }
      final intent = _patchForMaterial(index, material);
      if (intent != null) {
        result[index] = intent;
      }
    }
    return result;
  }

  _MaterialPatchGroupsIntent? _patchForMaterial(
    int materialIndex,
    Map<String, Object?> material,
  ) {
    final extensions = _map(material['extensions']);
    if (extensions == null) {
      return null;
    }
    var transmissionVolumeInvalid = false;
    var iorInvalid = false;
    var clearcoatInvalid = false;
    var specularInvalid = false;
    final transmissionVolumeTextureSlots = <String>[];
    final clearcoatTextureSlots = <String>[];
    final specularTextureSlots = <String>[];
    double? transmission;
    TextureSource? transmissionTexture;
    double? ior;
    double? thickness;
    TextureSource? thicknessTexture;
    List<double>? attenuationColor;
    double? attenuationDistance;
    double? clearcoat;
    TextureSource? clearcoatTexture;
    double? clearcoatRoughness;
    TextureSource? clearcoatRoughnessTexture;
    TextureSource? clearcoatNormalTexture;
    double? clearcoatNormalScale;
    double? specular;
    TextureSource? specularTexture;
    List<double>? specularColorFactor;
    TextureSource? specularColorTexture;

    final transmissionExtension = _extension(
      extensions,
      'KHR_materials_transmission',
      materialIndex,
    );
    if (transmissionExtension.invalid) {
      transmissionVolumeInvalid = true;
    } else {
      final extension = transmissionExtension.value;
      if (extension != null) {
        final factor = _unitIntervalField(
          extension,
          'transmissionFactor',
          'KHR_materials_transmission',
          materialIndex,
        );
        transmissionVolumeInvalid = transmissionVolumeInvalid || factor.invalid;
        transmission = factor.value;
        final texture = _textureField(
          extension,
          'transmissionTexture',
          'KHR_materials_transmission',
          materialIndex,
        );
        transmissionVolumeInvalid =
            transmissionVolumeInvalid || texture.invalid;
        transmissionTexture = texture.value;
        if (texture.requiresUv) {
          transmissionVolumeTextureSlots.add('transmissionTexture');
        }
      }
    }

    final iorExtension =
        _extension(extensions, 'KHR_materials_ior', materialIndex);
    if (iorExtension.invalid) {
      iorInvalid = true;
    } else {
      final extension = iorExtension.value;
      if (extension != null) {
        final value = _iorField(
          extension,
          'ior',
          'KHR_materials_ior',
          materialIndex,
        );
        iorInvalid = iorInvalid || value.invalid;
        ior = value.value;
      }
    }

    final volumeExtension =
        _extension(extensions, 'KHR_materials_volume', materialIndex);
    if (volumeExtension.invalid) {
      transmissionVolumeInvalid = true;
    } else {
      final extension = volumeExtension.value;
      if (extension != null) {
        final thicknessValue = _doubleField(
          extension,
          'thicknessFactor',
          'KHR_materials_volume',
          materialIndex,
        );
        transmissionVolumeInvalid =
            transmissionVolumeInvalid || thicknessValue.invalid;
        thickness = thicknessValue.value;
        final texture = _textureField(
          extension,
          'thicknessTexture',
          'KHR_materials_volume',
          materialIndex,
        );
        transmissionVolumeInvalid =
            transmissionVolumeInvalid || texture.invalid;
        thicknessTexture = texture.value;
        if (texture.requiresUv) {
          transmissionVolumeTextureSlots.add('thicknessTexture');
        }
        final color = _doubleListField(
          extension,
          'attenuationColor',
          'KHR_materials_volume',
          materialIndex,
          length: 3,
        );
        transmissionVolumeInvalid = transmissionVolumeInvalid || color.invalid;
        attenuationColor = color.value;
        final distance = _doubleField(
          extension,
          'attenuationDistance',
          'KHR_materials_volume',
          materialIndex,
        );
        transmissionVolumeInvalid =
            transmissionVolumeInvalid || distance.invalid;
        attenuationDistance = distance.value;
      }
    }

    final clearcoatExtension =
        _extension(extensions, 'KHR_materials_clearcoat', materialIndex);
    if (clearcoatExtension.invalid) {
      clearcoatInvalid = true;
    } else {
      final extension = clearcoatExtension.value;
      if (extension != null) {
        final factor = _unitIntervalField(
          extension,
          'clearcoatFactor',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || factor.invalid;
        clearcoat = factor.value;
        final texture = _textureField(
          extension,
          'clearcoatTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || texture.invalid;
        clearcoatTexture = texture.value;
        if (texture.requiresUv) {
          clearcoatTextureSlots.add('clearcoatTexture');
        }
        final roughness = _unitIntervalField(
          extension,
          'clearcoatRoughnessFactor',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || roughness.invalid;
        clearcoatRoughness = roughness.value;
        final roughnessTexture = _textureField(
          extension,
          'clearcoatRoughnessTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || roughnessTexture.invalid;
        clearcoatRoughnessTexture = roughnessTexture.value;
        if (roughnessTexture.requiresUv) {
          clearcoatTextureSlots.add('clearcoatRoughnessTexture');
        }
        final normalTexture = _textureField(
          extension,
          'clearcoatNormalTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || normalTexture.invalid;
        clearcoatNormalTexture = normalTexture.value;
        if (normalTexture.requiresUv) {
          clearcoatTextureSlots.add('clearcoatNormalTexture');
        }
        final normalScale = _finiteTextureInfoDoubleField(
          extension,
          'clearcoatNormalTexture',
          'scale',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        clearcoatInvalid = clearcoatInvalid || normalScale.invalid;
        clearcoatNormalScale = normalScale.value;
      }
    }

    final specularExtension =
        _extension(extensions, 'KHR_materials_specular', materialIndex);
    if (specularExtension.invalid) {
      specularInvalid = true;
    } else {
      final extension = specularExtension.value;
      if (extension != null) {
        final factor = _unitIntervalField(
          extension,
          'specularFactor',
          'KHR_materials_specular',
          materialIndex,
        );
        specularInvalid = specularInvalid || factor.invalid;
        specular = factor.value;
        final texture = _textureField(
          extension,
          'specularTexture',
          'KHR_materials_specular',
          materialIndex,
        );
        specularInvalid = specularInvalid || texture.invalid;
        specularTexture = texture.value;
        if (texture.requiresUv) {
          specularTextureSlots.add('specularTexture');
        }
        final colorFactor = _nonNegativeRgbField(
          extension,
          'specularColorFactor',
          'KHR_materials_specular',
          materialIndex,
        );
        specularInvalid = specularInvalid || colorFactor.invalid;
        specularColorFactor = colorFactor.value;
        final colorTexture = _textureField(
          extension,
          'specularColorTexture',
          'KHR_materials_specular',
          materialIndex,
        );
        specularInvalid = specularInvalid || colorTexture.invalid;
        specularColorTexture = colorTexture.value;
        if (colorTexture.requiresUv) {
          specularTextureSlots.add('specularColorTexture');
        }
      }
    }

    final hasTransmissionOrVolumeIntent =
        extensions.containsKey('KHR_materials_transmission') ||
            extensions.containsKey('KHR_materials_volume');
    final groups =
        <MaterialExtensionPatchGroup, _MaterialExtensionGroupIntent>{};
    final transmissionVolumePatch = MaterialPatch(
      transmission: transmission,
      transmissionTexture: transmissionTexture,
      ior: hasTransmissionOrVolumeIntent && !iorInvalid ? ior : null,
      thickness: thickness,
      thicknessTexture: thicknessTexture,
      attenuationColor: attenuationColor,
      attenuationDistance: attenuationDistance,
    );
    if (!transmissionVolumeInvalid && !transmissionVolumePatch.isEmpty) {
      groups[MaterialExtensionPatchGroup.transmissionVolume] =
          _MaterialExtensionGroupIntent(
        patch: transmissionVolumePatch,
        textureSlots: List<String>.unmodifiable(transmissionVolumeTextureSlots),
      );
    }
    final opaqueIorPatch = MaterialPatch(
      ior: !hasTransmissionOrVolumeIntent && !iorInvalid ? ior : null,
    );
    if (!iorInvalid && !opaqueIorPatch.isEmpty) {
      groups[MaterialExtensionPatchGroup.opaqueIor] =
          _MaterialExtensionGroupIntent(
        patch: opaqueIorPatch,
        textureSlots: const <String>[],
      );
    }
    final clearcoatPatch = MaterialPatch(
      clearcoat: clearcoat,
      clearcoatTexture: clearcoatTexture,
      clearcoatRoughness: clearcoatRoughness,
      clearcoatRoughnessTexture: clearcoatRoughnessTexture,
      clearcoatNormalTexture: clearcoatNormalTexture,
      clearcoatNormalScale: clearcoatNormalScale,
    );
    if (!clearcoatInvalid && !clearcoatPatch.isEmpty) {
      groups[MaterialExtensionPatchGroup.clearcoat] =
          _MaterialExtensionGroupIntent(
        patch: clearcoatPatch,
        textureSlots: List<String>.unmodifiable(clearcoatTextureSlots),
      );
    }
    final specularPatch = MaterialPatch(
      specular: specular,
      specularTexture: specularTexture,
      specularColorFactor: specularColorFactor,
      specularColorTexture: specularColorTexture,
    );
    if (!specularInvalid && !specularPatch.isEmpty) {
      groups[MaterialExtensionPatchGroup.specular] =
          _MaterialExtensionGroupIntent(
        patch: specularPatch,
        textureSlots: List<String>.unmodifiable(specularTextureSlots),
      );
    }
    if (groups.isEmpty) {
      return null;
    }
    return _MaterialPatchGroupsIntent(
      Map<MaterialExtensionPatchGroup,
          _MaterialExtensionGroupIntent>.unmodifiable(groups),
    );
  }

  List<int> _sceneNodeIndices() {
    final nodes = _list(json['nodes']);
    if (nodes == null) {
      return const <int>[];
    }
    final scenes = _list(json['scenes']);
    final sceneIndex = _intValue(json['scene']);
    if (scenes != null &&
        sceneIndex != null &&
        sceneIndex >= 0 &&
        sceneIndex < scenes.length) {
      final scene = _map(scenes[sceneIndex]);
      final sceneNodes = _intList(scene?['nodes']);
      if (sceneNodes != null) {
        return sceneNodes;
      }
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
    required Map<int, _MaterialPatchGroupsIntent> materialPatches,
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
    _nodePathsByKey[nodePathKey] = nodePath;

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
    required Map<int, _MaterialPatchGroupsIntent> materialPatches,
  }) {
    final meshes = _list(json['meshes']);
    if (meshes == null || meshIndex < 0 || meshIndex >= meshes.length) {
      return;
    }
    final mesh = _map(meshes[meshIndex]);
    final primitives = _list(mesh?['primitives']);
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
      final intent = materialPatches[materialIndex];
      if (intent == null) {
        continue;
      }
      final address = PartAddress(
        nodePath: nodePath,
        primitiveIndex: primitiveIndex,
      );
      for (final entry in intent.groups.entries) {
        final boundPatch = _bindGroupPatchForPrimitive(
          materialIndex: materialIndex,
          primitive: primitive ?? const <String, Object?>{},
          group: entry.key,
          patch: entry.value.patch,
        );
        if (boundPatch == null || boundPatch.isEmpty) {
          continue;
        }
        _candidates.add(
          _AuthoredPatchCandidate(
            address: address,
            nodePathKey: nodePathKey,
            group: entry.key,
            patch: boundPatch,
          ),
        );
      }
    }
  }

  MaterialPatch? _bindGroupPatchForPrimitive({
    required int materialIndex,
    required Map<String, Object?> primitive,
    required MaterialExtensionPatchGroup group,
    required MaterialPatch patch,
  }) {
    if (group == MaterialExtensionPatchGroup.opaqueIor) {
      return patch;
    }
    final materials = _list(json['materials']) ?? const <Object?>[];
    final material = materialIndex >= 0 && materialIndex < materials.length
        ? _map(materials[materialIndex])
        : null;
    final extensions = _map(material?['extensions']);
    final context = readGlbPrimitiveTextureContext(
      primitive: primitive,
      extensionsRequired: Set<String>.from(
        (_list(json['extensionsRequired']) ?? const <Object?>[])
            .whereType<String>(),
      ),
    );
    final textures = _list(json['textures']) ?? const <Object?>[];
    final samplers = _list(json['samplers']) ?? const <Object?>[];
    var failed = false;

    MaterialTextureBinding? bind(
      String extensionName,
      String field,
      TextureSource? source,
    ) {
      if (source == null) {
        return null;
      }
      final textureInfo = _map(_map(extensions?[extensionName])?[field]);
      if (textureInfo == null) {
        failed = true;
        return null;
      }
      final result = readGlbTextureBinding(
        textureInfo: textureInfo,
        textures: textures,
        samplers: samplers,
        source: source,
        availableTexCoords: context.availableTexCoords,
        textureTransformRequired: context.textureTransformRequired,
        slot: '$extensionName.$field',
        debugName: debugName ?? 'GLB',
      );
      diagnostics.addAll(result.diagnostics);
      if (result.binding == null) {
        failed = true;
      }
      return result.binding;
    }

    if (group == MaterialExtensionPatchGroup.transmissionVolume) {
      final transmissionBinding = bind(
        'KHR_materials_transmission',
        'transmissionTexture',
        patch.transmissionTexture,
      );
      final thicknessBinding = bind(
        'KHR_materials_volume',
        'thicknessTexture',
        patch.thicknessTexture,
      );
      if (failed) {
        return null;
      }
      return MaterialPatch(
        transmission: patch.transmission,
        transmissionTextureBinding: transmissionBinding,
        ior: patch.ior,
        thickness: patch.thickness,
        thicknessTextureBinding: thicknessBinding,
        attenuationColor: patch.attenuationColor,
        attenuationDistance: patch.attenuationDistance,
      );
    }
    if (group == MaterialExtensionPatchGroup.clearcoat) {
      final clearcoatBinding = bind(
        'KHR_materials_clearcoat',
        'clearcoatTexture',
        patch.clearcoatTexture,
      );
      final roughnessBinding = bind(
        'KHR_materials_clearcoat',
        'clearcoatRoughnessTexture',
        patch.clearcoatRoughnessTexture,
      );
      final normalBinding = bind(
        'KHR_materials_clearcoat',
        'clearcoatNormalTexture',
        patch.clearcoatNormalTexture,
      );
      if (failed) {
        return null;
      }
      return MaterialPatch(
        clearcoat: patch.clearcoat,
        clearcoatTextureBinding: clearcoatBinding,
        clearcoatRoughness: patch.clearcoatRoughness,
        clearcoatRoughnessTextureBinding: roughnessBinding,
        clearcoatNormalTextureBinding: normalBinding,
        clearcoatNormalScale:
            normalBinding == null ? null : patch.clearcoatNormalScale,
      );
    }
    final specularBinding = bind(
      'KHR_materials_specular',
      'specularTexture',
      patch.specularTexture,
    );
    final colorBinding = bind(
      'KHR_materials_specular',
      'specularColorTexture',
      patch.specularColorTexture,
    );
    if (failed) {
      return null;
    }
    return MaterialPatch(
      specular: patch.specular,
      specularTextureBinding: specularBinding,
      specularColorFactor: patch.specularColorFactor,
      specularColorTextureBinding: colorBinding,
    );
  }

  _ExtensionRead _extension(
    Map<String, Object?> extensions,
    String extensionName,
    int materialIndex,
  ) {
    final raw = extensions[extensionName];
    if (raw == null) {
      return const _ExtensionRead();
    }
    final extension = _map(raw);
    if (extension == null) {
      diagnostics.add(
        _invalidExtensionDiagnostic(
          extensionName: extensionName,
          field: 'extensions.$extensionName',
          materialIndex: materialIndex,
          value: raw,
        ),
      );
      return const _ExtensionRead.invalid();
    }
    return _ExtensionRead(value: extension);
  }

  _DoubleRead _doubleField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final value = extension[field];
    if (value == null) {
      return const _DoubleRead();
    }
    if (value is num) {
      return _DoubleRead(value: value.toDouble());
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: field,
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleRead.invalid();
  }

  _DoubleRead _unitIntervalField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final result = _doubleField(extension, field, extensionName, materialIndex);
    final value = result.value;
    if (result.invalid || value == null) {
      return result;
    }
    if (value.isFinite && value >= 0 && value <= 1) {
      return result;
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: field,
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleRead.invalid();
  }

  _DoubleRead _iorField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final result = _doubleField(extension, field, extensionName, materialIndex);
    final value = result.value;
    if (result.invalid || value == null) {
      return result;
    }
    if (value.isFinite && (value == 0 || value >= 1)) {
      return result;
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: field,
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleRead.invalid();
  }

  _DoubleListRead _doubleListField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex, {
    required int length,
  }) {
    final value = extension[field];
    if (value == null) {
      return const _DoubleListRead();
    }
    if (value is List && value.length == length) {
      final result = <double>[];
      for (final item in value) {
        if (item is! num) {
          diagnostics.add(
            _invalidExtensionDiagnostic(
              extensionName: extensionName,
              field: field,
              materialIndex: materialIndex,
              value: value,
            ),
          );
          return const _DoubleListRead.invalid();
        }
        result.add(item.toDouble());
      }
      return _DoubleListRead(value: List<double>.unmodifiable(result));
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: field,
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleListRead.invalid();
  }

  _DoubleListRead _nonNegativeRgbField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final result = _doubleListField(
      extension,
      field,
      extensionName,
      materialIndex,
      length: 3,
    );
    final value = result.value;
    if (result.invalid || value == null) {
      return result;
    }
    if (value.every((component) => component.isFinite && component >= 0)) {
      return result;
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: field,
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleListRead.invalid();
  }

  _DoubleRead _textureInfoDoubleField(
    Map<String, Object?> extension,
    String textureField,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final textureInfo = _map(extension[textureField]);
    if (textureInfo == null || !textureInfo.containsKey(field)) {
      return const _DoubleRead();
    }
    final value = textureInfo[field];
    if (value is num) {
      return _DoubleRead(value: value.toDouble());
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: '$textureField.$field',
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleRead.invalid();
  }

  _DoubleRead _finiteTextureInfoDoubleField(
    Map<String, Object?> extension,
    String textureField,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final result = _textureInfoDoubleField(
      extension,
      textureField,
      field,
      extensionName,
      materialIndex,
    );
    final value = result.value;
    if (result.invalid || value == null || value.isFinite) {
      return result;
    }
    diagnostics.add(
      _invalidExtensionDiagnostic(
        extensionName: extensionName,
        field: '$textureField.$field',
        materialIndex: materialIndex,
        value: value,
      ),
    );
    return const _DoubleRead.invalid();
  }

  _TextureRead _textureField(
    Map<String, Object?> extension,
    String field,
    String extensionName,
    int materialIndex,
  ) {
    final value = extension[field];
    if (value == null) {
      return const _TextureRead();
    }
    final textureInfo = _map(value);
    final index = _intValue(textureInfo?['index']);
    if (textureInfo == null) {
      diagnostics.add(
        _invalidExtensionDiagnostic(
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          value: value,
        ),
      );
      return const _TextureRead.invalid();
    }
    final textures = _list(json['textures']) ?? const <Object?>[];
    if (index == null || index < 0 || index >= textures.length) {
      final malformed = readGlbTextureBinding(
        textureInfo: textureInfo,
        textures: textures,
        samplers: _list(json['samplers']) ?? const <Object?>[],
        source: const AssetTextureSource('__unresolved_glb_texture__'),
        availableTexCoords: const <int>{0},
        textureTransformRequired:
            (_list(json['extensionsRequired']) ?? const <Object?>[])
                .contains('KHR_texture_transform'),
        slot: '$extensionName.$field',
        debugName: debugName ?? 'GLB',
      );
      diagnostics.addAll(
        malformed.diagnostics.map(
          (diagnostic) => ViewerDiagnostic(
            code: diagnostic.code,
            message: diagnostic.message,
            details: <String, Object?>{
              ...diagnostic.details,
              'extension': extensionName,
              'field': field,
              'materialIndex': materialIndex,
              ..._requirednessDetails(extensionName),
            },
          ),
        ),
      );
      return const _TextureRead.invalid();
    }
    final bytes = _textureBytes(
      index,
      extensionName: extensionName,
      field: field,
      materialIndex: materialIndex,
    );
    if (bytes == null) {
      return const _TextureRead.invalid(requiresUv: true);
    }
    return _TextureRead(
      requiresUv: true,
      value: TextureSource.bytes(
        bytes,
        debugName: 'glb-texture:$index:$extensionName.$field',
      ),
    );
  }

  Uint8List? _textureBytes(
    int textureIndex, {
    required String extensionName,
    required String field,
    required int materialIndex,
  }) {
    final textures = _list(json['textures']);
    if (textures == null ||
        textureIndex < 0 ||
        textureIndex >= textures.length) {
      diagnostics.add(
        _textureDiagnostic(
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
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
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          reason:
              'Texture uses KHR_texture_basisu and requires KTX2/BasisU transcode support.',
          extension: 'KHR_texture_basisu',
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
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          reason: 'Texture does not reference an image source.',
        ),
      );
      return null;
    }
    return _imageBytes(
      imageIndex,
      extensionName: extensionName,
      field: field,
      materialIndex: materialIndex,
      textureIndex: textureIndex,
    );
  }

  Uint8List? _imageBytes(
    int imageIndex, {
    required String extensionName,
    required String field,
    required int materialIndex,
    required int textureIndex,
  }) {
    final images = _list(json['images']);
    if (images == null || imageIndex < 0 || imageIndex >= images.length) {
      diagnostics.add(
        _textureDiagnostic(
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
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
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          reason: 'KTX2 image transcode is not available for GLB textures.',
          extension: 'KHR_texture_basisu',
          details: _ktx2ImageDetails(imageIndex),
        ),
      );
      return null;
    }
    final bufferViewIndex = _intValue(image?['bufferView']);
    if (bufferViewIndex == null) {
      diagnostics.add(
        _textureDiagnostic(
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
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
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
          reason: 'Image bufferView index is outside the bufferViews array.',
        ),
      );
      return null;
    }
    final bufferView = _map(bufferViews[bufferViewIndex]);
    final byteOffset = _intValue(bufferView?['byteOffset']) ?? 0;
    final byteLength = _intValue(bufferView?['byteLength']);
    final bin = this.bin;
    if (bin == null || byteLength == null) {
      diagnostics.add(
        _textureDiagnostic(
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
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
          extensionName: extensionName,
          field: field,
          materialIndex: materialIndex,
          textureIndex: textureIndex,
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
    final bufferView = _map(bufferViews[bufferViewIndex]);
    final byteOffset = _intValue(bufferView?['byteOffset']) ?? 0;
    final byteLength = _intValue(bufferView?['byteLength']);
    final bin = this.bin;
    if (bin == null ||
        byteLength == null ||
        byteOffset < 0 ||
        byteLength < 0 ||
        byteOffset + byteLength > bin.lengthInBytes) {
      return null;
    }
    return Uint8List.sublistView(bin, byteOffset, byteOffset + byteLength);
  }

  ViewerDiagnostic _textureDiagnostic({
    required String extensionName,
    required String field,
    required int materialIndex,
    required int textureIndex,
    required String reason,
    String? extension,
    int? uvSet,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message:
          'Authored GLB material extension texture cannot be loaded through role-aware path.',
      details: <String, Object?>{
        'source': debugName,
        'materialIndex': materialIndex,
        'textureIndex': textureIndex,
        'extension': extensionName,
        'field': field,
        'reason': reason,
        if (extension != null) 'requiredExtension': extension,
        if (uvSet != null) 'uvSet': uvSet,
        ..._requirednessDetails(
          extensionName,
          dependencyExtension: extension,
        ),
        ...details,
      },
    );
  }

  ViewerDiagnostic _invalidExtensionDiagnostic({
    required String extensionName,
    required String field,
    required int materialIndex,
    required Object? value,
  }) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.invalidMaterialOverride,
      message: 'Authored GLB material extension value is invalid.',
      details: <String, Object?>{
        'source': debugName,
        'materialIndex': materialIndex,
        'extension': extensionName,
        'field': field,
        'value': value?.toString(),
        ..._requirednessDetails(extensionName),
      },
    );
  }

  Map<String, Object?> _requirednessDetails(
    String extensionName, {
    String? dependencyExtension,
  }) {
    final requiredExtensions =
        (_list(json['extensionsRequired']) ?? const <Object?>[])
            .whereType<String>()
            .toSet();
    final required = requiredExtensions.contains(extensionName) ||
        (dependencyExtension != null &&
            requiredExtensions.contains(dependencyExtension));
    return <String, Object?>{
      'required': required,
      'blocking': required,
      'status': required ? 'malformedAsset' : 'optionalExtensionIgnored',
      'fallback': required ? 'none' : 'coreMaterial',
    };
  }

  GlbMaterialExtensionReaderResult _result(
    Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>> patches,
  ) {
    final immutablePatches =
        <PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>{
      for (final entry in patches.entries)
        entry.key: Map<MaterialExtensionPatchGroup, MaterialPatch>.unmodifiable(
          entry.value,
        ),
    };
    return GlbMaterialExtensionReaderResult(
      patches: Map<PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>.unmodifiable(
        immutablePatches,
      ),
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
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

final class _MaterialPatchGroupsIntent {
  const _MaterialPatchGroupsIntent(this.groups);

  final Map<MaterialExtensionPatchGroup, _MaterialExtensionGroupIntent> groups;
}

final class _MaterialExtensionGroupIntent {
  const _MaterialExtensionGroupIntent({
    required this.patch,
    required this.textureSlots,
  });

  final MaterialPatch patch;
  final List<String> textureSlots;
}

final class _AuthoredPatchCandidate {
  const _AuthoredPatchCandidate({
    required this.address,
    required this.nodePathKey,
    required this.group,
    required this.patch,
  });

  final PartAddress address;
  final String nodePathKey;
  final MaterialExtensionPatchGroup group;
  final MaterialPatch patch;
}

final class _ExtensionRead {
  const _ExtensionRead({this.value}) : invalid = false;
  const _ExtensionRead.invalid()
      : value = null,
        invalid = true;

  final Map<String, Object?>? value;
  final bool invalid;
}

final class _DoubleRead {
  const _DoubleRead({this.value}) : invalid = false;
  const _DoubleRead.invalid()
      : value = null,
        invalid = true;

  final double? value;
  final bool invalid;
}

final class _DoubleListRead {
  const _DoubleListRead({this.value}) : invalid = false;
  const _DoubleListRead.invalid()
      : value = null,
        invalid = true;

  final List<double>? value;
  final bool invalid;
}

final class _TextureRead {
  const _TextureRead({this.value, this.requiresUv = false}) : invalid = false;
  const _TextureRead.invalid({this.requiresUv = false})
      : value = null,
        invalid = true;

  final TextureSource? value;
  final bool requiresUv;
  final bool invalid;
}

ViewerDiagnostic _glbFailure(
  String? debugName,
  String message, {
  Object? error,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.adapterFailure,
    message: 'Could not read authored GLB material extension metadata.',
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

String? _stringValue(Object? value) => value is String ? value : null;

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

List<int>? _intList(Object? value) {
  if (value is! List) {
    return null;
  }
  final result = <int>[];
  for (final item in value) {
    if (item is! int) {
      return null;
    }
    result.add(item);
  }
  return result;
}

String _pathKey(List<String> nodePath) {
  return nodePath.map((segment) => '${segment.length}:$segment').join('|');
}
