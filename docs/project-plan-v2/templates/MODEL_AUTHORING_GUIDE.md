# Model Authoring Guide Template

For reliable V1 behavior:

- Export glTF 2.0 single-file GLB.
- Use triangle mesh topology.
- Preserve meaningful node hierarchy for assembly/sub-assembly/part selection.
- Give nodes helpful names, but do not rely on names being unique.
- Include `TEXCOORD_0` for every primitive that needs runtime texture replacement.
- Include suitable normals; validate normal-map appearance in target viewer.
- Use standard metallic-roughness PBR.
- Keep texture dimensions within the documented limit.
- Avoid unsupported glTF extensions or check the capability matrix.
- Apply/verify transforms and orientation in a reference glTF viewer before shipping.
- Do not expect the viewer to create UVs, tessellate CAD, repair meshes, or infer DCC axes.

Recommended preflight:

- Khronos glTF Validator
- gltf.report or equivalent inspection
- Test on Android/iOS/web capability matrix
