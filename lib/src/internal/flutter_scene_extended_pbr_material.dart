import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;

import '../texture_binding.dart';

const String flutterSceneExtendedPbrShaderName = 'FSViewerExtendedPbr';
const String flutterSceneExtendedPbrUv1ShaderName = 'FSViewerExtendedPbrUV1';
const String flutterSceneSheenExtendedPbrShaderName =
    'FSViewerSheenExtendedPbr';
const String flutterSceneSheenExtendedPbrUv1ShaderName =
    'FSViewerSheenExtendedPbrUV1';
const String flutterSceneClearcoatSheenExtendedPbrShaderName =
    'FSViewerClearcoatSheenExtendedPbr';
const String flutterSceneClearcoatSheenExtendedPbrUv1ShaderName =
    'FSViewerClearcoatSheenExtendedPbrUV1';
const String flutterSceneClearcoatExtendedPbrShaderName =
    'FSViewerClearcoatExtendedPbr';
const String flutterSceneClearcoatExtendedPbrUv1ShaderName =
    'FSViewerClearcoatExtendedPbrUV1';
const String flutterSceneExtendedPbrUniformBlockName = 'ExtendedPbrParams';
const String flutterSceneSheenUniformBlockName = 'SheenParams';
const String flutterSceneClearcoatSheenUniformBlockName =
    'ClearcoatSheenParams';

typedef BindFlutterSceneSheenBrdfLut = void Function(
  flutter_scene_gpu.RenderPass pass,
  flutter_scene_gpu.Shader shader,
);

const List<MaterialTextureSlot> _coreSlots = <MaterialTextureSlot>[
  MaterialTextureSlot.baseColor,
  MaterialTextureSlot.metallicRoughness,
  MaterialTextureSlot.normal,
  MaterialTextureSlot.occlusion,
  MaterialTextureSlot.emissive,
];

const List<MaterialTextureSlot> _sheenSlots = <MaterialTextureSlot>[
  MaterialTextureSlot.sheenColor,
  MaterialTextureSlot.sheenRoughness,
];

const List<MaterialTextureSlot> _clearcoatSheenSlots = <MaterialTextureSlot>[
  MaterialTextureSlot.clearcoat,
  MaterialTextureSlot.clearcoatRoughness,
];

Float32List _packExtendedPbrParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms, {
  double specularFactor = 1,
  List<double> specularColorFactor = const <double>[1, 1, 1],
  double ior = 1.5,
  bool hasSpecularFactorTexture = false,
  bool hasSpecularColorTexture = false,
}) {
  _validateExtendedPbrFactors(
    specularFactor: specularFactor,
    specularColorFactor: specularColorFactor,
    ior: ior,
  );
  final values = Float32List(48);
  for (var index = 0; index < _coreSlots.length; index += 1) {
    final transform =
        transforms[_coreSlots[index]] ?? TextureTransform.identity;
    final offset = index * 8;
    values[offset] = transform.offsetX;
    values[offset + 1] = transform.offsetY;
    values[offset + 2] = transform.scaleX;
    values[offset + 3] = transform.scaleY;
    values[offset + 4] = math.cos(transform.rotation);
    values[offset + 5] = math.sin(transform.rotation);
  }
  values[40] = specularColorFactor[0];
  values[41] = specularColorFactor[1];
  values[42] = specularColorFactor[2];
  values[44] = specularFactor;
  values[45] = ior;
  values[46] = hasSpecularFactorTexture ? 1 : 0;
  values[47] = hasSpecularColorTexture ? 1 : 0;
  return values;
}

Float32List _packSheenParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms, {
  required List<double> sheenColorFactor,
  required double sheenRoughness,
  required bool hasSheenColorTexture,
  required bool hasSheenRoughnessTexture,
}) {
  if (sheenColorFactor.length != 3 ||
      sheenColorFactor.any(
        (value) => !value.isFinite || value < 0 || value > 1,
      )) {
    throw ArgumentError.value(
      sheenColorFactor,
      'sheenColorFactor',
      'must contain three finite values in [0, 1]',
    );
  }
  if (!sheenRoughness.isFinite || sheenRoughness < 0 || sheenRoughness > 1) {
    throw ArgumentError.value(
      sheenRoughness,
      'sheenRoughness',
      'must be finite and in [0, 1]',
    );
  }
  final values = Float32List(24);
  for (var index = 0; index < _sheenSlots.length; index += 1) {
    final transform =
        transforms[_sheenSlots[index]] ?? TextureTransform.identity;
    final offset = index * 8;
    values[offset] = transform.offsetX;
    values[offset + 1] = transform.offsetY;
    values[offset + 2] = transform.scaleX;
    values[offset + 3] = transform.scaleY;
    values[offset + 4] = math.cos(transform.rotation);
    values[offset + 5] = math.sin(transform.rotation);
  }
  values[16] = sheenColorFactor[0];
  values[17] = sheenColorFactor[1];
  values[18] = sheenColorFactor[2];
  values[20] = sheenRoughness;
  values[21] = hasSheenColorTexture ? 1 : 0;
  values[22] = hasSheenRoughnessTexture ? 1 : 0;
  return values;
}

Float32List _packClearcoatSheenParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms,
) {
  final values = Float32List(16);
  for (var index = 0; index < _clearcoatSheenSlots.length; index += 1) {
    final transform =
        transforms[_clearcoatSheenSlots[index]] ?? TextureTransform.identity;
    final offset = index * 8;
    values[offset] = transform.offsetX;
    values[offset + 1] = transform.offsetY;
    values[offset + 2] = transform.scaleX;
    values[offset + 3] = transform.scaleY;
    values[offset + 4] = math.cos(transform.rotation);
    values[offset + 5] = math.sin(transform.rotation);
  }
  return values;
}

void _validateExtendedPbrFactors({
  required double specularFactor,
  required List<double> specularColorFactor,
  required double ior,
}) {
  if (!specularFactor.isFinite || specularFactor < 0 || specularFactor > 1) {
    throw ArgumentError.value(
      specularFactor,
      'specularFactor',
      'must be finite and in [0, 1]',
    );
  }
  if (specularColorFactor.length != 3 ||
      specularColorFactor.any((value) => !value.isFinite || value < 0)) {
    throw ArgumentError.value(
      specularColorFactor,
      'specularColorFactor',
      'must contain three finite non-negative linear values',
    );
  }
  if (!ior.isFinite || (ior != 0 && ior < 1)) {
    throw ArgumentError.value(
      ior,
      'ior',
      'must be exactly 0 or finite and greater than or equal to 1',
    );
  }
}

double _iorF0(double ior) {
  if (!ior.isFinite || (ior != 0 && ior < 1)) {
    throw ArgumentError.value(
      ior,
      'ior',
      'must be exactly 0 or finite and greater than or equal to 1',
    );
  }
  if (ior == 0) {
    return 1;
  }
  final ratio = (ior - 1) / (ior + 1);
  return ratio * ratio;
}

List<double> _dielectricFresnel({
  required double ior,
  required double specularFactor,
  required List<double> specularColorFactor,
  required double cosine,
}) {
  _validateExtendedPbrFactors(
    specularFactor: specularFactor,
    specularColorFactor: specularColorFactor,
    ior: ior,
  );
  if (!cosine.isFinite || cosine < 0 || cosine > 1) {
    throw ArgumentError.value(cosine, 'cosine', 'must be finite and in [0, 1]');
  }
  if (ior == 0) {
    return const <double>[1, 1, 1];
  }
  final baseF0 = _iorF0(ior);
  final grazing = math.pow(1 - cosine, 5).toDouble();
  return <double>[
    for (final color in specularColorFactor)
      () {
        final f0 = math.min(baseF0 * color, 1) * specularFactor;
        final f90 = specularFactor;
        return f0 + (f90 - f0) * grazing;
      }(),
  ];
}

double _diffuseWeight(List<double> fresnel) {
  if (fresnel.length != 3 ||
      fresnel.any((value) => !value.isFinite || value < 0 || value > 1)) {
    throw ArgumentError.value(
      fresnel,
      'fresnel',
      'must contain three finite values in [0, 1]',
    );
  }
  return 1 - fresnel.reduce(math.max);
}

List<double> _surfaceF0({
  required List<double> albedo,
  required double metallic,
  required double ior,
  required double specularFactor,
  required List<double> specularColorFactor,
}) {
  if (albedo.length != 3 ||
      albedo.any((value) => !value.isFinite || value < 0) ||
      !metallic.isFinite ||
      metallic < 0 ||
      metallic > 1) {
    throw ArgumentError('albedo and metallic must describe a finite surface');
  }
  final dielectric = _dielectricFresnel(
    ior: ior,
    specularFactor: specularFactor,
    specularColorFactor: specularColorFactor,
    cosine: 1,
  );
  return <double>[
    for (var index = 0; index < 3; index += 1)
      dielectric[index] * (1 - metallic) + albedo[index] * metallic,
  ];
}

void _copyPbrState(
  flutter_scene.PhysicallyBasedMaterial source,
  flutter_scene.PhysicallyBasedMaterial target,
) {
  target
    ..baseColorTexture = source.baseColorTexture
    ..metallicRoughnessTexture = source.metallicRoughnessTexture
    ..normalTexture = source.normalTexture
    ..occlusionTexture = source.occlusionTexture
    ..clearcoatTexture = source.clearcoatTexture
    ..clearcoatFactor = source.clearcoatFactor
    ..clearcoatRoughnessTexture = source.clearcoatRoughnessTexture
    ..clearcoatRoughnessFactor = source.clearcoatRoughnessFactor
    ..clearcoatNormalTexture = source.clearcoatNormalTexture
    ..clearcoatNormalScale = source.clearcoatNormalScale
    ..emissiveTexture = source.emissiveTexture
    ..baseColorFactor = source.baseColorFactor.clone()
    ..vertexColorWeight = source.vertexColorWeight
    ..metallicFactor = source.metallicFactor
    ..roughnessFactor = source.roughnessFactor
    ..normalScale = source.normalScale
    ..occlusionStrength = source.occlusionStrength
    // ignore: invalid_use_of_internal_member
    ..occlusionTextureTexCoord = source.occlusionTextureTexCoord
    // ignore: invalid_use_of_internal_member
    ..occlusionTextureTransform = source.occlusionTextureTransform
    ..emissiveFactor = source.emissiveFactor.clone()
    ..environment = source.environment
    ..alphaMode = source.alphaMode
    ..alphaCutoff = source.alphaCutoff
    ..doubleSided = source.doubleSided
    ..specularAntiAliasingVariance = source.specularAntiAliasingVariance
    ..specularAntiAliasingThreshold = source.specularAntiAliasingThreshold;
}

/// State contract retained across repeated material-scoped extended PBR deltas.
abstract interface class FlutterSceneExtendedPbrState {
  Map<MaterialTextureSlot, TextureTransform> get transforms;
  double get specularFactor;
  List<double> get specularColorFactor;
  double get ior;
  flutter_scene.TextureSource? get specularFactorTexture;
  flutter_scene.TextureSource? get specularColorTexture;
  bool get hasSheenIntent;
  List<double> get retainedSheenColorFactor;
  double get sheenRoughness;
  flutter_scene.TextureSource? get sheenColorTexture;
  flutter_scene.TextureSource? get sheenRoughnessTexture;
}

extension FlutterSceneExtendedPbrStateRetention
    on FlutterSceneExtendedPbrState {
  List<double> get sheenColorFactor => retainedSheenColorFactor;
}

/// Internal material-scoped PBR extension boundary.
///
/// Runtime routing must not construct this material until the shader bundle
/// and its complete reflected contract have passed preflight.
final class FlutterSceneExtendedPbrMaterial extends flutter_scene
    .PhysicallyBasedMaterial implements FlutterSceneExtendedPbrState {
  FlutterSceneExtendedPbrMaterial({
    required flutter_scene_gpu.Shader fragmentShader,
    required flutter_scene.PhysicallyBasedMaterial source,
    required this.usesClearcoatShader,
    required this.usesSheenShader,
    this.bindSheenBrdfLut,
    Map<MaterialTextureSlot, TextureTransform> transforms =
        const <MaterialTextureSlot, TextureTransform>{},
    this.specularFactor = 1,
    List<double> specularColorFactor = const <double>[1, 1, 1],
    double ior = 1.5,
    this.specularFactorTexture,
    this.specularColorTexture,
    this.hasSheenIntent = false,
    List<double> sheenColorFactor = const <double>[0, 0, 0],
    this.sheenRoughness = 0,
    flutter_scene.TextureSource? sheenColorTexture,
    flutter_scene.TextureSource? sheenRoughnessTexture,
  })  : transforms = Map<MaterialTextureSlot, TextureTransform>.unmodifiable(
          transforms,
        ),
        specularColorFactor = List<double>.unmodifiable(specularColorFactor),
        retainedSheenColorFactor = List<double>.unmodifiable(sheenColorFactor) {
    _validateExtendedPbrFactors(
      specularFactor: specularFactor,
      specularColorFactor: specularColorFactor,
      ior: ior,
    );
    _copyPbrState(source, this);
    this.sheenColorTexture = sheenColorTexture;
    this.sheenRoughnessTexture = sheenRoughnessTexture;
    if (hasSheenIntent != usesSheenShader) {
      throw ArgumentError(
        'Sheen intent must use the independently preflighted sheen shader.',
      );
    }
    if (usesSheenShader && bindSheenBrdfLut == null) {
      throw ArgumentError.notNull('bindSheenBrdfLut');
    }
    if (hasSheenIntent) {
      _packSheenParameters(
        transforms,
        sheenColorFactor: sheenColorFactor,
        sheenRoughness: sheenRoughness,
        hasSheenColorTexture: sheenColorTexture != null,
        hasSheenRoughnessTexture: sheenRoughnessTexture != null,
      );
      if (usesClearcoatShader) {
        _packClearcoatSheenParameters(transforms);
      }
    }
    this.ior = ior;
    setFragmentShader(fragmentShader);
  }

  @override
  final Map<MaterialTextureSlot, TextureTransform> transforms;
  @override
  final double specularFactor;
  @override
  final List<double> specularColorFactor;
  @override
  final flutter_scene.TextureSource? specularFactorTexture;
  @override
  final flutter_scene.TextureSource? specularColorTexture;
  @override
  final bool hasSheenIntent;
  @override
  final List<double> retainedSheenColorFactor;
  @override
  final double sheenRoughness;
  final bool usesClearcoatShader;
  final bool usesSheenShader;
  final BindFlutterSceneSheenBrdfLut? bindSheenBrdfLut;

  @override
  bool get bindsClearcoatTextureSlots =>
      usesClearcoatShader && !usesSheenShader;

  static final flutter_scene_gpu.SamplerOptions _repeatSampler =
      flutter_scene_gpu.SamplerOptions(
    widthAddressMode: flutter_scene_gpu.SamplerAddressMode.repeat,
    heightAddressMode: flutter_scene_gpu.SamplerAddressMode.repeat,
  );

  @override
  void bind(
    flutter_scene_gpu.RenderPass pass,
    flutter_scene_gpu.HostBuffer transientsBuffer,
    flutter_scene.Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);
    final parameters = _packExtendedPbrParameters(
      transforms,
      specularFactor: specularFactor,
      specularColorFactor: specularColorFactor,
      ior: ior,
      hasSpecularFactorTexture: specularFactorTexture != null,
      hasSpecularColorTexture: specularColorTexture != null,
    );
    pass.bindUniform(
      fragmentShader.getUniformSlot(flutterSceneExtendedPbrUniformBlockName),
      transientsBuffer.emplace(ByteData.sublistView(parameters)),
    );
    if (!usesClearcoatShader) {
      _bindExtensionTexture(
        pass,
        'specular_factor_texture',
        specularFactorTexture,
      );
      _bindExtensionTexture(
        pass,
        'specular_color_texture',
        specularColorTexture,
      );
    }
    if (usesClearcoatShader && usesSheenShader) {
      final clearcoatSheenParameters =
          _packClearcoatSheenParameters(transforms);
      pass.bindUniform(
        fragmentShader.getUniformSlot(
          flutterSceneClearcoatSheenUniformBlockName,
        ),
        transientsBuffer.emplace(
          ByteData.sublistView(clearcoatSheenParameters),
        ),
      );
      _bindExtensionTexture(
        pass,
        'clearcoat_texture',
        clearcoatTexture,
      );
      _bindExtensionTexture(
        pass,
        'clearcoat_roughness_texture',
        clearcoatRoughnessTexture,
      );
    }
    if (usesSheenShader) {
      final sheenParameters = _packSheenParameters(
        transforms,
        sheenColorFactor: retainedSheenColorFactor,
        sheenRoughness: sheenRoughness,
        hasSheenColorTexture: sheenColorTexture != null,
        hasSheenRoughnessTexture: sheenRoughnessTexture != null,
      );
      pass.bindUniform(
        fragmentShader.getUniformSlot(flutterSceneSheenUniformBlockName),
        transientsBuffer.emplace(ByteData.sublistView(sheenParameters)),
      );
      _bindExtensionTexture(
        pass,
        'sheen_color_texture',
        sheenColorTexture,
      );
      _bindExtensionTexture(
        pass,
        'sheen_roughness_texture',
        sheenRoughnessTexture,
      );
      // PhysicallyBasedMaterial.bind() binds the renderer's two-channel GGX
      // DFG texture. The sheen entry needs the package-owned combined RGBA16F
      // texture instead, so this intentionally remains the final binding.
      bindSheenBrdfLut!(pass, fragmentShader);
    }
  }

  void _bindExtensionTexture(
    flutter_scene_gpu.RenderPass pass,
    String name,
    flutter_scene.TextureSource? source,
  ) {
    // ignore: invalid_use_of_internal_member
    final texture = source?.sampledTexture;
    pass.bindTexture(
      fragmentShader.getUniformSlot(name),
      flutter_scene.Material.whitePlaceholder(texture),
      // ignore: invalid_use_of_internal_member
      sampler: source?.sampledSampler ?? _repeatSampler,
    );
  }
}

@visibleForTesting
Float32List debugPackFlutterSceneExtendedPbrParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms, {
  double specularFactor = 1,
  List<double> specularColorFactor = const <double>[1, 1, 1],
  double ior = 1.5,
  bool hasSpecularFactorTexture = false,
  bool hasSpecularColorTexture = false,
}) =>
    _packExtendedPbrParameters(
      transforms,
      specularFactor: specularFactor,
      specularColorFactor: specularColorFactor,
      ior: ior,
      hasSpecularFactorTexture: hasSpecularFactorTexture,
      hasSpecularColorTexture: hasSpecularColorTexture,
    );

@visibleForTesting
Float32List debugPackFlutterSceneSheenParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms, {
  List<double> sheenColorFactor = const <double>[0, 0, 0],
  double sheenRoughness = 0,
  bool hasSheenColorTexture = false,
  bool hasSheenRoughnessTexture = false,
}) =>
    _packSheenParameters(
      transforms,
      sheenColorFactor: sheenColorFactor,
      sheenRoughness: sheenRoughness,
      hasSheenColorTexture: hasSheenColorTexture,
      hasSheenRoughnessTexture: hasSheenRoughnessTexture,
    );

@visibleForTesting
Float32List debugPackFlutterSceneClearcoatSheenParameters(
  Map<MaterialTextureSlot, TextureTransform> transforms,
) =>
    _packClearcoatSheenParameters(transforms);

@visibleForTesting
void debugCopyFlutterSceneExtendedPbrState(
  flutter_scene.PhysicallyBasedMaterial source,
  flutter_scene.PhysicallyBasedMaterial target,
) =>
    _copyPbrState(source, target);

@visibleForTesting
double debugFlutterSceneExtendedPbrIorF0(double ior) => _iorF0(ior);

@visibleForTesting
List<double> debugFlutterSceneExtendedPbrDielectricFresnel({
  required double ior,
  required double specularFactor,
  required List<double> specularColorFactor,
  required double cosine,
}) =>
    _dielectricFresnel(
      ior: ior,
      specularFactor: specularFactor,
      specularColorFactor: specularColorFactor,
      cosine: cosine,
    );

@visibleForTesting
double debugFlutterSceneExtendedPbrDiffuseWeight(List<double> fresnel) =>
    _diffuseWeight(fresnel);

@visibleForTesting
List<double> debugFlutterSceneExtendedPbrSurfaceF0({
  required List<double> albedo,
  required double metallic,
  required double ior,
  required double specularFactor,
  required List<double> specularColorFactor,
}) =>
    _surfaceF0(
      albedo: albedo,
      metallic: metallic,
      ior: ior,
      specularFactor: specularFactor,
      specularColorFactor: specularColorFactor,
    );
