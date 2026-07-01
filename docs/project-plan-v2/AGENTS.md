# AGENTS.md — Kalıcı Coding Agent Kuralları

## Öncelik sırası

1. Çalışan ve ölçülebilir küçük dilim.
2. Doğru kaynak yaşam döngüsü.
3. Güvenilir public API.
4. Test ve diagnostics.
5. Performans optimizasyonu.
6. Gelecek özellikler.

## Zorunlu çalışma biçimi

- Önce `START_HERE.md`, tüm `docs/` ve `planning/` dosyalarını oku.
- Her milestone öncesinde gerçek `flutter_scene` ve Flutter SDK source/API'sini doğrula.
- API ismi tahmin etme; analyzer ve dependency source'u esas al.
- Küçük, test edilebilir commit/dilimlerle ilerle.
- Her dilim sonunda `dart format`, `flutter analyze` ve ilgili testleri çalıştır.
- Public API değiştiğinde docs ve changelog'u aynı değişiklikte güncelle.
- Başarısız bir upstream yeteneği için engine yazmaya atlama; önce blokajı raporla ve minimum upstream PR seçeneğini değerlendir.
- Exact Flutter ve `flutter_scene` revision'ını kaydetmeden benchmark veya performans iddiası yayımlama.

## Kesin mimari sınırlar

- Ham `flutter_gpu` kullanarak sıfırdan renderer yazma.
- Yeni PBR master shader veya GLSL yazma; önce mevcut `flutter_scene` PBR material/shader'ını kullan.
- GLB tessellation yapma. GLB triangle/index/attribute verisini upstream importer'a ver.
- UV unwrap, tangent generation, mesh simplification veya CAD tessellation yazma.
- Widget içinde HTTP, disk cache veya GPU resource ownership yönetme.
- Raw `Node`, `Material` veya GPU texture objelerini ana public API yapma.
- GPU objelerini serialize etme.
- Node adını tek başına stable kimlik kabul etme.
- V1'e animation, skinning, morph target, KHR lights veya compression sokma.

## Sorumluluk ayrımı

### flutter_scene_viewer

- Source loading, progress, timeout, cancellation
- Session generation ve stale-result koruması
- Assembly/part index
- Camera controller ve picking mapping
- Material patch semantics ve reset
- Texture descriptor/cache policy
- Viewer-controlled lighting preset
- Render scheduler
- Persistence ve diagnostics

### flutter_scene

- GLB/glTF parsing
- Geometry/vertex/index GPU buffer oluşturma
- PBR shader/material
- Texture decode/upload primitives
- Scene graph rendering
- Raycast ve bounds
- Flutter GPU/Impeller integration

## GLB ve geometri kuralları

- GLB runtime importer'ın triangle primitive ve mevcut attributes'larını tüket.
- Viewer geometri “düzeltme” motoru olmayacak.
- Texture override için `TEXCOORD_0` yoksa typed `MissingUvSet` sonucu dön.
- Normal/tangent davranışını upstream capability olarak kaydet. Viewer kendisi tangent üretmeyecek.
- Unsupported primitive topology veya glTF extension sessizce yok sayılmamalı; diagnostics'e girilmeli.
- DCC programına göre eksen tahmin etme. Canonical glTF → engine dönüşümünü upstream'e bırak; yalnızca explicit `rootTransform` escape hatch sun.

## Scene graph kuralları

- Mesh taşımayan `Node`, assembly/sub-assembly/dummy transform node olarak korunmalı.
- Mesh taşıyan node bir veya daha fazla primitive içeriyorsa her primitive ayrı material slot/part adresi almalı.
- Stable address: node child-index path + optional semantic name + primitive index.
- Duplicate names desteklenmeli.
- Shared material mutation için copy-on-write uygulanmalı.

## Materyal kuralları

- V1 temel glTF metallic-roughness PBR:
  - base color factor/texture
  - metallic factor
  - roughness factor
  - normal texture (mevcut modelde koruma; runtime slot capability'ye bağlı)
  - occlusion
  - emissive
  - alpha/double-sided koruma
- Base-color/emissive sRGB; normal/metallic-roughness/occlusion linear data olarak ele alınmalı.
- Runtime patch failure mevcut materyali bozmamalı.
- Orijinal snapshot reset için immutable tutulmalı.
- Parallax, displacement, SSS, clear coat, transmission vb. V1'e eklenmemeli.

## Lighting kuralları

- V1 viewer-controlled lighting kullanır.
- Default studio environment/IBL, exposure, tone mapping, background ve opsiyonel directional light sağlanır.
- GLB embedded camera ve `KHR_lights_punctual` V1'de import edilmez.
- Full-scene import ayrı future milestone'dır.

## Async ve lifecycle kuralları

- Her model load bir generation id taşımalı.
- A yüklemesi, B başladıktan sonra bitse bile B'yi değiştirememeli.
- Dispose sonrası callback/state mutation olmamalı.
- Texture slot operation'ları last-write-wins veya explicit queue semantiğine sahip olmalı.
- GPU context isolate-bound olabilir; `Node.fromGlbBytes()` ve GPU upload'ı körlemesine `Isolate.run` içine taşıma.
- Saf CPU parse ayrımı ancak upstream güvenli bir ara representation sunuyorsa düşünülmeli.

## Güvenlik ve limitler

- Max model bytes, redirects, timeout ve MIME/signature validation.
- GLB magic/version/declared length doğrulaması.
- Max texture dimensions ve decoded byte budget.
- Untrusted model için node/primitive/vertex/index/texture count limitleri.
- Auth header'larını loglama veya state'e serialize etme.
- Web CORS hatalarını typed ve açıklayıcı raporla.

## Her çalışma sonunda rapor

1. Tamamlanan milestone/task'lar.
2. Değişen dosyalar.
3. Çalıştırılan komutlar ve sonuçları.
4. Exact Flutter ve `flutter_scene` revision'ları.
5. Gerçek cihaz/platform doğrulaması.
6. Bilinen limit/blokajlar.
7. Sonraki en küçük görev.
