# 08 — Render Scheduler ve Performans

## Performans hedefi

Hedef “Filament'ten daha hızlı olmak” değildir. Hedef:

- Flutter UI ile akıcı composition
- orta ölçekli statik GLB'lerde rekabetçi frame time
- düşük idle GPU/battery kullanımı
- ölçülebilir ve dürüst davranış

## Risk

`SceneView(autoTick: true)` her frame repaint üretir. Statik product viewer için bu gereksizdir.

## Render policy

```dart
enum RenderPolicy {
  always,
  onDemand,
  whileInteracting,
  adaptive,
}
```

Default: `adaptive`.

## Render reasons

Scheduler bir reason set'i tutar:

- initialLoad
- oneShotRequest
- gesture
- inertia
- cameraAnimation
- materialMutation
- textureUpload
- resize
- lifecycleResume
- debugContinuous

Frame üretimi reason varken devam eder. Statik durumda durur.

## Adaptive akış

```text
Pointer down         → gesture reason on
Drag/pinch           → frame every vsync
Pointer up           → gesture off, inertia on
Velocity threshold   → inertia off
Material patch       → one-shot 1–2 frame
Texture upload       → one-shot + completion frame
Idle                 → ticker stopped
App background       → all noncritical reasons paused
```

## Upstream ihtiyaç

İdeal olarak `SceneView` dışarıdan repaint/listenable veya controller `requestFrame()` kabul etmelidir. Mevcut public API yeterli değilse:

1. Wrapper rebuild ile minimum çözüm spike edilir.
2. Küçük upstream PR hazırlanır.
3. Fork, son çare olur.

## Render scale ve quality

- Default `renderScale = 1.0` veya device-aware conservative policy
- 0.75/1.0/1.25 presets
- MSAA/FXAA capability bilgisi
- Static product viewer için gölge/bloom varsayılanı ölçülerek seçilir
- Quality parity olmadan benchmark karşılaştırması yapılmaz

## Ölçülecek metrikler

- Download duration
- Import duration
- Texture decode/upload duration
- Time to first visible frame
- Frame build/raster/GPU timings
- p50/p95/p99 frame time
- Gesture latency
- Texture swap latency
- Peak RSS / GPU memory proxy
- Repeated load/unload memory trend
- Idle rendered frames per minute
- Battery/thermal observation (uzun test)

## Olası avantajlar

- PlatformView/WebView olmadan Flutter composition
- Material operation'ların Dart scene modelinde doğrudan uygulanması
- On-demand render
- Tek üst seviye platform API'si

## Olası dezavantajlar

- Dart runtime importer initial load maliyeti
- Filament kadar optimize/olgun olmayan code paths
- Preview API instability
- Large GLB parse/decode sırasında main isolate jank

Bu nedenle sonuç benchmark ile belirlenir.
