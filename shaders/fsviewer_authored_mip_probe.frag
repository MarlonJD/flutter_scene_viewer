// Deterministic target-evidence probe for the repo-local authored-mip upload
// seam. This is not a product material: it samples three exact LODs so target
// tests can distinguish authored levels without relying on derivatives.

#include <material_varyings.glsl>

uniform sampler2D authored_mip_texture;

void main() {
  float lod = 0.0;
  if (v_texture_coords.x >= (2.0 / 3.0)) {
    lod = 2.0;
  } else if (v_texture_coords.x >= (1.0 / 3.0)) {
    lod = 1.0;
  }
  frag_color = textureLod(authored_mip_texture, v_texture_coords, lod);
}
