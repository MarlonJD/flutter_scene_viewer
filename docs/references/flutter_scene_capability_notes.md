# flutter_scene capability notes

This file records assumptions that the adapter must verify against the installed
`flutter_scene` version.

Known target capabilities:

- runtime GLB import through `Node.fromGlbBytes`;
- PBR material class with base color, metallic, roughness, normal, emissive,
  occlusion, alpha, and double-sided controls;
- SceneView widget for rendering;
- raycasting through scene geometry;
- Flutter GPU/Impeller native rendering and WebGL2 web backend.

Adapter implementation must keep direct `flutter_scene` imports isolated so API
breakage is easy to repair.
