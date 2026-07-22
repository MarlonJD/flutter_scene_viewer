#!/usr/bin/env python3
"""Generate the scalar-only Plan 018 renderer-native sheen control GLB."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = REPO_ROOT / "test/fixtures/MultiMaterialAssembly.glb"
DEFAULT_OUTPUT_PATH = (
    REPO_ROOT / "test/fixtures/Plan018RendererNativeSheenControl.glb"
)
SOURCE_SHA256 = "5f717f321050c3049a29cdf3e3223ad10fd05ce485a088011f77d84357b9ad5f"
GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


class FixtureError(RuntimeError):
    pass


def _read_source() -> tuple[dict[str, object], bytes]:
    data = SOURCE_PATH.read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise FixtureError("MultiMaterialAssembly.glb SHA-256 drifted")
    if len(data) < 28:
        raise FixtureError("source GLB is too short")
    magic, version, declared_length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC or version != 2 or declared_length != len(data):
        raise FixtureError("source GLB header drifted")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != JSON_CHUNK:
        raise FixtureError("source GLB JSON chunk is missing")
    json_end = 20 + json_length
    if json_end + 8 > len(data):
        raise FixtureError("source GLB JSON length is invalid")
    binary_length, binary_type = struct.unpack_from("<II", data, json_end)
    binary_start = json_end + 8
    binary_end = binary_start + binary_length
    if binary_type != BIN_CHUNK or binary_end != len(data):
        raise FixtureError("source GLB BIN chunk drifted")
    try:
        document = json.loads(data[20:json_end].decode("utf-8").rstrip(" \x00"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise FixtureError(f"source GLB JSON is malformed: {error}") from error
    if not isinstance(document, dict):
        raise FixtureError("source GLB JSON root is not an object")
    return document, data[binary_start:binary_end]


def _validate_source_contract(document: dict[str, object]) -> None:
    if "extensionsUsed" in document or "extensionsRequired" in document:
        raise FixtureError("source GLB unexpectedly declares extensions")
    if any(key in document for key in ("textures", "images", "samplers")):
        raise FixtureError("source GLB unexpectedly contains texture resources")
    materials = document.get("materials")
    meshes = document.get("meshes")
    if not isinstance(materials, list) or len(materials) != 3:
        raise FixtureError("source material inventory drifted")
    if not isinstance(materials[0], dict) or "extensions" in materials[0]:
        raise FixtureError("source control material already has extensions")
    if not isinstance(meshes, list) or len(meshes) != 3:
        raise FixtureError("source mesh inventory drifted")
    expected_attributes = {
        "POSITION": 0,
        "NORMAL": 1,
        "TEXCOORD_0": 2,
    }
    for mesh in meshes:
        if not isinstance(mesh, dict):
            raise FixtureError("source mesh is malformed")
        primitives = mesh.get("primitives")
        if not isinstance(primitives, list) or len(primitives) != 1:
            raise FixtureError("source primitive inventory drifted")
        primitive = primitives[0]
        if (
            not isinstance(primitive, dict)
            or primitive.get("attributes") != expected_attributes
        ):
            raise FixtureError("source NORMAL/TEXCOORD_0 layout drifted")


def _build_fixture(document: dict[str, object], binary: bytes) -> bytes:
    _validate_source_contract(document)
    derived = json.loads(json.dumps(document, ensure_ascii=False, allow_nan=False))
    derived["extensionsUsed"] = ["KHR_materials_sheen"]
    materials = derived["materials"]
    assert isinstance(materials, list) and isinstance(materials[0], dict)
    materials[0]["extensions"] = {
        "KHR_materials_sheen": {
            "sheenColorFactor": [1, 1, 1],
            "sheenRoughnessFactor": 0.5,
        }
    }
    json_bytes = json.dumps(
        derived,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary)
    return b"".join(
        [
            struct.pack("<III", GLB_MAGIC, 2, total_length),
            struct.pack("<II", len(json_bytes), JSON_CHUNK),
            json_bytes,
            struct.pack("<II", len(binary), BIN_CHUNK),
            binary,
        ]
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        document, binary = _read_source()
        fixture = _build_fixture(document, binary)
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(fixture)
        print(
            "Plan 018 renderer-native sheen fixture: "
            f"{len(fixture)} bytes, {hashlib.sha256(fixture).hexdigest()}"
        )
    except (FixtureError, OSError, ValueError) as error:
        print(f"Plan 018 renderer-native sheen fixture error: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
