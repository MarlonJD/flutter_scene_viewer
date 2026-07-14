import 'package:flutter/services.dart';

class FlutterSceneViewerBasisu {
  const FlutterSceneViewerBasisu._();

  static const MethodChannel channel =
      MethodChannel('flutter_scene_viewer/basisu');

  static Future<Map<String, Object?>?> getDecoderAvailability({
    required List<String> requiredExtensions,
    String? source,
  }) {
    return channel.invokeMapMethod<String, Object?>(
      'getDecoderAvailability',
      <String, Object?>{
        'requiredExtensions': requiredExtensions,
        'source': source,
      },
    );
  }

  static Future<Map<String, Object?>?> decodeGlb({
    required Uint8List bytes,
    required List<String> requiredExtensions,
    required Map<String, Object?> decodeBudget,
    required Map<String, Object?> decodeBudgetState,
    String? source,
    List<Object?> basisuImages = const <Object?>[],
  }) {
    return channel.invokeMapMethod<String, Object?>(
      'decodeGlb',
      <String, Object?>{
        'bytes': bytes,
        'requiredExtensions': requiredExtensions,
        'source': source,
        'basisuImages': basisuImages,
        'decodeBudget': decodeBudget,
        'decodeBudgetState': decodeBudgetState,
      },
    );
  }
}
