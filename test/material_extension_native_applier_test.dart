import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_applier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rendererNativeSupport = _materialExtensionSupport(
    backendKind: MaterialExtensionBackendKind.rendererNative,
  );

  test('applies clearcoat patch to native material fields', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final clearcoatTexture = Object();
    final clearcoatRoughnessTexture = Object();
    final clearcoatNormalTexture = Object();
    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        clearcoat: 1.0,
        clearcoatRoughness: 0.12,
        clearcoatNormalScale: 0.8,
        clearcoatTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat.png'),
        ),
        clearcoatRoughnessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-roughness.png'),
        ),
        clearcoatNormalTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-normal.png'),
        ),
      ),
      support: rendererNativeSupport,
      clearcoatTexture: clearcoatTexture,
      clearcoatRoughnessTexture: clearcoatRoughnessTexture,
      clearcoatNormalTexture: clearcoatNormalTexture,
    );

    expect(diagnostics, isEmpty);
    expect(material.clearcoatValue, 1.0);
    expect(material.clearcoatRoughnessValue, 0.12);
    expect(material.clearcoatNormalScaleValue, 0.8);
    expect(material.clearcoatTextureValue, same(clearcoatTexture));
    expect(
      material.clearcoatRoughnessTextureValue,
      same(clearcoatRoughnessTexture),
    );
    expect(material.clearcoatNormalTextureValue, same(clearcoatNormalTexture));
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

  test('applies transmission and thickness textures with UV transforms', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final transmissionTexture = Object();
    final thicknessTexture = Object();
    final transmissionTransform = TextureTransform(
      offset: <double>[0.1, 0.2],
      rotation: 0.3,
    );
    final thicknessTransform = TextureTransform(
      scale: <double>[0.5, 0.75],
    );

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        transmissionTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/transmission.png'),
          transform: transmissionTransform,
        ),
        thicknessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/thickness.png'),
          transform: thicknessTransform,
        ),
      ),
      support: rendererNativeSupport,
      transmissionTexture: transmissionTexture,
      thicknessTexture: thicknessTexture,
    );

    expect(diagnostics, isEmpty);
    expect(material.transmissionTextureValue, same(transmissionTexture));
    expect(material.transmissionTextureTransformValue, transmissionTransform);
    expect(material.thicknessTextureValue, same(thicknessTexture));
    expect(material.thicknessTextureTransformValue, thicknessTransform);
  });

  test('applies complete sheen state with authored UV sets and transforms', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final colorTexture = Object();
    final roughnessTexture = Object();
    final colorTransform = TextureTransform(
      offset: <double>[0.1, 0.2],
      scale: <double>[1.5, 0.75],
      rotation: 0.3,
    );
    final roughnessTransform = TextureTransform(
      offset: <double>[0.4, 0.5],
      scale: <double>[0.5, 2.0],
      rotation: 0.6,
    );
    final patch = MaterialPatch(
      sheenColorFactor: const <double>[0.2, 0.4, 0.8],
      sheenColorTextureBinding: MaterialTextureBinding(
        source: const TextureSource.asset('assets/sheen-color.png'),
        texCoord: 1,
        transform: colorTransform,
      ),
      sheenRoughness: 0.35,
      sheenRoughnessTextureBinding: MaterialTextureBinding(
        source: const TextureSource.asset('assets/sheen-roughness.png'),
        texCoord: 0,
        transform: roughnessTransform,
      ),
    );

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: patch,
      support: rendererNativeSupport,
      sheenColorTexture: colorTexture,
      sheenRoughnessTexture: roughnessTexture,
    );

    expect(diagnostics, isEmpty);
    expect(hasNativeMaterialExtensionIntent(patch), isTrue);
    expect(material.sheenColorValue, <double>[0.2, 0.4, 0.8]);
    expect(material.sheenRoughnessValue, 0.35);
    expect(material.sheenColorTextureValue, same(colorTexture));
    expect(material.sheenColorTextureTexCoordValue, 1);
    expect(material.sheenColorTextureTransformValue, colorTransform);
    expect(material.sheenRoughnessTextureValue, same(roughnessTexture));
    expect(material.sheenRoughnessTextureTexCoordValue, 0);
    expect(material.sheenRoughnessTextureTransformValue, roughnessTransform);
  });

  test('rejects specular textures without a native renderer contract', () {
    final cases = <({String slot, MaterialPatch patch})>[
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

  test('extension texture binding composes with scalar native state', () {
    final material = FakeNativeMaterialExtensionMaterial();
    final thicknessTexture = Object();

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        transmission: 0.8,
        thicknessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/thickness.png'),
        ),
      ),
      support: rendererNativeSupport,
      thicknessTexture: thicknessTexture,
    );

    expect(diagnostics, isEmpty);
    expect(material.transmissionValue, 0.8);
    expect(material.thicknessTextureValue, same(thicknessTexture));
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

  test('mixed core and native extension patch passes native preflight', () {
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

    expect(diagnostics, isEmpty);
    expect(material.transmissionValue, 1.0);
  });

  test('mixed core and native clearcoat patch is accepted', () {
    final material = FakeNativeMaterialExtensionMaterial();

    final diagnostics = applyNativeMaterialExtensionPatch(
      material: material,
      patch: MaterialPatch(
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        clearcoat: 0.75,
      ),
      support: rendererNativeSupport,
    );

    expect(diagnostics, isEmpty);
    expect(material.clearcoatValue, 0.75);
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
        MaterialExtensionFeature.sheen,
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
  Object? _clearcoatTexture;
  Object? _clearcoatRoughnessTexture;
  Object? _clearcoatNormalTexture;
  Object? _transmissionTexture;
  TextureTransform? _transmissionTextureTransform;
  Object? _thicknessTexture;
  TextureTransform? _thicknessTextureTransform;
  List<double>? _sheenColorFactor;
  double? _sheenRoughnessFactor;
  Object? _sheenColorTexture;
  int? _sheenColorTextureTexCoord;
  TextureTransform? _sheenColorTextureTransform;
  Object? _sheenRoughnessTexture;
  int? _sheenRoughnessTextureTexCoord;
  TextureTransform? _sheenRoughnessTextureTransform;

  double? get transmissionValue => _transmissionFactor;
  double? get iorValue => _ior;
  double? get thicknessValue => _thicknessFactor;
  double? get attenuationDistanceValue => _attenuationDistance;
  List<double>? get attenuationColorValue => _attenuationColor;
  double? get clearcoatValue => _clearcoatFactor;
  double? get clearcoatRoughnessValue => _clearcoatRoughnessFactor;
  double? get clearcoatNormalScaleValue => _clearcoatNormalScale;
  Object? get clearcoatTextureValue => _clearcoatTexture;
  Object? get clearcoatRoughnessTextureValue => _clearcoatRoughnessTexture;
  Object? get clearcoatNormalTextureValue => _clearcoatNormalTexture;
  Object? get transmissionTextureValue => _transmissionTexture;
  TextureTransform? get transmissionTextureTransformValue =>
      _transmissionTextureTransform;
  Object? get thicknessTextureValue => _thicknessTexture;
  TextureTransform? get thicknessTextureTransformValue =>
      _thicknessTextureTransform;
  List<double>? get sheenColorValue => _sheenColorFactor;
  double? get sheenRoughnessValue => _sheenRoughnessFactor;
  Object? get sheenColorTextureValue => _sheenColorTexture;
  int? get sheenColorTextureTexCoordValue => _sheenColorTextureTexCoord;
  TextureTransform? get sheenColorTextureTransformValue =>
      _sheenColorTextureTransform;
  Object? get sheenRoughnessTextureValue => _sheenRoughnessTexture;
  int? get sheenRoughnessTextureTexCoordValue => _sheenRoughnessTextureTexCoord;
  TextureTransform? get sheenRoughnessTextureTransformValue =>
      _sheenRoughnessTextureTransform;

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
  set transmissionTexture(Object? value) {
    setterCalls.add('transmissionTexture');
    _transmissionTexture = value;
  }

  @override
  set transmissionTextureTransform(TextureTransform value) {
    setterCalls.add('transmissionTextureTransform');
    _transmissionTextureTransform = value;
  }

  @override
  set thicknessTexture(Object? value) {
    setterCalls.add('thicknessTexture');
    _thicknessTexture = value;
  }

  @override
  set thicknessTextureTransform(TextureTransform value) {
    setterCalls.add('thicknessTextureTransform');
    _thicknessTextureTransform = value;
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

  @override
  set clearcoatTexture(Object? value) {
    setterCalls.add('clearcoatTexture');
    _clearcoatTexture = value;
  }

  @override
  set clearcoatRoughnessTexture(Object? value) {
    setterCalls.add('clearcoatRoughnessTexture');
    _clearcoatRoughnessTexture = value;
  }

  @override
  set clearcoatNormalTexture(Object? value) {
    setterCalls.add('clearcoatNormalTexture');
    _clearcoatNormalTexture = value;
  }

  @override
  set sheenColorFactor(List<double> value) {
    setterCalls.add('sheenColorFactor');
    _sheenColorFactor = value;
  }

  @override
  set sheenRoughnessFactor(double value) {
    setterCalls.add('sheenRoughnessFactor');
    _sheenRoughnessFactor = value;
  }

  @override
  set sheenColorTexture(Object? value) {
    setterCalls.add('sheenColorTexture');
    _sheenColorTexture = value;
  }

  @override
  set sheenColorTextureTexCoord(int value) {
    setterCalls.add('sheenColorTextureTexCoord');
    _sheenColorTextureTexCoord = value;
  }

  @override
  set sheenColorTextureTransform(TextureTransform value) {
    setterCalls.add('sheenColorTextureTransform');
    _sheenColorTextureTransform = value;
  }

  @override
  set sheenRoughnessTexture(Object? value) {
    setterCalls.add('sheenRoughnessTexture');
    _sheenRoughnessTexture = value;
  }

  @override
  set sheenRoughnessTextureTexCoord(int value) {
    setterCalls.add('sheenRoughnessTextureTexCoord');
    _sheenRoughnessTextureTexCoord = value;
  }

  @override
  set sheenRoughnessTextureTransform(TextureTransform value) {
    setterCalls.add('sheenRoughnessTextureTransform');
    _sheenRoughnessTextureTransform = value;
  }
}
