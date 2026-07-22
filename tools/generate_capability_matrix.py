#!/usr/bin/env python3
"""Generate the selected glTF extension capability matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = (
    REPO_ROOT
    / "tools/capability_matrix/selected_gltf_extension_capabilities.json"
)
HISTORICAL_PLAN014_SNAPSHOT_PATH = (
    REPO_ROOT
    / "tools/capability_matrix/history/plan014_feature_target_snapshot.json"
)
HISTORICAL_PLAN014_SOURCE_PATH = (
    REPO_ROOT
    / "tools/capability_matrix/history/plan014_selected_extension_capabilities.json"
)
EVIDENCE_MANIFEST_PATH = (
    REPO_ROOT / "tools/decoder_mip_acceptance/manifest.json"
)
EVIDENCE_RECORDS_DIR = REPO_ROOT / "tools/decoder_mip_acceptance/records"
OUTPUT_PATH = REPO_ROOT / "docs/generated/capability_matrix.md"
TARGET_LABELS = {
    "ios_simulator": "iOS Simulator",
    "ios_physical": "physical iOS",
    "android": "Android",
    "web": "Web",
}
HOST_STAGE_KEYS = ("parsed", "preserved", "decoded")
TARGET_ROW_KEYS = (
    "applicationKind",
    "applied",
    "visuallyVerified",
    "runtimeCapability",
    "releaseMaturity",
    "targetEvidence",
    "blocker",
)
MATURITY_VALUES = {
    "diagnostic-only",
    "candidate-only",
    "release pending",
    "production-ready",
}
EVIDENCE_VALUES = {"not run", "verified locally"}
APPLIED_VALUES = {"blocked", "not run", "unsupported", "verified locally"}
RUNTIME_CAPABILITY_VALUES = {
    "available",
    "diagnostic-only",
    "candidate-only availability",
    "candidate-only native plugin",
    "candidate-only pure-Dart rewrite",
    "unsupported",
    "production-ready",
    "not run",
}
APPLICATION_KIND_VALUES = {
    "not recorded",
    "not run",
    "rendererNative",
}
PLAN018_RENDERER_NATIVE_EVIDENCE_PATH = (
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/"
    "ios_simulator/renderer-native-run-05/evidence.json"
)
PLAN018_RENDERER_NATIVE_EVIDENCE_SHA256 = (
    "9f4d3e1b2c561174c9426ad0da653f09c8c3d8ab7494bdfa7dcdf06d121f74da"
)
PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_PATH = (
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/"
    "ios_simulator/candidate-run-14/evidence.json"
)
PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_SHA256 = (
    "87cb87f7ecce3b5916ae72896d1b7980ca6d950ef18a2aed2165734cb8d05cbb"
)
PLAN018_SHEEN_EVIDENCE = {
    "rendererNative": {
        "path": PLAN018_RENDERER_NATIVE_EVIDENCE_PATH,
        "sha256": PLAN018_RENDERER_NATIVE_EVIDENCE_SHA256,
        "applicationKind": "rendererNative",
        "visualEvidence": "verified locally",
        "runtimeAvailability": "available",
        "maturity": "release pending",
        "targetEvidence": "verified locally",
    },
    "historicalCandidate": {
        "path": PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_PATH,
        "sha256": PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_SHA256,
        "applicationKind": "packageLocalCandidate",
        "executionEvidence": "verified locally",
        "visualEvidence": "not run",
        "maturity": "candidate-only",
        "targetEvidence": "not run",
    },
}
PLAN018_SHEEN_TARGET_ROWS = {
    "ios_simulator": {
        "applicationKind": "rendererNative",
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "available",
        "releaseMaturity": "release pending",
        "targetEvidence": "verified locally",
        "blocker": (
            "renderer-local scalar sheen on/off evidence is recorded at "
            f"{PLAN018_RENDERER_NATIVE_EVIDENCE_PATH}; release and "
            "production-ready evidence remain not run"
        ),
    },
    "ios_physical": {
        "applicationKind": "not run",
        "applied": "not run",
        "visuallyVerified": "not run",
        "runtimeCapability": "not run",
        "releaseMaturity": "release pending",
        "targetEvidence": "not run",
        "blocker": (
            "no physical-iOS renderer-native sheen runtime/render or "
            "release-packaging run"
        ),
    },
    "android": {
        "applicationKind": "not run",
        "applied": "not run",
        "visuallyVerified": "not run",
        "runtimeCapability": "not run",
        "releaseMaturity": "release pending",
        "targetEvidence": "not run",
        "blocker": (
            "no Android renderer-native sheen runtime/render or "
            "release-packaging run"
        ),
    },
    "web": {
        "applicationKind": "not run",
        "applied": "not run",
        "visuallyVerified": "not run",
        "runtimeCapability": "not run",
        "releaseMaturity": "release pending",
        "targetEvidence": "not run",
        "blocker": (
            "no Web renderer-native sheen runtime/render or "
            "release-packaging run"
        ),
    },
}
HISTORICAL_PLAN014_IOS_SIMULATOR_EVIDENCE = (
    "tools/out/material_extension_acceptance/"
    "plan014_extended_pbr_ios_simulator/evidence.json"
)
HISTORICAL_PLAN014_VERIFIED_TARGET_ROWS = {
    ("KHR_texture_transform", "ios_simulator"): {
        "applicationKind": "not recorded",
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator transform evidence recorded at "
            f"{HISTORICAL_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_materials_specular", "ios_simulator"): {
        "applicationKind": "not recorded",
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator specular evidence recorded at "
            f"{HISTORICAL_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_materials_ior", "ios_simulator"): {
        "applicationKind": "not recorded",
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator opaque-IOR evidence recorded at "
            f"{HISTORICAL_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_draco_mesh_compression", "ios_simulator"): {
        "applicationKind": "not recorded",
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only native plugin",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only A1B32 Draco decode/render evidence recorded at "
            f"{HISTORICAL_PLAN014_IOS_SIMULATOR_EVIDENCE}; native in-flight "
            "cancellation, allocation control, and release packaging remain "
            "unverified"
        ),
    },
}
PLAN014_LIVE_TARGET_ROW_DIFFERENCES = [
    {
        "feature": "KHR_materials_clearcoat",
        "target": "ios_simulator",
        "field": "blocker",
        "historicalValue": (
            "current Plan 014 target run is absent; renderer-native "
            "integration is deferred to Plan 015"
        ),
        "liveValue": (
            "durable current target run is absent; renderer-native integration "
            "was completed separately by Plan 015"
        ),
    },
    {
        "feature": "KHR_materials_transmission",
        "target": "ios_simulator",
        "field": "blocker",
        "historicalValue": (
            "current Plan 014 target run is absent; renderer-native glass is "
            "deferred to Plan 016"
        ),
        "liveValue": (
            "durable current target run is absent; renderer-native glass was "
            "completed separately by Plan 016"
        ),
    },
    {
        "feature": "KHR_materials_volume",
        "target": "ios_simulator",
        "field": "blocker",
        "historicalValue": (
            "current Plan 014 target run is absent; full volume transport is "
            "deferred to Plan 016"
        ),
        "liveValue": (
            "durable current target run is absent; full volume transport was "
            "completed separately by Plan 016"
        ),
    },
    {
        "feature": "KHR_texture_basisu",
        "target": "ios_simulator",
        "field": "blocker",
        "historicalValue": (
            "no current Plan 014 iOS Simulator transcode/import/render or "
            "packaging run"
        ),
        "liveValue": (
            "no durable iOS Simulator transcode/import/render or packaging run"
        ),
    },
]
PLAN014_LIVE_TARGET_ROW_DIFFERENCES_SHA256 = (
    "7ac7b800fd80c6f6fc9e6e462014f7a3746d652af47567a263ffca86c84ef636"
)
UNVERIFIED_TARGET_BLOCKERS = {
    (
        "KHR_texture_transform",
        "ios_physical",
    ): "package-local FSViewerExtendedPbr transform path has no physical-device run",
    (
        "KHR_texture_transform",
        "android",
    ): "package-local FSViewerExtendedPbr transform path has no Android runtime/render run",
    (
        "KHR_texture_transform",
        "web",
    ): "package-local FSViewerExtendedPbr transform path has no Web runtime/render run",
    (
        "KHR_materials_specular",
        "ios_physical",
    ): "package-local FSViewerExtendedPbr specular path has no physical-device run",
    (
        "KHR_materials_specular",
        "android",
    ): "package-local FSViewerExtendedPbr specular path has no Android runtime/render run",
    (
        "KHR_materials_specular",
        "web",
    ): "package-local FSViewerExtendedPbr specular path has no Web runtime/render run",
    (
        "KHR_materials_ior",
        "ios_physical",
    ): "package-local FSViewerExtendedPbr opaque-IOR path has no physical-device run",
    (
        "KHR_materials_ior",
        "android",
    ): "package-local FSViewerExtendedPbr opaque-IOR path has no Android runtime/render run",
    (
        "KHR_materials_ior",
        "web",
    ): "package-local FSViewerExtendedPbr opaque-IOR path has no Web runtime/render run",
}
NATIVE_ONLY_WEB_ROWS = {
    "KHR_draco_mesh_compression": "the optional Draco decoder is native-only; no Web decoder is provided",
    "KHR_texture_basisu": "the optional BasisU transcoder is native-only; no Web transcoder is provided",
}
HISTORICAL_PLAN014_CONTEXT = [
    {
        "feature": "KHR_draco_mesh_compression",
        "target": "ios_simulator",
        "evidenceStatus": "verified locally",
        "evidenceDate": "2026-07-04",
        "scope": "historical Plan 013 iPhone 17 Simulator candidate run",
        "source": "docs/exec-plans/completed/013_v2_production_glb_pipeline.md",
        "artifactDurability": "not durable",
        "currentPlan014TargetEvidence": "verified locally",
        "releaseMaturity": "candidate-only",
    },
    {
        "feature": "KHR_texture_basisu",
        "target": "ios_simulator",
        "evidenceStatus": "verified locally",
        "evidenceDate": "2026-07-05",
        "scope": "historical Plan 013 iPhone 17 Simulator candidate run",
        "source": "docs/exec-plans/completed/013_v2_production_glb_pipeline.md",
        "artifactDurability": "not durable",
        "currentPlan014TargetEvidence": "not run",
        "releaseMaturity": "candidate-only",
    },
]
NATIVE_CODEC_TARGETS = {
    "KHR_draco_mesh_compression",
    "KHR_texture_basisu",
}
DECODER_CONTROL_BOUNDARIES = [
    {
        "feature": "EXT_meshopt_compression",
        "implementation": "yieldable pure-Dart EXT-v0 decode and GLB rewrite",
        "allocationControl": "declared-output and aggregate rewrite budgets use atomic commit outside the decoder loop",
        "timeoutControl": "cooperative Dart deadline checkpoints are enforced across claimed modes and filters",
        "cancellationControl": "cooperative caller cancellation checkpoints are enforced across claimed modes and filters",
        "resourceRelease": "timed-out decode buffers become garbage-collectible after stack unwind; deterministic collection is not guaranteed",
        "blockingApi": "asynchronous decoder accepts an internal deadline control and a load cancellation token",
        "bridgeContract": "not applicable; Meshopt has no native MethodChannel bridge",
        "evidenceSources": [
            "lib/src/internal/meshopt_decoder.dart",
            "lib/src/internal/glb_meshopt_rewriter.dart",
            "lib/src/internal/glb_decode_budget.dart",
        ],
        "evidenceSha256": {
            "lib/src/internal/meshopt_decoder.dart": "f7efcea019d4b7505bf7eede8d9ae2310a57308956f66dd3d2dc794774577e7c",
            "lib/src/internal/glb_meshopt_rewriter.dart": "26d3462406d1f2f9c1dcec4ec9c09b0bcd876082064731878bafd70839114a86",
            "lib/src/internal/glb_decode_budget.dart": "8661beb697dcaa363cf858dfe67f99bd34329086fe6f217615556ad947cf2e2c",
        },
    },
    {
        "feature": "KHR_draco_mesh_compression",
        "implementation": "synchronous pinned Google Draco 1.5.7 native decode",
        "allocationControl": "every reachable native request, codec, preflight, decoded output, and retained-result allocation is request-owned; managed platform message copies are size-guarded but outside maxNativeWorkingBytes",
        "timeoutControl": "one shared Dart deadline cancels the active request; native stop latency is bounded by pinned codec-loop checkpoints",
        "cancellationControl": "requestId and cancelDecode reach a request-owned atomic control checked inside pinned topology, attribute, and output loops",
        "resourceRelease": "request-owned native allocations release by normal unwind after success, cancellation, deadline, budget, heap failure, and corruption; exact live-byte gates cover bridge and platform-copy lifetimes",
        "blockingApi": "the repo-local pinned DecodeMeshFromBuffer overload and platform serializers accept explicit request control; no global/TLS current-request state is used",
        "bridgeContract": "decodeGlb carries a unique requestId; missing native controls fail atomically before registry or native work; signed-size guards and pre/post-copy stop checks keep native results alive until atomic managed serialization completes; every non-detached request delivers exactly one response or typed terminal error and no partial response escapes",
        "evidenceSources": [
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h",
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/core/fsv_decode_allocator.h",
            "packages/flutter_scene_viewer_draco/third_party/draco/FSV_LOCAL_MODIFICATIONS.md",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.h",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.cc",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_owned.h",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_platform_serialization.h",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/flutter_scene_viewer_draco_jni.cc",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FsvDecodeRequestRegistry.java",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.h",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_owned.h",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_platform_serialization.h",
            "packages/flutter_scene_viewer_draco/ios/Classes/FlutterSceneViewerDracoPlugin.mm",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.h",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.cc",
            "lib/src/internal/glb_native_decoder_probe.dart",
        ],
        "evidenceSha256": {
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h": "84845292bd3f94068e7ac79f28d74207637fae449d5f75c0913dc0bdf004d5d3",
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/core/fsv_decode_allocator.h": "cdfe7df8ec909d58b0a87635551f4e67d08f39bec099f8b077e63094c034bb36",
            "packages/flutter_scene_viewer_draco/third_party/draco/FSV_LOCAL_MODIFICATIONS.md": "dfc98cfc0a5c39dbd101cd7f7dfba4a0f88f1e228196a49180661d0d754c7a5f",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.h": "c504953bedd79711b67f2921509e0e1551768f1d706430132148e0b8b3bbe5f7",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_control.cc": "3d24f41d8c38a1731448e6cd9bdb9bb96baa8a0c0aabf438ea81bb82119569cc",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_owned.h": "ced809b240b08d7ae168f046427b3bfba7a9351e4fa6bc4e25fa5c9336170f89",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc": "71c51e292687c7fe0b597b43204517aadb108b0f6ed7a2a903bce605ed1e4e54",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_platform_serialization.h": "3a1fb97462c5abccf1b4f2badde948e3391b05d24920327a78213e9d4f0d9999",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/flutter_scene_viewer_draco_jni.cc": "f031ce9319c980d0b3e17b4fbdb2015448383c0c8c2a2c654a636841893d9d70",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java": "d898e973fdc447eba5c770dcb5f8894f86e3b7067f9441550beb91e18e446b87",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FsvDecodeRequestRegistry.java": "98db643056e14809f1393620777b274145a3af45c3d573e470013722705490cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.h": "c504953bedd79711b67f2921509e0e1551768f1d706430132148e0b8b3bbe5f7",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_control.cc": "3d24f41d8c38a1731448e6cd9bdb9bb96baa8a0c0aabf438ea81bb82119569cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_owned.h": "ced809b240b08d7ae168f046427b3bfba7a9351e4fa6bc4e25fa5c9336170f89",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc": "71c51e292687c7fe0b597b43204517aadb108b0f6ed7a2a903bce605ed1e4e54",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_platform_serialization.h": "3a1fb97462c5abccf1b4f2badde948e3391b05d24920327a78213e9d4f0d9999",
            "packages/flutter_scene_viewer_draco/ios/Classes/FlutterSceneViewerDracoPlugin.mm": "d5541a5509b5e6396706e6038b16f1183316c3672529be2130aecaf57ad3e202",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.h": "8513d6d1568bc53b2866e24e8a8ad2720ca5b5882d939be34771b98fed14d686",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_request_registry.cc": "46931fdb669a061608307c0882911b8b74067bfa6c035cae838ffd55648a94d1",
            "lib/src/internal/glb_native_decoder_probe.dart": "691b5ec51b2e02259de62e05d9016aa2cb5eed98b8263a478561c241a45ad7ed",
        },
    },
    {
        "feature": "KHR_texture_basisu",
        "implementation": "synchronous pinned Basis Universal KTX2 native transcode",
        "allocationControl": "every reached native request input, preflight, metadata, ETC1S codec state, Zstd workspace, decoded output, retained-result, and bridge-staging allocation is request-owned; managed platform message copies are size-guarded but outside maxNativeWorkingBytes",
        "timeoutControl": "one shared Dart deadline cancels the active request; native stop latency is bounded by metadata-owner, image, ETC1S/UASTC block-row, and Zstd block-output checkpoints",
        "cancellationControl": "requestId and cancelDecode reach a request-owned atomic control checked inside pinned BasisU and Zstd codec loops",
        "resourceRelease": "request-owned native allocations release by normal unwind after success, cancellation, deadline, budget, heap failure, corruption, and platform serialization failure; exact live-byte gates cover codec, bridge, and platform-copy lifetimes",
        "blockingApi": "the repo-local pinned KTX2, ETC1S, and static-Zstd paths plus platform serializers accept explicit request control; no global/TLS current-request state is used",
        "bridgeContract": "decodeGlb carries a unique requestId; signed-size guards and pre/post-copy stop checks keep native results alive until atomic managed serialization completes; every non-detached request delivers exactly one response or typed terminal error and no partial response escapes",
        "evidenceSources": [
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_containers.h",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder_internal.h",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.cpp",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/zstd/zstd.h",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/zstd/zstddeclib.c",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/FSV_LOCAL_MODIFICATIONS.md",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_budget.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_budget.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_owned.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_platform_serialization.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FlutterSceneViewerBasisuPlugin.java",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FsvDecodeRequestRegistry.java",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.cc",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_budget.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_budget.cc",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_owned.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.cc",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_platform_serialization.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.h",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.cc",
            "lib/src/internal/glb_native_decoder_probe.dart",
        ],
        "evidenceSha256": {
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_containers.h": "312c491ed8d15323dc3a9d617da2d05569e9ed0d02b99c29ae43911a5a156c8a",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder_internal.h": "da36bb4e18483bda1804bb45de25a9ea65f36d82f1d16b92d3c3fbe3c7d831c5",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h": "5a0b32d64e3335a9926a8bf17ba3cb7120cbaf48042859c14be6ff96d4aeb551",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.cpp": "316c54c224889e7b887c66663b6668e51ec90b89a7d836db8deec167b1b239d2",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/zstd/zstd.h": "704a4c95feec9487ade1db223b7b4bcd745711c96421f4b57f7f71ea9438fc1c",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/zstd/zstddeclib.c": "2107e6c0d421f5c0bb838d978f6b20bbd14b5b8c493e5be55247f645020284b4",
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/FSV_LOCAL_MODIFICATIONS.md": "6d9e1984399050c50392c5638431ff6c07b8dcbdd2a879b4c0fb3f17775d6794",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.h": "89d0b464615a1a3e6c788040623a7ba8fba9839705d3bf864bff234753dddfbf",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.cc": "c6d27fa6d1ac170e39cd4c787c2117d71ed28657969730e6c42baffc55c9019a",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_budget.h": "1f9c859ccea3a856d6c73e86504a46e62c4aeb509059c9cdf69f538d42073d08",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_budget.cc": "e952eb4747b4413a54fa410db2936de1d20310de98823947b806f21475b0c2f6",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_owned.h": "945572f28948be01272207b1ff0c5cb509f2434a8307681a498e8cc5b387db06",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.h": "cc05b9db420e8e2798017742c3d2ecc1de14ac7854276110b7a865be9dca99d4",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.cc": "1d3ce97e80fa6fa353eac1cb6cdde0a4d107664a1d8da3bde124c3ab057e6f58",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_platform_serialization.h": "03b98ad1809d1eb486209a135a483d3dda838ebafc402e1d3a1e30b215bbeb6b",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc": "dba89a12488c0fc2a4a1dd214d8677df1db1d43c5a6b1e136233600cfc21237e",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FlutterSceneViewerBasisuPlugin.java": "e10fdb82ab233be44317d043c3db5f1a22a59cc2f0f07b858035fe55545cd22a",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FsvDecodeRequestRegistry.java": "ffe931d33314e32c9f05448192aa828f4098f6cc1c04432cbdc44fa3e65a6744",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.h": "89d0b464615a1a3e6c788040623a7ba8fba9839705d3bf864bff234753dddfbf",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_control.cc": "c6d27fa6d1ac170e39cd4c787c2117d71ed28657969730e6c42baffc55c9019a",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_budget.h": "1f9c859ccea3a856d6c73e86504a46e62c4aeb509059c9cdf69f538d42073d08",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_budget.cc": "e952eb4747b4413a54fa410db2936de1d20310de98823947b806f21475b0c2f6",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_owned.h": "945572f28948be01272207b1ff0c5cb509f2434a8307681a498e8cc5b387db06",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.h": "cc05b9db420e8e2798017742c3d2ecc1de14ac7854276110b7a865be9dca99d4",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.cc": "1d3ce97e80fa6fa353eac1cb6cdde0a4d107664a1d8da3bde124c3ab057e6f58",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_platform_serialization.h": "03b98ad1809d1eb486209a135a483d3dda838ebafc402e1d3a1e30b215bbeb6b",
            "packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm": "ef77d609455bf57f519f96c04c042c887bd6ac5d4cb597b41911e47ff7d0890b",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.h": "fc8667dafa97fb370af14073ea722585a24875c6872ba72b9f59a6caf87093eb",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_request_registry.cc": "118bfab5a4d3f0f590dee47a8fc3b716edfb2bc36da4376a71dc3003ab1fdf1a",
            "lib/src/internal/glb_native_decoder_probe.dart": "691b5ec51b2e02259de62e05d9016aa2cb5eed98b8263a478561c241a45ad7ed",
        },
    },
]
DECODER_CONTROL_SOURCE_MARKERS = {
    "lib/src/internal/meshopt_decoder.dart": (
        "final class MeshoptDecodeControl {",
        "Future<Uint8List> decodeMeshoptGltfBuffer(",
        "required MeshoptCompressionFilter filter,",
        "MeshoptDecodeControl? control,",
        "stage: 'meshoptDecodeStart',",
        "ModelLoadCancellationToken? cancellationToken,",
    ),
    "lib/src/internal/glb_meshopt_rewriter.dart": (
        "MeshoptDecodeControl.running(",
        "timeout: tracker.budget.decodeTimeout,",
        "final rewriteTracker = GlbDecodeBudgetTracker(tracker.budget);",
        "on MeshoptDecodeStopped catch (error)",
        "cancellationToken: cancellationToken,",
    ),
    "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h": (
        "StatusOr<std::unique_ptr<Mesh>> DecodeMeshFromBuffer(",
        "DecoderBuffer *in_buffer);",
    ),
    "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h": (
        "bool init(const void* pData, uint32_t data_size);",
        "bool start_transcoding();",
        "bool transcode_image_level(",
    ),
    "lib/src/internal/glb_native_decoder_probe.dart": (
        "Map<String, Object?> _nativeDecodeBudgetMap(GlbDecodeBudget budget)",
        "'maxNativeOutputBytes': budget.maxNativeOutputBytes,",
        "final remaining = deadline.remainingOrThrow();",
        "timer = Timer(remaining, () {",
        "'cancelDecode',",
        "'nativeDispatch': dispatched ? 'started' : 'notStarted'",
        "'nativeResourceRelease': dispatched ? 'notGuaranteed' : 'notApplicable'",
    ),
}
DECODER_CONTROL_FORBIDDEN_MARKERS = {
    "lib/src/internal/meshopt_decoder.dart": (
        "decodeTimeout",
        "cancellationCheckInterval",
        "shouldCancel",
        "cancelToken",
    ),
    "lib/src/internal/glb_meshopt_rewriter.dart": (
        "shouldCancel",
        "cancelToken",
    ),
    "lib/src/internal/glb_native_decoder_probe.dart": (
        "cancellationCheckInterval",
    ),
}
DECODER_CONTROL_SOURCE_SHA256 = {
    source_path: sha256
    for record in DECODER_CONTROL_BOUNDARIES
    for source_path, sha256 in record["evidenceSha256"].items()
}


class MatrixError(RuntimeError):
    pass


def _load_evidence_manifest() -> dict[str, object]:
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))
    from tools.validate_decoder_mip_evidence import (  # pylint: disable=import-outside-toplevel
        EvidenceError,
        load_manifest,
    )

    try:
        return load_manifest(
            EVIDENCE_MANIFEST_PATH,
            EVIDENCE_RECORDS_DIR,
            verify_local_artifacts=True,
        )
    except EvidenceError as error:
        raise MatrixError(f"decoder/mip evidence is invalid: {error}") from error


def _claim_has_durable_evidence(
    manifest: dict[str, object],
    feature: str,
    target: str,
    *,
    production_ready: bool,
) -> bool:
    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))
    from tools.validate_decoder_mip_evidence import (  # pylint: disable=import-outside-toplevel
        claim_has_durable_evidence,
    )

    return claim_has_durable_evidence(
        manifest,
        feature,
        target,
        production_ready=production_ready,
    )


def load_source() -> dict[str, object]:
    value = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise MatrixError("capability source must be a JSON object")
    validate_source(
        value,
        evidence_manifest=_load_evidence_manifest(),
        evidence_artifacts_verified=True,
    )
    return value


def decoder_control_source_texts() -> dict[str, str]:
    return {
        relative_path: (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        for relative_path in DECODER_CONTROL_SOURCE_SHA256
    }


def validate_decoder_control_sources(source_texts: dict[str, str]) -> None:
    if set(source_texts) != set(DECODER_CONTROL_SOURCE_SHA256):
        raise MatrixError("decoder control source set changed")
    for relative_path, expected_sha256 in DECODER_CONTROL_SOURCE_SHA256.items():
        actual_sha256 = hashlib.sha256(
            source_texts[relative_path].encode("utf-8")
        ).hexdigest()
        if actual_sha256 != expected_sha256:
            raise MatrixError(
                f"decoder control evidence fingerprint changed in {relative_path}; "
                "reassess the blocker"
            )


def _validate_plan018_sheen_source(source: dict[str, object]) -> None:
    if source.get("plan018SheenEvidence") != PLAN018_SHEEN_EVIDENCE:
        raise MatrixError("Plan 018 sheen evidence provenance changed")
    raw_features = source.get("features")
    if not isinstance(raw_features, list):
        raise MatrixError("Plan 018 sheen feature inventory is missing")
    sheen_features = [
        feature
        for feature in raw_features
        if isinstance(feature, dict) and feature.get("id") == "KHR_materials_sheen"
    ]
    if len(sheen_features) != 1:
        raise MatrixError("Plan 018 sheen feature inventory changed")
    if sheen_features[0].get("targets") != PLAN018_SHEEN_TARGET_ROWS:
        raise MatrixError("Plan 018 sheen target evidence axes changed")
    validate_plan018_sheen_artifacts()


def validate_plan018_sheen_artifacts(repo_root: Path = REPO_ROOT) -> None:
    native_path = repo_root / PLAN018_RENDERER_NATIVE_EVIDENCE_PATH
    if native_path.is_file():
        if hashlib.sha256(native_path.read_bytes()).hexdigest() != (
            PLAN018_RENDERER_NATIVE_EVIDENCE_SHA256
        ):
            raise MatrixError("Plan 018 sheen renderer-native evidence changed")
        try:
            native = _json_object(native_path, "Plan 018 renderer-native evidence")
        except (OSError, json.JSONDecodeError, MatrixError) as error:
            raise MatrixError(
                f"Plan 018 sheen renderer-native evidence is invalid: {error}"
            ) from error
        expected_native = {
            "schemaVersion": 1,
            "scope": "flutter_scene_viewer iOS Simulator renderer-native sheen control",
            "comparisonBoundary": "renderer-local sheen on/off control only",
            "status": "release pending",
            "featureMaturity": "release pending",
            "targetEvidence": "verified locally",
            "visualEvidence": "verified locally",
            "executionEvidence": "verified locally",
            "runtimeAvailability": "available",
            "productionReadiness": "not run",
            "release": "release pending",
            "physicalIos": "not run",
            "android": "not run",
            "web": "not run",
            "physicalCorrectness": "not run",
            "generalPixelParity": "not run",
            "referenceComparison": "not run",
            "fixtureValidation": False,
            "flutterScenePin": "766351c865c621e8720c726f9aa51173ce76e786",
            "stateSha256": (
                "e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63"
            ),
            "application": {"sheenOff": "none", "sheenOn": "rendererNative"},
        }
        if any(native.get(key) != value for key, value in expected_native.items()):
            raise MatrixError("Plan 018 sheen renderer-native claims changed")
        visual_analysis = _object(
            native.get("visualAnalysis"), "Plan 018 renderer-native visual analysis"
        )
        expected_visual = {
            "status": "verified locally",
            "visualEvidence": "verified locally",
            "application": {"sheenOff": "none", "sheenOn": "rendererNative"},
            "comparisonBoundary": "renderer-local sheen on/off control only",
            "physicalCorrectness": "not run",
            "generalPixelParity": "not run",
            "productionReadiness": "not run",
        }
        if any(
            visual_analysis.get(key) != value
            for key, value in expected_visual.items()
        ):
            raise MatrixError("Plan 018 sheen visual evidence boundary changed")

    candidate_path = repo_root / PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_PATH
    if candidate_path.is_file():
        if hashlib.sha256(candidate_path.read_bytes()).hexdigest() != (
            PLAN018_HISTORICAL_CANDIDATE_EVIDENCE_SHA256
        ):
            raise MatrixError("Plan 018 sheen historical candidate evidence changed")
        try:
            candidate = _json_object(
                candidate_path, "Plan 018 historical candidate evidence"
            )
        except (OSError, json.JSONDecodeError, MatrixError) as error:
            raise MatrixError(
                f"Plan 018 sheen historical candidate evidence is invalid: {error}"
            ) from error
        expected_candidate = {
            "schemaVersion": 1,
            "scope": "flutter_scene_viewer iOS Simulator controlled sheen captures",
            "comparisonBoundary": "direction/conformance-only",
            "status": "candidate-only",
            "featureMaturity": "candidate-only",
            "executionEvidence": "verified locally",
            "referenceComparison": "not run",
            "rendererNativeSheen": "not established",
            "physicalIos": "not run",
            "android": "not run",
            "web": "not run",
            "fixtureValidation": False,
            "flutterScenePin": "8e2e2221405b04c517189428d0faf8474cf7f708",
            "stateSha256": (
                "385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843"
            ),
        }
        if any(
            candidate.get(key) != value
            for key, value in expected_candidate.items()
        ):
            raise MatrixError("Plan 018 sheen historical candidate claims changed")


def validate_source(
    source: dict[str, object],
    *,
    evidence_manifest: dict[str, object] | None = None,
    evidence_artifacts_verified: bool = False,
) -> None:
    if source.get("schemaVersion") != 3:
        raise MatrixError("schemaVersion must equal 3")
    if source.get("scope") != (
        "Selected glTF extension capability and evidence truth; historical, "
        "host, simulator, build-only, and target evidence remain independent."
    ):
        raise MatrixError("capability source scope changed")
    _validate_plan018_sheen_source(source)
    expected_historical = {
        "path": "tools/capability_matrix/history/plan014_feature_target_snapshot.json",
        "sourcePath": (
            "tools/capability_matrix/history/"
            "plan014_selected_extension_capabilities.json"
        ),
        "sourceSha256": (
            "0ebe4e6c17919e3dca21dedf0e7d21ef1eef24431c1ab8c62d408ebfd52ac74d"
        ),
        "featureTargetRowsSha256": (
            "9d9dd71db8768cf42d54319fa7996190bdc034d4270fdbe9fcc372864c19ba06"
        ),
        "historicalContextSha256": (
            "12f4205de76da66db7d89e391fc869500b5e0380f5fd88d55b1a003b2419adab"
        ),
    }
    if source.get("historicalPlan014") != expected_historical:
        raise MatrixError("historical Plan 014 fingerprint changed")
    historical_snapshot = _json_object(
        HISTORICAL_PLAN014_SNAPSHOT_PATH,
        "historical Plan 014 snapshot",
    )
    historical_payload = _json_object(
        HISTORICAL_PLAN014_SOURCE_PATH,
        "historical Plan 014 source",
    )
    if evidence_manifest is None:
        evidence_manifest = _load_evidence_manifest()
        evidence_artifacts_verified = True
    feature_set = _string_list(source.get("featureSet"), "featureSet")
    target_set = _string_list(source.get("targetSet"), "targetSet")
    if len(feature_set) != len(set(feature_set)):
        raise MatrixError("featureSet must be unique")
    if len(target_set) != len(set(target_set)):
        raise MatrixError("targetSet must be unique")
    if any(target not in TARGET_LABELS for target in target_set):
        raise MatrixError("targetSet contains an unknown target")
    if source.get("historicalContext") != HISTORICAL_PLAN014_CONTEXT:
        raise MatrixError("historical candidate context changed")
    for record in HISTORICAL_PLAN014_CONTEXT:
        if record["feature"] not in feature_set or record["target"] not in target_set:
            raise MatrixError("historical candidate context is outside matrix scope")
        if not (REPO_ROOT / record["source"]).is_file():
            raise MatrixError("historical candidate evidence source is missing")
    if (
        source.get("decoderControlBoundaries")
        != DECODER_CONTROL_BOUNDARIES
    ):
        raise MatrixError("decoder control boundary evidence changed")
    for record in DECODER_CONTROL_BOUNDARIES:
        if record["feature"] not in feature_set:
            raise MatrixError("decoder control boundary is outside matrix scope")
        for evidence_source in record["evidenceSources"]:
            if not (REPO_ROOT / evidence_source).is_file():
                raise MatrixError("decoder control evidence source is missing")
        if tuple(record["evidenceSha256"]) != tuple(record["evidenceSources"]):
            raise MatrixError("decoder control evidence fingerprints changed")
    validate_decoder_control_sources(decoder_control_source_texts())
    for relative_path, markers in DECODER_CONTROL_SOURCE_MARKERS.items():
        source_text = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        if any(marker not in source_text for marker in markers):
            raise MatrixError(
                f"decoder control evidence changed in {relative_path}; "
                "reassess the blocker"
            )
    for relative_path, markers in DECODER_CONTROL_FORBIDDEN_MARKERS.items():
        source_text = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
        if any(marker in source_text for marker in markers):
            raise MatrixError(
                f"decoder controls may now exist in {relative_path}; "
                "reassess the blocker"
            )

    features = source.get("features")
    if not isinstance(features, list):
        raise MatrixError("features must be an array")
    ids: list[str] = []
    durably_verified_target_rows: set[tuple[str, str]] = set()
    for raw_feature in features:
        feature = _object(raw_feature, "feature")
        feature_id = _string(feature.get("id"), "feature.id")
        ids.append(feature_id)
        _string(feature.get("displayName"), f"{feature_id}.displayName")
        host_stages = _object(
            feature.get("hostStages"), f"{feature_id}.hostStages"
        )
        if tuple(host_stages) != HOST_STAGE_KEYS:
            raise MatrixError(f"{feature_id}.hostStages keys changed")
        for stage, raw_record in host_stages.items():
            record = _object(raw_record, f"{feature_id}.{stage}")
            if tuple(record) != ("status", "scope", "evidence"):
                raise MatrixError(f"{feature_id}.{stage} keys changed")
            for key in record:
                _string(record[key], f"{feature_id}.{stage}.{key}")

        targets = _object(feature.get("targets"), f"{feature_id}.targets")
        if tuple(targets) != tuple(target_set):
            raise MatrixError(f"{feature_id} must define every target explicitly")
        for target, raw_row in targets.items():
            row = _object(raw_row, f"{feature_id}.{target}")
            if tuple(row) != TARGET_ROW_KEYS:
                raise MatrixError(f"{feature_id}.{target} keys changed")
            for key in TARGET_ROW_KEYS:
                _string(row.get(key), f"{feature_id}.{target}.{key}")
            if row["applicationKind"] not in APPLICATION_KIND_VALUES:
                raise MatrixError(
                    f"{feature_id}.{target} application kind is invalid"
                )
            if row["applied"] not in APPLIED_VALUES:
                raise MatrixError(f"{feature_id}.{target} applied status is invalid")
            if row["runtimeCapability"] not in RUNTIME_CAPABILITY_VALUES:
                raise MatrixError(
                    f"{feature_id}.{target} runtime capability is invalid"
                )
            if row["releaseMaturity"] not in MATURITY_VALUES:
                raise MatrixError(
                    f"{feature_id}.{target} maturity is invalid; use literal "
                    "release pending when release evidence is incomplete"
                )
            if row["targetEvidence"] not in EVIDENCE_VALUES:
                raise MatrixError(f"{feature_id}.{target} evidence is invalid")
            if row["visuallyVerified"] not in EVIDENCE_VALUES:
                raise MatrixError(f"{feature_id}.{target} visual status is invalid")
            if row["applied"] == "verified locally" and (
                row["targetEvidence"] != "verified locally"
            ):
                raise MatrixError(
                    f"{feature_id}.{target} applied status lacks target evidence"
                )
            if row["targetEvidence"] == "verified locally" and (
                row["applied"] != "verified locally"
            ):
                raise MatrixError(
                    f"{feature_id}.{target} target evidence lacks application"
                )
            if row["visuallyVerified"] == "verified locally" and (
                row["targetEvidence"] != "verified locally"
            ):
                raise MatrixError(
                    f"{feature_id}.{target} visual evidence lacks target evidence"
                )
            if (row["applied"] == "unsupported") != (
                row["runtimeCapability"] == "unsupported"
            ):
                raise MatrixError(
                    f"{feature_id}.{target} unsupported statuses disagree"
                )
            if (
                row["releaseMaturity"] == "production-ready"
                or row["runtimeCapability"] == "production-ready"
            ) and not (
                row["applied"] == "verified locally"
                and row["visuallyVerified"] == "verified locally"
                and row["targetEvidence"] == "verified locally"
                and row["runtimeCapability"] == "production-ready"
                and row["releaseMaturity"] == "production-ready"
            ):
                raise MatrixError(
                    f"{feature_id}.{target} production-ready gates are incomplete"
                )
            production_claim = (
                row["runtimeCapability"] == "production-ready"
                or row["releaseMaturity"] == "production-ready"
            )
            needs_durable_evidence = production_claim or (
                row["targetEvidence"] == "verified locally"
                and (feature_id, target)
                not in HISTORICAL_PLAN014_VERIFIED_TARGET_ROWS
            )
            plan018_native_claim = (
                feature_id == "KHR_materials_sheen" and target == "ios_simulator"
            )
            if (
                needs_durable_evidence
                and not plan018_native_claim
                and not evidence_artifacts_verified
            ):
                raise MatrixError(
                    f"{feature_id}.{target} requires verified local artifact proof"
                )
            if (
                needs_durable_evidence
                and not plan018_native_claim
                and not _claim_has_durable_evidence(
                    evidence_manifest,
                    feature_id,
                    target,
                    production_ready=production_claim,
                )
            ):
                raise MatrixError(
                    f"{feature_id}.{target} has no matching durable evidence "
                    "for its target and required gates"
                )
            if needs_durable_evidence:
                durably_verified_target_rows.add((feature_id, target))
            expected_verified_row = HISTORICAL_PLAN014_VERIFIED_TARGET_ROWS.get(
                (feature_id, target)
            )
            if expected_verified_row is not None:
                if row != expected_verified_row:
                    raise MatrixError(
                        f"{feature_id}.{target} verified target evidence row changed"
                    )
            else:
                if (
                    row["targetEvidence"] != "verified locally"
                    and row["targetEvidence"] != "not run"
                ):
                    raise MatrixError(f"{feature_id}.{target} evidence is invalid")
                if row["targetEvidence"] == "not run" and (
                    row["visuallyVerified"] != "not run"
                ):
                    raise MatrixError(
                        f"{feature_id}.{target} current visual evidence "
                        "must remain not run until a target artifact is recorded"
                    )
                if (
                    row["targetEvidence"] == "not run"
                    and row["applied"] == "verified locally"
                ):
                    raise MatrixError(
                        f"{feature_id}.{target} host evidence cannot establish "
                        "target application"
                    )
            expected_blocker = UNVERIFIED_TARGET_BLOCKERS.get(
                (feature_id, target)
            )
            if (
                expected_blocker is not None
                and row["targetEvidence"] == "not run"
                and row["blocker"] != expected_blocker
            ):
                raise MatrixError(
                    f"{feature_id}.{target} exact upstream blocker changed"
                )
            native_only_blocker = NATIVE_ONLY_WEB_ROWS.get(feature_id)
            if target == "web" and native_only_blocker is not None and row != {
                "applicationKind": "not recorded",
                "applied": "unsupported",
                "visuallyVerified": "not run",
                "runtimeCapability": "unsupported",
                "releaseMaturity": "diagnostic-only",
                "targetEvidence": "not run",
                "blocker": native_only_blocker,
            }:
                raise MatrixError(
                    f"{feature_id}.web must remain native-only and unsupported"
                )
            if (
                feature_id in NATIVE_CODEC_TARGETS
                and target != "web"
                and expected_verified_row is None
                and row["targetEvidence"] == "not run"
                and (
                    row["applied"] != "not run"
                    or row["visuallyVerified"] != "not run"
                    or row["runtimeCapability"] != "candidate-only native plugin"
                    or row["releaseMaturity"] != "candidate-only"
                    or row["targetEvidence"] != "not run"
                )
            ):
                raise MatrixError(
                    f"{feature_id}.{target} native codec target labels changed"
                )
    if ids != feature_set:
        raise MatrixError("features must exactly match featureSet order")
    validate_historical_plan014_payload(
        historical_payload,
        live_source=source,
        snapshot=historical_snapshot,
        allowed_live_row_changes=durably_verified_target_rows,
    )


def validate_historical_plan014_payload(
    historical: dict[str, object],
    *,
    live_source: dict[str, object] | None = None,
    snapshot: dict[str, object] | None = None,
    allowed_live_row_changes: set[tuple[str, str]] | None = None,
) -> None:
    if snapshot is None:
        snapshot = _json_object(
            HISTORICAL_PLAN014_SNAPSHOT_PATH,
            "historical Plan 014 snapshot",
        )
    if live_source is None:
        live_source = _json_object(SOURCE_PATH, "live capability source")
    if allowed_live_row_changes is None:
        allowed_live_row_changes = set()
    if historical.get("schemaVersion") != 1 or historical.get("scope") != (
        "Plan 014 current evidence only; historical candidate runs are context, "
        "not current target evidence."
    ):
        raise MatrixError("historical Plan 014 source identity changed")
    historical_features = _object_list(historical.get("features"), "historical features")
    rows = [
        {"feature": feature["id"], "target": target, "row": row}
        for feature in historical_features
        for target, row in _object(feature.get("targets"), "historical targets").items()
    ]
    if len(historical_features) != 9 or len(rows) != 36:
        raise MatrixError("historical Plan 014 must retain all 36 target rows")
    if _canonical_sha256(rows) != snapshot.get("featureTargetRowsSha256"):
        raise MatrixError("historical Plan 014 row payload changed")
    if _canonical_sha256(historical.get("historicalContext")) != snapshot.get(
        "historicalContextSha256"
    ):
        raise MatrixError("historical Plan 014 context payload changed")
    if _canonical_sha256(historical.get("decoderControlBoundaries")) != snapshot.get(
        "decoderControlBoundariesSha256"
    ):
        raise MatrixError("historical Plan 014 decoder boundary payload changed")
    if HISTORICAL_PLAN014_SOURCE_PATH.is_file() and hashlib.sha256(
        HISTORICAL_PLAN014_SOURCE_PATH.read_bytes()
    ).hexdigest() != snapshot.get("sourceSha256"):
        raise MatrixError("historical Plan 014 complete source payload changed")
    if (
        _canonical_sha256(PLAN014_LIVE_TARGET_ROW_DIFFERENCES)
        != PLAN014_LIVE_TARGET_ROW_DIFFERENCES_SHA256
    ):
        raise MatrixError("pinned Plan 014 live-difference digest changed")
    if snapshot.get("liveTargetRowDifferences") != (
        PLAN014_LIVE_TARGET_ROW_DIFFERENCES
    ) or snapshot.get("liveTargetRowDifferencesSha256") != (
        PLAN014_LIVE_TARGET_ROW_DIFFERENCES_SHA256
    ):
        raise MatrixError("historical Plan 014 live-difference ledger changed")

    historical_rows = {
        (feature["id"], target): _object(row, "historical target row")
        for feature in historical_features
        for target, row in _object(feature.get("targets"), "historical targets").items()
    }
    live_rows = {
        (feature["id"], target): _object(row, "live target row")
        for feature in _object_list(live_source.get("features"), "live features")
        for target, row in _object(feature.get("targets"), "live targets").items()
    }
    differences: list[dict[str, object]] = []
    for key, historical_row in historical_rows.items():
        live_row = live_rows.get(key)
        if live_row is None:
            raise MatrixError("live source dropped a historical Plan 014 row")
        for field, historical_value in historical_row.items():
            live_value = live_row.get(field)
            if live_value != historical_value:
                differences.append(
                    {
                        "feature": key[0],
                        "target": key[1],
                        "field": field,
                        "historicalValue": historical_value,
                        "liveValue": live_value,
                    }
                )
    durable_filtered_differences = [
        difference
        for difference in differences
        if (difference["feature"], difference["target"])
        not in allowed_live_row_changes
    ]
    if durable_filtered_differences != PLAN014_LIVE_TARGET_ROW_DIFFERENCES:
        raise MatrixError("live target rows differ from Plan 014 outside the ledger")


def _canonical_sha256(value: object) -> str:
    payload = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _json_object(path: Path, label: str) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    return _object(value, label)


def _object_list(value: object, label: str) -> list[dict[str, object]]:
    if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
        raise MatrixError(f"{label} must be an object array")
    return value


def select(
    source: dict[str, object],
    requested_features: list[str] | None,
    requested_targets: list[str] | None,
) -> tuple[list[dict[str, object]], list[str]]:
    feature_set = _string_list(source["featureSet"], "featureSet")
    target_set = _string_list(source["targetSet"], "targetSet")
    selected_features = requested_features or feature_set
    selected_targets = requested_targets or target_set
    unknown_features = set(selected_features) - set(feature_set)
    unknown_targets = set(selected_targets) - set(target_set)
    if unknown_features:
        raise MatrixError(f"unknown features: {sorted(unknown_features)}")
    if unknown_targets:
        raise MatrixError(f"unknown targets: {sorted(unknown_targets)}")
    if not selected_features or not selected_targets:
        raise MatrixError("feature and target selections must be non-empty")
    by_id = {
        _string(feature.get("id"), "feature.id"): feature
        for feature in source["features"]
        if isinstance(feature, dict)
    }
    return [by_id[feature_id] for feature_id in selected_features], selected_targets


def aggregate_summary(
    features: list[dict[str, object]], targets: list[str]
) -> dict[str, object]:
    rows = [
        _object(_object(feature["targets"], "targets")[target], "target row")
        for feature in features
        for target in targets
    ]
    all_applied = all(row["applied"] == "verified locally" for row in rows)
    all_visual = all(
        row["visuallyVerified"] == "verified locally" for row in rows
    )
    all_evidence = all(
        row["targetEvidence"] == "verified locally" for row in rows
    )
    all_mature = all(
        row["releaseMaturity"] == "production-ready" for row in rows
    )
    all_runtime = all(row["runtimeCapability"] == "production-ready" for row in rows)
    return {
        "featureSet": [feature["id"] for feature in features],
        "targetSet": targets,
        "allApplied": all_applied,
        "allVisuallyVerified": all_visual,
        "allTargetEvidenceVerified": all_evidence,
        "productionReady": (
            all_applied and all_visual and all_evidence and all_mature and all_runtime
        ),
    }


def render_markdown(source: dict[str, object]) -> str:
    features, targets = select(source, None, None)
    summary = aggregate_summary(features, targets)
    lines = [
        "# Capability matrix",
        "",
        "Generated by `python3 tools/generate_capability_matrix.py --write` from",
        "`tools/capability_matrix/selected_gltf_extension_capabilities.json`.",
        "Do not edit this file by hand.",
        "",
        f"Scope: {source['scope']}",
        "",
        "Host decode/validator evidence is not target render evidence.",
        "Historical candidate runs are not promoted into live target rows.",
        "",
        "The aggregate below is evaluated only for the explicit feature and target sets",
        "listed here; no backend-wide boolean is copied into individual rows.",
        "",
        f"- Feature set: {', '.join(summary['featureSet'])}",
        f"- Target set: {', '.join(TARGET_LABELS[target] for target in targets)}",
        f"- All applied: {_yes_no(summary['allApplied'])}",
        f"- All visually verified: {_yes_no(summary['allVisuallyVerified'])}",
        f"- All target evidence verified: {_yes_no(summary['allTargetEvidenceVerified'])}",
        f"- Production-ready: {_yes_no(summary['productionReady'])}",
        "",
        "## Historical candidate context",
        "",
        "This retained historical evidence does not alter any live target row.",
        "The original artifacts were temporary and are not durable release evidence.",
        "",
        "| Feature | Target | Historical evidence | Date | Scope | Source | Artifact durability | Live target evidence | Release maturity |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for record in source["historicalContext"]:
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{record['feature']}`",
                    TARGET_LABELS[record["target"]],
                    _escape(record["evidenceStatus"]),
                    _escape(record["evidenceDate"]),
                    _escape(record["scope"]),
                    f"`{record['source']}`",
                    _escape(record["artifactDurability"]),
                    _escape(record["currentPlan014TargetEvidence"]),
                    _escape(record["releaseMaturity"]),
                ]
            )
            + " |"
        )
    sheen_evidence = _object(
        source["plan018SheenEvidence"], "Plan 018 sheen evidence"
    )
    renderer_native_evidence = _object(
        sheen_evidence["rendererNative"], "Plan 018 renderer-native evidence"
    )
    candidate_evidence = _object(
        sheen_evidence["historicalCandidate"],
        "Plan 018 historical candidate evidence",
    )
    lines.extend(
        [
            "",
            "## Plan 018 sheen evidence boundary",
            "",
            "The current iOS Simulator row is bound to the finalized renderer-native",
            "scalar sheen on/off control. The earlier package-local captures remain",
            "historical `candidate-only` evidence and do not promote the live row.",
            "A renderer capture does not automatically establish visual evidence, "
            "physical correctness, general pixel parity, release, or production-ready "
            "status.",
            "",
            "| Evidence | Application kind | Visual evidence | Runtime availability | Maturity | Target evidence | Source |",
            "| --- | --- | --- | --- | --- | --- | --- |",
            (
                "| Renderer-native current | "
                f"{_escape(renderer_native_evidence['applicationKind'])} | "
                f"{_escape(renderer_native_evidence['visualEvidence'])} | "
                f"{_escape(renderer_native_evidence['runtimeAvailability'])} | "
                f"{_escape(renderer_native_evidence['maturity'])} | "
                f"{_escape(renderer_native_evidence['targetEvidence'])} | "
                f"`{renderer_native_evidence['path']}` "
                f"(`{renderer_native_evidence['sha256']}`) |"
            ),
            (
                "| Historical package-local candidate | "
                f"{_escape(candidate_evidence['applicationKind'])} | "
                f"{_escape(candidate_evidence['visualEvidence'])} | "
                "not recorded | "
                f"{_escape(candidate_evidence['maturity'])} | "
                f"{_escape(candidate_evidence['targetEvidence'])} | "
                f"`{candidate_evidence['path']}` "
                f"(`{candidate_evidence['sha256']}`) |"
            ),
        ]
    )
    lines.extend(
        [
            "",
            "## Host pipeline evidence",
            "",
            "These columns are host-scoped parser/rewriter/codec facts. They do not inherit",
            "a target label.",
            "",
            "| Feature | Parsed | Preserved | Decoded |",
            "| --- | --- | --- | --- |",
        ]
    )
    for feature in features:
        host = _object(feature["hostStages"], "hostStages")
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{feature['id']}`",
                    _host_cell(_object(host["parsed"], "parsed")),
                    _host_cell(_object(host["preserved"], "preserved")),
                    _host_cell(_object(host["decoded"], "decoded")),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Decoder control blockers",
            "",
            "This blocker-only evidence does not promote any host or target capability.",
            "A Dart `Future.timeout` bounds only Dart result consumption; it cannot prove",
            "that synchronous native work stopped or resources were released. No native-stop,",
            "resource-release, or cancellation guarantee is inferred.",
            "",
            "| Feature | Implementation | Allocation control | Timeout | Cancellation | Resource release | Blocking API | Bridge contract | Evidence sources |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for record in source["decoderControlBoundaries"]:
        lines.append(
            "| "
            + " | ".join(
                [
                    f"`{record['feature']}`",
                    _escape(record["implementation"]),
                    _escape(record["allocationControl"]),
                    _escape(record["timeoutControl"]),
                    _escape(record["cancellationControl"]),
                    _escape(record["resourceRelease"]),
                    _escape(record["blockingApi"]),
                    _escape(record["bridgeContract"]),
                    "<br>".join(
                        f"`{source_path}` (`{record['evidenceSha256'][source_path]}`)"
                        for source_path in record["evidenceSources"]
                    ),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Target application and release evidence",
            "",
            "Each feature/target row is explicit. `not run` is never inferred from another",
            "feature, backend, simulator, host codec, or validator result.",
            "",
            "| Feature | Target | Application kind | Applied | Visual evidence | Runtime availability | Maturity | Target evidence | Exact blocker |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for feature in features:
        feature_targets = _object(feature["targets"], "targets")
        for target in targets:
            row = _object(feature_targets[target], "target row")
            lines.append(
                "| "
                + " | ".join(
                    [
                        f"`{feature['id']}`",
                        TARGET_LABELS[target],
                        _escape(row["applicationKind"]),
                        _escape(row["applied"]),
                        _escape(row["visuallyVerified"]),
                        _escape(row["runtimeCapability"]),
                        _escape(row["releaseMaturity"]),
                        _escape(row["targetEvidence"]),
                        _escape(row["blocker"]),
                    ]
                )
                + " |"
            )
    lines.extend(
        [
            "",
            "## Evidence interpretation",
            "",
            "- `verified locally` in the host table proves only the named host boundary.",
            "- `candidate-only` is release maturity or availability, not target evidence.",
            "- `diagnostic-only` and `unsupported` never authorize renderer application.",
            "- A target becomes production-ready only when that exact feature/target row",
            "  has production-ready runtime capability and maturity plus verified applied,",
            "  visual, and target evidence.",
            "",
        ]
    )
    return "\n".join(lines)


def _parse_selection(value: str | None) -> list[str] | None:
    if value is None:
        return None
    result = [item.strip() for item in value.split(",") if item.strip()]
    if len(result) != len(set(result)):
        raise MatrixError("selection entries must be unique")
    return result


def _host_cell(record: dict[str, object]) -> str:
    return _escape(f"{record['status']} — {record['scope']}; {record['evidence']}")


def _escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def _yes_no(value: object) -> str:
    return "yes" if value is True else "no"


def _object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise MatrixError(f"{label} must be an object")
    return value


def _string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise MatrixError(f"{label} must be a non-empty string")
    return value


def _string_list(value: object, label: str) -> list[str]:
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        raise MatrixError(f"{label} must be a non-empty string array")
    return list(value)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--check", action="store_true")
    actions.add_argument("--write", action="store_true")
    actions.add_argument("--summary-json", action="store_true")
    parser.add_argument("--features")
    parser.add_argument("--targets")
    args = parser.parse_args(argv)

    source = load_source()
    features, targets = select(
        source,
        _parse_selection(args.features),
        _parse_selection(args.targets),
    )
    if args.summary_json:
        print(json.dumps(aggregate_summary(features, targets), separators=(",", ":")))
        return 0
    if args.features is not None or args.targets is not None:
        raise MatrixError("--features/--targets are valid only with --summary-json")

    rendered = render_markdown(source)
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
        print(f"wrote {OUTPUT_PATH.relative_to(REPO_ROOT)}")
        return 0
    actual = OUTPUT_PATH.read_text(encoding="utf-8")
    if actual != rendered:
        raise MatrixError(
            "docs/generated/capability_matrix.md is stale; run with --write"
        )
    print("capability matrix is current")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (MatrixError, OSError, json.JSONDecodeError) as error:
        print(f"capability matrix generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
