# Harness-ready certification

The repository currently carries a `candidate-only` manifest. The bounded label
`harness-ready` may be used only when the repository-native strict gate and the
independent verifier both return zero with `CERT000` for one source commit `S`
and its clean direct-child attestation commit `A`.

This result would certify the inspected repository harness and evidence window;
it would not prove that the Flutter package was published, deployed, security
reviewed, or independently certified for production.

## Convergence ownership

- Owner: Repository maintainers.
- Structural project gate: `python3 tools/harness_gate.py`.
- Strict project gate: `python3 tools/harness_gate.py --require-harness-ready`
  with `FSV_HARNESS_ATTESTATION_KEY_FILE` naming an owner-only external key.
- Safe repair procedure: update the active managed plan, repair only authorized
  repository-local drift, rerun mapped checks, refresh records, and create a
  new source/direct-child pair.
- Evidence issuer: the local repository-maintainer process that directly
  observes the named commands; it is not externally authenticated.
- Key custody: the invoking maintainer supplies a 32–4096 byte non-symlinked,
  single-linked, owner-only file outside the repository; the key is never
  committed.
- Optional production verifier: N/A and unavailable for the current
  unpublished local package.
- Escalation: secrets, destructive changes, external writes, merge, publish,
  release, deployment, production, and product judgment require separate
  authority.

## Current convergence state

The source tree preserves partial upstream README and auto-generated fixture
license bytes as `.txt`, so they are not misclassified as project-owned
Markdown navigation. Certification runs from a clean clone, where ignored
`tools/out/` captures are absent by construction. Deferred Plan 028 is now an
authorized tracked source artifact. The remaining step is to bind fresh
schema-v2 records to the final source commit and obtain `CERT000` from its
clean direct-child attestation commit.

## Source and attestation procedure

All implementation, commands, and maintenance behavior belong in source commit
`S`. Evidence records and `certification.json.repository_commit` name `S`.
Direct-child commit `A` may change only the configured coverage matrix,
certification manifest, and exactly the referenced evidence JSON files. It
contains no implementation change.

Every record follows schema v2 and binds the exact capability, source commit,
`scm://github.com/MarlonJD/flutter_scene_viewer`, and
`harness://github.com/MarlonJD/flutter_scene_viewer/flutter-package-local-validation`.
HMAC consistency prevents accidental record mixing but does not authenticate a
provider, human reviewer, production target, approval, or rollback exercise.

## Revalidation and invalidation

Maintenance is manual. Run the structural gate before ordinary task completion.
After any source, authority, coverage, applicability, command, or evidence
change, any prior attestation is invalid. Recovery requires new observed
evidence, a new direct-child attestation, the strict local gate, and
independent `CERT000`. No hosted workflow or schedule was added because the
user did not request CI automation.

The production-authority row is N/A while this repository remains
`publish_to: none` with no deployment action. An explicitly requested
production attestation would require a provider-backed verifier and must fail
closed when that authority is absent.
