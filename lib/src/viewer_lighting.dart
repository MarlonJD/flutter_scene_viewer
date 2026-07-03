/// Viewer-controlled lighting preset.
final class ViewerLighting {
  const ViewerLighting._({
    required this.kind,
    required this.exposure,
    required this.ambientOcclusion,
    required this.environmentIntensity,
    required this.keyLightIntensity,
    required this.keyLightColor,
    required this.keyLightDirection,
  });

  const ViewerLighting.studio({
    double exposure = 1.0,
    bool ambientOcclusion = false,
    double environmentIntensity = 1.0,
    double keyLightIntensity = 3.0,
    List<double> keyLightColor = const <double>[1.0, 1.0, 1.0],
    List<double> keyLightDirection = const <double>[-0.45, -0.85, -0.35],
  }) : this._(
          kind: ViewerLightingKind.studio,
          exposure: exposure,
          ambientOcclusion: ambientOcclusion,
          environmentIntensity: environmentIntensity,
          keyLightIntensity: keyLightIntensity,
          keyLightColor: keyLightColor,
          keyLightDirection: keyLightDirection,
        );

  const ViewerLighting.none()
      : this._(
          kind: ViewerLightingKind.none,
          exposure: 1.0,
          ambientOcclusion: false,
          environmentIntensity: 0.0,
          keyLightIntensity: 0.0,
          keyLightColor: const <double>[0.0, 0.0, 0.0],
          keyLightDirection: const <double>[0, -1, 0],
        );

  final ViewerLightingKind kind;
  final double exposure;
  final bool ambientOcclusion;
  final double environmentIntensity;
  final double keyLightIntensity;
  final List<double> keyLightColor;
  final List<double> keyLightDirection;
}

enum ViewerLightingKind { studio, none }
