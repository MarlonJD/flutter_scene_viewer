#!/usr/bin/env python3
"""Generate the Plan 014 selected-extension capability matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = (
    REPO_ROOT
    / "tools/capability_matrix/plan014_selected_extension_capabilities.json"
)
OUTPUT_PATH = REPO_ROOT / "docs/generated/capability_matrix.md"
TARGET_LABELS = {
    "ios_simulator": "iOS Simulator",
    "ios_physical": "physical iOS",
    "android": "Android",
    "web": "Web",
}
HOST_STAGE_KEYS = ("parsed", "preserved", "decoded")
TARGET_ROW_KEYS = (
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
    "release-pending",
    "production-ready",
}
EVIDENCE_VALUES = {"not run", "verified locally"}
APPLIED_VALUES = {"blocked", "not run", "unsupported", "verified locally"}
RUNTIME_CAPABILITY_VALUES = {
    "diagnostic-only",
    "candidate-only availability",
    "candidate-only native plugin",
    "candidate-only pure-Dart rewrite",
    "unsupported",
    "production-ready",
}
CURRENT_PLAN014_IOS_SIMULATOR_EVIDENCE = (
    "tools/out/material_extension_acceptance/"
    "plan014_extended_pbr_ios_simulator/evidence.json"
)
CURRENT_PLAN014_VERIFIED_TARGET_ROWS = {
    ("KHR_texture_transform", "ios_simulator"): {
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator transform evidence recorded at "
            f"{CURRENT_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_materials_specular", "ios_simulator"): {
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator specular evidence recorded at "
            f"{CURRENT_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_materials_ior", "ios_simulator"): {
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only availability",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only iPhone 17 Simulator opaque-IOR evidence recorded at "
            f"{CURRENT_PLAN014_IOS_SIMULATOR_EVIDENCE}; physical and release "
            "evidence remain not run"
        ),
    },
    ("KHR_draco_mesh_compression", "ios_simulator"): {
        "applied": "verified locally",
        "visuallyVerified": "verified locally",
        "runtimeCapability": "candidate-only native plugin",
        "releaseMaturity": "candidate-only",
        "targetEvidence": "verified locally",
        "blocker": (
            "candidate-only A1B32 Draco decode/render evidence recorded at "
            f"{CURRENT_PLAN014_IOS_SIMULATOR_EVIDENCE}; native in-flight "
            "cancellation, allocation control, and release packaging remain "
            "unverified"
        ),
    },
}
CURRENT_PLAN014_UNVERIFIED_TARGET_BLOCKERS = {
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
CURRENT_PLAN014_NATIVE_ONLY_WEB_ROWS = {
    "KHR_draco_mesh_compression": "the optional Draco decoder is native-only; no Web decoder is provided",
    "KHR_texture_basisu": "the optional BasisU transcoder is native-only; no Web transcoder is provided",
}
CURRENT_PLAN014_HISTORICAL_CONTEXT = [
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
CURRENT_PLAN014_NATIVE_CODEC_TARGETS = {
    "KHR_draco_mesh_compression",
    "KHR_texture_basisu",
}
CURRENT_PLAN014_DECODER_CONTROL_BOUNDARIES = [
    {
        "feature": "EXT_meshopt_compression",
        "implementation": "synchronous pure-Dart EXT-v0 decode and GLB rewrite",
        "allocationControl": "declared-output and aggregate rewrite budgets use atomic commit outside the decoder loop",
        "timeoutControl": "cooperative Dart deadline checkpoints are enforced across claimed modes and filters",
        "cancellationControl": "not enforced",
        "resourceRelease": "timed-out decode buffers become garbage-collectible after stack unwind; deterministic collection is not guaranteed",
        "blockingApi": "synchronous decode accepts an internal deadline control but no external cancellation signal",
        "bridgeContract": "not applicable; Meshopt has no native MethodChannel bridge",
        "evidenceSources": [
            "lib/src/internal/meshopt_decoder.dart",
            "lib/src/internal/glb_meshopt_rewriter.dart",
            "lib/src/internal/glb_decode_budget.dart",
        ],
        "evidenceSha256": {
            "lib/src/internal/meshopt_decoder.dart": "86e0ff6038636ca0cbd17cebfa36a65b6ac4c8691f30c6733037650aca4a4f72",
            "lib/src/internal/glb_meshopt_rewriter.dart": "5c87b90b33103f37dac736fe145b78908b88c42c4a958357aa467f8dab056f1c",
            "lib/src/internal/glb_decode_budget.dart": "a14c1a1aaf6aa33884812e63440c14469fb40cc23b2411d1d904b5afbee0f2f3",
        },
    },
    {
        "feature": "KHR_draco_mesh_compression",
        "implementation": "synchronous pinned Google Draco 1.5.7 native decode",
        "allocationControl": "bridge preflight and output budgets do not bound allocations inside Decoder::DecodeMeshFromBuffer",
        "timeoutControl": "Dart deadline enforced; native work is not stopped",
        "cancellationControl": "not enforced",
        "resourceRelease": "bridge-owned RAII scopes unwind after synchronous decode returns; deadline or cancellation release is not established",
        "blockingApi": "draco::Decoder::DecodeMeshFromBuffer(DecoderBuffer*) exposes no deadline, cancellation callback, or allocator budget",
        "bridgeContract": "decodeGlb is one MethodChannel request and response; Dart discards a late response, but no deadline or cancellation signal enters native code",
        "evidenceSources": [
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/flutter_scene_viewer_draco_jni.cc",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/FlutterSceneViewerDracoPlugin.mm",
            "lib/src/internal/glb_native_decoder_probe.dart",
        ],
        "evidenceSha256": {
            "packages/flutter_scene_viewer_draco/third_party/draco/src/draco/compression/decode.h": "ea23e1dfabf34d11260f51f4f4e160f89480b2ac53d919e354a12266a05c00c1",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/fsv_draco_bridge.cc": "fc962ca317150853ef19829d9c8b602d6972f8069508c336f123705885b9a6a6",
            "packages/flutter_scene_viewer_draco/android/src/main/cpp/flutter_scene_viewer_draco_jni.cc": "5a74f2990ab35fbe465b026985a8db552e6262540c4435bce3b45bfb82c1c606",
            "packages/flutter_scene_viewer_draco/android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java": "776159773789c82024c8e93a77c45169e5216d0b6a72808a17b94efba53d47cc",
            "packages/flutter_scene_viewer_draco/ios/Classes/fsv_draco_bridge.cc": "fc962ca317150853ef19829d9c8b602d6972f8069508c336f123705885b9a6a6",
            "packages/flutter_scene_viewer_draco/ios/Classes/FlutterSceneViewerDracoPlugin.mm": "3b202a7bb9839f24e29c2793d2690d97f5eee9d9fa9aff3d962b9a08dce88cb5",
            "lib/src/internal/glb_native_decoder_probe.dart": "d785e2ad34d7eff2bfdd0590b6b567794e5afd38ec351ab5d634e06afbd9e301",
        },
    },
    {
        "feature": "KHR_texture_basisu",
        "implementation": "synchronous pinned Basis Universal KTX2 native transcode",
        "allocationControl": "bridge preflight and output budgets do not bound allocations inside init, start_transcoding, or transcode_image_level",
        "timeoutControl": "Dart deadline enforced; native work is not stopped",
        "cancellationControl": "not enforced",
        "resourceRelease": "bridge-owned RAII scopes unwind after synchronous transcode returns; deadline or cancellation release is not established",
        "blockingApi": "ktx2_transcoder init, start_transcoding, and transcode_image_level expose no deadline, cancellation callback, or allocator budget",
        "bridgeContract": "decodeGlb is one MethodChannel request and response; Dart discards a late response, but no deadline or cancellation signal enters native code",
        "evidenceSources": [
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FlutterSceneViewerBasisuPlugin.java",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.cc",
            "packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm",
            "lib/src/internal/glb_native_decoder_probe.dart",
        ],
        "evidenceSha256": {
            "packages/flutter_scene_viewer_basisu/third_party/basis_universal/transcoder/basisu_transcoder.h": "7e8d9949364cb72dc8532004357f1585e5e9abea3bc76ae9964abe9fd2e4af09",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_bridge.cc": "f61da352239f699fb44f02e93127102d37881f2d90d75a74c79aca35182b8703",
            "packages/flutter_scene_viewer_basisu/android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc": "8cde1d37d7104f4d3ed7447f14d30612f13e593efa49dc7eb4dc498561731780",
            "packages/flutter_scene_viewer_basisu/android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FlutterSceneViewerBasisuPlugin.java": "1187dd42cb8df81d4ad3a792fd8cec45ab750754d8c06fc476fc88c5d7ae3cae",
            "packages/flutter_scene_viewer_basisu/ios/Classes/fsv_basisu_bridge.cc": "f61da352239f699fb44f02e93127102d37881f2d90d75a74c79aca35182b8703",
            "packages/flutter_scene_viewer_basisu/ios/Classes/FlutterSceneViewerBasisuPlugin.mm": "f8a0a714e4ea13649da50ddb74a460b6bb4481390195d99beec0ac821587fbb1",
            "lib/src/internal/glb_native_decoder_probe.dart": "d785e2ad34d7eff2bfdd0590b6b567794e5afd38ec351ab5d634e06afbd9e301",
        },
    },
]
DECODER_CONTROL_SOURCE_MARKERS = {
    "lib/src/internal/meshopt_decoder.dart": (
        "final class MeshoptDecodeControl {",
        "Uint8List decodeMeshoptGltfBuffer(",
        "required MeshoptCompressionFilter filter,",
        "MeshoptDecodeControl? control,",
        "control?.checkpoint(stage: 'meshoptDecodeStart', force: true);",
    ),
    "lib/src/internal/glb_meshopt_rewriter.dart": (
        "MeshoptDecodeControl.running(",
        "timeout: tracker.budget.decodeTimeout,",
        "final rewriteTracker = GlbDecodeBudgetTracker(tracker.budget);",
        "on MeshoptDecodeDeadlineExceeded catch (error)",
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
        ".timeout(remaining)",
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
    for record in CURRENT_PLAN014_DECODER_CONTROL_BOUNDARIES
    for source_path, sha256 in record["evidenceSha256"].items()
}


class MatrixError(RuntimeError):
    pass


def load_source() -> dict[str, object]:
    value = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise MatrixError("capability source must be a JSON object")
    validate_source(value)
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


def validate_source(source: dict[str, object]) -> None:
    if source.get("schemaVersion") != 1:
        raise MatrixError("schemaVersion must equal 1")
    feature_set = _string_list(source.get("featureSet"), "featureSet")
    target_set = _string_list(source.get("targetSet"), "targetSet")
    if len(feature_set) != len(set(feature_set)):
        raise MatrixError("featureSet must be unique")
    if len(target_set) != len(set(target_set)):
        raise MatrixError("targetSet must be unique")
    if any(target not in TARGET_LABELS for target in target_set):
        raise MatrixError("targetSet contains an unknown target")
    if source.get("historicalContext") != CURRENT_PLAN014_HISTORICAL_CONTEXT:
        raise MatrixError("historical candidate context changed")
    for record in CURRENT_PLAN014_HISTORICAL_CONTEXT:
        if record["feature"] not in feature_set or record["target"] not in target_set:
            raise MatrixError("historical candidate context is outside matrix scope")
        if not (REPO_ROOT / record["source"]).is_file():
            raise MatrixError("historical candidate evidence source is missing")
    if (
        source.get("decoderControlBoundaries")
        != CURRENT_PLAN014_DECODER_CONTROL_BOUNDARIES
    ):
        raise MatrixError("decoder control boundary evidence changed")
    for record in CURRENT_PLAN014_DECODER_CONTROL_BOUNDARIES:
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
            if row["applied"] not in APPLIED_VALUES:
                raise MatrixError(f"{feature_id}.{target} applied status is invalid")
            if row["runtimeCapability"] not in RUNTIME_CAPABILITY_VALUES:
                raise MatrixError(
                    f"{feature_id}.{target} runtime capability is invalid"
                )
            if row["releaseMaturity"] not in MATURITY_VALUES:
                raise MatrixError(f"{feature_id}.{target} maturity is invalid")
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
            expected_verified_row = CURRENT_PLAN014_VERIFIED_TARGET_ROWS.get(
                (feature_id, target)
            )
            if expected_verified_row is not None:
                if row != expected_verified_row:
                    raise MatrixError(
                        f"{feature_id}.{target} verified target evidence row changed"
                    )
            else:
                if row["targetEvidence"] != "not run":
                    raise MatrixError(
                        f"{feature_id}.{target} current Plan 014 target evidence "
                        "must remain not run until a target artifact is recorded"
                    )
                if row["visuallyVerified"] != "not run":
                    raise MatrixError(
                        f"{feature_id}.{target} current Plan 014 visual evidence "
                        "must remain not run until a target artifact is recorded"
                    )
                if row["applied"] == "verified locally":
                    raise MatrixError(
                        f"{feature_id}.{target} host evidence cannot establish "
                        "current Plan 014 target application"
                    )
            expected_blocker = CURRENT_PLAN014_UNVERIFIED_TARGET_BLOCKERS.get(
                (feature_id, target)
            )
            if expected_blocker is not None and row["blocker"] != expected_blocker:
                raise MatrixError(
                    f"{feature_id}.{target} exact upstream blocker changed"
                )
            native_only_blocker = CURRENT_PLAN014_NATIVE_ONLY_WEB_ROWS.get(feature_id)
            if target == "web" and native_only_blocker is not None and row != {
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
                feature_id in CURRENT_PLAN014_NATIVE_CODEC_TARGETS
                and target != "web"
                and expected_verified_row is None
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
        "`tools/capability_matrix/plan014_selected_extension_capabilities.json`.",
        "Do not edit this file by hand.",
        "",
        f"Scope: {source['scope']}",
        "",
        "Host decode/validator evidence is not target render evidence.",
        "Historical candidate runs are not promoted into current Plan 014 target rows.",
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
        "This retained historical evidence does not alter any current Plan 014 target row.",
        "The original artifacts were temporary and are not durable release evidence.",
        "",
        "| Feature | Target | Historical evidence | Date | Scope | Source | Artifact durability | Current Plan 014 target evidence | Release maturity |",
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
            "| Feature | Target | Applied | Visually verified | Runtime capability | Release maturity | Target evidence | Exact blocker |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
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
