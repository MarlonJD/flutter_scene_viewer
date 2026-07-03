import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_source.dart';

const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _maxJsonChunkBytes = 8 * 1024 * 1024;

final class GlbMaterialExtensionReaderResult {
  const GlbMaterialExtensionReaderResult({
    this.patches = const <PartAddress, MaterialPatch>{},
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  static const empty = GlbMaterialExtensionReaderResult();

  final Map<PartAddress, MaterialPatch> patches;
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
  return _GlbMaterialExtensionMapper(json, debugName: debugName).map();
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
      try {
        final decoded = jsonDecode(
          utf8.decode(bytes.sublist(offset, offset + chunkLength)),
        );
        if (decoded is Map) {
          return _JsonChunkReadResult.json(_objectMap(decoded));
        }
        return _JsonChunkReadResult.diagnostic(
          _glbFailure(debugName, 'GLB JSON chunk must decode to an object.'),
        );
      } on Object catch (error) {
        return _JsonChunkReadResult.diagnostic(
          _glbFailure(debugName, 'GLB JSON chunk could not be decoded.',
              error: error),
        );
      }
    }
    offset += chunkLength;
  }

  return _JsonChunkReadResult.diagnostic(
    _glbFailure(debugName, 'GLB JSON chunk was not found.'),
  );
}

final class _GlbMaterialExtensionMapper {
  _GlbMaterialExtensionMapper(this.json, {required this.debugName});

  final Map<String, Object?> json;
  final String? debugName;
  final List<ViewerDiagnostic> diagnostics = <ViewerDiagnostic>[];
  final Map<String, int> _nodePathCounts = <String, int>{};
  final Map<String, List<String>> _nodePathsByKey = <String, List<String>>{};
  final List<_AuthoredPatchCandidate> _candidates = <_AuthoredPatchCandidate>[];

  GlbMaterialExtensionReaderResult map() {
    final materialPatches = _materialPatches();
    if (materialPatches.isEmpty) {
      return _result(const <PartAddress, MaterialPatch>{});
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
      patches[candidate.address] = candidate.patch;
    }
    return _result(patches);
  }

  Map<int, _MaterialPatchIntent> _materialPatches() {
    final materials = _list(json['materials']);
    if (materials == null) {
      return const <int, _MaterialPatchIntent>{};
    }
    final result = <int, _MaterialPatchIntent>{};
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

  _MaterialPatchIntent? _patchForMaterial(
    int materialIndex,
    Map<String, Object?> material,
  ) {
    final extensions = _map(material['extensions']);
    if (extensions == null) {
      return null;
    }
    var invalid = false;
    final textureSlots = <String>[];
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

    final transmissionExtension = _extension(
      extensions,
      'KHR_materials_transmission',
      materialIndex,
    );
    if (transmissionExtension.invalid) {
      invalid = true;
    } else {
      final extension = transmissionExtension.value;
      if (extension != null) {
        final factor = _doubleField(
          extension,
          'transmissionFactor',
          'KHR_materials_transmission',
          materialIndex,
        );
        invalid = invalid || factor.invalid;
        transmission = factor.value;
        final texture = _textureField(
          extension,
          'transmissionTexture',
          'KHR_materials_transmission',
          materialIndex,
        );
        invalid = invalid || texture.invalid;
        transmissionTexture = texture.value;
        if (texture.value != null) {
          textureSlots.add('transmissionTexture');
        }
      }
    }

    final iorExtension =
        _extension(extensions, 'KHR_materials_ior', materialIndex);
    if (iorExtension.invalid) {
      invalid = true;
    } else {
      final extension = iorExtension.value;
      if (extension != null) {
        final value = _doubleField(
          extension,
          'ior',
          'KHR_materials_ior',
          materialIndex,
        );
        invalid = invalid || value.invalid;
        ior = value.value;
      }
    }

    final volumeExtension =
        _extension(extensions, 'KHR_materials_volume', materialIndex);
    if (volumeExtension.invalid) {
      invalid = true;
    } else {
      final extension = volumeExtension.value;
      if (extension != null) {
        final thicknessValue = _doubleField(
          extension,
          'thicknessFactor',
          'KHR_materials_volume',
          materialIndex,
        );
        invalid = invalid || thicknessValue.invalid;
        thickness = thicknessValue.value;
        final texture = _textureField(
          extension,
          'thicknessTexture',
          'KHR_materials_volume',
          materialIndex,
        );
        invalid = invalid || texture.invalid;
        thicknessTexture = texture.value;
        if (texture.value != null) {
          textureSlots.add('thicknessTexture');
        }
        final color = _doubleListField(
          extension,
          'attenuationColor',
          'KHR_materials_volume',
          materialIndex,
          length: 3,
        );
        invalid = invalid || color.invalid;
        attenuationColor = color.value;
        final distance = _doubleField(
          extension,
          'attenuationDistance',
          'KHR_materials_volume',
          materialIndex,
        );
        invalid = invalid || distance.invalid;
        attenuationDistance = distance.value;
      }
    }

    final clearcoatExtension =
        _extension(extensions, 'KHR_materials_clearcoat', materialIndex);
    if (clearcoatExtension.invalid) {
      invalid = true;
    } else {
      final extension = clearcoatExtension.value;
      if (extension != null) {
        final factor = _doubleField(
          extension,
          'clearcoatFactor',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        invalid = invalid || factor.invalid;
        clearcoat = factor.value;
        final texture = _textureField(
          extension,
          'clearcoatTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        invalid = invalid || texture.invalid;
        clearcoatTexture = texture.value;
        if (texture.value != null) {
          textureSlots.add('clearcoatTexture');
        }
        final roughness = _doubleField(
          extension,
          'clearcoatRoughnessFactor',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        invalid = invalid || roughness.invalid;
        clearcoatRoughness = roughness.value;
        final roughnessTexture = _textureField(
          extension,
          'clearcoatRoughnessTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        invalid = invalid || roughnessTexture.invalid;
        clearcoatRoughnessTexture = roughnessTexture.value;
        if (roughnessTexture.value != null) {
          textureSlots.add('clearcoatRoughnessTexture');
        }
        final normalTexture = _textureField(
          extension,
          'clearcoatNormalTexture',
          'KHR_materials_clearcoat',
          materialIndex,
        );
        invalid = invalid || normalTexture.invalid;
        clearcoatNormalTexture = normalTexture.value;
        if (normalTexture.value != null) {
          textureSlots.add('clearcoatNormalTexture');
        }
      }
    }

    if (invalid) {
      return null;
    }
    final patch = MaterialPatch(
      transmission: transmission,
      transmissionTexture: transmissionTexture,
      ior: ior,
      thickness: thickness,
      thicknessTexture: thicknessTexture,
      attenuationColor: attenuationColor,
      attenuationDistance: attenuationDistance,
      clearcoat: clearcoat,
      clearcoatTexture: clearcoatTexture,
      clearcoatRoughness: clearcoatRoughness,
      clearcoatRoughnessTexture: clearcoatRoughnessTexture,
      clearcoatNormalTexture: clearcoatNormalTexture,
    );
    if (patch.isEmpty) {
      return null;
    }
    return _MaterialPatchIntent(
      patch: patch,
      textureSlots: List<String>.unmodifiable(textureSlots),
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
    required Map<int, _MaterialPatchIntent> materialPatches,
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
    required Map<int, _MaterialPatchIntent> materialPatches,
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
      if (intent.textureSlots.isNotEmpty && !_hasTexCoord0(primitive)) {
        diagnostics.add(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.missingUvSet,
            message: 'Authored material extension texture requires TEXCOORD_0.',
            details: <String, Object?>{
              'source': debugName,
              'part': address.debugPath,
              'uvSet': 0,
              'textureSlots': intent.textureSlots,
            },
          ),
        );
        continue;
      }
      _candidates.add(
        _AuthoredPatchCandidate(
          address: address,
          nodePathKey: nodePathKey,
          patch: intent.patch,
        ),
      );
    }
  }

  bool _hasTexCoord0(Map<String, Object?>? primitive) {
    final attributes = _map(primitive?['attributes']);
    return attributes != null && attributes.containsKey('TEXCOORD_0');
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
    if (textureInfo == null || index == null) {
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
    return _TextureRead(
      value: TextureSource.bytes(
        Uint8List(0),
        debugName: 'glb-texture:$index:$extensionName.$field',
      ),
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
      },
    );
  }

  GlbMaterialExtensionReaderResult _result(
      Map<PartAddress, MaterialPatch> patches) {
    return GlbMaterialExtensionReaderResult(
      patches: Map<PartAddress, MaterialPatch>.unmodifiable(patches),
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }
}

final class _JsonChunkReadResult {
  const _JsonChunkReadResult.json(this.json) : diagnostic = null;
  const _JsonChunkReadResult.diagnostic(this.diagnostic) : json = null;

  final Map<String, Object?>? json;
  final ViewerDiagnostic? diagnostic;
}

final class _MaterialPatchIntent {
  const _MaterialPatchIntent({
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
    required this.patch,
  });

  final PartAddress address;
  final String nodePathKey;
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
  const _TextureRead({this.value}) : invalid = false;
  const _TextureRead.invalid()
      : value = null,
        invalid = true;

  final TextureSource? value;
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
