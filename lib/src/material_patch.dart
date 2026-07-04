import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'material_effect_mask.dart';
import 'material_extension_policy.dart';
import 'part_address.dart';
import 'texture_source.dart';

/// How a material patch should interpret alpha.
enum MaterialAlphaMode {
  opaque,
  mask,
  blend,
}

/// Runtime patch for core glTF metallic-roughness material controls.
@immutable
final class MaterialPatch {
  const MaterialPatch({
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
    this.effectMask,
    this.transmission,
    this.transmissionTexture,
    this.ior,
    this.thickness,
    this.thicknessTexture,
    this.attenuationColor,
    this.attenuationDistance,
    this.clearcoat,
    this.clearcoatTexture,
    this.clearcoatRoughness,
    this.clearcoatRoughnessTexture,
    this.clearcoatNormalTexture,
    this.clearcoatNormalScale,
    this.specular,
    this.specularTexture,
    this.specularColorFactor,
    this.specularColorTexture,
    this.visible,
  })  : assert(
          baseColorFactor == null || baseColorFactor.length == 4,
          'baseColorFactor must be RGBA',
        ),
        assert(
          emissiveFactor == null || emissiveFactor.length == 3,
          'emissiveFactor must be RGB',
        );

  /// Linear or engine-adapted RGBA factor. Adapter owns color-space details.
  final List<double>? baseColorFactor;

  final TextureSource? baseColorTexture;

  final TextureSource? metallicRoughnessTexture;

  final TextureSource? normalTexture;

  final double? normalScale;

  final double? metallic;

  final double? roughness;

  final List<double>? emissiveFactor;

  final TextureSource? emissiveTexture;

  final TextureSource? occlusionTexture;

  final double? occlusionStrength;

  final MaterialAlphaMode? alphaMode;

  final double? alphaCutoff;

  final MaterialEffectMask? effectMask;

  /// KHR_materials_transmission scalar.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real transmission/refraction support.
  final double? transmission;

  /// KHR_materials_transmission texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real transmission/refraction support.
  final TextureSource? transmissionTexture;

  /// KHR_materials_ior index of refraction.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real IOR support.
  final double? ior;

  /// KHR_materials_volume thickness scalar.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real volume attenuation support.
  final double? thickness;

  /// KHR_materials_volume thickness texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real volume attenuation support.
  final TextureSource? thicknessTexture;

  /// KHR_materials_volume attenuation color.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real volume attenuation support.
  final List<double>? attenuationColor;

  /// KHR_materials_volume attenuation distance.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real volume attenuation support.
  final double? attenuationDistance;

  /// KHR_materials_clearcoat clearcoat factor.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final double? clearcoat;

  /// KHR_materials_clearcoat clearcoat factor texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final TextureSource? clearcoatTexture;

  /// KHR_materials_clearcoat clearcoat roughness factor.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final double? clearcoatRoughness;

  /// KHR_materials_clearcoat clearcoat roughness texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final TextureSource? clearcoatRoughnessTexture;

  /// KHR_materials_clearcoat clearcoat normal texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final TextureSource? clearcoatNormalTexture;

  /// KHR_materials_clearcoat clearcoat normal intensity.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final double? clearcoatNormalScale;

  /// KHR_materials_specular scalar strength.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real specular support.
  final double? specular;

  /// KHR_materials_specular scalar strength texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real specular support.
  final TextureSource? specularTexture;

  /// KHR_materials_specular RGB color factor.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real specular support.
  final List<double>? specularColorFactor;

  /// KHR_materials_specular RGB color texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real specular support.
  final TextureSource? specularColorTexture;

  final bool? visible;

  bool get isEmpty =>
      baseColorFactor == null &&
      baseColorTexture == null &&
      metallicRoughnessTexture == null &&
      normalTexture == null &&
      normalScale == null &&
      metallic == null &&
      roughness == null &&
      emissiveFactor == null &&
      emissiveTexture == null &&
      occlusionTexture == null &&
      occlusionStrength == null &&
      alphaMode == null &&
      alphaCutoff == null &&
      effectMask == null &&
      transmission == null &&
      transmissionTexture == null &&
      ior == null &&
      thickness == null &&
      thicknessTexture == null &&
      attenuationColor == null &&
      attenuationDistance == null &&
      clearcoat == null &&
      clearcoatTexture == null &&
      clearcoatRoughness == null &&
      clearcoatRoughnessTexture == null &&
      clearcoatNormalTexture == null &&
      clearcoatNormalScale == null &&
      specular == null &&
      specularTexture == null &&
      specularColorFactor == null &&
      specularColorTexture == null &&
      visible == null;

  bool get hasGlassOverride =>
      transmission != null ||
      transmissionTexture != null ||
      ior != null ||
      thickness != null ||
      thicknessTexture != null ||
      attenuationColor != null ||
      attenuationDistance != null;

  bool get hasClearcoatOverride =>
      clearcoat != null ||
      clearcoatTexture != null ||
      clearcoatRoughness != null ||
      clearcoatRoughnessTexture != null ||
      clearcoatNormalTexture != null ||
      clearcoatNormalScale != null;

  bool get hasSpecularOverride =>
      specular != null ||
      specularTexture != null ||
      specularColorFactor != null ||
      specularColorTexture != null;

  bool get hasTextureOverride =>
      baseColorTexture != null ||
      metallicRoughnessTexture != null ||
      normalTexture != null ||
      emissiveTexture != null ||
      occlusionTexture != null ||
      effectMask != null ||
      transmissionTexture != null ||
      thicknessTexture != null ||
      clearcoatTexture != null ||
      clearcoatRoughnessTexture != null ||
      clearcoatNormalTexture != null ||
      specularTexture != null ||
      specularColorTexture != null;

  MaterialPatch merge(MaterialPatch next) => MaterialPatch(
        baseColorFactor: next.baseColorFactor ?? baseColorFactor,
        baseColorTexture: next.baseColorTexture ?? baseColorTexture,
        metallicRoughnessTexture:
            next.metallicRoughnessTexture ?? metallicRoughnessTexture,
        normalTexture: next.normalTexture ?? normalTexture,
        normalScale: next.normalScale ?? normalScale,
        metallic: next.metallic ?? metallic,
        roughness: next.roughness ?? roughness,
        emissiveFactor: next.emissiveFactor ?? emissiveFactor,
        emissiveTexture: next.emissiveTexture ?? emissiveTexture,
        occlusionTexture: next.occlusionTexture ?? occlusionTexture,
        occlusionStrength: next.occlusionStrength ?? occlusionStrength,
        alphaMode: next.alphaMode ?? alphaMode,
        alphaCutoff: next.alphaCutoff ?? alphaCutoff,
        effectMask: next.effectMask ?? effectMask,
        transmission: next.transmission ?? transmission,
        transmissionTexture: next.transmissionTexture ?? transmissionTexture,
        ior: next.ior ?? ior,
        thickness: next.thickness ?? thickness,
        thicknessTexture: next.thicknessTexture ?? thicknessTexture,
        attenuationColor: next.attenuationColor ?? attenuationColor,
        attenuationDistance: next.attenuationDistance ?? attenuationDistance,
        clearcoat: next.clearcoat ?? clearcoat,
        clearcoatTexture: next.clearcoatTexture ?? clearcoatTexture,
        clearcoatRoughness: next.clearcoatRoughness ?? clearcoatRoughness,
        clearcoatRoughnessTexture:
            next.clearcoatRoughnessTexture ?? clearcoatRoughnessTexture,
        clearcoatNormalTexture:
            next.clearcoatNormalTexture ?? clearcoatNormalTexture,
        clearcoatNormalScale: next.clearcoatNormalScale ?? clearcoatNormalScale,
        specular: next.specular ?? specular,
        specularTexture: next.specularTexture ?? specularTexture,
        specularColorFactor: next.specularColorFactor ?? specularColorFactor,
        specularColorTexture: next.specularColorTexture ?? specularColorTexture,
        visible: next.visible ?? visible,
      );

  List<ViewerDiagnostic> validate(
    PartAddress address, {
    MaterialExtensionSupport support = MaterialExtensionSupport.unsupported,
  }) {
    final unsupportedDiagnostics = <ViewerDiagnostic>[
      ..._glassSupportDiagnostics(address, support),
      if (hasClearcoatOverride && !support.clearcoat)
        _clearcoatUnsupportedDiagnostic(address),
      if (hasSpecularOverride && !support.specular)
        _specularUnsupportedDiagnostic(address),
    ];
    if (unsupportedDiagnostics.isNotEmpty) {
      return unsupportedDiagnostics;
    }
    final effectMaskDiagnostics = <ViewerDiagnostic>[
      if (effectMask != null) ...effectMask!.validate(address),
      if (effectMask != null && !_effectMaskAllowedInResolvedFamily())
        _effectMaskFamilyDiagnostic(address),
    ];
    if (effectMaskDiagnostics.isNotEmpty) {
      return effectMaskDiagnostics;
    }
    return <ViewerDiagnostic>[
      if (!_isUnitInterval(metallic))
        _rangeDiagnostic(address, 'metallic', metallic!),
      if (!_isUnitInterval(roughness))
        _rangeDiagnostic(address, 'roughness', roughness!),
      if (!_isUnitInterval(occlusionStrength))
        _rangeDiagnostic(address, 'occlusionStrength', occlusionStrength!),
      if (!_isUnitInterval(specular))
        _rangeDiagnostic(address, 'specular', specular!),
      if (!_isUnitInterval(alphaCutoff))
        _rangeDiagnostic(address, 'alphaCutoff', alphaCutoff!),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (baseColorFactor != null)
          'baseColorFactor': List<double>.of(baseColorFactor!),
        if (baseColorTexture != null)
          'baseColorTexture': baseColorTexture!.toJson(),
        if (metallicRoughnessTexture != null)
          'metallicRoughnessTexture': metallicRoughnessTexture!.toJson(),
        if (normalTexture != null) 'normalTexture': normalTexture!.toJson(),
        if (normalScale != null) 'normalScale': normalScale,
        if (metallic != null) 'metallic': metallic,
        if (roughness != null) 'roughness': roughness,
        if (emissiveFactor != null)
          'emissiveFactor': List<double>.of(emissiveFactor!),
        if (emissiveTexture != null)
          'emissiveTexture': emissiveTexture!.toJson(),
        if (occlusionTexture != null)
          'occlusionTexture': occlusionTexture!.toJson(),
        if (occlusionStrength != null) 'occlusionStrength': occlusionStrength,
        if (alphaMode != null) 'alphaMode': alphaMode!.name,
        if (alphaCutoff != null) 'alphaCutoff': alphaCutoff,
        if (effectMask != null) 'effectMask': effectMask!.toJson(),
        if (transmission != null) 'transmission': transmission,
        if (transmissionTexture != null)
          'transmissionTexture': transmissionTexture!.toJson(),
        if (ior != null) 'ior': ior,
        if (thickness != null) 'thickness': thickness,
        if (thicknessTexture != null)
          'thicknessTexture': thicknessTexture!.toJson(),
        if (attenuationColor != null)
          'attenuationColor': List<double>.of(attenuationColor!),
        if (attenuationDistance != null)
          'attenuationDistance': attenuationDistance,
        if (clearcoat != null) 'clearcoat': clearcoat,
        if (clearcoatTexture != null)
          'clearcoatTexture': clearcoatTexture!.toJson(),
        if (clearcoatRoughness != null)
          'clearcoatRoughness': clearcoatRoughness,
        if (clearcoatRoughnessTexture != null)
          'clearcoatRoughnessTexture': clearcoatRoughnessTexture!.toJson(),
        if (clearcoatNormalTexture != null)
          'clearcoatNormalTexture': clearcoatNormalTexture!.toJson(),
        if (clearcoatNormalScale != null)
          'clearcoatNormalScale': clearcoatNormalScale,
        if (specular != null) 'specular': specular,
        if (specularTexture != null)
          'specularTexture': specularTexture!.toJson(),
        if (specularColorFactor != null)
          'specularColorFactor': List<double>.of(specularColorFactor!),
        if (specularColorTexture != null)
          'specularColorTexture': specularColorTexture!.toJson(),
        if (visible != null) 'visible': visible,
      };

  static MaterialPatch fromJson(Map<String, Object?> json) {
    return MaterialPatch(
      baseColorFactor: _doubleList(json['baseColorFactor'], 'baseColorFactor'),
      baseColorTexture: _textureSource(json, 'baseColorTexture'),
      metallicRoughnessTexture:
          _textureSource(json, 'metallicRoughnessTexture'),
      normalTexture: _textureSource(json, 'normalTexture'),
      normalScale: _doubleValue(json['normalScale'], 'normalScale'),
      metallic: _doubleValue(json['metallic'], 'metallic'),
      roughness: _doubleValue(json['roughness'], 'roughness'),
      emissiveFactor: _doubleList(json['emissiveFactor'], 'emissiveFactor'),
      emissiveTexture: _textureSource(json, 'emissiveTexture'),
      occlusionTexture: _textureSource(json, 'occlusionTexture'),
      occlusionStrength:
          _doubleValue(json['occlusionStrength'], 'occlusionStrength'),
      alphaMode: _alphaMode(json['alphaMode']),
      alphaCutoff: _doubleValue(json['alphaCutoff'], 'alphaCutoff'),
      effectMask: _effectMask(json, 'effectMask'),
      transmission: _doubleValue(json['transmission'], 'transmission'),
      transmissionTexture: _textureSource(json, 'transmissionTexture'),
      ior: _doubleValue(json['ior'], 'ior'),
      thickness: _doubleValue(json['thickness'], 'thickness'),
      thicknessTexture: _textureSource(json, 'thicknessTexture'),
      attenuationColor:
          _doubleList(json['attenuationColor'], 'attenuationColor'),
      attenuationDistance:
          _doubleValue(json['attenuationDistance'], 'attenuationDistance'),
      clearcoat: _doubleValue(json['clearcoat'], 'clearcoat'),
      clearcoatTexture: _textureSource(json, 'clearcoatTexture'),
      clearcoatRoughness:
          _doubleValue(json['clearcoatRoughness'], 'clearcoatRoughness'),
      clearcoatRoughnessTexture:
          _textureSource(json, 'clearcoatRoughnessTexture'),
      clearcoatNormalTexture: _textureSource(json, 'clearcoatNormalTexture'),
      clearcoatNormalScale:
          _doubleValue(json['clearcoatNormalScale'], 'clearcoatNormalScale'),
      specular: _doubleValue(json['specular'], 'specular'),
      specularTexture: _textureSource(json, 'specularTexture'),
      specularColorFactor:
          _doubleList(json['specularColorFactor'], 'specularColorFactor'),
      specularColorTexture: _textureSource(json, 'specularColorTexture'),
      visible: json['visible'] as bool?,
    );
  }

  bool _effectMaskAllowedInResolvedFamily() {
    if (hasGlassOverride) {
      return false;
    }
    if (alphaMode == MaterialAlphaMode.mask ||
        alphaMode == MaterialAlphaMode.blend) {
      return false;
    }
    if (alphaMode == MaterialAlphaMode.opaque) {
      return true;
    }
    final factor = baseColorFactor;
    return factor == null || factor.length < 4 || factor[3] >= 1.0;
  }

  List<ViewerDiagnostic> _glassSupportDiagnostics(
    PartAddress address,
    MaterialExtensionSupport support,
  ) {
    final missingExtensions = <String>[
      if ((transmission != null || transmissionTexture != null) &&
          !support.transmission)
        'KHR_materials_transmission',
      if (ior != null && !support.ior) 'KHR_materials_ior',
      if ((thickness != null ||
              thicknessTexture != null ||
              attenuationColor != null ||
              attenuationDistance != null) &&
          !support.volume)
        'KHR_materials_volume',
    ];
    if (missingExtensions.isEmpty) {
      return const <ViewerDiagnostic>[];
    }
    return <ViewerDiagnostic>[
      _glassUnsupportedDiagnostic(
        address,
        extensions: List<String>.unmodifiable(missingExtensions),
      ),
    ];
  }
}

MaterialAlphaMode? _alphaMode(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ArgumentError.value(value, 'alphaMode', 'Expected a string');
  }
  for (final mode in MaterialAlphaMode.values) {
    if (mode.name == value) {
      return mode;
    }
  }
  throw ArgumentError.value(value, 'alphaMode', 'Unsupported alpha mode');
}

bool _isUnitInterval(double? value) =>
    value == null || (value >= 0 && value <= 1);

ViewerDiagnostic _rangeDiagnostic(
  PartAddress address,
  String field,
  double value,
) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.invalidMaterialOverride,
    message: 'Material override value must be in the 0..1 range.',
    details: <String, Object?>{
      'part': address.debugPath,
      'field': field,
      'value': value,
      'min': 0,
      'max': 1,
    },
  );
}

ViewerDiagnostic _glassUnsupportedDiagnostic(
  PartAddress address, {
  required List<String> extensions,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedMaterialFeature,
    message:
        'Transmission/glass material overrides require flutter_scene support for transmission, IOR, and volume attenuation.',
    details: <String, Object?>{
      'part': address.debugPath,
      'extensions': extensions,
      'upstreamPackage': 'flutter_scene',
      'status': 'unsupported',
    },
  );
}

ViewerDiagnostic _clearcoatUnsupportedDiagnostic(PartAddress address) {
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

ViewerDiagnostic _specularUnsupportedDiagnostic(PartAddress address) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedMaterialFeature,
    message:
        'Specular material overrides require flutter_scene support for KHR_materials_specular.',
    details: <String, Object?>{
      'part': address.debugPath,
      'extensions': const <String>['KHR_materials_specular'],
      'upstreamPackage': 'flutter_scene',
      'status': 'unsupported',
    },
  );
}

ViewerDiagnostic _effectMaskFamilyDiagnostic(PartAddress address) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedMaterialFeature,
    message:
        'Material effect masks are opaque-family data maps and cannot be combined with alpha cutout, alpha blend, or glass material families.',
    details: <String, Object?>{
      'part': address.debugPath,
      'feature': 'effectMask',
      'requiredFamily': 'opaque',
    },
  );
}

double? _doubleValue(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, name, 'Expected a number');
}

List<double>? _doubleList(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw ArgumentError.value(value, name, 'Expected a list');
  }
  return List<double>.unmodifiable(
    value.map((item) {
      if (item is num) {
        return item.toDouble();
      }
      throw ArgumentError.value(value, name, 'Expected numeric values');
    }),
  );
}

Map<String, Object?> _objectMap(Object value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'Expected a map');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

TextureSource? _textureSource(Map<String, Object?> json, String name) {
  final rawTexture = json[name];
  return rawTexture == null
      ? null
      : TextureSource.fromJson(_objectMap(rawTexture, name));
}

MaterialEffectMask? _effectMask(Map<String, Object?> json, String name) {
  final rawMask = json[name];
  return rawMask == null
      ? null
      : MaterialEffectMask.fromJson(_objectMap(rawMask, name));
}
