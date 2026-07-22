import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authored mip GPU probe reports the current renderer revision', () {
    final harness = File(
      'integration_test/authored_mip_sampling_test.dart',
    ).readAsStringSync();
    final revisionMatches = RegExp(
      r"const String _pinnedFlutterSceneCommit\s*=\s*'([0-9a-f]{40})';",
    ).allMatches(harness).toList();

    expect(revisionMatches, hasLength(1));
    expect(
      revisionMatches.single.group(1),
      '766351c865c621e8720c726f9aa51173ce76e786',
    );
  });

  test('authored mip GPU probe owns explicit LOD and a base-only control', () {
    final manifest = jsonDecode(
      File(
        'shaders/fsviewer_extended_pbr.shaderbundle.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final entry = manifest['FSViewerAuthoredMipProbe'];

    expect(
      entry,
      <String, Object?>{
        'type': 'fragment',
        'file': 'shaders/fsviewer_authored_mip_probe.frag',
      },
    );

    final shader = File(
      'shaders/fsviewer_authored_mip_probe.frag',
    ).readAsStringSync();
    expect(shader, contains('textureLod(authored_mip_texture'));
    expect(shader, contains('lod = 0.0'));
    expect(shader, contains('lod = 1.0'));
    expect(shader, contains('lod = 2.0'));

    final harness = File(
      'integration_test/authored_mip_sampling_test.dart',
    ).readAsStringSync();
    expect(harness, contains('_solidLevel(0, 8, 8, 255, 0, 0)'));
    expect(harness, contains('_solidLevel(1, 4, 4, 0, 255, 0)'));
    expect(harness, contains('_solidLevel(2, 2, 2, 0, 0, 255)'));
    expect(
      harness,
      contains('expect(_matchesAuthoredMipBands(baseOnlySamples), isFalse)'),
    );
    expect(
      harness,
      contains(
        'Future<List<_RgbSample>> _readAndDisposeBandSamples(ui.Image image)',
      ),
    );
    expect(
      harness,
      matches(
        RegExp(
          r'_readAndDisposeBandSamples\(ui\.Image image\).*?'
          r'try \{.*?_readBandSamples\(image\).*?'
          r'\} finally \{\s*image\.dispose\(\);',
          dotAll: true,
        ),
      ),
    );
    expect(harness, contains('Future<ui.Image> _pictureToImage('));
    expect(
      harness,
      matches(
        RegExp(
          r'_pictureToImage\(.*?final imageFuture = picture\.toImage.*?'
          r'on TimeoutException.*?imageFuture\.then<void>.*?image\.dispose\(\)',
          dotAll: true,
        ),
      ),
    );
    expect(
      harness,
      contains('binding.reportData = <String, dynamic>{'),
    );
    for (final field in <String>[
      "'rendererCommit': _pinnedFlutterSceneCommit",
      "'authoredSamples':",
      "'baseOnlySamples':",
      "'targetResult': 'passed'",
      "'evidenceLabel': 'verified locally'",
    ]) {
      expect(harness, contains(field), reason: field);
    }

    final driver = File('test_driver/integration_test.dart').readAsStringSync();
    expect(driver, contains('createAuthoredMipEvidenceCallback('));
    expect(driver, contains('repositoryRoot: Directory.current'));
  });
}
