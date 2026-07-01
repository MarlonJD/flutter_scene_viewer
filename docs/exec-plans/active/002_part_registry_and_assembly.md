# Exec plan: part registry and assembly tree

## Goal

Build a registry that maps `flutter_scene` node hierarchy to assembly,
sub-assembly, and part addresses.

## Non-goals

- Do not flatten hierarchy to entity names.
- Do not resolve duplicate names by guessing silently.

## Steps

1. Change: define internal `PartNode`/`PartRecord` model.
   Verify: pure Dart tests for assembly and primitive records.
2. Change: traverse adapter-provided node snapshots.
   Verify: fixture tree tests including dummy parent nodes.
3. Change: detect duplicate/ambiguous paths.
   Verify: diagnostics tests.
4. Change: expose read-only part tree API.
   Verify: controller/widget API tests.

## Acceptance criteria

- [ ] geometrisiz dummy nodes are preserved;
- [ ] `PartAddress(nodePath, primitiveIndex)` resolves correctly;
- [ ] ambiguous paths emit diagnostics;
- [ ] tests cover nested assembly/sub-assembly/part structures.

## Progress log

- 2026-07-01: Plan created.
