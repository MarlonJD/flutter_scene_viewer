# 04 — Scene Graph, Assembly ve Part Modeli

## Temel glTF terminolojisi

- **Node:** Transform, name ve child ilişkileri taşıyan scene graph öğesi. Mesh taşımak zorunda değildir.
- **Mesh:** Bir veya daha fazla primitive koleksiyonu.
- **Primitive:** Tek draw/material slotuna karşılık gelen geometry + material eşleşmesi.
- **Material:** PBR factor ve texture slotları.
- **Accessor/BufferView:** Vertex, normal, UV, index gibi typed binary data tanımları.

## Inventor benzeri assembly mantığı

```text
VehicleRoot                       (Node, mesh yok)
├── FrontAssembly                 (Node, mesh yok)
│   ├── LeftHeadlight             (Node + Mesh)
│   │   ├── Primitive 0: glass
│   │   └── Primitive 1: reflector
│   └── Bumper                    (Node + Mesh)
└── RearAssembly                  (Node, mesh yok)
    └── Trunk                     (Node + Mesh)
```

Mesh taşımayan Node, Inventor'daki assembly/sub-assembly/dummy object işlevini görür. Parent transform child mesh'lere uygulanır.

## Viewer domain modeli

```dart
sealed class ViewerElement {}

final class AssemblyInfo extends ViewerElement {
  final NodeAddress address;
  final String? name;
  final List<NodeAddress> children;
}

final class PartInfo extends ViewerElement {
  final PartAddress address;
  final String? nodeName;
  final int primitiveIndex;
  final MaterialCapabilities material;
}
```

Gerçek implementation isimleri değişebilir; semantik korunmalıdır.

## Stable adresleme

Node name tek başına güvenilir değildir. Aynı isim tekrarlanabilir veya boş olabilir.

Önerilen adres:

```dart
PartAddress(
  nodePath: [0, 2, 1],       // root'tan child index path
  primitiveIndex: 0,
  semanticPath: ['VehicleRoot', 'FrontAssembly', 'LeftHeadlight'],
)
```

- `nodePath` canonical kimliktir.
- `semanticPath` debug/UX içindir.
- `primitiveIndex`, aynı node içindeki material slotunu ayırır.
- Model fingerprint ile birlikte saklanır.

## Assembly işlemleri

Controller şu işlemleri assembly veya part seviyesinde destekleyebilir:

- visibility
- selection/highlight
- frame/focus camera
- enumerate descendants
- material patch yalnızca part/primitive üzerinde

Assembly'ye material patch verilirse policy açık olmalıdır:

```dart
AssemblyPatchPolicy.descendants
```

V1'de bunu eklemek zorunlu değildir; explicit descendant listesi tercih edilebilir.

## Shared material problemi

İki primitive aynı material instance'ını paylaşabilir. Birini doğrudan mutate etmek diğerini de değiştirir.

Çözüm:

1. Part ilk kez değiştirildiğinde source material snapshot al.
2. Material instance başka part tarafından kullanılıyorsa copy-on-write clone oluştur.
3. Primitive material slotunu clone'a yönlendir.
4. Override'ı clone üzerinde uygula.
5. Reset'te original slot/material state'e dön.

Bu davranış fixture ile test edilmelidir.

## Tessellation ve attributes

GLB zaten render edilebilir triangle topology ve attributes taşır. Viewer:

- triangle üretmez
- UV unwrap yapmaz
- source DCC verisini yeniden kurmaz

Texture için UV yoksa hata/diagnostic verir. Normal/tangent eksikliği upstream importer/shader capability olarak raporlanır; viewer repair yapmaz.
