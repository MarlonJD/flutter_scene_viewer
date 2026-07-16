import '../diagnostics.dart';
import '../material_extension_policy.dart';

/// Result of probing renderer-native material extension support.
final class NativeMaterialExtensionCapability {
  const NativeMaterialExtensionCapability({
    required this.support,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final MaterialExtensionSupport support;
  final List<ViewerDiagnostic> diagnostics;
}

/// Narrow contract for renderer-native glTF/PBR extension fields.
abstract interface class RendererMaterialExtensionProbe {
  bool get hasTransmission;
  bool get hasIor;
  bool get hasVolume;
  bool get hasClearcoat;
}

/// Detects whether the active renderer exposes all production material
/// extension fields as native material inputs.
NativeMaterialExtensionCapability detectNativeMaterialExtensionCapability({
  RendererMaterialExtensionProbe rendererProbe =
      const CurrentFlutterSceneMaterialExtensionProbe(),
}) {
  final availability = <MaterialExtensionFeature, bool>{
    MaterialExtensionFeature.transmission: rendererProbe.hasTransmission,
    MaterialExtensionFeature.ior: rendererProbe.hasIor,
    MaterialExtensionFeature.volume: rendererProbe.hasVolume,
    MaterialExtensionFeature.clearcoat: rendererProbe.hasClearcoat,
  };
  if (availability.values.any((available) => available)) {
    return NativeMaterialExtensionCapability(
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          for (final entry in availability.entries)
            entry.key: entry.value
                ? MaterialExtensionFeatureSupport(available: true)
                : MaterialExtensionFeatureSupport.unsupported,
        },
      ),
    );
  }
  return NativeMaterialExtensionCapability(
    support: MaterialExtensionSupport.unsupported,
    diagnostics: <ViewerDiagnostic>[
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.unsupportedMaterialFeature,
        message: 'Renderer-native material extension fields are not available.',
        details: <String, Object?>{
          'backendKind': 'none',
          'status': 'unsupported',
          'productionBlocker': 'rendererNativeMaterialExtensionContractMissing',
          'missing': <String>[
            if (!rendererProbe.hasTransmission) 'transmission',
            if (!rendererProbe.hasIor) 'ior',
            if (!rendererProbe.hasVolume) 'volume',
            if (!rendererProbe.hasClearcoat) 'clearcoat',
          ],
        },
      ),
    ],
  );
}

/// Current installed renderer probe.
///
/// Plan 015's renderer revision exposes the complete selected clearcoat
/// contract and the stable dependency pin now resolves that published commit.
/// The remaining extension fields stay unavailable until their own upstream
/// plans land.
final class CurrentFlutterSceneMaterialExtensionProbe
    implements RendererMaterialExtensionProbe {
  const CurrentFlutterSceneMaterialExtensionProbe();

  @override
  bool get hasTransmission => false;

  @override
  bool get hasIor => false;

  @override
  bool get hasVolume => false;

  @override
  bool get hasClearcoat => true;
}
