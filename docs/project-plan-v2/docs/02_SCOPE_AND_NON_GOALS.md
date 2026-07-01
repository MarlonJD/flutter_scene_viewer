# 02 — V1 Scope ve Non-Goals

## V1 kapsamı

### Model kaynakları

- `ModelSource.asset`
- `ModelSource.network`
- `ModelSource.bytes`
- Öncelik: tek dosyalı `.glb`
- Multi-file `.gltf`: V1 sonrası veya capability flag

### Model türü

- Statik triangle mesh
- Transform-only parent/dummy/assembly node'ları
- Bir node içinde birden fazla mesh primitive
- Standart glTF metallic-roughness PBR

### Viewer

- Perspective camera
- Orbit, pan, pinch zoom
- Camera auto-fit
- Optional root transform override
- Background color/image/environment
- Viewer-controlled studio lighting
- Picking/raycast
- Part/assembly visibility
- Adaptive/on-demand render

### Runtime materyal

- Base-color factor ve texture
- Metallic factor
- Roughness factor
- Emissive factor
- Original normal, metallic-roughness, occlusion ve emissive slotlarını koruma
- Capability doğrulanırsa runtime normal/MR/occlusion texture ataması
- Alpha mode ve double-sided değerlerini koruma
- Reset part / reset all
- Partial patch merge

### State ve lifecycle

- Serializable viewer state
- Model fingerprint
- Material/texture descriptor'ları
- Camera ve visibility state
- Route reopen restore
- Load cancellation ve source replacement safety
- Model/texture cache

### Diagnostics

- Missing UV
- Unsupported primitive topology
- Unsupported glTF extension/material
- Oversized model/texture
- Duplicate names
- Import/decode/upload errors
- Coordinate/root-transform bilgisi

## V1 dışı

### Geometri üretimi/onarımı

- CAD tessellation
- STEP/IGES/DWG/FBX/OBJ importu
- UV unwrap
- Tangent generation
- Mesh simplification/LOD generation
- Boolean/mesh editing

GLB'nin mevcut triangle/accessor verisi upstream importer'a verilir. Viewer geometri authoring aracı değildir.

### Animation ve deformation

- Skeletal animation
- Interactive bone posing
- Skinning controller
- Morph target/blend shape
- Cloth simulation
- Vertex deformation
- Rigid/node animation bile MVP kabul kriteri değildir; post-MVP olabilir.

### Full-scene import

- Embedded glTF camera seçimi
- `KHR_lights_punctual`
- Çoklu point/spot light sistemi
- Imported post-process/render settings

V1, scene içindeki mesh hierarchy'yi import eder fakat ışık/kamera viewer tarafından kontrol edilir.

### Advanced materials

- Parallax mapping
- Displacement/tessellation shader
- Subsurface scattering
- World-aligned/triplanar texture
- Clear coat/transmission/sheen/specular extension'ları
- Runtime arbitrary shader compilation

### Compression ve ileri streaming

- Draco runtime decode
- meshopt runtime decode
- KTX2/BasisU runtime source
- Progressive mesh streaming
- Virtual texturing

Bunlar önemlidir fakat önce çalışan viewer çıkarılır.

### Platform/engine hedefleri

- VR/AR
- Physics
- Game engine
- Unity/Unreal alternatifi
- Full 3D editor

## V1 capability tablosu

| Özellik | V1 durumu |
|---|---|
| Static GLB | Zorunlu |
| Triangle primitives | Zorunlu |
| Transform-only assembly nodes | Zorunlu |
| Multiple primitives | Zorunlu |
| Duplicate node names | Zorunlu |
| Base-color texture | Zorunlu |
| Metallic/roughness factors | Zorunlu |
| Viewer-controlled IBL | Zorunlu |
| Runtime normal map swap | Capability doğrulamasına bağlı |
| Rigid animation | Post-MVP |
| Skeletal animation | V2+ / talebe bağlı |
| Morph targets | Planlanmıyor, upstream contribution olabilir |
| Embedded lights/cameras | Post-MVP |
| Compression extensions | Post-MVP |
| VR/parallax/displacement | Non-goal |
