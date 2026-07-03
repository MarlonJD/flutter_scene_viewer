import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/viewer_controller.dart'
    show ViewerCommandSink;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller explains unattached usage', () async {
    final controller = FlutterSceneViewerController();

    expect(
      () => controller.fitCamera(),
      throwsA(isA<StateError>()),
    );
  });

  test('setCameraOrbit explains unattached usage', () async {
    final controller = FlutterSceneViewerController();

    expect(
      () => controller.setCameraOrbit(distance: 2),
      throwsA(isA<StateError>()),
    );
  });

  test('fitCamera forwards to the attached viewer and requests a frame',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = FitCameraSink();
    controller.attach(sink);

    await controller.fitCamera();

    expect(sink.fitCalls, 1);
    expect(sink.renderRequests, 1);
  });

  test('setCameraOrbit forwards to the attached viewer and requests a frame',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = FitCameraSink();
    controller.attach(sink);

    await controller.setCameraOrbit(
      target: const <double>[1, 2, 3],
      distance: 4,
      yawRadians: 0.5,
      pitchRadians: -0.25,
    );

    expect(sink.orbitCalls, 1);
    expect(sink.lastTarget, <double>[1, 2, 3]);
    expect(sink.lastDistance, 4);
    expect(sink.lastYawRadians, 0.5);
    expect(sink.lastPitchRadians, -0.25);
    expect(sink.renderRequests, 1);
  });

  test('setCameraPosition forwards to the attached viewer and requests a frame',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = FitCameraSink();
    controller.attach(sink);

    await controller.setCameraPosition(
      position: const <double>[3, 4, 5],
      target: const <double>[1, 2, 3],
    );

    expect(sink.positionCalls, 1);
    expect(sink.lastPosition, <double>[3, 4, 5]);
    expect(sink.lastTarget, <double>[1, 2, 3]);
    expect(sink.renderRequests, 1);
  });
}

final class FitCameraSink implements ViewerCommandSink {
  int fitCalls = 0;
  int orbitCalls = 0;
  int positionCalls = 0;
  int renderRequests = 0;
  List<double>? lastTarget;
  List<double>? lastPosition;
  double? lastDistance;
  double? lastYawRadians;
  double? lastPitchRadians;

  @override
  Future<ModelLoadResult> load(ModelSource source) {
    throw UnimplementedError();
  }

  @override
  Future<void> fitCamera() async {
    fitCalls += 1;
  }

  @override
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) async {
    orbitCalls += 1;
    lastTarget = target;
    lastDistance = distance;
    lastYawRadians = yawRadians;
    lastPitchRadians = pitchRadians;
  }

  @override
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) async {
    positionCalls += 1;
    lastPosition = position;
    lastTarget = target;
  }

  @override
  void requestRenderFrame() {
    renderRequests += 1;
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) async =>
      const <ViewerDiagnostic>[];
}
