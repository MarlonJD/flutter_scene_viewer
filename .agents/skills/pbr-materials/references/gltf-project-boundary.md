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
- [KHR_texture_transform](https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Khronos/KHR_texture_transform)

Use the ratified extension text, not renderer-specific property names, for
public serialization and validation semantics.

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

Before changing an extension path, inspect range validation, texture channels,
color-space selection, UV handling, combined base-plus-extension patches,
double-sided state, reset/persistence behavior, and unsupported diagnostics.

## Renderer identity

The dependency pinned by this repository is not backed by Google Filament:

- Native: Flutter GPU over Impeller.
- Web: the pinned `flutter_scene` WebGL2 implementation.
- Filament and Karis: public shading references used by `flutter_scene` and
  package-local material work.

Primary evidence:

- [Pinned flutter_scene README](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/README.md#L39-L79)
- [Pinned PBR helpers](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/shaders/pbr.glsl#L5-L57)

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
