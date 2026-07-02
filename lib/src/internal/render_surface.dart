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

/// Opaque adapter-owned render surface for a loaded scene.
@internal
abstract interface class AdapterRenderScene {
  Widget buildView({
    Key? key,
    required RenderCameraFrame camera,
    required bool autoTick,
  });
}
