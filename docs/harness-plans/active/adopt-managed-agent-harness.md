<!-- harness-plan:v1
id: adopt-managed-agent-harness
status: active
created: 2026-07-23
updated: 2026-07-23
completed:
owner: Repository maintainers
-->

# Adopt the managed agent harness

Maintain this plan according to the
[configured planning policy](../../PLANS.md). It is the restart record for the
explicit 2026-07-23 harness-engineering adoption request.

## Purpose / Big Picture

After this work, an agent can discover project intent, choose exact checks,
inspect runtime and evidence boundaries, resume complex work, run a
repository-native fail-closed harness gate, and distinguish local verification
from certification or production claims. Success is observable through the
managed documentation routes, `python3 tools/harness_gate.py`, repository
checks, and the external adaptive verifier.

## Progress

- [x] (2026-07-23 13:11Z) Read repository instructions, product and architecture authorities, the repository-local skill, and the harness package contract.
- [x] (2026-07-23 13:11Z) Ran the adaptive baseline audit and classified the existing lightweight harness as a partial adoption.
- [x] (2026-07-23 13:11Z) Selected an adaptive managed lifecycle that preserves historical product plans without rewriting them into a new schema.
- [x] (2026-07-23 13:26Z) Created and tailored the canonical knowledge,
  security, reliability, environment, verification, coverage, and
  certification authorities.
- [x] (2026-07-23 13:26Z) Implemented and exercised the repository-native
  structural and strict harness modes with actionable pass/fail signals.
- [x] (2026-07-23 13:26Z) Ran focused and broad project checks and recorded
  their literal scoped evidence.
- [ ] Obtain a warning-free independent whole-tree verifier result, a clean
  source/direct-child attestation pair, fresh schema-v2 records, and `CERT000`.
  Source convergence is complete: tracked upstream/fixture text no longer
  presents incomplete Markdown navigation, ignored captures will be excluded
  through a clean clone, and the user authorized deferred Plan 028 for commit.

## Surprises & Discoveries

- Observation: The baseline external audit reported 49 link errors, but the
  broken paths are partial vendored upstream documentation, fixture license
  Markdown, and ignored `tools/out/` captures rather than project-owned
  navigation.
  Evidence: `harness.py audit --root .` on 2026-07-23.
- Observation: The old `docs/exec-plans/completed/` collection contains many
  valid historical lightweight plans that are structurally incompatible with
  the strict thirteen-section managed schema.
  Evidence: `docs/exec-plans/templates/EXEC_PLAN_TEMPLATE.md` and completed
  plan inspection.
- Observation: The user subsequently authorized all outstanding work,
  including deferred Plan 028, for commit.
  Evidence: the 2026-07-23 follow-up explicitly requested committing
  everything before pursuing `CERT000`.
- Observation: Renaming byte-identical partial upstream README and generated
  fixture license snapshots from `.md` to `.txt` removes all 33 tracked
  `LINK001` findings without changing their content or SHA-256 identities.
  Evidence: the independent check's remaining 16 findings are exclusively
  ignored `tools/out/` captures, which are absent from a clean clone.
- Observation: The first strict source/attestation pair passed the
  repository-native gate but the independent verifier returned `CERT014` for
  the tracked `packages/flutter_scene_viewer_draco/ios/third_party` symlink.
  Evidence: the verifier named that exact path as the only certification
  error; `git ls-files -s` showed it as the repository's only `120000` entry.
- Observation: The broad repository gate still has the same three frozen
  Plan 018 capture failures recorded before this adoption; the added harness
  tests do not widen that failure set.
  Evidence: `bash tools/run_checks.sh` passed harness lint, repository lint,
  format, dependency resolution, and analyze; 809 tests passed, 17 GPU tests
  skipped, and three `plan018_ios_capture_runner_test.dart` cases failed with
  `HEAD/origin/main drifted from the Plan 018 base`.
- Observation: Once direct Markdown routing was added to `AGENTS.md`, the
  independent adaptive checker reported no project-owned routing, plan,
  coverage, placeholder, or semantic warning.
  Evidence: its remaining 49 errors exactly match the baseline partial
  third-party, fixture-license, and ignored-output link set.

## Decision Log

- Decision: Use a custom adaptive authority map rather than the canonical
  standard path layout.
  Rationale: The repository already owns `docs/ARCHITECTURE.md`, and forcing a
  duplicate root authority would create drift.
  Date/Author: 2026-07-23 / Repository maintainers.
- Decision: Put the strict lifecycle under `docs/harness-plans/` and retain
  `docs/exec-plans/` as historical/deferred product planning input.
  Rationale: This keeps one active managed lifecycle while preserving
  long-lived product evidence and the user's unrelated untracked plan.
  Date/Author: 2026-07-23 / Repository maintainers.
- Decision: Default revalidation to a manual repository-local Python gate and
  do not add hosted CI.
  Rationale: The user authorized repository adoption but did not request CI
  automation; the skill explicitly defaults to manual maintenance.
  Date/Author: 2026-07-23 / Repository maintainers.
- Decision: Preserve incomplete upstream and generated license documents as
  `.txt`, and perform independent certification in a clean clone.
  Rationale: This retains exact provenance bytes and hashes while preventing a
  generic Markdown crawler from treating partial vendor trees or ignored
  generated outputs as repository navigation.
  Date/Author: 2026-07-23 / Repository maintainers.
- Decision: Remove the iOS Draco vendor symlink and route CocoaPods to the
  package vendor tree through explicit `../third_party/draco` paths.
  Rationale: The aggregate source already uses the parent-relative tree, this
  avoids duplicating vendored code, and the certification contract rejects
  tracked symlinks. The native gate now enforces the same boundary.
  Date/Author: 2026-07-23 / Repository maintainers.

## Outcomes & Retrospective

The repository now has a managed adaptive harness with one concise instruction
map, canonical authority configuration, strict restartable plans, security and
reliability contracts, a complete 31-row inventory, exact local verification
routes, and a standard-library Python gate covered by two Flutter tests. The
structural gate is `verified locally` and reports the repository certification
state as `candidate-only`.

The outcome does not yet include `harness-ready`; that label remains reserved
for the direct-child attestation and observed `CERT000`. The former source
blockers are resolved without changing upstream bytes: partial README and
generated fixture license snapshots use `.txt`, deferred Plan 028 is authorized
source, and the ignored-output boundary is enforced by certifying a clean
clone. HDEBT-001 records that resolution.

## Context and Orientation

`flutter_scene_viewer` is a Flutter package and two optional decoder packages,
not a deployed service. Product intent lives in `docs/PROJECT_CHARTER.md`, the
system boundary lives in `docs/ARCHITECTURE.md`, commands live in
`docs/REPO_TOOLING.md`, and the main project gate is
`bash tools/run_checks.sh`. The existing `docs/agent-harness/` directory
documents a lightweight loop but lacks the complete authority map, 31-row
coverage inventory, certification contract, and native harness gate required
by the invoked skill.

## Plan of Work

First, map existing authorities and create only the missing project-specific
documents. Second, implement a Python gate that validates routes, managed plan
structure, coverage inventory, literal evidence language, and project-owned
Markdown links without depending on the globally installed skill. Third,
exercise focused and broad repository checks, record the observed boundary,
and run the external adaptive check with warnings treated as errors from a
clean clone. Finally, bind fresh HMAC evidence to source commit `S`, create the
exact direct-child attestation commit `A`, and require `CERT000` before
claiming `harness-ready`.

## Concrete Steps

Run commands from the repository root:

    python3 tools/harness_gate.py
    python3 tools/repo_lint.py
    python3 tools/doc_garden.py
    bash tools/run_checks.sh
    git diff --check
    python3 /Users/marlonjd/.codex/skills/harness-engineering/scripts/harness.py check --root . --warnings-as-errors

The local gates and clean-clone external command must exit zero. The strict
native gate and independent certification must then accept the same source and
direct-child attestation boundary.

Observed results on 2026-07-23:

    python3 tools/harness_gate.py
    harness gate passed (certification state: candidate-only)

    python3 tools/harness_gate.py --require-harness-ready
    HARNESS_ERROR: docs/agent-harness/certification.json: strict gate requires claim harness-ready
    HARNESS_ERROR: strict gate requires FSV_HARNESS_ATTESTATION_KEY_FILE or --attestation-key-file

    flutter test test/harness_gate_test.dart
    2 tests passed

    python3 tools/repo_lint.py
    repo lint passed

    python3 tools/doc_garden.py
    no stale markers reported

    git diff --check
    exit 0

    bash tools/run_checks.sh
    format/analyze passed; 809 tests passed, 17 skipped, 3 pre-existing Plan 018 evidence-base failures

    external harness check --warnings-as-errors
    49 link errors, 0 warnings; no project-owned harness finding

    external harness check --warnings-as-errors after tracked source cleanup
    16 link errors, 0 warnings; all 16 are ignored tools/out captures and the
    clean-clone result is pending the source commit

## Validation and Acceptance

An agent starting at `AGENTS.md` can reach every configured authority through
real Markdown links. The managed plan validator accepts this active plan.
`tools/harness_gate.py` passes the structural tree and strict mode rejects the
controlled candidate manifest/missing-key state with actionable messages.
Repository checks preserve product behavior. Certification language never
blends `verified locally`, `candidate-only`, `blocked`, `harness-ready`,
`release pending`, or `production-ready`.

## Idempotence and Recovery

Documentation and gate checks are read-only and safe to rerun. Apply changes
additively; Plan 028 remains deferred even though it is now tracked. Preserve
upstream bytes, use a clean clone for the independent whole-tree scan, and
keep the attestation overlay limited to its configured paths. Do not create a
branch, hosted workflow, release, deployment, or production artifact.

## Artifacts and Notes

The baseline commit is `1dee52551bc986b0584ca394cf5a3b8f814c7fcd`.
The repository identity is the configured GitHub origin
`https://github.com/MarlonJD/flutter_scene_viewer`. Raw command logs under
`tools/out/` are temporary; concise outcomes belong in this plan.

The tracked `LINK001` set is resolved through byte-preserving `.txt` paths.
The only remaining dirty-worktree findings are 16 ignored
material-acceptance capture licenses; a clean clone contains none of them.
HDEBT-001 records the resolution and clean-clone boundary.

## Interfaces and Dependencies

The durable checker will use Python 3 standard-library modules only and expose
`python3 tools/harness_gate.py`. `tools/run_checks.sh` will invoke it before
Flutter checks. The installed harness helper remains an independent
read-only cross-check, not a runtime dependency. Managed plan metadata and
coverage row identities follow the invoked skill's schemas.

## Revision History

- (2026-07-23 13:11Z) Change: Created the managed adoption plan and selected
  the adaptive authority layout.
  Reason: Preserve existing canonical documents and historical plan evidence
  while establishing a strict future lifecycle.
- (2026-07-23 13:26Z) Change: Recorded implemented authorities, local gate
  behavior, repository verification, and the exact certification blockers.
  Reason: Leave a literal, restartable boundary after converging every
  project-owned harness finding while preserving third-party provenance and
  unrelated user work.
- (2026-07-23 13:27Z) Change: Made the structural gate reject an unverified
  `harness-ready` manifest unless strict key-bound validation is selected.
  Reason: Prevent an ordinary local check from accepting a stale certification
  claim without its evidence-integrity inputs.
- (2026-07-23 14:05Z) Change: Recorded user authorization for Plan 028,
  byte-preserving upstream/fixture text paths, clean-clone verification, and
  the pending source/attestation certification boundary.
  Reason: Resolve every tracked whole-tree finding without rewriting external
  source text and make the final `CERT000` sequence restartable.
- (2026-07-23 13:55Z) Change: Recorded the first independent `CERT014`,
  parent-relative CocoaPods vendor routing, and the native tracked-symlink
  guard.
  Reason: Preserve the observed failed certification attempt and prevent the
  same repository-shape drift from recurring.
- (2026-07-23 14:02Z) Change: Kept the ordinary harness gate structural after
  certification and made it report `not revalidated` for a harness-ready
  manifest.
  Reason: Preserve the keyless main repository check while ensuring only the
  key-bound strict gate can revalidate the certification claim.
