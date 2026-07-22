import 'dart:io';

import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;
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

  test('packaged sheen shader and combined DFG pass reflected preflight',
      () async {
    final backend = FlutterSceneExtendedPbrBackend();

    final diagnostic = await backend.preflightSheen(
      PartAddress(
        nodePath: const <String>['Root', 'Fabric'],
        primitiveIndex: 0,
      ),
      request: const FlutterSceneExtendedPbrResourceRequest(
        hasSheen: true,
        hasSpecular: true,
        hasSpecularFactorTexture: true,
        hasSpecularColorTexture: true,
        hasSheenColorTexture: true,
        hasSheenRoughnessTexture: true,
      ),
    );

    expect(diagnostic, isNull, reason: '${diagnostic?.details}');
    expect(backend.isSheenReady, isTrue);
  },
      skip: Platform.environment['FLUTTER_SCENE_GPU_TESTS'] == 'true'
          ? false
          : 'not run: requires an Impeller-enabled Flutter GPU test process');

  test('sheen sampler manifest passes 16 and rejects projected 17 and 19', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );
    const exactSixteen = FlutterSceneExtendedPbrResourceRequest(
      hasSheen: true,
      hasSpecular: true,
      hasSpecularFactorTexture: true,
      hasSpecularColorTexture: true,
      hasSheenColorTexture: true,
      hasSheenRoughnessTexture: true,
    );
    const projectedSeventeen = FlutterSceneExtendedPbrResourceRequest(
      hasSheen: true,
      hasClearcoat: true,
      hasSheenColorTexture: true,
      hasSheenRoughnessTexture: true,
      hasClearcoatTexture: true,
      hasClearcoatRoughnessTexture: true,
      hasClearcoatNormalTexture: true,
    );
    const projectedNineteen = FlutterSceneExtendedPbrResourceRequest(
      hasSheen: true,
      hasSpecular: true,
      hasClearcoat: true,
      hasSpecularFactorTexture: true,
      hasSpecularColorTexture: true,
      hasSheenColorTexture: true,
      hasSheenRoughnessTexture: true,
      hasClearcoatTexture: true,
      hasClearcoatRoughnessTexture: true,
      hasClearcoatNormalTexture: true,
    );

    final exact = debugFlutterSceneExtendedPbrSamplerManifest(exactSixteen);
    expect(exact.entryName, 'FSViewerSheenExtendedPbr');
    expect(exact.portableLimit, 16);
    expect(exact.declaredSamplerSlots, hasLength(16));
    expect(exact.projectedRequestSamplerCount, 16);
    expect(
      debugFlutterSceneExtendedPbrResourceDiagnostic(address, exactSixteen),
      isNull,
    );

    for (final entry in <(FlutterSceneExtendedPbrResourceRequest, int)>[
      (projectedSeventeen, 17),
      (projectedNineteen, 19),
    ]) {
      final manifest = debugFlutterSceneExtendedPbrSamplerManifest(entry.$1);
      expect(manifest.projectedRequestSamplerCount, entry.$2);
      final diagnostic = debugFlutterSceneExtendedPbrResourceDiagnostic(
        address,
        entry.$1,
      );
      expect(diagnostic, isNotNull);
      expect(
          diagnostic!.details['limitation'], 'fragmentSamplerBudgetExceeded');
      expect(diagnostic.details['portableLimit'], 16);
      expect(diagnostic.details['requestedSamplerCount'], entry.$2);
      expect(diagnostic.details['materialReplaced'], isFalse);
      expect(diagnostic.details['decodedTextureCount'], 0);
      expect(
          diagnostic.details['requestedSlots'], manifest.requestedTextureSlots);
    }
  });

  test('clearcoat sheen variant owns one bounded exact sixteen manifest', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'CoatedFabric'],
      primitiveIndex: 0,
    );
    const request = FlutterSceneExtendedPbrResourceRequest(
      hasSheen: true,
      hasSpecular: true,
      hasClearcoat: true,
      hasSheenColorTexture: true,
      hasSheenRoughnessTexture: true,
      hasClearcoatTexture: true,
      hasClearcoatRoughnessTexture: true,
    );

    final manifest = debugFlutterSceneExtendedPbrSamplerManifest(request);

    expect(manifest.entryName, 'FSViewerClearcoatSheenExtendedPbr');
    expect(manifest.portableLimit, 16);
    expect(manifest.declaredSamplerSlots, hasLength(16));
    expect(
      manifest.declaredSamplerSlots,
      containsAll(<String>[
        'sheen_color_texture',
        'sheen_roughness_texture',
        'clearcoat_texture',
        'clearcoat_roughness_texture',
      ]),
    );
    expect(manifest.declaredSamplerSlots,
        isNot(contains('specular_factor_texture')));
    expect(manifest.declaredSamplerSlots,
        isNot(contains('specular_color_texture')));
    expect(manifest.declaredSamplerSlots,
        isNot(contains('clearcoat_normal_texture')));
    expect(manifest.projectedRequestSamplerCount, 16);
    expect(
      debugFlutterSceneExtendedPbrResourceDiagnostic(address, request),
      isNull,
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: true,
        hasClearcoatState: true,
      ),
      'FSViewerClearcoatSheenExtendedPbr',
    );
  });

  test('real backend accepts uniform specular IOR for combined selection',
      () async {
    final source = flutter_scene.PhysicallyBasedMaterial()
      ..clearcoatFactor = 0.8
      ..clearcoatRoughnessFactor = 0.2;
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, __) async => null,
    );

    await expectLater(
      backend.createMaterial(
        FlutterSceneExtendedPbrMaterialConfig(
          source: source,
          specularFactor: 0.6,
          specularColorFactor: const <double>[0.8, 0.7, 0.6],
          ior: 1.45,
          hasSheenIntent: true,
          sheenColorFactor: const <double>[0.4, 0.3, 0.2],
          sheenRoughness: 0.55,
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must pass preflight before use'),
        ),
      ),
    );
  });

  test('real backend rejects combined resources when preflight is bypassed',
      () async {
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, __) async => null,
    );
    final cases = <(FlutterSceneExtendedPbrMaterialConfig, String)>[
      (
        FlutterSceneExtendedPbrMaterialConfig(
          source: flutter_scene.PhysicallyBasedMaterial()
            ..clearcoatFactor = 0.8,
          hasSheenIntent: true,
          specularFactorTexture: const _NullTextureSource(),
        ),
        'specular textures',
      ),
      (
        FlutterSceneExtendedPbrMaterialConfig(
          source: flutter_scene.PhysicallyBasedMaterial()
            ..clearcoatNormalTexture = const _NullTextureSource(),
          hasSheenIntent: true,
        ),
        'clearcoat normal texture',
      ),
      (
        FlutterSceneExtendedPbrMaterialConfig(
          source: flutter_scene.PhysicallyBasedMaterial()
            ..clearcoatFactor = 0.8
            ..transmissionFactor = 0.5,
          hasSheenIntent: true,
        ),
        'transmission or volume state',
      ),
    ];

    for (final entry in cases) {
      await expectLater(
        backend.createMaterial(entry.$1),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            contains(entry.$2),
          ),
        ),
        reason: entry.$2,
      );
    }
  });

  test('clearcoat sheen rejects incompatible texture slots atomically', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'CoatedFabric'],
      primitiveIndex: 0,
    );
    const cases = <(FlutterSceneExtendedPbrResourceRequest, String)>[
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasSpecular: true,
          hasClearcoat: true,
          hasSpecularFactorTexture: true,
        ),
        'specular_factor_texture',
      ),
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasSpecular: true,
          hasClearcoat: true,
          hasSpecularColorTexture: true,
        ),
        'specular_color_texture',
      ),
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasClearcoat: true,
          hasClearcoatNormalTexture: true,
        ),
        'clearcoat_normal_texture',
      ),
    ];

    for (final entry in cases) {
      final manifest = debugFlutterSceneExtendedPbrSamplerManifest(entry.$1);
      expect(manifest.projectedRequestSamplerCount, 13);
      final diagnostic = debugFlutterSceneExtendedPbrResourceDiagnostic(
        address,
        entry.$1,
      );

      expect(diagnostic, isNotNull, reason: entry.$2);
      expect(
        diagnostic!.details['limitation'],
        'sheenCompositionResourceIncompatible',
      );
      expect(
        diagnostic.details['selectedVariant'],
        'FSViewerClearcoatSheenExtendedPbr',
      );
      expect(diagnostic.details['portableLimit'], 16);
      expect(diagnostic.details['requestedSamplerCount'], 13);
      expect(diagnostic.details['incompatibleSlots'], <String>[entry.$2]);
      expect(diagnostic.details['materialReplaced'], isFalse);
      expect(diagnostic.details['decodedTextureCount'], 0);
      expect(diagnostic.details['maturity'], 'candidate-only');
      expect(diagnostic.details['renderingEvidence'], 'not run');
    }
  });

  test('clearcoat sheen rejects transmission and volume state atomically', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'CoatedFabric'],
      primitiveIndex: 0,
    );
    const cases = <(FlutterSceneExtendedPbrResourceRequest, List<String>)>[
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasClearcoat: true,
          hasTransmissionState: true,
        ),
        <String>['transmission'],
      ),
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasClearcoat: true,
          hasVolumeState: true,
        ),
        <String>['volume'],
      ),
      (
        FlutterSceneExtendedPbrResourceRequest(
          hasSheen: true,
          hasClearcoat: true,
          hasTransmissionState: true,
          hasVolumeState: true,
        ),
        <String>['transmission', 'volume'],
      ),
    ];

    for (final entry in cases) {
      final diagnostic = debugFlutterSceneExtendedPbrResourceDiagnostic(
        address,
        entry.$1,
      );

      expect(diagnostic, isNotNull, reason: '${entry.$2}');
      expect(
        diagnostic!.details['limitation'],
        'sheenCompositionStateIncompatible',
      );
      expect(
        diagnostic.details['selectedVariant'],
        'FSViewerClearcoatSheenExtendedPbr',
      );
      expect(diagnostic.details['portableLimit'], 16);
      expect(diagnostic.details['requestedSamplerCount'], 12);
      expect(diagnostic.details['incompatibleSlots'], isEmpty);
      expect(diagnostic.details['incompatibleState'], entry.$2);
      expect(diagnostic.details['materialReplaced'], isFalse);
      expect(diagnostic.details['decodedTextureCount'], 0);
      expect(diagnostic.details['maturity'], 'candidate-only');
      expect(diagnostic.details['renderingEvidence'], 'not run');
    }
  });

  test('legacy and sheen shader readiness fail independently', () async {
    final shaderNames = <String>[];
    var lutLoadCount = 0;
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, shaderName) async {
        shaderNames.add(shaderName);
        return null;
      },
      loadSheenBrdfLut: () async {
        lutLoadCount += 1;
        return null;
      },
    );
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );

    final legacyDiagnostic = await backend.preflight(address);

    expect(legacyDiagnostic, isNotNull);
    expect(
      shaderNames,
      everyElement('FSViewerExtendedPbr'),
      reason: 'Legacy readiness must not request the sheen entry.',
    );
    expect(backend.isReady, isFalse);

    shaderNames.clear();
    final sheenDiagnostic = await backend.preflightSheen(
      address,
      request: const FlutterSceneExtendedPbrResourceRequest(
        hasSheen: true,
      ),
    );

    expect(sheenDiagnostic, isNotNull);
    expect(sheenDiagnostic!.details['limitation'], 'sheenShaderUnavailable');
    expect(shaderNames, everyElement('FSViewerSheenExtendedPbr'));
    expect(lutLoadCount, 0);
    expect(backend.isReady, isFalse);
    expect(backend.isSheenReady, isFalse);
  });

  test('combined sheen preflight selects only its own reflected entry',
      () async {
    final shaderNames = <String>[];
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, shaderName) async {
        shaderNames.add(shaderName);
        return null;
      },
    );
    final address = PartAddress(
      nodePath: const <String>['Root', 'CoatedFabric'],
      primitiveIndex: 0,
    );

    final combinedDiagnostic = await backend.preflightSheen(
      address,
      request: const FlutterSceneExtendedPbrResourceRequest(
        hasSheen: true,
        hasClearcoat: true,
      ),
    );

    expect(combinedDiagnostic, isNotNull);
    expect(combinedDiagnostic!.details['limitation'], 'sheenShaderUnavailable');
    expect(
      shaderNames,
      everyElement('FSViewerClearcoatSheenExtendedPbr'),
    );
    expect(backend.isSheenReady, isFalse);

    shaderNames.clear();
    final sheenOnlyDiagnostic = await backend.preflightSheen(
      address,
      request: const FlutterSceneExtendedPbrResourceRequest(hasSheen: true),
    );

    expect(sheenOnlyDiagnostic, isNotNull);
    expect(
        sheenOnlyDiagnostic!.details['limitation'], 'sheenShaderUnavailable');
    expect(shaderNames, everyElement('FSViewerSheenExtendedPbr'));
    expect(backend.isReady, isFalse);
    expect(backend.isSheenReady, isFalse);
  });

  test('shared sheen LUT preflight reuses one allocation across variants',
      () async {
    var lutLoadCount = 0;
    final backend = FlutterSceneExtendedPbrBackend(
      loadShader: (_, __) async => null,
      loadSheenBrdfLut: () async {
        lutLoadCount += 1;
        return const _FakeSheenBrdfLut();
      },
    );
    final address = PartAddress(
      nodePath: const <String>['Root', 'CoatedFabric'],
      primitiveIndex: 0,
    );

    final sheenOnlyDiagnostic =
        await backend.debugPreflightSheenBrdfLutForTesting(
      address,
      selectedVariant: 'FSViewerSheenExtendedPbr',
    );
    final combinedDiagnostic =
        await backend.debugPreflightSheenBrdfLutForTesting(
      address,
      selectedVariant: 'FSViewerClearcoatSheenExtendedPbr',
    );

    expect(sheenOnlyDiagnostic, isNull);
    expect(combinedDiagnostic, isNull);
    expect(lutLoadCount, 1);
  });

  test('sheen LUT failures stay typed separately from reflection failures', () {
    final address = PartAddress(
      nodePath: const <String>['Root', 'Fabric'],
      primitiveIndex: 0,
    );

    final unavailable = debugFlutterSceneSheenPreflightDiagnostic(
      address,
      foundReflectedShader: true,
    );
    expect(
      unavailable.details['limitation'],
      'sheenDirectionalAlbedoResourceUnavailable',
    );
    expect(unavailable.details['resourceStage'], 'combinedDfgLut');
    expect(unavailable.details, isNot(contains('error')));

    final resourceError = debugFlutterSceneSheenPreflightDiagnostic(
      address,
      foundReflectedShader: true,
      resourceError: StateError('RGBA16F upload failed'),
    );
    expect(
      resourceError.details['limitation'],
      'sheenDirectionalAlbedoResourceUnavailable',
    );
    expect(resourceError.details['resourceStage'], 'combinedDfgLut');
    expect(resourceError.details['error'], contains('RGBA16F upload failed'));

    final reflectionError = debugFlutterSceneSheenPreflightDiagnostic(
      address,
      shaderError: StateError('missing SheenParams'),
    );
    expect(
      reflectionError.details['limitation'],
      'sheenShaderContractMismatch',
    );
    expect(reflectionError.details, isNot(contains('resourceStage')));
  });

  test('sheen shader selection keeps all no-sheen routes independent', () {
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: false,
        hasClearcoatState: false,
      ),
      'FSViewerExtendedPbr',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: true,
        hasClearcoatState: false,
      ),
      'FSViewerSheenExtendedPbr',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: false,
        hasClearcoatState: true,
      ),
      'FSViewerClearcoatExtendedPbr',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: true,
        hasClearcoatState: true,
      ),
      'FSViewerClearcoatSheenExtendedPbr',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: false,
        hasClearcoatState: false,
        usesTexCoord1: true,
      ),
      'FSViewerExtendedPbrUV1',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: true,
        hasClearcoatState: false,
        usesTexCoord1: true,
      ),
      'FSViewerSheenExtendedPbrUV1',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: false,
        hasClearcoatState: true,
        usesTexCoord1: true,
      ),
      'FSViewerClearcoatExtendedPbrUV1',
    );
    expect(
      debugFlutterSceneExtendedPbrShaderSelection(
        hasSheenIntent: true,
        hasClearcoatState: true,
        usesTexCoord1: true,
      ),
      'FSViewerClearcoatSheenExtendedPbrUV1',
    );
  });
}

final class _NullTextureSource implements flutter_scene.TextureSource {
  const _NullTextureSource();

  @override
  flutter_scene_gpu.Texture? get sampledTexture => null;

  @override
  flutter_scene_gpu.SamplerOptions get sampledSampler =>
      flutter_scene_gpu.SamplerOptions();
}

final class _FakeSheenBrdfLut implements FlutterSceneSheenBrdfLut {
  const _FakeSheenBrdfLut();

  @override
  void bind(
    flutter_scene_gpu.RenderPass pass,
    flutter_scene_gpu.Shader shader,
  ) {}
}
