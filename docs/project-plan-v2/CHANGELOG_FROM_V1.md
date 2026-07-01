# Project Pack v1 → v2 Değişiklik Özeti

## Kapsam daraltma

- V1 yalnızca statik GLB viewer/configurator olarak tanımlandı.
- Skinning, skeletal animation, morph target ve blend shape V1'den çıkarıldı.
- Rigid node animation post-MVP olarak taşındı.
- Draco, meshopt ve KTX2 runtime compression post-MVP yapıldı.
- Full-scene embedded camera/light importu post-MVP yapıldı.
- Parallax, displacement, SSS, world-aligned texture, VR ve AR non-goal oldu.

## Teknik netleştirme

- GLB'nin zaten tessellated triangle/index/accessor verisi taşıdığı açıkça belirtildi.
- Viewer'ın tessellation, UV unwrap veya geometry repair yapmayacağı kararlaştırıldı.
- Runtime texture için UV yoksa typed diagnostic/error politikası eklendi.
- DCC'ye göre eksen tahmini yerine canonical glTF → engine dönüşümü ve explicit root transform benimsendi.
- Viewer-controlled studio lighting V1 standardı oldu.
- Shared material için copy-on-write ve primitive-level addressing güçlendirildi.

## Ürün konumlandırma

- “Daha hızlı renderer” iddiası kaldırıldı.
- Farklılaştırıcılar: tek Dart scene/material hattı, Flutter-native composition, web için aynı API, assembly-aware addressing ve production lifecycle.
- `interactive_3d` üretim mobil alternatifi olarak kabul edildi; yeni paket başlangıçta experimental/alpha olarak konumlandırıldı.
