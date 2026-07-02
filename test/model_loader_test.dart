import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/model_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads bytes sources through the adapter', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'inline.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes.single, bytes);
    expect(adapter.debugNames.single, 'inline.glb');
  });

  test('loads asset sources through the configured asset bundle', () async {
    final adapter = FakeFlutterSceneAdapter();
    final assetBundle = MemoryAssetBundle(<String, Uint8List>{
      'assets/chair.glb': Uint8List.fromList(<int>[4, 5, 6]),
    });
    final loader = ModelLoader(
      adapter: adapter,
      assetBundle: assetBundle,
    );

    final result = await loader.load(
      const ModelSource.asset('assets/chair.glb'),
    );

    expect(result.isSuccess, isTrue);
    expect(assetBundle.loadedKeys, <String>['assets/chair.glb']);
    expect(adapter.loadedBytes.single, <int>[4, 5, 6]);
    expect(adapter.debugNames.single, 'assets/chair.glb');
  });

  test('loads network sources with optional headers', () async {
    final adapter = FakeFlutterSceneAdapter();
    http.Request? capturedRequest;
    final httpClient = MockClient((request) async {
      capturedRequest = request;
      return http.Response.bytes(<int>[7, 8, 9], 200, request: request);
    });
    final loader = ModelLoader(
      adapter: adapter,
      httpClient: httpClient,
    );

    final result = await loader.load(
      ModelSource.network(
        Uri.parse('https://models.example/chair.glb'),
        headers: const <String, String>{'Authorization': 'Bearer token'},
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.headers['Authorization'], 'Bearer token');
    expect(adapter.loadedBytes.single, <int>[7, 8, 9]);
    expect(adapter.debugNames.single, 'https://models.example/chair.glb');
  });

  test('rejects invalid network URLs before dispatching to the adapter',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);

    final result = await loader.load(
      ModelSource.network(Uri.parse('models/chair.glb')),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.invalidModelUrl);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('reports network timeout using configured timeout', () async {
    final adapter = FakeFlutterSceneAdapter();
    final httpClient = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response.bytes(<int>[1], 200, request: request);
    });
    final loader = ModelLoader(
      adapter: adapter,
      httpClient: httpClient,
      options: const ModelLoaderOptions(
        timeout: Duration(milliseconds: 1),
      ),
    );

    final result = await loader.load(
      ModelSource.network(Uri.parse('https://models.example/slow.glb')),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('rejects models over the configured size limit', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(maxBytes: 2),
    );

    final result = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3])),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelTooLarge);
    expect(result.diagnostic?.details['byteLength'], 3);
    expect(result.diagnostic?.details['maxBytes'], 2);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('reports flutter_scene import failures through adapter diagnostics',
      () async {
    final loader = ModelLoader(adapter: FlutterSceneRuntimeAdapter());

    final result = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3])),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.adapterFailure);
  });

  test('imports a valid GLB fixture through the flutter_scene adapter',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final adapter = FlutterSceneRuntimeAdapter();
    final loader = ModelLoader(adapter: adapter);
    final bytes = await File('test/fixtures/Box.glb').readAsBytes();

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'Box.glb'),
    );

    expect(result.diagnostic, isNull);
    expect(result.isSuccess, isTrue);
    expect(adapter.rootNode, isNotNull);
  }, skip: _runFlutterSceneGpuTests ? false : _flutterSceneGpuSkipReason);
}

const bool _runFlutterSceneGpuTests = bool.fromEnvironment(
  'FLUTTER_SCENE_GPU_TESTS',
);

const String _flutterSceneGpuSkipReason =
    'Requires --enable-impeller --enable-flutter-gpu and '
    '--dart-define=FLUTTER_SCENE_GPU_TESTS=true.';

final class FakeFlutterSceneAdapter implements FlutterSceneAdapter {
  final List<Uint8List> loadedBytes = <Uint8List>[];
  final List<String?> debugNames = <String?>[];

  @override
  AdapterNodeSnapshot? get nodeSnapshot => null;

  @override
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName}) async {
    loadedBytes.add(bytes);
    debugNames.add(debugName);
  }

  @override
  Future<List<ViewerDiagnostic>> applyMaterialPatch(address, patch) async =>
      const <ViewerDiagnostic>[];

  @override
  List<ViewerDiagnostic> collectDiagnostics() => const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> resetMaterial(address) async =>
      const <ViewerDiagnostic>[];
}

final class MemoryAssetBundle extends CachingAssetBundle {
  MemoryAssetBundle(this.assets);

  final Map<String, Uint8List> assets;
  final List<String> loadedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loadedKeys.add(key);
    final bytes = assets[key];
    if (bytes == null) {
      throw StateError('Missing test asset: $key');
    }
    return ByteData.sublistView(bytes);
  }
}
