# Karis 2013 UE4 shading reference

Use this note for the historical real-time choices behind GGX, the split-sum
IBL approximation, and a compact artist-facing metallic-roughness workflow.

## Canonical source

- Brian Karis, [Real Shading in Unreal Engine 4](https://blog.selfshadow.com/publications/s2013-shading-course/karis/s2013_pbs_epic_slides.pdf), SIGGRAPH 2013 course slides.

Use 1-based PDF page numbers when citing this source.

## Page map

- p. 5: Lambert diffuse; more complex diffuse produced little visible benefit
  for the target.
- pp. 6-9: Cook-Torrance microfacet specular, GGX distribution, Schlick
  geometry fitted to Smith, and Schlick Fresnel.
- pp. 10-17: single-sample real-time IBL and the split-sum approximation.
  Prefiltered cubemap mips store the lighting term by roughness; a 2D BRDF LUT
  stores the view-angle/roughness response. The `n = v` assumption loses
  stretched highlights.
- pp. 19-20: BaseColor, Metallic, Roughness, and Cavity material workflow.
- pp. 21-24: UE4 shader-graph material layering.
- pp. 26-35: inverse-square and representative-point area-light work.

## Project mapping

The pinned `flutter_scene` source explicitly attributes its DFG LUT and
split-sum use to Karis 2013:

- [DFG LUT generation](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/lib/src/material/dfg_lut.dart#L6-L55)
- [Split-sum lighting evaluation](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/shaders/material_lighting.glsl#L294-L313)

This is shading lineage, not evidence that the backend is Unreal Engine or
Filament.

## Wrapper implications

- Preserve the glTF metallic-roughness vocabulary; do not expose BRDF terms,
  LUT controls, or roughness remaps.
- Do not map UE4 `Cavity` directly to glTF occlusion. The glTF field has its
  own normative channel and strength semantics.
- Directional studio lighting does not need inverse-square attenuation.
  Point, sphere, tube, and general area lights are not implied v1 features.
- Test visible trends rather than UE4 pixel parity: increasing roughness
  broadens reflections, environment rotation moves reflections, and lighting
  affects lit but not unlit materials.

## Limits

These slides predate glTF 2.0 and do not define current normal, occlusion,
emissive, alpha, transmission, volume, IOR, clearcoat, or texture-transform
semantics. Page 36 points to the full course notes for detailed formulas and
code. Use Khronos specifications for the public asset contract.
