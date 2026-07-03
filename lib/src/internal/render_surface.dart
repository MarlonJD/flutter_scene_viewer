import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Adapter-neutral camera values used to build a concrete render camera.
@internal
final class RenderCameraFrame {
  const RenderCameraFrame({
    required this.position,
    required this.target,
    this.up = const <double>[0, 1, 0],
    this.verticalFovRadians = 1.0471975511965976,
    this.near = 0.1,
    this.far = 1000,
  });

  final List<double> position;
  final List<double> target;
  final List<double> up;
  final double verticalFovRadians;
  final double near;
  final double far;
}

/// Adapter-neutral lighting values used to configure a concrete scene.
@internal
final class RenderLightingFrame {
  const RenderLightingFrame({
    required this.kind,
    required this.exposure,
    this.ambientOcclusionEnabled = false,
    this.environmentIntensity = 1.0,
    this.keyLightIntensity = 3.0,
    this.keyLightColor = const <double>[1.0, 1.0, 1.0],
    this.keyLightDirection = const <double>[-0.45, -0.85, -0.35],
  });

  final RenderLightingKind kind;
  final double exposure;
  final bool ambientOcclusionEnabled;
  final double environmentIntensity;
  final double keyLightIntensity;
  final List<double> keyLightColor;
  final List<double> keyLightDirection;
}

@internal
enum RenderLightingKind { studio, none }

/// Adapter-neutral environment values used to configure a concrete scene.
@internal
final class RenderEnvironmentFrame {
  const RenderEnvironmentFrame({
    required this.kind,
    this.assetPath,
    this.rawBytes,
    this.rawDebugName,
    this.rawFormat = RenderEnvironmentFileFormat.auto,
    this.polyHavenAssetId,
    this.polyHavenResolution,
    this.polyHavenFileType,
    this.polyHavenUserAgent,
    this.intensity = 1.0,
    this.rotationRadians = 0.0,
    this.showSkybox = false,
    this.skyboxBlur = 0.0,
  });

  final RenderEnvironmentKind kind;
  final String? assetPath;
  final Uint8List? rawBytes;
  final String? rawDebugName;
  final RenderEnvironmentFileFormat rawFormat;
  final String? polyHavenAssetId;
  final String? polyHavenResolution;
  final String? polyHavenFileType;
  final String? polyHavenUserAgent;
  final double intensity;
  final double rotationRadians;
  final bool showSkybox;
  final double skyboxBlur;
}

@internal
enum RenderEnvironmentKind {
  studio,
  empty,
  asset,
  rawAsset,
  rawBytes,
  polyHaven
}

@internal
enum RenderEnvironmentFileFormat { auto, hdr, exr }

/// Adapter-neutral model bounds used for camera fitting.
@internal
final class AdapterModelBounds {
  const AdapterModelBounds({
    required this.center,
    required this.radius,
  });

  final List<double> center;
  final double radius;
}

/// Opaque adapter-owned render surface for a loaded scene.
@internal
abstract interface class AdapterRenderScene {
  Widget buildView({
    Key? key,
    required RenderCameraFrame camera,
    required RenderLightingFrame lighting,
    required RenderEnvironmentFrame environment,
    required bool autoTick,
  });
}
