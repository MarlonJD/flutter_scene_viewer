import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_source.dart';

/// Internal boundary for direct `flutter_scene` API calls.
///
/// Keep this file and nearby adapter files as the only place where concrete
/// `flutter_scene` classes leak into implementation details. Public API should
/// stay stable even when `flutter_scene` changes.
abstract interface class FlutterSceneAdapter {
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName});

  AdapterNodeSnapshot? get nodeSnapshot;

  Future<List<ViewerDiagnostic>> applyMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  );

  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address);

  List<ViewerDiagnostic> collectDiagnostics();
}

/// Runtime adapter backed by the installed `flutter_scene` package.
final class FlutterSceneRuntimeAdapter implements FlutterSceneAdapter {
  flutter_scene.Node? _rootNode;
  final Map<PartAddress, _OriginalMaterialState> _originalMaterials =
      <PartAddress, _OriginalMaterialState>{};

  flutter_scene.Node? get rootNode => _rootNode;

  @override
  AdapterNodeSnapshot? get nodeSnapshot {
    final rootNode = _rootNode;
    if (rootNode == null) {
      return null;
    }
    return _snapshotNode(rootNode);
  }

  @override
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName}) async {
    await flutter_scene.loadBaseShaderLibrary();
    await flutter_scene.Material.initializeStaticResources();
    _rootNode = await flutter_scene.Node.fromGlbBytes(bytes);
    _originalMaterials.clear();
  }

  @override
  Future<List<ViewerDiagnostic>> applyMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  ) async {
    final target = _resolveTarget(address);
    if (target == null) {
      return <ViewerDiagnostic>[_primitiveNotFound(address)];
    }

    if (patch.baseColorTexture != null &&
        !_primitiveHasTexCoords(target.primitive)) {
      return <ViewerDiagnostic>[_missingUv(address)];
    }

    final material = target.primitive.material;
    if (_requiresPbrMaterial(patch) &&
        material is! flutter_scene.PhysicallyBasedMaterial) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Material override requires a PBR material.',
          details: <String, Object?>{'part': address.debugPath},
        ),
      ];
    }

    final texture = patch.baseColorTexture;
    final _TextureLoadResult? loadedTexture;
    if (texture == null) {
      loadedTexture = null;
    } else {
      loadedTexture = await _loadBaseColorTexture(texture, address);
      final diagnostic = loadedTexture.diagnostic;
      if (diagnostic != null) {
        return <ViewerDiagnostic>[diagnostic];
      }
    }

    _originalMaterials.putIfAbsent(
      address,
      () => _OriginalMaterialState.capture(target.node, target.primitive),
    );

    if (patch.visible != null) {
      target.node.visible = patch.visible!;
    }
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      if (patch.baseColorFactor != null) {
        material.baseColorFactor = _vector4(patch.baseColorFactor!);
      }
      if (loadedTexture != null) {
        material.baseColorTexture = loadedTexture.texture;
      }
      if (patch.metallic != null) {
        material.metallicFactor = patch.metallic!;
      }
      if (patch.roughness != null) {
        material.roughnessFactor = patch.roughness!;
      }
      if (patch.emissiveFactor != null) {
        material.emissiveFactor = _emissiveVector(patch.emissiveFactor!);
      }
    }
    return const <ViewerDiagnostic>[];
  }

  @override
  List<ViewerDiagnostic> collectDiagnostics() => const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address) async {
    final target = _resolveTarget(address);
    if (target == null) {
      return <ViewerDiagnostic>[_primitiveNotFound(address)];
    }
    final original = _originalMaterials.remove(address);
    if (original != null) {
      original.restore(target.node, target.primitive);
    }
    return const <ViewerDiagnostic>[];
  }

  AdapterNodeSnapshot _snapshotNode(flutter_scene.Node node) {
    final primitives = node.mesh?.primitives;
    return AdapterNodeSnapshot(
      name: node.name,
      primitives: <AdapterPrimitiveSnapshot>[
        if (primitives != null)
          for (final primitive in primitives)
            AdapterPrimitiveSnapshot(
              hasTexCoords: _primitiveHasTexCoords(primitive),
            ),
      ],
      children: <AdapterNodeSnapshot>[
        for (final child in node.children) _snapshotNode(child),
      ],
    );
  }

  _ResolvedPrimitive? _resolveTarget(PartAddress address) {
    final root = _rootNode;
    if (root == null || address.nodePath.isEmpty) {
      return null;
    }
    if (root.name != address.nodePath.first) {
      return null;
    }
    var node = root;
    for (final segment in address.nodePath.skip(1)) {
      final matches = <flutter_scene.Node>[
        for (final child in node.children)
          if (child.name == segment) child,
      ];
      if (matches.length != 1) {
        return null;
      }
      node = matches.single;
    }
    final primitives = node.mesh?.primitives;
    if (primitives == null ||
        address.primitiveIndex < 0 ||
        address.primitiveIndex >= primitives.length) {
      return null;
    }
    return _ResolvedPrimitive(node, primitives[address.primitiveIndex]);
  }

  bool _primitiveHasTexCoords(flutter_scene.MeshPrimitive primitive) {
    // ignore: invalid_use_of_internal_member
    final meshData = primitive.geometry.cpuMeshData;
    final vertices = meshData.vertices;
    if (vertices == null || meshData.vertexCount == 0) {
      return false;
    }
    final stride = vertices.lengthInBytes ~/ meshData.vertexCount;
    const texCoordOffset = 6 * 4;
    if (stride < texCoordOffset + 8) {
      return false;
    }
    for (var index = 0; index < meshData.vertexCount; index += 1) {
      final offset = index * stride + texCoordOffset;
      final u = vertices.getFloat32(offset, Endian.little);
      final v = vertices.getFloat32(offset + 4, Endian.little);
      if (u != 0 || v != 0) {
        return true;
      }
    }
    return false;
  }

  bool _requiresPbrMaterial(MaterialPatch patch) =>
      patch.baseColorFactor != null ||
      patch.baseColorTexture != null ||
      patch.metallic != null ||
      patch.roughness != null ||
      patch.emissiveFactor != null;

  Future<_TextureLoadResult> _loadBaseColorTexture(
    TextureSource source,
    PartAddress address,
  ) async {
    try {
      final texture = switch (source) {
        AssetTextureSource(:final assetPath) =>
          await flutter_scene.gpuTextureFromAsset(assetPath),
        BytesTextureSource(:final encodedBytes) =>
          await flutter_scene.gpuTextureFromImage(
              await flutter_scene.imageFromBytes(encodedBytes)),
        NetworkTextureSource(:final uri, :final headers) =>
          await _loadNetworkTexture(uri, headers),
      };
      return _TextureLoadResult(texture: texture);
    } on Object catch (error) {
      return _TextureLoadResult(
        diagnostic: ViewerDiagnostic(
          code: _textureFailureCode(source),
          message: 'Failed to load material texture override.',
          details: <String, Object?>{
            'part': address.debugPath,
            'source': _textureSourceLabel(source),
            'error': error.toString(),
          },
        ),
      );
    }
  }

  Future<Object> _loadNetworkTexture(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Texture request failed with HTTP ${response.statusCode}.');
    }
    final image = await flutter_scene.imageFromBytes(response.bodyBytes);
    return flutter_scene.gpuTextureFromImage(image);
  }

  ViewerDiagnosticCode _textureFailureCode(TextureSource source) {
    return switch (source) {
      AssetTextureSource() => ViewerDiagnosticCode.assetLoadFailure,
      NetworkTextureSource() => ViewerDiagnosticCode.networkFailure,
      BytesTextureSource() => ViewerDiagnosticCode.adapterFailure,
    };
  }

  String _textureSourceLabel(TextureSource source) {
    return switch (source) {
      AssetTextureSource(:final assetPath) => assetPath,
      NetworkTextureSource(:final uri) => uri.toString(),
      BytesTextureSource(:final debugName) => debugName ?? 'bytes',
    };
  }

  ViewerDiagnostic _primitiveNotFound(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.primitiveNotFound,
      message: 'Material override target was not found.',
      details: <String, Object?>{'part': address.debugPath},
    );
  }

  ViewerDiagnostic _missingUv(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.missingUvSet,
      message: 'Texture override requires authored UV coordinates.',
      details: <String, Object?>{'part': address.debugPath, 'uvSet': 0},
    );
  }
}

/// Adapter-owned snapshot of the scene graph fields needed by PartRegistry.
final class AdapterNodeSnapshot {
  AdapterNodeSnapshot({
    required this.name,
    int primitiveCount = 0,
    Iterable<AdapterPrimitiveSnapshot>? primitives,
    Iterable<AdapterNodeSnapshot> children = const <AdapterNodeSnapshot>[],
  })  : assert(primitiveCount >= 0, 'primitiveCount must be non-negative'),
        primitives = List<AdapterPrimitiveSnapshot>.unmodifiable(
          primitives ??
              List<AdapterPrimitiveSnapshot>.filled(
                primitiveCount,
                const AdapterPrimitiveSnapshot(),
              ),
        ),
        children = List<AdapterNodeSnapshot>.unmodifiable(children);

  final String name;
  final List<AdapterPrimitiveSnapshot> primitives;
  final List<AdapterNodeSnapshot> children;

  int get primitiveCount => primitives.length;
}

final class AdapterPrimitiveSnapshot {
  const AdapterPrimitiveSnapshot({this.hasTexCoords = true});

  final bool hasTexCoords;
}

final class _ResolvedPrimitive {
  const _ResolvedPrimitive(this.node, this.primitive);

  final flutter_scene.Node node;
  final flutter_scene.MeshPrimitive primitive;
}

final class _OriginalMaterialState {
  const _OriginalMaterialState({
    required this.visible,
    this.baseColorFactor,
    this.baseColorTexture,
    this.metallic,
    this.roughness,
    this.emissiveFactor,
  });

  factory _OriginalMaterialState.capture(
    flutter_scene.Node node,
    flutter_scene.MeshPrimitive primitive,
  ) {
    final material = primitive.material;
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      return _OriginalMaterialState(
        visible: node.visible,
        baseColorFactor: material.baseColorFactor.clone(),
        // ignore: invalid_use_of_internal_member
        baseColorTexture: material.baseColorTextureSource,
        metallic: material.metallicFactor,
        roughness: material.roughnessFactor,
        emissiveFactor: material.emissiveFactor.clone(),
      );
    }
    return _OriginalMaterialState(visible: node.visible);
  }

  final bool visible;
  final vm.Vector4? baseColorFactor;
  final Object? baseColorTexture;
  final double? metallic;
  final double? roughness;
  final vm.Vector4? emissiveFactor;

  void restore(
    flutter_scene.Node node,
    flutter_scene.MeshPrimitive primitive,
  ) {
    node.visible = visible;
    final material = primitive.material;
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      final baseColorFactor = this.baseColorFactor;
      final baseColorTexture = this.baseColorTexture;
      final metallic = this.metallic;
      final roughness = this.roughness;
      final emissiveFactor = this.emissiveFactor;
      if (baseColorFactor != null) {
        material.baseColorFactor = baseColorFactor.clone();
      }
      material.baseColorTexture = baseColorTexture;
      if (metallic != null) {
        material.metallicFactor = metallic;
      }
      if (roughness != null) {
        material.roughnessFactor = roughness;
      }
      if (emissiveFactor != null) {
        material.emissiveFactor = emissiveFactor.clone();
      }
    }
  }
}

final class _TextureLoadResult {
  const _TextureLoadResult({this.texture, this.diagnostic});

  final Object? texture;
  final ViewerDiagnostic? diagnostic;
}

vm.Vector4 _vector4(List<double> components) {
  return vm.Vector4(
    components[0],
    components[1],
    components[2],
    components[3],
  );
}

vm.Vector4 _emissiveVector(List<double> components) {
  return vm.Vector4(components[0], components[1], components[2], 1);
}

final class FlutterSceneAdapterUnavailableException implements Exception {
  const FlutterSceneAdapterUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
