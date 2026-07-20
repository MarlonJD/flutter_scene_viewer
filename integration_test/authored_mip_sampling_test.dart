import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene_viewer/src/internal/flutter_scene_authored_mip_texture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const String _shaderName = 'FSViewerAuthoredMipProbe';
const String _pinnedFlutterSceneCommit =
    '5dcf6fce7dc36719e64e536faba9538fe9fa1022';
const List<String> _shaderBundleCandidates = <String>[
  'flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  'packages/flutter_scene_viewer/flutter_gpu_shaders/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  'build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
  'packages/flutter_scene_viewer/build/shaderbundles/fsviewer_extended_pbr.shaderbundle',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'samples authored mip levels 0 1 2 and rejects a base-only control',
    (tester) async {
      final shader = await _loadProbeShader();
      final uploader = FlutterSceneAuthoredMipTextureUploader();
      final authored = uploader.upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _solidLevel(0, 8, 8, 255, 0, 0),
          _solidLevel(1, 4, 4, 0, 255, 0),
          _solidLevel(2, 2, 2, 0, 0, 255),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: const FlutterSceneAuthoredMipSamplerIntent(
          magFilter: 9728,
          minFilter: 9984,
          wrapS: 33071,
          wrapT: 33071,
        ),
      );
      expect(authored.diagnostic, isNull);
      expect(authored.textureSource, isNotNull);

      final authoredImage = await _renderProbe(
        shader: shader,
        texture: authored.textureSource!,
      );
      final authoredSamples = await _readAndDisposeBandSamples(authoredImage);
      expect(_matchesAuthoredMipBands(authoredSamples), isTrue);

      final baseOnly = uploader.upload(
        levels: <FlutterSceneAuthoredMipLevel>[
          _solidLevel(0, 8, 8, 255, 0, 0),
        ],
        contentRole: FlutterSceneAuthoredMipContentRole.data,
        sampler: const FlutterSceneAuthoredMipSamplerIntent(
          magFilter: 9728,
          minFilter: 9728,
          wrapS: 33071,
          wrapT: 33071,
        ),
      );
      expect(baseOnly.diagnostic, isNull);
      expect(baseOnly.textureSource, isNotNull);

      final baseOnlyImage = await _renderProbe(
        shader: shader,
        texture: baseOnly.textureSource!,
      );
      final baseOnlySamples = await _readAndDisposeBandSamples(baseOnlyImage);
      expect(_matchesAuthoredMipBands(baseOnlySamples), isFalse);
      expect(baseOnlySamples.every((sample) => sample.isDominant(0)), isTrue);

      binding.reportData = <String, dynamic>{
        'schemaVersion': 1,
        'rendererCommit': _pinnedFlutterSceneCommit,
        'authoredSamples': <List<int>>[
          for (final sample in authoredSamples) sample.rgb,
        ],
        'baseOnlySamples': <List<int>>[
          for (final sample in baseOnlySamples) sample.rgb,
        ],
        'targetResult': 'passed',
        'evidenceLabel': 'verified locally',
      };

      debugPrint(
        'FSV_AUTHORED_MIP_PROBE '
        'flutter_scene=$_pinnedFlutterSceneCommit '
        'authored=$authoredSamples baseOnly=$baseOnlySamples',
      );
    },
  );
}

FlutterSceneAuthoredMipLevel _solidLevel(
  int level,
  int width,
  int height,
  int red,
  int green,
  int blue,
) {
  final bytes = Uint8List(width * height * 4);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    bytes[offset] = red;
    bytes[offset + 1] = green;
    bytes[offset + 2] = blue;
    bytes[offset + 3] = 255;
  }
  return FlutterSceneAuthoredMipLevel(
    level: level,
    width: width,
    height: height,
    rgbaBytes: bytes,
  );
}

Future<flutter_scene_gpu.Shader> _loadProbeShader() async {
  final failures = <String>[];
  for (final path in _shaderBundleCandidates) {
    try {
      final library = await flutter_scene_gpu.loadShaderLibraryAsync(path);
      final shader = library?[_shaderName];
      if (shader != null) {
        return shader;
      }
      failures.add('$path: missing $_shaderName');
    } on Object catch (error) {
      failures.add('$path: $error');
    }
  }
  throw StateError(
    'Could not load $_shaderName from the package shader bundle: '
    '${failures.join('; ')}',
  );
}

Future<ui.Image> _renderProbe({
  required flutter_scene_gpu.Shader shader,
  required flutter_scene.TextureSource texture,
}) async {
  await flutter_scene.Scene.initializeStaticResources().timeout(
    const Duration(seconds: 15),
  );
  final material = flutter_scene.ShaderMaterial(fragmentShader: shader)
    ..setTexture('authored_mip_texture', texture);
  final scene = flutter_scene.Scene()
    ..antiAliasingMode = flutter_scene.AntiAliasingMode.none
    ..toneMapping = flutter_scene.ToneMappingMode.linear;
  final node = flutter_scene.Node(
    name: 'authored-mip-probe',
    mesh: flutter_scene.Mesh(
      flutter_scene.PlaneGeometry(width: 5.5, depth: 1.85),
      material,
    ),
  )..localTransform = (vm.Matrix4.identity()..rotateX(math.pi / 2));
  scene.add(node);

  final camera = flutter_scene.PerspectiveCamera(
    position: vm.Vector3(0, 0, 2),
    target: vm.Vector3.zero(),
  );
  ui.Image? latest;
  try {
    for (var frame = 0; frame < 4; frame += 1) {
      latest?.dispose();
      latest = null;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      scene.render(
        camera,
        canvas,
        viewport: const ui.Rect.fromLTWH(0, 0, 300, 100),
        pixelRatio: 1,
      );
      final picture = recorder.endRecording();
      try {
        latest = await _pictureToImage(picture, width: 300, height: 100);
      } finally {
        picture.dispose();
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return latest!;
  } catch (_) {
    latest?.dispose();
    rethrow;
  }
}

Future<ui.Image> _pictureToImage(
  ui.Picture picture, {
  required int width,
  required int height,
}) async {
  final imageFuture = picture.toImage(width, height);
  try {
    return await imageFuture.timeout(const Duration(seconds: 15));
  } on TimeoutException {
    unawaited(
      imageFuture.then<void>(
        (image) => image.dispose(),
        onError: (Object _, StackTrace __) {},
      ),
    );
    rethrow;
  }
}

Future<List<_RgbSample>> _readAndDisposeBandSamples(ui.Image image) async {
  try {
    return await _readBandSamples(image);
  } finally {
    image.dispose();
  }
}

Future<List<_RgbSample>> _readBandSamples(ui.Image image) async {
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba).timeout(
            const Duration(seconds: 15),
          );
  if (data == null) {
    throw StateError('Could not read authored mip probe pixels.');
  }
  final bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  // PlaneGeometry's U axis projects right-to-left for this fixed camera, so
  // read the screen bands in reverse to report logical LOD 0, 1, 2 order.
  return <_RgbSample>[
    _sample(bytes, image.width, image.height, 5 / 6),
    _sample(bytes, image.width, image.height, 1 / 2),
    _sample(bytes, image.width, image.height, 1 / 6),
  ];
}

_RgbSample _sample(
  Uint8List bytes,
  int width,
  int height,
  double xRatio,
) {
  final x = (width * xRatio).floor().clamp(0, width - 1);
  final y = height ~/ 2;
  final offset = (y * width + x) * 4;
  return _RgbSample(bytes[offset], bytes[offset + 1], bytes[offset + 2]);
}

bool _matchesAuthoredMipBands(List<_RgbSample> samples) =>
    samples.length == 3 &&
    samples[0].isDominant(0) &&
    samples[1].isDominant(1) &&
    samples[2].isDominant(2);

final class _RgbSample {
  const _RgbSample(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;

  List<int> get rgb => <int>[red, green, blue];

  bool isDominant(int channel) {
    final values = <int>[red, green, blue];
    return values[channel] >= 200 &&
        values[(channel + 1) % 3] <= 40 &&
        values[(channel + 2) % 3] <= 40;
  }

  @override
  String toString() => '[$red,$green,$blue]';
}
