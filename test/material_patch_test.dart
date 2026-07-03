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

  test('empty patch is empty', () {
    expect(const MaterialPatch().isEmpty, isTrue);
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
    expect(roundTripped.visible, isFalse);
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
