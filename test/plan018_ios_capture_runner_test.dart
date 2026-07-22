// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _runner = 'tools/run_plan018_ios_capture.py';
const _udid = '10C2CF77-CBA8-4948-ADD5-24C49D375059';
const _stateSha =
    '385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843';
const _rootPubspecSha =
    '89538562bf96a228fdd13c0d0a6a2ee92df27616615f4c42116b61ca464d5586';
const _rootLockSha =
    '7c9415caf27fdca2453234a7ea61e7a54df79eef25947a7767e4486206eeaa95';
const _pin = '766351c865c621e8720c726f9aa51173ce76e786';
const _cacheTree = '1479be24e5472cece6c041151bc48f663146da94';
const _environmentSha =
    'ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a';
const _viewerWidgetSha =
    '451151df37c0b72b340b64068eb4d6b54c1c538a614e80a7f01adfd7e3abe04f';
const _sheenShaderSha =
    '6e32cf046a99495228340030fb2f85720f3dc81cd33f2f0b30f5d265091ea630';
const _sheenUv1ShaderSha =
    'bca51c16988070fd644dc8596991edac7e97df2b254371834b5726ee8d3873ee';
const _clearcoatSheenShaderSha =
    'b0a4416c28399103d64e9e3b9626998eaaf3779e49aaf1ccdd9be925697c066f';
const _clearcoatSheenUv1ShaderSha =
    '4051d34a98e3c93ef86345957416a77d425447ad831dfeb8bc551d17399ce8d4';
const _flutter = '/Users/marlonjd/Developer/flutter/bin/flutter';
const _harness =
    '/Users/marlonjd/Developer/library/flutter_scene_viewer/tools/out/'
    'material_extension_acceptance/plan018_controlled_comparison/'
    'flutter_ios_harness';

const _views = <String, List<String>>{
  'sheen_chair': <String>['close', 'grazing'],
  'sheen_cloth': <String>['close', 'grazing'],
  'glam_velvet_sofa': <String>['close', 'grazing'],
  'toycar': <String>['close', 'grazing', 'context'],
};
const _passes = <String>['directOnly', 'iblOnly', 'combined'];

void main() {
  test('runner hard-pins the current renderer checkout contract', () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
import json

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(json.dumps({
    "pin": module.EXPECTED_PIN,
    "cacheTree": module.EXPECTED_CACHE_TREE,
    "checkout": str(module.CACHE_CHECKOUT),
    "packageUri": module.expected_flutter_scene_package_uri(),
}))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );

    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(
      jsonDecode(probe.stdout as String),
      <String, Object?>{
        'pin': _pin,
        'cacheTree': _cacheTree,
        'checkout': '/Users/marlonjd/.pub-cache/git/flutter_scene-$_pin',
        'packageUri':
            'file:///Users/marlonjd/.pub-cache/git/flutter_scene-$_pin/'
                'packages/flutter_scene',
      },
    );
  });

  test('plan mode validates the exact device and emits the bounded drive',
      () async {
    final fixture = await _deviceFixture();
    final runRoot = 'tools/out/material_extension_acceptance/'
        'plan018_controlled_comparison/ios_simulator/'
        'candidate-run-plan-test-${DateTime.now().microsecondsSinceEpoch}';
    addTearDown(() async {
      await fixture.parent.delete(recursive: true);
    });

    final result = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final plan = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(plan['mode'], 'plan');
    expect(plan['modelId'], 'sheen_chair');
    expect(plan['udid'], _udid);
    expect(plan['workingDirectory'], _harness);
    expect(
      (plan['command'] as List<dynamic>).cast<String>(),
      <String>[
        _flutter,
        'drive',
        '--no-pub',
        '--debug',
        '--enable-impeller',
        '-d',
        _udid,
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/plan018_capture_test.dart',
        '--dart-define=PLAN018_MODEL_ID=sheen_chair',
      ],
    );
    expect(plan['shell'], isFalse);
    expect(plan['captureTimeoutSeconds'], 1800.0);
    expect(plan['terminationGraceSeconds'], 10.0);
    expect(
      plan['timeoutContract'],
      <String, Object?>{
        'deviceDiscoveryTimeoutSeconds': 60.0,
        'harnessValidationTimeoutSeconds': 60.0,
        'captureTimeoutSeconds': 1800.0,
        'terminationGraceSeconds': 10.0,
        'killWaitSeconds': 5.0,
        'streamDrainTimeoutSeconds': 1.0,
      },
    );
    final preflight = plan['preflight'] as Map<String, dynamic>;
    expect(preflight['flutterScenePin'], _pin);
    expect(preflight['pubCacheHead'], _pin);
    expect(preflight['pubCacheClean'], isTrue);
    expect(preflight['generatedHarnessValidator'], 'passed');
    expect(
      (preflight['sourceSha256']
          as Map<String, dynamic>)['lib/src/viewer_widget.dart'],
      _viewerWidgetSha,
    );
    expect(
      (preflight['sourceSha256']
          as Map<String, dynamic>)['shaders/fsviewer_sheen_extended_pbr.frag'],
      _sheenShaderSha,
    );
    expect(
      (preflight['sourceSha256'] as Map<String, dynamic>)[
          'shaders/fsviewer_sheen_extended_pbr_uv1.frag'],
      _sheenUv1ShaderSha,
    );
    expect(
      (preflight['sourceSha256'] as Map<String, dynamic>)[
          'shaders/fsviewer_clearcoat_sheen_extended_pbr.frag'],
      _clearcoatSheenShaderSha,
    );
    expect(
      (preflight['sourceSha256'] as Map<String, dynamic>)[
          'shaders/fsviewer_clearcoat_sheen_extended_pbr_uv1.frag'],
      _clearcoatSheenUv1ShaderSha,
    );
    expect(plan['simulatorLifecycleActions'], isEmpty);
    expect(Directory(runRoot).existsSync(), isFalse);

    final occupiedRoot = Directory(runRoot)..createSync(recursive: true);
    addTearDown(() async {
      if (occupiedRoot.existsSync()) {
        await occupiedRoot.delete(recursive: true);
      }
    });
    final unexpectedSelectedPng =
        File('${occupiedRoot.path}/sheen_chair_unexpected.png');
    _writePng(unexpectedSelectedPng);
    final overwrite = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );
    expect(overwrite.exitCode, isNot(0));
    expect('${overwrite.stderr}', contains('overwrite'));
    unexpectedSelectedPng.deleteSync();

    final orphan = File('${occupiedRoot.path}/orphan.txt')
      ..writeAsStringSync('partial evidence');
    final unexpectedRootEntry = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );
    expect(unexpectedRootEntry.exitCode, isNot(0));
    expect('${unexpectedRootEntry.stderr}', contains('unexpected'));
    orphan.deleteSync();

    final wrongDevice = File('${occupiedRoot.path}/device.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'udid': 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
        }),
      );
    final mismatchedDevice = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );
    expect(mismatchedDevice.exitCode, isNot(0));
    expect('${mismatchedDevice.stderr}', contains('Simulator identity'));
    wrongDevice.deleteSync();

    await _writeFixtureModel(
      occupiedRoot,
      'sheen_cloth',
      fixtureValidation: false,
    );
    File('${occupiedRoot.path}/device.json').writeAsStringSync(
      jsonEncode(plan['device']),
    );
    final manifests = Directory('${occupiedRoot.path}/manifests')
      ..createSync(recursive: true);
    File('${manifests.path}/sheen_cloth.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'status': 'candidate-only',
        'executionEvidence': 'verified locally',
        'modelId': 'sheen_cloth',
        'captureExitCode': 0,
        'startedAt': '2026-07-21T08:35:00.000000+00:00',
        'captureFinishedAt': '2026-07-21T08:35:30.000000+00:00',
        'device': plan['device'],
        'preflight': <String, Object?>{'sourceSha256': 'stale'},
        'postflight': <String, Object?>{'sourceSha256': 'stale'},
        'artifactRecordSha256': List<String>.filled(64, '0').join(),
      }),
    );
    final staleSibling = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );
    expect(staleSibling.exitCode, isNot(0));
    expect('${staleSibling.stderr}', contains('source/dependency state'));

    final invalidModel = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'toycar_special_case',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        fixture.path,
      ],
    );
    expect(invalidModel.exitCode, isNot(0));

    final duplicateFixture = await _deviceFixture(duplicate: true);
    addTearDown(() async {
      await duplicateFixture.parent.delete(recursive: true);
    });
    final duplicate = await Process.run(
      'python3',
      <String>[
        _runner,
        '--plan',
        '--model',
        'sheen_chair',
        '--udid',
        _udid,
        '--run-root',
        runRoot,
        '--device-fixture',
        duplicateFixture.path,
      ],
    );
    expect(duplicate.exitCode, isNot(0));
    expect('${duplicate.stderr}', contains('exactly one'));
  });

  test('fixture seam validates ordered READY/COMPLETE response and PNGs',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(fixtureRoot, 'sheen_chair');

    final valid = await _validateFixture(fixtureRoot, model: 'sheen_chair');
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
    final record = jsonDecode(valid.stdout as String) as Map<String, dynamic>;
    expect(record['status'], 'candidate-only');
    expect(record['executionEvidence'], 'not run');
    expect(record['fixtureValidation'], isTrue);
    expect(record['modelId'], 'sheen_chair');
    expect(record['readyCount'], 6);
    expect((record['artifacts'] as List<dynamic>), hasLength(6));
    expect(File('${fixtureRoot.path}/evidence.json').existsSync(), isFalse);

    final response = File(
      '${fixtureRoot.path}/plan018_integration_response_sheen_chair.json',
    );
    final decoded =
        jsonDecode(response.readAsStringSync()) as Map<String, dynamic>;
    final names =
        (decoded['expectedScreenshotNames'] as List<dynamic>).cast<String>();
    decoded['expectedScreenshotNames'] = names.reversed.toList();
    response.writeAsStringSync(jsonEncode(decoded));
    final reordered = await _validateFixture(fixtureRoot, model: 'sheen_chair');
    expect(reordered.exitCode, isNot(0));
    expect('${reordered.stderr}', contains('ordered screenshot inventory'));
  });

  test('fixture correlates bounded READY markers to full response payloads',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_ready_transport_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(fixtureRoot, 'toycar');

    final markerLines = File('${fixtureRoot.path}/logs/toycar.log')
        .readAsLinesSync()
        .where((line) => line.contains('PLAN018_READY '))
        .toList(growable: false);
    expect(markerLines, hasLength(9));
    expect(
      markerLines.map((line) => utf8.encode(line).length),
      everyElement(lessThan(512)),
    );

    final valid = await _validateFixture(fixtureRoot, model: 'toycar');
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');

    final responseFile = File(
      '${fixtureRoot.path}/plan018_integration_response_toycar.json',
    );
    final baselineResponse = responseFile.readAsStringSync();
    Future<ProcessResult> validateResponseMutation(
      void Function(Map<String, dynamic>) mutate,
    ) async {
      final response = jsonDecode(baselineResponse) as Map<String, dynamic>;
      mutate(response);
      responseFile.writeAsStringSync(jsonEncode(response));
      final result = await _validateFixture(fixtureRoot, model: 'toycar');
      responseFile.writeAsStringSync(baselineResponse);
      return result;
    }

    final fieldDrift = await validateResponseMutation((response) {
      final payloads = response['readyPayloads'] as List<dynamic>;
      final firstPayload =
          jsonDecode(payloads.first as String) as Map<String, dynamic>;
      firstPayload['framesPerSecond'] = 59.0;
      payloads[0] = jsonEncode(firstPayload);
    });
    expect(fieldDrift.exitCode, isNot(0));
    expect('${fieldDrift.stderr}', contains('READY sha256'));

    final rawByteDrift = await validateResponseMutation((response) {
      final payloads = response['readyPayloads'] as List<dynamic>;
      payloads[0] = '${payloads.first} ';
    });
    expect(rawByteDrift.exitCode, isNot(0));
    expect('${rawByteDrift.stderr}', contains('READY sha256'));

    final reordered = await validateResponseMutation((response) {
      final payloads = response['readyPayloads'] as List<dynamic>;
      final first = payloads[0];
      payloads[0] = payloads[1];
      payloads[1] = first;
    });
    expect(reordered.exitCode, isNot(0));
    expect('${reordered.stderr}', contains('READY sha256'));

    final dropped = await validateResponseMutation((response) {
      (response['readyPayloads'] as List<dynamic>).removeLast();
    });
    expect(dropped.exitCode, isNot(0));
    expect('${dropped.stderr}', contains('READY payload inventory'));

    final nonString = await validateResponseMutation((response) {
      (response['readyPayloads'] as List<dynamic>)[0] = <String, Object?>{};
    });
    expect(nonString.exitCode, isNot(0));
    expect('${nonString.stderr}', contains('response payload is not a string'));

    final logFile = File('${fixtureRoot.path}/logs/toycar.log');
    final baselineLog = logFile.readAsStringSync();
    Future<ProcessResult> validateMarkerMutation(
      void Function(Map<String, dynamic>) mutate,
    ) async {
      const prefix = 'flutter: PLAN018_READY ';
      final lines = baselineLog.split('\n');
      final readyIndex = lines.indexWhere((line) => line.startsWith(prefix));
      final marker = jsonDecode(lines[readyIndex].substring(prefix.length))
          as Map<String, dynamic>;
      mutate(marker);
      lines[readyIndex] = '$prefix${jsonEncode(marker)}';
      logFile.writeAsStringSync(lines.join('\n'));
      final result = await _validateFixture(fixtureRoot, model: 'toycar');
      logFile.writeAsStringSync(baselineLog);
      return result;
    }

    final lengthDrift = await validateMarkerMutation((marker) {
      marker['byteLength'] = (marker['byteLength'] as int) + 1;
    });
    expect(lengthDrift.exitCode, isNot(0));
    expect('${lengthDrift.stderr}', contains('READY byteLength'));

    final schemaDrift = await validateMarkerMutation((marker) {
      marker['payload'] = 'not permitted';
    });
    expect(schemaDrift.exitCode, isNot(0));
    expect('${schemaDrift.stderr}', contains('marker schema'));
  });

  test('fixture rejects embedded READY marker occurrences', () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_ready_prefix_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(fixtureRoot, 'toycar');

    final logFile = File('${fixtureRoot.path}/logs/toycar.log');
    final lines = logFile.readAsLinesSync();
    final readyIndex = lines.indexWhere(
      (line) => line.startsWith('flutter: PLAN018_READY '),
    );
    expect(readyIndex, isNonNegative);
    lines[readyIndex] = lines[readyIndex].replaceFirst(
      'flutter: PLAN018_READY ',
      'diagnostic quoted PLAN018_READY ',
    );
    logFile.writeAsStringSync('${lines.join('\n')}\n');

    final spoofed = await _validateFixture(fixtureRoot, model: 'toycar');
    expect(spoofed.exitCode, isNot(0));
    expect('${spoofed.stderr}', contains('READY line prefix'));
  });

  test('fixture requires process-correlated Simulator Impeller proof',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_impeller_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(fixtureRoot, 'toycar');

    final valid = await _validateFixture(fixtureRoot, model: 'toycar');
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
    final validation =
        jsonDecode(valid.stdout as String) as Map<String, dynamic>;
    final backendEvidence =
        validation['backendEvidence'] as Map<String, dynamic>;
    expect(backendEvidence['source'], 'iOS Simulator unified log');
    expect(backendEvidence['processId'], 77419);
    expect(backendEvidence['backend'], 'Impeller Metal');

    final evidenceFile = File(
      '${fixtureRoot.path}/logs/toycar.impeller.json',
    );
    final originalEvidence = evidenceFile.readAsStringSync();
    final cases = <({
      String label,
      String expectedError,
      void Function(Map<String, dynamic>) mutate,
    })>[
      (
        label: 'process',
        expectedError: 'processId',
        mutate: (evidence) {
          final records = (evidence['records'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          records.last['processId'] = 77420;
        },
      ),
      (
        label: 'window',
        expectedError: 'outside captureWindow',
        mutate: (evidence) {
          final records = (evidence['records'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          records.first['timestamp'] = '2026-07-21 11:34:59.000000+0300';
        },
      ),
      (
        label: 'complete',
        expectedError: 'correlated to COMPLETE',
        mutate: (evidence) {
          final records = (evidence['records'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          records.last['eventMessage'] =
              '${records.last['eventMessage']}'.replaceFirst(
            '"modelId":"toycar"',
            '"modelId":"sheen_chair"',
          );
        },
      ),
      (
        label: 'uuid',
        expectedError: 'processImageUuid',
        mutate: (evidence) {
          final records = (evidence['records'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          records.last['processImageUuid'] =
              'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';
        },
      ),
      (
        label: 'query',
        expectedError: 'queryCommand',
        mutate: (evidence) {
          final query = (evidence['queryCommand'] as List<dynamic>);
          query[7] = '2026-07-21 08:34:00+0000';
        },
      ),
    ];
    for (final fixtureCase in cases) {
      final evidence = jsonDecode(originalEvidence) as Map<String, dynamic>;
      fixtureCase.mutate(evidence);
      evidenceFile.writeAsStringSync(jsonEncode(evidence));
      final mismatched = await _validateFixture(
        fixtureRoot,
        model: 'toycar',
      );
      expect(mismatched.exitCode, isNot(0), reason: fixtureCase.label);
      expect(
        '${mismatched.stderr}',
        contains(fixtureCase.expectedError),
        reason: fixtureCase.label,
      );
    }

    final driveLog = File('${fixtureRoot.path}/logs/toycar.log');
    driveLog.writeAsStringSync(
      'Using the Impeller rendering backend (Metal).\n'
      '${driveLog.readAsStringSync()}',
    );
    evidenceFile.deleteSync();
    final missing = await _validateFixture(fixtureRoot, model: 'toycar');
    expect(missing.exitCode, isNot(0));
    expect('${missing.stderr}', contains('proof is missing'));
  });

  test('fixture rejects inactive or non-rendering READY evidence', () async {
    final cases = <({
      double framesPerSecond,
      bool renderPolicyActive,
      bool renderPolicyAlways,
      String expectedError,
    })>[
      (
        framesPerSecond: 0.0,
        renderPolicyActive: true,
        renderPolicyAlways: true,
        expectedError: 'framesPerSecond',
      ),
      (
        framesPerSecond: 60.0,
        renderPolicyActive: false,
        renderPolicyAlways: true,
        expectedError: 'renderPolicyActive',
      ),
      (
        framesPerSecond: 60.0,
        renderPolicyActive: true,
        renderPolicyAlways: false,
        expectedError: 'renderPolicyAlways',
      ),
    ];
    for (final fixtureCase in cases) {
      final fixtureRoot = await Directory.systemTemp.createTemp(
        'plan018_ios_capture_readiness_fixture_',
      );
      addTearDown(() => fixtureRoot.delete(recursive: true));
      await _writeFixtureModel(
        fixtureRoot,
        'sheen_chair',
        framesPerSecond: fixtureCase.framesPerSecond,
        renderPolicyActive: fixtureCase.renderPolicyActive,
        renderPolicyAlways: fixtureCase.renderPolicyAlways,
      );

      final result = await _validateFixture(
        fixtureRoot,
        model: 'sheen_chair',
      );
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains(fixtureCase.expectedError));
    }
  });

  test('fixture rejects camera drift from the frozen state', () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_camera_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(
      fixtureRoot,
      'sheen_chair',
      readyMutation: (record) {
        record['cameraPosition'] = <double>[0.0, 0.0, 0.0];
      },
    );

    final result = await _validateFixture(
      fixtureRoot,
      model: 'sheen_chair',
    );
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('cameraPosition'));
  });

  test('fixture rejects an incomplete frozen lighting record', () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_lighting_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    await _writeFixtureModel(
      fixtureRoot,
      'sheen_chair',
      readyMutation: (record) {
        final lighting =
            record['appliedStageLighting']! as Map<String, Object?>;
        lighting.remove('exposure');
      },
    );

    final result = await _validateFixture(
      fixtureRoot,
      model: 'sheen_chair',
    );
    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('appliedStageLighting'));
  });

  test('fixture rejects GLB-derived authored or default inventory drift',
      () async {
    final cases = <({
      String label,
      String model,
      _ReadyMutation mutation,
      String expectedError,
    })>[
      (
        label: 'authored',
        model: 'sheen_chair',
        mutation: (record) {
          final inventory =
              record['authoredDependencyInventory']! as Map<String, Object?>;
          inventory['KHR_materials_sheen'] = <int>[0];
        },
        expectedError: 'authoredDependencyInventory',
      ),
      (
        label: 'default',
        model: 'glam_velvet_sofa',
        mutation: (record) {
          final inventory =
              record['defaultSceneInventory']! as Map<String, Object?>;
          inventory['KHR_materials_specular'] = <int>[];
        },
        expectedError: 'defaultSceneInventory',
      ),
    ];
    final results = <({
      String label,
      String expectedError,
      ProcessResult result,
    })>[];
    for (final fixtureCase in cases) {
      final fixtureRoot = await Directory.systemTemp.createTemp(
        'plan018_ios_capture_${fixtureCase.label}_inventory_fixture_',
      );
      addTearDown(() => fixtureRoot.delete(recursive: true));
      await _writeFixtureModel(
        fixtureRoot,
        fixtureCase.model,
        readyMutation: fixtureCase.mutation,
      );
      results.add((
        label: fixtureCase.label,
        expectedError: fixtureCase.expectedError,
        result: await _validateFixture(
          fixtureRoot,
          model: fixtureCase.model,
        ),
      ));
    }

    expect(
      <int>[for (final item in results) item.result.exitCode],
      everyElement(isNot(0)),
    );
    for (final item in results) {
      expect(
        '${item.result.stderr}',
        contains(item.expectedError),
        reason: item.label,
      );
    }
  });

  test('fixture rejects incomplete or malformed installed sheen proof',
      () async {
    final cases = <({
      String label,
      String model,
      _ReadyMutation mutation,
      String expectedError,
    })>[
      (
        label: 'count',
        model: 'sheen_chair',
        mutation: (record) {
          final probe =
              record['installedMaterialProbe']! as Map<String, Object?>;
          probe['installedDefaultSceneSheenCount'] = 0;
        },
        expectedError: 'installedMaterialProbe',
      ),
      (
        label: 'part_address',
        model: 'sheen_chair',
        mutation: (record) {
          final probe =
              record['installedMaterialProbe']! as Map<String, Object?>;
          final installed = probe['installedDefaultSceneSheen']! as List;
          final material = installed.single as Map<String, Object?>;
          final address = material['authoredAddress']! as Map<String, Object?>;
          address['debugPath'] = 'invented';
        },
        expectedError: 'PartAddress',
      ),
      (
        label: 'texture',
        model: 'sheen_cloth',
        mutation: (record) {
          final probe =
              record['installedMaterialProbe']! as Map<String, Object?>;
          final installed = probe['installedDefaultSceneSheen']! as List;
          final material = installed.single as Map<String, Object?>;
          material['sheenColorTextureGpuBacked'] = false;
        },
        expectedError: 'installedMaterialProbe',
      ),
    ];
    final results = <({
      String label,
      String expectedError,
      ProcessResult result,
    })>[];
    for (final fixtureCase in cases) {
      final fixtureRoot = await Directory.systemTemp.createTemp(
        'plan018_ios_capture_${fixtureCase.label}_probe_fixture_',
      );
      addTearDown(() => fixtureRoot.delete(recursive: true));
      await _writeFixtureModel(
        fixtureRoot,
        fixtureCase.model,
        readyMutation: fixtureCase.mutation,
      );
      results.add((
        label: fixtureCase.label,
        expectedError: fixtureCase.expectedError,
        result: await _validateFixture(
          fixtureRoot,
          model: fixtureCase.model,
        ),
      ));
    }

    expect(
      <int>[for (final item in results) item.result.exitCode],
      everyElement(isNot(0)),
    );
    for (final item in results) {
      expect(
        '${item.result.stderr}',
        contains(item.expectedError),
        reason: item.label,
      );
    }
  });

  test('fixture rejects source-invented generic role factors or addresses',
      () async {
    final cases = <({
      String label,
      _ReadyMutation mutation,
      String expectedError,
    })>[
      (
        label: 'factor',
        mutation: (record) {
          final probe =
              record['installedMaterialProbe']! as Map<String, Object?>;
          final roles =
              probe['genericSeparateExtensionRoles']! as Map<String, Object?>;
          final factors = roles['clearcoatFactors']! as List;
          final factor = factors.single as Map<String, Object?>;
          factor['expected'] = 0.4;
          factor['actual'] = 0.4;
        },
        expectedError: 'clearcoatFactors',
      ),
      (
        label: 'address',
        mutation: (record) {
          final probe =
              record['installedMaterialProbe']! as Map<String, Object?>;
          final roles =
              probe['genericSeparateExtensionRoles']! as Map<String, Object?>;
          roles['sheenAddresses'] = <Object?>[
            _address(<String>['root', 'Invented']),
          ];
        },
        expectedError: 'sheenAddresses',
      ),
    ];
    final results = <({
      String label,
      String expectedError,
      ProcessResult result,
    })>[];
    for (final fixtureCase in cases) {
      final fixtureRoot = await Directory.systemTemp.createTemp(
        'plan018_ios_capture_${fixtureCase.label}_roles_fixture_',
      );
      addTearDown(() => fixtureRoot.delete(recursive: true));
      await _writeFixtureModel(
        fixtureRoot,
        'toycar',
        readyMutation: fixtureCase.mutation,
      );
      results.add((
        label: fixtureCase.label,
        expectedError: fixtureCase.expectedError,
        result: await _validateFixture(fixtureRoot, model: 'toycar'),
      ));
    }

    expect(
      <int>[for (final item in results) item.result.exitCode],
      everyElement(isNot(0)),
    );
    for (final item in results) {
      expect(
        '${item.result.stderr}',
        contains(item.expectedError),
        reason: item.label,
      );
    }
  });

  test('fixture rejects reordered markers or output after terminal success',
      () async {
    final reorderedRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_marker_fixture_',
    );
    addTearDown(() => reorderedRoot.delete(recursive: true));
    await _writeFixtureModel(reorderedRoot, 'sheen_chair');
    final reorderedLog = File('${reorderedRoot.path}/logs/sheen_chair.log');
    final lines = reorderedLog.readAsLinesSync();
    final completeIndex = lines.indexWhere(
      (line) => line.contains('PLAN018_COMPLETE '),
    );
    final completeLine = lines.removeAt(completeIndex);
    lines.insert(1, completeLine);
    reorderedLog.writeAsStringSync('${lines.join('\n')}\n');

    final reordered = await _validateFixture(
      reorderedRoot,
      model: 'sheen_chair',
    );
    expect(reordered.exitCode, isNot(0));
    expect('${reordered.stderr}', contains('ordered READY/COMPLETE'));

    final trailingRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_terminal_fixture_',
    );
    addTearDown(() => trailingRoot.delete(recursive: true));
    await _writeFixtureModel(trailingRoot, 'sheen_chair');
    File('${trailingRoot.path}/logs/sheen_chair.log').writeAsStringSync(
      'late failure after test completion\n',
      mode: FileMode.append,
    );

    final trailing = await _validateFixture(
      trailingRoot,
      model: 'sheen_chair',
    );
    expect(trailing.exitCode, isNot(0));
    expect('${trailing.stderr}', contains('terminal success'));

    final malformedRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_json_fixture_',
    );
    addTearDown(() => malformedRoot.delete(recursive: true));
    await _writeFixtureModel(malformedRoot, 'sheen_chair');
    final malformedLog = File('${malformedRoot.path}/logs/sheen_chair.log');
    final malformedLines = malformedLog.readAsLinesSync();
    final readyIndex = malformedLines.indexWhere(
      (line) => line.contains('PLAN018_READY '),
    );
    malformedLines[readyIndex] = '${malformedLines[readyIndex]} trailing';
    malformedLog.writeAsStringSync('${malformedLines.join('\n')}\n');

    final malformed = await _validateFixture(
      malformedRoot,
      model: 'sheen_chair',
    );
    expect(malformed.exitCode, isNot(0));
    expect('${malformed.stderr}', contains('trailing JSON data'));
  });

  test('ToyCar fixture rejects mismatched authored extension factors',
      () async {
    final cases = <({
      double clearcoatActual,
      double transmissionActual,
      String expectedError,
    })>[
      (
        clearcoatActual: 0.25,
        transmissionActual: 1.0,
        expectedError: 'clearcoatFactors',
      ),
      (
        clearcoatActual: 1.0,
        transmissionActual: 0.25,
        expectedError: 'transmissionFactors',
      ),
    ];
    for (final fixtureCase in cases) {
      final fixtureRoot = await Directory.systemTemp.createTemp(
        'plan018_ios_capture_toycar_factor_fixture_',
      );
      addTearDown(() => fixtureRoot.delete(recursive: true));
      await _writeFixtureModel(
        fixtureRoot,
        'toycar',
        toyCarClearcoatActual: fixtureCase.clearcoatActual,
        toyCarTransmissionActual: fixtureCase.transmissionActual,
      );

      final result = await _validateFixture(fixtureRoot, model: 'toycar');
      expect(result.exitCode, isNot(0));
      expect('${result.stderr}', contains(fixtureCase.expectedError));
    }
  });

  test('fixture finalization requires exact PNG, log, backend, response set',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_full_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    for (final model in _views.keys) {
      await _writeFixtureModel(fixtureRoot, model);
    }

    final valid = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-fixture',
        '--finalize',
        '--run-root',
        fixtureRoot.path,
      ],
    );
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
    final evidence = jsonDecode(valid.stdout as String) as Map<String, dynamic>;
    expect(evidence['status'], 'candidate-only');
    expect(evidence['executionEvidence'], 'not run');
    expect(evidence['comparisonBoundary'], 'direction/conformance-only');
    expect(evidence['pngCount'], 27);
    expect(evidence['logCount'], 4);
    expect(evidence['backendEvidenceCount'], 4);
    expect(evidence['responseCount'], 4);
    expect(evidence['pixelHealthBoundary'], contains('separate'));
    expect(File('${fixtureRoot.path}/evidence.json').existsSync(), isFalse);

    _writePng(File('${fixtureRoot.path}/unexpected.png'));
    final extra = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-fixture',
        '--finalize',
        '--run-root',
        fixtureRoot.path,
      ],
    );
    expect(extra.exitCode, isNot(0));
    expect('${extra.stderr}', contains('exactly 27 PNG'));
  });

  test('partial summary records three accepted models without final evidence',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_ios_capture_partial_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));
    for (final model in <String>[
      'sheen_cloth',
      'glam_velvet_sofa',
      'toycar',
    ]) {
      await _writeFixtureModel(fixtureRoot, model);
    }

    final result = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-fixture',
        '--summarize-partial',
        '--run-root',
        fixtureRoot.path,
      ],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final evidence =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(evidence['status'], 'candidate-only');
    expect(evidence['executionEvidence'], 'not run');
    expect(evidence['evidenceCompleteness'], 'partial');
    expect(evidence['comparisonBoundary'], 'direction/conformance-only');
    expect(evidence['featureMaturity'], 'candidate-only');
    expect(evidence['finalEvidenceStatus'], 'absent');
    expect(evidence['finalEvidencePath'], 'evidence.json');
    expect(evidence['pngCount'], 21);
    expect(evidence['logCount'], 3);
    expect(evidence['backendEvidenceCount'], 3);
    expect(evidence['responseCount'], 3);
    expect(
      (evidence['completedModelIds'] as List<dynamic>).cast<String>(),
      <String>['sheen_cloth', 'glam_velvet_sofa', 'toycar'],
    );
    final missingModels =
        (evidence['missingModels'] as List<dynamic>).cast<Map>();
    expect(missingModels, hasLength(1));
    expect(missingModels.single['modelId'], 'sheen_chair');
    expect('${missingModels.single['reason']}', contains('TEXCOORD_1'));
    expect(
      '${missingModels.single['reason']}',
      contains('unsupportedMaterialFeature'),
    );
    expect(
      evidence['claimBoundary'],
      contains('not final four-model M3 evidence'),
    );
    expect(File('${fixtureRoot.path}/evidence.json').existsSync(), isFalse);
    expect(
      File('${fixtureRoot.path}/partial_evidence.json').existsSync(),
      isFalse,
    );
  });

  test('real partial summary separates captured and summary source hashes',
      () async {
    final fixture = await _deviceFixture();
    final runRoot = Directory(
      '${Directory.current.path}/tools/out/material_extension_acceptance/'
      'plan018_controlled_comparison/ios_simulator/'
      'candidate-run-partial-summary-test-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    final historyRunName = 'candidate-run-sheen-chair-history-test-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final historyRoot = Directory('${runRoot.parent.path}/$historyRunName');
    final malformedRunName = 'candidate-run-sheen-chair-malformed-test-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final malformedRoot = Directory('${runRoot.parent.path}/$malformedRunName');
    final symlinkRunName = 'candidate-run-sheen-chair-symlink-test-'
        '${DateTime.now().microsecondsSinceEpoch}';
    final symlinkRoot = Directory('${runRoot.parent.path}/$symlinkRunName');
    final symlinkTarget = Directory(
      '${Directory.systemTemp.path}/plan018-history-symlink-target-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (runRoot.existsSync()) {
        await runRoot.delete(recursive: true);
      }
      if (historyRoot.existsSync()) {
        await historyRoot.delete(recursive: true);
      }
      if (malformedRoot.existsSync()) {
        await malformedRoot.delete(recursive: true);
      }
      final manifestLink = Link('${symlinkRoot.path}/manifests');
      if (manifestLink.existsSync()) {
        manifestLink.deleteSync();
      }
      if (symlinkRoot.existsSync()) {
        await symlinkRoot.delete(recursive: true);
      }
      if (symlinkTarget.existsSync()) {
        await symlinkTarget.delete(recursive: true);
      }
      await fixture.parent.delete(recursive: true);
    });

    final plan = await _planForRealFixture(runRoot, fixture);
    runRoot.createSync(recursive: true);
    File('${runRoot.path}/device.json').writeAsStringSync(
      jsonEncode(plan['device']),
    );
    const partialModels = <String>[
      'sheen_cloth',
      'glam_velvet_sofa',
      'toycar',
    ];
    for (final model in partialModels) {
      await _writeFixtureModel(
        runRoot,
        model,
        fixtureValidation: false,
      );
      await _writeRealSuccessManifest(runRoot, model, plan);
    }
    final capturedGuard = _driftCapturedSourceHashes(runRoot, partialModels);

    final result = await Process.run(
      'python3',
      <String>[
        _runner,
        '--summarize-partial',
        '--run-root',
        runRoot.path,
      ],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final evidence =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(evidence['status'], 'candidate-only');
    expect(evidence['executionEvidence'], 'verified locally');
    expect(evidence['evidenceCompleteness'], 'partial');
    expect(evidence['finalEvidenceStatus'], 'absent');
    expect(evidence['sourceSha256'], capturedGuard['sourceSha256']);
    expect(
      evidence['summarySourceSha256'],
      isNot(equals(capturedGuard['sourceSha256'])),
    );
    expect(
      evidence['sourceHashBoundary'],
      contains('captured model manifests'),
    );
    expect(evidence['capturePreflight'], capturedGuard);
    expect(evidence['capturePostflight'], capturedGuard);
    final partialEvidenceFile = File('${runRoot.path}/partial_evidence.json');
    expect(partialEvidenceFile.existsSync(), isTrue);
    expect(File('${runRoot.path}/evidence.json').existsSync(), isFalse);

    final validation = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-partial-summary',
        '--run-root',
        runRoot.path,
      ],
    );
    expect(validation.exitCode, 0,
        reason: '${validation.stdout}\n${validation.stderr}');
    final validationRecord =
        jsonDecode(validation.stdout as String) as Map<String, dynamic>;
    expect(validationRecord['mode'], 'validate-partial-summary');
    expect(validationRecord['status'], 'verified locally');
    expect(validationRecord['evidenceStatus'], 'candidate-only');
    expect(validationRecord['evidenceCompleteness'], 'partial');
    expect(validationRecord['evidenceSha256'], hasLength(64));
    expect(validationRecord['pngCount'], 21);
    expect(
      (validationRecord['completedModelIds'] as List<dynamic>).cast<String>(),
      partialModels,
    );
    expect(partialEvidenceFile.existsSync(), isTrue);
    expect(File('${runRoot.path}/evidence.json').existsSync(), isFalse);

    final historyManifest =
        File('${historyRoot.path}/manifests/sheen_chair.failed.json');
    final historyLog = File('${historyRoot.path}/logs/sheen_chair.log');
    historyManifest.parent.createSync(recursive: true);
    historyLog.parent.createSync(recursive: true);
    historyLog.writeAsStringSync(
      'unsupportedMaterialFeature: authored TEXCOORD_1 ambient occlusion '
      'is outside the current SheenChair iOS capture boundary.',
    );
    historyManifest.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'modelId': 'sheen_chair',
        'status': 'failed',
        'executionEvidence': 'not verified',
        'failureType': 'CaptureError',
        'failure': 'unsupportedMaterialFeature: KHR_materials_occlusionTexture '
            'uses authored TEXCOORD_1; no UVs were invented.',
        'captureExitCode': 1,
        'retentionBoundary':
            'historical failed attempt only; not accepted M3 evidence',
      }),
    );
    final malformedManifest =
        File('${malformedRoot.path}/manifests/sheen_chair.failed.json');
    malformedManifest.parent.createSync(recursive: true);
    malformedManifest.writeAsStringSync('{not-json');
    symlinkRoot.createSync(recursive: true);
    symlinkTarget.createSync(recursive: true);
    File('${symlinkTarget.path}/sheen_chair.failed.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'modelId': 'sheen_chair',
        'status': 'failed',
        'executionEvidence': 'not verified',
        'failureType': 'CaptureError',
        'failure': 'unsupportedMaterialFeature outside the candidate root',
        'captureExitCode': 1,
      }),
    );
    Link('${symlinkRoot.path}/manifests').createSync(symlinkTarget.path);

    final audit = await Process.run(
      'python3',
      <String>[
        _runner,
        '--audit-m3-status',
        '--run-root',
        runRoot.path,
      ],
    );
    expect(audit.exitCode, 0, reason: '${audit.stdout}\n${audit.stderr}');
    final auditRecord =
        jsonDecode(audit.stdout as String) as Map<String, dynamic>;
    expect(auditRecord['mode'], 'audit-m3-status');
    expect(auditRecord['status'], 'candidate-only');
    expect(auditRecord['m3Status'], 'blocked');
    expect(auditRecord['m4Status'], 'not started');
    expect(auditRecord['finalEvidenceStatus'], 'absent');
    expect(auditRecord['canStartM4'], isFalse);
    final closureDisposition =
        auditRecord['m3ClosureDisposition'] as Map<String, dynamic>;
    expect(closureDisposition['status'], 'blocked');
    expect(closureDisposition['milestone'], 'M3');
    expect(closureDisposition['task'], 5);
    expect(closureDisposition['blockingGate'], 'sheenChairIOSCapture');
    expect(closureDisposition['requiredModelId'], 'sheen_chair');
    expect(closureDisposition['blockerEvidence'], 'verified locally');
    expect(closureDisposition['executionEvidence'], 'not run');
    expect(closureDisposition['finalEvidenceStatus'], 'absent');
    expect(closureDisposition['task5OverallCompletion'], 'partial');
    expect(closureDisposition['canCloseM3'], isFalse);
    expect(closureDisposition['canStartM4'], isFalse);
    expect(closureDisposition['m4Status'], 'not started');
    expect(
      closureDisposition['resolutionBoundary'],
      'Capture the frozen SheenChair without inventing UVs or reinterpreting '
      'channels, or explicitly amend Task 5 acceptance; this audit does '
      'neither.',
    );
    expect(
      closureDisposition['claimBoundary'],
      'Blocked closure disposition only; this does not close M3, satisfy '
      'final four-model evidence, or permit M4.',
    );
    expect(
      (auditRecord['completedModelIds'] as List<dynamic>).cast<String>(),
      partialModels,
    );
    final partialValidation =
        auditRecord['partialEvidenceValidation'] as Map<String, dynamic>;
    expect(partialValidation['evidenceStatus'], 'candidate-only');
    expect(partialValidation['executionEvidence'], 'verified locally');
    expect(
        partialValidation['comparisonBoundary'], 'direction/conformance-only');
    expect(partialValidation['evidenceCompleteness'], 'partial');
    final gates = (auditRecord['openGates'] as List<dynamic>).cast<Map>();
    expect(
      gates.map((gate) => gate['gate']),
      <String>[
        'finalFourModelM3Evidence',
        'sheenChairIOSCapture',
        'physicalTargets',
        'android',
        'web',
        'productionReadiness',
      ],
    );
    expect(
      gates.map((gate) => gate['status']),
      <String>[
        'absent',
        'not run',
        'not run',
        'not run',
        'not run',
        'not run',
      ],
    );
    final task5Checklist =
        (auditRecord['task5Checklist'] as List<dynamic>).cast<Map>();
    expect(
      task5Checklist.map((item) => item['item']),
      <String>[
        'fixtureProvenance',
        'comparisonState',
        'threeAndKhronosReferences',
        'threeLoaderContract',
        'closeGrazingViews',
        'captureHashesDiagnostics',
      ],
    );
    expect(
      task5Checklist.map((item) => item['status']),
      <String>[
        'verified locally',
        'verified locally',
        'verified locally',
        'verified locally',
        'candidate-only',
        'candidate-only',
      ],
    );
    expect(
      task5Checklist.map((item) => item['completion']),
      <String>[
        'complete',
        'complete',
        'complete',
        'complete',
        'partial',
        'partial',
      ],
    );
    expect(
      task5Checklist.every((item) => item['m4Boundary'] == 'not started'),
      isTrue,
    );
    final fixtureProvenance = task5Checklist.singleWhere(
      (item) => item['item'] == 'fixtureProvenance',
    );
    expect(
      (fixtureProvenance['artifacts'] as List<dynamic>).map(
        (artifact) => (artifact as Map)['path'],
      ),
      <String>[
        'tools/material_extension_acceptance/manifest.json',
        'tools/material_extension_acceptance/fixtures/'
            'plan018_controlled_comparison_state.json',
      ],
    );
    expect(
      (fixtureProvenance['artifacts'] as List<dynamic>).every(
          (artifact) => (artifact as Map)['status'] == 'verified locally'),
      isTrue,
    );
    expect(
      (fixtureProvenance['artifacts'] as List<dynamic>)
          .every((artifact) => '${(artifact as Map)['sha256']}'.length == 64),
      isTrue,
    );
    final comparisonState = task5Checklist.singleWhere(
      (item) => item['item'] == 'comparisonState',
    );
    expect(comparisonState['stateSha256'], _stateSha);
    expect(
      ((comparisonState['artifacts'] as List<dynamic>).single as Map)['path'],
      'tools/material_extension_acceptance/fixtures/'
      'plan018_controlled_comparison_state.json',
    );
    expect(
      ((comparisonState['artifacts'] as List<dynamic>).single as Map)['status'],
      'verified locally',
    );
    expect(
      '${((comparisonState['artifacts'] as List<dynamic>).single as Map)['sha256']}',
      _stateSha,
    );
    final references = task5Checklist.singleWhere(
      (item) => item['item'] == 'threeAndKhronosReferences',
    );
    expect(references['status'], 'verified locally');
    expect(references['completion'], 'complete');
    expect(references['maturity'], 'candidate-only');
    final referenceCoverage =
        references['referenceCoverage'] as Map<String, dynamic>;
    final threeCoverage = referenceCoverage['threejs'] as Map<String, dynamic>;
    expect(
      (threeCoverage['modelIds'] as List<dynamic>).cast<String>(),
      <String>[
        'sheen_chair',
        'sheen_cloth',
        'glam_velvet_sofa',
        'toycar',
      ],
    );
    expect(threeCoverage['captureCount'], 27);
    expect(threeCoverage['status'], 'verified locally');
    final khronosCoverage =
        referenceCoverage['khronosSampleRenderer'] as Map<String, dynamic>;
    expect(
      (khronosCoverage['modelIds'] as List<dynamic>).cast<String>(),
      <String>['toycar', 'glam_velvet_sofa'],
    );
    expect(khronosCoverage['captureCount'], 15);
    expect(khronosCoverage['status'], 'verified locally');
    expect(
      (references['artifacts'] as List<dynamic>).every(
        (artifact) => (artifact as Map)['status'] == 'verified locally',
      ),
      isTrue,
    );
    expect(
      '${references['practicalBoundary']}',
      contains('ToyCar and GlamVelvetSofa'),
    );
    expect(
      '${references['claimBoundary']}',
      contains('direction/conformance'),
    );
    final threeLoader = task5Checklist.singleWhere(
      (item) => item['item'] == 'threeLoaderContract',
    );
    expect(
      ((threeLoader['artifacts'] as List<dynamic>).single as Map)['path'],
      'tools/out/material_extension_acceptance/'
      'plan018_controlled_comparison/threejs/evidence.json',
    );
    expect(
      ((threeLoader['artifacts'] as List<dynamic>).single as Map)['status'],
      'verified locally',
    );
    expect(
      '${((threeLoader['artifacts'] as List<dynamic>).single as Map)['sha256']}',
      hasLength(64),
    );
    final closeGrazing = task5Checklist.singleWhere(
      (item) => item['item'] == 'closeGrazingViews',
    );
    expect(
      (closeGrazing['completedModelIds'] as List<dynamic>).cast<String>(),
      partialModels,
    );
    expect(
      (closeGrazing['missingModelIds'] as List<dynamic>).cast<String>(),
      <String>['sheen_chair'],
    );
    expect('${closeGrazing['claimBoundary']}', contains('not final'));
    expect(auditRecord['task5OverallCompletion'], 'partial');
    final sheenChairGate =
        gates.singleWhere((gate) => gate['gate'] == 'sheenChairIOSCapture');
    final staticBlocker =
        auditRecord['sheenChairStaticBlocker'] as Map<String, dynamic>;
    expect(staticBlocker['modelId'], 'sheen_chair');
    expect(staticBlocker['status'], 'not run');
    expect(staticBlocker['executionEvidence'], 'not run');
    expect(staticBlocker['blockerEvidence'], 'verified locally');
    expect(staticBlocker['blockerType'], 'unsupportedMaterialFeature');
    expect(staticBlocker['unsupportedFeature'], 'occlusionTexture.texCoord_1');
    expect(staticBlocker['stateSha256'], _stateSha);
    expect(staticBlocker['modelSha256'],
        'f0af2a2b102d28d540236306ae19f8fb36842df76bd38cf76f063f9bd2853399');
    expect(
      (staticBlocker['authoredSheenMaterialIndices'] as List<dynamic>)
          .cast<int>(),
      <int>[0, 4],
    );
    expect(
      (staticBlocker['defaultSceneSheenMaterialIndices'] as List<dynamic>)
          .cast<int>(),
      <int>[0],
    );
    final blockedPrimitives =
        (staticBlocker['blockedPrimitives'] as List<dynamic>).cast<Map>();
    expect(blockedPrimitives, hasLength(1));
    final blockedPrimitive = blockedPrimitives.single;
    expect(blockedPrimitive['materialIndex'], 0);
    expect(blockedPrimitive['materialName'], 'fabric Mystere Mango Velvet');
    expect(
      (blockedPrimitive['primitiveAttributes'] as List<dynamic>).cast<String>(),
      <String>['NORMAL', 'POSITION', 'TEXCOORD_0', 'TEXCOORD_1'],
    );
    final occlusion = blockedPrimitive['occlusionTexture'] as Map;
    expect(occlusion['index'], 1);
    expect(occlusion['texCoord'], 1);
    expect(occlusion['textureTransformTexCoord'], 1);
    expect(staticBlocker['noUvInvented'], isTrue);
    expect(staticBlocker['noChannelReinterpretation'], isTrue);
    expect(staticBlocker['acceptedEvidence'], isFalse);
    expect(staticBlocker['finalEvidence'], isFalse);
    expect('${staticBlocker['claimBoundary']}',
        contains('does not satisfy SheenChair iOS capture'));
    expect(staticBlocker['m4Boundary'], 'not started');
    final historicalAttempts =
        (auditRecord['historicalSheenChairAttempts'] as List<dynamic>)
            .cast<Map>();
    expect(sheenChairGate['historicalAttemptCount'], historicalAttempts.length);
    expect(
      sheenChairGate['historicalUnsupportedMaterialFeatureAttempts'],
      historicalAttempts
          .where(
            (attempt) => attempt['unsupportedMaterialFeatureDetected'] == true,
          )
          .length,
    );
    final historyAttempt = historicalAttempts.singleWhere(
      (attempt) => attempt['attemptRoot'] == historyRunName,
    );
    expect(historyAttempt['modelId'], 'sheen_chair');
    expect(historyAttempt['status'], 'failed');
    expect(historyAttempt['executionEvidence'], 'not verified');
    expect(historyAttempt['acceptedEvidence'], isFalse);
    expect(historyAttempt['finalEvidence'], isFalse);
    expect(historyAttempt['unsupportedMaterialFeatureDetected'], isTrue);
    expect(historyAttempt['manifestSha256'], hasLength(64));
    expect(historyAttempt['logSha256'], hasLength(64));
    expect(
      '${historyAttempt['evidenceBoundary']}',
      contains('not accepted M3 evidence'),
    );
    final malformedAttempt = historicalAttempts.singleWhere(
      (attempt) => attempt['attemptRoot'] == malformedRunName,
    );
    expect(malformedAttempt['modelId'], 'sheen_chair');
    expect(malformedAttempt['status'], 'invalid');
    expect(malformedAttempt['executionEvidence'], 'not verified');
    expect(malformedAttempt['acceptedEvidence'], isFalse);
    expect(malformedAttempt['finalEvidence'], isFalse);
    expect(malformedAttempt['unsupportedMaterialFeatureDetected'], isFalse);
    expect('${malformedAttempt['invalidReason']}', contains('malformed'));
    final symlinkAttempt = historicalAttempts.singleWhere(
      (attempt) => attempt['attemptRoot'] == symlinkRunName,
    );
    expect(symlinkAttempt['modelId'], 'sheen_chair');
    expect(symlinkAttempt['status'], 'invalid');
    expect(symlinkAttempt['executionEvidence'], 'not verified');
    expect(symlinkAttempt['acceptedEvidence'], isFalse);
    expect(symlinkAttempt['finalEvidence'], isFalse);
    expect(symlinkAttempt['unsupportedMaterialFeatureDetected'], isFalse);
    expect('${symlinkAttempt['invalidReason']}', contains('outside'));
    expect(symlinkAttempt['manifestSha256'], isNull);
    expect('${auditRecord['claimBoundary']}', contains('does not establish'));
    expect(partialEvidenceFile.existsSync(), isTrue);
    expect(File('${runRoot.path}/evidence.json').existsSync(), isFalse);
  });

  test('real final M3 audit closes Task 5 without widening evidence claims',
      () async {
    final runRoot = Directory(
      '${Directory.current.path}/tools/out/material_extension_acceptance/'
      'plan018_controlled_comparison/ios_simulator/candidate-run-14',
    );
    if (!File('${runRoot.path}/evidence.json').existsSync()) {
      markTestSkipped(
        'not run: requires retained candidate-run-14 final evidence',
      );
      return;
    }

    final audit = await Process.run(
      'python3',
      <String>[
        _runner,
        '--audit-m3-status',
        '--run-root',
        runRoot.path,
      ],
    );

    expect(audit.exitCode, 0, reason: '${audit.stdout}\n${audit.stderr}');
    final record = jsonDecode(audit.stdout as String) as Map<String, dynamic>;
    expect(record['mode'], 'audit-m3-status');
    expect(record['status'], 'candidate-only');
    expect(record['dependencyEvidenceStatus'], 'candidate-only');
    expect(
      record['capturedRendererRevision'],
      '8e2e2221405b04c517189428d0faf8474cf7f708',
    );
    expect(record['currentRendererRevision'], _pin);
    expect(record['m3Status'], 'complete');
    expect(record['m4Status'], 'not started');
    expect(record['finalEvidenceStatus'], 'verified locally');
    expect(record['pixelHealthStatus'], 'verified locally');
    final healthEvidence =
        record['iosRendererLocalHealth'] as Map<String, dynamic>;
    expect(healthEvidence['status'], 'verified locally');
    expect(healthEvidence['frameCount'], 27);
    expect(healthEvidence['passTripletCount'], 9);
    expect(record['canStartM4'], isTrue);
    expect(record['task5OverallCompletion'], 'complete');
    expect(
      (record['completedModelIds'] as List<dynamic>).cast<String>(),
      _views.keys,
    );
    expect(record['missingModels'], isEmpty);
    final closure = record['m3ClosureDisposition'] as Map<String, dynamic>;
    expect(closure['status'], 'verified locally');
    expect(closure['canCloseM3'], isTrue);
    expect(closure['canStartM4'], isTrue);
    expect(
      '${record['claimBoundary']}',
      contains('does not establish renderer-native sheen'),
    );
  });

  test('post-capture guard comparison permits only runner and test drift',
      () async {
    const script = '''
import importlib.util
from pathlib import Path

module_path = Path("tools/run_plan018_ios_capture.py").resolve()
spec = importlib.util.spec_from_file_location("plan018_runner", module_path)
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)

base = {
    "branch": "main",
    "sourceSha256": {
        "lib/src/internal/flutter_scene_adapter.dart": "a" * 64,
        "tools/run_plan018_ios_capture.py": "b" * 64,
        "test/plan018_ios_capture_runner_test.dart": "c" * 64,
    },
}
runner_test_drift = {
    **base,
    "sourceSha256": {
        **base["sourceSha256"],
        "tools/run_plan018_ios_capture.py": "d" * 64,
        "test/plan018_ios_capture_runner_test.dart": "e" * 64,
    },
}
production_drift = {
    **runner_test_drift,
    "sourceSha256": {
        **runner_test_drift["sourceSha256"],
        "lib/src/internal/flutter_scene_adapter.dart": "f" * 64,
    },
}
runner_key_missing = {
    **base,
    "sourceSha256": {
        key: value
        for key, value in base["sourceSha256"].items()
        if key != "tools/run_plan018_ios_capture.py"
    },
}
assert runner.guard_without_source_hashes(
    base,
    label="base",
) == runner.guard_without_source_hashes(
    runner_test_drift,
    label="runner/test drift",
)
assert runner.guard_without_source_hashes(
    base,
    label="base",
) != runner.guard_without_source_hashes(
    production_drift,
    label="production drift",
)
assert runner.guard_without_source_hashes(
    base,
    label="base",
) != runner.guard_without_source_hashes(
    runner_key_missing,
    label="runner key missing",
)
''';
    final result = await Process.run(
      'python3',
      <String>['-c', script],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('artifact audit refuses symlinked ancestor paths', () async {
    final root = Directory(
      '${Directory.current.path}/tools/out/material_extension_acceptance/'
      'plan018_controlled_comparison/artifact-audit-symlink-test-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    final allowed = Directory('${root.path}/allowed');
    final outside = Directory('${root.path}/outside');
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    allowed.createSync(recursive: true);
    outside.createSync(recursive: true);
    File('${outside.path}/artifact.json').writeAsStringSync('{"ok":true}');
    Link('${allowed.path}/link').createSync(outside.path);

    final result = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
import json
import pathlib
import sys

spec = importlib.util.spec_from_file_location(
    "plan018_capture", "tools/run_plan018_ios_capture.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
record = module.audit_artifact_record(
    pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[1])
)
print(json.dumps(record, sort_keys=True))
''',
        allowed.path,
        '${allowed.path}/link/artifact.json',
      ],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final record = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(record['status'], 'not run');
    expect('${record['reason']}', contains('outside'));
    expect(record.containsKey('sha256'), isFalse);
  });

  test('Three fixture seam requires the exact ordered capture inventory',
      () async {
    final fixtureRoot = await _writeThreeFixture();
    addTearDown(() => fixtureRoot.delete(recursive: true));

    final valid = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-three-fixture',
        '--run-root',
        fixtureRoot.path,
      ],
    );
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
    final record = jsonDecode(valid.stdout as String) as Map<String, dynamic>;
    expect(record['executionEvidence'], 'not run');
    expect(record['fixtureValidation'], isTrue);
    expect(record['pngCount'], 27);

    File('${fixtureRoot.path}/threejs/toycar_context_combined.png')
        .writeAsBytesSync(<int>[0], mode: FileMode.append);
    final drifted = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-three-fixture',
        '--run-root',
        fixtureRoot.path,
      ],
    );
    expect(drifted.exitCode, isNot(0));
    expect('${drifted.stderr}', contains('sha256'));
  });

  test('timeout fixture retains streamed bytes and typed kill evidence',
      () async {
    final fixtureRoot = await Directory.systemTemp.createTemp(
      'plan018_capture_timeout_fixture_',
    );
    addTearDown(() => fixtureRoot.delete(recursive: true));

    final result = await Process.run(
      'python3',
      <String>[
        _runner,
        '--exercise-timeout-fixture',
        '--run-root',
        fixtureRoot.path,
      ],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final record = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(record['executionEvidence'], 'not run');
    expect(record['fixtureValidation'], isTrue);
    expect(record['commandTimeoutType'], 'CaptureTimeoutError');
    expect(record['streamTimeoutType'], 'CaptureTimeoutError');
    final commandTermination =
        record['commandTermination'] as Map<String, dynamic>;
    expect(commandTermination['processGroupExitConfirmed'], isTrue);
    expect(commandTermination['parentReaped'], isTrue);
    final termination = record['streamTermination'] as Map<String, dynamic>;
    expect(termination['terminateAttempted'], isTrue);
    expect(termination['killRequired'], isTrue);
    expect(termination['timedOut'], isTrue);
    expect(termination['processGroupExitConfirmed'], isTrue);
    expect(termination['parentReaped'], isTrue);
    expect(termination['streamEof'], isTrue);
    expect(termination['partialLog'], logPathFor(fixtureRoot));

    final log = File('${fixtureRoot.path}/logs/timeout_fixture.log');
    expect(log.readAsStringSync(), contains('partial timeout fixture'));
    final manifest = jsonDecode(
      File('${fixtureRoot.path}/manifests/timeout_fixture.failed.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['status'], 'failed');
    expect(manifest['failureType'], 'CaptureTimeoutError');
    expect(manifest['timeout'], termination);
    expect(manifest['retentionBoundary'], contains('retained'));
  });

  test('runner source has no shell or Simulator lifecycle operations', () {
    final source = File(_runner).readAsStringSync();
    expect(source, isNot(contains('shell=True')));
    expect(source, isNot(contains('shutil.rmtree')));
    expect(source, isNot(contains("'boot'")));
    expect(source, isNot(contains("'shutdown'")));
    expect(source, isNot(contains("'erase'")));
    expect(source, isNot(contains("'uninstall'")));
  });
}

String logPathFor(Directory root) =>
    File('${root.path}/logs/timeout_fixture.log').resolveSymbolicLinksSync();

Future<File> _deviceFixture({bool duplicate = false}) async {
  final root = await Directory.systemTemp.createTemp(
    'plan018_ios_device_fixture_',
  );
  final devices = <Map<String, Object?>>[
    <String, Object?>{
      'name': 'iPhone 17',
      'udid': _udid,
      'state': 'Booted',
      'isAvailable': true,
    },
    if (duplicate)
      <String, Object?>{
        'name': 'iPhone 17',
        'udid': 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE',
        'state': 'Booted',
        'isAvailable': true,
      },
  ];
  final file = File('${root.path}/devices.json');
  file.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'simctl': <String, Object?>{
        'devices': <String, Object?>{
          'com.apple.CoreSimulator.SimRuntime.iOS-26-5': devices,
        },
      },
      'flutterDevices': <Map<String, Object?>>[
        <String, Object?>{
          'id': _udid,
          'name': 'iPhone 17',
          'targetPlatform': 'ios',
          'emulator': true,
          'isSupported': true,
        },
      ],
    }),
  );
  return file;
}

Future<ProcessResult> _validateFixture(
  Directory root, {
  required String model,
}) =>
    Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-fixture',
        '--model',
        model,
        '--run-root',
        root.path,
      ],
    );

Future<Map<String, dynamic>> _planForRealFixture(
  Directory runRoot,
  File fixture,
) async {
  final result = await Process.run(
    'python3',
    <String>[
      _runner,
      '--plan',
      '--model',
      'sheen_cloth',
      '--udid',
      _udid,
      '--run-root',
      runRoot.path,
      '--device-fixture',
      fixture.path,
    ],
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<void> _writeRealSuccessManifest(
  Directory root,
  String model,
  Map<String, dynamic> plan,
) async {
  const startedAt = '2026-07-21T08:35:00.000000+00:00';
  const captureFinishedAt = '2026-07-21T08:35:30.000000+00:00';
  final manifests = Directory('${root.path}/manifests')
    ..createSync(recursive: true);
  final manifestFile = File('${manifests.path}/$model.json');
  manifestFile.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'device': plan['device'],
      'startedAt': startedAt,
      'captureFinishedAt': captureFinishedAt,
    }),
  );
  final validation = await _validateRealModel(root, model);
  manifestFile.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'status': 'candidate-only',
      'executionEvidence': 'verified locally',
      'modelId': model,
      'captureExitCode': 0,
      'startedAt': startedAt,
      'captureFinishedAt': captureFinishedAt,
      'finishedAt': '2026-07-21T08:35:31.000000+00:00',
      'workingDirectory': _harness,
      'command': _captureCommand(model),
      'environment': <String, Object?>{
        'PLAN018_SCREENSHOT_OUTPUT': root.path,
      },
      'shell': false,
      'captureTimeoutSeconds': 1800.0,
      'terminationGraceSeconds': 10.0,
      'timeoutContract': _timeoutContract(),
      'device': plan['device'],
      'preflight': plan['preflight'],
      'postflight': plan['preflight'],
      'artifactRecordSha256': validation['artifactRecordSha256'],
      'result': validation['validation'],
      'featureMaturity': 'candidate-only',
      'physicalTargets': 'not run',
      'comparisonBoundary': 'direction/conformance-only',
    }),
  );
}

Future<Map<String, dynamic>> _validateRealModel(
  Directory root,
  String model,
) async {
  const script = '''
import hashlib
import importlib.util
import sys
from pathlib import Path

module_path = Path("tools/run_plan018_ios_capture.py").resolve()
spec = importlib.util.spec_from_file_location("plan018_runner", module_path)
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)
validation = runner.validate_model_artifacts(Path(sys.argv[1]), sys.argv[2])
print(runner.json_text({
    "artifactRecordSha256": hashlib.sha256(
        runner.json_text(validation).encode()
    ).hexdigest(),
    "validation": validation,
}))
''';
  final result = await Process.run(
    'python3',
    <String>['-c', script, root.path, model],
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Map<String, dynamic> _driftCapturedSourceHashes(
  Directory root,
  Iterable<String> models,
) {
  const capturedRunnerSha =
      '0000000000000000000000000000000000000000000000000000000000000000';
  Map<String, dynamic>? capturedGuard;
  for (final model in models) {
    final manifestFile = File('${root.path}/manifests/$model.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    for (final key in <String>['preflight', 'postflight']) {
      final guard = (manifest[key] as Map).cast<String, dynamic>();
      final source = (guard['sourceSha256'] as Map).cast<String, dynamic>();
      source['tools/run_plan018_ios_capture.py'] = capturedRunnerSha;
      guard['sourceSha256'] = source;
      manifest[key] = guard;
    }
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    capturedGuard ??= (manifest['preflight'] as Map).cast<String, dynamic>();
    expect(manifest['postflight'], capturedGuard);
  }
  return capturedGuard!;
}

List<String> _captureCommand(String model) => <String>[
      _flutter,
      'drive',
      '--no-pub',
      '--debug',
      '--enable-impeller',
      '-d',
      _udid,
      '--driver=test_driver/integration_test.dart',
      '--target=integration_test/plan018_capture_test.dart',
      '--dart-define=PLAN018_MODEL_ID=$model',
    ];

Map<String, Object?> _timeoutContract() => <String, Object?>{
      'deviceDiscoveryTimeoutSeconds': 60.0,
      'harnessValidationTimeoutSeconds': 60.0,
      'captureTimeoutSeconds': 1800.0,
      'terminationGraceSeconds': 10.0,
      'killWaitSeconds': 5.0,
      'streamDrainTimeoutSeconds': 1.0,
    };

typedef _ReadyMutation = void Function(Map<String, Object?> record);

Map<String, Object?> _inventory({
  List<int> sheen = const <int>[],
  List<int> clearcoat = const <int>[],
  List<int> transmission = const <int>[],
  List<int> volume = const <int>[],
  List<int> ior = const <int>[],
  List<int> specular = const <int>[],
}) =>
    <String, Object?>{
      'KHR_materials_sheen': List<int>.of(sheen),
      'KHR_materials_clearcoat': List<int>.of(clearcoat),
      'KHR_materials_transmission': List<int>.of(transmission),
      'KHR_materials_volume': List<int>.of(volume),
      'KHR_materials_ior': List<int>.of(ior),
      'KHR_materials_specular': List<int>.of(specular),
    };

Map<String, Object?> _authoredInventory(String model) => switch (model) {
      'sheen_chair' => _inventory(sheen: <int>[0, 4]),
      'sheen_cloth' => _inventory(sheen: <int>[0]),
      'glam_velvet_sofa' => _inventory(
          sheen: <int>[2, 3, 4, 5, 6],
          specular: <int>[2, 3, 4, 5, 6],
        ),
      'toycar' => _inventory(
          sheen: <int>[1],
          clearcoat: <int>[0],
          transmission: <int>[2],
        ),
      _ => throw ArgumentError.value(model, 'model'),
    };

Map<String, Object?> _defaultInventory(String model) => switch (model) {
      'sheen_chair' || 'sheen_cloth' => _inventory(sheen: <int>[0]),
      'glam_velvet_sofa' => _inventory(
          sheen: <int>[3],
          specular: <int>[3],
        ),
      'toycar' => _inventory(
          sheen: <int>[1],
          clearcoat: <int>[0],
          transmission: <int>[2],
        ),
      _ => throw ArgumentError.value(model, 'model'),
    };

Map<String, Object?> _address(List<String> nodePath) => <String, Object?>{
      'nodePath': List<String>.of(nodePath),
      'primitiveIndex': 0,
    };

Map<String, Object?> _installedMaterialProbe(
  String model, {
  required double toyCarClearcoatActual,
  required double toyCarTransmissionActual,
}) {
  final evidence = switch (model) {
    'sheen_chair' => (
        nodeName: 'SheenChair_fabric',
        color: <double>[1.0, 0.329, 0.1],
        roughness: 0.8,
        colorTexture: false,
        roughnessTexture: false,
      ),
    'sheen_cloth' => (
        nodeName: 'SheenCloth_mesh',
        color: <double>[1.0, 1.0, 1.0],
        roughness: 1.0,
        colorTexture: true,
        roughnessTexture: true,
      ),
    'glam_velvet_sofa' => (
        nodeName: 'GlamVelvetSofa_fabric',
        color: <double>[0.05, 0.17, 0.5],
        roughness: 0.6,
        colorTexture: false,
        roughnessTexture: false,
      ),
    'toycar' => (
        nodeName: 'Fabric',
        color: <double>[1.0, 0.0, 0.0],
        roughness: 0.5,
        colorTexture: false,
        roughnessTexture: false,
      ),
    _ => throw ArgumentError.value(model, 'model'),
  };
  final authoredAddress = _address(<String>[evidence.nodeName]);
  final concreteAddress = _address(<String>['root', evidence.nodeName]);
  final genericRoles = model == 'toycar'
      ? <String, Object?>{
          'selection': 'authored extension-group identity only',
          'sheenAddresses': <Object?>[concreteAddress],
          'clearcoatAddresses': <Object?>[
            _address(<String>['root', 'ToyCar']),
          ],
          'transmissionVolumeAddresses': <Object?>[
            _address(<String>['root', 'Glass']),
          ],
          'distinctPrimitiveAddresses': true,
          'distinctMaterialIdentity': true,
          'clearcoatFactors': <Object?>[
            <String, Object?>{
              'address': _address(<String>['root', 'ToyCar']),
              'expected': 1.0,
              'actual': toyCarClearcoatActual,
            },
          ],
          'transmissionFactors': <Object?>[
            <String, Object?>{
              'address': _address(<String>['root', 'Glass']),
              'expected': 1.0,
              'actual': toyCarTransmissionActual,
            },
          ],
        }
      : null;
  return <String, Object?>{
    'authoredDefaultSceneSheenCount': 1,
    'installedDefaultSceneSheenCount': 1,
    'installedDefaultSceneSheen': <Object?>[
      <String, Object?>{
        'authoredAddress': authoredAddress,
        'concreteAddress': concreteAddress,
        'materialType': 'FlutterSceneExtendedPbrMaterial',
        'hasSheenIntent': true,
        'usesSheenShader': true,
        'usesClearcoatShader': false,
        'sheenColorFactor': evidence.color,
        'sheenRoughness': evidence.roughness,
        'sheenColorTextureExpected': evidence.colorTexture,
        'sheenColorTextureGpuBacked': evidence.colorTexture,
        'sheenRoughnessTextureExpected': evidence.roughnessTexture,
        'sheenRoughnessTextureGpuBacked': evidence.roughnessTexture,
      },
    ],
    'noExtraRuntimeSheen': true,
    'genericSeparateExtensionRoles': genericRoles,
    'nonDefaultDependencyBoundary':
        'Authored dependency indices are recorded separately; only '
            'default-scene suffix-resolved primitives are installed and rendered.',
  };
}

Future<void> _writeFixtureModel(
  Directory root,
  String model, {
  double framesPerSecond = 60.0,
  bool renderPolicyActive = true,
  bool renderPolicyAlways = true,
  double toyCarClearcoatActual = 1.0,
  double toyCarTransmissionActual = 1.0,
  bool fixtureValidation = true,
  _ReadyMutation? readyMutation,
}) async {
  final names = <String>[
    for (final view in _views[model]!)
      for (final pass in _passes) '${model}_${view}_$pass',
  ];
  final state = jsonDecode(
    File(
      'tools/material_extension_acceptance/fixtures/'
      'plan018_controlled_comparison_state.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  final modelState =
      (state['models'] as Map<String, dynamic>)[model] as Map<String, dynamic>;
  final stateLighting = state['lighting'] as Map<String, dynamic>;
  final log = StringBuffer();
  final readyPayloads = <String>[];
  var readyIndex = 0;
  for (final name in names) {
    final parts = name.substring(model.length + 1).split('_');
    final view = parts.first;
    final pass = parts.last;
    final camera = view == 'context'
        ? ((modelState['context'] as Map<String, dynamic>)['camera']
            as Map<String, dynamic>)
        : ((modelState['cameras'] as Map<String, dynamic>)[view]
            as Map<String, dynamic>);
    final environmentIntensity = pass == 'directOnly' ? 0.0 : 1.0;
    final keyLightIntensity = pass == 'iblOnly' ? 0.0 : 3.0;
    final ready = <String, Object?>{
      'status': 'candidate-only',
      'modelId': model,
      'stateSha256': _stateSha,
      'rootPubspecSha256': _rootPubspecSha,
      'rootLockSha256': _rootLockSha,
      'flutterSceneRef': _pin,
      'flutterSceneResolvedRef': _pin,
      'modelSha256': modelState['sha256'],
      'environmentSha256': _environmentSha,
      'blockingDiagnostics': 0,
      'showSkybox': false,
      'toneMapping': 'pbrNeutral',
      'outputColorSpace': 'sRGB',
      'authoredDependencyInventory': _authoredInventory(model),
      'defaultSceneInventory': _defaultInventory(model),
      'installedMaterialProbe': _installedMaterialProbe(
        model,
        toyCarClearcoatActual: toyCarClearcoatActual,
        toyCarTransmissionActual: toyCarTransmissionActual,
      ),
      'stage': name,
      'view': view,
      'pass': pass,
      'logicalWidth': 402.0,
      'logicalHeight': 874.0,
      'devicePixelRatio': 3.0,
      'physicalWidth': 1206,
      'physicalHeight': 2622,
      'postCameraFrameTail': 12,
      'freshCompatibleStatsSamples': 2,
      'cameraPosition': List<Object?>.from(camera['position'] as List),
      'renderPolicyAlways': renderPolicyAlways,
      'framesPerSecond': framesPerSecond,
      'renderPolicyActive': renderPolicyActive,
      'appliedEnvironmentIntensity': environmentIntensity,
      'appliedKeyLightIntensity': keyLightIntensity,
      'appliedStageLighting': <String, Object?>{
        'environmentPresent': true,
        'environmentIntensity': environmentIntensity,
        'keyLightPresent': true,
        'keyLightIntensity': keyLightIntensity,
        'keyLightDirection': List<Object?>.from(
          stateLighting['keyLightDirectionFlutterSceneWorld'] as List,
        ),
        'keyLightColor': List<Object?>.from(
          stateLighting['keyLightColorLinear'] as List,
        ),
        'keyLightCastsShadow': stateLighting['keyLightCastsShadow'],
        'ambientOcclusion': stateLighting['ambientOcclusion'],
        'exposure': stateLighting['exposure'],
      },
    };
    if (readyIndex == 0) {
      readyMutation?.call(ready);
    }
    readyIndex += 1;
    final payload = jsonEncode(ready);
    final payloadBytes = utf8.encode(payload);
    readyPayloads.add(payload);
    log.writeln(
      'flutter: PLAN018_READY ${jsonEncode(<String, Object?>{
            'stage': name,
            'sha256': sha256.convert(payloadBytes).toString(),
            'byteLength': payloadBytes.length,
          })}',
    );
  }
  final complete = <String, Object?>{
    'status': 'candidate-only',
    'integrationPath': 'executed by flutter drive',
    'modelId': model,
    'screenshots': names,
    'count': names.length,
    'comparisonBoundary': 'direction/conformance-only',
  };
  log
    ..writeln('flutter: PLAN018_COMPLETE ${jsonEncode(complete)}')
    ..writeln('All tests passed.');
  final logs = Directory('${root.path}/logs')..createSync(recursive: true);
  File('${logs.path}/$model.log').writeAsStringSync(log.toString());
  final processImagePath =
      '/Users/test/Library/Developer/CoreSimulator/Devices/$_udid/data/'
      'Containers/Bundle/Application/fixture/Runner.app/Runner';
  final senderImagePath =
      '/Users/test/Library/Developer/CoreSimulator/Devices/$_udid/data/'
      'Containers/Bundle/Application/fixture/Runner.app/Frameworks/'
      'Flutter.framework/Flutter';
  final commonRecord = <String, Object?>{
    'eventType': 'logEvent',
    'messageType': 'Default',
    'processId': 77419,
    'processImagePath': processImagePath,
    'processImageUuid': '333C2EA5-B912-3982-BD53-5D5A27DE3CFE',
    'senderImagePath': senderImagePath,
    'bootUuid': '0AB9030C-68E8-4531-936E-E77BF316227A',
  };
  File('${logs.path}/$model.impeller.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'status': 'candidate-only',
      'executionEvidence': fixtureValidation ? 'not run' : 'verified locally',
      'fixtureValidation': fixtureValidation,
      'source': 'iOS Simulator unified log',
      'modelId': model,
      'deviceUdid': _udid,
      'captureWindow': <String, Object?>{
        'startedAt': '2026-07-21T08:35:00.000000+00:00',
        'finishedAt': '2026-07-21T08:35:30.000000+00:00',
      },
      'queryCommand': <String>[
        '/usr/bin/xcrun',
        'simctl',
        'spawn',
        _udid,
        'log',
        'show',
        '--start',
        '2026-07-21 08:35:00+0000',
        '--end',
        '2026-07-21 08:35:30+0000',
        '--style',
        'json',
        '--predicate',
        'process == "Runner" AND '
            '(eventMessage CONTAINS "Using the Impeller rendering backend" OR '
            'eventMessage CONTAINS "PLAN018_COMPLETE")',
      ],
      'records': <Object?>[
        <String, Object?>{
          'kind': 'impeller',
          'timestamp': '2026-07-21 11:35:01.000000+0300',
          'eventMessage': '[IMPORTANT:flutter/shell/platform/darwin/graphics/'
              'FlutterDarwinContextMetalImpeller.mm(45)] '
              'Using the Impeller rendering backend (Metal).',
          ...commonRecord,
        },
        <String, Object?>{
          'kind': 'complete',
          'timestamp': '2026-07-21 11:35:20.000000+0300',
          'eventMessage': 'flutter: PLAN018_COMPLETE ${jsonEncode(complete)}',
          ...commonRecord,
        },
      ],
    }),
  );
  File('${root.path}/plan018_integration_response_$model.json')
      .writeAsStringSync(
    jsonEncode(<String, Object?>{
      'modelId': model,
      'expectedScreenshotNames': names,
      'readyPayloads': readyPayloads,
      'status': 'candidate-only',
      'integrationPath': 'executed by flutter drive',
    }),
  );
  for (final name in names) {
    _writePng(File('${root.path}/$name.png'));
  }
}

void _writePng(File file) {
  final bytes = Uint8List(24)
    ..setAll(0, const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  final data = ByteData.sublistView(bytes)
    ..setUint32(16, 1206)
    ..setUint32(20, 2622);
  file.writeAsBytesSync(data.buffer.asUint8List());
}

Future<Directory> _writeThreeFixture() async {
  final root = await Directory.systemTemp.createTemp(
    'plan018_three_capture_fixture_',
  );
  final captureRoot = Directory('${root.path}/threejs')
    ..createSync(recursive: true);
  final inventory = <Map<String, Object?>>[];
  final captures = <Map<String, Object?>>[];
  for (final entry in _views.entries) {
    for (final view in entry.value) {
      for (final pass in _passes) {
        final fileName = '${entry.key}_${view}_$pass.png';
        final file = File('${captureRoot.path}/$fileName');
        _writePng(file);
        final bytes = file.readAsBytesSync();
        inventory.add(<String, Object?>{
          'modelId': entry.key,
          'view': view,
          'pass': pass,
          'fileName': fileName,
        });
        captures.add(<String, Object?>{
          'modelId': entry.key,
          'view': view,
          'pass': pass,
          'path': 'fixture/threejs/$fileName',
          'sha256': sha256.convert(bytes).toString(),
          'byteLength': bytes.length,
          'dimensions': <String, Object?>{
            'width': 1206,
            'height': 2622,
          },
        });
      }
    }
  }
  File('${root.path}/evidence.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'status': 'verified locally',
      'stateSha256': _stateSha,
      'captureInventory': inventory,
      'captures': captures,
    }),
  );
  return root;
}
