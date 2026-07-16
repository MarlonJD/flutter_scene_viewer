// FSViewerClearcoatExtendedPbr combines the package's bounded core UV0
// transform seam with flutter_scene's renderer-native clearcoat surface and
// lighting contract. The clearcoat BRDF, engine resources, shadows, fog, and
// HDR output remain owned by the pinned flutter_scene shader includes.
//
// The surface structure is adapted from flutter_scene revision
// ccf7372428961ebe0abb053727fe443150547a74 and its Plan 015 clearcoat
// revision. flutter_scene is Copyright (c) 2023 Brandon DeRosier and MIT
// licensed; the complete notice is retained in THIRD_PARTY_NOTICES.md.

#include <material_varyings.glsl>
#include <normals.glsl>
#include <pbr.glsl>
#include <texture.glsl>
#include <material_engine_lighting.glsl>
#include <material_inputs.glsl>
#include <material_lighting.glsl>
#include <lod_fade.glsl>

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;
uniform sampler2D clearcoat_texture;
uniform sampler2D clearcoat_roughness_texture;
uniform sampler2D clearcoat_normal_texture;

uniform ExtendedPbrParams {
  vec4 base_color_uv_offset_scale;
  vec4 base_color_uv_rotation;
  vec4 metallic_roughness_uv_offset_scale;
  vec4 metallic_roughness_uv_rotation;
  vec4 normal_uv_offset_scale;
  vec4 normal_uv_rotation;
  vec4 occlusion_uv_offset_scale;
  vec4 occlusion_uv_rotation;
  vec4 emissive_uv_offset_scale;
  vec4 emissive_uv_rotation;
  vec4 specular_color_factor;
  float specular_factor;
  float material_ior;
  float has_specular_factor_texture;
  float has_specular_color_texture;
}
extended_pbr;

vec2 TransformClearcoatExtendedPbrUv(vec2 uv, vec4 offset_scale,
                                     vec4 rotation) {
  vec2 scaled = uv * offset_scale.zw;
  vec2 rotated = vec2(
      rotation.x * scaled.x - rotation.y * scaled.y,
      rotation.y * scaled.x + rotation.x * scaled.y);
  return offset_scale.xy + rotated;
}

vec3 ClearcoatExtendedPbrGeometricNormal() {
  return gl_FrontFacing ? normalize(v_normal) : -normalize(v_normal);
}

void ClearcoatExtendedPbrSurface(inout MaterialInputs material) {
  vec2 base_color_uv = TransformClearcoatExtendedPbrUv(
      v_texture_coords, extended_pbr.base_color_uv_offset_scale,
      extended_pbr.base_color_uv_rotation);
  vec2 metallic_roughness_uv = TransformClearcoatExtendedPbrUv(
      v_texture_coords, extended_pbr.metallic_roughness_uv_offset_scale,
      extended_pbr.metallic_roughness_uv_rotation);
  vec2 normal_uv = TransformClearcoatExtendedPbrUv(
      v_texture_coords, extended_pbr.normal_uv_offset_scale,
      extended_pbr.normal_uv_rotation);
  vec2 occlusion_uv = TransformClearcoatExtendedPbrUv(
      v_texture_coords, extended_pbr.occlusion_uv_offset_scale,
      extended_pbr.occlusion_uv_rotation);
  vec2 emissive_uv = TransformClearcoatExtendedPbrUv(
      v_texture_coords, extended_pbr.emissive_uv_offset_scale,
      extended_pbr.emissive_uv_rotation);

  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, base_color_uv);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  if (frag_info.alpha_mode == 1.0) {
    if (alpha < frag_info.alpha_cutoff) {
      discard;
    }
    alpha = 1.0;
  }
  material.base_color = vec4(albedo, alpha);

  vec3 geometric_normal = ClearcoatExtendedPbrGeometricNormal();
  material.geometric_normal = geometric_normal;
  vec3 normal = geometric_normal;
  if (frag_info.has_normal_map > 0.5) {
    normal = PerturbNormal(normal_texture, normal, v_viewvector, normal_uv,
                           frag_info.normal_scale);
  }
  material.normal = normal;

  vec4 metallic_roughness =
      texture(metallic_roughness_texture, metallic_roughness_uv);
  material.metallic = clamp(
      metallic_roughness.b * frag_info.metallic_factor, 0.0, 1.0);
  material.roughness = clamp(
      metallic_roughness.g * frag_info.roughness_factor, kMinRoughness, 1.0);

  float occlusion = texture(occlusion_texture, occlusion_uv).r;
  material.occlusion =
      1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;
  material.emissive =
      SRGBToLinear(texture(emissive_texture, emissive_uv).rgb) *
      frag_info.emissive_factor.rgb;

  material.clearcoat = clamp(
      texture(clearcoat_texture, v_texture_coords).r *
          frag_info.clearcoat_params.x,
      0.0, 1.0);
  material.clearcoat_roughness = clamp(
      texture(clearcoat_roughness_texture, v_texture_coords).g *
          frag_info.clearcoat_params.y,
      kMinRoughness, 1.0);
  vec3 clearcoat_normal = geometric_normal;
  if (frag_info.clearcoat_params.z > 0.5) {
    clearcoat_normal = PerturbNormal(
        clearcoat_normal_texture, geometric_normal, v_viewvector,
        v_texture_coords, frag_info.clearcoat_params.w);
  }
  material.clearcoat_normal = clearcoat_normal;

  PrepareMaterial(material);
}

void main() {
  ApplyLodFade(frag_info.fade);
  MaterialInputs material = InitMaterialInputs();
  ClearcoatExtendedPbrSurface(material);
  frag_color = EvaluateLighting(material);
}
