# Material Extension Shader Reference

This note records the public glTF/PBR material concepts used by the
package-local material extension shaders. The implementation is repo-owned
shader code built on public `flutter_scene` custom material APIs.

## Glass / Transmission

`MaterialPatch.transmission` maps to the glTF transmission concept: `0.0`
keeps the material close to its base color, while `1.0` lets the material
visibly sample the scene behind it.

The local backend uses a bounded screen-space background `RenderTexture`
rather than full multi-bounce refraction. `MaterialPatch.ior` changes the
screen-space sample offset magnitude and the view-dependent Fresnel split
between surface reflection and transmitted background energy. The shader
derives normal-incidence reflectance from IOR with `((ior - 1) / (ior + 1))^2`
and reduces transmitted energy by the Fresnel term instead of letting grazing
angles look like plain alpha.

`MaterialPatch.thickness`, `MaterialPatch.attenuationColor`, and
`MaterialPatch.attenuationDistance` control local absorption with the glTF
attenuation-color-at-distance form: the sampled background is multiplied by
`attenuationColor^(thickness / attenuationDistance)` when an attenuation
distance is provided. `MaterialPatch.roughness` softens the background
contribution by mixing it back toward the base material.
`MaterialPatch.normalTexture` and `MaterialPatch.normalScale` perturb the
offset direction when a normal texture is provided. The unlit transmission
shader outputs premultiplied RGB for its alpha-blended glass pass, matching the
transparent-surface convention used by common renderer shader APIs.

Known glass limits are explicit: no nested glass correctness, caustics,
path-traced transmission, multiple refraction bounces, or order-independent
transparency claim. The current node-layer background capture also requires
glass geometry to be authored on separate nodes from opaque geometry.

## Clearcoat

`MaterialPatch.clearcoat` maps to a separate coating lobe layered over the
base metallic-roughness material. The local clearcoat shader does not lower
the base roughness to fake a glossy finish. Instead, the backend keeps the
source primitive's base material in place and draws a translucent clearcoat
overlay primitive that shares the source geometry. The overlay shader emits a
bounded coating contribution through `MaterialInputs.emissive` and alpha
blending, so real GLB base color, metallic-roughness, normal, occlusion, and
emissive detail remain owned by the original material.
The overlay also computes a clearcoat Fresnel term and uses it to attenuate
base-layer energy through translucent black alpha before adding the coating
lobe. This follows the common two-layer clearcoat model direction: add a
second specular lobe while reducing the base layer by the coat Fresnel instead
of simply stacking an unrelated highlight on top.

`MaterialPatch.clearcoatRoughness` controls only the coating lobe width and
peak. Higher coating roughness broadens/reduces the added lobe without changing
the base material roughness. `MaterialPatch.clearcoatNormalTexture` and
`MaterialPatch.clearcoatNormalScale` perturb the coating lobe independently
from the base normal when UV0 texture coordinates are available. When no
clearcoat normal texture is bound, the local shader uses the base material
normal for the coating lobe instead of recomputing from the geometric normal.

The clearcoat contribution is a bounded analytic lobe in the package-local
shader. It samples the engine prefiltered radiance, BRDF LUT, directional
light, and shadow state, then routes the coating contribution through
`material.emissive` in the overlay material. That routing is a local
approximation used so the engine lit material path still owns lighting,
tone mapping, and premultiplied alpha output. Task 011 visual evidence checks
trends rather than pixel parity: factor increases highlight strength, rougher
clearcoat does not exceed the smooth peak, a clearcoat texture changes the
frame, and a clearcoat normal map moves the coating highlight.
Real textured GLB evidence is stricter than the synthetic matrix. The
DamagedHelmet manual-clearcoat iOS Simulator run remains candidate-only because
the older replacement path looked overly stylized/striped on complex source
materials. A follow-up ToyCar iOS Simulator run verifies that the overlay path
preserves the authored source material while adding visible glass and
clearcoat effects. Task 012 accepts this repo-owned custom shader path as the
production route for the verified iOS Simulator scope after shader preflight
and acceptance metrics pass.

Production clearcoat uses `flutter_scene` `.fmat` metadata through
`PreprocessedMaterial`. A lit `.fmat` must use that material wrapper so the
engine lighting uniform block and image-based lighting samplers are bound.
`ShaderMaterial` remains valid for injected CPU tests and custom unlit shader
paths, but it is not the production wrapper for lit clearcoat.

## Source And License Boundaries

External renderer source is not copied into the package-local Dart or shader
implementation. Filament and SceneKit were used as public material-model
references only: Filament for IOR/Fresnel energy separation and transparent
surface blending direction, and SceneKit for the public transparent-surface,
view-vector, and Fresnel shader-surface concepts available in its SDK headers.
SceneKit does not expose a `KHR_materials_transmission` equivalent field in the
public material surface, so it is not treated as a native transmission backend.
three.js is used only as a visual reference-renderer dependency for trend
comparison against the shared fixture GLB. If reference harness code copies any
third-party source in the future, its license notice must be carried with that
copied code.
