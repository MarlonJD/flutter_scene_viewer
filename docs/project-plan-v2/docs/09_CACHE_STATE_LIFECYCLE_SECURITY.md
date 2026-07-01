# 09 — Cache, State, Lifecycle ve Güvenlik

## Model cache

Network GLB cache entry:

```text
canonical URI
ETag
Last-Modified
content hash
byte length
last access
local file path
```

Politikalar:

- noCache
- preferCache
- revalidate
- cacheOnly

Authorization header cache key'e veya serialized state'e düz metin yazılmamalıdır.

## Texture cache

İki katman düşünülebilir:

1. Encoded bytes disk/memory cache
2. GPU texture memory cache

GPU texture cache ref-count + LRU kullanır. Viewer dispose olduğunda references release edilir.

## ViewerState

Persist edilenler:

- schema version
- model fingerprint
- source descriptor (secret headers hariç)
- camera state
- part visibility
- material scalar override'ları
- texture source descriptor/cache key

Persist edilmeyenler:

- `Node`
- `Material`
- GPU texture
- `ui.Image`
- HTTP client
- auth token/header

## State restore

```text
Load model
Build PartRegistry
Compare model fingerprint
Apply camera
Apply visibility
Resolve texture descriptors
Apply material patches
Return StateApplyReport
```

Rapor:

- applied
- missingPart
- modelMismatch
- unsupportedSlot
- missingUv
- textureFailed
- skipped

## Lifecycle

- Widget dispose session'ı iptal eder.
- Controller detach sonrası command typed error döndürür.
- App paused olduğunda scheduler durur.
- Resume'da one-shot frame istenir.
- Source replacement kaynak ownership'i atomik yönetir.
- Route push/pop stress test edilir.

## Untrusted model limitleri

Configurable:

- max model bytes
- max node count
- max primitive count
- max vertex/index count
- max embedded image count
- max texture dimension
- max total decoded texture bytes
- max redirect count
- network timeout

Upstream importer tüm istatistikleri pre-import expose etmiyorsa header limitleri uygulanır, post-import diagnostics ile ek limitler kontrol edilir. Güvenli abort semantics belgelenir.

## Error behavior

- Silent fallback minimumda tutulur.
- Model kısmen render edilebiliyorsa diagnostics warning üretir.
- Material patch başarısızsa previous material korunur.
- Network/CORS/decode/import hataları typed exception'a çevrilir.
