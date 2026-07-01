# CODEX.md

## Mission

Implement `flutter_scene_viewer` as a high-level viewer/configurator package on
top of `flutter_scene`.

## Immediate command for a fresh Codex run

```text
Read AGENTS.md, CLAUDE.md, docs/PROJECT_CHARTER.md, docs/ARCHITECTURE.md, and
then execute docs/exec-plans/active/000_bootstrap_foundation.md. Make the
smallest verifiable changes. Run bash tools/run_checks.sh. Update the plan log.
```

## Local checks

```sh
bash tools/run_checks.sh
```

The tooling is designed to keep the repo agent-readable:

- `dart format` verifies style;
- `flutter analyze` verifies static correctness;
- `flutter test` verifies behavior;
- `python3 tools/repo_lint.py` verifies repository knowledge structure.

## PR loop

For each PR:

1. Cite the active plan.
2. Summarize assumptions.
3. List changed files and why each was touched.
4. Provide verification output.
5. Record remaining limitations.

Do not start another plan until the active plan is either complete or explicitly
paused in its progress log.
