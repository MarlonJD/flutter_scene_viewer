import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/glb_basisu_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_draco_rewriter.dart';
import 'package:flutter_scene_viewer/src/internal/glb_meshopt_rewriter.dart';
import 'package:flutter_test/flutter_test.dart';

const _meshoptFixture =
    'test/fixtures/meshopt/MeshoptCubeTest/glTF/MeshoptCubeTest.bin';
const _validatorRunner =
    'tools/gltf_rewrite_validation/validate_rewritten_glb.mjs';
const _validatorReportRoot = 'tools/gltf_rewrite_validation/reports';
const _updateValidatorReportsEnvironmentVariable =
    'FSV_UPDATE_GLTF_REWRITE_REPORTS';
const _dracoFixtureRoot =
    'packages/flutter_scene_viewer_draco/test/fixtures/draco/Box/glTF-Draco';
const _dracoConformanceRunner =
    'packages/flutter_scene_viewer_draco/test/native/draco_conformance_runner.cc';
const _basisuFixture =
    'packages/flutter_scene_viewer_basisu/test/fixtures/ktx2-cts/deflate/'
    'metadata/output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
const _basisuOutputRunner = 'packages/flutter_scene_viewer_basisu/test/native/'
    'basisu_output_runner.cc';
const _basisuFixtureSha256 =
    '27484bc9b6e062acf0d6478df1b3ad62f6b6f32b923539c93353e535b572b0e4';
const _basisuRgbaSha256 =
    '34219173d529d9cf97a7f8642e32142570426af0d4d52ac50eb316a614e6dae8';
const _basisuModificationNotice =
    'FSV LOCAL MODIFICATION (Apache-2.0 section 4(b))';
const _basisuVendoredSourceRoot =
    'packages/flutter_scene_viewer_basisu/third_party/basis_universal';
const _basisuCompiledSourcePaths = <String>[
  'transcoder/basisu.h',
  'transcoder/basisu_astc_cfgs.inl',
  'transcoder/basisu_astc_hdr_core.h',
  'transcoder/basisu_astc_helpers.h',
  'transcoder/basisu_containers.h',
  'transcoder/basisu_containers_impl.h',
  'transcoder/basisu_etc1_mods.inl',
  'transcoder/basisu_file_headers.h',
  'transcoder/basisu_idct.h',
  'transcoder/basisu_transcoder.cpp',
  'transcoder/basisu_transcoder.h',
  'transcoder/basisu_transcoder_internal.h',
  'transcoder/basisu_transcoder_tables_astc.inc',
  'transcoder/basisu_transcoder_tables_astc_0_255.inc',
  'transcoder/basisu_transcoder_tables_atc_55.inc',
  'transcoder/basisu_transcoder_tables_atc_56.inc',
  'transcoder/basisu_transcoder_tables_bc7_m5_alpha.inc',
  'transcoder/basisu_transcoder_tables_bc7_m5_color.inc',
  'transcoder/basisu_transcoder_tables_dxt1_5.inc',
  'transcoder/basisu_transcoder_tables_dxt1_6.inc',
  'transcoder/basisu_transcoder_tables_pvrtc2_45.inc',
  'transcoder/basisu_transcoder_tables_pvrtc2_alpha_33.inc',
  'transcoder/basisu_transcoder_uastc.h',
  'zstd/LICENSE',
  'zstd/zstd.c',
  'zstd/zstd.h',
  'zstd/zstd_errors.h',
  'zstd/zstddeclib.c',
];
const _meshoptFixtureLength = 10528;
const _mesh26PositionOffset = 7144;
const _mesh26PositionLength = 121;

void main() {
  test('official validator accepts the actual Meshopt rewrite output',
      () async {
    final compressed = File(_meshoptFixture).readAsBytesSync();
    expect(compressed, hasLength(_meshoptFixtureLength));
    final source = _meshoptSourceGlb(
      Uint8List.fromList(
        compressed.sublist(
          _mesh26PositionOffset,
          _mesh26PositionOffset + _mesh26PositionLength,
        ),
      ),
    );
    final rewrite = await rewriteMeshoptCompressedGlb(
      source,
      debugName: 'official-meshopt-v0-validator.glb',
    );

    expect(rewrite.diagnostics, isEmpty);
    expect(rewrite.bytes, isNotNull);

    final temporaryDirectory =
        await Directory.systemTemp.createTemp('fsv_meshopt_validator_');
    addTearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final rewrittenFile =
        File('${temporaryDirectory.path}/meshopt-rewritten.glb');
    await rewrittenFile.writeAsBytes(rewrite.bytes!, flush: true);

    final validation = await Process.run(
      'node',
      <String>[
        _validatorRunner,
        '--asset',
        'meshopt',
        '--input',
        rewrittenFile.path,
      ],
    );
    expect(
      validation.exitCode,
      0,
      reason: '${validation.stdout}\n${validation.stderr}',
    );

    final report = Map<String, Object?>.from(
      jsonDecode(validation.stdout as String) as Map,
    );
    expect(
      report['validator'],
      <String, Object?>{
        'package': 'gltf-validator',
        'version': '2.0.0-dev.3.10',
        'sourceCommit': 'bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1',
        'license': 'Apache-2.0',
      },
    );
    final asset = Map<String, Object?>.from(report['asset']! as Map);
    expect(asset['label'], 'meshopt');
    expect(asset['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      report['issues'],
      <String, Object?>{
        'errors': 0,
        'warnings': 0,
        'infos': 0,
        'hints': 0,
        'messages': <Object?>[],
      },
    );
    _expectOrUpdateTrackedValidatorReport('meshopt', report);
  });

  test('official validator accepts the actual Draco bridge rewrite output',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    expect(
      clang.exitCode,
      0,
      reason: 'Task 11 Draco evidence requires clang++ on this host.\n'
          '${clang.stdout}\n${clang.stderr}',
    );

    final runner = File(_dracoConformanceRunner);
    expect(
      runner.existsSync(),
      isTrue,
      reason: 'Actual bridge payloads must come from the reusable tracked '
          'Draco conformance runner.',
    );
    final gltfFile = File('$_dracoFixtureRoot/Box.gltf');
    final binFile = File('$_dracoFixtureRoot/Box.bin');
    expect(gltfFile.existsSync(), isTrue);
    expect(binFile.existsSync(), isTrue);

    final sourceJson = Map<String, Object?>.from(
      jsonDecode(gltfFile.readAsStringSync()) as Map,
    );
    final buffers = sourceJson['buffers']! as List<Object?>;
    final firstBuffer = Map<String, Object?>.from(buffers.single! as Map);
    expect(firstBuffer.remove('uri'), 'Box.bin');
    buffers[0] = firstBuffer;
    final sourceBin = binFile.readAsBytesSync();
    expect(sourceBin, hasLength(120));
    final source = _writeGlb(sourceJson, sourceBin);

    final temporaryDirectory =
        await Directory.systemTemp.createTemp('fsv_draco_validator_');
    addTearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final executable = '${temporaryDirectory.path}/draco_conformance';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ipackages/flutter_scene_viewer_draco/third_party/draco/src',
      '-Ipackages/flutter_scene_viewer_draco/android/src/main/cpp',
      runner.path,
      'packages/flutter_scene_viewer_draco/android/src/main/cpp/'
          'fsv_draco_budget.cc',
      'packages/flutter_scene_viewer_draco/android/src/main/cpp/'
          'fsv_draco_control.cc',
      'packages/flutter_scene_viewer_draco/android/src/main/cpp/'
          'fsv_draco_bridge.cc',
      'packages/flutter_scene_viewer_draco/ios/Classes/'
          'fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );

    final payloadDirectory = Directory('${temporaryDirectory.path}/payloads')
      ..createSync();
    final nativeRun = await Process.run(executable, <String>[
      binFile.path,
      '--output-directory',
      payloadDirectory.path,
    ]);
    expect(
      nativeRun.exitCode,
      0,
      reason: '${nativeRun.stdout}\n${nativeRun.stderr}',
    );
    final normal =
        File('${payloadDirectory.path}/normal.bin').readAsBytesSync();
    final position =
        File('${payloadDirectory.path}/position.bin').readAsBytesSync();
    final indices =
        File('${payloadDirectory.path}/indices.bin').readAsBytesSync();
    expect(normal, hasLength(288));
    expect(position, hasLength(288));
    expect(indices, hasLength(72));
    expect(normal.length + position.length + indices.length, 648);

    final rewrite = rewriteDracoCompressedGlb(
      source,
      decodedPrimitives: <GlbDecodedDracoPrimitive>[
        GlbDecodedDracoPrimitive(
          meshIndex: 0,
          primitiveIndex: 0,
          attributes: <String, Uint8List>{
            'NORMAL': normal,
            'POSITION': position,
          },
          indices: indices,
        ),
      ],
      debugName: 'official-draco-box-validator.glb',
    );
    expect(rewrite.diagnostics, isEmpty);
    expect(rewrite.bytes, isNotNull);

    final rewrittenFile =
        File('${temporaryDirectory.path}/draco-rewritten.glb');
    await rewrittenFile.writeAsBytes(rewrite.bytes!, flush: true);
    final validation = await Process.run(
      'node',
      <String>[
        _validatorRunner,
        '--asset',
        'draco',
        '--input',
        rewrittenFile.path,
      ],
    );
    expect(
      validation.exitCode,
      0,
      reason: '${validation.stdout}\n${validation.stderr}',
    );

    final report = Map<String, Object?>.from(
      jsonDecode(validation.stdout as String) as Map,
    );
    expect(
      report['validator'],
      <String, Object?>{
        'package': 'gltf-validator',
        'version': '2.0.0-dev.3.10',
        'sourceCommit': 'bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1',
        'license': 'Apache-2.0',
      },
    );
    final asset = Map<String, Object?>.from(report['asset']! as Map);
    expect(asset['label'], 'draco');
    expect(asset['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      report['issues'],
      <String, Object?>{
        'errors': 0,
        'warnings': 0,
        'infos': 1,
        'hints': 3,
        'messages': <Object?>[
          <String, Object?>{
            'severity': 2,
            'code': 'UNUSED_OBJECT',
            'message': 'This object may be unused.',
            'pointer': '/bufferViews/0',
          },
          <String, Object?>{
            'severity': 3,
            'code': 'BUFFER_VIEW_TARGET_MISSING',
            'message':
                'bufferView.target should be set for vertex or index data.',
            'pointer': '/meshes/0/primitives/0/attributes/NORMAL',
          },
          <String, Object?>{
            'severity': 3,
            'code': 'BUFFER_VIEW_TARGET_MISSING',
            'message':
                'bufferView.target should be set for vertex or index data.',
            'pointer': '/meshes/0/primitives/0/attributes/POSITION',
          },
          <String, Object?>{
            'severity': 3,
            'code': 'BUFFER_VIEW_TARGET_MISSING',
            'message':
                'bufferView.target should be set for vertex or index data.',
            'pointer': '/meshes/0/primitives/0/indices',
          },
        ],
      },
    );
    _expectOrUpdateTrackedValidatorReport('draco', report);
  });

  test('actual BasisU bridge raw output cannot enter the PNG rewrite path',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    expect(
      clang.exitCode,
      0,
      reason: 'Task 11 BasisU evidence requires clang++ on this host.\n'
          '${clang.stdout}\n${clang.stderr}',
    );

    final fixture = File(_basisuFixture);
    expect(fixture.existsSync(), isTrue);
    final fixtureHash = await Process.run(
      'shasum',
      <String>['-a', '256', fixture.path],
    );
    expect(
      fixtureHash.exitCode,
      0,
      reason: '${fixtureHash.stdout}\n${fixtureHash.stderr}',
    );
    expect(
      (fixtureHash.stdout as String).split(RegExp(r'\s+')).first,
      _basisuFixtureSha256,
    );

    final runner = File(_basisuOutputRunner);
    expect(
      runner.existsSync(),
      isTrue,
      reason: 'Actual bridge PNG bytes must come from the reusable tracked '
          'BasisU output runner.',
    );

    final temporaryDirectory =
        await Directory.systemTemp.createTemp('fsv_basisu_validator_');
    addTearDown(() async {
      if (temporaryDirectory.existsSync()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final executable = '${temporaryDirectory.path}/basisu_output';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Ipackages/flutter_scene_viewer_basisu/android/src/main/cpp',
      '-Ipackages/flutter_scene_viewer_basisu/third_party/'
          'basis_universal/transcoder',
      '-Ipackages/flutter_scene_viewer_basisu/third_party/'
          'basis_universal/zstd',
      runner.path,
      'packages/flutter_scene_viewer_basisu/android/src/main/cpp/'
          'fsv_basisu_budget.cc',
      'packages/flutter_scene_viewer_basisu/android/src/main/cpp/'
          'fsv_basisu_control.cc',
      'packages/flutter_scene_viewer_basisu/android/src/main/cpp/'
          'fsv_basisu_bridge.cc',
      'packages/flutter_scene_viewer_basisu/third_party/basis_universal/'
          'transcoder/basisu_transcoder.cpp',
      'packages/flutter_scene_viewer_basisu/third_party/basis_universal/'
          'zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );

    final rgbaFile = File('${temporaryDirectory.path}/basisu.rgba');
    final nativeRun = await Process.run(
      executable,
      <String>[fixture.path, rgbaFile.path],
    );
    expect(
      nativeRun.exitCode,
      0,
      reason: '${nativeRun.stdout}\n${nativeRun.stderr}',
    );
    final rgbaBytes = rgbaFile.readAsBytesSync();
    expect(rgbaBytes, hasLength(1024));
    final rgbaHash = await Process.run(
      'shasum',
      <String>['-a', '256', rgbaFile.path],
    );
    expect(
      rgbaHash.exitCode,
      0,
      reason: '${rgbaHash.stdout}\n${rgbaHash.stderr}',
    );
    expect(
      (rgbaHash.stdout as String).split(RegExp(r'\s+')).first,
      _basisuRgbaSha256,
    );

    final source = _basisuSourceGlb(fixture.readAsBytesSync());
    final rewrite = rewriteBasisuTexturesInGlb(
      source,
      decodedImages: <GlbDecodedBasisuImage>[
        GlbDecodedBasisuImage(
          imageIndex: 0,
          contentRole: 'color',
          levels: <GlbDecodedBasisuMipLevel>[
            GlbDecodedBasisuMipLevel(
              level: 0,
              width: 16,
              height: 16,
              rgbaBytes: rgbaBytes,
            ),
          ],
        ),
      ],
      debugName: 'official-basisu-uastc-zstd-validator.glb',
    );
    expect(rewrite.bytes, isNull);
    expect(rewrite.diagnostics, hasLength(1));
    expect(rewrite.diagnostics.single.details,
        containsPair('status', 'mipAwareImporterRequired'));
    expect(source, _basisuSourceGlb(fixture.readAsBytesSync()));
  });

  test('material acceptance manifest records strict rewrite provenance',
      () async {
    final manifest = jsonDecode(
      File('tools/material_extension_acceptance/manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final rewriteValidation = Map<String, Object?>.from(
      manifest['rewriteValidation']! as Map,
    );
    expect(
      rewriteValidation.keys,
      orderedEquals(<String>[
        'schemaVersion',
        'validator',
        'evidence',
        'assets',
      ]),
    );
    expect(rewriteValidation['schemaVersion'], 1);
    expect(
      rewriteValidation['validator'],
      <String, Object?>{
        'package': 'gltf-validator',
        'version': '2.0.0-dev.3.10',
        'prerelease': 'dev.3.10',
        'sourceCommit': 'bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1',
        'license': 'Apache-2.0',
        'lockPath': 'tools/gltf_rewrite_validation/package-lock.json',
        'npmIntegrity':
            'sha512-odJ4k0tRkGXiDGn78yDBg+fBbAIvBnXxh3RwAta0emSxGtyagFE8B4xELB1oYe3S5RD8Ci3uZAsZaascH2LAEQ==',
      },
    );
    expect(
      rewriteValidation['evidence'],
      <String, Object?>{
        'runtimeCapability': 'not established',
        'releaseMaturity': 'not established',
        'hostValidatorEvidence': 'verified locally',
        'targetEvidence': <Object?>[
          <String, Object?>{
            'target': 'iOS Simulator',
            'status': 'not run',
          },
          <String, Object?>{
            'target': 'physical iOS',
            'status': 'not run',
          },
          <String, Object?>{'target': 'Android', 'status': 'not run'},
          <String, Object?>{'target': 'Web', 'status': 'not run'},
        ],
        'scope': 'Official glTF Validator structural acceptance of actual '
            'rewritten GLB bytes on the host.',
        'doesNotEstablish': <Object?>[
          'production readiness',
          'runtime capability',
          'rendered correctness',
          'device support',
          'package readiness',
          'release readiness',
        ],
      },
    );

    final lock = jsonDecode(
      File('tools/gltf_rewrite_validation/package-lock.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final lockPackages = Map<String, Object?>.from(lock['packages']! as Map);
    expect(
      lockPackages['node_modules/gltf-validator'],
      <String, Object?>{
        'version': '2.0.0-dev.3.10',
        'resolved':
            'https://registry.npmjs.org/gltf-validator/-/gltf-validator-2.0.0-dev.3.10.tgz',
        'integrity':
            'sha512-odJ4k0tRkGXiDGn78yDBg+fBbAIvBnXxh3RwAta0emSxGtyagFE8B4xELB1oYe3S5RD8Ci3uZAsZaascH2LAEQ==',
        'license': 'Apache-2.0',
      },
    );

    final assets = (rewriteValidation['assets']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      assets.map((asset) => asset['id']),
      orderedEquals(<String>['meshopt', 'draco', 'basisu']),
    );
    final expectedProvenance = <String, Map<String, Object?>>{
      'meshopt': <String, Object?>{
        'source': 'KhronosGroup/glTF-Sample-Assets',
        'sourceCommit': '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf',
        'license': 'CC0-1.0',
        'licensePath': 'test/fixtures/meshopt/LICENSE.md',
        'licenseSha256':
            '63fc4b5080289c3640c904dcf5adb3a6122a707928164d7520f46b3051da8ac3',
        'sourceFixtures': <Object?>[
          <String, Object?>{
            'path': 'test/fixtures/meshopt/MeshoptCubeTest/glTF/'
                'MeshoptCubeTest.bin',
            'sha256':
                '6578c1d82c5cc2b228e9513e37f348ca89cdb24b5985aa0567efef8d3c014360',
          },
        ],
        'codec': <String, Object?>{
          'identity': 'repository-owned Dart EXT_meshopt_compression decoder',
          'implementationPath': 'lib/src/internal/glb_meshopt_rewriter.dart',
        },
        'normalizedReportPath':
            'tools/gltf_rewrite_validation/reports/meshopt.json',
        'rewrittenSha256':
            '676271e50ce235f349c01749613e7bfade4f5720cff72d7803a272f8ef41e549',
        'evidenceScope':
            'Actual fixture-to-Dart-rewriter-to-official-validator host '
                'chain only.',
      },
      'draco': <String, Object?>{
        'source': 'KhronosGroup/glTF-Sample-Assets',
        'sourceCommit': '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf',
        'license': 'CC-BY-4.0',
        'licensePath': 'packages/flutter_scene_viewer_draco/test/fixtures/'
            'draco/Box/LICENSE.md',
        'licenseSha256':
            '634623c7bef43aa4b16a3556ac55ae71b671daf4509437d403e4f2a0273928dc',
        'sourceFixtures': <Object?>[
          <String, Object?>{
            'path': 'packages/flutter_scene_viewer_draco/test/fixtures/'
                'draco/Box/glTF-Draco/Box.gltf',
            'sha256':
                '3c46acecdfa90b012ec9052d8a1dfa61358e6d56a9e333504189cc78a2de4d1b',
          },
          <String, Object?>{
            'path': 'packages/flutter_scene_viewer_draco/test/fixtures/'
                'draco/Box/glTF-Draco/Box.bin',
            'sha256':
                '610dc6e08aba7c2720c8e4ec0578efd91cf2d88a5e638dab7811a22f0235bf2e',
          },
        ],
        'codec': <String, Object?>{
          'identity': 'Google Draco 1.5.7',
          'sourceCommit': '8786740086a9f4d83f44aa83badfbea4dce7a1b5',
          'license': 'Apache-2.0',
          'licensePath':
              'packages/flutter_scene_viewer_draco/third_party/draco/LICENSE',
          'licenseSha256':
              'd3709b0fb4b8a94bbb1d02b8a2e484f258b0d9c5c5a01f940391f3fe662cd1a4',
        },
        'normalizedReportPath':
            'tools/gltf_rewrite_validation/reports/draco.json',
        'rewrittenSha256':
            'ed046b12e6be838c8702a631edfe6807bbc8380dc3d15ca31977ec930487842b',
        'evidenceScope': 'Actual fixture-to-pinned-codec/bridge-to-Dart-'
            'rewriter-to-official-validator host chain only.',
      },
      'basisu': <String, Object?>{
        'source': 'KhronosGroup/KTX-Software-CTS',
        'sourceCommit': '8c6bd82215d2ca4e015dca0b3378c602b9d4e688',
        'license': 'Apache-2.0',
        'licensePath': 'packages/flutter_scene_viewer_basisu/test/fixtures/'
            'ktx2-cts/LICENSE',
        'licenseSha256':
            'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4',
        'sourceFixtures': <Object?>[
          <String, Object?>{
            'path': 'packages/flutter_scene_viewer_basisu/test/fixtures/'
                'ktx2-cts/deflate/metadata/'
                'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
            'sha256':
                '27484bc9b6e062acf0d6478df1b3ad62f6b6f32b923539c93353e535b572b0e4',
          },
        ],
        'codec': isA<Map>()
            .having(
              (codec) => codec.keys,
              'strict keys',
              orderedEquals(<String>[
                'identity',
                'upstreamBaseCommit',
                'upstreamSourcePath',
                'upstreamSourceSha256',
                'vendoredSourcePath',
                'vendoredSourceSha256',
                'compiledSourceManifestPath',
                'compiledSourceManifestSha256',
                'localModificationsPath',
                'localModificationsSha256',
                'localModification',
                'license',
                'licensePath',
                'licenseSha256',
              ]),
            )
            .having(
              (codec) => codec['identity'],
              'identity',
              'Basis Universal transcoder',
            )
            .having(
              (codec) => codec['upstreamBaseCommit'],
              'upstream base commit',
              '882abb5320400ab650c1be33f9152e4955e83af3',
            )
            .having(
              (codec) => codec['upstreamSourcePath'],
              'upstream source path',
              'transcoder/basisu_transcoder.cpp',
            )
            .having(
              (codec) => codec['upstreamSourceSha256'],
              'official upstream source hash',
              '27fda5a2330831704a7adcf254b852c6df5081258dcc1e42283a936030b6f01f',
            )
            .having(
              (codec) => codec['vendoredSourcePath'],
              'vendored source path',
              '$_basisuVendoredSourceRoot/transcoder/basisu_transcoder.cpp',
            )
            .having(
              (codec) => codec['vendoredSourceSha256'],
              'vendored source hash',
              '316c54c224889e7b887c66663b6668e51ec90b89a7d836db8deec167b1b239d2',
            )
            .having(
              (codec) => codec['compiledSourceManifestPath'],
              'compiled source manifest path',
              '$_basisuVendoredSourceRoot/VENDORED_SOURCES.sha256',
            )
            .having(
              (codec) => codec['compiledSourceManifestSha256'],
              'compiled source manifest hash',
              'd675ed64ee129ac46c6f9fe4cc569bf9970bac65a69c7e1b1fc598eafe83bf55',
            )
            .having(
              (codec) => codec['localModificationsPath'],
              'local modifications path',
              '$_basisuVendoredSourceRoot/FSV_LOCAL_MODIFICATIONS.md',
            )
            .having(
              (codec) => codec['localModificationsSha256'],
              'local modifications hash',
              '6d9e1984399050c50392c5638431ff6c07b8dcbdd2a879b4c0fb3f17775d6794',
            )
            .having(
              (codec) => codec['localModification'],
              'local modification record',
              <String, Object?>{
                'notice': _basisuModificationNotice,
                'path': '$_basisuVendoredSourceRoot/transcoder/'
                    'basisu_transcoder.cpp',
                'purpose': 'Reject oversized KTX2 dimensions and route reached '
                    'KTX2 metadata, ETC1S state, Zstd workspace, input, result, '
                    'and platform-copy native lifetimes through an explicit '
                    'request allocator.',
              },
            )
            .having((codec) => codec['license'], 'license', 'Apache-2.0')
            .having(
              (codec) => codec['licensePath'],
              'license path',
              '$_basisuVendoredSourceRoot/LICENSE',
            )
            .having(
              (codec) => codec['licenseSha256'],
              'license hash',
              '065fcf48d6af21c0b75e23be5ed5753aee75c892e1c2cf178fa6736305614a5c',
            ),
        'normalizedReportPath':
            'tools/gltf_rewrite_validation/reports/basisu.json',
        'rewrittenSha256':
            '3bbea2f9c2e67bd5cfc34df2c775675780d5c1c4d48b72cc46cc210453dc0ffb',
        'evidenceScope': 'Actual fixture-to-pinned-codec/bridge-to-Dart-'
            'rewriter-to-official-validator host chain only.',
      },
    };

    for (final asset in assets) {
      final id = asset['id']! as String;
      final expected = expectedProvenance[id]!;
      expect(
        asset.keys.toSet(),
        <String>{'id', ...expected.keys, 'issueDisposition'},
      );
      for (final entry in expected.entries) {
        expect(asset[entry.key], entry.value, reason: '$id ${entry.key}');
      }
      await _expectTrackedFileSha256(
        asset['licensePath']! as String,
        asset['licenseSha256']! as String,
      );
      for (final fixture
          in (asset['sourceFixtures']! as List<Object?>).cast<Map>()) {
        await _expectTrackedFileSha256(
          fixture['path']! as String,
          fixture['sha256']! as String,
        );
      }
      final codec = Map<String, Object?>.from(asset['codec']! as Map);
      if (codec['licensePath'] case final String codecLicensePath) {
        await _expectTrackedFileSha256(
          codecLicensePath,
          codec['licenseSha256']! as String,
        );
      }
      if (id == 'basisu') {
        await _expectTrackedFileSha256(
          codec['vendoredSourcePath']! as String,
          codec['vendoredSourceSha256']! as String,
        );
        await _expectTrackedFileSha256(
          codec['compiledSourceManifestPath']! as String,
          codec['compiledSourceManifestSha256']! as String,
        );
        await _expectTrackedFileSha256(
          codec['localModificationsPath']! as String,
          codec['localModificationsSha256']! as String,
        );
        final vendoredSource =
            File(codec['vendoredSourcePath']! as String).readAsStringSync();
        expect(vendoredSource, contains(_basisuModificationNotice));
        await _expectBasisuCompiledSourceManifest(
          codec['compiledSourceManifestPath']! as String,
        );
      }

      final report = Map<String, Object?>.from(
        jsonDecode(
          File(asset['normalizedReportPath']! as String).readAsStringSync(),
        ) as Map,
      );
      final reportAsset = Map<String, Object?>.from(report['asset']! as Map);
      expect(reportAsset['label'], id);
      expect(reportAsset['sha256'], asset['rewrittenSha256']);

      final issues = Map<String, Object?>.from(report['issues']! as Map);
      final disposition =
          Map<String, Object?>.from(asset['issueDisposition']! as Map);
      for (final key in <String>[
        'errors',
        'warnings',
        'infos',
        'hints',
        'messages',
      ]) {
        expect(disposition[key], issues[key], reason: '$id $key disposition');
      }
      expect(disposition['warnings'], 0);
      expect(
        disposition['warningsDisposition'],
        'none; zero warnings reported',
      );
    }

    final meshoptDisposition =
        assets[0]['issueDisposition']! as Map<String, Object?>;
    expect(
      meshoptDisposition.keys,
      orderedEquals(<String>[
        'errors',
        'warnings',
        'infos',
        'hints',
        'messages',
        'warningsDisposition',
      ]),
    );
    final dracoDisposition = assets[1]['issueDisposition']! as Map;
    expect(
      dracoDisposition.keys,
      orderedEquals(<String>[
        'errors',
        'warnings',
        'infos',
        'hints',
        'messages',
        'warningsDisposition',
        'orphanSourceBufferViews',
        'orphanDisposition',
      ]),
    );
    expect(dracoDisposition['orphanSourceBufferViews'], <Object?>[
      '/bufferViews/0',
    ]);
    expect(
      dracoDisposition['orphanDisposition'],
      'intentionally retained; production compaction not performed',
    );
    final basisuDisposition = assets[2]['issueDisposition']! as Map;
    expect(
      basisuDisposition.keys,
      orderedEquals(<String>[
        'errors',
        'warnings',
        'infos',
        'hints',
        'messages',
        'warningsDisposition',
        'orphanSourceBufferViews',
        'orphanDisposition',
      ]),
    );
    expect(basisuDisposition['orphanSourceBufferViews'], <Object?>[
      '/bufferViews/2',
    ]);
    expect(
      basisuDisposition['orphanDisposition'],
      'intentionally retained; production compaction not performed',
    );
  });
}

Future<void> _expectTrackedFileSha256(String path, String expected) async {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Missing tracked evidence: $path');
  final result = await Process.run('shasum', <String>['-a', '256', path]);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  expect(
    (result.stdout as String).split(RegExp(r'\s+')).first,
    expected,
    reason: 'Tracked evidence hash drifted: $path',
  );
}

Future<void> _expectBasisuCompiledSourceManifest(String path) async {
  final lines = File(path)
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  expect(lines, hasLength(_basisuCompiledSourcePaths.length));
  final paths = <String>[];
  for (final line in lines) {
    final match = RegExp(r'^([0-9a-f]{64})  (\S+)$').firstMatch(line);
    expect(match, isNotNull, reason: 'Malformed vendored source entry: $line');
    final sourcePath = match!.group(2)!;
    paths.add(sourcePath);
    await _expectTrackedFileSha256(
      '$_basisuVendoredSourceRoot/$sourcePath',
      match.group(1)!,
    );
  }
  expect(paths, orderedEquals(_basisuCompiledSourcePaths));
}

void _expectOrUpdateTrackedValidatorReport(
  String asset,
  Map<String, Object?> actual,
) {
  final reportFile = File('$_validatorReportRoot/$asset.json');
  if (Platform.environment[_updateValidatorReportsEnvironmentVariable] == '1') {
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(actual)}\n',
      flush: true,
    );
  }
  expect(
    reportFile.existsSync(),
    isTrue,
    reason: 'Missing durable normalized $asset validator report.',
  );
  final expected = Map<String, Object?>.from(
    jsonDecode(reportFile.readAsStringSync()) as Map,
  );
  expect(actual, expected);
}

Uint8List _meshoptSourceGlb(Uint8List encodedPosition) {
  return _writeGlb(
    <String, Object?>{
      'asset': <String, Object?>{
        'version': '2.0',
        'generator': 'flutter_scene_viewer Plan 014 validator fixture',
      },
      'extensionsUsed': <Object?>['EXT_meshopt_compression'],
      'extensionsRequired': <Object?>['EXT_meshopt_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': encodedPosition.lengthInBytes},
        <String, Object?>{
          'byteLength': 288,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{'fallback': true},
          },
        },
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 1,
          'byteOffset': 0,
          'byteLength': 288,
          'byteStride': 12,
          'target': 34962,
          'extensions': <String, Object?>{
            'EXT_meshopt_compression': <String, Object?>{
              'buffer': 0,
              'byteOffset': 0,
              'byteLength': encodedPosition.lengthInBytes,
              'byteStride': 12,
              'count': 24,
              'mode': 'ATTRIBUTES',
              'filter': 'EXPONENTIAL',
            },
          },
        },
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'bufferView': 0,
          'componentType': 5126,
          'count': 24,
          'type': 'VEC3',
          'min': <Object?>[-0.5, -0.5, -0.5],
          'max': <Object?>[0.5, 0.5, 0.5],
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
              'mode': 4,
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
    encodedPosition,
  );
}

Uint8List _basisuSourceGlb(Uint8List ktx2) {
  const positionByteLength = 3 * 3 * 4;
  const texcoordByteLength = 3 * 2 * 4;
  const ktx2ByteOffset = positionByteLength + texcoordByteLength;
  final bin = Uint8List(ktx2ByteOffset + ktx2.lengthInBytes);
  final data = ByteData.sublistView(bin);
  const positions = <double>[
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    0,
  ];
  const texcoords = <double>[0, 0, 1, 0, 0, 1];
  for (var index = 0; index < positions.length; index += 1) {
    data.setFloat32(index * 4, positions[index], Endian.little);
  }
  for (var index = 0; index < texcoords.length; index += 1) {
    data.setFloat32(
      positionByteLength + index * 4,
      texcoords[index],
      Endian.little,
    );
  }
  bin.setRange(ktx2ByteOffset, bin.lengthInBytes, ktx2);

  return _writeGlb(
    <String, Object?>{
      'asset': <String, Object?>{
        'version': '2.0',
        'generator': 'flutter_scene_viewer Plan 014 validator fixture',
      },
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': bin.lengthInBytes},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': positionByteLength,
          'target': 34962,
        },
        <String, Object?>{
          'buffer': 0,
          'byteOffset': positionByteLength,
          'byteLength': texcoordByteLength,
          'target': 34962,
        },
        <String, Object?>{
          'buffer': 0,
          'byteOffset': ktx2ByteOffset,
          'byteLength': ktx2.lengthInBytes,
        },
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'bufferView': 0,
          'componentType': 5126,
          'count': 3,
          'type': 'VEC3',
          'min': <Object?>[0, 0, 0],
          'max': <Object?>[1, 1, 0],
        },
        <String, Object?>{
          'bufferView': 1,
          'componentType': 5126,
          'count': 3,
          'type': 'VEC2',
          'min': <Object?>[0, 0],
          'max': <Object?>[1, 1],
        },
      ],
      'images': <Object?>[
        <String, Object?>{
          'bufferView': 2,
          'mimeType': 'image/ktx2',
        },
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
              'attributes': <String, Object?>{
                'POSITION': 0,
                'TEXCOORD_0': 1,
              },
              'material': 0,
              'mode': 4,
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
    bin,
  );
}

Uint8List _writeGlb(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json)).toList(growable: true);
  while (jsonBytes.length.isOdd || jsonBytes.length % 4 != 0) {
    jsonBytes.add(0x20);
  }
  final paddedBin = bin.toList(growable: true);
  while (paddedBin.length.isOdd || paddedBin.length % 4 != 0) {
    paddedBin.add(0);
  }
  final totalLength = 12 + 8 + jsonBytes.length + 8 + paddedBin.length;
  final output = Uint8List(totalLength);
  final data = ByteData.sublistView(output);
  data
    ..setUint32(0, 0x46546c67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, jsonBytes.length, Endian.little)
    ..setUint32(16, 0x4e4f534a, Endian.little);
  output.setRange(20, 20 + jsonBytes.length, jsonBytes);
  final binHeaderOffset = 20 + jsonBytes.length;
  data
    ..setUint32(binHeaderOffset, paddedBin.length, Endian.little)
    ..setUint32(binHeaderOffset + 4, 0x004e4942, Endian.little);
  output.setRange(binHeaderOffset + 8, totalLength, paddedBin);
  return output;
}
