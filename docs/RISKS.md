# Risks

## Flutter GPU / flutter_scene maturity

`flutter_scene` and Flutter GPU may require master-channel Flutter and may have
API changes. Keep adapters isolated.

## Performance claims

Do not claim superiority over Filament or `interactive_3d` until benchmarked.

## Runtime import jank

Large GLB parsing and texture decode may block or jank. Mitigate with size
limits, progress UI, caching, and future isolate/offline preprocessing.

## Material completeness trap

glTF material extensions are open-ended. Keep v1 to core PBR and expose extension
points later.

## Asset authoring quality

Many GLBs have missing UVs, duplicate names, huge textures, or unsupported
extensions. The viewer should provide diagnostics and authoring guidance.
