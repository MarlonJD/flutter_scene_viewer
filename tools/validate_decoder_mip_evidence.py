#!/usr/bin/env python3
"""Validate tracked Plan 017 decoder and authored-mip evidence metadata."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST_PATH = (
    REPO_ROOT / "tools/decoder_mip_acceptance/manifest.json"
)
DEFAULT_RECORDS_DIR = REPO_ROOT / "tools/decoder_mip_acceptance/records"
PINNED_RENDERER_COMMIT = "5dcf6fce7dc36719e64e536faba9538fe9fa1022"
ARTIFACT_ROOT = "tools/out/plan017_decoder_mip_acceptance"
RECORD_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
RFC3339_DATE_TIME_PATTERN = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"
    r"[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?"
    r"(?:Z|[+-][0-9]{2}:[0-9]{2})$"
)
ARTIFACT_PATH_PATTERN = re.compile(
    r"^tools/out/plan017_decoder_mip_acceptance/"
    r"[A-Za-z0-9][A-Za-z0-9._-]*"
    r"(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*$"
)
FEATURES = {
    "EXT_meshopt_compression",
    "KHR_draco_mesh_compression",
    "KHR_texture_basisu",
}
CLAIM_TARGETS = {"ios_simulator", "ios_physical", "android", "web"}
TARGET_KINDS = {
    "host",
    "ios_simulator",
    "ios_physical",
    "android_build",
    "android_physical",
    "web_runtime",
}
TARGET_KIND_FOR_CLAIM = {
    "ios_simulator": "ios_simulator",
    "ios_physical": "ios_physical",
    "android": "android_physical",
    "web": "web_runtime",
}
EVIDENCE_STATUSES = {"verified locally", "not run", "blocked"}
MATURITIES = {"candidate-only", "release pending", "production-ready"}
GATES = {
    "host-validation",
    "discovery",
    "package-install",
    "release-build",
    "runtime",
    "runtime-diagnostic",
    "cancellation-resource",
    "authored-mip-sampling",
}
BUILD_ONLY_GATES = {"package-install", "release-build"}
CANONICAL_REQUIRED_GATES = {
    (feature, target): frozenset(
        {"package-install", "runtime", "cancellation-resource"}
        | ({"release-build"} if target in {"ios_physical", "android", "web"} else set())
        | ({"authored-mip-sampling"} if feature == "KHR_texture_basisu" else set())
    )
    for feature in FEATURES
    for target in CLAIM_TARGETS
}
for _native_web_feature in (
    "KHR_draco_mesh_compression",
    "KHR_texture_basisu",
):
    CANONICAL_REQUIRED_GATES[(_native_web_feature, "web")] = frozenset(
        {"package-install", "release-build", "runtime-diagnostic"}
    )
CONTENT_ROLES = {"color", "data", "normal"}
STORAGE_ROLES = {"color", "nonColor"}
MATERIAL_SLOTS = {
    "baseColor",
    "metallicRoughness",
    "normal",
    "occlusion",
    "emissive",
    "transmission",
    "thickness",
    "clearcoat",
    "clearcoatRoughness",
    "clearcoatNormal",
    "specular",
    "specularColor",
}
PACKAGE_NAMES = {
    "flutter_scene_viewer",
    "flutter_scene_viewer_draco",
    "flutter_scene_viewer_basisu",
}
SLOT_CONTENT_ROLE = {
    "baseColor": "color",
    "metallicRoughness": "data",
    "normal": "normal",
    "occlusion": "data",
    "emissive": "color",
    "transmission": "data",
    "thickness": "data",
    "clearcoat": "data",
    "clearcoatRoughness": "data",
    "clearcoatNormal": "normal",
    "specular": "data",
    "specularColor": "color",
}
MAG_FILTERS = {9728, 9729}
MIN_FILTERS = {9728, 9729, 9984, 9985, 9986, 9987}
WRAP_MODES = {33071, 33648, 10497}
ARTIFACT_KINDS = {
    "runtime-render",
    "runtime-readback",
    "runtime-diagnostic",
    "validator-report",
    "package-layout",
    "package-symbols",
    "package-licenses",
    "package-release",
    "mip-lod-readback",
    "mip-base-only-control",
    "log",
}


class EvidenceError(RuntimeError):
    pass


def load_manifest(
    manifest_path: Path = DEFAULT_MANIFEST_PATH,
    records_dir: Path = DEFAULT_RECORDS_DIR,
    *,
    verify_local_artifacts: bool = False,
) -> dict[str, object]:
    manifest = _json_object(manifest_path)
    validate_manifest(
        manifest,
        records_dir=records_dir,
        verify_local_artifacts=verify_local_artifacts,
    )
    return manifest


def validate_manifest(
    manifest: dict[str, object],
    *,
    records_dir: Path = DEFAULT_RECORDS_DIR,
    verify_local_artifacts: bool = False,
) -> None:
    _exact_keys(
        manifest,
        {
            "schemaVersion",
            "artifactRoot",
            "rendererCommit",
            "packageVersions",
            "discovery",
            "claims",
            "records",
            "aggregateMaturity",
            "productionReady",
        },
        "manifest",
    )
    if manifest.get("schemaVersion") != 1:
        raise EvidenceError("manifest schemaVersion must equal 1")
    if manifest.get("artifactRoot") != ARTIFACT_ROOT:
        raise EvidenceError(f"artifactRoot must equal {ARTIFACT_ROOT}")
    if manifest.get("rendererCommit") != PINNED_RENDERER_COMMIT:
        raise EvidenceError("rendererCommit must equal the immutable viewer pin")

    package_versions = _object(manifest.get("packageVersions"), "packageVersions")
    if set(package_versions) != PACKAGE_NAMES:
        raise EvidenceError("packageVersions must name the root and both plugins")
    for package, version in package_versions.items():
        _nonempty_string(version, f"packageVersions.{package}")

    discoveries = _list(manifest.get("discovery"), "discovery")
    discovery_targets: set[str] = set()
    for index, raw_discovery in enumerate(discoveries):
        discovery = _object(raw_discovery, f"discovery[{index}]")
        _exact_keys(
            discovery,
            {"target", "status", "device", "deviceId", "os", "scope"},
            f"discovery[{index}]",
        )
        target = _nonempty_string(discovery.get("target"), "discovery.target")
        if target not in TARGET_KINDS:
            raise EvidenceError(f"unknown discovery target {target}")
        if target in discovery_targets:
            raise EvidenceError(f"duplicate discovery target {target}")
        discovery_targets.add(target)
        status = _nonempty_string(discovery.get("status"), "discovery.status")
        if status not in EVIDENCE_STATUSES:
            raise EvidenceError(f"invalid discovery status {status}")
        for key in ("device", "deviceId", "os", "scope"):
            _nonempty_string(discovery.get(key), f"discovery.{key}")

    raw_record_paths = _list(manifest.get("records"), "records")
    record_paths: list[str] = []
    records_by_id: dict[str, dict[str, object]] = {}
    for index, raw_path in enumerate(raw_record_paths):
        relative_path = _nonempty_string(raw_path, f"records[{index}]")
        if not relative_path.startswith("records/") or not relative_path.endswith(
            ".json"
        ):
            raise EvidenceError("record paths must match records/*.json")
        if relative_path in record_paths:
            raise EvidenceError(f"duplicate record path {relative_path}")
        record_paths.append(relative_path)
        record_path = records_dir / Path(relative_path).name
        record = _json_object(record_path)
        validate_record(
            record,
            verify_local_artifacts=verify_local_artifacts,
        )
        record_id = _nonempty_string(record.get("id"), "record.id")
        if record_id in records_by_id:
            raise EvidenceError(f"duplicate record id {record_id}")
        records_by_id[record_id] = record

    claims = _list(manifest.get("claims"), "claims")
    claim_keys: set[tuple[str, str]] = set()
    for index, raw_claim in enumerate(claims):
        claim = _object(raw_claim, f"claims[{index}]")
        _exact_keys(
            claim,
            {
                "feature",
                "target",
                "requiredGates",
                "evidenceStatus",
                "maturity",
                "recordIds",
                "blocker",
            },
            f"claims[{index}]",
        )
        feature = _nonempty_string(claim.get("feature"), "claim.feature")
        target = _nonempty_string(claim.get("target"), "claim.target")
        if feature not in FEATURES:
            raise EvidenceError(f"unknown claim feature {feature}")
        if target not in CLAIM_TARGETS:
            raise EvidenceError(f"unknown claim target {target}")
        key = (feature, target)
        if key in claim_keys:
            raise EvidenceError(f"duplicate claim {feature}/{target}")
        claim_keys.add(key)
        required_gates = _string_set(
            claim.get("requiredGates"), "claim.requiredGates"
        )
        canonical_gates = CANONICAL_REQUIRED_GATES[key]
        if required_gates != canonical_gates:
            raise EvidenceError(
                f"{feature}/{target} canonical required gates changed"
            )
        evidence_status = _nonempty_string(
            claim.get("evidenceStatus"), "claim.evidenceStatus"
        )
        maturity = _nonempty_string(claim.get("maturity"), "claim.maturity")
        if evidence_status not in EVIDENCE_STATUSES:
            raise EvidenceError(f"invalid evidence status for {feature}/{target}")
        if maturity not in MATURITIES:
            raise EvidenceError(f"invalid maturity for {feature}/{target}")
        blocker = _nonempty_string(claim.get("blocker"), "claim.blocker")
        record_ids = _string_list(claim.get("recordIds"), "claim.recordIds")
        if len(record_ids) != len(set(record_ids)):
            raise EvidenceError(f"duplicate record id in {feature}/{target}")
        if evidence_status in {"not run", "blocked"}:
            if record_ids:
                raise EvidenceError(
                    f"{feature}/{target} {evidence_status} claim cannot cite records"
                )
            if maturity == "production-ready":
                raise EvidenceError(
                    f"{feature}/{target} is not run or blocked, not production-ready"
                )
            if blocker == "none":
                raise EvidenceError(f"{feature}/{target} must retain an exact blocker")
        else:
            covered_gates = _validate_claim_records(
                feature,
                target,
                record_ids,
                records_by_id,
                production_ready=maturity == "production-ready",
            )
            if not required_gates <= covered_gates:
                missing = sorted(required_gates - covered_gates)
                raise EvidenceError(
                    f"{feature}/{target} lacks required durable evidence gates: "
                    + ", ".join(missing)
                )
            if blocker == "none" and maturity != "production-ready":
                raise EvidenceError(
                    f"{feature}/{target} non-production claim must state its blocker"
                )

    expected_claims = {(feature, target) for feature in FEATURES for target in CLAIM_TARGETS}
    if claim_keys != expected_claims:
        raise EvidenceError("claims must cover every Plan 017 decoder feature/target")
    cited_record_ids = {
        record_id
        for raw_claim in claims
        for record_id in _string_list(_object(raw_claim, "claim").get("recordIds"), "recordIds")
    }
    if set(records_by_id) != cited_record_ids:
        raise EvidenceError("every tracked record must be cited by exactly scoped claims")

    production_ready = manifest.get("productionReady")
    if not isinstance(production_ready, bool):
        raise EvidenceError("productionReady must be a boolean")
    all_claims_ready = all(
        _object(raw_claim, "claim").get("evidenceStatus") == "verified locally"
        and _object(raw_claim, "claim").get("maturity") == "production-ready"
        for raw_claim in claims
    )
    if production_ready != all_claims_ready:
        raise EvidenceError("productionReady does not match the complete claim gate set")
    aggregate = _nonempty_string(
        manifest.get("aggregateMaturity"), "aggregateMaturity"
    )
    if aggregate not in MATURITIES:
        raise EvidenceError("aggregateMaturity is invalid")
    expected_aggregate = "production-ready" if production_ready else "release pending"
    if aggregate != expected_aggregate:
        raise EvidenceError(
            f"aggregateMaturity must remain {expected_aggregate} for this gate set"
        )


def validate_record(
    record: dict[str, object],
    *,
    verify_local_artifacts: bool = False,
) -> None:
    _exact_keys(
        record,
        {
            "schemaVersion",
            "id",
            "capturedAt",
            "evidenceStatus",
            "maturity",
            "features",
            "gates",
            "source",
            "codecs",
            "fixtures",
            "target",
            "limits",
            "runtime",
            "runtimeDiagnostic",
            "cancellation",
            "allocations",
            "mipChains",
            "mipSampling",
            "validator",
            "package",
            "artifacts",
            "blockers",
        },
        "record",
    )
    if record.get("schemaVersion") != 1:
        raise EvidenceError("record schemaVersion must equal 1")
    record_id = _record_id(record.get("id"), "record.id")
    _rfc3339_date_time(record.get("capturedAt"), f"{record_id}.capturedAt")
    if record.get("evidenceStatus") != "verified locally":
        raise EvidenceError(f"{record_id} records must be verified locally")
    maturity = _nonempty_string(record.get("maturity"), f"{record_id}.maturity")
    if maturity not in MATURITIES:
        raise EvidenceError(f"{record_id} maturity is invalid")
    features = _string_set(record.get("features"), f"{record_id}.features")
    if not features or not features <= FEATURES:
        raise EvidenceError(f"{record_id} features are invalid")
    gates = _string_set(record.get("gates"), f"{record_id}.gates")
    if not gates or not gates <= GATES:
        raise EvidenceError(f"{record_id} gates are invalid")

    source = _object(record.get("source"), f"{record_id}.source")
    _exact_keys(
        source,
        {"viewerBaseCommit", "viewerDiffSha256", "rendererCommit", "packageVersions"},
        f"{record_id}.source",
    )
    _sha(source.get("viewerBaseCommit"), f"{record_id}.viewerBaseCommit", length=40)
    _sha(source.get("viewerDiffSha256"), f"{record_id}.viewerDiffSha256")
    if source.get("rendererCommit") != PINNED_RENDERER_COMMIT:
        raise EvidenceError(f"{record_id} renderer commit does not match the pin")
    package_versions = _object(
        source.get("packageVersions"), f"{record_id}.packageVersions"
    )
    if set(package_versions) != PACKAGE_NAMES:
        raise EvidenceError(f"{record_id} package versions are incomplete")
    for package_name, version in package_versions.items():
        _nonempty_string(version, f"{record_id}.packageVersions.{package_name}")

    codecs = _list(record.get("codecs"), "codecs")
    codec_ids: set[str] = set()
    for index, raw_codec in enumerate(codecs):
        codec = _object(raw_codec, f"{record_id}.codecs[{index}]")
        _exact_keys(
            codec,
            {
                "id",
                "upstreamBase",
                "localPatchManifestPath",
                "localPatchManifestSha256",
                "compiledSourceManifestPath",
                "compiledSourceManifestSha256",
            },
            f"{record_id}.codecs[{index}]",
        )
        codec_id = _nonempty_string(codec.get("id"), "codec.id")
        if codec_id in codec_ids:
            raise EvidenceError(f"{record_id} codec ids must be unique")
        codec_ids.add(codec_id)
        _sha(codec.get("upstreamBase"), "codec.upstreamBase", length=40)
        for path_key, hash_key in (
            ("localPatchManifestPath", "localPatchManifestSha256"),
            ("compiledSourceManifestPath", "compiledSourceManifestSha256"),
        ):
            _repo_relative_path(codec.get(path_key), f"codec.{path_key}")
            _sha(codec.get(hash_key), f"codec.{hash_key}")

    fixtures = _list(record.get("fixtures"), f"{record_id}.fixtures")
    fixture_ids: set[str] = set()
    fixture_bytes = 0
    for index, raw_fixture in enumerate(fixtures):
        fixture = _object(raw_fixture, f"{record_id}.fixtures[{index}]")
        _exact_keys(
            fixture,
            {"id", "source", "sha256", "byteLength"},
            f"{record_id}.fixtures[{index}]",
        )
        fixture_id = _nonempty_string(fixture.get("id"), "fixture.id")
        if fixture_id in fixture_ids:
            raise EvidenceError(f"{record_id} fixture ids must be unique")
        fixture_ids.add(fixture_id)
        _nonempty_string(fixture.get("source"), "fixture.source")
        _sha(fixture.get("sha256"), "fixture.sha256")
        fixture_bytes += _positive_int(fixture.get("byteLength"), "fixture.byteLength")

    target = _object(record.get("target"), f"{record_id}.target")
    _exact_keys(
        target,
        {"kind", "deviceId", "device", "os", "architecture", "buildMode", "backend"},
        f"{record_id}.target",
    )
    target_kind = _nonempty_string(target.get("kind"), "target.kind")
    if target_kind not in TARGET_KINDS:
        raise EvidenceError(f"{record_id} target kind is invalid")
    for key in ("deviceId", "device", "os", "architecture", "buildMode", "backend"):
        target_value = _nonempty_string(target.get(key), f"target.{key}")
        if target_value in {"not run", "blocked"}:
            raise EvidenceError(f"{record_id} verified target contains {target_value}")

    limits = _object(record.get("limits"), f"{record_id}.limits")
    _exact_keys(
        limits,
        {
            "maxSourceBytes",
            "maxWorkingBytes",
            "maxNativeOutputBytes",
            "maxTextureDimension",
            "maxMipLevels",
        },
        f"{record_id}.limits",
    )
    for key in (
        "maxSourceBytes",
        "maxWorkingBytes",
        "maxNativeOutputBytes",
        "maxTextureDimension",
        "maxMipLevels",
    ):
        _positive_int(limits.get(key), f"limits.{key}")
    if fixture_bytes > limits["maxSourceBytes"]:
        raise EvidenceError(f"{record_id} fixtures exceed maxSourceBytes")

    runtime = _nullable_object(record.get("runtime"), f"{record_id}.runtime")
    if runtime is not None:
        _exact_keys(
            runtime,
            {
                "loadSucceeded",
                "renderSucceeded",
                "readbackSucceeded",
                "renderArtifactId",
                "readbackArtifactId",
            },
            f"{record_id}.runtime",
        )
        for key in ("loadSucceeded", "renderSucceeded", "readbackSucceeded"):
            _boolean(runtime.get(key), f"runtime.{key}")
        for key in ("renderArtifactId", "readbackArtifactId"):
            _nonempty_string(runtime.get(key), f"runtime.{key}")

    runtime_diagnostic = _nullable_object(
        record.get("runtimeDiagnostic"), f"{record_id}.runtimeDiagnostic"
    )
    if runtime_diagnostic is not None:
        _exact_keys(
            runtime_diagnostic,
            {"emitted", "code", "count", "nativePluginInvocationCount", "artifactId"},
            f"{record_id}.runtimeDiagnostic",
        )
        _boolean(runtime_diagnostic.get("emitted"), "runtimeDiagnostic.emitted")
        _nonempty_string(runtime_diagnostic.get("code"), "runtimeDiagnostic.code")
        _nonnegative_int(runtime_diagnostic.get("count"), "runtimeDiagnostic.count")
        _nonnegative_int(
            runtime_diagnostic.get("nativePluginInvocationCount"),
            "runtimeDiagnostic.nativePluginInvocationCount",
        )
        _nonempty_string(runtime_diagnostic.get("artifactId"), "runtimeDiagnostic.artifactId")

    cancellation = _object(record.get("cancellation"), f"{record_id}.cancellation")
    _exact_keys(
        cancellation,
        {
            "trigger",
            "latencyMicros",
            "maxUiGapMicros",
            "workerExited",
            "terminalDiagnosticCount",
            "latePublicationCount",
            "registryEntriesAfter",
            "subsequentLoadSucceeded",
            "artifactId",
        },
        f"{record_id}.cancellation",
    )
    _nonempty_string(cancellation.get("trigger"), "cancellation.trigger")
    for key in (
        "latencyMicros",
        "maxUiGapMicros",
        "terminalDiagnosticCount",
        "latePublicationCount",
        "registryEntriesAfter",
    ):
        _nonnegative_int(cancellation.get(key), f"cancellation.{key}")
    for key in ("workerExited", "subsequentLoadSucceeded"):
        _boolean(cancellation.get(key), f"cancellation.{key}")
    cancellation_artifact_id = _optional_string(
        cancellation.get("artifactId"), "cancellation.artifactId"
    )

    allocations = _object(record.get("allocations"), f"{record_id}.allocations")
    _exact_keys(
        allocations,
        {"limitBytes", "peakLiveBytes", "liveBytesAfter", "allocationCount", "releaseCount"},
        f"{record_id}.allocations",
    )
    for key in (
        "limitBytes",
        "peakLiveBytes",
        "liveBytesAfter",
        "allocationCount",
        "releaseCount",
    ):
        _nonnegative_int(allocations.get(key), f"allocations.{key}")

    artifacts = _list(record.get("artifacts"), f"{record_id}.artifacts")
    if not artifacts:
        raise EvidenceError(f"{record_id} must cite at least one artifact")
    artifacts_by_id: dict[str, dict[str, object]] = {}
    artifact_paths: set[str] = set()
    for index, raw_artifact in enumerate(artifacts):
        artifact = _object(raw_artifact, f"{record_id}.artifacts[{index}]")
        _exact_keys(
            artifact,
            {"id", "path", "sha256", "byteLength", "kind"},
            f"{record_id}.artifacts[{index}]",
        )
        artifact_id = _nonempty_string(artifact.get("id"), "artifact.id")
        if artifact_id in artifacts_by_id:
            raise EvidenceError(f"{record_id} artifact ids must be unique")
        artifact_path = _artifact_path(artifact.get("path"), "artifact.path")
        if artifact_path in artifact_paths:
            raise EvidenceError(f"{record_id} artifact paths must be unique")
        artifact_paths.add(artifact_path)
        _sha(artifact.get("sha256"), "artifact.sha256")
        _positive_int(artifact.get("byteLength"), "artifact.byteLength")
        kind = _nonempty_string(artifact.get("kind"), "artifact.kind")
        if kind not in ARTIFACT_KINDS:
            raise EvidenceError(f"{record_id} artifact kind is invalid")
        artifacts_by_id[artifact_id] = artifact

    mip_chains = _list(record.get("mipChains"), f"{record_id}.mipChains")
    chains_by_key: dict[tuple[int, str], dict[str, object]] = {}
    total_mip_bytes = 0
    for chain_index, raw_chain in enumerate(mip_chains):
        chain = _object(raw_chain, f"{record_id}.mipChains[{chain_index}]")
        _exact_keys(
            chain,
            {"imageIndex", "fixtureId", "storageRole", "materialConsumers", "levels"},
            f"{record_id}.mipChains[{chain_index}]",
        )
        image_index = _nonnegative_int(chain.get("imageIndex"), "mipChain.imageIndex")
        fixture_id = _nonempty_string(chain.get("fixtureId"), "mipChain.fixtureId")
        if fixture_id not in fixture_ids:
            raise EvidenceError(f"{record_id} mip chain fixture is not inventoried")
        storage_role = _nonempty_string(chain.get("storageRole"), "storageRole")
        if storage_role not in STORAGE_ROLES:
            raise EvidenceError(f"{record_id} storage role is invalid")
        chain_key = (image_index, storage_role)
        if chain_key in chains_by_key:
            raise EvidenceError(f"{record_id} mip chain identity is duplicated")
        chains_by_key[chain_key] = chain
        consumers = _list(chain.get("materialConsumers"), "materialConsumers")
        if not consumers:
            raise EvidenceError(f"{record_id} mip chain has no material consumer")
        texture_indices: set[int] = set()
        for raw_consumer in consumers:
            consumer = _object(raw_consumer, "materialConsumer")
            _exact_keys(
                consumer,
                {"textureIndex", "materialSlot", "contentRole", "magFilter", "minFilter", "wrapS", "wrapT"},
                "materialConsumer",
            )
            texture_index = _nonnegative_int(consumer.get("textureIndex"), "textureIndex")
            if texture_index in texture_indices:
                raise EvidenceError(f"{record_id} texture consumer is duplicated")
            texture_indices.add(texture_index)
            slot = _nonempty_string(consumer.get("materialSlot"), "materialSlot")
            content_role = _nonempty_string(consumer.get("contentRole"), "contentRole")
            if slot not in MATERIAL_SLOTS or SLOT_CONTENT_ROLE[slot] != content_role:
                raise EvidenceError(f"{record_id} material slot/content role is incompatible")
            expected_storage = "color" if content_role == "color" else "nonColor"
            if storage_role != expected_storage:
                raise EvidenceError(f"{record_id} content/storage roles disagree")
            if consumer.get("magFilter") not in MAG_FILTERS:
                raise EvidenceError(f"{record_id} magFilter is not a glTF sampler enum")
            if consumer.get("minFilter") not in MIN_FILTERS:
                raise EvidenceError(f"{record_id} minFilter is not a glTF sampler enum")
            if consumer.get("wrapS") not in WRAP_MODES or consumer.get("wrapT") not in WRAP_MODES:
                raise EvidenceError(f"{record_id} wrap mode is not a glTF sampler enum")
        levels = _list(chain.get("levels"), "levels")
        if not levels:
            raise EvidenceError(f"{record_id} mip chain has no levels")
        if len(levels) > limits["maxMipLevels"]:
            raise EvidenceError(f"{record_id} mip chain exceeds maxMipLevels")
        previous_width: int | None = None
        previous_height: int | None = None
        for expected_level, raw_level in enumerate(levels):
            level = _object(raw_level, "mip level")
            _exact_keys(level, {"level", "width", "height", "byteLength", "rgbaSha256"}, "mip level")
            if level.get("level") != expected_level:
                raise EvidenceError(f"{record_id} mip levels must be ordered")
            width = _positive_int(level.get("width"), "mipLevel.width")
            height = _positive_int(level.get("height"), "mipLevel.height")
            byte_length = _positive_int(level.get("byteLength"), "mipLevel.byteLength")
            if width > limits["maxTextureDimension"] or height > limits["maxTextureDimension"]:
                raise EvidenceError(f"{record_id} mip dimensions exceed the declared limit")
            if previous_width is not None and (
                width != max(1, previous_width // 2)
                or height != max(1, previous_height // 2)
            ):
                raise EvidenceError(f"{record_id} mip dimensions are not canonical")
            if byte_length != width * height * 4:
                raise EvidenceError(f"{record_id} RGBA mip byte length is not canonical")
            total_mip_bytes += byte_length
            previous_width = width
            previous_height = height
            _sha(level.get("rgbaSha256"), "mipLevel.rgbaSha256")
    if total_mip_bytes > limits["maxNativeOutputBytes"]:
        raise EvidenceError(f"{record_id} mip bytes exceed maxNativeOutputBytes")

    mip_sampling = _nullable_object(record.get("mipSampling"), f"{record_id}.mipSampling")

    validator = _object(record.get("validator"), f"{record_id}.validator")
    _exact_keys(validator, {"name", "version", "passed", "reportArtifactId"}, f"{record_id}.validator")
    _nonempty_string(validator.get("name"), "validator.name")
    _nonempty_string(validator.get("version"), "validator.version")
    _boolean(validator.get("passed"), "validator.passed")
    _require_artifact(
        artifacts_by_id,
        validator.get("reportArtifactId"),
        "validator-report",
        f"{record_id} validator report",
    )

    package = _object(record.get("package"), f"{record_id}.package")
    _exact_keys(
        package,
        {
            "pluginRegistered",
            "nativeSymbolsVerified",
            "licensesVerified",
            "releaseStrippingVerified",
            "layoutArtifactId",
            "symbolsArtifactId",
            "licensesArtifactId",
            "releaseArtifactId",
        },
        f"{record_id}.package",
    )
    for key in (
        "pluginRegistered",
        "nativeSymbolsVerified",
        "licensesVerified",
        "releaseStrippingVerified",
    ):
        _boolean(package.get(key), f"package.{key}")
    package_artifact_ids = {
        key: _optional_string(package.get(key), f"package.{key}")
        for key in (
            "layoutArtifactId",
            "symbolsArtifactId",
            "licensesArtifactId",
            "releaseArtifactId",
        )
    }

    for artifact in artifacts_by_id.values():
        if verify_local_artifacts:
            artifact_path = _nonempty_string(artifact.get("path"), "artifact.path")
            absolute_path = _verified_local_artifact_path(artifact_path)
            payload = absolute_path.read_bytes()
            if len(payload) != artifact["byteLength"]:
                raise EvidenceError(f"artifact byte length changed: {artifact_path}")
            if hashlib.sha256(payload).hexdigest() != artifact["sha256"]:
                raise EvidenceError(f"artifact SHA-256 changed: {artifact_path}")

    blockers = _string_list(record.get("blockers"), f"{record_id}.blockers")
    if maturity != "production-ready" and not blockers:
        raise EvidenceError(f"{record_id} non-production record needs a blocker")
    if maturity == "production-ready" and blockers:
        raise EvidenceError(f"{record_id} production-ready record cannot retain blockers")

    if "host-validation" in gates and validator.get("passed") is not True:
        raise EvidenceError(f"{record_id} host-validation gate did not pass")
    if "package-install" in gates:
        native_feature = bool(
            features
            & {"KHR_draco_mesh_compression", "KHR_texture_basisu"}
        )
        if package.get("licensesVerified") is not True or (
            native_feature and package.get("pluginRegistered") is not True
        ):
            raise EvidenceError(f"{record_id} package-install gate is incomplete")
        _require_artifact(artifacts_by_id, package_artifact_ids["layoutArtifactId"], "package-layout", f"{record_id} package layout")
        _require_artifact(artifacts_by_id, package_artifact_ids["licensesArtifactId"], "package-licenses", f"{record_id} package licenses")
    if "release-build" in gates and any(
        package.get(key) is not True
        for key in (
            "nativeSymbolsVerified",
            "licensesVerified",
            "releaseStrippingVerified",
        )
    ):
        raise EvidenceError(f"{record_id} release-build gate is incomplete")
    if "release-build" in gates:
        _require_artifact(artifacts_by_id, package_artifact_ids["symbolsArtifactId"], "package-symbols", f"{record_id} package symbols")
        _require_artifact(artifacts_by_id, package_artifact_ids["releaseArtifactId"], "package-release", f"{record_id} release build")
    if "runtime" in gates:
        if runtime is None or not all(
            runtime.get(key) is True
            for key in ("loadSucceeded", "renderSucceeded", "readbackSucceeded")
        ):
            raise EvidenceError(f"{record_id} runtime gate needs a successful target render/readback")
        _require_artifact(artifacts_by_id, runtime.get("renderArtifactId"), "runtime-render", f"{record_id} runtime render")
        _require_artifact(artifacts_by_id, runtime.get("readbackArtifactId"), "runtime-readback", f"{record_id} runtime readback")
    if "runtime-diagnostic" in gates:
        if runtime_diagnostic is None or not (
            runtime_diagnostic.get("emitted") is True
            and runtime_diagnostic.get("code") == "unsupportedModelFeature"
            and runtime_diagnostic.get("count") == 1
            and runtime_diagnostic.get("nativePluginInvocationCount") == 0
        ):
            raise EvidenceError(f"{record_id} runtime-diagnostic gate is incomplete")
        _require_artifact(artifacts_by_id, runtime_diagnostic.get("artifactId"), "runtime-diagnostic", f"{record_id} runtime diagnostic")
    if "cancellation-resource" in gates:
        cancellation_ok = (
            cancellation.get("workerExited") is True
            and cancellation.get("terminalDiagnosticCount") == 1
            and cancellation.get("latePublicationCount") == 0
            and cancellation.get("registryEntriesAfter") == 0
            and cancellation.get("subsequentLoadSucceeded") is True
        )
        allocation_ok = (
            allocations.get("liveBytesAfter") == 0
            and allocations.get("allocationCount")
            == allocations.get("releaseCount")
            and allocations.get("peakLiveBytes", 0)
            <= allocations.get("limitBytes", -1)
            and allocations.get("limitBytes", 0)
            <= limits.get("maxWorkingBytes", -1)
        )
        if not cancellation_ok or not allocation_ok:
            raise EvidenceError(
                f"{record_id} cancellation-resource gate is incomplete"
            )
        _require_artifact(artifacts_by_id, cancellation_artifact_id, "log", f"{record_id} cancellation/resource log")
    if "authored-mip-sampling" in gates:
        _validate_mip_sampling(
            record_id,
            features,
            mip_sampling,
            chains_by_key,
            artifacts_by_id,
        )


def claim_has_durable_evidence(
    manifest: dict[str, object],
    feature: str,
    target: str,
    *,
    production_ready: bool,
) -> bool:
    claims = _list(manifest.get("claims"), "claims")
    for raw_claim in claims:
        claim = _object(raw_claim, "claim")
        if claim.get("feature") == feature and claim.get("target") == target:
            if claim.get("evidenceStatus") != "verified locally":
                return False
            if production_ready and claim.get("maturity") != "production-ready":
                return False
            return True
    return False


def _validate_mip_sampling(
    record_id: str,
    features: set[str],
    sampling: dict[str, object] | None,
    chains_by_key: dict[tuple[int, str], dict[str, object]],
    artifacts_by_id: dict[str, dict[str, object]],
) -> None:
    if "KHR_texture_basisu" not in features or sampling is None:
        raise EvidenceError(
            f"{record_id} authored-mip-sampling gate needs explicit LOD RGB evidence"
        )
    _exact_keys(
        sampling,
        {"imageIndex", "storageRole", "lodSamples", "baseOnlyNegativeControl"},
        f"{record_id}.mipSampling",
    )
    image_index = _nonnegative_int(sampling.get("imageIndex"), "mipSampling.imageIndex")
    storage_role = _nonempty_string(sampling.get("storageRole"), "mipSampling.storageRole")
    chain = chains_by_key.get((image_index, storage_role))
    if chain is None:
        raise EvidenceError(f"{record_id} mip sampling does not identify a chain")
    levels = _list(chain.get("levels"), "mip levels")
    if len(levels) < 2:
        raise EvidenceError(
            f"{record_id} authored-mip-sampling gate needs a multi-level chain"
        )
    samples = _list(sampling.get("lodSamples"), "mipSampling.lodSamples")
    if len(samples) != len(levels):
        raise EvidenceError(f"{record_id} explicit LOD RGB evidence is incomplete")
    expected_rgbs: dict[int, list[int]] = {}
    for expected_level, raw_sample in enumerate(samples):
        sample = _object(raw_sample, "LOD sample")
        _exact_keys(
            sample,
            {"level", "expectedRgb", "observedRgb", "artifactId"},
            "LOD sample",
        )
        if sample.get("level") != expected_level:
            raise EvidenceError(f"{record_id} explicit LOD RGB levels are not canonical")
        expected_rgb = _rgb(sample.get("expectedRgb"), "LOD expectedRgb")
        observed_rgb = _rgb(sample.get("observedRgb"), "LOD observedRgb")
        if expected_rgb != observed_rgb:
            raise EvidenceError(f"{record_id} explicit LOD RGB readback does not match")
        expected_rgbs[expected_level] = expected_rgb
        _require_artifact(
            artifacts_by_id,
            sample.get("artifactId"),
            "mip-lod-readback",
            f"{record_id} LOD {expected_level} readback",
        )

    control = _object(
        sampling.get("baseOnlyNegativeControl"),
        "mipSampling.baseOnlyNegativeControl",
    )
    _exact_keys(
        control,
        {"lod", "expectedBaseRgb", "observedRgb", "authoredLodRgb", "artifactId"},
        "mipSampling.baseOnlyNegativeControl",
    )
    lod = _positive_int(control.get("lod"), "baseOnlyNegativeControl.lod")
    if lod >= len(levels):
        raise EvidenceError(f"{record_id} base-only negative-control LOD is invalid")
    expected_base = _rgb(control.get("expectedBaseRgb"), "expectedBaseRgb")
    observed = _rgb(control.get("observedRgb"), "baseOnly observedRgb")
    authored_lod = _rgb(control.get("authoredLodRgb"), "authoredLodRgb")
    if not (
        expected_base == observed == expected_rgbs[0]
        and authored_lod == expected_rgbs[lod]
        and observed != authored_lod
    ):
        raise EvidenceError(f"{record_id} base-only negative control is not discriminating")
    _require_artifact(
        artifacts_by_id,
        control.get("artifactId"),
        "mip-base-only-control",
        f"{record_id} base-only negative control",
    )


def _validate_claim_records(
    feature: str,
    target: str,
    record_ids: list[str],
    records_by_id: dict[str, dict[str, object]],
    *,
    production_ready: bool,
) -> set[str]:
    covered_gates: set[str] = set()
    expected_kind = TARGET_KIND_FOR_CLAIM[target]
    for record_id in record_ids:
        record = records_by_id.get(record_id)
        if record is None:
            raise EvidenceError(f"{feature}/{target} cites unknown record {record_id}")
        record_features = _string_set(record.get("features"), "record.features")
        if feature not in record_features:
            raise EvidenceError(
                f"record {record_id} does not match claim feature {feature}"
            )
        if production_ready and record.get("maturity") != "production-ready":
            raise EvidenceError(
                f"production-ready claim cites candidate-only record {record_id}"
            )
        target_record = _object(record.get("target"), "record.target")
        actual_kind = _nonempty_string(target_record.get("kind"), "record.target.kind")
        record_gates = _string_set(record.get("gates"), "record.gates")
        if target == "android" and actual_kind == "android_build":
            if not record_gates <= BUILD_ONLY_GATES:
                raise EvidenceError(
                    f"build-only record {record_id} cannot satisfy Android runtime"
                )
        elif actual_kind != expected_kind:
            raise EvidenceError(
                f"record {record_id} target {actual_kind} does not match claim target {target}"
            )
        covered_gates.update(record_gates)
    return covered_gates


def _json_object(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    return _object(value, str(path))


def _exact_keys(value: dict[str, object], keys: set[str], label: str) -> None:
    if set(value) != keys:
        raise EvidenceError(f"{label} keys changed")


def _object(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{label} must be an object")
    return value


def _list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise EvidenceError(f"{label} must be an array")
    return value


def _string_list(value: object, label: str) -> list[str]:
    values = _list(value, label)
    if not all(isinstance(item, str) and item for item in values):
        raise EvidenceError(f"{label} must contain non-empty strings")
    return list(values)


def _string_set(value: object, label: str) -> set[str]:
    values = _string_list(value, label)
    if len(values) != len(set(values)):
        raise EvidenceError(f"{label} must be unique")
    return set(values)


def _nonempty_string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise EvidenceError(f"{label} must be a non-empty string")
    return value


def _record_id(value: object, label: str) -> str:
    record_id = _nonempty_string(value, label)
    if RECORD_ID_PATTERN.fullmatch(record_id) is None:
        raise EvidenceError(
            f"{label} must match ^[a-z0-9][a-z0-9._-]*$"
        )
    return record_id


def _rfc3339_date_time(value: object, label: str) -> str:
    captured_at = _nonempty_string(value, label)
    if RFC3339_DATE_TIME_PATTERN.fullmatch(captured_at) is None:
        raise EvidenceError(f"{label} must be an RFC 3339 date-time")
    try:
        parsed = datetime.fromisoformat(captured_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise EvidenceError(f"{label} must be an RFC 3339 date-time") from error
    if parsed.utcoffset() is None:
        raise EvidenceError(f"{label} must be an RFC 3339 date-time")
    return captured_at


def _nonnegative_int(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise EvidenceError(f"{label} must be a non-negative integer")
    return value


def _positive_int(value: object, label: str) -> int:
    result = _nonnegative_int(value, label)
    if result == 0:
        raise EvidenceError(f"{label} must be positive")
    return result


def _boolean(value: object, label: str) -> bool:
    if not isinstance(value, bool):
        raise EvidenceError(f"{label} must be boolean")
    return value


def _nullable_object(value: object, label: str) -> dict[str, object] | None:
    if value is None:
        return None
    return _object(value, label)


def _optional_string(value: object, label: str) -> str | None:
    if value is None:
        return None
    return _nonempty_string(value, label)


def _rgb(value: object, label: str) -> list[int]:
    values = _list(value, label)
    if len(values) != 3 or any(
        not isinstance(channel, int)
        or isinstance(channel, bool)
        or channel < 0
        or channel > 255
        for channel in values
    ):
        raise EvidenceError(f"{label} must contain three 8-bit channels")
    return values


def _require_artifact(
    artifacts_by_id: dict[str, dict[str, object]],
    raw_artifact_id: object,
    expected_kind: str,
    label: str,
) -> dict[str, object]:
    artifact_id = _nonempty_string(raw_artifact_id, f"{label} artifact id")
    artifact = artifacts_by_id.get(artifact_id)
    if artifact is None or artifact.get("kind") != expected_kind:
        raise EvidenceError(
            f"{label} must resolve through the artifact inventory as {expected_kind}"
        )
    return artifact


def _sha(value: object, label: str, *, length: int = 64) -> str:
    result = _nonempty_string(value, label)
    if len(result) != length or any(character not in "0123456789abcdef" for character in result):
        raise EvidenceError(f"{label} must be {length} lowercase hexadecimal characters")
    return result


def _repo_relative_path(value: object, label: str) -> str:
    path = _nonempty_string(value, label)
    candidate = Path(path)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise EvidenceError(f"{label} must be repository-relative")
    return path


def _artifact_path(value: object, label: str) -> str:
    path = _nonempty_string(value, label)
    if ARTIFACT_PATH_PATTERN.fullmatch(path) is None:
        raise EvidenceError(
            f"{label} must stay below ignored artifact path {ARTIFACT_ROOT} "
            "and use safe path segments"
        )
    return path


def _verified_local_artifact_path(artifact_path: str) -> Path:
    candidate = REPO_ROOT / artifact_path
    current = REPO_ROOT
    for part in Path(artifact_path).parts:
        current /= part
        if current.is_symlink():
            raise EvidenceError(
                f"local artifact path contains a symbolic link: {artifact_path}"
            )
    artifact_root = REPO_ROOT / ARTIFACT_ROOT
    try:
        resolved_root = artifact_root.resolve(strict=True)
        resolved_candidate = candidate.resolve(strict=True)
    except FileNotFoundError as error:
        raise EvidenceError(f"local artifact is missing: {artifact_path}") from error
    try:
        resolved_candidate.relative_to(resolved_root)
    except ValueError as error:
        raise EvidenceError(
            f"local artifact escapes the resolved artifact root: {artifact_path}"
        ) from error
    if not resolved_candidate.is_file():
        raise EvidenceError(f"local artifact is missing: {artifact_path}")
    return resolved_candidate


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--records-dir", type=Path)
    parser.add_argument("--verify-local-artifacts", action="store_true")
    args = parser.parse_args(argv)
    if not args.check and args.manifest is None:
        parser.error("use --check or --manifest")
    manifest_path = args.manifest or DEFAULT_MANIFEST_PATH
    records_dir = args.records_dir or (
        manifest_path.parent / "records"
        if args.manifest is not None
        else DEFAULT_RECORDS_DIR
    )
    load_manifest(
        manifest_path,
        records_dir,
        verify_local_artifacts=args.verify_local_artifacts,
    )
    print("decoder/mip evidence manifest is valid")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (EvidenceError, OSError, json.JSONDecodeError) as error:
        print(f"decoder/mip evidence validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
