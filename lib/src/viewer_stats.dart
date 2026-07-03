/// Debug/smoke evidence snapshot for the viewer state.
final class ViewerStatsSnapshot {
  const ViewerStatsSnapshot({
    required this.framesPerSecond,
    required this.frameIntervalAverageMs,
    required this.frameIntervalMinMs,
    required this.frameIntervalMaxMs,
    required this.renderPolicyActive,
    required this.autoTick,
    required this.autoOrbit,
    required this.cameraDistance,
    required this.cameraPosition,
    required this.diagnosticsCount,
    this.lastDiagnosticCode,
    this.modelLoadDuration,
    this.modelByteSize,
    this.nodeCount,
    this.meshCount,
    this.materialCount,
    this.primitiveCount,
  });

  final int framesPerSecond;
  final double frameIntervalAverageMs;
  final double frameIntervalMinMs;
  final double frameIntervalMaxMs;
  final bool renderPolicyActive;
  final bool autoTick;
  final bool autoOrbit;
  final double cameraDistance;
  final List<double> cameraPosition;
  final int diagnosticsCount;
  final String? lastDiagnosticCode;
  final Duration? modelLoadDuration;
  final int? modelByteSize;
  final int? nodeCount;
  final int? meshCount;
  final int? materialCount;
  final int? primitiveCount;
}
