import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'tools/material_extension_acceptance/manifest.json';
const _toolPath = 'tools/stage_material_extension_fixtures.py';
const _plan018StagingRoot =
    'tools/out/material_extension_acceptance/plan018_sheen_corpus';
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

  test('Plan 018 sheen corpus provenance and staging contract is immutable',
      () async {
    final manifest = Map<String, Object?>.from(
      jsonDecode(File(_manifestPath).readAsStringSync()) as Map,
    );
    expect(manifest, contains('plan018SheenCorpus'));
    final corpus = Map<String, Object?>.from(
      manifest['plan018SheenCorpus']! as Map,
    );

    expect(corpus['schemaVersion'], 1);
    expect(corpus['sourceRepository'], _repository);
    expect(corpus['stagingToolPath'], _toolPath);
    expect(corpus['stagingRoot'], _plan018StagingRoot);
    expect(
      corpus['scope'],
      'Source/license provenance and deterministic derived-container staging '
      'only; no Three.js, Flutter, renderer, target, release, or '
      'production-readiness evidence.',
    );
    expect(corpus['evidence'], <String, Object?>{
      'sourceAndLicenseProvenance': 'verified locally',
      'threeJsLoading': 'not run',
      'flutterLoading': 'not run',
      'rendering': 'not run',
      'releaseMaturity': 'not established',
      'productionReadiness': 'not established',
      'targetEvidence': <Object?>[
        <String, Object?>{'target': 'iOS Simulator', 'status': 'not run'},
        <String, Object?>{'target': 'physical iOS', 'status': 'not run'},
        <String, Object?>{'target': 'Android', 'status': 'not run'},
        <String, Object?>{'target': 'Web', 'status': 'not run'},
      ],
    });
    expect(corpus['authoredCoverage'], <String, Object?>{
      'collectiveSheenInputs': <Object?>[
        'sheenColorFactor',
        'sheenColorTexture',
        'sheenRoughnessFactor',
        'sheenRoughnessTexture',
      ],
      'toyCarRoleSeparation': <String, Object?>{
        'evidenceKind': 'authored-data separation only',
        'sheen': <String, Object?>{
          'material': 'Fabric',
          'extension': 'KHR_materials_sheen',
        },
        'clearcoat': <String, Object?>{
          'material': 'ToyCar',
          'extension': 'KHR_materials_clearcoat',
        },
        'transmission': <String, Object?>{
          'material': 'Glass',
          'extension': 'KHR_materials_transmission',
        },
        'rendering': 'not run',
      },
    });

    final fixtures = (corpus['fixtures']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false);
    expect(
      fixtures.map((fixture) => fixture['id']),
      orderedEquals(<String>[
        'sheen_chair',
        'sheen_cloth',
        'glam_velvet_sofa',
        'toycar',
      ]),
    );
    final expectedAuthoredInputs = <List<Object?>>[
      <Object?>['sheenColorFactor', 'sheenRoughnessFactor'],
      <Object?>[
        'sheenColorFactor',
        'sheenColorTexture',
        'sheenRoughnessFactor',
        'sheenRoughnessTexture',
      ],
      <Object?>['sheenColorFactor', 'sheenRoughnessFactor'],
      <Object?>['sheenColorFactor', 'sheenRoughnessFactor'],
    ];
    for (var index = 0; index < fixtures.length; index += 1) {
      expect(
        fixtures[index]['authoredSheenInputs'],
        orderedEquals(expectedAuthoredInputs[index]),
      );
    }

    final expectedSources = <String, List<Map<String, Object?>>>{
      'sheen_chair': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'Models/SheenChair/glTF-Binary/SheenChair.glb',
          'sha256':
              'f0af2a2b102d28d540236306ae19f8fb36842df76bd38cf76f063f9bd2853399',
          'byteLength': 4125648,
          'mediaType': 'model/gltf-binary',
        },
      ],
      'sheen_cloth': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/SheenCloth.gltf',
          'sha256':
              '00a2cbc0d2ad4788dbfc00da3c51f252fd8e6003dbfda80b087a548fe3550f02',
          'byteLength': 6854,
          'mediaType': 'model/gltf+json',
        },
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/SheenCloth.bin',
          'sha256':
              '4ed1f49797ce52b9f653b8650a31fa249fac99524303b0e153804365fb7e45b1',
          'byteLength': 3479088,
          'mediaType': 'application/octet-stream',
        },
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/technicalFabricSmall_normal_256.png',
          'sha256':
              '299b1ccf8957d451d7841672b1750b5cfcea65fee1c97eec6b086dc3fdeea838',
          'byteLength': 127852,
          'mediaType': 'image/png',
        },
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/technicalFabricSmall_orm_256.png',
          'sha256':
              '41c04abdb9531d00a4ac832d41f02cd549c7be74886c4d492475cfb95d239a20',
          'byteLength': 131303,
          'mediaType': 'image/png',
        },
        <String, Object?>{
          'path':
              'Models/SheenCloth/glTF/technicalFabricSmall_basecolor_256.png',
          'sha256':
              'e945c0b2aa6e3987d8bb8af23aca58a3f75cce2992bb4803bec8cac6cde8474e',
          'byteLength': 125026,
          'mediaType': 'image/png',
        },
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/technicalFabricSmall_sheen_256.png',
          'sha256':
              '479c3c65b1b9161701c5587cdfccf42a2de38d4d5365b6b904daf9ba8b7b9aab',
          'byteLength': 170368,
          'mediaType': 'image/png',
        },
        <String, Object?>{
          'path': 'Models/SheenCloth/glTF/SheenCloth_AO.jpg',
          'sha256':
              '5b40abcf27c3c8a3ccf16e4672da35a1b27680c4037c1b27f390398aaaa896ff',
          'byteLength': 139947,
          'mediaType': 'image/jpeg',
        },
      ],
      'glam_velvet_sofa': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'Models/GlamVelvetSofa/glTF-Binary/GlamVelvetSofa.glb',
          'sha256':
              '67202c74a1a33377771f162dc7fad612a6c9bd51ee15124c488e9851d9ac5266',
          'byteLength': 3149844,
          'mediaType': 'model/gltf-binary',
        },
      ],
      'toycar': <Map<String, Object?>>[
        <String, Object?>{
          'path': 'Models/ToyCar/glTF-Binary/ToyCar.glb',
          'sha256':
              '01a60862de55cd4b9f3acfab0b0def86451800f9c42467fcd61052c16cb9838c',
          'byteLength': 5422412,
          'mediaType': 'model/gltf-binary',
        },
      ],
    };
    final expectedLicenses = <String, Map<String, Object?>>{
      'sheen_chair': <String, Object?>{
        'assetSpdx': 'CC0-1.0',
        'metadataSpdx': 'CC-BY-4.0',
        'evidencePath': 'Models/SheenChair/LICENSE.md',
        'evidenceSha256':
            'ec688136d27e6b32c3af32bd06f9066c78ff55bd0de6bff012580436b629dd57',
        'evidenceByteLength': 700,
      },
      'sheen_cloth': <String, Object?>{
        'assetSpdx': 'CC0-1.0',
        'metadataSpdx': 'CC-BY-4.0',
        'evidencePath': 'Models/SheenCloth/LICENSE.md',
        'evidenceSha256':
            '584e393d6faecc7d7e1738cb08bf6c0a0ace8dc04bcc1d2e38b077ff2141267a',
        'evidenceByteLength': 700,
      },
      'glam_velvet_sofa': <String, Object?>{
        'assetSpdx': 'CC-BY-4.0',
        'metadataSpdx': 'CC-BY-4.0',
        'evidencePath': 'Models/GlamVelvetSofa/LICENSE.md',
        'evidenceSha256':
            'b331316a5e62b1f97abb06902931d6c10c0013d7aaf0ac8af466e91843766ced',
        'evidenceByteLength': 705,
      },
      'toycar': <String, Object?>{
        'assetSpdx': 'CC0-1.0',
        'metadataSpdx': 'CC-BY-4.0',
        'evidencePath': 'Models/ToyCar/LICENSE.md',
        'evidenceSha256':
            'b6b2c8a062107e8a3140e7d65a815b5964d96e71b04dbdafd4df1c0efc1cddc1',
        'evidenceByteLength': 819,
      },
    };
    for (final fixture in fixtures) {
      final id = fixture['id']! as String;
      expect(fixture['sourceRepository'], _repository);
      expect(fixture['vendored'], isFalse);
      expect(fixture['localPath'], isNull);
      expect(
        fixture['stagingDirectory'],
        '$_plan018StagingRoot/$id',
      );
      final actualSources = (fixture['sourceFiles']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList(growable: false);
      expect(actualSources, hasLength(expectedSources[id]!.length));
      for (var index = 0; index < actualSources.length; index += 1) {
        final actual = actualSources[index];
        final expected = expectedSources[id]![index];
        expect(actual['path'], expected['path']);
        expect(
          actual['url'],
          'https://raw.githubusercontent.com/KhronosGroup/'
          'glTF-Sample-Assets/$_commit/${expected['path']}',
        );
        expect(actual['sha256'], expected['sha256']);
        expect(actual['byteLength'], expected['byteLength']);
        expect(actual['mediaType'], expected['mediaType']);
      }
      final expectedLicense = expectedLicenses[id]!;
      expect(fixture['license'], <String, Object?>{
        ...expectedLicense,
        'evidenceUrl': 'https://raw.githubusercontent.com/KhronosGroup/'
            'glTF-Sample-Assets/$_commit/${expectedLicense['evidencePath']}',
      });
    }

    expect(fixtures[0]['sourceKind'], 'khronos-official-glb');
    expect(fixtures[1]['sourceKind'], 'khronos-official-multifile-gltf');
    expect(fixtures[2]['sourceKind'], 'khronos-official-glb');
    expect(fixtures[3]['sourceKind'], 'khronos-official-glb');
    expect(fixtures[1]['derivedArtifact'], <String, Object?>{
      'artifactKind': 'repository-generated-deterministic-container',
      'provenance': 'repository-generated deterministic container derived '
          'from the hash-pinned official multi-file source',
      'transformation': 'External buffer and image bytes become GLB buffer '
          'views; authored materials, texture channels, samplers, transforms, '
          'UVs, geometry, and names remain unchanged.',
      'outputPath': '$_plan018StagingRoot/sheen_cloth/derived/SheenCloth.glb',
      'sha256':
          'bab89a56fe44396877f35fc794222b54f2107ba273634c6514c2a910cab61588',
      'byteLength': 4176696,
      'glbContract': <String, Object?>{
        'version': 2,
        'buffers': 1,
        'bufferViews': 9,
        'embeddedImages': 5,
        'materials': 1,
      },
    });

    expect(
      (manifest['fixtureProvenance']! as Map)['fixtures'],
      isA<List<Object?>>().having(
        (fixtures) => fixtures.length,
        'historical fixture count',
        6,
      ),
    );
    final verify = await Process.run(
      'python3',
      <String>[_toolPath, '--verify-metadata'],
    );
    expect(verify.exitCode, 0, reason: '${verify.stdout}\n${verify.stderr}');
    expect(
      verify.stdout,
      contains('4 Plan 018 sheen records'),
    );

    final temporaryDirectory =
        await Directory.systemTemp.createTemp('fsv_plan018_sheen_');
    addTearDown(() async => temporaryDirectory.delete(recursive: true));
    final source = File('${temporaryDirectory.path}/Models/SheenChair/'
        'glTF-Binary/SheenChair.glb')
      ..createSync(recursive: true)
      ..writeAsBytesSync(<int>[0, 1, 2, 3]);
    expect(source.existsSync(), isTrue);
    final rejected = await Process.run(
      'python3',
      <String>[
        _toolPath,
        '--stage-plan018-sheen',
        temporaryDirectory.path,
      ],
    );
    expect(rejected.exitCode, isNot(0));
    expect(rejected.stderr, contains('sheen_chair source byteLength mismatch'));
  });

  test('Plan 018 renderer-native scalar sheen control evidence is immutable',
      () {
    final manifest = Map<String, Object?>.from(
      jsonDecode(File(_manifestPath).readAsStringSync()) as Map,
    );

    expect(
      manifest['notes'],
      contains(
        'UV0/TEXCOORD_0 is required for package-owned authored '
        'texture-bearing extension inputs; renderer-native runtime bindings '
        'preserve their authored texture-coordinate semantic.',
      ),
    );
    expect(manifest['plan018RendererNativeSheenControl'], <String, Object?>{
      'schemaVersion': 1,
      'comparisonBoundary': 'renderer-local sheen on/off control only',
      'renderer': <String, Object?>{
        'package': 'flutter_scene',
        'revision': '766351c865c621e8720c726f9aa51173ce76e786',
        'reachability': 'externally reachable immutable commit',
      },
      'state': <String, Object?>{
        'path': 'tools/material_extension_acceptance/fixtures/'
            'plan018_renderer_native_scalar_sheen_control_state.json',
        'sha256':
            'e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63',
      },
      'fixture': <String, Object?>{
        'generatorPath':
            'tools/generate_plan018_renderer_native_sheen_fixture.py',
        'sourcePath': 'test/fixtures/MultiMaterialAssembly.glb',
        'sourceSha256':
            '5f717f321050c3049a29cdf3e3223ad10fd05ce485a088011f77d84357b9ad5f',
        'sourceByteLength': 2716,
        'derivedPath': 'test/fixtures/Plan018RendererNativeSheenControl.glb',
        'derivedSha256':
            '8c0d893fbf72553b3dbf4d9bf8bfa3a1a24bbbfebd699beee5cf72a8216d967d',
        'derivedByteLength': 2848,
        'binaryChunkSha256':
            '8030b3e4654c54a4b6f4dc5b72832da20064ff3217c1fafccc30ac7d4bb0fdea',
        'binaryChunkByteLength': 840,
        'geometry':
            'byte-identical source BIN with authored normals and TEXCOORD_0',
        'uv': 'authored TEXCOORD_0 preserved but unused by scalar-only sheen',
        'jsonDelta': 'KHR_materials_sheen factors on material 0 only',
      },
      'controls': <Object?>[
        <String, Object?>{
          'id': 'renderer_native_scalar_sheen_on',
          'path': 'test/fixtures/Plan018RendererNativeSheenControl.glb',
          'sha256':
              '8c0d893fbf72553b3dbf4d9bf8bfa3a1a24bbbfebd699beee5cf72a8216d967d',
          'application': 'rendererNative',
          'runtimeAvailability': 'available',
        },
        <String, Object?>{
          'id': 'renderer_native_scalar_sheen_off',
          'path': 'test/fixtures/MultiMaterialAssembly.glb',
          'sha256':
              '5f717f321050c3049a29cdf3e3223ad10fd05ce485a088011f77d84357b9ad5f',
          'application': 'none',
          'runtimeAvailability': 'available',
        },
      ],
      'evidence': <String, Object?>{
        'path': 'tools/out/material_extension_acceptance/'
            'plan018_controlled_comparison/ios_simulator/'
            'renderer-native-run-05/evidence.json',
        'sha256':
            '9f4d3e1b2c561174c9426ad0da653f09c8c3d8ab7494bdfa7dcdf06d121f74da',
        'execution': 'verified locally',
        'application': <String, Object?>{
          'sheenOn': 'rendererNative',
          'sheenOff': 'none',
        },
        'runtimeAvailability': 'available',
        'visual': 'verified locally',
        'featureMaturity': 'release pending',
        'targetEvidence': <String, Object?>{
          'iosSimulator': 'verified locally',
          'physicalIos': 'not run',
          'android': 'not run',
          'web': 'not run',
        },
        'externalReference': 'not run',
        'physicalCorrectness': 'not run',
        'generalPixelParity': 'not run',
        'productionReadiness': 'not run',
      },
    });
  });

  test('Plan 018 sheen metadata rejects path traversal', () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import copy
import importlib.util

spec = importlib.util.spec_from_file_location("fixture_tool", "$_toolPath")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
base = module._load_plan018_sheen()
accepted = []

def check(name, mutate):
    corpus = copy.deepcopy(base)
    mutate(corpus)
    try:
        module._verify_plan018_sheen_metadata(corpus)
    except module.FixtureError:
        return
    accepted.append(name)

def source_path(corpus):
    source = corpus["fixtures"][0]["sourceFiles"][0]
    source["path"] = "Models/../escape.glb"
    source["url"] = (
        "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/"
        "$_commit/Models/../escape.glb"
    )

def license_path(corpus):
    license_record = corpus["fixtures"][0]["license"]
    license_record["evidencePath"] = "Models/SheenChair/../escape/LICENSE.md"
    license_record["evidenceUrl"] = (
        "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/"
        "$_commit/Models/SheenChair/../escape/LICENSE.md"
    )

def staging_root(corpus):
    root = "tools/out/../escape"
    corpus["stagingRoot"] = root
    for fixture in corpus["fixtures"]:
        fixture["stagingDirectory"] = f"{root}/{fixture['id']}"
    corpus["fixtures"][1]["derivedArtifact"]["outputPath"] = (
        f"{root}/sheen_cloth/derived/SheenCloth.glb"
    )

def derived_output(corpus):
    corpus["fixtures"][1]["derivedArtifact"]["outputPath"] = (
        "$_plan018StagingRoot/sheen_cloth/../escape/SheenCloth.glb"
    )

check("source", source_path)
check("license", license_path)
check("staging-root", staging_root)
check("derived-output", derived_output)
if accepted:
    raise SystemExit("accepted unsafe paths: " + ", ".join(accepted))
print("4 traversal mutations rejected")
''',
      ],
      environment: <String, String>{'PYTHONDONTWRITEBYTECODE': '1'},
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(probe.stdout, contains('4 traversal mutations rejected'));
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
