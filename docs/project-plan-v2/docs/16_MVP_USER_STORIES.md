# 16 — MVP User Stories ve Acceptance

## Network model

Given geçerli bir HTTPS GLB URL
When viewer açılır
Then download progress görünür
And model viewer-controlled lighting ile kadraja alınır
And ready callback model info döndürür

## Assembly tree

Given mesh taşımayan parent/sub-assembly nodes içeren GLB
When parts listelenir
Then hierarchy korunur
And assembly ve part adresleri deterministiktir
And duplicate names çakışmaz

## Runtime PBR

Given PBR material taşıyan bir part
When metallic ve roughness patch edilir
Then sadece hedef primitive değişir
And sonraki frame'de görünür
And reset original değerlere döner

## Runtime texture

Given UV0 taşıyan bir part
When network PNG/JPEG base-color texture atanır
Then texture decode/upload edilir
And hedef primitive'e uygulanır
And aynı texture tekrar kullanılırsa cache devreye girer

## Missing UV

Given UV taşımayan bir part
When texture atanır
Then geometri için otomatik unwrap yapılmaz
And typed MissingUvSet sonucu döner
And mevcut material korunur

## Shared material

Given iki primitive aynı material instance'ını paylaşıyor
When yalnızca biri patch edilir
Then diğer primitive değişmez

## Picking

Given kullanıcı bir primitive üzerine tap eder
When raycast hit oluşur
Then callback stable PartAddress döndürür

## State restore

Given material/camera/visibility override'ları
When route kapanıp yeniden açılır
Then ViewerState descriptor'ları uygulanır
And StateApplyReport sonucu gösterir

## Adaptive render

Given model ve kamera statik
When idle threshold geçer
Then sürekli frame üretimi durur
When texture veya camera değişir
Then gerekli frame yeniden çizilir

## Safety

Given A modeli yüklenirken source B olur
When A daha geç tamamlanır
Then A scene'e attach edilmez
And B current model olarak kalır
