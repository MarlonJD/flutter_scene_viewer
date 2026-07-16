# glTF semantics and project boundary

Use this note to decide which concepts belong in the public viewer API, which
belong in `flutter_scene`, and which remain capability-gated.

## Normative sources

- [glTF 2.0 Materials](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials)
- [KHR_materials_clearcoat](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_clearcoat)
- [KHR_materials_transmission](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_transmission)
- [KHR_materials_ior](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_ior)
- [KHR_materials_volume](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_volume)
- [KHR_materials_specular](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_specular)
- [KHR_materials_sheen](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_sheen)
- [KHR_lights_punctual](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_lights_punctual)
- [KHR_materials_variants](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_variants)
- [KHR_materials_emissive_strength](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_emissive_strength)
- [KHR_materials_anisotropy](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_anisotropy)
- [KHR_materials_iridescence](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_iridescence)
- [KHR_materials_diffuse_transmission](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_diffuse_transmission)
- [KHR_materials_dispersion](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_materials_dispersion)
- [KHR_materials_subsurface draft PR](https://github.com/KhronosGroup/glTF/pull/1928)
- [Archived KHR_materials_pbrSpecularGlossiness](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Archived/KHR_materials_pbrSpecularGlossiness)
- [KHR_texture_transform](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_transform)

Use the ratified extension text, not renderer-specific property names, for
public serialization and validation semantics.

Status recorded 2026-07-16: punctual lights, variants, emissive strength,
anisotropy, iridescence, dispersion, sheen, clearcoat, specular, IOR,
transmission, and volume are ratified; diffuse transmission is Release
Candidate; subsurface is Initial Draft; specular-glossiness is archived. Re-read
the registry and pin an exact source revision before implementing an in-progress
extension.

## Core material contract

- Base-color factor/texture, metallic factor, roughness factor,
  metallic-roughness texture, normal texture, occlusion texture, emissive
  factor/texture, alpha mode, and double-sided state form the core v1 surface
  vocabulary.
- Base-color and emissive color data use color-space handling distinct from
  metallic, roughness, occlusion, normal, and other data textures.
- The core metallic-roughness texture packs roughness in green and metallic in
  blue. Occlusion commonly shares red in an ORM texture but remains a separate
  glTF textureInfo slot.
- Factors multiply authored texture data; runtime patches must not silently
  reinterpret channel packing or color space.
- TextureInfo can identify UV sets and transforms. This package deliberately
  limits runtime override application to authored UV0 and reports diagnostics
  for unsupported UV sets; that is a viewer capability boundary, not a glTF
  rule.

## Extension checkpoints

- Clearcoat factor/texture uses the red channel; clearcoat roughness uses the
  green channel; clearcoat normal is independent from the base normal.
- Transmission is not alpha blending. IOR controls interface Fresnel;
  volume adds thickness and attenuation behavior.
- Volume thickness texture uses its green channel.
- Specular and specular-color are separate dielectric controls and must not be
  inferred from the older UE4 `Specular` or `Cavity` terminology.
- Sheen color factor/texture and roughness factor/texture form an independent
  cloth/fiber lobe. Color texture RGB uses sRGB transfer while roughness uses
  linear alpha; clearcoat, when present, is layered above sheen.

Before changing an extension path, inspect range validation, texture channels,
color-space selection, UV handling, combined base-plus-extension patches,
double-sided state, reset/persistence behavior, and unsupported diagnostics.

## Reference-renderer policy

- Filament is a PBR implementation and gltfio reference, not this package's
  backend. Pin its version and verify gltfio support before using it as an
  importer reference. Its material figures/shaders may still inform renderer
  design when an extension importer is absent, but must be labeled as such.
- Pin Three.js exactly and add a pre-capture assertion that GLTFLoader or the
  selected plugin consumed every tested field. The current repository harness
  resolved `three@0.167.1`; a floating semver range is not durable evidence.
- Three.js variants require an external plugin; current built-in GLTFLoader
  does not advertise diffuse transmission or subsurface; specular-glossiness
  support was removed in r147. Do not treat those as ordinary Three.js
  reference renders.
- Reference output establishes direction and regression evidence, not
  automatic pixel parity or proof that the Flutter renderer applied a feature.

## Renderer identity

The dependency pinned by this repository is not backed by Google Filament:

- Native: Flutter GPU over Impeller.
- Web: the pinned `flutter_scene` WebGL2 implementation.
- Filament and Karis: public shading references used by `flutter_scene` and
  package-local material work.

Primary evidence:

- [Pinned flutter_scene README](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/README.md#L39-L79)
- [Pinned PBR helpers](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/shaders/pbr.glsl#L5-L57)

Always re-read `pubspec.lock` before citing the commit; update pinned links in
this note when the dependency revision changes.

## Package boundary

Public wrapper responsibilities:

- stable glTF-oriented API and serialization;
- part addressing, material overrides, validation, reset, and persistence;
- studio environment and key-light controls;
- capability diagnostics and evidence labels.

Renderer responsibilities:

- BRDF/BTDF integration and energy compensation;
- environment convolution, SH/DFG data, sampling, and GPU formats;
- shadows, transparency ordering, refraction compositing, tone mapping, and
  precision/performance choices.

Research or out-of-scope work must not enter the public API without an approved
plan, a real product requirement, renderer feasibility, and target evidence.
