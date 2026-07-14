// FSViewerExtendedPbr is a bounded material-scoped extension of the pinned
// flutter_scene metallic-roughness fragment contract. Khronos glTF extension
// specifications are normative for fields, channels, transforms, and color
// spaces. The flutter_scene framework remains the source of engine uniforms,
// varyings, normal preparation, IBL resources, shadows, fog, and output shape.
//
// The lighting/resource structure is adapted from flutter_scene revision
// cd6760912fa38beb55f63e388655a1aeabd32fe4, principally
// material_lighting.glsl and flutter_scene_standard.frag. flutter_scene is
// Copyright (c) 2023 Brandon DeRosier and MIT licensed; the complete notice is
// retained in THIRD_PARTY_NOTICES.md. Khronos equations are re-expressed from
// the extension specifications rather than copied from an implementation.

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
uniform sampler2D specular_factor_texture;
uniform sampler2D specular_color_texture;

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

vec2 TransformExtendedPbrUv(vec2 uv, vec4 offset_scale, vec4 rotation) {
  vec2 scaled = uv * offset_scale.zw;
  vec2 rotated = vec2(
      rotation.x * scaled.x - rotation.y * scaled.y,
      rotation.y * scaled.x + rotation.x * scaled.y);
  return offset_scale.xy + rotated;
}

void ExtendedPbrSurface(inout MaterialInputs material) {
  vec2 base_color_uv = TransformExtendedPbrUv(
      v_texture_coords, extended_pbr.base_color_uv_offset_scale,
      extended_pbr.base_color_uv_rotation);
  vec2 metallic_roughness_uv = TransformExtendedPbrUv(
      v_texture_coords, extended_pbr.metallic_roughness_uv_offset_scale,
      extended_pbr.metallic_roughness_uv_rotation);
  vec2 normal_uv = TransformExtendedPbrUv(
      v_texture_coords, extended_pbr.normal_uv_offset_scale,
      extended_pbr.normal_uv_rotation);
  vec2 occlusion_uv = TransformExtendedPbrUv(
      v_texture_coords, extended_pbr.occlusion_uv_offset_scale,
      extended_pbr.occlusion_uv_rotation);
  vec2 emissive_uv = TransformExtendedPbrUv(
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

  vec3 normal = normalize(v_normal);
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
  PrepareMaterial(material);
}

vec3 ExtendedPbrFresnel(float cosine, vec3 f0, vec3 f90) {
  float grazing = pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
  return f0 + (f90 - f0) * grazing;
}

vec3 ExtendedPbrFresnelRoughness(float cosine, vec3 f0, vec3 f90,
                                 float roughness) {
  vec3 rough_f90 = max(f90 * (1.0 - roughness), f0);
  float grazing = pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
  return f0 + (rough_f90 - f0) * grazing;
}

// This function follows the pinned flutter_scene lighting structure so routed
// materials keep the same environment, shadow, fog, and HDR output resources.
// The changed seam is limited to Khronos dielectric F0/F90, direct energy
// sharing, and their propagation through the existing split-sum IBL model.
vec4 EvaluateExtendedPbrLighting(MaterialInputs material) {
  vec3 albedo = material.base_color.rgb;
  float alpha = material.base_color.a;
  vec3 normal = material.normal;
  float metallic = material.metallic;
  float roughness = material.roughness;

  if (frag_info.specular_aa_variance > 0.0) {
    vec3 d_normal_x = dFdx(normal);
    vec3 d_normal_y = dFdy(normal);
    float variance = frag_info.specular_aa_variance *
                     (dot(d_normal_x, d_normal_x) +
                      dot(d_normal_y, d_normal_y));
    float kernel = min(2.0 * variance, frag_info.specular_aa_threshold);
    float widened = clamp(
        roughness * roughness * roughness * roughness + kernel, 0.0, 1.0);
    roughness = clamp(sqrt(sqrt(widened)), kMinRoughness, 1.0);
  }

  float occlusion = material.occlusion;
  if (frag_info.ssao_params.x > 0.5) {
    vec2 screen_uv = gl_FragCoord.xy * frag_info.ssao_params.zw;
    occlusion *= texture(ssao_texture, screen_uv).r;
  }

  float sampled_specular_factor = mix(
      1.0, texture(specular_factor_texture, v_texture_coords).a,
      extended_pbr.has_specular_factor_texture);
  vec3 sampled_specular_color = mix(
      vec3(1.0),
      SRGBToLinear(texture(specular_color_texture, v_texture_coords).rgb),
      extended_pbr.has_specular_color_texture);
  float specular_weight =
      clamp(extended_pbr.specular_factor * sampled_specular_factor, 0.0, 1.0);
  vec3 specular_color =
      extended_pbr.specular_color_factor.rgb * sampled_specular_color;

  float ior_ratio =
      (extended_pbr.material_ior - 1.0) / (extended_pbr.material_ior + 1.0);
  float ordinary_ior_f0 = ior_ratio * ior_ratio;
  vec3 dielectric_f0 = min(vec3(ordinary_ior_f0) * specular_color, vec3(1.0)) *
                       specular_weight;
  vec3 dielectric_f90 = vec3(specular_weight);
  if (extended_pbr.material_ior == 0.0) {
    // KHR_materials_ior compatibility mode represents infinite IOR. Fresnel
    // is one at every angle; it is not the result of clamping IOR to one.
    dielectric_f0 = vec3(1.0);
    dielectric_f90 = vec3(1.0);
  }
  vec3 reflectance = mix(dielectric_f0, albedo, metallic);
  vec3 grazing_reflectance =
      mix(dielectric_f90, vec3(1.0), metallic);

  vec3 camera_normal = normalize(v_viewvector);
  float n_dot_v = max(dot(normal, camera_normal), 0.0);
  float n_dot_v_energy = max(dot(GetWorldNormal(), camera_normal), 0.0);
  vec3 reflection_normal = reflect(-camera_normal, normal);
  vec3 k_S = ExtendedPbrFresnelRoughness(
      n_dot_v_energy, reflectance, grazing_reflectance, roughness);

  mat3 environment_transform = mat3(frag_info.environment_transform);
  vec3 env_normal = environment_transform * normal;
  vec3 env_reflection = environment_transform * reflection_normal;
  vec3 irradiance =
      max(EvaluateDiffuseSH(sh_coefficients, env_normal), vec3(0.0));
  vec3 prefiltered_color =
      SampleRadianceEnv(prefiltered_radiance, prefiltered_radiance_cube,
                        env_reflection, roughness);
  float env_blend = frag_info.radiance_blend.x;
  if (env_blend > 0.0) {
    vec3 irradiance_b =
        max(EvaluateDiffuseSH(sh_coefficients_b, env_normal), vec3(0.0));
    vec3 prefiltered_b =
        SampleRadianceEnv(prefiltered_radiance_b, prefiltered_radiance_cube_b,
                          env_reflection, roughness);
    irradiance = mix(irradiance, irradiance_b, env_blend);
    prefiltered_color = mix(prefiltered_color, prefiltered_b, env_blend);
  }
  irradiance *= frag_info.environment_intensity;
  prefiltered_color *= frag_info.environment_intensity;

  vec2 f_ab = texture(
                  brdf_lut,
                  clamp(vec2(n_dot_v_energy, roughness), 0.0, 0.99))
                  .rg;
  vec3 FssEss = k_S * f_ab.x + grazing_reflectance * f_ab.y;
  float Ems = 1.0 - (f_ab.x + f_ab.y);
  vec3 F_avg =
      reflectance + (grazing_reflectance - reflectance) / 21.0;
  vec3 FmsEms = Ems * FssEss * F_avg /
                max(vec3(1.0) - F_avg * Ems, vec3(1e-5));
  vec3 diffuse_color = albedo * (1.0 - metallic);
  vec3 k_D = diffuse_color * max(vec3(1.0) - FssEss + FmsEms, vec3(0.0));
  vec3 indirect_specular = FssEss * prefiltered_color;
  vec3 indirect_diffuse = (FmsEms + k_D) * irradiance;
  float specular_occlusion = frag_info.ssao_params.y > 0.5
      ? ComputeSpecularOcclusion(n_dot_v, occlusion, roughness)
      : occlusion;

  float n_dot_l = 0.0;
  float geometric_n_dot_l = 0.0;
  vec3 light_vector = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    light_vector = -normalize(frag_info.directional_light_direction.xyz);
    n_dot_l = dot(normal, light_vector);
    geometric_n_dot_l = dot(GetWorldNormal(), light_vector);
  }
  float facing = clamp(geometric_n_dot_l / 0.15, 0.0, 1.0);
  float shadow =
      (frag_info.has_directional_light > 0.5 && frag_info.casts_shadow > 0.5 &&
       facing > 0.0)
          ? SampleShadow(v_position, GetWorldNormal())
          : 1.0;
  float sun_visibility = facing * shadow;
  float ambient_shadow =
      mix(1.0, sun_visibility, frag_info.radiance_blend.y);
  vec3 ambient =
      (indirect_diffuse * occlusion + indirect_specular * specular_occlusion) *
      ambient_shadow;

  vec3 direct = vec3(0.0);
  if (frag_info.has_directional_light > 0.5 && n_dot_l > 0.0) {
    vec3 half_vector = normalize(light_vector + camera_normal);
    float n_dot_v_safe = max(n_dot_v, 1e-4);
    float distribution = DistributionGGX(normal, half_vector, roughness);
    float visibility =
        VisibilitySmithGGXCorrelated(n_dot_v_safe, n_dot_l, roughness);
    vec3 specular_fresnel = ExtendedPbrFresnel(
        max(dot(half_vector, camera_normal), 0.0), reflectance,
        grazing_reflectance);
    vec3 specular = distribution * visibility * specular_fresnel;
    float diffuse_weight =
        1.0 - max(max(specular_fresnel.r, specular_fresnel.g),
                  specular_fresnel.b);
    vec3 diffuse = vec3(diffuse_weight) * (1.0 - metallic) * albedo *
                   (1.0 / kPi);
    direct = (diffuse + specular) * frag_info.directional_light_color.rgb *
             n_dot_l * shadow;
  }

  vec3 out_color = ambient + direct + material.emissive;
  vec3 sky_fog_color = fog.color.rgb;
  if (fog.params0.y > 0.5 && fog.params0.w > 0.0) {
    const float kSkyFogRoughness = 0.0;
    vec3 sky_dir = environment_transform * normalize(-v_viewvector);
    sky_fog_color = SampleRadianceEnv(
        prefiltered_radiance, prefiltered_radiance_cube, sky_dir,
        kSkyFogRoughness);
    if (env_blend > 0.0) {
      sky_fog_color = mix(
          sky_fog_color,
          SampleRadianceEnv(prefiltered_radiance_b,
                            prefiltered_radiance_cube_b, sky_dir,
                            kSkyFogRoughness),
          env_blend);
    }
    sky_fog_color *= frag_info.environment_intensity;
  }
  return ApplyFog(vec4(out_color, 1.0) * alpha, sky_fog_color);
}

void main() {
  ApplyLodFade(frag_info.fade);
  MaterialInputs material = InitMaterialInputs();
  ExtendedPbrSurface(material);
  frag_color = EvaluateExtendedPbrLighting(material);
}
