#!/usr/bin/env python3
"""Verify and stage material-extension fixtures outside git."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import struct
import sys
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "tools/material_extension_acceptance/manifest.json"
OUT_ROOT = REPO_ROOT / "tools/out/material_extension_acceptance"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


class FixtureError(RuntimeError):
    pass


def _load_provenance() -> dict[str, object]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    provenance = manifest.get("fixtureProvenance")
    if not isinstance(provenance, dict):
        raise FixtureError("manifest fixtureProvenance must be an object")
    return provenance


def _load_plan015_clearcoat() -> dict[str, object]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    corpus = manifest.get("plan015ClearcoatCorpus")
    if not isinstance(corpus, dict):
        raise FixtureError("manifest plan015ClearcoatCorpus must be an object")
    return corpus


def _load_plan018_sheen() -> dict[str, object]:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    corpus = manifest.get("plan018SheenCorpus")
    if not isinstance(corpus, dict):
        raise FixtureError("manifest plan018SheenCorpus must be an object")
    return corpus


def _require_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise FixtureError(f"{label} must be a lowercase SHA-256 digest")
    return value


def _require_safe_relative_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        raise FixtureError(f"{label} must be a safe relative POSIX path")
    parts = value.split("/")
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or any(part in {"", ".", ".."} for part in parts)
        or str(path) != value
    ):
        raise FixtureError(f"{label} must be a safe relative POSIX path")
    return value


def _verify_metadata(provenance: dict[str, object]) -> list[dict[str, object]]:
    if provenance.get("schemaVersion") != 1:
        raise FixtureError("fixtureProvenance.schemaVersion must equal 1")
    expected_scope = (
        "Source and license provenance only; no renderer, runtime, target, "
        "release, or production-readiness evidence."
    )
    if provenance.get("scope") != expected_scope:
        raise FixtureError("fixtureProvenance.scope changed")
    evidence = provenance.get("evidence")
    if not isinstance(evidence, dict):
        raise FixtureError("fixtureProvenance.evidence must be an object")
    if evidence.get("runtimeCapability") != "not established":
        raise FixtureError("fixture provenance cannot establish runtime capability")
    if evidence.get("releaseMaturity") != "not established":
        raise FixtureError("fixture provenance cannot establish release maturity")
    repository = provenance.get("sourceRepository")
    if not isinstance(repository, dict):
        raise FixtureError("sourceRepository must be an object")
    commit = repository.get("commit")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
        raise FixtureError("sourceRepository.commit must be a full commit")

    fixtures = provenance.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) != 6:
        raise FixtureError("fixtureProvenance must contain exactly 6 fixtures")

    records: list[dict[str, object]] = []
    ids: set[str] = set()
    for raw in fixtures:
        if not isinstance(raw, dict):
            raise FixtureError("each fixture must be an object")
        record = dict(raw)
        fixture_id = record.get("id")
        if not isinstance(fixture_id, str) or not fixture_id or fixture_id in ids:
            raise FixtureError("fixture ids must be non-empty and unique")
        ids.add(fixture_id)
        _require_sha256(record.get("sourceSha256"), f"{fixture_id}.sourceSha256")
        if not isinstance(record.get("byteLength"), int) or record["byteLength"] <= 0:
            raise FixtureError(f"{fixture_id}.byteLength must be positive")

        if record.get("sourceKind") == "khronos-official":
            if record.get("sourceRepository") != repository:
                raise FixtureError(f"{fixture_id} repository pin differs")
            source_url = record.get("sourceUrl")
            if not isinstance(source_url, str) or f"/{commit}/" not in source_url:
                raise FixtureError(f"{fixture_id}.sourceUrl must pin the commit")
            license_record = record.get("license")
            if not isinstance(license_record, dict):
                raise FixtureError(f"{fixture_id}.license must be an object")
            evidence_url = license_record.get("evidenceUrl")
            if not isinstance(evidence_url, str) or f"/{commit}/" not in evidence_url:
                raise FixtureError(
                    f"{fixture_id}.license.evidenceUrl must pin the commit"
                )
            _require_sha256(
                license_record.get("evidenceSha256"),
                f"{fixture_id}.license.evidenceSha256",
            )
            if (
                not isinstance(license_record.get("evidenceByteLength"), int)
                or license_record["evidenceByteLength"] <= 0
            ):
                raise FixtureError(
                    f"{fixture_id}.license.evidenceByteLength must be positive"
                )
            if record.get("vendored") is not False or record.get("localPath") is not None:
                raise FixtureError(f"{fixture_id} must remain metadata-only")
        elif fixture_id == "a1b32":
            if record.get("sourceUrl") is not None or record.get("localPath") is not None:
                raise FixtureError("a1b32 must not invent public or tracked provenance")
            if record.get("vendored") is not False:
                raise FixtureError("a1b32 must remain unvendored")
            permission = record.get("permission")
            if not isinstance(permission, dict) or permission.get("status") != "user-authorized":
                raise FixtureError("a1b32 user authorization is required")
            if permission.get("scope") != "current Plan 014 repository-local use":
                raise FixtureError("a1b32 permission scope must remain task-local")
            if permission.get("redistribution") != "not established; asset is not vendored":
                raise FixtureError("a1b32 redistribution must remain unestablished")
            staging_path = record.get("stagingPath")
            if not isinstance(staging_path, str) or not staging_path.startswith("tools/out/"):
                raise FixtureError("a1b32 stagingPath must remain under tools/out")
            source_validation = record.get("sourceValidation")
            if not isinstance(source_validation, dict):
                raise FixtureError("a1b32 sourceValidation must be an object")
            warning_details = source_validation.get("warningDetails")
            if (
                not isinstance(warning_details, list)
                or len(warning_details) != source_validation.get("warnings")
            ):
                raise FixtureError("a1b32 warning details must match warning count")
            expected_warning_keys = {
                "severity",
                "code",
                "message",
                "pointer",
                "disposition",
            }
            for warning in warning_details:
                if not isinstance(warning, dict) or set(warning) != expected_warning_keys:
                    raise FixtureError("a1b32 warning detail schema changed")
                if warning.get("severity") != 1:
                    raise FixtureError("a1b32 source warning severity changed")
                if not isinstance(warning.get("message"), str) or not warning["message"]:
                    raise FixtureError("a1b32 source warning message is required")
                if "target" not in str(warning.get("disposition")):
                    raise FixtureError("a1b32 warning lacks target disposition")
        else:
            raise FixtureError(f"unsupported fixture source kind for {fixture_id}")
        records.append(record)
    return records


def _verify_plan015_clearcoat_metadata(
    corpus: dict[str, object],
) -> list[dict[str, object]]:
    if corpus.get("schemaVersion") != 1:
        raise FixtureError("plan015ClearcoatCorpus.schemaVersion must equal 1")
    repository = corpus.get("sourceRepository")
    if not isinstance(repository, dict):
        raise FixtureError("plan015ClearcoatCorpus.sourceRepository must be an object")
    commit = repository.get("commit")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
        raise FixtureError("plan015 clearcoat source commit must be full")
    fixtures = corpus.get("fixtures")
    if not isinstance(fixtures, list) or len(fixtures) != 3:
        raise FixtureError("plan015 clearcoat corpus must contain exactly 3 fixtures")

    records: list[dict[str, object]] = []
    expected_ids = ["clearcoat_test", "clearcoat_car_paint", "toycar"]
    for index, raw in enumerate(fixtures):
        if not isinstance(raw, dict):
            raise FixtureError("each plan015 clearcoat fixture must be an object")
        record = dict(raw)
        fixture_id = record.get("id")
        if fixture_id != expected_ids[index]:
            raise FixtureError("plan015 clearcoat fixture order or id changed")
        source_path = record.get("sourcePath")
        if not isinstance(source_path, str) or not source_path.endswith(".glb"):
            raise FixtureError(f"{fixture_id}.sourcePath must identify a GLB")
        _require_sha256(record.get("sourceSha256"), f"{fixture_id}.sourceSha256")
        if not isinstance(record.get("byteLength"), int) or record["byteLength"] <= 0:
            raise FixtureError(f"{fixture_id}.byteLength must be positive")
        license_record = record.get("license")
        if not isinstance(license_record, dict):
            raise FixtureError(f"{fixture_id}.license must be an object")
        license_path = license_record.get("evidencePath")
        if not isinstance(license_path, str) or not license_path.endswith("LICENSE.md"):
            raise FixtureError(f"{fixture_id}.license.evidencePath is invalid")
        _require_sha256(
            license_record.get("evidenceSha256"),
            f"{fixture_id}.license.evidenceSha256",
        )
        if (
            not isinstance(license_record.get("evidenceByteLength"), int)
            or license_record["evidenceByteLength"] <= 0
        ):
            raise FixtureError(
                f"{fixture_id}.license.evidenceByteLength must be positive"
            )
        records.append(record)
    return records


def _verify_plan018_sheen_metadata(
    corpus: dict[str, object],
) -> list[dict[str, object]]:
    if corpus.get("schemaVersion") != 1:
        raise FixtureError("plan018SheenCorpus.schemaVersion must equal 1")
    repository = corpus.get("sourceRepository")
    if not isinstance(repository, dict):
        raise FixtureError("plan018SheenCorpus.sourceRepository must be an object")
    commit = repository.get("commit")
    if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
        raise FixtureError("Plan 018 sheen source commit must be full")
    staging_root = _require_safe_relative_path(
        corpus.get("stagingRoot"), "plan018SheenCorpus.stagingRoot"
    )
    if (
        not staging_root.startswith("tools/out/")
        or Path(staging_root).is_absolute()
    ):
        raise FixtureError("Plan 018 sheen stagingRoot must stay under tools/out")
    _require_safe_relative_path(
        corpus.get("stagingToolPath"), "plan018SheenCorpus.stagingToolPath"
    )
    expected_scope = (
        "Source/license provenance and deterministic derived-container staging "
        "only; no Three.js, Flutter, renderer, target, release, or "
        "production-readiness evidence."
    )
    if corpus.get("scope") != expected_scope:
        raise FixtureError("plan018SheenCorpus.scope changed")
    evidence = corpus.get("evidence")
    if not isinstance(evidence, dict):
        raise FixtureError("plan018SheenCorpus.evidence must be an object")
    expected_evidence = {
        "sourceAndLicenseProvenance": "verified locally",
        "threeJsLoading": "not run",
        "flutterLoading": "not run",
        "rendering": "not run",
        "releaseMaturity": "not established",
        "productionReadiness": "not established",
        "targetEvidence": [
            {"target": "iOS Simulator", "status": "not run"},
            {"target": "physical iOS", "status": "not run"},
            {"target": "Android", "status": "not run"},
            {"target": "Web", "status": "not run"},
        ],
    }
    if evidence != expected_evidence:
        raise FixtureError("Plan 018 sheen evidence boundary changed")
    expected_coverage = {
        "collectiveSheenInputs": [
            "sheenColorFactor",
            "sheenColorTexture",
            "sheenRoughnessFactor",
            "sheenRoughnessTexture",
        ],
        "toyCarRoleSeparation": {
            "evidenceKind": "authored-data separation only",
            "sheen": {
                "material": "Fabric",
                "extension": "KHR_materials_sheen",
            },
            "clearcoat": {
                "material": "ToyCar",
                "extension": "KHR_materials_clearcoat",
            },
            "transmission": {
                "material": "Glass",
                "extension": "KHR_materials_transmission",
            },
            "rendering": "not run",
        },
    }
    if corpus.get("authoredCoverage") != expected_coverage:
        raise FixtureError("Plan 018 authored coverage or ToyCar roles changed")

    fixtures = corpus.get("fixtures")
    expected_ids = ["sheen_chair", "sheen_cloth", "glam_velvet_sofa", "toycar"]
    if not isinstance(fixtures, list) or len(fixtures) != len(expected_ids):
        raise FixtureError("Plan 018 sheen corpus must contain exactly 4 fixtures")
    expected_kinds = [
        "khronos-official-glb",
        "khronos-official-multifile-gltf",
        "khronos-official-glb",
        "khronos-official-glb",
    ]
    records: list[dict[str, object]] = []
    collective_inputs: set[str] = set()
    source_paths: set[str] = set()
    for index, raw in enumerate(fixtures):
        if not isinstance(raw, dict):
            raise FixtureError("each Plan 018 sheen fixture must be an object")
        record = dict(raw)
        fixture_id = record.get("id")
        if fixture_id != expected_ids[index]:
            raise FixtureError("Plan 018 sheen fixture order or id changed")
        if record.get("sourceKind") != expected_kinds[index]:
            raise FixtureError(f"{fixture_id}.sourceKind changed")
        if record.get("sourceRepository") != repository:
            raise FixtureError(f"{fixture_id} repository pin differs")
        if record.get("vendored") is not False or record.get("localPath") is not None:
            raise FixtureError(f"{fixture_id} must remain unvendored metadata")
        expected_staging_directory = f"{staging_root}/{fixture_id}"
        staging_directory = _require_safe_relative_path(
            record.get("stagingDirectory"), f"{fixture_id}.stagingDirectory"
        )
        if staging_directory != expected_staging_directory:
            raise FixtureError(f"{fixture_id}.stagingDirectory changed")
        authored_inputs = record.get("authoredSheenInputs")
        if not isinstance(authored_inputs, list) or not authored_inputs:
            raise FixtureError(f"{fixture_id}.authoredSheenInputs is invalid")
        for value in authored_inputs:
            if not isinstance(value, str):
                raise FixtureError(f"{fixture_id}.authoredSheenInputs is invalid")
            collective_inputs.add(value)

        source_files = record.get("sourceFiles")
        if not isinstance(source_files, list) or not source_files:
            raise FixtureError(f"{fixture_id}.sourceFiles must be non-empty")
        for raw_source in source_files:
            if not isinstance(raw_source, dict):
                raise FixtureError(f"{fixture_id} source record must be an object")
            source = dict(raw_source)
            path = _require_safe_relative_path(
                source.get("path"), f"{fixture_id} source path"
            )
            url = source.get("url")
            if (
                not path.startswith("Models/")
                or path in source_paths
            ):
                raise FixtureError(f"{fixture_id} source path is invalid or duplicated")
            source_paths.add(path)
            if not isinstance(url, str) or f"/{commit}/{path}" not in url:
                raise FixtureError(f"{fixture_id} source URL must pin path and commit")
            _require_sha256(source.get("sha256"), f"{fixture_id} {path} sha256")
            if not isinstance(source.get("byteLength"), int) or source["byteLength"] <= 0:
                raise FixtureError(f"{fixture_id} {path} byteLength must be positive")
            if not isinstance(source.get("mediaType"), str):
                raise FixtureError(f"{fixture_id} {path} mediaType is required")

        license_record = record.get("license")
        if not isinstance(license_record, dict):
            raise FixtureError(f"{fixture_id}.license must be an object")
        evidence_path = _require_safe_relative_path(
            license_record.get("evidencePath"),
            f"{fixture_id}.license.evidencePath",
        )
        evidence_url = license_record.get("evidenceUrl")
        if not evidence_path.endswith("LICENSE.md"):
            raise FixtureError(f"{fixture_id}.license.evidencePath is invalid")
        if (
            not isinstance(evidence_url, str)
            or f"/{commit}/{evidence_path}" not in evidence_url
        ):
            raise FixtureError(f"{fixture_id} license URL must pin path and commit")
        if not isinstance(license_record.get("assetSpdx"), str) or not isinstance(
            license_record.get("metadataSpdx"), str
        ):
            raise FixtureError(f"{fixture_id} SPDX labels are required")
        _require_sha256(
            license_record.get("evidenceSha256"),
            f"{fixture_id}.license.evidenceSha256",
        )
        if (
            not isinstance(license_record.get("evidenceByteLength"), int)
            or license_record["evidenceByteLength"] <= 0
        ):
            raise FixtureError(
                f"{fixture_id}.license.evidenceByteLength must be positive"
            )

        derived = record.get("derivedArtifact")
        if fixture_id == "sheen_cloth":
            if not isinstance(derived, dict):
                raise FixtureError("sheen_cloth.derivedArtifact is required")
            if (
                derived.get("artifactKind")
                != "repository-generated-deterministic-container"
                or derived.get("provenance")
                != "repository-generated deterministic container derived from the "
                "hash-pinned official multi-file source"
            ):
                raise FixtureError("SheenCloth derived artifact label changed")
            output_path = _require_safe_relative_path(
                derived.get("outputPath"), "sheen_cloth.derivedArtifact.outputPath"
            )
            if (
                not output_path.startswith(f"{staging_root}/sheen_cloth/")
                or not output_path.endswith("/SheenCloth.glb")
            ):
                raise FixtureError("SheenCloth derived output must stay ignored")
            _require_sha256(derived.get("sha256"), "SheenCloth derived sha256")
            if not isinstance(derived.get("byteLength"), int) or derived["byteLength"] <= 0:
                raise FixtureError("SheenCloth derived byteLength must be positive")
        elif derived is not None:
            raise FixtureError(f"{fixture_id} must not claim a derived artifact")
        records.append(record)

    if collective_inputs != set(expected_coverage["collectiveSheenInputs"]):
        raise FixtureError("Plan 018 fixtures do not cover every authored sheen input")
    return records


def _digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _verify_bytes(data: bytes, record: dict[str, object], label: str) -> None:
    expected_length = record["byteLength"]
    if len(data) != expected_length:
        raise FixtureError(
            f"{label} byteLength mismatch: expected {expected_length}, got {len(data)}"
        )
    expected_sha = record["sourceSha256"]
    actual_sha = _digest(data)
    if actual_sha != expected_sha:
        raise FixtureError(
            f"{label} SHA-256 mismatch: expected {expected_sha}, got {actual_sha}"
        )


def _download(url: str) -> bytes:
    try:
        result = subprocess.run(
            [
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--max-time",
                "30",
                "--user-agent",
                "flutter-scene-viewer-fixture-tool/1",
                url,
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=35,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as error:
        raise FixtureError(f"curl download failed for {url}: {error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise FixtureError(f"curl download failed for {url}: {detail}")
    return result.stdout


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(f".{path.name}.partial")
    partial.write_bytes(data)
    os.replace(partial, path)


def _fetch_khronos(records: list[dict[str, object]]) -> None:
    for record in records:
        if record["sourceKind"] != "khronos-official":
            continue
        fixture_id = str(record["id"])
        source = _download(str(record["sourceUrl"]))
        _verify_bytes(source, record, fixture_id)
        license_record = dict(record["license"])
        license_bytes = _download(str(license_record["evidenceUrl"]))
        expected_license_sha = license_record["evidenceSha256"]
        actual_license_sha = _digest(license_bytes)
        if actual_license_sha != expected_license_sha:
            raise FixtureError(
                f"{fixture_id} license SHA-256 mismatch: expected "
                f"{expected_license_sha}, got {actual_license_sha}"
            )
        expected_license_length = license_record["evidenceByteLength"]
        if len(license_bytes) != expected_license_length:
            raise FixtureError(
                f"{fixture_id} license byteLength mismatch: expected "
                f"{expected_license_length}, got {len(license_bytes)}"
            )
        destination = OUT_ROOT / "khronos" / fixture_id
        _write_atomic(destination / Path(str(record["sourcePath"])).name, source)
        _write_atomic(destination / "LICENSE.md", license_bytes)
        print(f"{fixture_id}: OK")


def _fetch_plan015_clearcoat(
    corpus: dict[str, object], records: list[dict[str, object]]
) -> None:
    repository = dict(corpus["sourceRepository"])
    commit = str(repository["commit"])
    staging_root = REPO_ROOT / str(corpus["stagingRoot"])
    raw_root = (
        "https://raw.githubusercontent.com/KhronosGroup/"
        f"glTF-Sample-Assets/{commit}"
    )
    for record in records:
        fixture_id = str(record["id"])
        source_path = str(record["sourcePath"])
        source = _download(f"{raw_root}/{source_path}")
        _verify_bytes(source, record, fixture_id)
        license_record = dict(record["license"])
        license_bytes = _download(
            f"{raw_root}/{license_record['evidencePath']}"
        )
        expected_license_sha = str(license_record["evidenceSha256"])
        if _digest(license_bytes) != expected_license_sha:
            raise FixtureError(f"{fixture_id} license SHA-256 mismatch")
        if len(license_bytes) != license_record["evidenceByteLength"]:
            raise FixtureError(f"{fixture_id} license byteLength mismatch")
        destination = staging_root / fixture_id
        _write_atomic(destination / Path(source_path).name, source)
        _write_atomic(destination / "LICENSE.md", license_bytes)
        print(f"plan015/{fixture_id}: OK")


def _verify_plan018_file_bytes(
    data: bytes, record: dict[str, object], label: str
) -> None:
    expected_length = record["byteLength"]
    if len(data) != expected_length:
        raise FixtureError(
            f"{label} byteLength mismatch: expected {expected_length}, got {len(data)}"
        )
    expected_sha = record["sha256"]
    actual_sha = _digest(data)
    if actual_sha != expected_sha:
        raise FixtureError(
            f"{label} SHA-256 mismatch: expected {expected_sha}, got {actual_sha}"
        )


def _read_plan018_fixture(
    record: dict[str, object], source_root: Path | None
) -> tuple[dict[str, bytes], bytes]:
    fixture_id = str(record["id"])
    source_data: dict[str, bytes] = {}
    for raw_source in list(record["sourceFiles"]):
        source = dict(raw_source)
        source_path = str(source["path"])
        data = (
            _download(str(source["url"]))
            if source_root is None
            else (source_root / source_path).read_bytes()
        )
        _verify_plan018_file_bytes(data, source, f"{fixture_id} source")
        source_data[source_path] = data

    license_record = dict(record["license"])
    license_bytes = (
        _download(str(license_record["evidenceUrl"]))
        if source_root is None
        else (source_root / str(license_record["evidencePath"])).read_bytes()
    )
    expected_license_length = int(license_record["evidenceByteLength"])
    if len(license_bytes) != expected_license_length:
        raise FixtureError(
            f"{fixture_id} license byteLength mismatch: expected "
            f"{expected_license_length}, got {len(license_bytes)}"
        )
    expected_license_sha = str(license_record["evidenceSha256"])
    actual_license_sha = _digest(license_bytes)
    if actual_license_sha != expected_license_sha:
        raise FixtureError(
            f"{fixture_id} license SHA-256 mismatch: expected "
            f"{expected_license_sha}, got {actual_license_sha}"
        )
    return source_data, license_bytes


def _pack_plan018_sheen_cloth(
    record: dict[str, object], source_data: dict[str, bytes]
) -> bytes:
    source_records = [dict(value) for value in list(record["sourceFiles"])]
    gltf_source = next(
        (value for value in source_records if value["mediaType"] == "model/gltf+json"),
        None,
    )
    if gltf_source is None:
        raise FixtureError("SheenCloth official glTF source is missing")
    gltf_path = str(gltf_source["path"])
    try:
        document = json.loads(source_data[gltf_path].decode("utf-8"))
    except (KeyError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FixtureError(f"SheenCloth glTF JSON is malformed: {error}") from error
    if not isinstance(document, dict):
        raise FixtureError("SheenCloth glTF JSON root must be an object")

    buffers = document.get("buffers")
    buffer_views = document.get("bufferViews")
    images = document.get("images")
    if (
        not isinstance(buffers, list)
        or len(buffers) != 1
        or not isinstance(buffers[0], dict)
        or not isinstance(buffer_views, list)
        or not isinstance(images, list)
    ):
        raise FixtureError("SheenCloth source container layout changed")
    source_directory = PurePosixPath(gltf_path).parent
    buffer_uri = buffers[0].get("uri")
    if not isinstance(buffer_uri, str):
        raise FixtureError("SheenCloth source buffer must be external")
    buffer_path = str(source_directory / buffer_uri)
    try:
        binary = bytearray(source_data[buffer_path])
    except KeyError as error:
        raise FixtureError(f"SheenCloth buffer source is missing: {buffer_path}") from error
    if buffers[0].get("byteLength") != len(binary):
        raise FixtureError("SheenCloth source buffer byteLength changed")

    media_types = {
        str(value["path"]): str(value["mediaType"]) for value in source_records
    }
    original_buffer_view_count = len(buffer_views)
    for image_index, raw_image in enumerate(images):
        if not isinstance(raw_image, dict):
            raise FixtureError(f"SheenCloth image {image_index} must be an object")
        uri = raw_image.get("uri")
        if not isinstance(uri, str) or "bufferView" in raw_image:
            raise FixtureError(f"SheenCloth image {image_index} must be external")
        image_path = str(source_directory / uri)
        try:
            image_bytes = source_data[image_path]
            mime_type = media_types[image_path]
        except KeyError as error:
            raise FixtureError(f"SheenCloth image source is missing: {image_path}") from error
        while len(binary) % 4 != 0:
            binary.append(0)
        buffer_view_index = len(buffer_views)
        buffer_views.append(
            {
                "buffer": 0,
                "byteOffset": len(binary),
                "byteLength": len(image_bytes),
            }
        )
        del raw_image["uri"]
        raw_image["bufferView"] = buffer_view_index
        raw_image["mimeType"] = mime_type
        binary.extend(image_bytes)

    document["buffers"] = [{"byteLength": len(binary)}]
    json_bytes = json.dumps(
        document,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    binary_bytes = bytes(binary)
    binary_bytes += b"\x00" * (-len(binary_bytes) % 4)
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary_bytes)
    result = b"".join(
        [
            struct.pack("<4sII", b"glTF", 2, total_length),
            struct.pack("<II", len(json_bytes), 0x4E4F534A),
            json_bytes,
            struct.pack("<II", len(binary_bytes), 0x004E4942),
            binary_bytes,
        ]
    )

    derived = dict(record["derivedArtifact"])
    _verify_plan018_file_bytes(result, derived, "sheen_cloth derived")
    contract = dict(derived["glbContract"])
    if (
        contract.get("version") != 2
        or len(document.get("buffers", [])) != contract.get("buffers")
        or len(buffer_views) != contract.get("bufferViews")
        or len(images) != contract.get("embeddedImages")
        or len(document.get("materials", [])) != contract.get("materials")
        or original_buffer_view_count + len(images) != len(buffer_views)
        or any("uri" in image or "bufferView" not in image for image in images)
    ):
        raise FixtureError("SheenCloth derived GLB structure differs from contract")
    return result


def _stage_plan018_sheen(
    records: list[dict[str, object]], source_root: Path | None
) -> None:
    for record in records:
        fixture_id = str(record["id"])
        source_data, license_bytes = _read_plan018_fixture(record, source_root)
        destination = REPO_ROOT / str(record["stagingDirectory"])
        source_destination = destination / "source"
        for source_path, data in source_data.items():
            _write_atomic(source_destination / PurePosixPath(source_path).name, data)
        _write_atomic(source_destination / "LICENSE.md", license_bytes)
        if fixture_id == "sheen_cloth":
            derived = dict(record["derivedArtifact"])
            derived_bytes = _pack_plan018_sheen_cloth(record, source_data)
            _write_atomic(REPO_ROOT / str(derived["outputPath"]), derived_bytes)
        print(f"plan018/{fixture_id}: OK")


def _glb_json(data: bytes) -> dict[str, object]:
    if len(data) < 20 or data[:4] != b"glTF":
        raise FixtureError("a1b32 is not a GLB container")
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        raise FixtureError("a1b32 GLB version or declared length mismatch")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A or 20 + json_length > len(data):
        raise FixtureError("a1b32 has no valid leading JSON chunk")
    try:
        value = json.loads(data[20 : 20 + json_length].decode("utf-8").rstrip(" \x00"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FixtureError(f"a1b32 JSON chunk is malformed: {error}") from error
    if not isinstance(value, dict):
        raise FixtureError("a1b32 JSON root must be an object")
    return value


def _verify_a1b32(data: bytes, record: dict[str, object]) -> None:
    _verify_bytes(data, record, "a1b32")
    glb = _glb_json(data)
    contract = dict(record["glbContract"])
    if glb.get("extensionsUsed") != contract["extensionsUsed"]:
        raise FixtureError("a1b32 extensionsUsed mismatch")
    if glb.get("extensionsRequired") != contract["extensionsRequired"]:
        raise FixtureError("a1b32 extensionsRequired mismatch")
    for key in ("nodes", "meshes", "materials"):
        value = glb.get(key)
        if not isinstance(value, list) or len(value) != contract[key]:
            raise FixtureError(f"a1b32 {key} count mismatch")


def _stage_a1b32(source_path: Path, record: dict[str, object]) -> None:
    data = source_path.read_bytes()
    _verify_a1b32(data, record)
    destination = REPO_ROOT / str(record["stagingPath"])
    _write_atomic(destination, data)
    print(f"a1b32 staged to {destination.relative_to(REPO_ROOT)}: OK")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--verify-metadata", action="store_true")
    actions.add_argument("--fetch-khronos", action="store_true")
    actions.add_argument("--fetch-plan015-clearcoat", action="store_true")
    actions.add_argument("--fetch-plan018-sheen", action="store_true")
    actions.add_argument(
        "--stage-plan018-sheen", type=Path, metavar="SOURCE_ROOT"
    )
    actions.add_argument("--stage-a1b32", type=Path, metavar="SOURCE_GLB")
    args = parser.parse_args(argv)

    provenance = _load_provenance()
    records = _verify_metadata(provenance)
    if args.verify_metadata:
        corpus = _load_plan015_clearcoat()
        clearcoat_records = _verify_plan015_clearcoat_metadata(corpus)
        sheen_corpus = _load_plan018_sheen()
        sheen_records = _verify_plan018_sheen_metadata(sheen_corpus)
        print(
            f"{len(records)} fixture records and "
            f"{len(clearcoat_records)} Plan 015 clearcoat records: OK"
        )
        print(f"{len(sheen_records)} Plan 018 sheen records: OK")
    elif args.fetch_khronos:
        _fetch_khronos(records)
    elif args.fetch_plan015_clearcoat:
        corpus = _load_plan015_clearcoat()
        clearcoat_records = _verify_plan015_clearcoat_metadata(corpus)
        _fetch_plan015_clearcoat(corpus, clearcoat_records)
    elif args.fetch_plan018_sheen:
        sheen_corpus = _load_plan018_sheen()
        sheen_records = _verify_plan018_sheen_metadata(sheen_corpus)
        _stage_plan018_sheen(sheen_records, None)
    elif args.stage_plan018_sheen is not None:
        sheen_corpus = _load_plan018_sheen()
        sheen_records = _verify_plan018_sheen_metadata(sheen_corpus)
        _stage_plan018_sheen(sheen_records, args.stage_plan018_sheen)
    else:
        a1b32 = next(record for record in records if record["id"] == "a1b32")
        _stage_a1b32(args.stage_a1b32, a1b32)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (FixtureError, OSError) as error:
        print(f"fixture staging failed: {error}", file=sys.stderr)
        raise SystemExit(1)
