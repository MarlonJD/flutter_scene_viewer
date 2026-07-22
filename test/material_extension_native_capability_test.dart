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
        hasSheen: false,
      ),
    );

    expect(capability.support, MaterialExtensionSupport.unsupported);
    expect(capability.diagnostics.single.details['backendKind'], 'none');
  });

  test('reports each renderer-native production field independently', () {
    final capability = detectNativeMaterialExtensionCapability(
      rendererProbe: const FakeRendererMaterialExtensionProbe(
        hasTransmission: true,
        hasIor: true,
        hasVolume: true,
        hasClearcoat: true,
        hasSheen: false,
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
    expect(
      capability.support.supportFor(MaterialExtensionFeature.sheen).available,
      isFalse,
    );
  });

  test('reports partial renderer-native clearcoat support independently', () {
    final capability = detectNativeMaterialExtensionCapability(
      rendererProbe: const FakeRendererMaterialExtensionProbe(
        hasTransmission: false,
        hasIor: false,
        hasVolume: false,
        hasClearcoat: true,
        hasSheen: false,
      ),
    );

    expect(
      capability.support.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
    expect(
      capability.support
          .supportFor(MaterialExtensionFeature.clearcoat)
          .available,
      isTrue,
    );
    for (final feature in <MaterialExtensionFeature>[
      MaterialExtensionFeature.transmission,
      MaterialExtensionFeature.ior,
      MaterialExtensionFeature.volume,
    ]) {
      expect(capability.support.supportFor(feature).available, isFalse);
    }
    expect(capability.diagnostics, isEmpty);
    expect(
      capability.support.supportFor(MaterialExtensionFeature.sheen).available,
      isFalse,
    );
  });

  test('default native probe reports the complete selected renderer contract',
      () {
    final capability = detectNativeMaterialExtensionCapability();

    expect(
      capability.support.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
    for (final feature in <MaterialExtensionFeature>[
      MaterialExtensionFeature.transmission,
      MaterialExtensionFeature.ior,
      MaterialExtensionFeature.volume,
      MaterialExtensionFeature.clearcoat,
    ]) {
      final support = capability.support.supportFor(feature);
      expect(support.available, isTrue);
      expect(
        support.maturityFor(MaterialExtensionTarget.iosSimulator),
        MaterialExtensionMaturity.releasePending,
      );
      expect(
        support.evidenceFor(MaterialExtensionTarget.iosSimulator),
        MaterialExtensionEvidenceStatus.verifiedLocally,
      );
      expect(
        support.maturityFor(MaterialExtensionTarget.iosPhysical),
        MaterialExtensionMaturity.diagnosticOnly,
      );
      expect(
        support.evidenceFor(MaterialExtensionTarget.iosPhysical),
        MaterialExtensionEvidenceStatus.notRun,
      );
    }
    expect(capability.support.productionReady, isFalse);
    expect(capability.support.claimedReleaseTargets, isEmpty);
    final sheen = capability.support.supportFor(MaterialExtensionFeature.sheen);
    expect(sheen.available, isTrue);
    expect(
      sheen.maturityFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionMaturity.releasePending,
    );
    expect(
      sheen.evidenceFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionEvidenceStatus.verifiedLocally,
    );
  });
}

final class FakeRendererMaterialExtensionProbe
    implements RendererMaterialExtensionProbe {
  const FakeRendererMaterialExtensionProbe({
    required this.hasTransmission,
    required this.hasIor,
    required this.hasVolume,
    required this.hasClearcoat,
    required this.hasSheen,
  });

  @override
  final bool hasTransmission;

  @override
  final bool hasIor;

  @override
  final bool hasVolume;

  @override
  final bool hasClearcoat;

  @override
  final bool hasSheen;
}
