# Draco conformance fixture

This directory contains the minimal official Khronos `Box` files needed to
compare the package's native bridge with the independently invoked pinned
Google Draco decoder. The compressed buffer view is 118 bytes inside the
120-byte `Box.bin` container and uses Draco bitstream version 2.2. The fixture
declares one `TRIANGLES` primitive with 24 positions, 24 normals, and 36
unsigned-short indices. Its extension attribute IDs deliberately order
`NORMAL` as 0 and `POSITION` as 1.

This is direct-codec and wrapper host evidence only. It is not an Android or
iOS runtime, device, packaging, release, or `production-ready` claim. The
official Khronos sample corpus contains no `TRIANGLE_STRIP` Draco primitive,
and the current bridge returns decoded face-list indices. The wrapper therefore
diagnoses `TRIANGLE_STRIP` before platform-channel invocation instead of
silently retaining an incompatible authored topology.

Source: `KhronosGroup/glTF-Sample-Assets`, commit
`2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf`, model `Box`, variant
`glTF-Draco`.

The decoder under test is the vendored Google Draco 1.5.7 source at commit
`8786740086a9f4d83f44aa83badfbea4dce7a1b5`, licensed under Apache-2.0.

Fetch and verify with:

```sh
bash tools/fetch_draco_conformance_fixtures.sh
```

Tracked files and SHA-256 digests:

| File | SHA-256 |
| --- | --- |
| `Box/glTF-Draco/Box.gltf` | `3c46acecdfa90b012ec9052d8a1dfa61358e6d56a9e333504189cc78a2de4d1b` |
| `Box/glTF-Draco/Box.bin` | `610dc6e08aba7c2720c8e4ec0578efd91cf2d88a5e638dab7811a22f0235bf2e` |
| `Box.bin` buffer view 0, first 118 bytes | `1d5e57c8179d5768bcfcf3fc53da7c1833386b071146236d59eec568a99a9831` |
| `Box/LICENSE.md` | `634623c7bef43aa4b16a3556ac55ae71b671daf4509437d403e4f2a0273928dc` |

The sample is © 2017 Cesium and licensed under CC-BY-4.0; see the vendored
`Box/LICENSE.md`.
