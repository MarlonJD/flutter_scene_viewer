# 03 — Engine Boundary ve Render Mimarisi

## Ana karar

Paket `flutter_scene` üzerine kurulacaktır. Ham `flutter_gpu` üzerinde renderer yazılmayacaktır.

```text
FlutterSceneViewer widget/controller
    ↓
ViewerSession + ModelLoader + PartRegistry
    ↓
MaterialOverrideService + Camera + Scheduler
    ↓
FlutterSceneAdapter
    ↓
flutter_scene Scene / Node / Mesh / Material / SceneView
    ↓
flutter_gpu / Impeller
```

## Neyi `flutter_scene` yapar?

- GLB container ve glTF document parse
- Node hierarchy oluşturma
- Triangle primitive attributes/index verisini kendi geometry buffer formatına paketleme
- GPU vertex/index buffer oluşturma
- Embedded image decode ve GPU texture oluşturma
- PBR `PhysicallyBasedMaterial` ve standard shader
- Environment lighting, raycast, bounds ve scene rendering

## Neyi viewer yapar?

- Network/asset/bytes source abstraction
- Download progress, timeout, cancellation, cache
- Import session generation
- Assembly/part registry
- Stable addressing
- Runtime patch/reset semantics
- Texture descriptor/cache/reuse
- Camera controls ve auto-fit
- Viewer-controlled lighting preset
- Persistence
- Diagnostics
- Adaptive frame scheduling

## “Texture GPU'ya neden yükleniyor?”

PNG/JPEG dosyası sıkıştırılmış dosya verisidir. Shader'ın örnekleyebilmesi için görüntü decode edilir ve GPU texture resource oluşturulur. Bu gerekli bir render adımıdır; fakat `flutter_scene_viewer` bunun düşük seviyeli implementation'ını yeniden yazmaz. `flutter_scene`in public image/texture helpers ve material slot API'leri kullanılır.

## “Master material yazmalı mıyız?”

Hayır. `flutter_scene` halihazırda standard glTF metallic-roughness material/shader sunar. Viewer:

1. Mevcut `PhysicallyBasedMaterial` verisini okur.
2. Gerekirse copy-on-write kopya material oluşturur.
3. Factor ve texture slotlarını değiştirir.
4. Orijinal snapshot'ı reset için saklar.

Yeni GLSL ancak upstream material gerçekten yetersizse ve ayrı bir future extension olarak düşünülür.

## Platform farkı

Android ve iOS'ta aynı Dart scene graph/material model/shader kaynakları kullanılacağı için görsel tutarlılık potansiyeli artar. Ancak şu nedenlerle pixel-perfect eşitlik garanti edilmez:

- GPU ve driver farkları
- color format/precision
- MSAA/FXAA capability
- platform image decode
- Impeller backend ayrıntıları

Bu yüzden görsel regression testleri gerekir.

## `interactive_3d` karşılaştırması

`interactive_3d` Android'de Filament ve iOS'ta SceneKit kullanır. Bu olgunluk ve performans avantajı sağlayabilir. Yeni paket:

- Filament'i yeniden yazmaz.
- “Daha hızlı” varsaymaz.
- Aynı Flutter scene/material API'sini her platformda kullanmayı hedefler.
- Web'i aynı viewer API'sine dahil eder.
- Assembly-aware product configurator API'sini merkez yapar.

## Adapter kuralı

Upstream değişken olduğu için tüm `flutter_scene` çağrıları dar bir adapter altında tutulmalıdır:

```text
lib/src/upstream/flutter_scene_adapter.dart
```

Public API hiçbir zaman doğrudan upstream sınıflarına bağımlı olmamalıdır. Böylece upstream kırılmaları tek yerde yönetilir.
