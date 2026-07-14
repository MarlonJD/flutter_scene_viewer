import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../diagnostics.dart';
import 'glb_basisu_rewriter.dart';
import 'glb_capability_reader.dart';
import 'glb_decode_budget.dart';
import 'glb_draco_rewriter.dart';

const String kBasisuTextureExtension = 'KHR_texture_basisu';
const String kBasisuInfoPlistKey = 'FlutterSceneViewerBasisuEnabled';
const String kBasisuAndroidManifestKey = 'flutter_scene_viewer_basisu_enabled';
const String kBasisuPluginPackageName = 'flutter_scene_viewer_basisu';
const String kDracoMeshCompressionExtension = 'KHR_draco_mesh_compression';
const String kDracoInfoPlistKey = 'FlutterSceneViewerDracoEnabled';
const String kDracoAndroidManifestKey = 'flutter_scene_viewer_draco_enabled';
const String kDracoPluginPackageName = 'flutter_scene_viewer_draco';
const int _glbMagic = 0x46546C67;
const int _jsonChunkType = 0x4E4F534A;
const int _binChunkType = 0x004E4942;

/// Optional native decoder availability reported by sibling decoder plugins.
final class GlbNativeDecoderAvailability {
  const GlbNativeDecoderAvailability({
    this.capabilities = const GlbDecoderCapabilities(),
    this.diagnosticsByExtension = const <String, ViewerDiagnostic>{},
  });

  final GlbDecoderCapabilities capabilities;
  final Map<String, ViewerDiagnostic> diagnosticsByExtension;

  Iterable<ViewerDiagnostic> get diagnostics => diagnosticsByExtension.values;
}

abstract interface class GlbNativeDecoderProbe {
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  });

  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    String? source,
  });
}

enum GlbNativeDecodeOutputAccounting {
  none,
  opaqueFinalBytes,
  componentPayloadsAccounted,
}

/// Result of rewriting a compressed GLB into importer-ready GLB bytes.
final class GlbNativeDecodeResult {
  const GlbNativeDecodeResult({
    required this.outputAccounting,
    this.bytes,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Uint8List? bytes;
  final List<ViewerDiagnostic> diagnostics;
  final GlbNativeDecodeOutputAccounting outputAccounting;
}

/// Probes the optional native Draco plugin without making it a root dependency.
final class MethodChannelGlbNativeDecoderProbe
    implements GlbNativeDecoderProbe {
  const MethodChannelGlbNativeDecoderProbe({
    MethodChannel channel = const MethodChannel('flutter_scene_viewer/draco'),
    MethodChannel basisuChannel =
        const MethodChannel('flutter_scene_viewer/basisu'),
  })  : _dracoChannel = channel,
        _basisuChannel = basisuChannel;

  final MethodChannel _dracoChannel;
  final MethodChannel _basisuChannel;

  @override
  Future<GlbNativeDecoderAvailability> checkAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    final checks = <GlbNativeDecoderAvailability>[];
    if (requiredExtensions.contains(kDracoMeshCompressionExtension)) {
      checks.add(
        await _checkDracoAvailability(
          requiredExtensions: requiredExtensions,
          source: source,
        ),
      );
    }
    if (requiredExtensions.contains(kBasisuTextureExtension)) {
      checks.add(
        await _checkBasisuAvailability(
          requiredExtensions: requiredExtensions,
          source: source,
        ),
      );
    }
    if (checks.isEmpty) {
      return const GlbNativeDecoderAvailability();
    }
    return _mergeAvailabilities(checks);
  }

  Future<GlbNativeDecoderAvailability> _checkDracoAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    try {
      final result = await _dracoChannel.invokeMapMethod<String, Object?>(
        'getDecoderAvailability',
        <String, Object?>{
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
        },
      );
      return _availabilityFromMethodResult(
        result,
        requiredExtensions: requiredExtensions,
        source: source,
      );
    } on MissingPluginException {
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kDracoMeshCompressionExtension: _dracoUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native Draco decoder plugin is not installed or not registered.',
          ),
        },
      );
    } on PlatformException catch (error) {
      final missingPlugin = error.code == 'channel-error';
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kDracoMeshCompressionExtension: _dracoUnavailableDiagnostic(
            source: source,
            status: missingPlugin ? 'pluginMissing' : 'probeFailed',
            message: missingPlugin
                ? 'Optional native Draco decoder plugin is not installed or not registered.'
                : 'Optional native Draco decoder availability check failed.',
            extraDetails: missingPlugin
                ? const <String, Object?>{}
                : <String, Object?>{'error': error.toString()},
          ),
        },
      );
    } on Object catch (error) {
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kDracoMeshCompressionExtension: _dracoUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native Draco decoder plugin is not installed or not registered.',
            extraDetails: <String, Object?>{'error': error.toString()},
          ),
        },
      );
    }
  }

  Future<GlbNativeDecoderAvailability> _checkBasisuAvailability({
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    try {
      final result = await _basisuChannel.invokeMapMethod<String, Object?>(
        'getDecoderAvailability',
        <String, Object?>{
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
        },
      );
      return _basisuAvailabilityFromMethodResult(
        result,
        requiredExtensions: requiredExtensions,
        source: source,
      );
    } on MissingPluginException {
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kBasisuTextureExtension: _basisuUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native BasisU/KTX2 transcoder plugin is not installed or not registered.',
          ),
        },
      );
    } on PlatformException catch (error) {
      final missingPlugin = error.code == 'channel-error';
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kBasisuTextureExtension: _basisuUnavailableDiagnostic(
            source: source,
            status: missingPlugin ? 'pluginMissing' : 'probeFailed',
            message: missingPlugin
                ? 'Optional native BasisU/KTX2 transcoder plugin is not installed or not registered.'
                : 'Optional native BasisU/KTX2 transcoder availability check failed.',
            extraDetails: missingPlugin
                ? const <String, Object?>{}
                : <String, Object?>{'error': error.toString()},
          ),
        },
      );
    } on Object catch (error) {
      return GlbNativeDecoderAvailability(
        diagnosticsByExtension: <String, ViewerDiagnostic>{
          kBasisuTextureExtension: _basisuUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native BasisU/KTX2 transcoder plugin is not installed or not registered.',
            extraDetails: <String, Object?>{'error': error.toString()},
          ),
        },
      );
    }
  }

  @override
  Future<GlbNativeDecodeResult> decodeGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    String? source,
  }) async {
    var currentBytes = bytes;
    var outputAccounting = GlbNativeDecodeOutputAccounting.none;
    final diagnostics = <ViewerDiagnostic>[];
    final deadline = _NativeDecodeDeadline(budget.decodeTimeout);
    final needsDraco =
        requiredExtensions.contains(kDracoMeshCompressionExtension);
    final needsBasisu = requiredExtensions.contains(kBasisuTextureExtension);
    if (needsDraco) {
      final result = await _decodeDracoGlb(
        bytes: currentBytes,
        requiredExtensions: requiredExtensions,
        budget: budget,
        budgetTracker: budgetTracker,
        deadline: deadline,
        source: source,
      );
      diagnostics.addAll(result.diagnostics);
      final accountingDiagnostic = _nativeStageOutputAccountingDiagnostic(
        result,
        extension: kDracoMeshCompressionExtension,
        source: source,
      );
      if (accountingDiagnostic != null) {
        diagnostics.add(accountingDiagnostic);
        return GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      final decodedBytes = result.bytes;
      if (decodedBytes == null) {
        return GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      currentBytes = decodedBytes;
      outputAccounting = result.outputAccounting;
      if (needsBasisu) {
        final intermediateDiagnostic = _accountIntermediateNativeOutput(
          bytes: currentBytes,
          outputAccounting: outputAccounting,
          budgetTracker: budgetTracker,
          extension: kDracoMeshCompressionExtension,
          source: source,
        );
        if (intermediateDiagnostic != null) {
          diagnostics.add(intermediateDiagnostic);
          return GlbNativeDecodeResult(
            outputAccounting: GlbNativeDecodeOutputAccounting.none,
            diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
          );
        }
      }
    }
    if (needsBasisu) {
      final result = await _decodeBasisuGlb(
        bytes: currentBytes,
        requiredExtensions: requiredExtensions,
        budget: budget,
        budgetTracker: budgetTracker,
        deadline: deadline,
        source: source,
      );
      diagnostics.addAll(result.diagnostics);
      final accountingDiagnostic = _nativeStageOutputAccountingDiagnostic(
        result,
        extension: kBasisuTextureExtension,
        source: source,
      );
      if (accountingDiagnostic != null) {
        diagnostics.add(accountingDiagnostic);
        return GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      final decodedBytes = result.bytes;
      if (decodedBytes == null) {
        return GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      currentBytes = decodedBytes;
      outputAccounting = result.outputAccounting;
    }
    return GlbNativeDecodeResult(
      bytes: currentBytes,
      outputAccounting: outputAccounting == GlbNativeDecodeOutputAccounting.none
          ? GlbNativeDecodeOutputAccounting.opaqueFinalBytes
          : outputAccounting,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }

  Future<GlbNativeDecodeResult> _decodeDracoGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    required _NativeDecodeDeadline deadline,
    String? source,
  }) async {
    try {
      final requestRead = _dracoPrimitiveRequestsFromGlb(
        bytes,
        source: source,
      );
      final requestDiagnostic = requestRead.diagnostic;
      if (requestDiagnostic != null) {
        return GlbNativeDecodeResult(
          outputAccounting: GlbNativeDecodeOutputAccounting.none,
          diagnostics: <ViewerDiagnostic>[requestDiagnostic],
        );
      }
      final remaining = deadline.remainingOrThrow();
      final result = await _dracoChannel.invokeMapMethod<String, Object?>(
        'decodeGlb',
        <String, Object?>{
          'bytes': bytes,
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
          'dracoPrimitives': requestRead.requests,
          'decodeBudget': _nativeDecodeBudgetMap(budget),
          'decodeBudgetState': _nativeDecodeBudgetStateMap(budgetTracker),
        },
      ).timeout(remaining);
      return _decodeResultFromMethodResult(
        result,
        sourceBytes: bytes,
        source: source,
        budget: budget,
        budgetTracker: budgetTracker,
      );
    } on _NativeDecodeDeadlineExpired {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _nativeDecodeTimeoutDiagnostic(
            extension: kDracoMeshCompressionExtension,
            decoder: 'draco',
            source: source,
            timeout: budget.decodeTimeout,
            dispatched: false,
          ),
        ],
      );
    } on TimeoutException {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _nativeDecodeTimeoutDiagnostic(
            extension: kDracoMeshCompressionExtension,
            decoder: 'draco',
            source: source,
            timeout: budget.decodeTimeout,
            dispatched: true,
          ),
        ],
      );
    } on MissingPluginException {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _dracoUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native Draco decoder plugin is not installed or not registered.',
          ),
        ],
      );
    } on PlatformException catch (error) {
      final missingPlugin = error.code == 'channel-error';
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _dracoUnavailableDiagnostic(
            source: source,
            status: missingPlugin ? 'pluginMissing' : 'decodeFailed',
            message: missingPlugin
                ? 'Optional native Draco decoder plugin is not installed or not registered.'
                : 'Native Draco decoder failed to rewrite the GLB.',
            extraDetails: missingPlugin
                ? const <String, Object?>{}
                : <String, Object?>{'error': error.toString()},
          ),
        ],
      );
    } on Object catch (error) {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _dracoUnavailableDiagnostic(
            source: source,
            status: 'decodeFailed',
            message: 'Native Draco decoder failed to rewrite the GLB.',
            extraDetails: <String, Object?>{'error': error.toString()},
          ),
        ],
      );
    }
  }

  Future<GlbNativeDecodeResult> _decodeBasisuGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    required GlbDecodeBudget budget,
    required GlbDecodeBudgetTracker budgetTracker,
    required _NativeDecodeDeadline deadline,
    String? source,
  }) async {
    try {
      final remaining = deadline.remainingOrThrow();
      final result = await _basisuChannel.invokeMapMethod<String, Object?>(
        'decodeGlb',
        <String, Object?>{
          'bytes': bytes,
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
          'basisuImages': _basisuImageRequestsFromGlb(bytes),
          'decodeBudget': _nativeDecodeBudgetMap(budget),
          'decodeBudgetState': _nativeDecodeBudgetStateMap(budgetTracker),
        },
      ).timeout(remaining);
      return _basisuDecodeResultFromMethodResult(
        result,
        sourceBytes: bytes,
        source: source,
        budget: budget,
        budgetTracker: budgetTracker,
      );
    } on _NativeDecodeDeadlineExpired {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _nativeDecodeTimeoutDiagnostic(
            extension: kBasisuTextureExtension,
            decoder: 'basisu',
            source: source,
            timeout: budget.decodeTimeout,
            dispatched: false,
          ),
        ],
      );
    } on TimeoutException {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _nativeDecodeTimeoutDiagnostic(
            extension: kBasisuTextureExtension,
            decoder: 'basisu',
            source: source,
            timeout: budget.decodeTimeout,
            dispatched: true,
          ),
        ],
      );
    } on MissingPluginException {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _basisuUnavailableDiagnostic(
            source: source,
            status: 'pluginMissing',
            message:
                'Optional native BasisU/KTX2 transcoder plugin is not installed or not registered.',
          ),
        ],
      );
    } on PlatformException catch (error) {
      final missingPlugin = error.code == 'channel-error';
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _basisuUnavailableDiagnostic(
            source: source,
            status: missingPlugin ? 'pluginMissing' : 'decodeFailed',
            message: missingPlugin
                ? 'Optional native BasisU/KTX2 transcoder plugin is not installed or not registered.'
                : 'Native BasisU/KTX2 transcoder failed to rewrite the GLB.',
            extraDetails: missingPlugin
                ? const <String, Object?>{}
                : <String, Object?>{'error': error.toString()},
          ),
        ],
      );
    } on Object catch (error) {
      return GlbNativeDecodeResult(
        outputAccounting: GlbNativeDecodeOutputAccounting.none,
        diagnostics: <ViewerDiagnostic>[
          _basisuUnavailableDiagnostic(
            source: source,
            status: 'decodeFailed',
            message: 'Native BasisU/KTX2 transcoder failed to rewrite the GLB.',
            extraDetails: <String, Object?>{'error': error.toString()},
          ),
        ],
      );
    }
  }
}

final class _NativeDecodeDeadline {
  _NativeDecodeDeadline(this.timeout) : _stopwatch = Stopwatch()..start();

  final Duration timeout;
  final Stopwatch _stopwatch;

  Duration remainingOrThrow() {
    final remainingMicroseconds =
        timeout.inMicroseconds - _stopwatch.elapsedMicroseconds;
    if (remainingMicroseconds <= 0) {
      throw const _NativeDecodeDeadlineExpired();
    }
    return Duration(microseconds: remainingMicroseconds);
  }
}

final class _NativeDecodeDeadlineExpired implements Exception {
  const _NativeDecodeDeadlineExpired();
}

ViewerDiagnostic _nativeDecodeTimeoutDiagnostic({
  required String extension,
  required String decoder,
  required String? source,
  required Duration timeout,
  required bool dispatched,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.modelLoadTimeout,
    message: 'Native $decoder decoding exceeded the configured decode timeout.',
    details: <String, Object?>{
      'source': source,
      'extension': extension,
      'decoder': decoder,
      'required': true,
      'stage': 'nativeDecodeMethodChannel',
      'limitation': 'nativeDecodeDeadline',
      'status': 'timedOut',
      'timeoutMilliseconds': timeout.inMilliseconds,
      'nativeDispatch': dispatched ? 'started' : 'notStarted',
      'nativeResourceRelease': dispatched ? 'notGuaranteed' : 'notApplicable',
      'lateResult': dispatched ? 'discardedByDart' : 'notApplicable',
      'fallback': 'diagnosticOnly',
    },
  );
}

ViewerDiagnostic? _nativeStageOutputAccountingDiagnostic(
  GlbNativeDecodeResult result, {
  required String extension,
  required String? source,
}) {
  final hasBytes = result.bytes != null;
  final hasAccounting =
      result.outputAccounting != GlbNativeDecodeOutputAccounting.none;
  if (hasBytes == hasAccounting) {
    return null;
  }
  return _nativeOutputAccountingDiagnostic(
    extension: extension,
    source: source,
    outputAccounting: result.outputAccounting,
    stage: 'nativeDecodedGlbOutput',
    hasBytes: hasBytes,
  );
}

ViewerDiagnostic? _accountIntermediateNativeOutput({
  required Uint8List bytes,
  required GlbNativeDecodeOutputAccounting outputAccounting,
  required GlbDecodeBudgetTracker budgetTracker,
  required String extension,
  required String? source,
}) {
  if (outputAccounting == GlbNativeDecodeOutputAccounting.none) {
    return _nativeOutputAccountingDiagnostic(
      extension: extension,
      source: source,
      outputAccounting: outputAccounting,
      stage: 'nativeDecodedGlbIntermediateOutput',
      hasBytes: true,
    );
  }
  try {
    switch (outputAccounting) {
      case GlbNativeDecodeOutputAccounting.none:
        break;
      case GlbNativeDecodeOutputAccounting.opaqueFinalBytes:
        budgetTracker.reserveNativeOutputBytes(
          bytes.lengthInBytes,
          stage: 'nativeDecodedGlbIntermediateOutput',
        );
      case GlbNativeDecodeOutputAccounting.componentPayloadsAccounted:
        budgetTracker.checkNativeOutputBytes(
          bytes.lengthInBytes,
          stage: 'nativeDecodedGlbIntermediateOutput',
        );
    }
  } on GlbDecodeBudgetExceeded catch (error) {
    return _nativeOutputBudgetDiagnostic(
      error,
      extension: extension,
      source: source,
    );
  }
  return null;
}

GlbNativeDecoderAvailability _mergeAvailabilities(
  List<GlbNativeDecoderAvailability> checks,
) {
  var capabilities = const GlbDecoderCapabilities();
  final diagnosticsByExtension = <String, ViewerDiagnostic>{};
  for (final check in checks) {
    capabilities = capabilities.merge(check.capabilities);
    diagnosticsByExtension.addAll(check.diagnosticsByExtension);
  }
  return GlbNativeDecoderAvailability(
    capabilities: capabilities,
    diagnosticsByExtension:
        Map<String, ViewerDiagnostic>.unmodifiable(diagnosticsByExtension),
  );
}

ViewerDiagnostic _nativeOutputAccountingDiagnostic({
  required String extension,
  required String? source,
  required GlbNativeDecodeOutputAccounting outputAccounting,
  required String stage,
  required bool hasBytes,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Native decoder returned inconsistent output accounting.',
    details: <String, Object?>{
      'source': source,
      'extension': extension,
      'decoder':
          extension == kDracoMeshCompressionExtension ? 'draco' : 'basisu',
      'required': true,
      'limitation': 'nativeDecodeOutputAccounting',
      'status': 'malformedOutput',
      'stage': stage,
      'field': 'outputAccounting',
      'limit':
          hasBytes ? 'opaqueFinalBytes or componentPayloadsAccounted' : 'none',
      'actual': outputAccounting.name,
      'bytesPresent': hasBytes,
    },
  );
}

ViewerDiagnostic _nativeOutputBudgetDiagnostic(
  GlbDecodeBudgetExceeded error, {
  required String extension,
  required String? source,
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Native decoded GLB exceeded the configured decode budget.',
    details: <String, Object?>{
      'source': source,
      'extension': extension,
      'decoder':
          extension == kDracoMeshCompressionExtension ? 'draco' : 'basisu',
      'required': true,
      'limitation': 'decodeBudget',
      'status': error.status,
      'stage': error.stage,
      'field': error.field,
      'limit': error.limit,
      'actual': error.actual,
      'actualExact': error.actualExact,
      'actualExceedsMaxSafeInteger': error.actualExceedsMaxSafeInteger,
      if (error.actualLowerBound != null)
        'actualLowerBound': error.actualLowerBound,
      if (error.operands.isNotEmpty) 'operands': error.operands,
    },
  );
}

GlbNativeDecoderAvailability _availabilityFromMethodResult(
  Map<String, Object?>? result, {
  required Set<String> requiredExtensions,
  required String? source,
}) {
  final capabilities = _capabilitiesFromValue(result?['capabilities']);
  final diagnosticsByExtension = <String, ViewerDiagnostic>{};
  final diagnostics = result?['diagnostics'];
  if (diagnostics is List) {
    for (final rawDiagnostic in diagnostics) {
      final diagnostic = _diagnosticFromValue(rawDiagnostic);
      final extension = diagnostic?.details['extension'];
      if (diagnostic != null && extension is String) {
        diagnosticsByExtension[extension] = diagnostic;
      }
    }
  }
  if (requiredExtensions.contains(kDracoMeshCompressionExtension) &&
      !capabilities.dracoMeshCompression &&
      !diagnosticsByExtension.containsKey(kDracoMeshCompressionExtension)) {
    diagnosticsByExtension[kDracoMeshCompressionExtension] =
        _dracoUnavailableDiagnostic(
      source: source,
      status: 'nativeLibraryUnavailable',
      message: 'Optional native Draco decoder is not available.',
    );
  }
  return GlbNativeDecoderAvailability(
    capabilities: capabilities,
    diagnosticsByExtension:
        Map<String, ViewerDiagnostic>.unmodifiable(diagnosticsByExtension),
  );
}

GlbNativeDecoderAvailability _basisuAvailabilityFromMethodResult(
  Map<String, Object?>? result, {
  required Set<String> requiredExtensions,
  required String? source,
}) {
  final capabilities = _capabilitiesFromValue(result?['capabilities']);
  final diagnosticsByExtension = <String, ViewerDiagnostic>{};
  final diagnostics = result?['diagnostics'];
  if (diagnostics is List) {
    for (final rawDiagnostic in diagnostics) {
      final diagnostic = _diagnosticFromValue(rawDiagnostic);
      final extension = diagnostic?.details['extension'];
      if (diagnostic != null && extension is String) {
        diagnosticsByExtension[extension] = diagnostic;
      }
    }
  }
  if (requiredExtensions.contains(kBasisuTextureExtension) &&
      !capabilities.textureBasisu &&
      !diagnosticsByExtension.containsKey(kBasisuTextureExtension)) {
    diagnosticsByExtension[kBasisuTextureExtension] =
        _basisuUnavailableDiagnostic(
      source: source,
      status: 'nativeLibraryUnavailable',
      message: 'Optional native BasisU/KTX2 transcoder is not available.',
    );
  }
  return GlbNativeDecoderAvailability(
    capabilities: capabilities,
    diagnosticsByExtension:
        Map<String, ViewerDiagnostic>.unmodifiable(diagnosticsByExtension),
  );
}

GlbNativeDecodeResult _decodeResultFromMethodResult(
  Map<String, Object?>? result, {
  required Uint8List sourceBytes,
  required String? source,
  required GlbDecodeBudget budget,
  required GlbDecodeBudgetTracker budgetTracker,
}) {
  final diagnostics = <ViewerDiagnostic>[];
  final rawDiagnostics = result?['diagnostics'];
  if (rawDiagnostics is List) {
    for (final rawDiagnostic in rawDiagnostics) {
      final diagnostic = _diagnosticFromValue(rawDiagnostic);
      if (diagnostic != null) {
        diagnostics.add(diagnostic);
      }
    }
  }
  final bytes = _bytesFromValue(result?['bytes']);
  if (bytes != null) {
    return GlbNativeDecodeResult(
      bytes: bytes,
      outputAccounting: GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }
  final decodedPrimitives = _decodedPrimitivesFromValue(
    result?['decodedPrimitives'],
  );
  if (decodedPrimitives.isNotEmpty) {
    final rewrite = rewriteDracoCompressedGlb(
      sourceBytes,
      decodedPrimitives: decodedPrimitives,
      debugName: source,
      budget: budget,
      budgetTracker: budgetTracker,
    );
    return GlbNativeDecodeResult(
      bytes: rewrite.bytes,
      outputAccounting: rewrite.bytes == null
          ? GlbNativeDecodeOutputAccounting.none
          : GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(<ViewerDiagnostic>[
        ...diagnostics,
        ...rewrite.diagnostics,
      ]),
    );
  }
  if (diagnostics.isEmpty) {
    diagnostics.add(
      _dracoUnavailableDiagnostic(
        source: source,
        status: 'decodeFailed',
        message: 'Native Draco decoder did not return decoded GLB bytes.',
      ),
    );
  }
  return GlbNativeDecodeResult(
    outputAccounting: GlbNativeDecodeOutputAccounting.none,
    diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
  );
}

GlbNativeDecodeResult _basisuDecodeResultFromMethodResult(
  Map<String, Object?>? result, {
  required Uint8List sourceBytes,
  required String? source,
  required GlbDecodeBudget budget,
  required GlbDecodeBudgetTracker budgetTracker,
}) {
  final diagnostics = <ViewerDiagnostic>[];
  final rawDiagnostics = result?['diagnostics'];
  if (rawDiagnostics is List) {
    for (final rawDiagnostic in rawDiagnostics) {
      final diagnostic = _diagnosticFromValue(rawDiagnostic);
      if (diagnostic != null) {
        diagnostics.add(diagnostic);
      }
    }
  }
  final bytes = _bytesFromValue(result?['bytes']);
  if (bytes != null) {
    return GlbNativeDecodeResult(
      bytes: bytes,
      outputAccounting: GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }
  final decodedImages = _decodedBasisuImagesFromValue(
    result?['decodedImages'],
  );
  if (decodedImages.isNotEmpty) {
    final rewrite = rewriteBasisuTexturesInGlb(
      sourceBytes,
      decodedImages: decodedImages,
      debugName: source,
      budget: budget,
      budgetTracker: budgetTracker,
    );
    return GlbNativeDecodeResult(
      bytes: rewrite.bytes,
      outputAccounting: rewrite.bytes == null
          ? GlbNativeDecodeOutputAccounting.none
          : GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(<ViewerDiagnostic>[
        ...diagnostics,
        ...rewrite.diagnostics,
      ]),
    );
  }
  if (diagnostics.isEmpty) {
    diagnostics.add(
      _basisuUnavailableDiagnostic(
        source: source,
        status: 'decodeFailed',
        message:
            'Native BasisU/KTX2 transcoder did not return decoded GLB bytes.',
      ),
    );
  }
  return GlbNativeDecodeResult(
    outputAccounting: GlbNativeDecodeOutputAccounting.none,
    diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
  );
}

GlbDecoderCapabilities _capabilitiesFromValue(Object? value) {
  if (value is! Map) {
    return const GlbDecoderCapabilities();
  }
  return GlbDecoderCapabilities(
    dracoMeshCompression: value['dracoMeshCompression'] == true,
    meshoptCompression: value['meshoptCompression'] == true,
    textureBasisu: value['textureBasisu'] == true,
  );
}

ViewerDiagnostic? _diagnosticFromValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  final rawCode = value['code'];
  final message = value['message'];
  if (rawCode is! String || message is! String) {
    return null;
  }
  ViewerDiagnosticCode? code;
  for (final item in ViewerDiagnosticCode.values) {
    if (item.name == rawCode) {
      code = item;
      break;
    }
  }
  final diagnosticCode = code;
  if (diagnosticCode == null) {
    return null;
  }
  return ViewerDiagnostic(
    code: diagnosticCode,
    message: message,
    details: _objectMap(value['details']),
  );
}

Uint8List? _bytesFromValue(Object? value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  return null;
}

List<GlbDecodedDracoPrimitive> _decodedPrimitivesFromValue(Object? value) {
  if (value is! List) {
    return const <GlbDecodedDracoPrimitive>[];
  }
  final decoded = <GlbDecodedDracoPrimitive>[];
  for (final rawPrimitive in value) {
    if (rawPrimitive is! Map) {
      continue;
    }
    final meshIndex = rawPrimitive['meshIndex'];
    final primitiveIndex = rawPrimitive['primitiveIndex'];
    final rawAttributes = rawPrimitive['attributes'];
    if (meshIndex is! int || primitiveIndex is! int || rawAttributes is! Map) {
      continue;
    }
    final attributes = <String, Uint8List>{};
    for (final entry in rawAttributes.entries) {
      final key = entry.key;
      final bytes = _bytesFromValue(entry.value);
      if (key is String && bytes != null) {
        attributes[key] = bytes;
      }
    }
    final indices = _bytesFromValue(rawPrimitive['indices']);
    decoded.add(
      GlbDecodedDracoPrimitive(
        meshIndex: meshIndex,
        primitiveIndex: primitiveIndex,
        attributes: Map<String, Uint8List>.unmodifiable(attributes),
        indices: indices,
      ),
    );
  }
  return List<GlbDecodedDracoPrimitive>.unmodifiable(decoded);
}

List<GlbDecodedBasisuImage> _decodedBasisuImagesFromValue(Object? value) {
  if (value is! List) {
    return const <GlbDecodedBasisuImage>[];
  }
  final decoded = <GlbDecodedBasisuImage>[];
  for (final rawImage in value) {
    if (rawImage is! Map) {
      continue;
    }
    final imageIndex = rawImage['imageIndex'];
    final mimeType = rawImage['mimeType'];
    final width = rawImage['width'];
    final height = rawImage['height'];
    final bytes = _bytesFromValue(rawImage['bytes']);
    if (bytes != null) {
      decoded.add(
        GlbDecodedBasisuImage(
          imageIndex: imageIndex is int ? imageIndex : -1,
          mimeType: mimeType is String ? mimeType : '',
          width: width is int ? width : -1,
          height: height is int ? height : -1,
          bytes: bytes,
        ),
      );
    }
  }
  return List<GlbDecodedBasisuImage>.unmodifiable(decoded);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

_DracoNativeRequestReadResult _dracoPrimitiveRequestsFromGlb(
  Uint8List bytes, {
  required String? source,
}) {
  final glb = _readGlbForNativeDecode(bytes);
  final json = glb?.json;
  final bin = glb?.bin;
  if (json == null || bin == null) {
    return const _DracoNativeRequestReadResult();
  }
  final bufferViews = _list(json['bufferViews']);
  final accessors = _list(json['accessors']);
  final meshes = _list(json['meshes']);
  if (bufferViews == null || accessors == null || meshes == null) {
    return const _DracoNativeRequestReadResult();
  }

  final requests = <Object?>[];
  for (var meshIndex = 0; meshIndex < meshes.length; meshIndex += 1) {
    final primitives = _list(_map(meshes[meshIndex])?['primitives']);
    if (primitives == null) {
      continue;
    }
    for (var primitiveIndex = 0;
        primitiveIndex < primitives.length;
        primitiveIndex += 1) {
      final primitive = _map(primitives[primitiveIndex]);
      final draco =
          _map(_map(primitive?['extensions'])?[kDracoMeshCompressionExtension]);
      if (primitive == null || draco == null) {
        continue;
      }
      final authoredMode = primitive['mode'];
      if (authoredMode != null && authoredMode != 4) {
        return _DracoNativeRequestReadResult(
          diagnostic: _dracoNativePrimitiveModeDiagnostic(
            source: source,
            json: json,
            field: 'meshes[$meshIndex].primitives[$primitiveIndex].mode',
            actual: authoredMode,
          ),
        );
      }
      final bufferViewIndex = _intValue(draco['bufferView']);
      final compressedBytes = _bufferViewBytes(
        bufferViews,
        bin,
        bufferViewIndex,
      );
      final compressedAttributes = _map(draco['attributes']);
      final primitiveAttributes = _map(primitive['attributes']);
      if (compressedBytes == null ||
          compressedAttributes == null ||
          primitiveAttributes == null) {
        continue;
      }

      final attributes = <String, Object?>{};
      final attributeAccessors = <String, Object?>{};
      for (final entry in compressedAttributes.entries) {
        final name = entry.key;
        final dracoAttributeId = _intValue(entry.value);
        if (dracoAttributeId == null ||
            dracoAttributeId < 0 ||
            dracoAttributeId > 0xffffffff) {
          return _DracoNativeRequestReadResult(
            diagnostic: _dracoNativeRequestDiagnostic(
              source: source,
              json: json,
              field:
                  'meshes[$meshIndex].primitives[$primitiveIndex].extensions.$kDracoMeshCompressionExtension.attributes.$name',
              actual: entry.value,
              attribute: name,
            ),
          );
        }
        attributes[name] = dracoAttributeId;
      }
      int? vertexAccessorIndex;
      for (final entry in primitiveAttributes.entries) {
        final accessorIndex = _intValue(entry.value);
        if (accessorIndex == null ||
            accessorIndex < 0 ||
            accessorIndex >= accessors.length) {
          return _DracoNativeRequestReadResult(
            diagnostic: _dracoNativeRequestDiagnostic(
              source: source,
              json: json,
              field:
                  'meshes[$meshIndex].primitives[$primitiveIndex].attributes.${entry.key}',
              actual: entry.value,
              attribute: entry.key,
            ),
          );
        }
        final accessorRead = _nativeDracoAccessorSchema(
          accessors[accessorIndex],
          accessorIndex: accessorIndex,
          indices: false,
        );
        if (accessorRead.schema == null) {
          return _DracoNativeRequestReadResult(
            diagnostic: _dracoNativeRequestDiagnostic(
              source: source,
              json: json,
              field: accessorRead.field!,
              actual: accessorRead.actual,
              accessorIndex: accessorIndex,
              attribute: entry.key,
            ),
          );
        }
        attributeAccessors[entry.key] = accessorRead.schema;
        if (vertexAccessorIndex == null || entry.key == 'POSITION') {
          vertexAccessorIndex = accessorIndex;
        }
      }

      Map<String, Object?>? indicesAccessor;
      if (primitive.containsKey('indices')) {
        final accessorIndex = _intValue(primitive['indices']);
        if (accessorIndex == null ||
            accessorIndex < 0 ||
            accessorIndex >= accessors.length) {
          return _DracoNativeRequestReadResult(
            diagnostic: _dracoNativeRequestDiagnostic(
              source: source,
              json: json,
              field: 'meshes[$meshIndex].primitives[$primitiveIndex].indices',
              actual: primitive['indices'],
            ),
          );
        }
        final accessorRead = _nativeDracoAccessorSchema(
          accessors[accessorIndex],
          accessorIndex: accessorIndex,
          indices: true,
        );
        if (accessorRead.schema == null) {
          return _DracoNativeRequestReadResult(
            diagnostic: _dracoNativeRequestDiagnostic(
              source: source,
              json: json,
              field: accessorRead.field!,
              actual: accessorRead.actual,
              accessorIndex: accessorIndex,
            ),
          );
        }
        indicesAccessor = accessorRead.schema;
      }

      requests.add(<String, Object?>{
        'meshIndex': meshIndex,
        'primitiveIndex': primitiveIndex,
        'bufferView': bufferViewIndex,
        'compressedBytes': compressedBytes,
        'attributes': attributes,
        'attributeAccessors': attributeAccessors,
        'vertexAccessorIndex': vertexAccessorIndex,
        'indicesAccessor': indicesAccessor,
      });
    }
  }
  return _DracoNativeRequestReadResult(
    requests: List<Object?>.unmodifiable(requests),
  );
}

ViewerDiagnostic _dracoNativePrimitiveModeDiagnostic({
  required String? source,
  required Map<String, Object?> json,
  required String field,
  required Object actual,
}) {
  final requiredExtensions = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'The native Draco bridge only preserves TRIANGLES topology.',
    details: <String, Object?>{
      'source': source,
      'extension': kDracoMeshCompressionExtension,
      'decoder': 'draco',
      'required':
          requiredExtensions?.contains(kDracoMeshCompressionExtension) ?? true,
      'limitation': 'dracoPrimitiveMode',
      'status': 'unsupportedLayout',
      'stage': 'dracoNativeRequestPreflight',
      'field': field,
      'limit': 4,
      'actual': actual,
    },
  );
}

Map<String, Object?> _nativeDecodeBudgetMap(GlbDecodeBudget budget) {
  return <String, Object?>{
    'maxJsonBytes': budget.maxJsonBytes,
    'maxTotalDecodedBytes': budget.maxTotalDecodedBytes,
    'maxAccessors': budget.maxAccessors,
    'maxVertices': budget.maxVertices,
    'maxIndices': budget.maxIndices,
    'maxTexturePixels': budget.maxTexturePixels,
    'maxNativeOutputBytes': budget.maxNativeOutputBytes,
  };
}

Map<String, Object?> _nativeDecodeBudgetStateMap(
  GlbDecodeBudgetTracker tracker,
) {
  return <String, Object?>{
    'totalDecodedBytes': tracker.totalDecodedBytes,
    'nativeOutputBytes': tracker.nativeOutputBytes,
    'accessors': tracker.accessors,
    'vertices': tracker.vertices,
    'indices': tracker.indices,
    'texturePixels': tracker.texturePixels,
  };
}

List<Object?> _basisuImageRequestsFromGlb(Uint8List bytes) {
  final glb = _readGlbForNativeDecode(bytes);
  final json = glb?.json;
  final bin = glb?.bin;
  if (json == null || bin == null) {
    return const <Object?>[];
  }
  final textures = _list(json['textures']);
  final images = _list(json['images']);
  final bufferViews = _list(json['bufferViews']);
  if (textures == null || images == null || bufferViews == null) {
    return const <Object?>[];
  }

  const redChannel = 1;
  const greenChannel = 2;
  const blueChannel = 4;
  const alphaChannel = 8;
  const rgbChannels = redChannel | greenChannel | blueChannel;
  final textureColorChannels = List<int>.filled(textures.length, 0);
  final textureNonColorChannels = List<int>.filled(textures.length, 0);
  void addTextureInfoChannels(
    Object? rawTextureInfo, {
    int colorChannels = 0,
    int nonColorChannels = 0,
  }) {
    final textureInfo = _map(rawTextureInfo);
    final textureIndex = _intValue(textureInfo?['index']);
    if (textureIndex == null ||
        textureIndex < 0 ||
        textureIndex >= textureColorChannels.length) {
      return;
    }
    textureColorChannels[textureIndex] |= colorChannels;
    textureNonColorChannels[textureIndex] |= nonColorChannels;
  }

  for (final rawMaterial in _list(json['materials']) ?? const <Object?>[]) {
    final material = _map(rawMaterial);
    if (material == null) {
      continue;
    }
    final pbr = _map(material['pbrMetallicRoughness']);
    final alphaMode = material['alphaMode'];
    final baseColorUsesAlpha = alphaMode == 'MASK' || alphaMode == 'BLEND';
    addTextureInfoChannels(
      pbr?['baseColorTexture'],
      colorChannels: rgbChannels,
      nonColorChannels: baseColorUsesAlpha ? alphaChannel : 0,
    );
    addTextureInfoChannels(
      pbr?['metallicRoughnessTexture'],
      nonColorChannels: greenChannel | blueChannel,
    );
    addTextureInfoChannels(
      material['emissiveTexture'],
      colorChannels: rgbChannels,
    );
    addTextureInfoChannels(
      material['normalTexture'],
      nonColorChannels: rgbChannels,
    );
    addTextureInfoChannels(
      material['occlusionTexture'],
      nonColorChannels: redChannel,
    );

    final extensions = _map(material['extensions']);
    final specular = _map(extensions?['KHR_materials_specular']);
    addTextureInfoChannels(
      specular?['specularColorTexture'],
      colorChannels: rgbChannels,
    );
    addTextureInfoChannels(
      specular?['specularTexture'],
      nonColorChannels: alphaChannel,
    );
    final clearcoat = _map(extensions?['KHR_materials_clearcoat']);
    addTextureInfoChannels(
      clearcoat?['clearcoatTexture'],
      nonColorChannels: rgbChannels,
    );
    addTextureInfoChannels(
      clearcoat?['clearcoatRoughnessTexture'],
      nonColorChannels: rgbChannels,
    );
    addTextureInfoChannels(
      clearcoat?['clearcoatNormalTexture'],
      nonColorChannels: rgbChannels,
    );
    final transmission = _map(extensions?['KHR_materials_transmission']);
    addTextureInfoChannels(
      transmission?['transmissionTexture'],
      nonColorChannels: redChannel,
    );
    final volume = _map(extensions?['KHR_materials_volume']);
    addTextureInfoChannels(
      volume?['thicknessTexture'],
      nonColorChannels: greenChannel,
    );
  }

  final imageColorChannels = <int, int>{};
  final imageNonColorChannels = <int, int>{};
  for (var textureIndex = 0;
      textureIndex < textures.length;
      textureIndex += 1) {
    final texture = _map(textures[textureIndex]);
    final basisu = _map(_map(texture?['extensions'])?[kBasisuTextureExtension]);
    final imageIndex = _intValue(basisu?['source']);
    if (imageIndex == null || imageIndex < 0 || imageIndex >= images.length) {
      continue;
    }
    imageColorChannels[imageIndex] = (imageColorChannels[imageIndex] ?? 0) |
        textureColorChannels[textureIndex];
    imageNonColorChannels[imageIndex] =
        (imageNonColorChannels[imageIndex] ?? 0) |
            textureNonColorChannels[textureIndex];
  }

  final requests = <Object?>[];
  final requestedImageIndices = <int>{};
  for (var textureIndex = 0;
      textureIndex < textures.length;
      textureIndex += 1) {
    final texture = _map(textures[textureIndex]);
    final basisu = _map(_map(texture?['extensions'])?[kBasisuTextureExtension]);
    if (basisu == null) {
      continue;
    }
    final imageIndex = _intValue(basisu['source']);
    if (imageIndex == null || imageIndex < 0 || imageIndex >= images.length) {
      continue;
    }
    if (!requestedImageIndices.add(imageIndex)) {
      continue;
    }
    final image = _map(images[imageIndex]);
    final bufferViewIndex = _intValue(image?['bufferView']);
    final imageBytes = _bufferViewBytes(bufferViews, bin, bufferViewIndex);
    if (imageBytes == null) {
      continue;
    }
    final colorChannels = imageColorChannels[imageIndex] ?? 0;
    final nonColorChannels = imageNonColorChannels[imageIndex] ?? 0;
    final sampledChannels = colorChannels | nonColorChannels;
    requests.add(<String, Object?>{
      'textureIndex': textureIndex,
      'imageIndex': imageIndex,
      'usageRole': colorChannels != 0 && (nonColorChannels & rgbChannels) != 0
          ? 'ambiguous'
          : colorChannels != 0
              ? 'color'
              : nonColorChannels != 0
                  ? 'nonColor'
                  : 'structuralOnly',
      'channelLayout': sampledChannels & alphaChannel != 0
          ? 'rgba'
          : sampledChannels & blueChannel != 0
              ? 'rgb'
              : sampledChannels & greenChannel != 0
                  ? 'rg'
                  : sampledChannels & redChannel != 0
                      ? 'r'
                      : 'structuralOnly',
      'bufferView': bufferViewIndex,
      'mimeType': image?['mimeType'],
      'uri': image?['uri'],
      'bytes': imageBytes,
    });
  }
  return List<Object?>.unmodifiable(requests);
}

_NativeDracoAccessorRead _nativeDracoAccessorSchema(
  Object? rawAccessor, {
  required int accessorIndex,
  required bool indices,
}) {
  final accessor = _map(rawAccessor);
  if (accessor == null) {
    return _NativeDracoAccessorRead.invalid(
      field: 'accessors[$accessorIndex]',
      actual: rawAccessor,
    );
  }
  final rawComponentType = accessor['componentType'];
  final componentType = _intValue(rawComponentType);
  final componentBytes = switch (componentType) {
    5120 || 5121 => 1,
    5122 || 5123 => 2,
    5125 || 5126 => 4,
    _ => null,
  };
  if (componentBytes == null ||
      (indices &&
          componentType != 5121 &&
          componentType != 5123 &&
          componentType != 5125)) {
    return _NativeDracoAccessorRead.invalid(
      field: 'accessors[$accessorIndex].componentType',
      actual: rawComponentType,
    );
  }
  final type = accessor['type'];
  final componentCount = switch (type) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    _ => null,
  };
  if (componentCount == null || (indices && type != 'SCALAR')) {
    return _NativeDracoAccessorRead.invalid(
      field: 'accessors[$accessorIndex].type',
      actual: type,
    );
  }
  final rawCount = accessor['count'];
  final count = _intValue(rawCount);
  final bytesPerElement = componentBytes * componentCount;
  if (count == null ||
      count <= 0 ||
      count > kGlbMaxSafeInteger ||
      count > kGlbMaxSafeInteger ~/ bytesPerElement) {
    return _NativeDracoAccessorRead.invalid(
      field: 'accessors[$accessorIndex].count',
      actual: rawCount,
    );
  }
  final normalized = accessor['normalized'];
  if (normalized != null && normalized is! bool) {
    return _NativeDracoAccessorRead.invalid(
      field: 'accessors[$accessorIndex].normalized',
      actual: normalized,
    );
  }
  return _NativeDracoAccessorRead(<String, Object?>{
    'accessorIndex': accessorIndex,
    'componentType': componentType,
    'type': type,
    'count': count,
    'normalized': normalized == true,
  });
}

ViewerDiagnostic _dracoNativeRequestDiagnostic({
  required String? source,
  required Map<String, Object?> json,
  required String field,
  required Object? actual,
  int? accessorIndex,
  String? attribute,
}) {
  final requiredExtensions = _list(json['extensionsRequired']);
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Could not build the native Draco decode request.',
    details: <String, Object?>{
      'source': source,
      'extension': kDracoMeshCompressionExtension,
      'decoder': 'draco',
      'required':
          requiredExtensions?.contains(kDracoMeshCompressionExtension) ?? true,
      'limitation': 'dracoAccessorSchema',
      'status': 'invalidMetadata',
      'stage': 'dracoNativeRequestPreflight',
      'field': field,
      if (accessorIndex != null) 'accessorIndex': accessorIndex,
      if (attribute != null) 'attribute': attribute,
      'actual': actual,
    },
  );
}

Uint8List? _bufferViewBytes(
  List<Object?> bufferViews,
  Uint8List bin,
  int? bufferViewIndex,
) {
  if (bufferViewIndex == null ||
      bufferViewIndex < 0 ||
      bufferViewIndex >= bufferViews.length) {
    return null;
  }
  final bufferView = _map(bufferViews[bufferViewIndex]);
  if (_intValue(bufferView?['buffer']) != 0) {
    return null;
  }
  final byteOffset = _intValue(bufferView?['byteOffset']) ?? 0;
  final byteLength = _intValue(bufferView?['byteLength']);
  if (byteLength == null ||
      byteOffset < 0 ||
      byteLength < 0 ||
      byteOffset + byteLength > bin.lengthInBytes) {
    return null;
  }
  return Uint8List.fromList(
    Uint8List.sublistView(bin, byteOffset, byteOffset + byteLength),
  );
}

_NativeDecodeGlb? _readGlbForNativeDecode(Uint8List bytes) {
  if (bytes.lengthInBytes < 20) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != _glbMagic ||
      data.getUint32(4, Endian.little) != 2) {
    return null;
  }
  final declaredLength = data.getUint32(8, Endian.little);
  if (declaredLength > bytes.lengthInBytes || declaredLength < 20) {
    return null;
  }

  var offset = 12;
  Map<String, Object?>? json;
  Uint8List? bin;
  while (offset + 8 <= declaredLength) {
    final chunkLength = data.getUint32(offset, Endian.little);
    final chunkType = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (offset + chunkLength > declaredLength) {
      return null;
    }
    if (chunkType == _jsonChunkType && json == null) {
      try {
        final decoded = jsonDecode(
          utf8.decode(
              Uint8List.sublistView(bytes, offset, offset + chunkLength)),
        );
        if (decoded is Map) {
          json = _objectMap(decoded);
        }
      } on Object {
        return null;
      }
    } else if (chunkType == _binChunkType && bin == null) {
      bin = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, offset + chunkLength),
      );
    }
    offset += chunkLength;
  }
  return json == null ? null : _NativeDecodeGlb(json: json, bin: bin);
}

Map<String, Object?>? _map(Object? value) {
  if (value is! Map) {
    return null;
  }
  return _objectMap(value);
}

List<Object?>? _list(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return null;
}

int? _intValue(Object? value) {
  return value is int ? value : null;
}

final class _NativeDecodeGlb {
  const _NativeDecodeGlb({required this.json, required this.bin});

  final Map<String, Object?> json;
  final Uint8List? bin;
}

final class _DracoNativeRequestReadResult {
  const _DracoNativeRequestReadResult({
    this.requests = const <Object?>[],
    this.diagnostic,
  });

  final List<Object?> requests;
  final ViewerDiagnostic? diagnostic;
}

final class _NativeDracoAccessorRead {
  const _NativeDracoAccessorRead(this.schema)
      : field = null,
        actual = null;
  const _NativeDracoAccessorRead.invalid({
    required this.field,
    required this.actual,
  }) : schema = null;

  final Map<String, Object?>? schema;
  final String? field;
  final Object? actual;
}

ViewerDiagnostic _dracoUnavailableDiagnostic({
  required String? source,
  required String status,
  required String message,
  Map<String, Object?> extraDetails = const <String, Object?>{},
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: message,
    details: <String, Object?>{
      'source': source,
      'extension': kDracoMeshCompressionExtension,
      'decoder': 'draco',
      'required': true,
      'status': status,
      'pluginPackage': kDracoPluginPackageName,
      'configurationKey': kDracoInfoPlistKey,
      'androidManifestKey': kDracoAndroidManifestKey,
      ...extraDetails,
    },
  );
}

ViewerDiagnostic _basisuUnavailableDiagnostic({
  required String? source,
  required String status,
  required String message,
  Map<String, Object?> extraDetails = const <String, Object?>{},
}) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: message,
    details: <String, Object?>{
      'source': source,
      'extension': kBasisuTextureExtension,
      'decoder': 'basisu',
      'required': true,
      'status': status,
      'pluginPackage': kBasisuPluginPackageName,
      'configurationKey': kBasisuInfoPlistKey,
      'androidManifestKey': kBasisuAndroidManifestKey,
      ...extraDetails,
    },
  );
}
