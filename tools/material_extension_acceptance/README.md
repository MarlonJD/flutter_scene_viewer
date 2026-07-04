# Material Extension Acceptance Corpus

This folder defines the real-asset acceptance corpus required before glass and
clearcoat can move from candidate evidence to production support.

The manifest is intentionally metadata-first. The listed GLBs are not vendored
in this repository, and the manifest does not claim evidence has passed. Test
or release tooling must explicitly stage each asset, record its exact source,
and write target evidence before public production wording changes.

## Required Roles

- `glass_only`: exercises `KHR_materials_transmission`,
  `KHR_materials_ior`, and `KHR_materials_volume`.
- `clearcoat_only`: exercises `KHR_materials_clearcoat`.
- `combined_glass_clearcoat`: exercises authored glass and clearcoat in one
  real asset.

## Source And License

The initial corpus points to Khronos glTF Sample Models entries:

- `ToyCar` for combined glass and clearcoat.
- `ClearCoatTest` for clearcoat-only behavior.
- `TransmissionTest` for glass/transmission behavior.

The manifest records the source URL, license, vendoring status, required glTF
extensions, and minimum evidence for each asset. If a future run downloads or
vendors any asset, update `manifest.json` with the local path and exact
revision or content hash before using it as release evidence.

## Evidence Rules

Passing the manifest coverage test only proves the corpus roles are defined.
Production promotion still requires renderer-native iOS Simulator metrics,
three.js directional reference comparison, and physical iOS release evidence.
Package-local shader evidence remains `candidate-only`.
