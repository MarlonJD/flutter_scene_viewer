# CLAUDE.md

Behavioral rules adapted for `flutter_scene_viewer`. These rules also apply to
Codex. They intentionally bias toward caution, small diffs, and verifiable work.

## 1. Think before coding

Do not assume silently.

Before changing code:

- Name the active plan you are executing.
- State assumptions and constraints.
- Surface tradeoffs if more than one implementation is plausible.
- Push back on overbroad scope.
- Ask only when blocked; otherwise make a conservative documented choice.

Project-specific examples:

- Do not assume all GLB files have UVs, tangents, skins, or animations.
- Do not assume `interactive_3d` is slower; benchmarks decide.
- Do not assume missing material features can be approximated invisibly; emit diagnostics.

## 2. Simplicity first

Write the minimum code that makes the plan pass.

- No speculative render features.
- No single-use abstractions.
- No custom shader work in v1.
- No CAD tessellation, UV unwrap, or tangent generation in the viewer layer.
- No VR-specific behavior.
- If a feature requires engine-level work in `flutter_scene`, document it instead of faking it.

## 3. Surgical changes

Touch only what the active plan requires.

- Match existing style.
- Do not refactor adjacent code opportunistically.
- Remove only unused code introduced by your change.
- Keep public API changes documented in `docs/PUBLIC_API.md`.
- Keep architecture changes documented in `docs/ARCHITECTURE.md` or an ADR.

Every changed line should trace to the active plan.

## 4. Goal-driven execution

Each task must have success criteria and checks.

Plan format:

```text
1. Change: ...
   Verify: ...
2. Change: ...
   Verify: ...
```

For behavior changes:

- write or update a test first when practical;
- implement;
- run `bash harness/run_checks.sh`;
- update the active plan log with results.

## 5. Harness discipline

The repository is the source of truth. Put durable decisions in files, not in chat.

- Add design context to `docs/design-docs/`.
- Add executable implementation plans to `docs/exec-plans/active/`.
- Move completed plans to `docs/exec-plans/completed/`.
- Update `docs/generated/` only through scripts when scripts exist.
- Keep `AGENTS.md` short; link out to details.

## 6. Done definition

A change is done only when:

- implementation is complete for the selected slice;
- tests or lints cover the behavior;
- harness checks were attempted;
- docs/plans were updated;
- remaining limitations are explicitly logged.
