# Harness

This directory contains agent-runnable verification tools.

## Main command

```sh
bash harness/run_checks.sh
```

The script attempts:

1. repo structure lint;
2. Dart/Flutter formatting;
3. Flutter analyze;
4. Flutter tests.

If Flutter is missing, the script reports the missing toolchain and still runs
Python repository lints.
