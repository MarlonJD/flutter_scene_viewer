import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_capability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports unsupported when renderer native material fields are absent',
      () {
    final capability = detectNativeMaterialExtensionCapability(
      rendererProbe: const FakeRendererMaterialExtensionProbe(
        hasTransmission: false,
        hasIor: false,
        hasVolume: false,
        hasClearcoat: false,
      ),
    );

    expect(capability.support, MaterialExtensionSupport.unsupported);
    expect(capability.diagnostics.single.details['backendKind'], 'none');
  });

  test(
      'reports renderer native support only when every production field exists',
      () {
    final capability = detectNativeMaterialExtensionCapability(
      rendererProbe: const FakeRendererMaterialExtensionProbe(
        hasTransmission: true,
        hasIor: true,
        hasVolume: true,
        hasClearcoat: true,
      ),
    );

    expect(capability.support.productionReady, isFalse);
    expect(capability.support.claimedReleaseTargets, isEmpty);
    for (final feature in <MaterialExtensionFeature>[
      MaterialExtensionFeature.transmission,
      MaterialExtensionFeature.ior,
      MaterialExtensionFeature.volume,
      MaterialExtensionFeature.clearcoat,
    ]) {
      expect(capability.support.supportFor(feature).available, isTrue);
      expect(
        capability.support
            .supportFor(feature)
            .evidenceFor(MaterialExtensionTarget.iosPhysical),
        MaterialExtensionEvidenceStatus.notRun,
      );
    }
    expect(
      capability.support.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
    expect(capability.diagnostics, isEmpty);
  });

  test('default native probe reports current renderer unsupported', () {
    final capability = detectNativeMaterialExtensionCapability();

    expect(capability.support, MaterialExtensionSupport.unsupported);
    expect(capability.diagnostics.single.details['backendKind'], 'none');
  });
}

final class FakeRendererMaterialExtensionProbe
    implements RendererMaterialExtensionProbe {
  const FakeRendererMaterialExtensionProbe({
    required this.hasTransmission,
    required this.hasIor,
    required this.hasVolume,
    required this.hasClearcoat,
  });

  @override
  final bool hasTransmission;

  @override
  final bool hasIor;

  @override
  final bool hasVolume;

  @override
  final bool hasClearcoat;
}
