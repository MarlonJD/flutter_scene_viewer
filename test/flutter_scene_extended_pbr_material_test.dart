import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('extended PBR defaults pack to the native dielectric contract', () {
    final packed = debugPackFlutterSceneExtendedPbrParameters(
      const <MaterialTextureSlot, TextureTransform>{},
    );

    expect(packed, hasLength(48));
    for (var offset = 0; offset < 40; offset += 8) {
      expect(
        packed.sublist(offset, offset + 8),
        <double>[0, 0, 1, 1, 1, 0, 0, 0],
      );
    }
    expect(packed.sublist(40, 44), <double>[1, 1, 1, 0]);
    expect(packed[44], 1);
    expect(packed[45], 1.5);
    expect(packed[46], 0);
    expect(packed[47], 0);
  });

  test('extended PBR packs independent UV state and extension flags', () {
    final packed = debugPackFlutterSceneExtendedPbrParameters(
      <MaterialTextureSlot, TextureTransform>{
        MaterialTextureSlot.baseColor: TextureTransform(
          offset: const <double>[0.1, 0.2],
          scale: const <double>[2.5, -3],
          rotation: math.pi / 2,
        ),
        MaterialTextureSlot.normal: TextureTransform(
          offset: const <double>[-0.25, 0.5],
          scale: const <double>[-1, 0.75],
          rotation: -math.pi / 4,
        ),
      },
      specularFactor: 0.6,
      specularColorFactor: const <double>[1.2, 0.8, 0.4],
      ior: 1.45,
      hasSpecularFactorTexture: true,
      hasSpecularColorTexture: true,
    );

    expect(
      packed.sublist(0, 8),
      <Object>[
        closeTo(0.1, 1e-6),
        closeTo(0.2, 1e-6),
        closeTo(2.5, 1e-6),
        closeTo(-3, 1e-6),
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
    expect(
      packed.sublist(40, 44),
      <Object>[
        closeTo(1.2, 1e-6),
        closeTo(0.8, 1e-6),
        closeTo(0.4, 1e-6),
        0,
      ],
    );
    expect(
      packed.sublist(44),
      <Object>[closeTo(0.6, 1e-6), closeTo(1.45, 1e-6), 1, 1],
    );
  });

  test('extended PBR state copy preserves the native material contract', () {
    final source = flutter_scene.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.1, 0.2, 0.3, 0.4)
      ..vertexColorWeight = 0.35
      ..metallicFactor = 0.45
      ..roughnessFactor = 0.55
      ..normalScale = 0.65
      ..occlusionStrength = 0.75
      ..clearcoatFactor = 0.6
      ..clearcoatRoughnessFactor = 0.35
      ..clearcoatNormalScale = 0.8
      ..emissiveFactor = vm.Vector4(0.8, 0.7, 0.6, 1)
      ..alphaMode = flutter_scene.AlphaMode.mask
      ..alphaCutoff = 0.25
      ..doubleSided = true
      ..specularAntiAliasingVariance = 0.12
      ..specularAntiAliasingThreshold = 0.18;
    final target = flutter_scene.PhysicallyBasedMaterial();

    debugCopyFlutterSceneExtendedPbrState(source, target);

    expect(target.baseColorFactor, source.baseColorFactor);
    expect(target.baseColorFactor, isNot(same(source.baseColorFactor)));
    expect(target.vertexColorWeight, 0.35);
    expect(target.metallicFactor, 0.45);
    expect(target.roughnessFactor, 0.55);
    expect(target.normalScale, 0.65);
    expect(target.occlusionStrength, 0.75);
    expect(target.clearcoatFactor, source.clearcoatFactor);
    expect(target.clearcoatRoughnessFactor, source.clearcoatRoughnessFactor);
    expect(target.clearcoatNormalScale, source.clearcoatNormalScale);
    expect(target.emissiveFactor, source.emissiveFactor);
    expect(target.emissiveFactor, isNot(same(source.emissiveFactor)));
    expect(target.alphaMode, flutter_scene.AlphaMode.mask);
    expect(target.alphaCutoff, 0.25);
    expect(target.doubleSided, isTrue);
    expect(target.specularAntiAliasingVariance, 0.12);
    expect(target.specularAntiAliasingThreshold, 0.18);
  });

  test('opaque IOR maps to dielectric F0 including compatibility zero', () {
    expect(debugFlutterSceneExtendedPbrIorF0(1), 0);
    expect(debugFlutterSceneExtendedPbrIorF0(1.5), closeTo(0.04, 1e-12));
    expect(debugFlutterSceneExtendedPbrIorF0(2), closeTo(1 / 9, 1e-12));
    expect(
      debugFlutterSceneExtendedPbrIorF0(0),
      1,
      reason: 'IOR 0 is full Fresnel compatibility, not clamped IOR 1.',
    );
  });

  test('specular controls dielectric Fresnel and shares diffuse energy', () {
    final normal = debugFlutterSceneExtendedPbrDielectricFresnel(
      ior: 1.5,
      specularFactor: 0.5,
      specularColorFactor: const <double>[2, 1, 0.5],
      cosine: 1,
    );
    expect(normal, <Object>[
      closeTo(0.04, 1e-12),
      closeTo(0.02, 1e-12),
      closeTo(0.01, 1e-12),
    ]);
    expect(
      debugFlutterSceneExtendedPbrDiffuseWeight(normal),
      closeTo(0.96, 1e-12),
    );

    final grazing = debugFlutterSceneExtendedPbrDielectricFresnel(
      ior: 1.5,
      specularFactor: 0.5,
      specularColorFactor: const <double>[2, 1, 0.5],
      cosine: 0,
    );
    expect(grazing, everyElement(closeTo(0.5, 1e-12)));
    expect(
      debugFlutterSceneExtendedPbrDiffuseWeight(grazing),
      closeTo(0.5, 1e-12),
    );
  });

  test('IOR zero stays full Fresnel independently of angle and specular', () {
    for (final cosine in <double>[0, 0.2, 0.7, 1]) {
      expect(
        debugFlutterSceneExtendedPbrDielectricFresnel(
          ior: 0,
          specularFactor: 0,
          specularColorFactor: const <double>[0, 0, 0],
          cosine: cosine,
        ),
        <double>[1, 1, 1],
        reason: '$cosine',
      );
    }
  });

  test('metallic F0 is isolated from dielectric specular controls', () {
    const albedo = <double>[0.8, 0.3, 0.1];
    final metallic = debugFlutterSceneExtendedPbrSurfaceF0(
      albedo: albedo,
      metallic: 1,
      ior: 1.8,
      specularFactor: 0,
      specularColorFactor: const <double>[0, 4, 9],
    );
    expect(metallic, albedo);
  });

  test('extended fragment owns specular IOR lighting and reflected slots', () {
    const fragmentPath = 'shaders/fsviewer_extended_pbr.frag';
    final source = File(fragmentPath).readAsStringSync();

    expect(source, contains('EvaluateExtendedPbrLighting'));
    expect(source, isNot(contains('frag_color = EvaluateLighting(material)')));
    expect(
      source,
      matches(
        RegExp(
          r'texture\(specular_factor_texture,[^;]+\)\.a',
          dotAll: true,
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'SRGBToLinear\(texture\(specular_color_texture,[^;]+\)\.rgb\)',
          dotAll: true,
        ),
      ),
    );
    expect(source, contains('extended_pbr.material_ior == 0.0'));
    expect(source, contains('vec3 dielectric_f0'));
    expect(source, contains('vec3 dielectric_f90'));
    expect(source, contains('mix(dielectric_f0, albedo, metallic)'));
    expect(source, contains('mix(dielectric_f90, vec3(1.0), metallic)'));
    expect(source, contains('SamplePrimaryRadiance'));
    expect(source, contains('SampleSecondaryRadiance'));
    expect(source, isNot(contains('SampleRadianceEnv(')));

    final bundle = File(
      'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    );
    expect(bundle.existsSync(), isTrue);
    final reflectionText = latin1.decode(bundle.readAsBytesSync());
    for (final name in <String>[
      'FSViewerExtendedPbr',
      'ExtendedPbrParams',
      'specular_factor_texture',
      'specular_color_texture',
      'material_ior',
    ]) {
      expect(reflectionText, contains(name), reason: name);
    }
  });

  test('extended fragment lights back faces with face-correct normals', () {
    final source =
        File('shaders/fsviewer_extended_pbr.frag').readAsStringSync();

    expect(source, contains('vec3 ExtendedPbrGeometricNormal()'));
    expect(
      source,
      matches(
        RegExp(
          r'return gl_FrontFacing\s*\?\s*normalize\(v_normal\)\s*'
          r':\s*-normalize\(v_normal\);',
        ),
      ),
      reason: 'glTF double-sided back faces must reverse their normal.',
    );
    expect(
      RegExp(
        r'vec3 (?:normal|geometric_normal) = '
        r'ExtendedPbrGeometricNormal\(\);',
      ).allMatches(source),
      hasLength(2),
      reason:
          'Surface perturbation and geometric lighting must share face orientation.',
    );
    expect(
      source,
      isNot(contains('GetWorldNormal()')),
      reason:
          'Unoriented geometric normals must not leak into energy, light, or shadow terms.',
    );
  });

  test('extended fragment applies core UV0 transforms without asset branches',
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
      expect(
        source,
        contains('vec2 ${slot}_uv = TransformExtendedPbrUv('),
        reason: '$slot must calculate its UV independently.',
      );
    }
    expect(
      source,
      matches(
        RegExp(
          r'PerturbNormal\(normal_texture,\s*normal,\s*v_viewvector,\s*'
          r'normal_uv,\s*frag_info\.normal_scale\)',
        ),
      ),
      reason:
          'The normal read and derivative tangent frame must share transformed UVs.',
    );
    for (final forbidden in <String>['A1B32', 'C28', 'Glorvia']) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('clearcoat transform variant delegates layered lighting upstream', () {
    final source = File(
      'shaders/fsviewer_clearcoat_extended_pbr.frag',
    ).readAsStringSync();

    expect(source, contains('uniform sampler2D clearcoat_texture;'));
    expect(source, contains('uniform sampler2D clearcoat_roughness_texture;'));
    expect(source, contains('uniform sampler2D clearcoat_normal_texture;'));
    expect(source, contains('texture(clearcoat_texture, v_texture_coords).r'));
    expect(
      source,
      contains('texture(clearcoat_roughness_texture, v_texture_coords).g'),
    );
    expect(source, contains('frag_color = EvaluateLighting(material);'));
    expect(
      source,
      isNot(contains('uniform sampler2D specular_factor_texture;')),
    );
    expect(
      source,
      isNot(contains('uniform sampler2D specular_color_texture;')),
    );
  });

  test('build hook packages only the combined extended PBR route', () {
    final hook = File('hook/build.dart').readAsStringSync();

    expect(
      hook,
      contains('shaders/fsviewer_extended_pbr.shaderbundle.json'),
    );
    expect(hook, isNot(contains('fsviewer_uv_transform_pbr.fmat')));
  });

  test('flutter_scene shader structure retains its MIT attribution', () {
    final source =
        File('shaders/fsviewer_extended_pbr.frag').readAsStringSync();
    final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();

    expect(
      source,
      contains('ccf7372428961ebe0abb053727fe443150547a74'),
    );
    expect(source, contains('THIRD_PARTY_NOTICES.md'));
    expect(notices, contains('flutter_scene'));
    expect(notices, contains('Copyright (c) 2023 Brandon DeRosier'));
    expect(notices, contains('Permission is hereby granted, free of charge'));
  });
}
