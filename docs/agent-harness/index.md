# Agent harness

This directory is the progressive-disclosure entry point for capabilities that
help coding agents work reliably in this repository. Installing an external
skill does not create, execute, monitor, or certify this harness.

Root [`AGENTS.md`](../../AGENTS.md) is the canonical instruction map.
[`config.json`](config.json) declares downstream authorities but does not make
an arbitrary file auto-loadable by Codex.

## Capability map

| Need | Source of truth |
| --- | --- |
| Available commands and tools | [`registry.md`](registry.md) |
| Adopted authority paths | [`config.json`](config.json) |
| Human/agent responsibilities and recovery | [`operating-loop.md`](operating-loop.md) |
| Local isolation and observable surfaces | [`environment-contract.md`](environment-contract.md) |
| Completion and evidence language | [`output-contract.md`](output-contract.md) |
| Change-to-check mapping | [`verification-matrix.md`](verification-matrix.md) |
| Recurring drift cleanup | [`entropy-cleanup-checklist.md`](entropy-cleanup-checklist.md) |
| Canonical capability inventory | [`coverage-matrix.md`](coverage-matrix.md) |
| Bounded certification and invalidation | [`certification.md`](certification.md) and [`certification.json`](certification.json) |
| Long-running work | [`../harness-plans/index.md`](../harness-plans/index.md) |

## Route by task

| Task | Read first | Continue with |
| --- | --- | --- |
| Understand product intent | [`../PROJECT_CHARTER.md`](../PROJECT_CHARTER.md) | [`../ROADMAP.md`](../ROADMAP.md) and [`../ARCHITECTURE.md`](../ARCHITECTURE.md) |
| Start or resume complex work | [`../PLANS.md`](../PLANS.md) | [`../harness-plans/index.md`](../harness-plans/index.md) and its active plan |
| Implement and verify a change | [`operating-loop.md`](operating-loop.md) | [`registry.md`](registry.md), [`verification-matrix.md`](verification-matrix.md), and [`output-contract.md`](output-contract.md) |
| Change a renderer or material boundary | [`../MATERIALS_AND_LIGHTING.md`](../MATERIALS_AND_LIGHTING.md) | The repository-local `pbr-materials` skill and a managed plan |
| Reproduce library behavior | [`environment-contract.md`](environment-contract.md) | Focused tests and fixture routes in [`registry.md`](registry.md) |
| Change architecture | [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | [`../design-docs/index.md`](../design-docs/index.md) and a managed plan when cross-cutting |
| Sweep drift or debt | [`entropy-cleanup-checklist.md`](entropy-cleanup-checklist.md) | [`../harness-plans/tech-debt-tracker.md`](../harness-plans/tech-debt-tracker.md) |
| Prepare external, release, or production work | [`operating-loop.md`](operating-loop.md) | [`../SECURITY.md`](../SECURITY.md), [`../RELIABILITY.md`](../RELIABILITY.md), and explicit user authority |
| Evaluate harness completeness | [`coverage-matrix.md`](coverage-matrix.md) | Run the local gate, then the independent verifier |

## Maturity assessment

| Dimension | Current state | Evidence | Next increment |
| --- | --- | --- | --- |
| Knowledge routing | repeatable | `AGENTS.md`, [`../index.md`](../index.md), and configured authorities | Keep routes within the 32 KiB instruction budget |
| Planning continuity | repeatable | Strict managed registry and active adoption plan | Complete the first managed lifecycle move |
| Executable verification | enforced locally | `tools/run_checks.sh`, `tools/repo_lint.py`, and `tools/harness_gate.py` | Add CI only with explicit authorization |
| Agent-readable runtime | repeatable for a library | Fixture-driven unit/widget tests and scoped capture runners | Add target evidence when a feature plan requires it |
| Mechanical boundaries | enforced locally | Repository lint, harness gate, generation tests, and adapter tests | Promote only repeated or critical rules |
| Entropy control | repeatable | `tools/doc_garden.py` and the cleanup checklist | Revisit recorded debt on its stated trigger |
| Safe autonomy | repeatable inside local scope | Operating loop and explicit escalation boundaries | External actions remain approval-gated |

`harness-ready` requires a fresh `CERT000` result for a clean source and
direct-child attestation pair. These documents alone do not establish it.
