# Roadmap

This roadmap is the current product direction for `flutter_scene_viewer`.
It is intentionally scoped around Flutter product configurators, not game-engine
or CAD-authoring workflows.

## V1.0: static GLB product viewer/configurator

V1.0 focuses on a lightweight, high-performance static GLB viewer for product,
vehicle, textile, medical, and industrial configurator use cases.

In scope:

- GLB loading from network, assets, and bytes;
- assembly/sub-assembly/part hierarchy from glTF nodes;
- stable `nodePath` plus `primitiveIndex` part addressing;
- picking, visibility, camera fit, orbit, pan, and zoom;
- runtime material and texture overrides, reset, and serializable state;
- adaptive/on-demand rendering, cache behavior, and diagnostics;
- viewer-controlled studio lighting plus a small curated environment workflow;
- core glTF metallic-roughness PBR: base color, normal, metallic/roughness,
  occlusion, emissive, alpha, and double-sided behavior;
- opaque-family material/effect masks for channel-packed regional material
  controls such as paint regions, dirt, roughness variation, and coat masks;
- real transmission/glass support as a release blocker;
- real clearcoat support as a release blocker.

Transmission/glass must mean actual glTF-style transmission/refraction behavior
with IOR/Fresnel and volume attenuation where requested. Clearcoat must mean an
actual second specular coating layer such as `KHR_materials_clearcoat`. The
viewer must not market alpha blending as glass or lower roughness as clearcoat.
If upstream `flutter_scene` does not expose these renderer/importer features,
V1.0 remains blocked or reports typed capability diagnostics.

Material/effect masks in V1 are not alpha cutout and not visibility masks.
They are opaque-family packed data maps that route channels to material
parameters. Pixel discard / masked cutout remains a separate material family,
and configurator show/hide behavior must use part or node visibility.

## V2: production configurator polish

V2 matures the product configurator surface without turning the package into a
game engine.

Candidate scope:

- curated material presets such as glass, car paint, clearcoat paint, fabric,
  plastic, and metal;
- curated environment presets as the recommended workflow;
- stronger capability diagnostics and model-authoring guidance;
- better persisted configurator state and restore flows;
- cache, memory-budget, and large-model behavior hardening;
- production GLB compression support for target configurator assets:
  `KHR_draco_mesh_compression`, `EXT_meshopt_compression`, and KTX2 /
  `KHR_texture_basisu`, with typed diagnostics instead of silent fallback when
  a decoder is unavailable;
- role-aware imported texture mipmaps for GLB material textures, so base-color
  textures, normal maps, and data maps such as metallic-roughness/occlusion are
  downsampled with the correct color, vector, or linear-data rules;
- imported material-extension coverage needed by real configurator assets,
  including `KHR_materials_specular`, `KHR_materials_ior`, and
  `KHR_materials_sheen` in addition to the V1 glass/clearcoat
  material-extension path;
- A1B32-style compressed textile/fashion assets as a V2 acceptance gate:
  Draco-compressed primitives, specular/IOR materials, texture maps, hierarchy,
  picking, and diagnostics must work without manual asset preprocessing;
- packed material-mask authoring guidance when compressed-texture support is in
  place;
- bounded multi-file `.gltf` resolution when target assets need external
  `.bin` or image files;
- simple rigid/node animation for product interactions such as doors,
  exploded views, and mechanical movement.

Current V2 implementation status: `KHR_draco_mesh_compression` is wired
through an optional sibling native decoder plugin with iOS Simulator A1B32
evidence and Android native build evidence still pending; `EXT_meshopt_compression`
is decoded in Dart by rewriting embedded GLB bufferViews before
`flutter_scene` import; KTX2 / `KHR_texture_basisu` is handled through the
optional `flutter_scene_viewer_basisu` sibling plugin, which vendors Basis
Universal plus Zstd, transcodes GLB-embedded KTX2 images to PNG, and hands the
decoded image payloads back to the root Dart GLB rewrite path before
`flutter_scene` import. Full visual evidence for KTX2 samples still belongs to
the V2 validation pass.

The bounded ingestion/compression baseline is recorded in completed
[Plan 013](exec-plans/completed/013_v2_production_glb_pipeline.md). Selected
glTF material, texture, sampler, and compression extension correctness is
recorded in completed
[Plan 014](exec-plans/completed/014_selected_gltf_extension_support.md).
Renderer-native clearcoat implementation and pin closure are recorded in completed
[Plan 015](exec-plans/completed/015_renderer_native_clearcoat.md); native
transmission/volume implementation, immutable pin, and controlled iOS
Simulator evidence are recorded in completed
[Plan 016](exec-plans/completed/016_renderer_native_transmission_volume.md).
Decoder cancellation/resource control, authored KTX2 mip chains, physical
targets, packaging, and release evidence are active in
[Plan 017](exec-plans/active/017_decoder_control_mip_chains_and_release_evidence.md).
Sheen diagnostics, a bounded package-local candidate, controlled textile/ToyCar
evidence, and the renderer-native release path remain deferred in
[Plan 018](exec-plans/deferred/018_khr_materials_sheen.md).

The approved modern-glTF follow-up sequence is split into independent deferred
plans. Numeric order is the planning order, not permission to activate more
than one plan at a time:

| Plan | Capability | Khronos status on 2026-07-16 | Activation gate |
| --- | --- | --- | --- |
| [018](exec-plans/deferred/018_khr_materials_sheen.md) | `KHR_materials_sheen` | ratified | Plan 015 complete; diagnostic → candidate-only → renderer-native gates. |
| [019](exec-plans/deferred/019_khr_lights_punctual.md) | `KHR_lights_punctual` | ratified | Plan 015 complete; establish the shared directional/point/spot direct-light loop before later directional lobes. |
| [020](exec-plans/deferred/020_khr_materials_variants.md) | `KHR_materials_variants` | ratified | Finish the active plan; keep source-material selection separate from runtime overrides. |
| [021](exec-plans/deferred/021_khr_materials_emissive_strength.md) | `KHR_materials_emissive_strength` | ratified | Finish the active plan; require native HDR emission and tone-mapping evidence. |
| [022](exec-plans/deferred/022_khr_materials_anisotropy.md) | `KHR_materials_anisotropy` | ratified | Plans 015 and 019 complete; renderer-native tangent, direct, and IBL paths required. |
| [023](exec-plans/deferred/023_khr_materials_iridescence.md) | `KHR_materials_iridescence` | ratified | Plans 015 and 019 complete; renderer-native thin-film direct and IBL paths required. |
| [024](exec-plans/deferred/024_khr_materials_diffuse_transmission.md) | `KHR_materials_diffuse_transmission` | Release Candidate | Re-audit/pin the spec and approve renderer feasibility before freezing public API. |
| [025](exec-plans/deferred/025_khr_materials_dispersion.md) | `KHR_materials_dispersion` | ratified | Plan 016 native transport is complete; explicit Plan 025 promotion and its spectral/evidence gates remain. |
| [026](exec-plans/deferred/026_khr_materials_subsurface.md) | `KHR_materials_subsurface` | Initial Draft | Research only until spec, product, renderer, and measured target gates pass. |
| [027](exec-plans/deferred/027_khr_materials_pbr_specular_glossiness_compatibility.md) | archived `KHR_materials_pbrSpecularGlossiness` input | archived/ratified | Compatibility last; bounded conversion or typed fallback, never a new authoring workflow. |

Filament and Three.js are implementation/reference renderers for this sequence,
not automatic proof of viewer support. Every comparison pins the reference
version and verifies that its importer and shader actually consume the tested
extension. The same camera, model transform, HDRI, direct lights, exposure,
tone mapping, output color space, and viewport are mandatory.

Already-built raw HDR/EXR and Poly Haven environment paths may remain if they
work, and they may be completed as bounded advanced opt-in environment sources.
They are still not the default product workflow: no implicit network downloads,
no HDRI marketplace experience, and no expansion into a general HDR/EXR
material texture decoder. They should keep the existing safety shape: byte
limits, timeouts, cancellation, cache behavior, and typed diagnostics.

## V3: lightweight authored animation

V3 can add optional authored animation playback for small interactive scenes.

Candidate scope:

- authored GLB animation playback;
- clip listing and selection;
- play, pause, loop, and playback speed controls;
- skeletal animation playback when upstream support and fixture evidence are
  strong enough;
- lightweight mascot, character, mechanical, or small-game style animations.

Out of scope:

- runtime rig editing;
- inverse kinematics;
- animation authoring tools;
- ragdoll, cloth, or physics-driven characters;
- full game-engine animation systems.

Morph targets and blend shapes are V3+ or later candidates only if there is a
clear product need and upstream support. They are not V1/V2 work.

## V3 research lane: Flutter GPU material rendering

V3 may also carry a bounded Flutter GPU / `flutter_scene` rendering research
lane for material quality work that is too speculative for V2. This lane must
not introduce a Filament backend, a general shader graph, or a replacement PBR
renderer.

Candidate scope:

- targeted repo-local shader improvements for clearcoat and glass when they can
  stay compatible with `flutter_scene` scene ownership;
- Flutter GPU feasibility checks for better real-time refraction, transmission
  compositing, and clearcoat highlights;
- fork-free experimental ray/path-tracing reference views for visual
  validation, measured device feasibility, and offline comparison only, not as
  the default interactive mobile renderer;
- explicit diagnostics when a material feature requires renderer capabilities
  outside the current Flutter GPU / `flutter_scene` path.

Out of scope:

- Filament-backed rendering;
- production claims of full physical glass, caustics, multi-bounce refraction,
  or path tracing without measured target-platform evidence;
- a maintained `flutter_scene` fork, a permanent viewer-owned ray-tracing
  package, or conversion of the root viewer package into a native renderer;
- replacing the V2 production GLB pipeline or viewer/configurator API.

The deferred
[Plan 028](exec-plans/deferred/028_adaptive_ray_path_tracing_feasibility.md)
owns this research lane. It starts with an unpublished
`tools/raytracing_lab/` Flutter application, leaves the root package and pinned
`flutter_scene` unchanged, and reaches a measured GO/NO-GO decision before any
upstream or product integration. A GO result produces a direct-upstream
`flutter_scene` seam proposal and a separately approved Plan 029; it does not
create `flutter_scene_viewer_raytracing` by default. A temporary sibling plugin
requires a separate product/timing decision and explicit removal or migration
criteria.

## V4: CAD/import research track

V4 is a research track for CAD import, not a core viewer refactor.

Candidate scope:

- Open Cascade Technology (OCCT) FFI feasibility;
- STEP and IGES parsing;
- native build and packaging strategy;
- CAD tessellation settings and diagnostics;
- an optional separate importer package if the workflow proves viable.

CAD tessellation should not be attempted with ad hoc Dart geometry code. It
requires a real CAD kernel/import path before tessellation quality can be
discussed.

## Persistent non-goals

- VR, AR, OpenXR, WebXR, and platform-specific AR integrations;
- UV unwrap, mesh repair, and DCC-specific axis guessing;
- parallax and displacement mapping;
- terrain rendering;
- arbitrary custom shader graphs or a custom PBR renderer;
- claims that this is faster than other viewers without benchmark evidence.
