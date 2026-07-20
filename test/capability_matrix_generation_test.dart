import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath =
    'tools/capability_matrix/selected_gltf_extension_capabilities.json';
const _staleSourcePath =
    'tools/capability_matrix/plan014_selected_extension_capabilities.json';
const _historicalSnapshotPath =
    'tools/capability_matrix/history/plan014_feature_target_snapshot.json';
const _historicalSourcePath =
    'tools/capability_matrix/history/plan014_selected_extension_capabilities.json';
const _generatorPath = 'tools/generate_capability_matrix.py';
const _artifactRoot = 'tools/out/plan017_decoder_mip_acceptance';
const _artifactPayloadSha256 =
    '2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881';
const _plan014LiveDifferencesSha256 =
    '7ac7b800fd80c6f6fc9e6e462014f7a3746d652af47567a263ffca86c84ef636';

const _features = <String>[
  'KHR_texture_transform',
  'KHR_materials_specular',
  'KHR_materials_ior',
  'KHR_materials_clearcoat',
  'KHR_materials_transmission',
  'KHR_materials_volume',
  'KHR_draco_mesh_compression',
  'EXT_meshopt_compression',
  'KHR_texture_basisu',
];

const _targets = <String>[
  'ios_simulator',
  'ios_physical',
  'android',
  'web',
];

const _plan014IosSimulatorEvidence = 'tools/out/material_extension_acceptance/'
    'plan014_extended_pbr_ios_simulator/evidence.json';

const _verifiedIosSimulatorFeatures = <String>{
  'KHR_texture_transform',
  'KHR_materials_specular',
  'KHR_materials_ior',
  'KHR_draco_mesh_compression',
};

const _expectedPlan014LiveDifferences = <Object?>[
  <String, Object?>{
    'feature': 'KHR_materials_clearcoat',
    'target': 'ios_simulator',
    'field': 'blocker',
    'historicalValue': 'current Plan 014 target run is absent; '
        'renderer-native integration is deferred to Plan 015',
    'liveValue': 'durable current target run is absent; renderer-native '
        'integration was completed separately by Plan 015',
  },
  <String, Object?>{
    'feature': 'KHR_materials_transmission',
    'target': 'ios_simulator',
    'field': 'blocker',
    'historicalValue': 'current Plan 014 target run is absent; '
        'renderer-native glass is deferred to Plan 016',
    'liveValue': 'durable current target run is absent; renderer-native '
        'glass was completed separately by Plan 016',
  },
  <String, Object?>{
    'feature': 'KHR_materials_volume',
    'target': 'ios_simulator',
    'field': 'blocker',
    'historicalValue': 'current Plan 014 target run is absent; full volume '
        'transport is deferred to Plan 016',
    'liveValue': 'durable current target run is absent; full volume transport '
        'was completed separately by Plan 016',
  },
  <String, Object?>{
    'feature': 'KHR_texture_basisu',
    'target': 'ios_simulator',
    'field': 'blocker',
    'historicalValue': 'no current Plan 014 iOS Simulator '
        'transcode/import/render or packaging run',
    'liveValue': 'no durable iOS Simulator transcode/import/render or '
        'packaging run',
  },
];

void main() {
  test('generated capability matrix has explicit feature-target truth',
      () async {
    expect(File(_sourcePath).existsSync(), isTrue);
    expect(File(_staleSourcePath).existsSync(), isFalse);
    expect(File(_historicalSnapshotPath).existsSync(), isTrue);
    expect(File(_historicalSourcePath).existsSync(), isTrue);
    expect(File(_generatorPath).existsSync(), isTrue);

    final source = Map<String, Object?>.from(
      jsonDecode(File(_sourcePath).readAsStringSync()) as Map,
    );
    expect(source['schemaVersion'], 2);
    expect(source['featureSet'], _features);
    expect(source['targetSet'], _targets);
    expect(
      source['scope'],
      'Selected glTF extension capability and evidence truth; historical, '
      'host, simulator, build-only, and target evidence remain independent.',
    );
    final historical = source['historicalPlan014']! as Map<String, Object?>;
    expect(historical['path'], _historicalSnapshotPath);
    expect(historical['sourcePath'], _historicalSourcePath);
    for (final key in <String>[
      'sourceSha256',
      'featureTargetRowsSha256',
      'historicalContextSha256',
    ]) {
      expect(historical[key], matches(RegExp(r'^[a-f0-9]{64}$')), reason: key);
    }
    final features =
        (source['features']! as List<Object?>).cast<Map<String, Object?>>();
    expect(
      features.map((feature) => feature['id']),
      orderedEquals(_features),
    );
    for (final feature in features) {
      final hostStages = Map<String, Object?>.from(
        feature['hostStages']! as Map,
      );
      expect(
        hostStages.keys,
        orderedEquals(<String>['parsed', 'preserved', 'decoded']),
        reason: '${feature['id']} host stages',
      );
      final targets = Map<String, Object?>.from(feature['targets']! as Map);
      expect(targets.keys, orderedEquals(_targets));
      for (final target in _targets) {
        final row = Map<String, Object?>.from(targets[target]! as Map);
        expect(
          row.keys,
          orderedEquals(<String>[
            'applied',
            'visuallyVerified',
            'runtimeCapability',
            'releaseMaturity',
            'targetEvidence',
            'blocker',
          ]),
          reason: '${feature['id']} / $target',
        );
        final isVerifiedSimulatorRow = target == 'ios_simulator' &&
            _verifiedIosSimulatorFeatures.contains(feature['id']);
        expect(
          row['applied'],
          isVerifiedSimulatorRow
              ? 'verified locally'
              : isNot('verified locally'),
        );
        expect(
          row['visuallyVerified'],
          isVerifiedSimulatorRow ? 'verified locally' : 'not run',
        );
        expect(
          row['targetEvidence'],
          isVerifiedSimulatorRow ? 'verified locally' : 'not run',
        );
        if (isVerifiedSimulatorRow) {
          expect(row['releaseMaturity'], 'candidate-only');
          expect(row['blocker'], contains(_plan014IosSimulatorEvidence));
        }
        expect(row['releaseMaturity'], isNot('production-ready'));
      }
    }

    final check = await Process.run(
      'python3',
      <String>[_generatorPath, '--check'],
    );
    expect(check.exitCode, 0, reason: '${check.stdout}\n${check.stderr}');

    final summaryResult = await Process.run(
      'python3',
      <String>[
        _generatorPath,
        '--summary-json',
        '--features',
        'EXT_meshopt_compression',
        '--targets',
        'ios_simulator',
      ],
    );
    expect(
      summaryResult.exitCode,
      0,
      reason: '${summaryResult.stdout}\n${summaryResult.stderr}',
    );
    expect(
      jsonDecode(summaryResult.stdout as String),
      <String, Object?>{
        'featureSet': <Object?>['EXT_meshopt_compression'],
        'targetSet': <Object?>['ios_simulator'],
        'allApplied': false,
        'allVisuallyVerified': false,
        'allTargetEvidenceVerified': false,
        'productionReady': false,
      },
    );

    final generated =
        File('docs/generated/capability_matrix.md').readAsStringSync();
    expect(
      generated,
      contains('Host decode/validator evidence is not target render evidence.'),
    );
    expect(generated, contains(_sourcePath));
    expect(generated, isNot(contains(_staleSourcePath)));
    expect(generated, isNot(contains('current Plan 014 target row')));
    expect(generated, contains('EXT_meshopt_compression'));
    expect(generated, contains('| iOS Simulator |'));
    expect(generated, isNot(contains('iOS native decode verified')));

    for (final path in <String>[
      'docs/PUBLIC_API.md',
      'docs/MATERIALS_AND_LIGHTING.md',
      'docs/RUNTIME_GLB_PIPELINE.md',
    ]) {
      final document = File(
        path,
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
      expect(document, contains('Plan 014 iOS Simulator evidence'));
      expect(document, contains('`verified locally`'), reason: path);
      expect(
        document,
        contains('physical iOS, Android, and Web remain `not run`'),
        reason: path,
      );
      expect(
        document,
        contains('generated/capability_matrix.md'),
        reason: path,
      );
    }
    final quality = File('docs/QUALITY_SCORE.md').readAsStringSync();
    expect(quality, contains('Selected glTF extension evidence'));
    expect(quality, contains('generated/capability_matrix.md'));
  });

  test('full Plan 014 payload and four live blocker changes are frozen',
      () async {
    final frozen = jsonDecode(File(_historicalSourcePath).readAsStringSync())
        as Map<String, Object?>;
    final snapshot =
        jsonDecode(File(_historicalSnapshotPath).readAsStringSync())
            as Map<String, Object?>;
    expect(frozen['schemaVersion'], 1);
    expect((frozen['features']! as List<Object?>), hasLength(9));
    final rowCount = (frozen['features']! as List<Object?>).fold<int>(
      0,
      (count, rawFeature) =>
          count +
          ((rawFeature! as Map<String, Object?>)['targets']!
                  as Map<String, Object?>)
              .length,
    );
    expect(rowCount, 36);
    expect(
      snapshot['liveTargetRowDifferences'],
      _expectedPlan014LiveDifferences,
    );
    expect(
      snapshot['liveTargetRowDifferencesSha256'],
      _plan014LiveDifferencesSha256,
    );

    final mutated = jsonDecode(jsonEncode(frozen)) as Map<String, Object?>;
    _targetRow(
      mutated,
      'EXT_meshopt_compression',
      'web',
    )['blocker'] = 'eroded historical row';
    final result = await _validateMutatedHistoricalPayload(mutated);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('historical Plan 014 row payload changed'));
  });

  test('capability promotion requires verified local artifact proof', () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final row = _targetRow(source, 'EXT_meshopt_compression', 'ios_simulator');
    row
      ..['applied'] = 'verified locally'
      ..['visuallyVerified'] = 'verified locally'
      ..['runtimeCapability'] = 'production-ready'
      ..['releaseMaturity'] = 'production-ready'
      ..['targetEvidence'] = 'verified locally'
      ..['blocker'] = 'none';
    final manifest = jsonDecode(
      File('tools/decoder_mip_acceptance/manifest.json').readAsStringSync(),
    ) as Map;
    final claims = (manifest['claims'] as List).cast<Map>();
    final claim = claims.singleWhere(
      (candidate) =>
          candidate['feature'] == 'EXT_meshopt_compression' &&
          candidate['target'] == 'ios_simulator',
    );
    claim
      ..['evidenceStatus'] = 'verified locally'
      ..['maturity'] = 'production-ready'
      ..['recordIds'] = <Object?>['missing-artifact-record']
      ..['blocker'] = 'none';

    final result = await _validatePromotionWithoutArtifactProof(
      source,
      manifest,
    );
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('verified local artifact proof'));
  });

  test('loadSource accepts verified artifacts and rejects a tampered artifact',
      () async {
    final verified = await _loadPromotedSourceWithLocalArtifacts(
      tamperRuntimeReadback: false,
    );
    expect(verified.exitCode, 0,
        reason: '${verified.stdout}\n${verified.stderr}');

    final tampered = await _loadPromotedSourceWithLocalArtifacts(
      tamperRuntimeReadback: true,
    );
    expect(tampered.exitCode, isNot(0),
        reason: '${tampered.stdout}\n${tampered.stderr}');
    expect(tampered.stderr, contains('artifact SHA-256 changed'));
  });

  test('capability source rejects unsupported Web codec promotion', () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final features = (source['features'] as List).cast<Map>();
    final basisu = features.singleWhere(
      (feature) => feature['id'] == 'KHR_texture_basisu',
    );
    final web = (basisu['targets'] as Map)['web'] as Map;
    web['applied'] = 'not run';
    web['runtimeCapability'] = 'candidate-only native plugin';
    web['releaseMaturity'] = 'candidate-only';

    final result = await _validateMutatedSource(source);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('MatrixError'));
  });

  test('capability source rejects production runtime without target gates',
      () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final features = (source['features'] as List).cast<Map>();
    final meshopt = features.singleWhere(
      (feature) => feature['id'] == 'EXT_meshopt_compression',
    );
    final simulator = (meshopt['targets'] as Map)['ios_simulator'] as Map;
    simulator
      ..['applied'] = 'verified locally'
      ..['visuallyVerified'] = 'verified locally'
      ..['runtimeCapability'] = 'production-ready'
      ..['releaseMaturity'] = 'production-ready'
      ..['targetEvidence'] = 'verified locally'
      ..['blocker'] = 'host evidence';

    final result = await _validateMutatedSource(source);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('durable evidence'));
  });

  test('capability source rejects hyphenated release pending label', () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    _targetRow(
      source,
      'KHR_materials_clearcoat',
      'ios_simulator',
    )['releaseMaturity'] = 'release-pending';

    final result = await _validateMutatedSource(source);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('release pending'));
  });

  test('simulator evidence cannot promote a physical target', () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final physical = _targetRow(
      source,
      'KHR_texture_basisu',
      'ios_physical',
    );
    physical
      ..['applied'] = 'verified locally'
      ..['visuallyVerified'] = 'verified locally'
      ..['runtimeCapability'] = 'production-ready'
      ..['releaseMaturity'] = 'production-ready'
      ..['targetEvidence'] = 'verified locally'
      ..['blocker'] = 'covered by iOS Simulator evidence';

    final result = await _validateMutatedSource(source);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('matching durable evidence'));
  });

  test('capability source rejects host leakage and evidence-row erosion',
      () async {
    final mutations = <void Function(Map)>[
      (source) => _targetRow(
            source,
            'KHR_texture_transform',
            'ios_physical',
          )['applied'] = 'verified locally',
      (source) => _targetRow(
            source,
            'EXT_meshopt_compression',
            'ios_simulator',
          )['applied'] = 'verified locally',
      (source) => _targetRow(
            source,
            'KHR_texture_transform',
            'ios_simulator',
          )['blocker'] = 'upstream support missing',
      (source) => _targetRow(
            source,
            'KHR_materials_specular',
            'ios_simulator',
          )['blocker'] = 'upstream support missing',
      (source) => _targetRow(
            source,
            'KHR_materials_ior',
            'ios_simulator',
          )['blocker'] = 'upstream support missing',
    ];

    for (final mutate in mutations) {
      final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
      mutate(source);
      final result = await _validateMutatedSource(source);
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('MatrixError'));
    }
  });

  test('capability source constrains applied and runtime vocabularies',
      () async {
    for (final mutation in <Map<String, String>>[
      <String, String>{'applied': 'host verified'},
      <String, String>{'runtimeCapability': 'candidate'},
    ]) {
      final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
      _targetRow(
        source,
        'EXT_meshopt_compression',
        'ios_simulator',
      ).addAll(mutation);
      final result = await _validateMutatedSource(source);
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('MatrixError'));
    }
  });

  test('historical simulator evidence is separate from current target rows',
      () {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final rawHistory = source['historicalContext'];
    expect(rawHistory, isA<List>());
    if (rawHistory is! List) {
      return;
    }
    expect(
      rawHistory,
      <Object?>[
        <String, Object?>{
          'feature': 'KHR_draco_mesh_compression',
          'target': 'ios_simulator',
          'evidenceStatus': 'verified locally',
          'evidenceDate': '2026-07-04',
          'scope': 'historical Plan 013 iPhone 17 Simulator candidate run',
          'source':
              'docs/exec-plans/completed/013_v2_production_glb_pipeline.md',
          'artifactDurability': 'not durable',
          'currentPlan014TargetEvidence': 'verified locally',
          'releaseMaturity': 'candidate-only',
        },
        <String, Object?>{
          'feature': 'KHR_texture_basisu',
          'target': 'ios_simulator',
          'evidenceStatus': 'verified locally',
          'evidenceDate': '2026-07-05',
          'scope': 'historical Plan 013 iPhone 17 Simulator candidate run',
          'source':
              'docs/exec-plans/completed/013_v2_production_glb_pipeline.md',
          'artifactDurability': 'not durable',
          'currentPlan014TargetEvidence': 'not run',
          'releaseMaturity': 'candidate-only',
        },
      ],
    );
    final generated =
        File('docs/generated/capability_matrix.md').readAsStringSync();
    expect(generated, contains('Historical candidate context'));
    expect(
      generated,
      contains('does not alter any live target row'),
    );
  });

  test('native codec platform labels reject unsupported promotion', () async {
    final mutations = <void Function(Map)>[
      (source) => _targetRow(
            source,
            'KHR_draco_mesh_compression',
            'ios_simulator',
          )['runtimeCapability'] = 'diagnostic-only',
      (source) => _targetRow(
            source,
            'KHR_draco_mesh_compression',
            'android',
          )['releaseMaturity'] = 'diagnostic-only',
      (source) => _targetRow(
            source,
            'KHR_texture_basisu',
            'ios_physical',
          )['runtimeCapability'] = 'diagnostic-only',
      (source) => _targetRow(
            source,
            'KHR_texture_basisu',
            'android',
          )['releaseMaturity'] = 'diagnostic-only',
    ];
    for (final mutate in mutations) {
      final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
      mutate(source);
      final result = await _validateMutatedSource(source);
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('MatrixError'));
    }
  });

  test('decoder timeout cancellation and release blockers stay explicit',
      () async {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    final rawBoundaries = source['decoderControlBoundaries'];
    expect(rawBoundaries, isA<List>());
    if (rawBoundaries is! List) {
      return;
    }
    expect(rawBoundaries, hasLength(3));
    expect(
      rawBoundaries.map((record) => (record as Map)['feature']),
      <String>[
        'EXT_meshopt_compression',
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      ],
    );
    for (final rawRecord in rawBoundaries) {
      final record = rawRecord as Map;
      if (record['feature'] == 'EXT_meshopt_compression') {
        expect(
          record['allocationControl'],
          'declared-output and aggregate rewrite budgets use atomic '
          'commit outside the decoder loop',
        );
        expect(
          record['timeoutControl'],
          'cooperative Dart deadline checkpoints are enforced across '
          'claimed modes and filters',
        );
        expect(
          record['resourceRelease'],
          'timed-out decode buffers become garbage-collectible after stack '
          'unwind; deterministic collection is not guaranteed',
        );
        expect(
          record['blockingApi'],
          'asynchronous decoder accepts an internal deadline control and a '
          'load cancellation token',
        );
        expect(
          record['cancellationControl'],
          'cooperative caller cancellation checkpoints are enforced across '
          'claimed modes and filters',
        );
      } else if (record['feature'] == 'KHR_draco_mesh_compression') {
        expect(
          record['allocationControl'],
          'every reachable native request, codec, preflight, decoded output, '
          'and retained-result allocation is request-owned; managed platform '
          'message copies are size-guarded but outside maxNativeWorkingBytes',
        );
        expect(
          record['timeoutControl'],
          'one shared Dart deadline cancels the active request; native stop '
          'latency is bounded by pinned codec-loop checkpoints',
        );
        expect(
          record['cancellationControl'],
          'requestId and cancelDecode reach a request-owned atomic control '
          'checked inside pinned topology, attribute, and output loops',
        );
        expect(
          record['resourceRelease'],
          'request-owned native allocations release by normal unwind after '
          'success, cancellation, deadline, budget, heap failure, and '
          'corruption; exact live-byte gates cover bridge and platform-copy '
          'lifetimes',
        );
        expect(
          record['blockingApi'],
          'the repo-local pinned DecodeMeshFromBuffer overload and platform '
          'serializers accept explicit request control; no global/TLS '
          'current-request state is used',
        );
        expect(
          record['bridgeContract'],
          'decodeGlb carries a unique requestId; missing native controls fail '
          'atomically before registry or native work; signed-size guards and '
          'pre/post-copy stop checks keep native results alive until atomic '
          'managed serialization completes; every non-detached request '
          'delivers exactly one response or typed terminal error and no '
          'partial response escapes',
        );
      } else {
        expect(
          record['allocationControl'],
          'every reached native request input, preflight, metadata, ETC1S '
          'codec state, Zstd workspace, decoded output, retained-result, and '
          'bridge-staging allocation is request-owned; managed platform '
          'message copies are size-guarded but outside maxNativeWorkingBytes',
        );
        expect(
          record['timeoutControl'],
          'one shared Dart deadline cancels the active request; native stop '
          'latency is bounded by metadata-owner, image, ETC1S/UASTC '
          'block-row, and Zstd block-output checkpoints',
        );
        expect(
          record['cancellationControl'],
          'requestId and cancelDecode reach a request-owned atomic control '
          'checked inside pinned BasisU and Zstd codec loops',
        );
        expect(
          record['resourceRelease'],
          'request-owned native allocations release by normal unwind after '
          'success, cancellation, deadline, budget, heap failure, corruption, '
          'and platform serialization failure; exact live-byte gates cover '
          'codec, bridge, and platform-copy lifetimes',
        );
        expect(
          record['blockingApi'],
          'the repo-local pinned KTX2, ETC1S, and static-Zstd paths plus '
          'platform serializers accept explicit request control; no '
          'global/TLS current-request state is used',
        );
        expect(
          record['bridgeContract'],
          'decodeGlb carries a unique requestId; signed-size guards and '
          'pre/post-copy stop checks keep native results alive until atomic '
          'managed serialization completes; every non-detached request '
          'delivers exactly one response or typed terminal error and no '
          'partial response escapes',
        );
      }
      expect(record['resourceRelease'], isNot('guaranteed'));
      expect(record['evidenceSources'], isA<List>());
      for (final sourcePath in record['evidenceSources'] as List) {
        expect(File(sourcePath as String).existsSync(), isTrue);
      }
    }

    final generated =
        File('docs/generated/capability_matrix.md').readAsStringSync();
    expect(generated, contains('Decoder control blockers'));
    expect(
      generated,
      contains('does not promote any host or target capability'),
    );
    final runtimePipeline =
        File('docs/RUNTIME_GLB_PIPELINE.md').readAsStringSync();
    expect(
      runtimePipeline,
      contains(
        'Meshopt timeout and caller cancellation are cooperatively enforced '
        'inside the',
      ),
    );
    expect(runtimePipeline, contains('yieldable Dart decoder'));
    expect(
      runtimePipeline,
      contains(
        'Native decoder timeout and caller cancellation now use one active '
        'MethodChannel',
      ),
    );
    expect(runtimePipeline, contains('request id. Android runs bounded'));
    expect(
      runtimePipeline,
      contains('generated/capability_matrix.md#decoder-control-blockers'),
    );

    for (var index = 0; index < rawBoundaries.length; index += 1) {
      final mutated = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
      final boundaries = mutated['decoderControlBoundaries'] as List;
      (boundaries[index] as Map)['timeoutControl'] = 'enforced';
      (boundaries[index] as Map)['cancellationControl'] = 'enforced';
      (boundaries[index] as Map)['resourceRelease'] = 'guaranteed';
      final result = await _validateMutatedSource(mutated);
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('MatrixError'));
    }

    final sourceMutations = <(String, String)>[
      (
        'lib/src/internal/meshopt_decoder.dart',
        '\nvoid futureControl(DateTime? deadline, bool Function()? shouldCancel) {}',
      ),
      (
        'packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h',
        '\nDecodeMeshFromBuffer(DecoderBuffer*, CancelToken*, int timeoutMs);',
      ),
      (
        'packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h',
        '\nbool start_transcoding(CancelToken*, uint64_t deadline);',
      ),
      (
        'lib/src/internal/glb_native_decoder_probe.dart',
        "\nfinal futureControls = {'timeoutMs': 1, 'cancelToken': 'future'};",
      ),
      (
        'packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc',
        '\nvoid FutureBridgeControl(int64_t deadline, void* cancelToken) {}',
      ),
      (
        'packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java',
        '\n// future MethodCall timeoutMs and cancelToken handling',
      ),
      (
        'packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.h',
        '\n// mutated Task 4 control contract',
      ),
      (
        'packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.cc',
        '\n// mutated Task 4 control implementation',
      ),
      (
        'packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FsvDecodeRequestRegistry.java',
        '\n// mutated Task 4 Android registry',
      ),
      (
        'packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.h',
        '\n// mutated Task 4 iOS control contract',
      ),
      (
        'packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.cc',
        '\n// mutated Task 4 iOS control implementation',
      ),
      (
        'packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.h',
        '\n// mutated Task 4 iOS registry contract',
      ),
      (
        'packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.cc',
        '\n// mutated Task 4 iOS registry implementation',
      ),
      (
        'packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
        '\nvoid FutureJniDeadline(int64_t timeoutMs, void* cancelToken) {}',
      ),
      (
        'packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.h',
        '\n// mutated Task 4 control contract',
      ),
      (
        'packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.cc',
        '\n// mutated Task 4 control implementation',
      ),
      (
        'packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FsvDecodeRequestRegistry.java',
        '\n// mutated Task 4 Android registry',
      ),
      (
        'packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.h',
        '\n// mutated Task 4 iOS control contract',
      ),
      (
        'packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.cc',
        '\n// mutated Task 4 iOS control implementation',
      ),
      (
        'packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.h',
        '\n// mutated Task 4 iOS registry contract',
      ),
      (
        'packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.cc',
        '\n// mutated Task 4 iOS registry implementation',
      ),
      (
        'packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm',
        '\n// future FlutterMethodCall deadline and cancellation handling',
      ),
    ];
    for (final (sourcePath, mutation) in sourceMutations) {
      final result = await _validateMutatedDecoderControlSource(
        sourcePath,
        mutation,
      );
      expect(result.exitCode, isNot(0),
          reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('MatrixError'));
    }
  });
}

Map _targetRow(Map source, String featureId, String target) {
  final features = (source['features'] as List).cast<Map>();
  final feature = features.singleWhere(
    (candidate) => candidate['id'] == featureId,
  );
  return (feature['targets'] as Map)[target] as Map;
}

Future<ProcessResult> _loadPromotedSourceWithLocalArtifacts({
  required bool tamperRuntimeReadback,
}) async {
  final scratch = Directory.systemTemp.createTempSync('plan017_load_source_');
  final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final relativeArtifactDirectory = '$_artifactRoot/load-source-$suffix';
  final artifactDirectory = Directory(relativeArtifactDirectory)..createSync();
  try {
    final source = jsonDecode(File(_sourcePath).readAsStringSync()) as Map;
    _targetRow(source, 'EXT_meshopt_compression', 'ios_simulator')
      ..['applied'] = 'verified locally'
      ..['visuallyVerified'] = 'verified locally'
      ..['runtimeCapability'] = 'production-ready'
      ..['releaseMaturity'] = 'production-ready'
      ..['targetEvidence'] = 'verified locally'
      ..['blocker'] = 'none';

    const recordId = 'meshopt-ios-simulator-proof';
    final artifacts = <Object?>[];
    for (final (id, filename, kind) in <(String, String, String)>[
      ('validator-report', 'validator.json', 'validator-report'),
      ('package-layout', 'package-layout.json', 'package-layout'),
      ('package-licenses', 'package-licenses.json', 'package-licenses'),
      ('runtime-render', 'runtime-render.png', 'runtime-render'),
      ('runtime-readback', 'runtime-readback.json', 'runtime-readback'),
      ('cancellation-log', 'cancellation.log', 'log'),
    ]) {
      final payload =
          tamperRuntimeReadback && id == 'runtime-readback' ? 'y' : 'x';
      File('${artifactDirectory.path}/$filename').writeAsStringSync(payload);
      artifacts.add(<String, Object?>{
        'id': id,
        'path': '$relativeArtifactDirectory/$filename',
        'sha256': _artifactPayloadSha256,
        'byteLength': 1,
        'kind': kind,
      });
    }

    final manifest = jsonDecode(
      File('tools/decoder_mip_acceptance/manifest.json').readAsStringSync(),
    ) as Map;
    final claims = (manifest['claims'] as List).cast<Map>();
    claims.singleWhere(
      (candidate) =>
          candidate['feature'] == 'EXT_meshopt_compression' &&
          candidate['target'] == 'ios_simulator',
    )
      ..['evidenceStatus'] = 'verified locally'
      ..['maturity'] = 'production-ready'
      ..['recordIds'] = <Object?>[recordId]
      ..['blocker'] = 'none';
    manifest['records'] = <Object?>['records/$recordId.json'];

    final sourceFile = File('${scratch.path}/source.json')
      ..writeAsStringSync(jsonEncode(source));
    final manifestFile = File('${scratch.path}/manifest.json')
      ..writeAsStringSync(jsonEncode(manifest));
    final recordsDirectory = Directory('${scratch.path}/records')..createSync();
    File('${recordsDirectory.path}/$recordId.json').writeAsStringSync(
      jsonEncode(
        _meshoptPromotionRecord(
          id: recordId,
          artifacts: artifacts,
        ),
      ),
    );
    return await Process.run(
      'python3',
      <String>[
        '-c',
        'import pathlib,sys; '
            'import tools.generate_capability_matrix as generator; '
            'generator.SOURCE_PATH=pathlib.Path(sys.argv[1]); '
            'generator.EVIDENCE_MANIFEST_PATH=pathlib.Path(sys.argv[2]); '
            'generator.EVIDENCE_RECORDS_DIR=pathlib.Path(sys.argv[3]); '
            'generator.load_source()',
        sourceFile.path,
        manifestFile.path,
        recordsDirectory.path,
      ],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
  } finally {
    if (artifactDirectory.existsSync()) {
      artifactDirectory.deleteSync(recursive: true);
    }
    scratch.deleteSync(recursive: true);
  }
}

Map<String, Object?> _meshoptPromotionRecord({
  required String id,
  required List<Object?> artifacts,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    'capturedAt': '2026-07-19T00:00:00Z',
    'evidenceStatus': 'verified locally',
    'maturity': 'production-ready',
    'features': <Object?>['EXT_meshopt_compression'],
    'gates': <Object?>[
      'package-install',
      'runtime',
      'cancellation-resource',
    ],
    'source': <String, Object?>{
      'viewerBaseCommit': '87944991be7e44fe5ea253a5f013ab0cc3230d44',
      'viewerDiffSha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'rendererCommit': '5dcf6fce7dc36719e64e536faba9538fe9fa1022',
      'packageVersions': <String, Object?>{
        'flutter_scene_viewer': '0.1.0-alpha.0',
        'flutter_scene_viewer_draco': '0.1.0-alpha.0',
        'flutter_scene_viewer_basisu': '0.1.0-alpha.0',
      },
    },
    'codecs': <Object?>[],
    'fixtures': <Object?>[],
    'target': <String, Object?>{
      'kind': 'ios_simulator',
      'deviceId': 'test-simulator',
      'device': 'test simulator',
      'os': 'test OS',
      'architecture': 'arm64',
      'buildMode': 'release',
      'backend': 'Impeller Metal',
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
    'runtimeDiagnostic': null,
    'cancellation': <String, Object?>{
      'trigger': 'decode-loop',
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
    'mipChains': <Object?>[],
    'mipSampling': null,
    'validator': <String, Object?>{
      'name': 'gltf-validator',
      'version': '2.0.0-dev.3.10',
      'passed': true,
      'reportArtifactId': 'validator-report',
    },
    'package': <String, Object?>{
      'pluginRegistered': false,
      'nativeSymbolsVerified': false,
      'licensesVerified': true,
      'releaseStrippingVerified': false,
      'layoutArtifactId': 'package-layout',
      'symbolsArtifactId': null,
      'licensesArtifactId': 'package-licenses',
      'releaseArtifactId': null,
    },
    'artifacts': artifacts,
    'blockers': <Object?>[],
  };
}

Future<ProcessResult> _validateMutatedSource(Map source) async {
  final directory = Directory.systemTemp.createTempSync('plan014_matrix_');
  try {
    final sourceFile = File('${directory.path}/source.json')
      ..writeAsStringSync(jsonEncode(source));
    final result = await Process.run(
      'python3',
      <String>[
        '-c',
        'import json,sys; '
            'from tools.generate_capability_matrix import validate_source; '
            'validate_source(json.load(open(sys.argv[1], encoding="utf-8")))',
        sourceFile.path,
      ],
      workingDirectory: Directory.current.path,
      environment: <String, String>{
        ...Platform.environment,
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    return result;
  } finally {
    directory.deleteSync(recursive: true);
  }
}

Future<ProcessResult> _validateMutatedHistoricalPayload(Map source) async {
  final directory = Directory.systemTemp.createTempSync('plan014_history_');
  try {
    final sourceFile = File('${directory.path}/source.json')
      ..writeAsStringSync(jsonEncode(source));
    return await Process.run(
      'python3',
      <String>[
        '-c',
        'import json,sys; '
            'from tools.generate_capability_matrix import '
            'validate_historical_plan014_payload; '
            'validate_historical_plan014_payload('
            'json.load(open(sys.argv[1], encoding="utf-8")))',
        sourceFile.path,
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

Future<ProcessResult> _validatePromotionWithoutArtifactProof(
  Map source,
  Map manifest,
) async {
  final directory = Directory.systemTemp.createTempSync('plan017_promotion_');
  try {
    final sourceFile = File('${directory.path}/source.json')
      ..writeAsStringSync(jsonEncode(source));
    final manifestFile = File('${directory.path}/manifest.json')
      ..writeAsStringSync(jsonEncode(manifest));
    return await Process.run(
      'python3',
      <String>[
        '-c',
        'import json,sys; '
            'from tools.generate_capability_matrix import validate_source; '
            'validate_source('
            'json.load(open(sys.argv[1], encoding="utf-8")), '
            'evidence_manifest=json.load('
            'open(sys.argv[2], encoding="utf-8")), '
            'evidence_artifacts_verified=False)',
        sourceFile.path,
        manifestFile.path,
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

Future<ProcessResult> _validateMutatedDecoderControlSource(
  String relativePath,
  String mutation,
) {
  return Process.run(
    'python3',
    <String>[
      '-c',
      'import sys; '
          'from tools.generate_capability_matrix import '
          'decoder_control_source_texts,validate_decoder_control_sources; '
          'sources=decoder_control_source_texts(); '
          'sources[sys.argv[1]] += sys.argv[2]; '
          'validate_decoder_control_sources(sources)',
      relativePath,
      mutation,
    ],
    workingDirectory: Directory.current.path,
    environment: <String, String>{
      ...Platform.environment,
      'PYTHONDONTWRITEBYTECODE': '1',
    },
  );
}
