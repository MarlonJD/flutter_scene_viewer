# Basis Universal local modifications

The vendored Basis Universal decoder is based on the official
`BinomialLLC/basis_universal` commit
`882abb5320400ab650c1be33f9152e4955e83af3` under Apache-2.0.

Upstream source identity:

- path: `transcoder/basisu_transcoder.cpp`;
- official URL: `https://raw.githubusercontent.com/BinomialLLC/basis_universal/882abb5320400ab650c1be33f9152e4955e83af3/transcoder/basisu_transcoder.cpp`;
- SHA-256: `27fda5a2330831704a7adcf254b852c6df5081258dcc1e42283a936030b6f01f`.

Vendored source identity:

- path: `transcoder/basisu_transcoder.cpp`;
- SHA-256: `316c54c224889e7b887c66663b6668e51ec90b89a7d836db8deec167b1b239d2`.

## Modified hunks

`ktx2_transcoder::init()` has one local functional change immediately after
the existing 2D-texture dimension check. It rejects a KTX2 whose width or
height exceeds `BASISU_MAX_SUPPORTED_TEXTURE_DIMENSION` before later size and
layout calculations. The source hunk carries this prominent notice:

```text
FSV LOCAL MODIFICATION (Apache-2.0 section 4(b))
```

A separate patch artifact is intentionally omitted because the exact source
hashes, in-source notices, deterministic `VENDORED_SOURCES.sha256` manifest,
and pre-task/patched `FSV_CODEC_CONTROL_PROVENANCE.sha256` entries identify the
vendored state without another generated source of truth.

Plan 017 adds a second narrow seam: one request-owned
`fsv_transcode_control` pointer on `ktx2_transcoder`, propagated to the ETC1S
and UASTC LDR block-row loops. It checks init, metadata, start-transcoding,
image-level, Zstd output, and block-row boundaries without global or
thread-global mutable state. The bundled BSD-3-Clause Zstd entry adds
`ZSTD_decompress_fsv`. Its callback and cumulative output count live on the
request-owned static `ZSTD_DCtx`. The checked, 8-byte-aligned estimated
workspace is allocated directly through the request allocator, initialized by
`ZSTD_initStaticDCtx`, and released through its exact allocation token after
success, decode failure, cancellation, or initialization failure. Static
context storage is never passed to `ZSTD_freeDCtx`. A null request control
retains the pinned heap-backed one-shot behavior. The exact frame loop checks
after every decoded block.
`basisu_containers.h` exposes the logical vector allocation size; the KTX2
transcoder state clears its decoded-level vector on every controlled return.
Task 5E.2 gives `ktx2_transcoder` an explicit non-owning request allocator
binding. The Level Index, DFD, outer KVD, each nested KVD key/value vector,
ETC1S image descriptors, and covered Zstd decoded-level state allocate and
release directly through that request allocator. Rebinding first clears the
old request's owned storage. Controlled returns clear the explicit decoded-
level state and unbind its non-owning allocator before caller-owned controls
can expire. A null binding retains the pinned upstream malloc/realloc/free
behavior. Overflow-safe Level Index range checks reject malformed 64-bit
offset/length pairs before pointer arithmetic. Request cancellation checkpoints
separate the completed Level Index, DFD, outer KVD, KVD relocation, and each
completed KVD entry so partial metadata construction unwinds through exact
owner release. The decoded-level vector no longer carries a duplicate
`fsv_try_reserve` envelope; the Zstd context is the direct static-workspace
allocation above. Final post-5E.6 hashes are frozen in
`FSV_CODEC_CONTROL_PROVENANCE.sha256`.

Task 5E.3 binds the reached low-level ETC1S transcoder to the same request
allocator. Endpoint and selector palettes, persistent and temporary Huffman
models, selector history, default and caller predictors, all 32 prior-frame
vectors, and per-level temporaries therefore use fallible request-controlled
growth. The per-level state guard clears and unbinds predictor, prior-frame,
and decoded-level storage before a caller-owned control may expire. A null
control retains the pinned allocator behavior.

KVD lists can exceed the pinned vector's initial eight-entry capacity. The
allocator-aware nontrivial mover therefore selects a nothrow move constructor
before a potentially allocating copy constructor. `ktx2_level_index` is also
narrowly declared bitwise-copyable because its packed integer fields are
representation-only wrappers; this preserves the controlled Level Index
allocation path under the project's full `-fno-exceptions` evidence build.

The package bridge directly request-allocates input bytes, preflight layouts
and diagnostics, codec metadata/state, decoded mip/result storage, and bridge
staging. The former broad retained-output reservation is removed; checked
layout, pixel, output, platform-message, aggregate-budget, and overflow
preflight remains in place. Each Zstd-decoded KTX2 level is allocated directly
by the codec state above, while the static Zstd context workspace is separately
request-allocated and exactly released. Native result bytes remain charged
through the Java or Objective-C managed copy and release before request-control
destruction; managed heap storage remains outside `maxNativeWorkingBytes`.
RAII releases every controlled allocation on success, codec failure,
allocation failure, budget rejection, cancellation, deadline, corruption, and
platform serialization failure. The bridge fully validates KVD structure before
rejecting an exact `KTXanimData` key as unsupported by the selected 2D glTF
material profile. Published raw RGBA output remains governed by the separate
native-output budget. The narrow exception-to-diagnostic guard is compiled only
when C++ exceptions are enabled; exception-disabled evidence builds retain the
same explicit controlled-return path without an invalid `try`/`catch` construct.

## Verification

Task 5E.1 adds a narrowly scoped allocator seam to `basisu_containers.h` and
`basisu_containers_impl.h`. A null allocator keeps the pinned upstream
malloc/realloc/free path. A request allocator carries a linear, move-only
allocation record (pointer, bytes, alignment, allocator identity). Record move
assignment is deleted so a live token cannot be overwritten; exact token swaps
cover storage transfer. Controlled growth allocates before publishing and exact
release cannot escape to raw free. Nontrivial relocation either uses a bitwise
or nothrow move contract, or a copy-constructible rollback path that destroys a
partial destination and retains the source. Nested vectors preserve each child
allocator during relocation and cross-control copy, move, shrink, and swap.
The nontrivial mover and bitwise `memcpy` paths are mutually exclusive, so a
successful constructed relocation cannot be overwritten by raw bytes.
Move construction keeps the source as an empty vector bound to its original
allocator and retains a separate destination owner while transferring storage
and its exact token once. In exception-disabled builds, allocator-bound
nontrivial relocation/copy/move rejects before allocation unless the selected
construction is nothrow; the null/raw upstream path remains unchanged.
Controlled capacity shrink copies directly into its single preallocated
replacement block, retains the requested capacity, and does not introduce a
second temporary allocation that can spuriously exhaust the request budget or
heap ordinal. The allocator-aware public copy constructor tracks each
successfully constructed element and, when a later copy throws, destroys the
partial destination, releases its exact storage and allocator owner, preserves
the source, and rethrows the original exception.
In exception-disabled builds, copy-only operations use a separate copy-safety
predicate instead of inheriting the broader relocation predicate. A controlled
mixed-trait element with potentially throwing copy but nothrow move is rejected
before owner retention or allocation by public copy construction, and before
replacement allocation by capacity shrink. For controlled nested vectors, the
same preflight recursively inspects the actual source children before changing
any outer or child owner/allocation accounting; this prevents a nested unsafe
copy from aborting only after outer storage was allocated. A top-level null/raw
copy or shrink retains the pinned upstream behavior.
The mirrored platform control owns the request allocator and rejects lifetime
or exact-release mismatches.

From this directory:

```sh
shasum -a 256 -c VENDORED_SOURCES.sha256
```

The manifest covers every one of the 28 tracked files in `transcoder/` and
`zstd/` that form the vendored compile/include source set and its bundled Zstd
license record.
