import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;
import 'package:flutter_scene_viewer/src/internal/flutter_scene_authored_mip_texture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlutterSceneAuthoredMipTextureUploader', () {
    test('owns immutable ordered level bytes', () {
      final source = Uint8List.fromList(List<int>.filled(4 * 4 * 4, 7));
      final level = FlutterSceneAuthoredMipLevel(
        level: 0,
        width: 4,
        height: 4,
        rgbaBytes: source,
      );

      source[0] = 99;
      final exposed = level.rgbaBytes;
      exposed[1] = 88;

      expect(level.rgbaBytes[0], 7);
      expect(level.rgbaBytes[1], 7);
    });

    test('validates the complete chain before allocating', () {
      final cases = <String, List<FlutterSceneAuthoredMipLevel>>{
        'empty': <FlutterSceneAuthoredMipLevel>[],
        'first level is not zero': <FlutterSceneAuthoredMipLevel>[
          _level(1, 2, 2, 1),
        ],
        'duplicate level': <FlutterSceneAuthoredMipLevel>[
          _level(0, 4, 4, 1),
          _level(0, 2, 2, 2),
        ],
        'reordered level': <FlutterSceneAuthoredMipLevel>[
          _level(0, 4, 4, 1),
          _level(2, 1, 1, 2),
          _level(1, 2, 2, 3),
        ],
        'non-canonical dimensions': <FlutterSceneAuthoredMipLevel>[
          _level(0, 4, 4, 1),
          _level(1, 3, 2, 2),
        ],
        'wrong rgba byte length': <FlutterSceneAuthoredMipLevel>[
          FlutterSceneAuthoredMipLevel(
            level: 0,
            width: 2,
            height: 2,
            rgbaBytes: Uint8List(15),
          ),
        ],
      };

      for (final entry in cases.entries) {
        final interop = _RecordingInterop();
        final result =
            FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
          levels: entry.value,
          contentRole: FlutterSceneAuthoredMipContentRole.color,
          sampler: _mipSampler,
        );

        expect(result.textureSource, isNull, reason: entry.key);
        expect(result.diagnostic, isNotNull, reason: entry.key);
        expect(
          result.diagnostic!.details['limitation'],
          'invalidAuthoredMipChain',
          reason: entry.key,
        );
        expect(interop.allocations, isEmpty, reason: entry.key);
        expect(interop.uploads, isEmpty, reason: entry.key);
      }
    });

    test('rejects the renderer mip limit before allocation', () {
      final interop = _RecordingInterop(maxMipLevelCount: 2);
      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _level(0, 4, 4, 1),
          _level(1, 2, 2, 2),
          _level(2, 1, 1, 3),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: _mipSampler,
      );

      expect(result.textureSource, isNull);
      expect(result.diagnostic, isNotNull);
      expect(result.diagnostic!.details['limitation'], 'rendererMipCountLimit');
      expect(result.diagnostic!.details['requestedMipLevelCount'], 3);
      expect(result.diagnostic!.details['rendererMipLevelCount'], 2);
      expect(interop.allocations, isEmpty);
      expect(interop.uploads, isEmpty);
    });

    test('rejects no-mip minification for a multi-level WebGL2-safe source',
        () {
      final interop = _RecordingInterop();
      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _level(0, 2, 2, 1),
          _level(1, 1, 1, 2),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.normal,
        sampler: const FlutterSceneAuthoredMipSamplerIntent(
          magFilter: 9729,
          minFilter: 9729,
          wrapS: 10497,
          wrapT: 10497,
        ),
      );

      expect(result.textureSource, isNull);
      expect(result.diagnostic, isNotNull);
      expect(
          result.diagnostic!.details['limitation'], 'unsupportedSamplerIntent');
      expect(result.diagnostic!.details['minFilter'], 9729);
      expect(interop.allocations, isEmpty);
    });

    test('allocates exact count and uploads every immutable level by index',
        () {
      final interop = _RecordingInterop();
      final levels = <FlutterSceneAuthoredMipLevel>[
        _level(0, 4, 4, 11),
        _level(1, 2, 2, 22),
        _level(2, 1, 1, 33),
      ];

      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: levels,
        contentRole: FlutterSceneAuthoredMipContentRole.color,
        sampler: const FlutterSceneAuthoredMipSamplerIntent(
          magFilter: 9728,
          minFilter: 9987,
          wrapS: 33071,
          wrapT: 33648,
        ),
      );

      expect(result.diagnostic, isNull);
      expect(result.textureSource, isNotNull);
      expect(interop.allocations, <(int, int, int)>[(4, 4, 3)]);
      expect(
        interop.uploads.map((upload) => upload.$1),
        <int>[0, 1, 2],
      );
      expect(
        interop.uploads.map((upload) => upload.$2.lengthInBytes),
        <int>[64, 16, 4],
      );
      expect(interop.uploads[0].$2.buffer.asUint8List().toSet(), <int>{11});
      expect(interop.uploads[1].$2.buffer.asUint8List().toSet(), <int>{22});
      expect(interop.uploads[2].$2.buffer.asUint8List().toSet(), <int>{33});

      final sampler = result.textureSource!.sampledSampler;
      expect(sampler.minFilter, flutter_scene_gpu.MinMagFilter.linear);
      expect(sampler.magFilter, flutter_scene_gpu.MinMagFilter.nearest);
      expect(sampler.mipFilter, flutter_scene_gpu.MipFilter.linear);
      expect(
        sampler.widthAddressMode,
        flutter_scene_gpu.SamplerAddressMode.clampToEdge,
      );
      expect(
        sampler.heightAddressMode,
        flutter_scene_gpu.SamplerAddressMode.mirror,
      );
      expect(result.contentRole, FlutterSceneAuthoredMipContentRole.color);
    });

    test('uploads shared image once and retains each texture sampler', () {
      final interop = _RecordingInterop();
      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _level(0, 2, 2, 1),
          _level(1, 1, 1, 2),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: _mipSampler,
        additionalSamplers: const <FlutterSceneAuthoredMipSamplerIntent>[
          FlutterSceneAuthoredMipSamplerIntent(
            magFilter: 9728,
            minFilter: 9984,
            wrapS: 33071,
            wrapT: 33648,
          ),
        ],
      );

      expect(result.diagnostic, isNull);
      expect(interop.allocations, hasLength(1));
      expect(interop.uploads, hasLength(2));
      expect(result.textureSources, hasLength(2));
      expect(
        result.textureSources[0].sampledSampler.widthAddressMode,
        flutter_scene_gpu.SamplerAddressMode.repeat,
      );
      expect(
        result.textureSources[1].sampledSampler.widthAddressMode,
        flutter_scene_gpu.SamplerAddressMode.clampToEdge,
      );
      expect(
        result.textureSources[1].sampledSampler.heightAddressMode,
        flutter_scene_gpu.SamplerAddressMode.mirror,
      );
    });

    test('validates every shared-image sampler before allocation', () {
      final interop = _RecordingInterop();
      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _level(0, 2, 2, 1),
          _level(1, 1, 1, 2),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: _mipSampler,
        additionalSamplers: const <FlutterSceneAuthoredMipSamplerIntent>[
          FlutterSceneAuthoredMipSamplerIntent(
            magFilter: 9729,
            minFilter: 9729,
            wrapS: 10497,
            wrapT: 10497,
          ),
        ],
      );

      expect(result.textureSources, isEmpty);
      expect(result.diagnostic, isNotNull);
      expect(
        result.diagnostic!.details['limitation'],
        'unsupportedSamplerIntent',
      );
      expect(result.diagnostic!.details['samplerIndex'], 1);
      expect(interop.allocations, isEmpty);
    });

    test('reports allocation failure without publishing a texture source', () {
      final interop = _RecordingInterop(allocationError: StateError('limit'));
      final result =
          FlutterSceneAuthoredMipTextureUploader(interop: interop).upload(
        levels: <FlutterSceneAuthoredMipLevel>[_level(0, 1, 1, 1)],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: _singleLevelSampler,
      );

      expect(result.textureSource, isNull);
      expect(result.diagnostic, isNotNull);
      expect(result.diagnostic!.details['limitation'],
          'rendererTextureAllocation');
      expect(result.diagnostic!.details['deterministicDispose'], 'unavailable');
      expect(interop.uploads, isEmpty);
    });
  });
}

const FlutterSceneAuthoredMipSamplerIntent _mipSampler =
    FlutterSceneAuthoredMipSamplerIntent(
  magFilter: 9729,
  minFilter: 9987,
  wrapS: 10497,
  wrapT: 10497,
);

const FlutterSceneAuthoredMipSamplerIntent _singleLevelSampler =
    FlutterSceneAuthoredMipSamplerIntent(
  magFilter: 9729,
  minFilter: 9729,
  wrapS: 10497,
  wrapT: 10497,
);

FlutterSceneAuthoredMipLevel _level(
  int level,
  int width,
  int height,
  int fill,
) =>
    FlutterSceneAuthoredMipLevel(
      level: level,
      width: width,
      height: height,
      rgbaBytes: Uint8List.fromList(
        List<int>.filled(width * height * 4, fill),
      ),
    );

final class _RecordingInterop implements FlutterSceneAuthoredMipTextureInterop {
  _RecordingInterop({
    this.maxMipLevelCount = 32,
    this.allocationError,
  });

  final int maxMipLevelCount;
  final Object? allocationError;
  final List<(int, int, int)> allocations = <(int, int, int)>[];
  final List<(int, ByteData)> uploads = <(int, ByteData)>[];

  @override
  int rendererMipLevelLimit({required int width, required int height}) =>
      maxMipLevelCount;

  @override
  Object allocateRgba8Texture({
    required int width,
    required int height,
    required int mipLevelCount,
  }) {
    final error = allocationError;
    if (error != null) {
      throw error;
    }
    allocations.add((width, height, mipLevelCount));
    return Object();
  }

  @override
  void overwriteRgba8(
    Object texture,
    ByteData rgbaBytes, {
    required int mipLevel,
  }) {
    uploads.add((mipLevel, ByteData.sublistView(rgbaBytes)));
  }

  @override
  flutter_scene.TextureSource wrapTexture(
    Object texture, {
    required flutter_scene_gpu.SamplerOptions sampler,
  }) =>
      _FakeTextureSource(sampler);
}

final class _FakeTextureSource implements flutter_scene.TextureSource {
  const _FakeTextureSource(this.sampledSampler);

  @override
  final flutter_scene_gpu.SamplerOptions sampledSampler;

  @override
  flutter_scene_gpu.Texture? get sampledTexture => null;
}
