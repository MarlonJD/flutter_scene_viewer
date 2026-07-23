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
  Blocker: the verifier reports 49 links in partial vendored/fixture/ignored
  trees outside the project-owned documentation contract, and the user's
  unrelated untracked Plan 028 prevents a clean attestation worktree.

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
- Observation: The working tree contains the user's untracked deferred Plan
  028 and it must remain untouched.
  Evidence: `git status --short --branch` reported only
  `docs/exec-plans/deferred/028_adaptive_ray_path_tracing_feasibility.md`
  before harness edits.
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

## Outcomes & Retrospective

The repository now has a managed adaptive harness with one concise instruction
map, canonical authority configuration, strict restartable plans, security and
reliability contracts, a complete 31-row inventory, exact local verification
routes, and a standard-library Python gate covered by two Flutter tests. The
structural gate is `verified locally` and reports the repository certification
state as `candidate-only`.

The outcome does not yet include `harness-ready`. The independent verifier has
no repository-declared exclusion mechanism for the partial upstream and
ignored evidence trees it scans, and modifying vendored provenance solely to
silence that generic scan would be unsafe. The user-owned untracked Plan 028
also prevents the clean attestation boundary. HDEBT-001 records the verifier
scope issue; this plan remains blocked and resumable rather than hiding it as
complete.

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
and run the external adaptive check with warnings treated as errors. If the
whole-tree verifier remains blocked by partial upstream snapshots or the
unrelated dirty path, preserve that exact gap rather than claiming
`harness-ready`.

## Concrete Steps

Run commands from the repository root:

    python3 tools/harness_gate.py
    python3 tools/repo_lint.py
    python3 tools/doc_garden.py
    bash tools/run_checks.sh
    git diff --check
    python3 /Users/marlonjd/.codex/skills/harness-engineering/scripts/harness.py check --root . --warnings-as-errors

The local gates must exit zero. The external command must either exit zero or
name only a documented implementation/authority blocker; any new
project-owned harness finding must be fixed.

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
additively and preserve the user's untracked Plan 028. If a new gate creates
baseline noise, keep it focused on project-owned authorities and record the
unsupported external surface as debt instead of mutating vendored source
documentation. Do not create a branch, hosted workflow, release, deployment,
or production artifact.

## Artifacts and Notes

The baseline commit is `1dee52551bc986b0584ca394cf5a3b8f814c7fcd`.
The repository identity is the configured GitHub origin
`https://github.com/MarlonJD/flutter_scene_viewer`. Raw command logs under
`tools/out/` are temporary; concise outcomes belong in this plan.

The external verifier's exact remaining set is 49 `LINK001` errors: partial
BasisU and Draco README targets/anchors, quoted-URL fixture license Markdown,
and ignored material-acceptance capture licenses. HDEBT-001 owns the revisit
condition.

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
