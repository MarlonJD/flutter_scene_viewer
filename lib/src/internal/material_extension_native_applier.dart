import '../diagnostics.dart';
import '../material_extension_policy.dart';
import '../material_patch.dart';

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
}

List<ViewerDiagnostic> applyNativeMaterialExtensionPatch({
  required NativeMaterialExtensionMaterial material,
  required MaterialPatch patch,
  required MaterialExtensionSupport support,
}) {
  if (!support.productionReady ||
      support.backendKind != MaterialExtensionBackendKind.rendererNative) {
    return <ViewerDiagnostic>[
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.unsupportedMaterialFeature,
        message:
            'Production material extension patches require renderer-native material fields.',
        details: <String, Object?>{
          'backendKind': support.backendKind.name,
          'status': 'unsupported',
          'productionBlocker': 'rendererNativeMaterialExtensionContractMissing',
        },
      ),
    ];
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

  return const <ViewerDiagnostic>[];
}
