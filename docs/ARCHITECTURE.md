# Architecture

## Layering

```text
Flutter app
  ↓
FlutterSceneViewer widget + controller
  ↓
Viewer services
  - model loading
  - part registry
  - material override store
  - texture/model cache
  - render scheduler
  - diagnostics
  ↓
flutter_scene adapter
  ↓
flutter_scene scene graph + materials
  ↓
Flutter GPU / Impeller on native, WebGL2 backend on web
```

## Boundary rule

The viewer layer must not become a renderer. It adapts public `flutter_scene`
capabilities and emits diagnostics when a requested feature is unsupported.

## Assembly model

Inventor-style assembly/sub-assembly/part mapping:

- `Node` with no mesh: assembly/sub-assembly/dummy object.
- `Node` with `MeshComponent`: part or renderable subpart.
- `MeshPrimitive`: one geometry + one material slot.
- `PartAddress`: stable address = `nodePath` + `primitiveIndex`.

This is the core product differentiator. Do not collapse hierarchy into flat
entity names.

## Runtime GLB import

The runtime importer consumes already-tessellated GLB data. The viewer must not
compute CAD tessellation or UV unwraps. It should treat GLB attributes as asset
authoring responsibilities and report diagnostics for missing requirements.
Single-file GLB remains the default v1 target. A bounded multi-file `.gltf`
resolver can be added in v1 when target assets require external `.bin` or image
files, but compression, progressive streaming, and virtual texturing remain
separate features.

## Lighting

V1 uses viewer-controlled lighting:

- environment/IBL preset;
- exposure/tone mapping controls where supported;
- simple directional key light where supported.

Full imported glTF camera/light playback is future work. V1 may report authored
camera and light metadata/diagnostics while continuing to use viewer-controlled
camera and lighting for rendering.

## Rendering policy

Default target is adaptive rendering:

- render while loading;
- render during user interaction;
- render for animations when enabled;
- render a small tail after interaction;
- pause when static;
- force a frame after material/texture changes.

If `flutter_scene` lacks a direct one-shot frame request API, implement the
simplest widget-level invalidation first and document upstream needs.
