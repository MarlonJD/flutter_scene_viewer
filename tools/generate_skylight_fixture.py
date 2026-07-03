#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'test' / 'fixtures' / 'SkylightTable.glb'


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
        0, 1, 2, 0, 2, 3,
        4, 5, 6, 4, 6, 7,
        8, 9, 10, 8, 10, 11,
        12, 13, 14, 12, 14, 15,
        16, 17, 18, 16, 18, 19,
        20, 21, 22, 20, 22, 23,
    ]

    binary = bytearray()
    views: list[dict[str, object]] = []
    position_view = _append_buffer_view(binary, views, _pack_floats(_flatten(positions)), target=34962)
    normal_view = _append_buffer_view(binary, views, _pack_floats(_flatten(normals)), target=34962)
    texcoord_view = _append_buffer_view(binary, views, _pack_floats(_flatten(texcoords)), target=34962)
    index_view = _append_buffer_view(
        binary,
        views,
        struct.pack('<' + 'H' * len(indices), *indices),
        target=34963,
    )

    gltf = {
        'asset': {
            'version': '2.0',
            'generator': 'flutter_scene_viewer skylight fixture generator',
        },
        'scene': 0,
        'scenes': [{'name': 'Scene', 'nodes': [0]}],
        'nodes': [
            {'name': 'SkylightSmokeAssembly', 'children': [1, 2, 3]},
            {
                'name': 'Table',
                'mesh': 0,
                'translation': [0.0, 0.0, 0.0],
                'scale': [3.0, 0.12, 1.6],
            },
            {
                'name': 'UpperObject',
                'mesh': 1,
                'translation': [-0.75, 0.36, 0.0],
                'scale': [0.48, 0.48, 0.48],
            },
            {
                'name': 'LowerObject',
                'mesh': 2,
                'translation': [0.75, -0.38, 0.0],
                'scale': [0.48, 0.48, 0.48],
            },
        ],
        'meshes': [
            _mesh('TableMesh', 0),
            _mesh('UpperObjectMesh', 1),
            _mesh('LowerObjectMesh', 2),
        ],
        'materials': [
            _pbr_material(
                'Matte warm table',
                base_color=[0.52, 0.47, 0.39, 1.0],
                metallic=0.0,
                roughness=0.72,
            ),
            _pbr_material(
                'Upper matte object',
                base_color=[0.88, 0.90, 0.92, 1.0],
                metallic=0.0,
                roughness=0.48,
            ),
            _pbr_material(
                'Lower matte object',
                base_color=[0.82, 0.86, 0.90, 1.0],
                metallic=0.0,
                roughness=0.48,
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


def _pack_floats(values: list[float]) -> bytes:
    return struct.pack('<' + 'f' * len(values), *values)


def _flatten(values: list[tuple[float, ...]]) -> list[float]:
    return [component for value in values for component in value]


def _glb(gltf: dict[str, object], binary: bytes) -> bytes:
    json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    json_padding = (4 - len(json_bytes) % 4) % 4
    bin_padding = (4 - len(binary) % 4) % 4
    json_chunk = json_bytes + b' ' * json_padding
    bin_chunk = binary + b'\0' * bin_padding
    total_length = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    return b''.join(
        [
            struct.pack('<III', 0x46546C67, 2, total_length),
            struct.pack('<I4s', len(json_chunk), b'JSON'),
            json_chunk,
            struct.pack('<I4s', len(bin_chunk), b'BIN\0'),
            bin_chunk,
        ]
    )


def _pad(binary: bytearray, value: int) -> None:
    while len(binary) % 4:
        binary.append(value)


if __name__ == '__main__':
    main()
