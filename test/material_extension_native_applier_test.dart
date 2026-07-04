import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_applier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rendererNativeSupport = MaterialExtensionSupport(
    transmission: true,
    ior: true,
    volume: true,
    clearcoat: true,
    backendKind: MaterialExtensionBackendKind.rendererNative,
  );

  test('applies clearcoat patch to native material fields', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: const MaterialPatch(
        clearcoat: 1.0,
        clearcoatRoughness: 0.12,
        clearcoatNormalScale: 0.8,
      ),
      support: rendererNativeSupport,
    );

    expect(diagnostics, isEmpty);
    expect(material.clearcoatFactor, 1.0);
    expect(material.clearcoatRoughnessFactor, 0.12);
    expect(material.clearcoatNormalScale, 0.8);
  });

  test('applies transmission ior and volume patch to native material fields',
      () {
    final material = FakeNativeMaterialExtensionMaterial();
    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: const MaterialPatch(
        transmission: 1.0,
        ior: 1.45,
        thickness: 0.04,
        attenuationDistance: 1.5,
        attenuationColor: <double>[0.8, 0.95, 1.0],
      ),
      support: rendererNativeSupport,
    );

    expect(diagnostics, isEmpty);
    expect(material.transmissionFactor, 1.0);
    expect(material.ior, 1.45);
    expect(material.thicknessFactor, 0.04);
    expect(material.attenuationDistance, 1.5);
    expect(material.attenuationColor, <double>[0.8, 0.95, 1.0]);
  });

  test('reports unsupported when support is not renderer native', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: const MaterialPatch(transmission: 1.0),
      support: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
        clearcoat: true,
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
    );

    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['backendKind'], 'packageLocalCandidate');
    expect(material.transmissionFactor, isNull);
  });
}

final class FakeNativeMaterialExtensionMaterial
    implements NativeMaterialExtensionMaterial {
  double? transmissionFactor;
  double? ior;
  double? thicknessFactor;
  double? attenuationDistance;
  List<double>? attenuationColor;
  double? clearcoatFactor;
  double? clearcoatRoughnessFactor;
  double? clearcoatNormalScale;
}
