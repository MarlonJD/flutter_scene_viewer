# Harness Technical Debt Tracker

Track confirmed debt that affects delivery, reliability, security,
maintainability, or agent effectiveness. Product feature debt remains in the
roadmap and historical `docs/exec-plans/` tree.

| ID | Area | Evidence | Impact | Owner | Next action or revisit trigger | Status |
| --- | --- | --- | --- | --- | --- | --- |
| HDEBT-001 | External harness link scan | Adaptive audit on 2026-07-23 reported broken links inside partial third-party snapshots and ignored `tools/out/` fixtures | The external whole-tree verifier could not issue `CERT000` from a generated-output worktree | Repository maintainers | Preserve upstream README and fixture-license bytes as `.txt`; run certification from a clean clone so ignored captures cannot masquerade as source | resolved 2026-07-23 |
| HDEBT-002 | iOS Draco vendor routing | First bounded certification attempt reported `CERT014` because `ios/third_party` was a tracked symlink to the package vendor tree | The independent verifier rejects every tracked symlink even when its target stays inside the repository | Repository maintainers | Remove the symlink, use explicit `../third_party/draco` podspec paths, and reject tracked symlinks in the native harness gate | resolved 2026-07-23 |

## Rules

- Add evidence before priority.
- Link a large remediation to an active managed ExecPlan.
- Record mitigation separately from resolution.
- Preserve resolved entries long enough to explain the guardrail.
