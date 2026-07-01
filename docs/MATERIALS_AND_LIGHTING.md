# Materials and lighting

## V1 material scope

Support core glTF metallic-roughness PBR:

- base color factor and texture;
- normal texture;
- metallic factor;
- roughness factor;
- metallic-roughness texture;
- occlusion texture;
- emissive factor and texture;
- alpha mode and double-sided where `flutter_scene` exposes them.

## Texture UV requirement

Texture override requires authored UV coordinates; `flutter_scene_viewer` does
not generate UV unwraps. If the target primitive lacks the required UV set, the
viewer reports diagnostics and preserves the current material.

## Excluded from v1

- clearcoat;
- transmission/glass;
- sheen;
- subsurface scattering;
- parallax mapping;
- displacement mapping;
- world-aligned textures;
- custom network shader code.

## Subsurface scattering note

Subsurface scattering models light traveling through translucent material and
taking on material-dependent color, such as skin appearing red when strong light
passes through it. That level of light transport belongs in dedicated 3D engines
or future opt-in extensions, not the v1 viewer core.

## Normal map note

Normal maps do not change silhouette or actual geometry. Advanced depth effects
may require parallax or displacement, but that belongs outside this v1 viewer
core.

## Lighting policy

V1 uses viewer-controlled studio lighting. The goal is predictable product
viewing, not authored full-scene playback. Imported glTF lights are future work.
