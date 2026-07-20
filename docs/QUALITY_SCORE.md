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
| Selected glTF extension evidence | 4/5 | Host parsing/codec/rewrite evidence, the stable [feature/target matrix](generated/capability_matrix.md), its fingerprinted Plan 014 history, the tracked decoder/mip evidence contract, and renderer-native clearcoat plus transmission/volume iOS Simulator evidence exist | Capture durable iOS Simulator and Web runtime records, then physical iOS and packaging records; Android remains `blocked` until its device/build environment is available, and unchecked rows remain `not run` |
| Docs | 4/5 | Project docs, plans, and generated capability truth exist | Keep plan logs and target rows current |

Scores are intentionally conservative. Do not inflate without executable checks.
