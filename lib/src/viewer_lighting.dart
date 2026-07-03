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
    required this.keyLightCastsShadow,
    required this.keyLightShadowMapResolution,
    required this.keyLightShadowMaxDistance,
    required this.keyLightShadowSoftness,
    required this.keyLightShadowFadeRange,
    required this.keyLightShadowDepthBias,
    required this.keyLightShadowNormalBias,
    required this.keyLightShadowCascadeCount,
    required this.keyLightShadowCascadeSplitLambda,
  });

  const ViewerLighting.studio({
    double exposure = 1.0,
    bool ambientOcclusion = false,
    double environmentIntensity = 1.0,
    double keyLightIntensity = 3.0,
    List<double> keyLightColor = const <double>[1.0, 1.0, 1.0],
    List<double> keyLightDirection = const <double>[-0.45, -0.85, -0.35],
    bool keyLightCastsShadow = false,
    int keyLightShadowMapResolution = 1024,
    double keyLightShadowMaxDistance = 150.0,
    double keyLightShadowSoftness = 0.08,
    double keyLightShadowFadeRange = 2.0,
    double keyLightShadowDepthBias = 0.02,
    double keyLightShadowNormalBias = 0.02,
    int keyLightShadowCascadeCount = 4,
    double keyLightShadowCascadeSplitLambda = 0.6,
  }) : this._(
          kind: ViewerLightingKind.studio,
          exposure: exposure,
          ambientOcclusion: ambientOcclusion,
          environmentIntensity: environmentIntensity,
          keyLightIntensity: keyLightIntensity,
          keyLightColor: keyLightColor,
          keyLightDirection: keyLightDirection,
          keyLightCastsShadow: keyLightCastsShadow,
          keyLightShadowMapResolution: keyLightShadowMapResolution,
          keyLightShadowMaxDistance: keyLightShadowMaxDistance,
          keyLightShadowSoftness: keyLightShadowSoftness,
          keyLightShadowFadeRange: keyLightShadowFadeRange,
          keyLightShadowDepthBias: keyLightShadowDepthBias,
          keyLightShadowNormalBias: keyLightShadowNormalBias,
          keyLightShadowCascadeCount: keyLightShadowCascadeCount,
          keyLightShadowCascadeSplitLambda: keyLightShadowCascadeSplitLambda,
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
          keyLightCastsShadow: false,
          keyLightShadowMapResolution: 1024,
          keyLightShadowMaxDistance: 150.0,
          keyLightShadowSoftness: 0.08,
          keyLightShadowFadeRange: 2.0,
          keyLightShadowDepthBias: 0.02,
          keyLightShadowNormalBias: 0.02,
          keyLightShadowCascadeCount: 4,
          keyLightShadowCascadeSplitLambda: 0.6,
        );

  final ViewerLightingKind kind;
  final double exposure;
  final bool ambientOcclusion;
  final double environmentIntensity;
  final double keyLightIntensity;
  final List<double> keyLightColor;
  final List<double> keyLightDirection;
  final bool keyLightCastsShadow;
  final int keyLightShadowMapResolution;
  final double keyLightShadowMaxDistance;
  final double keyLightShadowSoftness;
  final double keyLightShadowFadeRange;
  final double keyLightShadowDepthBias;
  final double keyLightShadowNormalBias;
  final int keyLightShadowCascadeCount;
  final double keyLightShadowCascadeSplitLambda;
}

enum ViewerLightingKind { studio, none }
