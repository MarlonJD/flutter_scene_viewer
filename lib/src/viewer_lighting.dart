/// Viewer-controlled lighting preset.
final class ViewerLighting {
  const ViewerLighting._({required this.kind, required this.exposure});

  const ViewerLighting.studio({double exposure = 1.0})
      : this._(kind: ViewerLightingKind.studio, exposure: exposure);

  const ViewerLighting.none()
      : this._(kind: ViewerLightingKind.none, exposure: 1.0);

  final ViewerLightingKind kind;
  final double exposure;
}

enum ViewerLightingKind { studio, none }
