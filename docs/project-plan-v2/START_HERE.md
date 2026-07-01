# flutter_scene_viewer — Project Pack v2

Tarih: 23 Haziran 2026

Bu paket, `flutter_scene` üzerinde kurulacak yüksek seviyeli ve WebView kullanmayan bir Flutter GLB viewer/configurator paketinin uygulanması için hazırlanmıştır.

## Tek cümlelik ürün tanımı

> Network, asset veya byte kaynağından statik GLB yükleyen; assembly/sub-assembly/part hiyerarşisini koruyan; parça seçimi, runtime PBR materyal/texture değişimi, viewer kontrollü ışıklandırma, cache, persistence ve adaptif render sağlayan Flutter-native viewer SDK'sı.

## Bu proje ne değildir?

- Yeni bir 3D motor değildir.
- Filament, Unity veya Unreal alternatifi değildir.
- GLB'yi tessellate etmez; GLB zaten triangle/index/attribute verisiyle gelir.
- UV unwrap, CAD tessellation, geometri onarımı veya runtime shader compiler yazmaz.
- V1'de skeletal animation, morph target, VR, parallax veya full-scene light/camera importu hedeflemez.

## Teknik katmanlama

```text
Flutter uygulaması
    ↓
flutter_scene_viewer
    ├── network/cache/session/controller
    ├── assembly & part registry
    ├── camera/picking/material overrides
    ├── diagnostics/persistence/adaptive scheduler
    ↓
flutter_scene
    ├── scene graph / Node / Mesh / Primitive
    ├── GLB runtime importer
    ├── PBR material / lighting / raycast
    └── GPU resource creation
    ↓
flutter_gpu → Impeller (Android/iOS)
WebGL2 shim (web)
```

Ham `flutter_gpu` üzerinde renderer yazılmayacaktır. `flutter_scene` GLB parse, geometry buffer hazırlama, PBR shader, texture upload ve rendering işlerini yapar. Bu proje bunları production uygulamasında kolay ve güvenli kullanılır bir API'ye dönüştürür.

## V1 ürün sınırı

V1: statik ürün, endüstriyel parça, mobilya, otomobil parçası, anatomi ve benzeri viewer/configurator senaryoları.

Dahil:

- Tek dosyalı GLB
- Runtime network yükleme
- Transform-only dummy/assembly node'ları
- Node path + primitive index ile adresleme
- Temel glTF metallic-roughness PBR
- Runtime base-color texture ve PBR factor override
- Picking, visibility, orbit/pan/zoom, camera fit
- Studio IBL/environment + temel directional light
- Cache, state restore ve boşta render durdurma

Hariç:

- Skeletal mesh ve poz verme
- Morph target/blend shape
- Rigid animation bile V1 kabul kriteri değildir
- KHR_lights_punctual ve embedded camera importu
- Draco/meshopt/KTX2 runtime decode
- Parallax/displacement/SSS/world-aligned texture
- VR/AR/fizik/model editörü

## Önce okunacaklar

1. `docs/01_PRODUCT_VISION_AND_MOTIVATION.md`
2. `docs/02_SCOPE_AND_NON_GOALS.md`
3. `docs/03_ENGINE_BOUNDARY_AND_RENDER_ARCHITECTURE.md`
4. `docs/04_SCENE_GRAPH_AND_ASSEMBLY_MODEL.md`
5. `docs/05_PUBLIC_API_SPEC.md`
6. `docs/10_IMPLEMENTATION_ROADMAP.md`
7. `planning/task_graph.yaml`
8. `prompts/MASTER_PROMPT.txt`

## Ajanı başlatma

Yeni bir repo oluştur:

```bash
flutter create --template=package flutter_scene_viewer
cd flutter_scene_viewer
```

Bu paketin içeriğini repo köküne kopyala. Daha sonra Codex veya Claude Code'a `prompts/MASTER_PROMPT.txt` içeriğini ver.

Ajan ilk olarak yalnızca şunları yapmalıdır:

1. Uyumlu Flutter SDK revision'ını sabitlemek.
2. Uyumlu `flutter_scene` sürümü/commit'ini sabitlemek.
3. Gerçek upstream API'leri source üzerinden doğrulamak.
4. Android ve ikinci bir platformda network GLB spike yapmak.
5. Runtime material/texture mutation spike yapmak.
6. Sonuç başarısızsa engine yazmaya başlamadan blokaj raporu çıkarmak.

## Kritik toolchain notu

23 Haziran 2026 itibarıyla `flutter_scene` ve `flutter_gpu` erken önizleme durumundadır ve güncel özellikler recent Flutter master toolchain gerektirebilir. Dokümanlardaki API isimleri ürün sözleşmesini anlatır; upstream API değişmişse adapter gerçek API'ye göre uygulanmalıdır. Uydurma API kullanılmamalıdır.

## Bu sürümde değişenler

Önceki pakete göre:

- V1 statik GLB viewer olarak kesin biçimde daraltıldı.
- Skinning, skeletal animation ve morph target çıkarıldı.
- Compression, full-scene lighting/camera ve gelişmiş materyaller ertelendi.
- Tessellation/UV unwrap/geometri repair açıkça non-goal oldu.
- Assembly/sub-assembly/dummy node modeli ürünün merkezine alındı.
- Viewer kontrollü PBR ışıklandırma V1 standardı oldu.
- “Filament'ten daha hızlı” hedefi kaldırıldı; yalnızca benchmark ile kanıtlanabilir rekabetçi performans hedeflendi.
- `interactive_3d` ile fark, renderer hızından çok tek pipeline, web, Flutter composition ve configurator ergonomisi olarak tanımlandı.
