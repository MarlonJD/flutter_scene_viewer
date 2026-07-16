import 'dart:io';

// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf.dart' as flutter_scene_gltf;
import 'package:flutter_scene_viewer/src/internal/glb_material_extension_reader.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_patch_group.dart';
import 'package:flutter_test/flutter_test.dart';

const _corpusRoot =
    'tools/out/material_extension_acceptance/plan015_renderer_native_clearcoat';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fixture in const <_ClearcoatFixture>[
    _ClearcoatFixture(
      id: 'clearcoat_test',
      fileName: 'ClearCoatTest.glb',
      expectsFactorTexture: true,
      expectsRoughnessTexture: true,
      expectsNormalTexture: true,
    ),
    _ClearcoatFixture(
      id: 'clearcoat_car_paint',
      fileName: 'ClearCoatCarPaint.glb',
    ),
    _ClearcoatFixture(
      id: 'toycar',
      fileName: 'ToyCar.glb',
      expectsFactorTexture: true,
    ),
  ]) {
    final path = '$_corpusRoot/${fixture.id}/${fixture.fileName}';
    test(
      '${fixture.fileName} reaches the renderer-native clearcoat material',
      () async {
        final bytes = File(path).readAsBytesSync();
        final intent = readGlbMaterialExtensionIntent(
          bytes,
          debugName: fixture.fileName,
        );
        final clearcoatPatches = intent.patches.values
            .map((groups) => groups[MaterialExtensionPatchGroup.clearcoat])
            .whereType<Object>()
            .toList(growable: false);

        expect(intent.diagnostics, isEmpty);
        expect(clearcoatPatches, isNotEmpty);

        final container = flutter_scene_gltf.parseGlb(bytes);
        final document = flutter_scene_gltf.parseGltfJson(container.json);
        final materials = document.materials
            .map((material) => material.clearcoat)
            .whereType<flutter_scene_gltf.GltfMaterialClearcoat>()
            .where((clearcoat) => clearcoat.clearcoatFactor > 0)
            .toList(growable: false);

        expect(materials, isNotEmpty);
        if (fixture.expectsFactorTexture) {
          expect(
            materials.any((clearcoat) => clearcoat.clearcoatTexture != null),
            isTrue,
          );
        }
        if (fixture.expectsRoughnessTexture) {
          expect(
            materials.any(
              (clearcoat) => clearcoat.clearcoatRoughnessTexture != null,
            ),
            isTrue,
          );
        }
        if (fixture.expectsNormalTexture) {
          expect(
            materials.any(
              (clearcoat) => clearcoat.clearcoatNormalTexture != null,
            ),
            isTrue,
          );
        }
      },
      skip: File(path).existsSync()
          ? false
          : 'Run the hash-pinned Plan 015 fixture staging command first.',
    );
  }
}

final class _ClearcoatFixture {
  const _ClearcoatFixture({
    required this.id,
    required this.fileName,
    this.expectsFactorTexture = false,
    this.expectsRoughnessTexture = false,
    this.expectsNormalTexture = false,
  });

  final String id;
  final String fileName;
  final bool expectsFactorTexture;
  final bool expectsRoughnessTexture;
  final bool expectsNormalTexture;
}
