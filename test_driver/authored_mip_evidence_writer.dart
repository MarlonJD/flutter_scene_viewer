import 'dart:convert';
import 'dart:io';

const String authoredMipEvidenceOutputEnvironmentKey =
    'FSV_AUTHORED_MIP_EVIDENCE_OUTPUT';

typedef AuthoredMipEvidenceCallback = Future<void> Function(
  Map<String, dynamic>? data,
);

AuthoredMipEvidenceCallback? createAuthoredMipEvidenceCallback({
  required Directory repositoryRoot,
  Map<String, String>? environment,
}) {
  final configured = (environment ??
      Platform.environment)[authoredMipEvidenceOutputEnvironmentKey];
  if (configured == null || configured.isEmpty) {
    return null;
  }
  final validated = _validatedOutputFile(
    configured,
    repositoryRoot: repositoryRoot,
  );
  return (data) => _writeEvidence(
        validated.output,
        validated.artifactRoot,
        data,
      );
}

({File output, Directory artifactRoot}) _validatedOutputFile(
  String configured, {
  required Directory repositoryRoot,
}) {
  if (configured.trim() != configured || configured.contains('\u0000')) {
    throw ArgumentError.value(configured, 'outputPath', 'Invalid path.');
  }
  final rawSegments = configured.replaceAll('\\', '/').split('/');
  if (rawSegments.any((segment) => segment == '.' || segment == '..')) {
    throw ArgumentError.value(
      configured,
      'outputPath',
      'Path traversal is not allowed.',
    );
  }

  if (!repositoryRoot.existsSync()) {
    throw ArgumentError.value(
      repositoryRoot.path,
      'repositoryRoot',
      'Repository root must exist.',
    );
  }
  final canonicalRepositoryRoot = Directory(
    repositoryRoot.absolute.resolveSymbolicLinksSync(),
  );
  final separator = Platform.pathSeparator;
  final artifactRoot = Directory(
    '${canonicalRepositoryRoot.path}${separator}tools${separator}out'
    '${separator}plan017_decoder_mip_acceptance',
  ).absolute;
  final configuredOutput = File(configured).absolute;
  if (!configuredOutput.parent.existsSync() ||
      configuredOutput.parent.resolveSymbolicLinksSync() != artifactRoot.path) {
    throw ArgumentError.value(
      configured,
      'outputPath',
      'Evidence must be a direct child of the Plan 017 artifact root.',
    );
  }
  final filename = configuredOutput.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .last;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.json$').hasMatch(filename)) {
    throw ArgumentError.value(
      configured,
      'outputPath',
      'Evidence filename must be a safe .json filename.',
    );
  }
  final output = File('${artifactRoot.path}${Platform.pathSeparator}$filename');
  _rejectSymlinkEscape(output, artifactRoot, configured: configured);
  return (output: output, artifactRoot: artifactRoot);
}

void _rejectSymlinkEscape(
  File output,
  Directory artifactRoot, {
  required String configured,
}) {
  if (!artifactRoot.existsSync() ||
      artifactRoot.resolveSymbolicLinksSync() != artifactRoot.path) {
    throw ArgumentError.value(
      configured,
      'outputPath',
      'Plan 017 artifact root must exist and cannot be a symlink.',
    );
  }
  final outputType = FileSystemEntity.typeSync(
    output.path,
    followLinks: false,
  );
  if (outputType == FileSystemEntityType.link ||
      outputType == FileSystemEntityType.directory) {
    throw ArgumentError.value(
      configured,
      'outputPath',
      'Evidence output cannot be a symlink or directory.',
    );
  }
}

Future<void> _writeEvidence(
  File output,
  Directory artifactRoot,
  Map<String, dynamic>? data,
) async {
  if (data == null) {
    throw StateError('The authored-mip integration test returned no data.');
  }
  _rejectSymlinkEscape(output, artifactRoot, configured: output.path);
  final encoded = const JsonEncoder.withIndent('  ').convert(data);
  await output.writeAsString('$encoded\n', flush: true);
}
