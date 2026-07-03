import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MaterialEffectMask serializes to JSON and back', () {
    const mask = MaterialEffectMask(
      texture: TextureSource.asset('assets/masks/material_mask.png'),
      channels: <MaterialMaskChannel, MaterialEffectTarget>{
        MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
        MaterialMaskChannel.green: MaterialEffectTarget.roughness,
        MaterialMaskChannel.blue: MaterialEffectTarget.dirt,
      },
    );

    final json = mask.toJson();
    final roundTripped = MaterialEffectMask.fromJson(json);

    expect(roundTripped.texture, isA<AssetTextureSource>());
    expect(
      (roundTripped.texture as AssetTextureSource).assetPath,
      'assets/masks/material_mask.png',
    );
    expect(roundTripped.channels, mask.channels);
  });

  test('duplicate effect targets validate as invalid material override', () {
    const mask = MaterialEffectMask(
      texture: TextureSource.asset('assets/masks/material_mask.png'),
      channels: <MaterialMaskChannel, MaterialEffectTarget>{
        MaterialMaskChannel.red: MaterialEffectTarget.roughness,
        MaterialMaskChannel.green: MaterialEffectTarget.roughness,
      },
    );

    final diagnostics = mask.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(1));
    expect(
        diagnostics.single.code, ViewerDiagnosticCode.invalidMaterialOverride);
    expect(diagnostics.single.details['field'], 'effectMask.channels');
    expect(diagnostics.single.details['target'], 'roughness');
  });

  test('malformed JSON channel and target names validate as invalid', () {
    final mask = MaterialEffectMask.fromJson(
      <String, Object?>{
        'texture': const TextureSource.asset('assets/masks/material_mask.png')
            .toJson(),
        'channels': <String, Object?>{
          'purple': 'roughness',
          'red': 'unsupportedTarget',
        },
      },
    );

    final diagnostics = mask.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
    );

    expect(diagnostics, hasLength(2));
    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      everyElement(ViewerDiagnosticCode.invalidMaterialOverride),
    );
    expect(
      diagnostics.map((diagnostic) => diagnostic.details['field']),
      containsAll(<String>['effectMask.channel', 'effectMask.target']),
    );
  });
}
