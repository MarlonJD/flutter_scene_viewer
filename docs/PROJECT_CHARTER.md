# Project charter

## One-sentence motivation

`flutter_scene_viewer` exists to provide a Flutter-native, WebView-free,
production-oriented GLB viewer/configurator SDK on top of `flutter_scene`.

## Why this package exists

`flutter_scene` is an engine-level API. It exposes scene graph, materials,
GLB runtime import, rendering, raycasting, and Flutter GPU/Impeller integration.
Application developers still need a higher-level product viewer layer:

- load a GLB from a URL;
- show progress and errors;
- fit the camera;
- list parts in the model hierarchy;
- select parts by tap/raycast;
- change PBR material properties and textures at runtime;
- reset original materials;
- persist overrides and reapply them;
- avoid rendering forever when the scene is idle.

This package supplies that layer.

## Competitive positioning

This package should not claim raw performance superiority over Filament or
`interactive_3d` without benchmark evidence.

It differs by aiming for:

- one Flutter/Dart viewer API across Android, iOS, and web;
- one `flutter_scene` scene/material model rather than Android Filament + iOS SceneKit;
- assembly-aware node hierarchy and stable part addressing;
- Flutter-native composition instead of WebView/PlatformView-first integration;
- serializable configurator state and diagnostics.

## Non-goal sentence

This is not Unity, Unreal, BabylonJS, or a CAD tessellation pipeline. If a user
needs complex VR materials, physics, deformation, or authored game scenes, they
should use a dedicated 3D engine.
