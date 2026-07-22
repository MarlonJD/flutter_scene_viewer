# Pinned Khronos Sample Renderer bundle

`gltf-viewer.module.js` and `libs/mikktspace_bg.wasm` are deterministic build
outputs from the exact Sample Renderer revision pinned by the current Khronos
glTF Sample Viewer source audit.

- Sample Viewer revision:
  `6b4012c8cd58f933565401fbe4404a40380ee0fb`
- Sample Renderer revision:
  `bec106e53da4a6a398aa3205f0f96563519a657e`
- Renderer source archive SHA-256:
  `d96863aa8ccd0cbefc0453290306c2384835bf5dfe52f4078da484d080f11955`
- Renderer package-lock SHA-256:
  `1c15b53288a7dab7cf234bd1d263d65768a1e592df6ce7826e949e597bb1bb97`
- Build command: `npm ci --ignore-scripts`, then `npm run build`
- Bundle SHA-256:
  `ca863c37b8deb6fcaa456e2a59da46311867aab2baf0d15bac48f5239b3a4f4b`
- MikkTSpace WASM SHA-256:
  `d734e040ae6480a0d00ba08b8aaae29c2eb59c8705c38b7bc120885fc94c54e2`
- License: Apache-2.0, inherited from the source repository
  [LICENSE.md](https://github.com/KhronosGroup/glTF-Sample-Renderer/blob/bec106e53da4a6a398aa3205f0f96563519a657e/LICENSE.md).

The bundle is reference-harness input only. It is not linked into the Flutter
package, does not replace the pinned `flutter_scene` dependency, and does not
establish renderer-native or target support.
