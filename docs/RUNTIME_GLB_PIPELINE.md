# Runtime GLB pipeline

## MVP flow

```text
ModelSource
  ↓
ModelLoader downloads/reads bytes
  ↓
flutter_scene Node.fromGlbBytes
  ↓
Viewer builds PartRegistry from node hierarchy
  ↓
Viewer applies initial overrides
  ↓
Scene is rendered through SceneView
```

## What the viewer must not do

- no tessellation of STEP/DWG/IGES/CAD;
- no UV unwrap;
- no tangent generation in v1;
- no custom shader generation;
- no imported glTF light/camera handling in v1.

## Diagnostics

Report these explicitly:

- missing UVs when a texture override is requested;
- unsupported material/extension;
- ambiguous node path;
- missing primitive index;
- model exceeds configured size limits;
- network timeout or cache failure.

## Security and resource limits

Network models can be hostile or simply too large. MVP should support:

- maximum GLB byte size;
- timeout;
- optional allowed hostnames;
- cancellation;
- texture dimension limit;
- memory-budget-aware texture cache.
