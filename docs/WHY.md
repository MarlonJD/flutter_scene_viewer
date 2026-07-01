# Why flutter_scene_viewer exists

Flutter apps need a practical way to show and configure real GLB assets without
leaving the Flutter UI model.

`flutter_scene` exposes the important low-level pieces: scene graph, materials,
GLB runtime import, raycasting, rendering, and Flutter GPU/Impeller integration.
Application developers still need a product viewer layer around those pieces:
load a model, show progress and errors, fit the camera, preserve the part
hierarchy, pick parts, change PBR materials, reset overrides, serialize
configuration state, and avoid rendering forever when nothing is changing.

`flutter_scene_viewer` exists to provide that layer for static GLB
product/medical/industrial models.

## What makes it different

### Compared with WebView-based viewers

Web renderers and JavaScript model viewers are mature, but embedding them in a
Flutter app usually means running a second UI/runtime surface and bridging state
between Dart and JavaScript. That can be the right tradeoff for authored web 3D
experiences, but it is not ideal for a Flutter product configurator whose
buttons, panels, gestures, state, theming, and diagnostics already live in Dart.

`flutter_scene_viewer` keeps the product viewer in Flutter. Through
`flutter_scene`, native rendering is designed around Flutter GPU / Impeller; on
web it follows the `flutter_scene` WebGL2 backend. The point is not "JavaScript
is bad"; the point is one Flutter-first SDK surface.

### Compared with per-platform native viewers

Native 3D stacks can be powerful, but a Flutter package that wraps different
engines per platform often inherits different scene models, material behavior,
gesture behavior, and integration limits. Product configuration code then has
to account for platform-specific differences.

`flutter_scene_viewer` aims for one Dart API across Android, iOS, and web, with
one `flutter_scene` scene/material model and explicit diagnostics when a feature
is unavailable.

### Compared with raw flutter_scene

`flutter_scene` is the engine-level API. It should expose primitives such as
nodes, meshes, materials, textures, raycasting, and render integration.

`flutter_scene_viewer` is the application-facing layer. It provides the
controller, model-loading states, assembly registry, stable part addressing,
material override store, cache behavior, camera controls, picking, visibility,
diagnostics, and render scheduling that product viewers repeatedly need.

### Compared with full 3D engines

This package is not Unity, Unreal, BabylonJS, or a CAD pipeline. It does not
tessellate CAD files, unwrap UVs, simulate physics, author game scenes, or
implement advanced custom shader effects. GLB assets should already be authored
for runtime viewing.

## Performance position

Performance is a design goal, not a benchmark claim.

The architecture is performance-oriented because it avoids a WebView-first
surface, builds on the Flutter GPU/Impeller path exposed by `flutter_scene`,
keeps viewer state in Dart, uses cacheable model/texture resources, and targets
adaptive/on-demand rendering so a static scene can stop requesting frames.

The README should not claim that this package is faster than Filament,
`interactive_3d`, BabylonJS, or any other viewer until the benchmark harness
produces fair evidence. The right claim before benchmarks is that
`flutter_scene_viewer` is Flutter-native, WebView-free, and designed around
Flutter's GPU-backed rendering path.

## Design principles

- Flutter-native API first.
- WebView-free by default.
- High-level viewer layer, not a new renderer.
- Stable assembly and part addressing.
- Serializable configurator state.
- Diagnostics instead of silent fallback behavior.
- Performance claims backed by benchmark reports.
