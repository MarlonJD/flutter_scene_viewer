import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_base_family.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opaque patch resolves to opaque base family', () {
    expect(
      resolveMaterialBaseFamily(const MaterialPatch(roughness: 0.6)),
      MaterialBaseFamily.opaque,
    );
    expect(
      resolveMaterialBaseFamily(
        MaterialPatch(baseColorFactor: const <double>[0.8, 0.7, 0.6, 1]),
      ),
      MaterialBaseFamily.opaque,
    );
  });

  test('alpha mask resolves to masked cutout base family', () {
    expect(
      resolveMaterialBaseFamily(
        const MaterialPatch(alphaMode: MaterialAlphaMode.mask),
      ),
      MaterialBaseFamily.maskedCutout,
    );
  });

  test('alpha blend resolves to translucent blend base family', () {
    expect(
      resolveMaterialBaseFamily(
        const MaterialPatch(alphaMode: MaterialAlphaMode.blend),
      ),
      MaterialBaseFamily.translucentBlend,
    );
  });

  test('base color alpha below one resolves to translucent blend base family',
      () {
    expect(
      resolveMaterialBaseFamily(
        MaterialPatch(baseColorFactor: const <double>[1, 1, 1, 0.4]),
      ),
      MaterialBaseFamily.translucentBlend,
    );
  });

  test('explicit alpha opaque keeps transparent base color in opaque family',
      () {
    expect(
      resolveMaterialBaseFamily(
        MaterialPatch(
          alphaMode: MaterialAlphaMode.opaque,
          baseColorFactor: const <double>[1, 1, 1, 0.4],
        ),
      ),
      MaterialBaseFamily.opaque,
    );
  });

  test('glass fields win over alpha mask and blend', () {
    expect(
      resolveMaterialBaseFamily(
        const MaterialPatch(
          alphaMode: MaterialAlphaMode.mask,
          transmission: 1.0,
        ),
      ),
      MaterialBaseFamily.realisticGlass,
    );
    expect(
      resolveMaterialBaseFamily(
        const MaterialPatch(
          alphaMode: MaterialAlphaMode.blend,
          ior: 1.45,
        ),
      ),
      MaterialBaseFamily.realisticGlass,
    );

    for (final patch in <MaterialPatch>[
      const MaterialPatch(transmissionTexture: TextureSource.asset('t.png')),
      const MaterialPatch(thickness: 0.02),
      const MaterialPatch(thicknessTexture: TextureSource.asset('v.png')),
      const MaterialPatch(attenuationColor: <double>[0.8, 0.9, 1.0]),
      const MaterialPatch(attenuationDistance: 4.0),
    ]) {
      expect(
          resolveMaterialBaseFamily(patch), MaterialBaseFamily.realisticGlass);
    }
  });

  test('clearcoat-only patch remains opaque until clearcoat shader support',
      () {
    expect(
      resolveMaterialBaseFamily(const MaterialPatch(clearcoat: 1.0)),
      MaterialBaseFamily.opaque,
    );
  });
}
