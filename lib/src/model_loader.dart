import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'internal/flutter_scene_adapter_cancellation.dart';
import 'internal/flutter_scene_authored_mip_texture.dart';
import 'internal/glb_capability_reader.dart';
import 'internal/glb_decode_budget.dart';
import 'internal/glb_imported_texture_patch_reader.dart';
import 'internal/glb_material_extension_reader.dart';
import 'internal/glb_meshopt_rewriter.dart';
import 'internal/glb_native_decoder_probe.dart';
import 'internal/material_extension_patch_group.dart';
import 'material_extension_policy.dart';
import 'material_patch.dart';
import 'material_shading_mode.dart';
import 'model_load_cancellation.dart';
import 'model_source.dart';
import 'part_address.dart';
import 'part_registry.dart';

/// Configuration for runtime GLB loading.
final class ModelLoaderOptions {
  const ModelLoaderOptions({
    this.maxBytes = 50 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
    this.decoderCapabilities = const GlbDecoderCapabilities(),
    this.nativeDecoderProbe = const MethodChannelGlbNativeDecoderProbe(),
    this.decodeBudget = const GlbDecodeBudget(),
  });

  final int maxBytes;
  final Duration timeout;
  final GlbDecoderCapabilities decoderCapabilities;
  final GlbNativeDecoderProbe nativeDecoderProbe;
  final GlbDecodeBudget decodeBudget;
}

/// Result of a model load attempt.
final class ModelLoadResult {
  const ModelLoadResult.success({
    this.diagnostics = const <ViewerDiagnostic>[],
    this.partTree = const PartTree.empty(),
    this.modelLoadDuration,
    this.modelByteSize,
    this.nodeCount,
    this.meshCount,
    this.materialCount,
    this.primitiveCount,
    this.authoredCoreMaterialPatches = const <PartAddress, MaterialPatch>{},
    this.authoredExtensionMaterialPatches =
        const <PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
  })  : diagnostic = null,
        superseded = false;

  const ModelLoadResult.failure(
    ViewerDiagnostic this.diagnostic, {
    this.diagnostics = const <ViewerDiagnostic>[],
    this.superseded = false,
  })  : partTree = const PartTree.empty(),
        modelLoadDuration = null,
        modelByteSize = null,
        nodeCount = null,
        meshCount = null,
        materialCount = null,
        primitiveCount = null,
        authoredCoreMaterialPatches = const <PartAddress, MaterialPatch>{},
        authoredExtensionMaterialPatches = const <PartAddress,
            Map<MaterialExtensionPatchGroup, MaterialPatch>>{};

  final ViewerDiagnostic? diagnostic;
  final List<ViewerDiagnostic> diagnostics;
  final PartTree partTree;
  final Duration? modelLoadDuration;
  final int? modelByteSize;
  final int? nodeCount;
  final int? meshCount;
  final int? materialCount;
  final int? primitiveCount;
  final Map<PartAddress, MaterialPatch> authoredCoreMaterialPatches;
  final Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>
      authoredExtensionMaterialPatches;
  final bool superseded;

  bool get isSuccess => diagnostic == null;
}

/// Loads GLB bytes from a [ModelSource] and dispatches them to flutter_scene.
final class ModelLoader {
  ModelLoader({
    required this.adapter,
    AssetBundle? assetBundle,
    http.Client? httpClient,
    this.options = const ModelLoaderOptions(),
    this.materialExtensionPolicy =
        const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
  })  : assetBundle = assetBundle ?? rootBundle,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final FlutterSceneAdapter adapter;
  final AssetBundle assetBundle;
  final ModelLoaderOptions options;
  final ViewerMaterialExtensionPolicy materialExtensionPolicy;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<ModelLoadResult> load(
    ModelSource source, {
    MaterialShadingPolicy materialShadingPolicy =
        MaterialShadingPolicy.authored,
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) async {
    final preSourceCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'sourceAcquisition',
    );
    if (preSourceCancellation != null) {
      return preSourceCancellation;
    }
    final stopwatch = Stopwatch()..start();
    final sourceOperation = _loadBytes(source);
    final sourceTerminal = await _firstSourceTerminal(
      sourceOperation,
      cancellationToken: cancellationToken,
    );
    final _LoadedModelBytes loaded;
    switch (sourceTerminal) {
      case _SourceAcquisitionSucceeded(:final value):
        loaded = value;
        break;
      case _SourceAcquisitionFailed(:final error):
        if (error case _ModelLoadFailure(:final diagnostic)) {
          return ModelLoadResult.failure(diagnostic);
        }
        return ModelLoadResult.failure(
          _unexpectedSourceDiagnostic(source, error),
        );
      case _SourceAcquisitionCancelled():
        unawaited(sourceOperation.cancel());
        return _cancelledResult(
          source,
          cancellationToken!,
          stage: 'sourceAcquisition',
        );
      case _SourceAcquisitionTimedOut():
        unawaited(sourceOperation.cancel());
        return ModelLoadResult.failure(_timeoutDiagnostic(source));
    }

    final postSourceCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'sourceAcquisition',
    );
    if (postSourceCancellation != null) {
      return postSourceCancellation;
    }

    final sizeDiagnostic = _sizeDiagnostic(loaded);
    if (sizeDiagnostic != null) {
      return ModelLoadResult.failure(sizeDiagnostic);
    }

    final isGlb = isBinaryGlb(loaded.bytes);
    final decodeBudgetTracker = GlbDecodeBudgetTracker(options.decodeBudget);
    var importBytes = loaded.bytes;
    FlutterSceneAuthoredMipBindingPlan? authoredMipBindingPlan;
    var capabilityResult = isGlb
        ? readGlbAssetCapabilities(
            importBytes,
            debugName: loaded.debugName,
            decoderCapabilities: options.decoderCapabilities,
          )
        : const GlbAssetCapabilityResult();
    var meshoptRewriteDiagnostics = const <ViewerDiagnostic>[];
    if (isGlb && capabilityResult.meshoptCompressedBufferViewCount > 0) {
      final preMeshoptCancellation = _cancellationResult(
        source,
        cancellationToken,
        stage: 'meshoptDispatch',
      );
      if (preMeshoptCancellation != null) {
        return preMeshoptCancellation;
      }
      final meshoptRewrite = await rewriteMeshoptCompressedGlb(
        importBytes,
        debugName: loaded.debugName,
        budget: options.decodeBudget,
        budgetTracker: decodeBudgetTracker,
        cancellationToken: cancellationToken,
      );
      meshoptRewriteDiagnostics =
          meshoptRewrite.diagnostics.toList(growable: false);
      ViewerDiagnostic? meshoptCancellation;
      for (final diagnostic in meshoptRewriteDiagnostics) {
        if (diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled) {
          meshoptCancellation = diagnostic;
          break;
        }
      }
      if (meshoptCancellation != null) {
        return ModelLoadResult.failure(
          meshoptCancellation,
          diagnostics: <ViewerDiagnostic>[meshoptCancellation],
        );
      }
      final postMeshoptCancellation = _cancellationResult(
        source,
        cancellationToken,
        stage: 'meshoptDecode',
      );
      if (postMeshoptCancellation != null) {
        return postMeshoptCancellation;
      }
      final rewrittenBytes = meshoptRewrite.bytes;
      if (rewrittenBytes != null) {
        importBytes = rewrittenBytes;
        capabilityResult = readGlbAssetCapabilities(
          importBytes,
          debugName: loaded.debugName,
          decoderCapabilities: options.decoderCapabilities,
        );
      } else if (capabilityResult.extensionsRequired.contains(
        kMeshoptCompressionExtension,
      )) {
        final meshoptDiagnostic = _diagnosticForExtension(
          kMeshoptCompressionExtension,
          meshoptRewriteDiagnostics,
        );
        return ModelLoadResult.failure(
          meshoptDiagnostic ??
              _blockingCapabilityDiagnostic(capabilityResult) ??
              _meshoptRewriteDiagnostic(loaded.debugName),
          diagnostics: <ViewerDiagnostic>[
            ...meshoptRewriteDiagnostics,
            ...capabilityResult.diagnostics,
          ],
        );
      }
    }
    var nativeDecoderDiagnostics = const <ViewerDiagnostic>[];
    if (isGlb && _blockingCapabilityDiagnostic(capabilityResult) != null) {
      final requiredExtensions = capabilityResult.extensionsRequired;
      final preAvailabilityCancellation = _cancellationResult(
        source,
        cancellationToken,
        stage: 'nativeAvailability',
      );
      if (preAvailabilityCancellation != null) {
        return preAvailabilityCancellation;
      }
      final nativeAvailability =
          await options.nativeDecoderProbe.checkAvailability(
        requiredExtensions: requiredExtensions,
        source: loaded.debugName,
      );
      final postAvailabilityCancellation = _cancellationResult(
        source,
        cancellationToken,
        stage: 'nativeAvailability',
      );
      if (postAvailabilityCancellation != null) {
        return postAvailabilityCancellation;
      }
      nativeDecoderDiagnostics =
          nativeAvailability.diagnostics.toList(growable: false);
      final mergedDecoderCapabilities = options.decoderCapabilities.merge(
        nativeAvailability.capabilities,
      );
      capabilityResult = readGlbAssetCapabilities(
        importBytes,
        debugName: loaded.debugName,
        decoderCapabilities: mergedDecoderCapabilities,
      );
      if (_blockingCapabilityDiagnostic(capabilityResult) == null &&
          _requiresNativeDecode(
            requiredExtensions,
            baseCapabilities: options.decoderCapabilities,
            nativeCapabilities: nativeAvailability.capabilities,
          )) {
        final preNativeDecodeCancellation = _cancellationResult(
          source,
          cancellationToken,
          stage: 'nativeDispatch',
        );
        if (preNativeDecodeCancellation != null) {
          return preNativeDecodeCancellation;
        }
        final decodeResult = await options.nativeDecoderProbe.decodeGlb(
          bytes: importBytes,
          requiredExtensions: requiredExtensions,
          budget: options.decodeBudget,
          budgetTracker: decodeBudgetTracker,
          cancellationToken: cancellationToken,
          source: loaded.debugName,
        );
        nativeDecoderDiagnostics = <ViewerDiagnostic>[
          ...nativeDecoderDiagnostics,
          ...decodeResult.diagnostics,
        ];
        final nativeCancellation = decodeResult.diagnostics
            .where(
              (diagnostic) =>
                  diagnostic.code == ViewerDiagnosticCode.modelLoadCancelled,
            )
            .firstOrNull;
        if (nativeCancellation != null) {
          return ModelLoadResult.failure(
            nativeCancellation,
            diagnostics: nativeDecoderDiagnostics,
          );
        }
        final postNativeDecodeCancellation = _cancellationResult(
          source,
          cancellationToken,
          stage: 'nativeDecode',
        );
        if (postNativeDecodeCancellation != null) {
          return postNativeDecodeCancellation;
        }
        final decodedBytes = decodeResult.bytes;
        final decodedMipImages = decodeResult.decodedBasisuImages;
        final accountingDiagnostic = _nativeDecodeOutputAccountingDiagnostic(
          decodeResult,
          loaded.debugName,
          requiredExtensions,
        );
        if (accountingDiagnostic != null) {
          return ModelLoadResult.failure(
            accountingDiagnostic,
            diagnostics: <ViewerDiagnostic>[
              ...nativeDecoderDiagnostics,
              accountingDiagnostic,
            ],
          );
        }
        if (decodedBytes == null && decodedMipImages.isEmpty) {
          return ModelLoadResult.failure(
            _nativeDecodeDiagnostic(
              nativeDecoderDiagnostics,
              loaded.debugName,
              requiredExtensions,
            ),
            diagnostics: nativeDecoderDiagnostics,
          );
        }
        if (decodedBytes != null) {
          try {
            switch (decodeResult.outputAccounting) {
              case GlbNativeDecodeOutputAccounting.none:
                break;
              case GlbNativeDecodeOutputAccounting.opaqueFinalBytes:
                decodeBudgetTracker.reserveNativeOutputBytes(
                  decodedBytes.lengthInBytes,
                  stage: 'nativeDecodedGlbOutput',
                );
              case GlbNativeDecodeOutputAccounting.componentPayloadsAccounted:
                decodeBudgetTracker.checkNativeOutputBytes(
                  decodedBytes.lengthInBytes,
                  stage: 'nativeDecodedGlbOutput',
                );
            }
          } on GlbDecodeBudgetExceeded catch (error) {
            final diagnostic = _nativeDecodeBudgetDiagnostic(
              error,
              loaded.debugName,
              requiredExtensions,
            );
            return ModelLoadResult.failure(
              diagnostic,
              diagnostics: <ViewerDiagnostic>[
                ...nativeDecoderDiagnostics,
                diagnostic,
              ],
            );
          }
          importBytes = decodedBytes;
        }
        if (decodedMipImages.isNotEmpty) {
          final topologyBytes = decodeResult.topologyBytes;
          if (topologyBytes == null) {
            final diagnostic = ViewerDiagnostic(
              code: ViewerDiagnosticCode.unsupportedModelFeature,
              message:
                  'Native authored mip output did not retain importer topology bytes.',
              details: <String, Object?>{
                'source': loaded.debugName,
                'extension': kBasisuTextureExtension,
                'decoder': 'basisu',
                'required': true,
                'limitation': 'authoredMipTopologyMissing',
                'status': 'malformedOutput',
                'blocking': true,
              },
            );
            return ModelLoadResult.failure(
              diagnostic,
              diagnostics: <ViewerDiagnostic>[
                ...nativeDecoderDiagnostics,
                diagnostic,
              ],
            );
          }
          try {
            switch (decodeResult.topologyOutputAccounting) {
              case GlbNativeDecodeOutputAccounting.none:
                break;
              case GlbNativeDecodeOutputAccounting.opaqueFinalBytes:
                decodeBudgetTracker.reserveNativeOutputBytes(
                  topologyBytes.lengthInBytes,
                  stage: 'nativeDecodedTopologyOutput',
                );
              case GlbNativeDecodeOutputAccounting.componentPayloadsAccounted:
                decodeBudgetTracker.checkNativeOutputBytes(
                  topologyBytes.lengthInBytes,
                  stage: 'nativeDecodedTopologyOutput',
                );
            }
          } on GlbDecodeBudgetExceeded catch (error) {
            final diagnostic = _nativeDecodeBudgetDiagnostic(
              error,
              loaded.debugName,
              requiredExtensions,
            );
            return ModelLoadResult.failure(
              diagnostic,
              diagnostics: <ViewerDiagnostic>[
                ...nativeDecoderDiagnostics,
                diagnostic,
              ],
            );
          }
          importBytes = topologyBytes;
          final planResult = buildFlutterSceneAuthoredMipBindingPlan(
            importBytes,
            decodedImages: decodedMipImages,
            debugName: loaded.debugName,
          );
          if (planResult.plan == null) {
            final diagnostic = planResult.diagnostics.first;
            return ModelLoadResult.failure(
              diagnostic,
              diagnostics: <ViewerDiagnostic>[
                ...nativeDecoderDiagnostics,
                ...planResult.diagnostics,
              ],
            );
          }
          authoredMipBindingPlan = planResult.plan;
          nativeDecoderDiagnostics = nativeDecoderDiagnostics
              .where(
                (diagnostic) =>
                    diagnostic.details['status'] != 'mipAwareImporterRequired',
              )
              .toList(growable: false);
          capabilityResult = readGlbAssetCapabilities(
            importBytes,
            debugName: loaded.debugName,
            decoderCapabilities: options.decoderCapabilities.merge(
              const GlbDecoderCapabilities(textureBasisu: true),
            ),
          );
        } else {
          capabilityResult = readGlbAssetCapabilities(
            importBytes,
            debugName: loaded.debugName,
            decoderCapabilities: options.decoderCapabilities,
          );
        }
      }
    }
    final blockingCapabilityDiagnostic =
        _blockingCapabilityDiagnostic(capabilityResult);
    if (blockingCapabilityDiagnostic != null) {
      final nativeDiagnostic = _nativeDiagnosticFor(
        blockingCapabilityDiagnostic,
        nativeDecoderDiagnostics,
      );
      return ModelLoadResult.failure(
        nativeDiagnostic ?? blockingCapabilityDiagnostic,
        diagnostics: <ViewerDiagnostic>[
          ...nativeDecoderDiagnostics,
          ...capabilityResult.diagnostics,
        ],
      );
    }
    final preAuthoredPatchCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'authoredPatchExtraction',
    );
    if (preAuthoredPatchCancellation != null) {
      return preAuthoredPatchCancellation;
    }
    final authoredExtensionResult = isGlb
        ? readGlbMaterialExtensionIntent(
            importBytes,
            debugName: loaded.debugName,
          )
        : GlbMaterialExtensionReaderResult.empty;
    final importedTexturePatchResult = isGlb
        ? readGlbImportedTexturePatches(
            importBytes,
            debugName: loaded.debugName,
          )
        : GlbImportedTexturePatchResult.empty;
    final importedTextureDiagnostics = authoredMipBindingPlan == null
        ? importedTexturePatchResult.diagnostics
        : importedTexturePatchResult.diagnostics
            .where(
              (diagnostic) =>
                  diagnostic.details['extension'] != kBasisuTextureExtension,
            )
            .toList(growable: false);
    final preAdapterCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'adapterImport',
    );
    if (preAdapterCancellation != null) {
      return preAdapterCancellation;
    }
    final preImportDiagnostics = <ViewerDiagnostic>[
      ...meshoptRewriteDiagnostics,
      ...nativeDecoderDiagnostics,
      ...capabilityResult.diagnostics,
      ...importedTextureDiagnostics,
      ...authoredExtensionResult.diagnostics,
    ];
    final blockingTextureBindingDiagnostic =
        _blockingTextureBindingDiagnostic(preImportDiagnostics);
    if (blockingTextureBindingDiagnostic != null) {
      return ModelLoadResult.failure(
        blockingTextureBindingDiagnostic,
        diagnostics: preImportDiagnostics,
      );
    }

    var publicationSuperseded = false;
    var publicationClosed = false;
    bool acceptPublication() {
      if (publicationClosed) {
        return false;
      }
      if (tryAcceptPublication?.call() == false) {
        publicationSuperseded = true;
        return false;
      }
      final tokenAccepted = cancellationToken == null ||
          tryAcceptModelLoadPublication(cancellationToken);
      if (!tokenAccepted) {
        onPublicationRejected?.call();
      }
      return tokenAccepted;
    }

    try {
      final bindingPlan = authoredMipBindingPlan;
      if (bindingPlan == null) {
        await adapter
            .loadGlbBytes(
              importBytes,
              debugName: loaded.debugName,
              materialShadingPolicy: materialShadingPolicy,
              tryAcceptPublication: acceptPublication,
            )
            .timeout(options.timeout);
      } else if (adapter is FlutterSceneAuthoredMipBindingAdapter) {
        final mipAdapter = adapter as FlutterSceneAuthoredMipBindingAdapter;
        await mipAdapter
            .loadGlbBytesWithAuthoredMips(
              importBytes,
              bindingPlan: bindingPlan,
              debugName: loaded.debugName,
              materialShadingPolicy: materialShadingPolicy,
              isLoadCancelled: () => cancellationToken?.isCancelled ?? false,
              tryAcceptPublication: acceptPublication,
            )
            .timeout(options.timeout);
      } else {
        throw FlutterSceneAuthoredMipBindingException(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.adapterUnavailable,
            message:
                'The configured adapter does not support authored mip binding.',
            details: <String, Object?>{
              'source': loaded.debugName,
              'extension': kBasisuTextureExtension,
              'limitation': 'authoredMipBindingAdapterUnavailable',
              'status': 'blocked',
              'blocking': true,
              'required': true,
            },
          ),
          const <ViewerDiagnostic>[],
        );
      }
    } on FlutterSceneAdapterLoadCancelledException {
      if (publicationSuperseded) {
        return _supersededPublicationResult(loaded.debugName);
      }
      if (cancellationToken != null) {
        return _cancelledResult(source, cancellationToken,
            stage: 'adapterPublication');
      }
      return _supersededPublicationResult(loaded.debugName);
    } on FlutterSceneAuthoredMipBindingException catch (error) {
      return ModelLoadResult.failure(
        error.diagnostic,
        diagnostics: <ViewerDiagnostic>[
          ...preImportDiagnostics,
          ...error.diagnostics,
          if (!error.diagnostics.contains(error.diagnostic)) error.diagnostic,
        ],
      );
    } on FlutterSceneAdapterUnavailableException catch (error) {
      return ModelLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.adapterUnavailable,
          message: error.message,
          details: <String, Object?>{'source': loaded.debugName},
        ),
        diagnostics: preImportDiagnostics,
      );
    } on TimeoutException {
      return ModelLoadResult.failure(
        _timeoutDiagnostic(source),
        diagnostics: preImportDiagnostics,
      );
    } on Object catch (error) {
      return ModelLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.adapterFailure,
          message: 'flutter_scene failed to import the GLB bytes.',
          details: <String, Object?>{
            'source': loaded.debugName,
            'error': error.toString(),
          },
        ),
        diagnostics: preImportDiagnostics,
      );
    } finally {
      publicationClosed = true;
    }

    final postAdapterCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'adapterImport',
    );
    if (postAdapterCancellation != null) {
      return postAdapterCancellation;
    }

    final snapshot = adapter.nodeSnapshot;
    final registry = _buildPartRegistry(snapshot);
    final fallbackStats = _modelStatsFromSnapshot(snapshot);
    final adapterStats = adapter.modelStats;
    final successCancellation = _cancellationResult(
      source,
      cancellationToken,
      stage: 'successPublication',
    );
    if (successCancellation != null) {
      return successCancellation;
    }
    return ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[
        ...preImportDiagnostics,
        ...adapter.collectDiagnostics(),
        ...registry.diagnostics,
      ],
      partTree: registry.tree,
      modelLoadDuration: stopwatch.elapsed,
      modelByteSize: loaded.bytes.lengthInBytes,
      nodeCount: adapterStats?.nodeCount ?? fallbackStats?.nodeCount,
      meshCount: adapterStats?.meshCount ?? fallbackStats?.meshCount,
      materialCount: adapterStats?.materialCount,
      primitiveCount:
          adapterStats?.primitiveCount ?? fallbackStats?.primitiveCount,
      authoredCoreMaterialPatches: importedTexturePatchResult.patches,
      authoredExtensionMaterialPatches: authoredExtensionResult.patches,
    );
  }

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  ModelLoadResult? _cancellationResult(
    ModelSource source,
    ModelLoadCancellationToken? cancellationToken, {
    required String stage,
  }) {
    if (cancellationToken?.isCancelled != true) {
      return null;
    }
    return _cancelledResult(source, cancellationToken!, stage: stage);
  }

  ModelLoadResult _cancelledResult(
    ModelSource source,
    ModelLoadCancellationToken cancellationToken, {
    required String stage,
  }) {
    return ModelLoadResult.failure(
      modelLoadCancellationDiagnostic(
        source,
        cancellationToken,
        stage: stage,
      ),
    );
  }

  ModelLoadResult _supersededPublicationResult(String source) {
    return ModelLoadResult.failure(
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterFailure,
        message: 'Model publication was superseded before commit.',
        details: <String, Object?>{
          'source': source,
          'stage': 'controllerPublication',
          'reason': 'superseded',
          'status': 'notPublished',
        },
      ),
      superseded: true,
    );
  }

  _SourceLoadOperation _loadBytes(ModelSource source) {
    return switch (source) {
      BytesModelSource() => _SourceLoadOperation(
          Future<_LoadedModelBytes>.value(
            _LoadedModelBytes(
              source.bytes,
              debugName: source.debugName ?? 'bytes',
            ),
          ),
        ),
      AssetModelSource() => _SourceLoadOperation(_loadAssetBytes(source)),
      NetworkModelSource() => _networkLoadOperation(source),
    };
  }

  Future<_SourceAcquisitionTerminal> _firstSourceTerminal(
    _SourceLoadOperation operation, {
    ModelLoadCancellationToken? cancellationToken,
  }) async {
    final timeout = Completer<_SourceAcquisitionTerminal>();
    final timer = Timer(
      options.timeout,
      () => timeout.complete(const _SourceAcquisitionTimedOut()),
    );
    try {
      return await Future.any<_SourceAcquisitionTerminal>(
        <Future<_SourceAcquisitionTerminal>>[
          operation.future.then<_SourceAcquisitionTerminal>(
            _SourceAcquisitionSucceeded.new,
            onError: (Object error, StackTrace _) =>
                _SourceAcquisitionFailed(error),
          ),
          if (cancellationToken != null)
            cancellationToken.whenCancelled.then<_SourceAcquisitionTerminal>(
              (_) => const _SourceAcquisitionCancelled(),
            ),
          timeout.future,
        ],
      );
    } finally {
      timer.cancel();
    }
  }

  Future<_LoadedModelBytes> _loadAssetBytes(AssetModelSource source) async {
    try {
      final byteData = await assetBundle.load(source.assetPath);
      return _LoadedModelBytes(
        Uint8List.sublistView(byteData),
        debugName: source.assetPath,
      );
    } on Object catch (error) {
      throw _ModelLoadFailure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.assetLoadFailure,
          message: 'Failed to load GLB asset bytes.',
          details: <String, Object?>{
            'assetPath': source.assetPath,
            'error': error.toString(),
          },
        ),
      );
    }
  }

  _SourceLoadOperation _networkLoadOperation(NetworkModelSource source) {
    final uri = source.uri;
    if (!_isValidNetworkUri(uri)) {
      return _SourceLoadOperation(
        Future<_LoadedModelBytes>.error(
          _ModelLoadFailure(
            ViewerDiagnostic(
              code: ViewerDiagnosticCode.invalidModelUrl,
              message:
                  'Network model URLs must be absolute http or https URLs.',
              details: <String, Object?>{'url': uri.toString()},
            ),
          ),
        ),
      );
    }
    final request = _LoadScopedNetworkRequest(
      client: _httpClient,
      source: source,
    );
    return _SourceLoadOperation(
      request.result,
      cancel: request.cancel,
    );
  }

  bool _isValidNetworkUri(Uri uri) {
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  ViewerDiagnostic? _sizeDiagnostic(_LoadedModelBytes loaded) {
    final byteLength = loaded.bytes.lengthInBytes;
    if (byteLength <= options.maxBytes) {
      return null;
    }
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.modelTooLarge,
      message: 'Model exceeds the configured GLB byte limit.',
      details: <String, Object?>{
        'source': loaded.debugName,
        'byteLength': byteLength,
        'maxBytes': options.maxBytes,
      },
    );
  }

  ViewerDiagnostic _timeoutDiagnostic(ModelSource source) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.modelLoadTimeout,
      message: 'Model loading exceeded the configured timeout.',
      details: <String, Object?>{
        'source': _sourceLabel(source),
        'timeoutMilliseconds': options.timeout.inMilliseconds,
      },
    );
  }

  ViewerDiagnostic _unexpectedSourceDiagnostic(
      ModelSource source, Object error) {
    final code = switch (source) {
      AssetModelSource() => ViewerDiagnosticCode.assetLoadFailure,
      NetworkModelSource() => ViewerDiagnosticCode.networkFailure,
      BytesModelSource() => ViewerDiagnosticCode.adapterFailure,
    };
    return ViewerDiagnostic(
      code: code,
      message: 'Failed to load GLB bytes from the model source.',
      details: <String, Object?>{
        'source': _sourceLabel(source),
        'error': error.toString(),
      },
    );
  }

  String _sourceLabel(ModelSource source) {
    return switch (source) {
      BytesModelSource() => source.debugName ?? 'bytes',
      AssetModelSource() => source.assetPath,
      NetworkModelSource() => source.uri.toString(),
    };
  }

  PartRegistry _buildPartRegistry(AdapterNodeSnapshot? snapshot) {
    if (snapshot == null) {
      return const PartRegistry.empty();
    }
    return PartRegistry.fromSnapshot(snapshot);
  }

  AdapterModelStats? _modelStatsFromSnapshot(AdapterNodeSnapshot? snapshot) {
    if (snapshot == null) {
      return null;
    }
    var nodeCount = 0;
    var meshCount = 0;
    var primitiveCount = 0;
    void visit(AdapterNodeSnapshot node) {
      nodeCount += 1;
      if (node.primitiveCount > 0) {
        meshCount += 1;
        primitiveCount += node.primitiveCount;
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(snapshot);
    return AdapterModelStats(
      nodeCount: nodeCount,
      meshCount: meshCount,
      primitiveCount: primitiveCount,
    );
  }
}

final class _SourceLoadOperation {
  _SourceLoadOperation(
    this.future, {
    Future<void> Function()? cancel,
  }) : _cancel = cancel;

  final Future<_LoadedModelBytes> future;
  final Future<void> Function()? _cancel;

  Future<void> cancel() => _cancel?.call() ?? Future<void>.value();
}

sealed class _SourceAcquisitionTerminal {
  const _SourceAcquisitionTerminal();
}

final class _SourceAcquisitionSucceeded extends _SourceAcquisitionTerminal {
  const _SourceAcquisitionSucceeded(this.value);

  final _LoadedModelBytes value;
}

final class _SourceAcquisitionFailed extends _SourceAcquisitionTerminal {
  const _SourceAcquisitionFailed(this.error);

  final Object error;
}

final class _SourceAcquisitionCancelled extends _SourceAcquisitionTerminal {
  const _SourceAcquisitionCancelled();
}

final class _SourceAcquisitionTimedOut extends _SourceAcquisitionTerminal {
  const _SourceAcquisitionTimedOut();
}

final class _LoadScopedNetworkRequest {
  _LoadScopedNetworkRequest({
    required http.Client client,
    required NetworkModelSource source,
  })  : _client = client,
        _source = source {
    unawaited(_startSafely());
  }

  final http.Client _client;
  final NetworkModelSource _source;
  final Completer<_LoadedModelBytes> _result = Completer<_LoadedModelBytes>();
  final Completer<void> _abortTrigger = Completer<void>();
  // Retained across callbacks so load cancellation can close only this stream.
  // ignore: cancel_subscriptions
  StreamSubscription<List<int>>? _responseSubscription;
  var _cancelled = false;

  Future<_LoadedModelBytes> get result => _result.future;

  Future<void> _startSafely() async {
    try {
      await _start();
    } on Object catch (error, stackTrace) {
      if (!_cancelled) {
        _completeNetworkFailure(error, stackTrace);
      }
    }
  }

  Future<void> _start() async {
    final uri = _source.uri;
    final request = http.AbortableRequest(
      'GET',
      uri,
      abortTrigger: _abortTrigger.future,
    )..headers.addAll(_source.headers);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Object catch (error, stackTrace) {
      if (!_cancelled) {
        _completeNetworkFailure(error, stackTrace);
      }
      return;
    }
    if (_cancelled) {
      final lateSubscription = response.stream.listen(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      await _cancelSubscriptionSafely(lateSubscription);
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final diagnostic = _ModelLoadFailure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'Network model request failed.',
          details: <String, Object?>{
            'url': uri.toString(),
            'statusCode': response.statusCode,
          },
        ),
      );
      if (!_result.isCompleted) {
        _result.completeError(diagnostic);
      }
      final rejectedSubscription = response.stream.listen(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      await _cancelSubscriptionSafely(rejectedSubscription);
      return;
    }

    final body = BytesBuilder(copy: false);
    _responseSubscription = response.stream.listen(
      (chunk) {
        if (!_cancelled) {
          body.add(chunk);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_cancelled) {
          _completeNetworkFailure(error, stackTrace);
        }
        scheduleMicrotask(
          () => unawaited(
            _cancelSubscriptionSafely(_responseSubscription),
          ),
        );
      },
      onDone: () {
        if (!_cancelled && !_result.isCompleted) {
          _result.complete(
            _LoadedModelBytes(
              body.takeBytes(),
              debugName: uri.toString(),
            ),
          );
        }
      },
      cancelOnError: false,
    );
  }

  void _completeNetworkFailure(Object error, StackTrace stackTrace) {
    if (_result.isCompleted) {
      return;
    }
    _result.completeError(
      _ModelLoadFailure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'Network model request failed.',
          details: <String, Object?>{
            'url': _source.uri.toString(),
            'error': error.toString(),
          },
        ),
      ),
      stackTrace,
    );
  }

  Future<void> cancel() async {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    if (!_abortTrigger.isCompleted) {
      _abortTrigger.complete();
    }
    await _cancelSubscriptionSafely(_responseSubscription);
  }

  Future<void> _cancelSubscriptionSafely(
    StreamSubscription<List<int>>? subscription,
  ) async {
    if (subscription == null) {
      return;
    }
    try {
      await subscription.cancel();
    } on Object {
      // Cleanup is best-effort and must not replace the load's typed terminal
      // result or escape from this unawaited request lifecycle.
    }
  }
}

final class _LoadedModelBytes {
  const _LoadedModelBytes(this.bytes, {required this.debugName});

  final Uint8List bytes;
  final String debugName;
}

final class _ModelLoadFailure implements Exception {
  const _ModelLoadFailure(this.diagnostic);

  final ViewerDiagnostic diagnostic;
}

ViewerDiagnostic? _blockingCapabilityDiagnostic(
  GlbAssetCapabilityResult result,
) {
  for (final diagnostic in result.diagnostics) {
    if (diagnostic.code == ViewerDiagnosticCode.unsupportedModelFeature &&
        diagnostic.details['required'] == true) {
      return diagnostic;
    }
  }
  return null;
}

ViewerDiagnostic? _blockingTextureBindingDiagnostic(
  List<ViewerDiagnostic> diagnostics,
) {
  for (final diagnostic in diagnostics) {
    if (diagnostic.details['blocking'] != true) {
      continue;
    }
    if (diagnostic.details['required'] == true ||
        diagnostic.details['status'] == 'malformedAsset') {
      return diagnostic;
    }
  }
  return null;
}

ViewerDiagnostic? _nativeDiagnosticFor(
  ViewerDiagnostic blockingDiagnostic,
  List<ViewerDiagnostic> nativeDiagnostics,
) {
  final extension = blockingDiagnostic.details['extension'];
  return _diagnosticForExtension(extension, nativeDiagnostics);
}

ViewerDiagnostic? _diagnosticForExtension(
  Object? extension,
  List<ViewerDiagnostic> diagnostics,
) {
  for (final diagnostic in diagnostics) {
    if (diagnostic.code == ViewerDiagnosticCode.unsupportedModelFeature &&
        diagnostic.details['extension'] == extension) {
      return diagnostic;
    }
  }
  return null;
}

bool _requiresNativeDecode(
  Set<String> requiredExtensions, {
  required GlbDecoderCapabilities baseCapabilities,
  required GlbDecoderCapabilities nativeCapabilities,
}) {
  return (requiredExtensions.contains(kDracoMeshCompressionExtension) &&
          !baseCapabilities.dracoMeshCompression &&
          nativeCapabilities.dracoMeshCompression) ||
      (requiredExtensions.contains(kBasisuTextureExtension) &&
          !baseCapabilities.textureBasisu &&
          nativeCapabilities.textureBasisu);
}

ViewerDiagnostic _nativeDecodeDiagnostic(
  List<ViewerDiagnostic> diagnostics,
  String? source,
  Set<String> requiredExtensions,
) {
  for (final diagnostic in diagnostics.reversed) {
    if (diagnostic.code == ViewerDiagnosticCode.unsupportedModelFeature &&
        requiredExtensions.contains(diagnostic.details['extension'])) {
      return diagnostic;
    }
  }
  if (requiredExtensions.contains(kBasisuTextureExtension)) {
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message:
          'Native BasisU/KTX2 transcoder did not return decoded GLB bytes.',
      details: <String, Object?>{
        'source': source,
        'extension': kBasisuTextureExtension,
        'decoder': 'basisu',
        'required': true,
        'status': 'decodeFailed',
        'pluginPackage': kBasisuPluginPackageName,
        'configurationKey': kBasisuInfoPlistKey,
        'androidManifestKey': kBasisuAndroidManifestKey,
      },
    );
  }
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Native Draco decoder did not return decoded GLB bytes.',
    details: <String, Object?>{
      'source': source,
      'extension': kDracoMeshCompressionExtension,
      'decoder': 'draco',
      'required': true,
      'status': 'decodeFailed',
      'pluginPackage': kDracoPluginPackageName,
      'configurationKey': kDracoInfoPlistKey,
      'androidManifestKey': kDracoAndroidManifestKey,
    },
  );
}

ViewerDiagnostic _meshoptRewriteDiagnostic(String? source) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Meshopt decoder did not return decoded GLB bytes.',
    details: <String, Object?>{
      'source': source,
      'extension': kMeshoptCompressionExtension,
      'decoder': 'meshopt',
      'required': true,
      'status': 'rewriteFailed',
    },
  );
}

ViewerDiagnostic _nativeDecodeBudgetDiagnostic(
  GlbDecodeBudgetExceeded error,
  String? source,
  Set<String> requiredExtensions,
) {
  final sortedExtensions = requiredExtensions.toList()..sort();
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Native decoded GLB exceeded the configured decode budget.',
    details: <String, Object?>{
      'source': source,
      if (sortedExtensions.length == 1) 'extension': sortedExtensions.single,
      'extensions': sortedExtensions,
      'decoder': 'native',
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

ViewerDiagnostic? _nativeDecodeOutputAccountingDiagnostic(
  GlbNativeDecodeResult result,
  String? source,
  Set<String> requiredExtensions,
) {
  final hasBytes = result.bytes != null;
  final hasAccounting =
      result.outputAccounting != GlbNativeDecodeOutputAccounting.none;
  if (hasBytes != hasAccounting) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'outputAccounting',
      limit:
          hasBytes ? 'opaqueFinalBytes or componentPayloadsAccounted' : 'none',
      actual: result.outputAccounting.name,
    );
  }
  final hasTopology = result.topologyBytes != null;
  final hasMipImages = result.decodedBasisuImages.isNotEmpty;
  if (hasTopology && !hasMipImages) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'decodedBasisuImages',
      limit: 'non-empty when topologyBytes is present',
      actual: 0,
    );
  }
  if (hasMipImages && !hasTopology) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'topologyBytes',
      limit: 'retained importer topology for decoded authored mip images',
      actual: 'missing',
    );
  }
  final topologyAccounting = result.topologyOutputAccounting;
  if (!hasTopology &&
      topologyAccounting != GlbNativeDecodeOutputAccounting.none) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'topologyOutputAccounting',
      limit: 'none when topologyBytes is absent',
      actual: topologyAccounting.name,
    );
  }
  if (hasTopology &&
      topologyAccounting == GlbNativeDecodeOutputAccounting.opaqueFinalBytes) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'topologyOutputAccounting',
      limit: 'none or componentPayloadsAccounted',
      actual: topologyAccounting.name,
    );
  }
  if (hasBytes && hasMipImages) {
    return _nativeDecodeAccountingShapeDiagnostic(
      result,
      source,
      requiredExtensions,
      field: 'bytes',
      limit: 'null when authored mip payloads travel out-of-band',
      actual: 'present',
    );
  }
  return null;
}

ViewerDiagnostic _nativeDecodeAccountingShapeDiagnostic(
  GlbNativeDecodeResult result,
  String? source,
  Set<String> requiredExtensions, {
  required String field,
  required Object limit,
  required Object actual,
}) {
  final sortedExtensions = requiredExtensions.toList()..sort();
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.unsupportedModelFeature,
    message: 'Native decoder returned inconsistent output accounting.',
    details: <String, Object?>{
      'source': source,
      if (sortedExtensions.length == 1) 'extension': sortedExtensions.single,
      'extensions': sortedExtensions,
      'decoder': 'native',
      'required': true,
      'limitation': 'nativeDecodeOutputAccounting',
      'status': 'malformedOutput',
      'stage': 'nativeDecodedGlbOutput',
      'field': field,
      'limit': limit,
      'actual': actual,
      'bytesPresent': result.bytes != null,
      'topologyBytesPresent': result.topologyBytes != null,
      'decodedBasisuImageCount': result.decodedBasisuImages.length,
      'outputAccounting': result.outputAccounting.name,
      'topologyOutputAccounting': result.topologyOutputAccounting.name,
    },
  );
}
