# flutter_scene_viewer

> Experimental, community-maintained package built on preview `flutter_scene` / Flutter GPU APIs. Not an official Flutter Scene package.

A Flutter-native static GLB viewer and product configurator with network loading, assembly-aware part selection, runtime PBR material/texture overrides, state persistence, and adaptive rendering—without a WebView.

## Why

Use this package when you need:

- network/asset/bytes GLB loading,
- Android, iOS and web-facing common viewer APIs,
- assembly/sub-assembly/part addressing,
- runtime product material configuration,
- Flutter-native composition,
- cache, lifecycle and persistence behavior.

This package is not a game engine, CAD tessellator, VR framework, or universal glTF extension renderer.

## Status

List exact tested Flutter and flutter_scene revisions here.

## Quick start

Add real example after M1–M5.

## Model requirements

- Single-file GLB
- Triangle primitives
- UV0 for runtime image textures
- Standard glTF metallic-roughness PBR
- Reasonable texture/model sizes

## Known non-goals

- skeletal/morph animation in V1
- embedded scene cameras/lights in V1
- Draco/meshopt/KTX2 in V1
- parallax/displacement/VR/AR/physics

## Capability matrix

Insert generated platform matrix.

## Performance

Publish methodology and device-specific results; do not claim general superiority.
