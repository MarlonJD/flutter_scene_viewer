import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Key, Offset, Size, Widget;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;
import 'package:http/http.dart' as http;
import 'package:vector_math/vector_math.dart' as vm;

import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';
import '../material_shading_mode.dart';
import '../part_address.dart';
import '../texture_binding.dart';
import '../texture_source.dart';
import 'environment_source_loader.dart';
import 'flutter_scene_extended_pbr_backend.dart';
import 'flutter_scene_extended_pbr_material.dart';
import 'flutter_scene_material_extension_backend.dart';
import 'material_base_family.dart';
import 'material_extension_native_applier.dart';
import 'material_extension_native_capability.dart';
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

/// Internal texture-construction seam used to verify that sampler intent is
/// passed through every wrapper-owned flutter_scene creation path.
abstract interface class FlutterSceneTextureFactory {
  Future<flutter_scene.TextureSource> fromAsset(
    String assetPath, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  });

  Future<flutter_scene.TextureSource> fromImage(
    ui.Image image, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  });

  flutter_scene.TextureSource fromPixels(
    Uint8List pixels,
    int width,
    int height, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  });
}

final class _DefaultFlutterSceneTextureFactory
    implements FlutterSceneTextureFactory {
  const _DefaultFlutterSceneTextureFactory();

  @override
  Future<flutter_scene.TextureSource> fromAsset(
    String assetPath, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) =>
      flutter_scene.Texture2D.fromAsset(
        assetPath,
        content: content,
        sampling: sampling,
      );

  @override
  Future<flutter_scene.TextureSource> fromImage(
    ui.Image image, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) =>
      flutter_scene.Texture2D.fromImage(
        image,
        content: content,
        sampling: sampling,
      );

  @override
  flutter_scene.TextureSource fromPixels(
    Uint8List pixels,
    int width,
    int height, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) =>
      flutter_scene.Texture2D.fromPixels(
        pixels,
        width,
        height,
        content: content,
        sampling: sampling,
      );
}

/// Runtime adapter backed by the installed `flutter_scene` package.
final class FlutterSceneRuntimeAdapter implements FlutterSceneAdapter {
  FlutterSceneRuntimeAdapter({
    EnvironmentSourceLoader? environmentSourceLoader,
    this.materialExtensionPolicy =
        const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
    FlutterSceneMaterialExtensionBackend? materialExtensionBackend,
    FlutterSceneExtendedPbrMaterialBackend? extendedPbrBackend,
    RendererMaterialExtensionProbe? materialExtensionRendererProbe,
    FlutterSceneTextureFactory? textureFactory,
  })  : _environmentSourceLoader =
            environmentSourceLoader ?? EnvironmentSourceLoader(),
        _materialExtensionBackend =
            materialExtensionBackend ?? FlutterSceneMaterialExtensionBackend(),
        _extendedPbrBackend =
            extendedPbrBackend ?? FlutterSceneExtendedPbrBackend(),
        _materialExtensionRendererProbe = materialExtensionRendererProbe ??
            const CurrentFlutterSceneMaterialExtensionProbe(),
        _textureFactory =
            textureFactory ?? const _DefaultFlutterSceneTextureFactory();

  final EnvironmentSourceLoader _environmentSourceLoader;
  final ViewerMaterialExtensionPolicy materialExtensionPolicy;
  final FlutterSceneMaterialExtensionBackend _materialExtensionBackend;
  final FlutterSceneExtendedPbrMaterialBackend _extendedPbrBackend;
  final RendererMaterialExtensionProbe _materialExtensionRendererProbe;
  final FlutterSceneTextureFactory _textureFactory;
  MaterialExtensionSupport _productionMaterialExtensionSupport =
      MaterialExtensionSupport.unsupported;
  final List<ViewerDiagnostic> _diagnostics = <ViewerDiagnostic>[];
  flutter_scene.Node? _rootNode;
  flutter_scene.Scene? _scene;
  List<flutter_scene.RenderView>? _materialExtensionSceneViewsForTesting;
  AdapterRenderScene? _renderScene;
  final Map<PartAddress, _OriginalMaterialState> _originalMaterials =
      <PartAddress, _OriginalMaterialState>{};

  flutter_scene.Node? get rootNode => _rootNode;

  flutter_scene.Scene? get debugScene => _scene;

  MaterialExtensionSupport get materialExtensionSupport {
    final base = materialExtensionPolicy.mode ==
            ViewerMaterialExtensionMode.productionFlutterSceneShaders
        ? _productionMaterialExtensionSupport
        : materialExtensionPolicy.support;
    return _extendedPbrBackend.isReady ? _withExtendedPbrSupport(base) : base;
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
    final extendedPbrDiagnostic = await _extendedPbrBackend.preflight(
      PartAddress(nodePath: const <String>['model'], primitiveIndex: 0),
    );
    if (extendedPbrDiagnostic != null) {
      _diagnostics.add(extendedPbrDiagnostic);
    }
    if (materialExtensionPolicy.mode ==
        ViewerMaterialExtensionMode.productionFlutterSceneShaders) {
      final nativeCapability = detectNativeMaterialExtensionCapability(
        rendererProbe: _materialExtensionRendererProbe,
      );
      final shaderPreflight =
          await _materialExtensionBackend.preflightProductionSupport();
      _productionMaterialExtensionSupport =
          _resolveProductionMaterialExtensionSupport(
        nativeCapability,
        shaderPreflight,
      );
      if (!_hasAvailableMaterialExtensionBackendFeatures(
        _productionMaterialExtensionSupport,
      )) {
        _diagnostics
          ..addAll(nativeCapability.diagnostics)
          ..addAll(shaderPreflight.diagnostics);
      }
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

    final usesNativeMaterialExtensionApplier =
        _usesNativeMaterialExtensionApplierFor(
      materialExtensionPolicy,
      patch,
      support: materialExtensionSupport,
    );
    final needsExtendedPbr =
        _usesExtendedPbrFor(target.primitive.material, patch);
    final combinesNativeClearcoatWithExtendedPbr =
        usesNativeMaterialExtensionApplier &&
            patch.hasClearcoatOverride &&
            !patch.hasGlassOverride &&
            needsExtendedPbr;
    final usesExtendedPbr = needsExtendedPbr &&
        (!usesNativeMaterialExtensionApplier ||
            combinesNativeClearcoatWithExtendedPbr);
    if (usesNativeMaterialExtensionApplier) {
      final validationDiagnostics = patch.validate(
        address,
        support: materialExtensionSupport,
      );
      if (validationDiagnostics.isNotEmpty) {
        return validationDiagnostics;
      }
    }
    if (usesExtendedPbr) {
      if (patch.hasGlassOverride ||
          (patch.hasClearcoatOverride &&
              !combinesNativeClearcoatWithExtendedPbr)) {
        return <ViewerDiagnostic>[
          _extendedPbrCombinationUnavailable(address, patch),
        ];
      }
      if (target.primitive.material is! flutter_scene.PhysicallyBasedMaterial) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedMaterialFeature,
            message: 'FSViewerExtendedPbr requires a lit PBR material.',
            details: <String, Object?>{
              'part': address.debugPath,
              'feature': flutterSceneExtendedPbrShaderName,
              'limitation': 'extendedPbrRequiresLitMaterial',
              'status': 'blocked',
              'materialReplaced': false,
            },
          ),
        ];
      }
      final validationDiagnostics = patch.validate(
        address,
        support: _withExtendedPbrSupport(materialExtensionSupport),
      );
      if (validationDiagnostics.isNotEmpty) {
        return validationDiagnostics;
      }
      final preflightDiagnostic = await _extendedPbrBackend.preflight(address);
      if (preflightDiagnostic != null) {
        return <ViewerDiagnostic>[preflightDiagnostic];
      }
    }

    if (materialExtensionPolicy.mode ==
            ViewerMaterialExtensionMode.productionFlutterSceneShaders &&
        materialExtensionSupport.backendKind ==
            MaterialExtensionBackendKind.rendererNative &&
        hasNativeMaterialExtensionIntent(patch)) {
      final diagnostic = nativeMaterialExtensionPatchDiagnostic(
        support: materialExtensionSupport,
        patch: patch,
        address: address,
      );
      if (diagnostic != null) {
        return <ViewerDiagnostic>[diagnostic];
      }
    }

    final standardPbrExtensionDiagnostic =
        _pinnedStandardPbrExtensionDiagnostic(
      address,
      patch,
      backendKind: materialExtensionSupport.backendKind,
      usesNativeMaterialExtensionApplier: usesNativeMaterialExtensionApplier,
      usesExtendedPbr: usesExtendedPbr,
      hasEffectiveOpaqueIorIntent: patch.hasOpaqueIorOverride ||
          ((patch.transmission ?? 0.0) == 0.0 && patch.ior != null),
    );
    if (standardPbrExtensionDiagnostic != null) {
      return <ViewerDiagnostic>[standardPbrExtensionDiagnostic];
    }

    final unsupportedDiagnostics = <ViewerDiagnostic>[
      if (patch.hasGlassOverride &&
          patch.hasClearcoatOverride &&
          !_usesNativeMaterialExtensionApplierFor(
            materialExtensionPolicy,
            patch,
            support: materialExtensionSupport,
          ))
        _unsupportedCombinedGlassClearcoatMaterial(address)
      else ...<ViewerDiagnostic>[
        if (patch.hasGlassOverride &&
            !_usesMaterialExtensionBackendFor(
              materialExtensionPolicy,
              patch,
              support: materialExtensionSupport,
            ) &&
            !_usesNativeMaterialExtensionApplierFor(
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
            ) &&
            !_usesNativeMaterialExtensionApplierFor(
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
    final usesMaterialExtensionBackend = _usesMaterialExtensionBackendFor(
      materialExtensionPolicy,
      patch,
      support: materialExtensionSupport,
    );
    final packageLocalTransmissionZeroBypass = patch.hasGlassOverride &&
        usesMaterialExtensionBackend &&
        (patch.transmission ?? 0.0) == 0.0;
    final isolationDiagnostic =
        patch.hasGlassOverride && !packageLocalTransmissionZeroBypass
            ? _glassNodeIsolationDiagnostic(
                address: address,
                primitiveCount: target.node.mesh?.primitives.length ?? 0,
                selectedPrimitiveIndex: address.primitiveIndex,
              )
            : null;
    if (isolationDiagnostic != null) {
      return <ViewerDiagnostic>[isolationDiagnostic];
    }
    final requiresUv0 = MaterialTextureSlot.values.any(
      (slot) =>
          patch.textureBindingFor(slot) != null &&
          !(packageLocalTransmissionZeroBypass &&
              (slot == MaterialTextureSlot.transmission ||
                  slot == MaterialTextureSlot.thickness)),
    );
    if (requiresUv0 && !_primitiveHasTexCoord0(target.primitive)) {
      return <ViewerDiagnostic>[_missingUv(address)];
    }
    final textureBindingPlans =
        <MaterialTextureSlot, FlutterSceneTextureBindingPlan>{};
    for (final slot in MaterialTextureSlot.values) {
      if (packageLocalTransmissionZeroBypass &&
          (slot == MaterialTextureSlot.transmission ||
              slot == MaterialTextureSlot.thickness)) {
        continue;
      }
      final binding = patch.textureBindingFor(slot);
      if (binding == null) {
        continue;
      }
      final plan = _flutterSceneTextureBindingPlan(
        binding,
        slot,
        address,
        allowExtendedPbrCoreTransform: usesExtendedPbr,
      );
      textureBindingPlans[slot] = plan;
      final diagnostic = plan.diagnostic;
      if (diagnostic != null) {
        return <ViewerDiagnostic>[diagnostic];
      }
    }
    if (patch.effectMask != null) {
      return <ViewerDiagnostic>[_unsupportedEffectMask(address)];
    }
    if (patch.normalScale != null &&
        patch.textureBindingFor(MaterialTextureSlot.normal) == null) {
      return <ViewerDiagnostic>[_normalScaleRequiresTexture(address)];
    }

    if (patch.hasGlassOverride && usesMaterialExtensionBackend) {
      final preflightDiagnostic =
          _materialExtensionBackend.packageLocalTransmissionPreflightDiagnostic(
        address: address,
        patch: patch,
        hasTransmissionTexture:
            patch.textureBindingFor(MaterialTextureSlot.transmission) != null,
        hasThicknessTexture:
            patch.textureBindingFor(MaterialTextureSlot.thickness) != null,
      );
      if (preflightDiagnostic != null) {
        return <ViewerDiagnostic>[preflightDiagnostic];
      }
    }

    final activeTransmissionSourceMaterial =
        patch.hasGlassOverride && usesMaterialExtensionBackend
            ? _materialExtensionBackend
                .activeTransmissionSourceMaterial(target.primitive)
            : null;
    final family = resolveMaterialBaseFamily(patch);
    var material = packageLocalTransmissionZeroBypass
        ? activeTransmissionSourceMaterial ?? target.primitive.material
        : target.primitive.material;
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
    final clearcoatManagesCoreInputs =
        _hasPackageLocalClearcoatConsumedCoreIntent(patch) &&
            _materialExtensionBackend
                .managesClearcoatCoreInputs(target.primitive);
    final clearcoatManagesCoreNormal =
        patch.textureBindingFor(MaterialTextureSlot.normal) != null &&
            clearcoatManagesCoreInputs;
    final usesRawNormalTexture = usesExtendedPbr ||
        (usesMaterialExtensionBackend && !packageLocalTransmissionZeroBypass) ||
        clearcoatManagesCoreNormal;
    if (patch.hasGlassOverride &&
        usesMaterialExtensionBackend &&
        !packageLocalTransmissionZeroBypass) {
      final diagnostic = _transmissionCoreInputsUnsupportedDiagnostic(
        address,
        patch,
        sourceMaterial:
            material is flutter_scene.PhysicallyBasedMaterial ? material : null,
      );
      if (diagnostic != null) {
        return <ViewerDiagnostic>[diagnostic];
      }
    }
    if (usesMaterialExtensionBackend &&
        !packageLocalTransmissionZeroBypass &&
        patch.visible != null) {
      return <ViewerDiagnostic>[
        _packageLocalExtensionVisibilityUnsupported(address),
      ];
    }

    final packageLocalTransmissionSceneViews =
        patch.hasGlassOverride && usesMaterialExtensionBackend
            ? _scene?.views ?? _materialExtensionSceneViewsForTesting
            : null;
    if (patch.hasGlassOverride &&
        usesMaterialExtensionBackend &&
        packageLocalTransmissionSceneViews == null) {
      if (!packageLocalTransmissionZeroBypass) {
        return <ViewerDiagnostic>[
          _transmissionSceneViewsUnavailableDiagnostic(
            address,
            activeReset: false,
          ),
        ];
      }
      if (activeTransmissionSourceMaterial != null) {
        return <ViewerDiagnostic>[
          _transmissionSceneViewsUnavailableDiagnostic(
            address,
            activeReset: true,
          ),
        ];
      }
    }

    final loadedBaseColorTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.baseColor),
      address,
      slot: MaterialTextureSlot.baseColor,
      textureContent: flutter_scene.TextureContent.color,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.baseColor],
    );
    final loadedMetallicRoughnessTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.metallicRoughness),
      address,
      slot: MaterialTextureSlot.metallicRoughness,
      textureContent: flutter_scene.TextureContent.data,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.metallicRoughness],
    );
    final loadedNormalTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.normal),
      address,
      slot: MaterialTextureSlot.normal,
      textureContent: flutter_scene.TextureContent.normal,
      normalMapScale: usesRawNormalTexture ? null : patch.normalScale,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.normal],
    );
    final loadedEmissiveTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.emissive),
      address,
      slot: MaterialTextureSlot.emissive,
      textureContent: flutter_scene.TextureContent.color,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.emissive],
    );
    final loadedOcclusionTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.occlusion),
      address,
      slot: MaterialTextureSlot.occlusion,
      textureContent: flutter_scene.TextureContent.data,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.occlusion],
    );
    final loadedSpecularTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.specular),
      address,
      slot: MaterialTextureSlot.specular,
      textureContent: flutter_scene.TextureContent.data,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.specular],
    );
    final loadedSpecularColorTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.specularColor),
      address,
      slot: MaterialTextureSlot.specularColor,
      textureContent: flutter_scene.TextureContent.color,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.specularColor],
    );
    final loadedTransmissionTexture = packageLocalTransmissionZeroBypass
        ? null
        : await _loadTextureOverride(
            patch.textureBindingFor(MaterialTextureSlot.transmission),
            address,
            slot: MaterialTextureSlot.transmission,
            textureContent: flutter_scene.TextureContent.data,
            bindingPlan: textureBindingPlans[MaterialTextureSlot.transmission],
          );
    final loadedThicknessTexture = packageLocalTransmissionZeroBypass
        ? null
        : await _loadTextureOverride(
            patch.textureBindingFor(MaterialTextureSlot.thickness),
            address,
            slot: MaterialTextureSlot.thickness,
            textureContent: flutter_scene.TextureContent.data,
            bindingPlan: textureBindingPlans[MaterialTextureSlot.thickness],
          );
    final loadedClearcoatTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.clearcoat),
      address,
      slot: MaterialTextureSlot.clearcoat,
      textureContent: flutter_scene.TextureContent.data,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.clearcoat],
    );
    final loadedClearcoatRoughnessTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.clearcoatRoughness),
      address,
      slot: MaterialTextureSlot.clearcoatRoughness,
      textureContent: flutter_scene.TextureContent.data,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.clearcoatRoughness],
    );
    final loadedClearcoatNormalTexture = await _loadTextureOverride(
      patch.textureBindingFor(MaterialTextureSlot.clearcoatNormal),
      address,
      slot: MaterialTextureSlot.clearcoatNormal,
      textureContent: flutter_scene.TextureContent.normal,
      bindingPlan: textureBindingPlans[MaterialTextureSlot.clearcoatNormal],
    );
    for (final loadedTexture in <_TextureLoadResult?>[
      loadedBaseColorTexture,
      loadedMetallicRoughnessTexture,
      loadedNormalTexture,
      loadedEmissiveTexture,
      loadedOcclusionTexture,
      loadedSpecularTexture,
      loadedSpecularColorTexture,
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

    if (packageLocalTransmissionZeroBypass &&
        activeTransmissionSourceMaterial != null) {
      final sceneViews = packageLocalTransmissionSceneViews;
      if (sceneViews == null) {
        return <ViewerDiagnostic>[
          _transmissionSceneViewsUnavailableDiagnostic(
            address,
            activeReset: true,
          ),
        ];
      }
      _materialExtensionBackend.resetTransmissionPatch(
        sceneViews: sceneViews,
        node: target.node,
        primitive: target.primitive,
      );
      material = target.primitive.material;
    }

    if (clearcoatManagesCoreInputs && !patch.hasClearcoatOverride) {
      final diagnostics =
          await _materialExtensionBackend.reconfigureClearcoatCoreInputs(
        node: target.node,
        primitive: target.primitive,
        address: address,
        patch: patch,
        baseColorTexture: loadedBaseColorTexture?.texture,
        normalTexture: loadedNormalTexture?.texture,
        occlusionTexture: loadedOcclusionTexture?.texture,
      );
      if (diagnostics.isNotEmpty) {
        return diagnostics;
      }
    }

    if (usesExtendedPbr) {
      final source = material as flutter_scene.PhysicallyBasedMaterial;
      final stagedSource = _copyPbrMaterial(source);
      _applyCorePbrState(
        stagedSource,
        patch,
        baseColorTexture: loadedBaseColorTexture?.texture,
        metallicRoughnessTexture: loadedMetallicRoughnessTexture?.texture,
        normalTexture: loadedNormalTexture?.texture,
        emissiveTexture: loadedEmissiveTexture?.texture,
        occlusionTexture: loadedOcclusionTexture?.texture,
        rawNormalTexture: true,
      );
      if (combinesNativeClearcoatWithExtendedPbr) {
        final diagnostics = applyNativeMaterialExtensionPatch(
          material: _FlutterSceneNativeClearcoatMaterial(stagedSource),
          patch: patch,
          support: materialExtensionSupport,
          clearcoatTexture: loadedClearcoatTexture?.texture,
          clearcoatRoughnessTexture: loadedClearcoatRoughnessTexture?.texture,
          clearcoatNormalTexture: loadedClearcoatNormalTexture?.texture,
        );
        if (diagnostics.isNotEmpty) {
          return diagnostics;
        }
      }
      final FlutterSceneExtendedPbrState? currentExtended =
          source is FlutterSceneExtendedPbrState
              ? source as FlutterSceneExtendedPbrState
              : null;
      final transforms = <MaterialTextureSlot, TextureTransform>{
        ...?currentExtended?.transforms,
      };
      for (final slot in _extendedPbrCoreSlots) {
        final binding = patch.textureBindingFor(slot);
        if (binding != null) {
          transforms[slot] = binding.transform;
        }
      }

      final flutter_scene.PhysicallyBasedMaterial replacement;
      try {
        final candidate = await _extendedPbrBackend.createMaterial(
          FlutterSceneExtendedPbrMaterialConfig(
            source: stagedSource,
            transforms: transforms,
            specularFactor:
                patch.specular ?? currentExtended?.specularFactor ?? 1,
            specularColorFactor: patch.specularColorFactor ??
                currentExtended?.specularColorFactor ??
                const <double>[1, 1, 1],
            ior: patch.ior ?? currentExtended?.ior ?? 1.5,
            specularFactorTexture: loadedSpecularTexture?.texture ??
                currentExtended?.specularFactorTexture,
            specularColorTexture: loadedSpecularColorTexture?.texture ??
                currentExtended?.specularColorTexture,
          ),
        );
        if (candidate is! FlutterSceneExtendedPbrState) {
          throw StateError(
            'FSViewerExtendedPbr backend returned a material without retained extension state.',
          );
        }
        replacement = candidate;
      } on Object catch (error) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedMaterialFeature,
            message:
                'FSViewerExtendedPbr material construction failed before replacement.',
            details: <String, Object?>{
              'part': address.debugPath,
              'feature': flutterSceneExtendedPbrShaderName,
              'limitation': 'extendedPbrMaterialConstructionFailed',
              'status': 'blocked',
              'materialReplaced': false,
              'encodedBytesModified': false,
              'error': error.toString(),
              'nextStep': 'verifyExtendedPbrReflectedContract',
            },
          ),
        ];
      }

      _originalMaterials.putIfAbsent(
        address,
        () => _OriginalMaterialState.capture(target.node, target.primitive),
      );
      target.primitive.material = replacement;
      if (patch.visible != null) {
        _applyPrimitiveVisibility(target, patch.visible!, address);
      }
      _refreshMountedMesh(target.node);
      return const <ViewerDiagnostic>[];
    }

    _originalMaterials.putIfAbsent(
      address,
      () => _OriginalMaterialState.capture(target.node, target.primitive),
    );

    if (patch.visible != null) {
      _applyPrimitiveVisibility(target, patch.visible!, address);
    }
    if (usesNativeMaterialExtensionApplier) {
      if (material is NativeMaterialExtensionMaterial) {
        return applyNativeMaterialExtensionPatch(
          material: material as NativeMaterialExtensionMaterial,
          patch: patch,
          support: materialExtensionSupport,
          clearcoatTexture: loadedClearcoatTexture?.texture,
          clearcoatRoughnessTexture: loadedClearcoatRoughnessTexture?.texture,
          clearcoatNormalTexture: loadedClearcoatNormalTexture?.texture,
        );
      }
      if (material is flutter_scene.PhysicallyBasedMaterial &&
          patch.hasClearcoatOverride &&
          !patch.hasGlassOverride &&
          patch.ior == null) {
        final stagedMaterial = _copyPbrMaterial(material);
        final diagnostics = applyNativeMaterialExtensionPatch(
          material: _FlutterSceneNativeClearcoatMaterial(stagedMaterial),
          patch: patch,
          support: materialExtensionSupport,
          clearcoatTexture: loadedClearcoatTexture?.texture,
          clearcoatRoughnessTexture: loadedClearcoatRoughnessTexture?.texture,
          clearcoatNormalTexture: loadedClearcoatNormalTexture?.texture,
        );
        if (diagnostics.isNotEmpty) {
          return diagnostics;
        }
        _applyCorePbrState(
          stagedMaterial,
          patch,
          baseColorTexture: loadedBaseColorTexture?.texture,
          metallicRoughnessTexture: loadedMetallicRoughnessTexture?.texture,
          normalTexture: loadedNormalTexture?.texture,
          emissiveTexture: loadedEmissiveTexture?.texture,
          occlusionTexture: loadedOcclusionTexture?.texture,
          rawNormalTexture: true,
        );
        target.primitive.material = stagedMaterial;
        _refreshMountedMesh(target.node);
        return const <ViewerDiagnostic>[];
      }
      return <ViewerDiagnostic>[_nativeMaterialContractUnavailable(address)];
    }
    if (patch.hasGlassOverride && !packageLocalTransmissionZeroBypass) {
      if (material is! flutter_scene.PhysicallyBasedMaterial) {
        return <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedMaterialFeature,
            message: 'Transmission/glass overrides require a PBR material.',
            details: <String, Object?>{'part': address.debugPath},
          ),
        ];
      }
      final sceneViews = packageLocalTransmissionSceneViews;
      if (sceneViews == null) {
        return <ViewerDiagnostic>[
          _transmissionSceneViewsUnavailableDiagnostic(
            address,
            activeReset: false,
          ),
        ];
      }
      return _materialExtensionBackend.applyTransmissionPatch(
        sceneViews: sceneViews,
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
      final diagnostics = await _materialExtensionBackend.applyClearcoatPatch(
        node: target.node,
        primitive: target.primitive,
        address: address,
        patch: patch,
        baseColorTexture: loadedBaseColorTexture?.texture,
        metallicRoughnessTexture: loadedMetallicRoughnessTexture?.texture,
        normalTexture: loadedNormalTexture?.texture,
        occlusionTexture: loadedOcclusionTexture?.texture,
        emissiveTexture: loadedEmissiveTexture?.texture,
        clearcoatTexture: loadedClearcoatTexture?.texture,
        clearcoatRoughnessTexture: loadedClearcoatRoughnessTexture?.texture,
        clearcoatNormalTexture: loadedClearcoatNormalTexture?.texture,
      );
      if (diagnostics.isNotEmpty) {
        return diagnostics;
      }
    }
    var refreshMountedMesh = false;
    if (material is flutter_scene.PhysicallyBasedMaterial &&
        _requiresPbrFamilyReplacement(family, patch)) {
      if (material is! NativeMaterialExtensionMaterial) {
        material = _copyPbrMaterial(material);
        target.primitive.material = material;
      }
      refreshMountedMesh = true;
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
      if (patch.textureBindingFor(MaterialTextureSlot.normal) != null &&
          patch.normalScale != null) {
        material.normalScale = usesRawNormalTexture ? patch.normalScale! : 1.0;
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
    if (refreshMountedMesh) {
      _refreshMountedMesh(target.node);
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
      return _resolveUniqueDescendantTarget(root, address);
    }
    return _resolveTargetFrom(
          root,
          address.nodePath.skip(1),
          primitiveIndex: address.primitiveIndex,
        ) ??
        _resolveUniqueDescendantTarget(root, address);
  }

  _ResolvedPrimitive? _resolveTargetFrom(
    flutter_scene.Node start,
    Iterable<String> pathSegments, {
    required int primitiveIndex,
  }) {
    var node = start;
    for (final segment in pathSegments) {
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
        primitiveIndex < 0 ||
        primitiveIndex >= primitives.length) {
      return null;
    }
    return _ResolvedPrimitive(node, primitives[primitiveIndex]);
  }

  _ResolvedPrimitive? _resolveUniqueDescendantTarget(
    flutter_scene.Node root,
    PartAddress address,
  ) {
    final matches = <flutter_scene.Node>[];

    void visit(flutter_scene.Node node) {
      if (node.name == address.nodePath.first) {
        final resolved = _resolveTargetFrom(
          node,
          address.nodePath.skip(1),
          primitiveIndex: address.primitiveIndex,
        );
        if (resolved != null) {
          matches.add(resolved.node);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    if (matches.length != 1) {
      return null;
    }
    return _resolveTargetFrom(
      matches.single,
      const <String>[],
      primitiveIndex: address.primitiveIndex,
    );
  }

  void _applyPrimitiveVisibility(
    _ResolvedPrimitive target,
    bool visible,
    PartAddress address,
  ) {
    if (!visible) {
      target.primitive.geometry = _HiddenPrimitiveGeometry.instance;
      _refreshMountedMesh(target.node);
      return;
    }
    final original = _originalMaterials[address];
    if (original != null) {
      target.primitive.geometry = original.geometry;
      _refreshMountedMesh(target.node);
    }
  }

  void _refreshMountedMesh(flutter_scene.Node node) {
    final mesh = node.mesh;
    if (mesh == null) {
      return;
    }
    node.mesh = flutter_scene.Mesh.primitives(
      primitives: List<flutter_scene.MeshPrimitive>.of(mesh.primitives),
    );
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
      // ignore: invalid_use_of_internal_member
      ..clearcoatTexture = source.clearcoatTextureSource
      ..clearcoatFactor = source.clearcoatFactor
      // ignore: invalid_use_of_internal_member
      ..clearcoatRoughnessTexture = source.clearcoatRoughnessTextureSource
      ..clearcoatRoughnessFactor = source.clearcoatRoughnessFactor
      // ignore: invalid_use_of_internal_member
      ..clearcoatNormalTexture = source.clearcoatNormalTextureSource
      ..clearcoatNormalScale = source.clearcoatNormalScale
      ..environment = source.environment
      ..alphaMode = source.alphaMode
      ..alphaCutoff = source.alphaCutoff
      ..vertexColorWeight = source.vertexColorWeight
      ..doubleSided = source.doubleSided
      ..specularAntiAliasingVariance = source.specularAntiAliasingVariance
      ..specularAntiAliasingThreshold = source.specularAntiAliasingThreshold;
    return material;
  }

  void _applyCorePbrState(
    flutter_scene.PhysicallyBasedMaterial material,
    MaterialPatch patch, {
    flutter_scene.TextureSource? baseColorTexture,
    flutter_scene.TextureSource? metallicRoughnessTexture,
    flutter_scene.TextureSource? normalTexture,
    flutter_scene.TextureSource? emissiveTexture,
    flutter_scene.TextureSource? occlusionTexture,
    required bool rawNormalTexture,
  }) {
    if (patch.baseColorFactor != null) {
      material.baseColorFactor = _vector4(patch.baseColorFactor!);
    }
    if (baseColorTexture != null) {
      material.baseColorTexture = baseColorTexture;
    }
    if (metallicRoughnessTexture != null) {
      material.metallicRoughnessTexture = metallicRoughnessTexture;
    }
    if (normalTexture != null) {
      material.normalTexture = normalTexture;
    }
    if (patch.textureBindingFor(MaterialTextureSlot.normal) != null &&
        patch.normalScale != null) {
      material.normalScale = rawNormalTexture ? patch.normalScale! : 1;
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
    if (emissiveTexture != null) {
      material.emissiveTexture = emissiveTexture;
    }
    if (occlusionTexture != null) {
      material.occlusionTexture = occlusionTexture;
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
  }

  Future<_TextureLoadResult?> _loadTextureOverride(
    MaterialTextureBinding? binding,
    PartAddress address, {
    required MaterialTextureSlot slot,
    required flutter_scene.TextureContent textureContent,
    double? normalMapScale,
    FlutterSceneTextureBindingPlan? bindingPlan,
  }) async {
    if (binding == null) {
      return null;
    }
    final plan =
        bindingPlan ?? _flutterSceneTextureBindingPlan(binding, slot, address);
    final planDiagnostic = plan.diagnostic;
    if (planDiagnostic != null) {
      return _TextureLoadResult(diagnostic: planDiagnostic);
    }
    final sampling = plan.sampling!;
    final source = binding.source;
    try {
      final texture = normalMapScale == null || normalMapScale == 1
          ? await _loadTexture(
              source,
              content: textureContent,
              sampling: sampling,
            )
          : await _loadScaledNormalTexture(
              source,
              normalMapScale,
              sampling: sampling,
            );
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

  Future<flutter_scene.TextureSource> _loadTexture(
    TextureSource source, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    return switch (source) {
      AssetTextureSource(:final assetPath) => await _textureFactory.fromAsset(
          assetPath,
          content: content,
          sampling: sampling,
        ),
      BytesTextureSource(:final encodedBytes) => await _textureFromEncodedBytes(
          encodedBytes,
          content: content,
          sampling: sampling,
        ),
      NetworkTextureSource(:final uri, :final headers) =>
        await _loadNetworkTexture(
          uri,
          headers,
          content: content,
          sampling: sampling,
        ),
    };
  }

  Future<flutter_scene.TextureSource> _loadScaledNormalTexture(
    TextureSource source,
    double scale, {
    required flutter_scene.TextureSampling sampling,
  }) async {
    final encodedBytes = await _loadEncodedTextureBytes(source);
    final image = await flutter_scene.imageFromBytes(encodedBytes);
    try {
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        throw StateError('Unable to read normal texture pixels.');
      }
      final rgba = Uint8List.fromList(
        byteData.buffer
            .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      );
      final scaled = scaleNormalMapRgba(rgba, scale);
      return _textureFactory.fromPixels(
        scaled,
        image.width,
        image.height,
        content: flutter_scene.TextureContent.normal,
        sampling: sampling,
      );
    } finally {
      image.dispose();
    }
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

  Future<flutter_scene.TextureSource> _textureFromEncodedBytes(
    Uint8List bytes, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    final image = await flutter_scene.imageFromBytes(bytes);
    try {
      return await _textureFactory.fromImage(
        image,
        content: content,
        sampling: sampling,
      );
    } finally {
      image.dispose();
    }
  }

  Future<flutter_scene.TextureSource> _loadNetworkTexture(
    Uri uri,
    Map<String, String> headers, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    final bodyBytes = await _loadNetworkTextureBytes(uri, headers);
    return _textureFromEncodedBytes(
      bodyBytes,
      content: content,
      sampling: sampling,
    );
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

  ViewerDiagnostic _transmissionSceneViewsUnavailableDiagnostic(
    PartAddress address, {
    required bool activeReset,
  }) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.adapterFailure,
      message: activeReset
          ? 'Cannot restore an active transmission patch without its scene-view collection.'
          : 'Cannot apply transmission/glass before a scene-view collection is available.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'transmission',
        'limitation': activeReset
            ? 'activeTransmissionSceneViewsUnavailable'
            : 'transmissionApplySceneViewsUnavailable',
        'status': 'blocked',
        'nextStep': activeReset
            ? 'replayWithTheOriginalSceneViewsCollection'
            : 'loadTheSceneBeforeApplyingTransmission',
      },
    );
  }

  ViewerDiagnostic? _transmissionCoreInputsUnsupportedDiagnostic(
    PartAddress address,
    MaterialPatch patch, {
    required flutter_scene.PhysicallyBasedMaterial? sourceMaterial,
  }) {
    final fieldOrigins = <String, String>{};
    void addPatchField(String field, bool present) {
      if (present) {
        fieldOrigins[field] = 'incomingPatch';
      }
    }

    addPatchField('metallic', patch.metallic != null);
    addPatchField(
      'metallicRoughnessTexture',
      patch.textureBindingFor(MaterialTextureSlot.metallicRoughness) != null,
    );
    addPatchField(
      'occlusionTexture',
      patch.textureBindingFor(MaterialTextureSlot.occlusion) != null,
    );
    addPatchField('occlusionStrength', patch.occlusionStrength != null);
    addPatchField('emissiveFactor', patch.emissiveFactor != null);
    addPatchField(
      'emissiveTexture',
      patch.textureBindingFor(MaterialTextureSlot.emissive) != null,
    );
    addPatchField('alphaMode', patch.alphaMode != null);
    addPatchField('alphaCutoff', patch.alphaCutoff != null);

    if (sourceMaterial != null) {
      void addSourceField(String field, bool present) {
        if (present) {
          fieldOrigins.putIfAbsent(field, () => 'sourceMaterial');
        }
      }

      addSourceField(
        'metallic',
        patch.metallic == null && sourceMaterial.metallicFactor != 0.0,
      );
      addSourceField(
        'roughness',
        patch.roughness == null && sourceMaterial.roughnessFactor != 0.0,
      );
      final sourceMetallicRoughness = sourceMaterial.metallicRoughnessTexture;
      addSourceField(
        'metallicRoughnessTexture',
        patch.textureBindingFor(MaterialTextureSlot.metallicRoughness) ==
                null &&
            sourceMetallicRoughness != null,
      );
      final sourceOcclusion = sourceMaterial.occlusionTexture;
      addSourceField(
        'occlusionTexture',
        patch.textureBindingFor(MaterialTextureSlot.occlusion) == null &&
            sourceOcclusion != null,
      );
      addSourceField(
        'occlusionStrength',
        patch.occlusionStrength == null &&
            (sourceOcclusion != null ||
                sourceMaterial.occlusionStrength != 1.0),
      );
      addSourceField(
        'emissiveFactor',
        patch.emissiveFactor == null &&
            (sourceMaterial.emissiveFactor.x != 0.0 ||
                sourceMaterial.emissiveFactor.y != 0.0 ||
                sourceMaterial.emissiveFactor.z != 0.0),
      );
      final sourceEmissive = sourceMaterial.emissiveTexture;
      addSourceField(
        'emissiveTexture',
        patch.textureBindingFor(MaterialTextureSlot.emissive) == null &&
            sourceEmissive != null,
      );
      final sourceUsesAlphaMask =
          sourceMaterial.alphaMode == flutter_scene.AlphaMode.mask;
      addSourceField(
        'alphaMode',
        patch.alphaMode == null &&
            sourceMaterial.alphaMode != flutter_scene.AlphaMode.opaque,
      );
      addSourceField(
        'alphaCutoff',
        patch.alphaCutoff == null && sourceUsesAlphaMask,
      );
    }

    if (fieldOrigins.isEmpty) {
      return null;
    }
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The flutter_scene transmission shader backend cannot consume every active core PBR field alongside transmission atomically.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'transmission',
        'limitation': 'transmissionCoreInputsUnsupported',
        'fields': List<String>.unmodifiable(fieldOrigins.keys),
        'fieldOrigins': Map<String, String>.unmodifiable(fieldOrigins),
        'backendKind': materialExtensionSupport.backendKind.name,
        'status': 'unsupported',
        'nextStep': 'useRendererContractWithCombinedCoreTransmissionSupport',
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

  ViewerDiagnostic _packageLocalExtensionVisibilityUnsupported(
    PartAddress address,
  ) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Package-local material extension patches cannot change primitive visibility atomically.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'visibility',
        'limitation': 'packageLocalExtensionVisibilityUnsupported',
        'fields': const <String>['visible'],
        'backendKind': materialExtensionSupport.backendKind.name,
        'status': 'unsupported',
        'nextStep': 'applyVisibilityAsASeparatePatchAfterMaterialSuccess',
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

  ViewerDiagnostic _nativeMaterialContractUnavailable(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Production material extension support was advertised, but the target material does not expose the native material extension contract.',
      details: <String, Object?>{
        'part': address.debugPath,
        'backendKind': MaterialExtensionBackendKind.rendererNative.name,
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

final class _FlutterSceneNativeClearcoatMaterial
    implements NativeMaterialExtensionMaterial {
  _FlutterSceneNativeClearcoatMaterial(this.material);

  final flutter_scene.PhysicallyBasedMaterial material;

  @override
  set clearcoatFactor(double value) => material.clearcoatFactor = value;

  @override
  set clearcoatRoughnessFactor(double value) =>
      material.clearcoatRoughnessFactor = value;

  @override
  set clearcoatNormalScale(double value) =>
      material.clearcoatNormalScale = value;

  @override
  set clearcoatTexture(Object? value) =>
      material.clearcoatTexture = value as flutter_scene.TextureSource?;

  @override
  set clearcoatRoughnessTexture(Object? value) =>
      material.clearcoatRoughnessTexture =
          value as flutter_scene.TextureSource?;

  @override
  set clearcoatNormalTexture(Object? value) =>
      material.clearcoatNormalTexture = value as flutter_scene.TextureSource?;

  @override
  set transmissionFactor(double value) =>
      throw UnsupportedError('Renderer-native transmission is unavailable.');

  @override
  set ior(double value) =>
      throw UnsupportedError('Renderer-native IOR is unavailable.');

  @override
  set thicknessFactor(double value) =>
      throw UnsupportedError('Renderer-native volume is unavailable.');

  @override
  set attenuationDistance(double value) =>
      throw UnsupportedError('Renderer-native volume is unavailable.');

  @override
  set attenuationColor(List<double> value) =>
      throw UnsupportedError('Renderer-native volume is unavailable.');
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
    required this.geometry,
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
        geometry: primitive.geometry,
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
        geometry: primitive.geometry,
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
      geometry: primitive.geometry,
      material: material,
    );
  }

  final bool visible;
  final int layers;
  final flutter_scene.Geometry geometry;
  final flutter_scene.Material material;
  final vm.Vector4? baseColorFactor;
  final flutter_scene.TextureSource? baseColorTexture;
  final flutter_scene.TextureSource? metallicRoughnessTexture;
  final flutter_scene.TextureSource? normalTexture;
  final double? normalScale;
  final double? metallic;
  final double? roughness;
  final vm.Vector4? emissiveFactor;
  final flutter_scene.TextureSource? emissiveTexture;
  final flutter_scene.TextureSource? occlusionTexture;
  final double? occlusionStrength;
  final flutter_scene.AlphaMode? alphaMode;
  final double? alphaCutoff;
  final vm.Vector4? unlitBaseColorFactor;
  final flutter_scene.TextureSource? unlitBaseColorTexture;
  final flutter_scene.AlphaMode? unlitAlphaMode;

  void restore(
    flutter_scene.Node node,
    flutter_scene.MeshPrimitive primitive,
  ) {
    node.visible = visible;
    node.layers = layers;
    primitive.geometry = geometry;
    primitive.material = material;
    final mesh = node.mesh;
    if (mesh != null) {
      node.mesh = flutter_scene.Mesh.primitives(
        primitives: List<flutter_scene.MeshPrimitive>.of(mesh.primitives),
      );
    }
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

final class _HiddenPrimitiveGeometry {
  _HiddenPrimitiveGeometry._();

  static final flutter_scene.Geometry instance = _create();

  static flutter_scene.Geometry _create() {
    try {
      final geometry = flutter_scene.MeshGeometry.fromArrays(
        positions: Float32List.fromList(<double>[
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
        normals: Float32List.fromList(<double>[
          0,
          0,
          1,
          0,
          0,
          1,
          0,
          0,
          1,
        ]),
        texCoords: Float32List(6),
      );
      geometry.setLocalBounds(null, null);
      return geometry;
    } on Exception {
      return _NoopHiddenPrimitiveGeometry();
    }
  }
}

final class _NoopHiddenPrimitiveGeometry extends flutter_scene.Geometry {
  @override
  void bind(
    flutter_scene_gpu.RenderPass pass,
    flutter_scene_gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    flutter_scene_gpu.Shader? shaderOverride,
  }) {}
}

final class _TextureLoadResult {
  const _TextureLoadResult({this.texture, this.diagnostic});

  final flutter_scene.TextureSource? texture;
  final ViewerDiagnostic? diagnostic;
}

typedef FlutterSceneTextureBindingPlan = ({
  flutter_scene.TextureSampling? sampling,
  ViewerDiagnostic? diagnostic,
});

FlutterSceneTextureBindingPlan _flutterSceneTextureBindingPlan(
  MaterialTextureBinding binding,
  MaterialTextureSlot slot,
  PartAddress address, {
  bool allowExtendedPbrCoreTransform = false,
}) {
  final diagnostic = flutterSceneTextureBindingDiagnostic(
    address: address,
    slot: slot,
    binding: binding,
    allowExtendedPbrCoreTransform: allowExtendedPbrCoreTransform,
  );
  if (diagnostic != null) {
    return (sampling: null, diagnostic: diagnostic);
  }
  return (
    sampling: _flutterSceneTextureSampling(binding.sampler),
    diagnostic: null,
  );
}

flutter_scene.TextureSampling _flutterSceneTextureSampling(
  TextureSampler sampler,
) {
  var minFilter = flutter_scene_gpu.MinMagFilter.linear;
  var mipFilter = flutter_scene_gpu.MipFilter.linear;
  var mipmaps = true;
  switch (sampler.minFilter) {
    case null:
      break;
    case TextureMinFilter.nearest:
      minFilter = flutter_scene_gpu.MinMagFilter.nearest;
      mipFilter = flutter_scene_gpu.MipFilter.nearest;
      mipmaps = false;
    case TextureMinFilter.linear:
      minFilter = flutter_scene_gpu.MinMagFilter.linear;
      mipFilter = flutter_scene_gpu.MipFilter.nearest;
      mipmaps = false;
    case TextureMinFilter.nearestMipmapNearest:
      minFilter = flutter_scene_gpu.MinMagFilter.nearest;
      mipFilter = flutter_scene_gpu.MipFilter.nearest;
    case TextureMinFilter.linearMipmapNearest:
      minFilter = flutter_scene_gpu.MinMagFilter.linear;
      mipFilter = flutter_scene_gpu.MipFilter.nearest;
    case TextureMinFilter.nearestMipmapLinear:
      minFilter = flutter_scene_gpu.MinMagFilter.nearest;
      mipFilter = flutter_scene_gpu.MipFilter.linear;
    case TextureMinFilter.linearMipmapLinear:
      minFilter = flutter_scene_gpu.MinMagFilter.linear;
      mipFilter = flutter_scene_gpu.MipFilter.linear;
  }
  return flutter_scene.TextureSampling(
    mipmaps: mipmaps,
    minFilter: minFilter,
    magFilter: switch (sampler.magFilter) {
      null || TextureMagFilter.linear => flutter_scene_gpu.MinMagFilter.linear,
      TextureMagFilter.nearest => flutter_scene_gpu.MinMagFilter.nearest,
    },
    mipFilter: mipFilter,
    addressMode: switch (sampler.wrapS) {
      TextureWrapMode.clampToEdge =>
        flutter_scene_gpu.SamplerAddressMode.clampToEdge,
      TextureWrapMode.mirroredRepeat =>
        flutter_scene_gpu.SamplerAddressMode.mirror,
      TextureWrapMode.repeat => flutter_scene_gpu.SamplerAddressMode.repeat,
    },
  );
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

const List<MaterialTextureSlot> _extendedPbrCoreSlots = <MaterialTextureSlot>[
  MaterialTextureSlot.baseColor,
  MaterialTextureSlot.metallicRoughness,
  MaterialTextureSlot.normal,
  MaterialTextureSlot.occlusion,
  MaterialTextureSlot.emissive,
];

bool _usesExtendedPbrFor(
  flutter_scene.Material material,
  MaterialPatch patch,
) =>
    material is FlutterSceneExtendedPbrState ||
    patch.hasSpecularOverride ||
    patch.hasOpaqueIorOverride ||
    _extendedPbrCoreSlots.any((slot) {
      final binding = patch.textureBindingFor(slot);
      return binding != null && !_isIdentityTransform(binding.transform);
    });

bool _isIdentityTransform(TextureTransform transform) =>
    transform.offsetX == 0 &&
    transform.offsetY == 0 &&
    transform.scaleX == 1 &&
    transform.scaleY == 1 &&
    transform.rotation == 0;

ViewerDiagnostic _extendedPbrCombinationUnavailable(
  PartAddress address,
  MaterialPatch patch,
) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'FSViewerExtendedPbr does not implement clearcoat or transmission/volume in this bounded slice.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': flutterSceneExtendedPbrShaderName,
        'limitation': 'extendedPbrLayeredMaterialCombinationUnsupported',
        'clearcoat': patch.hasClearcoatOverride,
        'transmissionVolume': patch.hasGlassOverride,
        'status': 'blocked',
        'materialReplaced': false,
        'nextStep': 'useSeparatelyAcceptedLayeredMaterialBackend',
      },
    );

bool _hasPackageLocalClearcoatConsumedCoreIntent(MaterialPatch patch) =>
    patch.baseColorFactor != null ||
    patch.textureBindingFor(MaterialTextureSlot.baseColor) != null ||
    patch.textureBindingFor(MaterialTextureSlot.normal) != null ||
    patch.textureBindingFor(MaterialTextureSlot.occlusion) != null;

ViewerDiagnostic? _pinnedStandardPbrExtensionDiagnostic(
  PartAddress address,
  MaterialPatch patch, {
  required MaterialExtensionBackendKind backendKind,
  required bool usesNativeMaterialExtensionApplier,
  required bool usesExtendedPbr,
  bool? hasEffectiveOpaqueIorIntent,
}) {
  if (usesNativeMaterialExtensionApplier || usesExtendedPbr) {
    return null;
  }
  if (patch.hasSpecularOverride) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The pinned flutter_scene standard PBR path cannot consume KHR_materials_specular intent.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'specular',
        'extensions': const <String>['KHR_materials_specular'],
        'limitation': 'pinnedStandardPbrSpecularContractMissing',
        'backendKind': backendKind.name,
        'upstreamPackage': 'flutter_scene',
        'upstreamRevision': 'ccf7372428961ebe0abb053727fe443150547a74',
        'status': 'unsupported',
        'productionBlocker': 'rendererNativeSpecularContractMissing',
        'nextStep': 'implementRendererNativeSpecularContract',
      },
    );
  }
  if (hasEffectiveOpaqueIorIntent ?? patch.hasOpaqueIorOverride) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The pinned flutter_scene standard PBR path cannot consume opaque KHR_materials_ior intent.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'opaqueIor',
        'extensions': const <String>['KHR_materials_ior'],
        'limitation': 'pinnedStandardPbrOpaqueIorContractMissing',
        'backendKind': backendKind.name,
        'upstreamPackage': 'flutter_scene',
        'upstreamRevision': 'ccf7372428961ebe0abb053727fe443150547a74',
        'status': 'unsupported',
        'productionBlocker': 'rendererNativeOpaqueIorContractMissing',
        'nextStep': 'implementRendererNativeOpaqueIorContract',
      },
    );
  }
  return null;
}

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
      ViewerMaterialExtensionMode.productionFlutterSceneShaders) {
    if (support == null) {
      return false;
    }
    if (resolvedSupport.backendKind !=
        MaterialExtensionBackendKind.flutterSceneCustomShader) {
      return false;
    }
  }
  if (patch.hasClearcoatOverride) {
    return resolvedSupport
        .supportFor(MaterialExtensionFeature.clearcoat)
        .available;
  }
  if (!patch.hasGlassOverride) {
    return false;
  }
  final transmissionBinding =
      patch.textureBindingFor(MaterialTextureSlot.transmission);
  final thicknessBinding =
      patch.textureBindingFor(MaterialTextureSlot.thickness);
  return ((patch.transmission == null && transmissionBinding == null) ||
          resolvedSupport
              .supportFor(MaterialExtensionFeature.transmission)
              .available) &&
      (patch.ior == null ||
          resolvedSupport.supportFor(MaterialExtensionFeature.ior).available) &&
      ((patch.thickness == null &&
              thicknessBinding == null &&
              patch.attenuationColor == null &&
              patch.attenuationDistance == null) ||
          resolvedSupport
              .supportFor(MaterialExtensionFeature.volume)
              .available);
}

bool _usesNativeMaterialExtensionApplierFor(
  ViewerMaterialExtensionPolicy policy,
  MaterialPatch patch, {
  MaterialExtensionSupport? support,
}) {
  if (!hasNativeMaterialExtensionIntent(patch)) {
    return false;
  }
  final resolvedSupport = support ?? policy.support;
  return policy.mode ==
          ViewerMaterialExtensionMode.productionFlutterSceneShaders &&
      resolvedSupport.backendKind ==
          MaterialExtensionBackendKind.rendererNative &&
      supportsNativeMaterialExtensionPatch(resolvedSupport, patch);
}

MaterialExtensionSupport _resolveProductionMaterialExtensionSupport(
  NativeMaterialExtensionCapability nativeCapability, [
  MaterialExtensionPreflightResult shaderPreflight =
      const MaterialExtensionPreflightResult(
    support: MaterialExtensionSupport.unsupported,
  ),
]) {
  final support = nativeCapability.support;
  if (support.backendKind == MaterialExtensionBackendKind.rendererNative &&
      _hasAvailableMaterialExtensionBackendFeatures(support)) {
    return support;
  }
  final shaderSupport = shaderPreflight.support;
  return shaderSupport.backendKind ==
              MaterialExtensionBackendKind.flutterSceneCustomShader &&
          _hasAvailableMaterialExtensionBackendFeatures(shaderSupport)
      ? shaderSupport
      : MaterialExtensionSupport.unsupported;
}

bool _hasAvailableMaterialExtensionBackendFeatures(
  MaterialExtensionSupport support,
) =>
    const <MaterialExtensionFeature>{
      MaterialExtensionFeature.transmission,
      MaterialExtensionFeature.ior,
      MaterialExtensionFeature.volume,
      MaterialExtensionFeature.clearcoat,
    }.any((feature) => support.supportFor(feature).available);

MaterialExtensionSupport _withExtendedPbrSupport(
  MaterialExtensionSupport base,
) {
  final candidate = MaterialExtensionFeatureSupport(
    available: true,
    maturityByTarget: <MaterialExtensionTarget, MaterialExtensionMaturity>{
      for (final target in MaterialExtensionTarget.values)
        target: MaterialExtensionMaturity.candidateOnly,
    },
  );
  return MaterialExtensionSupport(
    backendKind: base.backendKind == MaterialExtensionBackendKind.none
        ? MaterialExtensionBackendKind.flutterSceneCustomShader
        : base.backendKind,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      ...base.features,
      MaterialExtensionFeature.specular: candidate,
      MaterialExtensionFeature.ior: candidate,
    },
    claimedReleaseTargets: base.claimedReleaseTargets,
  );
}

@visibleForTesting
flutter_scene.AlphaMode debugFlutterSceneAlphaModeFor(
  MaterialAlphaMode alphaMode,
) =>
    _alphaMode(alphaMode);

@visibleForTesting
FlutterSceneTextureBindingPlan debugFlutterSceneTextureBindingPlan(
  MaterialTextureBinding binding,
  MaterialTextureSlot slot,
) =>
    _flutterSceneTextureBindingPlan(
      binding,
      slot,
      PartAddress(nodePath: const <String>['debug'], primitiveIndex: 0),
    );

@visibleForTesting
Future<List<ViewerDiagnostic>> debugLoadTextureBinding(
  MaterialTextureBinding binding,
  MaterialTextureSlot slot, {
  required flutter_scene.TextureContent textureContent,
  double? normalMapScale,
  required FlutterSceneTextureFactory textureFactory,
}) async {
  final adapter = FlutterSceneRuntimeAdapter(textureFactory: textureFactory);
  final result = await adapter._loadTextureOverride(
    binding,
    PartAddress(nodePath: const <String>['debug'], primitiveIndex: 0),
    slot: slot,
    textureContent: textureContent,
    normalMapScale: normalMapScale,
  );
  final diagnostic = result?.diagnostic;
  return diagnostic == null
      ? const <ViewerDiagnostic>[]
      : <ViewerDiagnostic>[diagnostic];
}

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
bool debugUsesNativeMaterialExtensionApplierFor(
  ViewerMaterialExtensionPolicy policy,
  MaterialPatch patch, {
  MaterialExtensionSupport? support,
}) =>
    _usesNativeMaterialExtensionApplierFor(policy, patch, support: support);

@visibleForTesting
MaterialExtensionSupport debugResolveProductionMaterialExtensionSupport(
  NativeMaterialExtensionCapability nativeCapability, [
  MaterialExtensionPreflightResult shaderPreflight =
      const MaterialExtensionPreflightResult(
    support: MaterialExtensionSupport.unsupported,
  ),
]) =>
    _resolveProductionMaterialExtensionSupport(
      nativeCapability,
      shaderPreflight,
    );

@visibleForTesting
ViewerDiagnostic? debugGlassNodeIsolationDiagnostic({
  required int primitiveCount,
  required int selectedPrimitiveIndex,
}) =>
    _glassNodeIsolationDiagnostic(
      primitiveCount: primitiveCount,
      selectedPrimitiveIndex: selectedPrimitiveIndex,
    );

@visibleForTesting
bool debugCanResolvePartAddress(
  flutter_scene.Node root,
  PartAddress address,
) {
  final adapter = FlutterSceneRuntimeAdapter().._rootNode = root;
  return adapter._resolveTarget(address) != null;
}

@visibleForTesting
Future<List<ViewerDiagnostic>> debugApplyMaterialPatchToRoot(
  flutter_scene.Node root,
  PartAddress address,
  MaterialPatch patch, {
  ViewerMaterialExtensionPolicy materialExtensionPolicy =
      const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
  FlutterSceneMaterialExtensionBackend? materialExtensionBackend,
  MaterialExtensionSupport? materialExtensionSupport,
  flutter_scene.Scene? materialExtensionScene,
  List<flutter_scene.RenderView>? materialExtensionSceneViews,
  FlutterSceneTextureFactory? textureFactory,
  FlutterSceneRuntimeAdapter? runtimeAdapter,
}) {
  final adapter = runtimeAdapter ??
      FlutterSceneRuntimeAdapter(
        materialExtensionPolicy: materialExtensionPolicy,
        materialExtensionBackend: materialExtensionBackend,
        textureFactory: textureFactory,
      );
  adapter
    .._rootNode = root
    .._scene = materialExtensionScene
    .._materialExtensionSceneViewsForTesting = materialExtensionSceneViews;
  if (materialExtensionSupport != null) {
    adapter._productionMaterialExtensionSupport = materialExtensionSupport;
  }
  return adapter.applyMaterialPatch(address, patch);
}

final class FlutterSceneAdapterUnavailableException implements Exception {
  const FlutterSceneAdapterUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}
