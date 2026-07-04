import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../diagnostics.dart';
import 'glb_basisu_rewriter.dart';
import 'glb_capability_reader.dart';
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
    String? source,
  });
}

/// Result of rewriting a compressed GLB into importer-ready GLB bytes.
final class GlbNativeDecodeResult {
  const GlbNativeDecodeResult({
    this.bytes,
    this.diagnostics = const <ViewerDiagnostic>[],
  });

  final Uint8List? bytes;
  final List<ViewerDiagnostic> diagnostics;
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
    String? source,
  }) async {
    var currentBytes = bytes;
    final diagnostics = <ViewerDiagnostic>[];
    if (requiredExtensions.contains(kDracoMeshCompressionExtension)) {
      final result = await _decodeDracoGlb(
        bytes: currentBytes,
        requiredExtensions: requiredExtensions,
        source: source,
      );
      diagnostics.addAll(result.diagnostics);
      final decodedBytes = result.bytes;
      if (decodedBytes == null) {
        return GlbNativeDecodeResult(
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      currentBytes = decodedBytes;
    }
    if (requiredExtensions.contains(kBasisuTextureExtension)) {
      final result = await _decodeBasisuGlb(
        bytes: currentBytes,
        requiredExtensions: requiredExtensions,
        source: source,
      );
      diagnostics.addAll(result.diagnostics);
      final decodedBytes = result.bytes;
      if (decodedBytes == null) {
        return GlbNativeDecodeResult(
          diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
        );
      }
      currentBytes = decodedBytes;
    }
    return GlbNativeDecodeResult(
      bytes: currentBytes,
      diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
    );
  }

  Future<GlbNativeDecodeResult> _decodeDracoGlb({
    required Uint8List bytes,
    required Set<String> requiredExtensions,
    String? source,
  }) async {
    try {
      final result = await _dracoChannel.invokeMapMethod<String, Object?>(
        'decodeGlb',
        <String, Object?>{
          'bytes': bytes,
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
          'dracoPrimitives': _dracoPrimitiveRequestsFromGlb(bytes),
        },
      );
      return _decodeResultFromMethodResult(
        result,
        sourceBytes: bytes,
        source: source,
      );
    } on MissingPluginException {
      return GlbNativeDecodeResult(
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
    String? source,
  }) async {
    try {
      final result = await _basisuChannel.invokeMapMethod<String, Object?>(
        'decodeGlb',
        <String, Object?>{
          'bytes': bytes,
          'requiredExtensions': requiredExtensions.toList(growable: false),
          'source': source,
          'basisuImages': _basisuImageRequestsFromGlb(bytes),
        },
      );
      return _basisuDecodeResultFromMethodResult(
        result,
        sourceBytes: bytes,
        source: source,
      );
    } on MissingPluginException {
      return GlbNativeDecodeResult(
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
    );
    return GlbNativeDecodeResult(
      bytes: rewrite.bytes,
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
    diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
  );
}

GlbNativeDecodeResult _basisuDecodeResultFromMethodResult(
  Map<String, Object?>? result, {
  required Uint8List sourceBytes,
  required String? source,
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
    );
    return GlbNativeDecodeResult(
      bytes: rewrite.bytes,
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
    final bytes = _bytesFromValue(rawImage['bytes']);
    if (imageIndex is int && mimeType is String && bytes != null) {
      decoded.add(
        GlbDecodedBasisuImage(
          imageIndex: imageIndex,
          mimeType: mimeType,
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

List<Object?> _dracoPrimitiveRequestsFromGlb(Uint8List bytes) {
  final glb = _readGlbForNativeDecode(bytes);
  final json = glb?.json;
  final bin = glb?.bin;
  if (json == null || bin == null) {
    return const <Object?>[];
  }
  final bufferViews = _list(json['bufferViews']);
  final accessors = _list(json['accessors']);
  final meshes = _list(json['meshes']);
  if (bufferViews == null || accessors == null || meshes == null) {
    return const <Object?>[];
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
        if (dracoAttributeId == null) {
          continue;
        }
        attributes[name] = dracoAttributeId;
        final accessorSchema = _accessorDecodeSchema(
          accessors,
          _intValue(primitiveAttributes[name]),
        );
        if (accessorSchema != null) {
          attributeAccessors[name] = accessorSchema;
        }
      }

      requests.add(<String, Object?>{
        'meshIndex': meshIndex,
        'primitiveIndex': primitiveIndex,
        'bufferView': bufferViewIndex,
        'compressedBytes': compressedBytes,
        'attributes': attributes,
        'attributeAccessors': attributeAccessors,
        'indicesAccessor': _accessorDecodeSchema(
          accessors,
          _intValue(primitive['indices']),
        ),
      });
    }
  }
  return List<Object?>.unmodifiable(requests);
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

  final requests = <Object?>[];
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
    final image = _map(images[imageIndex]);
    final bufferViewIndex = _intValue(image?['bufferView']);
    final imageBytes = _bufferViewBytes(bufferViews, bin, bufferViewIndex);
    if (imageBytes == null) {
      continue;
    }
    requests.add(<String, Object?>{
      'textureIndex': textureIndex,
      'imageIndex': imageIndex,
      'bufferView': bufferViewIndex,
      'mimeType': image?['mimeType'],
      'uri': image?['uri'],
      'bytes': imageBytes,
    });
  }
  return List<Object?>.unmodifiable(requests);
}

Map<String, Object?>? _accessorDecodeSchema(
  List<Object?> accessors,
  int? accessorIndex,
) {
  if (accessorIndex == null ||
      accessorIndex < 0 ||
      accessorIndex >= accessors.length) {
    return null;
  }
  final accessor = _map(accessors[accessorIndex]);
  final componentType = _intValue(accessor?['componentType']);
  final count = _intValue(accessor?['count']);
  final type = accessor?['type'];
  if (componentType == null || count == null || type is! String) {
    return null;
  }
  return <String, Object?>{
    'accessorIndex': accessorIndex,
    'componentType': componentType,
    'type': type,
    'count': count,
    'normalized': accessor?['normalized'] == true,
  };
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
