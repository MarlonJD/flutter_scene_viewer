import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'material_shading_mode.dart';
import 'model_source.dart';
import 'part_registry.dart';

/// Configuration for runtime GLB loading.
final class ModelLoaderOptions {
  const ModelLoaderOptions({
    this.maxBytes = 50 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
  });

  final int maxBytes;
  final Duration timeout;
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
        primitiveCount = null;

  final ViewerDiagnostic? diagnostic;
  final List<ViewerDiagnostic> diagnostics;
  final PartTree partTree;
  final Duration? modelLoadDuration;
  final int? modelByteSize;
  final int? nodeCount;
  final int? meshCount;
  final int? materialCount;
  final int? primitiveCount;

  bool get isSuccess => diagnostic == null;
}

/// Loads GLB bytes from a [ModelSource] and dispatches them to flutter_scene.
final class ModelLoader {
  ModelLoader({
    required this.adapter,
    AssetBundle? assetBundle,
    http.Client? httpClient,
    this.options = const ModelLoaderOptions(),
  })  : assetBundle = assetBundle ?? rootBundle,
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  final FlutterSceneAdapter adapter;
  final AssetBundle assetBundle;
  final ModelLoaderOptions options;
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

    try {
      await adapter
          .loadGlbBytes(
            loaded.bytes,
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
      );
    } on TimeoutException {
      return ModelLoadResult.failure(_timeoutDiagnostic(source));
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
      );
    }

    final snapshot = adapter.nodeSnapshot;
    final registry = _buildPartRegistry(snapshot);
    final fallbackStats = _modelStatsFromSnapshot(snapshot);
    final adapterStats = adapter.modelStats;
    return ModelLoadResult.success(
      diagnostics: <ViewerDiagnostic>[
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
