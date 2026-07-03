import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/normal_map_scaler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scaleNormalMapRgba flattens normals at zero intensity', () {
    final scaled = scaleNormalMapRgba(
      Uint8List.fromList(<int>[191, 128, 238, 77]),
      0,
    );

    expect(scaled, <int>[128, 128, 255, 77]);
  });

  test('scaleNormalMapRgba increases xy displacement and preserves alpha', () {
    final scaled = scaleNormalMapRgba(
      Uint8List.fromList(<int>[191, 128, 238, 77]),
      2,
    );

    expect(scaled[0], greaterThan(191));
    expect(scaled[1], closeTo(128, 1));
    expect(scaled[2], lessThan(238));
    expect(scaled[3], 77);
  });
}
