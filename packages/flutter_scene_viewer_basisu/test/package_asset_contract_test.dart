import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _assetHashes = <String, String>{
  'third_party/basis_universal/LICENSE':
      '065fcf48d6af21c0b75e23be5ed5753aee75c892e1c2cf178fa6736305614a5c',
  'third_party/basis_universal/NOTICE':
      '4e111248d4d7c9881bd40200d8ed5495e632b63bf898afaf4b2d500ad1a20ed3',
  'third_party/basis_universal/FSV_LOCAL_MODIFICATIONS.md':
      '6d9e1984399050c50392c5638431ff6c07b8dcbdd2a879b4c0fb3f17775d6794',
  'third_party/basis_universal/FSV_CODEC_CONTROL_PROVENANCE.sha256':
      '5092aa05cc3a3c1340a610c22b00b70530fd7bff004e42d7d82bf2ace4222dad',
  'third_party/basis_universal/VENDORED_SOURCES.sha256':
      'd675ed64ee129ac46c6f9fe4cc569bf9970bac65a69c7e1b1fc598eafe83bf55',
  'third_party/basis_universal/zstd/LICENSE':
      '2c1a7fa704df8f3a606f6fc010b8b5aaebf403f3aeec339a12048f1ba7331a0b',
};

void main() {
  test('packages exact BasisU attribution and provenance assets', () async {
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
      'third_party/basis_universal/FSV_CODEC_CONTROL_PROVENANCE.sha256',
    ).readAsString();
    expect(
      provenance,
      contains(
        'upstream=BinomialLLC/basis_universal@'
        '882abb5320400ab650c1be33f9152e4955e83af3',
      ),
    );
    expect(
      provenance,
      contains(
        'compiled_manifest=android/CMakeLists.txt+'
        'ios/Classes/fsv_basisu_vendor_sources.cc',
      ),
    );
    final vendorManifest = await Process.run(
      'shasum',
      const <String>['-a', '256', '-c', 'VENDORED_SOURCES.sha256'],
      workingDirectory: 'third_party/basis_universal',
    );
    expect(
      vendorManifest.exitCode,
      0,
      reason: '${vendorManifest.stdout}\n${vendorManifest.stderr}',
    );
  });
}
