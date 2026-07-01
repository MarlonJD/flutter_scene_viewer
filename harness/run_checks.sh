#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p harness/out

echo "== repo lint =="
python3 harness/repo_lint.py | tee harness/out/repo_lint.log

if command -v dart >/dev/null 2>&1; then
  echo "== dart format check =="
  dart format --set-exit-if-changed lib test | tee harness/out/dart_format.log
else
  echo "dart not found; skipping format" | tee harness/out/dart_missing.log
fi

if command -v flutter >/dev/null 2>&1; then
  echo "== flutter pub get =="
  flutter pub get | tee harness/out/flutter_pub_get.log
  echo "== flutter analyze =="
  flutter analyze | tee harness/out/flutter_analyze.log
  echo "== flutter test =="
  flutter test | tee harness/out/flutter_test.log
else
  echo "flutter not found; skipping analyze/test" | tee harness/out/flutter_missing.log
fi

echo "== done =="
