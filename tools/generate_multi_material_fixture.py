#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'test' / 'fixtures' / 'MultiMaterialAssembly.glb'


def main() -> None:
    positions = [
        (-0.5, -0.5, 0.5),
        (0.5, -0.5, 0.5),
        (0.5, 0.5, 0.5),
        (-0.5, 0.5, 0.5),
        (0.5, -0.5, -0.5),
        (-0.5, -0.5, -0.5),
        (-0.5, 0.5, -0.5),
        (0.5, 0.5, -0.5),
        (0.5, -0.5, 0.5),
        (0.5, -0.5, -0.5),
        (0.5, 0.5, -0.5),
        (0.5, 0.5, 0.5),
        (-0.5, -0.5, -0.5),
        (-0.5, -0.5, 0.5),
        (-0.5, 0.5, 0.5),
        (-0.5, 0.5, -0.5),
        (-0.5, 0.5, 0.5),
        (0.5, 0.5, 0.5),
        (0.5, 0.5, -0.5),
        (-0.5, 0.5, -0.5),
        (-0.5, -0.5, -0.5),
        (0.5, -0.5, -0.5),
        (0.5, -0.5, 0.5),
        (-0.5, -0.5, 0.5),
    ]
    face_normals = [
        (0.0, 0.0, 1.0),
        (0.0, 0.0, -1.0),
        (1.0, 0.0, 0.0),
        (-1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, -1.0, 0.0),
    ]
    normals = [normal for normal in face_normals for _ in range(4)]
    texcoords = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)] * 6
    indices = [
        0,
        1,
        2,
        0,
        2,
        3,
        4,
        5,
        6,
        4,
        6,
        7,
        8,
        9,
        10,
        8,
        10,
        11,
        12,
        13,
        14,
        12,
        14,
        15,
        16,
        17,
        18,
        16,
        18,
        19,
        20,
        21,
        22,
        20,
        22,
        23,
    ]

    binary = bytearray()
    views: list[dict[str, object]] = []

    position_view = _append_buffer_view(
        binary,
        views,
        _pack_floats(_flatten(positions)),
        target=34962,
    )
    normal_view = _append_buffer_view(
        binary,
        views,
        _pack_floats(_flatten(normals)),
        target=34962,
    )
    texcoord_view = _append_buffer_view(
        binary,
        views,
        _pack_floats(_flatten(texcoords)),
        target=34962,
    )
    index_view = _append_buffer_view(
        binary,
        views,
        struct.pack('<' + 'H' * len(indices), *indices),
        target=34963,
    )

    gltf = {
        'asset': {
            'version': '2.0',
            'generator': 'flutter_scene_viewer fixture generator',
        },
        'scene': 0,
        'scenes': [{'name': 'Scene', 'nodes': [0]}],
        'nodes': [
            {'name': 'SampleAssembly', 'children': [1, 2, 3]},
            {
                'name': 'BlueBody',
                'mesh': 0,
                'scale': [1.5, 0.75, 0.6],
            },
            {
                'name': 'GoldPanel',
                'mesh': 1,
                'translation': [0.95, 0.0, 0.0],
                'scale': [0.25, 1.0, 0.7],
            },
            {
                'name': 'RedAccent',
                'mesh': 2,
                'translation': [0.0, 0.55, 0.0],
                'scale': [1.2, 0.15, 0.7],
            },
        ],
        'meshes': [
            _mesh('BlueBodyMesh', 0),
            _mesh('GoldPanelMesh', 1),
            _mesh('RedAccentMesh', 2),
        ],
        'materials': [
            _pbr_material(
                'Matte blue body',
                base_color=[0.08, 0.28, 0.95, 1.0],
                metallic=0.0,
                roughness=0.6,
            ),
            _pbr_material(
                'Warm metallic panel',
                base_color=[1.0, 0.68, 0.16, 1.0],
                metallic=1.0,
                roughness=0.25,
            ),
            _pbr_material(
                'Red accent',
                base_color=[0.92, 0.08, 0.05, 1.0],
                metallic=0.0,
                roughness=0.45,
            ),
        ],
        'buffers': [{'byteLength': len(binary)}],
        'bufferViews': views,
        'accessors': [
            {
                'bufferView': position_view,
                'componentType': 5126,
                'count': len(positions),
                'type': 'VEC3',
                'min': [-0.5, -0.5, -0.5],
                'max': [0.5, 0.5, 0.5],
            },
            {
                'bufferView': normal_view,
                'componentType': 5126,
                'count': len(normals),
                'type': 'VEC3',
            },
            {
                'bufferView': texcoord_view,
                'componentType': 5126,
                'count': len(texcoords),
                'type': 'VEC2',
                'min': [0.0, 0.0],
                'max': [1.0, 1.0],
            },
            {
                'bufferView': index_view,
                'componentType': 5123,
                'count': len(indices),
                'type': 'SCALAR',
                'min': [0],
                'max': [23],
            },
        ],
    }

    OUTPUT.write_bytes(_glb(gltf, bytes(binary)))
    print(f'wrote {OUTPUT.relative_to(ROOT)} ({OUTPUT.stat().st_size} bytes)')


def _mesh(name: str, material: int) -> dict[str, object]:
    return {
        'name': name,
        'primitives': [
            {
                'attributes': {
                    'POSITION': 0,
                    'NORMAL': 1,
                    'TEXCOORD_0': 2,
                },
                'indices': 3,
                'material': material,
            }
        ],
    }


def _pbr_material(
    name: str,
    *,
    base_color: list[float],
    metallic: float,
    roughness: float,
) -> dict[str, object]:
    return {
        'name': name,
        'pbrMetallicRoughness': {
            'baseColorFactor': base_color,
            'metallicFactor': metallic,
            'roughnessFactor': roughness,
        },
    }


def _append_buffer_view(
    binary: bytearray,
    views: list[dict[str, object]],
    data: bytes,
    *,
    target: int,
) -> int:
    _pad(binary, 0)
    offset = len(binary)
    binary.extend(data)
    _pad(binary, 0)
    views.append(
        {
            'buffer': 0,
            'byteOffset': offset,
            'byteLength': len(data),
            'target': target,
        }
    )
    return len(views) - 1


def _glb(gltf: dict[str, object], binary: bytes) -> bytes:
    json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    json_chunk = bytearray(json_bytes)
    _pad(json_chunk, 0x20)
    bin_chunk = bytearray(binary)
    _pad(bin_chunk, 0)
    total_length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    return b''.join(
        [
            struct.pack('<III', 0x46546C67, 2, total_length),
            struct.pack('<I4s', len(json_chunk), b'JSON'),
            bytes(json_chunk),
            struct.pack('<I4s', len(bin_chunk), b'BIN\x00'),
            bytes(bin_chunk),
        ]
    )


def _pack_floats(values: list[float]) -> bytes:
    return struct.pack('<' + 'f' * len(values), *values)


def _flatten(values: list[tuple[float, ...]]) -> list[float]:
    return [component for value in values for component in value]


def _pad(data: bytearray, value: int) -> None:
    while len(data) % 4:
        data.append(value)


if __name__ == '__main__':
    main()
