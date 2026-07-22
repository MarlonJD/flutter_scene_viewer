import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/gltf.dart' as flutter_scene_gltf;
import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter_cancellation.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_authored_mip_texture.dart';
import 'package:flutter_scene_viewer/src/internal/glb_basisu_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
import 'package:flutter_scene_viewer/src/internal/glb_draco_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_native_decoder_probe.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_patch_group.dart';
import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_scene_viewer/src/material_extension_policy.dart';
import 'package:flutter_scene_viewer/src/material_patch.dart';
import 'package:flutter_scene_viewer/src/material_shading_mode.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/model_source.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_scene_viewer/src/texture_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vector_math/vector_math.dart' as vm;

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

  test('a cancelled older adapter publication cannot overwrite a fresh load',
      () async {
    final oldGate = Completer<void>();
    final freshGate = Completer<void>();
    final adapter = FakeFlutterSceneAdapter(
      loadGates: <String, Completer<void>>{
        'old.glb': oldGate,
        'fresh.glb': freshGate,
      },
    );
    final loader = ModelLoader(adapter: adapter);
    final cancelled = ModelLoadCancellationController();
    final fresh = ModelLoadCancellationController();

    final oldLoad = loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'old.glb'),
      cancellationToken: cancelled.token,
    );
    await adapter.waitForLoad('old.glb');
    cancelled.cancel('superseded');

    final freshLoad = loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'fresh.glb'),
      cancellationToken: fresh.token,
    );
    await adapter.waitForLoad('fresh.glb');
    freshGate.complete();
    final freshResult = await freshLoad;

    oldGate.complete();
    final oldResult = await oldLoad;

    expect(freshResult.isSuccess, isTrue);
    expect(oldResult.isSuccess, isFalse);
    expect(oldResult.diagnostic!.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(adapter.debugNames, <String?>['fresh.glb']);
    expect(adapter.receivedPublicationCallbacks['old.glb'], isNotNull);
    expect(adapter.receivedPublicationCallbacks['fresh.glb'], isNotNull);
  });

  test('controller supersession leaves a live cancellation token unaccepted',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final cancellation = ModelLoadCancellationController();

    final result = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'stale.glb'),
      cancellationToken: cancellation.token,
      tryAcceptPublication: () => false,
    );

    expect(result.isSuccess, isFalse);
    expect(result.superseded, isTrue);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.adapterFailure);
    expect(cancellation.cancel('still-live'), isTrue);
  });

  test('adapter publication is closed after timeout before a fresh load',
      () async {
    final timedOutGate = Completer<void>();
    final adapter = FakeFlutterSceneAdapter(
      loadGates: <String, Completer<void>>{'timed-out.glb': timedOutGate},
    );
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(timeout: Duration(milliseconds: 1)),
    );

    final timedOutLoad = loader.load(
      ModelSource.bytes(
        Uint8List.fromList(<int>[1]),
        debugName: 'timed-out.glb',
      ),
    );
    await adapter.waitForLoad('timed-out.glb');
    final timedOutResult = await timedOutLoad;
    expect(
        timedOutResult.diagnostic!.code, ViewerDiagnosticCode.modelLoadTimeout);

    timedOutGate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.debugNames, isEmpty);

    final freshResult = await loader.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'fresh.glb'),
    );
    expect(freshResult.isSuccess, isTrue);
    expect(adapter.debugNames, <String?>['fresh.glb']);
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

  test('delivers imported core and extension patches independently', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final imageBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    final result = await loader.load(
      ModelSource.bytes(
        _glbWithBin(
          <String, Object?>{
            'asset': <String, Object?>{'version': '2.0'},
            'scene': 0,
            'scenes': <Object?>[
              <String, Object?>{
                'nodes': <Object?>[0],
              },
            ],
            'nodes': <Object?>[
              <String, Object?>{'name': 'TextilePanel', 'mesh': 0},
            ],
            'meshes': <Object?>[
              <String, Object?>{
                'primitives': <Object?>[
                  <String, Object?>{
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'TEXCOORD_0': 1,
                    },
                    'material': 0,
                  },
                ],
              },
            ],
            'materials': <Object?>[
              <String, Object?>{
                'pbrMetallicRoughness': <String, Object?>{
                  'baseColorTexture': <String, Object?>{'index': 0},
                },
                'extensions': <String, Object?>{
                  'KHR_materials_ior': <String, Object?>{'ior': 1.45},
                  'KHR_materials_specular': <String, Object?>{
                    'specularFactor': 0.6,
                  },
                },
              },
            ],
            'textures': <Object?>[
              <String, Object?>{'source': 0},
            ],
            'images': <Object?>[
              <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
            ],
            'bufferViews': <Object?>[
              <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': imageBytes.length,
              },
            ],
            'buffers': <Object?>[
              <String, Object?>{'byteLength': imageBytes.length},
            ],
          },
          imageBytes,
        ),
        debugName: 'texture-patch.glb',
      ),
    );

    expect(result.isSuccess, isTrue);
    final address = PartAddress(
      nodePath: const <String>['TextilePanel'],
      primitiveIndex: 0,
    );
    final patch = result.authoredCoreMaterialPatches[address]!;
    expect(
      (patch.baseColorTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      imageBytes,
    );
    final extensionPatches = result.authoredExtensionMaterialPatches[address]!;
    expect(
      extensionPatches[MaterialExtensionPatchGroup.opaqueIor]!.ior,
      1.45,
    );
    expect(
      extensionPatches[MaterialExtensionPatchGroup.specular]!.specular,
      0.6,
    );
  });

  test('required malformed texture transform fails before adapter import',
      () async {
    final imageBytes = Uint8List.fromList(<int>[7, 8, 9]);

    Uint8List fixture({required bool required}) => _glbWithBin(
          <String, Object?>{
            'asset': <String, Object?>{'version': '2.0'},
            'extensionsUsed': <Object?>['KHR_texture_transform'],
            if (required)
              'extensionsRequired': <Object?>['KHR_texture_transform'],
            'scene': 0,
            'scenes': <Object?>[
              <String, Object?>{
                'nodes': <Object?>[0],
              },
            ],
            'nodes': <Object?>[
              <String, Object?>{'name': 'TransformPanel', 'mesh': 0},
            ],
            'meshes': <Object?>[
              <String, Object?>{
                'primitives': <Object?>[
                  <String, Object?>{
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'TEXCOORD_0': 1,
                    },
                    'material': 0,
                  },
                ],
              },
            ],
            'materials': <Object?>[
              <String, Object?>{
                'pbrMetallicRoughness': <String, Object?>{
                  'baseColorTexture': <String, Object?>{
                    'index': 0,
                    'extensions': <String, Object?>{
                      'KHR_texture_transform': <String, Object?>{
                        'scale': <Object?>['invalid', 1],
                      },
                    },
                  },
                },
              },
            ],
            'textures': <Object?>[
              <String, Object?>{'source': 0},
            ],
            'images': <Object?>[
              <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
            ],
            'bufferViews': <Object?>[
              <String, Object?>{
                'buffer': 0,
                'byteLength': imageBytes.length,
              },
            ],
            'buffers': <Object?>[
              <String, Object?>{'byteLength': imageBytes.length},
            ],
          },
          imageBytes,
        );

    final optionalAdapter = FakeFlutterSceneAdapter();
    final optional = await ModelLoader(adapter: optionalAdapter).load(
      ModelSource.bytes(
        fixture(required: false),
        debugName: 'optional-transform.glb',
      ),
    );
    expect(optional.isSuccess, isTrue);
    expect(optionalAdapter.loadedBytes, hasLength(1));
    expect(
      optional.diagnostics
          .where((diagnostic) => diagnostic.details['blocking'] == false),
      hasLength(1),
    );

    final requiredAdapter = FakeFlutterSceneAdapter();
    final required = await ModelLoader(adapter: requiredAdapter).load(
      ModelSource.bytes(
        fixture(required: true),
        debugName: 'required-transform.glb',
      ),
    );
    expect(required.isSuccess, isFalse);
    expect(requiredAdapter.loadedBytes, isEmpty);
    expect(required.diagnostic!.details['blocking'], isTrue);
    expect(required.diagnostic!.details['required'], isTrue);
  });

  test('malformed texture transform on optional sheen remains blocking',
      () async {
    final imageBytes = Uint8List.fromList(<int>[7, 8, 9]);
    Uint8List fixture({required bool required}) => _glbWithBin(
          <String, Object?>{
            'asset': <String, Object?>{'version': '2.0'},
            'extensionsUsed': <Object?>[
              'KHR_materials_sheen',
              'KHR_texture_transform',
            ],
            if (required)
              'extensionsRequired': <Object?>['KHR_texture_transform'],
            'scene': 0,
            'scenes': <Object?>[
              <String, Object?>{
                'nodes': <Object?>[0],
              },
            ],
            'nodes': <Object?>[
              <String, Object?>{'name': 'TransformFabric', 'mesh': 0},
            ],
            'meshes': <Object?>[
              <String, Object?>{
                'primitives': <Object?>[
                  <String, Object?>{
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'TEXCOORD_0': 1,
                    },
                    'material': 0,
                  },
                ],
              },
            ],
            'materials': <Object?>[
              <String, Object?>{
                'extensions': <String, Object?>{
                  'KHR_materials_sheen': <String, Object?>{
                    'sheenColorTexture': <String, Object?>{
                      'index': 0,
                      'extensions': <String, Object?>{
                        'KHR_texture_transform': <String, Object?>{
                          'scale': <Object?>['invalid', 1],
                        },
                      },
                    },
                  },
                },
              },
            ],
            'textures': <Object?>[
              <String, Object?>{'source': 0},
            ],
            'images': <Object?>[
              <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
            ],
            'bufferViews': <Object?>[
              <String, Object?>{
                'buffer': 0,
                'byteLength': imageBytes.length,
              },
            ],
            'buffers': <Object?>[
              <String, Object?>{'byteLength': imageBytes.length},
            ],
          },
          imageBytes,
        );

    for (final required in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter();
      final result = await ModelLoader(adapter: adapter).load(
        ModelSource.bytes(
          fixture(required: required),
          debugName: 'malformed-transform-optional-sheen.glb',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.loadedBytes, isEmpty);
      expect(result.diagnostic!.details['extension'], 'KHR_texture_transform');
      expect(result.diagnostic!.details['required'], required);
      expect(result.diagnostic!.details['blocking'], isTrue);
      expect(result.diagnostic!.details['status'], 'malformedAsset');
      expect(result.diagnostic!.details['fallback'], 'none');
    }
  });

  test('required malformed clearcoat fails while optional intent falls back',
      () async {
    Uint8List fixture({required bool required}) => _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_materials_clearcoat'],
          if (required)
            'extensionsRequired': <Object?>['KHR_materials_clearcoat'],
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'CoatedPanel', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{'POSITION': 0},
                  'material': 0,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'pbrMetallicRoughness': <String, Object?>{
                'baseColorFactor': <Object?>[0.2, 0.3, 0.4, 1.0],
              },
              'extensions': <String, Object?>{
                'KHR_materials_clearcoat': <String, Object?>{
                  'clearcoatFactor': 1.2,
                },
              },
            },
          ],
        });

    final optionalAdapter = FakeFlutterSceneAdapter();
    final optional = await ModelLoader(adapter: optionalAdapter).load(
      ModelSource.bytes(
        fixture(required: false),
        debugName: 'optional-clearcoat.glb',
      ),
    );
    expect(optional.isSuccess, isTrue);
    expect(optionalAdapter.loadedBytes, hasLength(1));
    expect(optional.authoredExtensionMaterialPatches, isEmpty);
    expect(optional.diagnostics.single.details['required'], isFalse);
    expect(optional.diagnostics.single.details['blocking'], isFalse);
    expect(optional.diagnostics.single.details['fallback'], 'coreMaterial');

    final requiredAdapter = FakeFlutterSceneAdapter();
    final required = await ModelLoader(adapter: requiredAdapter).load(
      ModelSource.bytes(
        fixture(required: true),
        debugName: 'required-clearcoat.glb',
      ),
    );
    expect(required.isSuccess, isFalse);
    expect(requiredAdapter.loadedBytes, isEmpty);
    expect(required.diagnostic!.code,
        ViewerDiagnosticCode.invalidMaterialOverride);
    expect(required.diagnostic!.details['required'], isTrue);
    expect(required.diagnostic!.details['blocking'], isTrue);
    expect(required.diagnostic!.details['fallback'], 'none');
  });

  test(
      'optional valid unsupported sheen imports only core fallback and preserves intent',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final bytes = _sheenFixture(
      sheen: <String, Object?>{
        'sheenColorFactor': <Object?>[0.2, 0.3, 0.4],
        'sheenRoughnessFactor': 0.6,
      },
    );

    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(bytes, debugName: 'optional-sheen.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes, hasLength(1));
    expect(adapter.loadedBytes.single, same(bytes));
    final sheen = result.authoredExtensionMaterialPatches.values
        .single[MaterialExtensionPatchGroup.sheen]!;
    expect(sheen.sheenColorFactor, <double>[0.2, 0.3, 0.4]);
    expect(sheen.sheenRoughness, 0.6);
    final diagnostic = result.diagnostics.singleWhere(
      (item) => item.details['extension'] == 'KHR_materials_sheen',
    );
    expect(
      diagnostic.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['blocking'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(diagnostic.details['status'], 'unsupported');
  });

  test(
      'production authored UV1 sheen diagnoses and plans exact native core fallback',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(),
        debugName: 'authored-uv1-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) => item.details['limitation'] == 'authoredUv0Only',
    );
    expect(diagnostic.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(diagnostic.details['extension'], 'KHR_materials_sheen');
    expect(diagnostic.details['field'], 'sheenColorTexture');
    expect(diagnostic.details['materialIndex'], 0);
    expect(diagnostic.details['uvSet'], 1);
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.authoredMaterialPreflightPatches, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test(
      'production authored data URI sheen diagnoses and neutralizes exact native fallback',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final bytes = _authoredDataUriSheenTextureFixture();
    final pinnedSheen = _pinnedParserSheen(bytes);
    expect(pinnedSheen.sheenColorFactor, <double>[0.2, 0.4, 0.8]);
    expect(pinnedSheen.sheenColorTexture?.index, 0);

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        bytes,
        debugName: 'authored-data-uri-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) =>
          item.details['extension'] == 'KHR_materials_sheen' &&
          item.details['reason'] ==
              'Imported texture image is not stored in a GLB bufferView.',
    );
    expect(diagnostic.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(diagnostic.details['field'], 'sheenColorTexture');
    expect(diagnostic.details['materialIndex'], 0);
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.authoredMaterialPreflightPatches, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test(
      'production authored specular-glossiness sheen conflict neutralizes exact native fallback',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final bytes = _sheenFixture(
      sheen: <String, Object?>{
        'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
      },
      siblingExtension: 'KHR_materials_pbrSpecularGlossiness',
    );
    final pinnedSheen = _pinnedParserSheen(bytes);
    expect(pinnedSheen.sheenColorFactor, <double>[0.2, 0.4, 0.8]);

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        bytes,
        debugName: 'authored-specgloss-sheen-conflict.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) =>
          item.details['extension'] == 'KHR_materials_sheen' &&
          item.details['conflict'] == 'KHR_materials_pbrSpecularGlossiness',
    );
    expect(diagnostic.code, ViewerDiagnosticCode.invalidMaterialOverride);
    expect(diagnostic.details['materialIndex'], 0);
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.authoredMaterialPreflightPatches, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('sheen fallback address follows compacted runtime primitive indices',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _compactedRuntimeSheenFallbackFixture(),
        debugName: 'compacted-runtime-sheen-fallback.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) =>
          item.details['extension'] == 'KHR_materials_sheen' &&
          item.details['conflict'] == 'KHR_materials_pbrSpecularGlossiness',
    );
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('optional sheen with wrong-type sampler blocks before adapter import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(
        _authoredSheenTextureEdgeFixture(sampler: 'invalid'),
        debugName: 'wrong-type-sheen-sampler.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, isEmpty);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.adapterFailure);
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['field'], 'textures[0].sampler');
    expect(result.diagnostic!.details['required'], isFalse);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['status'], 'malformedAsset');
    expect(result.diagnostic!.details['fallback'], 'none');
  });

  test('optional sheen with missing or wrong-type texture index blocks',
      () async {
    for (final fixture in <Uint8List>[
      _authoredSheenTextureEdgeFixture(
        includeTextureIndex: false,
      ),
      _authoredSheenTextureEdgeFixture(
        textureIndex: 'invalid',
      ),
    ]) {
      final adapter = FakeFlutterSceneAdapter();
      final result = await ModelLoader(adapter: adapter).load(
        ModelSource.bytes(
          fixture,
          debugName: 'malformed-sheen-texture-index.glb',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.loadedBytes, isEmpty);
      expect(result.diagnostic!.code, ViewerDiagnosticCode.adapterFailure);
      expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
      expect(result.diagnostic!.details['field'], 'sheenColorTexture');
      expect(result.diagnostic!.details['required'], isFalse);
      expect(result.diagnostic!.details['blocking'], isTrue);
      expect(result.diagnostic!.details['status'], 'malformedAsset');
      expect(result.diagnostic!.details['fallback'], 'none');
    }
  });

  test(
      'optional sheen with out-of-range texture index neutralizes exact fallback',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredSheenTextureEdgeFixture(textureIndex: 7),
        debugName: 'out-of-range-sheen-texture-index.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) => item.details['field'] == 'sheenColorTexture',
    );
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['blocking'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('optional sheen with out-of-range sampler neutralizes exact fallback',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.singleFabric();
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredSheenTextureEdgeFixture(sampler: 7),
        debugName: 'out-of-range-sheen-sampler.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) => item.details['field'] == 'textures[0].sampler',
    );
    expect(diagnostic.details['required'], isFalse);
    expect(diagnostic.details['blocking'], isFalse);
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('ambiguous authored UV1 sheen falls back globally without native leak',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.duplicateFabricPaths();

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(duplicateFabricPath: true),
        debugName: 'ambiguous-authored-uv1-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final ambiguity = result.diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == ViewerDiagnosticCode.ambiguousNodePath,
    );
    expect(ambiguity.details['nodePath'], <String>['Fabric']);
    expect(ambiguity.details['count'], 2);
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[true]);
    expect(adapter.liveMaterials, hasLength(2));
    for (final material in adapter.liveMaterials) {
      expect(material.sheenColorFactor, vm.Vector3.zero());
      expect(material.sheenRoughnessFactor, 0);
      expect(material.clearcoatFactor, 0.7);
    }
  });

  test('ambiguous valid optional sheen falls back globally without native leak',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.duplicateFabricPaths();

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _sheenFixture(
          sheen: <String, Object?>{
            'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
            'sheenRoughnessFactor': 0.6,
          },
          duplicateFabricPath: true,
        ),
        debugName: 'ambiguous-valid-optional-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final ambiguity = result.diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == ViewerDiagnosticCode.ambiguousNodePath,
    );
    expect(ambiguity.details['extension'], 'KHR_materials_sheen');
    expect(ambiguity.details['required'], isFalse);
    expect(ambiguity.details['blocking'], isFalse);
    expect(ambiguity.details['fallback'], 'coreMaterial');
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.authoredMaterialPreflightPatches, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[true]);
    for (final material in adapter.liveMaterials) {
      expect(material.sheenColorFactor, vm.Vector3.zero());
      expect(material.sheenRoughnessFactor, 0);
      expect(material.clearcoatFactor, 0.7);
    }
  });

  test('ambiguous valid required sheen blocks before adapter import', () async {
    final adapter = _RendererNativeSheenPolicyAdapter.duplicateFabricPaths();

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _sheenFixture(
          sheen: <String, Object?>{
            'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
          },
          required: true,
          duplicateFabricPath: true,
        ),
        debugName: 'ambiguous-valid-required-sheen.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, isEmpty);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.ambiguousNodePath);
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['required'], isTrue);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['fallback'], 'none');
  });

  test('authored sheen fallback follows pinned default scene selection',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.named(
      const <String>['ActiveFabric'],
    );
    final activeAddress = PartAddress(
      nodePath: const <String>['ActiveFabric'],
      primitiveIndex: 0,
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(
          nodeNames: const <String>['ActiveFabric', 'InactiveFabric'],
          sceneNodeIndices: const <List<int>>[
            <int>[0],
            <int>[1],
          ],
          includeDefaultScene: false,
        ),
        debugName: 'implicit-default-scene-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{activeAddress},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials, hasLength(1));
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('empty authored node name uses pinned synthetic fallback address',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.named(
      const <String>['node_0'],
    );
    final address = PartAddress(
      nodePath: const <String>['node_0'],
      primitiveIndex: 0,
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(
          nodeNames: const <String>[''],
        ),
        debugName: 'empty-node-name-sheen.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      <PartAddress>{address},
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials.single.sheenColorFactor, vm.Vector3.zero());
    expect(adapter.liveMaterials.single.sheenRoughnessFactor, 0);
    expect(adapter.liveMaterials.single.clearcoatFactor, 0.7);
  });

  test('shared rejected sheen material neutralizes every unique address',
      () async {
    final adapter = _RendererNativeSheenPolicyAdapter.named(
      const <String>['FabricA', 'FabricB'],
    );
    final addresses = <PartAddress>{
      PartAddress(
        nodePath: const <String>['FabricA'],
        primitiveIndex: 0,
      ),
      PartAddress(
        nodePath: const <String>['FabricB'],
        primitiveIndex: 0,
      ),
    };

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(
          nodeNames: const <String>['FabricA', 'FabricB'],
        ),
        debugName: 'shared-rejected-sheen-material.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.authoredSheenCoreFallbackPlans, <Set<PartAddress>>[
      addresses,
    ]);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, <bool>[false]);
    expect(adapter.liveMaterials, hasLength(2));
    for (final material in adapter.liveMaterials) {
      expect(material.sheenColorFactor, vm.Vector3.zero());
      expect(material.sheenRoughnessFactor, 0);
      expect(material.clearcoatFactor, 0.7);
    }
  });

  test('required valid unsupported sheen blocks atomically before publication',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final priorBytes = Uint8List.fromList(<int>[1, 2, 3]);
    final prior = await loader.load(
      ModelSource.bytes(priorBytes, debugName: 'prior-live.glb'),
    );
    expect(prior.isSuccess, isTrue);
    final requiredBytes = _sheenFixture(
      sheen: <String, Object?>{
        'sheenColorFactor': <Object?>[0.7, 0.6, 0.5],
      },
      required: true,
    );
    final originalCopy = Uint8List.fromList(requiredBytes);

    final result = await loader.load(
      ModelSource.bytes(requiredBytes, debugName: 'required-sheen.glb'),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, hasLength(1));
    expect(adapter.loadedBytes.single, same(priorBytes));
    expect(requiredBytes, originalCopy);
    expect(
      result.diagnostic!.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['required'], isTrue);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['fallback'], 'none');
  });

  test('opt-in no-sheen import never asks the sheen candidate to preflight',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
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
            <String, Object?>{'name': 'Plain', 'mesh': 0},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              ],
            },
          ],
        }),
        debugName: 'plain.glb',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.authoredMaterialPreflightPatches, isEmpty);
    expect(adapter.loadedBytes, hasLength(1));
  });

  test('opt-in authored sheen preflight failure follows requiredness',
      () async {
    ViewerDiagnostic failure(PartAddress address) => ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Sheen candidate resources are unavailable for test.',
          details: <String, Object?>{
            'part': address.debugPath,
            'feature': 'FSViewerSheenExtendedPbr',
            'limitation': 'sheenShaderUnavailable',
            'status': 'blocked',
            'materialReplaced': false,
            'encodedBytesModified': false,
          },
        );

    for (final required in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter(
        authoredMaterialPreflightDiagnostic: failure,
      );
      final bytes = _sheenFixture(
        sheen: <String, Object?>{
          'sheenColorFactor': <Object?>[0.3, 0.4, 0.5],
          'sheenRoughnessFactor': 0.7,
        },
        required: required,
      );
      final result = await ModelLoader(
        adapter: adapter,
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.experimentalShaders(
          enableSheen: true,
        ),
      ).load(ModelSource.bytes(bytes, debugName: 'preflight-failure.glb'));

      expect(adapter.authoredMaterialPreflightPatches, hasLength(1));
      final preflightPatch = adapter.authoredMaterialPreflightPatches.single;
      expect(preflightPatch.sheenColorFactor, <double>[0.3, 0.4, 0.5]);
      expect(preflightPatch.sheenRoughness, 0.7);
      expect(result.isSuccess, !required);
      expect(adapter.loadedBytes, required ? isEmpty : hasLength(1));
      expect(
        adapter.authoredSheenCoreFallbackPlans,
        required
            ? isEmpty
            : <Set<PartAddress>>[
                <PartAddress>{
                  PartAddress(
                    nodePath: const <String>['Fabric'],
                    primitiveIndex: 0,
                  ),
                },
              ],
      );
      final diagnostic =
          required ? result.diagnostic! : result.diagnostics.single;
      expect(diagnostic.details['extension'], 'KHR_materials_sheen');
      expect(diagnostic.details['required'], required);
      expect(diagnostic.details['blocking'], required);
      expect(
          diagnostic.details['fallback'], required ? 'none' : 'coreMaterial');
      expect(diagnostic.details['parsedIntentPreserved'], isTrue);
      expect(diagnostic.details['limitation'], 'sheenShaderUnavailable');
    }
  });

  test('authored sheen preflight exception returns typed adapter failure',
      () async {
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (_) =>
          throw StateError('preflight exploded'),
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _sheenFixture(
          sheen: <String, Object?>{
            'sheenColorFactor': <Object?>[0.3, 0.4, 0.5],
          },
          required: true,
        ),
        debugName: 'throwing-authored-preflight.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.adapterFailure);
    expect(
      result.diagnostic!.details['stage'],
      'authoredMaterialPreflight',
    );
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['feature'], 'sheen');
    expect(result.diagnostic!.details['status'], 'blocked');
    expect(result.diagnostic!.details['materialReplaced'], isFalse);
    expect(result.diagnostic!.details['encodedBytesModified'], isFalse);
    expect(result.diagnostic!.details['error'], contains('preflight exploded'));
    expect(adapter.loadedBytes, isEmpty);
    expect(adapter.receivedPublicationCallbacks, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, isEmpty);
    expect(result.authoredCoreMaterialPatches, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
  });

  test('authored sheen preflight obeys the model load timeout', () async {
    final gate = Completer<ViewerDiagnostic?>();
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (_) => gate.future,
    );
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(
        timeout: Duration(milliseconds: 10),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    );
    final load = loader.load(
      ModelSource.bytes(
        _sheenFixture(
          sheen: <String, Object?>{
            'sheenColorFactor': <Object?>[0.3, 0.4, 0.5],
          },
          required: true,
        ),
        debugName: 'timed-out-authored-preflight.glb',
      ),
    );
    final delayedCompletion = Future<void>.delayed(
      const Duration(milliseconds: 100),
      () {
        if (!gate.isCompleted) {
          gate.complete(null);
        }
      },
    );

    final result = await load;
    await delayedCompletion;

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(
      result.diagnostic!.details['source'],
      'timed-out-authored-preflight.glb',
    );
    expect(result.diagnostic!.details['timeoutMilliseconds'], 10);
    expect(adapter.loadedBytes, isEmpty);
    expect(adapter.receivedPublicationCallbacks, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, isEmpty);
    expect(result.authoredCoreMaterialPatches, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
  });

  test('authored sheen preflight cancellation returns before its gate',
      () async {
    final started = Completer<void>();
    final gate = Completer<ViewerDiagnostic?>();
    final preflightedAddresses = <PartAddress>[];
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (address) {
        preflightedAddresses.add(address);
        if (!started.isCompleted) {
          started.complete();
        }
        return gate.future;
      },
    );
    final cancellation = ModelLoadCancellationController();
    final load = ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _twoSheenMaterialFixture(required: true),
        debugName: 'cancelled-authored-preflight.glb',
      ),
      cancellationToken: cancellation.token,
    );
    await started.future;
    expect(cancellation.cancel('preflight-dismissed'), isTrue);
    final timeoutSentinel = Object();
    final first = await Future.any<Object>(<Future<Object>>[
      load.then<Object>((result) => result),
      Future<Object>.delayed(
        const Duration(milliseconds: 50),
        () => timeoutSentinel,
      ),
    ]);
    if (!gate.isCompleted) {
      gate.complete(null);
    }
    final result = first is ModelLoadResult ? first : await load;
    await Future<void>.delayed(Duration.zero);

    expect(first, isNot(same(timeoutSentinel)));
    expect(result.isSuccess, isFalse);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(result.diagnostic!.details['stage'], 'authoredMaterialPreflight');
    expect(result.diagnostic!.details['reason'], 'preflight-dismissed');
    expect(result.diagnostic!.details['status'], 'cancelled');
    expect(adapter.loadedBytes, isEmpty);
    expect(adapter.receivedPublicationCallbacks, isEmpty);
    expect(adapter.authoredSheenCoreFallbackPlans, isEmpty);
    expect(result.authoredCoreMaterialPatches, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(
      preflightedAddresses,
      <PartAddress>[
        PartAddress(
          nodePath: const <String>['IncompatibleFabric'],
          primitiveIndex: 0,
        ),
      ],
    );
  });

  test('optional authored sheen preflight scopes request failure by address',
      () async {
    final failingAddress = PartAddress(
      nodePath: const <String>['IncompatibleFabric'],
      primitiveIndex: 0,
    );
    final validAddress = PartAddress(
      nodePath: const <String>['ValidFabric'],
      primitiveIndex: 0,
    );
    final preflightedAddresses = <PartAddress>[];
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (address) {
        preflightedAddresses.add(address);
        if (address != failingAddress) {
          return null;
        }
        return const ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'The requested sheen resources are incompatible.',
          details: <String, Object?>{
            'feature': 'FSViewerSheenExtendedPbr',
            'limitation': 'sheenCompositionResourceIncompatible',
            'status': 'blocked',
            'materialReplaced': false,
            'encodedBytesModified': false,
          },
        );
      },
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _twoSheenMaterialFixture(),
        debugName: 'address-scoped-preflight.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(preflightedAddresses, <PartAddress>[failingAddress, validAddress]);
    final sheenDiagnostics = result.diagnostics.where(
      (diagnostic) =>
          diagnostic.details['extension'] == 'KHR_materials_sheen' &&
          diagnostic.details['parsedIntentPreserved'] == true,
    );
    expect(sheenDiagnostics, hasLength(1));
    expect(sheenDiagnostics.single.details['part'], failingAddress.debugPath);
    expect(
      sheenDiagnostics.single.details['partAddress'],
      failingAddress.toJson(),
    );
    expect(
      result
          .authoredExtensionMaterialPatches[validAddress]![
              MaterialExtensionPatchGroup.sheen]!
          .sheenRoughness,
      0.7,
    );
    expect(adapter.authoredSheenCoreFallbackPlans, hasLength(1));
    expect(
      adapter.authoredSheenCoreFallbackPlans.single,
      <PartAddress>{failingAddress},
    );

    final plainResult = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
        }),
        debugName: 'plain-after-address-scoped-preflight.glb',
      ),
    );

    expect(plainResult.isSuccess, isTrue);
    expect(adapter.authoredSheenCoreFallbackPlans, hasLength(2));
    expect(adapter.authoredSheenCoreFallbackPlans.last, isEmpty);
  });

  test('authored sheen shader failure stays scoped to selected variant',
      () async {
    final combinedAddress = PartAddress(
      nodePath: const <String>['IncompatibleFabric'],
      primitiveIndex: 0,
    );
    final sheenOnlyAddress = PartAddress(
      nodePath: const <String>['ValidFabric'],
      primitiveIndex: 0,
    );
    final preflightedAddresses = <PartAddress>[];
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (address) {
        preflightedAddresses.add(address);
        if (address != combinedAddress) {
          return null;
        }
        return ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'The selected combined sheen shader is unavailable.',
          details: <String, Object?>{
            'part': address.debugPath,
            'feature': 'FSViewerClearcoatSheenExtendedPbr',
            'selectedVariant': 'FSViewerClearcoatSheenExtendedPbr',
            'limitation': 'sheenShaderUnavailable',
            'status': 'blocked',
            'materialReplaced': false,
            'encodedBytesModified': false,
          },
        );
      },
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _twoSheenMaterialFixture(firstHasClearcoat: true),
        debugName: 'selected-variant-preflight.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(
      preflightedAddresses,
      <PartAddress>[combinedAddress, sheenOnlyAddress],
    );
    final sheenDiagnostics = result.diagnostics.where(
      (diagnostic) =>
          diagnostic.details['extension'] == 'KHR_materials_sheen' &&
          diagnostic.details['parsedIntentPreserved'] == true,
    );
    expect(sheenDiagnostics, hasLength(1));
    expect(sheenDiagnostics.single.details['part'], combinedAddress.debugPath);
    expect(
      sheenDiagnostics.single.details['partAddress'],
      combinedAddress.toJson(),
    );
    expect(
      sheenDiagnostics.single.details['selectedVariant'],
      'FSViewerClearcoatSheenExtendedPbr',
    );
    expect(
      result
          .authoredExtensionMaterialPatches[sheenOnlyAddress]![
              MaterialExtensionPatchGroup.sheen]!
          .sheenRoughness,
      0.7,
    );
  });

  test('authored sheen LUT failure stays singular and addressless', () async {
    final affectedAddresses = <PartAddress>{
      PartAddress(
        nodePath: const <String>['IncompatibleFabric'],
        primitiveIndex: 0,
      ),
      PartAddress(
        nodePath: const <String>['ValidFabric'],
        primitiveIndex: 0,
      ),
    };
    final preflightedAddresses = <PartAddress>[];
    final adapter = FakeFlutterSceneAdapter(
      authoredMaterialPreflightDiagnostic: (address) {
        preflightedAddresses.add(address);
        return ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'The package-local sheen LUT is unavailable.',
          details: <String, Object?>{
            'part': address.debugPath,
            'feature': 'FSViewerSheenExtendedPbr',
            'limitation': 'sheenDirectionalAlbedoResourceUnavailable',
            'status': 'blocked',
            'materialReplaced': false,
            'encodedBytesModified': false,
          },
        );
      },
    );

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _twoSheenMaterialFixture(),
        debugName: 'global-preflight.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(preflightedAddresses, hasLength(1));
    final sheenDiagnostics = result.diagnostics.where(
      (diagnostic) =>
          diagnostic.details['extension'] == 'KHR_materials_sheen' &&
          diagnostic.details['parsedIntentPreserved'] == true,
    );
    expect(sheenDiagnostics, hasLength(1));
    expect(sheenDiagnostics.single.details, isNot(contains('part')));
    expect(sheenDiagnostics.single.details, isNot(contains('partAddress')));
    expect(adapter.authoredSheenCoreFallbackPlans, hasLength(1));
    expect(
      adapter.authoredSheenCoreFallbackPlans.single,
      affectedAddresses,
    );

    final plainResult = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
        }),
        debugName: 'plain-after-global-preflight.glb',
      ),
    );

    expect(plainResult.isSuccess, isTrue);
    expect(adapter.authoredSheenCoreFallbackPlans, hasLength(2));
    expect(adapter.authoredSheenCoreFallbackPlans.last, isEmpty);
  });

  test('optional sheen without preflight adapter falls back every address',
      () async {
    final adapter = _NonPreflightFlutterSceneAdapter();
    final affectedAddresses = <PartAddress>{
      PartAddress(
        nodePath: const <String>['IncompatibleFabric'],
        primitiveIndex: 0,
      ),
      PartAddress(
        nodePath: const <String>['ValidFabric'],
        primitiveIndex: 0,
      ),
    };

    final result = await ModelLoader(
      adapter: adapter,
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
    ).load(
      ModelSource.bytes(
        _twoSheenMaterialFixture(),
        debugName: 'missing-preflight-adapter.glb',
      ),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final diagnostic = result.diagnostics.singleWhere(
      (item) =>
          item.details['limitation'] ==
          'authoredSheenPreflightAdapterUnavailable',
    );
    expect(diagnostic.details['fallback'], 'coreMaterial');
    expect(diagnostic.details, isNot(contains('part')));
    expect(adapter.authoredSheenCoreFallbackPlans, hasLength(1));
    expect(
      adapter.authoredSheenCoreFallbackPlans.single,
      affectedAddresses,
    );
  });

  test(
      'malformed sheen blocks before adapter import regardless of requiredness',
      () async {
    for (final invalidSheen in <Object?>[
      <String, Object?>{
        'sheenColorFactor': <Object?>[1, 1],
      },
      <String, Object?>{
        'sheenColorFactor': <Object?>[1.01, 0, 0],
      },
    ]) {
      for (final required in <bool>[false, true]) {
        final adapter = FakeFlutterSceneAdapter();
        final bytes = _sheenFixture(
          sheen: invalidSheen,
          required: required,
        );

        final result = await ModelLoader(adapter: adapter).load(
          ModelSource.bytes(bytes, debugName: 'malformed-sheen.glb'),
        );

        expect(result.isSuccess, isFalse);
        expect(adapter.loadedBytes, isEmpty);
        expect(result.authoredExtensionMaterialPatches, isEmpty);
        final diagnostic = result.diagnostic!;
        expect(diagnostic.details['extension'], 'KHR_materials_sheen');
        expect(
          diagnostic.code,
          ViewerDiagnosticCode.invalidMaterialOverride,
        );
        expect(diagnostic.details['required'], required);
        expect(diagnostic.details['blocking'], isTrue);
        expect(diagnostic.details['status'], 'malformedAsset');
        expect(diagnostic.details['fallback'], 'none');
      }
    }
  });

  test('malformed sheen blocks publication beside otherwise valid material',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_materials_sheen'],
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0, 1],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'InvalidFabric', 'mesh': 0},
            <String, Object?>{'name': 'ValidFabric', 'mesh': 1},
          ],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{'POSITION': 0},
                  'material': 0,
                },
              ],
            },
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'attributes': <String, Object?>{'POSITION': 0},
                  'material': 1,
                },
              ],
            },
          ],
          'materials': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_materials_sheen': <String, Object?>{
                  'sheenColorFactor': <Object?>[1, 1],
                },
              },
            },
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_materials_sheen': <String, Object?>{
                  'sheenRoughnessFactor': 0.6,
                },
              },
            },
          ],
        }),
        debugName: 'mixed-sheen.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(
        result.diagnostic!.code, ViewerDiagnosticCode.invalidMaterialOverride);
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['materialIndex'], 0);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['status'], 'malformedAsset');
    expect(result.diagnostic!.details['fallback'], 'none');
  });

  test('unlit sheen combination blocks before adapter import', () async {
    for (final required in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter();
      final result = await ModelLoader(adapter: adapter).load(
        ModelSource.bytes(
          _sheenFixture(
            sheen: <String, Object?>{
              'sheenColorFactor': <Object?>[0.2, 0.3, 0.4],
            },
            required: required,
            siblingExtension: 'KHR_materials_unlit',
          ),
          debugName: 'invalid-sheen-combination.glb',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.loadedBytes, isEmpty);
      expect(result.diagnostic!.details['conflict'], 'KHR_materials_unlit');
      expect(result.diagnostic!.details['required'], required);
      expect(result.diagnostic!.details['blocking'], isTrue);
      expect(result.diagnostic!.details['status'], 'malformedAsset');
      expect(result.diagnostic!.details['fallback'], 'none');
    }
  });

  test('optional sheen with missing selected UV blocks before adapter import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(includeSelectedTexCoord: false),
        debugName: 'missing-sheen-uv.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.missingUvSet);
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['materialIndex'], 0);
    expect(result.diagnostic!.details['uvSet'], 1);
    expect(result.diagnostic!.details['required'], isFalse);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['status'], 'malformedAsset');
    expect(result.diagnostic!.details['fallback'], 'none');
    expect(adapter.authoredSheenCoreFallbackPlans, isEmpty);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, isEmpty);
  });

  test('optional sheen with unsupported higher UV blocks before adapter import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(
        _authoredUv1SheenTextureFixture(texCoord: 2),
        debugName: 'unsupported-sheen-uv.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.loadedBytes, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(
      result.diagnostic!.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostic!.details['extension'], 'KHR_materials_sheen');
    expect(result.diagnostic!.details['materialIndex'], 0);
    expect(result.diagnostic!.details['uvSet'], 2);
    expect(result.diagnostic!.details['limitation'], 'authoredUv0Only');
    expect(result.diagnostic!.details['required'], isFalse);
    expect(result.diagnostic!.details['blocking'], isTrue);
    expect(result.diagnostic!.details['status'], 'malformedAsset');
    expect(result.diagnostic!.details['fallback'], 'none');
    expect(adapter.authoredSheenCoreFallbackPlans, isEmpty);
    expect(adapter.authoredSheenGlobalCoreFallbackPlans, isEmpty);
  });

  test('missing effective UV diagnoses once without blocking adapter import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final imageBytes = Uint8List.fromList(<int>[11, 12, 13]);
    final result = await ModelLoader(adapter: adapter).load(
      ModelSource.bytes(
        _glbWithBin(
          <String, Object?>{
            'asset': <String, Object?>{'version': '2.0'},
            'scene': 0,
            'scenes': <Object?>[
              <String, Object?>{
                'nodes': <Object?>[0],
              },
            ],
            'nodes': <Object?>[
              <String, Object?>{'name': 'MissingUvPanel', 'mesh': 0},
            ],
            'meshes': <Object?>[
              <String, Object?>{
                'primitives': <Object?>[
                  <String, Object?>{
                    'attributes': <String, Object?>{
                      'POSITION': 0,
                      'TEXCOORD_0': 1,
                    },
                    'material': 0,
                  },
                ],
              },
            ],
            'materials': <Object?>[
              <String, Object?>{
                'pbrMetallicRoughness': <String, Object?>{
                  'baseColorTexture': <String, Object?>{
                    'index': 0,
                    'texCoord': 1,
                  },
                },
              },
            ],
            'textures': <Object?>[
              <String, Object?>{'source': 0},
            ],
            'images': <Object?>[
              <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
            ],
            'bufferViews': <Object?>[
              <String, Object?>{
                'buffer': 0,
                'byteLength': imageBytes.length,
              },
            ],
            'buffers': <Object?>[
              <String, Object?>{'byteLength': imageBytes.length},
            ],
          },
          imageBytes,
        ),
        debugName: 'missing-effective-uv.glb',
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.loadedBytes, hasLength(1));
    expect(result.authoredCoreMaterialPatches, isEmpty);
    final missingUvDiagnostics = result.diagnostics
        .where(
          (diagnostic) => diagnostic.code == ViewerDiagnosticCode.missingUvSet,
        )
        .toList();
    expect(missingUvDiagnostics, hasLength(1));
    expect(missingUvDiagnostics.single.details['uvSet'], 1);
    expect(missingUvDiagnostics.single.details['blocking'], isFalse);
  });

  test('fails before adapter import when required Draco decoder is missing',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);

    final result = await loader.load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
          'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'material': 0,
                  'extensions': <String, Object?>{
                    'KHR_draco_mesh_compression': <String, Object?>{
                      'bufferView': 0,
                      'attributes': <String, Object?>{'POSITION': 0},
                    },
                  },
                },
              ],
            },
          ],
        }),
        debugName: 'required-draco.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(
        result.diagnostic?.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(
        result.diagnostic?.details['extension'], 'KHR_draco_mesh_compression');
    expect(result.diagnostic?.details['required'], isTrue);
    expect(result.diagnostic?.details['status'], 'pluginMissing');
    expect(
      result.diagnostic?.details['pluginPackage'],
      'flutter_scene_viewer_draco',
    );
    expect(
      result.diagnostic?.details['configurationKey'],
      'FlutterSceneViewerDracoEnabled',
    );
    expect(adapter.loadedBytes, isEmpty);
  });

  test('passes required Draco assets to adapter when decoder is available',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(
        decoderCapabilities: GlbDecoderCapabilities(
          dracoMeshCompression: true,
        ),
      ),
    );
    final bytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'material': 0,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'required-draco.glb'),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.loadedBytes.single, bytes);
  });

  test('loads optional Draco assets with non-blocking diagnostics', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final bytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'material': 0,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'optional-draco.glb'),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.loadedBytes.single, bytes);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostics.single.details['required'], isFalse);
  });

  test('rewrites required meshopt bufferViews before adapter import', () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(adapter: adapter);
    final encoded = _meshoptAttributeStream(<int>[1, 2, 3, 4]);
    final bytes = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['EXT_meshopt_compression'],
        'extensionsRequired': <Object?>['EXT_meshopt_compression'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': encoded.lengthInBytes},
          <String, Object?>{
            'byteLength': 4,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'fallback': true,
              },
            },
          },
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 1,
            'byteOffset': 0,
            'byteLength': 4,
            'byteStride': 4,
            'extensions': <String, Object?>{
              'EXT_meshopt_compression': <String, Object?>{
                'buffer': 0,
                'byteOffset': 0,
                'byteLength': encoded.lengthInBytes,
                'byteStride': 4,
                'count': 1,
                'mode': 'ATTRIBUTES',
              },
            },
          },
        ],
      },
      encoded,
    );

    final result = await loader.load(
      ModelSource.bytes(bytes, debugName: 'required-meshopt.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes, hasLength(1));
    final capabilities = readGlbAssetCapabilities(adapter.loadedBytes.single);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.extensionsUsed, isEmpty);
    expect(capabilities.meshoptCompressedBufferViewCount, 0);
    expect(
      _glbBufferViewBytes(adapter.loadedBytes.single, 0),
      orderedEquals(<int>[1, 2, 3, 4]),
    );
    expect(
      result.diagnostics.where(
        (diagnostic) =>
            diagnostic.details['extension'] == 'EXT_meshopt_compression',
      ),
      isEmpty,
    );
  });

  test('cancellation during Meshopt returns one typed terminal diagnostic',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(
        decodeBudget: GlbDecodeBudget(cancellationCheckInterval: 1),
      ),
    );
    final cancellation = ModelLoadCancellationController();
    final encoded = _meshoptAttributeStream(<int>[1, 2, 3, 4]);
    final bytes = _glbWithBin(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['EXT_meshopt_compression'],
      'extensionsRequired': <Object?>['EXT_meshopt_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': encoded.lengthInBytes},
        <String, Object?>{
          'byteLength': 4,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{'fallback': true},
          },
        },
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 1,
          'byteOffset': 0,
          'byteLength': 4,
          'byteStride': 4,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{
              'buffer': 0,
              'byteOffset': 0,
              'byteLength': encoded.lengthInBytes,
              'byteStride': 4,
              'count': 1,
              'mode': 'ATTRIBUTES',
            },
          },
        },
      ],
    }, encoded);

    final load = loader.load(
      ModelSource.bytes(bytes, debugName: 'cancelled-meshopt.glb'),
      cancellationToken: cancellation.token,
    );
    scheduleMicrotask(() => cancellation.cancel('meshopt-test'));
    final result = await load;

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic!.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(result.diagnostic!.details['source'], 'cancelled-meshopt.glb');
    expect(result.diagnostic!.details['extension'], 'EXT_meshopt_compression');
    expect(result.diagnostic!.details['stage'], 'meshoptAttributes');
    expect(result.diagnostic!.details['reason'], 'meshopt-test');
    expect(result.diagnostic!.details['status'], 'cancelled');
    expect(result.diagnostics, hasLength(1));
    expect(adapter.loadedBytes, isEmpty);
  });

  test('reports native Draco opt-in diagnostics before adapter import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final loader = ModelLoader(
      adapter: adapter,
      options: const ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          GlbNativeDecoderAvailability(
            diagnosticsByExtension: <String, ViewerDiagnostic>{
              'KHR_draco_mesh_compression': ViewerDiagnostic(
                code: ViewerDiagnosticCode.unsupportedModelFeature,
                message: 'Native Draco decoder is installed but disabled.',
                details: <String, Object?>{
                  'extension': 'KHR_draco_mesh_compression',
                  'decoder': 'draco',
                  'required': true,
                  'status': 'disabled',
                  'configurationKey': 'FlutterSceneViewerDracoEnabled',
                },
              ),
            },
          ),
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(
        _glb(<String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
          'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
          'meshes': <Object?>[
            <String, Object?>{
              'primitives': <Object?>[
                <String, Object?>{
                  'extensions': <String, Object?>{
                    'KHR_draco_mesh_compression': <String, Object?>{
                      'bufferView': 0,
                      'attributes': <String, Object?>{'POSITION': 0},
                    },
                  },
                },
              ],
            },
          ],
        }),
        debugName: 'disabled-draco.glb',
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(
        result.diagnostic?.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(result.diagnostic?.details['status'], 'disabled');
    expect(
      result.diagnostic?.details['configurationKey'],
      'FlutterSceneViewerDracoEnabled',
    );
    expect(adapter.loadedBytes, isEmpty);
  });

  test('uses native Draco capability probe before adapter import', () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
            },
          ],
        },
      ],
    });
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(
              dracoMeshCompression: true,
            ),
          ),
          decodedBytes: decodedBytes,
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'native-draco.glb'),
    );

    expect(result.isSuccess, isTrue);
    expect(adapter.loadedBytes.single, decodedBytes);
  });

  test('threads the selected decode budget and per-load tracker to the probe',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 4096,
      maxNativeOutputBytes: 4096,
      maxAccessors: 17,
      maxVertices: 19,
      maxIndices: 23,
    );
    final probe = RecordingNativeDecoderProbe(decodedBytes);
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        decodeBudget: budget,
        nativeDecoderProbe: probe,
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'threaded-budget.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(identical(probe.receivedBudget, budget), isTrue);
    expect(probe.receivedTracker, isNotNull);
    expect(identical(probe.receivedTracker!.budget, budget), isTrue);
    expect(probe.trackerTotalDecodedBytesAtDecode, 0);
    expect(probe.trackerNativeOutputBytesAtDecode, 0);
    expect(
        probe.receivedTracker!.totalDecodedBytes, decodedBytes.lengthInBytes);
    expect(
        probe.receivedTracker!.nativeOutputBytes, decodedBytes.lengthInBytes);
    expect(adapter.loadedBytes.single, decodedBytes);
  });

  test('component Draco output checks final GLB size without double counting',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/model_loader/component-draco');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final sourceBytes = _nativeDracoComponentGlb();
    final positionBytes = _float32Bytes(<double>[1, 2, 3]);
    final indexBytes = _uint16Bytes(<int>[0, 0, 0]);
    final expectedBytes = rewriteDracoCompressedGlb(
      sourceBytes,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{'POSITION': positionBytes},
          indices: indexBytes,
        ),
      ],
    ).bytes!;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getDecoderAvailability') {
        return <String, Object?>{
          'capabilities': <String, Object?>{
            'dracoMeshCompression': true,
          },
          'diagnostics': <Object?>[],
        };
      }
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedPrimitives': <Object?>[
          <String, Object?>{
            'meshIndex': 0,
            'primitiveIndex': 0,
            'attributes': <String, Object?>{'POSITION': positionBytes},
            'indices': indexBytes,
          },
        ],
      };
    });

    for (final belowFinalLimit in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter();
      final loader = ModelLoader(
        adapter: adapter,
        options: ModelLoaderOptions(
          decodeBudget: GlbDecodeBudget(
            maxTotalDecodedBytes: 18,
            maxNativeOutputBytes:
                expectedBytes.lengthInBytes - (belowFinalLimit ? 1 : 0),
            maxAccessors: 2,
            maxVertices: 1,
            maxIndices: 3,
          ),
          nativeDecoderProbe: const MethodChannelGlbNativeDecoderProbe(
            channel: channel,
          ),
        ),
      );

      final result = await loader.load(
        ModelSource.bytes(sourceBytes, debugName: 'component-draco.glb'),
      );

      expect(result.isSuccess, !belowFinalLimit);
      if (belowFinalLimit) {
        expect(result.diagnostic?.details['field'], 'nativeOutputBytes');
        expect(result.diagnostic?.details['stage'], 'nativeDecodedGlbOutput');
        expect(adapter.loadedBytes, isEmpty);
      } else {
        expect(adapter.loadedBytes.single, expectedBytes);
      }
    }
  });

  test('component BasisU output checks final GLB size without double counting',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/model_loader/component-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final sourceBytes = _nativeBasisuComponentGlb();
    final decodedImageBytes = _pngBytes(width: 1, height: 1);
    final expectedBytes = rewriteBasisuTexturesInGlb(
      sourceBytes,
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          mimeType: 'image/png',
          width: 1,
          height: 1,
          bytes: decodedImageBytes,
        ),
      ],
    ).bytes!;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getDecoderAvailability') {
        return <String, Object?>{
          'capabilities': <String, Object?>{'textureBasisu': true},
          'diagnostics': <Object?>[],
        };
      }
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
            'bytes': decodedImageBytes,
          },
        ],
      };
    });

    for (final belowFinalLimit in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter();
      final loader = ModelLoader(
        adapter: adapter,
        options: ModelLoaderOptions(
          decodeBudget: GlbDecodeBudget(
            maxTotalDecodedBytes: decodedImageBytes.lengthInBytes,
            maxNativeOutputBytes:
                expectedBytes.lengthInBytes - (belowFinalLimit ? 1 : 0),
          ),
          nativeDecoderProbe: const MethodChannelGlbNativeDecoderProbe(
            basisuChannel: channel,
          ),
        ),
      );

      final result = await loader.load(
        ModelSource.bytes(sourceBytes, debugName: 'component-basisu.glb'),
      );

      expect(result.isSuccess, !belowFinalLimit);
      if (belowFinalLimit) {
        expect(result.diagnostic?.details['field'], 'nativeOutputBytes');
        expect(result.diagnostic?.details['stage'], 'nativeDecodedGlbOutput');
        expect(adapter.loadedBytes, isEmpty);
      } else {
        expect(adapter.loadedBytes.single, expectedBytes);
      }
    }
  });

  test('opaque MethodChannel output is reserved exactly once', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('test/model_loader/opaque-draco');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final sourceBytes = _nativeDracoComponentGlb();
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getDecoderAvailability') {
        return <String, Object?>{
          'capabilities': <String, Object?>{
            'dracoMeshCompression': true,
          },
          'diagnostics': <Object?>[],
        };
      }
      return <String, Object?>{
        'bytes': decodedBytes,
        'diagnostics': <Object?>[],
      };
    });

    for (final belowFinalLimit in <bool>[false, true]) {
      final adapter = FakeFlutterSceneAdapter();
      final loader = ModelLoader(
        adapter: adapter,
        options: ModelLoaderOptions(
          decodeBudget: GlbDecodeBudget(
            maxTotalDecodedBytes:
                decodedBytes.lengthInBytes - (belowFinalLimit ? 1 : 0),
            maxNativeOutputBytes:
                decodedBytes.lengthInBytes - (belowFinalLimit ? 1 : 0),
          ),
          nativeDecoderProbe: const MethodChannelGlbNativeDecoderProbe(
            channel: channel,
          ),
        ),
      );

      final result = await loader.load(
        ModelSource.bytes(sourceBytes, debugName: 'opaque-draco.glb'),
      );

      expect(result.isSuccess, !belowFinalLimit);
      if (belowFinalLimit) {
        expect(result.diagnostic?.details['field'], 'nativeOutputBytes');
        expect(adapter.loadedBytes, isEmpty);
      } else {
        expect(adapter.loadedBytes.single, decodedBytes);
      }
    }
  });

  test('rejects inconsistent native output accounting metadata', () async {
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    final mipImage = GlbDecodedBasisuImage(
      imageIndex: 0,
      contentRole: 'color',
      levels: <GlbDecodedBasisuMipLevel>[
        GlbDecodedBasisuMipLevel(
          level: 0,
          width: 1,
          height: 1,
          rgbaBytes: Uint8List(4),
        ),
      ],
    );
    final cases = <({GlbNativeDecodeResult result, String field})>[
      (
        result: GlbNativeDecodeResult(
          bytes: decodedBytes,
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
        ),
        field: 'outputAccounting',
      ),
      (
        result: const GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
        ),
        field: 'outputAccounting',
      ),
      (
        result: GlbNativeDecodeResult(
          topologyBytes: decodedBytes,
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
        ),
        field: 'decodedBasisuImages',
      ),
      (
        result: GlbNativeDecodeResult(
          decodedBasisuImages: <GlbDecodedBasisuImage>[mipImage],
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
        ),
        field: 'topologyBytes',
      ),
      (
        result: const GlbNativeDecodeResult(
          topologyOutputAccounting:
              GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
        ),
        field: 'topologyOutputAccounting',
      ),
      (
        result: GlbNativeDecodeResult(
          topologyBytes: decodedBytes,
          topologyOutputAccounting:
              GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
          decodedBasisuImages: <GlbDecodedBasisuImage>[mipImage],
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
        ),
        field: 'topologyOutputAccounting',
      ),
    ];

    for (final testCase in cases) {
      final invalidResult = testCase.result;
      final adapter = FakeFlutterSceneAdapter();
      final loader = ModelLoader(
        adapter: adapter,
        options: ModelLoaderOptions(
          nativeDecoderProbe: FixedNativeDecoderProbe(invalidResult),
        ),
      );

      final result = await loader.load(
        ModelSource.bytes(
          _nativeDracoComponentGlb(),
          debugName: 'invalid-accounting.glb',
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.diagnostic?.details['limitation'],
        'nativeDecodeOutputAccounting',
      );
      expect(result.diagnostic?.details['status'], 'malformedOutput');
      expect(result.diagnostic?.details['field'], testCase.field);
      expect(adapter.loadedBytes, isEmpty);
    }
  });

  test('rejects oversized native decoded GLB before capability read or import',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        decodeBudget: GlbDecodeBudget(
          maxNativeOutputBytes: decodedBytes.lengthInBytes - 1,
        ),
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(
              dracoMeshCompression: true,
            ),
          ),
          decodedBytes: decodedBytes,
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'oversized-native.glb'),
    );

    expect(result.isSuccess, isFalse);
    expect(
        result.diagnostic?.code, ViewerDiagnosticCode.unsupportedModelFeature);
    expect(result.diagnostic?.details['limitation'], 'decodeBudget');
    expect(result.diagnostic?.details['status'], 'budgetExceeded');
    expect(result.diagnostic?.details['stage'], 'nativeDecodedGlbOutput');
    expect(
      result.diagnostic?.details['limit'],
      decodedBytes.lengthInBytes - 1,
    );
    expect(result.diagnostic?.details['actual'], decodedBytes.lengthInBytes);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('accepts native decoded GLB exactly at both output budgets', () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    });
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        decodeBudget: GlbDecodeBudget(
          maxTotalDecodedBytes: decodedBytes.lengthInBytes,
          maxNativeOutputBytes: decodedBytes.lengthInBytes,
        ),
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(
              dracoMeshCompression: true,
            ),
          ),
          decodedBytes: decodedBytes,
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'exact-native-budget.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes.single, decodedBytes);
  });

  test('uses native BasisU capability probe before adapter import', () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'extensionsUsed': <Object?>['KHR_texture_basisu'],
        'extensionsRequired': <Object?>['KHR_texture_basisu'],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 4},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        ],
        'images': <Object?>[
          <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
        ],
        'textures': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_texture_basisu': <String, Object?>{'source': 0},
            },
          },
        ],
      },
      Uint8List.fromList(<int>[9, 9, 9, 9]),
    );
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
      ],
      'textures': <Object?>[
        <String, Object?>{'source': 0},
      ],
    });
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(
              textureBasisu: true,
            ),
          ),
          decodedBytes: decodedBytes,
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'native-basisu.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes.single, decodedBytes);
  });

  test('publishes multi-level BasisU through the repo-local binding adapter',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final sourceBytes = _nativeBasisuMipMaterialGlb();
    final decodedImages = <GlbDecodedBasisuImage>[
      GlbDecodedBasisuImage(
        imageIndex: 0,
        contentRole: 'color',
        levels: <GlbDecodedBasisuMipLevel>[
          GlbDecodedBasisuMipLevel(
            level: 0,
            width: 2,
            height: 2,
            rgbaBytes: Uint8List.fromList(List<int>.filled(16, 1)),
          ),
          GlbDecodedBasisuMipLevel(
            level: 1,
            width: 1,
            height: 1,
            rgbaBytes: Uint8List.fromList(List<int>.filled(4, 2)),
          ),
        ],
        textureBindings: const <GlbDecodedBasisuTextureBinding>[
          GlbDecodedBasisuTextureBinding(
            textureIndex: 0,
            sampler: GlbBasisuSamplerIntent(
              magFilter: 9729,
              minFilter: 9987,
              wrapS: 33071,
              wrapT: 33648,
            ),
          ),
        ],
      ),
    ];
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(textureBasisu: true),
          ),
          topologyBytes: sourceBytes,
          decodedImages: decodedImages,
          decodeDiagnostics: <ViewerDiagnostic>[
            const ViewerDiagnostic(
              code: ViewerDiagnosticCode.unsupportedModelFeature,
              message: 'Mip-aware importer required.',
              details: <String, Object?>{
                'extension': 'KHR_texture_basisu',
                'status': 'mipAwareImporterRequired',
                'limitation': 'authoredMipImporter',
                'required': true,
              },
            ),
          ],
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(sourceBytes, debugName: 'authored-mips.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes.single, same(sourceBytes));
    expect(adapter.authoredMipPlans, hasLength(1));
    final upload = adapter.authoredMipPlans.single.uploads.single;
    expect(upload.imageIndex, 0);
    expect(upload.levels.map((level) => level.level), <int>[0, 1]);
    expect(upload.textureBindings.single.textureIndex, 0);
    expect(
      upload.textureBindings.single.targets.single.slot,
      FlutterSceneAuthoredMipMaterialSlot.baseColor,
    );
    expect(upload.textureBindings.single.targets.single.required, isTrue);
  });

  test('blocks required BasisU publication when decoded binding is missing',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final sourceBytes = _nativeBasisuMipMaterialGlb();
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(textureBasisu: true),
          ),
          topologyBytes: sourceBytes,
          decodedImages: <GlbDecodedBasisuImage>[
            GlbDecodedBasisuImage(
              imageIndex: 0,
              contentRole: 'color',
              levels: <GlbDecodedBasisuMipLevel>[
                GlbDecodedBasisuMipLevel(
                  level: 0,
                  width: 2,
                  height: 2,
                  rgbaBytes: Uint8List(16),
                ),
                GlbDecodedBasisuMipLevel(
                  level: 1,
                  width: 1,
                  height: 1,
                  rgbaBytes: Uint8List(4),
                ),
              ],
              textureBindings: const <GlbDecodedBasisuTextureBinding>[],
            ),
          ],
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(sourceBytes, debugName: 'missing-mip-binding.glb'),
    );

    expect(result.isSuccess, isFalse);
    expect(
      result.diagnostic?.details['limitation'],
      'authoredMipBindingPlanSchema',
    );
    expect(adapter.authoredMipPlans, isEmpty);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('plans one native nonColor upload across normal and occlusion slots',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final sourceBytes = _nativeBasisuSharedNonColorMipMaterialGlb();
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(textureBasisu: true),
          ),
          topologyBytes: sourceBytes,
          decodedImages: <GlbDecodedBasisuImage>[
            GlbDecodedBasisuImage(
              imageIndex: 0,
              contentRole: 'nonColor',
              levels: <GlbDecodedBasisuMipLevel>[
                GlbDecodedBasisuMipLevel(
                  level: 0,
                  width: 2,
                  height: 2,
                  rgbaBytes: Uint8List(16),
                ),
                GlbDecodedBasisuMipLevel(
                  level: 1,
                  width: 1,
                  height: 1,
                  rgbaBytes: Uint8List(4),
                ),
              ],
              textureBindings: const <GlbDecodedBasisuTextureBinding>[
                GlbDecodedBasisuTextureBinding(
                  textureIndex: 0,
                  sampler: GlbBasisuSamplerIntent(
                    magFilter: 9729,
                    minFilter: 9987,
                    wrapS: 10497,
                    wrapT: 10497,
                  ),
                ),
                GlbDecodedBasisuTextureBinding(
                  textureIndex: 1,
                  sampler: GlbBasisuSamplerIntent(
                    magFilter: 9728,
                    minFilter: 9984,
                    wrapS: 33071,
                    wrapT: 33648,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(sourceBytes, debugName: 'shared-noncolor-mips.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    final plan = adapter.authoredMipPlans.single;
    expect(plan.uploads, hasLength(1));
    expect(plan.uploads.single.textureBindings, hasLength(2));
    expect(
      plan.uploads.single.textureBindings
          .expand((binding) => binding.targets)
          .map((target) => target.slot),
      containsAll(<FlutterSceneAuthoredMipMaterialSlot>[
        FlutterSceneAuthoredMipMaterialSlot.normal,
        FlutterSceneAuthoredMipMaterialSlot.occlusion,
      ]),
    );
  });

  test('uses Draco-rewritten topology for mixed authored-mip publication',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final compressedBytes = _nativeMixedDracoBasisuMipGlb();
    final topologyBytes = _nativeBasisuMipMaterialGlb();
    final decodedImages = <GlbDecodedBasisuImage>[
      GlbDecodedBasisuImage(
        imageIndex: 0,
        contentRole: 'color',
        levels: <GlbDecodedBasisuMipLevel>[
          GlbDecodedBasisuMipLevel(
            level: 0,
            width: 2,
            height: 2,
            rgbaBytes: Uint8List.fromList(List<int>.filled(16, 1)),
          ),
          GlbDecodedBasisuMipLevel(
            level: 1,
            width: 1,
            height: 1,
            rgbaBytes: Uint8List.fromList(List<int>.filled(4, 2)),
          ),
        ],
        textureBindings: const <GlbDecodedBasisuTextureBinding>[
          GlbDecodedBasisuTextureBinding(
            textureIndex: 0,
            sampler: GlbBasisuSamplerIntent(
              magFilter: 9729,
              minFilter: 9987,
              wrapS: 10497,
              wrapT: 10497,
            ),
          ),
        ],
      ),
    ];
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(
              dracoMeshCompression: true,
              textureBasisu: true,
            ),
          ),
          topologyBytes: topologyBytes,
          topologyOutputAccounting:
              GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
          decodedImages: decodedImages,
          decodeDiagnostics: const <ViewerDiagnostic>[
            ViewerDiagnostic(
              code: ViewerDiagnosticCode.unsupportedModelFeature,
              message: 'Mip-aware importer required.',
              details: <String, Object?>{
                'extension': 'KHR_texture_basisu',
                'status': 'mipAwareImporterRequired',
                'required': true,
              },
            ),
          ],
        ),
      ),
    );

    final result = await loader.load(
      ModelSource.bytes(compressedBytes, debugName: 'mixed-authored-mips.glb'),
    );

    expect(result.isSuccess, isTrue, reason: result.diagnostic?.toString());
    expect(adapter.loadedBytes.single, same(topologyBytes));
    expect(adapter.loadedBytes.single, isNot(same(compressedBytes)));
    expect(adapter.authoredMipPlans, hasLength(1));
  });

  test('cancelled authored-mip replacement cannot publish and fresh load works',
      () async {
    final gate = Completer<void>();
    final adapter = FakeFlutterSceneAdapter(
      loadGates: <String, Completer<void>>{'cancel-mips.glb': gate},
    );
    final sourceBytes = _nativeBasisuMipMaterialGlb();
    final decodedImages = <GlbDecodedBasisuImage>[
      GlbDecodedBasisuImage(
        imageIndex: 0,
        contentRole: 'color',
        levels: <GlbDecodedBasisuMipLevel>[
          GlbDecodedBasisuMipLevel(
            level: 0,
            width: 2,
            height: 2,
            rgbaBytes: Uint8List.fromList(List<int>.filled(16, 1)),
          ),
          GlbDecodedBasisuMipLevel(
            level: 1,
            width: 1,
            height: 1,
            rgbaBytes: Uint8List.fromList(List<int>.filled(4, 2)),
          ),
        ],
        textureBindings: const <GlbDecodedBasisuTextureBinding>[
          GlbDecodedBasisuTextureBinding(
            textureIndex: 0,
            sampler: GlbBasisuSamplerIntent(
              magFilter: 9729,
              minFilter: 9987,
              wrapS: 10497,
              wrapT: 10497,
            ),
          ),
        ],
      ),
    ];
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(
        nativeDecoderProbe: FakeNativeDecoderProbe(
          const GlbNativeDecoderAvailability(
            capabilities: GlbDecoderCapabilities(textureBasisu: true),
          ),
          topologyBytes: sourceBytes,
          decodedImages: decodedImages,
          decodeDiagnostics: <ViewerDiagnostic>[
            const ViewerDiagnostic(
              code: ViewerDiagnosticCode.unsupportedModelFeature,
              message: 'Mip-aware importer required.',
              details: <String, Object?>{
                'extension': 'KHR_texture_basisu',
                'status': 'mipAwareImporterRequired',
                'required': true,
              },
            ),
          ],
        ),
      ),
    );
    final cancellation = ModelLoadCancellationController();

    final cancelledLoad = loader.load(
      ModelSource.bytes(sourceBytes, debugName: 'cancel-mips.glb'),
      cancellationToken: cancellation.token,
    );
    await adapter.waitForLoad('cancel-mips.glb');
    cancellation.cancel('replacement-superseded');
    gate.complete();
    final cancelledResult = await cancelledLoad;

    expect(cancelledResult.isSuccess, isFalse);
    expect(
      cancelledResult.diagnostic!.code,
      ViewerDiagnosticCode.modelLoadCancelled,
    );
    expect(adapter.authoredMipPlans, isEmpty);
    expect(adapter.loadedBytes, isEmpty);

    final fresh = ModelLoadCancellationController();
    final freshResult = await loader.load(
      ModelSource.bytes(sourceBytes, debugName: 'fresh-mips.glb'),
      cancellationToken: fresh.token,
    );
    expect(freshResult.isSuccess, isTrue);
    expect(adapter.authoredMipPlans, hasLength(1));
    expect(adapter.loadedBytes, hasLength(1));
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

  test('asset cancellation wins while load is pending and ignores a late value',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final assetBundle = DelayedAssetBundle();
    final loader = ModelLoader(adapter: adapter, assetBundle: assetBundle);
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      const ModelSource.asset('assets/delayed.glb'),
      cancellationToken: cancellation.token,
    );
    await assetBundle.loadStarted.future;
    expect(cancellation.cancel('asset-dismissed'), isTrue);
    final result = await load.timeout(const Duration(seconds: 1));

    assetBundle.complete(Uint8List.fromList(<int>[1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(result.diagnostic?.details['stage'], 'sourceAcquisition');
    expect(adapter.loadedBytes, isEmpty);
  });

  test('asset cancellation ignores a late source error', () async {
    final adapter = FakeFlutterSceneAdapter();
    final assetBundle = DelayedAssetBundle();
    final loader = ModelLoader(adapter: adapter, assetBundle: assetBundle);
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      const ModelSource.asset('assets/failing-late.glb'),
      cancellationToken: cancellation.token,
    );
    await assetBundle.loadStarted.future;
    expect(cancellation.cancel('asset-dismissed'), isTrue);
    final result = await load.timeout(const Duration(seconds: 1));

    assetBundle.fail(StateError('late asset failure'));
    await Future<void>.delayed(Duration.zero);

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(adapter.loadedBytes, isEmpty);
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

  test(
      'network cancellation aborts a pending send without closing shared client',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final httpClient = PendingSendHttpClient();
    final loader = ModelLoader(adapter: adapter, httpClient: httpClient);
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      ModelSource.network(Uri.parse('https://models.example/pending.glb')),
      cancellationToken: cancellation.token,
    );
    final firstRequest = await httpClient.firstRequest.future;
    var abortObserved = false;
    if (firstRequest case http.AbortableRequest(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) => abortObserved = true));
    }

    expect(cancellation.cancel('network-dismissed'), isTrue);
    await Future<void>.delayed(Duration.zero);
    httpClient.completeFirstResponse(<int>[1, 2, 3]);
    final result = await load;
    await Future<void>.delayed(Duration.zero);

    expect(firstRequest, isA<http.AbortableRequest>());
    expect(abortObserved, isTrue);
    expect(httpClient.firstResponseStreamCancelled.isCompleted, isTrue);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(adapter.loadedBytes, isEmpty);
    expect(httpClient.closeCalls, 0);

    final freshResult = await loader.load(
      ModelSource.network(Uri.parse('https://models.example/fresh.glb')),
    );
    expect(freshResult.isSuccess, isTrue);
    expect(adapter.debugNames, <String?>['https://models.example/fresh.glb']);
    expect(httpClient.closeCalls, 0);
    await httpClient.closeFirstResponseStream();
  });

  test('network cancellation cancels only the pending response subscription',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final httpClient = PendingResponseStreamHttpClient();
    final loader = ModelLoader(adapter: adapter, httpClient: httpClient);
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      ModelSource.network(Uri.parse('https://models.example/streaming.glb')),
      cancellationToken: cancellation.token,
    );
    final firstRequest = await httpClient.firstRequest.future;
    await httpClient.firstStreamListened.future;

    expect(cancellation.cancel('stream-dismissed'), isTrue);
    final result = await load;
    await Future<void>.delayed(Duration.zero);

    expect(firstRequest, isA<http.AbortableRequest>());
    expect(httpClient.firstStreamCancelled.isCompleted, isTrue);
    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(adapter.loadedBytes, isEmpty);
    expect(httpClient.closeCalls, 0);

    final freshResult = await loader.load(
      ModelSource.network(Uri.parse('https://models.example/fresh.glb')),
    );
    expect(freshResult.isSuccess, isTrue);
    expect(adapter.debugNames, <String?>['https://models.example/fresh.glb']);
    expect(httpClient.closeCalls, 0);
    await httpClient.closeFirstStream();
  });

  test(
      'response cleanup failure cannot replace cancellation or escape asynchronously',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final httpClient = FailingCleanupHttpClient();
    final loader = ModelLoader(adapter: adapter, httpClient: httpClient);
    final cancellation = ModelLoadCancellationController();
    ModelLoadResult? cancelledResult;
    ModelLoadResult? freshResult;

    final asyncErrors = await captureAsyncErrors(() async {
      final load = loader.load(
        ModelSource.network(
          Uri.parse('https://models.example/failing-cleanup.glb'),
        ),
        cancellationToken: cancellation.token,
      );
      await httpClient.firstStreamListened.future;
      cancellation.cancel('cleanup-failed');
      cancelledResult = await load;
      httpClient.emitLateStreamError(StateError('late stream error'));
      await Future<void>.delayed(Duration.zero);

      freshResult = await loader.load(
        ModelSource.network(Uri.parse('https://models.example/fresh.glb')),
      );
      await httpClient.closeFirstStream();
    });

    expect(asyncErrors, isEmpty);
    expect(cancelledResult?.diagnostic?.code,
        ViewerDiagnosticCode.modelLoadCancelled);
    expect(freshResult?.isSuccess, isTrue);
    expect(httpClient.closeCalls, 0);
    expect(adapter.debugNames, <String?>['https://models.example/fresh.glb']);
  });

  test('late response cleanup failure is contained after cancellation',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final httpClient = FailingCleanupHttpClient(pendingSend: true);
    final loader = ModelLoader(adapter: adapter, httpClient: httpClient);
    final cancellation = ModelLoadCancellationController();
    ModelLoadResult? result;

    final asyncErrors = await captureAsyncErrors(() async {
      final load = loader.load(
        ModelSource.network(
          Uri.parse('https://models.example/late-response.glb'),
        ),
        cancellationToken: cancellation.token,
      );
      await httpClient.firstRequest.future;
      cancellation.cancel('late-response');
      result = await load;
      httpClient.completeFirstResponse();
      await httpClient.firstStreamCancelled.future;
      await Future<void>.delayed(Duration.zero);
      await httpClient.closeFirstStream();
    });

    expect(asyncErrors, isEmpty);
    expect(result?.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(adapter.loadedBytes, isEmpty);
    expect(httpClient.closeCalls, 0);
  });

  test('non-success HTTP status survives response cleanup failure', () async {
    final httpClient = FailingCleanupHttpClient(statusCode: 503);
    final loader = ModelLoader(
      adapter: FakeFlutterSceneAdapter(),
      httpClient: httpClient,
      options: const ModelLoaderOptions(timeout: Duration(milliseconds: 30)),
    );
    ModelLoadResult? result;

    final asyncErrors = await captureAsyncErrors(() async {
      result = await loader.load(
        ModelSource.network(
            Uri.parse('https://models.example/unavailable.glb')),
      );
      await httpClient.closeFirstStream();
    });

    expect(asyncErrors, isEmpty);
    expect(result?.diagnostic?.code, ViewerDiagnosticCode.networkFailure);
    expect(result?.diagnostic?.details['statusCode'], 503);
    expect(httpClient.closeCalls, 0);
  });

  test('response stream error survives automatic cleanup failure', () async {
    late FailingCleanupHttpClient httpClient;
    ModelLoadResult? result;

    final asyncErrors = await captureAsyncErrors(() async {
      httpClient = FailingCleanupHttpClient();
      final loader = ModelLoader(
        adapter: FakeFlutterSceneAdapter(),
        httpClient: httpClient,
      );
      final load = loader.load(
        ModelSource.network(
          Uri.parse('https://models.example/stream-error.glb'),
        ),
      );
      await httpClient.firstStreamListened.future;
      httpClient.emitLateStreamError(StateError('response stream failed'));
      result = await load;
      await Future<void>.delayed(Duration.zero);
      await httpClient.closeFirstStream();
    });

    expect(asyncErrors, isEmpty);
    expect(result?.diagnostic?.code, ViewerDiagnosticCode.networkFailure);
    expect(httpClient.closeCalls, 0);
  });

  test('late send error after cancellation is ignored without closing client',
      () async {
    final cancellation = ModelLoadCancellationController();
    late PendingSendErrorHttpClient httpClient;
    ModelLoadResult? cancelledResult;
    ModelLoadResult? freshResult;

    final asyncErrors = await captureAsyncErrors(() async {
      httpClient = PendingSendErrorHttpClient();
      final loader = ModelLoader(
        adapter: FakeFlutterSceneAdapter(),
        httpClient: httpClient,
      );
      final load = loader.load(
        ModelSource.network(
          Uri.parse('https://models.example/late-send-error.glb'),
        ),
        cancellationToken: cancellation.token,
      );
      await httpClient.firstRequest.future;
      cancellation.cancel('late-send-error');
      cancelledResult = await load;
      httpClient.failFirstSend(StateError('late send error'));
      await Future<void>.delayed(Duration.zero);
      freshResult = await loader.load(
        ModelSource.network(Uri.parse('https://models.example/fresh.glb')),
      );
    });

    expect(asyncErrors, isEmpty);
    expect(cancelledResult?.diagnostic?.code,
        ViewerDiagnosticCode.modelLoadCancelled);
    expect(freshResult?.isSuccess, isTrue);
    expect(httpClient.closeCalls, 0);
  });

  test('cancellation after native availability cannot dispatch native decode',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final probe = DelayedNativeDecoderProbe(delayAvailability: true);
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(nativeDecoderProbe: probe),
    );
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      ModelSource.bytes(
        _nativeDracoComponentGlb(),
        debugName: 'availability-boundary.glb',
      ),
      cancellationToken: cancellation.token,
    );
    await probe.availabilityStarted.future;
    expect(cancellation.cancel('availability-dismissed'), isTrue);
    probe.completeAvailability();
    final result = await load;

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(probe.decodeCalls, 0);
    expect(result.authoredCoreMaterialPatches, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('cancellation after native decode cannot reach adapter or patches',
      () async {
    final adapter = FakeFlutterSceneAdapter();
    final decodedBytes = _glb(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
    });
    final probe = DelayedNativeDecoderProbe(
      delayDecode: true,
      decodedBytes: decodedBytes,
    );
    final loader = ModelLoader(
      adapter: adapter,
      options: ModelLoaderOptions(nativeDecoderProbe: probe),
    );
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      ModelSource.bytes(
        _nativeDracoComponentGlb(),
        debugName: 'decode-boundary.glb',
      ),
      cancellationToken: cancellation.token,
    );
    await probe.decodeStarted.future;
    expect(cancellation.cancel('decode-dismissed'), isTrue);
    probe.completeDecode();
    final result = await load;

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
    expect(probe.decodeCalls, 1);
    expect(result.authoredCoreMaterialPatches, isEmpty);
    expect(result.authoredExtensionMaterialPatches, isEmpty);
    expect(adapter.loadedBytes, isEmpty);
  });

  test('caller cancellation wins when observed before source timeout',
      () async {
    final assetBundle = DelayedAssetBundle();
    final loader = ModelLoader(
      adapter: FakeFlutterSceneAdapter(),
      assetBundle: assetBundle,
      options: const ModelLoaderOptions(timeout: Duration(milliseconds: 40)),
    );
    final cancellation = ModelLoadCancellationController();

    final load = loader.load(
      const ModelSource.asset('assets/cancel-first.glb'),
      cancellationToken: cancellation.token,
    );
    await assetBundle.loadStarted.future;
    expect(cancellation.cancel('cancel-first'), isTrue);
    final result = await load;
    assetBundle.complete(Uint8List.fromList(<int>[1]));

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadCancelled);
  });

  test('source timeout wins when observed before caller cancellation',
      () async {
    final assetBundle = DelayedAssetBundle();
    final loader = ModelLoader(
      adapter: FakeFlutterSceneAdapter(),
      assetBundle: assetBundle,
      options: const ModelLoaderOptions(timeout: Duration(milliseconds: 5)),
    );
    final cancellation = ModelLoadCancellationController();

    final result = await loader.load(
      const ModelSource.asset('assets/timeout-first.glb'),
      cancellationToken: cancellation.token,
    );
    expect(cancellation.cancel('too-late'), isTrue);
    assetBundle.fail(StateError('ignored after timeout'));

    expect(result.diagnostic?.code, ViewerDiagnosticCode.modelLoadTimeout);
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

flutter_scene_gltf.GltfMaterialSheen _pinnedParserSheen(Uint8List bytes) {
  final container = flutter_scene_gltf.parseGlb(bytes);
  final document = flutter_scene_gltf.parseGltfJson(container.json);
  return document.materials.single.sheen!;
}

Uint8List _sheenFixture({
  required Object? sheen,
  bool required = false,
  String? siblingExtension,
  bool duplicateFabricPath = false,
}) {
  return _glb(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>[
      'KHR_materials_sheen',
      if (siblingExtension != null) siblingExtension,
    ],
    if (required) 'extensionsRequired': <Object?>['KHR_materials_sheen'],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0, if (duplicateFabricPath) 1]
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'Fabric', 'mesh': 0},
      if (duplicateFabricPath) <String, Object?>{'name': 'Fabric', 'mesh': 0},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
            'material': 0,
          },
        ],
      },
    ],
    'materials': <Object?>[
      <String, Object?>{
        'pbrMetallicRoughness': <String, Object?>{
          'baseColorFactor': <Object?>[0.1, 0.2, 0.3, 1],
        },
        'extensions': <String, Object?>{
          'KHR_materials_sheen': sheen,
          if (siblingExtension != null) siblingExtension: <String, Object?>{},
        },
      },
    ],
  });
}

Uint8List _authoredUv1SheenTextureFixture({
  bool duplicateFabricPath = false,
  int texCoord = 1,
  bool includeSelectedTexCoord = true,
  List<String>? nodeNames,
  List<List<int>>? sceneNodeIndices,
  bool includeDefaultScene = true,
}) {
  final textureBytes = Uint8List.fromList(<int>[1, 2, 3]);
  final effectiveNodeNames =
      nodeNames ?? <String>['Fabric', if (duplicateFabricPath) 'Fabric'];
  final effectiveSceneNodeIndices = sceneNodeIndices ??
      <List<int>>[
        <int>[
          for (var index = 0; index < effectiveNodeNames.length; index += 1)
            index,
        ],
      ];
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_materials_sheen'],
      if (includeDefaultScene) 'scene': 0,
      'scenes': <Object?>[
        for (final indices in effectiveSceneNodeIndices)
          <String, Object?>{
            'nodes': <Object?>[...indices]
          },
      ],
      'nodes': <Object?>[
        for (final name in effectiveNodeNames)
          <String, Object?>{'name': name, 'mesh': 0},
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{
                'POSITION': 0,
                if (includeSelectedTexCoord) 'TEXCOORD_$texCoord': 1,
              },
              'material': 0,
            },
          ],
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_sheen': <String, Object?>{
              'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
              'sheenColorTexture': <String, Object?>{
                'index': 0,
                'texCoord': texCoord,
              },
            },
          },
        },
      ],
      'textures': <Object?>[
        <String, Object?>{'source': 0},
      ],
      'images': <Object?>[
        <String, Object?>{
          'mimeType': 'image/png',
          'bufferView': 0,
        },
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteLength': textureBytes.length,
        },
      ],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': textureBytes.length},
      ],
    },
    textureBytes,
  );
}

Uint8List _compactedRuntimeSheenFallbackFixture() {
  return _glb(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>[
      'KHR_materials_sheen',
      'KHR_materials_pbrSpecularGlossiness',
    ],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'Fabric', 'mesh': 0},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'mode': 1,
            'attributes': <String, Object?>{'POSITION': 0},
            'material': 0,
          },
          <String, Object?>{
            'mode': 4,
            'attributes': <String, Object?>{'POSITION': 0},
            'material': 1,
          },
        ],
      },
    ],
    'materials': <Object?>[
      <String, Object?>{},
      <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_materials_sheen': <String, Object?>{
            'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
            'sheenRoughnessFactor': 0.6,
          },
          'KHR_materials_pbrSpecularGlossiness': <String, Object?>{},
        },
      },
    ],
  });
}

Uint8List _authoredDataUriSheenTextureFixture() {
  return _glb(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>['KHR_materials_sheen'],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'Fabric', 'mesh': 0},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{
              'POSITION': 0,
              'TEXCOORD_0': 1,
            },
            'material': 0,
          },
        ],
      },
    ],
    'materials': <Object?>[
      <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_materials_sheen': <String, Object?>{
            'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
            'sheenColorTexture': <String, Object?>{'index': 0},
          },
        },
      },
    ],
    'textures': <Object?>[
      <String, Object?>{'source': 0},
    ],
    'images': <Object?>[
      <String, Object?>{
        'uri': 'data:image/png;base64,iVBORw0KGgo=',
      },
    ],
  });
}

Uint8List _authoredSheenTextureEdgeFixture({
  Object? sampler,
  Object? textureIndex = 0,
  bool includeTextureIndex = true,
}) {
  final textureBytes = Uint8List.fromList(<int>[1, 2, 3]);
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_materials_sheen'],
      'scene': 0,
      'scenes': <Object?>[
        <String, Object?>{
          'nodes': <Object?>[0],
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{'name': 'Fabric', 'mesh': 0},
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{
                'POSITION': 0,
                'TEXCOORD_0': 1,
              },
              'material': 0,
            },
          ],
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_sheen': <String, Object?>{
              'sheenColorFactor': <Object?>[0.2, 0.4, 0.8],
              'sheenColorTexture': <String, Object?>{
                if (includeTextureIndex) 'index': textureIndex,
              },
            },
          },
        },
      ],
      'textures': <Object?>[
        <String, Object?>{
          'source': 0,
          if (sampler != null) 'sampler': sampler,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteLength': textureBytes.length,
        },
      ],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': textureBytes.length},
      ],
      'samplers': <Object?>[<String, Object?>{}],
    },
    textureBytes,
  );
}

Uint8List _twoSheenMaterialFixture({
  bool firstHasClearcoat = false,
  bool required = false,
}) {
  return _glb(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'extensionsUsed': <Object?>[
      'KHR_materials_sheen',
      if (firstHasClearcoat) 'KHR_materials_clearcoat',
    ],
    if (required) 'extensionsRequired': <Object?>['KHR_materials_sheen'],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0, 1],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'IncompatibleFabric', 'mesh': 0},
      <String, Object?>{'name': 'ValidFabric', 'mesh': 1},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
            'material': 0,
          },
        ],
      },
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
            'material': 1,
          },
        ],
      },
    ],
    'materials': <Object?>[
      <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_materials_sheen': <String, Object?>{
            'sheenRoughnessFactor': 0.3,
          },
          if (firstHasClearcoat)
            'KHR_materials_clearcoat': <String, Object?>{
              'clearcoatFactor': 0.5,
            },
        },
      },
      <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_materials_sheen': <String, Object?>{
            'sheenRoughnessFactor': 0.7,
          },
        },
      },
    ],
  });
}

final class _NonPreflightFlutterSceneAdapter implements FlutterSceneAdapter {
  final List<Set<PartAddress>> authoredSheenCoreFallbackPlans =
      <Set<PartAddress>>[];
  final List<bool> authoredSheenGlobalCoreFallbackPlans = <bool>[];

  @override
  AdapterNodeSnapshot? get nodeSnapshot => null;

  @override
  AdapterRenderScene? get renderScene => null;

  @override
  AdapterModelBounds? get modelBounds => null;

  @override
  AdapterModelStats? get modelStats => null;

  @override
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
    Set<PartAddress> authoredSheenCoreFallbacks = const <PartAddress>{},
    bool authoredSheenGlobalCoreFallback = false,
    bool Function()? tryAcceptPublication,
  }) async {
    authoredSheenCoreFallbackPlans.add(
      Set<PartAddress>.unmodifiable(authoredSheenCoreFallbacks),
    );
    authoredSheenGlobalCoreFallbackPlans.add(
      authoredSheenGlobalCoreFallback,
    );
  }

  @override
  Future<List<ViewerDiagnostic>> configureEnvironment(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> applyMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  ) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<PartAddress?> pickPart({
    required Offset localPosition,
    required Size viewportSize,
    required RenderCameraFrame camera,
  }) async =>
      null;

  @override
  List<ViewerDiagnostic> collectDiagnostics() => const <ViewerDiagnostic>[];
}

final class FakeFlutterSceneAdapter
    implements
        FlutterSceneAdapter,
        FlutterSceneAuthoredMipBindingAdapter,
        FlutterSceneAuthoredMaterialPreflightAdapter {
  FakeFlutterSceneAdapter({
    this.snapshot,
    this.modelStats,
    this.loadGates = const <String, Completer<void>>{},
    this.authoredMaterialPreflightDiagnostic,
  });

  final List<Uint8List> loadedBytes = <Uint8List>[];
  final List<String?> debugNames = <String?>[];
  final List<MaterialShadingPolicy> materialShadingPolicies =
      <MaterialShadingPolicy>[];
  final List<FlutterSceneAuthoredMipBindingPlan> authoredMipPlans =
      <FlutterSceneAuthoredMipBindingPlan>[];
  final List<MaterialPatch> authoredMaterialPreflightPatches =
      <MaterialPatch>[];
  final List<Set<PartAddress>> authoredSheenCoreFallbackPlans =
      <Set<PartAddress>>[];
  final List<bool> authoredSheenGlobalCoreFallbackPlans = <bool>[];
  final AdapterNodeSnapshot? snapshot;
  final Map<String, Completer<void>> loadGates;
  final Map<String, Completer<void>> _loadStarted = <String, Completer<void>>{};
  final FutureOr<ViewerDiagnostic?> Function(PartAddress address)?
      authoredMaterialPreflightDiagnostic;
  final Map<String, bool Function()?> receivedPublicationCallbacks =
      <String, bool Function()?>{};
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
    Set<PartAddress> authoredSheenCoreFallbacks = const <PartAddress>{},
    bool authoredSheenGlobalCoreFallback = false,
    bool Function()? tryAcceptPublication,
  }) async {
    if (debugName != null) {
      receivedPublicationCallbacks[debugName] = tryAcceptPublication;
      (_loadStarted[debugName] ??= Completer<void>()).complete();
      await loadGates[debugName]?.future;
    }
    if (tryAcceptPublication?.call() == false) {
      throw const FlutterSceneAdapterLoadCancelledException();
    }
    loadedBytes.add(bytes);
    debugNames.add(debugName);
    materialShadingPolicies.add(materialShadingPolicy);
    authoredSheenCoreFallbackPlans.add(
      Set<PartAddress>.unmodifiable(authoredSheenCoreFallbacks),
    );
    authoredSheenGlobalCoreFallbackPlans.add(
      authoredSheenGlobalCoreFallback,
    );
  }

  @override
  Future<void> loadGlbBytesWithAuthoredMips(
    Uint8List bytes, {
    required FlutterSceneAuthoredMipBindingPlan bindingPlan,
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
    Set<PartAddress> authoredSheenCoreFallbacks = const <PartAddress>{},
    bool authoredSheenGlobalCoreFallback = false,
    bool Function()? isLoadCancelled,
    bool Function()? tryAcceptPublication,
  }) async {
    if (debugName != null) {
      receivedPublicationCallbacks[debugName] = tryAcceptPublication;
      (_loadStarted[debugName] ??= Completer<void>()).complete();
      await loadGates[debugName]?.future;
    }
    if ((isLoadCancelled?.call() ?? false) ||
        tryAcceptPublication?.call() == false) {
      throw const FlutterSceneAdapterLoadCancelledException();
    }
    authoredMipPlans.add(bindingPlan);
    loadedBytes.add(bytes);
    debugNames.add(debugName);
    materialShadingPolicies.add(materialShadingPolicy);
    authoredSheenCoreFallbackPlans.add(
      Set<PartAddress>.unmodifiable(authoredSheenCoreFallbacks),
    );
    authoredSheenGlobalCoreFallbackPlans.add(
      authoredSheenGlobalCoreFallback,
    );
  }

  Future<void> waitForLoad(String debugName) =>
      (_loadStarted[debugName] ??= Completer<void>()).future;

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
  Future<ViewerDiagnostic?> preflightAuthoredMaterialPatch({
    required PartAddress address,
    required MaterialPatch patch,
  }) async {
    authoredMaterialPreflightPatches.add(patch);
    final callback = authoredMaterialPreflightDiagnostic;
    return callback == null ? null : await callback(address);
  }

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

final class _RendererNativeSheenPolicyAdapter extends FakeFlutterSceneAdapter {
  _RendererNativeSheenPolicyAdapter._(this._root, this._materialNodes);

  factory _RendererNativeSheenPolicyAdapter.singleFabric() =>
      _RendererNativeSheenPolicyAdapter.named(const <String>['Fabric']);

  factory _RendererNativeSheenPolicyAdapter.duplicateFabricPaths() =>
      _RendererNativeSheenPolicyAdapter.named(
        const <String>['Fabric', 'Fabric'],
      );

  factory _RendererNativeSheenPolicyAdapter.named(List<String> names) {
    final nodes = <flutter_scene.Node>[
      for (final name in names) _materialNode(name),
    ];
    final root = nodes.length == 1
        ? nodes.single
        : (flutter_scene.Node(name: 'ImportedScene')..addAll(nodes));
    return _RendererNativeSheenPolicyAdapter._(
      root,
      nodes,
    );
  }

  final flutter_scene.Node _root;
  final List<flutter_scene.Node> _materialNodes;

  List<flutter_scene.PhysicallyBasedMaterial> get liveMaterials =>
      <flutter_scene.PhysicallyBasedMaterial>[
        for (final node in _materialNodes)
          node.mesh!.primitives.single.material
              as flutter_scene.PhysicallyBasedMaterial,
      ];

  @override
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
    Set<PartAddress> authoredSheenCoreFallbacks = const <PartAddress>{},
    bool authoredSheenGlobalCoreFallback = false,
    bool Function()? tryAcceptPublication,
  }) async {
    await super.loadGlbBytes(
      bytes,
      debugName: debugName,
      materialShadingPolicy: materialShadingPolicy,
      authoredSheenCoreFallbacks: authoredSheenCoreFallbacks,
      authoredSheenGlobalCoreFallback: authoredSheenGlobalCoreFallback,
      tryAcceptPublication: tryAcceptPublication,
    );
    debugApplyRendererNativeSheenImportPolicy(
      _root,
      retainRendererNativeSheen: true,
      coreFallbackAddresses: authoredSheenCoreFallbacks,
      globalCoreFallback: authoredSheenGlobalCoreFallback,
    );
  }

  static flutter_scene.Node _materialNode(String name) {
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
      ..sheenRoughnessFactor = 0.6
      ..clearcoatFactor = 0.7;
    return flutter_scene.Node(
      name: name,
      mesh: flutter_scene.Mesh(_NonRenderingGeometry(), material),
    );
  }
}

final class _NonRenderingGeometry extends flutter_scene.Geometry {
  @override
  void bind(
    flutter_scene_internal_gpu.RenderPass pass,
    flutter_scene_internal_gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    flutter_scene_internal_gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Test geometry is not renderable.');
  }
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

final class DelayedAssetBundle extends CachingAssetBundle {
  final Completer<void> loadStarted = Completer<void>();
  final Completer<ByteData> _load = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) {
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    return _load.future;
  }

  void complete(Uint8List bytes) {
    if (!_load.isCompleted) {
      _load.complete(ByteData.sublistView(bytes));
    }
  }

  void fail(Object error) {
    if (!_load.isCompleted) {
      _load.completeError(error);
    }
  }
}

final class PendingSendHttpClient extends http.BaseClient {
  final Completer<http.BaseRequest> firstRequest =
      Completer<http.BaseRequest>();
  final Completer<http.StreamedResponse> _firstResponse =
      Completer<http.StreamedResponse>();
  final Completer<void> firstResponseStreamCancelled = Completer<void>();
  http.BaseRequest? _firstRequestValue;
  StreamController<List<int>>? _firstResponseStreamController;
  var requests = 0;
  var closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests += 1;
    if (requests == 1) {
      _firstRequestValue = request;
      firstRequest.complete(request);
      return _firstResponse.future;
    }
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(<int>[7, 8, 9]),
        200,
        request: request,
      ),
    );
  }

  void completeFirstResponse(List<int> bytes) {
    final streamController = StreamController<List<int>>(
      onCancel: () {
        if (!firstResponseStreamCancelled.isCompleted) {
          firstResponseStreamCancelled.complete();
        }
      },
    );
    _firstResponseStreamController = streamController;
    _firstResponse.complete(
      http.StreamedResponse(
        streamController.stream,
        200,
        request: _firstRequestValue,
      ),
    );
    streamController.add(bytes);
  }

  Future<void> closeFirstResponseStream() async {
    await _firstResponseStreamController?.close();
  }

  @override
  void close() {
    closeCalls += 1;
  }
}

final class PendingResponseStreamHttpClient extends http.BaseClient {
  PendingResponseStreamHttpClient() {
    _firstStreamController = StreamController<List<int>>(
      onListen: firstStreamListened.complete,
      onCancel: () {
        if (!firstStreamCancelled.isCompleted) {
          firstStreamCancelled.complete();
        }
      },
    );
  }

  final Completer<http.BaseRequest> firstRequest =
      Completer<http.BaseRequest>();
  final Completer<void> firstStreamListened = Completer<void>();
  final Completer<void> firstStreamCancelled = Completer<void>();
  late final StreamController<List<int>> _firstStreamController;
  var requests = 0;
  var closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests += 1;
    if (requests == 1) {
      firstRequest.complete(request);
      return http.StreamedResponse(
        _firstStreamController.stream,
        200,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(<int>[7, 8, 9]),
      200,
      request: request,
    );
  }

  Future<void> closeFirstStream() => _firstStreamController.close();

  @override
  void close() {
    closeCalls += 1;
  }
}

final class FailingCleanupHttpClient extends http.BaseClient {
  FailingCleanupHttpClient({
    this.pendingSend = false,
    this.statusCode = 200,
  }) {
    _firstStreamController = StreamController<List<int>>(
      onListen: () {
        if (!firstStreamListened.isCompleted) {
          firstStreamListened.complete();
        }
      },
      onCancel: () {
        if (!firstStreamCancelled.isCompleted) {
          firstStreamCancelled.complete();
        }
        return Future<void>.error(StateError('subscription cleanup failed'));
      },
    );
  }

  final bool pendingSend;
  final int statusCode;
  final Completer<http.BaseRequest> firstRequest =
      Completer<http.BaseRequest>();
  final Completer<void> firstStreamListened = Completer<void>();
  final Completer<void> firstStreamCancelled = Completer<void>();
  final Completer<http.StreamedResponse> _firstResponse =
      Completer<http.StreamedResponse>();
  late final StreamController<List<int>> _firstStreamController;
  http.BaseRequest? _firstRequestValue;
  var requests = 0;
  var closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests += 1;
    if (requests != 1) {
      return Future<http.StreamedResponse>.value(
        http.StreamedResponse(
          Stream<List<int>>.value(<int>[7, 8, 9]),
          200,
          request: request,
        ),
      );
    }
    _firstRequestValue = request;
    firstRequest.complete(request);
    if (pendingSend) {
      return _firstResponse.future;
    }
    return Future<http.StreamedResponse>.value(_firstStreamedResponse());
  }

  void completeFirstResponse() {
    _firstResponse.complete(_firstStreamedResponse());
  }

  http.StreamedResponse _firstStreamedResponse() => http.StreamedResponse(
        _firstStreamController.stream,
        statusCode,
        request: _firstRequestValue,
      );

  void emitLateStreamError(Object error) {
    _firstStreamController.addError(error);
  }

  Future<void> closeFirstStream() => _firstStreamController.close();

  @override
  void close() {
    closeCalls += 1;
  }
}

final class PendingSendErrorHttpClient extends http.BaseClient {
  final Completer<http.BaseRequest> firstRequest =
      Completer<http.BaseRequest>();
  final Completer<http.StreamedResponse> _firstResponse =
      Completer<http.StreamedResponse>();
  var requests = 0;
  var closeCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests += 1;
    if (requests == 1) {
      firstRequest.complete(request);
      return _firstResponse.future;
    }
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(<int>[7, 8, 9]),
        200,
        request: request,
      ),
    );
  }

  void failFirstSend(Object error) {
    _firstResponse.completeError(error);
  }

  @override
  void close() {
    closeCalls += 1;
  }
}

Future<List<Object>> captureAsyncErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final guarded = runZonedGuarded<Future<void>>(
    () async {
      await body();
      await Future<void>.delayed(Duration.zero);
    },
    (error, stackTrace) => errors.add(error),
  );
  await guarded;
  await Future<void>.delayed(Duration.zero);
  return errors;
}

final class DelayedNativeDecoderProbe implements GlbNativeDecoderProbe {
  DelayedNativeDecoderProbe({
    this.delayAvailability = false,
    this.delayDecode = false,
    Uint8List? decodedBytes,
  }) : decodedBytes = decodedBytes ?? Uint8List(0);

  final bool delayAvailability;
  final bool delayDecode;
  final Uint8List decodedBytes;
  final Completer<void> availabilityStarted = Completer<void>();
  final Completer<void> decodeStarted = Completer<void>();
  final Completer<void> _availabilityGate = Completer<void>();
  final Completer<void> _decodeGate = Completer<void>();
  var decodeCalls = 0;

  @override
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    if (!availabilityStarted.isCompleted) {
      availabilityStarted.complete();
    }
    if (delayAvailability) {
      await _availabilityGate.future;
    }
    return const GlbNativeDecoderAvailability(
      capabilities: GlbDecoderCapabilities(dracoMeshCompression: true),
    );
  }

  void completeAvailability() {
    if (!_availabilityGate.isCompleted) {
      _availabilityGate.complete();
    }
  }

  @override
  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    ModelLoadCancellationToken? cancellationToken,
    String? source,
  }) async {
    decodeCalls += 1;
    if (!decodeStarted.isCompleted) {
      decodeStarted.complete();
    }
    if (delayDecode) {
      await _decodeGate.future;
    }
    return GlbNativeDecodeResult(
      bytes: decodedBytes,
      outputAccounting: GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
    );
  }

  void completeDecode() {
    if (!_decodeGate.isCompleted) {
      _decodeGate.complete();
    }
  }
}

final class FakeNativeDecoderProbe implements GlbNativeDecoderProbe {
  const FakeNativeDecoderProbe(
    this.availability, {
    this.decodedBytes,
    this.topologyBytes,
    this.topologyOutputAccounting = GlbNativeDecodeOutputAccounting.none,
    this.decodedImages = const <GlbDecodedBasisuImage>[],
    this.decodeDiagnostics = const <ViewerDiagnostic>[],
  });

  final GlbNativeDecoderAvailability availability;
  final Uint8List? decodedBytes;
  final Uint8List? topologyBytes;
  final GlbNativeDecodeOutputAccounting topologyOutputAccounting;
  final List<GlbDecodedBasisuImage> decodedImages;
  final List<ViewerDiagnostic> decodeDiagnostics;

  @override
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    return availability;
  }

  @override
  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    ModelLoadCancellationToken? cancellationToken,
    String? source,
  }) async {
    return GlbNativeDecodeResult(
      bytes: decodedBytes,
      topologyBytes: topologyBytes,
      topologyOutputAccounting: topologyOutputAccounting,
      decodedBasisuImages: decodedImages,
      outputAccounting: decodedBytes == null
          ? GlbNativeDecodeOutputAccounting.none
          : GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
      diagnostics: decodeDiagnostics,
    );
  }
}

final class RecordingNativeDecoderProbe implements GlbNativeDecoderProbe {
  RecordingNativeDecoderProbe(this.decodedBytes);

  final Uint8List decodedBytes;
  GlbDecodeBudget? receivedBudget;
  GlbDecodeBudgetTracker? receivedTracker;
  int? trackerTotalDecodedBytesAtDecode;
  int? trackerNativeOutputBytesAtDecode;

  @override
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    return const GlbNativeDecoderAvailability(
      capabilities: GlbDecoderCapabilities(dracoMeshCompression: true),
    );
  }

  @override
  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    ModelLoadCancellationToken? cancellationToken,
    String? source,
  }) async {
    receivedBudget = budget;
    receivedTracker = budgetTracker;
    trackerTotalDecodedBytesAtDecode = budgetTracker.totalDecodedBytes;
    trackerNativeOutputBytesAtDecode = budgetTracker.nativeOutputBytes;
    return GlbNativeDecodeResult(
      bytes: decodedBytes,
      outputAccounting: GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
    );
  }
}

final class FixedNativeDecoderProbe implements GlbNativeDecoderProbe {
  const FixedNativeDecoderProbe(this.result);

  final GlbNativeDecodeResult result;

  @override
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    return const GlbNativeDecoderAvailability(
      capabilities: GlbDecoderCapabilities(dracoMeshCompression: true),
    );
  }

  @override
  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    ModelLoadCancellationToken? cancellationToken,
    String? source,
  }) async {
    return result;
  }
}

Uint8List _nativeDracoComponentGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'componentType': 5126,
          'count': 1,
          'type': 'VEC3',
        },
        <String, Object?>{
          'componentType': 5123,
          'count': 3,
          'type': 'SCALAR',
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
              'indices': 1,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _nativeBasisuComponentGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _nativeBasisuMipMaterialGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'samplers': <Object?>[
        <String, Object?>{
          'magFilter': 9729,
          'minFilter': 9987,
          'wrapS': 33071,
          'wrapT': 33648,
        },
      ],
      'textures': <Object?>[
        <String, Object?>{
          'sampler': 0,
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': 0},
          },
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{'material': 0},
          ],
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{'mesh': 0},
      ],
      'scenes': <Object?>[
        <String, Object?>{
          'nodes': <Object?>[0],
        },
      ],
      'scene': 0,
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _nativeBasisuSharedNonColorMipMaterialGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'samplers': <Object?>[
        <String, Object?>{
          'magFilter': 9729,
          'minFilter': 9987,
          'wrapS': 10497,
          'wrapT': 10497,
        },
        <String, Object?>{
          'magFilter': 9728,
          'minFilter': 9984,
          'wrapS': 33071,
          'wrapT': 33648,
        },
      ],
      'textures': <Object?>[
        for (var sampler = 0; sampler < 2; sampler += 1)
          <String, Object?>{
            'sampler': sampler,
            'extensions': <String, Object?>{
              'KHR_texture_basisu': <String, Object?>{'source': 0},
            },
          },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'normalTexture': <String, Object?>{'index': 0},
          'occlusionTexture': <String, Object?>{'index': 1},
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{'material': 0},
          ],
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{'mesh': 0},
      ],
      'scenes': <Object?>[
        <String, Object?>{
          'nodes': <Object?>[0],
        },
      ],
      'scene': 0,
    },
    Uint8List.fromList(<int>[1, 2, 3, 4]),
  );
}

Uint8List _nativeMixedDracoBasisuMipGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>[
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      ],
      'extensionsRequired': <Object?>[
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      ],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 4,
          'byteLength': 4,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': 0},
          },
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'material': 0,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 1,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
      'nodes': <Object?>[
        <String, Object?>{'mesh': 0},
      ],
      'scenes': <Object?>[
        <String, Object?>{
          'nodes': <Object?>[0],
        },
      ],
      'scene': 0,
    },
    Uint8List.fromList(<int>[9, 9, 9, 9, 8, 8, 8, 8]),
  );
}

Uint8List _float32Bytes(List<double> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setFloat32(index * 4, values[index], Endian.little);
  }
  return bytes;
}

Uint8List _uint16Bytes(List<int> values) {
  final bytes = Uint8List(values.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setUint16(index * 2, values[index], Endian.little);
  }
  return bytes;
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

Uint8List _glbWithBin(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final paddedBinLength = _align4(bin.length);
  final totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length;
      index < 20 + paddedJsonLength;
      index += 1) {
    bytes[index] = 0x20;
  }
  final binHeaderOffset = 20 + paddedJsonLength;
  data
    ..setUint32(binHeaderOffset, paddedBinLength, Endian.little)
    ..setUint32(binHeaderOffset + 4, 0x004E4942, Endian.little);
  bytes.setRange(binHeaderOffset + 8, binHeaderOffset + 8 + bin.length, bin);
  return bytes;
}

Uint8List _meshoptAttributeStream(List<int> values) {
  final byteStride = values.length;
  final bytes = Uint8List(1 + byteStride * 17 + 32);
  bytes[0] = 0xa0;
  var offset = 1;
  for (final value in values) {
    bytes[offset] = 0x03;
    bytes[offset + 1] = value * 2;
    offset += 17;
  }
  return bytes;
}

Uint8List _glbBufferViewBytes(Uint8List bytes, int bufferViewIndex) {
  final data = ByteData.sublistView(bytes);
  final jsonLength = data.getUint32(12, Endian.little);
  final json = jsonDecode(
    utf8.decode(bytes.sublist(20, 20 + jsonLength)),
  ) as Map<String, Object?>;
  final bufferViews = json['bufferViews'] as List<Object?>;
  final bufferView = bufferViews[bufferViewIndex] as Map<String, Object?>;
  final binHeaderOffset = 20 + jsonLength;
  final binOffset = binHeaderOffset + 8;
  final byteOffset = bufferView['byteOffset'] as int? ?? 0;
  final byteLength = bufferView['byteLength'] as int;
  return Uint8List.sublistView(
    bytes,
    binOffset + byteOffset,
    binOffset + byteOffset + byteLength,
  );
}

int _align4(int value) => (value + 3) & ~3;

Uint8List _pngBytes({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setRange(0, 8, const <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ]);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(8, 13)
    ..setUint32(12, 0x49484452)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}
