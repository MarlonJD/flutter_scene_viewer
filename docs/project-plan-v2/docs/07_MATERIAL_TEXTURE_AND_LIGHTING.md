# 07 — Material, Texture ve Lighting Sistemi

## Temel yaklaşım

`flutter_scene`in `PhysicallyBasedMaterial` ve standard glTF metallic-roughness shader'ı kullanılır. Yeni GLSL/master material yazılmaz.

V1 material yüzeyi:

- base color factor + texture
- metallic factor
- roughness factor
- normal texture
- metallic-roughness texture
- occlusion texture
- emissive factor/texture
- alpha mode
- double-sided

Viewer'ın ana runtime garantisi base-color texture + scalar PBR factor'larıdır. Diğer runtime slots upstream capability doğrulamasına bağlı açılır.

## Patch semantiği

```text
Original material snapshot
       ↓
Patch A: roughness = 0.8
       ↓
Patch B: baseColorTexture = fabric.png
       ↓
Sonuç: roughness 0.8 korunur, texture eklenir
```

Patch yalnızca verilen alanları değiştirir. `resetPartMaterial` original snapshot'a döner.

## Copy-on-write

Material birden fazla primitive tarafından paylaşılırsa ilk mutation'da clone edilir. Aksi halde tek part değişimi başka part'ları etkileyebilir.

## Runtime texture akışı

```text
TextureSource
  ↓
fetch/read encoded bytes
  ↓
size/MIME/signature limit
  ↓
decode to ui.Image (target size where possible)
  ↓
flutter_scene helper → GPU texture
  ↓
assign material slot
  ↓
request frame
```

Viewer düşük seviyeli GPU texture implementation yazmaz; upstream public helper kullanır.

## UV gereksinimi

Bir base-color/normal/MR/occlusion texture'ın anlamlı map edilmesi için uygun UV set gerekir.

V1 politikası:

- UV yoksa otomatik unwrap yok.
- Texture assignment başarısız olur veya typed unsupported result döner.
- Önceki texture/material korunur.
- Diagnostics authoring rehberine yönlendirir.

## Tangent ve normal map

Normal map görüntüsü tangent frame'e bağlıdır. Viewer authored tangent üretmez. Mevcut upstream shader derivative/cotangent frame kullanıyorsa:

- capability note olarak belgelenir
- mirrored UV/seam testleri yapılır
- “glTF tangent fidelity” garantisi verilmez

Bu, V1 blocker değildir; fakat görsel karşılaştırma fixture'ı gerektirir.

## Renk uzayı

- Base-color ve emissive: sRGB kaynak → linear shading
- Normal: linear data
- Metallic-roughness: linear data; glTF kanalları korunur
- Occlusion: linear data

Texture descriptor slot semantiğini taşımalı; aynı bytes yanlış slotta sessizce kullanılmamalı.

## Texture cache

- URL + validators/content hash bazlı key
- in-flight request coalescing
- decoded/GPU byte tahmini
- LRU + ref-count
- aktif material'ın texture'ı evict edilmez
- max dimensions ve memory budget

## Viewer-controlled lighting

PBR materyalin iyi görünmesi için sadece material yeterli değildir. V1, varsayılan bir studio lighting sağlar:

- environment/IBL
- environment intensity
- exposure
- tone mapping
- optional directional key light
- background/skybox

Bu sayede kullanıcı ışık kurmadan makul sonuç alır.

## Full-scene lighting neden ertelendi?

GLB içindeki complete scene'i authored camera/lights ile kullanmak için:

- glTF cameras
- `KHR_lights_punctual`
- point/spot/directional light mapping
- range/intensity units
- shadows
- imported lighting ile environment birleşimi

gereklidir. Bu engine/importer-level iştir ve V1 viewer için gerekli değildir.

## Advanced material extension stratejisi

Parallax, displacement, SSS, clear coat, transmission gibi özellikler core'a eklenmez. Gelecekte opt-in resolver/adapter olabilir:

```dart
materialResolvers: [
  CustomMaterialResolver(...),
]
```

Ancak stable viewer API, upstream/custom shader tiplerine doğrudan bağlanmamalıdır.
