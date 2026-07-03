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
- KTX2 / `KHR_texture_basisu` texture-compression investigation plus packed
  material-mask authoring guidance when upstream support is available;
- bounded multi-file `.gltf` resolution when target assets need external
  `.bin` or image files;
- simple rigid/node animation for product interactions such as doors,
  exploded views, and mechanical movement.

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
