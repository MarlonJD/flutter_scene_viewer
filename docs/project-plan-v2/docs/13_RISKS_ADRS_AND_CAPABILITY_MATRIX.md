# 13 — Riskler, ADR'ler ve Capability Matrix

## Risk register

| Risk | Etki | Olasılık | Mitigation |
|---|---:|---:|---|
| flutter_scene/flutter_gpu API kırılması | Yüksek | Yüksek | Exact pin, narrow adapter, CI matrix |
| Runtime GLB load jank | Yüksek | Orta | Limits, timings, loading UX, upstream parse split araştırması |
| Filament'ten düşük import/render performansı | Orta/Yüksek | Orta | Benchmark, scope, adaptive render |
| Visual mismatch platformlar arası | Orta | Orta | Same shader pipeline, visual fixtures, tolerance |
| Missing glTF extensions | Yüksek | Orta | Capability matrix, diagnostics, authoring guide |
| Shared material side effects | Yüksek | Orta | Copy-on-write + fixture |
| GPU texture leaks | Yüksek | Orta | Ownership/ref-count/LRU stress tests |
| SceneView on-demand repaint eksikliği | Yüksek | Orta | Spike, minimal upstream PR |
| Large untrusted GLB memory exhaustion | Yüksek | Orta | Byte/dimension/count limits |
| Package officialmiş gibi algılanması | Orta | Orta | Community-maintained disclaimer |

## ADR-001: Engine seçimi

Karar: `flutter_scene` üzerinde build et; raw `flutter_gpu` renderer yazma.

Gerekçe: Scene graph, importer, PBR, lighting, raycast ve render altyapısı hazırdır. Yeniden yazmak gereksiz ve kapsam dışıdır.

## ADR-002: V1 statik GLB

Karar: V1 skeletal/morph/animation özelliklerini içermez.

Gerekçe: Product viewer/configurator için zorunlu değildir; scope ve test matrisi ciddi büyür.

## ADR-003: Viewer-controlled lighting

Karar: V1 embedded cameras/lights yerine studio environment preset kullanır.

Gerekçe: Tutarlı out-of-box PBR görünümü ve daha küçük importer scope.

## ADR-004: No geometry repair

Karar: Tessellation, UV unwrap, tangent generation veya DCC axis heuristic yoktur.

Gerekçe: Viewer model authoring aracı değildir. Eksik data diagnostics ile görünür olur.

## ADR-005: Stable part identity

Karar: child-index node path + primitive index canonical address'tir.

Gerekçe: Node names duplicate/empty olabilir.

## ADR-006: Performance claim

Karar: Filament/SceneKit/BabylonJS'ten daha hızlı iddiası benchmark öncesi yasaktır.

Gerekçe: Mimari avantaj raw performance kanıtı değildir.

## Capability matrix template

| Capability | Android | iOS | Web | Notes |
|---|---|---|---|---|
| Network GLB | TBD | TBD | TBD | Web CORS |
| Static triangles | TBD | TBD | TBD | |
| Assembly nodes | TBD | TBD | TBD | |
| Base PBR | TBD | TBD | TBD | |
| Normal mapping | TBD | TBD | TBD | Tangent behavior |
| Runtime base texture | TBD | TBD | TBD | UV required |
| Runtime PBR factors | TBD | TBD | TBD | |
| Raycast | TBD | TBD | TBD | |
| Adaptive render | TBD | TBD | TBD | Upstream API |
| Embedded camera/lights | No | No | No | Post-MVP |
| Skeletal/morph | No | No | No | V1 non-goal |
