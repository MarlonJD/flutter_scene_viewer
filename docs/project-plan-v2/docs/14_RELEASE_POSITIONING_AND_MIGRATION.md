# 14 — Release, Positioning ve Mevcut Paketlerle İlişki

## Alpha konumlandırması

İlk sürüm:

> Experimental community package built on preview Flutter Scene/Flutter GPU APIs.

README'de mutlaka:

- Not official
- Preview dependencies
- Exact tested Flutter revision
- Capability matrix
- Known GLB limitations
- No performance superiority claim

bulunmalıdır.

## Neden kullanıcı seçsin?

- WebView istemiyor
- Android/iOS/web için aynı viewer API'sini istiyor
- Assembly/sub-assembly/part hiyerarşisi gerekiyor
- Runtime product configuration yapıyor
- Flutter overlays/clipping/route composition önemli
- Persist edilebilir material state ve production cache istiyor

## Ne zaman `interactive_3d` daha mantıklı?

- Bugün stabil Android/iOS production gerekir
- Filament/SceneKit'in olgun importer/render davranışı önceliklidir
- Web gerekli değildir
- Mevcut API ihtiyacı karşılamaktadır

## `babylonjs_viewer` stratejisi

Yeni paket alpha iken eski package archive/deprecated yapılmamalıdır.

README banner:

```md
> Experimental Flutter-native successor under development:
> flutter_scene_viewer. The existing BabylonJS/WebView package remains
> available for stable and broader web-engine compatibility.
```

Deprecated yönlendirme için minimum eşikler:

- Android+iOS gerçek cihaz stability
- Network GLB, runtime texture/PBR, camera, picking tamam
- Memory/lifecycle stress test
- External users
- Migration guide
- Tercihen Flutter stable toolchain compatibility

## Package README ana mesajı

1. Ne yapar?
2. Ne yapmaz?
3. Neden flutter_scene?
4. Quick start
5. Runtime PBR example
6. Assembly addressing
7. Model authoring requirements
8. Capability matrix
9. Benchmark methodology
10. Preview warning
