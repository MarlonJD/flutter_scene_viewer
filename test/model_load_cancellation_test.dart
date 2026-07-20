import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/viewer_controller.dart'
    show ViewerCommandSink;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancellation controller is idempotent and preserves the first reason',
      () async {
    final controller = ModelLoadCancellationController();
    var cancellationCompletions = 0;
    final cancellationCompletion = controller.token.whenCancelled
        .then((_) => cancellationCompletions += 1);

    expect(controller.token.isCancelled, isFalse);
    expect(controller.cancel('user-dismissed'), isTrue);
    expect(controller.cancel('later-reason'), isFalse);
    await controller.token.whenCancelled;
    await cancellationCompletion;

    expect(controller.token.isCancelled, isTrue);
    expect(controller.token.reason, 'user-dismissed');
    expect(cancellationCompletions, 1);
  });

  test('a pre-cancelled initial load does not invoke its command sink',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = _RecordingLoadSink();
    controller.attach(sink);
    final cancellation = ModelLoadCancellationController()
      ..cancel('view-disposed');

    await controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
      cancellationToken: cancellation.token,
    );

    expect(sink.loadCalls, 0);
    expect(controller.partTree.root, isNull);
    expect(controller.materialOverrides.isEmpty, isTrue);
    final cancellationDiagnostics = controller.diagnostics
        .where((diagnostic) =>
            diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled)
        .toList();
    expect(cancellationDiagnostics, hasLength(1));
    expect(cancellationDiagnostics.single.details['reason'], 'view-disposed');
    expect(cancellationDiagnostics.single.details['stage'], 'controller');
  });
}

final class _RecordingLoadSink implements ViewerCommandSink {
  int loadCalls = 0;

  @override
  MaterialExtensionSupport get materialExtensionSupport =>
      MaterialExtensionSupport.unsupported;

  @override
  Future<ModelLoadResult> load(
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) async {
    loadCalls += 1;
    return const ModelLoadResult.success();
  }

  @override
  Future<void> fitCamera() async {}

  @override
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) async {}

  @override
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) async {}

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) async =>
      const <ViewerDiagnostic>[];

  @override
  void requestRenderFrame() {}

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) async =>
      const <ViewerDiagnostic>[];
}
