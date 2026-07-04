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
| Production shader preflight | Candidate-only | `productionShaders()` performs shader preflight but does not advertise production support for package-local glass or clearcoat; shader-load failures and candidate-only status report typed diagnostics with `stage: shaderPreflight` |
| Transmission/glass | Candidate on iOS Simulator | Default policy is diagnostic-only; package-local shader evidence exists for fixtures and ToyCar real-asset evidence, but production support is not advertised |
| Clearcoat | Candidate on iOS Simulator | Diagnostic-only by default; the package-local `.fmat` clearcoat overlay backend has shader-load, synthetic visual-matrix, and ToyCar real-asset evidence, but production support is not advertised |
| Material extension platform evidence | Verified locally on iOS Simulator | iOS Simulator is the only 011 production target with evidence; macOS, Android, Web, and physical iOS are deferred/not run |
| Part hierarchy | Planned | Node path + primitive index |
| Picking | Planned | Scene raycast adapter |
| Adaptive render | Planned | Widget/scheduler implementation |
| Skeletal animation | Deferred | Not MVP |
| Morph targets | Deferred | Not MVP |
| Imported lights/cameras | Deferred | Not MVP |
