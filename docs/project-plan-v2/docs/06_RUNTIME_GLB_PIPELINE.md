# 06 — Runtime Network GLB Pipeline

## Pipeline

```text
ModelSource
  ↓
Fetch/read bytes
  ↓
Limits + GLB header validation
  ↓
Node.fromGlbBytes(bytes)
  ↓
flutter_scene imports scene/material/textures/GPU resources
  ↓
PartRegistry builds assembly/part index
  ↓
Diagnostics and capabilities
  ↓
Apply root transform + viewer lighting
  ↓
Camera fit
  ↓
Apply initial ViewerState
  ↓
First requested frame
```

## 1. Network yükleme

Network loader:

- streamed response kullanmalı
- byte progress üretmeli
- timeout ve redirect limitine sahip olmalı
- max byte limitini Content-Length varsa önceden, yoksa stream sırasında uygulamalı
- cancellation token/session generation kontrol etmeli
- auth header'larını loglamamalı
- ETag/Last-Modified metadata'sını cache için saklamalı

## 2. GLB doğrulama

Import öncesi minimum doğrulama:

- magic `glTF`
- supported version
- declared length ve actual byte length
- minimum header/chunk bounds
- configurable max model size

Bu validation tam glTF validator değildir; bozuk ve aşırı input'u erken reddeder.

## 3. Import

`Node.fromGlbBytes()` runtime importer olarak kullanılır. Viewer şunları yapmaz:

- triangle topology hesaplama
- tessellation
- UV unwrap
- DCC format conversion

GLB'nin accessor/index/attribute verisi upstream importer tarafından geometry buffer'a paketlenir.

## 4. Texture import

Embedded GLB images upstream tarafından decode edilip GPU texture'a çevrilir. Viewer yükleme aşamasında yalnızca:

- limits/diagnostics
- cache policy
- error mapping

sorumluluğu alır.

## 5. Part registry

Import edilen tree bir kez dolaşılır:

- transform-only nodes assembly olarak kaydedilir
- mesh node'ları kaydedilir
- her primitive ayrı PartAddress alır
- duplicate names kaydedilir
- shared material usage map oluşturulur
- bounds ve material capability çıkarılır

## 6. Attribute diagnostics

V1 viewer geometri repair yapmaz.

- Base-color texture kullanacak primitive için UV0 yoksa `MissingUvSet`.
- Authored normal/tangent varlığı model diagnostics'e yazılır.
- Upstream fallback normal veya derivative tangent behavior'ı capability notes'ta belirtilir.
- Triangle dışı topology desteklenmiyorsa typed issue/error.

## 7. Coordinate sistemi

Kaynak programın Blender, Maya, Inventor veya başka bir DCC olması viewer tarafından tahmin edilmez. Exporter'ın canonical glTF koordinatlarına çevirdiği varsayılır.

- Upstream glTF → flutter_scene dönüşümü kullanılır.
- Viewer ek bir otomatik axis heuristic uygulamaz.
- Kullanıcı için explicit `rootTransform` escape hatch bulunur.
- Testler farklı DCC export'larıyla yapılır.

## 8. Viewer lighting ve camera

Model importundan sonra:

- ViewerLighting uygulanır.
- Scene environment/IBL hazır edilir.
- Model combined bounds hesaplanır.
- Camera target merkez, distance FOV ve extent'e göre belirlenir.
- Invalid/empty bounds için fallback kullanılır.

## 9. Source replacement

A modeli yüklenirken B kaynağı atanırsa:

- generation id artırılır
- A'nın network/import sonrası sonuçları stale kabul edilir
- A scene'e attach edilmez
- A'nın sahip olunan kaynakları güvenli biçimde bırakılır
- B tamamlanınca atomik swap yapılır

Eski model, yeni model first-frame hazır olmadan kaldırılacaksa black-frame UX ölçülmeli; loading overlay kullanılabilir.

## 10. Main isolate riski

Runtime importer parse, image decode ve GPU upload içerir. GPU objeleri isolate'lar arasında taşınamaz. Bu nedenle tüm importer'ı `Isolate.run` içine koymak güvenli varsayılmamalıdır.

İlk sürüm:

- loading UI gösterir
- timings kaydeder
- büyük model limitleri uygular
- jank ölçer

Daha sonra upstream saf CPU parse representation ayırırsa parse isolate'a taşınabilir.
