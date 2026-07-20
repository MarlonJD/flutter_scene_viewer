import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

import 'authored_mip_evidence_writer.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: createAuthoredMipEvidenceCallback(
        repositoryRoot: Directory.current,
      ),
    );
