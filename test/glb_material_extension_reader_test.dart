import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_material_extension_reader.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_patch_group.dart';
import 'package:flutter_scene_viewer/src/part_address.dart';
import 'package:flutter_scene_viewer/src/texture_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads authored transmission glass extensions from binary GLB JSON', () {
    final textureBytes = <Uint8List>[
      Uint8List.fromList(<int>[21, 22]),
      Uint8List.fromList(<int>[23, 24]),
    ];
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(<String, Object?>{
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
                'transmissionTexture': <String, Object?>{'index': 0},
              },
              'KHR_materials_ior': <String, Object?>{'ior': 1.45},
              'KHR_materials_volume': <String, Object?>{
                'thicknessFactor': 0.02,
                'thicknessTexture': <String, Object?>{'index': 1},
                'attenuationColor': <Object?>[0.8, 0.95, 1.0],
                'attenuationDistance': 4.0,
              },
            },
          },
        ],
        'textures': <Object?>[
          for (var index = 0; index < textureBytes.length; index += 1)
            <String, Object?>{'source': index},
        ],
        'images': <Object?>[
          for (var index = 0; index < textureBytes.length; index += 1)
            <String, Object?>{
              'mimeType': 'image/png',
              'bufferView': index,
            },
        ],
        'bufferViews': <Object?>[
          for (var index = 0, offset = 0;
              index < textureBytes.length;
              offset += textureBytes[index].length, index += 1)
            <String, Object?>{
              'buffer': 0,
              'byteOffset': offset,
              'byteLength': textureBytes[index].length,
            },
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': textureBytes.fold<int>(
              0,
              (sum, bytes) => sum + bytes.length,
            ),
          },
        ],
      }, textureBytes),
      debugName: 'glass.glb',
    );

    final address = PartAddress(
      nodePath: <String>['GlassPanel'],
      primitiveIndex: 0,
    );
    final patch = result
        .patches[address]![MaterialExtensionPatchGroup.transmissionVolume]!;

    expect(result.diagnostics, isEmpty);
    expect(patch.transmission, 0.75);
    expect(
      (patch.transmissionTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[0],
    );
    expect(patch.ior, 1.45);
    expect(patch.thickness, 0.02);
    expect(
      (patch.thicknessTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[1],
    );
    expect(patch.attenuationColor, <double>[0.8, 0.95, 1.0]);
    expect(patch.attenuationDistance, 4.0);
  });

  test('reads authored specular and IOR extensions from binary GLB JSON', () {
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
          <String, Object?>{'name': 'A1B32', 'mesh': 0},
        ],
        'meshes': <Object?>[
          <String, Object?>{
            'primitives': <Object?>[
              <String, Object?>{
                'attributes': <String, Object?>{
                  'POSITION': 0,
                  'NORMAL': 1,
                  'TEXCOORD_0': 2,
                },
                'material': 0,
              },
            ],
          },
        ],
        'materials': <Object?>[
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_materials_specular': <String, Object?>{
                'specularFactor': 0.6,
                'specularColorFactor': <Object?>[0.18, 0.19, 0.2],
              },
              'KHR_materials_ior': <String, Object?>{'ior': 1.45},
            },
          },
        ],
      }),
      debugName: 'a1b32-style.glb',
    );

    final address = PartAddress(
      nodePath: <String>['A1B32'],
      primitiveIndex: 0,
    );
    final patchGroups = result.patches[address]!;
    final opaqueIor = patchGroups[MaterialExtensionPatchGroup.opaqueIor]!;
    final specular = patchGroups[MaterialExtensionPatchGroup.specular]!;

    expect(result.diagnostics, isEmpty);
    expect(specular.specular, 0.6);
    expect(specular.specularColorFactor, <double>[0.18, 0.19, 0.2]);
    expect(specular.ior, isNull);
    expect(opaqueIor.ior, 1.45);
    expect(opaqueIor.hasGlassOverride, isFalse);
  });

  test('reads authored extension texture bytes from GLB image bufferViews', () {
    final textureBytes = <Uint8List>[
      Uint8List.fromList(<int>[1, 2]),
      Uint8List.fromList(<int>[3, 4, 5]),
      Uint8List.fromList(<int>[6]),
      Uint8List.fromList(<int>[7, 8]),
      Uint8List.fromList(<int>[9, 10, 11]),
      Uint8List.fromList(<int>[12]),
      Uint8List.fromList(<int>[13, 14]),
    ];
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(
        <String, Object?>{
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
                  'transmissionTexture': <String, Object?>{'index': 0},
                },
                'KHR_materials_volume': <String, Object?>{
                  'thicknessTexture': <String, Object?>{'index': 1},
                },
                'KHR_materials_clearcoat': <String, Object?>{
                  'clearcoatTexture': <String, Object?>{'index': 2},
                  'clearcoatRoughnessTexture': <String, Object?>{'index': 3},
                  'clearcoatNormalTexture': <String, Object?>{
                    'index': 4,
                    'scale': 0.25,
                  },
                },
                'KHR_materials_specular': <String, Object?>{
                  'specularTexture': <String, Object?>{
                    'index': 5,
                    'extensions': <String, Object?>{
                      'KHR_texture_transform': <String, Object?>{
                        'scale': <Object?>[2.5, 2.5],
                      },
                    },
                  },
                  'specularColorTexture': <String, Object?>{
                    'index': 6,
                    'extensions': <String, Object?>{
                      'KHR_texture_transform': <String, Object?>{
                        'offset': <Object?>[0.1, 0.2],
                      },
                    },
                  },
                },
              },
            },
          ],
          'textures': <Object?>[
            for (var index = 0; index < textureBytes.length; index += 1)
              <String, Object?>{
                'source': index == 6 ? 5 : index,
                if (index == 5) 'sampler': 0,
                if (index == 6) 'sampler': 1,
              },
          ],
          'samplers': <Object?>[
            <String, Object?>{'wrapS': 33071, 'wrapT': 10497},
            <String, Object?>{'wrapS': 10497, 'wrapT': 33648},
          ],
          'images': <Object?>[
            for (var index = 0; index < textureBytes.length; index += 1)
              <String, Object?>{
                'mimeType': 'image/png',
                'bufferView': index,
              },
          ],
          'bufferViews': <Object?>[
            for (var index = 0, offset = 0;
                index < textureBytes.length;
                offset += textureBytes[index].length, index += 1)
              <String, Object?>{
                'buffer': 0,
                'byteOffset': offset,
                'byteLength': textureBytes[index].length,
              },
          ],
          'buffers': <Object?>[
            <String, Object?>{
              'byteLength': textureBytes.fold<int>(
                0,
                (sum, bytes) => sum + bytes.length,
              ),
            },
          ],
        },
        textureBytes,
      ),
      debugName: 'extension-textures.glb',
    );

    final patchGroups = result.patches[PartAddress(
      nodePath: <String>['CoatedGlass'],
      primitiveIndex: 0,
    )]!;
    final transmissionVolume =
        patchGroups[MaterialExtensionPatchGroup.transmissionVolume]!;
    final clearcoat = patchGroups[MaterialExtensionPatchGroup.clearcoat]!;
    final specular = patchGroups[MaterialExtensionPatchGroup.specular]!;

    expect(result.diagnostics, isEmpty);
    expect(
      (transmissionVolume.transmissionTextureBinding!.source
              as BytesTextureSource)
          .encodedBytes,
      textureBytes[0],
    );
    expect(
      (transmissionVolume.thicknessTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[1],
    );
    expect(
      (clearcoat.clearcoatTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[2],
    );
    expect(
      (clearcoat.clearcoatRoughnessTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[3],
    );
    expect(
      (clearcoat.clearcoatNormalTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[4],
    );
    expect(clearcoat.clearcoatNormalScale, 0.25);
    expect(
      (specular.specularTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[5],
    );
    expect(
      (specular.specularColorTextureBinding!.source as BytesTextureSource)
          .encodedBytes,
      textureBytes[5],
    );
    expect(
      specular.specularTextureBinding!.transform.scale,
      <double>[2.5, 2.5],
    );
    expect(
      specular.specularColorTextureBinding!.transform.offset,
      <double>[0.1, 0.2],
    );
    expect(
      specular.specularTextureBinding!.sampler.wrapS.name,
      'clampToEdge',
    );
    expect(
      specular.specularColorTextureBinding!.sampler.wrapT.name,
      'mirroredRepeat',
    );
  });

  test('reports BasisU extension texture sources as unsupported', () {
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(
        <String, Object?>{
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
                  'transmissionTexture': <String, Object?>{'index': 0},
                },
              },
            },
          ],
          'textures': <Object?>[
            <String, Object?>{
              'extensions': <String, Object?>{
                'KHR_texture_basisu': <String, Object?>{'source': 0},
              },
            },
          ],
          'images': <Object?>[
            <String, Object?>{
              'mimeType': 'image/ktx2',
              'bufferView': 0,
            },
          ],
          'bufferViews': <Object?>[
            <String, Object?>{
              'buffer': 0,
              'byteLength': _basisuKtx2Header.length,
            },
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 4},
          ],
        },
        <Uint8List>[_basisuKtx2Header],
      ),
      debugName: 'basisu-extension.glb',
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(
      result.diagnostics.single.details['requiredExtension'],
      'KHR_texture_basisu',
    );
    expect(
      result.diagnostics.single.details['status'],
      'basisuTranscodeUnavailable',
    );
    expect(
      result.diagnostics.single.details['reason'],
      contains('Basis Universal ETC1S/UASTC transcode support'),
    );
    expect(
      result.diagnostics.single.details['nextStep'],
      contains('optional BasisU transcoder plugin'),
    );
    expect(
      result.diagnostics.single.details['ktx2'],
      containsPair('supercompression', 'basisLz'),
    );
    expect(
      result.diagnostics.single.details['ktx2'],
      containsPair('vkFormat', 0),
    );
  });

  test('preserves authored extension textures that use an available UV set',
      () {
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(
        <String, Object?>{
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
                    'TEXCOORD_0': 1,
                    'TEXCOORD_1': 2,
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
                  'transmissionTexture': <String, Object?>{
                    'index': 0,
                    'texCoord': 1,
                  },
                },
              },
            },
          ],
          'textures': <Object?>[
            <String, Object?>{'source': 0},
          ],
          'images': <Object?>[
            <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
          ],
          'bufferViews': <Object?>[
            <String, Object?>{'buffer': 0, 'byteLength': 3},
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': 3},
          ],
        },
        <Uint8List>[
          Uint8List.fromList(<int>[1, 2, 3])
        ],
      ),
      debugName: 'extension-texcoord1.glb',
    );

    expect(result.diagnostics, isEmpty);
    final patch = result.patches[PartAddress(
      nodePath: <String>['CoatedGlass'],
      primitiveIndex: 0,
    )]![MaterialExtensionPatchGroup.transmissionVolume]!;
    expect(patch.transmissionTextureBinding!.texCoord, 1);
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

  test('malformed extension group does not discard a valid sibling group', () {
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
          <String, Object?>{'name': 'CoatedPanel', 'mesh': 0},
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
              'KHR_materials_specular': <String, Object?>{
                'specularFactor': 'invalid',
              },
              'KHR_materials_clearcoat': <String, Object?>{
                'clearcoatFactor': 0.8,
              },
            },
          },
        ],
      }),
    );

    final groups = result.patches[PartAddress(
      nodePath: const <String>['CoatedPanel'],
      primitiveIndex: 0,
    )]!;
    expect(groups, isNot(contains(MaterialExtensionPatchGroup.specular)));
    expect(
      groups[MaterialExtensionPatchGroup.clearcoat]!.clearcoat,
      0.8,
    );
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details['extension'],
      'KHR_materials_specular',
    );
  });

  test('range-invalid specular group preserves valid opaque IOR sibling', () {
    final result = readGlbMaterialExtensionIntent(
      _singleMaterialExtensionsGlb(<String, Object?>{
        'KHR_materials_specular': <String, Object?>{
          'specularFactor': 1.01,
        },
        'KHR_materials_ior': <String, Object?>{'ior': 1.45},
      }),
      debugName: 'invalid-specular.glb',
    );
    final groups = result.patches[PartAddress(
      nodePath: const <String>['Material'],
      primitiveIndex: 0,
    )]!;

    expect(groups, isNot(contains(MaterialExtensionPatchGroup.specular)));
    expect(groups[MaterialExtensionPatchGroup.opaqueIor]!.ior, 1.45);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride);
    expect(result.diagnostics.single.details['extension'],
        'KHR_materials_specular');
    expect(result.diagnostics.single.details['field'], 'specularFactor');
  });

  test('invalid specular color domain or shape preserves opaque IOR sibling',
      () {
    for (final colorFactor in <List<Object?>>[
      <Object?>[-0.01, 1, 1],
      <Object?>[1, 1],
    ]) {
      final result = readGlbMaterialExtensionIntent(
        _singleMaterialExtensionsGlb(<String, Object?>{
          'KHR_materials_specular': <String, Object?>{
            'specularColorFactor': colorFactor,
          },
          'KHR_materials_ior': <String, Object?>{'ior': 1.45},
        }),
        debugName: 'invalid-specular-color.glb',
      );
      final groups = result.patches[PartAddress(
        nodePath: const <String>['Material'],
        primitiveIndex: 0,
      )]!;

      expect(
        groups,
        isNot(contains(MaterialExtensionPatchGroup.specular)),
        reason: '$colorFactor',
      );
      expect(groups[MaterialExtensionPatchGroup.opaqueIor]!.ior, 1.45);
      expect(result.diagnostics, hasLength(1), reason: '$colorFactor');
      expect(result.diagnostics.single.code,
          ViewerDiagnosticCode.invalidMaterialOverride);
      expect(result.diagnostics.single.details['extension'],
          'KHR_materials_specular');
      expect(
        result.diagnostics.single.details['field'],
        'specularColorFactor',
      );
    }
  });

  test('range-invalid opaque IOR preserves valid specular sibling', () {
    final result = readGlbMaterialExtensionIntent(
      _singleMaterialExtensionsGlb(<String, Object?>{
        'KHR_materials_specular': <String, Object?>{
          'specularFactor': 0.6,
          'specularColorFactor': <Object?>[0.25, 1.5, 3.0],
        },
        'KHR_materials_ior': <String, Object?>{'ior': 0.5},
      }),
      debugName: 'invalid-ior.glb',
    );
    final groups = result.patches[PartAddress(
      nodePath: const <String>['Material'],
      primitiveIndex: 0,
    )]!;

    expect(groups, isNot(contains(MaterialExtensionPatchGroup.opaqueIor)));
    expect(groups[MaterialExtensionPatchGroup.specular]!.specular, 0.6);
    expect(
      groups[MaterialExtensionPatchGroup.specular]!.specularColorFactor,
      <double>[0.25, 1.5, 3],
    );
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride);
    expect(result.diagnostics.single.details['extension'], 'KHR_materials_ior');
    expect(result.diagnostics.single.details['field'], 'ior');
  });

  test('invalid IOR does not discard valid transmission volume or sibling', () {
    for (final invalidIor in <Object?>['invalid', 0.5]) {
      final result = readGlbMaterialExtensionIntent(
        _singleMaterialExtensionsGlb(<String, Object?>{
          'KHR_materials_transmission': <String, Object?>{
            'transmissionFactor': 0.75,
          },
          'KHR_materials_volume': <String, Object?>{
            'thicknessFactor': 0.02,
            'attenuationColor': <Object?>[0.8, 0.9, 1.0],
            'attenuationDistance': 4.0,
          },
          'KHR_materials_ior': <String, Object?>{'ior': invalidIor},
          'KHR_materials_specular': <String, Object?>{
            'specularFactor': 0.6,
          },
        }),
        debugName: 'invalid-glass-ior.glb',
      );
      final groups = result.patches[PartAddress(
        nodePath: const <String>['Material'],
        primitiveIndex: 0,
      )]!;
      final transmissionVolume =
          groups[MaterialExtensionPatchGroup.transmissionVolume]!;

      expect(transmissionVolume.transmission, 0.75, reason: '$invalidIor');
      expect(transmissionVolume.thickness, 0.02, reason: '$invalidIor');
      expect(
        transmissionVolume.attenuationColor,
        <double>[0.8, 0.9, 1],
        reason: '$invalidIor',
      );
      expect(
        transmissionVolume.attenuationDistance,
        4,
        reason: '$invalidIor',
      );
      expect(transmissionVolume.ior, isNull, reason: '$invalidIor');
      expect(groups[MaterialExtensionPatchGroup.specular]!.specular, 0.6);
      expect(result.diagnostics, hasLength(1), reason: '$invalidIor');
      expect(result.diagnostics.single.code,
          ViewerDiagnosticCode.invalidMaterialOverride);
      expect(
          result.diagnostics.single.details['extension'], 'KHR_materials_ior');
      expect(result.diagnostics.single.details['field'], 'ior');
    }
  });

  test('accepts the authored IOR zero compatibility value as opaque intent',
      () {
    final result = readGlbMaterialExtensionIntent(
      _singleMaterialExtensionsGlb(<String, Object?>{
        'KHR_materials_ior': <String, Object?>{'ior': 0},
      }),
      debugName: 'ior-zero.glb',
    );
    final patch = result.patches[PartAddress(
      nodePath: const <String>['Material'],
      primitiveIndex: 0,
    )]![MaterialExtensionPatchGroup.opaqueIor]!;

    expect(result.diagnostics, isEmpty);
    expect(patch.ior, 0);
    expect(patch.hasGlassOverride, isFalse);
    expect(patch.hasOpaqueIorOverride, isTrue);
  });

  test('unsupported extension texture discards only its own group', () {
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
          <String, Object?>{'name': 'CoatedPanel', 'mesh': 0},
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
              'KHR_materials_specular': <String, Object?>{
                'specularFactor': 0.6,
                'specularTexture': <String, Object?>{'index': 0},
              },
              'KHR_materials_clearcoat': <String, Object?>{
                'clearcoatFactor': 0.8,
              },
            },
          },
        ],
      }),
    );

    final groups = result.patches[PartAddress(
      nodePath: const <String>['CoatedPanel'],
      primitiveIndex: 0,
    )]!;
    expect(groups, isNot(contains(MaterialExtensionPatchGroup.specular)));
    expect(
      groups[MaterialExtensionPatchGroup.clearcoat]!.clearcoat,
      0.8,
    );
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details['extension'],
      'KHR_materials_specular',
    );
    expect(
      result.diagnostics.single.details['reason'],
      contains('outside the glTF textures array'),
    );
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
    final textureBytes = <Uint8List>[
      Uint8List.fromList(<int>[31, 32])
    ];
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(<String, Object?>{
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
                'transmissionTexture': <String, Object?>{'index': 0},
              },
            },
          },
        ],
        'textures': <Object?>[
          <String, Object?>{'source': 0},
        ],
        'images': <Object?>[
          <String, Object?>{'mimeType': 'image/png', 'bufferView': 0},
        ],
        'bufferViews': <Object?>[
          <String, Object?>{
            'buffer': 0,
            'byteLength': textureBytes.single.length,
          },
        ],
        'buffers': <Object?>[
          <String, Object?>{'byteLength': textureBytes.single.length},
        ],
      }, textureBytes),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
    expect(result.diagnostics.single.details['uvSet'], 0);
  });

  test('reports texture slots for authored extension UV0 diagnostics', () {
    final textureBytes = <Uint8List>[
      for (var index = 0; index < 5; index += 1)
        Uint8List.fromList(<int>[40 + index]),
    ];
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(<String, Object?>{
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
                'transmissionTexture': <String, Object?>{'index': 0},
              },
              'KHR_materials_volume': <String, Object?>{
                'thicknessTexture': <String, Object?>{'index': 1},
              },
              'KHR_materials_clearcoat': <String, Object?>{
                'clearcoatTexture': <String, Object?>{'index': 2},
                'clearcoatRoughnessTexture': <String, Object?>{'index': 3},
                'clearcoatNormalTexture': <String, Object?>{'index': 4},
              },
            },
          },
        ],
        'textures': <Object?>[
          for (var index = 0; index < textureBytes.length; index += 1)
            <String, Object?>{'source': index},
        ],
        'images': <Object?>[
          for (var index = 0; index < textureBytes.length; index += 1)
            <String, Object?>{
              'mimeType': 'image/png',
              'bufferView': index,
            },
        ],
        'bufferViews': <Object?>[
          for (var index = 0, offset = 0;
              index < textureBytes.length;
              offset += textureBytes[index].length, index += 1)
            <String, Object?>{
              'buffer': 0,
              'byteOffset': offset,
              'byteLength': textureBytes[index].length,
            },
        ],
        'buffers': <Object?>[
          <String, Object?>{
            'byteLength': textureBytes.fold<int>(
              0,
              (sum, bytes) => sum + bytes.length,
            ),
          },
        ],
      }, textureBytes),
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics, hasLength(5));
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      everyElement(ViewerDiagnosticCode.missingUvSet),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['uvSet']),
      everyElement(0),
    );
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.details['textureSlot']),
      containsAll(<Object?>[
        'KHR_materials_transmission.transmissionTexture',
        'KHR_materials_volume.thicknessTexture',
        'KHR_materials_clearcoat.clearcoatTexture',
        'KHR_materials_clearcoat.clearcoatRoughnessTexture',
        'KHR_materials_clearcoat.clearcoatNormalTexture',
      ]),
    );
  });

  test('reports invalid GLB headers without throwing', () {
    final result = readGlbMaterialExtensionIntent(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      debugName: 'broken.glb',
    );

    expect(result.patches, isEmpty);
    expect(result.diagnostics.single.code, ViewerDiagnosticCode.adapterFailure);
  });

  test('JSON reader limit does not reject a larger decoded BIN chunk', () {
    final bin = Uint8List(8 * 1024 * 1024 + 4);
    final result = readGlbMaterialExtensionIntent(
      _glbWithBin(
        <String, Object?>{
          'asset': <String, Object?>{'version': '2.0'},
          'scene': 0,
          'scenes': <Object?>[
            <String, Object?>{
              'nodes': <Object?>[0],
            },
          ],
          'nodes': <Object?>[
            <String, Object?>{'name': 'LargeDecodedMesh', 'mesh': 0},
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
                'KHR_materials_specular': <String, Object?>{
                  'specularFactor': 0.8,
                },
                'KHR_materials_ior': <String, Object?>{'ior': 1.45},
              },
            },
          ],
          'buffers': <Object?>[
            <String, Object?>{'byteLength': bin.lengthInBytes},
          ],
        },
        <Uint8List>[bin],
      ),
      debugName: 'decoded-large-bin.glb',
    );

    final patchGroups = result.patches.values.single;
    expect(
      result.diagnostics.where(
        (diagnostic) => diagnostic.code == ViewerDiagnosticCode.adapterFailure,
      ),
      isEmpty,
    );
    expect(
      patchGroups[MaterialExtensionPatchGroup.specular]!.specular,
      0.8,
    );
    expect(
      patchGroups[MaterialExtensionPatchGroup.opaqueIor]!.ior,
      1.45,
    );
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

Uint8List _singleMaterialExtensionsGlb(
  Map<String, Object?> extensions,
) {
  return _glb(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <Object?>[0],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'name': 'Material', 'mesh': 0},
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
      <String, Object?>{'extensions': extensions},
    ],
  });
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

Uint8List _glbWithBin(Map<String, Object?> json, List<Uint8List> chunks) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final binLength = chunks.fold<int>(0, (sum, bytes) => sum + bytes.length);
  final paddedBinLength = _align4(binLength);
  final totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length;
      index < 20 + paddedJsonLength;
      index += 1) {
    bytes[index] = 0x20;
  }
  final binHeaderOffset = 20 + paddedJsonLength;
  data
    ..setUint32(binHeaderOffset, paddedBinLength, Endian.little)
    ..setUint32(binHeaderOffset + 4, 0x004E4942, Endian.little);
  var binOffset = binHeaderOffset + 8;
  for (final chunk in chunks) {
    bytes.setRange(binOffset, binOffset + chunk.length, chunk);
    binOffset += chunk.length;
  }
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;

final Uint8List _basisuKtx2Header = _ktx2Header(
  vkFormat: 0,
  pixelWidth: 4,
  pixelHeight: 4,
  levelCount: 1,
  supercompressionScheme: 1,
);

Uint8List _ktx2Header({
  required int vkFormat,
  required int pixelWidth,
  required int pixelHeight,
  required int levelCount,
  required int supercompressionScheme,
}) {
  final bytes = Uint8List(80);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 12, const <int>[
    0xAB,
    0x4B,
    0x54,
    0x58,
    0x20,
    0x32,
    0x30,
    0xBB,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  data
    ..setUint32(12, vkFormat, Endian.little)
    ..setUint32(16, 1, Endian.little)
    ..setUint32(20, pixelWidth, Endian.little)
    ..setUint32(24, pixelHeight, Endian.little)
    ..setUint32(36, 1, Endian.little)
    ..setUint32(40, levelCount, Endian.little)
    ..setUint32(44, supercompressionScheme, Endian.little);
  return bytes;
}
