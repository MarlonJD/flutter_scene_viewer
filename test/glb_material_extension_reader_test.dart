import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_material_extension_reader.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads authored transmission glass extensions from binary GLB JSON', () {
    final result = readGlbMaterialExtensionIntent(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'name': 'GlassPanel', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'TEXCOORD_0': 1,
                },
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_materials_transmission': <String, Object?>{
                'transmissionFactor': 0.75,
                'transmissionTexture': <String, Object?>{'index': 2},
              },
              'KHR_materials_ior': <String, Object?>{'ior': 1.45},
              'KHR_materials_volume': <String, Object?>{
                'thicknessFactor': 0.02,
                'thicknessTexture': <String, Object?>{'index': 3},
                'attenuationColor': <Object?>[0.8, 0.95, 1.0],
                'attenuationDistance': 4.0,
              },
            },
          },
        ],
      }),
      debugName: 'glass.glb',
    );

    final address = PartAddress(
      nodePath: <String>['GlassPanel'],
      primitiveIndex: 0,
    );
    final patch = result.patches[address]!;

    expect(result.diagnostics, isEmpty);
    expect(patch.transmission, 0.75);
    expect(patch.transmissionTexture, isNotNull);
    expect(patch.ior, 1.45);
    expect(patch.thickness, 0.02);
    expect(patch.thicknessTexture, isNotNull);
    expect(patch.attenuationColor, <double>[0.8, 0.95, 1.0]);
    expect(patch.attenuationDistance, 4.0);
  });

  test('reports malformed extension values as diagnostics', () {
    final result = readGlbMaterialExtensionIntent(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'name': 'GlassPanel', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'TEXCOORD_0': 0},
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_materials_transmission': <String, Object?>{
                'transmissionFactor': 'opaque',
              },
            },
          },
        ],
      }),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.invalidMaterialOverride,
    );
    expect(result.diagnostics.single.details['extension'],
        'KHR_materials_transmission');
  });

  test('reports duplicate node paths as ambiguous and skips auto-apply', () {
    final result = readGlbMaterialExtensionIntent(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{
            'name': 'Root',
            'children': <Object?>[1, 2],
          },
          <String, Object?>{'name': 'GlassPanel', 'mesh': 0},
          <String, Object?>{'name': 'GlassPanel', 'mesh': 1},
        ],
        'meshes': <Object?>[
          _meshWithTransmissionPrimitive(),
          _meshWithTransmissionPrimitive(),
        ],
        'materials': <Object?>[
          _transmissionMaterial(),
        ],
      }),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.ambiguousNodePath,
    );
    expect(result.diagnostics.single.details['debugPath'], 'Root/GlassPanel');
  });

  test('reports missing UV0 for texture-bearing authored extensions', () {
    final result = readGlbMaterialExtensionIntent(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'name': 'GlassPanel', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{'POSITION': 0},
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_materials_transmission': <String, Object?>{
                'transmissionTexture': <String, Object?>{'index': 2},
              },
            },
          },
        ],
      }),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
    expect(result.diagnostics.single.details['uvSet'], 0);
  });

  test('reports texture slots for authored extension UV0 diagnostics', () {
    final result = readGlbMaterialExtensionIntent(
      _glb(<String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'scene': 0,
        'scenes': <Object?>[
          <String, Object?>{
            'nodes': <Object?>[0],
          },
        ],
        'nodes': <Object?>[
          <String, Object?>{'name': 'CoatedGlass', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'TEXCOORD_1': 1,
                },
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_materials_transmission': <String, Object?>{
                'transmissionTexture': <String, Object?>{'index': 2},
              },
              'KHR_materials_volume': <String, Object?>{
                'thicknessTexture': <String, Object?>{'index': 3},
              },
              'KHR_materials_clearcoat': <String, Object?>{
                'clearcoatTexture': <String, Object?>{'index': 4},
                'clearcoatRoughnessTexture': <String, Object?>{'index': 5},
                'clearcoatNormalTexture': <String, Object?>{'index': 6},
              },
            },
          },
        ],
      }),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
    expect(result.diagnostics.single.details['uvSet'], 0);
    expect(result.diagnostics.single.details['textureSlots'], <String>[
      'transmissionTexture',
      'thicknessTexture',
      'clearcoatTexture',
      'clearcoatRoughnessTexture',
      'clearcoatNormalTexture',
    ]);
  });

  test('reports invalid GLB headers without throwing', () {
    final result = readGlbMaterialExtensionIntent(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      debugName: 'broken.glb',
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.adapterFailure);
  });
}

Map<String, Object?> _meshWithTransmissionPrimitive() {
  return <String, Object?>{
    'primitives': <Object?>[
      <String, Object?>{
        'attributes': <String, Object?>{'TEXCOORD_0': 0},
        'material': 0,
      },
    ],
  };
}

Map<String, Object?> _transmissionMaterial() {
  return <String, Object?>{
    'extensions': <String, Object?>{
      'KHR_materials_transmission': <String, Object?>{
        'transmissionFactor': 1.0,
      },
    },
  };
}

Uint8List _glb(Map<String, Object?> json) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final totalLength = 12 + 8 + paddedJsonLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length; index < bytes.length; index += 1) {
    bytes[index] = 0x20;
  }
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;
