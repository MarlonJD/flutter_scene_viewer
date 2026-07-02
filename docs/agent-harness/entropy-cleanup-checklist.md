# Entropy cleanup checklist

Use this checklist when docs or plans start feeling noisy.

## Active plans

- There should be exactly one current execution plan for the next work slice.
- Plans with all acceptance criteria checked should move to `completed/` unless
  the progress log clearly says why they remain active.
- Deferred work belongs in `deferred/`, not as a checked-off active plan.
- `docs/project-plan-v2/` is source material only; do not implement directly
  from it.

## Generated and score docs

- `docs/QUALITY_SCORE.md` should match completed evidence, not old intentions.
- `docs/generated/*` should either name its generator or say it is a manual
  placeholder waiting for tooling.
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
- Promote repeated checklist items into `tools/repo_lint.py` or
  `tools/doc_garden.py` only after they are stable enough to enforce.
