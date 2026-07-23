# Entropy cleanup checklist

Use this checklist when docs or plans start feeling noisy.

## Active plans

- There should be exactly one current execution plan for the next work slice.
- Plans with all acceptance criteria checked should move to `completed/` unless
  the progress log clearly says why they remain active.
- Deferred work belongs in `deferred/`, not as a checked-off active plan.
- Historical planning source should be promoted into roadmap or exec-plan
  files, not kept as parallel planning packs.

## Generated and score docs

- `docs/generated/*` should name its source and regeneration command.
- Capability matrices should not say `Planned` for behavior that has verified
  code and tests.

## Claims

- Performance claims require benchmark evidence.
- Viewer capability claims require tests, smoke evidence, or explicit adapter
  diagnostics.
- Missing release, production, or device evidence should be labeled literally
  instead of implied.

## Harness docs

- Keep `AGENTS.md` as the map.
- Keep `docs/REPO_TOOLING.md` as the tooling overview.
- Keep this directory focused on evidence and cleanup contracts.
- Retire planning-source documents after their decisions are represented in the
  roadmap and active/deferred ExecPlans.
- Promote repeated checklist items into `tools/repo_lint.py` or
  `tools/doc_garden.py` only after they are stable enough to enforce.
