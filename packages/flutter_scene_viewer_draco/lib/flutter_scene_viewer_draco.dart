import 'package:flutter/services.dart';

class FlutterSceneViewerDraco {
  const FlutterSceneViewerDraco._();

  static const MethodChannel channel =
      MethodChannel('flutter_scene_viewer/draco');

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
    String? source,
    List<Object?> dracoPrimitives = const <Object?>[],
  }) {
    return channel.invokeMapMethod<String, Object?>(
      'decodeGlb',
      <String, Object?>{
        'bytes': bytes,
        'requiredExtensions': requiredExtensions,
        'source': source,
        'dracoPrimitives': dracoPrimitives,
      },
    );
  }
}
