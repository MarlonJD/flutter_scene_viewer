import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sourcePath =
    'tools/capability_matrix/plan014_selected_extension_capabilities.json';
const _generatorPath = 'tools/generate_capability_matrix.py';

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

void main() {
  test('generated capability matrix has explicit feature-target truth',
      () async {
    expect(File(_sourcePath).existsSync(), isTrue);
    expect(File(_generatorPath).existsSync(), isTrue);

    final source = Map<String, Object?>.from(
      jsonDecode(File(_sourcePath).readAsStringSync()) as Map,
    );
    expect(source['schemaVersion'], 1);
    expect(source['featureSet'], _features);
    expect(source['targetSet'], _targets);
    expect(
      source['scope'],
      'Plan 014 current evidence only; historical candidate runs are context, '
      'not current target evidence.',
    );
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
    expect(generated, contains('EXT_meshopt_compression'));
    expect(generated, contains('| iOS Simulator |'));
    expect(generated, isNot(contains('iOS native decode verified')));

    for (final path in <String>[
      'docs/PUBLIC_API.md',
      'docs/MATERIALS_AND_LIGHTING.md',
      'docs/RUNTIME_GLB_PIPELINE.md',
    ]) {
      final document = File(path).readAsStringSync();
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
    simulator['runtimeCapability'] = 'production-ready';

    final result = await _validateMutatedSource(source);
    expect(result.exitCode, isNot(0),
        reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('MatrixError'));
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
      contains('does not alter any current Plan 014 target row'),
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
          'synchronous decode accepts an internal deadline control but no '
          'external cancellation signal',
        );
      } else {
        expect(
          record['timeoutControl'],
          'Dart deadline enforced; native work is not stopped',
        );
      }
      expect(record['cancellationControl'], 'not enforced');
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
        'Meshopt timeout is cooperatively enforced inside the synchronous '
        'Dart decoder',
      ),
    );
    expect(
      runtimePipeline,
      contains(
        'Native decoder timeout is enforced only at the Dart MethodChannel '
        'result',
      ),
    );
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
        'packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
        '\nvoid FutureJniDeadline(int64_t timeoutMs, void* cancelToken) {}',
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
