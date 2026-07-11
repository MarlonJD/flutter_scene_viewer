# Frostbite sky, atmosphere, and cloud reference

Use this note for participating media, physical sky/atmosphere, aerial
perspective, and volumetric clouds. Do not treat this source as a glTF surface
material specification.

## Canonical source

- Sebastien Hillaire, [Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite](https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf), SIGGRAPH 2016 course material, 62 pages.

Use 1-based PDF page numbers when citing this source.

## Page map

- pp. 4-7: goals and production context: dynamic time of day, weather,
  physical parameterization, artist control, and real-time scalability.
- pp. 8-16: participating-media fundamentals: absorption, scattering,
  extinction, transmittance, in-scattering, visibility, albedo, and phase
  functions.
- pp. 17-24: atmosphere rendering with Rayleigh/Mie/ozone terms,
  transmittance/scattering LUTs, and aerial perspective.
- pp. 25-29: sun, moon, stars, exposure, and environment/reflection capture.
- pp. 30-36: weather/type textures, procedural 3D noise, cloud density,
  ray marching, shadow rays, and temporal reprojection.
- pp. 37-42: low-sample integration, dual-lobe phase behavior, and practical
  multiple-scattering approximation.
- pp. 42-45: cloud interaction with shadows, GI, aerial perspective,
  reflections, and multiple render views.
- p. 51: explicit limitations and future work.

## Relevant lessons for this package

- Keep material values independent from the current lighting environment.
- Treat background, IBL, direct key light, exposure, reflections, and shadows
  as a coherent lighting state.
- If an HDRI contains a visible sun, align any analytic key light with it to
  avoid contradictory highlights.
- Use curated HDRI/environment presets as the bounded v1 solution. A skybox
  image alone is not dynamic atmosphere support.
- A continuously changing sky would require sustained render scheduling;
  the current adaptive static viewer does not imply that mode.

## Pinned upstream foothold

The pinned `flutter_scene` revision already exposes `PhysicalSkySource`,
`SkyEnvironment`, and `SunLight`. `PhysicalSkySource` is a bounded analytic
Rayleigh/Mie daylight sky; it is not the Frostbite LUT, ozone,
aerial-perspective, or volumetric-cloud system. The current viewer adapter
clears `skyEnvironment` and installs its own environment-backed skybox.

Treat an upstream-backed physical-daylight preset as a possible future
`candidate-only` investigation. Require an approved plan, coherent sun/IBL/key
light behavior, scheduler analysis, and target visual/performance evidence.
Start with static or manual refresh and make no cloud or full-atmosphere claim.

Pinned source checkpoints:

- [PhysicalSkySource](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/lib/src/sky_sources.dart#L93-L103)
- [SkyEnvironment refresh policy](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/lib/src/sky_environment.dart#L8-L26)
- [SunLight](https://github.com/bdero/flutter_scene/blob/cd6760912fa38beb55f63e388655a1aeabd32fe4/packages/flutter_scene/lib/src/sun_light.dart#L9-L23)

## Out of v1 scope

- Rayleigh/Mie/ozone atmosphere simulation and LUT generation;
- froxel or aerial-perspective volumes;
- volumetric cloud authoring, ray marching, temporal accumulation, or
  multiple scattering;
- cloud shadows, cloud-driven GI, and cloud/environment feedback;
- physical sun/moon/star simulation and full imported-scene playback.

Those features belong in upstream `flutter_scene`, a separate optional
renderer package, or an explicitly approved future research lane. Do not add
v1 public controls or diagnostics for a request surface that does not exist.
