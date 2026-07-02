import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MaterialPatch merges sparse fields', () {
    const first = MaterialPatch(metallic: 0.2);
    const second = MaterialPatch(roughness: 0.8);

    final merged = first.merge(second);

    expect(merged.metallic, 0.2);
    expect(merged.roughness, 0.8);
    expect(merged.isEmpty, isFalse);
  });

  test('empty patch is empty', () {
    expect(const MaterialPatch().isEmpty, isTrue);
  });

  test('MaterialPatch reports invalid metallic and roughness values', () {
    const patch = MaterialPatch(metallic: 1.2, roughness: -0.1);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Body'], primitiveIndex: 0),
    );

    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      everyElement(ViewerDiagnosticCode.invalidMaterialOverride),
    );
    expect(diagnostics, hasLength(2));
  });

  test('MaterialPatch serializes to JSON and back', () {
    final patch = MaterialPatch(
      baseColorFactor: const <double>[0.1, 0.2, 0.3, 0.4],
      baseColorTexture: const TextureSource.asset('assets/albedo.png'),
      metallic: 0.25,
      roughness: 0.75,
      emissiveFactor: const <double>[1, 0.5, 0.25],
      visible: false,
    );

    final roundTripped = MaterialPatch.fromJson(patch.toJson());

    expect(roundTripped.baseColorFactor, patch.baseColorFactor);
    expect(roundTripped.baseColorTexture, isA<AssetTextureSource>());
    expect(
      (roundTripped.baseColorTexture! as AssetTextureSource).assetPath,
      'assets/albedo.png',
    );
    expect(roundTripped.metallic, 0.25);
    expect(roundTripped.roughness, 0.75);
    expect(roundTripped.emissiveFactor, patch.emissiveFactor);
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
