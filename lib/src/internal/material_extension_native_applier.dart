import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_binding.dart';

/// Narrow renderer-native material interface for production extension fields.
abstract interface class NativeMaterialExtensionMaterial {
  set transmissionFactor(double value);
  set ior(double value);
  set thicknessFactor(double value);
  set attenuationDistance(double value);
  set attenuationColor(List<double> value);
  set clearcoatFactor(double value);
  set clearcoatRoughnessFactor(double value);
  set clearcoatNormalScale(double value);
  set clearcoatTexture(Object? value);
  set clearcoatRoughnessTexture(Object? value);
  set clearcoatNormalTexture(Object? value);
}

List<ViewerDiagnostic> applyNativeMaterialExtensionPatch({
  required NativeMaterialExtensionMaterial material,
  required MaterialPatch patch,
  required MaterialExtensionSupport support,
  Object? clearcoatTexture,
  Object? clearcoatRoughnessTexture,
  Object? clearcoatNormalTexture,
}) {
  final diagnostic = nativeMaterialExtensionPatchDiagnostic(
    support: support,
    patch: patch,
  );
  if (diagnostic != null) {
    return <ViewerDiagnostic>[diagnostic];
  }

  final transmission = patch.transmission;
  if (transmission != null) {
    material.transmissionFactor = transmission;
  }
  final ior = patch.ior;
  if (ior != null) {
    material.ior = ior;
  }
  final thickness = patch.thickness;
  if (thickness != null) {
    material.thicknessFactor = thickness;
  }
  final attenuationDistance = patch.attenuationDistance;
  if (attenuationDistance != null) {
    material.attenuationDistance = attenuationDistance;
  }
  final attenuationColor = patch.attenuationColor;
  if (attenuationColor != null) {
    material.attenuationColor = List<double>.unmodifiable(attenuationColor);
  }
  final clearcoat = patch.clearcoat;
  if (clearcoat != null) {
    material.clearcoatFactor = clearcoat;
  }
  final clearcoatRoughness = patch.clearcoatRoughness;
  if (clearcoatRoughness != null) {
    material.clearcoatRoughnessFactor = clearcoatRoughness;
  }
  final clearcoatNormalScale = patch.clearcoatNormalScale;
  if (clearcoatNormalScale != null) {
    material.clearcoatNormalScale = clearcoatNormalScale;
  }
  if (patch.textureBindingFor(MaterialTextureSlot.clearcoat) != null) {
    material.clearcoatTexture = clearcoatTexture;
  }
  if (patch.textureBindingFor(MaterialTextureSlot.clearcoatRoughness) != null) {
    material.clearcoatRoughnessTexture = clearcoatRoughnessTexture;
  }
  if (patch.textureBindingFor(MaterialTextureSlot.clearcoatNormal) != null) {
    material.clearcoatNormalTexture = clearcoatNormalTexture;
  }

  return const <ViewerDiagnostic>[];
}

bool supportsNativeMaterialExtensionPatch(
  MaterialExtensionSupport support,
  MaterialPatch patch,
) =>
    nativeMaterialExtensionPatchDiagnostic(
      support: support,
      patch: patch,
    ) ==
    null;

bool hasNativeMaterialExtensionIntent(MaterialPatch patch) =>
    patch.hasGlassOverride ||
    patch.hasClearcoatOverride ||
    patch.hasSpecularOverride ||
    patch.ior != null;

ViewerDiagnostic? nativeMaterialExtensionPatchDiagnostic({
  required MaterialExtensionSupport support,
  required MaterialPatch patch,
  PartAddress? address,
}) {
  if (support.backendKind != MaterialExtensionBackendKind.rendererNative) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  final unsupportedTextureSlots = <String>[
    for (final slot in const <MaterialTextureSlot>[
      MaterialTextureSlot.transmission,
      MaterialTextureSlot.thickness,
      MaterialTextureSlot.specular,
      MaterialTextureSlot.specularColor,
    ])
      if (patch.textureBindingFor(slot) != null) slot.name,
  ];
  if (unsupportedTextureSlots.isNotEmpty) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The renderer-native material extension contract exposes scalar fields only and cannot consume extension texture bindings.',
      details: <String, Object?>{
        if (address != null) 'part': address.debugPath,
        'limitation': 'rendererNativeExtensionTextureContractMissing',
        'slots': unsupportedTextureSlots,
        'backendKind': support.backendKind.name,
        'status': 'unsupported',
        'productionBlocker':
            'rendererNativeMaterialExtensionTextureContractMissing',
        'nextStep': 'implementRendererNativeExtensionTextureContract',
      },
    );
  }
  final unsupportedSpecularFields = <String>[
    if (patch.specular != null) 'specular',
    if (patch.specularColorFactor != null) 'specularColorFactor',
  ];
  if (unsupportedSpecularFields.isNotEmpty) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The renderer-native material extension contract does not expose specular or specular-color setters.',
      details: <String, Object?>{
        if (address != null) 'part': address.debugPath,
        'feature': 'specular',
        'limitation': 'rendererNativeSpecularContractMissing',
        'fields': unsupportedSpecularFields,
        'backendKind': support.backendKind.name,
        'status': 'unsupported',
        'productionBlocker': 'rendererNativeSpecularContractMissing',
        'nextStep': 'implementRendererNativeSpecularContract',
      },
    );
  }
  final coreFields = _mixedCorePatchFields(patch);
  if (coreFields.isNotEmpty && _hasNonClearcoatNativeIntent(patch)) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The scalar-only renderer-native extension contract cannot apply core PBR state and extension state atomically.',
      details: <String, Object?>{
        if (address != null) 'part': address.debugPath,
        'limitation': 'rendererNativeMixedCoreExtensionPatchUnsupported',
        'fields': coreFields,
        'backendKind': support.backendKind.name,
        'status': 'unsupported',
        'nextStep': 'implementCombinedRendererNativeMaterialContract',
      },
    );
  }
  if (patch.hasClearcoatOverride &&
      !support.supportFor(MaterialExtensionFeature.clearcoat).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  if (patch.transmission != null &&
      !support.supportFor(MaterialExtensionFeature.transmission).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  if (patch.ior != null &&
      !support.supportFor(MaterialExtensionFeature.ior).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  if ((patch.thickness != null ||
          patch.attenuationColor != null ||
          patch.attenuationDistance != null) &&
      !support.supportFor(MaterialExtensionFeature.volume).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  return null;
}

bool _hasNonClearcoatNativeIntent(MaterialPatch patch) =>
    patch.transmission != null ||
    patch.textureBindingFor(MaterialTextureSlot.transmission) != null ||
    patch.ior != null ||
    patch.thickness != null ||
    patch.textureBindingFor(MaterialTextureSlot.thickness) != null ||
    patch.attenuationColor != null ||
    patch.attenuationDistance != null;

List<String> _mixedCorePatchFields(MaterialPatch patch) => <String>[
      if (patch.baseColorFactor != null) 'baseColorFactor',
      if (patch.textureBindingFor(MaterialTextureSlot.baseColor) != null)
        'baseColorTexture',
      if (patch.textureBindingFor(MaterialTextureSlot.metallicRoughness) !=
          null)
        'metallicRoughnessTexture',
      if (patch.textureBindingFor(MaterialTextureSlot.normal) != null)
        'normalTexture',
      if (patch.normalScale != null) 'normalScale',
      if (patch.metallic != null) 'metallic',
      if (patch.roughness != null) 'roughness',
      if (patch.emissiveFactor != null) 'emissiveFactor',
      if (patch.textureBindingFor(MaterialTextureSlot.emissive) != null)
        'emissiveTexture',
      if (patch.textureBindingFor(MaterialTextureSlot.occlusion) != null)
        'occlusionTexture',
      if (patch.occlusionStrength != null) 'occlusionStrength',
      if (patch.alphaMode != null) 'alphaMode',
      if (patch.alphaCutoff != null) 'alphaCutoff',
      if (patch.effectMask != null) 'effectMask',
      if (patch.visible != null) 'visible',
    ];

ViewerDiagnostic _nativeMaterialExtensionUnsupportedDiagnostic({
  required MaterialExtensionSupport support,
  required PartAddress? address,
}) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Production material extension patches require renderer-native material fields.',
      details: <String, Object?>{
        if (address != null) 'part': address.debugPath,
        'backendKind': support.backendKind.name,
        'status': 'unsupported',
        'productionBlocker': 'rendererNativeMaterialExtensionContractMissing',
      },
    );
