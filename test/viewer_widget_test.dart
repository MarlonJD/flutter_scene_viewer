import 'dart:typed_data';

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
      find.byKey(const ValueKey<String>('flutter_scene_viewer.ready.0')),
      findsOneWidget,
    );
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

    expect(
      find.byKey(const ValueKey<String>('flutter_scene_viewer.ready.0')),
      findsOneWidget,
    );

    await controller.setPartMaterial(
      address,
      const MaterialPatch(roughness: 0.4),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('flutter_scene_viewer.ready.1')),
      findsOneWidget,
    );
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
      closeTo(13.674234614174767, 1e-9),
    );
    expect(renderScene.cameras.last.position[1], closeTo(23, 1e-9));
    expect(
        renderScene.cameras.last.position[2], closeTo(33.67423461417477, 1e-9));
  });
}

final class FakeViewerAdapter implements FlutterSceneAdapter {
  FakeViewerAdapter({
    this.snapshot,
    this.loadFailure,
    this.renderScene,
    this.modelBounds,
  });

  final AdapterNodeSnapshot? snapshot;
  final ViewerDiagnostic? loadFailure;
  @override
  final AdapterRenderScene? renderScene;
  @override
  final AdapterModelBounds? modelBounds;
  final List<PartAddress> materialCalls = <PartAddress>[];

  @override
  AdapterNodeSnapshot? get nodeSnapshot => snapshot;

  @override
  Future<void> loadGlbBytes(Uint8List bytes, {String? debugName}) async {
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
  final List<bool> autoTicks = <bool>[];

  @override
  Widget buildView({
    Key? key,
    required RenderCameraFrame camera,
    required bool autoTick,
  }) {
    cameras.add(camera);
    autoTicks.add(autoTick);
    return const SizedBox(key: surfaceKey);
  }
}
