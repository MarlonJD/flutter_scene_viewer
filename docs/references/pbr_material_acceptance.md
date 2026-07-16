# PBR material acceptance

## Decision

Material acceptance uses Khronos glTF as the normative asset contract and the
pinned `flutter_scene` source as proof of renderer behavior. Filament and Brian
Karis provide audit direction only. Frostbite sky and cloud material does not
define glTF material semantics and is not an authority for this acceptance
work.

The fixed wrapper-owned capture configuration is
[`reference_state.json`](../../tools/material_extension_acceptance/fixtures/reference_state.json).
It is evidence configuration, not viewer API, and it does not add renderer
controls.

Plan 015 cross-renderer evidence uses the stricter
[`plan015_controlled_comparison_state.json`](../../tools/material_extension_acceptance/fixtures/plan015_controlled_comparison_state.json).
It freezes canonical per-model camera frames, exact generated HDR bytes,
separate direct/IBL/combined passes, PBR Neutral, sRGB output, and the complete
renderer coordinate mapping. It supplements rather than silently changes the
general `reference_state.json` contract.

## Authority and ownership

| Question | Owner and evidence |
| --- | --- |
| glTF fields, defaults, channels, color spaces, and extension semantics | Khronos [glTF 2.0 Materials](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#materials) and the applicable ratified Khronos extension |
| Viewer configuration, validation, persistence, diagnostics, and evidence labels | `flutter_scene_viewer` public types, adapter, tests, and acceptance fixtures |
| Current BRDF, IBL, exposure, tone mapping, and GPU implementation | `flutter_scene` 0.18.1 pinned at `ccf7372428961ebe0abb053727fe443150547a74`, plus target evidence |
| Real-time shading audit direction | Filament material-system documentation and Karis, *Real Shading in Unreal Engine 4* (2013) |
| Atmosphere and participating-media direction | Frostbite sky/cloud references only; never glTF material definitions |

The pinned source identifies native rendering as Flutter GPU over Impeller and
web rendering as its WebGL2 backend. It implements the built-in procedural
studio environment, neutral environment intensity and exposure defaults, PBR
Neutral tone mapping, GGX/Smith/Schlick direct lighting, and roughness-aware
split-sum IBL. These are renderer facts, not proof that Filament or Unreal
Engine is the backend:

- [`flutter_scene` platform identity](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/README.md)
- [`Scene` environment, exposure, and tone-mapping defaults](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/lib/src/scene.dart)
- [procedural `EnvironmentMap.studio()`](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/lib/src/material/environment.dart)
- [direct, split-sum, and clearcoat lighting](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/shaders/material_lighting.glsl)
- [GGX, correlated Smith visibility, and Schlick Fresnel helpers](https://github.com/MarlonJD/flutter_scene/blob/ccf7372428961ebe0abb053727fe443150547a74/packages/flutter_scene/shaders/pbr.glsl)

Re-check these pinned paths whenever the dependency revision changes. A
reference paper or a matching equation never proves behavior on a target.

Plan 015 evidence uses published `flutter_scene` revision
`ccf7372428961ebe0abb053727fe443150547a74`, which is also the viewer's
immutable Git dependency. That revision is the renderer authority for the
recorded clearcoat captures; Simulator evidence still does not establish
physical-device or cross-platform release capability.

## Fixed capture state

Every material comparison must load `reference_state.json` and keep its
asset-bounds camera fit, front/left/right/back views, studio environment,
environment rotation and intensity, exposure, ambient-occlusion state,
directional key light, and shadow state unchanged.

The fixture freezes wrapper-exposed values. Each evidence record must also
record the `flutter_scene` commit, target, renderer backend, and tone-mapping
mode. For this pinned renderer the unchanged default is
`ToneMappingMode.pbrNeutral`; the adapter does not expose or replace it. If a
capture changes tone mapping or any fixed value, it is a different evidence
state and must not be compared as though it used this fixture.

## Material-phase invariants

The fixed capture state, tone mapping, renderer backend, renderer revision,
viewport, and source asset must remain stable through every phase below. Change
one material variable at a time and retain the baseline capture.

On a multi-primitive real asset, every non-target primitive must remain at the
same baseline optical state while a target primitive is varied. Restore the
target to that baseline before handing the scene to interactive camera review;
never leave different IOR/specular conformance extremes active across adjacent
parts and present the result as a normal product-viewer state.

| Phase | Required directional observation |
| --- | --- |
| Core metallic-roughness baseline | Preserve Khronos factor, texture, channel, and color-space semantics. Dielectrics retain a dielectric specular response and diffuse energy; metals move base color into colored specular response and lose the dielectric diffuse contribution. |
| Dielectric specular and opaque IOR | Increasing dielectric IOR increases normal-incidence Fresnel reflectance according to the Khronos IOR model. Specular controls affect dielectric response; they must not be treated as a metallic substitute or classify opaque IOR as glass. |
| Roughness | Increasing roughness broadens and softens direct highlights and prefiltered environment reflections. Judge lobe shape and reflection detail, not an arbitrary pixel-brightness threshold; renderer energy compensation can change peak and integrated brightness differently. |
| Clearcoat | Increasing clearcoat produces a distinct second dielectric lobe with its own roughness and normal trend while attenuating the visible base by coat Fresnel. A brighter unrelated overlay, lowered base roughness, or boosted environment is not acceptance. |
| Direct and image-based lighting | The material classification, Fresnel, metallic separation, roughness ordering, and clearcoat layering must remain directionally consistent under the analytic key light and the renderer's split-sum IBL. Direct and IBL images are not expected to be numerically identical. |

Transmission, volume, specular, IOR, or clearcoat support still requires a real
renderer path and target evidence. A wrapper parser, fixture, candidate shader,
or Filament/Karis citation cannot promote an unsupported target.

## Evidence interpretation

Store the source screenshot beside any derived crop or metrics and identify the
asset, material phase, camera view, fixture schema version, renderer commit,
backend, platform/device, and artifact path. Label screenshots and metrics as
directional comparisons, never pixel parity with Khronos Sample Viewer,
three.js, Filament, or Unreal Engine.

Metrics may describe trends such as highlight width, reflection movement, or
base-layer attenuation. They must not hide a contradictory source image or use
an unexplained global brightness threshold as a physical-correctness gate.
Cross-renderer differences in environment processing, precision, exposure,
tone mapping, and approximations are expected.

For the Plan 015 controlled state, a displaced analytic-light point is a
camera/light/coordinate failure because roughness filtering is not involved in
its direction. A small displacement or shape change in an IBL softbox is not
equivalent evidence: stock Three.js mixes rough reflection directions toward
the normal and prefilters with PMREM, while flutter_scene uses its independent
reflection-direction and GGX radiance prefilter path. Use the `directOnly`
pass to validate camera and light alignment, a zero-roughness mirror probe to
validate raw environment direction, and the authored `iblOnly`/`combined`
passes to evaluate directional clearcoat behavior. Do not relabel those stock
renderer differences as pixel parity.

GPU and visual rows without an executed target capture remain `not run`.
Package-local extension shaders remain `candidate-only` unless a later release
gate supplies the required evidence; an iOS Simulator result labeled
`verified locally` does not establish physical iOS, Android, or Web behavior.
