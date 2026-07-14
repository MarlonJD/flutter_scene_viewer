# Quality score

Each completed plan should update this table.

| Area | Score | Evidence | Next action |
| --- | ---: | --- | --- |
| Public API skeleton | 2/5 | Stubs and tests exist | Implement real adapter |
| Runtime GLB loading | 1/5 | Planned | Implement network/bytes loader |
| Part registry | 1/5 | Planned | Traverse node hierarchy |
| Material overrides | 1/5 | Public types exist | Bind to flutter_scene materials |
| Adaptive render | 1/5 | Policy enum exists | Implement scheduler |
| Tooling | 3/5 | Checks and repo lints exist | Add fixture tests |
| Selected glTF extension evidence | 3/5 | Host parsing/codec/rewrite evidence and an explicit [feature/target matrix](generated/capability_matrix.md) exist | Run current target captures; resolve upstream renderer blockers |
| Docs | 4/5 | Project docs, plans, and generated capability truth exist | Keep plan logs and target rows current |

Scores are intentionally conservative. Do not inflate without executable checks.
