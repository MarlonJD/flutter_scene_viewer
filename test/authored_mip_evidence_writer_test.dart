import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test_driver/authored_mip_evidence_writer.dart';

void main() {
  test('does not create an evidence callback without an explicit host path',
      () {
    expect(
      createAuthoredMipEvidenceCallback(
        repositoryRoot: Directory.current,
        environment: const <String, String>{},
      ),
      isNull,
    );
  });

  test('rejects paths outside the exact Plan 017 artifact root', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'fsv-authored-mip-evidence-root-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final artifactRoot = Directory(
      '${temporary.path}/tools/out/plan017_decoder_mip_acceptance',
    );
    await artifactRoot.create(recursive: true);

    for (final path in <String>[
      '${temporary.path}/tools/out/evidence.json',
      '${temporary.path}/tools/out/other/evidence.json',
      '${artifactRoot.path}/../escaped.json',
      '${artifactRoot.path}/nested/evidence.json',
      '${temporary.path}/build/evidence.json',
      '${artifactRoot.path}/evidence.txt',
    ]) {
      expect(
        () => createAuthoredMipEvidenceCallback(
          repositoryRoot: temporary,
          environment: <String, String>{
            authoredMipEvidenceOutputEnvironmentKey: path,
          },
        ),
        throwsArgumentError,
        reason: path,
      );
    }
  });

  test('rejects artifact directory and output-file symlink escapes', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'fsv-authored-mip-evidence-symlink-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final outside = Directory('${temporary.path}/outside');
    await outside.create();
    final toolsOut = Directory('${temporary.path}/tools/out');
    await toolsOut.create(recursive: true);
    final artifactRoot = Link(
      '${toolsOut.path}/plan017_decoder_mip_acceptance',
    );
    await artifactRoot.create(outside.path);

    expect(
      () => createAuthoredMipEvidenceCallback(
        repositoryRoot: temporary,
        environment: <String, String>{
          authoredMipEvidenceOutputEnvironmentKey:
              '${artifactRoot.path}/escaped.json',
        },
      ),
      throwsArgumentError,
    );

    await artifactRoot.delete();
    final realArtifactRoot = Directory(artifactRoot.path);
    await realArtifactRoot.create();
    final outsideFile = File('${outside.path}/outside.json');
    await outsideFile.writeAsString('{}');
    final outputLink = Link('${realArtifactRoot.path}/evidence.json');
    await outputLink.create(outsideFile.path);

    expect(
      () => createAuthoredMipEvidenceCallback(
        repositoryRoot: temporary,
        environment: <String, String>{
          authoredMipEvidenceOutputEnvironmentKey: outputLink.path,
        },
      ),
      throwsArgumentError,
    );
  });

  test('revalidates an artifact-root symlink swap at callback invocation',
      () async {
    expect(
      _isDocumentedSymlinkUnavailable(
        const FileSystemException(
          'privilege not held',
          '',
          OSError('ERROR_PRIVILEGE_NOT_HELD', 1314),
        ),
        isWindows: true,
      ),
      isTrue,
    );
    expect(
      _isDocumentedSymlinkUnavailable(
        const FileSystemException(
          'access denied',
          '',
          OSError('ERROR_ACCESS_DENIED', 5),
        ),
        isWindows: true,
      ),
      isFalse,
    );
    expect(
      _isDocumentedSymlinkUnavailable(
        const FileSystemException(
          'privilege not held',
          '',
          OSError('ERROR_PRIVILEGE_NOT_HELD', 1314),
        ),
        isWindows: false,
      ),
      isFalse,
    );
    final temporary = await Directory.systemTemp.createTemp(
      'fsv-authored-mip-evidence-root-swap-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final artifactRoot = Directory(
      '${temporary.path}/tools/out/plan017_decoder_mip_acceptance',
    );
    await artifactRoot.create(recursive: true);
    final output = File('${artifactRoot.path}/evidence.json');
    final callback = createAuthoredMipEvidenceCallback(
      repositoryRoot: temporary,
      environment: <String, String>{
        authoredMipEvidenceOutputEnvironmentKey: output.path,
      },
    );
    expect(callback, isNotNull);

    final outside = Directory('${temporary.path}/outside');
    await outside.create();
    await artifactRoot.delete(recursive: true);
    final artifactRootLink = Link(artifactRoot.path);
    if (!await _createSymlinkOrSkip(artifactRootLink, outside.path)) {
      return;
    }

    await expectLater(
      callback!(<String, dynamic>{'targetResult': 'passed'}),
      throwsArgumentError,
    );
    expect(File('${outside.path}/evidence.json').existsSync(), isFalse);
  });

  test('revalidates an output-file symlink swap at callback invocation',
      () async {
    final temporary = await Directory.systemTemp.createTemp(
      'fsv-authored-mip-evidence-output-swap-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final artifactRoot = Directory(
      '${temporary.path}/tools/out/plan017_decoder_mip_acceptance',
    );
    await artifactRoot.create(recursive: true);
    final output = File('${artifactRoot.path}/evidence.json');
    final callback = createAuthoredMipEvidenceCallback(
      repositoryRoot: temporary,
      environment: <String, String>{
        authoredMipEvidenceOutputEnvironmentKey: output.path,
      },
    );
    expect(callback, isNotNull);

    final outside = Directory('${temporary.path}/outside');
    await outside.create();
    final outsideFile = File('${outside.path}/evidence.json');
    await outsideFile.writeAsString('outside sentinel');
    final outputLink = Link(output.path);
    if (!await _createSymlinkOrSkip(outputLink, outsideFile.path)) {
      return;
    }

    await expectLater(
      callback!(<String, dynamic>{'targetResult': 'passed'}),
      throwsArgumentError,
    );
    expect(await outsideFile.readAsString(), 'outside sentinel');
  });

  test('writes deterministic JSON only to the selected tools/out file',
      () async {
    final temporary = await Directory.systemTemp.createTemp(
      'fsv-authored-mip-evidence-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final artifactRoot = Directory(
      '${temporary.path}/tools/out/plan017_decoder_mip_acceptance',
    );
    await artifactRoot.create(recursive: true);
    final output = File('${artifactRoot.path}/authored_mips.json');
    final callback = createAuthoredMipEvidenceCallback(
      repositoryRoot: temporary,
      environment: <String, String>{
        authoredMipEvidenceOutputEnvironmentKey: output.path,
      },
    );
    expect(callback, isNotNull);

    final data = <String, dynamic>{
      'rendererCommit': '5dcf6f',
      'authoredSamples': <List<int>>[
        <int>[255, 0, 0],
        <int>[0, 255, 0],
        <int>[0, 0, 255],
      ],
      'baseOnlySamples': <List<int>>[
        <int>[255, 0, 0],
      ],
      'targetResult': 'passed',
      'evidenceLabel': 'verified locally',
    };
    await callback!(data);
    final first = await output.readAsString();
    await callback(data);
    final second = await output.readAsString();

    expect(first, second);
    expect(first, endsWith('\n'));
    expect(jsonDecode(first), data);
  });
}

Future<bool> _createSymlinkOrSkip(Link link, String target) async {
  try {
    await link.create(target);
    return true;
  } on FileSystemException catch (error) {
    if (_isDocumentedSymlinkUnavailable(error)) {
      markTestSkipped(
        'Windows symlink privilege is unavailable (error 1314): $error',
      );
      return false;
    }
    rethrow;
  }
}

bool _isDocumentedSymlinkUnavailable(
  FileSystemException error, {
  bool? isWindows,
}) {
  return (isWindows ?? Platform.isWindows) && error.osError?.errorCode == 1314;
}
