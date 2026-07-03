/// Whether an imported material responds to scene lighting.
enum MaterialShadingMode {
  lit,
  unlit,
  unknown,
}

/// Import-time preference for choosing base material shader behavior.
enum MaterialShadingPolicy {
  /// Preserve the material shading mode authored in the GLB.
  authored,

  /// Convert supported imported materials to lit scene-light-responsive
  /// materials during load.
  forceLit,

  /// Convert supported imported materials to unlit texture/color materials
  /// during load.
  forceUnlit,
}
