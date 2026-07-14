import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MaterialPatch merges sparse fields', () {
    const first = MaterialPatch(
      metallic: 0.2,
      normalTexture: TextureSource.asset('assets/normal.png'),
    );
    const second = MaterialPatch(
      roughness: 0.8,
      occlusionTexture: TextureSource.asset('assets/ao.png'),
    );

    final merged = first.merge(second);

    expect(merged.metallic, 0.2);
    expect(merged.roughness, 0.8);
    expect(merged.normalTexture, isA<AssetTextureSource>());
    expect(merged.occlusionTexture, isA<AssetTextureSource>());
    expect(merged.isEmpty, isFalse);
  });

  test('MaterialPatch merges alpha mode fields', () {
    const first = MaterialPatch(alphaMode: MaterialAlphaMode.opaque);
    const second = MaterialPatch(alphaMode: MaterialAlphaMode.mask);
    const third = MaterialPatch(alphaMode: MaterialAlphaMode.blend);

    expect(
        first.merge(const MaterialPatch()).alphaMode, MaterialAlphaMode.opaque);
    expect(first.merge(second).alphaMode, MaterialAlphaMode.mask);
    expect(second.merge(third).alphaMode, MaterialAlphaMode.blend);
  });

  test('MaterialPatch merges alpha cutoff', () {
    const first = MaterialPatch(alphaCutoff: 0.35);
    const second = MaterialPatch(alphaCutoff: 0.8);

    expect(first.merge(const MaterialPatch()).alphaCutoff, 0.35);
    expect(first.merge(second).alphaCutoff, 0.8);
  });

  test('MaterialPatch merges effect mask', () {
    const first = MaterialPatch(roughness: 0.5);
    const second = MaterialPatch(
      effectMask: MaterialEffectMask(
        texture: TextureSource.asset('assets/masks/material_mask.png'),
        channels: <MaterialMaskChannel, MaterialEffectTarget>{
          MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
        },
      ),
    );

    final merged = first.merge(second);

    expect(merged.roughness, 0.5);
    expect(merged.effectMask, isNotNull);
    expect(merged.effectMask!.channels[MaterialMaskChannel.red],
        MaterialEffectTarget.paintRegion);
  });

  test('empty patch is empty', () {
    expect(const MaterialPatch().isEmpty, isTrue);
  });

  test('MaterialPatch distinguishes opaque IOR from transmission and volume',
      () {
    expect(const MaterialPatch(ior: 1.5).hasGlassOverride, isFalse);
    expect(const MaterialPatch(ior: 1.5).hasOpaqueIorOverride, isTrue);
    expect(
      const MaterialPatch(ior: 1.5).hasTransmissionOrVolumeOverride,
      isFalse,
    );
    expect(
      const MaterialPatch(transmission: 1, ior: 1.5).hasGlassOverride,
      isTrue,
    );
    expect(
      const MaterialPatch(transmission: 1, ior: 1.5)
          .hasTransmissionOrVolumeOverride,
      isTrue,
    );
    expect(
      const MaterialPatch(transmission: 1, ior: 1.5).hasOpaqueIorOverride,
      isFalse,
    );
  });

  test('MaterialPatch reports invalid metallic and roughness values', () {
    const patch = MaterialPatch(
      metallic: 1.2,
      roughness: -0.1,
      occlusionStrength: 1.2,
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Body'], primitiveIndex: 0),
    );

    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      everyElement(ViewerDiagnosticCode.invalidMaterialOverride),
    );
    expect(diagnostics, hasLength(3));
  });

  test('MaterialPatch reports invalid alpha cutoff values', () {
    const patch = MaterialPatch(alphaCutoff: 1.2);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Leaf'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(
        diagnostics.single.code, ViewerDiagnosticCode.invalidMaterialOverride);
    expect(diagnostics.single.details['field'], 'alphaCutoff');
    expect(diagnostics.single.details['value'], 1.2);
  });

  test('MaterialPatch reports effect mask outside opaque family unsupported',
      () {
    const patch = MaterialPatch(
      alphaMode: MaterialAlphaMode.blend,
      effectMask: MaterialEffectMask(
        texture: TextureSource.asset('assets/masks/material_mask.png'),
        channels: <MaterialMaskChannel, MaterialEffectTarget>{
          MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
        },
      ),
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['feature'], 'effectMask');
    expect(diagnostics.single.details['requiredFamily'], 'opaque');
  });

  test('MaterialPatch reports glass fields as unsupported for current adapter',
      () {
    const patch = MaterialPatch(
      transmission: 1.0,
      ior: 1.45,
      thickness: 0.02,
      attenuationColor: <double>[0.8, 0.95, 1.0],
      attenuationDistance: 4.0,
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Glass'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_transmission'));
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_ior'));
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_volume'));
  });

  test(
      'MaterialPatch reports clearcoat fields as unsupported for current adapter',
      () {
    const patch = MaterialPatch(
      clearcoat: 1.0,
      clearcoatTexture: TextureSource.asset('assets/clearcoat.png'),
      clearcoatRoughness: 0.18,
      clearcoatRoughnessTexture:
          TextureSource.asset('assets/clearcoat_roughness.png'),
      clearcoatNormalTexture: TextureSource.asset('assets/coat_normal.png'),
      clearcoatNormalScale: 0.75,
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_clearcoat'));
  });

  test('MaterialPatch reports specular fields as unsupported by default', () {
    const patch = MaterialPatch(
      specular: 0.7,
      specularColorFactor: <double>[0.2, 0.3, 0.4],
      specularTexture: TextureSource.asset('assets/specular.png'),
      specularColorTexture: TextureSource.asset('assets/specular_color.png'),
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Fabric'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    expect(
      diagnostics.single.details['extensions'],
      contains('KHR_materials_specular'),
    );
  });

  test('MaterialPatch accepts normative specular and opaque IOR domains', () {
    final support = _specularAndIorSupport();
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );

    for (final specularFactor in <double>[0, 0.5, 1]) {
      for (final ior in <double>[0, 1, 1.5, 2.42]) {
        final patch = MaterialPatch(
          specular: specularFactor,
          specularColorFactor: const <double>[0, 1.5, 4],
          ior: ior,
        );

        expect(
          patch.validate(address, support: support),
          isEmpty,
          reason: 'specularFactor=$specularFactor, ior=$ior',
        );
        expect(patch.hasGlassOverride, isFalse, reason: '$ior');
        expect(patch.hasOpaqueIorOverride, isTrue, reason: '$ior');
      }
    }
  });

  test('MaterialPatch rejects specular factors outside the unit interval', () {
    final support = _specularAndIorSupport();
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );

    for (final factor in <double>[-0.01, 1.01, double.nan, double.infinity]) {
      final diagnostics =
          MaterialPatch(specular: factor).validate(address, support: support);

      expect(diagnostics, hasLength(1), reason: '$factor');
      expect(diagnostics.single.code,
          ViewerDiagnosticCode.invalidMaterialOverride);
      expect(diagnostics.single.details['field'], 'specular');
    }
  });

  test('MaterialPatch rejects invalid specular color factors with diagnostics',
      () {
    final support = _specularAndIorSupport();
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );
    final invalidFactors = <List<double>>[
      <double>[1, 1],
      <double>[-0.01, 1, 1],
      <double>[double.nan, 1, 1],
      <double>[double.infinity, 1, 1],
    ];

    for (final factor in invalidFactors) {
      final diagnostics = MaterialPatch(
        specularColorFactor: factor,
      ).validate(address, support: support);

      expect(diagnostics, hasLength(1), reason: '$factor');
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride,
        reason: '$factor',
      );
      expect(
        diagnostics.single.details['field'],
        'specularColorFactor',
        reason: '$factor',
      );
    }
  });

  test('MaterialPatch rejects invalid opaque IOR values with diagnostics', () {
    final support = _specularAndIorSupport();
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );

    for (final ior in <double>[-1, 0.5, double.nan, double.infinity]) {
      final diagnostics =
          MaterialPatch(ior: ior).validate(address, support: support);

      expect(diagnostics, hasLength(1), reason: '$ior');
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride,
        reason: '$ior',
      );
      expect(diagnostics.single.details['field'], 'ior', reason: '$ior');
    }
  });

  test('intrinsic specular and IOR errors precede unavailable capability', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );
    final cases = <(MaterialPatch, String)>[
      (const MaterialPatch(specular: 1.01), 'specular'),
      (
        const MaterialPatch(specularColorFactor: <double>[1, -0.01, 1]),
        'specularColorFactor',
      ),
      (const MaterialPatch(ior: 0.5), 'ior'),
    ];

    for (final entry in cases) {
      for (final diagnostics in <List<ViewerDiagnostic>>[
        entry.$1.validate(address),
        entry.$1.validate(
          address,
          support: MaterialExtensionSupport.unsupported,
        ),
      ]) {
        expect(diagnostics, hasLength(1), reason: entry.$2);
        expect(
          diagnostics.single.code,
          ViewerDiagnosticCode.invalidMaterialOverride,
          reason: entry.$2,
        );
        expect(diagnostics.single.details['field'], entry.$2);
      }
    }
  });

  test('deserialized intrinsic extension errors precede unavailable capability',
      () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );
    final cases = <(Map<String, Object?>, String)>[
      (<String, Object?>{'specular': -0.01}, 'specular'),
      (
        <String, Object?>{
          'specularColorFactor': <Object?>[1, 1],
        },
        'specularColorFactor',
      ),
      (<String, Object?>{'ior': double.infinity}, 'ior'),
    ];

    for (final entry in cases) {
      final diagnostics = MaterialPatch.fromJson(entry.$1).validate(address);

      expect(diagnostics, hasLength(1), reason: entry.$2);
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride,
        reason: entry.$2,
      );
      expect(diagnostics.single.details['field'], entry.$2);
    }
  });

  test('valid unsupported opaque IOR remains a capability diagnostic', () {
    final diagnostics = const MaterialPatch(ior: 1.45).validate(
      PartAddress(
        nodePath: const <String>['Root', 'Fabric'],
        primitiveIndex: 0,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    final diagnostic = diagnostics.single;
    expect(diagnostic.message, contains('Opaque IOR'));
    expect(diagnostic.message, isNot(contains('Transmission/glass')));
    expect(diagnostic.details['feature'], 'opaqueIor');
    expect(
      diagnostic.details['limitation'],
      'pinnedStandardPbrOpaqueIorContractMissing',
    );
    expect(diagnostic.details['extensions'], contains('KHR_materials_ior'));
  });

  test('MaterialPatch merges clearcoat fields', () {
    const first = MaterialPatch(
      clearcoat: 0.4,
      clearcoatTexture: TextureSource.asset('assets/clearcoat.png'),
      clearcoatNormalScale: 0.5,
    );
    const second = MaterialPatch(
      clearcoatRoughness: 0.2,
      clearcoatRoughnessTexture:
          TextureSource.asset('assets/clearcoat_roughness.png'),
      clearcoatNormalTexture: TextureSource.asset('assets/coat_normal.png'),
    );

    final merged = first.merge(second);

    expect(merged.clearcoat, 0.4);
    expect(merged.clearcoatTexture, isA<AssetTextureSource>());
    expect(merged.clearcoatRoughness, 0.2);
    expect(merged.clearcoatRoughnessTexture, isA<AssetTextureSource>());
    expect(merged.clearcoatNormalTexture, isA<AssetTextureSource>());
    expect(merged.clearcoatNormalScale, 0.5);
  });

  test('MaterialPatch serializes to JSON and back', () {
    final patch = MaterialPatch(
      baseColorFactor: const <double>[0.1, 0.2, 0.3, 0.4],
      baseColorTexture: const TextureSource.asset('assets/albedo.png'),
      metallicRoughnessTexture:
          const TextureSource.asset('assets/metallic_roughness.png'),
      normalTexture: const TextureSource.asset('assets/normal.png'),
      normalScale: 0.6,
      metallic: 0.25,
      roughness: 0.75,
      emissiveFactor: const <double>[1, 0.5, 0.25],
      emissiveTexture: const TextureSource.asset('assets/emissive.png'),
      occlusionTexture: const TextureSource.asset('assets/ao.png'),
      occlusionStrength: 0.8,
      alphaMode: MaterialAlphaMode.mask,
      alphaCutoff: 0.42,
      effectMask: const MaterialEffectMask(
        texture: TextureSource.asset('assets/masks/material_mask.png'),
        channels: <MaterialMaskChannel, MaterialEffectTarget>{
          MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
        },
      ),
      transmission: 0.7,
      transmissionTexture: const TextureSource.asset('assets/transmission.png'),
      ior: 1.45,
      thickness: 0.05,
      thicknessTexture: const TextureSource.asset('assets/thickness.png'),
      attenuationColor: const <double>[0.8, 0.9, 1.0],
      attenuationDistance: 6.0,
      clearcoat: 0.9,
      clearcoatTexture: const TextureSource.asset('assets/clearcoat.png'),
      clearcoatRoughness: 0.18,
      clearcoatRoughnessTexture:
          const TextureSource.asset('assets/clearcoat_roughness.png'),
      clearcoatNormalTexture:
          const TextureSource.asset('assets/clearcoat_normal.png'),
      clearcoatNormalScale: 0.7,
      specular: 0.55,
      specularTexture: const TextureSource.asset('assets/specular.png'),
      specularColorFactor: const <double>[0.2, 0.3, 0.4],
      specularColorTexture:
          const TextureSource.asset('assets/specular_color.png'),
      visible: false,
    );

    final roundTripped = MaterialPatch.fromJson(patch.toJson());

    expect(roundTripped.baseColorFactor, patch.baseColorFactor);
    expect(roundTripped.baseColorTexture, isA<AssetTextureSource>());
    expect(
      (roundTripped.baseColorTexture! as AssetTextureSource).assetPath,
      'assets/albedo.png',
    );
    expect(roundTripped.metallicRoughnessTexture, isA<AssetTextureSource>());
    expect(roundTripped.normalTexture, isA<AssetTextureSource>());
    expect(roundTripped.normalScale, 0.6);
    expect(roundTripped.metallic, 0.25);
    expect(roundTripped.roughness, 0.75);
    expect(roundTripped.emissiveFactor, patch.emissiveFactor);
    expect(roundTripped.emissiveTexture, isA<AssetTextureSource>());
    expect(roundTripped.occlusionTexture, isA<AssetTextureSource>());
    expect(roundTripped.occlusionStrength, 0.8);
    expect(roundTripped.alphaMode, MaterialAlphaMode.mask);
    expect(roundTripped.alphaCutoff, 0.42);
    expect(roundTripped.effectMask, isNotNull);
    expect(roundTripped.effectMask!.channels[MaterialMaskChannel.red],
        MaterialEffectTarget.paintRegion);
    expect(roundTripped.transmission, 0.7);
    expect(roundTripped.transmissionTexture, isA<AssetTextureSource>());
    expect(roundTripped.ior, 1.45);
    expect(roundTripped.thickness, 0.05);
    expect(roundTripped.thicknessTexture, isA<AssetTextureSource>());
    expect(roundTripped.attenuationColor, patch.attenuationColor);
    expect(roundTripped.attenuationDistance, 6.0);
    expect(roundTripped.clearcoat, 0.9);
    expect(roundTripped.clearcoatTexture, isA<AssetTextureSource>());
    expect(roundTripped.clearcoatRoughness, 0.18);
    expect(roundTripped.clearcoatRoughnessTexture, isA<AssetTextureSource>());
    expect(roundTripped.clearcoatNormalTexture, isA<AssetTextureSource>());
    expect(roundTripped.clearcoatNormalScale, 0.7);
    expect(roundTripped.specular, 0.55);
    expect(roundTripped.specularTexture, isA<AssetTextureSource>());
    expect(roundTripped.specularColorFactor, <double>[0.2, 0.3, 0.4]);
    expect(roundTripped.specularColorTexture, isA<AssetTextureSource>());
    expect(roundTripped.visible, isFalse);
  });

  test('MaterialPatch serializes binding fields to JSON and back', () {
    final binding = MaterialTextureBinding(
      source: const TextureSource.asset('assets/fabric.png'),
      transform: TextureTransform(scale: <double>[2.5, 2.5]),
    );
    final patch = MaterialPatch(
      baseColorTextureBinding: binding,
      metallicRoughnessTextureBinding: binding,
      normalTextureBinding: binding,
      occlusionTextureBinding: binding,
      emissiveTextureBinding: binding,
      transmissionTextureBinding: binding,
      thicknessTextureBinding: binding,
      clearcoatTextureBinding: binding,
      clearcoatRoughnessTextureBinding: binding,
      clearcoatNormalTextureBinding: binding,
      specularTextureBinding: binding,
      specularColorTextureBinding: binding,
    );

    final json = patch.toJson();
    final roundTripped = MaterialPatch.fromJson(json);

    expect(json.keys.where((key) => key.endsWith('TextureBinding')),
        hasLength(12));
    expect(roundTripped.baseColorTextureBinding, isNotNull);
    expect(roundTripped.metallicRoughnessTextureBinding, isNotNull);
    expect(roundTripped.normalTextureBinding, isNotNull);
    expect(roundTripped.occlusionTextureBinding, isNotNull);
    expect(roundTripped.emissiveTextureBinding, isNotNull);
    expect(roundTripped.transmissionTextureBinding, isNotNull);
    expect(roundTripped.thicknessTextureBinding, isNotNull);
    expect(roundTripped.clearcoatTextureBinding, isNotNull);
    expect(roundTripped.clearcoatRoughnessTextureBinding, isNotNull);
    expect(roundTripped.clearcoatNormalTextureBinding, isNotNull);
    expect(roundTripped.specularTextureBinding, isNotNull);
    expect(roundTripped.specularColorTextureBinding, isNotNull);
  });

  test('MaterialPatch keeps source-only JSON structurally unchanged', () {
    const patch = MaterialPatch(
      baseColorTexture: TextureSource.asset('assets/albedo.png'),
      normalTexture: TextureSource.asset('assets/normal.png'),
    );

    expect(patch.toJson(), <String, Object?>{
      'baseColorTexture': <String, Object?>{
        'type': 'asset',
        'assetPath': 'assets/albedo.png',
      },
      'normalTexture': <String, Object?>{
        'type': 'asset',
        'assetPath': 'assets/normal.png',
      },
    });
  });

  test('MaterialPatch normalizes source-only slots to default bindings', () {
    const patch = MaterialPatch(
      normalTexture: TextureSource.asset('assets/normal.png'),
    );

    final binding = patch.textureBindingFor(MaterialTextureSlot.normal);

    expect(binding, isNotNull);
    expect(binding!.source, same(patch.normalTexture));
    expect(binding.texCoord, 0);
    expect(binding.sampler.wrapS, TextureWrapMode.repeat);
    expect(binding.sampler.wrapT, TextureWrapMode.repeat);
    expect(binding.sampler.magFilter, isNull);
    expect(binding.sampler.minFilter, isNull);
    expect(binding.transform, same(TextureTransform.identity));
  });

  test('MaterialPatch reports source and binding slot conflicts', () {
    final patch = MaterialPatch(
      baseColorTexture: const TextureSource.asset('assets/source_albedo.png'),
      baseColorTextureBinding: MaterialTextureBinding(
        source: const TextureSource.asset('assets/binding_albedo.png'),
      ),
    );

    final diagnostics = patch.validate(
      PartAddress(
        nodePath: const <String>['Root', 'Fabric'],
        primitiveIndex: 0,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.code,
      ViewerDiagnosticCode.invalidMaterialOverride,
    );
    expect(diagnostics.single.details['slot'], 'baseColor');
    expect(diagnostics.single.details['sourceField'], 'baseColorTexture');
    expect(
      diagnostics.single.details['bindingField'],
      'baseColorTextureBinding',
    );
  });

  test('MaterialPatch JSON rejects source and binding slot conflicts', () {
    final binding = MaterialTextureBinding(
      source: const TextureSource.asset('assets/binding_albedo.png'),
    );

    expect(
      () => MaterialPatch.fromJson(<String, Object?>{
        'baseColorTexture': const TextureSource.asset(
          'assets/source_albedo.png',
        ).toJson(),
        'baseColorTextureBinding': binding.toJson(),
      }),
      throwsFormatException,
    );
  });

  test('MaterialPatch serializes explicit alpha modes to JSON and back', () {
    for (final mode in MaterialAlphaMode.values) {
      final patch = MaterialPatch(alphaMode: mode);

      final json = patch.toJson();
      final roundTripped = MaterialPatch.fromJson(json);

      expect(json['alphaMode'], mode.name);
      expect(roundTripped.alphaMode, mode);
    }
  });

  test('MaterialPatch serializes alpha cutoff to JSON and back', () {
    const patch = MaterialPatch(alphaCutoff: 0.28);

    final json = patch.toJson();
    final roundTripped = MaterialPatch.fromJson(json);

    expect(json['alphaCutoff'], 0.28);
    expect(roundTripped.alphaCutoff, 0.28);
  });

  test('TextureSource serializes byte textures to JSON and back', () {
    final source = TextureSource.bytes(
      Uint8List.fromList(<int>[1, 2, 3]),
      debugName: 'sample.png',
    );

    final roundTripped = TextureSource.fromJson(source.toJson());

    expect(roundTripped, isA<BytesTextureSource>());
    final bytes = roundTripped as BytesTextureSource;
    expect(bytes.encodedBytes, <int>[1, 2, 3]);
    expect(bytes.debugName, 'sample.png');
  });
}

MaterialExtensionSupport _specularAndIorSupport() {
  return MaterialExtensionSupport(
    backendKind: MaterialExtensionBackendKind.rendererNative,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      MaterialExtensionFeature.specular:
          MaterialExtensionFeatureSupport(available: true),
      MaterialExtensionFeature.ior:
          MaterialExtensionFeatureSupport(available: true),
    },
  );
}
