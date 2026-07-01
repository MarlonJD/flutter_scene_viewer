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

## Excluded from v1

- clearcoat;
- transmission/glass;
- sheen;
- subsurface scattering;
- parallax mapping;
- displacement mapping;
- world-aligned textures;
- custom network shader code.

## Normal map note

Normal maps do not change silhouette or actual geometry. Advanced VR/depth use
cases may require parallax or displacement, but that belongs outside this v1
viewer core.

## Lighting policy

V1 uses viewer-controlled studio lighting. The goal is predictable product
viewing, not authored full-scene playback. Imported glTF lights are future work.
