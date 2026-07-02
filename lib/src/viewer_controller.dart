import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
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
  final List<ViewerDiagnostic> _diagnostics = <ViewerDiagnostic>[];
  ViewerLoadState _loadState = const ViewerLoadState.idle();
  PartTree _partTree = const PartTree.empty();

  List<ViewerDiagnostic> get diagnostics =>
      List<ViewerDiagnostic>.unmodifiable(_diagnostics);

  ViewerLoadState get loadState => _loadState;

  PartTree get partTree => _partTree;

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

  Future<void> setPartMaterial(PartAddress address, MaterialPatch patch) =>
      _requireSink().setPartMaterial(address, patch);

  Future<void> setPartTexture(PartAddress address, TextureSource source) =>
      setPartMaterial(address, MaterialPatch(baseColorTexture: source));

  Future<void> resetPart(PartAddress address) =>
      _requireSink().resetPart(address);

  Future<void> setPartVisibility(PartAddress address, bool visible) =>
      setPartMaterial(address, MaterialPatch(visible: visible));

  Future<void> fitCamera() => _requireSink().fitCamera();

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
}

@internal
abstract interface class ViewerCommandSink {
  Future<ModelLoadResult> load(ModelSource source);
  Future<void> setPartMaterial(PartAddress address, MaterialPatch patch);
  Future<void> resetPart(PartAddress address);
  Future<void> fitCamera();
}
