import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer_basisu/flutter_scene_viewer_basisu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeGlb sends BasisU image payloads over the channel', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = FlutterSceneViewerBasisu.channel;
    final sourceBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final decodedBytes = Uint8List.fromList(<int>[4, 5, 6]);
    final basisuImages = <Object?>[
      <String, Object?>{
        'textureIndex': 0,
        'imageIndex': 0,
        'mimeType': 'image/ktx2',
        'bytes': Uint8List.fromList(<int>[7, 8, 9]),
      },
    ];
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['bytes'], sourceBytes);
      expect(arguments['requiredExtensions'], <String>['KHR_texture_basisu']);
      expect(arguments['source'], 'basisu.glb');
      expect(arguments['basisuImages'], basisuImages);
      return <String, Object?>{
        'bytes': decodedBytes,
        'diagnostics': <Object?>[],
      };
    });

    final result = await FlutterSceneViewerBasisu.decodeGlb(
      bytes: sourceBytes,
      requiredExtensions: const <String>['KHR_texture_basisu'],
      source: 'basisu.glb',
      basisuImages: basisuImages,
    );

    expect(result?['bytes'], decodedBytes);
  });
}
