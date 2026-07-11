import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'material_effect_mask.dart';
import 'material_extension_policy.dart';
import 'part_address.dart';
import 'texture_binding.dart';
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
    this.baseColorTextureBinding,
    this.metallicRoughnessTexture,
    this.metallicRoughnessTextureBinding,
    this.normalTexture,
    this.normalTextureBinding,
    this.normalScale,
    this.metallic,
    this.roughness,
    this.emissiveFactor,
    this.emissiveTexture,
    this.emissiveTextureBinding,
    this.occlusionTexture,
    this.occlusionTextureBinding,
    this.occlusionStrength,
    this.alphaMode,
    this.alphaCutoff,
    this.effectMask,
    this.transmission,
    this.transmissionTexture,
    this.transmissionTextureBinding,
    this.ior,
    this.thickness,
    this.thicknessTexture,
    this.thicknessTextureBinding,
    this.attenuationColor,
    this.attenuationDistance,
    this.clearcoat,
    this.clearcoatTexture,
    this.clearcoatTextureBinding,
    this.clearcoatRoughness,
    this.clearcoatRoughnessTexture,
    this.clearcoatRoughnessTextureBinding,
    this.clearcoatNormalTexture,
    this.clearcoatNormalTextureBinding,
    this.clearcoatNormalScale,
    this.specular,
    this.specularTexture,
    this.specularTextureBinding,
    this.specularColorFactor,
    this.specularColorTexture,
    this.specularColorTextureBinding,
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

  final MaterialTextureBinding? baseColorTextureBinding;

  final TextureSource? metallicRoughnessTexture;

  final MaterialTextureBinding? metallicRoughnessTextureBinding;

  final TextureSource? normalTexture;

  final MaterialTextureBinding? normalTextureBinding;

  final double? normalScale;

  final double? metallic;

  final double? roughness;

  final List<double>? emissiveFactor;

  final TextureSource? emissiveTexture;

  final MaterialTextureBinding? emissiveTextureBinding;

  final TextureSource? occlusionTexture;

  final MaterialTextureBinding? occlusionTextureBinding;

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

  final MaterialTextureBinding? transmissionTextureBinding;

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

  final MaterialTextureBinding? thicknessTextureBinding;

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

  final MaterialTextureBinding? clearcoatTextureBinding;

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

  final MaterialTextureBinding? clearcoatRoughnessTextureBinding;

  /// KHR_materials_clearcoat clearcoat normal texture.
  ///
  /// This field is intentionally rejected by the current adapter until
  /// flutter_scene exposes real clearcoat support.
  final TextureSource? clearcoatNormalTexture;

  final MaterialTextureBinding? clearcoatNormalTextureBinding;

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

  final MaterialTextureBinding? specularTextureBinding;

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

  final MaterialTextureBinding? specularColorTextureBinding;

  final bool? visible;

  bool get isEmpty =>
      baseColorFactor == null &&
      baseColorTexture == null &&
      baseColorTextureBinding == null &&
      metallicRoughnessTexture == null &&
      metallicRoughnessTextureBinding == null &&
      normalTexture == null &&
      normalTextureBinding == null &&
      normalScale == null &&
      metallic == null &&
      roughness == null &&
      emissiveFactor == null &&
      emissiveTexture == null &&
      emissiveTextureBinding == null &&
      occlusionTexture == null &&
      occlusionTextureBinding == null &&
      occlusionStrength == null &&
      alphaMode == null &&
      alphaCutoff == null &&
      effectMask == null &&
      transmission == null &&
      transmissionTexture == null &&
      transmissionTextureBinding == null &&
      ior == null &&
      thickness == null &&
      thicknessTexture == null &&
      thicknessTextureBinding == null &&
      attenuationColor == null &&
      attenuationDistance == null &&
      clearcoat == null &&
      clearcoatTexture == null &&
      clearcoatTextureBinding == null &&
      clearcoatRoughness == null &&
      clearcoatRoughnessTexture == null &&
      clearcoatRoughnessTextureBinding == null &&
      clearcoatNormalTexture == null &&
      clearcoatNormalTextureBinding == null &&
      clearcoatNormalScale == null &&
      specular == null &&
      specularTexture == null &&
      specularTextureBinding == null &&
      specularColorFactor == null &&
      specularColorTexture == null &&
      specularColorTextureBinding == null &&
      visible == null;

  /// Whether this patch contains transmission or volume intent.
  bool get hasTransmissionOrVolumeOverride =>
      transmission != null ||
      transmissionTexture != null ||
      transmissionTextureBinding != null ||
      thickness != null ||
      thicknessTexture != null ||
      thicknessTextureBinding != null ||
      attenuationColor != null ||
      attenuationDistance != null;

  /// Whether this patch changes IOR on an otherwise opaque material.
  bool get hasOpaqueIorOverride =>
      ior != null && !hasTransmissionOrVolumeOverride;

  /// Compatibility classification for realistic transmission/glass intent.
  ///
  /// Opaque IOR alone does not make a material glass.
  bool get hasGlassOverride => hasTransmissionOrVolumeOverride;

  bool get hasClearcoatOverride =>
      clearcoat != null ||
      clearcoatTexture != null ||
      clearcoatTextureBinding != null ||
      clearcoatRoughness != null ||
      clearcoatRoughnessTexture != null ||
      clearcoatRoughnessTextureBinding != null ||
      clearcoatNormalTexture != null ||
      clearcoatNormalTextureBinding != null ||
      clearcoatNormalScale != null;

  bool get hasSpecularOverride =>
      specular != null ||
      specularTexture != null ||
      specularTextureBinding != null ||
      specularColorFactor != null ||
      specularColorTexture != null ||
      specularColorTextureBinding != null;

  bool get hasTextureOverride =>
      baseColorTexture != null ||
      baseColorTextureBinding != null ||
      metallicRoughnessTexture != null ||
      metallicRoughnessTextureBinding != null ||
      normalTexture != null ||
      normalTextureBinding != null ||
      emissiveTexture != null ||
      emissiveTextureBinding != null ||
      occlusionTexture != null ||
      occlusionTextureBinding != null ||
      effectMask != null ||
      transmissionTexture != null ||
      transmissionTextureBinding != null ||
      thicknessTexture != null ||
      thicknessTextureBinding != null ||
      clearcoatTexture != null ||
      clearcoatTextureBinding != null ||
      clearcoatRoughnessTexture != null ||
      clearcoatRoughnessTextureBinding != null ||
      clearcoatNormalTexture != null ||
      clearcoatNormalTextureBinding != null ||
      specularTexture != null ||
      specularTextureBinding != null ||
      specularColorTexture != null ||
      specularColorTextureBinding != null;

  /// Returns the explicit binding for [slot], or a default binding wrapping
  /// the source-only compatibility field for that slot.
  MaterialTextureBinding? textureBindingFor(MaterialTextureSlot slot) {
    return switch (slot) {
      MaterialTextureSlot.baseColor =>
        _normalizedBinding(baseColorTextureBinding, baseColorTexture),
      MaterialTextureSlot.metallicRoughness => _normalizedBinding(
          metallicRoughnessTextureBinding,
          metallicRoughnessTexture,
        ),
      MaterialTextureSlot.normal =>
        _normalizedBinding(normalTextureBinding, normalTexture),
      MaterialTextureSlot.occlusion =>
        _normalizedBinding(occlusionTextureBinding, occlusionTexture),
      MaterialTextureSlot.emissive =>
        _normalizedBinding(emissiveTextureBinding, emissiveTexture),
      MaterialTextureSlot.transmission =>
        _normalizedBinding(transmissionTextureBinding, transmissionTexture),
      MaterialTextureSlot.thickness =>
        _normalizedBinding(thicknessTextureBinding, thicknessTexture),
      MaterialTextureSlot.clearcoat =>
        _normalizedBinding(clearcoatTextureBinding, clearcoatTexture),
      MaterialTextureSlot.clearcoatRoughness => _normalizedBinding(
          clearcoatRoughnessTextureBinding,
          clearcoatRoughnessTexture,
        ),
      MaterialTextureSlot.clearcoatNormal => _normalizedBinding(
          clearcoatNormalTextureBinding,
          clearcoatNormalTexture,
        ),
      MaterialTextureSlot.specular =>
        _normalizedBinding(specularTextureBinding, specularTexture),
      MaterialTextureSlot.specularColor => _normalizedBinding(
          specularColorTextureBinding,
          specularColorTexture,
        ),
    };
  }

  MaterialPatch merge(MaterialPatch next) => MaterialPatch(
        baseColorFactor: next.baseColorFactor ?? baseColorFactor,
        baseColorTexture: _mergedSource(
          baseColorTexture,
          next.baseColorTexture,
          next.baseColorTextureBinding,
        ),
        baseColorTextureBinding: _mergedBinding(
          baseColorTextureBinding,
          next.baseColorTextureBinding,
          next.baseColorTexture,
        ),
        metallicRoughnessTexture: _mergedSource(
          metallicRoughnessTexture,
          next.metallicRoughnessTexture,
          next.metallicRoughnessTextureBinding,
        ),
        metallicRoughnessTextureBinding: _mergedBinding(
          metallicRoughnessTextureBinding,
          next.metallicRoughnessTextureBinding,
          next.metallicRoughnessTexture,
        ),
        normalTexture: _mergedSource(
          normalTexture,
          next.normalTexture,
          next.normalTextureBinding,
        ),
        normalTextureBinding: _mergedBinding(
          normalTextureBinding,
          next.normalTextureBinding,
          next.normalTexture,
        ),
        normalScale: next.normalScale ?? normalScale,
        metallic: next.metallic ?? metallic,
        roughness: next.roughness ?? roughness,
        emissiveFactor: next.emissiveFactor ?? emissiveFactor,
        emissiveTexture: _mergedSource(
          emissiveTexture,
          next.emissiveTexture,
          next.emissiveTextureBinding,
        ),
        emissiveTextureBinding: _mergedBinding(
          emissiveTextureBinding,
          next.emissiveTextureBinding,
          next.emissiveTexture,
        ),
        occlusionTexture: _mergedSource(
          occlusionTexture,
          next.occlusionTexture,
          next.occlusionTextureBinding,
        ),
        occlusionTextureBinding: _mergedBinding(
          occlusionTextureBinding,
          next.occlusionTextureBinding,
          next.occlusionTexture,
        ),
        occlusionStrength: next.occlusionStrength ?? occlusionStrength,
        alphaMode: next.alphaMode ?? alphaMode,
        alphaCutoff: next.alphaCutoff ?? alphaCutoff,
        effectMask: next.effectMask ?? effectMask,
        transmission: next.transmission ?? transmission,
        transmissionTexture: _mergedSource(
          transmissionTexture,
          next.transmissionTexture,
          next.transmissionTextureBinding,
        ),
        transmissionTextureBinding: _mergedBinding(
          transmissionTextureBinding,
          next.transmissionTextureBinding,
          next.transmissionTexture,
        ),
        ior: next.ior ?? ior,
        thickness: next.thickness ?? thickness,
        thicknessTexture: _mergedSource(
          thicknessTexture,
          next.thicknessTexture,
          next.thicknessTextureBinding,
        ),
        thicknessTextureBinding: _mergedBinding(
          thicknessTextureBinding,
          next.thicknessTextureBinding,
          next.thicknessTexture,
        ),
        attenuationColor: next.attenuationColor ?? attenuationColor,
        attenuationDistance: next.attenuationDistance ?? attenuationDistance,
        clearcoat: next.clearcoat ?? clearcoat,
        clearcoatTexture: _mergedSource(
          clearcoatTexture,
          next.clearcoatTexture,
          next.clearcoatTextureBinding,
        ),
        clearcoatTextureBinding: _mergedBinding(
          clearcoatTextureBinding,
          next.clearcoatTextureBinding,
          next.clearcoatTexture,
        ),
        clearcoatRoughness: next.clearcoatRoughness ?? clearcoatRoughness,
        clearcoatRoughnessTexture: _mergedSource(
          clearcoatRoughnessTexture,
          next.clearcoatRoughnessTexture,
          next.clearcoatRoughnessTextureBinding,
        ),
        clearcoatRoughnessTextureBinding: _mergedBinding(
          clearcoatRoughnessTextureBinding,
          next.clearcoatRoughnessTextureBinding,
          next.clearcoatRoughnessTexture,
        ),
        clearcoatNormalTexture: _mergedSource(
          clearcoatNormalTexture,
          next.clearcoatNormalTexture,
          next.clearcoatNormalTextureBinding,
        ),
        clearcoatNormalTextureBinding: _mergedBinding(
          clearcoatNormalTextureBinding,
          next.clearcoatNormalTextureBinding,
          next.clearcoatNormalTexture,
        ),
        clearcoatNormalScale: next.clearcoatNormalScale ?? clearcoatNormalScale,
        specular: next.specular ?? specular,
        specularTexture: _mergedSource(
          specularTexture,
          next.specularTexture,
          next.specularTextureBinding,
        ),
        specularTextureBinding: _mergedBinding(
          specularTextureBinding,
          next.specularTextureBinding,
          next.specularTexture,
        ),
        specularColorFactor: next.specularColorFactor ?? specularColorFactor,
        specularColorTexture: _mergedSource(
          specularColorTexture,
          next.specularColorTexture,
          next.specularColorTextureBinding,
        ),
        specularColorTextureBinding: _mergedBinding(
          specularColorTextureBinding,
          next.specularColorTextureBinding,
          next.specularColorTexture,
        ),
        visible: next.visible ?? visible,
      );

  List<ViewerDiagnostic> validate(
    PartAddress address, {
    MaterialExtensionSupport support = MaterialExtensionSupport.unsupported,
  }) {
    final conflictDiagnostics = _textureBindingConflictDiagnostics(address);
    if (conflictDiagnostics.isNotEmpty) {
      return conflictDiagnostics;
    }
    final unsupportedDiagnostics = <ViewerDiagnostic>[
      ..._glassSupportDiagnostics(address, support),
      if (hasClearcoatOverride &&
          !support.supportFor(MaterialExtensionFeature.clearcoat).available)
        _clearcoatUnsupportedDiagnostic(address),
      if (hasSpecularOverride &&
          !support.supportFor(MaterialExtensionFeature.specular).available)
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

  List<ViewerDiagnostic> _textureBindingConflictDiagnostics(
    PartAddress address,
  ) {
    return <ViewerDiagnostic>[
      if (baseColorTexture != null && baseColorTextureBinding != null)
        _textureBindingConflictDiagnostic(
            address, MaterialTextureSlot.baseColor),
      if (metallicRoughnessTexture != null &&
          metallicRoughnessTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.metallicRoughness,
        ),
      if (normalTexture != null && normalTextureBinding != null)
        _textureBindingConflictDiagnostic(address, MaterialTextureSlot.normal),
      if (occlusionTexture != null && occlusionTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.occlusion,
        ),
      if (emissiveTexture != null && emissiveTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.emissive,
        ),
      if (transmissionTexture != null && transmissionTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.transmission,
        ),
      if (thicknessTexture != null && thicknessTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.thickness,
        ),
      if (clearcoatTexture != null && clearcoatTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.clearcoat,
        ),
      if (clearcoatRoughnessTexture != null &&
          clearcoatRoughnessTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.clearcoatRoughness,
        ),
      if (clearcoatNormalTexture != null &&
          clearcoatNormalTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.clearcoatNormal,
        ),
      if (specularTexture != null && specularTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.specular,
        ),
      if (specularColorTexture != null && specularColorTextureBinding != null)
        _textureBindingConflictDiagnostic(
          address,
          MaterialTextureSlot.specularColor,
        ),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (baseColorFactor != null)
          'baseColorFactor': List<double>.of(baseColorFactor!),
        if (baseColorTexture != null)
          'baseColorTexture': baseColorTexture!.toJson(),
        if (baseColorTextureBinding != null)
          'baseColorTextureBinding': baseColorTextureBinding!.toJson(),
        if (metallicRoughnessTexture != null)
          'metallicRoughnessTexture': metallicRoughnessTexture!.toJson(),
        if (metallicRoughnessTextureBinding != null)
          'metallicRoughnessTextureBinding':
              metallicRoughnessTextureBinding!.toJson(),
        if (normalTexture != null) 'normalTexture': normalTexture!.toJson(),
        if (normalTextureBinding != null)
          'normalTextureBinding': normalTextureBinding!.toJson(),
        if (normalScale != null) 'normalScale': normalScale,
        if (metallic != null) 'metallic': metallic,
        if (roughness != null) 'roughness': roughness,
        if (emissiveFactor != null)
          'emissiveFactor': List<double>.of(emissiveFactor!),
        if (emissiveTexture != null)
          'emissiveTexture': emissiveTexture!.toJson(),
        if (emissiveTextureBinding != null)
          'emissiveTextureBinding': emissiveTextureBinding!.toJson(),
        if (occlusionTexture != null)
          'occlusionTexture': occlusionTexture!.toJson(),
        if (occlusionTextureBinding != null)
          'occlusionTextureBinding': occlusionTextureBinding!.toJson(),
        if (occlusionStrength != null) 'occlusionStrength': occlusionStrength,
        if (alphaMode != null) 'alphaMode': alphaMode!.name,
        if (alphaCutoff != null) 'alphaCutoff': alphaCutoff,
        if (effectMask != null) 'effectMask': effectMask!.toJson(),
        if (transmission != null) 'transmission': transmission,
        if (transmissionTexture != null)
          'transmissionTexture': transmissionTexture!.toJson(),
        if (transmissionTextureBinding != null)
          'transmissionTextureBinding': transmissionTextureBinding!.toJson(),
        if (ior != null) 'ior': ior,
        if (thickness != null) 'thickness': thickness,
        if (thicknessTexture != null)
          'thicknessTexture': thicknessTexture!.toJson(),
        if (thicknessTextureBinding != null)
          'thicknessTextureBinding': thicknessTextureBinding!.toJson(),
        if (attenuationColor != null)
          'attenuationColor': List<double>.of(attenuationColor!),
        if (attenuationDistance != null)
          'attenuationDistance': attenuationDistance,
        if (clearcoat != null) 'clearcoat': clearcoat,
        if (clearcoatTexture != null)
          'clearcoatTexture': clearcoatTexture!.toJson(),
        if (clearcoatTextureBinding != null)
          'clearcoatTextureBinding': clearcoatTextureBinding!.toJson(),
        if (clearcoatRoughness != null)
          'clearcoatRoughness': clearcoatRoughness,
        if (clearcoatRoughnessTexture != null)
          'clearcoatRoughnessTexture': clearcoatRoughnessTexture!.toJson(),
        if (clearcoatRoughnessTextureBinding != null)
          'clearcoatRoughnessTextureBinding':
              clearcoatRoughnessTextureBinding!.toJson(),
        if (clearcoatNormalTexture != null)
          'clearcoatNormalTexture': clearcoatNormalTexture!.toJson(),
        if (clearcoatNormalTextureBinding != null)
          'clearcoatNormalTextureBinding':
              clearcoatNormalTextureBinding!.toJson(),
        if (clearcoatNormalScale != null)
          'clearcoatNormalScale': clearcoatNormalScale,
        if (specular != null) 'specular': specular,
        if (specularTexture != null)
          'specularTexture': specularTexture!.toJson(),
        if (specularTextureBinding != null)
          'specularTextureBinding': specularTextureBinding!.toJson(),
        if (specularColorFactor != null)
          'specularColorFactor': List<double>.of(specularColorFactor!),
        if (specularColorTexture != null)
          'specularColorTexture': specularColorTexture!.toJson(),
        if (specularColorTextureBinding != null)
          'specularColorTextureBinding': specularColorTextureBinding!.toJson(),
        if (visible != null) 'visible': visible,
      };

  static MaterialPatch fromJson(Map<String, Object?> json) {
    _rejectTextureBindingConflicts(json);
    return MaterialPatch(
      baseColorFactor: _doubleList(json['baseColorFactor'], 'baseColorFactor'),
      baseColorTexture: _textureSource(json, 'baseColorTexture'),
      baseColorTextureBinding: _textureBinding(json, 'baseColorTextureBinding'),
      metallicRoughnessTexture:
          _textureSource(json, 'metallicRoughnessTexture'),
      metallicRoughnessTextureBinding:
          _textureBinding(json, 'metallicRoughnessTextureBinding'),
      normalTexture: _textureSource(json, 'normalTexture'),
      normalTextureBinding: _textureBinding(json, 'normalTextureBinding'),
      normalScale: _doubleValue(json['normalScale'], 'normalScale'),
      metallic: _doubleValue(json['metallic'], 'metallic'),
      roughness: _doubleValue(json['roughness'], 'roughness'),
      emissiveFactor: _doubleList(json['emissiveFactor'], 'emissiveFactor'),
      emissiveTexture: _textureSource(json, 'emissiveTexture'),
      emissiveTextureBinding: _textureBinding(json, 'emissiveTextureBinding'),
      occlusionTexture: _textureSource(json, 'occlusionTexture'),
      occlusionTextureBinding: _textureBinding(json, 'occlusionTextureBinding'),
      occlusionStrength:
          _doubleValue(json['occlusionStrength'], 'occlusionStrength'),
      alphaMode: _alphaMode(json['alphaMode']),
      alphaCutoff: _doubleValue(json['alphaCutoff'], 'alphaCutoff'),
      effectMask: _effectMask(json, 'effectMask'),
      transmission: _doubleValue(json['transmission'], 'transmission'),
      transmissionTexture: _textureSource(json, 'transmissionTexture'),
      transmissionTextureBinding:
          _textureBinding(json, 'transmissionTextureBinding'),
      ior: _doubleValue(json['ior'], 'ior'),
      thickness: _doubleValue(json['thickness'], 'thickness'),
      thicknessTexture: _textureSource(json, 'thicknessTexture'),
      thicknessTextureBinding: _textureBinding(json, 'thicknessTextureBinding'),
      attenuationColor:
          _doubleList(json['attenuationColor'], 'attenuationColor'),
      attenuationDistance:
          _doubleValue(json['attenuationDistance'], 'attenuationDistance'),
      clearcoat: _doubleValue(json['clearcoat'], 'clearcoat'),
      clearcoatTexture: _textureSource(json, 'clearcoatTexture'),
      clearcoatTextureBinding: _textureBinding(json, 'clearcoatTextureBinding'),
      clearcoatRoughness:
          _doubleValue(json['clearcoatRoughness'], 'clearcoatRoughness'),
      clearcoatRoughnessTexture:
          _textureSource(json, 'clearcoatRoughnessTexture'),
      clearcoatRoughnessTextureBinding:
          _textureBinding(json, 'clearcoatRoughnessTextureBinding'),
      clearcoatNormalTexture: _textureSource(json, 'clearcoatNormalTexture'),
      clearcoatNormalTextureBinding:
          _textureBinding(json, 'clearcoatNormalTextureBinding'),
      clearcoatNormalScale:
          _doubleValue(json['clearcoatNormalScale'], 'clearcoatNormalScale'),
      specular: _doubleValue(json['specular'], 'specular'),
      specularTexture: _textureSource(json, 'specularTexture'),
      specularTextureBinding: _textureBinding(json, 'specularTextureBinding'),
      specularColorFactor:
          _doubleList(json['specularColorFactor'], 'specularColorFactor'),
      specularColorTexture: _textureSource(json, 'specularColorTexture'),
      specularColorTextureBinding:
          _textureBinding(json, 'specularColorTextureBinding'),
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
      if ((transmission != null ||
              transmissionTexture != null ||
              transmissionTextureBinding != null) &&
          !support.supportFor(MaterialExtensionFeature.transmission).available)
        'KHR_materials_transmission',
      if (ior != null &&
          !support.supportFor(MaterialExtensionFeature.ior).available)
        'KHR_materials_ior',
      if ((thickness != null ||
              thicknessTexture != null ||
              thicknessTextureBinding != null ||
              attenuationColor != null ||
              attenuationDistance != null) &&
          !support.supportFor(MaterialExtensionFeature.volume).available)
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

MaterialTextureBinding? _normalizedBinding(
  MaterialTextureBinding? binding,
  TextureSource? source,
) {
  if (binding != null) {
    return binding;
  }
  return source == null ? null : MaterialTextureBinding(source: source);
}

TextureSource? _mergedSource(
  TextureSource? current,
  TextureSource? next,
  MaterialTextureBinding? nextBinding,
) =>
    next ?? (nextBinding == null ? current : null);

MaterialTextureBinding? _mergedBinding(
  MaterialTextureBinding? current,
  MaterialTextureBinding? next,
  TextureSource? nextSource,
) =>
    next ?? (nextSource == null ? current : null);

ViewerDiagnostic _textureBindingConflictDiagnostic(
  PartAddress address,
  MaterialTextureSlot slot,
) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.invalidMaterialOverride,
    message:
        'A material texture slot cannot contain both a source-only value and a texture binding.',
    details: <String, Object?>{
      'part': address.debugPath,
      'slot': slot.name,
      'sourceField': _sourceFieldFor(slot),
      'bindingField': _bindingFieldFor(slot),
    },
  );
}

void _rejectTextureBindingConflicts(Map<String, Object?> json) {
  for (final slot in MaterialTextureSlot.values) {
    final sourceField = _sourceFieldFor(slot);
    final bindingField = _bindingFieldFor(slot);
    if (json[sourceField] != null && json[bindingField] != null) {
      throw FormatException(
        '$sourceField and $bindingField cannot both be present',
        json,
      );
    }
  }
}

String _sourceFieldFor(MaterialTextureSlot slot) => switch (slot) {
      MaterialTextureSlot.baseColor => 'baseColorTexture',
      MaterialTextureSlot.metallicRoughness => 'metallicRoughnessTexture',
      MaterialTextureSlot.normal => 'normalTexture',
      MaterialTextureSlot.occlusion => 'occlusionTexture',
      MaterialTextureSlot.emissive => 'emissiveTexture',
      MaterialTextureSlot.transmission => 'transmissionTexture',
      MaterialTextureSlot.thickness => 'thicknessTexture',
      MaterialTextureSlot.clearcoat => 'clearcoatTexture',
      MaterialTextureSlot.clearcoatRoughness => 'clearcoatRoughnessTexture',
      MaterialTextureSlot.clearcoatNormal => 'clearcoatNormalTexture',
      MaterialTextureSlot.specular => 'specularTexture',
      MaterialTextureSlot.specularColor => 'specularColorTexture',
    };

String _bindingFieldFor(MaterialTextureSlot slot) =>
    '${_sourceFieldFor(slot)}Binding';

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

MaterialTextureBinding? _textureBinding(
  Map<String, Object?> json,
  String name,
) {
  final rawBinding = json[name];
  if (rawBinding == null) {
    return null;
  }
  try {
    return MaterialTextureBinding.fromJson(_objectMap(rawBinding, name));
  } on FormatException {
    rethrow;
  } on ArgumentError catch (error) {
    throw FormatException(error.message.toString(), rawBinding);
  }
}

MaterialEffectMask? _effectMask(Map<String, Object?> json, String name) {
  final rawMask = json[name];
  return rawMask == null
      ? null
      : MaterialEffectMask.fromJson(_objectMap(rawMask, name));
}
