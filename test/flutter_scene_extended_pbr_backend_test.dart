import 'dart:io';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extended PBR preflight reports unavailable shader before mutation',
      () async {
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, __) async => null,
    );

    final diagnostic = await backend.preflight(
      PartAddress(
        nodePath: const <String>['Root', 'Body'],
        primitiveIndex: 0,
      ),
    );

    expect(diagnostic, isNotNull);
    expect(
      diagnostic!.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    expect(diagnostic.details['feature'], 'FSViewerExtendedPbr');
    expect(diagnostic.details['limitation'], 'extendedPbrShaderUnavailable');
    expect(diagnostic.details['status'], 'blocked');
    expect(diagnostic.details['materialReplaced'], isFalse);
    expect(diagnostic.details['nextStep'], 'packageExtendedPbrShaderBundle');
  });

  test('packaged extended PBR shader passes the reflected contract', () async {
    final backend = FlutterSceneExtendedPbrBackend();

    final diagnostic = await backend.preflight(
      PartAddress(nodePath: const <String>['Root'], primitiveIndex: 0),
    );

    expect(diagnostic, isNull, reason: '${diagnostic?.details}');
    expect(backend.isReady, isTrue);
  },
      skip: Platform.environment['FLUTTER_SCENE_GPU_TESTS'] == 'true'
          ? false
          : 'not run: requires an Impeller-enabled Flutter GPU test process');
}
