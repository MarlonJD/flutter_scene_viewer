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

  test('fitCamera forwards to the attached viewer and requests a frame',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = FitCameraSink();
    controller.attach(sink);

    await controller.fitCamera();

    expect(sink.fitCalls, 1);
    expect(sink.renderRequests, 1);
  });
}

final class FitCameraSink implements ViewerCommandSink {
  int fitCalls = 0;
  int renderRequests = 0;

  @override
  Future<ModelLoadResult> load(ModelSource source) {
    throw UnimplementedError();
  }

  @override
  Future<void> fitCamera() async {
    fitCalls += 1;
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
