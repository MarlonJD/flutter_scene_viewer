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
| Production shader preflight | Supported for custom shader backend | `productionShaders()` performs shader preflight and reports `backendKind: flutterSceneCustomShader` when required package shader entries are available; shader-load failures report typed diagnostics with `stage: shaderPreflight` |
| Transmission/glass | Production on verified iOS Simulator scope | Default policy is diagnostic-only; production policy routes supported glass patches through the repo-owned custom shader backend after preflight, with fixture, ToyCar, and acceptance metrics evidence |
| Clearcoat | Production on verified iOS Simulator scope | Diagnostic-only by default; production policy routes supported clearcoat patches through the repo-owned `.fmat` overlay backend after preflight, with synthetic matrix, ToyCar, and acceptance corpus evidence |
| Material extension platform evidence | Verified locally on iOS Simulator | iOS Simulator is the current verified production target for `backendKind: flutterSceneCustomShader`; macOS, Android, Web, and physical iOS are deferred/not run |
| Part hierarchy | Planned | Node path + primitive index |
| Picking | Planned | Scene raycast adapter |
| Adaptive render | Planned | Widget/scheduler implementation |
| Skeletal animation | Deferred | Not MVP |
| Morph targets | Deferred | Not MVP |
| Imported lights/cameras | Deferred | Not MVP |
