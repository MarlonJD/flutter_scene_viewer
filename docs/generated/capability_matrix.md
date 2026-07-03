# Capability matrix

Generated placeholder. Update through tooling when adapter checks exist.

| Capability | Status | Notes |
| --- | --- | --- |
| Static GLB load | Planned | `Node.fromGlbBytes` adapter |
| Core PBR material read | Planned | `PhysicallyBasedMaterial` adapter |
| Runtime base color texture | Planned | Requires UV diagnostic |
| Metallic/roughness override | Planned | Patch + reset semantics |
| Alpha opaque/mask/blend | Supported | Runtime `MaterialAlphaMode` maps to `flutter_scene` alpha behavior for supported materials; unlit mask reports diagnostics because upstream treats it like blend |
| Material/effect masks | Blocked | Public opaque-family intent and validation exist, but rendering requires an opaque-family shader backend; current standard PBR path reports diagnostics rather than faking output |
| Authored material extension intent | Supported | Binary GLB JSON reader maps transmission, IOR, volume, and clearcoat intent to internal patches; malformed values, duplicate node paths, and missing UV0 texture slots produce diagnostics |
| Production shader preflight | Supported on iOS Simulator | `productionShaders()` advertises support only after shader preflight succeeds; shader-load failures report typed diagnostics with `stage: shaderPreflight` |
| Transmission/glass | Supported on iOS Simulator | Default policy is diagnostic-only; production mode is preflight-gated and has local host visual-matrix/reference evidence plus verified local iOS Simulator visual evidence |
| Clearcoat | Candidate on iOS Simulator | Diagnostic-only by default; production mode is preflight-gated and uses a lit `.fmat` clearcoat backend with a bounded separate coating lobe; shader-load and synthetic visual-matrix evidence pass locally on iOS Simulator, but real textured GLB evidence remains candidate-only and not production-ready |
| Material extension platform evidence | Verified locally on iOS Simulator | iOS Simulator is the only 011 production target with evidence; macOS, Android, Web, and physical iOS are deferred/not run |
| Part hierarchy | Planned | Node path + primitive index |
| Picking | Planned | Scene raycast adapter |
| Adaptive render | Planned | Widget/scheduler implementation |
| Skeletal animation | Deferred | Not MVP |
| Morph targets | Deferred | Not MVP |
| Imported lights/cameras | Deferred | Not MVP |
