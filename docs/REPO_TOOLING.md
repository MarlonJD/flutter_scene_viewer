# Repository tooling

This repo follows an agent-first engineering style.

## Principles

1. The repository is the durable source of truth.
2. `AGENTS.md` is a map, not a manual.
3. Plans are first-class artifacts.
4. Mechanical checks enforce taste and architecture.
5. Docs are maintained like code.
6. Every task has a verification loop.

## Repository knowledge structure

```text
AGENTS.md
CLAUDE.md
CODEX.md
docs/
  PROJECT_CHARTER.md
  ARCHITECTURE.md
  REPO_TOOLING.md
  design-docs/
  exec-plans/
    active/
    completed/
    templates/
  generated/
  product-specs/
  references/
tools/
  run_checks.sh
  repo_lint.py
  doc_garden.py
```

## Agent-readable constraints

Codex should never need chat history to understand the project. If a decision is
important, put it in docs or an active plan.

## Quality loop

For each active plan:

1. read plan;
2. implement smallest slice;
3. run tooling checks;
4. update progress log;
5. stop or continue with next verifiable slice.

## Entropy control

`tools/repo_lint.py` guards basic structure. `tools/doc_garden.py` is a
lightweight scanner for stale TODOs, broad claims, and missing plan updates.
More checks can be added as repeated mistakes appear.
