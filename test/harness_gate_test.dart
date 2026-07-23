import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository-native harness structure passes in candidate state', () {
    final result = Process.runSync(
      'python3',
      const <String>['tools/harness_gate.py'],
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      result.stdout,
      contains('harness gate passed (certification state: candidate-only)'),
    );
  });

  test('strict harness-ready mode fails closed without attestation inputs', () {
    final environment = Map<String, String>.from(Platform.environment)
      ..remove('FSV_HARNESS_ATTESTATION_KEY_FILE');
    final result = Process.runSync(
      'python3',
      const <String>[
        'tools/harness_gate.py',
        '--require-harness-ready',
      ],
      environment: environment,
    );

    expect(result.exitCode, 1);
    expect(
      result.stdout,
      contains('strict gate requires claim harness-ready'),
    );
    expect(
      result.stdout,
      contains('strict gate requires FSV_HARNESS_ATTESTATION_KEY_FILE'),
    );
  });
}
