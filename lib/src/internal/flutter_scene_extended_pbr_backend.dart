import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu_public;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;

import '../diagnostics.dart';
import '../part_address.dart';
import '../texture_binding.dart';
import 'flutter_scene_extended_pbr_material.dart';

typedef LoadFlutterSceneExtendedPbrShader = Future<flutter_scene_gpu.Shader?>
    Function(String assetPath, String shaderName);

final class FlutterSceneExtendedPbrMaterialConfig {
  FlutterSceneExtendedPbrMaterialConfig({
    required this.source,
    this.transforms = const <MaterialTextureSlot, TextureTransform>{},
    this.specularFactor = 1,
    this.specularColorFactor = const <double>[1, 1, 1],
    this.ior = 1.5,
    this.specularFactorTexture,
    this.specularColorTexture,
  });

  final flutter_scene.PhysicallyBasedMaterial source;
  final Map<MaterialTextureSlot, TextureTransform> transforms;
  final double specularFactor;
  final List<double> specularColorFactor;
  final double ior;
  final flutter_scene.TextureSource? specularFactorTexture;
  final flutter_scene.TextureSource? specularColorTexture;
}

abstract interface class FlutterSceneExtendedPbrMaterialBackend {
  bool get isReady;

  Future<ViewerDiagnostic?> preflight(PartAddress address);

  /// Returns a PBR material that also implements [FlutterSceneExtendedPbrState].
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  );
}

/// Loads, validates, and constructs the bounded FSViewerExtendedPbr material.
final class FlutterSceneExtendedPbrBackend
    implements FlutterSceneExtendedPbrMaterialBackend {
  FlutterSceneExtendedPbrBackend({
    LoadFlutterSceneExtendedPbrShader? loadShader,
  }) : _loadShader = loadShader ?? _loadShaderFromBundle;

  static const String shaderName = flutterSceneExtendedPbrShaderName;
  static const String clearcoatShaderName =
      flutterSceneClearcoatExtendedPbrShaderName;
  static const List<String> shaderBundleAssets = <String>[
    'flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  ];

  static List<String> _requiredUniformSlots(String shaderName) => <String>[
        'FragInfo',
        flutterSceneExtendedPbrUniformBlockName,
        'FogInfo',
        'RadianceLayoutInfo',
        'base_color_texture',
        'emissive_texture',
        'metallic_roughness_texture',
        'normal_texture',
        'occlusion_texture',
        if (shaderName == clearcoatShaderName) ...<String>[
          'clearcoat_texture',
          'clearcoat_roughness_texture',
          'clearcoat_normal_texture',
        ] else ...<String>[
          'specular_factor_texture',
          'specular_color_texture',
        ],
        if (flutter_scene_gpu.usesCubeRadianceShader)
          'prefiltered_radiance_cube'
        else
          'prefiltered_radiance',
        'brdf_lut',
        'shadow_map',
        'sh_coefficients',
        if (flutter_scene_gpu.usesCubeRadianceShader)
          'prefiltered_radiance_cube_b'
        else
          'prefiltered_radiance_b',
        'sh_coefficients_b',
        'ssao_texture',
      ];

  final LoadFlutterSceneExtendedPbrShader _loadShader;
  final Map<String, flutter_scene_gpu.Shader> _shaders =
      <String, flutter_scene_gpu.Shader>{};

  @override
  bool get isReady =>
      _shaders.containsKey(shaderName) &&
      _shaders.containsKey(clearcoatShaderName);

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async {
    if (isReady) {
      return null;
    }
    Object? lastError;
    for (final assetPath in shaderBundleAssets) {
      try {
        final loaded = <String, flutter_scene_gpu.Shader>{};
        var missingEntry = false;
        for (final name in <String>[shaderName, clearcoatShaderName]) {
          final shader = await _loadShader(assetPath, name);
          if (shader == null) {
            missingEntry = true;
            break;
          }
          for (final slot in _requiredUniformSlots(name)) {
            shader.getUniformSlot(slot);
          }
          loaded[name] = shader;
        }
        if (missingEntry) {
          continue;
        }
        _shaders
          ..clear()
          ..addAll(loaded);
        return null;
      } on Object catch (error) {
        lastError = error;
      }
    }
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The package-built FSViewerExtendedPbr shader is unavailable or has a stale reflected contract.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': shaderName,
        'limitation': lastError == null
            ? 'extendedPbrShaderUnavailable'
            : 'extendedPbrShaderContractMismatch',
        'status': 'blocked',
        'materialReplaced': false,
        'encodedBytesModified': false,
        'nextStep': 'packageExtendedPbrShaderBundle',
        if (lastError != null) 'error': lastError.toString(),
      },
    );
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async {
    final usesClearcoatShader = _hasClearcoatState(config.source);
    if (usesClearcoatShader && _hasExtendedSpecularState(config)) {
      throw UnsupportedError(
        'FSViewerClearcoatExtendedPbr cannot combine clearcoat with '
        'specular textures, non-default specular factors, or non-default IOR '
        'within the 16-sampler backend floor.',
      );
    }
    final selectedName = usesClearcoatShader ? clearcoatShaderName : shaderName;
    final shader = _shaders[selectedName];
    if (shader == null) {
      throw StateError('FSViewerExtendedPbr must pass preflight before use.');
    }
    return FlutterSceneExtendedPbrMaterial(
      fragmentShader: shader,
      source: config.source,
      usesClearcoatShader: usesClearcoatShader,
      transforms: config.transforms,
      specularFactor: config.specularFactor,
      specularColorFactor: config.specularColorFactor,
      ior: config.ior,
      specularFactorTexture: config.specularFactorTexture,
      specularColorTexture: config.specularColorTexture,
    );
  }

  static Future<flutter_scene_gpu.Shader?> _loadShaderFromBundle(
    String assetPath,
    String shaderName,
  ) async {
    final library =
        await flutter_scene_gpu_public.loadShaderLibraryAsync(assetPath);
    return library?[shaderName];
  }
}

bool _hasClearcoatState(flutter_scene.PhysicallyBasedMaterial material) =>
    material.clearcoatFactor != 0 ||
    material.clearcoatRoughnessFactor != 0 ||
    material.clearcoatTexture != null ||
    material.clearcoatRoughnessTexture != null ||
    material.clearcoatNormalTexture != null;

bool _hasExtendedSpecularState(FlutterSceneExtendedPbrMaterialConfig config) =>
    config.specularFactor != 1 ||
    config.specularColorFactor.length != 3 ||
    config.specularColorFactor[0] != 1 ||
    config.specularColorFactor[1] != 1 ||
    config.specularColorFactor[2] != 1 ||
    config.ior != 1.5 ||
    config.specularFactorTexture != null ||
    config.specularColorTexture != null;
