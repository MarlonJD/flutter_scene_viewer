# Risks

## Flutter GPU / flutter_scene maturity

`flutter_scene` and Flutter GPU may require master-channel Flutter and may have
API changes. Keep adapters isolated.

## Performance claims

Do not claim superiority over other viewers until benchmarked.

## Runtime import jank

Large GLB parsing and texture decode may block or jank. Mitigate with size
limits, progress UI, caching, and future isolate/offline preprocessing.

## Material completeness trap

glTF material extensions are open-ended. Keep v1 to core PBR and expose extension
points later.

Transmission/glass is the exception now tracked as a v1.0 release blocker. It
must wait for real upstream `flutter_scene` support for transmission/refraction,
IOR, and volume attenuation; alpha blending is not an acceptable substitute.

Clearcoat is also a v1.0 release blocker for automotive, varnished, and coated
product materials. It must wait for real clearcoat support; lowering base
roughness is not an acceptable substitute.

## Asset authoring quality

Many GLBs have missing UVs, duplicate names, huge textures, or unsupported
extensions. The viewer should provide diagnostics and authoring guidance.
