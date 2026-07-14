import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('combined extended PBR path packs independent core UV transforms', () {
    final packed = debugPackFlutterSceneExtendedPbrParameters(
      <MaterialTextureSlot, TextureTransform>{
        MaterialTextureSlot.baseColor: TextureTransform(
          offset: const <double>[0.1, 0.2],
          scale: const <double>[2.5, 3],
          rotation: math.pi / 2,
        ),
        MaterialTextureSlot.normal: TextureTransform(
          offset: const <double>[-0.25, 0.5],
          scale: const <double>[-1, 0.75],
          rotation: -math.pi / 4,
        ),
      },
    );

    expect(packed, hasLength(48));
    expect(
      packed.sublist(0, 8),
      <Object>[
        closeTo(0.1, 1e-6),
        closeTo(0.2, 1e-6),
        closeTo(2.5, 1e-6),
        closeTo(3, 1e-6),
        closeTo(0, 1e-6),
        closeTo(1, 1e-6),
        0,
        0,
      ],
    );
    expect(
      packed.sublist(16, 24),
      <Object>[
        closeTo(-0.25, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(-1, 1e-6),
        closeTo(0.75, 1e-6),
        closeTo(math.sqrt1_2, 1e-6),
        closeTo(-math.sqrt1_2, 1e-6),
        0,
        0,
      ],
    );
  });

  test('combined fragment transforms every core slot and normal derivatives',
      () {
    final source =
        File('shaders/fsviewer_extended_pbr.frag').readAsStringSync();

    expect(source, contains('vec2 scaled = uv * offset_scale.zw;'));
    expect(source, contains('return offset_scale.xy + rotated;'));
    for (final slot in <String>[
      'base_color',
      'metallic_roughness',
      'normal',
      'occlusion',
      'emissive',
    ]) {
      expect(source, contains('vec2 ${slot}_uv = TransformExtendedPbrUv('));
    }
    expect(
      source,
      matches(
        RegExp(
          r'PerturbNormal\(normal_texture,\s*normal,\s*v_viewvector,\s*'
          r'normal_uv,\s*frag_info\.normal_scale\)',
        ),
      ),
    );
    for (final forbidden in <String>['A1B32', 'C28', 'Glorvia']) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('legacy Task 6 test path guards only the combined build route', () {
    final hook = File('hook/build.dart').readAsStringSync();

    expect(
      hook,
      contains('shaders/fsviewer_extended_pbr.shaderbundle.json'),
    );
    expect(hook, isNot(contains('fsviewer_uv_transform_pbr.fmat')));
    expect(File('assets/materials/fsviewer_uv_transform_pbr.fmat').existsSync(),
        isFalse);
  });
}
