# ExecPlan Registry

The files under `active/` and `completed/` are authoritative. Keep this index
as their navigational mirror.

## Active

| Plan | Owner | State | Updated (UTC) | Current milestone or blocker |
| --- | --- | --- | --- | --- |
<!-- harness:plans:active:start -->
| [Adopt the managed agent harness](active/adopt-managed-agent-harness.md) | Repository maintainers | implementing | 2026-07-23 | Commit source state and create the bounded attestation overlay |
<!-- harness:plans:active:end -->

## Completed

| Plan | Completed (UTC) | Outcome | Verification |
| --- | --- | --- | --- |
<!-- harness:plans:completed:start -->
_None._
<!-- harness:plans:completed:end -->

## Lifecycle rules

- Keep `planning`, `implementing`, and `blocked` plans under `active/`.
- Move a plan to `completed/` only after the gate in
  [`../PLANS.md`](../PLANS.md) passes.
- Track confirmed harness debt in
  [`tech-debt-tracker.md`](tech-debt-tracker.md).
- Treat [`../exec-plans/`](../exec-plans/) as historical and deferred product
  planning input, not as a second active lifecycle.
