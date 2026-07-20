import 'dart:async';

import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'internal/material_effect_mask_resolver.dart';
import 'internal/material_extension_patch_group.dart';
import 'material_extension_policy.dart';
import 'material_override_store.dart';
import 'material_patch.dart';
import 'material_shading_mode.dart';
import 'model_load_cancellation.dart';
import 'model_loader.dart';
import 'model_source.dart';
import 'part_address.dart';
import 'part_registry.dart';
import 'texture_binding.dart';
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
  ViewerLoadState _lastSettledLoadState = const ViewerLoadState.idle();
  Completer<void>? _acceptedPublicationFinalization;
  var _nextLoadAttempt = 0;
  var _activeLoadAttempt = 0;
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

  Future<void> load(
    ModelSource source, {
    MaterialOverrideSnapshot initialMaterialOverrides =
        MaterialOverrideSnapshot.empty,
    ModelLoadCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled == true) {
      recordDiagnostic(
        modelLoadCancellationDiagnostic(
          source,
          cancellationToken!,
          stage: 'controller',
        ),
      );
      return;
    }
    final activeFinalization = _acceptedPublicationFinalization;
    if (activeFinalization != null) {
      await activeFinalization.future;
    }
    final sink = _requireSink();
    final attempt = ++_nextLoadAttempt;
    _activeLoadAttempt = attempt;
    _setLoadState(ViewerLoadState.loading(source));
    Completer<void>? acceptedFinalization;
    var publicationClosed = false;
    try {
      final result = await _loadFromSink(
        sink,
        source,
        cancellationToken: cancellationToken,
        tryAcceptPublication: () {
          if (publicationClosed || !_isCurrentLoadAttempt(attempt)) {
            return false;
          }
          acceptedFinalization ??= _beginAcceptedPublicationFinalization();
          return true;
        },
        onPublicationRejected: () {
          final finalization = acceptedFinalization;
          if (finalization != null) {
            _endAcceptedPublicationFinalization(finalization);
            acceptedFinalization = null;
          }
        },
      );
      if (!_isCurrentLoadAttempt(attempt)) {
        if (result.superseded) {
          return;
        }
        _recordStaleCancellation(result);
        return;
      }
      final diagnostic = result.diagnostic;
      if (diagnostic == null) {
        if (_finishCancellationIfRequested(
          source,
          cancellationToken,
          attempt: attempt,
          stage: 'authoredPatchPublication',
        )) {
          return;
        }
        acceptedFinalization ??= _beginAcceptedPublicationFinalization();
        for (final resultDiagnostic in result.diagnostics) {
          recordDiagnostic(resultDiagnostic);
        }
        _partTree = result.partTree;
        _materialOverrides.resetAll();
        await _applyAuthoredMaterialPatches(
          result.authoredCoreMaterialPatches,
          result.authoredExtensionMaterialPatches,
          sink,
        );
        if (_finishCancellationIfRequested(
          source,
          cancellationToken,
          attempt: attempt,
          stage: 'initialOverridePublication',
        )) {
          return;
        }
        await _applyLoadInitialMaterialOverrides(
          initialMaterialOverrides,
          sink,
        );
        if (_finishCancellationIfRequested(
          source,
          cancellationToken,
          attempt: attempt,
          stage: 'successPublication',
        )) {
          return;
        }
        _setSettledLoadState(ViewerLoadState.success(source));
        return;
      } else {
        final isCancelled =
            diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled;
        if (isCancelled) {
          for (final resultDiagnostic in result.diagnostics) {
            if (resultDiagnostic.code !=
                ViewerDiagnosticCode.modelLoadCancelled) {
              recordDiagnostic(resultDiagnostic);
            }
          }
          _finishLoadCancellation(
            source,
            cancellationToken,
            attempt: attempt,
            diagnostic: diagnostic,
            stage: 'controller',
          );
          return;
        }
        _partTree = const PartTree.empty();
        _materialOverrides.resetAll();
        _setSettledLoadState(ViewerLoadState.error(source, diagnostic));
        for (final resultDiagnostic in result.diagnostics) {
          recordDiagnostic(resultDiagnostic);
        }
        recordDiagnostic(diagnostic);
      }
    } on Object catch (error) {
      if (!_isCurrentLoadAttempt(attempt)) {
        return;
      }
      _settleUnexpectedLoadFailure(source, error);
    } finally {
      publicationClosed = true;
      final finalization = acceptedFinalization;
      if (finalization != null) {
        _endAcceptedPublicationFinalization(finalization);
      }
    }
  }

  Completer<void> _beginAcceptedPublicationFinalization() {
    final activeFinalization = _acceptedPublicationFinalization;
    if (activeFinalization != null) {
      return activeFinalization;
    }
    final finalization = Completer<void>();
    _acceptedPublicationFinalization = finalization;
    return finalization;
  }

  void _endAcceptedPublicationFinalization(Completer<void> finalization) {
    if (identical(_acceptedPublicationFinalization, finalization)) {
      _acceptedPublicationFinalization = null;
    }
    if (!finalization.isCompleted) {
      finalization.complete();
    }
  }

  void _settleUnexpectedLoadFailure(ModelSource source, Object error) {
    _partTree = const PartTree.empty();
    _materialOverrides.resetAll();
    final diagnostic = ViewerDiagnostic(
      code: ViewerDiagnosticCode.adapterFailure,
      message: 'Model loading failed.',
      details: <String, Object?>{'error': error.toString()},
    );
    _setSettledLoadState(ViewerLoadState.error(source, diagnostic));
    recordDiagnostic(diagnostic);
  }

  bool _isCurrentLoadAttempt(int attempt) => attempt == _activeLoadAttempt;

  void _recordStaleCancellation(ModelLoadResult result) {
    final diagnostic = result.diagnostic;
    if (diagnostic?.code == ViewerDiagnosticCode.modelLoadCancelled) {
      recordDiagnostic(diagnostic!);
    }
  }

  Future<ModelLoadResult> _loadFromSink(
    ViewerCommandSink sink,
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) {
    final load = sink.load(
      source,
      cancellationToken: cancellationToken,
      tryAcceptPublication: tryAcceptPublication,
      onPublicationRejected: onPublicationRejected,
    );
    if (cancellationToken == null) {
      return load;
    }
    return Future.any<ModelLoadResult>(<Future<ModelLoadResult>>[
      load,
      cancellationToken.whenCancelled.then<ModelLoadResult>(
        (_) => ModelLoadResult.failure(
          modelLoadCancellationDiagnostic(
            source,
            cancellationToken,
            stage: 'controller',
          ),
        ),
      ),
    ]);
  }

  void _finishLoadCancellation(
    ModelSource source,
    ModelLoadCancellationToken? cancellationToken, {
    required int attempt,
    ViewerDiagnostic? diagnostic,
    required String stage,
  }) {
    final cancellationDiagnostic = diagnostic ??
        modelLoadCancellationDiagnostic(
          source,
          cancellationToken!,
          stage: stage,
        );
    recordDiagnostic(cancellationDiagnostic);
    if (_isCurrentLoadAttempt(attempt)) {
      _setLoadState(_lastSettledLoadState);
    }
  }

  bool _finishCancellationIfRequested(
    ModelSource source,
    ModelLoadCancellationToken? cancellationToken, {
    required int attempt,
    required String stage,
  }) {
    if (cancellationToken?.isCancelled != true) {
      return false;
    }
    _finishLoadCancellation(
      source,
      cancellationToken,
      attempt: attempt,
      stage: stage,
    );
    return true;
  }

  void _setSettledLoadState(ViewerLoadState state) {
    _lastSettledLoadState = state;
    _setLoadState(state);
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

  Future<void> setPartTextureBinding(
    PartAddress address,
    MaterialTextureSlot slot,
    MaterialTextureBinding binding,
  ) {
    final patch = switch (slot) {
      MaterialTextureSlot.baseColor =>
        MaterialPatch(baseColorTextureBinding: binding),
      MaterialTextureSlot.metallicRoughness =>
        MaterialPatch(metallicRoughnessTextureBinding: binding),
      MaterialTextureSlot.normal =>
        MaterialPatch(normalTextureBinding: binding),
      MaterialTextureSlot.occlusion =>
        MaterialPatch(occlusionTextureBinding: binding),
      MaterialTextureSlot.emissive =>
        MaterialPatch(emissiveTextureBinding: binding),
      MaterialTextureSlot.transmission =>
        MaterialPatch(transmissionTextureBinding: binding),
      MaterialTextureSlot.thickness =>
        MaterialPatch(thicknessTextureBinding: binding),
      MaterialTextureSlot.clearcoat =>
        MaterialPatch(clearcoatTextureBinding: binding),
      MaterialTextureSlot.clearcoatRoughness =>
        MaterialPatch(clearcoatRoughnessTextureBinding: binding),
      MaterialTextureSlot.clearcoatNormal =>
        MaterialPatch(clearcoatNormalTextureBinding: binding),
      MaterialTextureSlot.specular =>
        MaterialPatch(specularTextureBinding: binding),
      MaterialTextureSlot.specularColor =>
        MaterialPatch(specularColorTextureBinding: binding),
    };
    return setPartMaterial(address, patch);
  }

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
    Map<PartAddress, MaterialPatch> corePatches,
    Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>
        extensionPatches,
    ViewerCommandSink sink,
  ) async {
    var appliedAny = false;
    final addresses = <PartAddress>{
      ...corePatches.keys,
      ...extensionPatches.keys,
    };
    for (final address in addresses) {
      final corePatch = corePatches[address];
      if (corePatch != null &&
          await _applyAuthoredMaterialPatch(
            address,
            patch: corePatch,
            sink: sink,
          )) {
        appliedAny = true;
      }
      final groups = extensionPatches[address];
      if (groups == null) {
        continue;
      }
      for (final group in MaterialExtensionPatchGroup.values) {
        final groupPatch = groups[group];
        if (groupPatch == null) {
          continue;
        }
        if (await _applyAuthoredMaterialPatch(
          address,
          patch: groupPatch,
          sink: sink,
        )) {
          appliedAny = true;
        }
      }
    }
    if (appliedAny) {
      sink.requestRenderFrame();
    }
  }

  Future<bool> _applyAuthoredMaterialPatch(
    PartAddress address, {
    required MaterialPatch patch,
    required ViewerCommandSink sink,
  }) async {
    final diagnostics = _validateMaterialPatch(
      address,
      patch,
      support: sink.materialExtensionSupport,
    );
    if (diagnostics.isNotEmpty) {
      for (final diagnostic in diagnostics) {
        recordDiagnostic(diagnostic);
      }
      return false;
    }
    final sinkDiagnostics = await sink.setPartMaterial(address, patch);
    if (sinkDiagnostics.isNotEmpty) {
      for (final diagnostic in sinkDiagnostics) {
        recordDiagnostic(diagnostic);
      }
      return false;
    }
    return true;
  }

  Future<void> _applyLoadInitialMaterialOverrides(
    MaterialOverrideSnapshot snapshot,
    ViewerCommandSink sink,
  ) async {
    for (final entry in snapshot.entries) {
      final diagnostics = _validateMaterialPatch(
        entry.key,
        entry.value,
        support: sink.materialExtensionSupport,
      );
      if (diagnostics.isNotEmpty) {
        for (final diagnostic in diagnostics) {
          recordDiagnostic(diagnostic);
        }
        continue;
      }
      final sinkDiagnostics =
          await sink.setPartMaterial(entry.key, entry.value);
      if (sinkDiagnostics.isNotEmpty) {
        for (final diagnostic in sinkDiagnostics) {
          recordDiagnostic(diagnostic);
        }
        continue;
      }
      _materialOverrides.applyPatch(entry.key, entry.value);
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
    if (patch.baseColorTextureBinding != null) 'baseColorTextureBinding',
    if (patch.metallicRoughnessTexture != null) 'metallicRoughnessTexture',
    if (patch.metallicRoughnessTextureBinding != null)
      'metallicRoughnessTextureBinding',
    if (patch.normalTexture != null) 'normalTexture',
    if (patch.normalTextureBinding != null) 'normalTextureBinding',
    if (patch.emissiveTexture != null) 'emissiveTexture',
    if (patch.emissiveTextureBinding != null) 'emissiveTextureBinding',
    if (patch.occlusionTexture != null) 'occlusionTexture',
    if (patch.occlusionTextureBinding != null) 'occlusionTextureBinding',
    if (patch.effectMask != null) 'effectMask',
    if (patch.transmissionTexture != null) 'transmissionTexture',
    if (patch.transmissionTextureBinding != null) 'transmissionTextureBinding',
    if (patch.thicknessTexture != null) 'thicknessTexture',
    if (patch.thicknessTextureBinding != null) 'thicknessTextureBinding',
    if (patch.clearcoatTexture != null) 'clearcoatTexture',
    if (patch.clearcoatTextureBinding != null) 'clearcoatTextureBinding',
    if (patch.clearcoatRoughnessTexture != null) 'clearcoatRoughnessTexture',
    if (patch.clearcoatRoughnessTextureBinding != null)
      'clearcoatRoughnessTextureBinding',
    if (patch.clearcoatNormalTexture != null) 'clearcoatNormalTexture',
    if (patch.clearcoatNormalTextureBinding != null)
      'clearcoatNormalTextureBinding',
    if (patch.specularTexture != null) 'specularTexture',
    if (patch.specularTextureBinding != null) 'specularTextureBinding',
    if (patch.specularColorTexture != null) 'specularColorTexture',
    if (patch.specularColorTextureBinding != null)
      'specularColorTextureBinding',
  ];
}

@internal
abstract interface class ViewerCommandSink {
  MaterialExtensionSupport get materialExtensionSupport;

  Future<ModelLoadResult> load(
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  });
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
