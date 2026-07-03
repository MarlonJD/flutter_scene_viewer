# Test fixtures

## Box.glb

Source:
https://github.com/KhronosGroup/glTF-Sample-Models/tree/main/2.0/Box

Downloaded file:
https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/main/2.0/Box/glTF-Binary/Box.glb

Attribution:
The Box model was donated by Cesium for glTF testing.

License:
Creative Commons Attribution 4.0 International.

## MultiMaterialAssembly.glb

Source:
Generated in-repo by `tools/generate_multi_material_fixture.py`.

Contents:
A compact static GLB with one assembly root, three mesh child nodes, authored
normals and UVs, and three core glTF metallic-roughness materials. It exists to
smoke-test viewer camera framing and material readability beyond the simple
single-material `Box.glb`.

License:
Project fixture, available under the repository license.

## SkylightTable.glb

Source:
Generated in-repo by `tools/generate_skylight_fixture.py`.

Contents:
A compact static GLB with one assembly root and three mesh child nodes:
`Table`, `UpperObject`, and `LowerObject`. It exists for visual smoke checks
that distinguish environment/skylight readability from HDRI reflection. With
studio key-light shadows enabled and the key light directly overhead
(`keyLightDirection: [0, -1, 0]`), the lower object should read slightly darker
than the upper object while still remaining visible from the environment/IBL
term.

License:
Project fixture, available under the repository license.
