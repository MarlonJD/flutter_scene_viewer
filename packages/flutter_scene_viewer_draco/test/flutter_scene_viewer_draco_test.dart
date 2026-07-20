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
    final decodeBudget = <String, Object?>{
      'maxTotalDecodedBytes': 100,
      'maxAccessors': 10,
      'maxVertices': 20,
      'maxIndices': 30,
      'maxNativeOutputBytes': 100,
    };
    final decodeBudgetState = <String, Object?>{
      'totalDecodedBytes': 4,
      'nativeOutputBytes': 3,
      'accessors': 2,
      'vertices': 1,
      'indices': 0,
    };
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['requestId'], 'draco-test-1');
      expect(arguments['bytes'], sourceBytes);
      expect(arguments['requiredExtensions'], <String>[
        'KHR_draco_mesh_compression',
      ]);
      expect(arguments['source'], 'compressed.glb');
      expect(arguments['dracoPrimitives'], dracoPrimitives);
      expect(arguments['decodeBudget'], decodeBudget);
      expect(arguments['decodeBudgetState'], decodeBudgetState);
      return <String, Object?>{
        'bytes': decodedBytes,
        'diagnostics': <Object?>[],
      };
    });

    final result = await FlutterSceneViewerDraco.decodeGlb(
      requestId: 'draco-test-1',
      bytes: sourceBytes,
      requiredExtensions: const <String>['KHR_draco_mesh_compression'],
      source: 'compressed.glb',
      dracoPrimitives: dracoPrimitives,
      decodeBudget: decodeBudget,
      decodeBudgetState: decodeBudgetState,
    );

    expect(result?['bytes'], decodedBytes);
  });

  test('cancelDecode sends the active request id', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = FlutterSceneViewerDraco.channel;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'cancelDecode');
      expect(call.arguments, <String, Object?>{'requestId': 'draco-test-2'});
      return <String, Object?>{'status': 'cancelled'};
    });

    final result = await FlutterSceneViewerDraco.cancelDecode(
      requestId: 'draco-test-2',
    );

    expect(result, <String, Object?>{'status': 'cancelled'});
  });
}
