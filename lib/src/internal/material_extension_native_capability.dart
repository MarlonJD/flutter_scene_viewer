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
  bool get hasSheen;
}

/// Detects whether the active renderer exposes all production material
/// extension fields as native material inputs.
NativeMaterialExtensionCapability detectNativeMaterialExtensionCapability({
  RendererMaterialExtensionProbe rendererProbe =
      const CurrentFlutterSceneMaterialExtensionProbe(),
}) {
  final hasCurrentTargetEvidence =
      rendererProbe is CurrentFlutterSceneMaterialExtensionProbe;
  final availability = <MaterialExtensionFeature, bool>{
    MaterialExtensionFeature.transmission: rendererProbe.hasTransmission,
    MaterialExtensionFeature.ior: rendererProbe.hasIor,
    MaterialExtensionFeature.volume: rendererProbe.hasVolume,
    MaterialExtensionFeature.clearcoat: rendererProbe.hasClearcoat,
    MaterialExtensionFeature.sheen: rendererProbe.hasSheen,
  };
  if (availability.values.any((available) => available)) {
    return NativeMaterialExtensionCapability(
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          for (final entry in availability.entries)
            entry.key: entry.value
                ? MaterialExtensionFeatureSupport(
                    available: true,
                    maturityByTarget: hasCurrentTargetEvidence
                        ? const <MaterialExtensionTarget,
                            MaterialExtensionMaturity>{
                            MaterialExtensionTarget.iosSimulator:
                                MaterialExtensionMaturity.releasePending,
                          }
                        : const <MaterialExtensionTarget,
                            MaterialExtensionMaturity>{},
                    evidenceByTarget: hasCurrentTargetEvidence
                        ? const <MaterialExtensionTarget,
                            MaterialExtensionEvidenceStatus>{
                            MaterialExtensionTarget.iosSimulator:
                                MaterialExtensionEvidenceStatus.verifiedLocally,
                          }
                        : const <MaterialExtensionTarget,
                            MaterialExtensionEvidenceStatus>{},
                  )
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
            if (!rendererProbe.hasSheen) 'sheen',
          ],
        },
      ),
    ],
  );
}

/// Current installed renderer probe.
///
/// The selected renderer contract exposes transmission, volume, glass IOR,
/// clearcoat, and sheen. Release maturity and per-target evidence remain
/// separate from this compile-time API capability probe.
final class CurrentFlutterSceneMaterialExtensionProbe
    implements RendererMaterialExtensionProbe {
  const CurrentFlutterSceneMaterialExtensionProbe();

  @override
  bool get hasTransmission => true;

  @override
  bool get hasIor => true;

  @override
  bool get hasVolume => true;

  @override
  bool get hasClearcoat => true;

  @override
  bool get hasSheen => true;
}
