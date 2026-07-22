import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';
import '../part_address.dart';
import '../texture_binding.dart';

/// Narrow renderer-native material interface for production extension fields.
abstract interface class NativeMaterialExtensionMaterial {
  set transmissionFactor(double value);
  set transmissionTexture(Object? value);
  set transmissionTextureTransform(TextureTransform value);
  set ior(double value);
  set thicknessFactor(double value);
  set thicknessTexture(Object? value);
  set thicknessTextureTransform(TextureTransform value);
  set attenuationDistance(double value);
  set attenuationColor(List<double> value);
  set clearcoatFactor(double value);
  set clearcoatRoughnessFactor(double value);
  set clearcoatNormalScale(double value);
  set clearcoatTexture(Object? value);
  set clearcoatRoughnessTexture(Object? value);
  set clearcoatNormalTexture(Object? value);
  set sheenColorFactor(List<double> value);
  set sheenRoughnessFactor(double value);
  set sheenColorTexture(Object? value);
  set sheenColorTextureTexCoord(int value);
  set sheenColorTextureTransform(TextureTransform value);
  set sheenRoughnessTexture(Object? value);
  set sheenRoughnessTextureTexCoord(int value);
  set sheenRoughnessTextureTransform(TextureTransform value);
}

List<ViewerDiagnostic> applyNativeMaterialExtensionPatch({
  required NativeMaterialExtensionMaterial material,
  required MaterialPatch patch,
  required MaterialExtensionSupport support,
  Object? transmissionTexture,
  Object? thicknessTexture,
  Object? clearcoatTexture,
  Object? clearcoatRoughnessTexture,
  Object? clearcoatNormalTexture,
  Object? sheenColorTexture,
  Object? sheenRoughnessTexture,
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
  final transmissionBinding =
      patch.textureBindingFor(MaterialTextureSlot.transmission);
  if (transmissionBinding != null) {
    material.transmissionTexture = transmissionTexture;
    material.transmissionTextureTransform = transmissionBinding.transform;
  }
  final ior = patch.ior;
  if (ior != null) {
    material.ior = ior;
  }
  final thickness = patch.thickness;
  if (thickness != null) {
    material.thicknessFactor = thickness;
  }
  final thicknessBinding =
      patch.textureBindingFor(MaterialTextureSlot.thickness);
  if (thicknessBinding != null) {
    material.thicknessTexture = thicknessTexture;
    material.thicknessTextureTransform = thicknessBinding.transform;
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
  final sheenColorFactor = patch.sheenColorFactor;
  if (sheenColorFactor != null) {
    material.sheenColorFactor = List<double>.unmodifiable(sheenColorFactor);
  }
  final sheenRoughness = patch.sheenRoughness;
  if (sheenRoughness != null) {
    material.sheenRoughnessFactor = sheenRoughness;
  }
  final sheenColorBinding =
      patch.textureBindingFor(MaterialTextureSlot.sheenColor);
  if (sheenColorBinding != null) {
    material.sheenColorTexture = sheenColorTexture;
    material.sheenColorTextureTexCoord = sheenColorBinding.effectiveTexCoord;
    material.sheenColorTextureTransform = sheenColorBinding.transform;
  }
  final sheenRoughnessBinding =
      patch.textureBindingFor(MaterialTextureSlot.sheenRoughness);
  if (sheenRoughnessBinding != null) {
    material.sheenRoughnessTexture = sheenRoughnessTexture;
    material.sheenRoughnessTextureTexCoord =
        sheenRoughnessBinding.effectiveTexCoord;
    material.sheenRoughnessTextureTransform = sheenRoughnessBinding.transform;
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
    patch.hasSheenOverride ||
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
      MaterialTextureSlot.specular,
      MaterialTextureSlot.specularColor,
    ])
      if (patch.textureBindingFor(slot) != null) slot.name,
  ];
  if (unsupportedTextureSlots.isNotEmpty) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'The renderer-native material extension contract cannot consume specular texture bindings.',
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
  if (patch.hasClearcoatOverride &&
      !support.supportFor(MaterialExtensionFeature.clearcoat).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  if (patch.hasSheenOverride &&
      !support.supportFor(MaterialExtensionFeature.sheen).available) {
    return _nativeMaterialExtensionUnsupportedDiagnostic(
      support: support,
      address: address,
    );
  }
  if ((patch.transmission != null ||
          patch.textureBindingFor(MaterialTextureSlot.transmission) != null) &&
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
          patch.textureBindingFor(MaterialTextureSlot.thickness) != null ||
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
