import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'internal/render_surface.dart';

/// Bounding sphere used by the camera fit shell.
@internal
final class ViewerBounds {
  const ViewerBounds({
    this.center = const <double>[0, 0, 0],
    required this.radius,
  });

  final List<double> center;
  final double radius;
}

/// Pure Dart orbit camera state used before adapting to flutter_scene cameras.
@internal
final class OrbitCameraState {
  const OrbitCameraState({
    this.target = const <double>[0, 0, 0],
    this.distance = 4,
    this.yawRadians = 0,
    this.pitchRadians = 0,
  });

  const OrbitCameraState.inspection({
    this.target = const <double>[0, 0, 0],
    this.distance = 4,
    this.yawRadians = math.pi / 4,
    this.pitchRadians = math.pi / 6,
  });

  final List<double> target;
  final double distance;
  final double yawRadians;
  final double pitchRadians;

  List<double> get position {
    final pitchCos = math.cos(pitchRadians);
    return <double>[
      target[0] + distance * math.sin(yawRadians) * pitchCos,
      target[1] + distance * math.sin(pitchRadians),
      target[2] + distance * math.cos(yawRadians) * pitchCos,
    ];
  }

  OrbitCameraState copyWith({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) {
    return OrbitCameraState(
      target: target ?? this.target,
      distance: distance ?? this.distance,
      yawRadians: yawRadians ?? this.yawRadians,
      pitchRadians: pitchRadians ?? this.pitchRadians,
    );
  }

  RenderCameraFrame toRenderCameraFrame({
    double verticalFovRadians = math.pi / 3,
    double near = 0.1,
    double far = 1000,
  }) {
    return RenderCameraFrame(
      position: List<double>.unmodifiable(position),
      target: List<double>.unmodifiable(target),
      verticalFovRadians: verticalFovRadians,
      near: near,
      far: far,
    );
  }
}

/// Orbit, pan, zoom, and fit math for the viewer camera shell.
@internal
final class OrbitCameraController extends ChangeNotifier {
  OrbitCameraController({
    OrbitCameraState initialState = const OrbitCameraState.inspection(),
    this.minDistance = 0.05,
    this.maxDistance = 100000,
  }) : _state = initialState;

  static const double maxPitchRadians = math.pi / 2 - 0.001;

  final double minDistance;
  final double maxDistance;
  OrbitCameraState _state;

  OrbitCameraState get state => _state;

  void orbit({
    required double yawDeltaRadians,
    required double pitchDeltaRadians,
  }) {
    _setState(
      _state.copyWith(
        yawRadians: _state.yawRadians + yawDeltaRadians,
        pitchRadians: _clampDouble(
          _state.pitchRadians + pitchDeltaRadians,
          -maxPitchRadians,
          maxPitchRadians,
        ),
      ),
    );
  }

  void pan({
    required double rightDelta,
    required double upDelta,
  }) {
    final right = <double>[
      math.cos(_state.yawRadians),
      0,
      -math.sin(_state.yawRadians),
    ];
    _setState(
      _state.copyWith(
        target: <double>[
          _state.target[0] + right[0] * rightDelta,
          _state.target[1] + upDelta,
          _state.target[2] + right[2] * rightDelta,
        ],
      ),
    );
  }

  void zoom(double scale) {
    if (!scale.isFinite || scale <= 0) {
      return;
    }
    _setState(
      _state.copyWith(
        distance: _clampDouble(
          _state.distance * scale,
          minDistance,
          maxDistance,
        ),
      ),
    );
  }

  void fitBounds(
    ViewerBounds bounds, {
    double verticalFovRadians = math.pi / 3,
    double padding = 1,
  }) {
    final safeRadius = math.max(bounds.radius, minDistance);
    final halfFov = _clampDouble(
      verticalFovRadians / 2,
      0.001,
      math.pi / 2 - 0.001,
    );
    _setState(
      _state.copyWith(
        target: List<double>.unmodifiable(bounds.center),
        distance: _clampDouble(
          safeRadius * padding / math.sin(halfFov),
          minDistance,
          maxDistance,
        ),
      ),
    );
  }

  void _setState(OrbitCameraState value) {
    _state = value;
    notifyListeners();
  }
}

double _clampDouble(double value, double lowerLimit, double upperLimit) {
  return math.min(math.max(value, lowerLimit), upperLimit);
}
