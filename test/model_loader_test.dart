import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' as flutter_scene;
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
import 'package:flutter_scene_viewer/src/material_shading_mode.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/model_source.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_scene_viewer/src/texture_source.dart';
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

final class FakeFlutterSceneAdapter
    implements FlutterSceneAdapter, FlutterSceneAuthoredMipBindingAdapter {
  FakeFlutterSceneAdapter({
    this.snapshot,
    this.modelStats,
    this.loadGates = const <String, Completer<void>>{},
  });

  final List<Uint8List> loadedBytes = <Uint8List>[];
  final List<String?> debugNames = <String?>[];
  final List<MaterialShadingPolicy> materialShadingPolicies =
      <MaterialShadingPolicy>[];
  final List<FlutterSceneAuthoredMipBindingPlan> authoredMipPlans =
      <FlutterSceneAuthoredMipBindingPlan>[];
  final AdapterNodeSnapshot? snapshot;
  final Map<String, Completer<void>> loadGates;
  final Map<String, Completer<void>> _loadStarted = <String, Completer<void>>{};
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
  }

  @override
  Future<void> loadGlbBytesWithAuthoredMips(
    Uint8List bytes, {
    required FlutterSceneAuthoredMipBindingPlan bindingPlan,
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
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
