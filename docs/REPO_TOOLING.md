# Repository tooling

This repo follows an agent-first engineering style.

## Principles

1. The repository is the durable source of truth.
2. `AGENTS.md` is a map, not a manual.
3. Plans are first-class artifacts.
4. Mechanical checks enforce stable quality and architecture boundaries.
5. Docs are maintained like code.
6. Every task has a verification loop.

## Repository knowledge structure

```text
AGENTS.md
docs/
  index.md
  PLANS.md
  PROJECT_CHARTER.md
  ARCHITECTURE.md
  SECURITY.md
  RELIABILITY.md
  REPO_TOOLING.md
  agent-harness/
    index.md
    config.json
    registry.md
    environment-contract.md
    verification-matrix.md
    coverage-matrix.md
    certification.md
    output-contract.md
    entropy-cleanup-checklist.md
  harness-plans/
    active/
    completed/
    index.md
    plan-template.md
    tech-debt-tracker.md
  exec-plans/
    completed/
    deferred/
    templates/
  generated/
  references/
tools/
  run_checks.sh
  harness_gate.py
  repo_lint.py
  doc_garden.py
```

## Agent-readable constraints

Agents should never need chat history to understand the project. If a decision is
important, put it in docs or an active plan.

## Quality loop

For each active managed plan:

1. read plan;
2. implement smallest slice;
3. run tooling checks;
4. update progress log;
5. stop or continue with next verifiable slice.

When no work is selected, `docs/harness-plans/active/` may be empty. When work
is selected, it contains at most one Markdown plan. Completion follows the
structural and semantic gate in `docs/PLANS.md`.

`docs/exec-plans/` preserves historical and deferred product planning. Promote
its intent into a current managed plan before implementation; do not use the
historical tree as a second active lifecycle.

## Entropy control

`tools/harness_gate.py` guards configured authorities, managed plans, the
canonical coverage inventory, project-owned links, and certification claim
boundaries. `tools/repo_lint.py` guards basic repository structure.
`tools/doc_garden.py` is a lightweight scanner for stale markers and missing
plan updates. More checks can be added as repeated mistakes appear.

`docs/agent-harness/` defines the evidence and cleanup contract. Keep executable
orchestration in `.sh`, structured repository scanning in `.py`, and policy or
output rules in Markdown until a rule is stable enough to enforce mechanically.
