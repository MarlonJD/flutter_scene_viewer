import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Key, Offset, Size, Widget;
import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';
import '../material_shading_mode.dart';
import '../part_address.dart';
import '../texture_source.dart';
import 'environment_source_loader.dart';
import 'flutter_scene_material_extension_backend.dart';
import 'material_base_family.dart';
import 'normal_map_scaler.dart';
import 'render_surface.dart';

/// Internal boundary for direct `flutter_scene` API calls.
///
/// Keep this file and nearby adapter files as the only place where concrete
/// `flutter_scene` classes leak into implementation details. Public API should
/// stay stable even when `flutter_scene` changes.
abstract interface class FlutterSceneAdapter {
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
  });

  AdapterNodeSnapshot? get nodeSnapshot;

  AdapterRenderScene? get renderScene;

  AdapterModelBounds? get modelBounds;

  AdapterModelStats? get modelStats;

  Future<List<ViewerDiagnostic>> configureEnvironment(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  });

  Future<List<ViewerDiagnostic>> applyMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  );

  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address);

  Future<PartAddress?> pickPart({
    required Offset localPosition,
    required Size viewportSize,
    required RenderCameraFrame camera,
  });

  List<ViewerDiagnostic> collectDiagnostics();
}

/// Runtime adapter backed by the installed `flutter_scene` package.
final class FlutterSceneRuntimeAdapter implements FlutterSceneAdapter {
  FlutterSceneRuntimeAdapter({
    EnvironmentSourceLoader? environmentSourceLoader,
    this.materialExtensionPolicy =
        const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
    FlutterSceneMaterialExtensionBackend? materialExtensionBackend,
  })  : _environmentSourceLoader =
            environmentSourceLoader ?? EnvironmentSourceLoader(),
        _materialExtensionBackend =
            materialExtensionBackend ?? FlutterSceneMaterialExtensionBackend();

  final EnvironmentSourceLoader _environmentSourceLoader;
  final ViewerMaterialExtensionPolicy materialExtensionPolicy;
  final FlutterSceneMaterialExtensionBackend _materialExtensionBackend;
  MaterialExtensionSupport _productionMaterialExtensionSupport =
      MaterialExtensionSupport.unsupported;
  final List<ViewerDiagnostic> _diagnostics = <ViewerDiagnostic>[];
  flutter_scene.Node? _rootNode;
  flutter_scene.Scene? _scene;
  AdapterRenderScene? _renderScene;
  final Map<PartAddress, _OriginalMaterialState> _originalMaterials =
      <PartAddress, _OriginalMaterialState>{};

  flutter_scene.Node? get rootNode => _rootNode;

  flutter_scene.Scene? get debugScene => _scene;

  MaterialExtensionSupport get materialExtensionSupport {
    if (materialExtensionPolicy.mode ==
        ViewerMaterialExtensionMode.productionFlutterSceneShaders) {
      return _productionMaterialExtensionSupport;
    }
    return materialExtensionPolicy.support;
  }

  @override
  AdapterRenderScene? get renderScene => _renderScene;

  @override
  AdapterModelBounds? get modelBounds {
    final rootNode = _rootNode;
    final localBounds = rootNode?.combinedLocalBounds;
    if (rootNode == null || localBounds == null) {
      return null;
    }
    final bounds = vm.Aabb3.copy(localBounds)
      ..transform(rootNode.localTransform);
    final center = bounds.center;
    final radius = (bounds.max - center).length;
    return AdapterModelBounds(
      center: <double>[center.x, center.y, center.z],
      radius: radius,
    );
  }

  @override
  AdapterModelStats? get modelStats {
    final root = _rootNode;
    if (root == null) {
      return null;
    }
    final materials = Set<flutter_scene.Material>.identity();
    var nodeCount = 0;
    var meshCount = 0;
    var primitiveCount = 0;
    void visit(flutter_scene.Node node) {
      nodeCount += 1;
      final primitives = node.mesh?.primitives;
      if (primitives != null) {
        meshCount += 1;
        primitiveCount += primitives.length;
        for (final primitive in primitives) {
          materials.add(primitive.material);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    return AdapterModelStats(
      nodeCount: nodeCount,
      meshCount: meshCount,
      materialCount: materials.length,
      primitiveCount: primitiveCount,
    );
  }

  @override
  AdapterNodeSnapshot? get nodeSnapshot {
    final rootNode = _rootNode;
    if (rootNode == null) {
      return null;
    }
    return _snapshotNode(rootNode);
  }

  @override
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
  }) async {
    final previousScene = _scene;
    if (previousScene != null) {
      _materialExtensionBackend.clear(sceneViews: previousScene.views);
    }
    _diagnostics.clear();
    _productionMaterialExtensionSupport = MaterialExtensionSupport.unsupported;
    if (materialExtensionPolicy.mode ==
        ViewerMaterialExtensionMode.productionFlutterSceneShaders) {
      final preflight =
          await _materialExtensionBackend.preflightProductionSupport();
      _productionMaterialExtensionSupport = preflight.support;
      _diagnostics.addAll(preflight.diagnostics);
    }
    await flutter_scene.loadBaseShaderLibrary();
    await flutter_scene.Material.initializeStaticResources();
    final rootNode = await flutter_scene.Node.fromGlbBytes(bytes);
    _applyMaterialShadingPolicy(rootNode, materialShadingPolicy);
    await flutter_scene.Scene.initializeStaticResources();
    final scene = flutter_scene.Scene()..root.add(rootNode);
    _rootNode = rootNode;
    _scene = scene;
    _renderScene = _FlutterSceneRenderScene(
      scene,
      materialExtensionBackend: _materialExtensionBackend,
    );
    _originalMaterials.clear();
  }

  @override
  Future<List<ViewerDiagnostic>> configureEnvironment(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    final scene = _scene;
    if (scene == null) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.adapterFailure,
          message: 'Cannot configure environment before a scene is loaded.',
          details: <String, Object?>{'kind': frame.kind.name},
        ),
      ];
    }

    final flutter_scene.EnvironmentMap? environment;
    try {
      environment = await _environmentMapFor(frame, isCanceled: isCanceled);
    } on _EnvironmentConfigurationException catch (error) {
      return <ViewerDiagnostic>[error.diagnostic];
    } on Object catch (error) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: frame.kind == RenderEnvironmentKind.asset
              ? ViewerDiagnosticCode.assetLoadFailure
              : ViewerDiagnosticCode.adapterFailure,
          message: 'Failed to configure viewer environment.',
          details: <String, Object?>{
            'kind': frame.kind.name,
            if (frame.assetPath != null) 'assetPath': frame.assetPath,
            'error': error.toString(),
          },
        ),
      ];
    }
    if (environment == null || (isCanceled?.call() ?? false)) {
      return const <ViewerDiagnostic>[];
    }

    scene
      ..skyEnvironment = null
      ..environment = environment
      ..environmentIntensity = frame.intensity
      ..environmentTransform = vm.Matrix3.rotationY(frame.rotationRadians)
      ..skybox = frame.showSkybox
          ? flutter_scene.Skybox(
              flutter_scene.EnvironmentSkySource(
                blurriness: frame.skyboxBlur,
              ),
            )
          : null;
    return const <ViewerDiagnostic>[];
  }

  Future<flutter_scene.EnvironmentMap?> _environmentMapFor(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    return switch (frame.kind) {
      RenderEnvironmentKind.studio =>
        Future<flutter_scene.EnvironmentMap>.value(
          flutter_scene.EnvironmentMap.studio(),
        ),
      RenderEnvironmentKind.empty => Future<flutter_scene.EnvironmentMap>.value(
          flutter_scene.EnvironmentMap.empty(),
        ),
      RenderEnvironmentKind.asset => flutter_scene.EnvironmentMap.fromAssets(
          radianceImagePath: frame.assetPath ??
              (throw ArgumentError('Asset environment requires assetPath.')),
        ),
      RenderEnvironmentKind.rawAsset ||
      RenderEnvironmentKind.rawBytes ||
      RenderEnvironmentKind.polyHaven =>
        await _decodedEnvironmentMapFor(frame, isCanceled: isCanceled),
    };
  }

  Future<flutter_scene.EnvironmentMap?> _decodedEnvironmentMapFor(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    final result = await _environmentSourceLoader.load(
      frame,
      isCanceled: isCanceled,
    );
    if (result.isCanceled || (isCanceled?.call() ?? false)) {
      return null;
    }
    final diagnostic = result.diagnostic;
    if (diagnostic != null) {
      throw _EnvironmentConfigurationException(diagnostic);
    }
    final decoded = result.decoded;
    if (decoded == null) {
      throw _EnvironmentConfigurationException(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentDecodeFailure,
          message: 'Decoded environment pixels were not available.',
          details: <String, Object?>{'kind': frame.kind.name},
        ),
      );
    }
    return flutter_scene.EnvironmentMap.fromEquirectHdr(
      linearPixels: decoded.linearPixels,
      width: decoded.width,
      height: decoded.height,
    );
  }

  void _applyMaterialShadingPolicy(
    flutter_scene.Node node,
    MaterialShadingPolicy policy,
  ) {
    if (policy == MaterialShadingPolicy.authored) {
      return;
    }
    final primitives = node.mesh?.primitives;
    if (primitives != null) {
      for (final primitive in primitives) {
        primitive.material = switch (policy) {
          MaterialShadingPolicy.forceLit => _litMaterialFor(primitive.material),
          MaterialShadingPolicy.forceUnlit =>
            _unlitMaterialFor(primitive.material),
          MaterialShadingPolicy.authored => primitive.material,
        };
      }
    }
    for (final child in node.children) {
      _applyMaterialShadingPolicy(child, policy);
    }
  }

  flutter_scene.Material _litMaterialFor(flutter_scene.Material material) {
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      return material;
    }
    if (material is flutter_scene.UnlitMaterial) {
      final lit = flutter_scene.PhysicallyBasedMaterial();
      lit
        ..baseColorFactor = material.baseColorFactor.clone()
        // ignore: invalid_use_of_internal_member
        ..baseColorTexture = material.baseColorTextureSource
        ..metallicFactor = 0.0
        ..roughnessFactor = 1.0
        ..alphaMode = _pbrAlphaModeForUnlit(material.alphaMode);
      return lit;
    }
    return material;
  }

  flutter_scene.Material _unlitMaterialFor(flutter_scene.Material material) {
    if (material is flutter_scene.UnlitMaterial) {
      return material;
    }
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      final unlit = flutter_scene.UnlitMaterial();
      unlit
        ..baseColorFactor = material.baseColorFactor.clone()
        // ignore: invalid_use_of_internal_member
        ..baseColorTexture = material.baseColorTextureSource
        ..alphaMode = _unlitAlphaModeForPbr(material.alphaMode);
      return unlit;
    }
    return material;
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

    final unsupportedDiagnostics = <ViewerDiagnostic>[
      if (patch.hasGlassOverride && patch.hasClearcoatOverride)
        _unsupportedCombinedGlassClearcoatMaterial(address)
      else ...<ViewerDiagnostic>[
        if (patch.hasGlassOverride &&
            !_usesMaterialExtensionBackendFor(
              materialExtensionPolicy,
              patch,
              support: materialExtensionSupport,
            ))
          _unsupportedGlassMaterial(address),
        if (patch.hasClearcoatOverride &&
            !_usesMaterialExtensionBackendFor(
              materialExtensionPolicy,
              patch,
              support: materialExtensionSupport,
            ))
          _unsupportedClearcoatMaterial(address),
      ],
    ];
    if (unsupportedDiagnostics.isNotEmpty) {
      return unsupportedDiagnostics;
    }
    final isolationDiagnostic = patch.hasGlassOverride
        ? _glassNodeIsolationDiagnostic(
            address: address,
            primitiveCount: target.node.mesh?.primitives.length ?? 0,
            selectedPrimitiveIndex: address.primitiveIndex,
          )
        : null;
    if (isolationDiagnostic != null) {
      return <ViewerDiagnostic>[isolationDiagnostic];
    }
    if (patch.hasTextureOverride && !_primitiveHasTexCoord0(target.primitive)) {
      return <ViewerDiagnostic>[_missingUv(address)];
    }
    if (patch.effectMask != null) {
      return <ViewerDiagnostic>[_unsupportedEffectMask(address)];
    }
    if (patch.normalScale != null && patch.normalTexture == null) {
      return <ViewerDiagnostic>[_normalScaleRequiresTexture(address)];
    }

    final family = resolveMaterialBaseFamily(patch);
    var material = target.primitive.material;
    if (family == MaterialBaseFamily.maskedCutout &&
        material is flutter_scene.UnlitMaterial) {
      return <ViewerDiagnostic>[_unsupportedUnlitAlphaMask(address)];
    }
    if (_requiresPbrMaterial(patch, family) &&
        material is! flutter_scene.PhysicallyBasedMaterial) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Material override requires a PBR material.',
          details: <String, Object?>{'part': address.debugPath},
        ),
      ];
    }
    if (_requiresKnownAlphaMaterial(patch) &&
        material is! flutter_scene.PhysicallyBasedMaterial &&
        material is! flutter_scene.UnlitMaterial) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Alpha material override requires a known material type.',
          details: <String, Object?>{'part': address.debugPath},
        ),
      ];
    }

    final loadedBaseColorTexture = await _loadTextureOverride(
      patch.baseColorTexture,
      address,
    );
    final loadedMetallicRoughnessTexture = await _loadTextureOverride(
      patch.metallicRoughnessTexture,
      address,
    );
    final loadedNormalTexture = await _loadTextureOverride(
      patch.normalTexture,
      address,
      normalMapScale: patch.normalScale,
    );
    final loadedEmissiveTexture = await _loadTextureOverride(
      patch.emissiveTexture,
      address,
    );
    final loadedOcclusionTexture = await _loadTextureOverride(
      patch.occlusionTexture,
      address,
    );
    final loadedTransmissionTexture = await _loadTextureOverride(
      patch.transmissionTexture,
      address,
    );
    final loadedThicknessTexture = await _loadTextureOverride(
      patch.thicknessTexture,
      address,
    );
    final loadedClearcoatTexture = await _loadTextureOverride(
      patch.clearcoatTexture,
      address,
    );
    final loadedClearcoatRoughnessTexture = await _loadTextureOverride(
      patch.clearcoatRoughnessTexture,
      address,
    );
    final loadedClearcoatNormalTexture = await _loadTextureOverride(
      patch.clearcoatNormalTexture,
      address,
    );
    for (final loadedTexture in <_TextureLoadResult?>[
      loadedBaseColorTexture,
      loadedMetallicRoughnessTexture,
      loadedNormalTexture,
      loadedEmissiveTexture,
      loadedOcclusionTexture,
      loadedTransmissionTexture,
      loadedThicknessTexture,
      loadedClearcoatTexture,
      loadedClearcoatRoughnessTexture,
      loadedClearcoatNormalTexture,
    ]) {
      final diagnostic = loadedTexture?.diagnostic;
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
    if (patch.hasGlassOverride) {
      if (material is! flutter_scene.PhysicallyBasedMaterial) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedMaterialFeature,
            message: 'Transmission/glass overrides require a PBR material.',
            details: <String, Object?>{'part': address.debugPath},
          ),
        ];
      }
      final scene = _scene;
      if (scene == null) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.adapterFailure,
            message:
                'Cannot apply transmission/glass before a scene is loaded.',
            details: <String, Object?>{'part': address.debugPath},
          ),
        ];
      }
      return _materialExtensionBackend.applyTransmissionPatch(
        sceneViews: scene.views,
        node: target.node,
        primitive: target.primitive,
        address: address,
        patch: patch,
        baseColorTexture: loadedBaseColorTexture?.texture,
        normalTexture: loadedNormalTexture?.texture,
        transmissionTexture: loadedTransmissionTexture?.texture,
        thicknessTexture: loadedThicknessTexture?.texture,
      );
    }
    if (patch.hasClearcoatOverride) {
      if (material is! flutter_scene.PhysicallyBasedMaterial) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedMaterialFeature,
            message: 'Clearcoat overrides require a PBR material.',
            details: <String, Object?>{'part': address.debugPath},
          ),
        ];
      }
      return _materialExtensionBackend.applyClearcoatPatch(
        node: target.node,
        primitive: target.primitive,
        address: address,
        patch: patch,
        baseColorTexture: loadedBaseColorTexture?.texture,
        metallicRoughnessTexture: loadedMetallicRoughnessTexture?.texture,
        normalTexture: loadedNormalTexture?.texture,
        clearcoatTexture: loadedClearcoatTexture?.texture,
        clearcoatRoughnessTexture: loadedClearcoatRoughnessTexture?.texture,
        clearcoatNormalTexture: loadedClearcoatNormalTexture?.texture,
      );
    }
    if (material is flutter_scene.PhysicallyBasedMaterial &&
        _requiresPbrFamilyReplacement(family, patch)) {
      material = _copyPbrMaterial(material);
      target.primitive.material = material;
    }
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      if (patch.baseColorFactor != null) {
        material.baseColorFactor = _vector4(patch.baseColorFactor!);
      }
      if (loadedBaseColorTexture != null) {
        material.baseColorTexture = loadedBaseColorTexture.texture;
      }
      if (loadedMetallicRoughnessTexture != null) {
        material.metallicRoughnessTexture =
            loadedMetallicRoughnessTexture.texture;
      }
      if (loadedNormalTexture != null) {
        material.normalTexture = loadedNormalTexture.texture;
      }
      if (patch.normalTexture != null && patch.normalScale != null) {
        material.normalScale = 1.0;
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
      if (loadedEmissiveTexture != null) {
        material.emissiveTexture = loadedEmissiveTexture.texture;
      }
      if (loadedOcclusionTexture != null) {
        material.occlusionTexture = loadedOcclusionTexture.texture;
      }
      if (patch.occlusionStrength != null) {
        material.occlusionStrength = patch.occlusionStrength!;
      }
      if (patch.alphaMode != null) {
        material.alphaMode = _alphaMode(patch.alphaMode!);
      }
      if (patch.alphaCutoff != null) {
        material.alphaCutoff = patch.alphaCutoff!;
      }
    } else if (material is flutter_scene.UnlitMaterial) {
      if (patch.alphaMode != null) {
        material.alphaMode = _alphaMode(patch.alphaMode!);
      }
    }
    return const <ViewerDiagnostic>[];
  }

  @override
  List<ViewerDiagnostic> collectDiagnostics() =>
      List<ViewerDiagnostic>.unmodifiable(_diagnostics);

  @override
  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address) async {
    final target = _resolveTarget(address);
    if (target == null) {
      return <ViewerDiagnostic>[_primitiveNotFound(address)];
    }
    final original = _originalMaterials.remove(address);
    final scene = _scene;
    if (scene != null) {
      _materialExtensionBackend.resetTransmissionPatch(
        sceneViews: scene.views,
        node: target.node,
        primitive: target.primitive,
      );
    }
    _materialExtensionBackend.resetClearcoatPatch(
      node: target.node,
      primitive: target.primitive,
    );
    if (original != null) {
      original.restore(target.node, target.primitive);
    }
    return const <ViewerDiagnostic>[];
  }

  @override
  Future<PartAddress?> pickPart({
    required Offset localPosition,
    required Size viewportSize,
    required RenderCameraFrame camera,
  }) async {
    final scene = _scene;
    if (scene == null ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        !viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        !localPosition.dx.isFinite ||
        !localPosition.dy.isFinite) {
      return null;
    }

    final perspectiveCamera = flutter_scene.PerspectiveCamera(
      position: _vector3(camera.position),
      target: _vector3(camera.target),
      up: _vector3(camera.up),
      fovRadiansY: camera.verticalFovRadians,
      fovNear: camera.near,
      fovFar: camera.far,
    );
    final hit = scene.raycast(
      perspectiveCamera.screenPointToRay(localPosition, viewportSize),
    );
    if (hit == null || hit.primitiveIndex < 0) {
      return null;
    }
    final nodePath = _nodePathFor(hit.node);
    if (nodePath == null) {
      return null;
    }
    final primitives = hit.node.mesh?.primitives;
    if (primitives == null || hit.primitiveIndex >= primitives.length) {
      return null;
    }
    return PartAddress(
      nodePath: nodePath,
      primitiveIndex: hit.primitiveIndex,
    );
  }

  AdapterNodeSnapshot _snapshotNode(flutter_scene.Node node) {
    final primitives = node.mesh?.primitives;
    return AdapterNodeSnapshot(
      name: node.name,
      primitives: <AdapterPrimitiveSnapshot>[
        if (primitives != null)
          for (final primitive in primitives)
            AdapterPrimitiveSnapshot(
              materialShadingMode: _primitiveMaterialShadingMode(primitive),
              textureCoordinateChannels:
                  _primitiveTextureCoordinateChannels(primitive),
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

  List<String>? _nodePathFor(flutter_scene.Node target) {
    final root = _rootNode;
    if (root == null) {
      return null;
    }

    List<String>? visit(flutter_scene.Node node, List<String> parentPath) {
      final path = List<String>.unmodifiable(<String>[
        ...parentPath,
        node.name,
      ]);
      if (identical(node, target)) {
        return path;
      }
      for (final child in node.children) {
        final childPath = visit(child, path);
        if (childPath != null) {
          return childPath;
        }
      }
      return null;
    }

    return visit(root, const <String>[]);
  }

  List<int> _primitiveTextureCoordinateChannels(
    flutter_scene.MeshPrimitive primitive,
  ) {
    return _primitiveHasTexCoord0(primitive) ? const <int>[0] : const <int>[];
  }

  MaterialShadingMode _primitiveMaterialShadingMode(
    flutter_scene.MeshPrimitive primitive,
  ) {
    final material = primitive.material;
    return switch (material) {
      flutter_scene.PhysicallyBasedMaterial() => MaterialShadingMode.lit,
      flutter_scene.UnlitMaterial() => MaterialShadingMode.unlit,
      _ => MaterialShadingMode.unknown,
    };
  }

  bool _primitiveHasTexCoord0(flutter_scene.MeshPrimitive primitive) {
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

  bool _requiresPbrMaterial(
    MaterialPatch patch,
    MaterialBaseFamily family,
  ) =>
      patch.baseColorFactor != null ||
      patch.hasTextureOverride ||
      patch.normalScale != null ||
      patch.metallic != null ||
      patch.roughness != null ||
      patch.emissiveFactor != null ||
      patch.occlusionStrength != null ||
      patch.alphaCutoff != null ||
      family == MaterialBaseFamily.maskedCutout;

  bool _requiresKnownAlphaMaterial(MaterialPatch patch) =>
      patch.alphaMode != null || patch.alphaCutoff != null;

  flutter_scene.PhysicallyBasedMaterial _copyPbrMaterial(
    flutter_scene.PhysicallyBasedMaterial source,
  ) {
    final material = flutter_scene.PhysicallyBasedMaterial();
    material
      ..baseColorFactor = source.baseColorFactor.clone()
      // ignore: invalid_use_of_internal_member
      ..baseColorTexture = source.baseColorTextureSource
      // ignore: invalid_use_of_internal_member
      ..metallicRoughnessTexture = source.metallicRoughnessTextureSource
      // ignore: invalid_use_of_internal_member
      ..normalTexture = source.normalTextureSource
      ..normalScale = source.normalScale
      ..metallicFactor = source.metallicFactor
      ..roughnessFactor = source.roughnessFactor
      ..emissiveFactor = source.emissiveFactor.clone()
      // ignore: invalid_use_of_internal_member
      ..emissiveTexture = source.emissiveTextureSource
      // ignore: invalid_use_of_internal_member
      ..occlusionTexture = source.occlusionTextureSource
      ..occlusionStrength = source.occlusionStrength
      ..environment = source.environment
      ..alphaMode = source.alphaMode
      ..alphaCutoff = source.alphaCutoff
      ..vertexColorWeight = source.vertexColorWeight
      ..doubleSided = source.doubleSided;
    return material;
  }

  Future<_TextureLoadResult?> _loadTextureOverride(
      TextureSource? source, PartAddress address,
      {double? normalMapScale}) async {
    if (source == null) {
      return null;
    }
    try {
      final texture = normalMapScale == null || normalMapScale == 1
          ? await _loadTexture(source)
          : await _loadScaledNormalTexture(source, normalMapScale);
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

  Future<Object> _loadTexture(TextureSource source) async {
    return switch (source) {
      AssetTextureSource(:final assetPath) =>
        await flutter_scene.gpuTextureFromAsset(assetPath),
      BytesTextureSource(:final encodedBytes) =>
        await flutter_scene.gpuTextureFromImage(
            await flutter_scene.imageFromBytes(encodedBytes)),
      NetworkTextureSource(:final uri, :final headers) =>
        await _loadNetworkTexture(uri, headers),
    };
  }

  Future<Object> _loadScaledNormalTexture(
    TextureSource source,
    double scale,
  ) async {
    final encodedBytes = await _loadEncodedTextureBytes(source);
    final image = await flutter_scene.imageFromBytes(encodedBytes);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Unable to read normal texture pixels.');
    }
    final rgba = Uint8List.fromList(
      byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    );
    final scaled = scaleNormalMapRgba(rgba, scale);
    final scaledImage = await _imageFromRgba(
      scaled,
      image.width,
      image.height,
    );
    return flutter_scene.gpuTextureFromImage(scaledImage);
  }

  Future<Uint8List> _loadEncodedTextureBytes(TextureSource source) async {
    return switch (source) {
      AssetTextureSource(:final assetPath) =>
        Uint8List.sublistView(await rootBundle.load(assetPath)),
      BytesTextureSource(:final encodedBytes) => encodedBytes,
      NetworkTextureSource(:final uri, :final headers) =>
        await _loadNetworkTextureBytes(uri, headers),
    };
  }

  Future<ui.Image> _imageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<Object> _loadNetworkTexture(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final bodyBytes = await _loadNetworkTextureBytes(uri, headers);
    final image = await flutter_scene.imageFromBytes(bodyBytes);
    return flutter_scene.gpuTextureFromImage(image);
  }

  Future<Uint8List> _loadNetworkTextureBytes(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final response = await http.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Texture request failed with HTTP ${response.statusCode}.');
    }
    return response.bodyBytes;
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

  ViewerDiagnostic _normalScaleRequiresTexture(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Normal intensity override currently requires a normal texture override.',
      details: <String, Object?>{'part': address.debugPath},
    );
  }

  ViewerDiagnostic _unsupportedUnlitAlphaMask(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Alpha mask overrides require a lit PBR material because the installed flutter_scene unlit material treats mask like blend.',
      details: <String, Object?>{
        'part': address.debugPath,
        'alphaMode': MaterialAlphaMode.mask.name,
        'materialShadingMode': MaterialShadingMode.unlit.name,
        'upstreamPackage': 'flutter_scene',
      },
    );
  }

  ViewerDiagnostic _unsupportedEffectMask(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Material effect masks require an opaque-family shader backend before they can affect rendering.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'effectMask',
        'requiredFamily': 'opaque',
        'status': 'unsupported',
      },
    );
  }

  ViewerDiagnostic _unsupportedGlassMaterial(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Transmission/glass material overrides require flutter_scene support for transmission, IOR, and volume attenuation.',
      details: <String, Object?>{
        'part': address.debugPath,
        'extensions': const <String>[
          'KHR_materials_transmission',
          'KHR_materials_ior',
          'KHR_materials_volume',
        ],
        'upstreamPackage': 'flutter_scene',
        'status': 'unsupported',
      },
    );
  }

  ViewerDiagnostic _unsupportedClearcoatMaterial(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Clearcoat material overrides require flutter_scene support for KHR_materials_clearcoat.',
      details: <String, Object?>{
        'part': address.debugPath,
        'extensions': const <String>['KHR_materials_clearcoat'],
        'upstreamPackage': 'flutter_scene',
        'status': 'unsupported',
      },
    );
  }

  ViewerDiagnostic _unsupportedCombinedGlassClearcoatMaterial(
    PartAddress address,
  ) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Combining transmission/glass and clearcoat requires a combined experimental shader backend.',
      details: <String, Object?>{
        'part': address.debugPath,
        'extensions': const <String>[
          'KHR_materials_transmission',
          'KHR_materials_clearcoat',
        ],
        'upstreamPackage': 'flutter_scene',
        'status': 'unsupported',
      },
    );
  }
}

ViewerDiagnostic? _glassNodeIsolationDiagnostic({
  PartAddress? address,
  required int primitiveCount,
  required int selectedPrimitiveIndex,
}) {
  if (primitiveCount <= 1) {
    return null;
  }
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedMaterialFeature,
    message:
        'Production glass requires glass primitives to be isolated on separate nodes.',
    details: <String, Object?>{
      if (address != null) 'part': address.debugPath,
      'limitation': 'nodeLayerIsolation',
      'primitiveCount': primitiveCount,
      'primitiveIndex': selectedPrimitiveIndex,
      'authoring': 'separateGlassNode',
    },
  );
}

final class _FlutterSceneRenderScene implements AdapterRenderScene {
  const _FlutterSceneRenderScene(
    this.scene, {
    required this.materialExtensionBackend,
  });

  final flutter_scene.Scene scene;
  final FlutterSceneMaterialExtensionBackend materialExtensionBackend;

  @override
  Widget buildView({
    Key? key,
    required RenderCameraFrame camera,
    required RenderLightingFrame lighting,
    required RenderEnvironmentFrame environment,
    required Size? viewportSize,
    required double devicePixelRatio,
    required bool autoTick,
  }) {
    if (viewportSize != null) {
      materialExtensionBackend.updateViewport(
        width: viewportSize.width,
        height: viewportSize.height,
        pixelRatio: devicePixelRatio,
      );
    }
    materialExtensionBackend.updateCamera(camera);
    _applyLighting(lighting);
    return flutter_scene.SceneView(
      scene,
      key: key,
      camera: flutter_scene.PerspectiveCamera(
        position: _vector3(camera.position),
        target: _vector3(camera.target),
        up: _vector3(camera.up),
        fovRadiansY: camera.verticalFovRadians,
        fovNear: camera.near,
        fovFar: camera.far,
      ),
      autoTick: autoTick,
    );
  }

  void _applyLighting(RenderLightingFrame lighting) {
    scene.exposure = lighting.exposure;
    scene.ambientOcclusion.enabled = lighting.ambientOcclusionEnabled;
    switch (lighting.kind) {
      case RenderLightingKind.studio:
        scene.environmentIntensity = lighting.environmentIntensity;
        var light = scene.directionalLight;
        if (light == null) {
          light = flutter_scene.DirectionalLight();
          scene.directionalLight = light;
        }
        light
          ..direction = _vector3(lighting.keyLightDirection)
          ..color = _vector3(lighting.keyLightColor)
          ..intensity = lighting.keyLightIntensity
          ..castsShadow = lighting.keyLightCastsShadow
          ..shadowMapResolution = lighting.keyLightShadowMapResolution
          ..shadowMaxDistance = lighting.keyLightShadowMaxDistance
          ..shadowSoftness = lighting.keyLightShadowSoftness
          ..shadowFadeRange = lighting.keyLightShadowFadeRange
          ..shadowDepthBias = lighting.keyLightShadowDepthBias
          ..shadowNormalBias = lighting.keyLightShadowNormalBias
          ..shadowCascadeCount = lighting.keyLightShadowCascadeCount
          ..shadowCascadeSplitLambda =
              lighting.keyLightShadowCascadeSplitLambda;
      case RenderLightingKind.none:
        scene.environmentIntensity = 0.0;
        scene.directionalLight = null;
    }
  }
}

/// Adapter-owned model counters used as debug evidence when known.
final class AdapterModelStats {
  const AdapterModelStats({
    this.nodeCount,
    this.meshCount,
    this.materialCount,
    this.primitiveCount,
  });

  final int? nodeCount;
  final int? meshCount;
  final int? materialCount;
  final int? primitiveCount;
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
  const AdapterPrimitiveSnapshot({
    bool hasTexCoords = true,
    List<int>? textureCoordinateChannels,
    this.materialShadingMode = MaterialShadingMode.lit,
  }) : textureCoordinateChannels = textureCoordinateChannels ??
            (hasTexCoords ? const <int>[0] : const <int>[]);

  final List<int> textureCoordinateChannels;
  final MaterialShadingMode materialShadingMode;

  bool get hasTexCoords => textureCoordinateChannels.contains(0);
}

final class _ResolvedPrimitive {
  const _ResolvedPrimitive(this.node, this.primitive);

  final flutter_scene.Node node;
  final flutter_scene.MeshPrimitive primitive;
}

final class _OriginalMaterialState {
  const _OriginalMaterialState({
    required this.visible,
    required this.layers,
    required this.material,
    this.baseColorFactor,
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.normalScale,
    this.metallic,
    this.roughness,
    this.emissiveFactor,
    this.emissiveTexture,
    this.occlusionTexture,
    this.occlusionStrength,
    this.alphaMode,
    this.alphaCutoff,
    this.unlitBaseColorFactor,
    this.unlitBaseColorTexture,
    this.unlitAlphaMode,
  });

  factory _OriginalMaterialState.capture(
    flutter_scene.Node node,
    flutter_scene.MeshPrimitive primitive,
  ) {
    final material = primitive.material;
    if (material is flutter_scene.PhysicallyBasedMaterial) {
      return _OriginalMaterialState(
        visible: node.visible,
        layers: node.layers,
        material: material,
        baseColorFactor: material.baseColorFactor.clone(),
        // ignore: invalid_use_of_internal_member
        baseColorTexture: material.baseColorTextureSource,
        // ignore: invalid_use_of_internal_member
        metallicRoughnessTexture: material.metallicRoughnessTextureSource,
        // ignore: invalid_use_of_internal_member
        normalTexture: material.normalTextureSource,
        normalScale: material.normalScale,
        metallic: material.metallicFactor,
        roughness: material.roughnessFactor,
        emissiveFactor: material.emissiveFactor.clone(),
        // ignore: invalid_use_of_internal_member
        emissiveTexture: material.emissiveTextureSource,
        // ignore: invalid_use_of_internal_member
        occlusionTexture: material.occlusionTextureSource,
        occlusionStrength: material.occlusionStrength,
        alphaMode: material.alphaMode,
        alphaCutoff: material.alphaCutoff,
      );
    }
    if (material is flutter_scene.UnlitMaterial) {
      return _OriginalMaterialState(
        visible: node.visible,
        layers: node.layers,
        material: material,
        unlitBaseColorFactor: material.baseColorFactor.clone(),
        // ignore: invalid_use_of_internal_member
        unlitBaseColorTexture: material.baseColorTextureSource,
        unlitAlphaMode: material.alphaMode,
      );
    }
    return _OriginalMaterialState(
      visible: node.visible,
      layers: node.layers,
      material: material,
    );
  }

  final bool visible;
  final int layers;
  final flutter_scene.Material material;
  final vm.Vector4? baseColorFactor;
  final Object? baseColorTexture;
  final Object? metallicRoughnessTexture;
  final Object? normalTexture;
  final double? normalScale;
  final double? metallic;
  final double? roughness;
  final vm.Vector4? emissiveFactor;
  final Object? emissiveTexture;
  final Object? occlusionTexture;
  final double? occlusionStrength;
  final flutter_scene.AlphaMode? alphaMode;
  final double? alphaCutoff;
  final vm.Vector4? unlitBaseColorFactor;
  final Object? unlitBaseColorTexture;
  final flutter_scene.AlphaMode? unlitAlphaMode;

  void restore(
    flutter_scene.Node node,
    flutter_scene.MeshPrimitive primitive,
  ) {
    node.visible = visible;
    node.layers = layers;
    primitive.material = material;
    final restoredMaterial = primitive.material;
    if (restoredMaterial is flutter_scene.PhysicallyBasedMaterial) {
      final baseColorFactor = this.baseColorFactor;
      final baseColorTexture = this.baseColorTexture;
      final normalScale = this.normalScale;
      final metallic = this.metallic;
      final roughness = this.roughness;
      final emissiveFactor = this.emissiveFactor;
      final occlusionStrength = this.occlusionStrength;
      final alphaMode = this.alphaMode;
      final alphaCutoff = this.alphaCutoff;
      if (baseColorFactor != null) {
        restoredMaterial.baseColorFactor = baseColorFactor.clone();
      }
      restoredMaterial.baseColorTexture = baseColorTexture;
      restoredMaterial.metallicRoughnessTexture = metallicRoughnessTexture;
      restoredMaterial.normalTexture = normalTexture;
      if (normalScale != null) {
        restoredMaterial.normalScale = normalScale;
      }
      if (metallic != null) {
        restoredMaterial.metallicFactor = metallic;
      }
      if (roughness != null) {
        restoredMaterial.roughnessFactor = roughness;
      }
      if (emissiveFactor != null) {
        restoredMaterial.emissiveFactor = emissiveFactor.clone();
      }
      restoredMaterial.emissiveTexture = emissiveTexture;
      restoredMaterial.occlusionTexture = occlusionTexture;
      if (occlusionStrength != null) {
        restoredMaterial.occlusionStrength = occlusionStrength;
      }
      if (alphaMode != null) {
        restoredMaterial.alphaMode = alphaMode;
      }
      if (alphaCutoff != null) {
        restoredMaterial.alphaCutoff = alphaCutoff;
      }
    } else if (restoredMaterial is flutter_scene.UnlitMaterial) {
      final baseColorFactor = unlitBaseColorFactor;
      final alphaMode = unlitAlphaMode;
      if (baseColorFactor != null) {
        restoredMaterial.baseColorFactor = baseColorFactor.clone();
      }
      restoredMaterial.baseColorTexture = unlitBaseColorTexture;
      if (alphaMode != null) {
        restoredMaterial.alphaMode = alphaMode;
      }
    }
  }
}

final class _TextureLoadResult {
  const _TextureLoadResult({this.texture, this.diagnostic});

  final Object? texture;
  final ViewerDiagnostic? diagnostic;
}

final class _EnvironmentConfigurationException implements Exception {
  const _EnvironmentConfigurationException(this.diagnostic);

  final ViewerDiagnostic diagnostic;
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

vm.Vector3 _vector3(List<double> components) {
  return vm.Vector3(components[0], components[1], components[2]);
}

flutter_scene.AlphaMode _pbrAlphaModeForUnlit(
  flutter_scene.AlphaMode alphaMode,
) {
  return switch (alphaMode) {
    flutter_scene.AlphaMode.blend => flutter_scene.AlphaMode.blend,
    flutter_scene.AlphaMode.mask => flutter_scene.AlphaMode.mask,
    flutter_scene.AlphaMode.opaque => flutter_scene.AlphaMode.opaque,
  };
}

flutter_scene.AlphaMode _unlitAlphaModeForPbr(
  flutter_scene.AlphaMode alphaMode,
) {
  return switch (alphaMode) {
    flutter_scene.AlphaMode.blend => flutter_scene.AlphaMode.blend,
    flutter_scene.AlphaMode.mask => flutter_scene.AlphaMode.opaque,
    flutter_scene.AlphaMode.opaque => flutter_scene.AlphaMode.opaque,
  };
}

flutter_scene.AlphaMode _alphaMode(MaterialAlphaMode alphaMode) {
  return switch (alphaMode) {
    MaterialAlphaMode.opaque => flutter_scene.AlphaMode.opaque,
    MaterialAlphaMode.mask => flutter_scene.AlphaMode.mask,
    MaterialAlphaMode.blend => flutter_scene.AlphaMode.blend,
  };
}

bool _requiresPbrFamilyReplacement(
  MaterialBaseFamily family,
  MaterialPatch patch,
) =>
    family == MaterialBaseFamily.maskedCutout ||
    family == MaterialBaseFamily.translucentBlend ||
    patch.alphaMode == MaterialAlphaMode.opaque;

bool _usesMaterialExtensionBackendFor(
  ViewerMaterialExtensionPolicy policy,
  MaterialPatch patch, {
  MaterialExtensionSupport? support,
}) {
  if (patch.hasGlassOverride && patch.hasClearcoatOverride) {
    return false;
  }
  final resolvedSupport = support ?? policy.support;
  if (policy.mode ==
          ViewerMaterialExtensionMode.productionFlutterSceneShaders &&
      !resolvedSupport.productionReady) {
    return false;
  }
  if (patch.hasClearcoatOverride) {
    return resolvedSupport.clearcoat;
  }
  if (!patch.hasGlassOverride) {
    return false;
  }
  return ((patch.transmission == null && patch.transmissionTexture == null) ||
          resolvedSupport.transmission) &&
      (patch.ior == null || resolvedSupport.ior) &&
      ((patch.thickness == null &&
              patch.thicknessTexture == null &&
              patch.attenuationColor == null &&
              patch.attenuationDistance == null) ||
          resolvedSupport.volume);
}

@visibleForTesting
flutter_scene.AlphaMode debugFlutterSceneAlphaModeFor(
  MaterialAlphaMode alphaMode,
) =>
    _alphaMode(alphaMode);

@visibleForTesting
bool debugRequiresPbrFamilyReplacement(MaterialPatch patch) =>
    _requiresPbrFamilyReplacement(resolveMaterialBaseFamily(patch), patch);

@visibleForTesting
bool debugUsesMaterialExtensionBackendFor(
  ViewerMaterialExtensionPolicy policy,
  MaterialPatch patch, {
  MaterialExtensionSupport? support,
}) =>
    _usesMaterialExtensionBackendFor(policy, patch, support: support);

@visibleForTesting
ViewerDiagnostic? debugGlassNodeIsolationDiagnostic({
  required int primitiveCount,
  required int selectedPrimitiveIndex,
}) =>
    _glassNodeIsolationDiagnostic(
      primitiveCount: primitiveCount,
      selectedPrimitiveIndex: selectedPrimitiveIndex,
    );

final class FlutterSceneAdapterUnavailableException implements Exception {
  const FlutterSceneAdapterUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
