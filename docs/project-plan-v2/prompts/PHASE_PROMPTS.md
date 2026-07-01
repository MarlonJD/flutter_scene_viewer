# Milestone Bazlı Kısa Promptlar

## M0 — Feasibility

Implement M0 only. Pin exact Flutter and flutter_scene revisions, audit real APIs, and create a minimal example proving network GLB load, hierarchy, raycast, runtime roughness, runtime base-color texture, and one-shot/adaptive repaint on Android plus a second platform. Record timings and blockers. Do not create the full package architecture yet.

## M1 — Loader/session

Implement M1. Add package skeleton, ModelSource, typed load state/errors, streaming network loading, GLB header/size validation, and generation-based ViewerSession cancellation. Test stale A/B loads and dispose during load. No camera/material work yet.

## M2 — Assembly/lighting

Implement M2. Add narrow flutter_scene adapter, viewer-controlled studio lighting, deterministic transform-only assembly and primitive registry, duplicate-name-safe addresses, shared-material usage mapping, and baseline diagnostics. No animation or embedded lights/cameras.

## M3 — Camera/picking

Implement M3. Add bounds fit, orbit/pan/zoom, explicit root transform, raycast-to-PartHit, visibility and focus. Preserve hierarchy. Add orientation and duplicate-name tests.

## M4 — Materials

Implement M4. Add PBR capability inspection, immutable snapshots, copy-on-write, partial scalar patch merge, reset/reset-all, and shared-material regression tests. Use upstream PBR materials; no GLSL.

## M5 — Textures

Implement M5. Add TextureSource, bounded decode/upload through upstream helpers, base-color runtime assignment, MissingUvSet behavior, cache coalescing/ref-count/LRU, last-write-wins, and reset. Probe optional slots but expose only proven capabilities.

## M6 — Scheduler

Implement M6. Add render reason state machine, one-shot request frame, gesture/inertia behavior, app lifecycle handling and idle-frame tests. Prefer a minimal upstream PR if SceneView lacks a clean external repaint hook.

## M7 — State/cache

Implement M7. Add versioned ViewerState, model fingerprint, StateApplyReport, disk model cache validators and route reopen example. Never persist GPU objects or secret headers.

## M8 — Hardening/benchmark

Implement M8. Add malformed/oversized tests, lifecycle stress, visual fixtures, profile/release benchmark harness, exact metadata reporting, and fair comparison with interactive_3d and BabylonJS/WebView. Do not make unsupported superiority claims.
