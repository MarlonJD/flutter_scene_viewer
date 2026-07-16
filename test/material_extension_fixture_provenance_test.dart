import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'tools/material_extension_acceptance/manifest.json';
const _toolPath = 'tools/stage_material_extension_fixtures.py';
const _commit = '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf';
const _repository = <String, Object?>{
  'name': 'KhronosGroup/glTF-Sample-Assets',
  'commit': _commit,
  'commitUrl':
      'https://github.com/KhronosGroup/glTF-Sample-Assets/commit/$_commit',
};

const _expectedKhronosFixtures = <String, Map<String, Object?>>{
  'texture_transform_multi_test': <String, Object?>{
    'name': 'TextureTransformMultiTest',
    'features': <Object?>['KHR_texture_transform'],
    'sourcePath': 'Models/TextureTransformMultiTest/glTF-Binary/'
        'TextureTransformMultiTest.glb',
    'sourceSha256':
        '569aedb53822d5721e7e06af5983348683d4b2ffb1d469338ad4f02bf6a74911',
    'byteLength': 388264,
    'assetSpdx': 'CC-BY-4.0',
    'metadataSpdx': 'CC-BY-4.0',
    'licensePath': 'Models/TextureTransformMultiTest/LICENSE.md',
    'licenseSha256':
        '6ca5a443146e5012bdb86b20f23d591cbffec098ce32dbc7733705c32ad54e1f',
    'licenseByteLength': 719,
  },
  'specular_test': <String, Object?>{
    'name': 'SpecularTest',
    'features': <Object?>['KHR_materials_specular'],
    'sourcePath': 'Models/SpecularTest/glTF-Binary/SpecularTest.glb',
    'sourceSha256':
        'cf789c68c3ab4b74877da3c5992c612c213f9c901ed4fafbf9be362f434e48d9',
    'byteLength': 223376,
    'assetSpdx': 'CC-BY-4.0',
    'metadataSpdx': 'CC-BY-4.0',
    'licensePath': 'Models/SpecularTest/LICENSE.md',
    'licenseSha256':
        '720582df68ecd9818f27459b9aa502e07ec1e8307a63b464d726ec9dee2665e3',
    'licenseByteLength': 704,
  },
  'ior_test_grid': <String, Object?>{
    'name': 'IORTestGrid',
    'features': <Object?>['KHR_materials_ior'],
    'sourcePath': 'Models/IORTestGrid/glTF-Binary/IORTestGrid.glb',
    'sourceSha256':
        '863cf24d0e48892ec830a7c712e4eb8bf5c0fd6cc2ae2f34d213b216f0bd6c12',
    'byteLength': 2628524,
    'assetSpdx': 'CC0-1.0',
    'metadataSpdx': 'CC-BY-4.0',
    'licensePath': 'Models/IORTestGrid/LICENSE.md',
    'licenseSha256':
        'f82f11fb00c3b6386125483b75450cd47de2199017983eff7e5f8b9f21efa270',
    'licenseByteLength': 700,
  },
  'clearcoat_test': <String, Object?>{
    'name': 'ClearCoatTest',
    'features': <Object?>['KHR_materials_clearcoat'],
    'sourcePath': 'Models/ClearCoatTest/glTF-Binary/ClearCoatTest.glb',
    'sourceSha256':
        'c3a1cbe318cd043b937130af4eb83ec2ea0b03613387b1b7d769dfab4ac15948',
    'byteLength': 258048,
    'assetSpdx': 'CC-BY-4.0',
    'metadataSpdx': 'CC-BY-4.0',
    'licensePath': 'Models/ClearCoatTest/LICENSE.md',
    'licenseSha256':
        '4af69dbcddb15dda2711af88095c26b4d0672948dc81b6b02d7dcacb124ef8ae',
    'licenseByteLength': 719,
  },
  'attenuation_test': <String, Object?>{
    'name': 'AttenuationTest',
    'features': <Object?>[
      'KHR_materials_transmission',
      'KHR_materials_volume',
    ],
    'sourcePath': 'Models/AttenuationTest/glTF-Binary/AttenuationTest.glb',
    'sourceSha256':
        '7ca161b7f8a9e4b2ac1f7f75816b5848bb31f3b4c226c4cb731b487c8809b756',
    'byteLength': 57532,
    'assetSpdx': 'CC-BY-4.0',
    'metadataSpdx': 'CC-BY-4.0',
    'licensePath': 'Models/AttenuationTest/LICENSE.md',
    'licenseSha256':
        '0235f6ae8126cf61acc7e304224f21fe509993dd4e40a3c0202b88f06bc24779',
    'licenseByteLength': 707,
  },
};

void main() {
  test('material extension fixture provenance is immutable and honest',
      () async {
    final manifest = Map<String, Object?>.from(
      jsonDecode(File(_manifestPath).readAsStringSync()) as Map,
    );
    final provenance = Map<String, Object?>.from(
      manifest['fixtureProvenance']! as Map,
    );
    expect(
      provenance.keys,
      orderedEquals(<String>[
        'schemaVersion',
        'sourceRepository',
        'fetchToolPath',
        'scope',
        'evidence',
        'fixtures',
      ]),
    );
    expect(provenance['schemaVersion'], 1);
    expect(provenance['sourceRepository'], _repository);
    expect(provenance['fetchToolPath'], _toolPath);
    expect(
      provenance['scope'],
      'Source and license provenance only; no renderer, runtime, target, '
      'release, or production-readiness evidence.',
    );
    expect(provenance['evidence'], <String, Object?>{
      'fixtureProvenance': 'verified locally',
      'runtimeCapability': 'not established',
      'releaseMaturity': 'not established',
      'targetEvidence': <Object?>[
        <String, Object?>{'target': 'iOS Simulator', 'status': 'not run'},
        <String, Object?>{'target': 'physical iOS', 'status': 'not run'},
        <String, Object?>{'target': 'Android', 'status': 'not run'},
        <String, Object?>{'target': 'Web', 'status': 'not run'},
      ],
    });

    final fixtures =
        (provenance['fixtures']! as List<Object?>).cast<Map<String, Object?>>();
    expect(fixtures, hasLength(6));
    expect(
      fixtures.take(5).map((fixture) => fixture['id']),
      orderedEquals(_expectedKhronosFixtures.keys),
    );
    for (final fixture in fixtures.take(5)) {
      final id = fixture['id']! as String;
      final expected = _expectedKhronosFixtures[id]!;
      expect(fixture['name'], expected['name']);
      expect(fixture['features'], expected['features']);
      expect(fixture['sourceKind'], 'khronos-official');
      expect(fixture['sourceRepository'], _repository);
      expect(fixture['sourcePath'], expected['sourcePath']);
      expect(
        fixture['sourceUrl'],
        'https://raw.githubusercontent.com/KhronosGroup/'
        'glTF-Sample-Assets/$_commit/${expected['sourcePath']}',
      );
      expect(fixture['sourceSha256'], expected['sourceSha256']);
      expect(fixture['byteLength'], expected['byteLength']);
      expect(fixture['vendored'], isFalse);
      expect(fixture['localPath'], isNull);
      final license = Map<String, Object?>.from(fixture['license']! as Map);
      expect(license, <String, Object?>{
        'assetSpdx': expected['assetSpdx'],
        'metadataSpdx': expected['metadataSpdx'],
        'evidencePath': expected['licensePath'],
        'evidenceUrl': 'https://raw.githubusercontent.com/KhronosGroup/'
            'glTF-Sample-Assets/$_commit/${expected['licensePath']}',
        'evidenceSha256': expected['licenseSha256'],
        'evidenceByteLength': expected['licenseByteLength'],
      });
    }

    final a1b32 = fixtures.last;
    expect(a1b32, <String, Object?>{
      'id': 'a1b32',
      'name': 'A1B32',
      'features': <Object?>[
        'KHR_draco_mesh_compression',
        'KHR_materials_specular',
        'KHR_materials_ior',
      ],
      'sourceKind': 'user-authorized-local',
      'sourceOriginalFilename': 'A1B32.glb',
      'sourceUrl': null,
      'sourceSha256':
          'a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592',
      'byteLength': 2809824,
      'vendored': false,
      'localPath': null,
      'stagingPath': 'tools/out/material_extension_acceptance/A1B32.glb',
      'permission': <String, Object?>{
        'status': 'user-authorized',
        'authority': 'user',
        'scope': 'current Plan 014 repository-local use',
        'grantedFor': 'current Plan 014 task',
        'recordedOn': '2026-07-14',
        'userStatement':
            'User stated A1B32 may be used and has no license issue.',
        'redistribution': 'not established; asset is not vendored',
        'spdxLicense': 'not provided',
        'copyrightHolder': 'not provided',
      },
      'glbContract': <String, Object?>{
        'version': 2,
        'extensionsUsed': <Object?>[
          'KHR_draco_mesh_compression',
          'KHR_materials_specular',
          'KHR_materials_ior',
        ],
        'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
        'nodes': 1,
        'meshes': 1,
        'materials': 20,
      },
      'sourceValidation': <String, Object?>{
        'validator': 'gltf-validator@2.0.0-dev.3.10',
        'hostEvidence': 'verified locally',
        'errors': 0,
        'warnings': 6,
        'infos': 26,
        'hints': 0,
        'warningDetails': <Object?>[
          <String, Object?>{
            'severity': 1,
            'code': 'IMAGE_FEATURES_UNSUPPORTED',
            'message': 'Image contains unsupported features like non-default '
                'colorspace information, non-square pixels, or animation.',
            'pointer': '/images/7',
            'disposition':
                'Requires target and visual evaluation before A1B32 acceptance.',
          },
          <String, Object?>{
            'severity': 1,
            'code': 'IMAGE_FEATURES_UNSUPPORTED',
            'message': 'Image contains unsupported features like non-default '
                'colorspace information, non-square pixels, or animation.',
            'pointer': '/images/8',
            'disposition':
                'Requires target and visual evaluation before A1B32 acceptance.',
          },
          <String, Object?>{
            'severity': 1,
            'code': 'MESH_PRIMITIVE_GENERATED_TANGENT_SPACE',
            'message': 'Material requires a tangent space but the mesh '
                'primitive does not provide it. Runtime-generated tangent '
                'space may be non-portable across implementations.',
            'pointer': '/meshes/0/primitives/0/material',
            'disposition':
                'Generated tangent portability requires target and visual evaluation.',
          },
          <String, Object?>{
            'severity': 1,
            'code': 'MESH_PRIMITIVE_GENERATED_TANGENT_SPACE',
            'message': 'Material requires a tangent space but the mesh '
                'primitive does not provide it. Runtime-generated tangent '
                'space may be non-portable across implementations.',
            'pointer': '/meshes/0/primitives/1/material',
            'disposition':
                'Generated tangent portability requires target and visual evaluation.',
          },
          <String, Object?>{
            'severity': 1,
            'code': 'MESH_PRIMITIVE_GENERATED_TANGENT_SPACE',
            'message': 'Material requires a tangent space but the mesh '
                'primitive does not provide it. Runtime-generated tangent '
                'space may be non-portable across implementations.',
            'pointer': '/meshes/0/primitives/2/material',
            'disposition':
                'Generated tangent portability requires target and visual evaluation.',
          },
          <String, Object?>{
            'severity': 1,
            'code': 'MESH_PRIMITIVE_GENERATED_TANGENT_SPACE',
            'message': 'Material requires a tangent space but the mesh '
                'primitive does not provide it. Runtime-generated tangent '
                'space may be non-portable across implementations.',
            'pointer': '/meshes/0/primitives/3/material',
            'disposition':
                'Generated tangent portability requires target and visual evaluation.',
          },
        ],
        'warningDisposition':
            'Exact source warnings are retained and block A1B32 acceptance '
                'until target and visual evaluation; this is not rewrite, '
                'renderer, target, release, or production evidence.',
      },
    });

    expect(
      (manifest['rewriteValidation']! as Map)['assets'],
      isA<List<Object?>>().having(
        (assets) => assets
            .cast<Map<String, Object?>>()
            .map((asset) => asset['id'])
            .toList(growable: false),
        'codec ids',
        <String>['meshopt', 'draco', 'basisu'],
      ),
    );

    final tool = File(_toolPath);
    expect(tool.existsSync(), isTrue);
    final toolText = tool.readAsStringSync();
    expect(toolText, isNot(contains('/Users/')));
    expect(toolText, isNot(contains('/private/tmp')));
    final verify = await Process.run(
      'python3',
      <String>[_toolPath, '--verify-metadata'],
    );
    expect(verify.exitCode, 0, reason: '${verify.stdout}\n${verify.stderr}');
    expect(
      verify.stdout,
      contains('6 fixture records and 3 Plan 015 clearcoat records: OK'),
    );

    final temporaryDirectory =
        await Directory.systemTemp.createTemp('fsv_a1b32_provenance_');
    addTearDown(() async => temporaryDirectory.delete(recursive: true));
    final malformed = File('${temporaryDirectory.path}/A1B32.glb')
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    final rejected = await Process.run(
      'python3',
      <String>[_toolPath, '--stage-a1b32', malformed.path],
    );
    expect(rejected.exitCode, isNot(0));
    expect(rejected.stderr, contains('byteLength mismatch'));
  });

  test('Plan 015 clearcoat corpus is pinned and release-honest', () {
    final manifest = Map<String, Object?>.from(
      jsonDecode(File(_manifestPath).readAsStringSync()) as Map,
    );
    final corpus = Map<String, Object?>.from(
      manifest['plan015ClearcoatCorpus']! as Map,
    );

    expect(corpus['schemaVersion'], 1);
    expect(corpus['sourceRepository'], _repository);
    expect(corpus['renderer'], <String, Object?>{
      'package': 'flutter_scene',
      'revision': 'ccf7372428961ebe0abb053727fe443150547a74',
      'reachability':
          'published at https://github.com/MarlonJD/flutter_scene/tree/plan015-clearcoat and pinned by immutable commit',
    });
    expect(
      corpus['runtimeCapability'],
      'verified locally on iOS Simulator; the viewer dependency resolves the '
      'published immutable renderer commit',
    );
    expect(corpus['releaseMaturity'], 'release pending');
    expect(corpus['productionReady'], isFalse);

    final fixtures =
        (corpus['fixtures']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      fixtures.map((fixture) => fixture['id']),
      orderedEquals(<String>[
        'clearcoat_test',
        'clearcoat_car_paint',
        'toycar',
      ]),
    );
    expect(
      fixtures.map((fixture) => fixture['sourceSha256']),
      orderedEquals(<String>[
        'c3a1cbe318cd043b937130af4eb83ec2ea0b03613387b1b7d769dfab4ac15948',
        '4d4b32f2ef6d341191f6b6d6834f2b192762c878cd25d44e6b4b14514cd4be93',
        '01a60862de55cd4b9f3acfab0b0def86451800f9c42467fcd61052c16cb9838c',
      ]),
    );
    final targets = (corpus['targetEvidence']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    expect(targets.first, <String, Object?>{
      'target': 'iOS Simulator',
      'status': 'verified locally',
      'backend': 'rendererNative',
      'renderer': 'Impeller Metal',
      'device': 'iPhone 17 Simulator',
      'os': 'iOS 26.5',
      'captureRoot': 'tools/out/material_extension_acceptance/'
          'plan015_renderer_native_clearcoat/ios_simulator',
      'evidenceRecord':
          'docs/references/material_extension_platform_evidence.md',
    });
    expect(
      targets.skip(1).map((target) => target['status']),
      everyElement('not run'),
    );
  });

  test('A1B32 four-view reference evidence stays reference-only', () {
    final manifest = Map<String, Object?>.from(
      jsonDecode(File(_manifestPath).readAsStringSync()) as Map,
    );
    expect(manifest['referenceCaptureEvidence'], <String, Object?>{
      'schemaVersion': 1,
      'id': 'a1b32_threejs_four_view',
      'status': 'verified locally',
      'evidenceKind': 'reference-renderer-direction',
      'toolPath':
          'tools/reference_renderers/threejs_material_extension_fixture/'
              'render_plan014_a1b32_reference.mjs',
      'contractTestPath':
          'tools/reference_renderers/threejs_material_extension_fixture/'
              'plan014_capture_contract.test.mjs',
      'reportPath': 'tools/out/material_extension_acceptance/'
          'a1b32_threejs_reference/evidence.json',
      'sourceAsset': <String, Object?>{
        'id': 'a1b32',
        'sha256':
            'a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592',
        'byteLength': 2809824,
        'materialPolicy': 'authored-materials-unmodified',
      },
      'renderer': <String, Object?>{
        'name': 'three.js',
        'version': '0.167.1',
        'releaseTag': 'r167',
        'sourceCommit': '42a2f6aac8cffebb29524d68eb7136a756f15960',
        'npmIntegrity':
            'sha512-gYTLJA/UQip6J/tJvl91YYqlZF47+D/kxiWrbTon35ZHlXEN0VOo+Qke2walF1/x92v55H6enomymg4Dak52kw==',
        'backend': 'WebGL',
        'role': 'directional-reference-only',
      },
      'browser': <String, Object?>{
        'product': 'Chrome',
        'version': '150.0.7871.115',
        'platform': 'MacIntel',
      },
      'host': <String, Object?>{
        'platform': 'darwin',
        'release': '25.5.0',
        'architecture': 'arm64',
        'device': 'Apple M2',
      },
      'viewport': <String, Object?>{
        'width': 640,
        'height': 960,
        'deviceScaleFactor': 1,
      },
      'referenceState': <String, Object?>{
        'path':
            'tools/material_extension_acceptance/fixtures/reference_state.json',
        'schemaVersion': 1,
        'sha256':
            '774fb35234176d4d949ac84cf6ba16fb05ee7afd7e8d1b70d42c00521f9db8ff',
        'cameraFit': 'assetBounds',
        'views': <Object?>['front', 'left', 'right', 'back'],
      },
      'passCriteria': <Object?>[
        'all four configured views render non-empty PNG bytes',
        'authored materials, textures, geometry, UVs, and visibility remain unmodified',
        'capture metadata records exact source, renderer, state, view, and artifact hashes',
      ],
      'captures': <Object?>[
        <String, Object?>{
          'view': 'front',
          'artifactPath': 'tools/out/material_extension_acceptance/'
              'a1b32_threejs_reference/front.png',
          'byteLength': 103900,
          'sha256':
              'e83a2fcaac4be1f8e22762c4729928ffdd99ad8ada27ad466e085a5eda14eab9',
        },
        <String, Object?>{
          'view': 'left',
          'artifactPath': 'tools/out/material_extension_acceptance/'
              'a1b32_threejs_reference/left.png',
          'byteLength': 77562,
          'sha256':
              '36a89eb64369a36c1b2c00e03bcc4b6a8a9b5567bdbd11d2414c105f466e0203',
        },
        <String, Object?>{
          'view': 'right',
          'artifactPath': 'tools/out/material_extension_acceptance/'
              'a1b32_threejs_reference/right.png',
          'byteLength': 79293,
          'sha256':
              '3af9c2ba3487f0aac818dcbde5cde04fb3ef8cf734df4ff86c2853a34f2cd99c',
        },
        <String, Object?>{
          'view': 'back',
          'artifactPath': 'tools/out/material_extension_acceptance/'
              'a1b32_threejs_reference/back.png',
          'byteLength': 98053,
          'sha256':
              'fde6520710a6f32aff4d4efaeaeeaefef40312e8fea5730698d1457ce1381e05',
        },
      ],
      'persistence':
          'hash metadata is tracked; image artifacts stay ignored because '
              'redistribution is not established',
      'targetEvidence': <Object?>[
        <String, Object?>{'target': 'iOS Simulator', 'status': 'not run'},
        <String, Object?>{'target': 'physical iOS', 'status': 'not run'},
        <String, Object?>{'target': 'Android', 'status': 'not run'},
        <String, Object?>{'target': 'Web', 'status': 'not run'},
      ],
      'evidenceBoundary': <String, Object?>{
        'runtimeCapability': 'not established',
        'releaseMaturity': 'not established',
        'targetEvidence': 'not established',
        'productionReadiness': 'not established',
      },
    });
  });
}
