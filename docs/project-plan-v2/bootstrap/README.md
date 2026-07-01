# Bootstrap

## 1. Repo oluştur

```bash
flutter create --template=package flutter_scene_viewer
cd flutter_scene_viewer
```

## 2. Toolchain pinle

FVM veya eşdeğer mekanizmayla exact Flutter revision kullan. `master` kelimesini tek başına reproducible pin sayma.

Kaydet:

```text
Flutter revision:
Dart version:
Engine revision:
flutter_scene version/commit:
Date tested:
```

## 3. Dependency source audit

Implementation başlamadan gerçek source'ta doğrula:

- `Node.fromGlbBytes`
- `Scene` initialization
- `SceneView` autoTick/repaint
- `PhysicallyBasedMaterial` mutable slots
- image/texture helper APIs
- hierarchy traversal
- bounds/raycast
- cleanup/dispose semantics

Sonuçları implementation repo'sunda `docs/upstream_api_notes.md` dosyasına yaz.

## 4. Spike example

Önce `example/` içinde minimum code:

- networkten küçük GLB indir
- import et
- Scene'e ekle
- studio lighting
- camera
- roughness mutate
- texture mutate
- hierarchy print
- tap raycast
- frame/ticker kontrolü

Package architecture ancak spike geçince başlasın.

## 5. Standart komutlar

```bash
dart format .
flutter analyze
flutter test
flutter test integration_test
flutter run --profile
```

Preview toolchain için gereken flags source audit sonucu README'ye yazılmalıdır.
