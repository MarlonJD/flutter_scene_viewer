import 'dart:async';

import 'package:meta/meta.dart';

import 'diagnostics.dart';
import 'model_source.dart';

/// Immutable view of cancellation requested for a single model load.
final class ModelLoadCancellationToken {
  ModelLoadCancellationToken._(this._state);

  final _ModelLoadCancellationState _state;

  bool get isCancelled => _state.reason != null;

  String? get reason => _state.reason;

  Future<void> get whenCancelled => _state.whenCancelled.future;

  /// Registers a synchronously removable listener for package integrations.
  ///
  /// Public callers should normally use [whenCancelled]. Native request
  /// bridges use this seam so a completed request does not retain a callback
  /// until some later cancellation that can no longer affect it.
  @internal
  void Function() registerCancellationListener(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _state.listeners.add(listener);
    var removed = false;
    return () {
      if (removed) {
        return;
      }
      removed = true;
      _state.listeners.remove(listener);
    };
  }

  /// Throws when the caller has cancelled this load at [stage].
  void throwIfCancelled({required String stage}) {
    final cancellationReason = reason;
    if (cancellationReason != null) {
      throw _ModelLoadCancelledException(
        stage: stage,
        reason: cancellationReason,
      );
    }
  }
}

/// Owns cancellation for one model-load operation.
final class ModelLoadCancellationController {
  ModelLoadCancellationController() : _state = _ModelLoadCancellationState();

  final _ModelLoadCancellationState _state;

  late final ModelLoadCancellationToken token =
      ModelLoadCancellationToken._(_state);

  /// Cancels the load once, retaining the first cancellation [reason].
  bool cancel([String reason = 'caller']) {
    if (_state.reason != null || _state.publicationAccepted) {
      return false;
    }
    _state.reason = reason;
    final listeners = List<void Function()>.of(_state.listeners);
    _state.listeners.clear();
    for (final listener in listeners) {
      listener();
    }
    _state.whenCancelled.complete();
    return true;
  }
}

final class _ModelLoadCancellationState {
  final Completer<void> whenCancelled = Completer<void>();
  final Set<void Function()> listeners = <void Function()>{};
  String? reason;
  bool publicationAccepted = false;
}

final class _ModelLoadCancelledException implements Exception {
  const _ModelLoadCancelledException({
    required this.stage,
    required this.reason,
  });

  final String stage;
  final String reason;
}

/// Closes cancellation at the adapter's single live-publication commit gate.
///
/// This remains internal to the package library: callers use only the public
/// token and controller types exported from the package barrel.
bool tryAcceptModelLoadPublication(ModelLoadCancellationToken token) {
  final state = token._state;
  if (state.reason != null || state.publicationAccepted) {
    return false;
  }
  state.publicationAccepted = true;
  return true;
}

ViewerDiagnostic modelLoadCancellationDiagnostic(
  ModelSource source,
  ModelLoadCancellationToken cancellationToken, {
  required String stage,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.modelLoadCancelled,
    message: 'Model load was cancelled by the caller.',
    details: <String, Object?>{
      'source': switch (source) {
        BytesModelSource() => source.debugName ?? 'bytes',
        AssetModelSource() => source.assetPath,
        NetworkModelSource() => source.uri.toString(),
      },
      'stage': stage,
      'reason': cancellationToken.reason ?? 'caller',
      'status': 'cancelled',
    },
  );
}
