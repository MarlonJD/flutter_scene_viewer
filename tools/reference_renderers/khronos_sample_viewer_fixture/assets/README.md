# Khronos Sample Renderer resources

`lut_sheen_E.png` is copied byte-for-byte from KhronosGroup/glTF-Sample-Renderer
revision `d59d1d612ab6a6c242ff561b753fd4623a0ee4bd`, the source revision recorded
by the exact `@khronosgroup/gltf-viewer@1.1.0` package.
The identical bytes are retained by the current source-pinned renderer revision
`bec106e53da4a6a398aa3205f0f96563519a657e` used by the Plan 018 comparison.

- Source:
  <https://github.com/KhronosGroup/glTF-Sample-Renderer/blob/d59d1d612ab6a6c242ff561b753fd4623a0ee4bd/assets/images/lut_sheen_E.png>
- Current pinned source:
  <https://github.com/KhronosGroup/glTF-Sample-Renderer/blob/bec106e53da4a6a398aa3205f0f96563519a657e/assets/images/lut_sheen_E.png>
- SHA-256:
  `7f21d7754dd3a2a972d9d1298ee3e67e20c5b2f21969095d322a1bc20f8b2f04`
- License: Apache-2.0, inherited from the source repository
  [LICENSE.md](https://github.com/KhronosGroup/glTF-Sample-Renderer/blob/d59d1d612ab6a6c242ff561b753fd4623a0ee4bd/LICENSE.md).

The published npm tarball omits this resource although its environment loader
requires it. It is staged only for the pinned reference harness. It is not a
viewer runtime asset and is not used by the package-local Flutter shader.
