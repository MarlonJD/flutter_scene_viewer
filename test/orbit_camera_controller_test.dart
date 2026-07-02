import 'dart:math' as math;

import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_scene_viewer/src/orbit_camera_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default controller starts from an oblique inspection angle', () {
    final controller = OrbitCameraController();

    expect(controller.state.yawRadians, closeTo(math.pi / 4, 1e-9));
    expect(controller.state.pitchRadians, closeTo(math.pi / 6, 1e-9));
    expect(controller.state.position[0], greaterThan(0));
    expect(controller.state.position[1], greaterThan(0));
    expect(controller.state.position[2], greaterThan(0));
  });

  test('zoom scales distance within configured bounds', () {
    final controller = OrbitCameraController(
      initialState: const OrbitCameraState(distance: 10),
      minDistance: 2,
      maxDistance: 20,
    );

    controller.zoom(0.5);
    expect(controller.state.distance, 5);

    controller.zoom(100);
    expect(controller.state.distance, 20);
  });

  test('orbit changes yaw and clamps pitch away from the poles', () {
    final controller = OrbitCameraController(
      initialState: const OrbitCameraState(distance: 4),
    );

    controller.orbit(
      yawDeltaRadians: math.pi / 2,
      pitchDeltaRadians: math.pi,
    );

    expect(controller.state.yawRadians, closeTo(math.pi / 2, 1e-9));
    expect(controller.state.pitchRadians, lessThan(math.pi / 2));
    expect(controller.state.distance, 4);
  });

  test('pan moves the target along camera right and world up axes', () {
    final controller = OrbitCameraController(
      initialState: const OrbitCameraState(distance: 4),
    );

    controller.pan(rightDelta: 2, upDelta: -1);

    expect(controller.state.target, <double>[2, -1, 0]);
  });

  test('fitBounds centers target and computes distance from field of view', () {
    final controller = OrbitCameraController();

    controller.fitBounds(
      const ViewerBounds(center: <double>[1, 2, 3], radius: 2),
      verticalFovRadians: math.pi / 2,
    );

    expect(controller.state.target, <double>[1, 2, 3]);
    expect(controller.state.distance, closeTo(2 / math.sin(math.pi / 4), 1e-9));
  });

  test('camera state converts to render camera frame', () {
    const state = OrbitCameraState(
      target: <double>[1, 2, 3],
      distance: 4,
      yawRadians: math.pi / 2,
    );

    final frame = state.toRenderCameraFrame(verticalFovRadians: math.pi / 3);

    expect(frame, isA<RenderCameraFrame>());
    expect(frame.target, <double>[1, 2, 3]);
    expect(frame.position[0], closeTo(5, 1e-9));
    expect(frame.position[1], closeTo(2, 1e-9));
    expect(frame.position[2], closeTo(3, 1e-9));
    expect(frame.up, <double>[0, 1, 0]);
    expect(frame.verticalFovRadians, closeTo(math.pi / 3, 1e-9));
  });
}
