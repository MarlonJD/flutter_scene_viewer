# Decoder Control, Authored KTX2 Mip Chains, and Release Evidence Implementation Plan

> **Status (2026-07-19): active.** This plan owns the decoder-control,
> authored-mip, cross-platform runtime, packaging, and release-evidence work
> intentionally left outside completed
> [Plan 014](../completed/014_selected_gltf_extension_support.md). It does not
> reopen Plan 014's accepted `FSViewerExtendedPbr` UV/specular/opaque-IOR
> implementation, and it does not absorb renderer-native clearcoat or glass;
> those remain in [Plan 015](../completed/015_renderer_native_clearcoat.md) and
> [Plan 016](../completed/016_renderer_native_transmission_volume.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Use the
> repo-local `pbr-materials` skill whenever texture content roles, color space,
> material slots, or renderer texture boundaries are changed. Steps use
> checkbox (`- [ ]`) syntax for tracking.

## Goal

Finish the remaining production decoder boundary by adding externally
observable load cancellation, cooperative native decoder cancellation and
bounded working allocations, preservation of authored KTX2 mip chains, and
honest physical-target/package evidence without weakening Plan 014's existing
diagnostics or capability labels.

## Architecture

Keep cancellation and resource accounting load-scoped. One public cancellation
token flows from `FlutterSceneViewerController.load` through `ViewerCommandSink`,
`ModelLoader`, the pure-Dart Meshopt decoder, and the optional native decoder
plugins. Every native request carries a unique request id and one monotonic
deadline. Android and iOS execute native codec work off their platform/UI
threads, retain a request registry, and expose an idempotent `cancelDecode`
endpoint. The C++ bridges own the cancellation flag, working-allocation budget,
and result state until the worker exits; Dart may return a typed cancellation
diagnostic early, but a release claim is forbidden until native tests prove
that the codec itself observes cancellation and frees request-owned resources.

Do not preserve authored mip chains by writing only level 0 to PNG and letting
the renderer synthesize new mips. The BasisU plugin must return every selected
KTX2 level with exact dimensions, content role, and raw decoded pixels. The
viewer owns a repo-local authored-mip uploader and post-import material-binding
seam against the already pinned `flutter_scene` interop surface. It allocates
the exact supported mip count, uploads every authored level, and replaces
importer placeholders before adapter publication. No `flutter_scene` fork,
upstream commit, dependency-pin change, or pub-cache edit is part of this plan.
Single-level PNG rewrite remains a bounded compatibility path; multi-level
KTX2 routes through the repo-local mip-aware binding path or stays a typed
diagnostic with the original bytes unchanged.

Capability truth remains per feature and per target. Physical iOS, Android,
and Web rows start as `not run`. Host codec tests, simulator runs, compiler
success, late-result discard, and reference captures do not promote those
rows. Web is allowed to remain diagnostic-only for native-only Draco/BasisU;
the acceptance gate is an honest supported/unsupported result, not forced
cross-platform feature parity.

## Tech Stack

Dart 3, Flutter, `flutter_scene` pinned at
`5dcf6fce7dc36719e64e536faba9538fe9fa1022`, Flutter MethodChannel, Java
`ExecutorService`, Objective-C++ dispatch queues, C++17 atomics and RAII,
vendored Google Draco 1.5.7, vendored Basis Universal/KTX2 plus Zstd,
Flutter GPU/Impeller, the pinned WebGL2 backend, Khronos KTX-Software-CTS and
glTF Sample Assets, the official glTF Validator, and the existing Plan 014
capability/evidence generators.

## Global Constraints

- Work on the current branch. Do not create, switch, rename, or delete a
  branch unless the user explicitly asks in the execution turn.
- Do not edit the pub cache, fork `flutter_scene`, or change its dependency
  pin. Authored-mip construction and binding remain repo-local and are audited
  against the pinned `flutter_scene` commit.
- Do not create commits, push, or perform GitHub writes unless the user
  explicitly authorizes that exact action in the execution turn.
- Preserve the existing single-file GLB scope. External `.gltf` buffers and
  images remain a separate feature.
- Never treat a Dart timeout or ignored late result as proof that native work
  stopped or native memory was released.
- Never terminate a native thread asynchronously. Cancellation must be
  cooperative and memory must be released through normal RAII unwinding.
- Never replace authored mip levels with generated mips while claiming mip
  preservation. Generated mips are a distinct fallback capability.
- Never store mutable cancellation, sampler, or transform state on shared
  image bytes.
- Preserve color/data/normal roles for every mip. Base color, emissive, and
  specular-color data are color content; metallic-roughness, occlusion,
  specular strength, clearcoat factors, transmission, and thickness are data;
  base and clearcoat normals are normal content.
- Keep required/optional extension behavior atomic. A required decoder failure
  blocks import; an optional failure may use valid core fallback with a typed
  non-blocking diagnostic.
- Use the literal evidence labels `verified locally`, `not run`, `blocked`,
  `candidate-only`, `release pending`, and `production-ready`.
- Keep Plan 015 clearcoat and Plan 016 transmission/volume ownership separate.

---

## Source-backed baseline

- `GlbDecodeBudget` already limits JSON bytes, decoded bytes, accessors,
  vertices, indices, texture pixels, native output bytes, and one decode
  timeout. Its source correctly states that the native timeout does not stop
  native work or guarantee resource release.
- Pure-Dart Meshopt checks a monotonic deadline inside decode/filter loops, but
  its synchronous API cannot observe an external UI cancellation event while
  the same isolate is occupied.
- `MethodChannelGlbNativeDecoderProbe` shares one deadline across sequential
  Draco and BasisU stages and discards late results. Its timeout diagnostic
  truthfully records `nativeResourceRelease: notGuaranteed`.
- Draco and BasisU plugin APIs expose only `getDecoderAvailability` and
  `decodeGlb`. They have no request id, cancel endpoint, worker registry, or
  request lifecycle query.
- Android plugin handlers currently call JNI synchronously. iOS handlers call
  the Objective-C++ bridge without a cancellable request object. The C++
  bridge signatures accept budgets and accumulated state but no cancellation
  or working-allocation controller.
- Native preflight and post-decode output accounting are extensive and remain
  mandatory. The missing boundary is allocation/cancellation inside
  `draco::Decoder::DecodeMeshFromBuffer`, BasisU `init`,
  `start_transcoding`, `transcode_image_level`, and Zstd decode.
- BasisU currently rejects `effective_level_count > 1` with
  `unsupportedKtx2Layout` / `ktx2MipLevels`. Single-level output is encoded as
  PNG and inserted into a rewritten GLB. That path cannot preserve an authored
  mip pyramid.
- Pinned `flutter_scene.Texture2D.fromPixels` creates and uploads a generated
  mip chain, and the runtime GLB importer has no external texture-decoder hook.
  The same pinned revision already exposes `GpuTextureSource`, a raw GPU
  texture interop surface, exact `mipLevelCount` allocation, and per-level
  `overwrite`; the viewer can therefore own a narrow post-import binding seam
  without modifying or forking `flutter_scene`.
- Completed Plan 014 provides iOS Simulator `verified locally` evidence for
  texture transform, specular, opaque IOR, and A1B32 Draco. Physical iOS,
  Android, Web, release packaging, and `production-ready` remain `not run` or
  `release pending` as applicable.

## Ownership boundaries

| Boundary | Owner |
| --- | --- |
| Public cancellation token and controller load lifecycle | `flutter_scene_viewer` public API |
| Timeout/cancel diagnostic vocabulary and late-result suppression | Root Dart package |
| Meshopt cooperative checkpoints and atomic rewrite | Root Dart package |
| Native request registry, background execution, and MethodChannel cancel endpoint | Draco/BasisU sibling plugins |
| Codec-internal cancellation checks and working-allocation enforcement | Narrow, documented patches to the pinned vendored codecs, preferably upstreamed |
| Multi-level KTX2 parsing, role validation, and transcoding | BasisU sibling plugin |
| Multi-level GPU texture construction and pre-publication material binding | Root repo-local adapter against pinned `flutter_scene` interop |
| GLB capability truth, target labels, durable evidence, packaging | Root package and Plan 017 harness |
| Renderer-native clearcoat | Plan 015 |
| Renderer-native transmission/volume/glass | Plan 016 |

## Steps

### Milestones and execution order

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: load cancellation | 1-3 | User cancellation is distinct from timeout, reaches every root stage, and cannot publish a partial model. |
| M2: native request lifecycle | 4 | Android/iOS requests run off the UI thread, accept idempotent cancellation, and never deliver a late success. |
| M3: codec resource control | 5 | Draco/BasisU/Zstd observe cancellation inside codec work and reject working allocations before the configured limit. |
| M4: authored mip preservation | 6-7 | Every authored KTX2 level reaches a repo-local multi-level texture source without PNG flattening or regenerated substitution. |
| M5: target and release truth | 8 | Physical/runtime/package evidence is durable and only verified rows are promoted. |

M1 may land without M2 only while native cancellation remains explicitly
`notGuaranteed`. M2 does not close the resource gate unless M3 proves the
codec observes the flag inside long-running work. M4 keeps the existing
dependency pin and must prove the repo-local uploader and post-import binding
seam on native and WebGL2 before publication. M5 runs only after the exact
implementation to be claimed is packaged.

## Closure and release gates

| Gate | Required to complete Plan 017 | Required for a production-ready target claim |
| --- | --- | --- |
| Cancellation | Public cancellation is typed and atomic; Meshopt, Draco, and BasisU observe it during work; late results cannot mutate load state. | The selected physical target proves cancellation latency, native worker exit, and resource release under instrumented load. |
| Allocation | Preflight, output, and codec working allocations share one load budget with exact accounting and overflow checks. | Device stress evidence stays within the declared envelope with no OOM, leak, or post-cancel growth. |
| KTX2 mip chain | Official multi-level ETC1S and UASTC fixtures preserve every level's dimensions, bytes, role, ordering, and sampler intent through the repo-local uploader and binding seam. | The selected target uploads and samples authored levels through the packaged renderer path; generated-mip fallback is separately labelled. |
| Validators | Rewritten single-level GLBs and untouched mip-aware imports pass declared structural validation with exact warning disposition. | Packaged target loads the exact hashed assets used by the validator/evidence record. |
| Platform truth | iOS Simulator, physical iOS, Android, and Web rows record application, visual evidence, release maturity, and blockers independently. | Only rows with physical/runtime plus packaging evidence may be `production-ready`; Web may remain diagnostic-only. |

## Non-goals

- No general task scheduler, process supervisor, or arbitrary native job API.
- No unsafe thread termination, `pthread_cancel`, Java `Thread.stop`, or
  cancellation by leaking/abandoning native allocations.
- No global allocator replacement for the app process.
- No mutation of third-party source without a pinned upstream base, exact
  patch record, license notice, source hash, and focused conformance tests.
- No KTX2 cubemap, array, 3D texture, video texture, virtual texture, or
  progressive streaming support in the first mip-preservation slice.
- No decompression of external `.gltf` image URIs.
- No image-byte baking, mip flattening, UV generation, geometry repair, or
  asset-name branch.
- No material shader or BRDF changes. Texture roles feed the existing material
  slots; Plan 015/016 own layered/transport rendering.
- No production claim based only on unit tests, host-native runners,
  Simulator, Three.js, or the official validator.

### Task 1: Freeze cancellation, allocation, and mip-chain RED contracts

**Files:**

- Create: `test/model_load_cancellation_test.dart`
- Modify: `test/viewer_controller_load_test.dart`
- Modify: `test/glb_native_decoder_probe_test.dart`
- Modify: `test/meshopt_decoder_test.dart`
- Modify: `test/glb_meshopt_rewriter_test.dart`
- Modify: `packages/flutter_scene_viewer_draco/test/native_bridge_symbol_test.dart`
- Modify: `packages/flutter_scene_viewer_basisu/test/native_bridge_symbol_test.dart`
- Modify: `test/glb_basisu_rewriter_test.dart`
- Modify: `test/capability_matrix_generation_test.dart`

**Interfaces:**

- Expected public type: `ModelLoadCancellationController` with `token` and an
  idempotent `cancel([String reason = 'caller'])` method.
- Expected diagnostic: `ViewerDiagnosticCode.modelLoadCancelled` with
  `stage`, `reason`, `requestId` when dispatched, `nativeDispatch`,
  `nativeResourceRelease`, `lateResult`, and `status: cancelled`.
- Expected native methods: `decodeGlb` accepts `requestId`; `cancelDecode`
  accepts the same id and returns `cancelled`, `alreadyFinished`, or
  `unknownRequest`.
- Expected mip result: one image contains an ordered, immutable list of
  decoded RGBA levels with exact `level`, `width`, `height`, and byte length.

- [ ] **Step 1: Add public lifecycle RED tests**

Add tests proving cancellation before source loading, during network loading,
during Meshopt, before native dispatch, during native decode, during adapter
import, and while initial material overrides are being applied. Assert that a
cancelled load has an empty `PartTree`, no persisted material overrides, no
adapter publication, no render request, and exactly one terminal cancellation
diagnostic. A later ordinary load must succeed with a fresh token.

- [ ] **Step 2: Add native protocol RED tests**

Use fake MethodChannels to require a unique `requestId`, an exactly-once
`cancelDecode`, late-result discard, and shared cancellation across sequential
Draco/BasisU stages. Assert a timeout still reports `modelLoadTimeout`, while
caller cancellation reports `modelLoadCancelled`.

- [ ] **Step 3: Add native bridge RED runners**

Compile platform-shared C++ runners that start an instrumented long decode,
flip the request cancellation flag, and require: a cancelled status, no output
payload, no tracker commit, zero live request-owned allocations after join,
and a bounded checkpoint latency. Add over-budget working-allocation cases
that fail before the allocation is committed.

- [ ] **Step 4: Add authored-mip RED fixtures**

Use the existing official UASTC and ETC1S mip fixtures. Require every level to
be returned in order and reject missing, duplicate, reordered, incorrectly
sized, wrong-role, or partially decoded levels. Replace the existing success
expectation for `ktx2MipLevels` rejection only after this RED fails for the
absent multi-level contract.

- [ ] **Step 5: Run the RED commands**

```sh
flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/glb_native_decoder_probe_test.dart test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/glb_basisu_rewriter_test.dart
flutter test --no-pub test/native_bridge_symbol_test.dart
flutter test --no-pub test/native_bridge_symbol_test.dart
```

Run the two package commands from `packages/flutter_scene_viewer_draco` and
`packages/flutter_scene_viewer_basisu` respectively. Expected: failures name
the missing token, request-id/cancel protocol, working-allocation control, and
multi-level output. Record the exact failures in this plan before production
changes.

### Task 2: Add the public load-cancellation lifecycle

**Files:**

- Create: `lib/src/model_load_cancellation.dart`
- Modify: `lib/flutter_scene_viewer.dart`
- Modify: `lib/src/diagnostics.dart`
- Modify: `lib/src/viewer_controller.dart`
- Modify: `lib/src/model_loader.dart`
- Modify: `lib/src/viewer_widget.dart`
- Test: `test/model_load_cancellation_test.dart`
- Test: `test/viewer_controller_load_test.dart`
- Test: `test/viewer_widget_test.dart`
- Document: `docs/PUBLIC_API.md`
- Document: `docs/RUNTIME_GLB_PIPELINE.md`

**Interfaces:**

```dart
final class ModelLoadCancellationToken {
  bool get isCancelled;
  String? get reason;
  Future<void> get whenCancelled;
  void throwIfCancelled({required String stage});
}

final class ModelLoadCancellationController {
  ModelLoadCancellationToken get token;
  bool cancel([String reason = 'caller']);
}
```

Change the load boundary to:

```dart
Future<void> FlutterSceneViewerController.load(
  ModelSource source, {
  MaterialOverrideSnapshot initialMaterialOverrides =
      MaterialOverrideSnapshot.empty,
  ModelLoadCancellationToken? cancellationToken,
});

Future<ModelLoadResult> ViewerCommandSink.load(
  ModelSource source, {
  ModelLoadCancellationToken? cancellationToken,
});

Future<ModelLoadResult> ModelLoader.load(
  ModelSource source, {
  MaterialShadingPolicy materialShadingPolicy = MaterialShadingPolicy.authored,
  ModelLoadCancellationToken? cancellationToken,
});
```

- [x] **Step 1: Implement an immutable token with an idempotent controller**

Keep mutation private to the controller. Complete `whenCancelled` exactly
once; preserve the first reason; return `false` from later `cancel` calls.
`throwIfCancelled` throws one internal exception carrying the stage and
reason. Do not use `TimeoutException` for caller cancellation.

- [x] **Step 2: Thread the token through controller, sink, widget, and loader**

Check before clearing/publishing controller state, after every awaited source
operation, before and after each decoder stage, before adapter import, before
authored patches, before initial overrides, and immediately before success
publication. A cancellation terminal result must be distinct from adapter or
network failure.

- [x] **Step 3: Make source acquisition cancellation-aware**

Race non-cancellable asset/byte futures against `whenCancelled` and ignore
their late values. For HTTP, retain and close the request/stream subscription
for the cancelled load rather than closing a shared client. Preserve the
existing byte limit and timeout precedence; the first terminal event wins.

- [x] **Step 4: Preserve controller atomicity**

On cancellation, clear partial part-tree state, do not persist authored or
initial overrides, and do not request a frame. If a previous model was already
published, preserve that model until the new load reaches the existing atomic
adapter replacement boundary; document the exact replacement semantics.

- [x] **Step 5: Run focused GREEN verification**

```sh
flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/viewer_widget_test.dart
```

Expected: cancellation is typed, idempotent, and atomic; ordinary timeout and
successful reload behavior remain unchanged.

### Task 3: Make Meshopt observe external cancellation

**Files:**

- Modify: `lib/src/internal/meshopt_decoder.dart`
- Modify: `lib/src/internal/glb_meshopt_rewriter.dart`
- Modify: `lib/src/model_loader.dart`
- Test: `test/meshopt_decoder_test.dart`
- Test: `test/glb_meshopt_rewriter_test.dart`
- Test: `test/model_loader_test.dart`

**Interfaces:**

Extend `MeshoptDecodeControl` so one checkpoint can distinguish deadline from
caller cancellation:

```dart
enum MeshoptDecodeStopKind { timeout, cancelled }

final class MeshoptDecodeStopped implements Exception {
  const MeshoptDecodeStopped(this.kind, this.stage);
  final MeshoptDecodeStopKind kind;
  final String stage;
}
```

The production rewrite becomes asynchronous:

```dart
Future<GlbMeshoptRewriteResult> rewriteMeshoptCompressedGlb(
  Uint8List bytes, {
  String? debugName,
  GlbDecodeBudget budget = const GlbDecodeBudget(),
  GlbDecodeBudgetTracker? budgetTracker,
  ModelLoadCancellationToken? cancellationToken,
});
```

- [x] **Step 1: Convert decode checkpoints into yieldable checkpoints**

At each configured decoded-byte interval, yield to the event loop, then check
the external token and monotonic deadline. Keep forced start/complete checks.
Do not yield per element; preserve the existing interval as the scheduling and
latency bound.

- [x] **Step 2: Make the GLB rewrite atomic across awaits**

Keep source bytes, JSON, BIN, extensions, and caller tracker unchanged until
all compressed views decode and the final GLB is built. On cancellation,
discard shadow trackers and partial buffers and return the typed cancellation
diagnostic.

- [x] **Step 3: Add race tests**

Cancel in ATTRIBUTES, TRIANGLES, INDICES, OCTAHEDRAL, QUATERNION, and
EXPONENTIAL paths; cancel on a later bufferView; and race cancellation against
deadline. Assert the first observed terminal condition wins and no extension
declaration is partially removed.

- [x] **Step 4: Verify Meshopt**

```sh
flutter test --no-pub test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart test/model_loader_test.dart
```

Expected: every mode/filter observes external cancellation within the declared
interval and retains the existing malformed-stream and budget behavior.

### Task 4: Add cancellable native request ownership on Android and iOS

**Files:**

- Modify: `lib/src/internal/glb_native_decoder_probe.dart`
- Modify: `packages/flutter_scene_viewer_draco/lib/flutter_scene_viewer_draco.dart`
- Modify: `packages/flutter_scene_viewer_basisu/lib/flutter_scene_viewer_basisu.dart`
- Create: `packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.h`
- Create: `packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.cc`
- Create: `packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.h`
- Create: `packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.cc`
- Mirror: the four control files under each package's `ios/Classes/`
- Modify: both packages' Android Java plugin handlers and JNI bridges
- Modify: both packages' iOS Objective-C++ plugin handlers
- Modify: both packages' CMake and podspec source lists
- Test: `test/glb_native_decoder_probe_test.dart`
- Test: both packages' `native_bridge_symbol_test.dart`

**Interfaces:**

```cpp
enum class FsvDecodeStopReason { kNone, kCallerCancelled, kDeadline, kBudget };

class FsvDecodeControl {
 public:
  explicit FsvDecodeControl(uint64_t working_byte_limit);
  bool Cancel();
  bool IsCancelled() const;
  bool TryReserve(uint64_t bytes);
  void Release(uint64_t bytes);
  uint64_t live_bytes() const;
  FsvDecodeStopReason stop_reason() const;
};
```

The MethodChannel request contains `requestId`; the plugin adds:

```text
cancelDecode({requestId}) ->
  {status: cancelled|alreadyFinished|unknownRequest}
```

- [x] **Step 1: Generate collision-free request ids in Dart**

Use a per-probe monotonic counter plus a random/session prefix. Register a
listener on `ModelLoadCancellationToken.whenCancelled`; invoke `cancelDecode`
exactly once for the active codec stage; remove the listener on every terminal
path. Never send a cancel for a pre-dispatch cancellation.

- [x] **Step 2: Move platform decode work off UI threads**

Android uses one bounded `ExecutorService` per plugin and a synchronized
request registry. iOS uses one serial decode queue per plugin and a namespaced
C++ request registry. Registration happens before work starts; cancel and
finish share one registry lock; removal happens after the C++ result and all
request-owned objects are destroyed. Engine/plugin detach cancels and
joins/drains owned work without delivering results to a detached channel.

- [x] **Step 3: Make cancel idempotent and result delivery exactly once**

The platform handler sets the C++ atomic flag and returns the lifecycle status.
The decode completion path checks cancellation before serializing output. Dart
ignores late success even if a buggy platform handler responds after the
terminal diagnostic.

- [x] **Step 4: Test lifecycle races**

Cover cancel-before-worker-start, cancel-during-codec, cancel-after-finish,
duplicate cancel, timeout then cancel, cancel then timeout, plugin detach,
sequential Draco/BasisU, and two concurrent loads using distinct request ids.

- [x] **Step 5: Verify native request ownership**

```sh
flutter test --no-pub test/glb_native_decoder_probe_test.dart
flutter test --no-pub test/native_bridge_symbol_test.dart
flutter test --no-pub test/native_bridge_symbol_test.dart
```

Run the package commands in their package roots. Expected: no late success,
no cross-request cancellation, and every request registry is empty after test
teardown.

### Task 5: Enforce cancellation and working-allocation budgets inside codecs

**Files:**

- Modify: both platform copies of `fsv_draco_bridge.h/.cc`
- Modify: both platform copies of `fsv_draco_budget.h/.cc`
- Modify: `packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h`
- Modify: `packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.cc`
- Modify: the smallest decoded-mesh/attribute loops reached by the pinned
  Draco path, recorded by an exact source manifest before edits
- Modify: both platform copies of `fsv_basisu_bridge.h/.cc`
- Modify: both platform copies of `fsv_basisu_budget.h/.cc`
- Modify: `packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_containers.h`
- Modify: `packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h/.cpp`
- Modify: the vendored Zstd decode allocation entry points used by the pinned
  BasisU build
- Create: a tracked patch/provenance manifest beside each vendored codec
- Test: both packages' native bridge runners and source-manifest tests

**Interfaces:**

- Pass `FsvDecodeControl*` into the pinned codec entry point through a
  package-specific adapter; do not add global mutable cancellation state.
- Every patched loop checks `IsCancelled()` at a bounded unit of work: decoded
  face/point/attribute blocks for Draco and image-level/block-row/Zstd output
  intervals for BasisU.
- Every request-owned codec allocation uses a checked adapter that calls
  `TryReserve` before allocation and `Release` on destruction/free.
- `std::bad_alloc`, codec allocation failure, cancellation, and budget
  exhaustion map to distinct typed diagnostics.

- [x] **Step 1: Pin and hash the exact third-party edit surface**

Record upstream commit/tag, license, original source hashes, compiled source
manifest, and the intended patched files. Add mutation tests that fail when an
unrecorded third-party source changes. Carry a prominent modification notice.

- [x] **Step 2: Thread control through Draco**

Add an overload or decoder option in the pinned local source that accepts the
control pointer. Check before header decode, topology decode, attribute decode,
and large output construction. Route request-owned temporary/output
allocations through the budget adapter. Preserve byte-identical successful
decode output for the official Box fixture and A1B32 primitives.

- [x] **Step 3: Thread control through BasisU and Zstd**

Add a request-scoped allocator/cancellation context to BasisU containers and
the exact Zstd decode calls used by KTX2. Check before init, after header/DFD/
KVD validation, during supercompression output, before each image level, and
during block-row transcode. Preserve byte-identical single-level output for
the existing official fixture.

- [x] **Step 4: Prove normal RAII release**

Instrument live bytes, peak bytes, allocation count, and destructor/free
count. Cancel at every injected checkpoint and fail unless live bytes return
to zero after the worker joins. Do not accept `lateResult: discardedByDart` as
this proof.

- [x] **Step 5: Run sanitizer and mutation gates**

Run host-native runners with AddressSanitizer and UndefinedBehaviorSanitizer
where supported. Mutate cancellation checks, reservation calls, release calls,
and source-manifest hashes one at a time; every mutation must fail a focused
test. If a pinned codec path cannot accept a safe request-scoped allocator or
checkpoint, keep Plan 017 open and upstream that exact seam; do not relabel the
preflight-only boundary as complete.

### Task 6: Decode and preserve every authored KTX2 mip level

**Files:**

- Modify: both platform copies of `fsv_basisu_budget.h/.cc`
- Modify: both platform copies of `fsv_basisu_bridge.h/.cc`
- Modify: BasisU JNI, Java, Objective-C++, and Dart plugin result mapping
- Modify: `lib/src/internal/glb_native_decoder_probe.dart`
- Modify: `lib/src/internal/glb_basisu_rewriter.dart`
- Test: `test/glb_native_decoder_probe_test.dart`
- Test: `test/glb_basisu_rewriter_test.dart`
- Test: `packages/flutter_scene_viewer_basisu/test/native_bridge_symbol_test.dart`

**Interfaces:**

```dart
final class GlbDecodedBasisuMipLevel {
  const GlbDecodedBasisuMipLevel({
    required this.level,
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });
  final int level;
  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

final class GlbDecodedBasisuImage {
  const GlbDecodedBasisuImage({
    required this.imageIndex,
    required this.contentRole,
    required this.levels,
  });
  final int imageIndex;
  final String contentRole;
  final List<GlbDecodedBasisuMipLevel> levels;
}
```

- [x] **Step 1: Replace the level-count rejection with full validation**

Validate every Level Index entry using checked 64-bit arithmetic: offsets,
lengths, uncompressed lengths, non-overlap, containment, exact level order,
and complete payload coverage required by the supported 2D profile. Validate
expected dimensions as `max(1, base >> level)` and include every level in
aggregate pixel/decoded/native/working budgets before codec entry.

- [x] **Step 2: Transcode every level atomically**

Preflight the complete batch, then transcode levels in ascending order using
the exact selected `r`/`rg`/`rgb`/`rgba` role. Store raw RGBA8888 output with
exact dimensions. Do not PNG-encode individual levels and do not return a
partial chain.

- [x] **Step 3: Preserve role and sampler intent**

Reject shared-image color/data conflicts using the existing selected-channel
rules. Keep sampler min/mag/mip intent outside the image payload and associate
the decoded chain with every consuming texture slot without mutable sharing.

- [x] **Step 4: Keep the single-level compatibility rewrite honest**

`rewriteBasisuTexturesInGlb` may continue to accept one encoded PNG/JPEG image
for the compatibility importer path. It must reject a multi-level result with
`mipAwareImporterRequired`; it must never silently select level 0.

- [x] **Step 5: Verify official ETC1S and UASTC chains**

Run the official mip fixtures through the actual native bridge. Hash every
level, compare exact dimensions/byte lengths, test malformed Level Index
cases, and verify atomic budget/cancellation behavior on a later level.

### Task 7: Add a repo-local mip-aware texture and binding seam

**Files:**

- Create: `lib/src/internal/flutter_scene_authored_mip_texture.dart`
- Modify: `lib/src/internal/flutter_scene_adapter.dart`
- Modify: `lib/src/model_loader.dart`
- Test: `test/flutter_scene_authored_mip_texture_test.dart`
- Test: `test/flutter_scene_adapter_material_test.dart`
- Test: `test/model_loader_test.dart`

**Interfaces:**

Repo-local immutable texture input:

```dart
final class FlutterSceneAuthoredMipLevel {
  const FlutterSceneAuthoredMipLevel({
    required this.level,
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });
  final int level;
  final int width;
  final int height;
  final Uint8List rgbaBytes;
}
```

The internal uploader receives the ordered levels, content role, and one
immutable sampler description. It returns a `flutter_scene.TextureSource`
backed by an exact-count GPU texture or a typed renderer-limit diagnostic. The
adapter binding plan carries image index, consuming texture index and material
slot, sampler, content role, and whether `KHR_texture_basisu` is required.

- [x] **Step 1: Establish repo-local RED**

Add validation tests requiring immutable ordered levels, canonical dimensions,
exact per-level RGBA byte lengths, sampler retention, and upload to the
matching GPU mip index. Add adapter tests requiring a `KHR_texture_basisu`
image to upload once and bind the returned source to every consuming slot
before publication.

- [x] **Step 2: Implement the authored-mip uploader locally**

Validate the complete list before texture creation. Allocate exactly
`mipLevelCount: levels.length` through the pinned `flutter_scene` GPU interop,
upload each level with `overwrite(..., mipLevel: level)`, and wrap it in
`GpuTextureSource`. Never call `Texture2D.fromPixels` or any generated-mip path.
If the pinned backend cannot allocate the authored count, return a typed
renderer-limit diagnostic without dropping a level or mutating live state.

- [x] **Step 3: Implement post-import material binding locally**

Use a bounded placeholder only to let the pinned runtime importer construct
geometry and material topology. Before adapter publication, replace every
selected material slot with the authored-mip source. Deduplicate one decoded
image upload shared by multiple textures while preserving per-texture sampler
state. Required binding failure blocks import; optional failure may use a
valid core fallback. The placeholder is never published as authored-mip
success, and level 0 is never PNG-flattened as the multi-level result.

- [ ] **Step 4: Verify native and WebGL2 locally**

Run CPU validation plus an Impeller-enabled texture upload/sample test and a
WebGL2 test. Verify explicit LOD sampling or an equivalent deterministic
fixture distinguishes authored levels; a base-level-only image must fail the
test. Record the exact pinned `flutter_scene` commit and interop symbols used.

- [x] **Step 5: Keep the viewer pin unchanged**

Rerun the pinned-source audit and prove `pubspec.yaml` and `pubspec.lock` still
resolve `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Do not edit pub-cache files,
fork `flutter_scene`, add a local dependency override, or update the pin.

- [x] **Step 6: Verify the integrated root path**

```sh
flutter test --no-pub test/glb_native_decoder_probe_test.dart test/glb_basisu_rewriter_test.dart test/model_loader_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: multi-level KTX2 reaches the renderer through the repo-local binding
seam without PNG flattening, single-level compatibility remains green, and a
pinned-renderer mip-count limit remains a typed pre-publication diagnostic.

### Task 8: Produce target, packaging, and release evidence

**Files:**

- Modify: `tools/capability_matrix/plan014_selected_extension_capabilities.json`
  or rename it through a RED-first generator migration to a non-active-plan
  capability source
- Modify: `tools/generate_capability_matrix.py`
- Modify: `docs/generated/capability_matrix.md`
- Modify: `docs/RUNTIME_GLB_PIPELINE.md`
- Modify: `docs/QUALITY_SCORE.md`
- Modify: package READMEs and platform installation docs
- Create: durable Plan 017 evidence manifests under
  `tools/material_extension_acceptance/` or a decoder-specific sibling
  directory, with generated artifacts under ignored `tools/out/`
- Test: `test/capability_matrix_generation_test.dart`
- Test: `test/rewritten_glb_validator_test.dart`
- Test: package install/build/runtime harnesses

**Interfaces:**

Every evidence record stores source/fixture hashes, codec upstream base and
local patch hashes, renderer commit, package versions, target/device/OS,
build mode, backend, limits, cancellation trigger, peak/live allocation
metrics, mip-level hashes, sampler/role, validator result, artifact paths, and
the literal runtime/evidence/release labels.

- [x] **Step 1: Migrate capability truth away from an active-plan label**

Preserve all Plan 014 historical rows, but make current evidence owned by a
stable capability source rather than implying Plan 014 is still active. Add
generator tests that prevent historical/simulator evidence from promoting a
physical or release row.

- [ ] **Step 2: Capture cancellation/resource evidence**

On iOS Simulator first, then physical iOS and Android, cancel large Draco,
BasisU, and mixed sequential loads at deterministic checkpoints. Record UI
responsiveness, cancellation latency, worker exit, live/peak bytes, no late
model publication, no leaked request registry entry, and a successful
subsequent load.

- [ ] **Step 3: Capture authored-mip evidence**

Use official multi-level ETC1S and UASTC assets with visually distinct levels.
Record exact level hashes and a deterministic render proving the packaged path
samples uploaded authored levels. Keep reference-renderer direction separate
from target evidence.

- [ ] **Step 4: Verify package installation and release builds**

Build clean disposable apps using the published-package layout for iOS and
Android. Verify plugin registration, native symbols, codec licenses/notices,
release-mode stripping, and the exact packaged codec/source hashes. Web must
either pass the selected pure-Dart/importer path or produce the documented
diagnostic without attempting native plugin use.

- [x] **Step 5: Preserve the physical-evidence boundary**

The iOS Simulator synthetic GPU probe may be `verified locally`, but is not an
official ETC1S/UASTC end-to-end record. The physical iOS runtime is `blocked`
after build/sign/install-launch and before LLDB/VM-service attachment; Android
is `blocked`; and WebGL2 sampling is `not run`. Clean iOS/Web package-build
facts remain `candidate-only` or `release pending` until the matching official
fixture, cancellation/resource, Android, packaged-runtime, and physical-runtime
gates pass.

- [ ] **Step 6: Run final verification**

```sh
bash tools/run_checks.sh
python3 tools/repo_lint.py
git diff --check
flutter test --no-pub test/capability_matrix_generation_test.dart test/rewritten_glb_validator_test.dart
```

Then run both sibling-package test suites, upstream `flutter_scene` tests for
the pinned commit, Android release build/runtime, iOS release build/runtime,
and the selected Web diagnostics/runtime suite. Expected: every claimed row
has matching durable evidence; every unrun row remains `not run`; no aggregate
`production-ready` claim can bypass a missing target gate.

## Acceptance criteria

- [ ] Caller cancellation is a public, idempotent, typed operation distinct
      from timeout and adapter failure.
- [ ] Cancellation before or during source, Meshopt, Draco, BasisU, importer,
      authored-patch, and initial-override stages leaves no partial published
      model or persisted override.
- [x] Meshopt observes external cancellation within the declared checkpoint
      interval for every supported mode and filter.
- [ ] Draco and BasisU use unique request ids, background workers, idempotent
      cancel endpoints, exactly-once terminal delivery, and empty registries
      after completion/detach.
- [ ] Native cancellation is observed inside codec work; it is not merely a
      Dart timeout or discarded late result.
- [ ] Request-owned working allocations are checked before allocation and
      return to zero after success, failure, timeout, and cancellation.
- [ ] Third-party codec modifications have pinned upstream bases, licenses,
      original/patched hashes, compiled source manifests, modification notices,
      and focused mutation tests.
- [ ] Official ETC1S and UASTC mip fixtures preserve every authored level's
      order, dimensions, decoded bytes, content role, and sampler intent.
- [ ] Multi-level assets never route through PNG level-0 flattening or claim
      generated mips as authored preservation.
- [ ] The repo-local authored-mip uploader and pre-publication binding seam are
      tested against pinned `flutter_scene` on Impeller and WebGL2 without a
      fork, pin change, or pub-cache edit.
- [ ] Required/optional extension fallback remains atomic and the original GLB
      bytes are unchanged on failure.
- [ ] Meshopt, Draco, BasisU, and official validator regression suites pass.
- [ ] iOS Simulator, physical iOS, Android, and Web capability/evidence/
      maturity rows remain independent and literal.
- [ ] No physical or `production-ready` row is promoted without matching
      packaged runtime, cancellation/resource, and mip evidence.
- [ ] `bash tools/run_checks.sh`, `python3 tools/repo_lint.py`, and
      `git diff --check` pass at closure.

## Progress log

- 2026-07-20: Task 5C strict-TDD REDs were recorded before production changes
  (`verified locally`). Direct object ownership first failed because
  `PointCloud` lacked the request allocation header; attribute storage first
  failed because generic value scratch still used `unique_ptr<uint8_t[]>`; the
  sequential runtime contract first failed because no runner existed. The
  official Box exact-count assertion then intentionally failed at the previous
  79 baseline and exposed the new 110 total, while the new sequential runner's
  sentinel count exposed 58. Direct decoder, geometry, attribute, controller,
  sequencer, transform, data-buffer, and corner-table objects now use explicit
  request-aware construction; sequential connectivity and generic, integer,
  quantization-minimum, and inverse-quantization storage use the request
  allocator. No reachable Task 5C owner family remains incomplete.
- 2026-07-20: The official Box fixture preserves byte-identical direct/bridge
  NORMAL, POSITION, and index output and sweeps every allocation ordinal 1-110.
  A deterministic 110-byte Draco 2.2 sequential mesh fixture preserves
  byte-identical direct/bridge POSITION, generic `uint16`, and index output and
  sweeps every ordinal 1-58. Every injected failure is typed
  `allocationFailed`, preserves the allocation terminal reason, balances every
  successful reservation/release, and returns zero live bytes. Twenty-eight
  exact source mutants and three compiled reached-owner bypass mutants are
  rejected. Separate Box and sequential ASan+UBSan runners completed without
  sanitizer findings across their success, ordinal, constrained-budget, and
  applicable cancellation/deadline/corruption terminal paths
  (`verified locally`).
- 2026-07-20: Task 5C serial package verification passed
  `flutter_scene_viewer_draco_test.dart` (2/2),
  `package_asset_contract_test.dart` (1/1), and the complete
  `native_bridge_symbol_test.dart` (25/25). The Android/iOS pruned source sets
  remain identical; 74 patched-source provenance entries and exact package
  asset hashes pass. `python3 tools/repo_lint.py`, Dart format, analysis, and
  `git diff --check` pass. `bash tools/run_checks.sh` reached 626 passed with 16
  intentional skips and 6 capability-matrix failures; all six stem from the
  existing broader decoder-control fingerprint set, first reported at Draco
  `compression/decode.h`, and remain outside this vendored-Draco/package-only
  slice. Metadata/status, bridge/platform output ownership, the conservative
  outer reservation, Task 5/M3, physical-target, packaging, release, and
  `production-ready` evidence remain explicitly open.
- 2026-07-20: Task 5C review remediation is `verified locally`.
  `DataBuffer` and `AttributeTransformData` copy/move operations now either
  bind parameter storage to an explicit destination control or detach ordinary
  copies onto the host allocator; `PointAttribute::CopyFrom` binds both the
  transform object and parameter storage to its destination. A native runner
  destroys the source and its distinct control before destination use and
  deletion, locks source/destination charges at 6/5, and covers sized delete,
  over-aligned virtual delete, constructor throw cleanup, and distinct-control
  move. The sequential fixture now includes unquantized float generic data,
  is 132 bytes with SHA-256
  `5113cbc836363cae9a59526d983e12ee95d32cf2f342bf192be7b2fdc2321b33`,
  and locks 68 allocation ordinals. Ten compiled bypass mutants cover direct
  object, concrete decoder, controller, sequencer, transform object,
  transform buffer/copy, topology, integer scratch, and generic raw scratch;
  all are rejected by exact runtime counts. Immutable regeneration archives
  fixed source object `8794499f9f7e72c1cd64aea7242081a2d1ed5da3`, verifies
  the archive/license/generator/payload hashes, rebuilds from extracted source,
  and byte-compares the payload. Focused API/asset tests pass 3/3, the complete
  native suite passes 27/27 serially, copy and sequential ASan+UBSan runners
  exit 0, repo lint and `git diff --check` pass, and focused Dart format changes
  zero files. The broader capability fingerprint remains deliberately
  unchanged and Task 5D/release evidence remain open.
- 2026-07-20: Final Task 5C executable-mutation review is `verified locally`.
  Four additional compiled bypasses run through real fixtures and fail only
  after parity and zero-live accounting checks: decoded `PointAttribute`
  placement reduces sequential 68 to 65, `CornerTable` placement reduces Box
  110 to 109, quantization-minimum storage reduces sequential 68 to 67, and
  inverse-quantization scratch reduces sequential 68 to 67. Zero-count
  sentinels recorded each intentional RED before these values were locked.
  Task 5C now rejects 28 source mutants and 14 compiled-and-run mutants. No
  production file changed for this follow-up because all four owner/storage
  paths were already correctly request-controlled. The focused Box/sequential
  mutant tests pass 2/2, API/asset tests pass 3/3, the complete native suite
  passes 27/27 serially, copy/header and sequential ASan+UBSan runners exit 0,
  repo lint passes, focused Dart format changes zero files, and
  `git diff --check` passes.

- 2026-07-19: Task 8 target/package candidate evidence was reviewed without
  adding a target record or promoting capability truth (`verified locally`). An
  Impeller iOS Simulator synthetic probe against pinned `flutter_scene`
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022` explicitly sampled authored RGB
  levels red/green/blue and a discriminating base-only red/red/red control. The
  initial real-target RED exposed screen-space row order opposite the authored
  LOD order; screen-order normalization produced the final GREEN. This probe is
  not an official ETC1S/UASTC packaged end-to-end fixture, so Task 8 Step 3 and
  its acceptance gate remain open. WebGL2 was `blocked` before a test Chrome
  session produced test output; sampling is `not run`, and final spawned-process
  cleanup is `verified locally`. A physical iOS release drive was unsupported;
  the debug fallback reached build/sign/install-launch but was `blocked` at
  LLDB/VM-service attachment, with no JSON or sampling result. Android remains
  `blocked`.
- 2026-07-19: Clean disposable package evidence is `candidate-only` and
  `verified locally`. Initial incremental BasisU and Draco packaging-contract
  REDs exposed stale asset manifests; a clean rebuild made both contracts
  GREEN, produced a 22.3 MB no-codesign iOS release app and a Web release build,
  and preserved expected iOS/native-only Web plugin registration boundaries.
  The iOS Runner and both codec frameworks are arm64, expected native plugin and
  codec-control symbols are present, and all nine vendored license/notice/
  provenance assets have exact source-to-iOS-to-Web SHA-256 parity. Flutter also
  reports both plugins' missing Swift Package Manager support as a future-error
  warning. These are build/layout facts, not packaged runtime or release
  readiness: physical runtime and Android remain `blocked`, Web sampling is
  `not run`, release is `release pending`, and no `production-ready` claim is
  made. Task 5 allocator completeness and Task 8 cancellation/resource capture
  remain `blocked`; no production, pin, renderer, or capability change occurred.

- 2026-07-19: Task 8 second-rereview remediation is complete pending
  independent rereview (`verified locally`). `load_source()` now carries the
  verified-artifact result into capability validation: a real temporary
  inventory with matching files, positive lengths, and SHA-256 can satisfy a
  new exact-target claim, while a tampered file cannot. The four-entry Plan 014
  migration ledger now has production-owned exact old/new values and a pinned
  canonical digest independent of the mutable snapshot; evidence-backed future
  row changes remain separately admissible. Manual record validation now
  matches the strict schema for lowercase record IDs, RFC 3339 date-times, and
  safe artifact path segments. Local verification rejects any symlinked path
  component and proves the resolved file remains under the resolved ignored
  artifact root before hashing. No target evidence record or device artifact
  was integrated. Target/package/release capture remains `not run`, Android
  remains `blocked`, aggregate maturity remains `release pending`, and this is
  not a `production-ready` claim. No `flutter_scene` fork, upstream, pin, or
  pub-cache change was made.

- 2026-07-19: Task 8 review remediation is complete pending independent
  rereview (`verified locally`). The complete original Plan 014 source payload
  is now frozen as tracked history: all nine features and 36 target rows,
  original context, and decoder-control boundaries are checked against their
  actual hashes, while exactly four later live blocker-wording changes remain
  explicit in the snapshot ledger. Canonical required gate sets are immutable
  per decoder feature and target. Runtime means a successful target load,
  render, and readback; native-only Web diagnostic evidence means exactly one
  `unsupportedModelFeature` diagnostic and zero native plugin invocations; and
  authored-mip sampling means explicit expected/observed RGB for every LOD plus
  a discriminating base-only negative control. The full manifest/discovery/
  claim/record schema is closed with `additionalProperties: false` and matches
  validator enforcement of glTF sampler enums, role/slot/storage compatibility,
  canonical mip dimensions/RGBA lengths, and declared limits. Every referenced
  validator, package, runtime, diagnostic, cancellation, and mip-readback
  artifact must resolve through an inventory; capability promotion additionally
  verifies local existence, positive byte length, and SHA-256. The empty
  manifest stays portable. No target records were integrated in this
  remediation. Physical/runtime/package captures are still `not run`, Android
  target execution remains `blocked`, aggregate maturity is `release pending`,
  and no `production-ready` claim is made. All changes remain repo-local; no
  `flutter_scene` fork, upstream checkout, pin, or pub-cache edit was made.

- 2026-07-19: Task 8 Step 1 and the repo-local evidence-framework slice are
  complete pending independent review (`verified locally`). The live capability
  source moved from the Plan 014 filename to
  `tools/capability_matrix/selected_gltf_extension_capabilities.json`; a tracked
  Plan 014 snapshot fingerprints all 36 historical feature/target rows and the
  retained historical context. Generator guards reject stale source paths,
  hyphenated maturity labels, simulator-to-physical promotion, production
  labels without complete target gates, and any new verified row without an
  exact durable evidence claim. The dependency-free decoder/mip validator and
  tracked manifest define source/diff/pin/package, codec provenance, fixture,
  target, limit, cancellation/resource, authored-mip role/slot/sampler/level,
  validator, packaging, artifact, and blocker fields. Gate names alone cannot
  promote a claim: failed release-package facts, terminal/resource facts, or a
  level-0-only mip record are rejected. Generated artifacts are restricted to
  ignored `tools/out/plan017_decoder_mip_acceptance/`. Device discovery is
  recorded separately and is not runtime evidence. No target runtime, package
  installation, release build, or physical-device capture was run; Android is
  `blocked` by the unavailable device/build environment, all new target claims
  remain `not run`, and aggregate maturity remains `release pending`. No
  `production-ready` claim is made. No `flutter_scene` fork, upstream checkout,
  pub-cache, dependency pin, branch, commit, stage, push, or GitHub write was
  used.

- 2026-07-19: Task 7 Important review remediation completed and returned for
  independent rereview (`verified locally`). Review found that the first
  binding-plan implementation keyed a raw upload by wrapper material role, so
  one valid native `nonColor` chain consumed by normal and scalar/data slots
  was split into two GPU allocations. Strict RED tests reproduced both errors:
  the builder returned two uploads, and the adapter rejected the normal target
  before allocation. The binding plan now separates native pixel storage role
  (`color`/`nonColor`) from the exact material-slot semantic retained on every
  target. Raw upload identity is `(imageIndex, storageRole)`; one `nonColor`
  chain now allocates once, uploads each authored level once, and supplies
  distinct sampler wrappers to normal and occlusion without losing their slot
  meaning. Existing color/nonColor conflict rejection and staged publication,
  required/optional failure, and cancellation atomicity remain green. Pinned
  GPU textures still expose no deterministic dispose operation, so failed
  mid-upload cleanup evidence remains unavailable and is not claimed. No fork,
  pin, dependency override, pub-cache, upstream, branch, commit, stage, push,
  or GitHub write occurred. Impeller/WebGL2 and physical/package evidence remain
  `not run`; release remains `release pending`.

- 2026-07-19: Task 7 repo-local authored-mip upload and staged binding is
  complete pending independent review (`verified locally`). Strict RED-first
  coverage named the absent uploader/binding seam, missing shared-image sampler
  support, missing model-loader publication path, lost mixed Draco topology,
  malformed output-accounting acceptance, and a required BasisU texture with no
  decoded binding that incorrectly published. The final seam owns immutable
  RGBA8 levels, validates the complete chain and every sampler before allocation,
  allocates the exact authored mip count, uploads every level by index, and
  creates per-texture sampler wrappers while deduplicating the raw image upload.
  Material targets are resolved and validated on staged imported nodes before
  any GPU allocation; all required uploads complete before staged mutations,
  and adapter publication remains behind the cancellation/publication gate. The
  `pbr-materials` boundary kept color/data/normal roles derived from actual glTF
  slots and returned typed blocking diagnostics for renderer-unrepresentable
  slots; no shader or BRDF behavior changed. The implementation and tests are
  entirely repo-local. `pubspec.yaml` and `pubspec.lock` still resolve pinned
  `flutter_scene` commit `5dcf6fce7dc36719e64e536faba9538fe9fa1022` with
  no dependency override, fork, pub-cache edit, branch, commit, stage, push, or
  upstream write. Impeller and WebGL2 authored-level sampling are `not run`;
  physical targets and packaged runtime are `not run`, and release remains
  `release pending`.

- 2026-07-19: Task 6 full authored KTX2 mip-chain decode completed pending
  independent review (`verified locally`). The mirrored native preflight now
  validates every 64-bit Level Index entry, canonical level count/dimensions,
  containment, non-overlap/complete payload-tail coverage, aggregate pixels,
  raw RGBA output, decoded bytes, and working-output limits before codec
  entry. ETC1S and UASTC levels transcode atomically in authored level order
  into raw RGBA8888; platform mappings preserve image index, selected content
  role, ordered level metadata, exact bytes, and all consuming texture sampler
  intents. A deterministic level-1 cancellation test returns no chain or
  diagnostic payload and proves live request bytes return to zero with matched
  allocation/release counts. The legacy encoded PNG/JPEG compatibility
  rewriter remains separate and rejects every raw authored chain with typed
  `mipAwareImporterRequired`; it never selects level 0. The repo-local
  `pbr-materials` boundary kept color/data/normal role classification in the
  wrapper/native metadata and made no renderer, shader, `flutter_scene`, pin,
  pub-cache, branch, commit, stage, push, or upstream change. Task 7 GPU upload
  and material binding, target/runtime/package evidence, release, and
  `production-ready` remain `not run` or `release pending`.

- 2026-07-19: Task 6 authored-mip implementation started with repo-local
  `pbr-materials` boundary review and strict RED-first tests. The selected
  content role remains glTF material-slot metadata; no shader, BRDF,
  `flutter_scene`, dependency-pin, pub-cache, or upstream source change is in
  scope. Native ETC1S/UASTC output will remain raw RGBA8888 per authored level,
  while the existing one-level encoded PNG/JPEG compatibility rewriter stays a
  separate legacy input path. Task 7 GPU upload/material binding and all
  target/package/release evidence remain `not run` or `release pending`.

- 2026-07-19: Roadmap coordination added deferred Plan 028 for a fork-free,
  lab-first ray/path-tracing feasibility study. Plan 028 creates no permanent
  sibling package by default and requires measured GO before a direct-upstream
  `flutter_scene` proposal. This documentation-only coordination does not add
  ray/path tracing to Plan 017, change its implementation scope, or promote
  any target/release evidence; those Plan 028 results remain `not run` and
  `candidate-only`.

- 2026-07-19: Task 4 second-rereview remediation completed and returned for
  independent rereview (`verified locally`). The Java and C++ lifecycle
  runners now reject duplicate active registration, reject registration after
  detach, prevent queued work from starting after cancellation, reject result
  delivery after detach, distinguish unknown requests from finished
  tombstones, and retain the existing cancel-first/finish-first and 500-race
  coverage. The control runners capture the concurrent `Cancel()` return and
  require it to agree exactly with the single atomic stop reason across 500
  caller-vs-budget races. RED-sensitive mutation harnesses compile and execute
  ten invalid owner implementations per plugin and a caller-winner return-value
  mutant for both platform control copies; every mutant is required to exit
  nonzero before the production source is accepted. Capability evidence now
  fingerprints every Task 4 Android/iOS control, registry, handler,
  bridge/JNI, and Dart probe source, with mutation coverage for every newly
  added decisive source. This remains a repo-local implementation: no
  `flutter_scene` fork, upstream checkout edit, dependency-pin change, or pub
  cache edit was made. Physical-target runtime, packaged cancellation,
  codec-internal stop latency/resource release, and `production-ready`
  evidence remain `not run` or `release pending`.

- 2026-07-19: Task 4 independent-review remediation completed and returned for
  rereview (`verified locally`). Both plugins now namespace every control
  symbol (`fsv_draco`, `fsv_basisu`), and a combined executable proves the
  controls coexist without ODR/link collisions. One atomic stop-reason CAS is
  the caller-cancel vs budget linearization point and preserves the first
  reason. Android handlers use actual reusable synchronized Java request
  registries; iOS handlers use actual reusable namespaced C++ request
  registries. Cancel and finish serialize control destruction, active removal,
  tombstone publication, delivery ownership, and detach/drain. Executable host
  harnesses compile those production components and cover queued cancellation,
  duplicates, finish-first and cancel-first outcomes, 500 concurrent
  cancel/finish races, exact-once delivery, and empty registries after detach.
  BasisU request construction now occurs before the final shared-deadline
  check, so its synchronous manifest build consumes the same budget. Decoder
  capability fingerprints and generated blocker documentation were refreshed
  only for the approved Task 3/4 source changes. This does not establish
  codec-internal stop latency, allocator interception, physical-target runtime,
  packaging, release, or `production-ready` evidence; those remain `not run`
  or `release pending`.
- 2026-07-19: Final Task 5 slice verification `bash tools/run_checks.sh`
  passed repository lint, format check (92 files, 0 changes), dependency
  resolution, analysis, and 581 tests with 16 intentional GPU/build-hook skips
  (`verified locally`). Separate `python3 tools/repo_lint.py`, `git diff
  --check`, and the complete BasisU `VENDORED_SOURCES.sha256` verification
  passed (`verified locally`). This is host-local candidate evidence only;
  physical targets and packaged runtime remain `not run`, release remains
  `release pending`, and the open allocator boundaries above prevent any
  `production-ready` claim.

- 2026-07-19: Task 4 cancellable native request ownership completed pending
  independent review (`verified locally`; superseded by the remediation entry
  above). The root probe now supplies a
  collision-resistant per-probe session prefix plus monotonic sequence,
  registers a synchronously removable token listener, owns exactly one active
  `cancelDecode` message per codec stage, preserves the single monotonic
  Draco/BasisU deadline, and returns typed `modelLoadCancelled` details before
  `ModelLoader` can replace them with a generic stage diagnostic. Pre-dispatch
  cancellation sends no native message; caller cancellation and timeout both
  discard late MethodChannel output without committing budget state. Android
  plugins use bounded two-worker/32-entry executors, concurrent active maps,
  synchronized native-handle cancel/destroy, exact-once main-thread delivery,
  and detach cancellation/drain. iOS plugins use serial queues, locked maps,
  shared request controls, exact-once main-thread delivery, and equivalent
  detach drain. Mirrored `FsvDecodeControl` files provide atomic idempotent
  cancellation, first-terminal stop reasons, and overflow-safe basic working
  reservation accounting. The bridges observe cancellation before and after
  codec calls; codec-loop checkpoints and allocator interception remain Task 5
  and are `not run`. No `flutter_scene` fork, pin change, or upstream edit was
  made. Physical iOS/Android, packaging, release, and `production-ready`
  evidence remain `not run` or `release pending`.

- 2026-07-19: Task 2 review remediation completed (`verified locally`). HTTP
  response-subscription cancellation is now best-effort cleanup that cannot
  replace a typed cancellation, network failure, or timeout, and the unawaited
  request lifecycle has a terminal error guard. A non-success HTTP status
  completes its `networkFailure` result before stream cleanup. Active-stream,
  late-response, late-stream-error, and late-send-error paths retain no
  unhandled asynchronous error and never close the shared client. Corrected
  the runtime-pipeline documentation to record Meshopt's external cancellation
  checkpoints. Native request cancellation and resource release remain `not
  run`; release remains `release pending`.

- 2026-07-19: Closed Task 2 / the remaining M1 public lifecycle boundary
  (`verified locally`). Asset acquisition now races its late value or error
  against caller cancellation and the configured source timeout. HTTP uses one
  load-scoped `AbortableRequest`, completes its abort trigger and cancels only
  that response subscription on cancellation or timeout, attaches and cancels
  a response stream that arrives late, and never closes a caller-provided
  shared client. One first-terminal race owns source success, source failure,
  caller cancellation, or timeout; late source outcomes are inert. The loader
  checks the token after source acquisition, before and after Meshopt, native
  availability and native decode awaits, before authored patch extraction,
  before and after adapter import, and immediately before success. The
  controller also checks before authored-patch publication, initial overrides,
  and success settlement. Existing accepted-publication and replacement
  atomicity remain unchanged. Native request ids, `cancelDecode`, background
  native workers, codec allocation control, authored KTX2 mip preservation,
  packaging, and physical-target evidence remain subsequent tasks and are `not
  run` or `release pending`.

- 2026-07-19: Task 3 checkpoint-bound review remediation completed (`verified
  locally`). `MeshoptDecodeControl` now preserves residual decoded-byte work
  across ordinary and forced checks and emits at most one yield for each real
  bounded codec chunk; the discarded-remainder and repeated-empty-yield paths
  are removed. ATTRIBUTES delta reconstruction subdivides an 8192-byte block
  at the next actual configured interval boundary, so the production
  4096-byte interval produces two distinct work/yield boundaries rather than
  yields clustered before one synchronous block. TRIANGLES, INDICES, and
  filter checks follow completed indivisible codec primitives. Configured
  intervals smaller than one primitive retain documented hard minima of 12
  bytes for a triangle, 8 for a filter element, and 4 for an attribute or
  index element; normal production intervals do not yield per element. Native
  request lifecycle, codec allocation control, authored mips, packaging, and
  physical-target evidence remain `not run` or `release pending`.

- 2026-07-19: Opened a disposable renderer-native material demo on the
  iPhone 17 iOS 26.5 Simulator using the immutable pinned `flutter_scene`
  revision. The app exposes ToyCar as a combined authored clearcoat-body plus
  transmission-glass example, ClearCoatCarPaint as an isolated clearcoat
  example, and GlassVaseFlowers as an isolated transmission/volume example.
  All three use `productionShaders()` with the controlled Plan 015/016 HDRI;
  the isolated clearcoat and transmission loads completed with 1 and 4
  renderable parts respectively and zero diagnostics (`verified locally`).
  This is a transient Simulator visual smoke only; it does not reopen Plans
  015/016 or promote Plan 017 physical-target, packaging, release, or
  `production-ready` evidence.

- 2026-07-19: Reopened the user-authorized A1B32 bytes in a disposable iPhone
  17 iOS 26.5 Simulator harness and applied the previously hash-pinned Glorvia
  C28 front/reverse albedos at repeat `2.5 × 2.5` plus the crepe normal at
  `1.0 × 1.0` to primitives 0-3. The live Impeller/Metal run loaded 20
  renderable parts through the optional native Draco plugin and persisted all
  four texture patches without new diagnostics (`verified locally`). This was
  a transient visual smoke using `/private/tmp/fsv_a1b32_texture_demo`; it did
  not exercise Plan 017 native cancellation, codec allocation control,
  authored KTX2 mip preservation, physical iOS, packaging, release, or
  `production-ready` evidence, and no capability row is promoted.

- 2026-07-19: Task 3 pure-Dart Meshopt external cancellation completed
  (`verified locally`). `MeshoptDecodeControl` now yields only at configured
  decoded-byte checkpoints, then distinguishes caller cancellation from the
  existing monotonic deadline with `MeshoptDecodeStopped`; forced start and
  completion checks remain in place. All claimed modes and filters observe the
  load token, the asynchronous GLB rewrite keeps JSON/BIN/source bytes and the
  caller budget tracker shadowed until final success, and cancellation on a
  later bufferView returns one `modelLoadCancelled` diagnostic with source,
  extension, stage, reason, and bufferView identity. `ModelLoader` threads the
  token into the rewrite and terminates before adapter import. Native request
  ids, MethodChannel cancellation, codec working-allocation control, authored
  KTX2 mip preservation, packaging, and physical-target evidence remain `not
  run` or `release pending`.

- 2026-07-19: Task 7 architecture was revised by explicit user decision.
  `flutter_scene` will not be forked, committed, pushed, locally overridden, or
  repinned. Authored mip upload and material binding remain repo-local against
  pinned commit `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Source audit confirms that
  this revision already provides `GpuTextureSource`, exact-count GPU texture
  allocation, and per-mip `overwrite`; the root adapter will use a bounded
  importer placeholder and replace every affected material slot before atomic
  publication. This architecture decision is `verified locally`; its RED,
  GREEN, native/WebGL2, packaging, and physical-target evidence are `not run`.

- 2026-07-19: Final preflight-cache retry correction completed (`verified
  locally`). Accepted runtime scene replacement retains only a successful
  available `flutter_scene` shader preflight. An unavailable preflight cache,
  including a transient shader-library failure, is cleared despite the
  replacement preservation request and is retried on the next preflight.
  Ordinary backend clear still clears all cached preflight results. This is an
  internal cache-lifetime correction; native request cancellation, codec
  allocation control, authored mip-chain preservation, packaging, and
  physical-target evidence remain `not run` or `release pending`.

- 2026-07-19: Final publication-ownership correction completed (`verified
  locally`). Widget programmatic-load bookkeeping is generation-owned, so a
  stale B ordinary failure before publication cannot clear a newer C ready
  result, environment attempt, statistics, or render surface. The controller
  checks a pre-cancelled no-op before waiting for an accepted B finalization.
  `ModelLoader` and the controller close their publication callbacks in every
  terminal path, rejecting late adapter callbacks after timeout or settlement
  before they can commit or create an unreleased finalization gate. A token
  rejection after a controller claim releases that gate exactly once. Native
  request cancellation, codec allocation control, authored mip-chain
  preservation, packaging, and physical-target evidence remain `not run` or
  `release pending`.

- 2026-07-19: Publication-order and preflight-cache correction completed
  (`verified locally`). `ModelLoader` now asks the controller to claim the
  publication before accepting a live cancellation token; a stale claim is
  reported as an inert `superseded` result and leaves that token cancellable.
  If token acceptance subsequently rejects, the controller releases its narrow
  finalization gate. This keeps a stale tokenless or live-token B from
  publishing over accepted C without manufacturing a cancellation diagnostic
  or changing widget state. Accepted runtime scene replacement also preserves
  the already-computed production shader-preflight cache, while ordinary
  backend cleanup still clears it. Native request cancellation, codec
  allocation control, authored mip-chain preservation, packaging, and
  physical-target evidence remain `not run` or `release pending`.

- 2026-07-19: Acceptance-window ownership correction completed (`verified
  locally`). The package-internal adapter-publication callback now reaches the
  controller synchronously before token acceptance and before the adapter
  commits live fields. It opens the controller finalization gate at that exact
  boundary, so a replacement cannot allocate a newer attempt between accepted
  publication and sink settlement. A rejected token releases that gate; a
  rejected stale controller claim never closes the token. The gate is also
  released in the controller load's `finally` path for success, ordinary
  failure, cancellation, and unexpected error. No public API, native request
  id, allocation, or mip-chain scope was added.

- 2026-07-19: Final rereview remediation completed (`verified locally`). A
  late ordinary failure from a caller-cancelled widget load is now inert, so it
  cannot clear a newer model result or environment attempt. Once the controller
  observes an accepted successful publication, it holds a narrow finalization
  gate through diagnostics, part-tree installation, authored patches, initial
  overrides, and terminal settlement; a new load waits before it can allocate
  a generation. Failure state is installed before diagnostics notify listeners,
  preventing reentrant listener loads from being overwritten by stale terminal
  mutation. Native request cancellation, codec allocation control, authored
  mip-chain preservation, packaging, and physical-target evidence remain `not
  run` or `release pending`.

- 2026-07-19: Second follow-up review correction completed (`verified
  locally`). Adapter publication now atomically accepts a still-live token at
  its sole live-field commit; acceptance closes cancellation so a late caller
  cancellation cannot win the controller's pending sink race. Accepted loads
  continue through authored and initial material application. Controller load
  attempts are generation-scoped: a stale cancelled replacement records its
  one cancellation diagnostic but cannot restore an older state after a newer
  load succeeds. The widget preserves the mounted ready model and environment
  across a cancelled replacement, while an ordinary failure still clears the
  prior result and an accepted replacement still reconfigures the environment.

- 2026-07-19: Follow-up review correction completed (`verified locally`). The
  adapter boundary now stages diagnostics, material-extension support, root,
  scene, and render scene across imports, checks cancellation at the single
  live-field commit, and rejects a cancelled late replacement without clearing
  the previously published adapter scene. Controller cancellation restores the
  prior load state (including `success` for a published replacement). Atomic
  publication acceptance closes cancellation, and the accepted load continues
  through authored and initial material application. Widget programmatic loads now retain the prior model
  result/environment attempt until a new load succeeds. Source futures are no
  longer raced; their late work is ignored and cannot publish through the
  adapter commit gate. The prior first-slice GREEN evidence below is superseded
  by this review-correction verification.

- 2026-07-19: Completed the first independently verifiable M1 public
  cancellation lifecycle slice (`verified locally`). Added the public
  `ModelLoadCancellationToken` and idempotent
  `ModelLoadCancellationController`, `modelLoadCancelled`, and optional token
  threading from controller through command sink and widget to `ModelLoader`.
  The loader checks before source acquisition and immediately before adapter
  publication. Controller cancellation races a pending sink load, retains the
  previous `PartTree` and persisted overrides for replacements, emits one
  terminal cancellation diagnostic, and makes no render request for the
  cancelled load. Native cancellation, codec allocation control, request ids,
  and authored KTX2 mip work remain `not run` later milestones. Added the
  required `## Steps` heading to this promoted active plan so repository lint
  recognizes the existing task checklist.

- 2026-07-19: Started the smallest independently verifiable M1 public
  cancellation lifecycle slice. The wrapper-only implementation will preserve
  existing material semantics and renderer behavior: cancellation is handled
  at the controller/command-sink/widget/ModelLoader boundary, with no native
  request protocol, codec allocation, or mip-chain work in this slice. The
  controller must defer replacement state mutation until a non-cancelled load
  succeeds so a cancelled replacement retains its previously published
  `PartTree` and persisted overrides.

- 2026-07-19: Promoted Plan 017 for the smallest independently verifiable M1
  lifecycle slice. The repository is on the user-authorized current `main`
  branch at `8794499f9f7e72c1cd64aea7242081a2d1ed5da3`; the supplied starting
  point `87944991be7e44fe5ea253a5f013ab0cc3230d44` is not present in this
  checkout. Replaced the stale `cd6760912fa38beb55f63e388655a1aeabd32fe4`
  upstream baseline with the already resolved immutable `flutter_scene`
  commit `5dcf6fce7dc36719e64e536faba9538fe9fa1022` (`verified locally` from
  `pubspec.yaml`, `pubspec.lock`, and `.dart_tool/package_config.json`).
  Cancellation semantics for this slice are fixed as follows: cancelling an
  initial load with no published model leaves an empty `PartTree` and no
  overrides; cancelling a replacement load preserves the previously published
  model, `PartTree`, and persisted overrides unchanged; no cancelled
  replacement state may commit; no new authored or initial overrides, adapter
  publication, or render request may escape; exactly one terminal
  `modelLoadCancelled` diagnostic is emitted. Native request ids,
  MethodChannel cancellation, codec allocation control, native C++ runners,
  and KTX2 mip preservation remain subsequent Plan 017 work and are `not run`.

- 2026-07-15: Created as the explicit deferred owner for completed Plan 014's
  remaining native cancellation/resource-control, authored KTX2 mip-chain,
  cross-platform target, packaging, and release-evidence work. Plan 015 and
  Plan 016 retain renderer-native clearcoat and transmission/volume ownership.
  Current evidence is unchanged: Plan 014's iOS Simulator UV/specular/opaque-
  IOR/A1B32 rows are `verified locally` and `candidate-only`; physical iOS,
  Android, Web, release packaging, and production readiness remain `not run`
  or `release pending`. No implementation step in this deferred plan has run.

## Verification log

- 2026-07-19: The iOS Simulator authored-mip probe first failed after printing
  screen-ordered samples blue/green/red (`verified locally`):
  `tools/out/plan017_decoder_mip_acceptance/ios_simulator_flutter_drive.log`
  SHA-256 `da73b573bb48a9fb326d164d29f35cbfc33eb747fae1ef014dd1075a8d9deca1`
  and diagnostic rerun
  `tools/out/plan017_decoder_mip_acceptance/ios_simulator_diagnostic_rerun.log`
  SHA-256 `8deca06242bfd9693767b51b4998590a5352e482128fdc5ec5af05e3b7f70575`.
  After screen-order remediation, Flutter Driver passed 2/2 and recorded
  authored red/green/blue plus base-only red/red/red (`verified locally`):
  `ios_simulator_flutter_drive_green.log` is 868 bytes, SHA-256
  `39ad0965a32c419b350de5836741730f07f10091d904a89f4838f7483cc73eab`,
  and `ios_simulator_authored_mip_readback.json` is 456 bytes, SHA-256
  `758c1cb55b6a2848830e2e096fc443bdec37a75e808d4f9da0619fac79d429aa`.
  Supporting `flutter_version.json` is 655 bytes, SHA-256
  `26c7dbf93149b6e9f07fcbf3a8b6d4d01bb385c88dcb7d1f59dc2ac100e82d9a`,
  and `simctl_devices.json` is 6205 bytes, SHA-256
  `a5f88f77496e6306570a10ef381f43b61765fb6d269c242dfef86ca357767123`.
  This is synthetic GPU sampling, not official ETC1S/UASTC end-to-end evidence.
- 2026-07-19: WebGL2 Flutter Driver stopped while waiting for the Chrome debug
  service, before test output or sampling (`blocked`; sampling `not run`), as
  recorded in `tools/out/plan017_decoder_mip_acceptance/webgl2_flutter_drive.log`
  and its bounded verbose companion. Final spawned Chrome/test-driver/frontend-
  server cleanup was checked (`verified locally`). Physical iOS release drive
  rejected release mode; debug drive built, automatically signed, installed and
  launched, then failed to discover the Dart VM service after LLDB attachment
  delay (`blocked`). The physical run produced no JSON/readback and sampling is
  `not run`. Android is `blocked` by the unavailable SDK/build-tools/CMake/adb/
  device environment.
- 2026-07-19: Package-contract intentional incremental RED logs are
  `basisu_packaging_contract_red.log` SHA-256
  `8453df44bec7c2bcb0a14bf7cbd33606ec8ba9db3ba3ca64df852e7424e9e126`
  and `draco_packaging_contract_red.log` SHA-256
  `b896d43c0b9a01adb5817c95baf0dbcc92d425d2ac4acbbb807eab59afd65eae`;
  the clean GREEN logs are respectively
  `2054c064c0b3ae108fabfc26e218bb424d9121348a62fd4c38a24b9f9bd7d80a`
  and `ef43e0a3932a6837514a9d6616f70a1d65b1437b10f87be2909f22e26515b8f1`
  (`verified locally`). The clean no-codesign iOS release build produced 22.3
  MB, SHA-256
  `2c95128d9dead8cc4c8fa042d282c59c45e8f19132a3b56c69efd005e723094c`;
  the clean Web release build passed, SHA-256
  `c2b9ab1607f91efd024dbcbff749b329705033b408664ce67ceae493099f2e30`.
  Registration, native symbol, arm64 architecture, output, notice, and all nine
  exact attribution/parity hashes are inventoried in
  `package_build_evidence_sha256.txt`,
  `package_assets_evidence_sha256.txt`, and
  `packaged_license_notice_provenance_sha256.txt` (`verified locally`). Package
  runtime is `not run`, package status is `candidate-only`, and release remains
  `release pending`, not `production-ready`.

- 2026-07-19: Task 8 second-rereview intentional RED `flutter test --no-pub
  test/decoder_mip_evidence_test.dart
  test/capability_matrix_generation_test.dart` passed 25 tests and failed 4
  (`verified locally`). The failures named the missing `load_source()` artifact
  proof plumbing, missing pinned ledger digest, schema/manual ID-time-path
  mismatch, and accepted symlinked artifact directory.
- 2026-07-19: Task 8 second-rereview GREEN for the same command passed 29/29
  (`verified locally`). `python3 tools/generate_capability_matrix.py --check`,
  `python3 tools/validate_decoder_mip_evidence.py --check`, `flutter analyze
  --no-pub test/capability_matrix_generation_test.dart
  test/decoder_mip_evidence_test.dart`, `python3 tools/repo_lint.py`, and `git
  diff --check` passed (`verified locally`). Target/runtime/package/release
  capture was `not run`; Android remains `blocked` and release remains `release
  pending`.

- 2026-07-19: Task 8 review-remediation intentional RED `flutter test --no-pub
  test/decoder_mip_evidence_test.dart
  test/capability_matrix_generation_test.dart` passed 16 tests and failed 10
  (`verified locally`). The failures proved the missing complete frozen Plan
  014 history, immutable canonical gates, actual runtime/readback and
  runtime-diagnostic semantics, explicit LOD/base-only sampling, strict
  role/slot/sampler/dimension/byte/limit validation, and artifact-inventory
  promotion proof.
- 2026-07-19: Task 8 review-remediation focused GREEN for the same command
  passed 26/26 (`verified locally`). `python3
  tools/generate_capability_matrix.py --check`, `python3
  tools/validate_decoder_mip_evidence.py --check`, `python3
  tools/repo_lint.py`, and `git diff --check` all passed (`verified locally`).
  No physical-target, packaged-runtime, or release capture was run; those
  remain `not run` or `release pending`, and Android target execution remains
  `blocked`.

- 2026-07-19: Task 8 intentional migration RED `flutter test --no-pub
  test/capability_matrix_generation_test.dart
  test/decoder_mip_evidence_test.dart` exited 1 with 0 passing and 14 failing
  tests because the stable capability source, historical fingerprint, tracked
  evidence schema/manifest, and validator did not exist (`verified locally`).
  A focused gate-semantics RED later passed 4 tests and failed 3 because a
  record could claim release-build, cancellation-resource, and authored-mip
  gates while its package/resource facts failed or it contained only level 0
  (`verified locally`). After the minimum guards, the evidence suite passed
  7/7 and the capability suite passed 10/10 (`verified locally`).
- 2026-07-19: Final Task 8 focused integration `flutter test --no-pub
  test/capability_matrix_generation_test.dart
  test/decoder_mip_evidence_test.dart test/rewritten_glb_validator_test.dart`
  passed 21/21 (`verified locally`). `python3
  tools/generate_capability_matrix.py --check` reported the generated matrix
  current, and `python3 tools/validate_decoder_mip_evidence.py --check`
  reported the tracked manifest valid (`verified locally`). Direct Dart
  analysis of the two Task 8 test files reported no issues; `python3
  tools/repo_lint.py` and `git diff --check` passed (`verified locally`). Device
  runtime, package installation/build, physical-target capture, and local
  artifact verification are `not run`; Android target execution is `blocked`;
  release is `release pending`, not `production-ready`.

- 2026-07-19: Task 7 Important remediation RED `flutter test --no-pub
  test/flutter_scene_adapter_material_test.dart test/model_loader_test.dart
  --plain-name 'nonColor'` exited 1 with 2 failures (`verified locally`). The
  adapter case expected no diagnostic but received a typed role mismatch, and
  the loader case expected one upload but received two. After separating native
  storage role from material-slot role, the named command passed 2/2. The full
  Task 7 uploader/adapter/model group passed 122 tests with 3 intentional
  GPU-gated skips, and the integrated probe/rewriter/model/adapter/uploader
  group passed 175 tests with the same 3 skips (`verified locally`).
  `flutter analyze --no-pub` reported no issues; `python3
  tools/repo_lint.py` and `git diff --check` passed. The dependency manifests
  remain unchanged at pinned `flutter_scene`
  `5dcf6fce7dc36719e64e536faba9538fe9fa1022`. Impeller/WebGL2 authored-level
  sampling and physical/package evidence are `not run`; release is `release
  pending`, and no `production-ready` claim is made.

- 2026-07-19: Task 7 intentional RED evidence (`verified locally`) included:
  the initial uploader test failed to compile because the public internal seam
  did not exist; shared-image sampler RED failed because `additionalSamplers`
  did not exist; adapter/model-loader RED failed on the absent binding plan and
  mip-aware publication interfaces; the pure and mixed loader RED cases exposed
  the compatibility `mipAwareImporterRequired` diagnostic and loss of
  Draco-rewritten topology; malformed accounting RED accepted inconsistent
  topology/mip outputs; and the final named regression `blocks required BasisU
  publication when decoded binding is missing` exited 1 because the load
  incorrectly succeeded. The latter passed 1/1 after the minimal schema guard.

- 2026-07-19: Task 7 focused uploader/adapter/model GREEN passed 120 tests with
  3 intentional existing GPU-gated skips (`verified locally`). The required
  integrated rewriter/probe/model/adapter command, expanded with the focused
  uploader, passed 171 tests with the same 3 skips (`verified locally`). It
  covers exact mip allocation/upload indexes and bytes, renderer count limits,
  sampler retention and rejection, one shared image upload with independent
  texture samplers, all supported consuming slots, typed unsupported-slot and
  required-binding failures, mixed Draco-to-BasisU topology, cancellation with
  no rejected publication, and a later fresh load. `flutter analyze --no-pub`
  reported no issues; `python3 tools/repo_lint.py` and `git diff --check` passed
  (`verified locally`). The shared-worktree root `bash tools/run_checks.sh`
  rerun after Task 7 integration passed lint, formatting (94 files, 0 changes),
  dependency resolution, analysis, and 599 tests with 16 declared skips
  (`verified locally`). The dependency audit found the exact pinned commit in
  both manifests and no manifest diff. Impeller/WebGL2 authored-level sampling,
  physical targets, and packaged-runtime verification are `not run`; release is
  `release pending`, and this is not `production-ready` evidence.

- 2026-07-19: Task 5 review-remediation RED
  `flutter test --no-pub test/native_bridge_symbol_test.dart --plain-name
  'native codec failures preserve typed diagnostics and release bytes'`
  exited 1 at compile time and named the absent typed allocation hook,
  deadline method, bridge signature, and Zstd context-allocation API
  (`verified locally`).
- 2026-07-19: Task 5 review-remediation focused GREEN passed the real BasisU
  typed diagnostic/mutation runner 1/1 in 35 seconds, the Zstd ASan+UBSan
  success/failure/cancel and mutation runner 1/1 in 7 seconds, the executable
  codec provenance validator 1/1, the presence-aware bridge ordering test 1/1,
  and capability generation 8/8 (`verified locally`). The complete BasisU
  package passed 20/20 before the final later-level cancellation hook; final
  post-integration verification is recorded in a later entry. No physical
  target or packaged-runtime evidence was run, and release status remains
  `release pending`.
- 2026-07-19: Task 5 final post-integration verification passed (`verified
  locally`). The final BasisU package passed 20/20 and the Draco package passed
  14/14; both package analyses reported no issues. The required controller
  cancellation command passed 19/19, and its final expanded form with
  `model_loader_test.dart` passed 69 tests with 3 intentional GPU-gated skips.
  The strict rewritten-validator/provenance suite passed 4/4 and capability
  generation passed 8/8. The first full-harness candidate was `blocked` only
  by the intentionally stale final Task 7 probe fingerprint after 597 tests
  passed with 16 intentional skips; refreshing both Draco and BasisU evidence
  rows made the focused capability mutation suite GREEN. The final
  `bash tools/run_checks.sh` passed repository lint, formatting (94 files, 0
  changes), dependency resolution, analysis, and 599 tests with 16 explicit
  GPU/build-hook skips. Separate `python3 tools/repo_lint.py`, `git diff
  --check`, capability generator `--check`, and the complete BasisU vendored
  source hash manifest passed. This is host evidence only: broader codec
  allocator completeness remains `blocked`; physical targets and packaged
  runtime are `not run`; release remains `release pending`; no
  `production-ready` claim is made.

- 2026-07-19: Task 6 focused GREEN root rewriter/probe passed 49 tests with no
  failures or skips (`verified locally`). Expanded root native probe,
  compatibility rewriter, and `ModelLoader` passed 95 tests with 3 intentional
  GPU-gated skips (`verified locally`). The full BasisU package passed 20/20,
  including mirrored source identity, official single-level corpus, KHR
  profile negatives, sanitizer/control gates, official authored mips,
  malformed Level Index, aggregate preflight budget, and deterministic
  later-level cancellation (`verified locally`). Official mip fixture SHA-256
  identities are `7f13880e...f012` (ETC1S) and `4190e313...9e1` (UASTC);
  decoded level SHA-256 values are `03e1d296...0827`, `c7522e84...0c8c`,
  `48de634d...1474`, and `7a6a9f41...2075` for ETC1S L0/L1 and UASTC L0/L1.
  Actual single-level native RGBA is 1024 bytes with SHA-256
  `34219173...dae8`. Root and BasisU `flutter analyze --no-pub` reported no
  issues. Focused rewritten-validator regression passed 4/4 and proves actual
  raw output cannot enter the legacy PNG rewrite path. These results are host
  `verified locally`; Impeller/WebGL2 upload, physical targets, packaging,
  release, and `production-ready` are `not run` or `release pending`.

- 2026-07-19: Task 6 post-integration BasisU package rerun passed 20/20 with no
  skips (`verified locally`). `python3 tools/repo_lint.py` and `git diff
  --check` passed (`verified locally`). The final `bash tools/run_checks.sh`
  attempt passed repository lint, formatting (94 files, 0 changes), and
  dependency resolution, then stopped at `flutter analyze` on Task 7's
  concurrently authored RED tests: `_nativeBasisuMipMaterialGlb`, the
  `decodedImages` adapter argument, and
  `FakeFlutterSceneAdapter.authoredMipPlans` were not yet implemented
  (`blocked`). Task 6's focused and package GREEN evidence remains valid. No
  physical-target, packaged-runtime, release, or `production-ready` evidence
  is claimed.

- 2026-07-19: Task 6 intentional RED was recorded before production changes
  (`verified locally`). Root `flutter test --no-pub
  test/glb_basisu_rewriter_test.dart test/glb_native_decoder_probe_test.dart`
  exited 1: compilation named the absent `GlbDecodedBasisuMipLevel`,
  `contentRole`, and `levels` result contract, and the probe classified a raw
  two-level response as generic `decodeFailed` instead of
  `mipAwareImporterRequired`. BasisU package `flutter test --no-pub
  test/native_bridge_symbol_test.dart --plain-name 'native bridge preserves
  official ETC1S and UASTC mip pyramids'` exited 1 because
  `FsvBasisuDecodedImage` had no `content_role` or `levels`; the compiler
  emitted ten matching missing-member errors. No physical target, renderer,
  packaging, release, or `production-ready` evidence was run.

- 2026-07-19: Task 6 mixed-codec integration RED `flutter test --no-pub
  test/glb_native_decoder_probe_test.dart --plain-name 'decodeGlb carries
  Draco-rewritten topology beside authored BasisU mips'` exited 1 before the
  contract fix because `GlbNativeDecodeResult` had no `topologyBytes` or
  `topologyOutputAccounting` fields (`verified locally`). The case proves that
  a successful Draco rewrite must not fall back to the original compressed GLB
  when the following BasisU stage returns authored mip chains out-of-band.

- 2026-07-19: Task 6 mixed-codec integration GREEN added explicit
  `topologyBytes` and `topologyOutputAccounting` to the internal native decode
  result. Valid raw authored chains now retain the exact BasisU-stage input
  beside decoded images, consume only the compatibility rewriter's
  `mipAwareImporterRequired` handoff diagnostic, and reserve aggregate mip
  pixels/bytes atomically. Therefore a preceding Draco rewrite is preserved
  instead of reverting to the originally compressed GLB. The focused mixed
  case passed 1/1, the complete native probe passed 34/34, the combined
  rewriter/probe group passed 51/51, and focused analysis of the changed probe
  and test reported no issues (`verified locally`). After Task 7 consumed the
  contract, `test/model_loader_test.dart` passed 49 tests with 3 intentional
  GPU-gated skips, including mixed Draco-rewritten topology publication
  (`verified locally`). The final integrated rewriter/probe/loader group passed
  100 tests with the same 3 intentional GPU-gated skips (`verified locally`).
  Task 7 owns the remaining topology/binding result; physical-target and
  release evidence remain `not run` and `release pending`.

- 2026-07-19: Task 6 independent-rereview Dart RED was recorded before the
  contract remediation (`verified locally`). The focused terminal/payload XOR
  test exited 1 because a response containing both `decodeFailed` and decoded
  mip levels still returned topology bytes. The focused content-role test
  exited 1 because `color`, `nonColor`, and `structuralOnly` mismatches against
  request-derived `usageRole` still returned topology bytes. Both RED cases
  prove the prior probe could commit tracker/output state from malformed
  MethodChannel success envelopes.

- 2026-07-19: Task 6 independent-rereview native RED was recorded before the
  working/JNI remediation (`verified locally`). The pure native preflight
  runner failed compilation with eight missing members for aggregate retained
  RGBA, maximum applicable Level Index uncompressed bytes, and exact live
  working bytes. The platform-adapter focused test exited 1 because the JNI
  mapper had no checked `TryMapPutBytes`, `jsize` limit, pending-exception
  handling, or typed `platformMessageBytes` failure path.

- 2026-07-19: Task 6 independent-rereview remediation is complete and returned
  for rereview (`verified locally`). Native preflight now holds and checks the
  aggregate retained RGBA output for all images plus the maximum applicable
  live Zstd Level Index uncompressed buffer. Multi-image exact/one-byte-over
  working limits and second-image-boundary cancellation are atomic. The Dart
  MethodChannel contract rejects terminal diagnostics mixed with bytes or
  decoded images and rejects exact `color`/`nonColor`/`structuralOnly` role
  mismatches without tracker mutation. Per-level signed 32-bit platform-message
  limits run before codec entry; Android JNI checks `size_t` before `jsize` and
  converts byte-array allocation/copy exceptions into an atomic typed failure.
  Gap/tail, invalid/web-unsafe uncompressed length, excessive mip count, and
  opaque Draco-to-authored-BasisU accounting cases are covered. The probe
  passed 38/38, integrated rewriter/probe/loader passed 106 with 3 intentional
  GPU skips, BasisU passed 20/20, capability plus validator passed 12/12, and
  both analyses reported no issues. Final `bash tools/run_checks.sh` passed
  lint, format (94 files, 0 changes), dependency resolution, analysis, and 605
  tests with 16 intentional skips. Capability generation, repo lint, and diff
  check passed. Physical-target/package/release evidence remains `not run` or
  `release pending`; no `production-ready` claim is made.

- 2026-07-19: The documentation-only Plan 028 coordination check ran
  `bash tools/run_checks.sh`. Repository lint, Dart formatting, dependency
  resolution, and `flutter analyze` passed; the full test phase finished with
  577 passing, 16 intentionally skipped, and 4 failing tests (`blocked`). The
  failures are in the current Plan 017 worktree: two
  `glb_native_decoder_probe_test.dart` expectations, the decoder-control
  fingerprint in `capability_matrix_generation_test.dart`, and the BasisU
  provenance hash in `rewritten_glb_validator_test.dart`. The separate
  `python3 tools/repo_lint.py` and `git diff --check` checks passed (`verified
  locally`). No Plan 028 runtime or physical-target evidence was run.

- 2026-07-19: Task 4 final independent rereview approved the native request
  lifecycle with no Critical, Important, or Minor findings. Reviewer reruns
  passed Draco native bridge 11/11, BasisU native bridge 15/15, and capability
  matrix generation 8/8 (`verified locally`). The executable lifecycle and
  control mutation gates, combined-plugin link, and all fourteen decisive
  capability fingerprints were accepted. Codec-internal cancellation and
  allocation release remain Task 5; target/package/release evidence remains
  `not run` or `release pending`.

- 2026-07-19: Task 4 second-rereview mutation RED evidence (`verified
  locally`): for each plugin, five deliberately invalid Java registry owners
  and five deliberately invalid C++ registry owners compiled successfully and
  every executable exited nonzero under the strengthened lifecycle runner.
  For each Android/iOS mirrored control source, a mutant preserved the prior
  budget-terminal behavior but returned the wrong result when caller
  cancellation won; every mutant executable exited nonzero under the new
  return/reason correlation assertion.
- 2026-07-19: Task 4 second-rereview GREEN (`verified locally`): the actual
  control runner passed for both Android/iOS copies in both plugins. Full Draco
  package tests passed 13 tests and full BasisU package tests passed 17. The
  root cancellation/controller/loader/native-probe group passed 97 tests with
  3 intentional GPU skips. Capability generation `--write` and `--check`
  passed, and `test/capability_matrix_generation_test.dart` passed 8 tests,
  including per-source Task 4 fingerprint mutations. `bash
  tools/run_checks.sh` passed repo lint, unchanged formatting, dependency
  resolution, analysis, and 581 tests with 16 intentional GPU/build-hook skips
  (`verified locally`).
  Physical-target, packaged-runtime, codec-internal resource-release, and
  `production-ready` verification remain `not run` or `release pending`.

- 2026-07-19: Task 4 review-remediation RED evidence (`verified locally`): the
  combined Draco/BasisU control executable exited 1 before namespacing with
  global type redefinitions; the actual-owner lifecycle test exited 1 before
  reusable registry files existed; and the focused BasisU deadline test exited
  1 because request construction was still after `remainingOrThrow()`.
- 2026-07-19: Task 4 review-remediation GREEN (`verified locally`): the root
  cancellation/controller/loader/native-probe group passed 97 tests with 3
  intentional GPU skips. Draco `test/native_bridge_symbol_test.dart` passed 10
  tests and BasisU passed 14. Each focused actual-owner test also passed with
  500 concurrent cancel/finish Java races and 500 C++ registry races; each
  mirrored control runner passed 500 concurrent caller-vs-budget races. Both
  rewired Objective-C++ handlers passed iPhone Simulator `clang++
  -fsyntax-only` (`verified locally`, compiler-only evidence). Root, Draco, and
  BasisU analysis reported no issues. The required `bash tools/run_checks.sh`
  passed repo lint, unchanged format, dependency resolution, analysis, and 581
  tests with 16 intentional GPU/build-hook skips. `python3
  tools/repo_lint.py` and `git diff --check` passed. Physical targets, packaged
  runtime cancellation, codec-internal latency/resource release, and
  `production-ready` evidence remain `not run` or `release pending`.

- 2026-07-19: Task 4 intentional Dart RED `flutter test --no-pub
  test/glb_native_decoder_probe_test.dart` exited 1 before production edits
  because `GlbNativeDecoderProbe.decodeGlb` had no `cancellationToken`
  parameter (`verified locally`). The independent native control RED commands
  in the Draco and BasisU package roots each exited 1 with the mirrored control
  files absent; their remaining pre-existing native tests passed (Draco 6,
  BasisU 6) (`verified locally`).
- 2026-07-19: Task 4 root GREEN `flutter test --no-pub
  test/glb_native_decoder_probe_test.dart test/model_load_cancellation_test.dart
  test/model_loader_test.dart` passed 79 tests with 3 intentional GPU-gated
  skips (`verified locally`). Draco package GREEN `flutter test --no-pub
  test/native_bridge_symbol_test.dart test/flutter_scene_viewer_draco_test.dart`
  passed 10 tests; the equivalent BasisU command passed 15 tests
  (`verified locally`). Root, Draco, and BasisU `flutter analyze --no-pub`
  reported no issues after one root analysis remediation for a missing
  `unawaited` marker (`verified locally`). Both iOS Objective-C++ handlers
  passed iPhone Simulator `clang++ -fsyntax-only` checks (`verified locally`),
  which is compiler evidence only, not runtime or physical-target evidence.
  `python3 tools/repo_lint.py` passed and `git diff --check` passed
  (`verified locally`). Native codec-internal stop latency/resource release,
  physical targets, packaging, and production readiness are `not run` or
  `release pending`.

- 2026-07-19: Task 2 cleanup review-remediation intentional RED `flutter test
  --no-pub test/model_loader_test.dart` exited 1 before production edits
  (`verified locally`): 41 passed, 3 intentional GPU-gated skips, and 4 failed.
  The failures captured escaped subscription-cleanup errors for active
  cancellation, a late response, and a non-success status; a late send error
  also escaped the initial test boundary.
- 2026-07-19: Task 2 cleanup review-remediation GREEN `flutter test --no-pub
  test/model_loader_test.dart` passed: 46 passed, 0 failed, 3 intentional
  GPU-gated skips (`verified locally`). The complete focused command `flutter
  test --no-pub test/model_load_cancellation_test.dart
  test/model_loader_test.dart test/viewer_controller_load_test.dart
  test/viewer_widget_test.dart` passed: 103 passed, 0 failed, 3 intentional
  GPU-gated skips (`verified locally`). `flutter analyze --no-pub` reported no
  issues, `python3 tools/repo_lint.py` passed, and `git diff --check` passed
  (`verified locally`). Physical-target and packaging evidence remain `not
  run`; release remains `release pending`.
- 2026-07-19: Task 2 automatic stream-cleanup follow-up RED `flutter test
  --no-pub test/model_loader_test.dart --plain-name 'response stream error
  survives automatic cleanup failure'` exited 1 before its production
  correction (`verified locally`): the stream error retained its expected
  terminal result, but `cancelOnError` exposed the failing subscription cleanup.
  GREEN for the same command passed 1 test (`verified locally`) after moving
  error-path cancellation through the guarded cleanup helper.
- 2026-07-19: Task 2 independent remediation rereview approved the final
  source-cancellation slice with no Critical, Important, or Minor findings.
  The reviewer reran the focused suite at 103 passed and 3 intentional
  GPU-gated skips (`verified locally`) and confirmed guarded cleanup, typed
  first-terminal results, non-success HTTP classification, inert late network
  outcomes, shared-client reuse, and corrected Meshopt documentation.

- 2026-07-19: Task 2 remainder intentional RED `flutter test --no-pub
  test/model_load_cancellation_test.dart test/model_loader_test.dart
  test/viewer_controller_load_test.dart test/viewer_widget_test.dart` exited 1
  before production edits (`verified locally`): 92 tests passed, 3 intentional
  GPU-gated tests skipped, and 6 tests failed. The failures proved pending
  assets did not settle on cancellation, network loads used plain `Request`
  and retained their response subscription, cancellation after native
  availability still dispatched decode, and cancel-first source acquisition
  was misclassified as `modelLoadTimeout`. The uncancelled stream case reached
  the test harness's 30-second timeout and was terminated after its failure was
  recorded.
- 2026-07-19: Task 2 remainder focused GREEN `flutter test --no-pub
  test/model_load_cancellation_test.dart test/model_loader_test.dart
  test/viewer_controller_load_test.dart test/viewer_widget_test.dart` passed:
  98 passed, 0 failed, 3 intentional GPU-gated skips (`verified locally`).
  `flutter analyze --no-pub` reported no issues, `python3 tools/repo_lint.py`
  passed, and `git diff --check` passed (`verified locally`). Physical-target,
  native request-lifecycle, codec resource-control, authored-mip, packaging,
  and production readiness evidence were `not run` or remain `release
  pending`.

- 2026-07-19: Task 3 checkpoint-bound remediation RED `flutter test --no-pub
  test/meshopt_decoder_test.dart --plain-name 'ATTRIBUTES observes
  cancellation at the declared multi-interval bound'` exited 1 (`verified
  locally`). A realistic 256-vertex, 32-byte-stride ATTRIBUTES stream
  represented 8192 decoded bytes with a 4096-byte interval; cancellation
  queued between the two required boundaries was missed and the full output
  escaped.
- 2026-07-19: Task 3 checkpoint-bound remediation GREEN `flutter test
  --no-pub test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart
  test/model_loader_test.dart` passed: 69 passed, 0 failed, 3 intentional
  GPU-gated skips (`verified locally`). `flutter test --no-pub
  test/meshopt_conformance_test.dart test/rewritten_glb_validator_test.dart`
  passed 7 tests with no failures or skips, and `flutter analyze --no-pub`
  reported no issues (`verified locally`). Formatting, `python3
  tools/repo_lint.py`, and `git diff --check` passed (`verified locally`).

- 2026-07-19: The disposable clearcoat/transmission harness at
  `/private/tmp/fsv_clearcoat_transmission_demo` passed `flutter analyze` with
  no issues (`verified locally`). Runtime logs reported renderer-native
  `productionShaders` success with zero diagnostics for ToyCar,
  ClearCoatCarPaint, and GlassVaseFlowers. Simulator UI automation exercised
  both isolated selector buttons and real frames showed the clearcoat
  highlight and refractive glass; the app remained open on the transmission
  view after the Flutter tool detached. Physical iOS, Android, Web, packaging,
  and release evidence were `not run`.

- 2026-07-19: A1B32 texture Simulator smoke `flutter analyze` passed with no
  issues in the disposable harness (`verified locally`). Runtime logs reported
  `success`, 20 parts, four persisted overrides, and
  `FSV_A1B32_TEXTURE_READY applied=4/4`; a detached Simulator screenshot at
  `/private/tmp/fsv_a1b32_texture_demo/a1b32_texture_detached.png` visually
  confirms the C28 textile texture remained displayed after the Flutter tool
  detached. The A1B32 and three texture SHA-256 identities match the existing
  Plan 014 records.

- 2026-07-19: Task 3 intentional RED `flutter test --no-pub
  test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart
  test/model_loader_test.dart` exited 1 before production changes (`verified
  locally`). Compilation named the absent `cancellationToken` parameters,
  `MeshoptDecodeStopped`, and `MeshoptDecodeStopKind`; the loader behavioral
  RED also showed cancellation escaping Meshopt and lacking the expected
  `EXT_meshopt_compression` diagnostic detail.
- 2026-07-19: Task 3 focused GREEN `flutter test --no-pub
  test/meshopt_decoder_test.dart test/glb_meshopt_rewriter_test.dart
  test/model_loader_test.dart` passed: 67 passed, 0 failed, 3 intentional
  GPU-gated skips (`verified locally`). `flutter analyze --no-pub` passed with
  no issues, and `flutter test --no-pub test/meshopt_conformance_test.dart
  test/rewritten_glb_validator_test.dart` passed 7 tests with no failures or
  skips (`verified locally`), preserving official Meshopt output and validator
  behavior. Task 3 formatting, `python3 tools/repo_lint.py`, and `git diff
  --check` passed (`verified locally`).

- 2026-07-19: Final preflight-cache retry RED `flutter test --no-pub test/flutter_scene_material_extension_backend_test.dart --plain-name 'accepted replacement retries an unavailable shader preflight'` failed before the correction (`verified locally`): an unavailable preflight remained cached, with 2 shader-library loads instead of the expected retry count 3.
- 2026-07-19: Final preflight-cache retry GREEN `flutter test --no-pub test/flutter_scene_material_extension_backend_test.dart` passed: 47 passed, 12 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Final closure public/controller GREEN `flutter test --no-pub
  test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart`
  passed: 19 passed, 0 failed, 0 skipped (`verified locally`). Focused GREEN
  `flutter test --no-pub test/model_load_cancellation_test.dart
  test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 51
  passed, 3 intentional GPU-gated skips (`verified locally`). Standalone widget
  GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 38 passed,
  0 failed, 0 skipped (`verified locally`). Expanded GREEN `flutter test
  --no-pub test/model_load_cancellation_test.dart
  test/viewer_controller_load_test.dart test/model_loader_test.dart
  test/viewer_widget_test.dart
  test/flutter_scene_material_extension_backend_test.dart` passed: 136 passed,
  15 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Final closure `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 549 passed tests with 16 intentional GPU-gated skips (`verified locally`). `python3 tools/repo_lint.py` and `git diff --check` also passed (`verified locally`).

- 2026-07-19: Final publication-ownership RED demonstrated (`verified
  locally`): a pre-cancelled no-op waited behind accepted finalization, and
  `flutter test --no-pub test/model_loader_test.dart test/viewer_controller_load_test.dart test/viewer_widget_test.dart` observed `timed-out.glb` publishing after its timeout. The initial shared widget helper had a local test-scope compile error; it was corrected before behavioral execution, after which tokenless and live-token late pre-publication B failure coverage drove the widget generation fix.
- 2026-07-19: Final publication-ownership GREEN `flutter test --no-pub test/viewer_controller_load_test.dart --plain-name 'token rejection after a controller claim releases finalization once'` passed: 1 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Final publication-ownership focused GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 51 passed, 3 intentional GPU-gated skips (`verified locally`). Standalone widget GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 38 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Final publication-ownership GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart test/viewer_widget_test.dart test/flutter_scene_material_extension_backend_test.dart` passed: 135 passed, 15 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Final publication-ownership `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 548 passed tests with 16 intentional GPU-gated skips (`verified locally`). `python3 tools/repo_lint.py` and `git diff --check` also passed (`verified locally`).

- 2026-07-19: Publication-order and preflight-cache RED `flutter test --no-pub test/model_loader_test.dart test/flutter_scene_material_extension_backend_test.dart` failed before the correction (`verified locally`): the preflight-preservation seam was absent, and a controller rejection consumed the otherwise live cancellation token.
- 2026-07-19: Publication-order and preflight-cache GREEN `flutter test --no-pub test/model_loader_test.dart test/flutter_scene_material_extension_backend_test.dart` passed: 77 passed, 15 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Publication-order GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 46 passed, 3 intentional GPU-gated skips (`verified locally`). It covers pre-cancelled B, tokenless and live-token out-of-order B/C publication, and the loader-level live-token supersession classification.
- 2026-07-19: Widget GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 36 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 541 passed tests with 16 intentional GPU-gated skips (`verified locally`). `python3 tools/repo_lint.py` and `git diff --check` also passed (`verified locally`).

- 2026-07-19: Acceptance-window RED `flutter test --no-pub test/viewer_controller_load_test.dart --plain-name 'accepted publication blocks a replacement before sink settlement'` failed before synchronous controller acceptance ownership was wired (`verified locally`): C entered the sink before B settled.
- 2026-07-19: Acceptance-window GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` passed: 12 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Acceptance-window GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 42 passed, 0 failed, 3 GPU-gated skips (`verified locally`).
- 2026-07-19: Acceptance-window GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 36 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Acceptance-window `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 536 passed tests with 16 intentional GPU-gated skips (`verified locally`).

- 2026-07-19: Final rereview RED `flutter test --no-pub test/viewer_controller_load_test.dart test/viewer_widget_test.dart` failed before the finalization gate and stale-widget result guard were implemented (`verified locally`): accepted B could start C before initial overrides, reentrant diagnostics could leave stale success/error terminal state, and a late ordinary B failure cleared C widget state.
- 2026-07-19: Final rereview GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` passed: 11 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Final rereview GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 41 passed, 0 failed, 3 GPU-gated skips (`verified locally`).
- 2026-07-19: Final rereview GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 36 passed, 0 failed, 0 skipped (`verified locally`). It covers a caller-cancelled B later failing ordinarily while C's ready surface, visible model statistics, environment attempt, and render counts remain unchanged.
- 2026-07-19: Final rereview `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 535 passed tests with 16 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Final rereview `python3 tools/repo_lint.py` and `git diff --check` passed (`verified locally`).

- 2026-07-19: Second review-correction RED `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart test/viewer_widget_test.dart` failed before atomic acceptance and generation-scoped stale cancellation handling were implemented (`verified locally`).
- 2026-07-19: Second review-correction GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` passed: 8 passed, 0 failed, 0 skipped (`verified locally`). It covers post-publication cancellation before sink settlement and a stale B cancellation after C succeeds.
- 2026-07-19: Second review-correction GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 38 passed, 0 failed, 3 GPU-gated skips (`verified locally`).
- 2026-07-19: Second review-correction GREEN `flutter test --no-pub test/viewer_widget_test.dart` passed: 35 passed, 0 failed, 0 skipped (`verified locally`). It verifies a cancelled replacement preserves the ready model, configured environment, and rendered surface; ordinary-failure behavior remains covered by the existing widget error-state test.
- 2026-07-19: Second review-correction `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 531 passed tests with 16 intentional GPU-gated skips (`verified locally`).

- 2026-07-19: Review-correction RED `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` failed before the staged adapter implementation. The new assertions exposed replacement cancellation leaving `ViewerLoadStatus.error` rather than prior `success`; after test-harness imports were corrected, the absent internal atomic-adapter cancellation signal also failed compilation as intended. This is `verified locally` RED evidence.
- 2026-07-19: Review-correction GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` passed: 6 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: Review-correction GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 36 passed, 0 failed, 3 GPU-gated skips (`verified locally`). The added race test proves a cancelled old adapter publication cannot overwrite the fresh token's accepted load, and the controller test completes the cancelled sink late without material/tree mutation.
- 2026-07-19: Review-correction `bash tools/run_checks.sh` passed: repository lint, format check (92 files, 0 changes), dependency resolution, clean analysis, and 528 passed tests with 16 intentional GPU-gated skips (`verified locally`).
- 2026-07-19: Review-correction `python3 tools/repo_lint.py` and `git diff --check` both passed (`verified locally`).

- 2026-07-19: GREEN `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` passed: 6 passed, 0 failed, 0 skipped (`verified locally`).
- 2026-07-19: `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart test/model_loader_test.dart` passed: 35 passed, 0 failed, 3 GPU-gated skips (`verified locally`).
- 2026-07-19: `bash tools/run_checks.sh` passed: repository lint passed, 91 Dart files formatted with 0 changes, dependency resolution completed, `flutter analyze` reported no issues, and the full suite passed 527 tests with 16 intentional GPU-gated skips (`verified locally`). The first invocation exposed this promoted plan's missing literal `## Steps` heading; the heading was added and the rerun passed.
- 2026-07-19: `python3 tools/repo_lint.py` passed (`verified locally`).
- 2026-07-19: `git diff --check` passed (`verified locally`). No physical-target, native request-lifecycle, codec resource, authored-mip, packaging, or production-ready evidence was run; those remain `not run` or `release pending` as already scoped by this plan.

- 2026-07-19: `flutter test --no-pub test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` intentionally failed RED (0 passing,
  2 loading failures) before production changes. The focused failures named
  the absent `ModelLoadCancellationController` and
  `ModelLoadCancellationToken`, the missing
  `ViewerDiagnosticCode.modelLoadCancelled`, and the missing
  `cancellationToken` parameters on controller/sink loads. This is
  `verified locally` RED evidence only; all later Plan 017 milestones remain
  `not run`.

- 2026-07-15: Plan-authoring verification passed the repository link/path
  audit, `python3 tools/repo_lint.py`, `git diff --check`, and the root
  `bash tools/run_checks.sh` harness at `+503 ~16`; 88 Dart files formatted
  with zero changes and analysis reported no issues. These results validate
  the plan and existing repository baseline only. All Plan 017 implementation,
  native target, upstream, physical-device, packaging, and release gates are
  `not run`.

- 2026-07-19: Task 5 intentional RED was recorded in both package roots
  (`verified locally`). Each `test/native_bridge_symbol_test.dart` command
  exited 1 because its codec-control provenance manifest was absent: Draco
  reported 11 passed/1 failed and BasisU reported 15 passed/1 failed. A later
  focused BasisU provenance mutation exited 1 on the deliberately stale
  `zstddeclib.c` patched hash. These failures preceded the corresponding
  production/provenance corrections.
- 2026-07-19: Task 5 repo-local codec-control slice is partial and pending
  review. Exact upstream identities, licenses, original hashes, patched hashes,
  and compiled-source manifests are recorded beside both vendored codecs;
  mutation tests reject changed hashes, cancellation ownership, reserve calls,
  and RAII release calls (`verified locally`). No `flutter_scene` fork,
  upstream checkout, dependency pin, branch, worktree, commit, stage, push, or
  GitHub write was used.
- 2026-07-19: Draco request control reaches the pinned header, topology,
  attribute, and bounded output loops without global or thread-local mutable
  state. The full Draco package suite passed 14/14, including the official Box
  fixture, mirrored controls, race/mutation runners, and zero-live-byte outer
  reservation release (`verified locally`). Codec-internal STL/new allocator
  interception is still `blocked`: the conservative bridge envelope does not
  prove that every pinned Draco allocation reserves before allocation.
  Therefore Task 5 Steps 2 and 4 remain unchecked and no allocator-completeness
  claim is made.
- 2026-07-19: BasisU/Zstd request control reaches init, validated metadata,
  image-level, block-row, and the exact Zstd frame block-output loop. The
  callback/opaque/output count live on the request-owned `ZSTD_DCtx`; the KTX2
  state reserves decoded-level vector bytes before growth and clears/releases
  them on every controlled return. A pinned KTX2 Zstd runner cancelled after
  the first decoded block under ASan+UBSan and proved live bytes returned to
  zero with allocation count equal to release count (`verified locally`). The
  full BasisU package suite passed 19/19 and preserved official fixture bytes.
  Broader BasisU container allocator interception beyond this decoded-level
  allocation is not yet proven, so Step 3 remains unchecked.
- 2026-07-19: Task 5 independent review found three executable-evidence gaps
  (`verified locally`): BasisU budget rejection, allocation failure, and codec
  corruption were not separately exercised; decoded-level reserve/release and
  the allocation-size seam still relied on marker checks; and the heap-backed
  Zstd context allocation was outside request accounting. The corresponding
  remediation RED failed to compile before the typed testing hook, deadline
  terminal reason, five-argument bridge entry, and
  `ZSTD_fsv_dctx_allocation_size` contract existed.
- 2026-07-19: Task 5 review remediation is implemented and pending final
  rereview (`verified locally`). The real pinned KTX2/Zstd runner now
  distinguishes `budgetExceeded`, `allocationFailed`, and `decodeFailed`, while
  caller cancellation/deadline produces no codec diagnostic. The decoded-level
  vector capacity seam is consumed and enforced; compiled/executed mutants
  bypassing decoded-level/Zstd reserve, state release, or the allocation-size
  seam are rejected. The heap-backed `ZSTD_DCtx` is reserved before allocation
  and released after success, corruption failure, cancellation, and allocation
  failure. Compiled Zstd checkpoint/context-reserve/context-release mutants are
  rejected under ASan+UBSan. Exact patched hashes and generated capability
  evidence were refreshed. Broader Draco STL/direct-`new` interception and
  broader BasisU container allocator coverage remain `blocked`, so Task 5
  Steps 2-5 and M3 remain open; physical-target, packaging, release, and
  `production-ready` evidence remain `not run` or `release pending`.
- 2026-07-19: Task 5 review-remediation integration is complete and ready for
  independent rereview (`verified locally`). Final host checks passed BasisU
  20/20, Draco 14/14, the exact expanded controller/loader command at 69
  passed with 3 intentional GPU skips, and the root harness at 599 passed with
  16 intentional skips. The separate repo lint, diff, capability-current, and
  complete vendored-source hash checks passed. No `flutter_scene` fork or
  upstream edit was made. The remaining allocator-completeness and target/
  package/release gates stay literal and unchanged.
- 2026-07-19: Root native probe/loader/validator integration passed 79 tests
  with 3 intentional GPU-gated skips, and the focused probe+rewritten-validator
  rerun passed 36/36 (`verified locally`). Root, Draco, and BasisU analysis
  reported no issues. The first full `bash tools/run_checks.sh` attempt was
  `blocked` by an intentionally stale capability evidence fingerprint after
  the new working-budget field; the fingerprint and generated matrix were
  refreshed and the focused capability suite passed 8/8 (`verified locally`).
  Final full-harness, repo-lint, and diff evidence is recorded after this log
  update. Physical targets, packaged runtime, release evidence, authored mip
  preservation, renderer work, and `production-ready` evidence are `not run`
  or `release pending`.
- 2026-07-20: Task 5B strict-TDD REDs were recorded before the production
  slices (`verified locally`): the joint Edgebreaker topology/traversal slice
  first failed on its absent topology allocator marker, and the later focused
  entropy/RANS and mesh-prediction contracts each failed on their absent
  request-allocator marker. Edgebreaker-owned topology/hole/visited/seam and
  local map/vector scratch, standard/predictive/valence traversal storage,
  attribute traversal stacks/visited/point ids, reachable symbol/RANS tables,
  and every mesh prediction scheme accepted by the decoder factory now use
  the existing request control. The compiled `SymbolBitDecoder` remains
  unconverted only behind a mechanically enforced zero-reference mesh decode
  boundary; no Task 5B owner family remains incomplete.
- 2026-07-20: The official Box fixture preserved byte-identical attributes and
  indices and exercised 79 request-owned allocation ordinals. Success and
  every injected failure returned zero live bytes with balanced successful
  reservations; failures were typed `allocationFailed`. One ASan+UBSan runner
  passed success, ordinals 1-79, caller cancellation, deadline, working-budget
  rejection, and truncated/corrupt payload without sanitizer findings
  (`verified locally`). Android/iOS compiled-source closure, exact vendored
  hashes, and provenance/asset mutation contracts passed.
- 2026-07-20: Task 5B package verification passed
  `flutter_scene_viewer_draco_test.dart` (2/2),
  `package_asset_contract_test.dart` (1/1), and the complete
  `native_bridge_symbol_test.dart` (21/21), all serially (`verified locally`).
  `python3 tools/repo_lint.py` and `git diff --check` passed. The repo-wide
  `bash tools/run_checks.sh` passed repo lint, format, dependency resolution,
  and analysis but root Flutter tests remain `blocked` by the broader stale
  Task 5 decoder-control capability fingerprint set (first reported
  `compression/decode.h`); that parent-owned integration set spans files
  outside Task 5B and was not changed here. Direct decoder/geometry/attribute,
  sequencer/controller, sequential-topology, metadata/status, and bridge-output
  owner families remain outside this slice, the conservative outer reservation
  stays in place, and Task 5/M3 remains open. Physical-target, packaging,
  release, and `production-ready` evidence remain `not run` or `release
  pending`.
- 2026-07-20: Task 5B Important-review corrections passed strict focused
  RED→GREEN (`verified locally`). A reached-owner mutant initially reduced the
  official Box tracked allocation baseline from 79 to 78 and escaped; the
  native runner now locks exactly 79 and the Dart stdout contract plus compiled
  mutant reject that shrink. Exact source wiring rejects five mutations
  (`nullptr`, one dropped prediction branch, dropped nested valence allocator,
  and disabled move/swap propagation traits). The `SymbolBitDecoder` audit now
  derives the 61-source Android pruned closure, requires exact iOS aggregate
  equality, excludes only its implementation source, and rejects one injected
  use in a compiled entropy helper. The complete native suite passed 21/21,
  serial package/asset suites passed 2/2 and 1/1, and ASan+UBSan exited 0 at the
  locked 79-ordinal baseline. Repo lint, Dart formatting, and diff checks
  passed. The root harness was not rerun; its separately owned stale capability
  fingerprints remain `blocked` as previously recorded.
- 2026-07-20: Task 5B's final two Important evidence gaps passed strict focused
  RED→GREEN (`verified locally`). Five new `nullptr` mutants first escaped: the
  three separate prediction-factory control-source assignments, valence
  control retention, and the valence entropy-call handoff. Exact occurrence
  rules now reject all five while the normal contract remains green. The
  SymbolBit audit now recursively expands repo-local includes from the exact 61
  selected translation units to 203 reachable files (61 `.cc`, 142 `.h`),
  excludes only the defining `symbol_bit_decoder.cc/.h` owners, and rejects
  injected references in both a compiled entropy source and a reachable
  entropy header. The full native suite passed 21/21, serial package/asset
  suites passed 2/2 and 1/1, and Dart format, repo lint, and diff checks passed.
  Sanitizers and the root harness were not rerun because neither production
  code nor the native runner changed; previously recorded root fingerprints,
  residual owner families, and release/physical-target gates remain unchanged.
- 2026-07-20: Task 5C received final independent approval after the four
  remaining executable allocator-bypass gates were added (`verified locally`).
  Current locked production baselines are Box 110 and sequential 68; the 14
  compiled/run mutants include PointAttribute 68→65, CornerTable 110→109,
  quantization minima 68→67, and inverse-quantization scratch 68→67. The 28
  supplementary source mutants and immutable fixture regeneration also pass.
  Metadata/status, native bridge/result/platform ownership, BasisU allocator
  completeness, physical-target evidence, packaging, and release remain open;
  physical targets are `not run` and release is `release pending`.
- 2026-07-20: Task 5D.1 strict-TDD metadata/status ownership is implemented
  and `verified locally`. The behavioral pre-slice RED failed at the absent
  destination-controlled GeometryMetadata and Status contracts; a later
  review RED caught changed MetadataHasher semantics before the zero-copy
  string-view parity fix. Geometry, attribute, and nested metadata objects;
  entry/submetadata maps and names; entry blobs; attribute metadata vectors;
  decoder traversal scratch; destination-bound deep copies; ordinary detached
  copy/move; and controlled non-SSO Status text now use explicit request
  ownership. Large blob copying and metadata traversal have bounded stop
  checks, and stopped Status paths allocate no diagnostic.
- 2026-07-20: The deterministic 5,332-byte metadata fixture regenerates
  byte-for-byte offline from immutable source object
  `8794499f9f7e72c1cd64aea7242081a2d1ed5da3`; commit, source object, source
  archive, license, generator, and payload mutations are rejected. Exact
  runtime locks are 47 source allocations, 22 destination-copy allocations,
  Status 1/1, EntryValue 4/2, ordinary Metadata detach 3, calibrated blob stop
  14, peak 29,418 bytes, and corrupt input 15. All ordinals 1-47, one-byte-under
  budget, caller cancel/deadline, concurrent controls, source-control lifetime,
  and 27 compiled mutants pass. Portable dead-strip/garbage-collection plus
  `nm` inspection proves compiled structural metadata/property population
  owners are absent from the accepted link closure. Official Box 110 and
  sequential 68 remain unchanged; metadata ASan+UBSan exits 0 with exact
  release/live-byte assertions (LeakSan disabled on macOS).
- 2026-07-20: Task 5D.1 serial package verification passed API 2/2, asset 1/1,
  and complete native 31/31 in 04:58. Repo lint and focused Dart format passed.
  `bash tools/run_checks.sh` passed lint, format, dependency resolution, and
  analysis, then remained `blocked` at root Flutter 626 passed/16 gated skips/
  6 failures because the broader Task 5 decoder-control capability fingerprint
  is intentionally stale (first literal file `compression/decode.h`). Per the
  Task 5D.1 brief it was not refreshed while later Task 5D sources remain open.
  Native request/preflight, bridge result/output, platform serialization, outer
  reservation removal, physical targets, packaging, and release evidence remain
  open, `not run`, or `release pending`; Task 5D and Task 5/M3 are not closed.
- 2026-07-20: Task 5D.1 independent-review remediation completed strict
  RED→GREEN (`verified locally`). The pristine immutable
  `metadata_encoder.cc` RED failed with three public STL conversion errors; the
  long-literal RED exited 211 after observing two host allocations for one
  request allocation; and the corrupt final `DecodeMeshFromBuffer` RED exited
  157 because its returned `Status` retained no live request allocation.
  Null-control Metadata/GeometryMetadata/EntryValue storage now preserves the
  exact upstream `std::map`/`std::vector` public source behavior, including
  attribute pointer identity, while controlled canonical storage exposes lazy
  detached snapshots only to explicit legacy encoder/tool access. Exact return
  type static assertions pass, pristine `metadata_encoder.cc` compiles
  unchanged, and Metadata remains non-polymorphic without a virtual destructor.
  The successful controlled decode census reports 47 host-level allocations,
  all 47 accounted for by the request allocator; a compiled accessor-injection
  mutant proves that materializing a legacy snapshot on the accepted decoder
  path fails this boundary. Android and iOS bridge sources are identical and
  their headers expose no standalone Draco type or include. The audited local
  host layout is Status/EntryValue/Metadata/GeometryMetadata = 96/88/168/248
  bytes; the private layout change is intentional and internal because each
  plugin compiles vendored Draco from source and no affected type crosses its
  supported bridge ABI.
- 2026-07-20: Final controlled error handoff now retains request ownership
  through both `DRACO_RETURN_IF_ERROR` and the `StatusOr(Status&&)` boundary;
  char-literal Status construction uses `std::string_view` without an implicit
  host `std::string`. Destination copy failure sweeps exact ordinals 1-22 with
  balanced release, and final corrupt Status allocation failure is calibrated
  at ordinal 14 with zero live bytes. All 27 compiled mutants are rejected,
  including accepted-path snapshot, long-literal temporary, macro handoff, and
  StatusOr handoff mutants. Rebuilt metadata ASan+UBSan exits 0 across these
  paths (`detect_leaks=0` on macOS); the normal non-sanitized executable owns
  the global-allocation census because ASan interposes the runner's custom
  `operator new`. Serial package verification passes API 2/2, provenance asset
  1/1, and complete native 32/32 in 04:56. Official Box 110 and sequential 68
  remain unchanged. Mandatory `bash tools/run_checks.sh` passed repo lint,
  format (97 files, zero changes), dependency resolution, and analysis, then
  reached root Flutter 627 passed/16 gated skips/6 failures, all caused by the
  deliberately stale decoder-control capability fingerprint (first literal
  `compression/decode.h`). The fingerprint was not refreshed; broader Task 5D,
  physical-target, packaging, and release gates retain their prior status.
- 2026-07-20: Task 5D.1 final independent rereview is approved with no
  Critical, Important, or Minor findings (`verified locally`). The reviewer
  independently reran the public-surface, source-contract, 27-mutant, and
  ASan+UBSan gates and confirmed source 47, destination 22, peak 29,418,
  final-Status failure ordinal 14, corrupt 15, and private layout
  96/88/168/248. Task 5D.2/5D.3, BasisU allocator completeness, physical
  targets, packaging, and release remain open; physical targets are `not run`
  and release is `release pending`.
- 2026-07-20: Task 5D.2 strict ownership/lifetime REDs are implemented and
  `verified locally`, pending independent review. Allocation records now bind
  pointer, bytes, alignment, and causal outcome; exact release rejects a
  mismatch without losing the valid retry. Request, preflight, decoded
  intermediates, output, result, and diagnostics use the request control.
  Owner leases guard control destruction. Same-control assignments steal
  allocator-compatible storage with zero new allocation attempts, while
  cross-control construction and assignment deep-rebind to the destination.
  Typed caller, deadline, budget, allocation, and corruption terminals require
  no post-stop native diagnostic allocation. JNI and ObjC++ materialize managed
  terminal diagnostics only after native stop and destroy native results before
  the control finishes. The conservative outer reservation remains for Task
  5D.3.
- 2026-07-20: Exact Task 5D.2 bridge-inclusive baselines are official Box 132
  allocations/25,692 peak bytes, sequential 96/21,137, metadata 63/35,457, and
  two-primitive Box 256/29,126; codec-only counts remain 110, 68, and 47. Every
  bridge-inclusive ordinal is injected, partial output stays empty, successful
  reservations/releases balance, and live bytes return to zero. Box
  peak-minus-one (25,691) is typed `budgetExceeded`. Twenty-three isolated
  bridge-owner mutants plus three caller/deadline/post-stop terminal mutants
  are rejected. Focused Box, sequential, metadata, and ownership runners pass
  ASan+UBSan with macOS LeakSan disabled and exact live/release assertions
  retained (`verified locally`).
- 2026-07-20: The first post-fix complete serial native run reached 35 tests but
  failed the standalone `Android and iOS native budget preflight accept exact
  limits and reject overflow` runner at compile time: its old `std::string` and
  `std::vector<FsvDracoPrimitiveRequest>` assumptions did not match the owned
  aliases, then the migrated test exposed its omitted `fsv_draco_control.cc`
  link dependency. Both RED attempts exited 1; the test-only compatibility fix
  left production ownership unchanged and the focused runner passed 1/1.
  Required post-fix serial native verification then passed 36/36 in 07:12.
  Serial API passed 2/2, asset/provenance passed 1/1, focused Dart format changed
  0 files, repo lint passed, and `git diff --check` passed. The root harness
  passed lint, format, dependency resolution, and analysis, then reached 627
  passed/16 gated skips/6 failures; all six are pre-empted by the deliberately
  stale decoder-control capability fingerprint, first literal file
  `compression/decode.h`. That fingerprint was not refreshed. Task 5D.3, Task
  5/M3, physical targets, packaging, and release remain open, `not run`, or
  `release pending`; this is not `production-ready`.
- 2026-07-20: Task 5D.2 independent-review remediation began with strict RED
  evidence (`verified locally`). The focused ownership runner failed to compile
  because the codec adapter discarded its causal allocation record before
  release and accessor/request/diagnostic bridge owners still allowed ordinary
  null-control copies. The executable fake-JNI allocation-failure runner exited
  1 with `failed=1 releases=0 live=0`, proving the acquired UTF buffer was not
  released when controlled string assignment threw. Task 5D.2 rereview remains
  open; Task 5D.3, physical targets, and release remain `not run` or
  `release pending`.
- 2026-07-20: Task 5D.2 independent-review remediation is implemented and
  `verified locally`, pending independent rereview. JNI UTF chars now have an
  immediate exactly-once scope release even when controlled string assignment
  throws. The private codec adapter retains the causal pointer, bytes,
  alignment, and outcome record through exact release; wrong pointer, bytes,
  alignment, and double release are compiled mutants and cannot consume the
  valid retry. Its 128 inline records spill into request-controlled storage, so
  the inline threshold is not a fixed model-size ceiling; allocation 129 and
  two-control cross-release/cross-charge behavior pass. Accessor schemas,
  primitive requests, and diagnostics are move-only unless a destination
  control is explicit. No global/TLS hook, `flutter_scene` fork, pin change,
  upstream/pub-cache write, or branch/commit/stage/push operation was used.
- 2026-07-20: Final Task 5D.2 remediation verification is `verified locally`.
  Serial native passed 38/38 in 07:24. Fresh ASan+UBSan ownership, Box,
  sequential, and metadata executables exited 0 with exact locks owner family
  17; Box 132 bridge/110 codec/25,692 peak and two-primitive 256/29,126;
  sequential 96/68/21,137; metadata 63/47/35,457, destination 22, final Status
  failure ordinal 14, and corrupt 27. macOS LeakSan remained disabled while
  exact live-byte/release assertions stayed enabled. Serial API passed 2/2,
  provenance asset 1/1, focused format changed zero files, repo lint passed, and
  `git diff --check` passed. `bash tools/run_checks.sh` passed repo lint, Dart
  format (97 files, zero changes), dependency resolution, and analysis, then is
  `blocked` at root Flutter 627 passed/16 gated skips/6 failures solely by the
  intentionally stale Task 5 decoder-control capability fingerprint, first
  literal file `compression/decode.h`; the fingerprint was not refreshed while
  Task 5D.3 remains open. Physical targets are `not run`, packaging/runtime is
  `candidate-only` or `not run`, release is `release pending`, and no
  `production-ready` claim is made.
- 2026-07-20: Task 5D.2 final independent rereview is approved with no
  Critical, Important, or Minor findings (`verified locally`). JNI controlled
  request construction now releases acquired UTF buffers exactly once on
  allocation failure. The codec adapter preserves causal pointer/bytes/
  alignment records, rejects wrong-pointer/bytes/alignment and double-release
  mutants, supports request-controlled overflow beyond 128 simultaneous
  records, and isolates concurrent controls. Unsafe ordinary bridge-owner
  copies are deleted and zero-size codec allocations normalize symmetrically.
  Final serial native verification passes 38/38; ASan+UBSan preserves bridge/
  codec locks Box 132/110/25,692, two-primitive 256/29,126, sequential
  96/68/21,137, and metadata 63/47/35,457 with destination 22 and final Status
  failure ordinal 14. Task 5D.3, BasisU allocator completeness, physical
  targets, packaging, and release remain open; physical targets are `not run`
  and release is `release pending`.
- 2026-07-20: Task 5D.3 platform-serialization strict-TDD RED is recorded
  (`verified locally`). The executable fake Android/iOS copy gate exited 1
  because `fsv_draco_platform_serialization.h` did not exist; the missing seam
  covers signed platform-size rejection, managed allocation/copy failure,
  cancellation before and after each attribute/index payload copy, retained
  native-result charge, cleanup, and atomic no-partial-response behavior.
  Production platform adapters, outer-reservation removal, final exact peaks
  and ordinals, capability fingerprints, physical targets, packaging, and
  release remain open, `not run`, or `release pending`.
- 2026-07-20: Task 5D.3 implementation and integration verification are
  `verified locally`, pending independent review. The repository-local Android
  and iOS platform-copy contract rejects signed-size overflow, checks the
  request before allocation and after allocation/copy, releases every partial
  destination, and preserves atomic no-response behavior. JNI now checks and
  clears allocation/copy exceptions, releases non-null local refs returned with
  exceptions, propagates map/list/object construction failure, and discards
  partial diagnostics/primitives/responses; iOS catches typed-data and managed
  collection-construction exceptions and rechecks cancellation after response
  construction. Native result allocations stay charged until platform copying
  completes and are destroyed before registry finish/control destruction.
  Managed Java/Objective-C/Flutter message storage remains outside
  `maxNativeWorkingBytes`; no global/TLS current-request hook is used.
- 2026-07-20: Task 5D.3 compiled/run mutation and exact-accounting gates are
  `verified locally`. Five platform-copy mutant families pass on each Android/
  iOS mirror; the ten-case fake JNI runner rejects eight exception, local-ref,
  cleanup, and collection-failure mutants; ordering/result-charge/response-
  atomicity mutants and a reintroduced outer-reservation mutant are rejected.
  With the conservative outer reservation removed, exact bridge/codec/peak
  locks are Box 132/110/24,926, deterministic two-primitive 256/27,594,
  sequential 96/68/20,921, and metadata 63/47/30,083. Limits one byte below
  each peak return typed `budgetExceeded`; metadata destination 22, final Status
  failure ordinal 14, and corrupt request-inclusive 26 remain locked. Success,
  cancellation, deadline, budget, heap failure, corruption, ordinary
  diagnostic, concurrency, and multi-primitive paths return to zero live bytes.
- 2026-07-20: Final Task 5D.3 host verification is `verified locally`. Serial
  native passed 43/43 in 08:12, public API passed 2/2, attribution/provenance
  asset contract passed 1/1, and capability/fingerprint tests passed 13/13.
  Fresh ASan+UBSan ownership, Box/two-primitive, sequential, metadata, and both
  platform-copy executables exited 0; macOS used `detect_leaks=0` because
  LeakSanitizer is unavailable while exact live/release assertions remained
  enabled. `bash tools/run_checks.sh` passed repo lint, Dart format (97 files,
  zero changes), dependency resolution, analysis, and root Flutter 633 passed/
  16 declared GPU skips. Focused format, `python3 tools/repo_lint.py`, and
  `git diff --check` passed. Physical Android/iOS targets are `not run`;
  packaging/runtime remains `candidate-only` or `not run`; release is `release
  pending`; this is not `production-ready`. BasisU broader container allocator
  coverage remains open, so Task 5 Steps 2-5 and M3 remain unchecked. No
  `flutter_scene` fork/edit/pin change, upstream/pub-cache write, branch/
  worktree operation, commit, stage, push, or GitHub write occurred.
- 2026-07-20: Task 5D.3 independent review found one Important iOS delivery
  gap and remediation began with strict RED (`verified locally`). When
  typed-data/copy or managed collection construction returned `nil`, registry
  finish could still report success, but the main-thread delivery block handled
  only non-`nil` success and invoked no Flutter result. The new executable
  Objective-C++ failure seam exited 1 because `DeliverDecodeCompletion` was
  undeclared, directly naming the missing exactly-once typed terminal path.
  Production remediation, capability fingerprint refresh, and full reverification
  remain open; physical targets are `not run` and release is `release pending`.
- 2026-07-20: Task 5D.3 post-remediation host reverification is `verified
  locally`, pending independent review. The focused real Objective-C++
  exactly-once terminal delivery seam and both compiled/run delivery mutants
  pass. The serial Draco native suite passes 44/44 in 09:53, including signed
  platform-size, pre/post-copy stop, fake JNI exception/local-reference cleanup,
  ordering, response atomicity, outer-reservation removal, and exact
  peak-minus-one gates. API is 2/2, package attribution/provenance is 1/1, and
  capability generation/fingerprints are 13/13. Fresh ASan+UBSan ownership,
  Box/two-primitive, sequential, metadata, and Android/iOS platform-copy
  runners exit 0; the ObjC++ delivery runner is sanitizer-covered by the native
  suite. macOS runs with LeakSanitizer disabled (`detect_leaks=0`) while exact
  live-byte/release assertions remain enabled. `bash tools/run_checks.sh`
  passes repo lint, format (97 files, zero changes), dependency resolution,
  analysis, and 633 root tests with 16 declared/gated GPU skips; focused format
  passes 3 files with zero changes, `python3 tools/repo_lint.py` and `git diff
  --check` pass. Physical Android/iOS targets are `not run`, package runtime is
  `candidate-only` or `not run`, release is `release pending`, and this is not
  `production-ready`. BasisU allocator completeness and Task 5/M3 remain open.
- 2026-07-20: Task 5D.3 final host reverification is `verified locally`,
  pending independent review. Source freeze first exposed exactly one stale
  Android JNI capability fingerprint (`0662c2...`); the live source and
  generator were refreshed to `f031ce...`, the generated matrix was rewritten,
  and strict generation passed. Intentional JNI input-RAII REDs are recorded as
  `ForEach live6150` and `MapGet live4096`; final focused JNI passes 1/1 in
  00:22, and the real Objective-C++ delivery/lifetime seam passes 1/1 in 00:52
  under ASan+UBSan. The initial serial native run was 43/44 in 08:56 solely
  because a test still expected direct `MapGet`; production already used the
  safer `JniLocalRef` path. After the assertion was made RAII-aware, the focused
  contract passed 1/1 and clean serial native passed 45/45 in 09:12. API plus
  provenance asset tests pass 3/3, capability tests 13/13, and explicit
  ASan+UBSan Box/two-primitive (132/110/24,926 and 256/27,594), sequential
  (96/68/20,921), metadata (63/47/30,083), and both platform-copy contracts
  pass. Ordering/lifetime mutation evidence is compiled/run; source-order
  inspection is supplementary only. `bash tools/run_checks.sh` passes 633 root
  tests with 16 declared GPU skips; focused format, repo lint, and diff checks
  pass. Physical targets remain `not run`, package runtime is `candidate-only`
  or `not run`, release is `release pending`, and this is not
  `production-ready`; BasisU allocator completeness, Task 5 Steps 2-5, and M3
  remain open.
- 2026-07-20: Task 5D.3 final independent rereview is approved (`verified
  locally`). The reviewer confirmed bounded JNI input local-reference cleanup
  and exception propagation over 2,048 entries, with four compiled/run mutants,
  plus the real Objective-C++ `BuildManagedDecodeResponse` result/control/
  retained-charge/partial-response lifetime seam and its four compiled/run
  mutants under ASan+UBSan. Fresh focused results were 1/1 in 00:20 and 1/1 in
  00:51. The clean serial package result remains 45/45 in 09:12; capability
  generation, repository lint, and diff checks pass. Draco Step 2 is closed.
  BasisU allocator completeness, Task 5 Steps 3-5, and M3 remain open; physical
  targets are `not run`, package runtime is `candidate-only` or `not run`,
  release is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.1 required allocator-interface RED is recorded
  (`verified locally`). Compiling the focused production-header runner against
  the unmodified `HEAD` `basisu_containers.h`/`basisu_containers_impl.h` exited
  1 and literally reported `expected class name` for
  `basisu::fsv_vector_allocator`, no `basisu::fsv_allocation_result`, and no
  `basisu::fsv_allocation_outcome`. Independent resumption inspection then
  found a controlled reserve-shrink raw-allocator bypass and missing
  failure-atomic copy `try_*` seam. The remediation test was changed first;
  its direct clang RED exited 1 with `no member named 'try_copy_assign' in
  'basisu::vector<unsigned int>'`. The minimal GREEN retained the request
  allocator on shrink temporaries and added destination-controlled,
  failure-atomic `try_copy_assign`; the direct runner then exited 0.
- 2026-07-20: Task 5E.1 allocator/control GREEN is `verified locally`, pending
  independent controller review. The explicit non-global allocator returns
  typed success/stopped/budget/heap outcomes and a move-only exact
  pointer/bytes/alignment/allocator record. Mirrored Android/iOS controls own
  zero-size normalization, injectable heap failure, first-reason stop,
  exact-release mismatch accounting, peak/live/allocation/release counters,
  and lifetime owner/live-byte assertions. Null vectors retain upstream bytes;
  controlled growth/shrink, clear/destruction, raw ownership rejection,
  over-alignment, overflow, all seven allocation ordinals, 384-byte exact peak
  and 383-byte rejection, 300 live blocks, same/cross-control construction/
  copy/move/assignment/swap, nested relocation, and concurrent isolated
  controls are executable gates.
- 2026-07-20: Task 5E.1 focused mutation and sanitizer verification is
  `verified locally`. The focused control gate passed 1/1 in 22.21s. Bypassed
  live `basisu_containers_impl.h` allocation, missing old release, actual
  cross-control move-assignment theft, raw-free-controlled, allocation-record
  swap, and dropped exact-release validation each had `source-diff=true`,
  compile exit 0, and run exit -6 on Android and iOS: 12/12 printed mutant
  results. The ASan+UBSan vector gate passed 1/1 in 4.29s with macOS
  `detect_leaks=0`; exact live-byte/owner/release assertions remained enabled.
- 2026-07-20: Task 5E.1 serial package verification is `verified locally`.
  Native passed 19/19 in 124.74s, API passed 2/2 in 1.85s, package
  attribution/provenance passed 1/1 in 1.75s, package analyze/compile reported
  no issues in 1.57s, and the root provenance integration passed 1/1 in
  20.72s. Focused format checked 3 files with zero changes in 0.31s,
  `python3 tools/repo_lint.py` passed in 0.03s, and `git diff --check` passed in
  0.06s. The broader root harness passed lint, 97-file format, dependency
  resolution, and analysis, then reached 627 passed/16 declared GPU skips/6
  failures in 32.55s; every failure is pre-empted by the deliberately stale
  decoder-control capability fingerprint, first literal file
  `packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.h`.
  That fingerprint was not refreshed. Full evidence is in
  `.superpowers/sdd/task-5e1-basisu-container-allocator-foundation-report.md`.
  Task 5 Steps 3-5 and M3 remain unchecked; physical Android/iOS are `not run`,
  package runtime is `candidate-only` or `not run`, release is `release
  pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.1 first independent review found three Important
  ownership-contract gaps. A live `fsv_allocation_result` could be
  move-assigned and lose its exact token; nested cross-control operations
  default-constructed raw/null-allocator children; and the focused runner did
  not exercise existing-child relocation or nontrivial transactional paths.
  The correction test changed first. Its direct NDEBUG compile exited 1 in
  0.74s with the failing non-move-assignable record assertion, no allocation
  record `swap`, and no vector allocator-identity accessor. The GREEN deletes
  record move assignment, uses full-field exact-token swaps, recursively
  preserves child allocators, and makes copy/move/shrink/swap transactional.
  Nontrivial relocation uses a bitwise/nothrow move or copy-constructible
  rollback contract; allocation succeeds before source mutation. Final
  exact-diff inspection also found that a draft branch could `memcpy` over a
  successful nontrivial relocation. The destructor-side-effect fixture made
  that executable RED exit 106; the mutually exclusive mover/`memcpy` GREEN
  returned the same runner to exit 0.
- 2026-07-20: Task 5E.1 review correction verification is `verified locally`,
  but was superseded before re-review by the final moved-from/no-exception
  correction below. Its then-current 10/10-per-platform mutation, sanitizer,
  serial, package, provenance, format, lint, diff, and root-harness evidence is
  historical and was not reused as final closure evidence.
- 2026-07-20: Task 5E.1 final moved-from/no-exception strict-TDD REDs are
  recorded (`verified locally`). Before the final production correction, the
  NDEBUG runner exited 109 because move construction cleared the moved-from
  vector's request allocator binding; the `-fno-exceptions` NDEBUG runner
  exited 119 because controlled potentially-throwing nontrivial growth was
  accepted. The historical REDs were retained literally and were not recreated
  by reverting safe production code. Fresh final-source direct runners both
  compile and exit 0: NDEBUG compile/run 0.93s/0.40s and no-exception
  compile/run 0.57s/0.31s. The destination retains exact ownership once, the
  moved-from source retains its request allocator for controlled reuse, and
  exception-disabled controlled throwing relocation rejects before allocation
  while the raw/null path retains pinned BasisU parity.
- 2026-07-20: Task 5E.1 fresh final-source closure is `verified locally`,
  but its source freeze was superseded by the second independent-review
  remediation below. Its 11/11-per-platform mutation, sanitizer, serial,
  package, provenance, format, lint, diff, and root-harness evidence remains
  historical and was not reused for the final remediation freeze.
- 2026-07-20: Task 5E.1 second independent review found three Important gaps
  and strict behavior-first REDs are recorded (`verified locally`). The
  controlled shrink path discarded its requested-capacity replacement through
  a second temporary: isolated modes exited 120 for capacity 6 becoming 4,
  121 for false exact-one-block budget stop, and 122 for false injected-third-
  heap-call failure. Throwing copy 2 of 3 in the allocator-aware public copy
  constructor exited 125 with leaked partial allocation/owner while preserving
  the source. The new concurrent caller-cancel/deadline isolation mode passed
  production; its compiled shared-control test mutant compiled with exit 0 and
  ran with exit 131. Tests changed before production and no safe source was
  reverted.
- 2026-07-20: Task 5E.1 second-review remediation is `verified locally`, but
  its source freeze was superseded by the mixed-trait no-exception remediation
  below. Shrink now copies directly into one
  preallocated replacement, retains requested capacity 6, peaks at the exact
  old-8 plus new-6 blocks, and uses only two total heap ordinals. Public copy
  construction tracks partial size and on throw destroys partial elements,
  releases exact request storage/owner, preserves the source, and rethrows.
  Concurrent caller cancellation and deadline each leave the other request's
  growth, stop reason, allocator, and release counts untouched. Final frozen
  direct NDEBUG and `-fno-exceptions` runners compile/run 0 in
  0.58s/0.31s each. The focused gate passed 1/1 in 37.69s; Android 14/14 plus
  iOS 14/14 printed mutants were source-different, compiled with exit 0, and
  ran nonzero. ASan+UBSan passed 1/1 in 4.05s and the real transcoder gate
  passed 1/1 in 37.58s. Frozen hashes are `d0c18429...` containers header,
  `674e755e...` containers implementation, `585c5e9c...`/`9fea7b6d...`
  mirrored control header/source, `93b3f9b3...` direct runner, `84f8d430...`
  native/mutation harness, `c302109b...` codec provenance, `faeb7715...` local
  modifications, and `b82679ce...` 28/28 vendored manifest. Fresh serial native
  passed 19/19 in 135.86s; API 2/2 in 1.78s; provenance asset 1/1 in 1.62s;
  analyze reported no issues in 1.47s wall; focused format reported 3 files/0
  changes in 0.30s; root provenance passed 1/1 in 2.51s; repo lint and diff
  checks pass. The root harness passed lint, 97-file format, dependency
  resolution, and analysis, then reached 627 passed/16 declared GPU skips/6
  failures in 22s (30.34s wall), all pre-empted by the deliberately stale
  open-5E decoder-control fingerprint at the Android control header. It was not
  refreshed. Task 5 Steps 3-5 and M3 remain unchecked; physical Android/iOS are
  `not run`, runtime is `candidate-only` or `not run`, release is `release
  pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.1 final re-review found one Important mixed-trait
  no-exception gap and strict behavior-first REDs are recorded (`verified
  locally`). `increase_capacity` correctly admitted a type with a potentially
  throwing copy and `noexcept` move, but controlled shrink and public copy
  construction unconditionally copy. Raw/null parity succeeded before each
  RED. Before production edits, isolated `mixed-shrink` exited 42 after
  allocating and incorrectly succeeding, and `mixed-copy` exited 43 after
  reaching the injected heap instead of rejecting before allocation. No safe
  source was reverted.
- 2026-07-20: Task 5E.1 final mixed-trait remediation is `verified locally`,
  but its source freeze was superseded by the nested-composition remediation
  below. An operation-specific controlled-copy
  gate now rejects before public-copy owner retention/allocation, shrink
  replacement allocation, and `try_copy_from` reserve/copy. The broader
  growth relocation predicate and raw/null behavior remain unchanged. Frozen
  direct NDEBUG compile/run exited 0 in 0.58s/0.39s; frozen
  `-fno-exceptions` compile/aggregate run exited 0 in 0.57s/0.33s. The focused
  gate passed 1/1 in 40.95s; Android 16/16 plus iOS 16/16 printed mutants were
  source-different, compiled with exit 0, and ran nonzero. The new no-exception
  shrink and public-copy mutants exited 44 and 43. ASan+UBSan passed 1/1 in
  3.83s and the real transcoder gate passed 1/1 in 37.28s. Frozen hashes are
  `3bb60db1...` containers header, `674e755e...` containers implementation,
  `585c5e9c...`/`9fea7b6d...` mirrored control header/source,
  `fef93a21...` direct runner, `868c97a8...` native/mutation harness,
  `21b4380d...` codec provenance, `226cba62...` local modifications, and
  `1a29ed73...` 28/28 vendored manifest. Fresh serial native passed 19/19 in
  139.65s; API 2/2 in 1.69s; provenance asset 1/1 in 1.64s; analyze reported
  no issues in 1.37s wall; focused format reported 3 files/0 changes in 0.30s;
  root provenance passed 1/1 in 2.47s; repo lint and diff checks pass. The root
  harness passed lint, 97-file format, dependency resolution, and analysis,
  then reached 627 passed/16 declared GPU skips/6 failures in 21s (30.49s
  wall), all pre-empted by the deliberately stale open-5E decoder-control
  fingerprint at the Android control header. It was not refreshed. Task 5
  Steps 3-5 and M3 remain unchecked; physical Android/iOS are `not run`,
  runtime is `candidate-only` or `not run`, release is `release pending`, and
  this is not `production-ready`.
- 2026-07-20: Task 5E.1 next independent re-review approved the scalar
  mixed-trait gates and found one Important nested-composition no-exception
  gap. Strict behavior-first REDs are recorded (`verified locally`). Nested
  raw/null copy and shrink parity ran first and passed. Before production
  edits, the `-fno-exceptions` runner compiled with exit 0 in 0.59s;
  `nested-mixed-copy` then exited 58 on the outer owner-retain trap, while
  `nested-mixed-shrink` exited 73 after detecting cumulative outer/child owner
  and allocation/release accounting changes. Source data, capacity, content,
  allocator identities, and stop reasons were also gated. No safe source was
  reverted.
- 2026-07-20: Task 5E.1 final nested-composition remediation is `verified
  locally`; its production/provenance freeze remains current, while its
  runner/harness evidence freeze was superseded by the raw-intermediate
  strengthening below. Once a controlled ancestor
  requires no-throw copying, recursive source-aware preflight inspects the
  actual nested tree, including raw intermediate children, before any outer or
  child owner/allocation callback. Top-level raw/null behavior and direct
  scalar gates remain unchanged. Frozen direct NDEBUG compile/run exited 0 in
  0.61s/0.64s; frozen `-fno-exceptions` compile/aggregate run exited 0 in
  0.62s/0.43s. The focused gate passed 1/1 at 00:42; Android 18/18 plus iOS
  18/18 printed mutants were source-different, compiled with exit 0, and ran
  nonzero. The new nested public-copy and shrink mutants exited 58 and 73 on
  both mirrors. ASan+UBSan passed 1/1 in 3.76s and the real transcoder gate
  passed 1/1 in 37.24s. Frozen hashes are `46f1959e...` containers header,
  `674e755e...` containers implementation, `585c5e9c...`/`9fea7b6d...`
  mirrored control header/source, `ed03964d...` direct runner, `aee41613...`
  native/mutation harness, `30b66da1...` codec provenance, `39a6d857...` local
  modifications, and `835d3942...` 28/28 vendored manifest. Fresh serial
  native passed 19/19 in 142.58s; API 2/2 in 1.28s; provenance asset 1/1 in
  1.37s; analyze reported no issues in 0.85s wall; focused format reported 3
  files/0 changes in 0.03s; root provenance passed 1/1 in 2.25s; repo lint and
  diff checks pass. The root harness passed lint, 97-file format, dependency
  resolution, and analysis, then reached 627 passed/16 declared GPU skips/6
  failures in 21s (29.20s wall), all pre-empted by the deliberately stale
  open-5E decoder-control fingerprint at the Android control header. It was
  not refreshed. Task 5 Steps 3-5 and M3 remain unchecked; physical
  Android/iOS are `not run`, runtime is `candidate-only` or `not run`, release
  is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.2 malformed-metadata pre-production REDs are `verified
  locally`. One live-source compile exited 0 in 9.23s, and the combined
  plain-name Flutter harness ran all four isolated modes before exiting 1 in
  12.25s. Level-index range/truncation exited 130 with literal
  `invalidMetadata`/`basisuNativePreflight`/`ktx2LevelIndex`; DFD
  range/structure exited 131 with field `ktx2Dfd`; KVD
  range/entry/order/padding exited 132 with field `ktx2KeyValueData`. In each,
  all bridge diagnostic subassertions were true and direct init rejected the
  representative malformed input, but unchanged production recorded zero
  request allocations. The valid ordered `KTXanimData` plus later malformed
  padding case exited 133 with field `ktx2KeyValueData`, `precedence=1`, and
  `directInit=1`, proving current `invalidMetadata` precedence independently
  of the missing allocator seam. Every mode reported zero live bytes/owners,
  zero mismatches/failures, and balanced zero allocation/releases. Frozen
  runner/harness hashes are `073d5e14...`/`0c370275...`; production hashes
  remain pre-5E.2. No production, provenance, fixture, dependency-pin,
  `flutter_scene`, upstream, pub-cache, branch/worktree, staging, commit, push,
  or GitHub state changed. Ordinal/budget/cancel/heap/concurrency/reuse REDs and
  all GREEN/release gates remain `not run`; physical Android/iOS are `not
  run`, runtime is `candidate-only` or `not run`, release is `release pending`,
  and this is not `production-ready`.
- 2026-07-20: Task 5E.2 failure-control pre-production REDs are `verified
  locally`. One live-source compile exited 0 in 9.43s; the plain-name Flutter
  harness ran both real-transcode modes and exited 1 in 12.09s. Uncompressed
  UASTC exited 140 in 0.31s with `direct=0 attempts=0 reservations=0 peak=0`,
  and Zstd UASTC exited 141 in 0.29s with `direct=0 attempts=0 reservations=2
  reservationAttempts=2 peak=96248`. Both literals report `baseline=0
  ordinals=0 exactPeak=0 peakMinusOne=0 cancelBefore=1 cancelLater=0
  firstReason=1 heap=0 fresh=0 cleanup=1`. The Zstd reservation-only peak is
  deliberately not classified as direct allocator evidence. The runner now
  defines exact allocation/peak replay, every-ordinal heap failure,
  peak-minus-one budget rejection before heap, before/later cancellation,
  first-reason preservation, distinct heap failure, fresh controlled requests,
  and zero-live balanced cleanup once GREEN exposes a nonzero direct baseline.
  A first candidate Zstd run was discarded after signal 6 identified an
  uninitialized caller-state index in the test helper; explicit `state.clear`
  removed that harness defect, and the frozen modes return controlled nonzero
  exits without assertions. Runner/harness hashes are `6eb3be22...`/
  `d85d1486...`; production hashes remain pre-5E.2. No production, provenance,
  fixture, dependency-pin, `flutter_scene`, upstream, pub-cache,
  branch/worktree, staging, commit, push, or GitHub state changed. State-reuse/
  concurrency REDs and all GREEN/release gates remain `not run`; physical
  Android/iOS are `not run`, runtime is `candidate-only` or `not run`, release
  is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.1 latest independent re-review approved the recursive
  production preflight and found one Important permanent-mode/mutation evidence
  gap. Tests changed first (`verified locally`). The new three-level case uses
  a controlled outer, raw/null intermediate vector, and controlled unsafe
  mixed-trait descendant. The strengthened production baseline compiled under
  `-fno-exceptions` with exit 0 in 0.75s and both nested copy/shrink modes
  exited 0 with source, capacity, content, allocator, stop, live, owner,
  request, and heap accounting unchanged. The exact temporary short-circuit
  mutant compiled with exit 0 in 0.72s; copy exited 77 on premature outer owner
  retention and shrink exited 89 on changed outer/descendant accounting. The
  production line was restored immediately and its hash reconfirmed.
- 2026-07-20: Task 5E.1 raw-intermediate evidence strengthening is `verified
  locally`, pending final independent re-review. No production or provenance
  source changed. Frozen direct NDEBUG compile/run exited 0 in 0.62s/0.32s;
  frozen `-fno-exceptions` compile/aggregate run exited 0 in 0.63s/0.60s. The
  focused gate passed 1/1 in 47.68s; Android 19/19 plus iOS 19/19 printed
  mutants were source-different, compiled with exit 0, and ran nonzero. The
  permanent raw-intermediate mutant ran both isolated modes with exits 77/89
  on each mirror. ASan+UBSan passed 1/1 in 4.24s and the real transcoder gate
  passed 1/1 in 38.63s. Frozen hashes are unchanged `46f1959e...` containers
  header, `674e755e...` containers implementation, `585c5e9c...`/`9fea7b6d...`
  mirrored control header/source, unchanged `30b66da1...` codec provenance,
  `39a6d857...` local modifications, and `835d3942...` 28/28 vendored
  manifest; evidence-only hashes are `4ee8608d...` direct runner and
  `4c392714...` native/mutation harness. Fresh serial native passed 19/19 in
  146.46s; API 2/2 in 1.33s; provenance asset 1/1 in 1.24s; analyze reported
  no issues in 0.88s wall; focused format reported 3 files/0 changes in 0.04s;
  root provenance passed 1/1 in 2.04s; repo lint and diff checks pass. The root
  harness passed lint, 97-file format, dependency resolution, and analysis,
  then reached 627 passed/16 declared GPU skips/6 failures in 19s (27.77s
  wall), all pre-empted by the deliberately stale open-5E decoder-control
  fingerprint at the Android control header. It was not refreshed. Task 5
  Steps 3-5 and M3 remain unchecked; physical Android/iOS are `not run`,
  runtime is `candidate-only` or `not run`, release is `release pending`, and
  this is not `production-ready`.
- 2026-07-20: Task 5E.1 final independent re-review is approved with no
  Critical, Important, or Minor findings (`verified locally`). The reviewer
  accepted the moved-from allocator binding, exact-token ownership, direct and
  recursively composed no-exception copy gates, single-allocation shrink,
  exception cleanup, concurrent request isolation, Android/iOS mirror parity,
  19/19 compiled/run mutants per platform, and the frozen provenance chain.
  The live container header remains `46f1959e...`; the final evidence runner
  and harness are `4ee8608d...` and `4c392714...`. Task 5E.1 is closed. Task 5
  Steps 3-5 and M3 remain open for Tasks 5E.2-5E.6; physical Android/iOS are
  `not run`, runtime is `candidate-only` or `not run`, release is `release
  pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.2 bounded initial compiled RED stage is complete
  (`verified locally` RED only). A new native runner and plain-name Dart
  harness compile the live Android bridge, request control, pinned Basis
  Universal transcoder, and tracked CTS UASTC fixture. The direct compile
  exited 0 in 9.14s. Unchanged production metadata mode exited 100 in 0.35s
  with `metadata-owner-red persistent=0 nested=0 allocations=0 owners=0
  expectedOwners=8`; the focused combined Flutter test exited 1, and an
  independent parent execution reconfirmed native exit 100. Separate animation
  mode exited 104 with `animation-profile-red decoded=1 diagnostics=0
  allocations=0`. Its own plain-name Flutter test independently exited 1 in
  11.88s with native exit 104, proving the valid ordered `KTXanimData` profile
  remains accepted before the production change; a separate parent execution
  reconfirmed Flutter exit 1 in 11.65s and native exit 104 with the same
  literal. Runner, harness, and fixture hashes are `72dea220...`,
  `63e1450e...`, and `97beaf23...`; live transcoder and mirrored bridge hashes
  remain the pre-5E.2 values. No production,
  provenance, fixture, dependency-pin, `flutter_scene`, upstream, pub-cache,
  branch/worktree, staging, commit, push, or GitHub state changed. The broader
  E2 RED matrix, production implementation, GREEN, sanitizer, serial,
  provenance, root, and independent-review evidence are `not run`. Task 5
  Steps 3-5 and M3 remain open; physical Android/iOS are `not run`, runtime is
  `candidate-only` or `not run`, release is `release pending`, and this is not
  `production-ready`.
- 2026-07-20: Task 5E.2's next bounded pre-production RED pair is `verified
  locally`. One production-linked compile exited 0 in 10.89s, then the pinned
  Zstd UASTC path completed `init`, `start_transcoding`, and a real explicit-
  state RGBA32 transcode before exiting 110 in 0.26s with
  `zstd-state-red initialized=1 started=1 decoded=1 state=0 allocations=0
  releases=0 live=0 owners=0 allocationFailed=0`. The pinned ETC1S path
  completed `init` and `start_transcoding`, reached a nonempty image descriptor
  vector, and exited 120 in 0.23s with `etc1s-descriptor-red initialized=1
  started=1 present=1 descriptor=0 allocations=0 releases=0 live=0 owners=0
  allocationFailed=0`. The combined plain-name Flutter test exited 1 in
  13.07s; an independent parent execution reconfirmed exit 1 in 14.31s and
  both native literals. Runner/harness hashes are `8c937063...`/`aa3a193e...`;
  Zstd/ETC1S fixture hashes are `27484bc9...`/`03327b96...`. Live transcoder
  and mirrored bridge hashes remain the pre-5E.2 values. No production,
  provenance, fixture, dependency-pin, `flutter_scene`, upstream, pub-cache,
  branch/worktree, staging, commit, push, or GitHub state changed. Remaining
  pre-production REDs and all GREEN/release gates are `not run`; physical
  Android/iOS are `not run`, runtime is `candidate-only` or `not run`, release
  is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.2 implementation and host verification are `verified
  locally`, pending the required independent review. Strict TDD captured
  pre-production REDs for reused default/explicit KTX2 state ownership,
  concurrent request isolation, and eight source-different ownership/profile
  mutations per Android/iOS mirror. The implementation routes KTX2 levels,
  DFD, outer and nested KVD vectors, ETC1S descriptors, and explicit/default
  Zstd state through the request allocator; preserves null-control behavior;
  removes the duplicate decoded-vector reservation envelope; balances exact
  owner tokens across success, budget/cancel/injected-heap failures, reuse, and
  concurrency; and rejects structurally valid official-profile `KTXanimData`
  with `unsupportedKtx2Profile` / `basisuProfilePreflight` /
  `ktx2KTXanimData` while preserving malformed-KVD precedence. Final serial
  native verification passed 26/26 in 322.68s, including the prior 5E.1
  19/19 mutants per mirror and the new 8/8 mutants per mirror. ASan+UBSan
  compile/run passed all 13 focused modes on both mirrors, with an additional
  final ETC1S failure-matrix pass; macOS LeakSan is unavailable, while exact
  zero-live/zero-owner assertions remained active. Package API passed 2/2,
  package provenance asset passed 1/1, package analyze reported no issues,
  root codec provenance passed 1/1, the vendored manifest passed 28/28,
  focused formatting reported 3 files/0 changes, repo lint passed, and diff
  check passed. The root harness passed lint, 97-file format, dependency
  resolution, and analysis, then reached 627 passed/16 declared GPU skips/6
  failures, all pre-empted by the deliberately stale open-5E capability
  fingerprint; that fingerprint remains intentionally unrefreshed until
  Tasks 5E.3-5E.6 close. Frozen production hashes are `8682cc99...` header,
  `c418d470...` transcoder implementation, and identical `dd33545b...`
  Android/iOS bridges; evidence runner/harness hashes are `5d0e6bcf...` and
  `8d50c110...`. Task 5 Steps 3-5 and M3 remain open; physical Android/iOS are
  `not run`, runtime is `candidate-only` or `not run`, release is `release
  pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.2 independent-review safety remediation is `verified
  locally` at focused scope only. Four production-linked REDs first failed for
  partial metadata cancellation (Flutter/native exits 1/153), required
  malformed metadata (1/155), explicit state lifetime (1/154), and KVD
  relocation beyond eight entries (normal signal 6; full `-fno-exceptions`
  contract exit 157). The minimal fixes add Level Index/DFD/outer-KVD/
  relocation/per-entry cancellation checkpoints, overflow-safe Level Index
  range validation, immediate explicit-state allocator unbinding, nothrow-move
  KVD relocation, a narrow packed Level Index bitwise-copyable declaration,
  and exception-disabled bridge guards. The fresh combined focused command
  passed 4/4 in 51 seconds. The permanent 19-mode-per-mirror ASan+UBSan gate
  passed 1/1 in 58 seconds with exact cleanup assertions; the expanded nine-
  mutant-per-mirror gate passed 1/1 in 3:08, and every source-different mutant
  compiled with exit 0 and ran nonzero. Direct-allocation ordinal claims are
  limited to Task 5E.2 owners; peak/budget paths may include later reservation
  classes. Post-report `python3 tools/repo_lint.py` and `git diff --check`
  exited 0. Current candidate production hashes are `312c491e...` containers,
  `e004880c...` header, `45f87ddf...` transcoder, and identical `d30bab19...`
  mirrored bridges. Per the simplified closure scope, a fresh complete
  sanitizer wave, full serial suite, final provenance freeze, root harness,
  and independent rereview are deferred to the single Task 5E.6/Plan 017
  closure wave. The interrupted serial attempt is discarded. Task 5E.2 is not
  approved, `.superpowers/sdd/progress.md` is untouched, Task 5E.3 has not
  started, physical targets and packaged runtime are `not run`, maturity is
  `candidate-only` or `not run`, release is `release pending`, and this is not
  `production-ready`.
- 2026-07-20: Task 5E.3's required production-linked RED is `verified locally`.
  The live Android bridge/transcoder compiled with exit 0, then the focused
  official ETC1S RGB/RGBA/two-level-mip gate exited native 160 and Flutter 1
  in 13.16 seconds with `etc1s-state-owner-red owners=0 rgbBindOwners=4
  rgbaBindOwners=4 mipBindOwners=4 rgbStartDirect=1 rgbaStartDirect=1
  mipStartDirect=1 rgbTemp=0 rgbaTemp=0 mipTemp=0 parity=1 corruption=0
  cleanup=1`. This names the missing request allocation for reached palettes,
  Huffman/history state, predictors/prior-frame owners, and ETC1S temporaries
  while proving unchanged null-control byte parity and cleanup. The initial
  corrupt-slice construction is not yet decisive and is not claimed as
  corruption evidence. Pre-production hashes are `312c491e...` containers,
  `d58cebb5...` internal header, `e004880c...` public transcoder header,
  `45f87ddf...` transcoder source, and identical `d30bab19...` mirrored
  bridges; runner/harness hashes are `ac2c7aef...`/`26c28793...`; official
  RGB/RGBA/mip fixture hashes are `7e185709...`/`03327b96...`/`7f13880e...`.
  Production implementation and all GREEN gates are `not run`; physical
  Android/iOS are `not run`, packaged runtime is `candidate-only` or `not
  run`, release is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.3 implementation and focused host verification are
  `verified locally`. The explicit KTX2 request control now binds reached
  ETC1S endpoint/selector palettes, persistent and temporary Huffman storage,
  selector history, predictors, 32 prior-frame vectors, and per-pass
  temporaries to the request allocator; fallible growth returns through typed
  control and the existing state guard unbinds all caller state. Null-control
  bytes are unchanged. The combined official RGB/RGBA/two-level-mip
  command passed 3/3 in 51 seconds with 52 bound owner tokens, 59 direct start
  allocations, and temporary deltas RGB=3/RGBA=4/mips=8. The focused failure
  gate passed 1/1 in 12.59 seconds, replaying all RGB 80, RGBA 81, and complete
  two-level mip 85 direct allocation ordinals at peaks 40,166/40,212/40,355;
  exact peak, peak-minus-one, cancel, heap, corruption, first-reason, fresh-
  control, zero-live/zero-owner, and no-partial-output assertions passed.
  Bridge-local typed cancel/budget/heap/corruption cleanup passed. Three
  compact handoff/persistent/temporary mutants were source-different, compiled
  with exit 0, and ran 160. The Task 5E.2 animation rejection plus state reuse/
  concurrency boundary passed 2/2 in 22.20 seconds. Current candidate hashes
  are `312c491e...` containers, `da36bb4e...` internal header, `1da041f7...`
  public transcoder header, `9b37d711...` transcoder source, unchanged
  identical `d30bab19...` bridges, and `20205e73...`/`6feb3fe0...` runner/
  harness. The final runner/harness-only mip expansion passed its 85-ordinal
  failure gate after the 3/3 combined run; production sources were unchanged.
  Final `python3 tools/repo_lint.py` and `git diff --check` exited 0.
  Per the streamlined workflow, broad sanitizer/serial/root/
  provenance/review gates remain deferred through Task 5E.6;
  `.superpowers/sdd/progress.md` is unchanged, Task 5E.4 is not started,
  physical Android/iOS are `not run`, runtime is `candidate-only` or `not
  run`, release is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.4 implementation and focused host verification are
  `verified locally`. The required production-linked RED compiled the live
  Android bridge/transcoder/Zstd with exit 0, then the official tracked Zstd
  UASTC fixture exited 110 with `workspaceAllocations=0` while decode,
  state-unbinding, and exact cleanup all succeeded. The controlled path now
  checks and aligns the estimated 95,992-byte `DCtx` workspace to 8 bytes,
  allocates it directly through the explicit request allocator, initializes it
  with `ZSTD_initStaticDCtx`, decompresses, and releases the exact allocation
  token on every outcome. Static storage never reaches `ZSTD_freeDCtx`; the
  null-control heap path and bytes remain unchanged. The final focused Task
  5E.4 command passed 2/2 in 24 seconds, covering real-byte parity, corrupt
  input, cancellation, request heap failure, workspace-size-minus-one,
  peak-minus-one, typed bridge failure, and zero-live/exact-release cleanup.
  Android and iOS native `zstd-state` and 20-ordinal `failure-zstd` gates
  passed with one workspace allocation and peak 97,644. Three compact
  source-different checkpoint/static-init/exact-release mutants compiled with
  exit 0 and ran 13/12/110. Focused Task 5E.2/5E.3 regressions passed 4/4 in
  43 seconds. Current candidate hashes are `704a4c95...` Zstd header,
  `2107e6c0...` Zstd source, `5a0b32d6...` transcoder header,
  `316c54c2...` transcoder source, `245f0264...` runner, `17e458b3...`
  harness, and unchanged identical `d30bab19...` bridges. The detailed report
  is `.superpowers/sdd/task-5e4-basisu-zstd-static-dctx-report.md`. Per the
  streamlined workflow, the broad sanitizer/serial/root/provenance/review wave
  remains deferred through Task 5E.6; `.superpowers/sdd/progress.md` is
  unchanged, Task 5E.5 is not started, physical Android/iOS are `not run`,
  runtime is `candidate-only` or `not run`, release is `release pending`, and
  this is not `production-ready`.
- 2026-07-20: Task 5E.5's first production-linked RED is `verified locally`.
  The live Android bridge, budget/control sources, transcoder, and Zstd source
  compiled with exit 0 against a mixed official ETC1S/UASTC/Zstd batch. The
  runner decoded all three images, then exited 160 with
  `bridge-result-owner-red live=0 images=3`: native decoded-result storage was
  already uncharged while still awaiting the managed platform copy.
  Production implementation and focused GREEN gates are `not run`; physical
  Android/iOS are `not run`, packaged runtime is `not run`, release is
  `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.5 implementation and focused GREEN verification are
  `verified locally`. Mirrored request-controlled storage now covers BasisU
  platform input, preflight layouts/diagnostics, bridge staging, decoded mip
  results, and terminal diagnostics; native result bytes remain charged until
  Java/Objective-C managed copies complete, then release exactly before control
  destruction. The mixed official ETC1S/UASTC/Zstd gate passed both mirrors
  with 136 post-input heap ordinals, cancellation, budget, corrupt input, two
  concurrent requests, and a fresh request; literal evidence included
  `bridge-result-owner-green peak=104077 allocations=140 bridge-failure-ordinals=136 concurrency=2 fresh=green`.
  Generic platform-copy gates passed both mirrors, Android JNI passed 10
  charged copy/exception/local-reference cases, and host Objective-C++ passed
  seven charged-copy/atomic/exactly-once cases. Four compact source-different
  mutants compiled with exit 0 and ran 160/173/1/1 for bridge result ownership,
  JNI local-reference cleanup, Objective-C++ release-before-copy, and partial
  publication. Task 5E.2 metadata/animation, Task 5E.3 ETC1S state/failure, and
  Task 5E.4 Zstd focused regressions passed. Android/iOS budget, bridge,
  control, owned-allocator, and platform-copy mirrors are byte-identical.
  Candidate hashes are `e17e7f84...` bridge source, `cc05b9db...` bridge
  header, `e952eb47...` budget source, `1f9c859c...` budget header,
  `c6d27fa6...` control source, `945572f2...` owned allocator,
  `03b98ad1...` platform copy, `0ed540c3...` JNI, `93c1b0af...`
  Objective-C++, and `279851fb...` focused Dart harness. The detailed report is
  `.superpowers/sdd/task-5e5-basisu-bridge-platform-lifetimes-report.md`.
  The broad retained-output envelope remains for Task 5E.6. Per the streamlined
  workflow, sanitizer/full-serial/root/provenance/review closure remains
  deferred until after Task 5E.6; `.superpowers/sdd/progress.md` is unchanged,
  physical Android/iOS are `not run`, packaged runtime is `candidate-only` or
  `not run`, release is `release pending`, and this is not `production-ready`.
- 2026-07-20: Task 5E.6 implementation and focused exact-accounting
  verification are `verified locally`. Before production changed, the new
  production-linked runner compiled with exit 0 and ran 160 because each
  official ETC1S, uncompressed UASTC, Zstd UASTC, and mixed path had one extra
  retained-output reservation. The only production change removes that
  mirrored broad reservation; static checked output/pixel/platform-message/
  overflow and aggregate budget preflight remains unchanged, and every direct
  Task 5E.1-5E.5 owner remains charged. Exact direct allocation/peak contracts
  now pass on both mirrors at ETC1S 90/41,293, UASTC 27/2,781, Zstd 29/99,967,
  and mixed 140/102,541. Exact peak succeeds; peak-minus-one rejects before
  the disallowed heap call; all 140 mixed allocation ordinals, cancellation,
  deadline, corruption, concurrency=2, fresh recovery, atomic empty failures,
  and zero-live/zero-owner balanced cleanup pass. Source-different envelope
  and combined result/input-charge-bypass mutants compiled with exit 0 and ran
  160/67 on both mirrors. Focused Task 5E.2-5E.5 regressions, static preflight,
  and extended mirror parity passed. Candidate identities are `1d3ce97e...`
  bridge, `83d26b13...` runner, and `5a663d51...` harness. The detailed report
  is `.superpowers/sdd/task-5e6-basisu-outer-envelope-accounting-report.md`.
  `.superpowers/sdd/progress.md` is unchanged. The final ASan+UBSan/full-
  serial/root/provenance/fingerprint/review closure wave is `not run` and
  remains controller-owned; physical Android/iOS are `not run`, packaged
  runtime is `candidate-only` or `not run`, release is `release pending`, and
  this is not `production-ready`.
- 2026-07-20: The final Task 5E.2-5E.6 source freeze and deferred broad host
  verification are `verified locally`, pending independent review. Frozen
  production identities are `312c491e...` containers,
  `da36bb4e...` internal header, `5a0b32d6...` transcoder header,
  `316c54c2...` transcoder source, `704a4c95...`/`2107e6c0...` Zstd, and
  identical `1d3ce97e...` Android/iOS bridge sources; all eight required
  bridge/budget/control/owned/platform mirror pairs are byte-identical. Final
  provenance identities are `6d9e1984...` local modifications,
  `5092aa05...` codec control, and `d675ed64...` 28-source manifest. The
  permanent Android/iOS-host ASan+UBSan gate passed 2/2 in 56.92 seconds with
  exact cleanup assertions; macOS LeakSan remains unavailable. The definitive
  complete serial native suite passed 40/40 in 629.32 seconds. Package API
  passed 2/2, asset/provenance 1/1, analyze was clean, focused format reported
  four files/zero changes, and the vendored manifest passed 28/28. Root strict
  provenance passed 1/1, capability tests 13/13, decoder/mip validation and
  capability generation were current, repo lint and diff checks passed, and
  `bash tools/run_checks.sh` exited 0 with 633 passed, 16 declared GPU skips,
  zero failures, 97 formatted files/zero changes, and clean analysis in 35.88
  seconds. The first sanitizer and serial attempts exposed only stale test
  consumers of the final result-lifetime, Zstd-workspace, request-vector, and
  removed-envelope contracts; production hashes were unchanged, focused
  consumer corrections passed, and those earlier 1/2 and 36/40 attempts are
  discarded rather than final evidence. The first sandboxed broad harness
  invocation was blocked before formatting by external Flutter SDK cache
  permissions; the approved rerun above is final. The detailed frozen evidence
  is `.superpowers/sdd/task-5e-final-closure-report.md`. This entry does not
  approve Task 5E.2-5E.6: Task 5 Steps 3-5 and M3 remain controller-owned until
  independent review is clean; `.superpowers/sdd/progress.md` is unchanged,
  physical Android/iOS are `not run`, packaged runtime is `candidate-only` or
  `not run`, release is `release pending`, and this is not
  `production-ready`.
- 2026-07-20: The independent Task 5E.5 review's single Important
  control-creation finding is remediated and focused verification is
  `verified locally`. Production-linked REDs compiled with exit 0 and ran 160
  for Java admitting an invalid control, 188 for JNI entering work with handle
  zero, and 160 for iOS `bad_alloc` escaping registration. Android now rejects
  handle zero before registry/executor/native use and returns exactly one
  `nativeControlUnavailable` error; the actual host plugin runner reports
  `callbacks=1 native-entered=0`. JNI rejects null control before conversion or
  allocation and passes default, ASan+UBSan, and `-fno-exceptions` 11-case
  variants. iOS catches all four observed Entry/control/unordered-map
  registration allocation ordinals, leaves no active entry, permits a fresh
  request, and delivers exactly one typed Flutter error; default and
  ASan+UBSan variants pass. Four guard mutants compile with exit 0 and run
  160/160/-11/160 for Java registry, Android plugin typed admission, JNI null
  guard, and iOS allocation catch. The affected request-owner/JNI/platform/
  Task 5E.5/Task 5E.6 wave passed 7/7. Candidate hashes are `e10fdb82...`
  Android plugin, `ffe931d3...` Java registry, `dba89a12...` JNI,
  `ef77d609...` iOS plugin, `118bfab5...`/`fc8667da...` iOS registry, and
  `0aeb2044...` focused harness. Detailed evidence is
  `.superpowers/sdd/task-5e5-control-creation-failure-report.md`. Because this
  post-review remediation changes previously frozen adapters, the controller
  owns the final broad affected wave and refreshed freeze identities; they are
  not claimed here. `.superpowers/sdd/progress.md` is unchanged, physical
  Android/iOS are `not run`, packaged runtime is `candidate-only` or `not run`,
  release is `release pending`, and this is not `production-ready`.
- 2026-07-20: The final post-remediation Task 5E.2-5E.6 source freeze and broad
  affected verification are `verified locally`, pending final independent
  rereview. Final remediation identities are `e10fdb82...` Android plugin,
  `ffe931d3...` Android registry, `dba89a12...` JNI, `ef77d609...` iOS
  plugin, and `118bfab5...`/`fc8667da...` iOS registry source/header. The
  pinned Basis Universal/Zstd sources, three vendored provenance assets, and
  eight required Android/iOS native mirror pairs are unchanged; the vendored
  manifest passed 28/28 and mirror `cmp` exited 0. Capability fingerprint
  consumers now freeze all six remediation identities and the atomic
  missing-control-before-registry/native-work contract; final identities are
  `f7e2dcc7...` source JSON, `d33b8355...` generator,
  `f36919b3...` generated matrix, and `f6c4f97f...` capability test. The
  permanent control-creation gate passed 4/4 in 74.74 seconds across JNI
  default/ASan+UBSan/`-fno-exceptions`, Android plugin/registry, iOS default/
  ASan+UBSan four-ordinal failure injection, and four compiled/run guard
  mutants; macOS LeakSan remains unavailable while exact cleanup assertions
  stay active. The first serial attempt was discarded at 1 pass/1 failure and
  interrupted at 36.65 seconds because the strengthened registry admission
  structure left the older lifecycle duplicate-registration mutation matcher
  unchanged. Production hashes were unchanged; only that test consumer was
  corrected, its focused gate passed 1/1 in 17.66 seconds, and the permanent
  4/4 gate passed again against the final harness hash. The definitive fresh
  complete native/platform suite then passed 43/43 with zero failures/skips in
  724.94 seconds. Package API passed 2/2, package asset/provenance 1/1,
  analysis was clean, focused format reported four files/zero changes, root
  strict provenance passed 1/1, capability tests 13/13, decoder/mip validation
  and generation were current, and repo lint/diff checks passed. Final
  `bash tools/run_checks.sh` exited 0 with 633 passed, 16 declared GPU skips,
  zero failures, 97 formatted files/zero changes, and clean analysis in 41.40
  seconds. Detailed exact hashes and the separation of discarded from final
  evidence are in `.superpowers/sdd/task-5e-final-closure-report.md`. This
  entry does not approve Task 5E.2-5E.6: Task 5 Steps 3-5 and M3 remain
  controller-owned until independent rereview is clean;
  `.superpowers/sdd/progress.md` is unchanged, physical Android/iOS are `not
  run`, packaged runtime is `candidate-only` or `not run`, release is `release
  pending`, and this is not `production-ready`.
- 2026-07-20: Final independent Task 5E.2-5E.6 rereview is `APPROVED / GO`
  with zero Blocker, Important, or Minor findings. The prior Important
  missing-control finding is resolved: Android rejects handle zero before
  registry/executor/native work, JNI independently rejects null control before
  request conversion under normal, sanitizer, and `-fno-exceptions` builds,
  and iOS converts all four observed registration-allocation ordinals into one
  typed, exactly-once failure without retaining a partial request. The reviewer
  independently reran the permanent remediation gate 4/4, lifecycle-critical
  regressions 3/3, vendored manifest 28/28, mirror parity 8/8, capability and
  evidence validators, repo lint, and diff checking; all frozen source,
  runner, harness, capability, and provenance hashes matched the final closure
  report. Task 5E.2-5E.6 and Task 5 Steps 3-5 are closed, completing milestone
  M3 at the `verified locally` host boundary. Physical Android/iOS remain
  `not run`, packaged runtime remains `candidate-only` or `not run`, release
  is `release pending`, and this is not `production-ready`.
