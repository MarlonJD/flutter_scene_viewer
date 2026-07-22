import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu_public;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;

import '../diagnostics.dart';
import '../part_address.dart';
import '../texture_binding.dart';
import 'flutter_scene_extended_pbr_material.dart';
import 'sheen_semantics.dart';

typedef LoadFlutterSceneExtendedPbrShader = Future<flutter_scene_gpu.Shader?>
    Function(String assetPath, String shaderName);

abstract interface class FlutterSceneSheenBrdfLut {
  void bind(
    flutter_scene_gpu.RenderPass pass,
    flutter_scene_gpu.Shader shader,
  );
}

final class _FlutterSceneCombinedSheenBrdfLut
    implements FlutterSceneSheenBrdfLut {
  const _FlutterSceneCombinedSheenBrdfLut(this.texture);

  final flutter_scene_gpu.Texture texture;

  static final flutter_scene_gpu.SamplerOptions _linearClamp =
      flutter_scene_gpu.SamplerOptions(
    minFilter: flutter_scene_gpu.MinMagFilter.linear,
    magFilter: flutter_scene_gpu.MinMagFilter.linear,
    widthAddressMode: flutter_scene_gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: flutter_scene_gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  void bind(
    flutter_scene_gpu.RenderPass pass,
    flutter_scene_gpu.Shader shader,
  ) {
    pass.bindTexture(
      shader.getUniformSlot('brdf_lut'),
      texture,
      sampler: _linearClamp,
    );
  }
}

typedef LoadFlutterSceneSheenBrdfLut = Future<FlutterSceneSheenBrdfLut?>
    Function();

final class FlutterSceneExtendedPbrMaterialConfig {
  FlutterSceneExtendedPbrMaterialConfig({
    required this.source,
    this.transforms = const <MaterialTextureSlot, TextureTransform>{},
    this.specularFactor = 1,
    this.specularColorFactor = const <double>[1, 1, 1],
    this.ior = 1.5,
    this.specularFactorTexture,
    this.specularColorTexture,
    this.hasSheenIntent = false,
    this.sheenColorFactor = const <double>[0, 0, 0],
    this.sheenRoughness = 0,
    this.sheenColorTexture,
    this.sheenRoughnessTexture,
  });

  final flutter_scene.PhysicallyBasedMaterial source;
  final Map<MaterialTextureSlot, TextureTransform> transforms;
  final double specularFactor;
  final List<double> specularColorFactor;
  final double ior;
  final flutter_scene.TextureSource? specularFactorTexture;
  final flutter_scene.TextureSource? specularColorTexture;
  final bool hasSheenIntent;
  final List<double> sheenColorFactor;
  final double sheenRoughness;
  final flutter_scene.TextureSource? sheenColorTexture;
  final flutter_scene.TextureSource? sheenRoughnessTexture;
}

/// Request-specific extension/resource shape used before any texture decode or
/// live material mutation.
final class FlutterSceneExtendedPbrResourceRequest {
  const FlutterSceneExtendedPbrResourceRequest({
    required this.hasSheen,
    this.hasSpecular = false,
    this.hasClearcoat = false,
    this.hasTransmissionState = false,
    this.hasVolumeState = false,
    this.hasSpecularFactorTexture = false,
    this.hasSpecularColorTexture = false,
    this.hasSheenColorTexture = false,
    this.hasSheenRoughnessTexture = false,
    this.hasClearcoatTexture = false,
    this.hasClearcoatRoughnessTexture = false,
    this.hasClearcoatNormalTexture = false,
  });

  final bool hasSheen;
  final bool hasSpecular;
  final bool hasClearcoat;
  final bool hasTransmissionState;
  final bool hasVolumeState;
  final bool hasSpecularFactorTexture;
  final bool hasSpecularColorTexture;
  final bool hasSheenColorTexture;
  final bool hasSheenRoughnessTexture;
  final bool hasClearcoatTexture;
  final bool hasClearcoatRoughnessTexture;
  final bool hasClearcoatNormalTexture;
}

final class FlutterSceneExtendedPbrSamplerManifest {
  const FlutterSceneExtendedPbrSamplerManifest({
    required this.entryName,
    required this.declaredSamplerSlots,
    required this.requestedTextureSlots,
    required this.projectedRequestSamplerCount,
    this.portableLimit = 16,
  });

  final String entryName;
  final List<String> declaredSamplerSlots;
  final List<String> requestedTextureSlots;
  final int projectedRequestSamplerCount;
  final int portableLimit;
}

const List<String> _engineSamplerSlots = <String>[
  'prefiltered_radiance',
  'brdf_lut',
  'shadow_map',
  'sh_coefficients',
  'prefiltered_radiance_b',
  'sh_coefficients_b',
  'ssao_texture',
];

const List<String> _coreSamplerSlots = <String>[
  'base_color_texture',
  'metallic_roughness_texture',
  'normal_texture',
  'occlusion_texture',
  'emissive_texture',
];

const List<String> _specularSamplerSlots = <String>[
  'specular_factor_texture',
  'specular_color_texture',
];

const List<String> _sheenSamplerSlots = <String>[
  'sheen_color_texture',
  'sheen_roughness_texture',
];

const List<String> _clearcoatSamplerSlots = <String>[
  'clearcoat_texture',
  'clearcoat_roughness_texture',
  'clearcoat_normal_texture',
];

FlutterSceneExtendedPbrSamplerManifest _samplerManifest(
  FlutterSceneExtendedPbrResourceRequest request,
) {
  final requestedExtensionSlots = <String>[
    if (request.hasSpecularFactorTexture) _specularSamplerSlots[0],
    if (request.hasSpecularColorTexture) _specularSamplerSlots[1],
    if (request.hasSheenColorTexture) _sheenSamplerSlots[0],
    if (request.hasSheenRoughnessTexture) _sheenSamplerSlots[1],
    if (request.hasClearcoatTexture) _clearcoatSamplerSlots[0],
    if (request.hasClearcoatRoughnessTexture) _clearcoatSamplerSlots[1],
    if (request.hasClearcoatNormalTexture) _clearcoatSamplerSlots[2],
  ];
  final requestedSlots = <String>[
    ..._engineSamplerSlots,
    ..._coreSamplerSlots,
    ...requestedExtensionSlots,
  ];
  final declaredSlots = request.hasClearcoat
      ? <String>[
          ..._engineSamplerSlots,
          ..._coreSamplerSlots,
          ..._sheenSamplerSlots,
          _clearcoatSamplerSlots[0],
          _clearcoatSamplerSlots[1],
        ]
      : <String>[
          ..._engineSamplerSlots,
          ..._coreSamplerSlots,
          ..._specularSamplerSlots,
          ..._sheenSamplerSlots,
        ];
  return FlutterSceneExtendedPbrSamplerManifest(
    entryName: request.hasClearcoat
        ? flutterSceneClearcoatSheenExtendedPbrShaderName
        : 'FSViewerSheenExtendedPbr',
    declaredSamplerSlots: List<String>.unmodifiable(declaredSlots),
    requestedTextureSlots: List<String>.unmodifiable(requestedSlots),
    projectedRequestSamplerCount: requestedSlots.length,
  );
}

ViewerDiagnostic? _resourceDiagnostic(
  PartAddress address,
  FlutterSceneExtendedPbrResourceRequest request,
) {
  final manifest = _samplerManifest(request);
  final incompatibleSlots = request.hasClearcoat
      ? <String>[
          if (request.hasSpecularFactorTexture) _specularSamplerSlots[0],
          if (request.hasSpecularColorTexture) _specularSamplerSlots[1],
          if (request.hasClearcoatNormalTexture) _clearcoatSamplerSlots[2],
        ]
      : const <String>[];
  final incompatibleState = request.hasClearcoat
      ? <String>[
          if (request.hasTransmissionState) 'transmission',
          if (request.hasVolumeState) 'volume',
        ]
      : const <String>[];
  if (manifest.projectedRequestSamplerCount > manifest.portableLimit) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The requested sheen composition exceeds the portable fragment sampler floor.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': manifest.entryName,
        'selectedVariant': manifest.entryName,
        'extension': 'KHR_materials_sheen',
        'limitation': 'fragmentSamplerBudgetExceeded',
        'portableLimit': manifest.portableLimit,
        'requestedSamplerCount': manifest.projectedRequestSamplerCount,
        'requestedSlots': manifest.requestedTextureSlots,
        'incompatibleSlots': incompatibleSlots,
        'incompatibleState': incompatibleState,
        'status': 'blocked',
        'maturity': 'candidate-only',
        'renderingEvidence': 'not run',
        'materialReplaced': false,
        'decodedTextureCount': 0,
        'encodedBytesModified': false,
      },
    );
  }
  if (incompatibleState.isNotEmpty) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The bounded clearcoat-above-sheen variant cannot compose transmission or volume state.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': manifest.entryName,
        'selectedVariant': manifest.entryName,
        'extension': 'KHR_materials_sheen',
        'limitation': 'sheenCompositionStateIncompatible',
        'portableLimit': manifest.portableLimit,
        'requestedSamplerCount': manifest.projectedRequestSamplerCount,
        'requestedSlots': manifest.requestedTextureSlots,
        'incompatibleSlots': incompatibleSlots,
        'incompatibleState': incompatibleState,
        'status': 'blocked',
        'maturity': 'candidate-only',
        'renderingEvidence': 'not run',
        'materialReplaced': false,
        'decodedTextureCount': 0,
        'encodedBytesModified': false,
      },
    );
  }
  if (incompatibleSlots.isNotEmpty) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The bounded clearcoat-above-sheen variant cannot bind the requested texture slots.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': manifest.entryName,
        'selectedVariant': manifest.entryName,
        'extension': 'KHR_materials_sheen',
        'limitation': 'sheenCompositionResourceIncompatible',
        'portableLimit': manifest.portableLimit,
        'requestedSamplerCount': manifest.projectedRequestSamplerCount,
        'requestedSlots': manifest.requestedTextureSlots,
        'incompatibleSlots': incompatibleSlots,
        'incompatibleState': incompatibleState,
        'status': 'blocked',
        'maturity': 'candidate-only',
        'renderingEvidence': 'not run',
        'materialReplaced': false,
        'decodedTextureCount': 0,
        'encodedBytesModified': false,
      },
    );
  }
  return null;
}

ViewerDiagnostic _sheenPreflightDiagnostic(
  PartAddress address, {
  String selectedVariant = flutterSceneSheenExtendedPbrShaderName,
  required bool foundReflectedShader,
  Object? shaderError,
  Object? resourceError,
}) {
  final resourceFailure = foundReflectedShader;
  final error = resourceFailure ? resourceError : shaderError;
  final limitation = resourceFailure
      ? 'sheenDirectionalAlbedoResourceUnavailable'
      : shaderError != null
          ? 'sheenShaderContractMismatch'
          : 'sheenShaderUnavailable';
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedMaterialFeature,
    message: resourceFailure
        ? 'The package-local combined sheen DFG resource is unavailable.'
        : 'The package-local sheen shader is unavailable or has a stale reflected contract.',
    details: <String, Object?>{
      'part': address.debugPath,
      'feature': selectedVariant,
      'selectedVariant': selectedVariant,
      'extension': 'KHR_materials_sheen',
      'limitation': limitation,
      'status': 'blocked',
      'maturity': 'candidate-only',
      'renderingEvidence': 'not run',
      'materialReplaced': false,
      'decodedTextureCount': 0,
      'encodedBytesModified': false,
      if (resourceFailure) 'resourceStage': 'combinedDfgLut',
      if (error != null) 'error': error.toString(),
      'nextStep': 'packageSheenShaderAndDirectionalAlbedoResource',
    },
  );
}

String _shaderSelection({
  required bool hasSheenIntent,
  required bool hasClearcoatState,
  bool usesTexCoord1 = false,
}) {
  final String selected;
  if (hasSheenIntent && hasClearcoatState) {
    selected = flutterSceneClearcoatSheenExtendedPbrShaderName;
  } else if (hasSheenIntent) {
    selected = flutterSceneSheenExtendedPbrShaderName;
  } else if (hasClearcoatState) {
    selected = flutterSceneClearcoatExtendedPbrShaderName;
  } else {
    selected = flutterSceneExtendedPbrShaderName;
  }
  return usesTexCoord1 ? _uv1ShaderName(selected) : selected;
}

String _uv1ShaderName(String shaderName) => switch (shaderName) {
      flutterSceneExtendedPbrShaderName => flutterSceneExtendedPbrUv1ShaderName,
      flutterSceneClearcoatExtendedPbrShaderName =>
        flutterSceneClearcoatExtendedPbrUv1ShaderName,
      flutterSceneSheenExtendedPbrShaderName =>
        flutterSceneSheenExtendedPbrUv1ShaderName,
      flutterSceneClearcoatSheenExtendedPbrShaderName =>
        flutterSceneClearcoatSheenExtendedPbrUv1ShaderName,
      _ => throw ArgumentError.value(shaderName, 'shaderName'),
    };

String _baseShaderName(String shaderName) => switch (shaderName) {
      flutterSceneExtendedPbrUv1ShaderName => flutterSceneExtendedPbrShaderName,
      flutterSceneClearcoatExtendedPbrUv1ShaderName =>
        flutterSceneClearcoatExtendedPbrShaderName,
      flutterSceneSheenExtendedPbrUv1ShaderName =>
        flutterSceneSheenExtendedPbrShaderName,
      flutterSceneClearcoatSheenExtendedPbrUv1ShaderName =>
        flutterSceneClearcoatSheenExtendedPbrShaderName,
      _ => shaderName,
    };

@visibleForTesting
FlutterSceneExtendedPbrSamplerManifest
    debugFlutterSceneExtendedPbrSamplerManifest(
  FlutterSceneExtendedPbrResourceRequest request,
) =>
        _samplerManifest(request);

@visibleForTesting
ViewerDiagnostic? debugFlutterSceneExtendedPbrResourceDiagnostic(
  PartAddress address,
  FlutterSceneExtendedPbrResourceRequest request,
) =>
    _resourceDiagnostic(address, request);

@visibleForTesting
String debugFlutterSceneExtendedPbrShaderSelection({
  required bool hasSheenIntent,
  required bool hasClearcoatState,
  bool usesTexCoord1 = false,
}) =>
    _shaderSelection(
      hasSheenIntent: hasSheenIntent,
      hasClearcoatState: hasClearcoatState,
      usesTexCoord1: usesTexCoord1,
    );

@visibleForTesting
ViewerDiagnostic debugFlutterSceneSheenPreflightDiagnostic(
  PartAddress address, {
  bool foundReflectedShader = false,
  Object? shaderError,
  Object? resourceError,
}) =>
    _sheenPreflightDiagnostic(
      address,
      selectedVariant: flutterSceneSheenExtendedPbrShaderName,
      foundReflectedShader: foundReflectedShader,
      shaderError: shaderError,
      resourceError: resourceError,
    );

abstract interface class FlutterSceneExtendedPbrMaterialBackend {
  bool get isReady;

  Future<ViewerDiagnostic?> preflight(PartAddress address);

  /// Returns a PBR material that also implements [FlutterSceneExtendedPbrState].
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  );
}

/// Additional package-local contract owned only by the opt-in sheen variant.
abstract interface class FlutterSceneSheenMaterialBackend {
  bool get isSheenReady;

  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  });
}

/// Loads, validates, and constructs the bounded FSViewerExtendedPbr material.
final class FlutterSceneExtendedPbrBackend
    implements
        FlutterSceneExtendedPbrMaterialBackend,
        FlutterSceneSheenMaterialBackend {
  FlutterSceneExtendedPbrBackend({
    LoadFlutterSceneExtendedPbrShader? loadShader,
    LoadFlutterSceneSheenBrdfLut? loadSheenBrdfLut,
  })  : _loadShader = loadShader ?? _loadShaderFromBundle,
        _loadSheenBrdfLut = loadSheenBrdfLut ?? _loadCombinedSheenBrdfLut;

  static const String shaderName = flutterSceneExtendedPbrShaderName;
  static const String shaderUv1Name = flutterSceneExtendedPbrUv1ShaderName;
  static const String clearcoatShaderName =
      flutterSceneClearcoatExtendedPbrShaderName;
  static const String clearcoatShaderUv1Name =
      flutterSceneClearcoatExtendedPbrUv1ShaderName;
  static const String sheenShaderName = flutterSceneSheenExtendedPbrShaderName;
  static const String sheenShaderUv1Name =
      flutterSceneSheenExtendedPbrUv1ShaderName;
  static const String clearcoatSheenShaderName =
      flutterSceneClearcoatSheenExtendedPbrShaderName;
  static const String clearcoatSheenShaderUv1Name =
      flutterSceneClearcoatSheenExtendedPbrUv1ShaderName;
  static const List<String> shaderBundleAssets = <String>[
    'flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    'packages/flutter_scene_viewer/build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  ];

  static List<String> _requiredUniformSlots(String shaderName) {
    final familyName = _baseShaderName(shaderName);
    return <String>[
      'FragInfo',
      flutterSceneExtendedPbrUniformBlockName,
      if (familyName == sheenShaderName ||
          familyName == clearcoatSheenShaderName)
        flutterSceneSheenUniformBlockName,
      if (familyName == clearcoatSheenShaderName)
        flutterSceneClearcoatSheenUniformBlockName,
      'FogInfo',
      'RadianceLayoutInfo',
      'base_color_texture',
      'emissive_texture',
      'metallic_roughness_texture',
      'normal_texture',
      'occlusion_texture',
      if (familyName == clearcoatShaderName) ...<String>[
        'clearcoat_texture',
        'clearcoat_roughness_texture',
        'clearcoat_normal_texture',
      ] else if (familyName == clearcoatSheenShaderName) ...<String>[
        'sheen_color_texture',
        'sheen_roughness_texture',
        'clearcoat_texture',
        'clearcoat_roughness_texture',
      ] else ...<String>[
        'specular_factor_texture',
        'specular_color_texture',
        if (familyName == sheenShaderName) ...<String>[
          'sheen_color_texture',
          'sheen_roughness_texture',
        ],
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
  }

  final LoadFlutterSceneExtendedPbrShader _loadShader;
  final LoadFlutterSceneSheenBrdfLut _loadSheenBrdfLut;
  final Map<String, flutter_scene_gpu.Shader> _shaders =
      <String, flutter_scene_gpu.Shader>{};
  final Map<String, flutter_scene_gpu.Shader> _sheenShaders =
      <String, flutter_scene_gpu.Shader>{};
  FlutterSceneSheenBrdfLut? _sheenBrdfLut;

  @override
  bool get isReady =>
      _shaders.containsKey(shaderName) &&
      _shaders.containsKey(shaderUv1Name) &&
      _shaders.containsKey(clearcoatShaderName) &&
      _shaders.containsKey(clearcoatShaderUv1Name);

  @override
  bool get isSheenReady => _sheenShaders.isNotEmpty && _sheenBrdfLut != null;

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
        for (final name in <String>[
          shaderName,
          shaderUv1Name,
          clearcoatShaderName,
          clearcoatShaderUv1Name,
        ]) {
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
  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  }) async {
    final resourceDiagnostic = _resourceDiagnostic(address, request);
    if (resourceDiagnostic != null) {
      return resourceDiagnostic;
    }
    final selectedName = _samplerManifest(request).entryName;
    if (_sheenShaders.containsKey(selectedName) && _sheenBrdfLut != null) {
      return null;
    }
    Object? shaderError;
    Map<String, flutter_scene_gpu.Shader>? reflectedShaders;
    for (final assetPath in shaderBundleAssets) {
      try {
        final loaded = <String, flutter_scene_gpu.Shader>{};
        var missingEntry = false;
        for (final name in <String>[
          selectedName,
          _uv1ShaderName(selectedName),
        ]) {
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
        reflectedShaders = loaded;
        break;
      } on Object catch (error) {
        shaderError = error;
      }
    }
    if (reflectedShaders == null) {
      return _sheenPreflightDiagnostic(
        address,
        selectedVariant: selectedName,
        foundReflectedShader: false,
        shaderError: shaderError,
      );
    }

    final lutDiagnostic = await _preflightSheenBrdfLut(
      address,
      selectedVariant: selectedName,
    );
    if (lutDiagnostic != null) {
      return lutDiagnostic;
    }
    _sheenShaders.addAll(reflectedShaders);
    return null;
  }

  @visibleForTesting
  Future<ViewerDiagnostic?> debugPreflightSheenBrdfLutForTesting(
    PartAddress address, {
    required String selectedVariant,
  }) =>
      _preflightSheenBrdfLut(
        address,
        selectedVariant: selectedVariant,
      );

  Future<ViewerDiagnostic?> _preflightSheenBrdfLut(
    PartAddress address, {
    required String selectedVariant,
  }) async {
    if (_sheenBrdfLut != null) {
      return null;
    }
    final FlutterSceneSheenBrdfLut? lut;
    try {
      lut = await _loadSheenBrdfLut();
    } on Object catch (error) {
      return _sheenPreflightDiagnostic(
        address,
        selectedVariant: selectedVariant,
        foundReflectedShader: true,
        resourceError: error,
      );
    }
    if (lut == null) {
      return _sheenPreflightDiagnostic(
        address,
        selectedVariant: selectedVariant,
        foundReflectedShader: true,
      );
    }
    _sheenBrdfLut = lut;
    return null;
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async {
    final usesClearcoatShader = _hasClearcoatState(config.source);
    final usesSheenShader = config.hasSheenIntent;
    // ignore: invalid_use_of_internal_member
    final usesTexCoord1 = config.source.occlusionTextureTexCoord == 1;
    final selectedName = _shaderSelection(
      hasSheenIntent: usesSheenShader,
      hasClearcoatState: usesClearcoatShader,
      usesTexCoord1: usesTexCoord1,
    );
    if (usesClearcoatShader &&
        !usesSheenShader &&
        _hasExtendedSpecularState(config)) {
      throw UnsupportedError(
        'FSViewerClearcoatExtendedPbr cannot combine clearcoat with '
        'specular textures, non-default specular factors, or non-default IOR '
        'within the 16-sampler backend floor.',
      );
    }
    if (usesClearcoatShader && usesSheenShader) {
      if (config.specularFactorTexture != null ||
          config.specularColorTexture != null) {
        throw UnsupportedError(
          'FSViewerClearcoatSheenExtendedPbr cannot bind specular textures.',
        );
      }
      if (config.source.clearcoatNormalTexture != null) {
        throw UnsupportedError(
          'FSViewerClearcoatSheenExtendedPbr cannot bind a clearcoat normal texture.',
        );
      }
      if (_hasTransmissionVolumeState(config.source)) {
        throw UnsupportedError(
          'FSViewerClearcoatSheenExtendedPbr cannot compose transmission or volume state.',
        );
      }
    }
    final shader =
        usesSheenShader ? _sheenShaders[selectedName] : _shaders[selectedName];
    if (shader == null) {
      throw StateError('FSViewerExtendedPbr must pass preflight before use.');
    }
    final sheenBrdfLut = usesSheenShader ? _sheenBrdfLut : null;
    if (usesSheenShader && sheenBrdfLut == null) {
      throw StateError(
        'FSViewerSheenExtendedPbr resources must pass preflight before use.',
      );
    }
    return FlutterSceneExtendedPbrMaterial(
      fragmentShader: shader,
      source: config.source,
      usesClearcoatShader: usesClearcoatShader,
      usesSheenShader: usesSheenShader,
      bindSheenBrdfLut: sheenBrdfLut?.bind,
      transforms: config.transforms,
      specularFactor: config.specularFactor,
      specularColorFactor: config.specularColorFactor,
      ior: config.ior,
      specularFactorTexture: config.specularFactorTexture,
      specularColorTexture: config.specularColorTexture,
      hasSheenIntent: config.hasSheenIntent,
      sheenColorFactor: config.sheenColorFactor,
      sheenRoughness: config.sheenRoughness,
      sheenColorTexture: config.sheenColorTexture,
      sheenRoughnessTexture: config.sheenRoughnessTexture,
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

  static Future<FlutterSceneSheenBrdfLut?> _loadCombinedSheenBrdfLut() async {
    const size = 64;
    final halfData = buildCombinedSheenDfgLutHalfData(size: size);
    final texture = flutter_scene_gpu.gpuContext.createTexture(
      flutter_scene_gpu.StorageMode.hostVisible,
      size,
      size,
      format: flutter_scene_gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: false,
    );
    texture.overwrite(ByteData.sublistView(halfData));
    return _FlutterSceneCombinedSheenBrdfLut(texture);
  }
}

bool _hasClearcoatState(flutter_scene.PhysicallyBasedMaterial material) =>
    material.clearcoatFactor != 0 ||
    material.clearcoatRoughnessFactor != 0 ||
    material.clearcoatTexture != null ||
    material.clearcoatRoughnessTexture != null ||
    material.clearcoatNormalTexture != null;

bool _hasTransmissionVolumeState(
  flutter_scene.PhysicallyBasedMaterial material,
) =>
    material.transmissionFactor != 0 ||
    material.transmissionTexture != null ||
    material.thicknessFactor != 0 ||
    material.thicknessTexture != null ||
    material.attenuationDistance.isFinite ||
    material.attenuationColor.x != 1 ||
    material.attenuationColor.y != 1 ||
    material.attenuationColor.z != 1;

bool _hasExtendedSpecularState(FlutterSceneExtendedPbrMaterialConfig config) =>
    config.specularFactor != 1 ||
    config.specularColorFactor.length != 3 ||
    config.specularColorFactor[0] != 1 ||
    config.specularColorFactor[1] != 1 ||
    config.specularColorFactor[2] != 1 ||
    config.ior != 1.5 ||
    config.specularFactorTexture != null ||
    config.specularColorTexture != null;
