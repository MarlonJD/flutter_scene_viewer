import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';
import '../part_address.dart';
import 'render_surface.dart';

typedef CreateTransmissionMaterial = Future<flutter_scene.ShaderMaterial>
    Function(FlutterSceneTransmissionMaterialConfig config);

typedef CreateClearcoatMaterial = Future<flutter_scene.Material> Function(
    FlutterSceneClearcoatMaterialConfig config);

typedef LoadMaterialExtensionShaderLibrary
    = Future<MaterialExtensionShaderLibrary?> Function(String assetPath);

abstract interface class MaterialExtensionShaderLibrary {
  Object? operator [](String shaderName);
}

final class MaterialExtensionPreflightResult {
  const MaterialExtensionPreflightResult({
    required this.support,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final MaterialExtensionSupport support;
  final List<ViewerDiagnostic> diagnostics;
}

/// Experimental flutter_scene custom-material backend for material extensions.
///
/// This owns only backend state that cannot be expressed through standard PBR
/// fields: render-texture capture, layer separation, and shader-material
/// replacement. It is intentionally internal and capability-gated by
/// [ViewerMaterialExtensionPolicy].
final class FlutterSceneMaterialExtensionBackend {
  FlutterSceneMaterialExtensionBackend({
    int renderTextureWidth = 1024,
    int renderTextureHeight = 1024,
    bool bindFallbackTextures = true,
    CreateTransmissionMaterial? createTransmissionMaterial,
    CreateClearcoatMaterial? createClearcoatMaterial,
    LoadMaterialExtensionShaderLibrary? loadShaderLibrary,
  })  : assert(renderTextureWidth > 0),
        assert(renderTextureHeight > 0),
        _renderTextureWidth = renderTextureWidth,
        _renderTextureHeight = renderTextureHeight,
        _bindFallbackTextures = bindFallbackTextures,
        _createTransmissionMaterial =
            createTransmissionMaterial ?? _loadTransmissionMaterial,
        _createClearcoatMaterial =
            createClearcoatMaterial ?? _loadClearcoatMaterial,
        _loadShaderLibrary =
            loadShaderLibrary ?? _loadMaterialExtensionShaderLibrary;

  static const int transmissiveLayer = 1 << 30;
  static const int backgroundLayerMask =
      flutter_scene.kRenderLayerAll ^ transmissiveLayer;
  static const String shaderBundleAsset =
      'build/shaderbundles/materials.shaderbundle';
  static const String packagedShaderBundleAsset =
      'packages/flutter_scene_viewer/build/shaderbundles/materials.shaderbundle';
  static const String transmissionShaderName = 'FSViewerTransmission';
  static const String clearcoatShaderName = 'FSViewerClearcoat';
  static const String materialParamsBlockName = 'MaterialParams';
  static const String backgroundTextureName = 'backgroundTexture';
  static const int maxBackgroundTextureExtent = 4096;
  static const double _clearcoatSourceNormalAntiAliasScale = 0.35;
  static const double _clearcoatSourceNormalAntiAliasFactor = 0.35;

  int _renderTextureWidth;
  int _renderTextureHeight;
  final bool _bindFallbackTextures;
  final CreateTransmissionMaterial _createTransmissionMaterial;
  final CreateClearcoatMaterial _createClearcoatMaterial;
  final LoadMaterialExtensionShaderLibrary _loadShaderLibrary;
  final Map<flutter_scene.MeshPrimitive, _MaterialExtensionState> _states =
      <flutter_scene.MeshPrimitive, _MaterialExtensionState>{};
  final Set<flutter_scene.MeshPrimitive> _transmissionPrimitives =
      Set<flutter_scene.MeshPrimitive>.identity();

  flutter_scene.RenderTexture? _backgroundTexture;
  flutter_scene.RenderView? _backgroundView;
  RenderCameraFrame? _cameraFrame;
  MaterialExtensionPreflightResult? _productionPreflightResult;

  (int width, int height) get debugBackgroundTextureSize =>
      (_renderTextureWidth, _renderTextureHeight);

  int get debugActivePatchCount => _states.length;

  bool get debugHasProductionPreflight => _productionPreflightResult != null;

  Future<MaterialExtensionPreflightResult> preflightProductionSupport() async {
    final cached = _productionPreflightResult;
    if (cached != null) {
      return cached;
    }

    Object? lastError;
    String? lastAssetPath;
    List<String> lastMissingShaders = const <String>[];
    for (final assetPath in _shaderBundleAssetCandidates) {
      lastAssetPath = assetPath;
      try {
        final library = await _loadShaderLibrary(assetPath);
        if (library == null) {
          lastMissingShaders = _requiredProductionShaders;
          continue;
        }
        final missingShaders = <String>[
          for (final shaderName in _requiredProductionShaders)
            if (library[shaderName] == null) shaderName,
        ];
        if (missingShaders.isEmpty) {
          return _productionPreflightResult = MaterialExtensionPreflightResult(
            support: MaterialExtensionSupport(
              backendKind:
                  MaterialExtensionBackendKind.flutterSceneCustomShader,
              features: <MaterialExtensionFeature,
                  MaterialExtensionFeatureSupport>{
                for (final feature in <MaterialExtensionFeature>[
                  MaterialExtensionFeature.transmission,
                  MaterialExtensionFeature.ior,
                  MaterialExtensionFeature.volume,
                  MaterialExtensionFeature.clearcoat,
                ])
                  feature: _candidatePreflightFeatureSupport(),
              },
            ),
          );
        }
        lastMissingShaders = List<String>.unmodifiable(missingShaders);
      } on Object catch (error) {
        lastError = error;
        lastMissingShaders = _requiredProductionShaders;
      }
    }

    return _productionPreflightResult = MaterialExtensionPreflightResult(
      support: MaterialExtensionSupport.unsupported,
      diagnostics: <ViewerDiagnostic>[
        _productionPreflightDiagnostic(
          assetPath: lastAssetPath,
          missingShaders: lastMissingShaders,
          error: lastError,
        ),
      ],
    );
  }

  List<ViewerDiagnostic> updateViewport({
    required double width,
    required double height,
    required double pixelRatio,
  }) {
    if (!width.isFinite ||
        !height.isFinite ||
        !pixelRatio.isFinite ||
        width <= 0 ||
        height <= 0 ||
        pixelRatio <= 0) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.invalidMaterialOverride,
          message:
              'Production material extension viewport size must be positive and finite.',
          details: <String, Object?>{
            'stage': 'renderTextureResize',
            'width': width,
            'height': height,
            'pixelRatio': pixelRatio,
            'status': 'invalid',
          },
        ),
      ];
    }

    final requestedWidth = (width * pixelRatio).ceil();
    final requestedHeight = (height * pixelRatio).ceil();
    final nextWidth =
        requestedWidth.clamp(1, maxBackgroundTextureExtent).toInt();
    final nextHeight =
        requestedHeight.clamp(1, maxBackgroundTextureExtent).toInt();
    final clamped =
        nextWidth != requestedWidth || nextHeight != requestedHeight;
    if (nextWidth != _renderTextureWidth ||
        nextHeight != _renderTextureHeight) {
      _renderTextureWidth = nextWidth;
      _renderTextureHeight = nextHeight;
      _backgroundTexture?.resize(nextWidth, nextHeight);
    }
    if (!clamped) {
      return const <ViewerDiagnostic>[];
    }
    return <ViewerDiagnostic>[
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.unsupportedMaterialFeature,
        message:
            'Production material extension background texture size was clamped.',
        details: <String, Object?>{
          'stage': 'renderTextureResize',
          'requestedWidth': requestedWidth,
          'requestedHeight': requestedHeight,
          'width': nextWidth,
          'height': nextHeight,
          'maxTextureExtent': maxBackgroundTextureExtent,
          'status': 'clamped',
        },
      ),
    ];
  }

  Future<List<ViewerDiagnostic>> applyTransmissionPatch({
    required List<flutter_scene.RenderView> sceneViews,
    required flutter_scene.Node node,
    required flutter_scene.MeshPrimitive primitive,
    required PartAddress address,
    required MaterialPatch patch,
    Object? baseColorTexture,
    Object? normalTexture,
    Object? transmissionTexture,
    Object? thicknessTexture,
  }) async {
    final backgroundTexture = _ensureBackgroundTexture();
    final materialConfig = FlutterSceneTransmissionMaterialConfig(
      patch: patch,
      backgroundTexture: backgroundTexture,
      renderTextureWidth: _renderTextureWidth,
      renderTextureHeight: _renderTextureHeight,
      bindFallbackTextures: _bindFallbackTextures,
      sourceMaterial: primitive.material,
      baseColorTexture: baseColorTexture,
      normalTexture: normalTexture,
      transmissionTexture: transmissionTexture,
      thicknessTexture: thicknessTexture,
    );

    final flutter_scene.ShaderMaterial material;
    try {
      material = await _createTransmissionMaterial(materialConfig);
    } on Object catch (error) {
      return <ViewerDiagnostic>[_shaderUnavailableDiagnostic(address, error)];
    }

    _configureTransmissionMaterial(material, materialConfig);
    _states.putIfAbsent(
      primitive,
      () => _MaterialExtensionState(
        node: node,
        primitive: primitive,
        originalLayers: node.layers,
        originalMaterial: primitive.material,
      ),
    );
    _transmissionPrimitives.add(primitive);
    node.layers = transmissiveLayer;
    primitive.material = material;
    _refreshMountedMesh(node);
    _ensureBackgroundView(sceneViews, backgroundTexture);
    return const <ViewerDiagnostic>[];
  }

  Future<List<ViewerDiagnostic>> applyClearcoatPatch({
    required flutter_scene.Node node,
    required flutter_scene.MeshPrimitive primitive,
    required PartAddress address,
    required MaterialPatch patch,
    Object? baseColorTexture,
    Object? metallicRoughnessTexture,
    Object? normalTexture,
    Object? occlusionTexture,
    Object? emissiveTexture,
    Object? clearcoatTexture,
    Object? clearcoatRoughnessTexture,
    Object? clearcoatNormalTexture,
  }) async {
    final baseMaterial = primitive.material;
    final materialConfig = FlutterSceneClearcoatMaterialConfig(
      patch: patch,
      sourceMaterial: baseMaterial is flutter_scene.PhysicallyBasedMaterial
          ? baseMaterial
          : null,
      bindFallbackTextures: _bindFallbackTextures,
      baseColorTexture: baseColorTexture,
      metallicRoughnessTexture: metallicRoughnessTexture,
      normalTexture: normalTexture,
      occlusionTexture: occlusionTexture,
      emissiveTexture: emissiveTexture,
      clearcoatTexture: clearcoatTexture,
      clearcoatRoughnessTexture: clearcoatRoughnessTexture,
      clearcoatNormalTexture: clearcoatNormalTexture,
    );

    final flutter_scene.Material material;
    try {
      material = await _createClearcoatMaterial(materialConfig);
    } on Object catch (error) {
      return <ViewerDiagnostic>[
        _clearcoatShaderUnavailableDiagnostic(address, error),
      ];
    }

    final state = _states.putIfAbsent(
      primitive,
      () => _MaterialExtensionState(
        node: node,
        primitive: primitive,
        originalLayers: node.layers,
        originalMaterial: primitive.material,
        originalSourceNormalScale:
            baseMaterial is flutter_scene.PhysicallyBasedMaterial
                ? baseMaterial.normalScale
                : null,
        originalSourceNormalTexture:
            baseMaterial is flutter_scene.PhysicallyBasedMaterial
                // ignore: invalid_use_of_internal_member
                ? baseMaterial.normalTextureSource
                : null,
      ),
    );
    _applyClearcoatSourceNormalAntialiasing(state: state, patch: patch);
    _configureClearcoatMaterial(material, materialConfig);
    _attachClearcoatOverlay(
      node: node,
      primitive: primitive,
      material: material,
    );
    return const <ViewerDiagnostic>[];
  }

  void updateCamera(RenderCameraFrame camera) {
    _cameraFrame = camera;
    final backgroundView = _backgroundView;
    if (backgroundView != null) {
      backgroundView.camera = _camera(camera);
    }
  }

  void resetTransmissionPatch({
    required List<flutter_scene.RenderView> sceneViews,
    required flutter_scene.Node node,
    required flutter_scene.MeshPrimitive primitive,
  }) {
    final state = _states.remove(primitive);
    _transmissionPrimitives.remove(primitive);
    if (state != null) {
      state.restore();
      _refreshMountedMesh(state.node);
    }
    if (_transmissionPrimitives.isEmpty) {
      final backgroundView = _backgroundView;
      if (backgroundView != null) {
        sceneViews.remove(backgroundView);
      }
      _backgroundView = null;
    }
  }

  void resetClearcoatPatch({
    required flutter_scene.Node node,
    required flutter_scene.MeshPrimitive primitive,
  }) {
    final state = _states.remove(primitive);
    if (state != null) {
      state.restore();
      _refreshMountedMesh(state.node);
    }
  }

  void clear({List<flutter_scene.RenderView>? sceneViews}) {
    final backgroundView = _backgroundView;
    if (sceneViews != null && backgroundView != null) {
      sceneViews.remove(backgroundView);
    }
    for (final state in _states.values) {
      state.restore();
      _refreshMountedMesh(state.node);
    }
    _states.clear();
    _transmissionPrimitives.clear();
    _backgroundView = null;
    _backgroundTexture = null;
    _productionPreflightResult = null;
  }

  static void _refreshMountedMesh(flutter_scene.Node node) {
    final mesh = node.mesh;
    if (mesh == null) {
      return;
    }
    node.mesh = flutter_scene.Mesh.primitives(
      primitives: List<flutter_scene.MeshPrimitive>.of(mesh.primitives),
    );
  }

  void _attachClearcoatOverlay({
    required flutter_scene.Node node,
    required flutter_scene.MeshPrimitive primitive,
    required flutter_scene.Material material,
  }) {
    final existingState = _states[primitive];
    final existingOverlay = existingState?.overlayPrimitive;
    if (existingOverlay != null) {
      existingOverlay.material = material;
      _refreshMountedMesh(node);
      return;
    }

    final overlayPrimitive = flutter_scene.MeshPrimitive(
      primitive.geometry,
      material,
    );
    final mesh = node.mesh;
    if (mesh == null) {
      return;
    }
    final nextPrimitives = <flutter_scene.MeshPrimitive>[
      ...mesh.primitives,
      overlayPrimitive,
    ];
    node.mesh = flutter_scene.Mesh.primitives(primitives: nextPrimitives);
    _states[primitive] = _MaterialExtensionState(
      node: node,
      primitive: primitive,
      originalLayers: existingState?.originalLayers ?? node.layers,
      originalMaterial: existingState?.originalMaterial ?? primitive.material,
      originalSourceNormalScale: existingState?.originalSourceNormalScale,
      originalSourceNormalTexture: existingState?.originalSourceNormalTexture,
      overlayPrimitive: overlayPrimitive,
    );
  }

  flutter_scene.RenderTexture _ensureBackgroundTexture() {
    return _backgroundTexture ??= flutter_scene.RenderTexture(
      width: _renderTextureWidth,
      height: _renderTextureHeight,
      update: flutter_scene.RenderTextureUpdate.everyFrame,
    );
  }

  void _ensureBackgroundView(
    List<flutter_scene.RenderView> sceneViews,
    flutter_scene.RenderTexture backgroundTexture,
  ) {
    final view = _backgroundView ??= flutter_scene.RenderView(
      camera: _camera(_cameraFrame ?? _defaultCameraFrame),
      target: backgroundTexture,
      layerMask: backgroundLayerMask,
      order: -100,
    );
    if (!sceneViews.contains(view)) {
      sceneViews.add(view);
    }
  }

  static Future<flutter_scene.ShaderMaterial> _loadTransmissionMaterial(
    FlutterSceneTransmissionMaterialConfig config,
  ) async {
    Object? lastError;
    for (final assetPath in _shaderBundleAssetCandidates) {
      try {
        final library =
            await flutter_scene_gpu.loadShaderLibraryAsync(assetPath);
        final shader = library?[transmissionShaderName];
        if (shader != null) {
          return flutter_scene.ShaderMaterial(
            fragmentShader: shader,
            isOpaqueOverride: false,
          );
        }
        lastError = StateError(
          'Shader entry "$transmissionShaderName" was not found in $assetPath.',
        );
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw StateError(lastError?.toString() ?? 'Transmission shader not found.');
  }

  static Future<flutter_scene.Material> _loadClearcoatMaterial(
    FlutterSceneClearcoatMaterialConfig config,
  ) async {
    Object? lastError;
    for (final assetPath in _shaderBundleAssetCandidates) {
      try {
        final library =
            await flutter_scene_gpu.loadShaderLibraryAsync(assetPath);
        final shader = library?[clearcoatShaderName];
        if (shader != null) {
          final metadata = await _loadFmatMetadata(
            assetPath: assetPath,
            materialName: clearcoatShaderName,
          );
          return flutter_scene.PreprocessedMaterial(
            fragmentShader: shader,
            metadata: metadata,
          );
        }
        lastError = StateError(
          'Shader entry "$clearcoatShaderName" was not found in $assetPath.',
        );
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw StateError(lastError?.toString() ?? 'Clearcoat shader not found.');
  }

  static void _configureTransmissionMaterial(
    flutter_scene.ShaderMaterial material,
    FlutterSceneTransmissionMaterialConfig config,
  ) {
    material
      ..isOpaqueOverride = false
      ..cullingMode = config.sourceMaterial.doubleSided
          ? flutter_scene_internal_gpu.CullMode.none
          : flutter_scene_internal_gpu.CullMode.backFace
      ..setTexture(backgroundTextureName, config.backgroundTexture)
      ..setUniformBlockFromFloats(
        materialParamsBlockName,
        _materialParams(config),
      );
    material
      ..setTexture(
        'baseColorTexture',
        config.baseColorTexture ??
            config.sourceBaseColorTexture ??
            config.whiteFallbackTexture,
      )
      ..setTexture(
        'normalTexture',
        config.normalTexture ??
            config.sourceNormalTexture ??
            config.normalFallbackTexture,
      )
      ..setTexture(
        'transmissionTexture',
        config.transmissionTexture ?? config.whiteFallbackTexture,
      )
      ..setTexture(
        'thicknessTexture',
        config.thicknessTexture ?? config.whiteFallbackTexture,
      );
  }

  static List<double> _materialParams(
    FlutterSceneTransmissionMaterialConfig config,
  ) {
    final patch = config.patch;
    final source = config.sourcePbrMaterial;
    final baseColor = _unitVector4(
      patch.baseColorFactor ?? _vector4List(source?.baseColorFactor),
      const <double>[1, 1, 1, 1],
    );
    final attenuationColor = _unitVector3(
      patch.attenuationColor,
      const <double>[1, 1, 1],
    );
    return <double>[
      baseColor[0],
      baseColor[1],
      baseColor[2],
      baseColor[3],
      attenuationColor[0],
      attenuationColor[1],
      attenuationColor[2],
      _nonNegativeFinite(patch.attenuationDistance, fallback: 0.0),
      _unitFinite(patch.transmission, fallback: 0.0),
      _finiteRange(patch.ior, minimum: 1.0, maximum: 3.0, fallback: 1.5),
      _nonNegativeFinite(patch.thickness, fallback: 0.0),
      _unitFinite(patch.roughness, fallback: 0.0),
      1.0 / config.renderTextureWidth,
      1.0 / config.renderTextureHeight,
      _nonNegativeFinite(patch.normalScale, fallback: 1.0),
      0.0,
    ];
  }

  static void _configureClearcoatMaterial(
    flutter_scene.Material material,
    FlutterSceneClearcoatMaterialConfig config,
  ) {
    if (material is flutter_scene.PreprocessedMaterial) {
      _configurePreprocessedClearcoatMaterial(material, config);
      return;
    }
    if (material is! flutter_scene.ShaderMaterial) {
      return;
    }
    material
      ..useEnvironment = true
      ..isOpaqueOverride = false
      ..setUniformBlockFromFloats(
        materialParamsBlockName,
        _clearcoatMaterialParams(config),
      );
    material
      ..setTexture(
        'baseColorTexture',
        config.baseColorTexture ??
            config.sourceBaseColorTexture ??
            config.whiteFallbackTexture,
      )
      ..setTexture(
        'metallicRoughnessTexture',
        config.metallicRoughnessTexture ??
            config.sourceMetallicRoughnessTexture ??
            config.whiteFallbackTexture,
      )
      ..setTexture(
        'normalTexture',
        config.normalTexture ??
            config.sourceNormalTexture ??
            config.normalFallbackTexture,
      )
      ..setTexture(
        'occlusionTexture',
        config.occlusionTexture ??
            config.sourceOcclusionTexture ??
            config.whiteFallbackTexture,
      )
      ..setTexture(
        'emissiveTexture',
        config.emissiveTexture ??
            config.sourceEmissiveTexture ??
            config.blackFallbackTexture,
      )
      ..setTexture(
        'clearcoatTexture',
        config.clearcoatTexture ?? config.whiteFallbackTexture,
      )
      ..setTexture(
        'clearcoatRoughnessTexture',
        config.clearcoatRoughnessTexture ?? config.whiteFallbackTexture,
      )
      ..setTexture(
        'clearcoatNormalTexture',
        config.clearcoatNormalTexture ?? config.normalFallbackTexture,
      );
  }

  static void _configurePreprocessedClearcoatMaterial(
    flutter_scene.PreprocessedMaterial material,
    FlutterSceneClearcoatMaterialConfig config,
  ) {
    final params = material.parameters;
    final values = _clearcoatMaterialParams(config);
    params
      ..setVec4(
        'baseColorFactor',
        vm.Vector4(values[0], values[1], values[2], values[3]),
      )
      ..setVec4(
        'materialFactors',
        vm.Vector4(values[4], values[5], values[6], values[7]),
      )
      ..setVec4(
        'normalFactors',
        vm.Vector4(values[8], values[9], values[10], values[11]),
      )
      ..setVec4(
        'emissiveFactor',
        _emissiveFactor(config),
      );
    _setPreprocessedTexture(
      params,
      'baseColorTexture',
      config.baseColorTexture ?? config.sourceBaseColorTexture,
    );
    _setPreprocessedTexture(
      params,
      'metallicRoughnessTexture',
      config.metallicRoughnessTexture ?? config.sourceMetallicRoughnessTexture,
    );
    _setPreprocessedTexture(
      params,
      'normalTexture',
      config.normalTexture ?? config.sourceNormalTexture,
    );
    _setPreprocessedTexture(
      params,
      'occlusionTexture',
      config.occlusionTexture ?? config.sourceOcclusionTexture,
    );
    _setPreprocessedTexture(
      params,
      'emissiveTexture',
      config.emissiveTexture ?? config.sourceEmissiveTexture,
    );
    _setPreprocessedTexture(
      params,
      'clearcoatTexture',
      config.clearcoatTexture,
    );
    _setPreprocessedTexture(
      params,
      'clearcoatRoughnessTexture',
      config.clearcoatRoughnessTexture,
    );
    _setPreprocessedTexture(
      params,
      'clearcoatNormalTexture',
      config.clearcoatNormalTexture,
    );
  }

  static void _setPreprocessedTexture(
    flutter_scene.MaterialParameters params,
    String name,
    Object? texture,
  ) {
    if (texture is flutter_scene_gpu.Texture) {
      params.setTexture(name, texture);
    }
  }

  static void _applyClearcoatSourceNormalAntialiasing({
    required _MaterialExtensionState state,
    required MaterialPatch patch,
  }) {
    final material = state.primitive.material;
    if (material is! flutter_scene.PhysicallyBasedMaterial) {
      return;
    }
    // ignore: invalid_use_of_internal_member
    if (material.normalTextureSource == null) {
      return;
    }
    final originalScale = state.originalSourceNormalScale;
    if (_unitFinite(patch.clearcoat, fallback: 0.0) <= 0.0) {
      material.normalTexture = state.originalSourceNormalTexture;
      if (originalScale != null) {
        material.normalScale = originalScale;
      }
      return;
    }
    final requestedScale = _nonNegativeFinite(
      patch.normalScale ?? originalScale ?? material.normalScale,
      fallback: material.normalScale,
    );
    material.normalTexture = null;
    material.normalScale = _clearcoatAntialiasedNormalScale(requestedScale);
  }

  static List<double> _clearcoatMaterialParams(
    FlutterSceneClearcoatMaterialConfig config,
  ) {
    final patch = config.patch;
    final source = config.sourceMaterial;
    final baseColor = _unitVector4(
      patch.baseColorFactor ?? _vector4List(source?.baseColorFactor),
      const <double>[1, 1, 1, 1],
    );
    return <double>[
      baseColor[0],
      baseColor[1],
      baseColor[2],
      baseColor[3],
      _unitFinite(patch.metallic ?? source?.metallicFactor, fallback: 1.0),
      _unitFinite(patch.roughness ?? source?.roughnessFactor, fallback: 1.0),
      _unitFinite(patch.clearcoat, fallback: 0.0),
      _unitFinite(patch.clearcoatRoughness, fallback: 0.0),
      _clearcoatBaseNormalScale(config),
      _nonNegativeFinite(patch.clearcoatNormalScale, fallback: 1.0),
      config.clearcoatNormalTexture == null ? 0.0 : 1.0,
      0.0,
    ];
  }

  static double _clearcoatBaseNormalScale(
    FlutterSceneClearcoatMaterialConfig config,
  ) {
    final source = config.sourceMaterial;
    final requestedScale = _nonNegativeFinite(
      config.patch.normalScale ?? source?.normalScale,
      fallback: 1.0,
    );
    if (_unitFinite(config.patch.clearcoat, fallback: 0.0) <= 0.0) {
      return requestedScale;
    }
    final hasBaseNormal =
        config.normalTexture != null || config.sourceNormalTexture != null;
    if (!hasBaseNormal || requestedScale <= 0.0) {
      return requestedScale;
    }
    return _clearcoatAntialiasedNormalScale(requestedScale);
  }

  static double _clearcoatAntialiasedNormalScale(double requestedScale) {
    final attenuatedScale =
        requestedScale * _clearcoatSourceNormalAntiAliasFactor;
    return attenuatedScale > _clearcoatSourceNormalAntiAliasScale
        ? _clearcoatSourceNormalAntiAliasScale
        : attenuatedScale;
  }

  static vm.Vector4 _emissiveFactor(
    FlutterSceneClearcoatMaterialConfig config,
  ) {
    final patch = config.patch.emissiveFactor;
    if (patch != null) {
      return vm.Vector4(patch[0], patch[1], patch[2], 1.0);
    }
    return config.sourceMaterial?.emissiveFactor.clone() ?? vm.Vector4.zero();
  }

  static ViewerDiagnostic _shaderUnavailableDiagnostic(
    PartAddress address,
    Object error,
  ) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Transmission/glass requires the experimental flutter_scene shader backend, but the transmission shader could not be loaded.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'transmission',
        'shader': transmissionShaderName,
        'status': 'shaderUnavailable',
        'error': error.toString(),
      },
    );
  }

  static ViewerDiagnostic _clearcoatShaderUnavailableDiagnostic(
    PartAddress address,
    Object error,
  ) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Clearcoat requires the experimental flutter_scene shader backend, but the clearcoat shader could not be loaded.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'clearcoat',
        'shader': clearcoatShaderName,
        'status': 'shaderUnavailable',
        'error': error.toString(),
      },
    );
  }

  static Future<MaterialExtensionShaderLibrary?>
      _loadMaterialExtensionShaderLibrary(String assetPath) async {
    final library = await flutter_scene_gpu.loadShaderLibraryAsync(assetPath);
    return library == null ? null : _FlutterSceneShaderLibrary(library);
  }

  static Future<Map<String, Object?>> _loadFmatMetadata({
    required String assetPath,
    required String materialName,
  }) async {
    final sidecarPath = _fmatSidecarPath(assetPath);
    final decoded = jsonDecode(await rootBundle.loadString(sidecarPath)) as Map;
    final rawMetadata = decoded[materialName];
    if (rawMetadata is! Map) {
      throw StateError(
        'Material metadata "$materialName" was not found in $sidecarPath.',
      );
    }
    return rawMetadata.cast<String, Object?>();
  }

  static ViewerDiagnostic _productionPreflightDiagnostic({
    required String? assetPath,
    required List<String> missingShaders,
    Object? error,
  }) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Production material extension shaders are not available for this target.',
      details: <String, Object?>{
        'stage': 'shaderPreflight',
        'shader': missingShaders,
        'assetPath': assetPath,
        'platform': _platformLabel,
        'status': 'unavailable',
        'backendKind': 'none',
        'productionBlocker': 'rendererNativeMaterialExtensionContractMissing',
        if (error != null) 'error': error.toString(),
      },
    );
  }
}

MaterialExtensionFeatureSupport _candidatePreflightFeatureSupport() =>
    MaterialExtensionFeatureSupport(
      available: true,
      maturityByTarget: <MaterialExtensionTarget, MaterialExtensionMaturity>{
        for (final target in MaterialExtensionTarget.values)
          target: MaterialExtensionMaturity.candidateOnly,
      },
    );

const List<String> _shaderBundleAssetCandidates = <String>[
  FlutterSceneMaterialExtensionBackend.shaderBundleAsset,
  FlutterSceneMaterialExtensionBackend.packagedShaderBundleAsset,
];

const List<String> _requiredProductionShaders = <String>[
  FlutterSceneMaterialExtensionBackend.transmissionShaderName,
  FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
];

String _fmatSidecarPath(String shaderBundlePath) =>
    shaderBundlePath.replaceFirst('.shaderbundle', '.fmat.json');

String get _platformLabel {
  if (kIsWeb) {
    return 'web';
  }
  return defaultTargetPlatform.name;
}

final class _FlutterSceneShaderLibrary
    implements MaterialExtensionShaderLibrary {
  const _FlutterSceneShaderLibrary(this._library);

  final flutter_scene_gpu.ShaderLibrary _library;

  @override
  Object? operator [](String shaderName) => _library[shaderName];
}

final class FlutterSceneTransmissionMaterialConfig {
  const FlutterSceneTransmissionMaterialConfig({
    required this.patch,
    required this.backgroundTexture,
    required this.renderTextureWidth,
    required this.renderTextureHeight,
    required this.bindFallbackTextures,
    required this.sourceMaterial,
    this.baseColorTexture,
    this.normalTexture,
    this.transmissionTexture,
    this.thicknessTexture,
  });

  final MaterialPatch patch;
  final flutter_scene.RenderTexture backgroundTexture;
  final int renderTextureWidth;
  final int renderTextureHeight;
  final bool bindFallbackTextures;
  final flutter_scene.Material sourceMaterial;
  final Object? baseColorTexture;
  final Object? normalTexture;
  final Object? transmissionTexture;
  final Object? thicknessTexture;

  flutter_scene.PhysicallyBasedMaterial? get sourcePbrMaterial {
    final material = sourceMaterial;
    return material is flutter_scene.PhysicallyBasedMaterial ? material : null;
  }

  Object? get sourceBaseColorTexture {
    // ignore: invalid_use_of_internal_member
    return sourcePbrMaterial?.baseColorTextureSource;
  }

  Object? get sourceNormalTexture {
    // ignore: invalid_use_of_internal_member
    return sourcePbrMaterial?.normalTextureSource;
  }

  Object? get whiteFallbackTexture => bindFallbackTextures
      ? flutter_scene.Material.getWhitePlaceholderTexture()
      : null;

  Object? get normalFallbackTexture => bindFallbackTextures
      ? flutter_scene.Material.getNormalPlaceholderTexture()
      : null;
}

final class FlutterSceneClearcoatMaterialConfig {
  const FlutterSceneClearcoatMaterialConfig({
    required this.patch,
    required this.bindFallbackTextures,
    this.sourceMaterial,
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.occlusionTexture,
    this.emissiveTexture,
    this.clearcoatTexture,
    this.clearcoatRoughnessTexture,
    this.clearcoatNormalTexture,
  });

  final MaterialPatch patch;
  final flutter_scene.PhysicallyBasedMaterial? sourceMaterial;
  final bool bindFallbackTextures;
  final Object? baseColorTexture;
  final Object? metallicRoughnessTexture;
  final Object? normalTexture;
  final Object? occlusionTexture;
  final Object? emissiveTexture;
  final Object? clearcoatTexture;
  final Object? clearcoatRoughnessTexture;
  final Object? clearcoatNormalTexture;

  Object? get sourceBaseColorTexture {
    // ignore: invalid_use_of_internal_member
    return sourceMaterial?.baseColorTextureSource;
  }

  Object? get sourceMetallicRoughnessTexture {
    // ignore: invalid_use_of_internal_member
    return sourceMaterial?.metallicRoughnessTextureSource;
  }

  Object? get sourceNormalTexture {
    // ignore: invalid_use_of_internal_member
    return sourceMaterial?.normalTextureSource;
  }

  Object? get sourceOcclusionTexture {
    // ignore: invalid_use_of_internal_member
    return sourceMaterial?.occlusionTextureSource;
  }

  Object? get sourceEmissiveTexture {
    // ignore: invalid_use_of_internal_member
    return sourceMaterial?.emissiveTextureSource;
  }

  Object? get whiteFallbackTexture => bindFallbackTextures
      ? flutter_scene.Material.getWhitePlaceholderTexture()
      : null;

  Object? get normalFallbackTexture => bindFallbackTextures
      ? flutter_scene.Material.getNormalPlaceholderTexture()
      : null;

  Object? get blackFallbackTexture => bindFallbackTextures
      ? flutter_scene.Material.getBlackPlaceholderTexture()
      : null;
}

final class _MaterialExtensionState {
  const _MaterialExtensionState({
    required this.node,
    required this.primitive,
    required this.originalLayers,
    required this.originalMaterial,
    this.originalSourceNormalScale,
    this.originalSourceNormalTexture,
    this.overlayPrimitive,
  });

  final flutter_scene.Node node;
  final flutter_scene.MeshPrimitive primitive;
  final int originalLayers;
  final flutter_scene.Material originalMaterial;
  final double? originalSourceNormalScale;
  final flutter_scene.TextureSource? originalSourceNormalTexture;
  final flutter_scene.MeshPrimitive? overlayPrimitive;

  void restore() {
    node.layers = originalLayers;
    if (originalMaterial is flutter_scene.PhysicallyBasedMaterial) {
      final originalPbrMaterial =
          originalMaterial as flutter_scene.PhysicallyBasedMaterial;
      originalPbrMaterial.normalTexture = originalSourceNormalTexture;
      final originalNormalScale = originalSourceNormalScale;
      if (originalNormalScale != null) {
        originalPbrMaterial.normalScale = originalNormalScale;
      }
    }
    final overlay = overlayPrimitive;
    if (overlay != null) {
      final mesh = node.mesh;
      if (mesh == null || !mesh.primitives.contains(overlay)) {
        return;
      }
      node.mesh = flutter_scene.Mesh.primitives(
        primitives: <flutter_scene.MeshPrimitive>[
          for (final primitive in mesh.primitives)
            if (!identical(primitive, overlay)) primitive,
        ],
      );
      return;
    }
    primitive.material = originalMaterial;
  }
}

flutter_scene.PerspectiveCamera _camera(RenderCameraFrame frame) {
  return flutter_scene.PerspectiveCamera(
    position: _vector3(frame.position),
    target: _vector3(frame.target),
    up: _vector3(frame.up),
    fovRadiansY: frame.verticalFovRadians,
    fovNear: frame.near,
    fovFar: frame.far,
  );
}

List<double> _vector4List(vm.Vector4? vector) {
  if (vector == null) {
    return const <double>[1, 1, 1, 1];
  }
  return <double>[vector.x, vector.y, vector.z, vector.w];
}

List<double> _unitVector4(List<double>? values, List<double> fallback) {
  if (values == null || values.length != 4) {
    return List<double>.unmodifiable(fallback);
  }
  return List<double>.unmodifiable(<double>[
    _unitFinite(values[0], fallback: fallback[0]),
    _unitFinite(values[1], fallback: fallback[1]),
    _unitFinite(values[2], fallback: fallback[2]),
    _unitFinite(values[3], fallback: fallback[3]),
  ]);
}

List<double> _unitVector3(List<double>? values, List<double> fallback) {
  if (values == null || values.length != 3) {
    return List<double>.unmodifiable(fallback);
  }
  return List<double>.unmodifiable(<double>[
    _unitFinite(values[0], fallback: fallback[0]),
    _unitFinite(values[1], fallback: fallback[1]),
    _unitFinite(values[2], fallback: fallback[2]),
  ]);
}

double _unitFinite(double? value, {required double fallback}) {
  return _finiteRange(value, minimum: 0.0, maximum: 1.0, fallback: fallback);
}

double _nonNegativeFinite(double? value, {required double fallback}) {
  final finite = _finiteOrFallback(value, fallback);
  if (finite < 0.0) {
    return 0.0;
  }
  return finite;
}

double _finiteRange(
  double? value, {
  required double minimum,
  required double maximum,
  required double fallback,
}) {
  final finite = _finiteOrFallback(value, fallback);
  if (finite < minimum) {
    return minimum;
  }
  if (finite > maximum) {
    return maximum;
  }
  return finite;
}

double _finiteOrFallback(double? value, double fallback) {
  if (value == null || !value.isFinite) {
    return fallback;
  }
  return value;
}

const RenderCameraFrame _defaultCameraFrame = RenderCameraFrame(
  position: <double>[0, 0, 1],
  target: <double>[0, 0, 0],
);

vm.Vector3 _vector3(List<double> components) {
  return vm.Vector3(
    components[0],
    components[1],
    components[2],
  );
}
