/// Controls when the viewer should render frames.
enum RenderPolicy {
  /// Render continuously. Useful for debugging and animated scenes.
  always,

  /// Render only when explicitly invalidated.
  onDemand,

  /// Render while the user interacts, then stop after a short tail.
  whileInteracting,

  /// Adaptive default: loading, interaction, material changes, and animations.
  adaptive,
}
