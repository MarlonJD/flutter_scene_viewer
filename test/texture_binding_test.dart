import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MaterialTextureBinding serializes stable JSON and round-trips', () {
    final binding = MaterialTextureBinding(
      source: const TextureSource.asset('assets/fabric.png'),
      texCoord: 0,
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.repeat,
        wrapT: TextureWrapMode.mirroredRepeat,
        magFilter: TextureMagFilter.linear,
        minFilter: TextureMinFilter.linearMipmapLinear,
      ),
      transform: TextureTransform(
        offset: <double>[0.1, 0.2],
        scale: <double>[2.5, 2.5],
        rotation: 0.5,
      ),
    );

    final json = binding.toJson();
    final roundTripped = MaterialTextureBinding.fromJson(json);

    expect(json, <String, Object?>{
      'source': <String, Object?>{
        'kind': 'asset',
        'assetPath': 'assets/fabric.png',
      },
      'texCoord': 0,
      'sampler': <String, Object?>{
        'wrapS': 'repeat',
        'wrapT': 'mirroredRepeat',
        'magFilter': 'linear',
        'minFilter': 'linearMipmapLinear',
      },
      'transform': <String, Object?>{
        'offset': <double>[0.1, 0.2],
        'scale': <double>[2.5, 2.5],
        'rotation': 0.5,
      },
    });
    expect(roundTripped.source, isA<AssetTextureSource>());
    expect(
      (roundTripped.source as AssetTextureSource).assetPath,
      'assets/fabric.png',
    );
    expect(roundTripped.texCoord, 0);
    expect(roundTripped.effectiveTexCoord, 0);
    expect(roundTripped.sampler.wrapS, TextureWrapMode.repeat);
    expect(roundTripped.sampler.wrapT, TextureWrapMode.mirroredRepeat);
    expect(roundTripped.sampler.magFilter, TextureMagFilter.linear);
    expect(
      roundTripped.sampler.minFilter,
      TextureMinFilter.linearMipmapLinear,
    );
    expect(roundTripped.transform.offset, <double>[0.1, 0.2]);
    expect(roundTripped.transform.scale, <double>[2.5, 2.5]);
    expect(roundTripped.transform.rotation, 0.5);
    expect(roundTripped.transform.texCoordOverride, isNull);
  });

  test('TextureSampler keeps unspecified filters nullable', () {
    const sampler = TextureSampler();

    expect(sampler.wrapS, TextureWrapMode.repeat);
    expect(sampler.wrapT, TextureWrapMode.repeat);
    expect(sampler.magFilter, isNull);
    expect(sampler.minFilter, isNull);
  });

  test('TextureTransform rejects non-finite values', () {
    expect(
      () => TextureTransform(offset: <double>[double.nan, 0]),
      throwsArgumentError,
    );
    expect(
      () => TextureTransform(scale: <double>[1, double.infinity]),
      throwsArgumentError,
    );
    expect(
      () => TextureTransform(rotation: double.negativeInfinity),
      throwsArgumentError,
    );
  });

  test('texture bindings reject negative UV sets', () {
    expect(
      () => MaterialTextureBinding(
        source: const TextureSource.asset('assets/fabric.png'),
        texCoord: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => TextureTransform(texCoordOverride: -1),
      throwsArgumentError,
    );
  });

  test('TextureTransform defensively copies caller lists', () {
    final offset = <double>[0.1, 0.2];
    final scale = <double>[2.5, -2.5];
    final transform = TextureTransform(offset: offset, scale: scale);

    offset[0] = 9;
    scale[1] = 9;

    expect(transform.offset, <double>[0.1, 0.2]);
    expect(transform.scale, <double>[2.5, -2.5]);
    expect(() => transform.offset[0] = 4, throwsUnsupportedError);
    expect(() => transform.scale[0] = 4, throwsUnsupportedError);
  });

  test('TextureTransform preserves finite negative scale and UV override', () {
    final transform = TextureTransform(
      scale: <double>[-2.5, 2.5],
      texCoordOverride: 1,
    );
    final binding = MaterialTextureBinding(
      source: const TextureSource.asset('assets/fabric.png'),
      transform: transform,
    );

    expect(transform.scale, <double>[-2.5, 2.5]);
    expect(binding.effectiveTexCoord, 1);
    expect(
      binding.toJson()['transform'],
      <String, Object?>{
        'offset': <double>[0, 0],
        'scale': <double>[-2.5, 2.5],
        'rotation': 0,
        'texCoordOverride': 1,
      },
    );
  });
}
