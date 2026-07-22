import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _generatorPath = 'tools/generate_plan018_ios_harness.py';
const _outputPath = 'tools/out/material_extension_acceptance/'
    'plan018_controlled_comparison/flutter_ios_harness';
const _statePath = 'tools/material_extension_acceptance/fixtures/'
    'plan018_controlled_comparison_state.json';
const _nativeControlStatePath = 'tools/material_extension_acceptance/fixtures/'
    'plan018_renderer_native_scalar_sheen_control_state.json';
const _nativeControlStateSha256 =
    'e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63';
const _flutterSceneRef = '766351c865c621e8720c726f9aa51173ce76e786';

void main() {
  test('Plan 018 analysis template survives current Flutter migration', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/analysis_options.yaml.tmpl',
    ).readAsStringSync();

    for (final platform in <String>[
      'android',
      'ios',
      'web',
      'windows',
      'macos',
      'linux',
    ]) {
      expect(source, contains('    - $platform/**'));
    }
  });

  test('Plan 018 driver keeps each model response artifact distinct', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/integration_test_driver.dart.tmpl',
    ).readAsStringSync();

    expect(source, contains("data?['modelId']"));
    expect(source, contains('plan018ModelAssetPaths.containsKey(modelId)'));
    expect(
      source,
      contains(r"'plan018_integration_response_$modelId'"),
    );
    expect(
      source,
      isNot(contains("testOutputFilename: 'plan018_integration_response'")),
    );
  });

  test('Plan 018 READY transport hashes full payloads into bounded markers',
      () {
    final mainSource = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();
    final captureSource = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/plan018_capture_test.dart.tmpl',
    ).readAsStringSync();
    final driverSource = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/integration_test_driver.dart.tmpl',
    ).readAsStringSync();

    expect(mainSource, contains('final payload = jsonEncode(record);'));
    expect(mainSource, contains('final payloadBytes = utf8.encode(payload);'));
    expect(mainSource, contains('sha256.convert(payloadBytes).toString()'));
    expect(mainSource, contains("'byteLength': payloadBytes.length"));
    expect(mainSource, contains('List<String> get readyPayloads'));
    expect(captureSource, contains("reportData!['readyPayloads']"));
    expect(driverSource, contains("data?['readyPayloads']"));
    expect(driverSource, contains('jsonDecode(payload)'));
    expect(driverSource, contains('Ready payload inventory mismatch'));
  });

  test('Plan 018 runtime template proves stable applied stage state', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    expect(source, contains("String.fromEnvironment('PLAN018_MODEL_ID')"));
    expect(source, contains('_lastTwoStatsAreStable(compatible)'));
    expect(source, contains('left.cameraDistance'));
    expect(source, contains('right.cameraDistance'));
    expect(source, contains('left.framesPerSecond > 0'));
    expect(source, contains('right.framesPerSecond > 0'));
    expect(source, contains('left.renderPolicyActive'));
    expect(source, contains('right.renderPolicyActive'));
    expect(source, contains('left.diagnosticsCount == right.diagnosticsCount'));
    expect(source, contains('_assertAppliedStageLighting()'));
    expect(source, contains('scene.environmentIntensity'));
    expect(source, contains('scene.directionalLight'));
    expect(source, contains("'appliedEnvironmentIntensity'"));
    expect(source, contains("'appliedKeyLightIntensity'"));
    expect(source, contains("'clearcoatFactors'"));
    expect(source, contains("'transmissionFactors'"));
    expect(
      source,
      contains("'framesPerSecond': compatible.last.framesPerSecond"),
    );
    expect(
      source,
      contains("'renderPolicyActive': compatible.last.renderPolicyActive"),
    );
  });

  test('Plan 018 runtime template resolves enum names statically', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    expect(
      source,
      contains('final Object? toneMapping = scene.toneMapping;'),
    );
    expect(source, contains('toneMapping is! Enum ||'));
    expect(source, contains("toneMapping.name != 'pbrNeutral'"));
    expect(
      source,
      isNot(contains('final dynamic toneMapping = scene.toneMapping;')),
    );
  });

  test('Plan 018 runtime template logs diagnostics before blocking', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    final diagnosticLog = source.indexOf(
      'for (final diagnostic in _controller.diagnostics) {',
    );
    final blockingCheck = source.indexOf(
      'final blocking = _blockingDiagnostics();',
    );
    expect(diagnosticLog, greaterThanOrEqualTo(0));
    expect(blockingCheck, greaterThanOrEqualTo(0));
    expect(diagnosticLog, lessThan(blockingCheck));
    expect(source, contains("'message': diagnostic.message"));
    expect(source, contains("'details': diagnostic.details"));
  });

  test('Plan 018 generic extension factors match authored reader patches', () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    expect(source, contains('patch.clearcoat ?? 0'));
    expect(source, contains('patch.transmission ?? 0'));
    expect(
      source,
      contains('_near(clearcoatFactor, expectedClearcoatFactor)'),
    );
    expect(
      source,
      contains('_near(transmissionFactor, expectedTransmissionFactor)'),
    );
    expect(source, contains("'expected': expectedClearcoatFactor"));
    expect(source, contains("'actual': clearcoatFactor"));
    expect(source, contains("'expected': expectedTransmissionFactor"));
    expect(source, contains("'actual': transmissionFactor"));
    expect(source, isNot(contains('if (!(clearcoatFactor > 0))')));
    expect(source, isNot(contains('if (!(transmissionFactor > 0))')));
  });

  test('Plan 018 generator rejects controlled-state byte drift', () {
    final source = File(_generatorPath).readAsStringSync();

    expect(
      source,
      contains(
        'PLAN018_STATE_SHA256 = '
        '"385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843"',
      ),
    );
    expect(
      source,
      contains(
        '_require_hash(STATE_PATH, PLAN018_STATE_SHA256, "controlled state")',
      ),
    );
    expect(
      source,
      isNot(contains('_require_hash(STATE_PATH, _sha256_path(STATE_PATH)')),
    );
  });

  test('Plan 018 generator keeps native controls outside candidate history',
      () async {
    final source = File(_generatorPath).readAsStringSync();
    expect(
      source,
      contains(
        'PLAN018_STATE_SHA256 = '
        '"385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843"',
      ),
    );
    expect(
      source,
      contains(
        'PLAN018_NATIVE_CONTROL_STATE_SHA256 = "$_nativeControlStateSha256"',
      ),
    );

    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util
import json

spec = importlib.util.spec_from_file_location("plan018_generator", "$_generatorPath")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
state = module._load_renderer_native_control_state()
print(json.dumps({
    "name": state["name"],
    "models": list(state["models"]),
    "inventory": module._renderer_native_control_capture_inventory(state),
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
        'name': 'plan018_renderer_native_scalar_sheen_control',
        'models': <Object?>[
          'renderer_native_scalar_sheen_on',
          'renderer_native_scalar_sheen_off',
        ],
        'inventory': <Object?>[
          'renderer_native_scalar_sheen_on_grazing_directOnly',
          'renderer_native_scalar_sheen_on_grazing_iblOnly',
          'renderer_native_scalar_sheen_on_grazing_combined',
          'renderer_native_scalar_sheen_off_grazing_directOnly',
          'renderer_native_scalar_sheen_off_grazing_iblOnly',
          'renderer_native_scalar_sheen_off_grazing_combined',
        ],
      },
    );
    expect(File(_nativeControlStatePath).existsSync(), isTrue);
  });

  test('Plan 018 generator treats candidate source hashes as provenance',
      () async {
    final probe = await Process.run(
      'python3',
      <String>[
        '-c',
        '''
import importlib.util

spec = importlib.util.spec_from_file_location("plan018_generator", "$_generatorPath")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
state = module._load_state()
module._verify_frozen_sources(state)
print("historical candidate provenance preserved")
''',
      ],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(
      probe.exitCode,
      0,
      reason: '${probe.stdout}\n${probe.stderr}',
    );
    expect(probe.stdout, contains('historical candidate provenance preserved'));
  });

  test('Plan 018 generator hard-pins the flutter_scene revision', () {
    final source = File(_generatorPath).readAsStringSync();

    expect(
      source,
      contains('FLUTTER_SCENE_REF = "$_flutterSceneRef"'),
    );
    expect(source, contains('ref != FLUTTER_SCENE_REF'));
  });

  test('Plan 018 runtime advertises verified native Simulator sheen evidence',
      () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    expect(source, contains('_assertRendererNativeSupport()'));
    expect(
      source,
      contains(
        RegExp(
          r'support\.backendKind\s*!=\s*'
          r'MaterialExtensionBackendKind\.rendererNative',
        ),
      ),
    );
    expect(
      source,
      contains(
        'MaterialExtensionMaturity.releasePending',
      ),
    );
    expect(
      source,
      contains(
        'MaterialExtensionEvidenceStatus.verifiedLocally',
      ),
    );
    expect(source, contains("'runtimeAvailability': 'available'"));
    expect(source, contains("'featureMaturity': featureMaturity"));
    expect(source, contains("maturity = 'release pending'"));
    expect(source, contains("'targetEvidence': 'not run'"));
    expect(source, contains("'visualEvidence': 'not run'"));
    expect(
      source,
      isNot(contains('iOS Simulator sheen support is not candidate-only.')),
    );
  });

  test('Plan 018 runtime proves hybrid sheen application without name routing',
      () {
    final source = File(
      'tools/material_extension_acceptance/'
      'plan018_ios_harness_templates/main.dart.tmpl',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'MaterialExtensionPatchGroup.specular',
      ),
    );
    expect(
      source,
      contains(
        "src/internal/glb_imported_texture_patch_reader.dart",
      ),
    );
    expect(source, contains('readGlbImportedTexturePatches('));
    expect(source, contains('_requiresPackageCandidateForSheen('));
    expect(source, contains('MaterialTextureSlot.baseColor'));
    expect(source, contains('MaterialTextureSlot.metallicRoughness'));
    expect(source, contains('MaterialTextureSlot.normal'));
    expect(source, contains('MaterialTextureSlot.occlusion'));
    expect(source, contains('MaterialTextureSlot.emissive'));
    expect(source, contains('!_isIdentityTransform(binding.transform)'));
    expect(
      source,
      contains(
        RegExp(
          r'final requiresCandidateBridge\s*=\s*'
          r'_requiresPackageCandidateForSheen\(entry\.key\);',
        ),
      ),
    );
    expect(source, contains('if (requiresCandidateBridge)'));
    expect(
      source,
      contains('material is! FlutterSceneExtendedPbrMaterial'),
    );
    expect(
      source,
      contains('material is FlutterSceneExtendedPbrMaterial'),
    );
    expect(source, contains('final dynamic nativeMaterial = material;'));
    expect(
      source,
      contains('final dynamic color = nativeMaterial.sheenColorFactor;'),
    );
    expect(source, contains('(color.x as num).toDouble()'));
    expect(source, contains('nativeMaterial.sheenRoughnessFactor'));
    expect(source, contains('nativeMaterial.usesRendererNativeSheen != true'));
    expect(source, contains('nativeMaterial.sheenColorTextureTexCoord'));
    expect(source, contains('nativeMaterial.sheenRoughnessTextureTexCoord'));
    expect(source, contains('_requireNativeTransform('));
    expect(source, contains("'application': application"));
    expect(source, contains("'rendererNativeCount'"));
    expect(source, contains("'packageLocalCandidateCount'"));
    expect(source, contains("'rendererNative'"));
    expect(source, contains("'packageLocalCandidate'"));
    expect(source, contains("'candidate-only'"));
    expect(source, contains("'release pending'"));
    for (final assetName in <String>['ToyCar', 'Fabric', 'Glass']) {
      expect(source, isNot(contains("'$assetName'")));
      expect(source, isNot(contains('"$assetName"')));
    }
  });

  test('Plan 018 resolved output rejects flutter_scene lock drift', () async {
    final output = Directory(_outputPath);
    final temporary = await Directory.systemTemp.createTemp(
      'plan018_ios_harness_lock_validation_',
    );
    try {
      _copyDirectory(output, temporary);
      _copyPackageConfig(output, temporary);
      final lock = File('${temporary.path}/pubspec.lock');
      expect(lock.existsSync(), isTrue);
      lock.writeAsStringSync(
        lock.readAsStringSync().replaceAll(
              _flutterSceneRef,
              '0000000000000000000000000000000000000000',
            ),
      );

      final validation = await Process.run(
        'python3',
        <String>[_generatorPath, '--validate-output', temporary.path],
      );
      expect(
        validation.exitCode,
        isNot(0),
        reason: 'resolved flutter_scene lock drift was accepted',
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('Plan 018 resolved output rejects package-config root drift', () async {
    final output = Directory(_outputPath);
    final temporary = await Directory.systemTemp.createTemp(
      'plan018_ios_harness_package_config_validation_',
    );
    try {
      _copyDirectory(output, temporary);
      _copyPackageConfig(output, temporary);
      final config = File('${temporary.path}/.dart_tool/package_config.json');
      expect(config.existsSync(), isTrue);
      config.writeAsStringSync(
        config.readAsStringSync().replaceFirst(
              _flutterSceneRef,
              '0000000000000000000000000000000000000000',
            ),
      );

      final validation = await Process.run(
        'python3',
        <String>[_generatorPath, '--validate-output', temporary.path],
      );
      expect(
        validation.exitCode,
        isNot(0),
        reason: 'flutter_scene package-config root drift was accepted',
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  test('Plan 018 generated harness keeps native controls separately scoped',
      () async {
    final generated = await Process.run(
      'python3',
      <String>[_generatorPath],
      environment: const <String, String>{
        'PYTHONDONTWRITEBYTECODE': '1',
      },
    );
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    expect(
      generated.stdout,
      contains(
        '27 candidate capture stages + '
        '6 renderer-native control stages OK',
      ),
    );

    final candidateStateOutput = File(
      '$_outputPath/assets/plan018_controlled_comparison_state.json',
    );
    final nativeStateOutput = File(
      '$_outputPath/assets/'
      'plan018_renderer_native_scalar_sheen_control_state.json',
    );
    expect(candidateStateOutput.readAsBytesSync(),
        File(_statePath).readAsBytesSync());
    expect(
      nativeStateOutput.readAsBytesSync(),
      File(_nativeControlStatePath).readAsBytesSync(),
    );

    final nativeInventory = (jsonDecode(
      File(
        '$_outputPath/assets/'
        'plan018_renderer_native_control_capture_inventory.json',
      ).readAsStringSync(),
    ) as List<Object?>)
        .cast<String>();
    expect(
      nativeInventory,
      <String>[
        'renderer_native_scalar_sheen_on_grazing_directOnly',
        'renderer_native_scalar_sheen_on_grazing_iblOnly',
        'renderer_native_scalar_sheen_on_grazing_combined',
        'renderer_native_scalar_sheen_off_grazing_directOnly',
        'renderer_native_scalar_sheen_off_grazing_iblOnly',
        'renderer_native_scalar_sheen_off_grazing_combined',
      ],
    );
    for (final modelId in <String>[
      'renderer_native_scalar_sheen_on',
      'renderer_native_scalar_sheen_off',
    ]) {
      expect(
        File('$_outputPath/assets/models/$modelId.glb').existsSync(),
        isTrue,
      );
    }

    final contract = File(
      '$_outputPath/lib/plan018_generated_contract.dart',
    ).readAsStringSync();
    expect(contract, contains(_nativeControlStateSha256));
    expect(contract, contains('plan018ModelStateAssetPaths'));
    expect(contract, contains('plan018ExpectedScreenshotNamesByModel'));
    expect(contract, contains('renderer_native_scalar_sheen_on'));
    expect(contract, contains('renderer_native_scalar_sheen_off'));

    final mainSource = File('$_outputPath/lib/main.dart').readAsStringSync();
    expect(
      mainSource,
      contains('plan018ModelStateAssetPaths[_selectedModel]'),
    );
    expect(mainSource, contains("'expectedApplication': application"));
    expect(mainSource, contains("'application': application"));
    expect(mainSource, contains("'featureMaturity': featureMaturity"));
    expect(mainSource, isNot(contains("if (_selectedModel ==")));
    expect(mainSource, isNot(contains("case 'renderer_native")));
  });

  test('Plan 018 iOS harness generator preserves the frozen capture contract',
      () async {
    final generated = await Process.run(
      'python3',
      <String>[_generatorPath],
    );
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    expect(
      generated.stdout,
      contains(
        'Plan 018 iOS harness: 27 candidate capture stages + '
        '6 renderer-native control stages OK',
      ),
    );

    final output = Directory(_outputPath);
    expect(output.existsSync(), isTrue);
    final requiredFiles = <String>[
      'pubspec.yaml',
      'lib/main.dart',
      'lib/plan018_generated_contract.dart',
      'integration_test/plan018_capture_test.dart',
      'test_driver/integration_test.dart',
      'assets/plan018_controlled_comparison_state.json',
      'assets/plan018_renderer_native_scalar_sheen_control_state.json',
      'assets/plan018_renderer_native_control_capture_inventory.json',
      'assets/plan018_controlled_studio.hdr',
      'assets/models/sheen_chair.glb',
      'assets/models/sheen_cloth.glb',
      'assets/models/glam_velvet_sofa.glb',
      'assets/models/toycar.glb',
      'assets/models/renderer_native_scalar_sheen_on.glb',
      'assets/models/renderer_native_scalar_sheen_off.glb',
      'ios/Runner/Info.plist',
      'ios/Runner.xcodeproj/project.pbxproj',
    ];
    for (final relativePath in requiredFiles) {
      expect(
        File('$_outputPath/$relativePath').existsSync(),
        isTrue,
        reason: 'missing generated $relativePath',
      );
    }
    expect(
      File('$_outputPath/assets/plan018_controlled_comparison_state.json')
          .readAsBytesSync(),
      File(_statePath).readAsBytesSync(),
    );

    final state = Map<String, Object?>.from(
      jsonDecode(File(_statePath).readAsStringSync()) as Map,
    );
    final models = Map<String, Object?>.from(state['models']! as Map);
    final passes = (state['renderPasses']! as List<Object?>).cast<String>();
    final expectedNames = <String>[];
    for (final entry in models.entries) {
      final model = Map<String, Object?>.from(entry.value! as Map);
      final cameras = Map<String, Object?>.from(model['cameras']! as Map);
      for (final view in cameras.keys) {
        for (final pass in passes) {
          expectedNames.add('${entry.key}_${view}_$pass');
        }
      }
      final context = model['context'];
      if (context is Map && context['camera'] is Map) {
        for (final pass in passes) {
          expectedNames.add('${entry.key}_context_$pass');
        }
      }
    }
    expect(expectedNames, hasLength(27));
    expect(expectedNames.toSet(), hasLength(27));

    final inventory = (jsonDecode(
      File('$_outputPath/assets/plan018_capture_inventory.json')
          .readAsStringSync(),
    ) as List<Object?>)
        .cast<String>();
    expect(inventory, expectedNames);

    final pubspec = File('$_outputPath/pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('path: ../../../../..'));
    expect(pubspec, contains('crypto: 3.0.7'));
    expect(pubspec,
        isNot(contains(RegExp(r'^\s*flutter_scene:', multiLine: true))));
    expect(pubspec, isNot(contains('dependency_overrides:')));

    final mainSource = File('$_outputPath/lib/main.dart').readAsStringSync();
    expect(mainSource, contains('FlutterSceneViewer.test('));
    expect(mainSource, contains('FlutterSceneRuntimeAdapter('));
    expect(mainSource, contains('RenderPolicy.always'));
    expect(mainSource, contains('MaterialShadingPolicy.authored'));
    expect(mainSource,
        contains('ViewerMaterialExtensionPolicy.productionShaders('));
    expect(mainSource, contains('enableTransmission: true'));
    expect(mainSource, contains('enableClearcoat: true'));
    expect(mainSource, contains('enableSheen: true'));
    expect(mainSource, contains('readGlbMaterialExtensionIntent('));
    expect(mainSource, contains('FlutterSceneExtendedPbrMaterial'));
    expect(mainSource, contains('material.retainedSheenColorFactor'));
    expect(mainSource, contains('sampledTexture'));
    expect(mainSource, contains('adapter.rootNode'));
    expect(mainSource, contains('adapter.debugScene'));
    expect(mainSource, contains('PLAN018_READY'));
    expect(mainSource, contains('PLAN018_DIAGNOSTIC'));
    expect(mainSource, contains('PLAN018_COMPLETE'));
    expect(mainSource, contains("'candidate-only'"));
    expect(mainSource, isNot(contains('fitCamera(')));
    expect(mainSource, isNot(contains('ModelSource.network')));
    expect(mainSource, isNot(contains('ViewerPolyHavenEnvironment')));
    expect(mainSource, isNot(contains("package:flutter_scene/")));
    expect(mainSource, isNot(contains("'ToyCar'")));
    expect(mainSource, isNot(contains("'Fabric'")));
    expect(mainSource, isNot(contains("'Glass'")));

    final integrationSource =
        File('$_outputPath/integration_test/plan018_capture_test.dart')
            .readAsStringSync();
    expect(integrationSource, contains('takeScreenshot(name)'));
    expect(integrationSource, isNot(contains('pumpAndSettle')));
    expect(integrationSource, isNot(contains('fitCamera(')));
    expect(integrationSource, isNot(contains("package:flutter_scene/")));

    final driverSource = File('$_outputPath/test_driver/integration_test.dart')
        .readAsStringSync();
    expect(driverSource, contains('integrationDriver('));
    expect(driverSource, contains('1206'));
    expect(driverSource, contains('2622'));
    expect(driverSource, contains('pngSignature'));
    expect(driverSource, contains('expectedScreenshotNames'));

    final info = File('$_outputPath/ios/Runner/Info.plist').readAsStringSync();
    expect(info, contains('<key>FLTEnableFlutterGPU</key>'));
    expect(info, contains('<key>CADisableMinimumFrameDurationOnPhone</key>'));
    expect(info, contains('<string>UIInterfaceOrientationPortrait</string>'));
    expect(info, isNot(contains('UIInterfaceOrientationLandscape')));
    final project = File('$_outputPath/ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    expect(project, contains('dev.flutter_scene_viewer.plan018'));

    for (final entry in models.entries) {
      final model = Map<String, Object?>.from(entry.value! as Map);
      final bytes =
          File('$_outputPath/assets/models/${entry.key}.glb').readAsBytesSync();
      expect(bytes.length, model['byteLength']);
      expect(sha256.convert(bytes).toString(), model['sha256']);
    }
    final hdrBytes = File('$_outputPath/assets/plan018_controlled_studio.hdr')
        .readAsBytesSync();
    expect(sha256.convert(hdrBytes).toString(),
        Map<String, Object?>.from(state['environment']! as Map)['sha256']);

    final validation = await Process.run(
      'python3',
      <String>[_generatorPath, '--validate-output', _outputPath],
    );
    expect(validation.exitCode, 0,
        reason: '${validation.stdout}\n${validation.stderr}');

    final mutations = <String, void Function(Directory)>{
      'direct flutter_scene dependency': (root) {
        final file = File('${root.path}/pubspec.yaml');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
                '  crypto: 3.0.7',
                '  crypto: 3.0.7\n  flutter_scene: any',
              ),
        );
      },
      'direct flutter_scene import': (root) {
        final file = File('${root.path}/lib/main.dart');
        file.writeAsStringSync(
          "import 'package:flutter_scene/scene.dart';\n${file.readAsStringSync()}",
        );
      },
      'dependency override': (root) {
        File('${root.path}/pubspec_overrides.yaml')
            .writeAsStringSync('dependency_overrides: {}\n');
      },
      'network source': (root) {
        final file = File('${root.path}/lib/main.dart');
        file.writeAsStringSync(
          '${file.readAsStringSync()}\n// ModelSource.network\n',
        );
      },
      'missing sheen policy flag': (root) {
        final file = File('${root.path}/lib/main.dart');
        file.writeAsStringSync(
          file.readAsStringSync().replaceFirst(
                'enableSheen: true',
                'enableSheen: false',
              ),
        );
      },
      'incomplete screenshot inventory': (root) {
        final file = File('${root.path}/assets/plan018_capture_inventory.json');
        final values = (jsonDecode(file.readAsStringSync()) as List<Object?>)
          ..removeLast();
        file.writeAsStringSync('${jsonEncode(values)}\n');
      },
      'mutable camera fitting': (root) {
        final file =
            File('${root.path}/integration_test/plan018_capture_test.dart');
        file.writeAsStringSync('${file.readAsStringSync()}\n// fitCamera(\n');
      },
    };
    for (final mutation in mutations.entries) {
      final temporary = await Directory.systemTemp.createTemp(
        'plan018_ios_harness_validation_',
      );
      try {
        _copyDirectory(output, temporary);
        _copyPackageConfig(output, temporary);
        mutation.value(temporary);
        final rejected = await Process.run(
          'python3',
          <String>[
            _generatorPath,
            '--validate-output',
            temporary.path,
          ],
        );
        expect(
          rejected.exitCode,
          isNot(0),
          reason: '${mutation.key} was accepted',
        );
      } finally {
        await temporary.delete(recursive: true);
      }
    }
  });
}

void _copyDirectory(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relativePath = entity.path.substring(source.path.length + 1);
    final pathSegments = relativePath.split(Platform.pathSeparator);
    if (pathSegments.any(
      (segment) =>
          segment == '.dart_tool' ||
          segment == 'build' ||
          segment == 'Pods' ||
          segment == '.git',
    )) {
      continue;
    }
    final targetPath = '${destination.path}/$relativePath';
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      File(targetPath)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}

void _copyPackageConfig(Directory source, Directory destination) {
  final sourceFile = File('${source.path}/.dart_tool/package_config.json');
  expect(sourceFile.existsSync(), isTrue);
  File('${destination.path}/.dart_tool/package_config.json')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(sourceFile.readAsBytesSync());
}
