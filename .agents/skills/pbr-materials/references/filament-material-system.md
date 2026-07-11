# Filament material-system reference

Use this note for standard surface PBR, material authoring, clearcoat, IBL,
lighting units, and real-time BRDF tradeoffs. Filament is a design reference,
not the renderer used by this package.

## Canonical sources

- [Physically Based Rendering in Filament](https://google.github.io/filament/main/filament.html#material-system)
- [Current Filament Materials guide](https://google.github.io/filament/Materials.md.html)

The `main` documentation is living material. Cite a section anchor and record
an access date for implementation-specific claims. Never infer
`flutter_scene` capability from Filament documentation.

## Standard surface model

- Surface response is diffuse plus specular: `f = fd + fr`.
- Specular is Cook-Torrance microfacet `D * V * F`:
  - GGX/Trowbridge-Reitz normal distribution;
  - height-correlated Smith-GGX visibility;
  - Schlick Fresnel.
- Diffuse is Lambert in Filament's standard real-time model.
- Perceptual roughness is squared for the microfacet roughness parameter.
- Dielectrics retain diffuse response and achromatic normal-incidence
  reflectance. Conductors have no diffuse lobe and use base color for colored
  specular response.
- Metallic is chiefly an endpoint workflow. Intermediate values are useful for
  transitions such as rust, dirt, or antialiased masks.
- Baseline single-scattering GGX loses energy at high roughness; multiscatter
  compensation is a separate renderer concern.

Primary sections:

- [Specular BRDF](https://google.github.io/filament/main/filament.html#specular-brdf)
- [Diffuse BRDF](https://google.github.io/filament/main/filament.html#diffuse-brdf)
- [Roughness remapping](https://google.github.io/filament/main/filament.html#roughness-remapping-and-clamping)
- [Energy loss](https://google.github.io/filament/main/filament.html#energy-loss-in-specular-reflectance)
- [Material authoring](https://google.github.io/filament/main/filament.html#crafting-physically-based-materials)

## Clearcoat

Filament models clearcoat as a second isotropic dielectric specular lobe over
the base layer. Its documented model uses GGX, Schlick Fresnel with `F0 = 0.04`
for an IOR near 1.5, and a Kelemen visibility approximation. The surface
integration attenuates the base by coat Fresnel before adding the coat lobe:

`(Fd + Fr) * (1 - Fc) + Frc`

Use this as an audit direction, not a pixel-parity requirement. Check local
custom shaders for:

- separate coat factor, roughness, and normal;
- base-layer energy loss rather than an unrelated highlight overlay;
- double-counted direct highlights;
- shadow participation and indirect-specular occlusion;
- premultiplied-alpha interactions;
- source double-sided state and combined base-plus-coat patches.

Primary section: [Clear coat model](https://google.github.io/filament/main/filament.html#clear-coat-model).

## Image-based lighting and exposure

- A visible skybox is not sufficient. Diffuse irradiance and prefiltered
  specular radiance must be evaluated coherently.
- Real-time specular IBL uses prefiltered environment levels plus a DFG/BRDF
  lookup approximation. Roughness selects progressively blurrier radiance.
- Normal maps affect both direct lighting and IBL reflection direction.
- Ambient occlusion applies to indirect lighting; specular occlusion is a
  distinct derived treatment.
- HDR environment files are not necessarily calibrated. Keep exposure and
  environment intensity explicit unless the active renderer proves physical
  unit semantics.

Primary sections:

- [Image-based lights](https://google.github.io/filament/main/filament.html#image-based-lights)
- [Processing light probes](https://google.github.io/filament/main/filament.html#processing-light-probes)
- [IBL evaluation](https://google.github.io/filament/main/filament.html#ibl-evaluation-implementation)
- [Lighting units](https://google.github.io/filament/main/filament.html#units)

## Wrapper implications

Keep base color, metallic, roughness, normal, occlusion, emissive, and ratified
glTF extension fields in the public material vocabulary. Keep D/G/F choices,
roughness clamping, multiscatter compensation, probe convolution, LUTs,
precision, and shader permutations inside the renderer.
