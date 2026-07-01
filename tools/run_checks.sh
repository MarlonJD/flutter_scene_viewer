#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p tools/out

echo "== repo lint =="
python3 tools/repo_lint.py | tee tools/out/repo_lint.log

if command -v dart >/dev/null 2>&1; then
  echo "== dart format check =="
  dart format --set-exit-if-changed lib test | tee tools/out/dart_format.log
else
  echo "dart not found; skipping format" | tee tools/out/dart_missing.log
fi

if command -v flutter >/dev/null 2>&1; then
  echo "== flutter pub get =="
  flutter pub get | tee tools/out/flutter_pub_get.log
  echo "== flutter analyze =="
  flutter analyze | tee tools/out/flutter_analyze.log
  echo "== flutter test =="
  flutter test | tee tools/out/flutter_test.log
else
  echo "flutter not found; skipping analyze/test" | tee tools/out/flutter_missing.log
fi

echo "== done =="
