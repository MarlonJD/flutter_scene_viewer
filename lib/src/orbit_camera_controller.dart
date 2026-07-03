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
    double minDistance = 0.05,
    double maxDistance = 100000,
  })  : _state = initialState,
        _baseMinDistance = minDistance,
        _baseMaxDistance = maxDistance,
        _minDistance = minDistance,
        _maxDistance = maxDistance;

  static const double maxPitchRadians = math.pi / 2 - 0.001;
  static const double preventModelEntryMinDistanceFactor = 1.05;
  static const double allowModelEntryMinDistanceFactor = 0.25;

  final double _baseMinDistance;
  final double _baseMaxDistance;
  double _minDistance;
  double _maxDistance;
  OrbitCameraState _state;

  OrbitCameraState get state => _state;

  double get minDistance => _minDistance;

  double get maxDistance => _maxDistance;

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
          _minDistance,
          _maxDistance,
        ),
      ),
    );
  }

  void setOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) {
    _setState(
      _state.copyWith(
        target: target == null ? null : List<double>.unmodifiable(target),
        distance: distance == null
            ? null
            : _clampDouble(distance, _minDistance, _maxDistance),
        yawRadians: yawRadians,
        pitchRadians: pitchRadians == null
            ? null
            : _clampDouble(
                pitchRadians,
                -maxPitchRadians,
                maxPitchRadians,
              ),
      ),
    );
  }

  void setPosition({
    required List<double> position,
    required List<double> target,
  }) {
    final dx = position[0] - target[0];
    final dy = position[1] - target[1];
    final dz = position[2] - target[2];
    final rawDistance = math.sqrt(dx * dx + dy * dy + dz * dz);
    final distance = _clampDouble(rawDistance, _minDistance, _maxDistance);
    final yaw = rawDistance <= 0 ? _state.yawRadians : math.atan2(dx, dz);
    final pitch = rawDistance <= 0
        ? _state.pitchRadians
        : math.asin(_clampDouble(dy / rawDistance, -1, 1));
    setOrbit(
      target: target,
      distance: distance,
      yawRadians: yaw,
      pitchRadians: pitch,
    );
  }

  void fitBounds(
    ViewerBounds bounds, {
    double verticalFovRadians = math.pi / 3,
    double aspectRatio = 1,
    double padding = 1,
    double minDistanceFactor = preventModelEntryMinDistanceFactor,
    double maxDistanceFactor = 6,
  }) {
    final safeRadius = math.max(bounds.radius, _baseMinDistance);
    final halfVerticalFov = _clampDouble(
      verticalFovRadians / 2,
      0.001,
      math.pi / 2 - 0.001,
    );
    final safeAspectRatio =
        aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.0;
    final halfHorizontalFov =
        math.atan(math.tan(halfVerticalFov) * safeAspectRatio);
    final halfFov = math.min(halfVerticalFov, halfHorizontalFov);
    final fitDistance = safeRadius * padding / math.sin(halfFov);
    _setDistanceLimits(
      minDistance: safeRadius * minDistanceFactor,
      maxDistance: fitDistance * maxDistanceFactor,
    );
    _setState(
      _state.copyWith(
        target: List<double>.unmodifiable(bounds.center),
        distance: _clampDouble(
          fitDistance,
          _minDistance,
          _maxDistance,
        ),
      ),
    );
  }

  void _setDistanceLimits({
    required double minDistance,
    required double maxDistance,
  }) {
    final nextMinDistance = math.max(_baseMinDistance, minDistance);
    final nextMaxDistance = math.min(_baseMaxDistance, maxDistance);
    _minDistance = nextMinDistance;
    _maxDistance = math.max(nextMinDistance, nextMaxDistance);
  }

  void _setState(OrbitCameraState value) {
    _state = value;
    notifyListeners();
  }
}

double _clampDouble(double value, double lowerLimit, double upperLimit) {
  return math.min(math.max(value, lowerLimit), upperLimit);
}
