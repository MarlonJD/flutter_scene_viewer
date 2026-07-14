import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
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
  }) : diagnostic = null;

  const ModelLoadResult.failure(
    ViewerDiagnostic this.diagnostic, {
    this.diagnostics = const <ViewerDiagnostic>[],
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
  }) async {
    final stopwatch = Stopwatch()..start();
    final _LoadedModelBytes loaded;
    try {
      loaded = await _loadBytes(source).timeout(options.timeout);
    } on TimeoutException {
      return ModelLoadResult.failure(_timeoutDiagnostic(source));
    } on _ModelLoadFailure catch (failure) {
      return ModelLoadResult.failure(failure.diagnostic);
    } on Object catch (error) {
      return ModelLoadResult.failure(
          _unexpectedSourceDiagnostic(source, error));
    }

    final sizeDiagnostic = _sizeDiagnostic(loaded);
    if (sizeDiagnostic != null) {
      return ModelLoadResult.failure(sizeDiagnostic);
    }

    final isGlb = isBinaryGlb(loaded.bytes);
    final decodeBudgetTracker = GlbDecodeBudgetTracker(options.decodeBudget);
    var importBytes = loaded.bytes;
    var capabilityResult = isGlb
        ? readGlbAssetCapabilities(
            importBytes,
            debugName: loaded.debugName,
            decoderCapabilities: options.decoderCapabilities,
          )
        : const GlbAssetCapabilityResult();
    var meshoptRewriteDiagnostics = const <ViewerDiagnostic>[];
    if (isGlb && capabilityResult.meshoptCompressedBufferViewCount > 0) {
      final meshoptRewrite = rewriteMeshoptCompressedGlb(
        importBytes,
        debugName: loaded.debugName,
        budget: options.decodeBudget,
        budgetTracker: decodeBudgetTracker,
      );
      meshoptRewriteDiagnostics =
          meshoptRewrite.diagnostics.toList(growable: false);
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
      final nativeAvailability =
          await options.nativeDecoderProbe.checkAvailability(
        requiredExtensions: requiredExtensions,
        source: loaded.debugName,
      );
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
        final decodeResult = await options.nativeDecoderProbe.decodeGlb(
          bytes: importBytes,
          requiredExtensions: requiredExtensions,
          budget: options.decodeBudget,
          budgetTracker: decodeBudgetTracker,
          source: loaded.debugName,
        );
        nativeDecoderDiagnostics = <ViewerDiagnostic>[
          ...nativeDecoderDiagnostics,
          ...decodeResult.diagnostics,
        ];
        final decodedBytes = decodeResult.bytes;
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
        if (decodedBytes == null) {
          return ModelLoadResult.failure(
            _nativeDecodeDiagnostic(
              nativeDecoderDiagnostics,
              loaded.debugName,
              requiredExtensions,
            ),
            diagnostics: nativeDecoderDiagnostics,
          );
        }
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
        capabilityResult = readGlbAssetCapabilities(
          importBytes,
          debugName: loaded.debugName,
          decoderCapabilities: options.decoderCapabilities,
        );
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
    final preImportDiagnostics = <ViewerDiagnostic>[
      ...meshoptRewriteDiagnostics,
      ...nativeDecoderDiagnostics,
      ...capabilityResult.diagnostics,
      ...importedTexturePatchResult.diagnostics,
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

    try {
      await adapter
          .loadGlbBytes(
            importBytes,
            debugName: loaded.debugName,
            materialShadingPolicy: materialShadingPolicy,
          )
          .timeout(options.timeout);
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
    }

    final snapshot = adapter.nodeSnapshot;
    final registry = _buildPartRegistry(snapshot);
    final fallbackStats = _modelStatsFromSnapshot(snapshot);
    final adapterStats = adapter.modelStats;
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

  Future<_LoadedModelBytes> _loadBytes(ModelSource source) async {
    return switch (source) {
      BytesModelSource() => _LoadedModelBytes(
          source.bytes,
          debugName: source.debugName ?? 'bytes',
        ),
      AssetModelSource() => _loadAssetBytes(source),
      NetworkModelSource() => _loadNetworkBytes(source),
    };
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

  Future<_LoadedModelBytes> _loadNetworkBytes(NetworkModelSource source) async {
    final uri = source.uri;
    if (!_isValidNetworkUri(uri)) {
      throw _ModelLoadFailure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.invalidModelUrl,
          message: 'Network model URLs must be absolute http or https URLs.',
          details: <String, Object?>{'url': uri.toString()},
        ),
      );
    }

    try {
      final response = await _httpClient.get(uri, headers: source.headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _ModelLoadFailure(
          ViewerDiagnostic(
            code: ViewerDiagnosticCode.networkFailure,
            message: 'Network model request failed.',
            details: <String, Object?>{
              'url': uri.toString(),
              'statusCode': response.statusCode,
            },
          ),
        );
      }
      return _LoadedModelBytes(
        response.bodyBytes,
        debugName: uri.toString(),
      );
    } on _ModelLoadFailure {
      rethrow;
    } on Object catch (error) {
      throw _ModelLoadFailure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'Network model request failed.',
          details: <String, Object?>{
            'url': uri.toString(),
            'error': error.toString(),
          },
        ),
      );
    }
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
  if (hasBytes == hasAccounting) {
    return null;
  }
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
      'field': 'outputAccounting',
      'limit':
          hasBytes ? 'opaqueFinalBytes or componentPayloadsAccounted' : 'none',
      'actual': result.outputAccounting.name,
      'bytesPresent': hasBytes,
    },
  );
}
