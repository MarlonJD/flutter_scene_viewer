import 'dart:math' as math;

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_texture_binding_reader.dart';
import 'package:flutter_scene_viewer/src/texture_binding.dart';
import 'package:flutter_scene_viewer/src/texture_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = AssetTextureSource('assets/texture.png');

  test('uses core sampler defaults without inventing filter intent', () {
    final result = readGlbTextureBinding(
      textureInfo: <String, Object?>{'index': 0},
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'baseColorTexture',
      debugName: 'defaults.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.binding!.sampler.wrapS, TextureWrapMode.repeat);
    expect(result.binding!.sampler.wrapT, TextureWrapMode.repeat);
    expect(result.binding!.sampler.magFilter, isNull);
    expect(result.binding!.sampler.minFilter, isNull);
  });

  test('maps every core mag and min filter enum exactly', () {
    const magFilters = <int, TextureMagFilter>{
      9728: TextureMagFilter.nearest,
      9729: TextureMagFilter.linear,
    };
    const minFilters = <int, TextureMinFilter>{
      9728: TextureMinFilter.nearest,
      9729: TextureMinFilter.linear,
      9984: TextureMinFilter.nearestMipmapNearest,
      9985: TextureMinFilter.linearMipmapNearest,
      9986: TextureMinFilter.nearestMipmapLinear,
      9987: TextureMinFilter.linearMipmapLinear,
    };

    for (final mag in magFilters.entries) {
      for (final min in minFilters.entries) {
        final result = readGlbTextureBinding(
          textureInfo: <String, Object?>{'index': 0},
          textures: <Object?>[
            <String, Object?>{'source': 0, 'sampler': 0},
          ],
          samplers: <Object?>[
            <String, Object?>{
              'magFilter': mag.key,
              'minFilter': min.key,
            },
          ],
          source: source,
          availableTexCoords: const <int>{0},
          textureTransformRequired: false,
          slot: 'normalTexture',
          debugName: 'filters.glb',
        );

        expect(result.binding!.sampler.magFilter, mag.value);
        expect(result.binding!.sampler.minFilter, min.value);
      }
    }
  });

  test('preserves independent wrap axes', () {
    final result = readGlbTextureBinding(
      textureInfo: <String, Object?>{'index': 0},
      textures: <Object?>[
        <String, Object?>{'source': 0, 'sampler': 0},
      ],
      samplers: <Object?>[
        <String, Object?>{'wrapS': 33071, 'wrapT': 33648},
      ],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'occlusionTexture',
      debugName: 'wrap.glb',
    );

    expect(result.binding!.sampler.wrapS, TextureWrapMode.clampToEdge);
    expect(result.binding!.sampler.wrapT, TextureWrapMode.mirroredRepeat);
  });

  test('decodes transform defaults and normative T R S order', () {
    final result = readGlbTextureBinding(
      textureInfo: <String, Object?>{
        'index': 0,
        'extensions': <String, Object?>{
          'KHR_texture_transform': <String, Object?>{
            'offset': <Object?>[0.25, -0.5],
            'scale': <Object?>[2.0, 3.0],
            'rotation': math.pi / 2,
          },
        },
      },
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'baseColorTexture',
      debugName: 'transform.glb',
    );

    final transform = result.binding!.transform;
    final scaledU = transform.scaleX * 1;
    final scaledV = transform.scaleY * 2;
    final transformedU = transform.offsetX +
        math.cos(transform.rotation) * scaledU -
        math.sin(transform.rotation) * scaledV;
    final transformedV = transform.offsetY +
        math.sin(transform.rotation) * scaledU +
        math.cos(transform.rotation) * scaledV;
    expect(transformedU, closeTo(-5.75, 1e-12));
    expect(transformedV, closeTo(1.5, 1e-12));
    expect(transform.texCoordOverride, isNull);

    final defaults = readGlbTextureBinding(
      textureInfo: <String, Object?>{
        'index': 0,
        'extensions': <String, Object?>{
          'KHR_texture_transform': <String, Object?>{},
        },
      },
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'baseColorTexture',
      debugName: 'transform-defaults.glb',
    );
    expect(defaults.binding!.transform.offset, <double>[0, 0]);
    expect(defaults.binding!.transform.scale, <double>[1, 1]);
    expect(defaults.binding!.transform.rotation, 0);
  });

  test('processed extension overrides parent UV and accepts negative scale',
      () {
    final result = readGlbTextureBinding(
      textureInfo: <String, Object?>{
        'index': 0,
        'texCoord': 0,
        'extensions': <String, Object?>{
          'KHR_texture_transform': <String, Object?>{
            'texCoord': 1,
            'offset': <Object?>[0, 1],
            'scale': <Object?>[1, -1],
          },
        },
      },
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{1},
      textureTransformRequired: false,
      slot: 'normalTexture',
      debugName: 'uv-inversion.glb',
    );

    expect(result.binding!.texCoord, 0);
    expect(result.binding!.transform.texCoordOverride, 1);
    expect(result.binding!.effectiveTexCoord, 1);
    expect(result.binding!.transform.offset, <double>[0, 1]);
    expect(result.binding!.transform.scale, <double>[1, -1]);
  });

  test('UV0-only slots diagnose authored UV1 without changing shared behavior',
      () {
    final result = readGlbTextureBinding(
      textureInfo: <String, Object?>{'index': 0, 'texCoord': 1},
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0, 1},
      textureTransformRequired: false,
      requireUv0: true,
      slot: 'KHR_materials_sheen.sheenColorTexture',
      debugName: 'sheen-uv1.glb',
    );

    expect(result.binding, isNull);
    expect(result.hasBlockingDiagnostics, isFalse);
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostics.single.details['uvSet'], 1);
    expect(result.diagnostics.single.details['limitation'], 'authoredUv0Only');
  });

  test('optional malformed transform falls back but required form blocks', () {
    final textureInfo = <String, Object?>{
      'index': 0,
      'texCoord': 0,
      'extensions': <String, Object?>{
        'KHR_texture_transform': <String, Object?>{
          'scale': <Object?>[double.nan, 1],
          'texCoord': 1,
        },
      },
    };

    final optional = readGlbTextureBinding(
      textureInfo: textureInfo,
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'baseColorTexture',
      debugName: 'optional.glb',
    );
    expect(optional.binding, isNotNull);
    expect(optional.binding!.effectiveTexCoord, 0);
    expect(optional.binding!.transform, same(TextureTransform.identity));
    expect(optional.hasBlockingDiagnostics, isFalse);
    expect(optional.diagnostics, hasLength(1));

    final required = readGlbTextureBinding(
      textureInfo: textureInfo,
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0, 1},
      textureTransformRequired: true,
      slot: 'baseColorTexture',
      debugName: 'required.glb',
    );
    expect(required.binding, isNull);
    expect(required.hasBlockingDiagnostics, isTrue);

    for (final malformedTransform in <Map<String, Object?>>[
      <String, Object?>{
        'offset': <Object?>[double.infinity, 0],
      },
      <String, Object?>{'rotation': double.negativeInfinity},
    ]) {
      final nonFinite = readGlbTextureBinding(
        textureInfo: <String, Object?>{
          'index': 0,
          'extensions': <String, Object?>{
            'KHR_texture_transform': malformedTransform,
          },
        },
        textures: <Object?>[
          <String, Object?>{'source': 0}
        ],
        samplers: const <Object?>[],
        source: source,
        availableTexCoords: const <int>{0},
        textureTransformRequired: true,
        slot: 'baseColorTexture',
        debugName: 'non-finite.glb',
      );
      expect(nonFinite.binding, isNull);
      expect(nonFinite.hasBlockingDiagnostics, isTrue);
    }
  });

  test('missing effective UV is typed and malformed core indices block', () {
    final missingUv = readGlbTextureBinding(
      textureInfo: <String, Object?>{'index': 0, 'texCoord': 2},
      textures: <Object?>[
        <String, Object?>{'source': 0}
      ],
      samplers: const <Object?>[],
      source: source,
      availableTexCoords: const <int>{0, 1},
      textureTransformRequired: false,
      slot: 'emissiveTexture',
      debugName: 'missing-uv.glb',
    );
    expect(missingUv.binding, isNull);
    expect(
      missingUv.diagnostics.single.code,
      ViewerDiagnosticCode.missingUvSet,
    );
    expect(missingUv.diagnostics.single.details['uvSet'], 2);
    expect(missingUv.diagnostics.single.details['blocking'], isFalse);
    expect(missingUv.hasBlockingDiagnostics, isFalse);

    for (final input in <({
      Map<String, Object?> info,
      List<Object?> textures,
      List<Object?> samplers
    })>[
      (
        info: <String, Object?>{'index': 1},
        textures: <Object?>[
          <String, Object?>{'source': 0}
        ],
        samplers: const <Object?>[],
      ),
      (
        info: <String, Object?>{'index': 0},
        textures: <Object?>[
          <String, Object?>{'source': 0, 'sampler': 1},
        ],
        samplers: <Object?>[<String, Object?>{}],
      ),
    ]) {
      final result = readGlbTextureBinding(
        textureInfo: input.info,
        textures: input.textures,
        samplers: input.samplers,
        source: source,
        availableTexCoords: const <int>{0},
        textureTransformRequired: false,
        slot: 'baseColorTexture',
        debugName: 'malformed.glb',
      );
      expect(result.binding, isNull);
      expect(result.hasBlockingDiagnostics, isTrue);
      expect(
        result.diagnostics.single.code,
        ViewerDiagnosticCode.adapterFailure,
      );
    }
  });

  test('one image source may have distinct per-slot bindings', () {
    final first = readGlbTextureBinding(
      textureInfo: <String, Object?>{'index': 0},
      textures: <Object?>[
        <String, Object?>{'source': 0, 'sampler': 0},
      ],
      samplers: <Object?>[
        <String, Object?>{'wrapS': 33071},
      ],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'baseColorTexture',
      debugName: 'shared-image.glb',
    );
    final second = readGlbTextureBinding(
      textureInfo: <String, Object?>{
        'index': 1,
        'extensions': <String, Object?>{
          'KHR_texture_transform': <String, Object?>{
            'scale': <Object?>[2.5, 2.5],
          },
        },
      },
      textures: <Object?>[
        <String, Object?>{'source': 0, 'sampler': 0},
        <String, Object?>{'source': 0, 'sampler': 1},
      ],
      samplers: <Object?>[
        <String, Object?>{'wrapS': 33071},
        <String, Object?>{'wrapT': 33648},
      ],
      source: source,
      availableTexCoords: const <int>{0},
      textureTransformRequired: false,
      slot: 'normalTexture',
      debugName: 'shared-image.glb',
    );

    expect(first.binding!.source, same(second.binding!.source));
    expect(first.binding!.sampler.wrapS, TextureWrapMode.clampToEdge);
    expect(second.binding!.sampler.wrapT, TextureWrapMode.mirroredRepeat);
    expect(second.binding!.transform.scale, <double>[2.5, 2.5]);
  });
}
