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
  PROJECT_CHARTER.md
  ARCHITECTURE.md
  REPO_TOOLING.md
  agent-harness/
    README.md
    output-contract.md
    entropy-cleanup-checklist.md
  exec-plans/
    active/
    completed/
    deferred/
    templates/
  generated/
  references/
tools/
  run_checks.sh
  repo_lint.py
  doc_garden.py
```

## Agent-readable constraints

Agents should never need chat history to understand the project. If a decision is
important, put it in docs or an active plan.

## Quality loop

For each active plan:

1. read plan;
2. implement smallest slice;
3. run tooling checks;
4. update progress log;
5. stop or continue with next verifiable slice.

When no work is actively selected, `docs/exec-plans/active/` may be empty.
When work is selected, it contains at most one Markdown plan.
Completed plans with all acceptance criteria checked belong in
`docs/exec-plans/completed/`; future work should be promoted back into
`active/` before implementation.

Historical planning source has been promoted into `docs/ROADMAP.md` and the
exec-plan folders. Future work should be represented as a deferred or active
exec plan before implementation.

## Entropy control

`tools/repo_lint.py` guards basic structure. `tools/doc_garden.py` is a
lightweight scanner for stale markers, broad claims, and missing plan updates.
More checks can be added as repeated mistakes appear.

`docs/agent-harness/` defines the evidence and cleanup contract. Keep executable
orchestration in `.sh`, structured repository scanning in `.py`, and policy or
output rules in Markdown until a rule is stable enough to enforce mechanically.
