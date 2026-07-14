import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_applier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rendererNativeSupport = _materialExtensionSupport(
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
    expect(material.clearcoatValue, 1.0);
    expect(material.clearcoatRoughnessValue, 0.12);
    expect(material.clearcoatNormalScaleValue, 0.8);
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
    expect(material.transmissionValue, 1.0);
    expect(material.iorValue, 1.45);
    expect(material.thicknessValue, 0.04);
    expect(material.attenuationDistanceValue, 1.5);
    expect(material.attenuationColorValue, <double>[0.8, 0.95, 1.0]);
  });

  test('reports unsupported when support is not renderer native', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: const MaterialPatch(transmission: 1.0),
      support: _materialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
    );

    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['backendKind'], 'packageLocalCandidate');
    expect(material.transmissionValue, isNull);
  });

  test('rejects every extension texture binding before native setters', () {
    final cases = <({String slot, MaterialPatch patch})>[
      (
        slot: 'transmission',
        patch: MaterialPatch(
          transmissionTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/transmission.png'),
          ),
        ),
      ),
      (
        slot: 'thickness',
        patch: MaterialPatch(
          thicknessTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/thickness.png'),
          ),
        ),
      ),
      (
        slot: 'clearcoat',
        patch: MaterialPatch(
          clearcoatTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/clearcoat.png'),
          ),
        ),
      ),
      (
        slot: 'clearcoatRoughness',
        patch: MaterialPatch(
          clearcoatRoughnessTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset(
              'assets/clearcoat-roughness.png',
            ),
          ),
        ),
      ),
      (
        slot: 'clearcoatNormal',
        patch: MaterialPatch(
          clearcoatNormalTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/clearcoat-normal.png'),
          ),
        ),
      ),
      (
        slot: 'specular',
        patch: MaterialPatch(
          specularTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/specular.png'),
          ),
        ),
      ),
      (
        slot: 'specularColor',
        patch: MaterialPatch(
          specularColorTextureBinding: MaterialTextureBinding(
            source: const TextureSource.asset('assets/specular-color.png'),
          ),
        ),
      ),
    ];

    for (final entry in cases) {
      final material = FakeNativeMaterialExtensionMaterial();

      final diagnostics = applyNativeMaterialExtensionPatch(
        material: material,
        patch: entry.patch,
        support: rendererNativeSupport,
      );

      expect(diagnostics, hasLength(1), reason: entry.slot);
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature,
        reason: entry.slot,
      );
      expect(
        diagnostics.single.details['limitation'],
        'rendererNativeExtensionTextureContractMissing',
        reason: entry.slot,
      );
      expect(
        diagnostics.single.details['slots'],
        contains(entry.slot),
        reason: entry.slot,
      );
      expect(material.setterCalls, isEmpty, reason: entry.slot);
    }
  });

  test('extension texture binding keeps mixed native patch atomic', () {
    final material = FakeNativeMaterialExtensionMaterial();

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        transmission: 0.8,
        thicknessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/thickness.png'),
        ),
      ),
      support: rendererNativeSupport,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'rendererNativeExtensionTextureContractMissing');
    expect(material.setterCalls, isEmpty);
    expect(material.transmissionValue, isNull);
  });

  test('rejects scalar and color specular without a native contract', () {
    for (final patch in <MaterialPatch>[
      const MaterialPatch(specular: 0.8),
      const MaterialPatch(
        specularColorFactor: <double>[0.7, 0.8, 0.9],
      ),
    ]) {
      final material = FakeNativeMaterialExtensionMaterial();

      final diagnostics = applyNativeMaterialExtensionPatch(
        material: material,
        patch: patch,
        support: rendererNativeSupport,
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.details['limitation'],
          'rendererNativeSpecularContractMissing');
      expect(material.setterCalls, isEmpty);
    }
  });

  test('mixed core and native extension patch is atomic', () {
    final material = FakeNativeMaterialExtensionMaterial();

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        baseColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/base-color.png'),
        ),
        transmission: 1.0,
      ),
      support: rendererNativeSupport,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'rendererNativeMixedCoreExtensionPatchUnsupported');
    expect(
      diagnostics.single.details['fields'],
      containsAll(<String>['baseColorFactor', 'baseColorTexture']),
    );
    expect(material.setterCalls, isEmpty);
    expect(material.transmissionValue, isNull);
  });
}

MaterialExtensionSupport _materialExtensionSupport({
  required MaterialExtensionBackendKind backendKind,
}) {
  return MaterialExtensionSupport(
    backendKind: backendKind,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      for (final feature in <MaterialExtensionFeature>[
        MaterialExtensionFeature.transmission,
        MaterialExtensionFeature.ior,
        MaterialExtensionFeature.volume,
        MaterialExtensionFeature.clearcoat,
      ])
        feature: MaterialExtensionFeatureSupport(available: true),
    },
  );
}

final class FakeNativeMaterialExtensionMaterial
    implements NativeMaterialExtensionMaterial {
  final List<String> setterCalls = <String>[];

  double? _transmissionFactor;
  double? _ior;
  double? _thicknessFactor;
  double? _attenuationDistance;
  List<double>? _attenuationColor;
  double? _clearcoatFactor;
  double? _clearcoatRoughnessFactor;
  double? _clearcoatNormalScale;

  double? get transmissionValue => _transmissionFactor;
  double? get iorValue => _ior;
  double? get thicknessValue => _thicknessFactor;
  double? get attenuationDistanceValue => _attenuationDistance;
  List<double>? get attenuationColorValue => _attenuationColor;
  double? get clearcoatValue => _clearcoatFactor;
  double? get clearcoatRoughnessValue => _clearcoatRoughnessFactor;
  double? get clearcoatNormalScaleValue => _clearcoatNormalScale;

  @override
  set transmissionFactor(double value) {
    setterCalls.add('transmissionFactor');
    _transmissionFactor = value;
  }

  @override
  set ior(double value) {
    setterCalls.add('ior');
    _ior = value;
  }

  @override
  set thicknessFactor(double value) {
    setterCalls.add('thicknessFactor');
    _thicknessFactor = value;
  }

  @override
  set attenuationDistance(double value) {
    setterCalls.add('attenuationDistance');
    _attenuationDistance = value;
  }

  @override
  set attenuationColor(List<double> value) {
    setterCalls.add('attenuationColor');
    _attenuationColor = value;
  }

  @override
  set clearcoatFactor(double value) {
    setterCalls.add('clearcoatFactor');
    _clearcoatFactor = value;
  }

  @override
  set clearcoatRoughnessFactor(double value) {
    setterCalls.add('clearcoatRoughnessFactor');
    _clearcoatRoughnessFactor = value;
  }

  @override
  set clearcoatNormalScale(double value) {
    setterCalls.add('clearcoatNormalScale');
    _clearcoatNormalScale = value;
  }
}
