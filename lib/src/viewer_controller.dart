import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'material_override_store.dart';
import 'material_patch.dart';
import 'model_loader.dart';
import 'model_source.dart';
import 'part_address.dart';
import 'part_registry.dart';
import 'texture_source.dart';

/// Lifecycle states for the controller's current model load.
enum ViewerLoadStatus {
  idle,
  loading,
  success,
  error,
}

/// Public model loading state exposed by [FlutterSceneViewerController].
final class ViewerLoadState {
  const ViewerLoadState.idle()
      : status = ViewerLoadStatus.idle,
        source = null,
        diagnostic = null;

  const ViewerLoadState.loading(this.source)
      : status = ViewerLoadStatus.loading,
        diagnostic = null;

  const ViewerLoadState.success(this.source)
      : status = ViewerLoadStatus.success,
        diagnostic = null;

  const ViewerLoadState.error(this.source, this.diagnostic)
      : status = ViewerLoadStatus.error;

  final ViewerLoadStatus status;
  final ModelSource? source;
  final ViewerDiagnostic? diagnostic;

  bool get isLoading => status == ViewerLoadStatus.loading;
}

/// Controller for programmatic viewer operations.
class FlutterSceneViewerController extends ChangeNotifier {
  ViewerCommandSink? _sink;
  final MaterialOverrideStore _materialOverrides = MaterialOverrideStore();
  final List<ViewerDiagnostic> _diagnostics = <ViewerDiagnostic>[];
  ViewerLoadState _loadState = const ViewerLoadState.idle();
  PartTree _partTree = const PartTree.empty();

  List<ViewerDiagnostic> get diagnostics =>
      List<ViewerDiagnostic>.unmodifiable(_diagnostics);

  ViewerLoadState get loadState => _loadState;

  PartTree get partTree => _partTree;

  MaterialOverrideSnapshot get materialOverrides => _materialOverrides.snapshot;

  @internal
  void attach(ViewerCommandSink sink) {
    _sink = sink;
  }

  @internal
  void detach(ViewerCommandSink sink) {
    if (identical(_sink, sink)) {
      _sink = null;
    }
  }

  Future<void> load(ModelSource source) async {
    final sink = _requireSink();
    _partTree = const PartTree.empty();
    _materialOverrides.resetAll();
    _setLoadState(ViewerLoadState.loading(source));
    try {
      final result = await sink.load(source);
      for (final diagnostic in result.diagnostics) {
        recordDiagnostic(diagnostic);
      }
      final diagnostic = result.diagnostic;
      if (diagnostic == null) {
        _partTree = result.partTree;
        _setLoadState(ViewerLoadState.success(source));
      } else {
        _partTree = const PartTree.empty();
        recordDiagnostic(diagnostic);
        _setLoadState(ViewerLoadState.error(source, diagnostic));
      }
    } on Object catch (error) {
      _partTree = const PartTree.empty();
      final diagnostic = ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterFailure,
        message: 'Model loading failed.',
        details: <String, Object?>{'error': error.toString()},
      );
      recordDiagnostic(diagnostic);
      _setLoadState(ViewerLoadState.error(source, diagnostic));
    }
  }

  Future<void> setPartMaterial(PartAddress address, MaterialPatch patch) async {
    final diagnostics = _validateMaterialPatch(address, patch);
    if (diagnostics.isNotEmpty) {
      for (final diagnostic in diagnostics) {
        recordDiagnostic(diagnostic);
      }
      return;
    }
    final sink = _requireSink();
    final sinkDiagnostics = await sink.setPartMaterial(address, patch);
    if (sinkDiagnostics.isNotEmpty) {
      for (final diagnostic in sinkDiagnostics) {
        recordDiagnostic(diagnostic);
      }
      return;
    }
    _materialOverrides.applyPatch(address, patch);
    sink.requestRenderFrame();
    notifyListeners();
  }

  Future<void> setPartTexture(PartAddress address, TextureSource source) =>
      setPartMaterial(address, MaterialPatch(baseColorTexture: source));

  Future<void> resetPart(PartAddress address) async {
    final sink = _requireSink();
    final diagnostics = await sink.resetPart(address);
    if (diagnostics.isNotEmpty) {
      for (final diagnostic in diagnostics) {
        recordDiagnostic(diagnostic);
      }
      return;
    }
    _materialOverrides.resetPart(address);
    sink.requestRenderFrame();
    notifyListeners();
  }

  Future<void> applyMaterialOverrides(
    MaterialOverrideSnapshot snapshot,
  ) async {
    for (final entry in snapshot.entries) {
      await setPartMaterial(entry.key, entry.value);
    }
  }

  Future<void> setPartVisibility(PartAddress address, bool visible) =>
      setPartMaterial(address, MaterialPatch(visible: visible));

  /// Fits the viewer camera to the loaded model and requests a fresh frame.
  ///
  /// The public API intentionally stays independent of flutter_scene camera
  /// classes. The widget owns the adapter-specific camera mapping.
  Future<void> fitCamera() async {
    final sink = _requireSink();
    await sink.fitCamera();
    sink.requestRenderFrame();
  }

  void recordDiagnostic(ViewerDiagnostic diagnostic) {
    _diagnostics.add(diagnostic);
    notifyListeners();
  }

  void _setLoadState(ViewerLoadState state) {
    _loadState = state;
    notifyListeners();
  }

  ViewerCommandSink _requireSink() {
    final sink = _sink;
    if (sink == null) {
      throw StateError(
          'FlutterSceneViewerController is not attached to a FlutterSceneViewer.');
    }
    return sink;
  }

  List<ViewerDiagnostic> _validateMaterialPatch(
    PartAddress address,
    MaterialPatch patch,
  ) {
    final diagnostics = patch.validate(address);
    if (diagnostics.isNotEmpty || _partTree.root == null) {
      return diagnostics;
    }
    if (_partTree.isAmbiguous(address)) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.ambiguousNodePath,
          message: 'Material override target is ambiguous.',
          details: <String, Object?>{'part': address.debugPath},
        ),
      ];
    }
    final record = _partTree.resolvePart(address);
    if (record == null) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.primitiveNotFound,
          message: 'Material override target was not found.',
          details: <String, Object?>{'part': address.debugPath},
        ),
      ];
    }
    if (patch.baseColorTexture != null && !record.hasTexCoords) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.missingUvSet,
          message: 'Texture override requires authored UV coordinates.',
          details: <String, Object?>{'part': address.debugPath, 'uvSet': 0},
        ),
      ];
    }
    return const <ViewerDiagnostic>[];
  }
}

@internal
abstract interface class ViewerCommandSink {
  Future<ModelLoadResult> load(ModelSource source);
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  );
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address);
  Future<void> fitCamera();
  void requestRenderFrame();
}
