# Rewritten GLB validation

This host-only harness validates actual rewritten GLB bytes with the official
Khronos glTF Validator package. It pins the prerelease
`gltf-validator@2.0.0-dev.3.10`, corresponding to upstream commit
`bcd52cc4ba5f333b2999a58f67cc05ddf28b4fb1` under Apache-2.0.

Install the exact lockfile dependency:

```sh
npm ci --ignore-scripts --prefix tools/gltf_rewrite_validation
```

Run the runner contract tests:

```sh
npm test --prefix tools/gltf_rewrite_validation
```

Verify the tracked reports in the default read-only mode. This command runs
each approved fixture through its actual decoder or native bridge, the Dart
rewriter, and the pinned official validator before comparing the normalized
map exactly with the tracked JSON:

```sh
flutter test test/rewritten_glb_validator_test.dart
```

Refresh all three tracked reports only when intentionally accepting new
evidence. The environment variable must be set to the exact value `1`; without
it, the test never writes report files:

```sh
FSV_UPDATE_GLTF_REWRITE_REPORTS=1 flutter test test/rewritten_glb_validator_test.dart
git diff -- tools/gltf_rewrite_validation/reports tools/material_extension_acceptance/manifest.json
flutter test test/rewritten_glb_validator_test.dart
```

The update run is not an approval shortcut. Review every normalized issue and
rewritten SHA-256, update the separate `rewriteValidation` provenance in
`tools/material_extension_acceptance/manifest.json`, and require the final
read-only command to pass. Never regenerate or accept drift silently.

Validate a rewritten GLB:

```sh
npm run validate --prefix tools/gltf_rewrite_validation -- --asset meshopt --input path/to/rewritten.glb
```

The JSON report contains the pinned validator identity, caller-supplied asset
label, rewritten-byte SHA-256, issue counts, and every issue's severity, code,
message, and available location (`pointer`, `offset`, or both). It omits
timestamps and absolute input paths. Reports with any validator error exit
nonzero after the complete normalized JSON report is printed to stdout.

Warnings also exit nonzero by default. A caller may dispose every warning with
one `--allowed-warnings '<json-array>'` argument. Each array entry must exactly
match a normalized warning object, including severity, code, message, and every
reported location field. The complete warning multiset must match: missing,
changed, duplicate, or stale allow-list entries fail validation. The current
Meshopt, Draco, and BasisU gates use no allow-list and require zero warnings.

Passing this harness is evidence only for official validator acceptance of the
actual rewritten core GLB on the host. It is not decoder conformance, rendered
correctness, target runtime, device, packaging, release, or production-ready
evidence. The validator package is a prerelease and remains deliberately pinned
until an explicit evidence update changes both the dependency and identity.
