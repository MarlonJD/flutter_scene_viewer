import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _runner = 'tools/run_plan018_ios_capture.py';
const _candidateStateSha256 =
    '385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843';
const _nativeStateSha256 =
    'e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63';
const _rootPubspecSha256 =
    '89538562bf96a228fdd13c0d0a6a2ee92df27616615f4c42116b61ca464d5586';
const _rootLockSha256 =
    '7c9415caf27fdca2453234a7ea61e7a54df79eef25947a7767e4486206eeaa95';
const _flutterSceneRef = '766351c865c621e8720c726f9aa51173ce76e786';
const _environmentSha256 =
    'ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a';
const _udid = '10C2CF77-CBA8-4948-ADD5-24C49D375059';

void main() {
  test('renderer-native capture freeze matches every current source byte',
      () async {
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
print(json.dumps(module.collect_source_hashes()))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final hashes = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    expect(hashes,
        contains('lib/src/internal/material_extension_native_applier.dart'));
    expect(
      hashes,
      contains(
        'tools/reference_renderers/threejs_material_extension_fixture/'
        'analyze_plan018_renderer_native_sheen_control.mjs',
      ),
    );
    expect(
      hashes,
      contains(
        'tools/material_extension_acceptance/fixtures/'
        'plan018_renderer_native_scalar_sheen_control_state.json',
      ),
    );
  });

  test('runner separates current native controls from candidate history',
      () async {
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
state = module.load_renderer_native_control_state()
valid = module.resolve_renderer_native_run_root(
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/renderer-native-run-contract-test"
)
try:
    module.resolve_renderer_native_run_root(
        "tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-current"
    )
except module.CaptureError as error:
    rejected = str(error)
else:
    rejected = None
print(json.dumps({
    "candidateStateSha256": module.EXPECTED_STATE_SHA256,
    "candidateModels": list(module.EXPECTED_MODELS),
    "nativeStateSha256": module.EXPECTED_NATIVE_CONTROL_STATE_SHA256,
    "nativeModels": list(module.EXPECTED_NATIVE_CONTROL_MODELS),
    "stateName": state["name"],
    "inventory": {
        model: module.expected_renderer_native_control_names(state, model)
        for model in module.EXPECTED_NATIVE_CONTROL_MODELS
    },
    "validName": valid.name,
    "candidatePrefixRejected": rejected,
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
        'candidateStateSha256': _candidateStateSha256,
        'candidateModels': <Object?>[
          'sheen_chair',
          'sheen_cloth',
          'glam_velvet_sofa',
          'toycar',
        ],
        'nativeStateSha256': _nativeStateSha256,
        'nativeModels': <Object?>[
          'renderer_native_scalar_sheen_on',
          'renderer_native_scalar_sheen_off',
        ],
        'stateName': 'plan018_renderer_native_scalar_sheen_control',
        'inventory': <String, Object?>{
          'renderer_native_scalar_sheen_on': <Object?>[
            'renderer_native_scalar_sheen_on_grazing_directOnly',
            'renderer_native_scalar_sheen_on_grazing_iblOnly',
            'renderer_native_scalar_sheen_on_grazing_combined',
          ],
          'renderer_native_scalar_sheen_off': <Object?>[
            'renderer_native_scalar_sheen_off_grazing_directOnly',
            'renderer_native_scalar_sheen_off_grazing_iblOnly',
            'renderer_native_scalar_sheen_off_grazing_combined',
          ],
        },
        'validName': 'renderer-native-run-contract-test',
        'candidatePrefixRejected':
            'Run-root name must begin with renderer-native-run-',
      },
    );
  });

  test('native run-root inspection rejects nested foreign artifacts', () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_nested_artifact_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    final logs = Directory('${root.path}/logs')..createSync();
    File('${logs.path}/foreign.log').writeAsStringSync('foreign\n');
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.inspect_renderer_native_run_root(
        Path(${jsonEncode(root.path)}),
        "renderer_native_scalar_sheen_on",
        {"udid": "$_udid"},
        {"sourceSha256": {"runner": "a" * 64}},
    )
except module.CaptureError as error:
    print(error)
else:
    raise SystemExit("nested foreign artifact was accepted")
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(
      probe.stdout,
      contains('Renderer-native run root has unexpected nested entry'),
    );
  });

  test('native run-root inspection rejects a partial retained control',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_partial_control_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    _writePng(File(
      '${root.path}/'
      'renderer_native_scalar_sheen_off_grazing_directOnly.png',
    ));
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.inspect_renderer_native_run_root(
        Path(${jsonEncode(root.path)}),
        "renderer_native_scalar_sheen_on",
        {"udid": "$_udid"},
        {"sourceSha256": {"runner": "a" * 64}},
    )
except module.CaptureError as error:
    print(error)
else:
    raise SystemExit("partial retained control was accepted")
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(
      probe.stdout,
      contains('log or response is missing'),
    );
  });

  test('runner derives native application from authored control data',
      () async {
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
state = module.load_renderer_native_control_state()
result = {}
for model_id in module.EXPECTED_NATIVE_CONTROL_MODELS:
    contract = module.derive_renderer_native_control_contract(
        state["models"][model_id]
    )
    probe = contract["installedProbe"]
    result[model_id] = {
        "application": probe["application"],
        "featureMaturity": probe["featureMaturity"],
        "authoredCount": probe["authoredDefaultSceneSheenCount"],
        "installedCount": probe["installedDefaultSceneSheenCount"],
        "nativeCount": probe["rendererNativeCount"],
        "candidateCount": probe["packageLocalCandidateCount"],
        "installed": probe["installedDefaultSceneSheen"],
    }
print(json.dumps(result))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );

    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final result = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    final on = Map<String, Object?>.from(
      result['renderer_native_scalar_sheen_on']! as Map,
    );
    expect(on['application'], 'rendererNative');
    expect(on['featureMaturity'], 'release pending');
    expect(on['authoredCount'], 1);
    expect(on['installedCount'], 1);
    expect(on['nativeCount'], 1);
    expect(on['candidateCount'], 0);
    final installed = (on['installed']! as List<Object?>).single as Map;
    expect(installed['materialType'], 'PhysicallyBasedMaterial');
    expect(installed['application'], 'rendererNative');
    expect(installed['sheenColorFactor'], <Object?>[1.0, 1.0, 1.0]);
    expect(installed['sheenRoughness'], 0.5);
    expect(installed['sheenColorTextureExpected'], isFalse);
    expect(installed['sheenRoughnessTextureExpected'], isFalse);
    expect(installed['sheenColorTextureUvSet'], 0);
    expect(installed['sheenRoughnessTextureUvSet'], 0);

    final off = Map<String, Object?>.from(
      result['renderer_native_scalar_sheen_off']! as Map,
    );
    expect(off['application'], 'none');
    expect(off['featureMaturity'], 'release pending');
    expect(off['authoredCount'], 0);
    expect(off['installedCount'], 0);
    expect(off['nativeCount'], 0);
    expect(off['candidateCount'], 0);
    expect(off['installed'], isEmpty);
  });

  test('runner fixture validates exact native on and sheen-off payloads',
      () async {
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      final root = await Directory.systemTemp.createTemp(
        'plan018_renderer_native_runner_fixture_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      await _writeNativeFixtureModel(root, modelId);

      final validation = await Process.run(
        'python3',
        <String>[
          _runner,
          '--validate-renderer-native-fixture',
          '--model',
          modelId,
          '--run-root',
          root.path,
        ],
        environment: const <String, String>{
          'PYTHONDONTWRITEBYTECODE': '1',
        },
      );
      expect(
        validation.exitCode,
        0,
        reason: '${validation.stdout}\n${validation.stderr}',
      );
      final result = Map<String, Object?>.from(
        jsonDecode(validation.stdout as String) as Map,
      );
      expect(result['status'], 'release pending');
      expect(result['executionEvidence'], 'not run');
      expect(
        result['application'],
        modelId.endsWith('_on') ? 'rendererNative' : 'none',
      );
      expect(result['orderedScreenshotNames'], hasLength(3));
      expect(result['artifactCount'], 3);
      expect(result['fixtureValidation'], isTrue);
    }
  });

  test('runner plans current native capture without candidate labels',
      () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
import json
import types

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.repository_guard = lambda: {"guard": "verified"}
module.query_devices = lambda fixture: ({}, [], "fixture")
module.validate_device = lambda udid, simctl, devices, source: {
    "udid": udid,
    "source": source,
}
module.inspect_renderer_native_run_root = lambda *args: None
arguments = types.SimpleNamespace(
    model="renderer_native_scalar_sheen_on",
    udid="$_udid",
    run_root="tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/renderer-native-run-plan-test",
    device_fixture=None,
)
print(json.dumps(module.plan_renderer_native_capture(arguments)))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final plan = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    expect(plan['mode'], 'plan');
    expect(plan['status'], 'release pending');
    expect(plan['application'], 'rendererNative');
    expect(plan['targetEvidence'], 'not run');
    expect(plan['modelId'], 'renderer_native_scalar_sheen_on');
    expect(plan['runRoot'], endsWith('renderer-native-run-plan-test'));
    expect(
        plan['command'],
        contains('--dart-define=PLAN018_MODEL_ID='
            'renderer_native_scalar_sheen_on'));
    expect(jsonEncode(plan), isNot(contains('candidate-only')));
  });

  test('runner CLI requires the explicit renderer-native control mode',
      () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import contextlib
import importlib.util
import io
import json
import sys

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.repository_guard = lambda: {"guard": "verified"}
module.query_devices = lambda fixture: ({}, [], "fixture")
module.validate_device = lambda udid, simctl, devices, source: {
    "udid": udid,
    "source": source,
}
module.inspect_renderer_native_run_root = lambda *args: None
sys.argv = [
    "run_plan018_ios_capture.py",
    "--renderer-native-control",
    "--plan",
    "--model",
    "renderer_native_scalar_sheen_on",
    "--udid",
    "$_udid",
    "--run-root",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/renderer-native-run-cli-test",
]
output = io.StringIO()
with contextlib.redirect_stdout(output):
    exit_code = module.main()
print(json.dumps({
    "exitCode": exit_code,
    "result": json.loads(output.getvalue()),
}))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final result = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    expect(result['exitCode'], 0);
    final plan = Map<String, Object?>.from(result['result']! as Map);
    expect(plan['status'], 'release pending');
    expect(plan['application'], 'rendererNative');
    expect(plan['runRoot'], endsWith('renderer-native-run-cli-test'));
  });

  test('runner fixture finalization keeps native evidence claims scoped',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_final_fixture_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      await _writeNativeFixtureModel(root, modelId);
    }

    final validation = await Process.run(
      'python3',
      <String>[
        _runner,
        '--validate-renderer-native-fixture',
        '--finalize',
        '--run-root',
        root.path,
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(
      validation.exitCode,
      0,
      reason: '${validation.stdout}\n${validation.stderr}',
    );
    final evidence = Map<String, Object?>.from(
      jsonDecode(validation.stdout as String) as Map,
    );
    expect(evidence['status'], 'release pending');
    expect(evidence['executionEvidence'], 'not run');
    expect(evidence['runtimeAvailability'], 'available');
    expect(evidence['featureMaturity'], 'release pending');
    expect(evidence['targetEvidence'], 'not run');
    expect(evidence['visualEvidence'], 'not run');
    expect(evidence['stateSha256'], _nativeStateSha256);
    expect(evidence['historicalCandidateStateSha256'], _candidateStateSha256);
    expect(evidence['pngCount'], 6);
    expect(evidence['modelCount'], 2);
    expect(evidence['physicalIos'], 'not run');
    expect(evidence['android'], 'not run');
    expect(evidence['web'], 'not run');
    expect(evidence['productionReadiness'], 'not run');
    expect(evidence['physicalCorrectness'], 'not run');
    expect(evidence['generalPixelParity'], 'not run');
    expect(evidence['fixtureValidation'], isTrue);
    expect(File('${root.path}/evidence.json').existsSync(), isFalse);
  });

  test('runner success manifests cannot regress to candidate labels', () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import copy
import hashlib
import importlib.util
import json

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
model = "renderer_native_scalar_sheen_on"
device = {"udid": "$_udid"}
guard = {"sourceSha256": {"fixture": "hash"}}
validation = {
    "status": "release pending",
    "executionEvidence": "verified locally",
    "application": "rendererNative",
    "featureMaturity": "release pending",
    "targetEvidence": "verified locally",
    "backendEvidence": {
        "captureWindow": {
            "startedAt": "2026-07-22T08:35:00+00:00",
            "finishedAt": "2026-07-22T08:35:30+00:00",
        },
    },
}
manifest = {
    "schemaVersion": 1,
    "status": "release pending",
    "executionEvidence": "verified locally",
    "application": "rendererNative",
    "runtimeAvailability": "available",
    "featureMaturity": "release pending",
    "targetEvidence": "verified locally",
    "visualEvidence": "not run",
    "modelId": model,
    "captureExitCode": 0,
    "startedAt": "2026-07-22T08:35:00+00:00",
    "captureFinishedAt": "2026-07-22T08:35:30+00:00",
    "workingDirectory": str(module.HARNESS_ROOT),
    "command": module.capture_command(model, "$_udid"),
    "environment": {"PLAN018_SCREENSHOT_OUTPUT": "/fixture"},
    "shell": False,
    "captureTimeoutSeconds": module.FLUTTER_DRIVE_TIMEOUT_SECONDS,
    "terminationGraceSeconds": module.PROCESS_TERMINATION_GRACE_SECONDS,
    "timeoutContract": module.timeout_contract(),
    "device": device,
    "preflight": guard,
    "postflight": guard,
    "artifactRecordSha256": hashlib.sha256(
        module.json_text(validation).encode()
    ).hexdigest(),
    "result": validation,
    "physicalTargets": "not run",
    "comparisonBoundary": "renderer-local sheen on/off control only",
}
module.validate_renderer_native_success_manifest_record(
    manifest,
    model_id=model,
    validation=validation,
    expected_guard=guard,
    expected_device=device,
    run_root="/fixture",
)
mutant = copy.deepcopy(manifest)
mutant["status"] = "candidate-only"
try:
    module.validate_renderer_native_success_manifest_record(
        mutant,
        model_id=model,
        validation=validation,
        expected_guard=guard,
        expected_device=device,
        run_root="/fixture",
    )
except module.CaptureError as error:
    rejected = str(error)
else:
    rejected = None
print(json.dumps({"valid": True, "candidateRejected": rejected}))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final result = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    expect(result['valid'], isTrue);
    expect(
      result['candidateRejected'],
      contains('renderer-native success manifest drifted'),
    );
  });

  test('real native finalizer binds visual analysis without release claims',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_real_finalizer_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      await _writeNativeFixtureModel(root, modelId);
    }
    final manifests = Directory('${root.path}/manifests')
      ..createSync(recursive: true);
    File('${manifests.path}/renderer_native_scalar_sheen_on.json')
        .writeAsStringSync('{}\n');
    File('${manifests.path}/renderer_native_scalar_sheen_off.json')
        .writeAsStringSync('{}\n');
    File('${root.path}/device.json').writeAsStringSync(
      jsonEncode(<String, Object?>{'udid': _udid}),
    );

    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(${jsonEncode(root.path)})
models = {
    model: module.validate_renderer_native_control_artifacts(
        root,
        model,
        fixture_validation=True,
    )
    for model in module.EXPECTED_NATIVE_CONTROL_MODELS
}
for model in models.values():
    model["executionEvidence"] = "verified locally"
    model["fixtureValidation"] = False
    model["targetEvidence"] = "verified locally"
guard = {"sourceSha256": {"runner": "a" * 64}}
device = {"udid": "$_udid"}
visual = {
    "status": "verified locally",
    "executionEvidence": "verified locally",
    "visualEvidence": "verified locally",
    "featureMaturity": "release pending",
    "application": {"sheenOn": "rendererNative", "sheenOff": "none"},
    "comparisonBoundary": "renderer-local sheen on/off control only",
    "stateSha256": module.EXPECTED_NATIVE_CONTROL_STATE_SHA256,
    "frameCount": 6,
    "onOffComparisonCount": 3,
    "externalReference": "not run",
    "physicalIos": "not run",
    "android": "not run",
    "web": "not run",
    "physicalCorrectness": "not run",
    "generalPixelParity": "not run",
    "productionReadiness": "not run",
}
visual["frames"] = [
    {"fileName": Path(artifact["path"]).name, **artifact}
    for model in models.values()
    for artifact in model["artifacts"]
]
module.resolve_renderer_native_run_root = lambda _: root
module.repository_guard = lambda: guard
module.validate_renderer_native_control_artifacts = (
    lambda _root, model: models[model]
)
module.validate_renderer_native_success_manifest = lambda *args, **kwargs: {}
module.analyze_renderer_native_control_images = lambda _root: visual
result = module.finalize_renderer_native_capture(
    argparse.Namespace(run_root=str(root)),
)
print(json.dumps({
    "result": result,
    "stored": json.loads((root / "evidence.json").read_text()),
}))
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    final payload = Map<String, Object?>.from(
      jsonDecode(probe.stdout as String) as Map,
    );
    final result = Map<String, Object?>.from(payload['result']! as Map);
    expect(payload['stored'], result);
    expect(result['status'], 'release pending');
    expect(result['executionEvidence'], 'verified locally');
    expect(result['targetEvidence'], 'verified locally');
    expect(result['visualEvidence'], 'verified locally');
    expect(result['runtimeAvailability'], 'available');
    expect(result['featureMaturity'], 'release pending');
    expect(result['visualAnalysis'], isA<Map>());
    expect(result['physicalIos'], 'not run');
    expect(result['android'], 'not run');
    expect(result['web'], 'not run');
    expect(result['release'], 'release pending');
    expect(result['productionReadiness'], 'not run');
    expect(result['physicalCorrectness'], 'not run');
    expect(result['generalPixelParity'], 'not run');
    expect(result['manifests'], isA<List<Object?>>());
    expect((result['manifests']! as List<Object?>), hasLength(2));
  });

  test('real native aggregate rejects fixture-only model records', () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_fixture_rejection_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      await _writeNativeFixtureModel(root, modelId);
    }
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(${jsonEncode(root.path)})
models = [
    module.validate_renderer_native_control_artifacts(
        root,
        model,
        fixture_validation=True,
    )
    for model in module.EXPECTED_NATIVE_CONTROL_MODELS
]
try:
    module.renderer_native_evidence_from_models(
        root,
        models,
        source_hashes={},
        device=None,
        fixture_validation=False,
    )
except module.CaptureError as error:
    print(error)
else:
    raise SystemExit("fixture-only records were accepted as real evidence")
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(
      probe.stdout,
      contains('Renderer-native real model evidence drifted'),
    );
  });

  test('real native aggregate binds each visual frame exactly once', () async {
    final root = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_visual_binding_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      await _writeNativeFixtureModel(root, modelId);
    }
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = Path(${jsonEncode(root.path)})
models = [
    module.validate_renderer_native_control_artifacts(
        root,
        model,
        fixture_validation=True,
    )
    for model in module.EXPECTED_NATIVE_CONTROL_MODELS
]
for model in models:
    model["executionEvidence"] = "verified locally"
    model["fixtureValidation"] = False
    model["targetEvidence"] = "verified locally"
first = models[0]["artifacts"][0]
visual = {"frames": [
    {"fileName": Path(first["path"]).name, **first}
    for _ in range(6)
]}
try:
    module.renderer_native_evidence_from_models(
        root,
        models,
        source_hashes={"runner": "a" * 64},
        device={"udid": "$_udid"},
        fixture_validation=False,
        visual_evidence="verified locally",
        visual_analysis=visual,
    )
except module.CaptureError as error:
    print(error)
else:
    raise SystemExit("duplicate visual frames were accepted")
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    expect(
      probe.stdout,
      contains('Renderer-native visual frame binding drifted'),
    );
  });
}

Future<void> _writeNativeFixtureModel(
  Directory root,
  String modelId,
) async {
  final contractProbe = await Process.run(
    'python3',
    <String>[
      '-c',
      '''
import importlib.util
import json

spec = importlib.util.spec_from_file_location("plan018_runner", "$_runner")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
state = module.load_renderer_native_control_state()
print(json.dumps({
    "state": state,
    "contract": module.derive_renderer_native_control_contract(
        state["models"]["$modelId"]
    ),
}))
''',
    ],
    environment: const <String, String>{
      'PYTHONDONTWRITEBYTECODE': '1',
    },
  );
  expect(
    contractProbe.exitCode,
    0,
    reason: '${contractProbe.stdout}\n${contractProbe.stderr}',
  );
  final payload = Map<String, Object?>.from(
    jsonDecode(contractProbe.stdout as String) as Map,
  );
  final state = Map<String, Object?>.from(payload['state']! as Map);
  final contract = Map<String, Object?>.from(payload['contract']! as Map);
  final models = Map<String, Object?>.from(state['models']! as Map);
  final model = Map<String, Object?>.from(models[modelId]! as Map);
  final lighting = Map<String, Object?>.from(state['lighting']! as Map);
  final camera = Map<String, Object?>.from(
    Map<String, Object?>.from(model['cameras']! as Map)['grazing']! as Map,
  );
  final passes = (state['renderPasses']! as List<Object?>).cast<String>();
  final names = <String>[
    for (final pass in passes) '${modelId}_grazing_$pass',
  ];
  final installedProbe =
      Map<String, Object?>.from(contract['installedProbe']! as Map);
  final application = installedProbe['application']! as String;
  final log = StringBuffer();
  final readyPayloads = <String>[];
  for (final name in names) {
    final renderPass = name.substring(name.lastIndexOf('_') + 1);
    final environmentIntensity = renderPass == 'directOnly' ? 0.0 : 1.0;
    final keyLightIntensity = renderPass == 'iblOnly' ? 0.0 : 3.0;
    final ready = <String, Object?>{
      'status': 'release pending',
      'application': application,
      'runtimeAvailability': 'available',
      'featureMaturity': 'release pending',
      'targetEvidence': 'not run',
      'visualEvidence': 'not run',
      'comparisonBoundary': 'renderer-local sheen on/off control only',
      'modelId': modelId,
      'stateSha256': _nativeStateSha256,
      'rootPubspecSha256': _rootPubspecSha256,
      'rootLockSha256': _rootLockSha256,
      'flutterSceneRef': _flutterSceneRef,
      'flutterSceneResolvedRef': _flutterSceneRef,
      'modelSha256': model['sha256'],
      'environmentSha256': _environmentSha256,
      'authoredDependencyInventory': contract['authoredInventory'],
      'defaultSceneInventory': contract['defaultInventory'],
      'installedMaterialProbe': installedProbe,
      'blockingDiagnostics': 0,
      'showSkybox': false,
      'toneMapping': 'pbrNeutral',
      'outputColorSpace': 'sRGB',
      'stage': name,
      'view': 'grazing',
      'pass': renderPass,
      'logicalWidth': 402.0,
      'logicalHeight': 874.0,
      'devicePixelRatio': 3.0,
      'physicalWidth': 1206,
      'physicalHeight': 2622,
      'postCameraFrameTail': 12,
      'freshCompatibleStatsSamples': 2,
      'cameraPosition': List<Object?>.from(camera['position']! as List),
      'renderPolicyAlways': true,
      'framesPerSecond': 60.0,
      'renderPolicyActive': true,
      'appliedEnvironmentIntensity': environmentIntensity,
      'appliedKeyLightIntensity': keyLightIntensity,
      'appliedStageLighting': <String, Object?>{
        'environmentPresent': true,
        'environmentIntensity': environmentIntensity,
        'keyLightPresent': true,
        'keyLightIntensity': keyLightIntensity,
        'keyLightDirection': List<Object?>.from(
          Float32List.fromList(
            (lighting['keyLightDirectionFlutterSceneWorld']! as List)
                .cast<num>()
                .map((value) => value.toDouble())
                .toList(),
          ),
        ),
        'keyLightColor': List<Object?>.from(
          lighting['keyLightColorLinear']! as List,
        ),
        'keyLightCastsShadow': lighting['keyLightCastsShadow'],
        'ambientOcclusion': lighting['ambientOcclusion'],
        'exposure': lighting['exposure'],
      },
    };
    final encoded = jsonEncode(ready);
    final bytes = utf8.encode(encoded);
    readyPayloads.add(encoded);
    log.writeln(
      'flutter: PLAN018_READY ${jsonEncode(<String, Object?>{
            'stage': name,
            'sha256': sha256.convert(bytes).toString(),
            'byteLength': bytes.length,
          })}',
    );
  }
  final complete = <String, Object?>{
    'status': 'release pending',
    'application': application,
    'integrationPath': 'executed by flutter drive',
    'modelId': modelId,
    'screenshots': names,
    'count': names.length,
    'comparisonBoundary': 'renderer-local sheen on/off control only',
  };
  log
    ..writeln('flutter: PLAN018_COMPLETE ${jsonEncode(complete)}')
    ..writeln('All tests passed.');

  final logs = Directory('${root.path}/logs')..createSync(recursive: true);
  File('${logs.path}/$modelId.log').writeAsStringSync(log.toString());
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
  File('${logs.path}/$modelId.impeller.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'status': 'release pending',
      'executionEvidence': 'not run',
      'fixtureValidation': true,
      'source': 'iOS Simulator unified log',
      'modelId': modelId,
      'deviceUdid': _udid,
      'captureWindow': <String, Object?>{
        'startedAt': '2026-07-22T08:35:00.000000+00:00',
        'finishedAt': '2026-07-22T08:35:30.000000+00:00',
      },
      'queryCommand': <String>[
        '/usr/bin/xcrun',
        'simctl',
        'spawn',
        _udid,
        'log',
        'show',
        '--start',
        '2026-07-22 08:35:00+0000',
        '--end',
        '2026-07-22 08:35:30+0000',
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
          'timestamp': '2026-07-22 11:35:01.000000+0300',
          'eventMessage': '[IMPORTANT:flutter/shell/platform/darwin/graphics/'
              'FlutterDarwinContextMetalImpeller.mm(45)] '
              'Using the Impeller rendering backend (Metal).',
          ...commonRecord,
        },
        <String, Object?>{
          'kind': 'complete',
          'timestamp': '2026-07-22 11:35:20.000000+0300',
          'eventMessage': 'flutter: PLAN018_COMPLETE ${jsonEncode(complete)}',
          ...commonRecord,
        },
      ],
    }),
  );
  File('${root.path}/plan018_integration_response_$modelId.json')
      .writeAsStringSync(
    jsonEncode(<String, Object?>{
      'modelId': modelId,
      'expectedScreenshotNames': names,
      'readyPayloads': readyPayloads,
      'status': 'release pending',
      'application': application,
      'comparisonBoundary': 'renderer-local sheen on/off control only',
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
  ByteData.sublistView(bytes)
    ..setUint32(16, 1206)
    ..setUint32(20, 2622);
  file.writeAsBytesSync(bytes);
}
