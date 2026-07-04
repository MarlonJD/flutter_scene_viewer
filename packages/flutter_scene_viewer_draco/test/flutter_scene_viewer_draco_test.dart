import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer_draco/flutter_scene_viewer_draco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodeGlb sends bytes and required extensions over the channel',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = FlutterSceneViewerDraco.channel;
    final sourceBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final decodedBytes = Uint8List.fromList(<int>[4, 5, 6]);
    final dracoPrimitives = <Object?>[
      <String, Object?>{
        'meshIndex': 0,
        'primitiveIndex': 0,
        'compressedBytes': Uint8List.fromList(<int>[7, 8, 9]),
      },
    ];
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['bytes'], sourceBytes);
      expect(arguments['requiredExtensions'], <String>[
        'KHR_draco_mesh_compression',
      ]);
      expect(arguments['source'], 'compressed.glb');
      expect(arguments['dracoPrimitives'], dracoPrimitives);
      return <String, Object?>{
        'bytes': decodedBytes,
        'diagnostics': <Object?>[],
      };
    });

    final result = await FlutterSceneViewerDraco.decodeGlb(
      bytes: sourceBytes,
      requiredExtensions: const <String>['KHR_draco_mesh_compression'],
      source: 'compressed.glb',
      dracoPrimitives: dracoPrimitives,
    );

    expect(result?['bytes'], decodedBytes);
  });
}
