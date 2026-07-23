# Security

This repository ships a local Flutter library, not an authenticated service.
It has no production database, server-side authorization layer, or repository
owned secret. Security work therefore centers on untrusted model bytes,
network retrieval, native decoder boundaries, dependency provenance, and safe
resource limits.

## Trust boundaries

| Boundary | Invariant | Enforcer | Verification | Owner/update trigger |
| --- | --- | --- | --- | --- |
| Network, asset, and caller-provided model bytes | Loading is bounded by configured size, timeout, cancellation, and decode budgets; malformed input becomes typed diagnostics or errors | Model loader, GLB budget/reader code, decoder adapters | `flutter test test/model_loader_test.dart test/glb_decode_budget_test.dart test/model_load_cancellation_test.dart` | Repository maintainers when ingestion changes |
| GLB structure and extension metadata | Parsers validate offsets, lengths, JSON types, and capability requirements rather than trusting asset contents | Internal GLB readers/rewriters and fixture tests | `flutter test test/glb_capability_reader_test.dart test/glb_material_extension_reader_test.dart test/glb_texture_binding_reader_test.dart` | Repository maintainers when parsing changes |
| Optional native Draco and BasisU plugins | Vendored sources, local modifications, hashes, licenses, and bridge contracts remain inspectable | Checked-in manifests, provenance tests, package build definitions | `flutter test test/material_extension_fixture_provenance_test.dart test/rewritten_glb_validator_test.dart` | Decoder maintainers when pins or native sources change |
| Network texture/model fetch | Callers do not receive hidden credentials from the package; HTTP errors, byte limits, and cancellation remain explicit | `http` client boundary and loader diagnostics | Loader and environment source tests through `bash tools/run_checks.sh` | Repository maintainers when network behavior changes |
| Repository and release authority | Local implementation does not imply permission to publish packages, write external systems, merge, release, deploy, or operate production | `AGENTS.md`, managed plans, and the harness operating loop | `python3 tools/harness_gate.py` plus human approval for any external action | Repository maintainers when authority changes |

## Dependency and secret policy

- Pin Git dependencies to immutable revisions when behavior or evidence depends
  on them.
- Keep third-party licenses, provenance, local modifications, and generated
  hashes with vendored native code.
- Never commit credentials, signing material, evidence HMAC keys, or
  machine-local tokens. Harness keys live outside the repository with
  owner-only permissions.
- Treat dependency upgrades and native decoder changes as security-sensitive
  boundaries requiring focused provenance and malformed-input tests.

Security review, compliance certification, supply-chain attestation, and
production hardening are `not run` unless a managed plan records their exact
authorized evidence.
