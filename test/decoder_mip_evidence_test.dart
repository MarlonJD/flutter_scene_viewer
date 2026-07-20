import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'tools/decoder_mip_acceptance/manifest.json';
const _schemaPath = 'tools/decoder_mip_acceptance/schema.json';
const _validatorPath = 'tools/validate_decoder_mip_evidence.py';

void main() {
  test('tracked decoder mip evidence manifest is valid and unpromoted',
      () async {
    expect(File(_manifestPath).existsSync(), isTrue);
    expect(File(_schemaPath).existsSync(), isTrue);
    expect(File(_validatorPath).existsSync(), isTrue);

    final result = await Process.run(
      'python3',
      <String>[_validatorPath, '--check'],
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    expect(manifest['schemaVersion'], 1);
    expect(
      manifest['artifactRoot'],
      'tools/out/plan017_decoder_mip_acceptance',
    );
    expect(
        manifest['rendererCommit'], '5dcf6fce7dc36719e64e536faba9538fe9fa1022');
    expect(manifest['records'], isEmpty);
    expect(manifest['aggregateMaturity'], 'release pending');
    expect(manifest['productionReady'], isFalse);
  });

  test('schema fully closes manifest discovery claim and record objects', () {
    final schema = jsonDecode(File(_schemaPath).readAsStringSync())
        as Map<String, Object?>;
    expect(schema['additionalProperties'], isFalse);
    final definitions = schema[r'$defs']! as Map<String, Object?>;
    for (final name in <String>['discovery', 'claim', 'record']) {
      final definition = definitions[name]! as Map<String, Object?>;
      expect(definition['additionalProperties'], isFalse, reason: name);
      expect(definition['required'], isNotEmpty, reason: name);
    }
  });

  test('manual record identity time and artifact paths match strict schema',
      () async {
    final schema = jsonDecode(File(_schemaPath).readAsStringSync())
        as Map<String, Object?>;
    final definitions = schema[r'$defs']! as Map<String, Object?>;
    final record = definitions['record']! as Map<String, Object?>;
    final recordProperties = record['properties']! as Map<String, Object?>;
    expect(
      recordProperties['id'],
      <String, Object?>{r'$ref': r'#/$defs/recordId'},
    );
    expect(
      recordProperties['capturedAt'],
      <String, Object?>{r'$ref': r'#/$defs/rfc3339DateTime'},
    );
    final artifact = definitions['artifact']! as Map<String, Object?>;
    final artifactProperties = artifact['properties']! as Map<String, Object?>;
    expect(
      artifactProperties['path'],
      <String, Object?>{r'$ref': r'#/$defs/artifactPath'},
    );

    final mutations = <(void Function(Map<String, Object?>), String)>[
      ((candidate) => candidate['id'] = 'Invalid Record', 'record.id'),
      ((candidate) => candidate['capturedAt'] = '2026-07-19', 'RFC 3339'),
      (
        (candidate) {
          final artifacts = candidate['artifacts']! as List<Object?>;
          final first = artifacts.first! as Map<String, Object?>;
          first['path'] =
              'tools/out/plan017_decoder_mip_acceptance/nested\\escape.log';
        },
        'artifact path',
      ),
    ];
    for (var index = 0; index < mutations.length; index += 1) {
      final id = 'schema-parity-$index';
      final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
          as Map<String, Object?>;
      manifest['records'] = <Object?>['records/$id.json'];
      final candidate = _completeRecord(
        id: id,
        targetKind: 'host',
        gates: const <String>['discovery'],
      );
      mutations[index].$1(candidate);
      final result = await _validateMutatedManifest(
        manifest,
        records: <String, Map<String, Object?>>{'$id.json': candidate},
      );
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains(mutations[index].$2));
    }
  });

  test('claim required gates are immutable per feature and target', () async {
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    final claims =
        (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
    claims.first['requiredGates'] = <Object?>['runtime'];

    final result = await _validateMutatedManifest(manifest);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('canonical required gates'));
  });

  test('production-ready claim requires every matching durable gate', () async {
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    final claims =
        (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
    claims.first
      ..['evidenceStatus'] = 'verified locally'
      ..['maturity'] = 'production-ready'
      ..['recordIds'] = <Object?>[]
      ..['blocker'] = 'none';

    final result = await _validateMutatedManifest(manifest);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('required durable evidence gates'));
  });

  test('build and discovery records cannot satisfy physical runtime', () async {
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    final claims =
        (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
    final physical = claims.firstWhere(
      (claim) =>
          claim['feature'] == 'KHR_texture_basisu' &&
          claim['target'] == 'ios_physical',
    );
    physical
      ..['evidenceStatus'] = 'verified locally'
      ..['maturity'] = 'production-ready'
      ..['recordIds'] = <Object?>['simulator-build-only']
      ..['blocker'] = 'none';
    manifest['records'] = <Object?>['records/simulator-build-only.json'];

    final record = _completeRecord(
      id: 'simulator-build-only',
      targetKind: 'ios_simulator',
      gates: const <String>['discovery', 'release-build'],
    );
    _markRecordProduction(record);
    final package = record['package']! as Map<String, Object?>;
    package['releaseStrippingVerified'] = true;

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{
        'simulator-build-only.json': record,
      },
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('does not match claim target'));
  });

  test('release-build gate requires verified package facts', () async {
    final manifest = _manifestWithPromotedPhysicalBasisClaim('release-failed');
    final record = _completeRecord(
      id: 'release-failed',
      targetKind: 'ios_physical',
      gates: const <String>[
        'package-install',
        'release-build',
        'runtime',
        'cancellation-resource',
        'authored-mip-sampling',
      ],
    );
    _markRecordProduction(record);

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{'release-failed.json': record},
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('release-build gate'));
  });

  test('cancellation-resource gate requires successful terminal facts',
      () async {
    final manifest = _manifestWithPromotedPhysicalBasisClaim('cancel-failed');
    final record = _completeRecord(
      id: 'cancel-failed',
      targetKind: 'ios_physical',
      gates: const <String>[
        'package-install',
        'release-build',
        'runtime',
        'cancellation-resource',
        'authored-mip-sampling',
      ],
    );
    _markRecordProduction(record);
    final package = record['package']! as Map<String, Object?>;
    package['releaseStrippingVerified'] = true;
    final cancellation = record['cancellation']! as Map<String, Object?>;
    cancellation['workerExited'] = false;

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{'cancel-failed.json': record},
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('cancellation-resource gate'));
  });

  test('authored-mip gate requires more than level zero', () async {
    final manifest = _manifestWithPromotedPhysicalBasisClaim('mip-failed');
    final record = _completeRecord(
      id: 'mip-failed',
      targetKind: 'ios_physical',
      gates: const <String>[
        'package-install',
        'release-build',
        'runtime',
        'cancellation-resource',
        'authored-mip-sampling',
      ],
    );
    _markRecordProduction(record);
    final package = record['package']! as Map<String, Object?>;
    package['releaseStrippingVerified'] = true;

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{'mip-failed.json': record},
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('authored-mip-sampling gate'));
  });

  test('runtime gate requires successful target render and readback', () async {
    final manifest = _manifestWithPromotedPhysicalBasisClaim('runtime-failed');
    final record = _completeRecord(
      id: 'runtime-failed',
      targetKind: 'ios_physical',
      gates: _physicalBasisGates,
    );
    _satisfyLegacyPhysicalBasisGates(record);
    record['runtime'] = <String, Object?>{
      'loadSucceeded': true,
      'renderSucceeded': false,
      'readbackSucceeded': false,
      'renderArtifactId': 'runtime-render',
      'readbackArtifactId': 'runtime-readback',
    };

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{'runtime-failed.json': record},
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('runtime gate'));
  });

  test('runtime-diagnostic gate requires one non-native diagnostic', () async {
    final manifest = _manifestWithPromotedClaim(
      feature: 'KHR_texture_basisu',
      target: 'web',
      recordId: 'diagnostic-failed',
      maturity: 'candidate-only',
    );
    final record = _completeRecord(
      id: 'diagnostic-failed',
      targetKind: 'web_runtime',
      gates: const <String>[
        'package-install',
        'release-build',
        'runtime-diagnostic',
      ],
    );
    final package = record['package']! as Map<String, Object?>;
    package['releaseStrippingVerified'] = true;
    record['runtimeDiagnostic'] = <String, Object?>{
      'emitted': false,
      'code': 'unsupportedModelFeature',
      'count': 0,
      'nativePluginInvocationCount': 1,
      'artifactId': 'runtime-diagnostic',
    };

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{
        'diagnostic-failed.json': record,
      },
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('runtime-diagnostic gate'));
  });

  test('authored mip gate requires explicit LOD RGB and base-only control',
      () async {
    final manifest = _manifestWithPromotedPhysicalBasisClaim('sampling-failed');
    final record = _completeRecord(
      id: 'sampling-failed',
      targetKind: 'ios_physical',
      gates: _physicalBasisGates,
    );
    _satisfyLegacyPhysicalBasisGates(record);
    record['mipSampling'] = <String, Object?>{
      'imageIndex': 0,
      'storageRole': 'nonColor',
      'lodSamples': <Object?>[],
      'baseOnlyNegativeControl': <String, Object?>{
        'lod': 1,
        'expectedBaseRgb': <Object?>[255, 0, 0],
        'observedRgb': <Object?>[0, 255, 0],
        'authoredLodRgb': <Object?>[0, 255, 0],
        'artifactId': 'mip-base-only-control',
      },
    };

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{'sampling-failed.json': record},
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('explicit LOD RGB'));
  });

  test('record rejects role slot sampler dimension byte and limit mutations',
      () async {
    final mutations = <void Function(Map<String, Object?>)>[
      (record) {
        final chain = _firstMipChain(record);
        final consumers = chain['materialConsumers']! as List<Object?>;
        final consumer = consumers.first! as Map<String, Object?>;
        consumer['contentRole'] = 'data';
      },
      (record) {
        final chain = _firstMipChain(record);
        final consumers = chain['materialConsumers']! as List<Object?>;
        final consumer = consumers.first! as Map<String, Object?>;
        consumer['minFilter'] = 123;
      },
      (record) {
        final levels = _mipLevels(record);
        levels.add(<String, Object?>{
          'level': 1,
          'width': 3,
          'height': 2,
          'byteLength': 24,
          'rgbaSha256': _hash('3'),
        });
      },
      (record) {
        final level = _mipLevels(record).first! as Map<String, Object?>;
        level['byteLength'] = 63;
      },
      (record) {
        final limits = record['limits']! as Map<String, Object?>;
        limits['maxTextureDimension'] = 2;
      },
      (record) => record['unexpected'] = true,
    ];

    for (var index = 0; index < mutations.length; index += 1) {
      final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
          as Map<String, Object?>;
      final id = 'shape-$index';
      manifest['records'] = <Object?>['records/$id.json'];
      final record = _completeRecord(
        id: id,
        targetKind: 'host',
        gates: const <String>['discovery'],
      );
      mutations[index](record);
      final result = await _validateMutatedManifest(
        manifest,
        records: <String, Map<String, Object?>>{'$id.json': record},
      );
      expect(result.exitCode, isNot(0),
          reason: 'mutation $index: ${result.stdout}\n${result.stderr}');
    }
  });

  test('validator and package references must resolve through inventory',
      () async {
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    manifest['records'] = <Object?>['records/missing-inventory.json'];
    final record = _completeRecord(
      id: 'missing-inventory',
      targetKind: 'host',
      gates: const <String>['discovery'],
    );
    final validator = record['validator']! as Map<String, Object?>;
    validator['reportArtifactId'] = 'missing-validator-report';
    final package = record['package']! as Map<String, Object?>;
    package['layoutArtifactId'] = 'missing-package-layout';

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{
        'missing-inventory.json': record,
      },
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('artifact inventory'));
  });

  test('verified artifacts must stay below the ignored evidence root',
      () async {
    final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
        as Map<String, Object?>;
    manifest['records'] = <Object?>['records/outside-artifact.json'];
    final record = _completeRecord(
      id: 'outside-artifact',
      targetKind: 'host',
      gates: const <String>['host-validation'],
    );
    final artifacts = record['artifacts']! as List<Object?>;
    final firstArtifact = artifacts.first! as Map<String, Object?>;
    firstArtifact['path'] = 'docs/fake-evidence.log';

    final result = await _validateMutatedManifest(
      manifest,
      records: <String, Map<String, Object?>>{
        'outside-artifact.json': record,
      },
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('artifact path'));
  });

  test('verified artifact paths reject symlinked directory components',
      () async {
    final external = Directory.systemTemp.createTempSync('plan017_external_');
    final linkParent = Directory(
      'tools/out/plan017_decoder_mip_acceptance',
    )..createSync(recursive: true);
    final link = Link(
      '${linkParent.path}/test-link-${pid}_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      File('${external.path}/validator.json').writeAsStringSync('x');
      link.createSync(external.path);
      final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
          as Map<String, Object?>;
      const id = 'symlink-artifact';
      manifest['records'] = <Object?>['records/$id.json'];
      final record = _completeRecord(
        id: id,
        targetKind: 'host',
        gates: const <String>['discovery'],
      );
      final artifacts = record['artifacts']! as List<Object?>;
      final first = artifacts.first! as Map<String, Object?>;
      first
        ..['path'] = '${link.path}/validator.json'
        ..['sha256'] =
            '2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881'
        ..['byteLength'] = 1;

      final result = await _validateMutatedManifest(
        manifest,
        records: <String, Map<String, Object?>>{'$id.json': record},
        verifyLocalArtifacts: true,
      );
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('symbolic link'));
    } finally {
      if (link.existsSync()) {
        link.deleteSync();
      }
      external.deleteSync(recursive: true);
    }
  });
}

const _physicalBasisGates = <String>[
  'package-install',
  'release-build',
  'runtime',
  'cancellation-resource',
  'authored-mip-sampling',
];

Map<String, Object?> _manifestWithPromotedClaim({
  required String feature,
  required String target,
  required String recordId,
  required String maturity,
}) {
  final manifest = jsonDecode(File(_manifestPath).readAsStringSync())
      as Map<String, Object?>;
  final claims =
      (manifest['claims']! as List<Object?>).cast<Map<String, Object?>>();
  final claim = claims.firstWhere(
    (candidate) =>
        candidate['feature'] == feature && candidate['target'] == target,
  );
  claim
    ..['evidenceStatus'] = 'verified locally'
    ..['maturity'] = maturity
    ..['recordIds'] = <Object?>[recordId]
    ..['blocker'] = maturity == 'production-ready' ? 'none' : 'release pending';
  manifest['records'] = <Object?>['records/$recordId.json'];
  return manifest;
}

Map<String, Object?> _manifestWithPromotedPhysicalBasisClaim(String recordId) {
  return _manifestWithPromotedClaim(
    feature: 'KHR_texture_basisu',
    target: 'ios_physical',
    recordId: recordId,
    maturity: 'production-ready',
  );
}

void _markRecordProduction(Map<String, Object?> record) {
  record
    ..['maturity'] = 'production-ready'
    ..['blockers'] = <Object?>[];
}

void _satisfyLegacyPhysicalBasisGates(Map<String, Object?> record) {
  _markRecordProduction(record);
  final package = record['package']! as Map<String, Object?>;
  package['releaseStrippingVerified'] = true;
  _mipLevels(record).add(<String, Object?>{
    'level': 1,
    'width': 2,
    'height': 2,
    'byteLength': 16,
    'rgbaSha256': _hash('3'),
  });
  record['mipSampling'] = <String, Object?>{
    'imageIndex': 0,
    'storageRole': 'nonColor',
    'lodSamples': <Object?>[
      <String, Object?>{
        'level': 0,
        'expectedRgb': <Object?>[255, 0, 0],
        'observedRgb': <Object?>[255, 0, 0],
        'artifactId': 'mip-lod-0',
      },
      <String, Object?>{
        'level': 1,
        'expectedRgb': <Object?>[0, 255, 0],
        'observedRgb': <Object?>[0, 255, 0],
        'artifactId': 'mip-lod-1',
      },
    ],
    'baseOnlyNegativeControl': <String, Object?>{
      'lod': 1,
      'expectedBaseRgb': <Object?>[255, 0, 0],
      'observedRgb': <Object?>[255, 0, 0],
      'authoredLodRgb': <Object?>[0, 255, 0],
      'artifactId': 'mip-base-only-control',
    },
  };
}

Map<String, Object?> _firstMipChain(Map<String, Object?> record) {
  final chains = record['mipChains']! as List<Object?>;
  return chains.first! as Map<String, Object?>;
}

List<Object?> _mipLevels(Map<String, Object?> record) {
  return _firstMipChain(record)['levels']! as List<Object?>;
}

Map<String, Object?> _completeRecord({
  required String id,
  required String targetKind,
  required List<String> gates,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    'capturedAt': '2026-07-19T00:00:00Z',
    'evidenceStatus': 'verified locally',
    'maturity': 'candidate-only',
    'features': <Object?>['KHR_texture_basisu'],
    'gates': gates,
    'source': <String, Object?>{
      'viewerBaseCommit': '87944991be7e44fe5ea253a5f013ab0cc3230d44',
      'viewerDiffSha256': _hash('a'),
      'rendererCommit': '5dcf6fce7dc36719e64e536faba9538fe9fa1022',
      'packageVersions': <String, Object?>{
        'flutter_scene_viewer': '0.1.0-alpha.0',
        'flutter_scene_viewer_draco': '0.1.0-alpha.0',
        'flutter_scene_viewer_basisu': '0.1.0-alpha.0',
      },
    },
    'codecs': <Object?>[
      <String, Object?>{
        'id': 'basisu',
        'upstreamBase': '882abb5320400ab650c1be33f9152e4955e83af3',
        'localPatchManifestPath':
            'packages/flutter_scene_viewer_basisu/third_party/'
                'basis_universal/FSV_CODEC_CONTROL_PROVENANCE.sha256',
        'localPatchManifestSha256': _hash('b'),
        'compiledSourceManifestPath':
            'packages/flutter_scene_viewer_basisu/third_party/'
                'basis_universal/VENDORED_SOURCES.sha256',
        'compiledSourceManifestSha256': _hash('c'),
      },
    ],
    'fixtures': <Object?>[
      <String, Object?>{
        'id': 'official-uastc-mips',
        'source': 'KTX-Software CTS',
        'sha256': _hash('d'),
        'byteLength': 128,
      },
    ],
    'target': <String, Object?>{
      'kind': targetKind,
      'deviceId': 'test-device',
      'device': 'test device',
      'os': 'test OS',
      'architecture': 'arm64',
      'buildMode': 'debug',
      'backend': 'host-test',
    },
    'limits': <String, Object?>{
      'maxSourceBytes': 1024,
      'maxWorkingBytes': 2048,
      'maxNativeOutputBytes': 1024,
      'maxTextureDimension': 64,
      'maxMipLevels': 7,
    },
    'runtime': <String, Object?>{
      'loadSucceeded': true,
      'renderSucceeded': true,
      'readbackSucceeded': true,
      'renderArtifactId': 'runtime-render',
      'readbackArtifactId': 'runtime-readback',
    },
    'runtimeDiagnostic': <String, Object?>{
      'emitted': true,
      'code': 'unsupportedModelFeature',
      'count': 1,
      'nativePluginInvocationCount': 0,
      'artifactId': 'runtime-diagnostic',
    },
    'cancellation': <String, Object?>{
      'trigger': 'level-1',
      'latencyMicros': 10,
      'maxUiGapMicros': 10,
      'workerExited': true,
      'terminalDiagnosticCount': 1,
      'latePublicationCount': 0,
      'registryEntriesAfter': 0,
      'subsequentLoadSucceeded': true,
      'artifactId': 'cancellation-log',
    },
    'allocations': <String, Object?>{
      'limitBytes': 2048,
      'peakLiveBytes': 1024,
      'liveBytesAfter': 0,
      'allocationCount': 2,
      'releaseCount': 2,
    },
    'mipChains': <Object?>[
      <String, Object?>{
        'imageIndex': 0,
        'fixtureId': 'official-uastc-mips',
        'storageRole': 'nonColor',
        'materialConsumers': <Object?>[
          <String, Object?>{
            'textureIndex': 0,
            'materialSlot': 'normal',
            'contentRole': 'normal',
            'magFilter': 9729,
            'minFilter': 9987,
            'wrapS': 10497,
            'wrapT': 10497,
          },
        ],
        'levels': <Object?>[
          <String, Object?>{
            'level': 0,
            'width': 4,
            'height': 4,
            'byteLength': 64,
            'rgbaSha256': _hash('e'),
          },
        ],
      },
    ],
    'mipSampling': null,
    'validator': <String, Object?>{
      'name': 'gltf-validator',
      'version': '2.0.0-dev.3.10',
      'passed': true,
      'reportArtifactId': 'validator-report',
    },
    'package': <String, Object?>{
      'pluginRegistered': true,
      'nativeSymbolsVerified': true,
      'licensesVerified': true,
      'releaseStrippingVerified': false,
      'layoutArtifactId': 'package-layout',
      'symbolsArtifactId': 'package-symbols',
      'licensesArtifactId': 'package-licenses',
      'releaseArtifactId': 'package-release',
    },
    'artifacts': _artifactFixtures(),
    'blockers': <Object?>['candidate record only'],
  };
}

List<Object?> _artifactFixtures() => <Object?>[
      _artifact('validator-report', 'validator.json', 'validator-report', '0'),
      _artifact(
        'package-layout',
        'package-layout.json',
        'package-layout',
        '1',
      ),
      _artifact(
        'package-symbols',
        'package-symbols.json',
        'package-symbols',
        '2',
      ),
      _artifact(
        'package-licenses',
        'package-licenses.json',
        'package-licenses',
        '3',
      ),
      _artifact(
        'package-release',
        'package-release.log',
        'package-release',
        '4',
      ),
      _artifact('runtime-render', 'runtime-render.png', 'runtime-render', '5'),
      _artifact(
        'runtime-readback',
        'runtime-readback.json',
        'runtime-readback',
        '6',
      ),
      _artifact(
        'runtime-diagnostic',
        'runtime-diagnostic.log',
        'runtime-diagnostic',
        '7',
      ),
      _artifact('cancellation-log', 'cancellation.log', 'log', '8'),
      _artifact('mip-lod-0', 'mip-lod-0.json', 'mip-lod-readback', '9'),
      _artifact('mip-lod-1', 'mip-lod-1.json', 'mip-lod-readback', 'a'),
      _artifact(
        'mip-base-only-control',
        'mip-base-only-control.json',
        'mip-base-only-control',
        'b',
      ),
    ];

Map<String, Object?> _artifact(
  String id,
  String filename,
  String kind,
  String hashCharacter,
) {
  return <String, Object?>{
    'id': id,
    'path': 'tools/out/plan017_decoder_mip_acceptance/$filename',
    'sha256': _hash(hashCharacter),
    'byteLength': 1,
    'kind': kind,
  };
}

String _hash(String character) => List<String>.filled(64, character).join();

Future<ProcessResult> _validateMutatedManifest(
  Map<String, Object?> manifest, {
  Map<String, Map<String, Object?>> records =
      const <String, Map<String, Object?>>{},
  bool verifyLocalArtifacts = false,
}) async {
  final directory = Directory.systemTemp.createTempSync('plan017_evidence_');
  try {
    final recordsDirectory = Directory('${directory.path}/records')
      ..createSync();
    final manifestFile = File('${directory.path}/manifest.json')
      ..writeAsStringSync(jsonEncode(manifest));
    for (final entry in records.entries) {
      File('${recordsDirectory.path}/${entry.key}')
          .writeAsStringSync(jsonEncode(entry.value));
    }
    return await Process.run(
      'python3',
      <String>[
        _validatorPath,
        '--manifest',
        manifestFile.path,
        '--records-dir',
        recordsDirectory.path,
        if (verifyLocalArtifacts) '--verify-local-artifacts',
      ],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
  } finally {
    directory.deleteSync(recursive: true);
  }
}
