# 11 — Test ve Fixture Stratejisi

## Unit testler

- ModelSource equality/fingerprint
- PartAddress serialization/equality
- Node path traversal
- Duplicate name handling
- MaterialPatch merge
- ViewerState versioning
- StateApplyReport
- Render reason state machine
- LRU/ref-count cache
- Session generation/stale operation
- GLB header validation
- Limits

## Widget testler

- Loading/progress/error UI
- Controller attach/detach
- Source change A→B
- Dispose during load
- Render policy state transitions
- Route reopen state restore

GPU-gated testler CI capability'ye göre ayrılmalıdır.

## Integration testler

- Local HTTP server:
  - content-length progress
  - chunked response
  - timeout
  - redirect loop
  - ETag/304
  - truncated bytes
  - 404/500
- Runtime texture swap
- Shared material isolation
- Missing UV behavior
- Camera gesture/picking
- Idle render stop
- Repeated load/unload memory trend

## MVP GLB fixtures

1. `single_cube_pbr.glb`
   - Tek node, tek primitive, base PBR.

2. `assembly_dummy_nodes.glb`
   - Mesh taşımayan root/assembly/sub-assembly node'ları.

3. `duplicate_names.glb`
   - Aynı isimli sibling nodes.

4. `multi_primitive.glb`
   - Tek node içinde iki primitive/material slotu.

5. `shared_material.glb`
   - İki part aynı material instance'ını paylaşır.

6. `pbr_slots.glb`
   - Base-color, normal, metallic-roughness, occlusion, emissive.

7. `missing_uv.glb`
   - Solid color render olabilir; runtime texture assignment hata vermeli.

8. `transparent_double_sided.glb`
   - Alpha mask/blend ve double-sided koruma.

9. `orientation_axes.glb`
   - Canonical +X/+Y/+Z marker ve asymmetric object.

10. `unsupported_topology_or_extension.glb`
    - Typed diagnostics.

11. `large_textures.glb`
    - Limits ve memory tests.

12. `malformed_header.glb`
    - Validation.

MVP fixture listesinde skeletal veya morph model bulunmaz.

## Görsel regression

Aynı fixture için Android/iOS/web screenshot/reference metrics:

- camera pose sabit
- lighting/environment sabit
- exposure/tone mapping sabit
- render scale sabit
- tolerance belgeli

Pixel-perfect yerine perceptual/tolerance-based değerlendirme gerekebilir.

## DCC export testi

Aynı asymmetric model mümkünse:

- Blender
- Maya/3ds Max
- Inventor veya CAD→glTF pipeline

üzerinden export edilip orientation ve hierarchy karşılaştırılır. Viewer DCC heuristic eklemez; exporter uyumsuzluğu diagnostics ile ayrıştırılır.
