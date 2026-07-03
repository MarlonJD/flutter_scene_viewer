import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3]));
  final address = PartAddress(
    nodePath: <String>['Root'],
    primitiveIndex: 0,
  );

  testWidgets('viewer shows loading and ready states', (tester) async {
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          loadingBuilder: (_) => const Text('Loading test model'),
        ),
      ),
    );

    expect(find.text('Loading test model'), findsOneWidget);

    await tester.pump();
    await tester.pump();

    expect(
      _readyViewerFinder(),
      findsOneWidget,
    );
  });

  testWidgets('equivalent source rebuild does not reload the model',
      (tester) async {
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
    );
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: ModelSource.bytes(bytes, debugName: 'same.glb'),
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: ModelSource.bytes(bytes, debugName: 'same.glb'),
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();

    expect(adapter.loadCalls, 1);
  });

  testWidgets('material shading policy is passed during load and reloads',
      (tester) async {
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          materialShadingPolicy: MaterialShadingPolicy.forceLit,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          materialShadingPolicy: MaterialShadingPolicy.forceUnlit,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(adapter.materialShadingPolicies, <MaterialShadingPolicy>[
      MaterialShadingPolicy.forceLit,
      MaterialShadingPolicy.forceUnlit,
    ]);
  });

  testWidgets('viewer shows load diagnostics in the error state',
      (tester) async {
    final adapter = FakeViewerAdapter(
      loadFailure: const ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterFailure,
        message: 'Adapter failed.',
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Adapter failed.'), findsOneWidget);
  });

  testWidgets('material changes request a visible viewer update',
      (tester) async {
    final controller = FlutterSceneViewerController();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialReadyKey = _readyViewerKey(tester);

    await controller.setPartMaterial(
      address,
      const MaterialPatch(roughness: 0.4),
    );
    await tester.pump();

    expect(_readyViewerKey(tester), isNot(initialReadyKey));
  });

  testWidgets('viewer builds adapter render surface when model is ready',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(RecordingRenderScene.surfaceKey), findsOneWidget);
    expect(renderScene.cameras.single.target, <double>[0, 0, 0]);
    expect(renderScene.autoTicks.single, isFalse);
  });

  testWidgets('viewer passes lighting settings to the adapter render surface',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          lighting: const ViewerLighting.studio(
            exposure: 1.4,
            ambientOcclusion: true,
            environmentIntensity: 0.35,
            keyLightIntensity: 7,
            keyLightColor: <double>[1, 0.92, 0.84],
            keyLightDirection: <double>[-0.2, -0.9, -0.4],
            keyLightCastsShadow: true,
            keyLightShadowMapResolution: 4096,
            keyLightShadowMaxDistance: 8,
            keyLightShadowSoftness: 0.03,
            keyLightShadowFadeRange: 0.75,
            keyLightShadowDepthBias: 0.01,
            keyLightShadowNormalBias: 0.015,
            keyLightShadowCascadeCount: 2,
            keyLightShadowCascadeSplitLambda: 0.75,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.lightingFrames.single.kind, RenderLightingKind.studio);
    expect(renderScene.lightingFrames.single.exposure, 1.4);
    expect(renderScene.lightingFrames.single.ambientOcclusionEnabled, isTrue);
    expect(renderScene.lightingFrames.single.environmentIntensity, 0.35);
    expect(renderScene.lightingFrames.single.keyLightIntensity, 7);
    expect(renderScene.lightingFrames.single.keyLightColor, <double>[
      1,
      0.92,
      0.84,
    ]);
    expect(
      renderScene.lightingFrames.single.keyLightDirection,
      <double>[-0.2, -0.9, -0.4],
    );
    expect(renderScene.lightingFrames.single.keyLightCastsShadow, isTrue);
    expect(
      renderScene.lightingFrames.single.keyLightShadowMapResolution,
      4096,
    );
    expect(renderScene.lightingFrames.single.keyLightShadowMaxDistance, 8);
    expect(renderScene.lightingFrames.single.keyLightShadowSoftness, 0.03);
    expect(renderScene.lightingFrames.single.keyLightShadowFadeRange, 0.75);
    expect(renderScene.lightingFrames.single.keyLightShadowDepthBias, 0.01);
    expect(renderScene.lightingFrames.single.keyLightShadowNormalBias, 0.015);
    expect(renderScene.lightingFrames.single.keyLightShadowCascadeCount, 2);
    expect(
      renderScene.lightingFrames.single.keyLightShadowCascadeSplitLambda,
      0.75,
    );
  });

  testWidgets('viewer passes default studio environment to render surface',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.environmentFrames.single.kind,
        RenderEnvironmentKind.studio);
    expect(renderScene.environmentFrames.single.assetPath, isNull);
    expect(renderScene.environmentFrames.single.intensity, 1.0);
    expect(renderScene.environmentFrames.single.rotationRadians, 0.0);
    expect(renderScene.environmentFrames.single.showSkybox, isFalse);
    expect(renderScene.environmentFrames.single.skyboxBlur, 0.0);
  });

  testWidgets('viewer configures default studio environment after load',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(adapter.configuredEnvironmentFrames.single.kind,
        RenderEnvironmentKind.studio);
    expect(adapter.configuredEnvironmentFrames.single.assetPath, isNull);
  });

  testWidgets(
      'viewer passes changed asset environment and requests a render frame',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final initialReadyKey = _readyViewerKey(tester);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          environment: const ViewerEnvironment.asset(
            'assets/env/studio.png',
            intensity: 0.7,
            rotationRadians: 0.25,
            showSkybox: true,
            skyboxBlur: 0.2,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_readyViewerKey(tester), isNot(initialReadyKey));
    expect(
        renderScene.environmentFrames.last.kind, RenderEnvironmentKind.asset);
    expect(
        renderScene.environmentFrames.last.assetPath, 'assets/env/studio.png');
    expect(renderScene.environmentFrames.last.intensity, 0.7);
    expect(renderScene.environmentFrames.last.rotationRadians, 0.25);
    expect(renderScene.environmentFrames.last.showSkybox, isTrue);
    expect(renderScene.environmentFrames.last.skyboxBlur, 0.2);
    expect(adapter.configuredEnvironmentFrames.last.kind,
        RenderEnvironmentKind.asset);
    expect(adapter.configuredEnvironmentFrames.last.assetPath,
        'assets/env/studio.png');
  });

  testWidgets('viewer passes raw HDR asset environment to adapter boundary',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          environment: const ViewerEnvironment.rawAsset(
            'assets/env/studio.hdr',
            format: ViewerEnvironmentFileFormat.hdr,
            intensity: 0.8,
            showSkybox: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.environmentFrames.single.kind,
        RenderEnvironmentKind.rawAsset);
    expect(renderScene.environmentFrames.single.assetPath,
        'assets/env/studio.hdr');
    expect(renderScene.environmentFrames.single.rawFormat,
        RenderEnvironmentFileFormat.hdr);
    expect(renderScene.environmentFrames.single.intensity, 0.8);
    expect(renderScene.environmentFrames.single.showSkybox, isTrue);
    expect(adapter.configuredEnvironmentFrames.single.kind,
        RenderEnvironmentKind.rawAsset);
  });

  testWidgets(
      'viewer passes explicit Poly Haven environment to adapter boundary',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          environment: const ViewerEnvironment.polyHaven(
            assetId: 'venice_sunset',
            resolution: ViewerPolyHavenResolution.oneK,
            fileType: ViewerPolyHavenFileType.hdr,
            userAgent: 'flutter_scene_viewer_test/1.0',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.environmentFrames.single.kind,
        RenderEnvironmentKind.polyHaven);
    expect(
        renderScene.environmentFrames.single.polyHavenAssetId, 'venice_sunset');
    expect(renderScene.environmentFrames.single.polyHavenResolution, '1k');
    expect(renderScene.environmentFrames.single.polyHavenFileType, 'hdr');
    expect(renderScene.environmentFrames.single.polyHavenUserAgent,
        'flutter_scene_viewer_test/1.0');
  });

  testWidgets('viewer records environment configuration diagnostics',
      (tester) async {
    final controller = FlutterSceneViewerController();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: RecordingRenderScene(),
      environmentDiagnostics: const <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.assetLoadFailure,
          message: 'Failed to load environment asset.',
        ),
      ],
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.assetLoadFailure);
  });

  testWidgets('tap invokes onPartTapped with picked part address',
      (tester) async {
    final picked = <PartAddress>[];
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: RecordingRenderScene(),
      pickedPart: address,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          onPartTapped: picked.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(_readyViewerFinder());
    await tester.pump();

    expect(picked, <PartAddress>[address]);
    expect(
        adapter.pickPositions.single, tester.getCenter(_readyViewerFinder()));
    expect(adapter.pickViewportSizes.single.width, greaterThan(0));
    expect(adapter.pickViewportSizes.single.height, greaterThan(0));
  });

  testWidgets('tap miss does not invoke onPartTapped', (tester) async {
    final picked = <PartAddress>[];
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: RecordingRenderScene(),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          onPartTapped: picked.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(_readyViewerFinder());
    await tester.pump();

    expect(picked, isEmpty);
    expect(adapter.pickPositions, hasLength(1));
  });

  testWidgets('drag orbit does not invoke part tap picking', (tester) async {
    final picked = <PartAddress>[];
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: RecordingRenderScene(),
      pickedPart: address,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          onPartTapped: picked.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.drag(_readyViewerFinder(), const Offset(80, 0));
    await tester.pump();

    expect(picked, isEmpty);
    expect(adapter.pickPositions, isEmpty);
  });

  testWidgets('debug stats overlay shows fps and tick state', (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          debugShowStatsOverlay: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.byKey(const ValueKey<String>('flutter_scene_viewer.debug_stats')),
      findsOneWidget,
    );
    expect(find.textContaining('debug evidence'), findsOneWidget);
    expect(find.textContaining('FPS'), findsOneWidget);
    expect(find.textContaining('frame ms:'), findsOneWidget);
    expect(find.textContaining('tick:'), findsOneWidget);
    expect(find.textContaining('autoTick: off'), findsOneWidget);
    expect(find.textContaining('diagnostics: 0'), findsOneWidget);
    expect(find.textContaining('model bytes: 3'), findsOneWidget);
    expect(find.textContaining('nodes: 1'), findsOneWidget);
    expect(find.textContaining('primitives: 1'), findsOneWidget);
    expect(find.textContaining('dist:'), findsOneWidget);
    expect(find.textContaining('pos:'), findsOneWidget);
  });

  testWidgets('onStats reports scheduler, camera, diagnostics, and model data',
      (tester) async {
    final snapshots = <ViewerStatsSnapshot>[];
    final controller = FlutterSceneViewerController();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(
        name: 'Root',
        children: <AdapterNodeSnapshot>[
          AdapterNodeSnapshot(name: 'Part', primitiveCount: 2),
        ],
      ),
      renderScene: RecordingRenderScene(),
      environmentDiagnostics: const <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentUnsupportedEncoding,
          message: 'Unsupported test encoding.',
        ),
      ],
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
          renderPolicy: RenderPolicy.always,
          autoOrbit: true,
          autoOrbitSpeedRadiansPerSecond: 1,
          onStats: snapshots.add,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 1));

    expect(snapshots, isNotEmpty);
    final snapshot = snapshots.last;
    expect(snapshot.framesPerSecond, greaterThanOrEqualTo(0));
    expect(snapshot.frameIntervalAverageMs, greaterThanOrEqualTo(0));
    expect(snapshot.frameIntervalMinMs, greaterThanOrEqualTo(0));
    expect(snapshot.frameIntervalMaxMs, greaterThanOrEqualTo(0));
    expect(snapshot.renderPolicyActive, isTrue);
    expect(snapshot.autoTick, isTrue);
    expect(snapshot.autoOrbit, isTrue);
    expect(snapshot.cameraDistance, greaterThan(0));
    expect(snapshot.cameraPosition, hasLength(3));
    expect(snapshot.diagnosticsCount, 1);
    expect(
      snapshot.lastDiagnosticCode,
      ViewerDiagnosticCode.environmentUnsupportedEncoding.name,
    );
    expect(snapshot.modelByteSize, 3);
    expect(snapshot.modelLoadDuration, isNotNull);
    expect(snapshot.nodeCount, 2);
    expect(snapshot.meshCount, 1);
    expect(snapshot.primitiveCount, 2);
    expect(snapshot.materialCount, isNull);
  });

  testWidgets('fitCamera updates the adapter render camera', (tester) async {
    final controller = FlutterSceneViewerController();
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
      modelBounds: const AdapterModelBounds(
        center: <double>[10, 20, 30],
        radius: 3,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialPosition = renderScene.cameras.last.position;

    await controller.fitCamera();
    await tester.pump();

    expect(initialPosition[0], closeTo(2.449489742783178, 1e-9));
    expect(initialPosition[1], closeTo(2, 1e-9));
    expect(initialPosition[2], closeTo(2.4494897427831783, 1e-9));
    expect(
      renderScene.cameras.last.target,
      <double>[10, 20, 30],
    );
    expect(
      renderScene.cameras.last.position[0],
      closeTo(14.225369806300982, 1e-9),
    );
    expect(renderScene.cameras.last.position[1], closeTo(23.45, 1e-9));
    expect(
      renderScene.cameras.last.position[2],
      closeTo(34.225369806300984, 1e-9),
    );
  });

  testWidgets('setCameraOrbit updates the adapter render camera',
      (tester) async {
    final controller = FlutterSceneViewerController();
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await controller.setCameraOrbit(
      target: const <double>[1, 2, 3],
      distance: 2,
      yawRadians: math.pi / 2,
      pitchRadians: 0,
    );
    await tester.pump();

    expect(renderScene.cameras.last.target, <double>[1, 2, 3]);
    expect(renderScene.cameras.last.position[0], closeTo(3, 1e-9));
    expect(renderScene.cameras.last.position[1], closeTo(2, 1e-9));
    expect(renderScene.cameras.last.position[2], closeTo(3, 1e-9));
  });

  testWidgets('setCameraOrbit stays outside model bounds by default',
      (tester) async {
    final controller = FlutterSceneViewerController();
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
      modelBounds: const AdapterModelBounds(
        center: <double>[0, 0, 0],
        radius: 4,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await controller.fitCamera();
    await controller.setCameraOrbit(distance: 0.4);
    await tester.pump();

    expect(_cameraDistance(renderScene.cameras.last), closeTo(4 * 1.05, 1e-9));
  });

  testWidgets('allowCameraInsideModel permits close inspection distances',
      (tester) async {
    final controller = FlutterSceneViewerController();
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
      modelBounds: const AdapterModelBounds(
        center: <double>[0, 0, 0],
        radius: 4,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
          allowCameraInsideModel: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await controller.fitCamera();
    await controller.setCameraOrbit(distance: 0.4);
    await tester.pump();

    expect(_cameraDistance(renderScene.cameras.last), closeTo(1, 1e-9));
  });

  testWidgets('autoOrbit advances the rendered camera while enabled',
      (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          autoOrbit: true,
          autoOrbitSpeedRadiansPerSecond: 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialPosition = renderScene.cameras.last.position;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(renderScene.cameras.last.position[0], isNot(initialPosition[0]));
    expect(renderScene.cameras.last.position[2], isNot(initialPosition[2]));
  });

  testWidgets('fitCamera requested during load waits for viewport aspect',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(200, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = FlutterSceneViewerController();
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
      modelBounds: const AdapterModelBounds(
        center: <double>[0, 0, 0],
        radius: 2,
      ),
    );
    var fitRequested = false;
    controller.addListener(() {
      if (!fitRequested &&
          controller.loadState.status == ViewerLoadStatus.success) {
        fitRequested = true;
        unawaited(controller.fitCamera());
      }
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final halfHorizontalFov = math.atan(math.tan(math.pi / 6) * (200 / 600));
    expect(
      _cameraDistance(renderScene.cameras.last),
      closeTo(2 * 1.15 / math.sin(halfHorizontalFov), 1e-9),
    );
  });

  testWidgets('single pointer drag orbits the rendered camera', (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialPosition = renderScene.cameras.last.position;

    await tester.drag(
      _readyViewerFinder(),
      const Offset(80, -20),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.cameras.last.position[0], isNot(initialPosition[0]));
    expect(renderScene.cameras.last.position[1], isNot(initialPosition[1]));
    expect(renderScene.cameras.last.position[2], isNot(initialPosition[2]));
  });

  testWidgets('upward pointer drag lowers the rendered camera', (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialY = renderScene.cameras.last.position[1];

    await tester.drag(
      _readyViewerFinder(),
      const Offset(0, -40),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.cameras.last.position[1], lessThan(initialY));
  });

  testWidgets('pointer scroll orbits the rendered camera', (tester) async {
    final renderScene = RecordingRenderScene();
    final adapter = FakeViewerAdapter(
      snapshot: AdapterNodeSnapshot(name: 'Root', primitiveCount: 1),
      renderScene: renderScene,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FlutterSceneViewer.test(
          source: source,
          adapter: adapter,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final initialPosition = renderScene.cameras.last.position;
    final center = tester.getCenter(
      find.byKey(RecordingRenderScene.surfaceKey),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: center,
        scrollDelta: const Offset(80, 0),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(renderScene.cameras.last.position[0], isNot(initialPosition[0]));
    expect(renderScene.cameras.last.position[2], isNot(initialPosition[2]));
  });
}

final class FakeViewerAdapter implements FlutterSceneAdapter {
  FakeViewerAdapter({
    this.snapshot,
    this.loadFailure,
    this.renderScene,
    this.modelBounds,
    this.modelStats,
    this.pickedPart,
    this.environmentDiagnostics = const <ViewerDiagnostic>[],
  });

  final AdapterNodeSnapshot? snapshot;
  final ViewerDiagnostic? loadFailure;
  @override
  final AdapterRenderScene? renderScene;
  @override
  final AdapterModelBounds? modelBounds;
  @override
  final AdapterModelStats? modelStats;
  final PartAddress? pickedPart;
  final List<ViewerDiagnostic> environmentDiagnostics;
  final List<PartAddress> materialCalls = <PartAddress>[];
  final List<Offset> pickPositions = <Offset>[];
  final List<Size> pickViewportSizes = <Size>[];
  final List<MaterialShadingPolicy> materialShadingPolicies =
      <MaterialShadingPolicy>[];
  final List<RenderEnvironmentFrame> configuredEnvironmentFrames =
      <RenderEnvironmentFrame>[];
  int loadCalls = 0;

  @override
  AdapterNodeSnapshot? get nodeSnapshot => snapshot;

  @override
  Future<void> loadGlbBytes(
    Uint8List bytes, {
    String? debugName,
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
  }) async {
    loadCalls += 1;
    materialShadingPolicies.add(materialShadingPolicy);
    final failure = loadFailure;
    if (failure != null) {
      throw FlutterSceneAdapterUnavailableException(failure.message);
    }
  }

  @override
  Future<List<ViewerDiagnostic>> applyMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  ) async {
    materialCalls.add(address);
    return const <ViewerDiagnostic>[];
  }

  @override
  Future<List<ViewerDiagnostic>> configureEnvironment(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    configuredEnvironmentFrames.add(frame);
    return environmentDiagnostics;
  }

  @override
  Future<PartAddress?> pickPart({
    required Offset localPosition,
    required Size viewportSize,
    required RenderCameraFrame camera,
  }) async {
    pickPositions.add(localPosition);
    pickViewportSizes.add(viewportSize);
    return pickedPart;
  }

  @override
  List<ViewerDiagnostic> collectDiagnostics() {
    final failure = loadFailure;
    return failure == null
        ? const <ViewerDiagnostic>[]
        : <ViewerDiagnostic>[failure];
  }

  @override
  Future<List<ViewerDiagnostic>> resetMaterial(PartAddress address) async {
    return const <ViewerDiagnostic>[];
  }
}

final class RecordingRenderScene implements AdapterRenderScene {
  static const surfaceKey = ValueKey<String>('fake.render.surface');

  final List<RenderCameraFrame> cameras = <RenderCameraFrame>[];
  final List<RenderLightingFrame> lightingFrames = <RenderLightingFrame>[];
  final List<RenderEnvironmentFrame> environmentFrames =
      <RenderEnvironmentFrame>[];
  final List<bool> autoTicks = <bool>[];

  @override
  Widget buildView({
    Key? key,
    required RenderCameraFrame camera,
    required RenderLightingFrame lighting,
    required RenderEnvironmentFrame environment,
    required bool autoTick,
  }) {
    cameras.add(camera);
    lightingFrames.add(lighting);
    environmentFrames.add(environment);
    autoTicks.add(autoTick);
    return const SizedBox(key: surfaceKey);
  }
}

double _cameraDistance(RenderCameraFrame camera) {
  final dx = camera.position[0] - camera.target[0];
  final dy = camera.position[1] - camera.target[1];
  final dz = camera.position[2] - camera.target[2];
  return math.sqrt(dx * dx + dy * dy + dz * dz);
}

Finder _readyViewerFinder() {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        key.value.startsWith('flutter_scene_viewer.ready.');
  });
}

String _readyViewerKey(WidgetTester tester) {
  final widget = tester.widget<Listener>(_readyViewerFinder());
  final key = widget.key! as ValueKey<String>;
  return key.value;
}
