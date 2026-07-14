# Meshopt conformance fixtures

This directory contains the minimal files needed to compare the package's
direct Dart Meshopt decoder with the official `MeshoptCubeTest` fallback.
`ATTRIBUTES` and `INDICES` outputs are compared byte-for-byte. `TRIANGLES`
keeps the official triangle order and winding while allowing the three indices
within each triangle to be cyclically rotated, matching the specified decoder
semantics; reversed winding is rejected. This does not make a runtime `.gltf`
or `KHR_meshopt_compression` support claim. The runtime rewrite remains limited
to embedded-GLB `EXT_meshopt_compression`.

The KHR corpus contains both ATTRIBUTES bitstream v0 and v1. Only its v0 bytes
are applicable to the runtime EXT boundary; v1 remains direct-codec oracle
coverage and is not used as evidence for EXT support.

Source: `KhronosGroup/glTF-Sample-Assets`, commit
`2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf`, model `MeshoptCubeTest`.
The `TRIANGLES` comparison was cross-checked against meshoptimizer v1.2
`src/indexcodec.cpp` at commit
`9d9890c73011d75920af614485296d1e03e95448`; that reference source is not
vendored here.

`MeshoptCubeTest/glTF-Meshopt/MeshoptCubeTest.gltf` is a JSON-metadata-only
placeholder fixture. Its relative `MeshoptCubeTest.bin` is intentionally not
duplicated in that directory; the identical compressed binary is vendored only
in the sibling `glTF` corpus used by the direct-codec comparison.

The embedded-GLB runtime rewrite test derives mesh 26 POSITION and NORMAL from
the official v0 ranges in that sibling binary. KHR v0 and EXT v0 use the same
ATTRIBUTES bitstream bytes, so the derivative relabels only its test metadata;
it does not add or claim KHR runtime support.

Fetch and verify with:

```sh
bash tools/fetch_meshopt_conformance_fixtures.sh
```

Tracked files and SHA-256 digests:

| File | SHA-256 |
| --- | --- |
| `MeshoptCubeTest/glTF/MeshoptCubeTest.gltf` | `8721150e3409425acf83aa21986e55880360ab084c17e96409c25fac53477f72` |
| `MeshoptCubeTest/glTF/MeshoptCubeTest.bin` | `6578c1d82c5cc2b228e9513e37f348ca89cdb24b5985aa0567efef8d3c014360` |
| `MeshoptCubeTest/glTF/MeshoptCubeTestFallback.bin` | `8d3d779653780e85a75eda988110ab235ea85cd3d174361ffb318c6b657dee07` |
| `MeshoptCubeTest/glTF-Meshopt/MeshoptCubeTest.gltf` | `b5947609f3d8aba58de3d43101df3b635ffaaab5849431f8518af6a98a040433` |
| `LICENSE.md` | `63fc4b5080289c3640c904dcf5adb3a6122a707928164d7520f46b3051da8ac3` |

The model files are CC0-1.0. Repository metadata and license text are
CC-BY-4.0; see the vendored `LICENSE.md`. No textures are included.
