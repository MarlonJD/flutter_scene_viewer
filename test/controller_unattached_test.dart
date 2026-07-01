import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller explains unattached usage', () async {
    final controller = FlutterSceneViewerController();

    expect(
      () => controller.fitCamera(),
      throwsA(isA<StateError>()),
    );
  });
}
