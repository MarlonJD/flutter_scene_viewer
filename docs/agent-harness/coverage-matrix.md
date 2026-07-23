# Harness engineering coverage matrix

This inventory keeps all 31 canonical capabilities visible. `verified` means
the repository implementation and named behavior have been exercised at the
stated local scope. `N/A` means the OpenAI case-study choice or production
surface is inapplicable for this library and includes the reason.

These prose statuses are not HMAC evidence. Before `harness-ready`, every row
must link exactly one fresh source-commit-bound schema-v2 record and both the
repository-native strict gate and independent verifier must return zero with
`CERT000`.

## Coverage

| Source principle or capability | Repository implementation | Required evidence | Status and reason |
| --- | --- | --- | --- |
| Humans set intent; agents execute within authority | [`operating-loop.md`](operating-loop.md), [`../../AGENTS.md`](../../AGENTS.md), and product sources | Named judgment boundaries and a completed local task trace | verified — authority boundaries are explicit and the completed harness documentation cleanup plan records a preserved-work task trace |
| Break large goals into reusable design, code, review, test, and verification steps | [`../PLANS.md`](../PLANS.md) and [`../harness-plans/index.md`](../harness-plans/index.md) | Restartable plan with independently verifiable milestones | verified — the active adoption plan is self-contained and structurally validated through the configured lifecycle |
| Agents can self-review and respond to feedback | [`operating-loop.md`](operating-loop.md) and [`output-contract.md`](output-contract.md) | Review process plus resolved finding evidence | verified — diff, lint, focused test, broad gate, and durable feedback routes are defined and exercised by repository plans |
| Application behavior is directly readable | [`environment-contract.md`](environment-contract.md) and fixture-driven tests | Reproduced library/widget behavior with observed evidence | verified — unit and widget tests expose loader, controller, scheduler, material, and diagnostics behavior without a deployed runtime |
| Logs, metrics, and traces are queryable when relevant | [`environment-contract.md`](environment-contract.md) and [`registry.md`](registry.md) | Project-appropriate query or justified N/A | N/A — command logs are directly readable, while service metrics and distributed traces are irrelevant because the repository owns no service runtime |
| Repository knowledge is the durable record | [`../index.md`](../index.md), product docs, architecture, and plans | Canonical links resolve without hidden conversation context | verified — project intent, boundaries, commands, evidence labels, and active work are versioned and routed from the documentation map |
| Repository tools and authorized work context are directly invocable | [`registry.md`](registry.md) | Repository-local scripts/skills and source-control context are discoverable and exercised | verified — local Python/shell gates, the PBR skill, Git status, and diff checks have exact entry points |
| Dependencies and abstractions remain agent-legible | [`../ARCHITECTURE.md`](../ARCHITECTURE.md), [`registry.md`](registry.md), and [`../references/index.md`](../references/index.md) | Important upstream behavior has a discoverable contract and executable proof | verified — the adapter boundary, immutable dependency pin, checked-in references, fixtures, and provenance tests expose upstream behavior |
| `AGENTS.md` is a concise map, not an encyclopedia | [`../../AGENTS.md`](../../AGENTS.md) | Canonical routes fit the effective instruction budget | verified — one root instruction file contains the critical routes well below the conservative 32 KiB budget and no nested instruction chain exists |
| Plans are versioned living artifacts | [`../PLANS.md`](../PLANS.md) and [`../harness-plans/index.md`](../harness-plans/index.md) | Active/completed lifecycle with current progress, decisions, and evidence | verified — the configured strict lifecycle has one active managed plan and preserves historical product plans separately |
| Architecture and critical taste boundaries are mechanical | [`../ARCHITECTURE.md`](../ARCHITECTURE.md), [`../design-docs/core-beliefs.md`](../design-docs/core-beliefs.md), and project checks | Actionable failing and passing invariant | verified — repository and harness lint enforce routes, plan count/schema, generated provenance, and adapter/product boundaries with corrective messages |
| Local autonomy exists inside enforced central boundaries | [`operating-loop.md`](operating-loop.md), [`../../AGENTS.md`](../../AGENTS.md), and managed plans | Allowed actions, escalation gates, and recovery path | verified — repository-local discovery, edits, tests, and evidence are allowed while destructive, external, Git branch, release, and production actions remain gated |
| Verification proves working behavior, not only code changes | [`verification-matrix.md`](verification-matrix.md) | Exact commands plus user-visible or operational acceptance evidence | verified — each applicable library surface maps focused tests to observable results and a broader gate |
| Failures and review judgment feed back into the harness | [`operating-loop.md`](operating-loop.md) and completed harness cleanup plan | Example promoted to docs, test, linter, runbook, or debt | verified — the previous empty-active-plan failure was promoted into repository lint and the whole-tree verifier mismatch is tracked as HDEBT-001 |
| Entropy and technical debt are continuously controlled | [`entropy-cleanup-checklist.md`](entropy-cleanup-checklist.md) and [`../harness-plans/tech-debt-tracker.md`](../harness-plans/tech-debt-tracker.md) | Dated sweep evidence and bounded follow-up | verified — doc garden, repository lint, harness gate, and an evidence-backed debt revisit trigger form the manual sweep |
| Autonomy increases only after test, review, recovery, and escalation loops exist | [`operating-loop.md`](operating-loop.md), [`registry.md`](registry.md), and [`output-contract.md`](output-contract.md) | Granted level and unavailable higher levels are explicit | verified — local implementation and verification are repeatable while external, release, and production authority stays unavailable |
| Merge throughput policy matches project risk | [`operating-loop.md`](operating-loop.md), [`../SECURITY.md`](../SECURITY.md), and [`../RELIABILITY.md`](../RELIABILITY.md) | Project-specific gate rationale without copied low-blocking defaults | N/A — this adoption defines local review and verification but owns no hosted CI or merge automation policy |
| Release, deployment, and production actions require repository-local authority | [`operating-loop.md`](operating-loop.md), [`output-contract.md`](output-contract.md), and [`certification.md`](certification.md) | Exercised denial gate or justified N/A | N/A — the package is `publish_to: none`, no deployment action exists, and future publishing or production work requires an explicitly authorized owner and rollback contract |
| Repository-specific OpenAI examples are treated as options, not universal mandates | Case-study ledger below and project architecture | Independent decision for every listed choice | verified — all twelve case-study choices have project-specific decisions rather than inherited defaults |

## Case-study decision ledger

| OpenAI case-study choice | Local decision or implementation | Required evidence | Status and reason |
| --- | --- | --- | --- |
| Zero human-authored code as an operating constraint | Rejected; provenance is not used as a product-quality proxy | Explicit responsibility model | N/A — humans and agents may both contribute under the same tests, review, and authority boundaries |
| Reported repository size, pull-request throughput, elapsed-time speedup, and long agent-run duration as targets | Context only | Outcome and quality measures instead of copied vanity metrics | N/A — this repository measures behavior, evidence scope, and gate outcomes rather than case-study throughput |
| Local and cloud agent review loops continue until reviewers are satisfied while human review is optional | Not adopted as a mandatory independent-cloud loop | Project-specific review stopping condition and human gate | N/A — local self-review is defined, while human review remains required for product, release, dependency, and authority judgment |
| Per-worktree application isolation | Single-writer working tree with task-local process/output isolation | Collision-free setup and cleanup proof | N/A — ordinary work uses one writer and the repository has no long-lived application instance |
| Per-worktree observability stack | Not installed | Shared or isolated signal proof | N/A — focused test output and task-local logs are sufficient for this library |
| Chrome DevTools Protocol for UI control | Not used by the repository gate | Browser-flow evidence or justified absence | N/A — the package has no canonical browser application; widget and plan-scoped target tests are the supported surfaces |
| Victoria Logs, Metrics, and Traces with LogQL/PromQL/TraceQL | Not installed | Actual project telemetry queries or justified absence | N/A — the repository owns no service telemetry and does not copy the case-study stack |
| OpenAI's fixed layered domain architecture | Rejected in favor of the viewer/service/adapter/renderer boundary in [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | Project dependency model and executable boundary evidence | verified — project-specific layers, adapter isolation, tests, and durable constraints replace the case-study architecture |
| Reimplementing upstream dependency behavior locally | Rejected by default; adapt public `flutter_scene` behavior and keep bounded, evidence-backed exceptions isolated | Tradeoff covering maintenance, security, licensing, and compatibility | N/A — no general upstream reimplementation is an adopted harness strategy |
| Minimally blocking merge gates and short-lived pull requests | No repository-owned merge automation policy | Failure cost and recovery rationale | N/A — local gates are fail-closed and merge policy remains outside this adoption |
| Scheduled Codex documentation gardening and quality-scoring agents open targeted repair pull requests | Not authorized | Cadence, external-write authority, review, rollback, and observed trace | N/A — maintenance is manual and no hosted schedule or external write was requested |
| Automated merge and agent-authored release tooling | Not authorized | Automation gate, approval, rollback, and provider evidence | N/A — the repository has no automated merge/release path and local harness work grants no such authority |

Review this matrix after architecture, CI, runtime, release, or agent-workflow
changes. Prose completeness does not substitute for certification records.
