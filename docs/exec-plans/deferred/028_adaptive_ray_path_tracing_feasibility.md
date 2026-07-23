# Adaptive Ray/Path-Tracing Feasibility and Auto Quality Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Use the
> repo-local `pbr-materials` skill for transport, material, lighting, renderer,
> and evidence decisions. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Status (2026-07-19): deferred, research-only, and fork-free.** Numeric
> order places this after Plans 018-027 in the V3 research lane. This plan does
> not activate ray/path tracing, add a viewer capability, create a permanent
> sibling package, or authorize an upstream PR. Activation requires explicit
> promotion after the current active plan is complete.

**Goal:** Determine whether hardware-assisted progressive ray/path tracing can
improve static-product glass and nested-volume views on capable mobile devices,
switch safely from the existing raster renderer only while idle, and produce a
clean direct-upstream path without maintaining a `flutter_scene` fork.

**Architecture:** Start with an unpublished Flutter lab application under
`tools/raytracing_lab/`, not a `flutter_scene_viewer_raytracing` package and not
the root viewer library. The lab owns an isolated native Metal-first renderer,
fixed test-scene ingestion, progressive accumulation, capability probes, and
measurement UI while the production viewer and pinned `flutter_scene` remain
unchanged. If and only if the measured result is GO, write an upstream
`flutter_scene` renderer-seam proposal and a separately approved implementation
plan; a temporary sibling plugin is considered only when product integration
is explicitly required before upstream availability.

**Tech Stack:** Dart 3, Flutter, pinned `flutter_scene`
`5dcf6fce7dc36719e64e536faba9538fe9fa1022`, iOS Metal acceleration
structures and Flutter texture interop, Android Vulkan ray-query/ray-tracing
capability probes after the iOS gate, Objective-C++, Kotlin/JNI/C++ where
reached, glTF 2.0 metallic-roughness plus IOR/transmission/volume inputs,
deterministic image metrics, Xcode GPU capture, Instruments, and the existing
repository evidence conventions.

## Global Constraints

- Do not fork `flutter_scene`, edit pub-cache, add a path override, or change
  the root dependency pin during Plan 028 research.
- Do not create `packages/flutter_scene_viewer_raytracing` or another permanent
  sibling package in Tasks 1-7.
- Do not convert the root `flutter_scene_viewer` package into an iOS/Android
  plugin and do not add ray-tracing native code under the root package.
- Keep every executable prototype under `tools/raytracing_lab/`; it is an
  unpublished lab application and never becomes a transitive dependency of
  `flutter_scene_viewer`.
- Keep the existing raster `flutter_scene` path authoritative for production,
  camera interaction, part hierarchy, picking, material overrides, diagnostics,
  and fallback behavior throughout the research plan.
- Do not describe a full-screen fragment shader, screen-space ray march, depth
  reconstruction, or software BVH traversal as hardware ray tracing.
- Do not claim physically complete glass, caustics, nested media, multi-bounce
  refraction, or path tracing from a reflection-only or one-bounce prototype.
- A hardware capability bit is necessary but insufficient. Automatic
  eligibility requires the fixed microbenchmark, memory, thermal, latency, and
  visual gates in this plan.
- Unsupported devices, failed probes, failed benchmarks, low-power mode,
  serious/critical thermal state, renderer errors, camera interaction, scene
  mutation, or stale accumulation always select the raster path.
- Do not expose sample count, bounce count, BVH layout, denoiser choice, shader
  table layout, or acceleration-structure details as viewer material API knobs.
- Web remains raster/diagnostic-only in this research plan. Do not emulate a
  production path tracer in WebGL2.
- Do not make Plan 028 a V1/V2 release blocker and do not alter Plans 015-017
  capability or release evidence.
- Use the literal evidence labels `verified locally`, `not run`, `blocked`,
  `candidate-only`, `release pending`, and `production-ready`.
- This plan authorizes no branch, commit, push, dependency-pin change, upstream
  publication, PR, or GitHub write. Obtain explicit approval for each remote or
  dependency action in the execution turn.

---

## Source-Backed Baseline

- The pinned `flutter_scene` native renderer uses Flutter GPU/Impeller and its
  web renderer uses WebGL2. The pinned source contains no ray/path-tracing
  renderer, ray-tracing capability contract, or acceleration-structure API.
- `CustomRenderPass` exposes read-only color/depth/normal/shadow textures,
  object masks, and a full-screen fragment-shader step. Its context explicitly
  keeps command-buffer and pipeline creation inside the engine. It therefore
  supports screen-space research but cannot issue Metal/Vulkan hardware
  ray-tracing work.
- Current imported geometry retains private CPU copies for raycasting but does
  not expose a stable public scene snapshot containing every triangle, index,
  transform, material, texture, light, and volume boundary needed by an
  external path tracer.
- The root package is currently a pure Flutter package. Adding platform folders
  to it would impose native integration on every consumer, including devices
  and targets that cannot use ray tracing.
- The project architecture requires the viewer to adapt `flutter_scene`, not
  become a replacement renderer. The roadmap already limits ray/path tracing
  to V3 research/reference work until target evidence and an upstream-compatible
  renderer design exist.
- Existing Plan 016 transmission is renderer-native bounded screen-space
  transport with positive-volume support. It remains the production raster
  baseline and must not be weakened or relabeled by Plan 028.

## Ownership Boundaries

| Boundary | Owner during Plan 028 |
| --- | --- |
| Production scene graph, raster rendering, picking, and materials | Pinned `flutter_scene` plus existing viewer adapter |
| Research fixtures, native tracer, accumulation, and measurement UI | `tools/raytracing_lab/` only |
| Capability and benchmark observations | Lab-native bridge and tracked evidence manifest |
| Public viewer API | Unchanged during Tasks 1-7 |
| Permanent renderer seam | Future upstream `flutter_scene` work after GO and explicit approval |
| Optional temporary product integration | Separate decision; not pre-authorized and not created by this plan |
| Production/release maturity | Existing raster path; ray/path tracing remains `candidate-only` |

## Planned Research Files

The following paths are created only when Plan 028 is explicitly activated:

- Create `tools/raytracing_lab/README.md` with build, device, fixture, metric,
  and cleanup instructions.
- Create `tools/raytracing_lab/pubspec.yaml` and
  `tools/raytracing_lab/lib/main.dart` as an unpublished Flutter lab app.
- Create `tools/raytracing_lab/lib/src/lab_capability.dart`,
  `lab_bridge.dart`, `lab_decision.dart`, and `lab_metrics.dart` for the
  lab-only Dart contract.
- Create `tools/raytracing_lab/ios/Runner/RayTracingLabPlugin.h/.mm`,
  `RayTracingLabRenderer.h/.mm`, and `RayTracingKernels.metal` for Metal
  capability, acceleration, tracing, accumulation, and Flutter texture output.
- Create
  `tools/raytracing_lab/ios/RunnerTests/RayTracingLabPluginTests.mm` for iOS
  host contract/lifecycle coverage.
- Create
  `tools/raytracing_lab/android/app/src/main/kotlin/com/marlonjd/raytracing_lab/RayTracingLabPlugin.kt`,
  `tools/raytracing_lab/android/app/src/main/cpp/CMakeLists.txt`,
  `VulkanRayTracingLab.h`, `VulkanRayTracingLab.cpp`, and
  `ray_tracing_lab_jni.cpp` only after the iOS GO gate authorizes the Android
  feasibility slice.
- Create
  `tools/raytracing_lab/android/app/src/test/kotlin/com/marlonjd/raytracing_lab/RayTracingLabPluginTest.kt`
  and
  `tools/raytracing_lab/android/app/src/androidTest/kotlin/com/marlonjd/raytracing_lab/RayTracingLabDeviceTest.kt`
  only with that authorized Android slice.
- Create `tools/raytracing_lab/fixtures/generate_raytracing_fixtures.py` and
  tracked fixture manifests; generated GLBs and captures remain under ignored
  `tools/out/plan028_raytracing/`.
- Create `tools/raytracing_lab/test/` contract and decision tests plus the
  exact native host/device harnesses listed above.
- Create `docs/design-docs/flutter_scene_ray_tracing_upstream_seam.md` only
  after a GO decision; it is a proposal, not an implemented API.
- Modify `docs/ROADMAP.md`, `docs/MATERIALS_AND_LIGHTING.md`, and capability
  documentation only at Plan 028 closure, preserving research/maturity labels.

No root `lib/`, root `ios/`/`android/`, root public API, or sibling package file
is part of the initial research implementation.

## Lab-Only Contracts

These names are internal to the lab and must not be exported by
`flutter_scene_viewer`:

```dart
enum RayTracingLabSupport {
  unavailable,
  supportedUnbenchmarked,
  benchmarkEligible,
}

final class RayTracingLabCapability {
  const RayTracingLabCapability({
    required this.support,
    required this.backend,
    required this.deviceName,
    required this.reason,
    required this.featureSet,
  });

  final RayTracingLabSupport support;
  final String backend;
  final String deviceName;
  final String reason;
  final Map<String, Object?> featureSet;
}

enum RayTracingLabMode {
  rasterInteractive,
  rayTracingWarmup,
  progressiveIdle,
  rasterCooldown,
  unavailable,
}

final class RayTracingLabDecision {
  const RayTracingLabDecision({
    required this.mode,
    required this.reason,
    required this.benchmarkHash,
  });

  final RayTracingLabMode mode;
  final String reason;
  final String? benchmarkHash;
}
```

The native bridge uses exactly these lab methods during the research slice:

```text
getRayTracingCapability() -> capability map
loadFixture({fixturePath, fixtureSha256}) -> immutable scene summary
startBenchmark({width, height, warmupFrames, measuredFrames}) -> metrics map
startProgressiveRender({width, height, cameraStateHash, sceneStateHash, materialStateHash, lightStateHash, exposureStateHash}) -> texture id
updateRenderState({cameraStateHash, sceneStateHash, materialStateHash, lightStateHash, exposureStateHash, viewMatrix, projectionMatrix}) -> reset result
stopProgressiveRender({reason}) -> stopped result
getRayTracingMetrics() -> latest metrics map
```

Every native reply includes `status`, `backend`, `device`, `requestId`, and a
typed `reason`. A stale `requestId`, fixture hash, or camera/scene/material/
light/exposure state hash invalidates accumulation before presentation.

## Milestones and Execution Order

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: fork-free lab boundary | 1-2 | A standalone unpublished lab probes support without changing root/upstream packages. |
| M2: deterministic transport fixture | 3 | Exact static geometry/material/volume inputs and raster/reference states are reproducible. |
| M3: Metal feasibility | 4 | A physical capable iOS device builds acceleration structures and progressively renders the fixed corpus. |
| M4: adaptive eligibility | 5 | Capability, benchmark, interaction, thermal, and stale-state rules select or reject the candidate deterministically. |
| M5: second-target audit | 6 | Android is measured only after iOS GO; unsupported targets remain explicit raster fallbacks. |
| M6: decision and handoff | 7-8 | Evidence yields GO/NO-GO and, only on GO, a direct-upstream design proposal. |

## Task 1: Freeze Fork-Free RED Boundaries

**Files:**

- Create: `tools/raytracing_lab/pubspec.yaml`
- Create: `tools/raytracing_lab/test/repository_boundary_test.dart`
- Create: `tools/raytracing_lab/test/lab_contract_test.dart`
- Read: root `pubspec.yaml`, `pubspec.lock`, `.dart_tool/package_config.json`
- Read: pinned `flutter_scene` `scene.dart`, `custom_render_pass.dart`,
  geometry, material, runtime importer, and render-graph sources

- [ ] Create the minimal unpublished lab test scaffold with `publish_to: none`;
  it must contain no application/platform implementation yet.
- [ ] Write a repository-boundary test that hashes the root dependency stanza,
  asserts there is no root plugin declaration, rejects any path dependency,
  rejects writes under pub-cache, and rejects a
  `packages/flutter_scene_viewer_raytracing` directory.
- [ ] Write lab contract tests for every capability state, bridge reply field,
  stale request/camera/material hash, unsupported target, low-power mode,
  thermal rejection, benchmark rejection, and stop idempotency.
- [ ] Record the exact pinned Flutter, engine, `flutter_scene`, Xcode, Metal,
  iOS SDK, and physical-device identities before native work.
- [ ] Run `flutter test` inside `tools/raytracing_lab`; expect RED compile/test
  failures for the deliberately absent lab contracts and bridge only. Root
  package tests must not be changed to satisfy this RED.

## Task 2: Create the Standalone Lab and Capability Probes

**Files:**

- Create the lab Dart files and iOS Runner bridge listed under Planned
  Research Files.
- Test: `tools/raytracing_lab/test/lab_capability_test.dart`
- Test: `tools/raytracing_lab/ios/RunnerTests/RayTracingLabPluginTests.mm`

- [ ] Expand the unpublished test scaffold into a Flutter application; it may
  depend on the root package for raster comparison but must not be a root
  dependency or exported package.
- [ ] Implement `getRayTracingCapability()` on iOS using the selected
  `MTLDevice` and its public ray-tracing capability properties. Return
  `unavailable` rather than throwing when no eligible device exists.
- [ ] Return Simulator as `unavailable` for hardware-target claims even if
  compilation succeeds; Simulator results may validate UI/bridge shape only.
- [ ] Add fake-bridge Dart tests and native capability tests covering supported,
  unsupported, missing device, malformed reply, duplicate request, detach, and
  reattach.
- [ ] Run lab tests plus an iOS Simulator build. Expected: contract/build pass,
  capability is unavailable on Simulator, physical performance remains
  `not run`, and root `pubspec.yaml`/pin stay byte-identical.

## Task 3: Build Deterministic Scene Inputs and Reference States

**Files:**

- Create: `tools/raytracing_lab/fixtures/generate_raytracing_fixtures.py`
- Create: `tools/raytracing_lab/fixtures/fixtures.json`
- Create: `tools/raytracing_lab/lib/src/lab_scene_snapshot.dart`
- Test: `tools/raytracing_lab/test/lab_scene_snapshot_test.dart`

- [ ] Generate a triangle-only opaque control, a single closed glass volume in
  front of a black/white stripe field, and a nested air/glass/water/probe
  fixture whose straight probe visibly changes direction at interfaces.
- [ ] Store generator source, material factors, IOR values, transforms,
  topology counts, extension declarations, expected bounds, and SHA-256 hashes
  in `fixtures.json`; generated binary GLBs remain reproducible outputs.
- [ ] Define an immutable lab snapshot containing positions, indices, normals,
  UV0, node/world transforms, material/texture references, alpha/double-sided
  state, IOR, transmission, thickness, attenuation, and closed-volume ids.
- [ ] Reject animation, skinning, morphs, lines/points, unsupported compression,
  external URIs, UV1-only required slots, malformed volumes, and mutable scene
  updates with typed lab diagnostics rather than partial tracing.
- [ ] Capture fixed raster `flutter_scene` and pinned reference-renderer states
  with identical camera, transform, HDRI/direct light, exposure, tone mapping,
  resolution, and output color space.
- [ ] Run generator determinism, glTF validation, snapshot parser, and fixture
  hash tests. Expected: byte-identical outputs and no unrecorded fixture input.

## Task 4: Prove Physical-iOS Metal Ray/Path-Tracing Feasibility

**Files:**

- Create/modify the iOS renderer and Metal files listed under Planned Research
  Files.
- Test: native deterministic intersection/material tests and a physical-device
  lab integration test.

- [ ] Build bottom- and top-level acceleration structures from the immutable
  snapshot and record build time, scratch bytes, persistent bytes, triangle
  count, instance count, and rebuild/refit behavior.
- [ ] Implement progressive camera rays, closest-hit/miss handling, environment
  lighting, base metallic-roughness response, dielectric Fresnel, transmission,
  IOR boundaries, volume attenuation, and an internal fixed maximum of eight
  transport events for the research corpus.
- [ ] Keep accumulation in linear HDR, reset it on every camera/viewport/scene/
  material/light/exposure state hash change, and tone-map only for presentation.
- [ ] Publish the lab result through a Flutter texture without blocking the UI
  thread and without changing the production `flutter_scene` surface.
- [ ] Test opaque control equivalence, single-glass stripe displacement,
  nested-water probe displacement, total-internal-reflection stability, camera
  reset, resize, background/foreground lifecycle, device loss, and allocation
  cleanup.
- [ ] Label all results `candidate-only`. A visually convincing frame without
  physical-device timings, memory, state-reset, and lifecycle evidence does not
  satisfy this task.

## Task 5: Implement and Measure the Lab Auto-Quality State Machine

**Files:**

- Create: `tools/raytracing_lab/lib/src/lab_auto_policy.dart`
- Create: `tools/raytracing_lab/test/lab_auto_policy_test.dart`
- Modify: lab UI and native metrics bridge

- [ ] Implement the explicit state sequence
  `rasterInteractive -> rayTracingWarmup -> progressiveIdle`, with immediate
  transitions to `rasterCooldown` or `unavailable` on any rejection condition.
- [ ] Require 500 ms of unchanged camera/scene/material/light state before
  warmup; any pointer input or state change returns to raster within one
  display refresh and discards the old accumulation hash.
- [ ] Disable eligibility when low-power mode is active or thermal state is
  serious/critical; require 30 seconds of nominal/fair thermal state before one
  retry.
- [ ] Run 16 warmup frames and 120 measured frames at 1280x720. Record median,
  p95, first-sample latency, accumulation rate, UI-thread stalls, peak/persistent
  bytes, energy/thermal state, and fallback latency.
- [ ] The initial research GO threshold requires: first presented sample within
  250 ms; no main-thread stall above 16.7 ms caused by the tracer; raster
  fallback within one display refresh; tracer memory no more than 256 MiB and
  no more than 25% of physical memory; no serious/critical thermal state during
  a five-minute fixed-scene run; and deterministic cleanup back to baseline.
- [ ] Compare progressive output to the fixed high-sample reference using
  recorded linear-HDR and display-space metrics. Store the complete metric
  series; do not promote a hand-selected screenshot.
- [ ] Test every transition with a fake clock/thermal/power/metric source and
  run the physical-device benchmark three cold launches. A device is eligible
  only when all three runs pass every threshold.

## Task 6: Audit Android/Vulkan Only After the iOS Gate

**Files:**

- Create Android lab files listed under Planned Research Files only when Task 5
  records iOS GO.
- Test: Android host/device capability and lifecycle harnesses.

- [ ] If iOS is NO-GO, record Android as `not run` with the re-evaluation trigger
  and skip Android implementation; this is a valid Plan 028 outcome.
- [ ] If iOS is GO, probe the required Vulkan acceleration-structure and
  ray-query/ray-tracing features, limits, memory types, queue support, and
  driver identity before creating resources.
- [ ] Reuse the same lab snapshot, fixture hashes, state hashes, benchmark
  dimensions, thresholds, and lifecycle tests. Platform-specific differences
  stay behind the lab bridge.
- [ ] Treat missing extensions, insufficient limits, allocation failure, driver
  error, or failed benchmark as raster fallback rather than app failure.
- [ ] Record Android capability and performance per physical device. Do not
  infer one vendor/device result from another and do not claim Web parity.

## Task 7: Make the GO/NO-GO and Upstream Decision

**Files:**

- Create: `tools/raytracing_lab/evidence/plan028_decision.json`
- Create on GO only:
  `docs/design-docs/flutter_scene_ray_tracing_upstream_seam.md`
- Modify: this plan's Progress and Verification logs

- [ ] Produce one decision record containing source/fixture hashes, SDK and
  device identities, capability results, all benchmark runs, metric thresholds,
  visual comparisons, lifecycle results, unsupported targets, maintenance
  cost, and the literal maturity labels.
- [ ] Return NO-GO when the lab requires root public/native changes, a maintained
  `flutter_scene` fork, a replacement viewer renderer, relaxed correctness
  claims, unstable state synchronization, or unbounded target cost.
- [ ] On GO, propose the smallest upstream `flutter_scene` seam that exposes
  renderer-owned scene snapshots/resources, backend capability, progressive
  output, state invalidation, and raster fallback without leaking ray-tracing
  implementation knobs into viewer material APIs.
- [ ] Keep the upstream proposal implementation-free until the user approves a
  separate Plan 029. Plan 029 owns upstream code, tests, immutable publication,
  viewer pin integration, and production evidence.
- [ ] Do not create a sibling package by default. If upstream timing makes a
  temporary product integration necessary, stop and request a separate decision
  that compares: wait for upstream, create an unpublished temporary plugin, or
  abandon integration. Record removal/migration criteria before creating it.

## Task 8: Documentation, Cleanup, and Closure

**Files:**

- Modify: `docs/ROADMAP.md`
- Modify: `docs/MATERIALS_AND_LIGHTING.md`
- Modify: `docs/references/flutter_scene_capability_notes.md`
- Modify: this plan's logs

- [ ] Document the decision, supported/unsupported targets, exact evidence,
  upstream status, and re-evaluation trigger. Keep the production raster path
  and Plan 016 claims unchanged.
- [ ] Verify the lab leaves no GPU capture process, simulator/device runner,
  Flutter tool, or native test process alive after the documented commands.
- [ ] Run lab unit/native tests, fixture validation, and physical-target evidence
  commands recorded by the manifest.
- [ ] Run `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
  `git diff --check`; expect all repository checks to pass.
- [ ] Closure means a measured GO/NO-GO and an upstream proposal on GO. It does
  not mean ray/path tracing is available, released, or `production-ready`.

## Acceptance Criteria

- [ ] Research runs without a `flutter_scene` fork, pub-cache edit, path
  override, root plugin conversion, dependency-pin change, or permanent
  ray-tracing sibling package.
- [ ] The production viewer and raster renderer remain behaviorally and
  byte-for-byte dependency equivalent throughout Tasks 1-7.
- [ ] Capability detection, benchmark eligibility, state invalidation, thermal/
  power rejection, and raster fallback are deterministic and tested.
- [ ] The physical-iOS corpus proves opaque control, visible single-volume
  refraction, and nested glass/water/probe behavior or records NO-GO honestly.
- [ ] Every visual claim has exact fixture/source/device/state hashes and
  measured target evidence; Simulator/reference captures do not promote it.
- [ ] Android is independently measured only after iOS GO; Web remains an
  explicit raster/diagnostic fallback.
- [ ] GO produces a direct-upstream `flutter_scene` seam proposal and a need
  for separately approved Plan 029; it does not silently create a maintained
  viewer-owned renderer.
- [ ] NO-GO preserves all existing raster behavior and records a concrete
  re-evaluation trigger.

## Progress Log

- 2026-07-19: Created from the V3 research lane as deferred, fork-free, and
  lab-first. No `flutter_scene_viewer_raytracing` package is planned initially.
  Direct upstream work is conditional on measured GO and separate approval;
  implementation and physical-target evidence are `not run`.

## Verification Log

- 2026-07-19: `python3 tools/repo_lint.py` and `git diff --check` passed
  (`verified locally`). `bash tools/run_checks.sh` passed repository lint, Dart
  formatting, dependency resolution, and `flutter analyze`, then finished
  `blocked` by four failures in the concurrent active Plan 017 implementation:
  two native decoder probe expectations, the decoder-control evidence
  fingerprint, and the BasisU provenance hash. No Plan 028 implementation or
  physical-target evidence was run.
- 2026-07-19: Planning review checked the pinned `flutter_scene` public custom-
  pass/geometry boundary, the root pure-package shape, Plan 016 ownership, and
  the roadmap's “do not build a replacement renderer” constraint. No runtime,
  physical-device, upstream, package, or production evidence was run.
