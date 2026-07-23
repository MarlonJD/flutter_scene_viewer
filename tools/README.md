# Tools

This directory contains repo-local verification tools.

## Main command

```sh
bash tools/run_checks.sh
```

The script attempts:

1. repository-native harness validation;
2. repo structure lint;
3. Dart/Flutter formatting;
4. Flutter analyze;
5. Flutter tests.

If Flutter is missing, the script reports the missing toolchain and still runs
Python repository lints.

## Harness commands

```sh
python3 tools/harness_gate.py
python3 tools/harness_gate.py --require-harness-ready
```

The first command validates the repository-owned structural harness and may
report the certification state as `candidate-only`. The strict command requires
`FSV_HARNESS_ATTESTATION_KEY_FILE` and passes only for a fresh clean
source/direct-child attestation pair with complete schema-v2 evidence. It does
not grant release or production authority.
