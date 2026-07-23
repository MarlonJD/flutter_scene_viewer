# Human and agent operating loop

Use this loop only after an explicit repository request or an already
authorized repository-native trigger. Skill installation alone grants no
repository, Git, external-write, release, or production authority.

## Responsibilities

| Role | Owns |
| --- | --- |
| Repository maintainers | Product priorities, public scope, release intent, risk tolerance, dependency adoption, evidence maturity, and exceptional approvals |
| Agent | Discovery, managed planning, repository-local implementation, focused and broad local verification, self-review, evidence capture, and durable documentation within granted authority |
| Mechanical harness | Deterministic route, plan, lint, generation, test, and evidence-integrity checks with actionable failures |
| Release or production owner | Any future publish, signing, deployment, rollback, or provider-backed attestation; no such authority is implied by local work |

Human judgment is always required for public API direction, product scope,
performance claims, dependency/license tradeoffs, release maturity, external
writes, destructive operations, secrets, merge, publish, deployment, and
production actions.

## Task loop

1. Read `AGENTS.md`, the product/architecture sources, and any applicable
   repository-local skill.
2. Inspect the working tree and preserve unrelated changes.
3. Reproduce behavior or establish a measurable baseline.
4. Create or resume a managed ExecPlan when the work needs continuity.
5. Implement the smallest independently verifiable increment.
6. Run focused checks, then the broader rows selected from the verification
   matrix.
7. Observe library, widget, or target behavior through the environment
   contract at the evidence scope the claim requires.
8. Review the diff, tests, generated artifacts, failure modes, dependency
   boundary, and recovery path.
9. Address findings and repeat verification.
10. Update the plan and any canonical architecture, product, registry, debt,
    or enforcement authority that changed.
11. Run the repository-native harness gate. Refresh certification only through
    a new source/direct-child attestation pair; otherwise keep the claim
    invalid.
12. Hand off with literal evidence labels from the output contract.

## Review policy

| Change surface | Local self-review | Independent review | Stop condition | Human review required? | Failure path | Owner/evidence |
| --- | --- | --- | --- | --- | --- | --- |
| Documentation or harness | `git diff --check`, local harness gate, repo lint, and link review | External harness verifier when applicable | Project-owned findings resolved and remaining external blocker named | Risk-based; required for authority or public policy change | Keep plan active and record blocker | Repository maintainers and managed plan |
| Dart library behavior | Focused tests, format/analyze, full root suite, and diff review | Additional agent review is optional and must not write externally | Behavior and mapped checks pass | Required for public API/product judgment; otherwise risk-based | Reproduce, fix, add fixture, rerun | Change author and test output |
| Native decoder, renderer, or material behavior | Provenance/capability tests plus target-specific plan evidence | Independent technical review is recommended for release claims | Exact pin, target, fixture, and evidence boundary agree | Yes for release maturity or dependency tradeoffs | Keep `candidate-only`/`release pending`; do not upgrade claim | Repository maintainers and target plan |
| External, release, or production action | Local preparation only | Provider/repository review defined by future release policy | Explicit approval and rollback authority exist | Always | Stop and request authority | Release or production owner |

## Review and recovery

| Signal | Immediate response | Durable feedback |
| --- | --- | --- |
| Focused test failure | Diagnose and correct the current increment | Add or improve the reproducing fixture when a gap is exposed |
| Toolchain unavailable | Run remaining safe checks and label the missing surface `blocked` or `not run` | Record setup/recovery in the active plan or registry |
| Repeated review finding | Fix current and nearby occurrences | Promote a stable rule into docs, a test, linter, or structural gate |
| User-visible defect | Capture a reproducible path and verify the repair | Update product/reliability knowledge and acceptance evidence |
| Harness failure | Repair only safe authorized repository drift | Preserve the reproducer, update coverage/debt, and keep certification invalid |
| Missing authority | Stop before the protected action | Name the owner, approval, and recovery condition |

Continuous execution never broadens authority.
