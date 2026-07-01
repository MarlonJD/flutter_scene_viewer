# 17 — Future Roadmap ve Extension Sınırları

Bu liste taahhüt değildir. Kullanıcı talebi, upstream capability ve benchmark sonuçlarına göre sıralanır.

## Mantıklı post-MVP özellikler

### Rigid/node animation

- Kapı açılması
- Exploded view
- Parça rotasyonu
- Transform animation clip playback

Skinning gerektirmez ve product viewer'a doğal uzantıdır.

### Multi-file glTF

- Relative URI resolver
- External `.bin` ve image files
- Network base URL/CORS/cache handling

### Embedded cameras/lights

- glTF cameras
- `KHR_lights_punctual`
- SceneImportPolicy
- Imported vs viewer-controlled lighting merge

### Compression

- Draco
- meshopt
- KTX2/BasisU

Önce kullanım/uyumluluk verisi ölçülür; upstream/third-party decoder stratejisi belirlenir.

### Skeletal animation

Yalnız gerçek use case varsa:

- medical pose
- avatar/clothing pose
- character preview

Viewer v1'in parçası değildir. Interactive bone posing ayrı ve büyük bir ürün alanıdır.

### Advanced materials

Core material sonsuz büyütülmez. Resolver/plugin modeliyle:

- clear coat
- transmission
- sheen
- SSS
- parallax
- triplanar/world-aligned

opt-in eklenebilir.

## Planlanmayanlar

- Morph target/blend shape core roadmap
- VR framework
- Physics/gameplay
- Terrain engine
- CAD tessellator
- Unity/Unreal replacement

Bu ihtiyaçlar ortaya çıkarsa ayrı paket veya uygun motor tavsiye edilir.
