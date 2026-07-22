import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_material.dart';
import 'package:flutter_scene_viewer/src/internal/sheen_semantics.dart';
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

  test('sheen packs two transforms factors and texture flags into 24 floats',
      () {
    final packed = debugPackFlutterSceneSheenParameters(
      <MaterialTextureSlot, TextureTransform>{
        MaterialTextureSlot.sheenColor: TextureTransform(
          offset: const <double>[0.1, 0.2],
          scale: const <double>[2, 3],
          rotation: math.pi / 2,
        ),
        MaterialTextureSlot.sheenRoughness: TextureTransform(
          offset: const <double>[-0.4, 0.5],
          scale: const <double>[0.25, -0.75],
          rotation: -math.pi / 4,
        ),
      },
      sheenColorFactor: const <double>[0.2, 0.4, 0.8],
      sheenRoughness: 0.35,
      hasSheenColorTexture: true,
      hasSheenRoughnessTexture: true,
    );

    expect(packed, hasLength(24));
    expect(
      packed.sublist(0, 8),
      <Object>[
        closeTo(0.1, 1e-6),
        closeTo(0.2, 1e-6),
        2,
        3,
        closeTo(0, 1e-6),
        closeTo(1, 1e-6),
        0,
        0,
      ],
    );
    expect(
      packed.sublist(8, 16),
      <Object>[
        closeTo(-0.4, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(0.25, 1e-6),
        closeTo(-0.75, 1e-6),
        closeTo(math.sqrt1_2, 1e-6),
        closeTo(-math.sqrt1_2, 1e-6),
        0,
        0,
      ],
    );
    expect(
      packed.sublist(16),
      <Object>[
        closeTo(0.2, 1e-6),
        closeTo(0.4, 1e-6),
        closeTo(0.8, 1e-6),
        0,
        closeTo(0.35, 1e-6),
        1,
        1,
        0,
      ],
    );
  });

  test('combined clearcoat sheen packs two independent coat transforms', () {
    final packed = debugPackFlutterSceneClearcoatSheenParameters(
      <MaterialTextureSlot, TextureTransform>{
        MaterialTextureSlot.clearcoat: TextureTransform(
          offset: const <double>[0.1, -0.2],
          scale: const <double>[2, 3],
          rotation: math.pi / 2,
        ),
        MaterialTextureSlot.clearcoatRoughness: TextureTransform(
          offset: const <double>[0.4, 0.5],
          scale: const <double>[-0.25, 0.75],
          rotation: -math.pi / 4,
        ),
      },
    );

    expect(packed, hasLength(16));
    expect(
      packed.sublist(0, 8),
      <Object>[
        closeTo(0.1, 1e-6),
        closeTo(-0.2, 1e-6),
        2,
        3,
        closeTo(0, 1e-6),
        closeTo(1, 1e-6),
        0,
        0,
      ],
    );
    expect(
      packed.sublist(8),
      <Object>[
        closeTo(0.4, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(-0.25, 1e-6),
        closeTo(0.75, 1e-6),
        closeTo(math.sqrt1_2, 1e-6),
        closeTo(-math.sqrt1_2, 1e-6),
        0,
        0,
      ],
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
      // ignore: invalid_use_of_internal_member
      ..occlusionTextureTexCoord = 1
      // ignore: invalid_use_of_internal_member
      ..occlusionTextureTransform =
          const flutter_scene.MaterialTextureTransform(
        offsetX: 0.2,
        offsetY: 0.3,
        rotation: 0.4,
        scaleX: 1.5,
        scaleY: 1.6,
      )
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
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTexCoord, 1);
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTransform.offsetX, 0.2);
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTransform.offsetY, 0.3);
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTransform.rotation, 0.4);
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTransform.scaleX, 1.5);
    // ignore: invalid_use_of_internal_member
    expect(target.occlusionTextureTransform.scaleY, 1.6);
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

  test('custom PBR UV1 variants select authored AO coordinates explicitly', () {
    const shaderFiles = <String>[
      'fsviewer_extended_pbr',
      'fsviewer_clearcoat_extended_pbr',
      'fsviewer_sheen_extended_pbr',
      'fsviewer_clearcoat_sheen_extended_pbr',
    ];
    for (final stem in shaderFiles) {
      final source = File('shaders/$stem.frag').readAsStringSync();
      expect(
        source,
        contains(
          'SelectTextureCoordinates(frag_info.texture_coord_sets0.x)',
        ),
        reason: stem,
      );
      final uv1 = File('shaders/${stem}_uv1.frag').readAsStringSync();
      expect(uv1, contains('#define HAS_TEXTURE_COORD_1'), reason: stem);
      expect(uv1, contains('#include <$stem.frag>'), reason: stem);
    }

    final manifest = jsonDecode(
      File('shaders/fsviewer_extended_pbr.shaderbundle.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    const entries = <String, String>{
      'FSViewerExtendedPbrUV1': 'fsviewer_extended_pbr_uv1',
      'FSViewerClearcoatExtendedPbrUV1': 'fsviewer_clearcoat_extended_pbr_uv1',
      'FSViewerSheenExtendedPbrUV1': 'fsviewer_sheen_extended_pbr_uv1',
      'FSViewerClearcoatSheenExtendedPbrUV1':
          'fsviewer_clearcoat_sheen_extended_pbr_uv1',
    };
    for (final entry in entries.entries) {
      expect(
        manifest[entry.key],
        <String, Object?>{
          'type': 'fragment',
          'file': 'shaders/${entry.value}.frag',
        },
        reason: entry.key,
      );
    }
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

  test('sheen fragment owns Charlie direct IBL energy and zero branch', () {
    final source =
        File('shaders/fsviewer_sheen_extended_pbr.frag').readAsStringSync();

    expect(source, contains('uniform SheenParams'));
    expect(source, contains('uniform sampler2D sheen_color_texture;'));
    expect(source, contains('uniform sampler2D sheen_roughness_texture;'));
    expect(
      source,
      matches(
        RegExp(
          r'SRGBToLinear\(texture\(sheen_color_texture,[^;]+\)\.rgb\)',
          dotAll: true,
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'texture\(sheen_roughness_texture,[^;]+\)\.a',
          dotAll: true,
        ),
      ),
    );
    expect(source, contains('max(sheen_roughness, 0.07)'));
    expect(source, contains('0.0078125'));
    for (final coefficient in <String>[
      '21.5473',
      '25.3245',
      '3.82987',
      '3.32435',
      '0.19823',
      '0.16801',
      '-1.97760',
      '-1.27393',
      '-4.32054',
      '-4.85967',
    ]) {
      expect(source, contains(coefficient), reason: coefficient);
    }
    expect(source, contains('float SheenCharlieDistribution('));
    expect(source, contains('float SheenCharlieVisibility('));
    expect(source, contains('vec3 direct_sheen'));
    expect(source, contains('vec3 indirect_sheen'));
    expect(source, contains('texture(brdf_lut'));
    expect(source, contains('.b;'));
    expect(source, contains('base_direct * direct_sheen_attenuation'));
    expect(source, contains('base_ambient * indirect_sheen_attenuation'));
    expect(source, contains('if (max_sheen_color <= 0.0)'));
    expect(source, contains('return EvaluateSheenZeroLighting(material);'));
    expect(
      source,
      contains('candidate-only approximation: GGX-prefiltered radiance'),
    );
    for (final forbidden in <String>[
      'frag_info.environment_intensity *=',
      'material.roughness = sheen_roughness',
      'material.base_color = vec4(sheen',
      'rim_light',
      'A1B32',
      'C28',
      'Glorvia',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }

    final manifest = jsonDecode(
      File('shaders/fsviewer_extended_pbr.shaderbundle.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    expect(
      manifest['FSViewerSheenExtendedPbr'],
      <String, Object?>{
        'type': 'fragment',
        'file': 'shaders/fsviewer_sheen_extended_pbr.frag',
      },
    );

    final bundle = File(
      'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    );
    expect(bundle.existsSync(), isTrue);
    final reflectionText = latin1.decode(bundle.readAsBytesSync());
    for (final name in <String>[
      'FSViewerSheenExtendedPbr',
      'SheenParams',
      'sheen_color_texture',
      'sheen_roughness_texture',
      'brdf_lut',
    ]) {
      expect(reflectionText, contains(name), reason: name);
    }
  });

  test('combined fragment layers clearcoat above base and sheen exactly once',
      () {
    final source = File(
      'shaders/fsviewer_clearcoat_sheen_extended_pbr.frag',
    ).readAsStringSync();

    expect(source, contains('uniform SheenParams'));
    expect(source, contains('uniform ClearcoatSheenParams'));
    expect(
      RegExp(r'^uniform sampler2D ', multiLine: true).allMatches(source),
      hasLength(9),
    );
    for (final sampler in <String>[
      'base_color_texture',
      'emissive_texture',
      'metallic_roughness_texture',
      'normal_texture',
      'occlusion_texture',
      'sheen_color_texture',
      'sheen_roughness_texture',
      'clearcoat_texture',
      'clearcoat_roughness_texture',
    ]) {
      expect(source, contains('uniform sampler2D $sampler;'), reason: sampler);
    }
    for (final forbidden in <String>[
      'uniform sampler2D specular_factor_texture;',
      'uniform sampler2D specular_color_texture;',
      'uniform sampler2D clearcoat_normal_texture;',
      'frag_color = EvaluateLighting(material);',
      'GetWorldNormal()',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('material.normal = normal;'));
    expect(source, contains('material.clearcoat_normal = geometric_normal;'));
    expect(
      source,
      contains('texture(clearcoat_texture, clearcoat_uv).r'),
    );
    expect(
      source,
      contains(
        'texture(clearcoat_roughness_texture, clearcoat_roughness_uv).g',
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'PerturbNormal\(normal_texture,\s*normal,\s*v_viewvector,\s*'
          r'normal_uv,\s*frag_info\.normal_scale\)',
        ),
      ),
    );
    expect(
        source, contains('vec3 env_normal = environment_transform * normal;'));
    expect(
      source,
      contains(
        'environment_transform * reflect(-camera_normal, clearcoat_normal)',
      ),
    );
    expect(
      source,
      contains(
        '(base_ambient * indirect_sheen_attenuation + indirect_sheen) *\n'
        '          base_layer_view_attenuation +\n'
        '      clearcoat_indirect_specular * clearcoat_specular_occlusion',
      ),
    );
    expect(
      source,
      contains(
        '(base_direct * direct_sheen_attenuation + direct_sheen) *\n'
        '        (1.0 - clearcoat_direct_fresnel) *\n'
        '        frag_info.directional_light_color.rgb * n_dot_l * shadow',
      ),
    );
    expect(source, contains('direct += direct_clearcoat;'));
    expect(
      source,
      contains(
        'vec3 emissive = material.emissive * base_layer_view_attenuation;',
      ),
    );
    expect(
      source,
      contains(
        'return ApplyFog(vec4(out_color, 1.0) * alpha, sky_fog_color);',
      ),
    );

    final manifest = jsonDecode(
      File('shaders/fsviewer_extended_pbr.shaderbundle.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    expect(
      manifest['FSViewerClearcoatSheenExtendedPbr'],
      <String, Object?>{
        'type': 'fragment',
        'file': 'shaders/fsviewer_clearcoat_sheen_extended_pbr.frag',
      },
    );

    final bundle = File(
      'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
    );
    expect(bundle.existsSync(), isTrue);
    final reflectionText = latin1.decode(bundle.readAsBytesSync());
    for (final name in <String>[
      'FSViewerClearcoatSheenExtendedPbr',
      'ExtendedPbrParams',
      'SheenParams',
      'ClearcoatSheenParams',
      'sheen_color_texture',
      'sheen_roughness_texture',
      'clearcoat_texture',
      'clearcoat_roughness_texture',
      'brdf_lut',
    ]) {
      expect(reflectionText, contains(name), reason: name);
    }
  });

  test('combined scalar composition keeps clearcoat above both lower lobes',
      () {
    final noCoat = _composeClearcoatAboveSheen(
      baseIndirect: 2,
      sheenIndirect: 0.5,
      sheenViewAttenuation: 0.75,
      clearcoatIndirect: 0,
      clearcoatViewFresnel: 0,
      baseDirect: 3,
      sheenDirect: 0.25,
      sheenDirectAttenuation: 0.5,
      clearcoatDirect: 0,
      clearcoatHalfFresnel: 0,
      emission: 0.4,
    );
    expect(noCoat.indirect, 2);
    expect(noCoat.direct, 1.75);
    expect(noCoat.emission, 0.4);

    final attenuated = _composeClearcoatAboveSheen(
      baseIndirect: 2,
      sheenIndirect: 0.5,
      sheenViewAttenuation: 0.75,
      clearcoatIndirect: 0,
      clearcoatViewFresnel: 0.25,
      baseDirect: 3,
      sheenDirect: 0.25,
      sheenDirectAttenuation: 0.5,
      clearcoatDirect: 0,
      clearcoatHalfFresnel: 0.4,
      emission: 0.4,
    );
    expect(attenuated.indirect, 1.5);
    expect(attenuated.direct, 1.05);
    expect(attenuated.emission, closeTo(0.3, 1e-12));

    final withCoat = _composeClearcoatAboveSheen(
      baseIndirect: 2,
      sheenIndirect: 0.5,
      sheenViewAttenuation: 0.75,
      clearcoatIndirect: 0.2,
      clearcoatViewFresnel: 0.25,
      baseDirect: 3,
      sheenDirect: 0.25,
      sheenDirectAttenuation: 0.5,
      clearcoatDirect: 0.3,
      clearcoatHalfFresnel: 0.4,
      emission: 0.4,
    );
    expect(withCoat.lowerIndirect, attenuated.lowerIndirect);
    expect(withCoat.lowerDirect, attenuated.lowerDirect);
    expect(withCoat.indirect - attenuated.indirect, closeTo(0.2, 1e-12));
    expect(withCoat.direct - attenuated.direct, closeTo(0.3, 1e-12));
    expect(withCoat.emission, attenuated.emission);
  });

  test(
      'direct fitted sheen visibility matches the pinned current Sample Renderer clamp',
      () {
    for (final contract in <({String path, String functionName})>[
      (
        path: 'shaders/fsviewer_sheen_extended_pbr.frag',
        functionName: 'SheenCharlieVisibility',
      ),
      (
        path: 'shaders/fsviewer_clearcoat_sheen_extended_pbr.frag',
        functionName: 'ClearcoatSheenCharlieVisibility',
      ),
    ]) {
      final source = File(contract.path).readAsStringSync();
      final functionStart = source.indexOf('float ${contract.functionName}(');
      final functionEnd = source.indexOf('\n}\n', functionStart);

      expect(functionStart, greaterThanOrEqualTo(0), reason: contract.path);
      expect(functionEnd, greaterThan(functionStart), reason: contract.path);
      expect(
        source.substring(functionStart, functionEnd),
        matches(
          RegExp(
            r'return\s+clamp\(\s*1\.0\s*/\s*'
            r'max\(denominator,\s*1e-6\),\s*0\.0,\s*1\.0\s*\);',
          ),
        ),
        reason: contract.path,
      );
    }
  });

  test('sheen directional albedo follows the perturbed base normal', () {
    for (final contract in <({String path, String functionName})>[
      (
        path: 'shaders/fsviewer_sheen_extended_pbr.frag',
        functionName: 'SheenDirectionalAlbedo',
      ),
      (
        path: 'shaders/fsviewer_clearcoat_sheen_extended_pbr.frag',
        functionName: 'ClearcoatSheenDirectionalAlbedo',
      ),
    ]) {
      final source = File(contract.path).readAsStringSync();
      expect(
        source,
        contains('float n_dot_v = max(dot(normal, camera_normal), 0.0);'),
        reason: contract.path,
      );
      expect(
        source,
        matches(
          RegExp(
            '${contract.functionName}'
            r'\(n_dot_v,\s*sheen_roughness\)',
          ),
        ),
        reason: contract.path,
      );
      expect(
        source,
        isNot(
          matches(
            RegExp(
              '${contract.functionName}'
              r'\(n_dot_v_energy,\s*sheen_roughness\)',
            ),
          ),
        ),
        reason: contract.path,
      );
    }
  });

  test('sheen candidate matrix separates direct IBL grazing and black paths',
      () {
    const color = <double>[1, 0.25, 0];
    const roughness = 0.5;
    final directNormal = _candidateDirectSheen(
      color: color,
      roughness: roughness,
      nDotV: 0.5,
      nDotL: 0.5,
      nDotH: 0.8,
    );
    final directGrazing = _candidateDirectSheen(
      color: color,
      roughness: roughness,
      nDotV: 0.5,
      nDotL: 0.5,
      nDotH: 0.2,
    );
    final iblOnly = _candidateIblSheen(
      color: color,
      roughness: roughness,
      nDotV: 0.5,
      radiance: const <double>[0.4, 0.4, 0.4],
    );

    expect(directNormal[0], greaterThan(0));
    expect(directGrazing[0], greaterThan(directNormal[0]));
    expect(directGrazing[1], closeTo(directGrazing[0] * 0.25, 1e-12));
    expect(directGrazing[2], 0);
    expect(iblOnly[0], greaterThan(0));
    expect(iblOnly[1], closeTo(iblOnly[0] * 0.25, 1e-12));
    expect(iblOnly[2], 0);
    expect(
      directGrazing[0] + iblOnly[0],
      greaterThan(directGrazing[0]),
    );
    expect(
      _candidateDirectSheen(
        color: color,
        roughness: roughness,
        nDotV: 0.5,
        nDotL: 0.5,
        nDotH: 0.2,
        shadow: 0,
      ),
      <double>[0, 0, 0],
    );

    final blackSample = resolveGltfSheenSample(
      colorFactor: const <double>[1, 1, 1],
      roughnessFactor: roughness,
      colorTextureSampleSrgb: const <double>[0, 0, 0, 1],
    );
    expect(blackSample.isEnabled, isFalse);
    expect(
      _candidateDirectSheen(
        color: blackSample.linearColor,
        roughness: blackSample.roughness,
        nDotV: 0.5,
        nDotL: 0.5,
        nDotH: 0.2,
      ),
      <double>[0, 0, 0],
    );
  });

  test('sheen shader keeps direct and IBL controls independently gated', () {
    final source =
        File('shaders/fsviewer_sheen_extended_pbr.frag').readAsStringSync();
    final layeredStart = source.indexOf('vec4 EvaluateSheenLayeredLighting(');
    final layeredEnd = source.indexOf('\nvoid main()', layeredStart);
    final layered = source.substring(layeredStart, layeredEnd);

    expect(
      layered,
      contains(
        'if (frag_info.has_directional_light > 0.5 && n_dot_l > 0.0)',
      ),
    );
    expect(layered, contains('vec3 direct_sheen'));
    expect(layered, contains('sheen_distribution * sheen_visibility'));
    expect(layered, contains('* n_dot_l * shadow'));
    expect(layered, contains('vec3 indirect_sheen'));
    expect(layered, contains('sheen_prefiltered_color'));
    expect(layered, contains('sheen_energy_v'));
    expect(layered, contains('sheen_energy_l'));
    expect(layered, contains('base_direct * direct_sheen_attenuation'));
    expect(layered, contains('base_ambient * indirect_sheen_attenuation'));
    expect(
        layered, contains('DistributionGGX(normal, half_vector, roughness)'));
    expect(
      layered,
      contains('SheenCharlieDistribution(n_dot_h, sheen_roughness)'),
    );
  });

  test('sheen material rebinds its combined DFG resource after parent bind',
      () {
    final source = File(
      'lib/src/internal/flutter_scene_extended_pbr_material.dart',
    ).readAsStringSync();
    final bindStart = source.indexOf('  void bind(');
    final bindEnd = source.indexOf('\n  void _bind', bindStart);

    expect(bindStart, greaterThanOrEqualTo(0));
    expect(bindEnd, greaterThan(bindStart));
    final bindBody = source.substring(bindStart, bindEnd);
    final parentBind = bindBody.indexOf('super.bind(');
    final sheenUniform = bindBody.indexOf(
      'flutterSceneSheenUniformBlockName',
    );
    final sheenColor = bindBody.indexOf("'sheen_color_texture'");
    final sheenRoughness = bindBody.indexOf("'sheen_roughness_texture'");
    final combinedDfg = bindBody.indexOf(
      'bindSheenBrdfLut!(pass, fragmentShader)',
    );

    expect(parentBind, greaterThanOrEqualTo(0));
    expect(sheenUniform, greaterThan(parentBind));
    expect(sheenColor, greaterThan(sheenUniform));
    expect(sheenRoughness, greaterThan(sheenColor));
    expect(
      combinedDfg,
      greaterThan(sheenRoughness),
      reason:
          'The package-owned combined LUT must win over the parent brdf_lut binding.',
    );
  });

  test('combined material bypasses parent normal slot and binds two coat maps',
      () {
    final source = File(
      'lib/src/internal/flutter_scene_extended_pbr_material.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'bool get bindsClearcoatTextureSlots =>\n'
        '      usesClearcoatShader && !usesSheenShader;',
      ),
    );
    final bindStart = source.indexOf('  void bind(');
    final bindEnd = source.indexOf('\n  void _bind', bindStart);
    final bindBody = source.substring(bindStart, bindEnd);
    final parentBind = bindBody.indexOf('super.bind(');
    final coatUniform = bindBody.indexOf(
      'flutterSceneClearcoatSheenUniformBlockName',
    );
    final coatFactor = bindBody.indexOf("'clearcoat_texture'");
    final coatRoughness = bindBody.indexOf("'clearcoat_roughness_texture'");
    final sheenUniform = bindBody.indexOf('flutterSceneSheenUniformBlockName');
    final combinedDfg = bindBody.indexOf(
      'bindSheenBrdfLut!(pass, fragmentShader)',
    );

    expect(parentBind, greaterThanOrEqualTo(0));
    expect(coatUniform, greaterThan(parentBind));
    expect(coatFactor, greaterThan(coatUniform));
    expect(coatRoughness, greaterThan(coatFactor));
    expect(sheenUniform, greaterThan(coatRoughness));
    expect(combinedDfg, greaterThan(sheenUniform));
    expect(bindBody, isNot(contains("'clearcoat_normal_texture'")));
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

({
  double lowerIndirect,
  double indirect,
  double lowerDirect,
  double direct,
  double emission,
}) _composeClearcoatAboveSheen({
  required double baseIndirect,
  required double sheenIndirect,
  required double sheenViewAttenuation,
  required double clearcoatIndirect,
  required double clearcoatViewFresnel,
  required double baseDirect,
  required double sheenDirect,
  required double sheenDirectAttenuation,
  required double clearcoatDirect,
  required double clearcoatHalfFresnel,
  required double emission,
}) {
  final lowerIndirect = baseIndirect * sheenViewAttenuation + sheenIndirect;
  final lowerDirect = baseDirect * sheenDirectAttenuation + sheenDirect;
  return (
    lowerIndirect: lowerIndirect,
    indirect: lowerIndirect * (1 - clearcoatViewFresnel) + clearcoatIndirect,
    lowerDirect: lowerDirect,
    direct: lowerDirect * (1 - clearcoatHalfFresnel) + clearcoatDirect,
    emission: emission * (1 - clearcoatViewFresnel),
  );
}

List<double> _candidateDirectSheen({
  required List<double> color,
  required double roughness,
  required double nDotV,
  required double nDotL,
  required double nDotH,
  double shadow = 1,
}) {
  final scalar = evaluateCharlieDistribution(
        nDotH: nDotH,
        roughness: roughness,
      ) *
      evaluateCharlieVisibility(
        nDotV: nDotV,
        nDotL: nDotL,
        roughness: roughness,
      ) *
      nDotL *
      shadow;
  return <double>[for (final channel in color) channel * scalar];
}

List<double> _candidateIblSheen({
  required List<double> color,
  required double roughness,
  required double nDotV,
  required List<double> radiance,
}) {
  final directionalAlbedo = integrateCharlieDirectionalAlbedo(
    nDotV: nDotV,
    roughness: roughness,
  );
  return <double>[
    for (var channel = 0; channel < color.length; channel += 1)
      color[channel] * directionalAlbedo * radiance[channel],
  ];
}
