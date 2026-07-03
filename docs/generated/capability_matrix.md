# Capability matrix

Generated placeholder. Update through tooling when adapter checks exist.

| Capability | Status | Notes |
| --- | --- | --- |
| Static GLB load | Planned | `Node.fromGlbBytes` adapter |
| Core PBR material read | Planned | `PhysicallyBasedMaterial` adapter |
| Runtime base color texture | Planned | Requires UV diagnostic |
| Metallic/roughness override | Planned | Patch + reset semantics |
| Transmission/glass | Blocked | Intent fields are diagnostic-only until real `KHR_materials_transmission`, `KHR_materials_ior`, and `KHR_materials_volume` support exists in `flutter_scene`; alpha blend is not glass |
| Clearcoat | Blocked | Intent fields are diagnostic-only until real `KHR_materials_clearcoat` support exists in `flutter_scene`; low roughness is not clearcoat |
| Part hierarchy | Planned | Node path + primitive index |
| Picking | Planned | Scene raycast adapter |
| Adaptive render | Planned | Widget/scheduler implementation |
| Skeletal animation | Deferred | Not MVP |
| Morph targets | Deferred | Not MVP |
| Imported lights/cameras | Deferred | Not MVP |
