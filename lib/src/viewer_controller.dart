import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'material_patch.dart';
import 'model_source.dart';
import 'part_address.dart';
import 'texture_source.dart';

/// Controller for programmatic viewer operations.
class FlutterSceneViewerController extends ChangeNotifier {
  ViewerCommandSink? _sink;
  final List<ViewerDiagnostic> _diagnostics = <ViewerDiagnostic>[];

  List<ViewerDiagnostic> get diagnostics =>
      List<ViewerDiagnostic>.unmodifiable(_diagnostics);

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

  Future<void> load(ModelSource source) => _requireSink().load(source);

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
  Future<void> load(ModelSource source);
  Future<void> setPartMaterial(PartAddress address, MaterialPatch patch);
  Future<void> resetPart(PartAddress address);
  Future<void> fitCamera();
}
