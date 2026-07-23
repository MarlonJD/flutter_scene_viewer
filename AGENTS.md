# AGENTS.md

This file is the concise repository map. Put detailed product, architecture,
tooling, and evidence guidance in the linked canonical documents.

## Start here

1. Read `docs/PROJECT_CHARTER.md`.
2. Read `docs/ARCHITECTURE.md`.
3. Read `docs/ROADMAP.md` and the relevant ExecPlan. Promote future work from
   `docs/exec-plans/deferred/` into `active/` before implementation.
4. Keep at most one active plan. The directory may be empty between selected
   work slices.
5. Implement the smallest verifiable slice, run `bash tools/run_checks.sh`,
   and update the active plan before stopping.

Harness operation, output, and cleanup rules live in
`docs/agent-harness/README.md`. Tool commands live in
`docs/REPO_TOOLING.md`.

## Durable constraints

- Build a high-level `flutter_scene` viewer/configurator adapter, not a new
  renderer, game engine, CAD tessellator, or UV authoring tool.
- Preserve glTF node hierarchy and `nodePath` + `primitiveIndex` addressing.
- Return typed diagnostics for missing authoring data or unsupported features;
  do not invent UVs or fake material support.
- State material assumptions and evidence boundaries in the active plan.
- Add or update tests with every behavior change.
- Do not change public API names without updating docs and tests.
- Do not make performance-superiority claims without benchmark evidence.

## Documentation rules

- Keep `README.md` lean and public-facing. Extend an existing canonical
  document before creating a new authority or historical planning pack.
- For PBR, BRDF/BTDF, material, lighting, IBL, glass, clearcoat, Filament,
  Karis, or Frostbite questions, use the repo-local `pbr-materials` skill.

## Verification and completion

```sh
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
```

Work is complete when relevant tests and repository checks pass, the active
plan records the observed evidence, generated documents are refreshed from
their source, and remaining target or release gaps use the literal labels in
`docs/agent-harness/output-contract.md`.

When Flutter is unavailable, run the Python repository lint and record the
missing toolchain in the active plan rather than implying full verification.
