import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('network sources compare by URL and headers', () {
    final uri = Uri.parse('https://example.com/model.glb');

    expect(
      ModelSource.network(uri, headers: const <String, String>{'A': 'B'}),
      ModelSource.network(uri, headers: const <String, String>{'A': 'B'}),
    );
    expect(
      ModelSource.network(uri, headers: const <String, String>{'A': 'B'}),
      isNot(
        ModelSource.network(uri, headers: const <String, String>{'A': 'C'}),
      ),
    );
  });

  test('byte sources compare by byte-list identity and debug name', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    expect(
      ModelSource.bytes(bytes, debugName: 'inline.glb'),
      ModelSource.bytes(bytes, debugName: 'inline.glb'),
    );
    expect(
      ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3])),
      isNot(ModelSource.bytes(Uint8List.fromList(<int>[1, 2, 3]))),
    );
  });
}
