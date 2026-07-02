import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/viewer_controller.dart'
    show ViewerCommandSink;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load exposes loading and success states', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final observedStatuses = <ViewerLoadStatus>[];
    controller.addListener(
      () => observedStatuses.add(controller.loadState.status),
    );

    final loadFuture = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );

    expect(controller.loadState.status, ViewerLoadStatus.loading);
    sink.complete(const ModelLoadResult.success());
    await loadFuture;

    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect(observedStatuses, <ViewerLoadStatus>[
      ViewerLoadStatus.loading,
      ViewerLoadStatus.success,
    ]);
  });

  test('load records diagnostics and exposes error state', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    const diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.networkFailure,
      message: 'Network failed.',
    );

    final loadFuture = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );

    sink.complete(const ModelLoadResult.failure(diagnostic));
    await loadFuture;

    expect(controller.loadState.status, ViewerLoadStatus.error);
    expect(controller.loadState.diagnostic, diagnostic);
    expect(controller.diagnostics, <ViewerDiagnostic>[diagnostic]);
  });

  test('load exposes read-only part tree from successful load result',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final address = PartAddress(
      nodePath: <String>['Vehicle', 'Wheel'],
      primitiveIndex: 0,
    );
    final record = PartRecord(address: address);
    final tree = PartTree(
      root: PartNode(
        name: 'Vehicle',
        nodePath: <String>['Vehicle'],
        children: <PartNode>[
          PartNode(
            name: 'Wheel',
            nodePath: <String>['Vehicle', 'Wheel'],
            records: <PartRecord>[record],
          ),
        ],
      ),
      records: <PartRecord>[record],
    );

    final loadFuture = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );

    sink.complete(ModelLoadResult.success(partTree: tree));
    await loadFuture;

    expect(controller.partTree.root?.name, 'Vehicle');
    expect(controller.partTree.records.single.address, address);
    expect(
      () => controller.partTree.records.add(record),
      throwsUnsupportedError,
    );
  });
}

final class CompletingLoadSink implements ViewerCommandSink {
  Completer<ModelLoadResult>? _completer;

  void complete(ModelLoadResult result) {
    _completer!.complete(result);
  }

  @override
  Future<ModelLoadResult> load(ModelSource source) {
    _completer = Completer<ModelLoadResult>();
    return _completer!.future;
  }

  @override
  Future<void> fitCamera() {
    throw UnimplementedError();
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(address) async =>
      const <ViewerDiagnostic>[];

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(address, patch) async =>
      const <ViewerDiagnostic>[];
}
