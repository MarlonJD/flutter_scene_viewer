import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_patch_group.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
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

  test('load does not re-diagnose unsupported authored sheen intent', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    const capabilityDiagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'Authored sheen is unsupported.',
      details: <String, Object?>{
        'feature': 'sheen',
        'extension': 'KHR_materials_sheen',
        'required': false,
        'blocking': false,
        'status': 'unsupported',
        'fallback': 'coreMaterial',
        'parsedIntentPreserved': true,
      },
    );
    final result = ModelLoadResult.success(
      diagnostics: const <ViewerDiagnostic>[capabilityDiagnostic],
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.6),
        },
      },
    );

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );
    sink.complete(result);
    await load;

    expect(controller.diagnostics, const <ViewerDiagnostic>[
      capabilityDiagnostic,
    ]);
    expect(
      result
          .authoredExtensionMaterialPatches[address]![
              MaterialExtensionPatchGroup.sheen]!
          .sheenRoughness,
      0.6,
    );
    expect(sink.materialCalls, isEmpty);
  });

  test('load suppresses only the addressed optional authored sheen', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink(
      materialExtensionSupport:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
                  enableSheen: true)
              .support,
    );
    controller.attach(sink);
    final failingAddress = PartAddress(
      nodePath: const <String>['IncompatibleFabric'],
      primitiveIndex: 0,
    );
    final validAddress = PartAddress(
      nodePath: const <String>['ValidFabric'],
      primitiveIndex: 0,
    );
    final diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'The requested sheen resources are incompatible.',
      details: <String, Object?>{
        'part': failingAddress.debugPath,
        'partAddress': failingAddress.toJson(),
        'feature': 'sheen',
        'extension': 'KHR_materials_sheen',
        'required': false,
        'blocking': false,
        'status': 'unsupported',
        'fallback': 'coreMaterial',
        'parsedIntentPreserved': true,
      },
    );
    final result = ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[diagnostic],
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        failingAddress: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.3),
        },
        validAddress: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.7),
        },
      },
    );

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );
    sink.complete(result);
    await load;

    expect(controller.diagnostics, <ViewerDiagnostic>[diagnostic]);
    expect(sink.materialCalls, <PartAddress>[validAddress]);
  });

  test('load uses structured authored sheen address when display paths collide',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink(
      materialExtensionSupport:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
                  enableSheen: true)
              .support,
    );
    controller.attach(sink);
    final failingAddress = PartAddress(
      nodePath: const <String>['A/B'],
      primitiveIndex: 0,
    );
    final validAddress = PartAddress(
      nodePath: const <String>['A', 'B'],
      primitiveIndex: 0,
    );
    expect(failingAddress.debugPath, validAddress.debugPath);
    final diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'The requested sheen resources are incompatible.',
      details: <String, Object?>{
        'part': failingAddress.debugPath,
        'partAddress': failingAddress.toJson(),
        'feature': 'sheen',
        'extension': 'KHR_materials_sheen',
        'required': false,
        'blocking': false,
        'status': 'unsupported',
        'fallback': 'coreMaterial',
        'parsedIntentPreserved': true,
      },
    );
    final result = ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[diagnostic],
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        failingAddress: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.3),
        },
        validAddress: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.7),
        },
      },
    );

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );
    sink.complete(result);
    await load;

    expect(controller.diagnostics, <ViewerDiagnostic>[diagnostic]);
    expect(sink.materialCalls, <PartAddress>[validAddress]);
  });

  test('load does not suppress sheen for malformed structured address',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink(
      materialExtensionSupport:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
                  enableSheen: true)
              .support,
    );
    controller.attach(sink);
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    const diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'The requested sheen resources are incompatible.',
      details: <String, Object?>{
        'partAddress': null,
        'feature': 'sheen',
        'extension': 'KHR_materials_sheen',
        'required': false,
        'blocking': false,
        'status': 'unsupported',
        'fallback': 'coreMaterial',
        'parsedIntentPreserved': true,
      },
    );
    final result = ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[diagnostic],
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.6),
        },
      },
    );

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );
    sink.complete(result);
    await load;

    expect(controller.diagnostics, <ViewerDiagnostic>[diagnostic]);
    expect(sink.materialCalls, <PartAddress>[address]);
  });

  test('load does not treat display-only sheen diagnostic as global', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink(
      materialExtensionSupport:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
                  enableSheen: true)
              .support,
    );
    controller.attach(sink);
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'The requested sheen resources are incompatible.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'sheen',
        'extension': 'KHR_materials_sheen',
        'required': false,
        'blocking': false,
        'status': 'unsupported',
        'fallback': 'coreMaterial',
        'parsedIntentPreserved': true,
      },
    );
    final result = ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[diagnostic],
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.sheen:
              const MaterialPatch(sheenRoughness: 0.6),
        },
      },
    );

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
    );
    sink.complete(result);
    await load;

    expect(controller.diagnostics, <ViewerDiagnostic>[diagnostic]);
    expect(sink.materialCalls, <PartAddress>[address]);
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

  test('cancelling a pending replacement preserves published state', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final previousAddress = PartAddress(
      nodePath: <String>['Previous'],
      primitiveIndex: 0,
    );
    final previousTree = _treeFor(previousAddress);
    final previousOverrides = MaterialOverrideSnapshot(
      patches: <PartAddress, MaterialPatch>{
        previousAddress: const MaterialPatch(roughness: 0.4),
      },
    );

    final initialLoad = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
      initialMaterialOverrides: previousOverrides,
    );
    sink.complete(ModelLoadResult.success(partTree: previousTree));
    await initialLoad;
    final renderRequestsBeforeCancellation = sink.renderRequests;
    sink.materialCalls.clear();

    final cancellation = ModelLoadCancellationController();
    final replacementLoad = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2])),
      initialMaterialOverrides: MaterialOverrideSnapshot(
        patches: <PartAddress, MaterialPatch>{
          PartAddress(nodePath: <String>['New'], primitiveIndex: 0):
              const MaterialPatch(metallic: 0.9),
        },
      ),
      cancellationToken: cancellation.token,
    );
    expect(sink.pendingLoads, 1);

    expect(cancellation.cancel('user-dismissed'), isTrue);
    await replacementLoad;

    expect(controller.partTree, same(previousTree));
    expect(
      controller.materialOverrides.patchFor(previousAddress)?.roughness,
      0.4,
    );
    expect(controller.materialOverrides.entries, hasLength(1));
    expect(sink.renderRequests, renderRequestsBeforeCancellation);
    expect(
      controller.diagnostics.where((diagnostic) =>
          diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled),
      hasLength(1),
    );
    expect(controller.loadState.status, ViewerLoadStatus.success);

    sink.completeOldest(
      ModelLoadResult.success(
        partTree: _treeFor(
          PartAddress(nodePath: <String>['Cancelled'], primitiveIndex: 0),
        ),
        authoredCoreMaterialPatches: <PartAddress, MaterialPatch>{
          PartAddress(nodePath: <String>['Cancelled'], primitiveIndex: 0):
              const MaterialPatch(roughness: 0.9),
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sink.materialCalls, isEmpty);
    expect(controller.partTree, same(previousTree));

    final freshCancellation = ModelLoadCancellationController();
    final laterLoad = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[3])),
      cancellationToken: freshCancellation.token,
    );
    final laterAddress = PartAddress(
      nodePath: <String>['Later'],
      primitiveIndex: 0,
    );
    sink.complete(ModelLoadResult.success(partTree: _treeFor(laterAddress)));
    await laterLoad;

    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect(controller.partTree.records.single.address, laterAddress);
    expect(sink.cancellationTokens.last, same(freshCancellation.token));
    expect(sink.cancellationTokens.last, isNot(same(cancellation.token)));
  });

  test('a pre-cancelled replacement does not supersede a pending load',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);

    final loadA = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'A'),
    );
    final cancellationB = ModelLoadCancellationController()..cancel('closed');
    await controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'B'),
      cancellationToken: cancellationB.token,
    );

    expect(sink.pendingLoads, 1);
    expect(controller.loadState.status, ViewerLoadStatus.loading);
    expect((controller.loadState.source as BytesModelSource).debugName, 'A');

    sink.complete(const ModelLoadResult.success());
    await loadA;
    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect((controller.loadState.source as BytesModelSource).debugName, 'A');
  });

  test('a pre-cancelled no-op does not wait for accepted finalization',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = AcceptanceWindowSink();
    controller.attach(sink);
    final acceptedToken = ModelLoadCancellationController();
    final loadB = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'B'),
      cancellationToken: acceptedToken.token,
    );
    await sink.publicationAccepted.future;

    final cancelled = ModelLoadCancellationController()..cancel('no-op');
    var cComplete = false;
    final loadC = controller
        .load(
          ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
          cancellationToken: cancelled.token,
        )
        .whenComplete(() => cComplete = true);
    await Future<void>.delayed(Duration.zero);
    expect(cComplete, isTrue);
    expect(sink.cStarted.isCompleted, isFalse);

    sink.bSettlement.complete();
    await loadB;
    await loadC;
  });

  test('a stale ordinary tokenless failure cannot replace C', () async {
    await _verifyStaleOrdinaryFailure(withCancellationToken: false);
  });

  test('a stale ordinary live-token failure cannot replace C', () async {
    await _verifyStaleOrdinaryFailure(withCancellationToken: true);
  });

  test('token rejection after a controller claim releases finalization once',
      () async {
    final cancellation = ModelLoadCancellationController();
    final controller = FlutterSceneViewerController();
    final sink = ClaimThenRejectSink(cancellation);
    controller.attach(sink);

    await controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'B'),
      cancellationToken: cancellation.token,
    );
    expect(sink.claimed, isTrue);
    expect(
      controller.diagnostics.where((diagnostic) =>
          diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled),
      hasLength(1),
    );

    await controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
    );
    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect((controller.loadState.source as BytesModelSource).debugName, 'C');
  });

  test('accepted publication closes cancellation before sink settlement',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = PublicationAcceptingSink();
    controller.attach(sink);
    final cancellation = ModelLoadCancellationController();

    final load = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1])),
      cancellationToken: cancellation.token,
    );
    await sink.publicationAccepted.future;

    expect(cancellation.cancel('too-late'), isFalse);
    sink.settlement.complete();
    await load;

    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect(
      controller.diagnostics.where((diagnostic) =>
          diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled),
      isEmpty,
    );
  });

  test('accepted publication blocks a replacement before sink settlement',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = AcceptanceWindowSink();
    controller.attach(sink);
    final cancellation = ModelLoadCancellationController();
    final address = PartAddress(nodePath: <String>['B'], primitiveIndex: 0);

    final loadB = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'B'),
      cancellationToken: cancellation.token,
      initialMaterialOverrides: MaterialOverrideSnapshot(
        patches: <PartAddress, MaterialPatch>{
          address: const MaterialPatch(roughness: 0.3),
        },
      ),
    );
    await sink.publicationAccepted.future;

    final loadC = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
    );
    expect(sink.cStarted.isCompleted, isFalse);

    sink.bSettlement.complete();
    await loadB;
    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect((controller.loadState.source as BytesModelSource).debugName, 'B');
    expect(sink.materialCalls, <PartAddress>[address, address]);

    await sink.cStarted.future;
    sink.cSettlement.complete();
    await loadC;
  });

  test('a stale cancelled replacement cannot restore an older load state',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final addressA = PartAddress(nodePath: <String>['A'], primitiveIndex: 0);
    final addressC = PartAddress(nodePath: <String>['C'], primitiveIndex: 0);

    final loadA =
        controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));
    sink.complete(ModelLoadResult.success(partTree: _treeFor(addressA)));
    await loadA;

    final cancellationB = ModelLoadCancellationController();
    final loadB = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'B'),
      cancellationToken: cancellationB.token,
    );
    final cancellationC = ModelLoadCancellationController();
    final loadC = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[3]), debugName: 'C'),
      cancellationToken: cancellationC.token,
    );
    sink.complete(ModelLoadResult.success(partTree: _treeFor(addressC)));
    await loadC;

    expect(cancellationB.cancel('superseded'), isTrue);
    await loadB;

    expect(controller.loadState.status, ViewerLoadStatus.success);
    expect(controller.loadState.source, isA<BytesModelSource>());
    expect((controller.loadState.source! as BytesModelSource).debugName, 'C');
    expect(controller.partTree.records.single.address, addressC);
    expect(
      controller.diagnostics.where((diagnostic) =>
          diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled &&
          diagnostic.details['source'] == 'B'),
      hasLength(1),
    );
  });

  test('a stale tokenless publication cannot replace a newer live scene',
      () async {
    await _verifyOutOfOrderPublicationRejection(withCancellationToken: false);
  });

  test('a stale live-token publication cannot replace a newer live scene',
      () async {
    await _verifyOutOfOrderPublicationRejection(withCancellationToken: true);
  });

  test('accepted publication finalizes overrides before a replacement starts',
      () async {
    final materialGate = Completer<void>();
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink(materialGate: materialGate);
    controller.attach(sink);
    final authoredAddress =
        PartAddress(nodePath: <String>['B', 'Authored'], primitiveIndex: 0);
    final initialAddress = authoredAddress;
    final observedStates = <ViewerLoadState>[];
    controller.addListener(() => observedStates.add(controller.loadState));

    final loadB = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'B'),
      initialMaterialOverrides: MaterialOverrideSnapshot(
        patches: <PartAddress, MaterialPatch>{
          initialAddress: const MaterialPatch(roughness: 0.3),
        },
      ),
    );
    sink.complete(
      ModelLoadResult.success(
        partTree: _treeFor(authoredAddress),
        authoredCoreMaterialPatches: <PartAddress, MaterialPatch>{
          authoredAddress: const MaterialPatch(metallic: 0.8),
        },
      ),
    );
    await sink.materialPatchStarted.future;

    final loadC = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[3]), debugName: 'C'),
    );
    expect(sink.pendingLoads, 0);

    materialGate.complete();
    await loadB;
    await Future<void>.delayed(Duration.zero);

    expect(sink.materialCalls, <PartAddress>[authoredAddress, initialAddress]);
    final successB = observedStates.indexWhere(
      (state) =>
          state.status == ViewerLoadStatus.success &&
          (state.source as BytesModelSource?)?.debugName == 'B',
    );
    final loadingC = observedStates.indexWhere(
      (state) =>
          state.status == ViewerLoadStatus.loading &&
          (state.source as BytesModelSource?)?.debugName == 'C',
    );
    expect(successB, isNonNegative);
    expect(loadingC, greaterThan(successB));

    sink.complete(
      ModelLoadResult.success(
        partTree: _treeFor(
          PartAddress(nodePath: <String>['C'], primitiveIndex: 0),
        ),
      ),
    );
    await loadC;
  });

  test('reentrant load during success diagnostics waits for finalization',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    final observedStates = <ViewerLoadState>[];
    Future<void>? reentrantLoad;
    var startedReplacement = false;
    controller.addListener(() {
      observedStates.add(controller.loadState);
      if (!startedReplacement && controller.diagnostics.isNotEmpty) {
        startedReplacement = true;
        reentrantLoad = controller.load(
          ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
        );
      }
    });

    final loadA = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'A'),
    );
    sink.complete(
      const ModelLoadResult.success(
        diagnostics: <ViewerDiagnostic>[
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.unsupportedModelFeature,
            message: 'A diagnostic emitted with successful publication.',
          ),
        ],
      ),
    );
    await loadA;
    await Future<void>.delayed(Duration.zero);

    final successA = observedStates.indexWhere(
      (state) =>
          state.status == ViewerLoadStatus.success &&
          (state.source as BytesModelSource?)?.debugName == 'A',
    );
    final loadingC = observedStates.indexWhere(
      (state) =>
          state.status == ViewerLoadStatus.loading &&
          (state.source as BytesModelSource?)?.debugName == 'C',
    );
    expect(successA, isNonNegative);
    expect(loadingC, greaterThan(successA));
    expect(controller.loadState.status, ViewerLoadStatus.loading);
    expect((controller.loadState.source as BytesModelSource).debugName, 'C');

    sink.complete(const ModelLoadResult.success());
    await reentrantLoad;
  });

  test('reentrant load during failure diagnostics remains current', () async {
    final controller = FlutterSceneViewerController();
    final sink = CompletingLoadSink();
    controller.attach(sink);
    Future<void>? reentrantLoad;
    var startedReplacement = false;
    controller.addListener(() {
      if (!startedReplacement && controller.diagnostics.isNotEmpty) {
        startedReplacement = true;
        reentrantLoad = controller.load(
          ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
        );
      }
    });

    final loadA = controller.load(
      ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'A'),
    );
    sink.complete(
      const ModelLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'A failed before publication.',
        ),
      ),
    );
    await loadA;
    await Future<void>.delayed(Duration.zero);

    expect(controller.loadState.status, ViewerLoadStatus.loading);
    expect((controller.loadState.source as BytesModelSource).debugName, 'C');

    sink.complete(const ModelLoadResult.success());
    await reentrantLoad;
  });
}

PartTree _treeFor(PartAddress address) {
  final record = PartRecord(address: address);
  return PartTree(
    root: PartNode(
      name: address.nodePath.first,
      nodePath: <String>[address.nodePath.first],
      records: <PartRecord>[record],
    ),
    records: <PartRecord>[record],
  );
}

Future<void> _verifyOutOfOrderPublicationRejection({
  required bool withCancellationToken,
}) async {
  final controller = FlutterSceneViewerController();
  final sink = OutOfOrderPublicationSink();
  controller.attach(sink);
  final cancellation =
      withCancellationToken ? ModelLoadCancellationController() : null;

  final loadB = controller.load(
    ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'B'),
    cancellationToken: cancellation?.token,
  );
  await sink.bStarted.future;

  final loadC = controller.load(
    ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
  );
  await sink.cAccepted.future;
  await loadC;

  sink.allowBAcceptanceAttempt.complete();
  await loadB;

  expect(sink.bPublicationAccepted, isFalse);
  expect(sink.liveSource, 'C');
  expect(controller.loadState.status, ViewerLoadStatus.success);
  expect((controller.loadState.source as BytesModelSource).debugName, 'C');
  expect(controller.diagnostics, isEmpty);
  if (cancellation != null) {
    expect(cancellation.cancel('still-live'), isTrue);
  }
}

Future<void> _verifyStaleOrdinaryFailure({
  required bool withCancellationToken,
}) async {
  final controller = FlutterSceneViewerController();
  final sink = CompletingLoadSink();
  controller.attach(sink);
  final cancellation =
      withCancellationToken ? ModelLoadCancellationController() : null;
  final loadB = controller.load(
    ModelSource.bytes(Uint8List.fromList(<int>[1]), debugName: 'B'),
    cancellationToken: cancellation?.token,
  );
  final loadC = controller.load(
    ModelSource.bytes(Uint8List.fromList(<int>[2]), debugName: 'C'),
  );
  sink.complete(
    ModelLoadResult.success(
      partTree: _treeFor(
        PartAddress(nodePath: <String>['C'], primitiveIndex: 0),
      ),
    ),
  );
  await loadC;

  sink.completeOldest(
    const ModelLoadResult.failure(
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.networkFailure,
        message: 'Late B pre-publication failure.',
      ),
    ),
  );
  await loadB;

  expect(controller.loadState.status, ViewerLoadStatus.success);
  expect((controller.loadState.source as BytesModelSource).debugName, 'C');
  expect(controller.partTree.root?.name, 'C');
  expect(controller.diagnostics, isEmpty);
  if (cancellation != null) {
    expect(cancellation.cancel('still-live'), isTrue);
  }
}

final class CompletingLoadSink implements ViewerCommandSink {
  CompletingLoadSink({
    this.materialGate,
    this.materialExtensionSupport = MaterialExtensionSupport.unsupported,
  });

  final List<Completer<ModelLoadResult>> _completers =
      <Completer<ModelLoadResult>>[];
  final List<ModelLoadCancellationToken?> cancellationTokens =
      <ModelLoadCancellationToken?>[];
  final List<PartAddress> materialCalls = <PartAddress>[];
  final Completer<void>? materialGate;
  final Completer<void> materialPatchStarted = Completer<void>();
  int renderRequests = 0;

  int get pendingLoads =>
      _completers.where((entry) => !entry.isCompleted).length;

  @override
  final MaterialExtensionSupport materialExtensionSupport;

  void complete(ModelLoadResult result) {
    _completers.lastWhere((entry) => !entry.isCompleted).complete(result);
  }

  void completeOldest(ModelLoadResult result) {
    _completers.firstWhere((entry) => !entry.isCompleted).complete(result);
  }

  @override
  Future<ModelLoadResult> load(
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) {
    cancellationTokens.add(cancellationToken);
    final completer = Completer<ModelLoadResult>();
    _completers.add(completer);
    return completer.future;
  }

  @override
  Future<void> fitCamera() {
    throw UnimplementedError();
  }

  @override
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(address) async =>
      const <ViewerDiagnostic>[];

  @override
  void requestRenderFrame() {
    renderRequests += 1;
  }

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(address, patch) async {
    materialCalls.add(address);
    if (materialGate != null) {
      if (!materialPatchStarted.isCompleted) {
        materialPatchStarted.complete();
      }
      await materialGate!.future;
    }
    return const <ViewerDiagnostic>[];
  }
}

final class PublicationAcceptingSink implements ViewerCommandSink {
  final Completer<void> publicationAccepted = Completer<void>();
  final Completer<void> settlement = Completer<void>();

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
    expect(cancellationToken, isNotNull);
    expect(tryAcceptModelLoadPublication(cancellationToken!), isTrue);
    expect(tryAcceptPublication?.call(), isTrue);
    publicationAccepted.complete();
    await settlement.future;
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

final class AcceptanceWindowSink implements ViewerCommandSink {
  final Completer<void> publicationAccepted = Completer<void>();
  final Completer<void> bSettlement = Completer<void>();
  final Completer<void> cStarted = Completer<void>();
  final Completer<void> cSettlement = Completer<void>();
  final List<PartAddress> materialCalls = <PartAddress>[];

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
    final debugName = (source as BytesModelSource).debugName;
    if (debugName == 'B') {
      expect(tryAcceptModelLoadPublication(cancellationToken!), isTrue);
      if (tryAcceptPublication?.call() != true) {
        return const ModelLoadResult.failure(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.modelLoadCancelled,
            message: 'Publication was rejected.',
          ),
        );
      }
      publicationAccepted.complete();
      await bSettlement.future;
      final address = PartAddress(nodePath: <String>['B'], primitiveIndex: 0);
      return ModelLoadResult.success(
        partTree: _treeFor(address),
        authoredCoreMaterialPatches: <PartAddress, MaterialPatch>{
          address: const MaterialPatch(metallic: 0.8),
        },
      );
    }
    cStarted.complete();
    await cSettlement.future;
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
  ) async {
    materialCalls.add(address);
    return const <ViewerDiagnostic>[];
  }
}

final class OutOfOrderPublicationSink implements ViewerCommandSink {
  final Completer<void> bStarted = Completer<void>();
  final Completer<void> allowBAcceptanceAttempt = Completer<void>();
  final Completer<void> cAccepted = Completer<void>();
  bool bPublicationAccepted = false;
  String? liveSource;

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
    final debugName = (source as BytesModelSource).debugName;
    if (debugName == 'B') {
      bStarted.complete();
      await allowBAcceptanceAttempt.future;
      final controllerAccepted = tryAcceptPublication?.call() ?? true;
      if (!controllerAccepted) {
        return const ModelLoadResult.failure(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.adapterFailure,
            message: 'Stale publication was rejected.',
          ),
          superseded: true,
        );
      }
      final tokenAccepted = cancellationToken == null ||
          tryAcceptModelLoadPublication(cancellationToken);
      if (!tokenAccepted) {
        onPublicationRejected?.call();
        return const ModelLoadResult.failure(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.modelLoadCancelled,
            message: 'Caller cancellation rejected publication.',
          ),
        );
      }
      bPublicationAccepted = true;
      liveSource = 'B';
      return const ModelLoadResult.success();
    }
    expect(tryAcceptPublication?.call(), isTrue);
    liveSource = 'C';
    cAccepted.complete();
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

final class ClaimThenRejectSink implements ViewerCommandSink {
  ClaimThenRejectSink(this.cancellation);

  final ModelLoadCancellationController cancellation;
  var claimed = false;

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
    final debugName = (source as BytesModelSource).debugName;
    if (debugName == 'B') {
      expect(tryAcceptPublication?.call(), isTrue);
      claimed = true;
      expect(cancellation.cancel('rejected-after-claim'), isTrue);
      expect(tryAcceptModelLoadPublication(cancellationToken!), isFalse);
      onPublicationRejected?.call();
      return const ModelLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.modelLoadCancelled,
          message: 'Publication token was rejected.',
        ),
      );
    }
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
