# Decoder Control, Authored KTX2 Mip Chains, and Release Evidence Implementation Plan

> **Status (2026-07-15): deferred.** This plan owns the decoder-control,
> authored-mip, cross-platform runtime, packaging, and release-evidence work
> intentionally left outside completed
> [Plan 014](../completed/014_selected_gltf_extension_support.md). It does not
> reopen Plan 014's accepted `FSViewerExtendedPbr` UV/specular/opaque-IOR
> implementation, and it does not absorb renderer-native clearcoat or glass;
> those remain in [Plan 015](../completed/015_renderer_native_clearcoat.md) and
> [Plan 016](016_renderer_native_transmission_volume.md).

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
KTX2 level with exact dimensions, content role, and raw decoded pixels. A
separate upstream `flutter_scene` checkout must add a public multi-level
`Texture2D` construction contract plus a runtime-import texture-decoder seam.
The viewer updates its dependency pin only after that upstream contract passes
native and WebGL2 tests. Single-level PNG rewrite remains a bounded compatibility
path; multi-level KTX2 routes through the mip-aware importer or stays a typed
diagnostic with the original bytes unchanged.

Capability truth remains per feature and per target. Physical iOS, Android,
and Web rows start as `not run`. Host codec tests, simulator runs, compiler
success, late-result discard, and reference captures do not promote those
rows. Web is allowed to remain diagnostic-only for native-only Draco/BasisU;
the acceptance gate is an honest supported/unsupported result, not forced
cross-platform feature parity.

## Tech Stack

Dart 3, Flutter, `flutter_scene` pinned initially at
`cd6760912fa38beb55f63e388655a1aeabd32fe4`, Flutter MethodChannel, Java
`ExecutorService`, Objective-C++ dispatch queues, C++17 atomics and RAII,
vendored Google Draco 1.5.7, vendored Basis Universal/KTX2 plus Zstd,
Flutter GPU/Impeller, the pinned WebGL2 backend, Khronos KTX-Software-CTS and
glTF Sample Assets, the official glTF Validator, and the existing Plan 014
capability/evidence generators.

## Global Constraints

- Work on the current branch. Do not create, switch, rename, or delete a
  branch unless the user explicitly asks in the execution turn.
- Do not edit the pub cache. Upstream `flutter_scene` work happens in a
  separate checkout and produces a concrete reviewed commit before any
  dependency-pin update.
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
  mip chain, but the public API does not accept caller-supplied mip levels and
  the runtime GLB importer has no external texture-decoder hook.
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
| Multi-level GPU texture construction and runtime importer callback | Upstream `flutter_scene` |
| GLB capability truth, target labels, durable evidence, packaging | Root package and Plan 017 harness |
| Renderer-native clearcoat | Plan 015 |
| Renderer-native transmission/volume/glass | Plan 016 |

## Milestones and execution order

| Milestone | Tasks | Independently testable result |
| --- | --- | --- |
| M1: load cancellation | 1-3 | User cancellation is distinct from timeout, reaches every root stage, and cannot publish a partial model. |
| M2: native request lifecycle | 4 | Android/iOS requests run off the UI thread, accept idempotent cancellation, and never deliver a late success. |
| M3: codec resource control | 5 | Draco/BasisU/Zstd observe cancellation inside codec work and reject working allocations before the configured limit. |
| M4: authored mip preservation | 6-7 | Every authored KTX2 level reaches a multi-level `Texture2D` without PNG flattening or regenerated substitution. |
| M5: target and release truth | 8 | Physical/runtime/package evidence is durable and only verified rows are promoted. |

M1 may land without M2 only while native cancellation remains explicitly
`notGuaranteed`. M2 does not close the resource gate unless M3 proves the
codec observes the flag inside long-running work. M4 may not update the
dependency pin until the upstream constructor and importer seam pass their own
tests. M5 runs only after the exact implementation to be claimed is packaged.

## Closure and release gates

| Gate | Required to complete Plan 017 | Required for a production-ready target claim |
| --- | --- | --- |
| Cancellation | Public cancellation is typed and atomic; Meshopt, Draco, and BasisU observe it during work; late results cannot mutate load state. | The selected physical target proves cancellation latency, native worker exit, and resource release under instrumented load. |
| Allocation | Preflight, output, and codec working allocations share one load budget with exact accounting and overflow checks. | Device stress evidence stays within the declared envelope with no OOM, leak, or post-cancel growth. |
| KTX2 mip chain | Official multi-level ETC1S and UASTC fixtures preserve every level's dimensions, bytes, role, ordering, and sampler intent. | The selected target uploads and samples authored levels through the packaged renderer path; generated-mip fallback is separately labelled. |
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

- [ ] **Step 1: Implement an immutable token with an idempotent controller**

Keep mutation private to the controller. Complete `whenCancelled` exactly
once; preserve the first reason; return `false` from later `cancel` calls.
`throwIfCancelled` throws one internal exception carrying the stage and
reason. Do not use `TimeoutException` for caller cancellation.

- [ ] **Step 2: Thread the token through controller, sink, widget, and loader**

Check before clearing/publishing controller state, after every awaited source
operation, before and after each decoder stage, before adapter import, before
authored patches, before initial overrides, and immediately before success
publication. A cancellation terminal result must be distinct from adapter or
network failure.

- [ ] **Step 3: Make source acquisition cancellation-aware**

Race non-cancellable asset/byte futures against `whenCancelled` and ignore
their late values. For HTTP, retain and close the request/stream subscription
for the cancelled load rather than closing a shared client. Preserve the
existing byte limit and timeout precedence; the first terminal event wins.

- [ ] **Step 4: Preserve controller atomicity**

On cancellation, clear partial part-tree state, do not persist authored or
initial overrides, and do not request a frame. If a previous model was already
published, preserve that model until the new load reaches the existing atomic
adapter replacement boundary; document the exact replacement semantics.

- [ ] **Step 5: Run focused GREEN verification**

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

- [ ] **Step 1: Convert decode checkpoints into yieldable checkpoints**

At each configured decoded-byte interval, yield to the event loop, then check
the external token and monotonic deadline. Keep forced start/complete checks.
Do not yield per element; preserve the existing interval as the scheduling and
latency bound.

- [ ] **Step 2: Make the GLB rewrite atomic across awaits**

Keep source bytes, JSON, BIN, extensions, and caller tracker unchanged until
all compressed views decode and the final GLB is built. On cancellation,
discard shadow trackers and partial buffers and return the typed cancellation
diagnostic.

- [ ] **Step 3: Add race tests**

Cancel in ATTRIBUTES, TRIANGLES, INDICES, OCTAHEDRAL, QUATERNION, and
EXPONENTIAL paths; cancel on a later bufferView; and race cancellation against
deadline. Assert the first observed terminal condition wins and no extension
declaration is partially removed.

- [ ] **Step 4: Verify Meshopt**

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

- [ ] **Step 1: Generate collision-free request ids in Dart**

Use a per-probe monotonic counter plus a random/session prefix. Register a
listener on `ModelLoadCancellationToken.whenCancelled`; invoke `cancelDecode`
exactly once for the active codec stage; remove the listener on every terminal
path. Never send a cancel for a pre-dispatch cancellation.

- [ ] **Step 2: Move platform decode work off UI threads**

Android uses one bounded `ExecutorService` per plugin and a concurrent request
map. iOS uses one serial or bounded concurrent dispatch queue per plugin and a
locked request map. Registration happens before work starts; removal happens
after the C++ result and all request-owned objects are destroyed. Engine/plugin
detach cancels and joins/drains owned work without delivering results to a
detached channel.

- [ ] **Step 3: Make cancel idempotent and result delivery exactly once**

The platform handler sets the C++ atomic flag and returns the lifecycle status.
The decode completion path checks cancellation before serializing output. Dart
ignores late success even if a buggy platform handler responds after the
terminal diagnostic.

- [ ] **Step 4: Test lifecycle races**

Cover cancel-before-worker-start, cancel-during-codec, cancel-after-finish,
duplicate cancel, timeout then cancel, cancel then timeout, plugin detach,
sequential Draco/BasisU, and two concurrent loads using distinct request ids.

- [ ] **Step 5: Verify native request ownership**

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

- [ ] **Step 1: Pin and hash the exact third-party edit surface**

Record upstream commit/tag, license, original source hashes, compiled source
manifest, and the intended patched files. Add mutation tests that fail when an
unrecorded third-party source changes. Carry a prominent modification notice.

- [ ] **Step 2: Thread control through Draco**

Add an overload or decoder option in the pinned local source that accepts the
control pointer. Check before header decode, topology decode, attribute decode,
and large output construction. Route request-owned temporary/output
allocations through the budget adapter. Preserve byte-identical successful
decode output for the official Box fixture and A1B32 primitives.

- [ ] **Step 3: Thread control through BasisU and Zstd**

Add a request-scoped allocator/cancellation context to BasisU containers and
the exact Zstd decode calls used by KTX2. Check before init, after header/DFD/
KVD validation, during supercompression output, before each image level, and
during block-row transcode. Preserve byte-identical single-level output for
the existing official fixture.

- [ ] **Step 4: Prove normal RAII release**

Instrument live bytes, peak bytes, allocation count, and destructor/free
count. Cancel at every injected checkpoint and fail unless live bytes return
to zero after the worker joins. Do not accept `lateResult: discardedByDart` as
this proof.

- [ ] **Step 5: Run sanitizer and mutation gates**

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

- [ ] **Step 1: Replace the level-count rejection with full validation**

Validate every Level Index entry using checked 64-bit arithmetic: offsets,
lengths, uncompressed lengths, non-overlap, containment, exact level order,
and complete payload coverage required by the supported 2D profile. Validate
expected dimensions as `max(1, base >> level)` and include every level in
aggregate pixel/decoded/native/working budgets before codec entry.

- [ ] **Step 2: Transcode every level atomically**

Preflight the complete batch, then transcode levels in ascending order using
the exact selected `r`/`rg`/`rgb`/`rgba` role. Store raw RGBA8888 output with
exact dimensions. Do not PNG-encode individual levels and do not return a
partial chain.

- [ ] **Step 3: Preserve role and sampler intent**

Reject shared-image color/data conflicts using the existing selected-channel
rules. Keep sampler min/mag/mip intent outside the image payload and associate
the decoded chain with every consuming texture slot without mutable sharing.

- [ ] **Step 4: Keep the single-level compatibility rewrite honest**

`rewriteBasisuTexturesInGlb` may continue to accept one encoded PNG/JPEG image
for the compatibility importer path. It must reject a multi-level result with
`mipAwareImporterRequired`; it must never silently select level 0.

- [ ] **Step 5: Verify official ETC1S and UASTC chains**

Run the official mip fixtures through the actual native bridge. Hash every
level, compare exact dimensions/byte lengths, test malformed Level Index
cases, and verify atomic budget/cancellation behavior on a later level.

### Task 7: Add a mip-aware `flutter_scene` texture/importer seam

**Files:**

- Upstream separate checkout, modify:
  `packages/flutter_scene/lib/src/texture/texture2d.dart`
- Upstream separate checkout, modify:
  `packages/flutter_scene/lib/scene.dart`
- Upstream separate checkout, modify:
  `packages/flutter_scene/lib/src/runtime_importer/texture_builder.dart`
- Upstream separate checkout, modify:
  `packages/flutter_scene/lib/src/runtime_importer/runtime_importer.dart`
- Upstream separate checkout, test public texture construction, importer
  callback, native Flutter GPU upload, and WebGL2 upload
- Root modify only after upstream acceptance: `pubspec.yaml`, `pubspec.lock`
- Root modify: `lib/src/internal/flutter_scene_adapter.dart`
- Root modify: `lib/src/model_loader.dart`
- Root test: `test/flutter_scene_adapter_material_test.dart`
- Root test: `test/model_loader_test.dart`

**Interfaces:**

Proposed upstream public texture input:

```dart
final class TextureMipLevel {
  const TextureMipLevel(this.width, this.height, this.rgbaBytes);
  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

static Texture2D Texture2D.fromMipLevels(
  List<TextureMipLevel> levels, {
  TextureContent content = TextureContent.color,
  TextureSampling sampling = const TextureSampling(),
});
```

Proposed importer seam:

```dart
typedef RuntimeTextureDecoder = Future<Texture2D?> Function(
  RuntimeTextureDecodeRequest request,
);
```

The request carries image index, encoded bytes, MIME type, content role,
sampler, and whether `KHR_texture_basisu` is required.

- [ ] **Step 1: Establish upstream RED**

Add public-constructor tests requiring immutable ordered levels, canonical
dimensions, exact per-level byte lengths, sampler retention, and upload to
the matching GPU mip index. Add importer tests requiring a `KHR_texture_basisu`
image to call the decoder once and bind the returned texture to every consuming
slot.

- [ ] **Step 2: Implement `Texture2D.fromMipLevels` upstream**

Validate the complete list before texture creation. Allocate exactly
`mipLevelCount: levels.length`, upload each level with `overwrite(...,
mipLevel: level)`, and never call the generated-mip path. Preserve the content
role for validation/documentation even though pixels are already decoded.

- [ ] **Step 3: Implement the runtime importer callback upstream**

Invoke the callback only for image formats the default importer cannot decode
or when the caller explicitly owns the extension. Required callback failure
blocks import; optional failure may use a valid core fallback. Deduplicate one
decoded image shared by multiple textures while preserving per-texture sampler
state.

- [ ] **Step 4: Verify native and WebGL2 upstream**

Run CPU validation plus an Impeller-enabled texture upload/sample test and a
WebGL2 test. Verify explicit LOD sampling or an equivalent deterministic
fixture distinguishes authored levels; a base-level-only image must fail the
test.

- [ ] **Step 5: Update the viewer pin only after upstream acceptance**

Record the exact upstream commit, rerun the pinned-source audit, update
`pubspec.yaml` and `pubspec.lock`, and pass the decoded mip chain through the
adapter importer callback. Do not edit pub-cache files and do not carry an
unreviewed local dependency override.

- [ ] **Step 6: Verify the integrated root path**

```sh
flutter test --no-pub test/glb_native_decoder_probe_test.dart test/glb_basisu_rewriter_test.dart test/model_loader_test.dart test/flutter_scene_adapter_material_test.dart
```

Expected: multi-level KTX2 reaches the renderer without PNG flattening,
single-level compatibility remains green, and missing mip-aware renderer
support remains a typed pre-import diagnostic.

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

- [ ] **Step 1: Migrate capability truth away from an active-plan label**

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

- [ ] **Step 5: Preserve the physical-evidence boundary**

Physical iOS, Android, and Web remain `not run` until their exact commands and
artifacts exist. Simulator may be `verified locally`; package-local/native
codec availability remains `candidate-only` or `release pending` until the
matching packaging and physical-runtime gates pass.

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
- [ ] Meshopt observes external cancellation within the declared checkpoint
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
- [ ] The pinned `flutter_scene` commit exposes and tests multi-level texture
      upload plus the runtime importer decoder seam on Impeller and WebGL2.
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

- 2026-07-15: Created as the explicit deferred owner for completed Plan 014's
  remaining native cancellation/resource-control, authored KTX2 mip-chain,
  cross-platform target, packaging, and release-evidence work. Plan 015 and
  Plan 016 retain renderer-native clearcoat and transmission/volume ownership.
  Current evidence is unchanged: Plan 014's iOS Simulator UV/specular/opaque-
  IOR/A1B32 rows are `verified locally` and `candidate-only`; physical iOS,
  Android, Web, release packaging, and production readiness remain `not run`
  or `release pending`. No implementation step in this deferred plan has run.

## Verification log

- 2026-07-15: Plan-authoring verification passed the repository link/path
  audit, `python3 tools/repo_lint.py`, `git diff --check`, and the root
  `bash tools/run_checks.sh` harness at `+503 ~16`; 88 Dart files formatted
  with zero changes and analysis reported no issues. These results validate
  the plan and existing repository baseline only. All Plan 017 implementation,
  native target, upstream, physical-device, packaging, and release gates are
  `not run`.
