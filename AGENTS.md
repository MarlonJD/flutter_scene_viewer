# AGENTS.md

This file is a map, not an encyclopedia. Keep it short. Use the linked docs for
details. The repository is optimized for Codex-style agent work: small plans,
mechanical checks, and evidence-driven implementation.

## Start here

1. Read `docs/PROJECT_CHARTER.md`.
2. Read `docs/ARCHITECTURE.md`.
3. Pick exactly one active plan from `docs/exec-plans/active/`.
4. Implement the smallest verifiable slice.
5. Run `bash harness/run_checks.sh`.
6. Update the plan's progress log before stopping.

## Project intent

Build a high-level `flutter_scene` viewer/configurator package. Do not build a
new engine. Do not write a custom PBR renderer. Do not tessellate CAD files or
unwrap UVs. The viewer adapts `flutter_scene` into a stable public Flutter API.

## MVP boundaries

In scope for v1:

- static GLB loading from network/assets/bytes;
- assembly/sub-assembly/part hierarchy from glTF nodes;
- node path + primitive index addressing;
- core glTF PBR texture/material overrides;
- viewer-controlled studio lighting;
- picking, visibility, camera controls, cache, diagnostics;
- adaptive/on-demand render policy.

Out of scope for v1:

- skeletal posing, morph targets, blend shapes;
- Draco/meshopt/KTX2;
- imported glTF lights/cameras;
- parallax, displacement, subsurface, world-aligned textures;
- VR-specific features;
- claims that this is faster than Filament without benchmarks.

## Coding rules

- Think before coding; state assumptions in the plan log.
- Prefer the smallest code that satisfies the active plan.
- Touch only files required by the plan.
- Add or update tests with every behavior change.
- Do not change public API names without updating docs and tests.
- If a model lacks UVs for texture override, return diagnostics; do not invent UVs.
- If a material feature is unsupported, report capability diagnostics; do not fake support.

## Verification commands

```sh
bash harness/run_checks.sh
python3 harness/repo_lint.py
```

When Flutter is unavailable, run the Python repo lints and record the missing
Flutter toolchain in the active plan log.

## Key docs

- Product: `docs/PROJECT_CHARTER.md`
- Architecture: `docs/ARCHITECTURE.md`
- Harness: `docs/HARNESS_ENGINEERING.md`
- Public API: `docs/PUBLIC_API.md`
- Runtime GLB: `docs/RUNTIME_GLB_PIPELINE.md`
- Materials: `docs/MATERIALS_AND_LIGHTING.md`
- Quality: `docs/QUALITY_SCORE.md`
- Plans: `docs/exec-plans/active/`
