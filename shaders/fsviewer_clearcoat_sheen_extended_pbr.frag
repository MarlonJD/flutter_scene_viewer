// FSViewerClearcoatSheenExtendedPbr is an opt-in, package-local candidate for
// clearcoat(sheen(core metallic-roughness + specular + opaque IOR)). It owns
// one bounded 16-sampler evaluation and is not renderer-native or
// production-ready; physical iOS, Android, and Web evidence remains not run.
//
// The sheen equations are re-expressed from the ratified Khronos extension at
// glTF commit 3627d7e096eb95b89417a0968aa32b1f2e8f90cf (README SHA-256
// e5129babb2e7a638aec7e96e7c099d9d3ead0f9bb9b1176f8d5a74111ef278e7).
// Clearcoat composition was checked against the exact viewer pin
// 8e2e2221405b04c517189428d0faf8474cf7f708. The lighting/resource structure
// remains adapted from flutter_scene revision
// ccf7372428961ebe0abb053727fe443150547a74 under its MIT license; see
// THIRD_PARTY_NOTICES.md.

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
uniform sampler2D sheen_color_texture;
uniform sampler2D sheen_roughness_texture;
uniform sampler2D clearcoat_texture;
uniform sampler2D clearcoat_roughness_texture;

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

uniform SheenParams {
  vec4 sheen_color_uv_offset_scale;
  vec4 sheen_color_uv_rotation;
  vec4 sheen_roughness_uv_offset_scale;
  vec4 sheen_roughness_uv_rotation;
  vec4 sheen_color_factor;
  float sheen_roughness_factor;
  float has_sheen_color_texture;
  float has_sheen_roughness_texture;
  float sheen_reserved;
}
sheen_params;

uniform ClearcoatSheenParams {
  vec4 clearcoat_uv_offset_scale;
  vec4 clearcoat_uv_rotation;
  vec4 clearcoat_roughness_uv_offset_scale;
  vec4 clearcoat_roughness_uv_rotation;
}
clearcoat_sheen_params;

struct SheenInputs {
  vec3 color;
  float roughness;
};

vec2 TransformClearcoatSheenExtendedPbrUv(vec2 uv, vec4 offset_scale,
                                           vec4 rotation) {
  vec2 scaled = uv * offset_scale.zw;
  vec2 rotated = vec2(
      rotation.x * scaled.x - rotation.y * scaled.y,
      rotation.y * scaled.x + rotation.x * scaled.y);
  return offset_scale.xy + rotated;
}

vec3 ClearcoatSheenExtendedPbrGeometricNormal() {
  return gl_FrontFacing ? normalize(v_normal) : -normalize(v_normal);
}

void ClearcoatSheenExtendedPbrSurface(inout MaterialInputs material) {
  vec2 base_color_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, extended_pbr.base_color_uv_offset_scale,
      extended_pbr.base_color_uv_rotation);
  vec2 metallic_roughness_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, extended_pbr.metallic_roughness_uv_offset_scale,
      extended_pbr.metallic_roughness_uv_rotation);
  vec2 normal_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, extended_pbr.normal_uv_offset_scale,
      extended_pbr.normal_uv_rotation);
  vec2 occlusion_uv = TransformClearcoatSheenExtendedPbrUv(
      SelectTextureCoordinates(frag_info.texture_coord_sets0.x),
      extended_pbr.occlusion_uv_offset_scale,
      extended_pbr.occlusion_uv_rotation);
  vec2 emissive_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, extended_pbr.emissive_uv_offset_scale,
      extended_pbr.emissive_uv_rotation);
  vec2 clearcoat_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, clearcoat_sheen_params.clearcoat_uv_offset_scale,
      clearcoat_sheen_params.clearcoat_uv_rotation);
  vec2 clearcoat_roughness_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords,
      clearcoat_sheen_params.clearcoat_roughness_uv_offset_scale,
      clearcoat_sheen_params.clearcoat_roughness_uv_rotation);

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

  vec3 geometric_normal = ClearcoatSheenExtendedPbrGeometricNormal();
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
      texture(clearcoat_texture, clearcoat_uv).r *
          frag_info.clearcoat_params.x,
      0.0, 1.0);
  material.clearcoat_roughness = clamp(
      texture(clearcoat_roughness_texture, clearcoat_roughness_uv).g *
          frag_info.clearcoat_params.y,
      kMinRoughness, 1.0);
  material.clearcoat_normal = geometric_normal;

  PrepareMaterial(material);
}

SheenInputs ReadClearcoatSheenInputs() {
  vec2 sheen_color_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, sheen_params.sheen_color_uv_offset_scale,
      sheen_params.sheen_color_uv_rotation);
  vec2 sheen_roughness_uv = TransformClearcoatSheenExtendedPbrUv(
      v_texture_coords, sheen_params.sheen_roughness_uv_offset_scale,
      sheen_params.sheen_roughness_uv_rotation);
  vec3 sampled_color = mix(
      vec3(1.0),
      SRGBToLinear(texture(sheen_color_texture, sheen_color_uv).rgb),
      sheen_params.has_sheen_color_texture);
  float sampled_roughness = mix(
      1.0, texture(sheen_roughness_texture, sheen_roughness_uv).a,
      sheen_params.has_sheen_roughness_texture);
  SheenInputs sheen;
  sheen.color = sheen_params.sheen_color_factor.rgb * sampled_color;
  sheen.roughness =
      sheen_params.sheen_roughness_factor * sampled_roughness;
  return sheen;
}

vec3 ClearcoatSheenFresnel(float cosine, vec3 f0, vec3 f90) {
  float grazing = pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
  return f0 + (f90 - f0) * grazing;
}

vec3 ClearcoatSheenFresnelRoughness(float cosine, vec3 f0, vec3 f90,
                                    float roughness) {
  vec3 rough_f90 = max(f90 * (1.0 - roughness), f0);
  float grazing = pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
  return f0 + (rough_f90 - f0) * grazing;
}

float ClearcoatSheenCharlieDistribution(float n_dot_h,
                                         float sheen_roughness) {
  float alpha_g = max(sheen_roughness, 0.07);
  alpha_g *= alpha_g;
  float inverse_alpha_g = 1.0 / alpha_g;
  float sin2h = max(1.0 - n_dot_h * n_dot_h, 0.0078125);
  return (2.0 + inverse_alpha_g) *
         pow(sin2h, 0.5 * inverse_alpha_g) / (2.0 * kPi);
}

float ClearcoatSheenVisibilityFit(float x, float alpha_g) {
  float one_minus_alpha_sq = (1.0 - alpha_g) * (1.0 - alpha_g);
  float a = mix(21.5473, 25.3245, one_minus_alpha_sq);
  float b = mix(3.82987, 3.32435, one_minus_alpha_sq);
  float c = mix(0.19823, 0.16801, one_minus_alpha_sq);
  float d = mix(-1.97760, -1.27393, one_minus_alpha_sq);
  float e = mix(-4.32054, -4.85967, one_minus_alpha_sq);
  return a / (1.0 + b * pow(x, c)) + d * x + e;
}

float ClearcoatSheenCharlieLambda(float cosine, float alpha_g) {
  float x = clamp(abs(cosine), 1e-4, 1.0);
  return x < 0.5
      ? exp(ClearcoatSheenVisibilityFit(x, alpha_g))
      : exp(2.0 * ClearcoatSheenVisibilityFit(0.5, alpha_g) -
            ClearcoatSheenVisibilityFit(1.0 - x, alpha_g));
}

float ClearcoatSheenCharlieVisibility(float n_dot_v, float n_dot_l,
                                       float sheen_roughness) {
  float alpha_g = max(sheen_roughness, 0.07);
  alpha_g *= alpha_g;
  float safe_n_dot_v = max(n_dot_v, 1e-4);
  float safe_n_dot_l = max(n_dot_l, 1e-4);
  float denominator =
      (1.0 + ClearcoatSheenCharlieLambda(safe_n_dot_v, alpha_g) +
       ClearcoatSheenCharlieLambda(safe_n_dot_l, alpha_g)) *
      (4.0 * safe_n_dot_v * safe_n_dot_l);
  return clamp(1.0 / max(denominator, 1e-6), 0.0, 1.0);
}

float ClearcoatSheenDirectionalAlbedo(float n_dot_x,
                                       float sheen_roughness) {
  vec2 lut_uv = clamp(
      vec2(n_dot_x, max(sheen_roughness, 0.07)), vec2(0.0), vec2(0.99));
  return texture(brdf_lut, lut_uv).b;
}

vec4 EvaluateClearcoatSheenLayeredLighting(MaterialInputs material,
                                            SheenInputs sheen) {
  vec3 albedo = material.base_color.rgb;
  float alpha = material.base_color.a;
  vec3 normal = material.normal;
  vec3 geometric_normal = material.geometric_normal;
  float metallic = material.metallic;
  float roughness = material.roughness;
  float sheen_roughness = clamp(sheen.roughness, 0.0, 1.0);
  float max_sheen_color = max(max(sheen.color.r, sheen.color.g), sheen.color.b);
  float clearcoat = clamp(material.clearcoat, 0.0, 1.0);
  float clearcoat_roughness =
      clamp(material.clearcoat_roughness, kMinRoughness, 1.0);
  vec3 clearcoat_normal = normalize(material.clearcoat_normal);

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

  float specular_weight = clamp(extended_pbr.specular_factor, 0.0, 1.0);
  vec3 specular_color = extended_pbr.specular_color_factor.rgb;
  float ior_ratio =
      (extended_pbr.material_ior - 1.0) / (extended_pbr.material_ior + 1.0);
  float ordinary_ior_f0 = ior_ratio * ior_ratio;
  vec3 dielectric_f0 = min(vec3(ordinary_ior_f0) * specular_color, vec3(1.0)) *
                       specular_weight;
  vec3 dielectric_f90 = vec3(specular_weight);
  if (extended_pbr.material_ior == 0.0) {
    dielectric_f0 = vec3(1.0);
    dielectric_f90 = vec3(1.0);
  }
  vec3 reflectance = mix(dielectric_f0, albedo, metallic);
  vec3 grazing_reflectance = mix(dielectric_f90, vec3(1.0), metallic);

  vec3 camera_normal = normalize(v_viewvector);
  float n_dot_v = max(dot(normal, camera_normal), 0.0);
  float n_dot_v_energy = max(dot(geometric_normal, camera_normal), 0.0);
  float clearcoat_n_dot_v = max(dot(clearcoat_normal, camera_normal), 0.0);
  float clearcoat_view_fresnel =
      clearcoat *
      FresnelSchlickRoughness(clearcoat_n_dot_v, vec3(0.04),
                              clearcoat_roughness)
          .r;
  float base_layer_view_attenuation = 1.0 - clearcoat_view_fresnel;
  vec3 reflection_normal = reflect(-camera_normal, normal);
  vec3 k_S = ClearcoatSheenFresnelRoughness(
      n_dot_v_energy, reflectance, grazing_reflectance, roughness);

  mat3 environment_transform = mat3(frag_info.environment_transform);
  vec3 env_normal = environment_transform * normal;
  vec3 env_reflection = environment_transform * reflection_normal;
  vec3 clearcoat_reflection =
      environment_transform * reflect(-camera_normal, clearcoat_normal);
  vec3 irradiance =
      max(EvaluateDiffuseSH(sh_coefficients, env_normal), vec3(0.0));
  vec3 prefiltered_color = SamplePrimaryRadiance(env_reflection, roughness);
  // candidate-only approximation: GGX-prefiltered radiance is reused for the
  // sheen lobe while Charlie directional albedo comes from package LUT B.
  vec3 sheen_prefiltered_color =
      SamplePrimaryRadiance(env_reflection, max(sheen_roughness, 0.07));
  vec3 clearcoat_prefiltered =
      SamplePrimaryRadiance(clearcoat_reflection, clearcoat_roughness);
  float env_blend = frag_info.radiance_blend.x;
  if (env_blend > 0.0) {
    vec3 irradiance_b =
        max(EvaluateDiffuseSH(sh_coefficients_b, env_normal), vec3(0.0));
    vec3 prefiltered_b = SampleSecondaryRadiance(env_reflection, roughness);
    vec3 sheen_prefiltered_b = SampleSecondaryRadiance(
        env_reflection, max(sheen_roughness, 0.07));
    vec3 clearcoat_prefiltered_b =
        SampleSecondaryRadiance(clearcoat_reflection, clearcoat_roughness);
    irradiance = mix(irradiance, irradiance_b, env_blend);
    prefiltered_color = mix(prefiltered_color, prefiltered_b, env_blend);
    sheen_prefiltered_color =
        mix(sheen_prefiltered_color, sheen_prefiltered_b, env_blend);
    clearcoat_prefiltered =
        mix(clearcoat_prefiltered, clearcoat_prefiltered_b, env_blend);
  }
  irradiance *= frag_info.environment_intensity;
  prefiltered_color *= frag_info.environment_intensity;
  sheen_prefiltered_color *= frag_info.environment_intensity;
  clearcoat_prefiltered *= frag_info.environment_intensity;

  vec2 f_ab = texture(
                  brdf_lut,
                  clamp(vec2(n_dot_v_energy, roughness), 0.0, 0.99))
                  .rg;
  vec2 clearcoat_f_ab =
      texture(brdf_lut,
              clamp(vec2(clearcoat_n_dot_v, clearcoat_roughness), 0.0, 0.99))
          .rg;
  vec3 FssEss = k_S * f_ab.x + grazing_reflectance * f_ab.y;
  float Ems = 1.0 - (f_ab.x + f_ab.y);
  vec3 F_avg = reflectance + (grazing_reflectance - reflectance) / 21.0;
  vec3 FmsEms = Ems * FssEss * F_avg /
                max(vec3(1.0) - F_avg * Ems, vec3(1e-5));
  vec3 diffuse_color = albedo * (1.0 - metallic);
  vec3 k_D = diffuse_color * max(vec3(1.0) - FssEss + FmsEms, vec3(0.0));
  vec3 indirect_specular = FssEss * prefiltered_color;
  vec3 indirect_diffuse = (FmsEms + k_D) * irradiance;
  float specular_occlusion = frag_info.ssao_params.y > 0.5
      ? ComputeSpecularOcclusion(n_dot_v, occlusion, roughness)
      : occlusion;
  float sheen_energy_v =
      ClearcoatSheenDirectionalAlbedo(n_dot_v, sheen_roughness);
  float indirect_sheen_attenuation =
      clamp(1.0 - max_sheen_color * sheen_energy_v, 0.0, 1.0);
  vec3 base_ambient =
      indirect_diffuse * occlusion + indirect_specular * specular_occlusion;
  vec3 indirect_sheen =
      sheen.color * sheen_energy_v * sheen_prefiltered_color *
      specular_occlusion;
  vec3 clearcoat_indirect_specular =
      clearcoat * (vec3(0.04) * clearcoat_f_ab.x + clearcoat_f_ab.y) *
      clearcoat_prefiltered;
  float clearcoat_specular_occlusion = frag_info.ssao_params.y > 0.5
      ? ComputeSpecularOcclusion(clearcoat_n_dot_v, occlusion,
                                 clearcoat_roughness)
      : occlusion;

  float n_dot_l = 0.0;
  float geometric_n_dot_l = 0.0;
  vec3 light_vector = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    light_vector = -normalize(frag_info.directional_light_direction.xyz);
    n_dot_l = dot(normal, light_vector);
    geometric_n_dot_l = dot(geometric_normal, light_vector);
  }
  float facing = clamp(geometric_n_dot_l / 0.15, 0.0, 1.0);
  float shadow =
      (frag_info.has_directional_light > 0.5 && frag_info.casts_shadow > 0.5 &&
       facing > 0.0)
          ? SampleShadow(v_position, geometric_normal)
          : 1.0;
  float sun_visibility = facing * shadow;
  float ambient_shadow =
      mix(1.0, sun_visibility, frag_info.radiance_blend.y);
  vec3 ambient =
      ((base_ambient * indirect_sheen_attenuation + indirect_sheen) *
          base_layer_view_attenuation +
      clearcoat_indirect_specular * clearcoat_specular_occlusion) *
      ambient_shadow;

  vec3 direct = vec3(0.0);
  vec3 direct_clearcoat = vec3(0.0);
  float clearcoat_n_dot_l = max(dot(clearcoat_normal, light_vector), 0.0);
  if (frag_info.has_directional_light > 0.5 &&
      (n_dot_l > 0.0 || clearcoat_n_dot_l > 0.0)) {
    vec3 half_vector = normalize(light_vector + camera_normal);
    float v_dot_h = max(dot(half_vector, camera_normal), 0.0);
    float clearcoat_direct_fresnel =
        clearcoat * FresnelSchlick(v_dot_h, vec3(0.04)).r;
    if (n_dot_l > 0.0) {
      float n_dot_v_safe = max(n_dot_v, 1e-4);
      float distribution = DistributionGGX(normal, half_vector, roughness);
      float visibility =
          VisibilitySmithGGXCorrelated(n_dot_v_safe, n_dot_l, roughness);
      vec3 specular_fresnel = ClearcoatSheenFresnel(
          v_dot_h, reflectance, grazing_reflectance);
      vec3 specular = distribution * visibility * specular_fresnel;
      float diffuse_weight =
          1.0 - max(max(specular_fresnel.r, specular_fresnel.g),
                    specular_fresnel.b);
      vec3 diffuse = vec3(diffuse_weight) * (1.0 - metallic) * albedo *
                     (1.0 / kPi);
      vec3 base_direct = diffuse + specular;
      float n_dot_h = max(dot(normal, half_vector), 0.0);
      float sheen_distribution =
          ClearcoatSheenCharlieDistribution(n_dot_h, sheen_roughness);
      float sheen_visibility = ClearcoatSheenCharlieVisibility(
          n_dot_v_safe, n_dot_l, sheen_roughness);
      vec3 direct_sheen =
          sheen.color * sheen_distribution * sheen_visibility;
      float sheen_energy_l = ClearcoatSheenDirectionalAlbedo(
          max(n_dot_l, 0.0), sheen_roughness);
      float direct_sheen_attenuation = min(
          indirect_sheen_attenuation,
          clamp(1.0 - max_sheen_color * sheen_energy_l, 0.0, 1.0));
      direct =
          (base_direct * direct_sheen_attenuation + direct_sheen) *
        (1.0 - clearcoat_direct_fresnel) *
        frag_info.directional_light_color.rgb * n_dot_l * shadow;
    }
    if (clearcoat_n_dot_l > 0.0 && clearcoat > 0.0) {
      float clearcoat_distribution = DistributionGGX(
          clearcoat_normal, half_vector, clearcoat_roughness);
      float clearcoat_visibility = VisibilitySmithGGXCorrelated(
          max(clearcoat_n_dot_v, 1e-4), clearcoat_n_dot_l,
          clearcoat_roughness);
      vec3 clearcoat_specular =
          vec3(clearcoat_distribution * clearcoat_visibility *
               clearcoat_direct_fresnel);
      direct_clearcoat = clearcoat_specular *
                         frag_info.directional_light_color.rgb *
                         clearcoat_n_dot_l * shadow;
      direct += direct_clearcoat;
    }
  }

  vec3 emissive = material.emissive * base_layer_view_attenuation;
  vec3 out_color = ambient + direct + emissive;
  vec3 sky_fog_color = fog.color.rgb;
  if (fog.params0.y > 0.5 && fog.params0.w > 0.0) {
    const float kSkyFogRoughness = 0.0;
    vec3 sky_dir = environment_transform * normalize(-v_viewvector);
    sky_fog_color = SamplePrimaryRadiance(sky_dir, kSkyFogRoughness);
    if (env_blend > 0.0) {
      sky_fog_color = mix(
          sky_fog_color,
          SampleSecondaryRadiance(sky_dir, kSkyFogRoughness),
          env_blend);
    }
    sky_fog_color *= frag_info.environment_intensity;
  }
  return ApplyFog(vec4(out_color, 1.0) * alpha, sky_fog_color);
}

void main() {
  ApplyLodFade(frag_info.fade);
  MaterialInputs material = InitMaterialInputs();
  ClearcoatSheenExtendedPbrSurface(material);
  SheenInputs sheen = ReadClearcoatSheenInputs();
  frag_color = EvaluateClearcoatSheenLayeredLighting(material, sheen);
}
