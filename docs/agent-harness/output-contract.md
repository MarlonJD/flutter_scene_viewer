# Agent output contract

The repository is the durable source of truth. Raw command output is useful,
but it is not automatically durable evidence.

## Handoff requirements

1. Lead with the behavior or artifact delivered.
2. Name material files or systems changed.
3. Report exact commands and scoped outcomes.
4. Separate remaining gaps, debt, and approval-dependent work.
5. State destructive, external, release, production, or real-device work only
   when it actually occurred with the required authority.

## Evidence labels

| Label | Meaning |
| --- | --- |
| `verified locally` | The stated command or behavior was exercised in the local task environment. |
| `not run` | The check was intentionally not executed; include the reason. |
| `blocked` | A named condition prevented required progress or verification. |
| `candidate-only` | An implementation or command exists but lacks the evidence required for its intended claim. |
| `harness-ready` | A clean source/direct-child attestation pair, all 31 rows, the project-native gate, and fresh HMAC-consistent evidence passed with `CERT000`; this grants no release or production authority. |
| `release pending` | Local work is complete but release or deployment evidence does not exist. |
| `production-ready` | Use only after an explicitly requested provider-backed production verifier authenticates repository, target, approval, rollback, artifact, freshness, and revocation evidence; local checks and HMAC records are insufficient. |

## Temporary output

These outputs may be overwritten and should stay untracked:

- `tools/out/*.log` and local capture trees;
- Dart/Flutter/package caches and build output;
- simulator screenshots or videos under `/private/tmp`;
- ad hoc smoke harness directories.

## Durable evidence

Durable evidence belongs in the active managed plan, a linked canonical
document, or a committed fixture/report reviewers need to reproduce. Summarize
the command, result, date, target, and material flags. Do not paste long raw
logs unless the raw text is the task deliverable.

Commit an output artifact only when it is a test input, a stable reviewer
report, a visual result that cannot be summarized safely, or a plan-named
acceptance artifact. Generated capability documentation must be regenerated
from its source and checked for drift.

## Recommended handoff shape

- Outcome: delivered behavior or authority.
- Changed: material paths or systems.
- Verification: exact commands and literal results.
- Not verified: omitted or blocked surfaces and reasons.
- Remaining work: explicit debt, active-plan blocker, or none.
