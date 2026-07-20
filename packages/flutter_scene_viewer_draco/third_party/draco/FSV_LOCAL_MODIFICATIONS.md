# flutter_scene_viewer Draco codec-control modifications

The vendored source is Google Draco 1.5.7 commit
`8786740086a9f4d83f44aa83badfbea4dce7a1b5`, Apache-2.0. Local modified
files carry `FSV LOCAL MODIFICATION` notices. The exact original and patched
hashes are recorded in `FSV_CODEC_CONTROL_PROVENANCE.sha256`.

The local seam passes a request-owned cooperative control through the public
decode entry, header/topology/attribute stages, the sequential face loops, and
the Edgebreaker connectivity loop. Checkpoint granularity is at most 256
faces, points, values, or connectivity symbols in the patched loops. The
package bridge passes the same explicit request control through preflight,
codec work, decoded output, retained results, and platform serialization. It
does not use a process-global or TLS current-request hook.

The local allocator foundation extends that control with aligned allocation
and release callbacks plus distinct budget, stopped, and heap-failure
outcomes. The controlled mesh entry constructs request-aware mesh,
point-cloud, attribute, data-buffer, corner-table, and sequential decoder
containers. Edgebreaker topology maps and vectors, traversal stacks and
visited state, point-id sequencing, RANS/symbol tables, and every mesh
prediction scheme accepted by the decoder factory now allocate through the
same request. Prediction schemes retain ordinary `std::unique_ptr` ownership
through a request-aware object allocation header that releases the exact
reservation at virtual deletion. Direct decoded objects and decoder,
sequencer, controller, transform, attribute, data-buffer, and corner-table
objects use the same allocation header. Sequential connectivity indices,
generic and integer attribute conversion scratch, quantization minima, and
inverse-quantization scratch use request-aware allocators as well.
`DataBuffer` and `AttributeTransformData` copy/move operations either bind
storage to an explicit destination request or detach it onto the host
allocator. `PointAttribute::CopyFrom` uses the destination control for both
the transform object and its parameter buffer, so copied parameters remain
valid after the source object and source request control are destroyed.

Geometry, attribute, and nested metadata objects; entry and submetadata maps;
names and entry blobs; attribute-metadata vectors; and metadata-decoder
traversal scratch now use the explicit request control. Large entry blobs are
copied in bounded 256-byte chunks with stop checks. Explicit destination-bound
copies recursively rebind to the destination request, while ordinary
copy/move operations detach from the source control. Controlled `Status`
error text follows the same rule and is not allocated after the request has
entered a terminal stopped state. Null-control objects retain the pristine
`std::string`, `std::vector`, and `std::map` public source surface and behavior.
Controlled objects keep request-owned canonical storage; their exact legacy
STL-reference accessors materialize detached host snapshots only when an
encoder or tool explicitly calls those accessors. The production Android/iOS
mesh bridge and controlled decode path do not call them. `Status` literal
construction uses a nonallocating view, and the `DRACO_RETURN_IF_ERROR` and
`StatusOr` rvalue handoffs explicitly preserve control ownership through the
final returned error.

These private-storage changes intentionally change the binary layouts of
`Status`, `EntryValue`, `Metadata`, and `GeometryMetadata`. The vendored Draco
copy is compiled into each plugin from source, and none of those C++ types is
present in either platform bridge header, so there is no supported external
binary ABI to preserve. Public source signatures are compile-checked against
the pristine `metadata_encoder.cc`; `Metadata` remains non-polymorphic with no
virtual destructor or vptr.

The bridge maps budget exhaustion separately from heap failure. Stateful
request allocators now own native request bytes, strings, maps, accessor
schemas, preflight scratch, decoded mesh/metadata intermediates, attribute and
index output, ordinary diagnostics, and retained result containers. Native
tests assert byte-identical Box decoding and byte-identical direct/bridge
decoding of a deterministic sequential fixture, zero live tracked bytes after
every terminal path, and typed failure at each request-owned allocation
ordinal. Codec-only totals remain locked at 110 for official Box, 68 for the
sequential fixture, and 47 for metadata source ownership. Separately, the
post-removal bridge-inclusive totals/peaks are Box 132/24,926 bytes,
sequential 96/20,921 bytes, metadata 63/30,083 bytes, and deterministic
two-primitive Box 256/27,594 bytes. The metadata fixture also locks 22
destination-copy allocations, 26 request-inclusive corrupt-input allocations,
and 14
allocations before calibrated blob-copy cancellation.
The repository-local codec adapter retains the causal pointer, byte count, and
alignment for every live codec allocation. Its small inline registry has a
request-allocated overflow vector rather than a fixed model-size ceiling.
Wrong-pointer, wrong-size, wrong-alignment, and stale-record double releases
are rejected without consuming the correct release retry. Bridge accessor,
request, and diagnostic owners require an explicit destination control when
copied; ordinary copy construction is disabled. Android JNI string acquisition
uses an immediate scope guard so request allocation failure still releases the
JVM UTF buffer exactly once.
Direct ownership tests additionally lock EntryValue source/destination counts
at 4/2, ordinary Metadata detach at 3 source allocations, and controlled
Status source/destination counts at 1/1. Destination-copy heap failure is
swept at every ordinal 1-22. A successful controlled decode has 47 host-level
allocations, all 47 accounted for by the request allocator, so no legacy
snapshot is materialized. Corrupt final status ownership and its calibrated
allocation failure are checked at ordinal 14. The compiled
`SymbolBitDecoder` is
mechanically required to remain unreachable from the mesh decode slice; its
storage is not converted. Dead-strip symbol inspection likewise proves that
compiled structural-metadata/property population owners are unreachable from
the accepted mesh decode path. The conservative outer reservation is removed;
exact request-owned allocations reject each fixture's peak-minus-one without
double charging. Java, Objective-C, and Flutter message allocations used to
serialize the already-accounted native result are managed-runtime allocations
outside `maxNativeWorkingBytes`; this package does not claim ownership of those
heaps. Platform copies reject unrepresentable signed sizes, check stop state
before and after every attribute/index copy, release partial local objects, and
publish only an atomic complete response while the native result remains live.
On iOS, the first captured caller/deadline stop reason is retained before
registry finish destroys the control; every non-detached success disposition
with a missing managed response now completes exactly once with a typed
terminal error instead of leaving the MethodChannel call pending.
The production
Edgebreaker path passes the request into its `CornerTable` and its positional
and non-position `MeshAttributeIndicesEncodingData` owners.

Each controlled allocation attempt returns its pointer and immutable causal
outcome together. Caller/deadline stop, budget exhaustion, and host heap
failure remain distinct even when stop and heap failure race; the first atomic
terminal reason wins.

Android compiles the decoder-only files selected by `android/CMakeLists.txt`;
iOS compiles the matching vendored decoder set through
`ios/Classes/fsv_draco_vendor_sources.cc`. Package tests verify the manifest,
compiled inclusion, official Box/A1B32 success bytes, cancellation mutation,
reservation mutation, and sanitizer runners.
