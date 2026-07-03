import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'internal/material_effect_mask_resolver.dart';
import 'material_extension_policy.dart';
import 'material_override_store.dart';
import 'material_patch.dart';
import 'material_shading_mode.dart';
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
        await _applyAuthoredMaterialPatches(
          result.authoredMaterialPatches,
          sink,
        );
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
    final sink = _requireSink();
    final diagnostics = _validateMaterialPatch(
      address,
      patch,
      support: sink.materialExtensionSupport,
    );
    if (diagnostics.isNotEmpty) {
      for (final diagnostic in diagnostics) {
        recordDiagnostic(diagnostic);
      }
      return;
    }
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

  Future<void> _applyAuthoredMaterialPatches(
    Map<PartAddress, MaterialPatch> patches,
    ViewerCommandSink sink,
  ) async {
    var appliedAny = false;
    for (final entry in patches.entries) {
      final address = entry.key;
      final patch = entry.value;
      final diagnostics = _validateMaterialPatch(
        address,
        patch,
        support: sink.materialExtensionSupport,
      );
      if (diagnostics.isNotEmpty) {
        for (final diagnostic in diagnostics) {
          recordDiagnostic(diagnostic);
        }
        continue;
      }
      final sinkDiagnostics = await sink.setPartMaterial(address, patch);
      if (sinkDiagnostics.isNotEmpty) {
        for (final diagnostic in sinkDiagnostics) {
          recordDiagnostic(diagnostic);
        }
        continue;
      }
      appliedAny = true;
    }
    if (appliedAny) {
      sink.requestRenderFrame();
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

  /// Sets the orbit camera fields owned by the attached viewer widget.
  ///
  /// The method exposes only plain Dart values, not concrete flutter_scene
  /// camera classes. Omitted fields keep the current camera value.
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) async {
    final sink = _requireSink();
    await sink.setCameraOrbit(
      target: target,
      distance: distance,
      yawRadians: yawRadians,
      pitchRadians: pitchRadians,
    );
    sink.requestRenderFrame();
  }

  /// Places the camera at [position] while looking at [target].
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) async {
    final sink = _requireSink();
    await sink.setCameraPosition(position: position, target: target);
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
    MaterialPatch patch, {
    MaterialExtensionSupport support = MaterialExtensionSupport.unsupported,
  }) {
    final diagnostics = patch.validate(address, support: support);
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
    final effectMaskDiagnostics = validateMaterialEffectMaskUv(
      address,
      patch,
      hasTexCoords: record.hasTexCoords,
    );
    if (effectMaskDiagnostics.isNotEmpty) {
      return effectMaskDiagnostics;
    }
    if (patch.hasTextureOverride && !record.hasTexCoords) {
      return <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.missingUvSet,
          message: 'Texture override requires authored UV coordinates.',
          details: <String, Object?>{
            'part': address.debugPath,
            'uvSet': 0,
            'textureSlots': _textureSlotsForPatch(patch),
          },
        ),
      ];
    }
    if (patch.alphaMode == MaterialAlphaMode.mask &&
        record.materialShadingMode == MaterialShadingMode.unlit) {
      return <ViewerDiagnostic>[_unlitAlphaMaskUnsupported(address)];
    }
    return const <ViewerDiagnostic>[];
  }

  ViewerDiagnostic _unlitAlphaMaskUnsupported(PartAddress address) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message:
          'Alpha mask overrides require a lit PBR material because the installed flutter_scene unlit material treats mask like blend.',
      details: <String, Object?>{
        'part': address.debugPath,
        'alphaMode': MaterialAlphaMode.mask.name,
        'materialShadingMode': MaterialShadingMode.unlit.name,
        'upstreamPackage': 'flutter_scene',
      },
    );
  }
}

List<String> _textureSlotsForPatch(MaterialPatch patch) {
  return <String>[
    if (patch.baseColorTexture != null) 'baseColorTexture',
    if (patch.metallicRoughnessTexture != null) 'metallicRoughnessTexture',
    if (patch.normalTexture != null) 'normalTexture',
    if (patch.emissiveTexture != null) 'emissiveTexture',
    if (patch.occlusionTexture != null) 'occlusionTexture',
    if (patch.effectMask != null) 'effectMask',
    if (patch.transmissionTexture != null) 'transmissionTexture',
    if (patch.thicknessTexture != null) 'thicknessTexture',
    if (patch.clearcoatTexture != null) 'clearcoatTexture',
    if (patch.clearcoatRoughnessTexture != null) 'clearcoatRoughnessTexture',
    if (patch.clearcoatNormalTexture != null) 'clearcoatNormalTexture',
  ];
}

@internal
abstract interface class ViewerCommandSink {
  MaterialExtensionSupport get materialExtensionSupport;

  Future<ModelLoadResult> load(ModelSource source);
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  );
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address);
  Future<void> fitCamera();
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  });
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  });
  void requestRenderFrame();
}
