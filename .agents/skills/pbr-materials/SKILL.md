---
name: pbr-materials
description: Use when work in this repository involves PBR, BRDF or BTDF, metallic-roughness, clearcoat, glass or transmission, IOR or Fresnel, IBL or HDRI, exposure or tone mapping, material shader review, Filament, Brian Karis, Frostbite sky/cloud rendering, glTF material extensions, or flutter_scene renderer boundaries.
---

# PBR Materials

## Core principle

Ground material and lighting decisions in the primary source that owns the
claim. Never treat a renderer paper or shared equation as evidence that the
current `flutter_scene` backend implements that feature.

## Workflow

1. Read `docs/PROJECT_CHARTER.md`, `docs/ARCHITECTURE.md`, and
   `docs/MATERIALS_AND_LIGHTING.md` before proposing behavior.
2. Read the matching reference file completely:
   - Standard PBR, clearcoat, IBL, lighting, or material authoring:
     [filament-material-system.md](references/filament-material-system.md)
   - GGX choices, split-sum IBL, or UE4 material parameterization:
     [karis-2013-ue4.md](references/karis-2013-ue4.md)
   - Atmosphere, participating media, or volumetric sky/clouds:
     [frostbite-sky-clouds.md](references/frostbite-sky-clouds.md)
   - glTF semantics, current backend identity, or package boundaries:
     [gltf-project-boundary.md](references/gltf-project-boundary.md)
3. Verify current capability from the pinned dependency, adapter code, tests,
   and target evidence. Use `pubspec.yaml`, `pubspec.lock`, and
   `.dart_tool/package_config.json` to locate the exact `flutter_scene` source.
4. Classify each conclusion as one of:
   - wrapper public API, persistence, diagnostics, or validation;
   - renderer-internal or upstream `flutter_scene` behavior;
   - future research or explicitly out of scope.
5. Separate source facts from inference. Cite exact local lines and primary
   source pages or anchors for material claims.

## Evidence routing

| Claim | Authority |
| --- | --- |
| glTF field, channel, color-space, or extension semantics | Khronos glTF specification or ratified extension |
| Current rendered capability | Pinned `flutter_scene` source, adapter path, tests, and target evidence |
| BRDF or real-time approximation design | Filament documentation or Karis course material |
| Atmosphere or participating-media design | Frostbite course notes |
| Product scope and public promises | Project charter, architecture, roadmap, and active plan |

## Output contract

Lead with the decision. Then report implications in this order:

1. wrapper API, diagnostics, serialization, and validation;
2. renderer or shader internals;
3. evidence gaps, target limits, and future scope.

Use the repository's literal evidence labels: `verified locally`, `not run`,
`blocked`, `candidate-only`, `release pending`, and `production-ready`.

## Guardrails

- Do not call Filament the rendering backend. It is a shading reference;
  native rendering uses Flutter GPU/Impeller and web uses the pinned
  `flutter_scene` WebGL2 path.
- Do not expose GGX, Smith, Schlick, DFG LUT, probe convolution, or shader
  precision choices as viewer API knobs.
- Do not equate alpha blending with transmission, UE4 cavity with glTF
  occlusion, or a skybox image with a dynamic atmosphere.
- Do not copy third-party shader source. Re-express public equations and carry
  citations and license obligations when copied material is ever necessary.
- Report unsupported capabilities; never invent UVs or silently fake a
  requested material feature.
