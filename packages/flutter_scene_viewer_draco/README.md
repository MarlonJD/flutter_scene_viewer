# flutter_scene_viewer_draco

Optional native Draco decoder plugin for `flutter_scene_viewer`.

The root `flutter_scene_viewer` package stays pure Dart. Apps that need
`KHR_draco_mesh_compression` add this sibling plugin and opt in per platform.

## iOS opt-in

Add this key to the application `Info.plist`:

```xml
<key>FlutterSceneViewerDracoEnabled</key>
<true/>
```

## Android opt-in

Add this metadata entry to the application manifest:

```xml
<meta-data
    android:name="flutter_scene_viewer_draco_enabled"
    android:value="true" />
```

When the plugin is absent, disabled, or built without the Draco C++ decoder,
the core loader reports a typed `unsupportedModelFeature` diagnostic instead
of silently importing unsupported compressed geometry.

Current status: this package contains the platform opt-in, MethodChannel, JNI,
ObjC++, CMake, C++ bridge contract, and vendored Google Draco 1.5.7 source.
The Android CMake and iOS podspec configurations link a decoder-only Draco
source set inside this sibling plugin. The MethodChannel exposes
`getDecoderAvailability` and `decodeGlb`. The decode call receives a
`dracoPrimitives` manifest with compressed buffer bytes, Draco attribute ids,
and target accessor schemas so native code can focus on primitive decode. The
decode method may return either rewritten, importer-ready GLB `bytes`, or
`decodedPrimitives` entries with `meshIndex`, `primitiveIndex`, decoded
`attributes`, and optional decoded `indices`. The root package rewrites
`decodedPrimitives` into importer-ready GLB bytes and re-runs capability
preflight before import. iOS has a candidate Google Draco primitive bridge for
manifest-backed decode, verified locally in an iOS Simulator evidence app with
A1B32 rendering through native Draco decode. Android has the matching C++
primitive decode bridge and JNI result marshaling to MethodChannel
`decodedPrimitives`, but Android NDK/SDK native app build verification is still
pending. No platform returns fake geometry bytes.

Each decode now carries a unique request id. `cancelDecode`, background request
ownership, cooperative pinned-codec checkpoints, and exactly-once terminal
delivery prevent a cancelled request from publishing late output. Every
reachable native C++ request, codec, preflight, decoded-output, and
retained-result owner is budgeted. Android JNI and iOS Objective-C++ reject
unrepresentable platform sizes, check cancellation before and after each
attribute/index copy, discard partial managed responses, and keep the native
result charged until copying completes. The conservative outer reservation is
removed; exact request-owned allocations enforce the native peak directly. On
iOS, serialization failure completes the MethodChannel call exactly once with
a typed terminal error, while caller cancellation and deadline preserve their
first terminal reason.

The tracked [Plan 017 decoder/mip evidence contract](../../tools/decoder_mip_acceptance/README.md)
keeps discovery, simulator, physical-device, build-only, and packaged runtime
evidence separate. Current package/runtime evidence is `not run`, Android
capture is `blocked` by the unavailable device/build environment, and release
remains `release pending`.

Native request construction, preflight scratch, codec objects, decoded
attribute/index bytes, diagnostics, and retained C++ result containers are
charged to the active request's `maxNativeWorkingBytes` control. Native output
also remains subject to `maxNativeOutputBytes`. Serialization into Java,
Objective-C, or Flutter message objects copies from that live native result;
those managed-runtime allocations are outside `maxNativeWorkingBytes`. The
platform adapters size-check and failure-check those copies but do not claim to
intercept the Java, Objective-C, or Flutter managed heaps. Physical Android/iOS
runtime evidence remains `not run`, and release remains `release pending`.
