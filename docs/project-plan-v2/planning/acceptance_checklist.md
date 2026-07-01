# Acceptance Checklist — v2

## M0 feasibility

- [ ] Exact Flutter revision recorded.
- [ ] Exact flutter_scene version/commit recorded.
- [ ] Upstream API audit written.
- [ ] Network GLB visible on Android real device.
- [ ] Network GLB visible on second platform.
- [ ] Roughness runtime mutation visible.
- [ ] Base-color texture runtime mutation visible.
- [ ] Hierarchy and raycast inspected.
- [ ] One-shot/adaptive repaint strategy proven or upstream blocker documented.
- [ ] No engine/shader rewrite introduced.

## Loader/session

- [ ] Asset/network/bytes sources.
- [ ] Streaming progress.
- [ ] Timeout/redirect/max bytes.
- [ ] GLB header validation.
- [ ] Typed errors.
- [ ] Stale A cannot replace B.
- [ ] Dispose during load safe.

## Assembly/parts

- [ ] Transform-only nodes preserved.
- [ ] Node child-index paths deterministic.
- [ ] Duplicate names supported.
- [ ] Multiple primitives separately addressable.
- [ ] Shared material usage detected.
- [ ] Model fingerprint scopes addresses.

## Lighting/camera/interaction

- [ ] Viewer studio lighting preset.
- [ ] Environment intensity/exposure/background.
- [ ] Camera auto-fit.
- [ ] Orbit/pan/zoom.
- [ ] Explicit root transform.
- [ ] Raycast returns PartAddress.
- [ ] Part and assembly visibility.

## Material

- [ ] PBR capabilities inspected.
- [ ] Original snapshots immutable.
- [ ] Copy-on-write.
- [ ] Base color/metallic/roughness/emissive patches.
- [ ] Partial patch merge.
- [ ] Reset part/reset all.
- [ ] Shared-material fixture passes.
- [ ] Alpha/double-sided preserved.

## Texture

- [ ] Asset/network/bytes texture.
- [ ] Bounded decode/upload.
- [ ] UV missing typed failure.
- [ ] Previous material preserved on failure.
- [ ] Coalesced duplicate requests.
- [ ] Ref-count/LRU cache.
- [ ] Last-write-wins.
- [ ] Clear/reset.
- [ ] Slot color-space semantics documented.

## Scheduler

- [ ] Render reasons modeled.
- [ ] One-shot frame.
- [ ] Gesture/inertia frames.
- [ ] Idle ticker stopped.
- [ ] Lifecycle pause/resume.
- [ ] Idle frame count test.

## State/cache

- [ ] Versioned ViewerState.
- [ ] No GPU objects/secrets serialized.
- [ ] StateApplyReport.
- [ ] Disk model cache validators.
- [ ] Route reopen example.

## Hardening/release

- [ ] Malformed/oversized tests.
- [ ] Repeated load/unload stress.
- [ ] Repeated texture swap stress.
- [ ] Orientation and visual fixtures.
- [ ] Android/iOS/web capability matrix.
- [ ] Benchmark metadata reproducible.
- [ ] No unsupported performance claims.
- [ ] Preview/community disclaimer.
- [ ] Model authoring guide.

## Scope guard

- [ ] No tessellation/UV unwrap/tangent generator.
- [ ] No custom PBR GLSL in MVP.
- [ ] No skeletal/morph feature in MVP.
- [ ] No embedded camera/KHR lights in MVP.
- [ ] No compression extension in MVP.
- [ ] No VR/AR/physics/parallax/displacement scope creep.
