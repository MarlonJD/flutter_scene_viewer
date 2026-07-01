# 01 — Product Vision ve Motivasyon

## Problem

Flutter geliştiricileri GLB göstermek istediğinde çoğunlukla üç yol kullanır:

1. WebView içinde BabylonJS veya `<model-viewer>`.
2. Android ve iOS'ta farklı native renderer kullanan plugin'ler.
3. `flutter_scene` ve `flutter_gpu` gibi düşük seviyeli API'leri doğrudan kullanmak.

WebView yaklaşımı hızlı başlatır fakat JavaScript bridge, browser/CORS davranışı, WebView lifecycle ve Flutter composition maliyetleri getirir. Native plugin yaklaşımı güçlü olabilir fakat Android ve iOS'ta farklı renderer/material/lighting davranışları oluşabilir. `flutter_scene` ise aynı Dart scene/material modelini sunar fakat uygulama geliştiricisinin network yükleme, camera, selection, cache, material reset ve state restore gibi ürün sorunlarını kendisinin çözmesini bekler.

## Ürün tezi

`flutter_scene_viewer`, yeni bir motor değil; `flutter_scene`i gerçek uygulamalarda kullanılabilir bir viewer/configurator SDK'sına dönüştüren katmandır.

```dart
FlutterSceneViewer(
  source: ModelSource.network(modelUri),
  controller: controller,
  lighting: ViewerLighting.studio(),
  renderPolicy: RenderPolicy.adaptive,
  initialState: savedState,
  onPartTapped: (part) => selected = part,
)
```

```dart
await controller.patchPartMaterial(
  part,
  MaterialPatch(
    baseColorTexture: TextureSource.network(textureUri),
    metallic: 0.2,
    roughness: 0.75,
  ),
);
```

## Neden değerli olabilir?

- Network GLB ve runtime texture/PBR ihtiyacı gerçek ürün konfigüratörlerinde sık görülür.
- `flutter_scene` engine API'si ile uygulama geliştiricisi arasında ergonomi boşluğu vardır.
- Assembly/sub-assembly/part adresleme, endüstriyel ve medikal modeller için basit entity name'den daha değerlidir.
- Flutter UI ile aynı composition hattında 3D gösterim; clipping, overlays ve route animasyonlarında daha doğal entegrasyon sağlayabilir.
- Android/iOS'ta aynı scene graph, material modeli ve shader kaynaklarını kullanmak, Filament/SceneKit gibi iki ayrı pipeline'a göre görsel tutarlılık potansiyeli sunar.
- Web için aynı yüksek seviye API hedeflenebilir.

## `interactive_3d`den farkı

`interactive_3d` bugün Android'de Filament, iOS'ta SceneKit kullanır ve runtime texture/PBR override sunar. Yeni paketin farkı sadece texture değiştirmek değildir.

| Konu | interactive_3d | flutter_scene_viewer hedefi |
|---|---|---|
| Android renderer | Filament | flutter_scene → Flutter GPU/Impeller |
| iOS renderer | SceneKit | flutter_scene → Flutter GPU/Impeller |
| Web | Ana hedef değil | Aynı viewer API'siyle hedef |
| Scene/material modeli | Platforma göre iki implementation | Ortak Dart scene/material hattı |
| Assembly addressing | Entity-name odaklı | Node child path + primitive index |
| Flutter composition | Texture/PlatformView yolları | SceneView/Flutter paint hattı |
| Ürün API'si | Medikal/selection ağırlıklı | Genel viewer/configurator SDK |
| Performans | Olgun native motorlar | Ölçülmesi gereken rekabetçi hedef |

Yeni paket “kesin daha hızlı” diye yapılmaz. Filament'i geçmek varsayım değildir. Değer; tek pipeline, platform kapsamı, assembly semantiği, Flutter integration ve production ergonomisidir.

## Hedef kullanıcılar

- Mobilya, otomotiv, ayakkabı ve aksesuar konfigüratörleri
- Endüstriyel assembly/part viewer'ları
- Anatomik/medikal parça seçimi
- Eğitim ve katalog uygulamaları
- Kullanıcının networkten model ve texture getirdiği uygulamalar
- WebView bağımlılığından çıkmak isteyen Flutter ekipleri

## Başarı ölçütü

MVP değerli sayılırsa:

- URL, asset ve bytes kaynağından statik GLB yüklenir.
- Assembly hierarchy korunur ve duplicate-name-safe part addressing çalışır.
- İki farklı primitive bağımsız biçimde texture/PBR override alır.
- Reset orijinal materyali döndürür.
- Kamera ve selection güvenilirdir.
- Viewer kontrollü PBR ışıklandırma Android/iOS'ta kabul edilebilir tutarlılık gösterir.
- Route reopen ile state restore edilir.
- Boşta sürekli frame çizilmez.
- Benchmark sonucu iddiaları destekler veya sınırları dürüstçe gösterir.

## Ürün konumlandırma cümlesi

> A community-maintained, Flutter-native static GLB viewer and product configurator built on `flutter_scene`, with network loading, assembly-aware picking, runtime PBR overrides, and adaptive rendering—without a WebView.
