import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';

/// Internal boundary for direct `flutter_scene` API calls.
///
/// Keep this file and nearby adapter files as the only place where concrete
/// `flutter_scene` classes leak into implementation details. Public API should
/// stay stable even when `flutter_scene` changes.
abstract interface class FlutterSceneAdapter {
  Future<void> loadGlbBytes(List<int> bytes, {String? debugName});

  Future<void> applyMaterialPatch(PartAddress address, MaterialPatch patch);

  Future<void> resetMaterial(PartAddress address);

  List<ViewerDiagnostic> collectDiagnostics();
}
