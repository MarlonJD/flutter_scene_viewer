# 10 — Implementation Roadmap

## M0 — Toolchain ve feasibility spike

Amaç: Büyük mimari yazmadan temel varsayımları doğrulamak.

- Exact Flutter SDK revision pinle
- Exact `flutter_scene` version/commit pinle
- Android gerçek cihazda network GLB göster
- İkinci platformda göster (iOS veya web)
- Runtime roughness değiştir
- Runtime base-color texture değiştir
- Simple node hierarchy ve raycast doğrula
- SceneView one-shot/adaptive repaint imkanını doğrula
- Spike timings kaydet

Gate: Bunlar çalışmadan package architecture'a geçme.

## M1 — Package skeleton ve safe loader

- Package exports
- ModelSource
- Typed load state/errors
- Streaming network loader
- GLB header validation
- Limits
- ViewerSession generation/cancellation
- Dispose/source-replacement tests

## M2 — Scene adapter, assembly registry ve viewer lighting

- Narrow `FlutterSceneAdapter`
- Scene create/attach/detach
- Viewer-controlled studio lighting
- Hierarchy traversal
- Transform-only assembly index
- PartAddress node path + primitive index
- Duplicate name support
- Material usage/shared map
- Diagnostics baseline

## M3 — Camera, picking ve visibility

- Bounds-based fit
- Orbit/pan/zoom
- Root transform escape hatch
- Raycast → PartHit mapping
- Part/assembly visibility
- Focus part/assembly

## M4 — Material snapshot/patch/reset

- PBR capability inspection
- Immutable original snapshot
- Shared material copy-on-write
- Partial scalar patch merge
- Base-color/metallic/roughness/emissive
- Reset part/reset all
- Shared-material regression fixture

## M5 — Runtime textures ve diagnostics

- TextureSource
- Network/asset/bytes loading
- Max dimension/decoded budget
- Base-color texture assignment
- Missing UV typed behavior
- Texture cache coalescing/ref-count/LRU
- Last-write-wins operations
- Clear/reset texture
- Optional normal/MR/occlusion slot capability spike; başarısızsa public API capability ile sınırla

## M6 — Adaptive rendering

- Render reason state machine
- One-shot requestFrame
- Gesture/inertia scheduler
- Lifecycle pause/resume
- Idle frame counter test
- Upstream PR gerekiyorsa minimal değişiklik

## M7 — Persistence ve model cache

- ViewerState schema v1
- Model fingerprint
- StateApplyReport
- Disk GLB cache + validators
- Route reopen example
- Secret-safe serialization

## M8 — Hardening ve benchmark

- Malformed/oversized input tests
- Repeated load/unload stress
- Repeated texture swap stress
- Visual regression fixtures
- Android+iOS/web capability matrix
- Profile/release benchmark harness
- `interactive_3d` ve BabylonJS/WebView karşılaştırması
- Alpha README ve migration/positioning docs

## Post-MVP

Öncelik sırasıyla, talep varsa:

1. Rigid node animation playback
2. Multi-file glTF resolver
3. Embedded camera / KHR lights
4. Compression extensions
5. Skeletal animation controller
6. Advanced material resolver API

Morph targets, VR ve displacement core roadmap değildir.
