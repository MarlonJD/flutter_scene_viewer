import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu_public;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;

import '../diagnostics.dart';
import '../part_address.dart';
import '../texture_binding.dart';
import 'flutter_scene_extended_pbr_material.dart';

typedef LoadFlutterSceneExtendedPbrShader = Future<flutter_scene_gpu.Shader?>
    Function(String assetPath);

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
  static const List<String> shaderBundleAssets = <String>[
    'flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  ];

  static const List<String> _requiredUniformSlots = <String>[
    'FragInfo',
    flutterSceneExtendedPbrUniformBlockName,
    'FogInfo',
    'RadianceLayoutInfo',
    'base_color_texture',
    'emissive_texture',
    'metallic_roughness_texture',
    'normal_texture',
    'occlusion_texture',
    'specular_factor_texture',
    'specular_color_texture',
    'prefiltered_radiance',
    'prefiltered_radiance_cube',
    'brdf_lut',
    'shadow_map',
    'sh_coefficients',
    'prefiltered_radiance_b',
    'prefiltered_radiance_cube_b',
    'sh_coefficients_b',
    'ssao_texture',
  ];

  final LoadFlutterSceneExtendedPbrShader _loadShader;
  flutter_scene_gpu.Shader? _shader;

  @override
  bool get isReady => _shader != null;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async {
    if (_shader != null) {
      return null;
    }
    Object? lastError;
    for (final assetPath in shaderBundleAssets) {
      try {
        final shader = await _loadShader(assetPath);
        if (shader == null) {
          continue;
        }
        for (final slot in _requiredUniformSlots) {
          shader.getUniformSlot(slot);
        }
        _shader = shader;
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
    final shader = _shader;
    if (shader == null) {
      throw StateError('FSViewerExtendedPbr must pass preflight before use.');
    }
    return FlutterSceneExtendedPbrMaterial(
      fragmentShader: shader,
      source: config.source,
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
  ) async {
    final library =
        await flutter_scene_gpu_public.loadShaderLibraryAsync(assetPath);
    return library?[shaderName];
  }
}
