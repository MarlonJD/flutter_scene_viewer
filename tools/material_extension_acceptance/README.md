# Material Extension Acceptance Corpus

This folder defines the real-asset acceptance corpus required before glass and
clearcoat can be treated as production support for the repo-owned custom shader
backend.

The manifest is intentionally metadata-first. The listed GLBs are not vendored
in this repository. Test or release tooling must explicitly stage each asset,
record its exact source, and write target evidence before expanding production
wording beyond the verified target scope.

## Required Roles

- `glass_only`: exercises `KHR_materials_transmission`,
  `KHR_materials_ior`, and `KHR_materials_volume`.
- `clearcoat_only`: exercises `KHR_materials_clearcoat`.
- `combined_glass_clearcoat`: exercises authored glass and clearcoat in one
  real asset.

## Source And License

The initial corpus points to Khronos glTF Sample Models entries:

- `GlassVaseFlowers` for alpha-blend versus transmission/volume behavior.
- `ClearCoatCarPaint` for clearcoat over a rougher car-paint base material.
- `ToyCar` for combined glass and clearcoat.
- `ClearCoatTest` for clearcoat-only behavior.
- `TransmissionTest` for glass/transmission behavior.

The manifest records the source URL, license, vendoring status, required glTF
extensions, reference viewer URL where applicable, and minimum evidence for
each asset. If a future run downloads or vendors any asset, update
`manifest.json` with the local path and exact revision or content hash before
using it as release evidence.

The `fixtures/` files are small tracked inputs for the comparator unit test.
They mirror the reviewed iOS Simulator and reference-renderer metrics without
depending on ignored `tools/out/` artifacts being present in every checkout.

## Evidence Rules

Passing the manifest coverage test only proves the corpus roles are defined.
Production promotion for the current scope requires
`backendKind: flutterSceneCustomShader` iOS Simulator metrics, three.js or
Khronos Sample Viewer directional reference comparison, and clear evidence
labels for any target beyond iOS Simulator. Physical iOS remains not run until
device evidence is collected.
