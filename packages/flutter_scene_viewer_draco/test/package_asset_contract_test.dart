import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _assetHashes = <String, String>{
  'third_party/draco/LICENSE':
      'd3709b0fb4b8a94bbb1d02b8a2e484f258b0d9c5c5a01f940391f3fe662cd1a4',
  'third_party/draco/FSV_LOCAL_MODIFICATIONS.md':
      'dfc98cfc0a5c39dbd101cd7f7dfba4a0f88f1e228196a49180661d0d754c7a5f',
  'third_party/draco/FSV_CODEC_CONTROL_PROVENANCE.sha256':
      'c0f35d2a72af260dd0717e1a6dcfe7968b859ba41cbc0f7fe8c7caeb290ba766',
};

void main() {
  test('packages exact Draco attribution and provenance assets', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final assets = RegExp(
      r'^  assets:\n((?:    - .+\n)+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(assets, isNotNull);
    final declared = assets!
        .group(1)!
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) => line.substring('    - '.length))
        .toSet();
    expect(declared, _assetHashes.keys.toSet());

    for (final entry in _assetHashes.entries) {
      final file = File(entry.key);
      expect(await file.exists(), isTrue, reason: entry.key);
      final hash = await Process.run('shasum', <String>[
        '-a',
        '256',
        entry.key,
      ]);
      expect(hash.exitCode, 0, reason: '${hash.stdout}\n${hash.stderr}');
      expect('${hash.stdout}'.split(' ').first, entry.value, reason: entry.key);
    }

    final provenance = await File(
      'third_party/draco/FSV_CODEC_CONTROL_PROVENANCE.sha256',
    ).readAsString();
    expect(
      provenance,
      contains(
        'upstream=google/draco@1.5.7 '
        'commit=8786740086a9f4d83f44aa83badfbea4dce7a1b5',
      ),
    );
    expect(
      provenance,
      contains(
        'compiled_manifest=android/CMakeLists.txt+'
        'ios/Classes/fsv_draco_vendor_sources.cc',
      ),
    );
    final entries = RegExp(
      r'^original=[0-9a-f]{64} patched=([0-9a-f]{64}) path=(.+)$',
      multiLine: true,
    ).allMatches(provenance);
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      final source = File('third_party/draco/${entry.group(2)}');
      expect(await source.exists(), isTrue, reason: source.path);
      final hash = await Process.run('shasum', <String>[
        '-a',
        '256',
        source.path,
      ]);
      expect('${hash.stdout}'.split(' ').first, entry.group(1));
    }
    final addedEntries = RegExp(
      r'^added=([0-9a-f]{64}) path=(.+)$',
      multiLine: true,
    ).allMatches(provenance);
    expect(addedEntries, isNotEmpty);
    for (final entry in addedEntries) {
      final source = File('third_party/draco/${entry.group(2)}');
      expect(await source.exists(), isTrue, reason: source.path);
      final hash = await Process.run('shasum', <String>[
        '-a',
        '256',
        source.path,
      ]);
      expect('${hash.stdout}'.split(' ').first, entry.group(1));
    }
  });
}
