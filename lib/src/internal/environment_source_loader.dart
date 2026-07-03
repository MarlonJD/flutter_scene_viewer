import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../diagnostics.dart';
import '../viewer_environment.dart';
import 'hdr_environment_decoder.dart';
import 'render_surface.dart';

/// Configuration for encoded HDR environment source loading.
final class EnvironmentSourceLoaderOptions {
  const EnvironmentSourceLoaderOptions({
    this.maxBytes = 50 * 1024 * 1024,
    this.timeout = const Duration(seconds: 30),
  });

  final int maxBytes;
  final Duration timeout;
}

/// Result of resolving an encoded HDR environment source.
final class EnvironmentSourceLoadResult {
  const EnvironmentSourceLoadResult.success(this.decoded)
      : diagnostic = null,
        isCanceled = false;

  const EnvironmentSourceLoadResult.failure(this.diagnostic)
      : decoded = null,
        isCanceled = false;

  const EnvironmentSourceLoadResult.canceled()
      : decoded = null,
        diagnostic = null,
        isCanceled = true;

  final DecodedHdrEnvironment? decoded;
  final ViewerDiagnostic? diagnostic;
  final bool isCanceled;

  bool get isSuccess => decoded != null && diagnostic == null && !isCanceled;
}

/// Loads and decodes environment-only HDR/EXR sources.
final class EnvironmentSourceLoader {
  EnvironmentSourceLoader({
    AssetBundle? assetBundle,
    http.Client? httpClient,
    this.options = const EnvironmentSourceLoaderOptions(),
  })  : assetBundle = assetBundle ?? rootBundle,
        _httpClient = httpClient;

  static final Uri _polyHavenApiOrigin = Uri.parse('https://api.polyhaven.com');

  final AssetBundle assetBundle;
  final EnvironmentSourceLoaderOptions options;
  final http.Client? _httpClient;
  final Map<String, DecodedHdrEnvironment> _polyHavenCache =
      <String, DecodedHdrEnvironment>{};

  Future<EnvironmentSourceLoadResult> load(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    if (_isCanceled(isCanceled)) {
      return const EnvironmentSourceLoadResult.canceled();
    }
    try {
      return switch (frame.kind) {
        RenderEnvironmentKind.rawAsset => await _loadRawAsset(frame),
        RenderEnvironmentKind.rawBytes => _loadRawBytes(frame),
        RenderEnvironmentKind.polyHaven =>
          await _loadPolyHaven(frame, isCanceled: isCanceled),
        _ => EnvironmentSourceLoadResult.failure(
            ViewerDiagnostic(
              code: ViewerDiagnosticCode.environmentSourceUnavailable,
              message: 'Render environment source does not contain HDR bytes.',
              details: <String, Object?>{'kind': frame.kind.name},
            ),
          ),
      };
    } on TimeoutException {
      return EnvironmentSourceLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentLoadTimeout,
          message:
              'Environment source loading exceeded the configured timeout.',
          details: <String, Object?>{
            'kind': frame.kind.name,
            'timeoutMilliseconds': options.timeout.inMilliseconds,
          },
        ),
      );
    } on HdrEnvironmentDecodeException catch (error) {
      return EnvironmentSourceLoadResult.failure(error.diagnostic);
    }
  }

  Future<EnvironmentSourceLoadResult> _loadRawAsset(
    RenderEnvironmentFrame frame,
  ) async {
    final assetPath = frame.assetPath;
    if (assetPath == null || assetPath.isEmpty) {
      return EnvironmentSourceLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.assetLoadFailure,
          message: 'Raw environment asset path is missing.',
          details: <String, Object?>{'kind': frame.kind.name},
        ),
      );
    }
    final bytes = await _loadAssetBytes(assetPath).timeout(options.timeout);
    final sizeDiagnostic = _sizeDiagnostic(bytes.lengthInBytes, assetPath);
    if (sizeDiagnostic != null) {
      return EnvironmentSourceLoadResult.failure(sizeDiagnostic);
    }
    return EnvironmentSourceLoadResult.success(
      HdrEnvironmentDecoder.decode(
        bytes,
        debugName: assetPath,
        format: _viewerFormat(frame.rawFormat),
      ),
    );
  }

  EnvironmentSourceLoadResult _loadRawBytes(RenderEnvironmentFrame frame) {
    final bytes = frame.rawBytes;
    if (bytes == null) {
      return EnvironmentSourceLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentSourceUnavailable,
          message: 'Raw environment byte source is missing.',
          details: <String, Object?>{'kind': frame.kind.name},
        ),
      );
    }
    final debugName = frame.rawDebugName ?? 'bytes';
    final sizeDiagnostic = _sizeDiagnostic(bytes.lengthInBytes, debugName);
    if (sizeDiagnostic != null) {
      return EnvironmentSourceLoadResult.failure(sizeDiagnostic);
    }
    return EnvironmentSourceLoadResult.success(
      HdrEnvironmentDecoder.decode(
        bytes,
        debugName: debugName,
        format: _viewerFormat(frame.rawFormat),
      ),
    );
  }

  Future<EnvironmentSourceLoadResult> _loadPolyHaven(
    RenderEnvironmentFrame frame, {
    bool Function()? isCanceled,
  }) async {
    final assetId = frame.polyHavenAssetId;
    final resolution = frame.polyHavenResolution;
    final fileType = frame.polyHavenFileType;
    final userAgent = frame.polyHavenUserAgent;
    if (assetId == null ||
        assetId.isEmpty ||
        resolution == null ||
        resolution.isEmpty ||
        fileType == null ||
        fileType.isEmpty ||
        userAgent == null ||
        userAgent.isEmpty) {
      return EnvironmentSourceLoadResult.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentSourceUnavailable,
          message: 'Poly Haven environment requires asset id, resolution, '
              'file type, and User-Agent.',
          details: <String, Object?>{
            'assetId': assetId,
            'resolution': resolution,
            'fileType': fileType,
          },
        ),
      );
    }
    final cacheKey = '$assetId|$resolution|$fileType';
    final cached = _polyHavenCache[cacheKey];
    if (cached != null) {
      return EnvironmentSourceLoadResult.success(cached);
    }

    final descriptor = await _polyHavenDescriptor(
      assetId: assetId,
      resolution: resolution,
      fileType: fileType,
      userAgent: userAgent,
    ).timeout(options.timeout);
    final descriptorDiagnostic = descriptor.diagnostic;
    if (descriptorDiagnostic != null) {
      return EnvironmentSourceLoadResult.failure(descriptorDiagnostic);
    }
    if (_isCanceled(isCanceled)) {
      return const EnvironmentSourceLoadResult.canceled();
    }

    final byteSize = descriptor.byteSize;
    if (byteSize != null) {
      final sizeDiagnostic = _sizeDiagnostic(byteSize, descriptor.url);
      if (sizeDiagnostic != null) {
        return EnvironmentSourceLoadResult.failure(sizeDiagnostic);
      }
    }
    final bytes = await _loadNetworkBytes(
      Uri.parse(descriptor.url),
      userAgent: userAgent,
    ).timeout(options.timeout);
    final sizeDiagnostic = _sizeDiagnostic(bytes.lengthInBytes, descriptor.url);
    if (sizeDiagnostic != null) {
      return EnvironmentSourceLoadResult.failure(sizeDiagnostic);
    }
    if (_isCanceled(isCanceled)) {
      return const EnvironmentSourceLoadResult.canceled();
    }

    final decoded = HdrEnvironmentDecoder.decode(
      bytes,
      debugName: descriptor.url,
      format: fileType == 'exr'
          ? ViewerEnvironmentFileFormat.exr
          : ViewerEnvironmentFileFormat.hdr,
    );
    _polyHavenCache[cacheKey] = decoded;
    return EnvironmentSourceLoadResult.success(decoded);
  }

  Future<_PolyHavenDescriptor> _polyHavenDescriptor({
    required String assetId,
    required String resolution,
    required String fileType,
    required String userAgent,
  }) async {
    final uri = _polyHavenApiOrigin.replace(path: '/files/$assetId');
    final response = await _get(uri, userAgent: userAgent);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _PolyHavenDescriptor.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'Poly Haven environment descriptor request failed.',
          details: <String, Object?>{
            'assetId': assetId,
            'statusCode': response.statusCode,
          },
        ),
      );
    }
    final Object? decodedJson;
    try {
      decodedJson = jsonDecode(response.body);
    } on Object catch (error) {
      return _PolyHavenDescriptor.failure(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.environmentDecodeFailure,
          message: 'Poly Haven environment descriptor was not valid JSON.',
          details: <String, Object?>{
            'assetId': assetId,
            'error': error.toString(),
          },
        ),
      );
    }
    if (decodedJson is! Map<String, Object?>) {
      return _missingPolyHavenDescriptor(assetId, resolution, fileType);
    }
    final hdri = decodedJson['hdri'];
    if (hdri is! Map<String, Object?>) {
      return _missingPolyHavenDescriptor(assetId, resolution, fileType);
    }
    final resolutionEntry = hdri[resolution];
    if (resolutionEntry is! Map<String, Object?>) {
      return _missingPolyHavenDescriptor(assetId, resolution, fileType);
    }
    final fileEntry = resolutionEntry[fileType];
    if (fileEntry is! Map<String, Object?>) {
      return _missingPolyHavenDescriptor(assetId, resolution, fileType);
    }
    final url = fileEntry['url'];
    if (url is! String || url.isEmpty) {
      return _missingPolyHavenDescriptor(assetId, resolution, fileType);
    }
    final sizeValue = fileEntry['size'];
    return _PolyHavenDescriptor.success(
      url: url,
      byteSize: sizeValue is int ? sizeValue : null,
    );
  }

  _PolyHavenDescriptor _missingPolyHavenDescriptor(
    String assetId,
    String resolution,
    String fileType,
  ) {
    return _PolyHavenDescriptor.failure(
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.environmentSourceUnavailable,
        message: 'Poly Haven environment file descriptor was not available.',
        details: <String, Object?>{
          'assetId': assetId,
          'resolution': resolution,
          'fileType': fileType,
        },
      ),
    );
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    try {
      return Uint8List.sublistView(await assetBundle.load(assetPath));
    } on Object catch (error) {
      throw HdrEnvironmentDecodeException(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.assetLoadFailure,
          message: 'Failed to load raw environment asset bytes.',
          details: <String, Object?>{
            'assetPath': assetPath,
            'error': error.toString(),
          },
        ),
      );
    }
  }

  Future<Uint8List> _loadNetworkBytes(
    Uri uri, {
    required String userAgent,
  }) async {
    final response = await _get(uri, userAgent: userAgent);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HdrEnvironmentDecodeException(
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.networkFailure,
          message: 'Environment source request failed.',
          details: <String, Object?>{
            'url': uri.toString(),
            'statusCode': response.statusCode,
          },
        ),
      );
    }
    return response.bodyBytes;
  }

  Future<http.Response> _get(
    Uri uri, {
    required String userAgent,
  }) async {
    final headers = <String, String>{'user-agent': userAgent};
    final client = _httpClient;
    if (client != null) {
      return client.get(uri, headers: headers);
    }
    final ownedClient = http.Client();
    try {
      return await ownedClient.get(uri, headers: headers);
    } finally {
      ownedClient.close();
    }
  }

  ViewerDiagnostic? _sizeDiagnostic(int byteLength, String source) {
    if (byteLength <= options.maxBytes) {
      return null;
    }
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.environmentTooLarge,
      message: 'Environment source exceeds the configured byte limit.',
      details: <String, Object?>{
        'source': source,
        'byteLength': byteLength,
        'maxBytes': options.maxBytes,
      },
    );
  }

  ViewerEnvironmentFileFormat _viewerFormat(RenderEnvironmentFileFormat value) {
    return switch (value) {
      RenderEnvironmentFileFormat.auto => ViewerEnvironmentFileFormat.auto,
      RenderEnvironmentFileFormat.hdr => ViewerEnvironmentFileFormat.hdr,
      RenderEnvironmentFileFormat.exr => ViewerEnvironmentFileFormat.exr,
    };
  }

  bool _isCanceled(bool Function()? isCanceled) => isCanceled?.call() ?? false;
}

final class _PolyHavenDescriptor {
  const _PolyHavenDescriptor.success({
    required this.url,
    required this.byteSize,
  }) : diagnostic = null;

  const _PolyHavenDescriptor.failure(this.diagnostic)
      : url = '',
        byteSize = null;

  final String url;
  final int? byteSize;
  final ViewerDiagnostic? diagnostic;
}
