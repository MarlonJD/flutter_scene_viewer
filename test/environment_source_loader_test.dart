import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/environment_source_loader.dart';
import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads raw HDR asset environments through the decoder', () async {
    final loader = EnvironmentSourceLoader(
      assetBundle: MemoryAssetBundle(<String, Uint8List>{
        'assets/env/tiny.hdr': _radianceHdr(),
      }),
    );

    final result = await loader.load(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.rawAsset,
        assetPath: 'assets/env/tiny.hdr',
        rawFormat: RenderEnvironmentFileFormat.hdr,
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(result.decoded!.width, 2);
    expect(result.decoded!.height, 1);
  });

  test('reports missing raw environment assets without decoded pixels',
      () async {
    final loader = EnvironmentSourceLoader(
      assetBundle: MemoryAssetBundle(const <String, Uint8List>{}),
    );

    final result = await loader.load(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.rawAsset,
        assetPath: 'assets/env/missing.hdr',
        rawFormat: RenderEnvironmentFileFormat.hdr,
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.assetLoadFailure);
    expect(result.decoded, isNull);
  });

  test('downloads explicit Poly Haven descriptors and caches decoded pixels',
      () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/files/venice_sunset') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'hdri': <String, Object?>{
              '1k': <String, Object?>{
                'hdr': <String, Object?>{
                  'url': 'https://dl.polyhaven.org/venice_sunset_1k.hdr',
                  'size': _radianceHdr().length,
                  'md5': 'fixture-md5',
                },
              },
            },
          }),
          200,
          request: request,
        );
      }
      return http.Response.bytes(_radianceHdr(), 200, request: request);
    });
    final loader = EnvironmentSourceLoader(httpClient: httpClient);
    const frame = RenderEnvironmentFrame(
      kind: RenderEnvironmentKind.polyHaven,
      polyHavenAssetId: 'venice_sunset',
      polyHavenResolution: '1k',
      polyHavenFileType: 'hdr',
      polyHavenUserAgent: 'flutter_scene_viewer_test/1.0',
    );

    final first = await loader.load(frame);
    final second = await loader.load(frame);

    expect(first.isSuccess, isTrue, reason: first.diagnostic?.toString());
    expect(second.isSuccess, isTrue, reason: second.diagnostic?.toString());
    expect(first.decoded!.linearPixels, second.decoded!.linearPixels);
    expect(
      requests.map((request) => request.url.toString()),
      <String>[
        'https://api.polyhaven.com/files/venice_sunset',
        'https://dl.polyhaven.org/venice_sunset_1k.hdr',
      ],
    );
    expect(
      requests.map((request) => request.headers['user-agent']),
      everyElement('flutter_scene_viewer_test/1.0'),
    );
  });

  test('rejects oversized Poly Haven files from descriptor metadata', () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, Object?>{
          'hdri': <String, Object?>{
            '1k': <String, Object?>{
              'hdr': <String, Object?>{
                'url': 'https://dl.polyhaven.org/too_big.hdr',
                'size': 1024,
              },
            },
          },
        }),
        200,
        request: request,
      );
    });
    final loader = EnvironmentSourceLoader(
      httpClient: httpClient,
      options: const EnvironmentSourceLoaderOptions(maxBytes: 16),
    );

    final result = await loader.load(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.polyHaven,
        polyHavenAssetId: 'venice_sunset',
        polyHavenResolution: '1k',
        polyHavenFileType: 'hdr',
        polyHavenUserAgent: 'flutter_scene_viewer_test/1.0',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.environmentTooLarge);
    expect(requests, hasLength(1));
  });

  test('reports Poly Haven request timeouts as environment diagnostics',
      () async {
    final httpClient = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 200, request: request);
    });
    final loader = EnvironmentSourceLoader(
      httpClient: httpClient,
      options: const EnvironmentSourceLoaderOptions(
        timeout: Duration(milliseconds: 1),
      ),
    );

    final result = await loader.load(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.polyHaven,
        polyHavenAssetId: 'venice_sunset',
        polyHavenResolution: '1k',
        polyHavenFileType: 'hdr',
        polyHavenUserAgent: 'flutter_scene_viewer_test/1.0',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(
        result.diagnostic?.code, ViewerDiagnosticCode.environmentLoadTimeout);
  });

  test('cancels Poly Haven file download after descriptor resolution',
      () async {
    var descriptorReturned = false;
    final httpClient = MockClient((request) async {
      if (request.url.path == '/files/venice_sunset') {
        descriptorReturned = true;
        return http.Response(
          jsonEncode(<String, Object?>{
            'hdri': <String, Object?>{
              '1k': <String, Object?>{
                'hdr': <String, Object?>{
                  'url': 'https://dl.polyhaven.org/venice_sunset_1k.hdr',
                  'size': _radianceHdr().length,
                },
              },
            },
          }),
          200,
          request: request,
        );
      }
      fail('File download should not start after cancellation.');
    });
    final loader = EnvironmentSourceLoader(httpClient: httpClient);

    final result = await loader.load(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.polyHaven,
        polyHavenAssetId: 'venice_sunset',
        polyHavenResolution: '1k',
        polyHavenFileType: 'hdr',
        polyHavenUserAgent: 'flutter_scene_viewer_test/1.0',
      ),
      isCanceled: () => descriptorReturned,
    );

    expect(result.isCanceled, isTrue);
    expect(result.diagnostic, isNull);
    expect(result.decoded, isNull);
  });
}

Uint8List _radianceHdr() {
  final bytes = BytesBuilder();
  bytes.add('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 1 +X 2\n'.codeUnits);
  bytes.add(const <int>[
    128,
    64,
    32,
    129,
    64,
    128,
    255,
    130,
  ]);
  return bytes.toBytes();
}

final class MemoryAssetBundle extends CachingAssetBundle {
  MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;

  @override
  Future<ByteData> load(String key) async {
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(bytes);
  }
}
