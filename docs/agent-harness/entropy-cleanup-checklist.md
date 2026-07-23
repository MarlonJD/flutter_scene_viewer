# Entropy cleanup checklist

Run this lightweight sweep after documentation, planning, architecture, or
harness changes and before completing a managed plan.

## Managed plans and history

- The configured `docs/harness-plans/active/` lifecycle has at most one plan.
- Completed managed plans passed structural validation and semantic review.
- Historical/deferred product plans under `docs/exec-plans/` are not presented
  as a second active lifecycle.
- Deferred intent is promoted into a current managed plan before
  implementation.

## Routes and generated content

- `AGENTS.md`, `docs/index.md`, the harness index, and config point to the same
  authorities.
- Project-owned Markdown links resolve.
- `docs/generated/*` names its source, regeneration command, and drift check.
- Capability documentation does not say planned when code and tests prove a
  different state.

## Claims and evidence

- Performance claims have benchmark evidence.
- Viewer capability claims have tests, target evidence, or typed diagnostics.
- Simulator, physical-device, browser, release, and production scopes remain
  separate.
- `harness-ready` appears as a current result only with `CERT000`.
- Missing release, production, target, or approval evidence uses literal output
  labels.

## Code and tooling

- Repeated correctness boundaries are promoted into tests or lint only after
  they are stable.
- Temporary outputs remain under ignored paths and are not cited as immutable
  evidence.
- Stale suppressions, duplicated helpers, unowned debt, and abandoned plan
  state have a bounded cleanup or revisit trigger.
- Vendored snapshots are not edited merely to silence a generic documentation
  scan; verifier mismatch is tracked as harness debt.

Record the sweep in the active plan. Run:

    python3 tools/doc_garden.py
    python3 tools/repo_lint.py
    python3 tools/harness_gate.py
    git diff --check
