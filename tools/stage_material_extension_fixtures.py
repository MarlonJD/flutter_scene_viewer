#!/usr/bin/env python3
"""Verify and stage Plan 014 material-extension fixtures outside git."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import struct
import sys
from pathlib import Path


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


def _require_sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise FixtureError(f"{label} must be a lowercase SHA-256 digest")
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
    actions.add_argument("--stage-a1b32", type=Path, metavar="SOURCE_GLB")
    args = parser.parse_args(argv)

    provenance = _load_provenance()
    records = _verify_metadata(provenance)
    if args.verify_metadata:
        print(f"{len(records)} fixture records: OK")
    elif args.fetch_khronos:
        _fetch_khronos(records)
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
