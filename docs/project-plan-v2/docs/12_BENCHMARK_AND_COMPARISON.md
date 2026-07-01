# 12 — Benchmark ve Karşılaştırma Planı

## Amaç

“Daha hızlı” pazarlaması yapmak değil; kullanım alanına göre gerçek trade-off'ları göstermek.

Karşılaştırılacaklar:

- `flutter_scene_viewer`
- `interactive_3d`
- BabylonJS/WebView viewer

## Fairness kuralları

- Aynı GLB ve mümkünse aynı texture çözünürlükleri
- Benzer viewport physical pixels
- Benzer background/environment/exposure
- Benzer AA/render scale
- Animasyon kapalı
- Aynı camera path
- Release/profile build
- Thermal state ve cihaz metadata'sı

## Senaryolar

### Cold load

- Network cache miss
- Download hariç ve dahil ayrı ölçüm
- Time to first visible frame
- Peak memory

### Warm load

- Disk cache hit
- Texture cache hit/miss ayrımı

### Interaction

- 10 saniye orbit/pan/zoom scripted gesture
- p50/p95/p99 frame time
- missed frames
- input-to-visual latency proxy

### Runtime material

- roughness-only patch
- base-color texture swap 1K/2K
- repeated alternating texture swaps

### Idle

- 60 saniye statik scene
- rendered frame count
- CPU/GPU activity proxy
- thermal/battery observation

### Lifecycle

- 50 route push/pop
- 30 model replace
- 100 texture swap
- memory trend ve leaks

## Cihaz matrisi

Minimum:

- Android mid-range
- Android high-end
- iPhone gerçek cihaz
- Web desktop browser

## Rapor formatı

Her sonuç:

- Flutter revision
- `flutter_scene` revision
- package commit
- device/OS/GPU
- asset SHA256
- viewport
- quality settings
- test repetitions
- median ve percentile
- limitations

## Sonuç dili

Kabul edilebilir:

> On tested device X, flutter_scene_viewer produced lower idle frame activity and comparable interaction p95, while interactive_3d loaded the large GLB faster.

Kabul edilemez:

> flutter_scene_viewer is faster than Filament.
