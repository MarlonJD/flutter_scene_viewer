import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_scene_viewer/src/material_shading_mode.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/model_source.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
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

  test('records load evidence without inventing unavailable counters',
      () async {
    final adapter = FakeFlutterSceneAdapter(
      snapshot: AdapterNodeSnapshot(
        name: 'Root',
        children: <AdapterNodeSnapshot>[
          AdapterNodeSnapshot(name: 'Assembly'),
          AdapterNodeSnapshot(name: 'Part', primitiveCount: 2),
        ],
      ),
    );
    final loader = ModelLoader(adapter: adapter);
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'inline.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(result.modelByteSize, 4);
    expect(result.modelLoadDuration, isNotNull);
    expect(result.nodeCount, 3);
    expect(result.meshCount, 1);
    expect(result.primitiveCount, 2);
    expect(result.materialCount, isNull);
  });

  test('prefers adapter-provided model counters when known', () async {
    final adapter = FakeFlutterSceneAdapter(
      modelStats: const AdapterModelStats(
        nodeCount: 7,
        meshCount: 3,
        materialCount: 4,
        primitiveCount: 5,
      ),
    );
    final loader = ModelLoader(adapter: adapter);

    final result = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3])),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(result.nodeCount, 7);
    expect(result.meshCount, 3);
    expect(result.materialCount, 4);
    expect(result.primitiveCount, 5);
  });

  test('passes material shading policy to the adapter', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);

    final result = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3])),
      materialShadingPolicy: MaterialShadingPolicy.forceLit,
    );

    expect(result.isSuccess, isTrue);
    expect(
      adapter.materialShadingPolicies.single,
      MaterialShadingPolicy.forceLit,
    );
  });

  test('merges authored material extension reader diagnostics', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);

    final result = await loader.load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'GlassPanel', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{'TEXCOORD_0': 0},
                  'material': 0,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_materials_transmission': <String, Object?>{
                  'transmissionFactor': 'opaque',
                },
              },
            },
          ],
        }),
        debugName: 'bad-extension.glb',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.invalidMaterialOverride,
    );
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
    expect(adapter.modelBounds, isNotNull);
    expect(adapter.modelBounds!.radius, greaterThan(0));
  }, skip: _runFlutterSceneGpuTests ? false : _flutterSceneGpuSkipReason);

  test('imports a representative multi-material GLB fixture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final adapter = FlutterSceneRuntimeAdapter();
    final loader = ModelLoader(adapter: adapter);
    final bytes = await File(
      'test/fixtures/MultiMaterialAssembly.glb',
    ).readAsBytes();

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'MultiMaterialAssembly.glb'),
    );

    expect(result.diagnostic, isNull);
    expect(result.isSuccess, isTrue);
    expect(result.diagnostics, isEmpty);
    final root = result.partTree.root!;
    expect(root.name, 'root');
    final assembly = root.children.single;
    expect(assembly.name, 'SampleAssembly');
    expect(
      assembly.children.map((node) => node.name),
      <String>['BlueBody', 'GoldPanel', 'RedAccent'],
    );
    expect(result.partTree.records, hasLength(3));
    expect(
        result.partTree.records.every((record) => record.hasTexCoords), isTrue);
    expect(adapter.modelBounds, isNotNull);
    expect(adapter.modelBounds!.radius, greaterThan(1));
  }, skip: _runFlutterSceneGpuTests ? false : _flutterSceneGpuSkipReason);

  test('runtime adapter applies asset environment and skybox', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final adapter = FlutterSceneRuntimeAdapter();
    final loader = ModelLoader(adapter: adapter);
    final bytes = await File('test/fixtures/Box.glb').readAsBytes();
    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'Box.glb'),
    );
    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());

    final diagnostics = await adapter.configureEnvironment(
      const RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.asset,
        assetPath: 'packages/flutter_scene/assets/royal_esplanade.png',
        intensity: 0.6,
        rotationRadians: math.pi / 4,
        showSkybox: true,
        skyboxBlur: 0.35,
      ),
    );

    expect(diagnostics, isEmpty);
    final scene = adapter.debugScene!;
    expect(
      flutter_scene.environmentAssetPathOf(scene.environment!),
      'packages/flutter_scene/assets/royal_esplanade.png',
    );
    expect(scene.environmentIntensity, 0.6);
    expect(scene.skybox, isNotNull);
    expect(scene.skybox!.source, isA<flutter_scene.EnvironmentSkySource>());
    final source = scene.skybox!.source as flutter_scene.EnvironmentSkySource;
    expect(source.blurriness, 0.35);
    expect(scene.environmentTransform.storage[0], closeTo(math.sqrt1_2, 1e-7));
  }, skip: _runFlutterSceneGpuTests ? false : _flutterSceneGpuSkipReason);
}

const bool _runFlutterSceneGpuTests = bool.fromEnvironment(
  'FLUTTER_SCENE_GPU_TESTS',
);

const String _flutterSceneGpuSkipReason =
    'Requires --enable-impeller --enable-flutter-gpu and '
    '--dart-define=FLUTTER_SCENE_GPU_TESTS=true.';

final class FakeFlutterSceneAdapter implements FlutterSceneAdapter {
  FakeFlutterSceneAdapter({
    this.snapshot,
    this.modelStats,
  });

  final List<Uint8List> loadedBytes = <Uint8List>[];
  final List<String?> debugNames = <String?>[];
  final List<MaterialShadingPolicy> materialShadingPolicies =
      <MaterialShadingPolicy>[];
  final AdapterNodeSnapshot? snapshot;
  @override
  final AdapterModelStats? modelStats;

  @override
  AdapterNodeSnapshot? get nodeSnapshot => snapshot;

  @override
  AdapterRenderScene? get renderScene => null;

  @override
  AdapterModelBounds? get modelBounds => null;

  @override
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
  }) async {
    loadedBytes.add(bytes);
    debugNames.add(debugName);
    materialShadingPolicies.add(materialShadingPolicy);
  }

  @override
  Future<List<ViewerDiagnostic>> configureEnvironment(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    return const <ViewerDiagnostic>[];
  }

  @override
  Future<List<ViewerDiagnostic>> applyMaterialPatch(address, patch) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<PartAddress?> pickPart({
    required Offset localPosition,
    required Size viewportSize,
    required RenderCameraFrame camera,
  }) async {
    return null;
  }

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

Uint8List _glb(Map<String, Object?> json) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final totalLength = 12 + 8 + paddedJsonLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length; index < bytes.length; index += 1) {
    bytes[index] = 0x20;
  }
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;
