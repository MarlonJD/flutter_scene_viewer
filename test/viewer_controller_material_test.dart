import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/viewer_controller.dart'
    show ViewerCommandSink;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final address = PartAddress(
    nodePath: <String>['Root', 'Body'],
    primitiveIndex: 0,
  );

  test('setPartMaterial applies a valid patch and records override state',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(metallic: 0.4),
    );

    expect(sink.materialCalls.single.address, address);
    expect(sink.materialCalls.single.patch.metallic, 0.4);
    expect(controller.materialOverrides.patchFor(address)?.metallic, 0.4);
  });

  test('setPartMaterial applies and persists alpha blend patch', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        alphaMode: MaterialAlphaMode.blend,
        alphaCutoff: 0.35,
      ),
    );

    expect(sink.materialCalls.single.patch.alphaMode, MaterialAlphaMode.blend);
    expect(sink.materialCalls.single.patch.alphaCutoff, 0.35);
    expect(controller.materialOverrides.patchFor(address)?.alphaMode,
        MaterialAlphaMode.blend);
    expect(controller.materialOverrides.patchFor(address)?.alphaCutoff, 0.35);
  });

  test('alpha mask patch remains material alpha and not visibility', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(alphaMode: MaterialAlphaMode.mask),
    );

    expect(sink.materialCalls.single.patch.alphaMode, MaterialAlphaMode.mask);
    expect(sink.materialCalls.single.patch.visible, isNull);
    expect(controller.materialOverrides.patchFor(address)?.alphaMode,
        MaterialAlphaMode.mask);
    expect(controller.materialOverrides.patchFor(address)?.visible, isNull);
  });

  test('effect mask patch remains material data and not visibility', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        effectMask: MaterialEffectMask(
          texture: TextureSource.asset('assets/masks/material_mask.png'),
          channels: <MaterialMaskChannel, MaterialEffectTarget>{
            MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
          },
        ),
      ),
    );

    expect(sink.materialCalls.single.patch.effectMask, isNotNull);
    expect(sink.materialCalls.single.patch.visible, isNull);
  });

  test('setPartMaterial records diagnostics for invalid factor values',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(metallic: -0.2),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride);
  });

  test('setPartMaterial records diagnostics for invalid alpha cutoff',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(alphaCutoff: -0.1),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride);
    expect(controller.diagnostics.single.details['field'], 'alphaCutoff');
  });

  test('setPartMaterial reports unsupported alpha mask for unlit materials',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(
        address,
        materialShadingMode: MaterialShadingMode.unlit,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(alphaMode: MaterialAlphaMode.mask),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(controller.diagnostics.single.details['alphaMode'], 'mask');
    expect(
        controller.diagnostics.single.details['materialShadingMode'], 'unlit');
  });

  test('setPartMaterial reports missing UVs for effect mask', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address, hasTexCoords: false));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        effectMask: MaterialEffectMask(
          texture: TextureSource.asset('assets/masks/material_mask.png'),
          channels: <MaterialMaskChannel, MaterialEffectTarget>{
            MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
          },
        ),
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(
        controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
  });

  test('setPartMaterial rejects effect mask with alpha blend before adapter',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        alphaMode: MaterialAlphaMode.blend,
        effectMask: MaterialEffectMask(
          texture: TextureSource.asset('assets/masks/material_mask.png'),
          channels: <MaterialMaskChannel, MaterialEffectTarget>{
            MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
          },
        ),
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(controller.diagnostics.single.details['feature'], 'effectMask');
  });

  test('setPartMaterial records unsupported effect mask sink diagnostic',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialDiagnostics: const <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Effect masks require an opaque-family shader backend.',
          details: <String, Object?>{'feature': 'effectMask'},
        ),
      ],
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        effectMask: MaterialEffectMask(
          texture: TextureSource.asset('assets/masks/material_mask.png'),
          channels: <MaterialMaskChannel, MaterialEffectTarget>{
            MaterialMaskChannel.red: MaterialEffectTarget.paintRegion,
          },
        ),
      ),
    );

    expect(sink.materialCalls.single.patch.effectMask, isNotNull);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
  });

  test('setPartMaterial rejects glass fields without storing override',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(transmission: 1.0, ior: 1.45),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
  });

  test('experimental transmission support allows glass intent to reach sink',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialExtensionSupport: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(transmission: 1.0, ior: 1.45, thickness: 0.02),
    );

    expect(sink.materialCalls.single.patch.transmission, 1.0);
    expect(controller.materialOverrides.patchFor(address)?.transmission, 1.0);
  });

  test('experimental transmission support still rejects clearcoat by default',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialExtensionSupport: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 1.0),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(controller.diagnostics.single.details['extensions'],
        contains('KHR_materials_clearcoat'));
  });

  test('experimental clearcoat support allows clearcoat intent to reach sink',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialExtensionSupport: const MaterialExtensionSupport(
        clearcoat: true,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 1.0, clearcoatRoughness: 0.12),
    );

    expect(sink.materialCalls.single.patch.clearcoat, 1.0);
    expect(controller.materialOverrides.patchFor(address)?.clearcoat, 1.0);
  });

  test('setPartMaterial rejects clearcoat fields without storing override',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        clearcoat: 1.0,
        clearcoatRoughness: 0.2,
        clearcoatNormalScale: 0.75,
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(controller.diagnostics.single.details['extensions'],
        contains('KHR_materials_clearcoat'));
  });

  test('setPartTexture reports missing UVs without applying texture', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address, hasTexCoords: false));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartTexture(
      address,
      const TextureSource.asset('assets/albedo.png'),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(
        controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
  });

  test('setPartMaterial reports missing UVs for normal texture override',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address, hasTexCoords: false));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        normalTexture: TextureSource.asset('assets/normal.png'),
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(
        controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
  });

  test(
      'runtime production clearcoat texture patch is not persisted without UV0',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address, hasTexCoords: false),
      materialExtensionSupport: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
        clearcoat: true,
        backendKind: MaterialExtensionBackendKind.rendererNative,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        clearcoatTexture: TextureSource.asset('assets/clearcoat.png'),
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(
        controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
    expect(controller.diagnostics.single.details['textureSlots'],
        <String>['clearcoatTexture']);
  });

  test('setPartTexture applies texture when UVs exist', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartTexture(
      address,
      const TextureSource.asset('assets/albedo.png'),
    );

    expect(sink.materialCalls.single.patch.baseColorTexture,
        isA<AssetTextureSource>());
    expect(controller.materialOverrides.patchFor(address)?.baseColorTexture,
        isA<AssetTextureSource>());
  });

  test('setPartMaterial records sink diagnostics without storing patch',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialDiagnostics: const <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedMaterialFeature,
          message: 'Unsupported material.',
        ),
      ],
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(metallic: 0.4),
    );

    expect(sink.materialCalls.single.address, address);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
  });

  test('resetPart restores adapter state and removes stored override',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));
    await controller.setPartMaterial(
      address,
      const MaterialPatch(roughness: 0.6),
    );

    await controller.resetPart(address);

    expect(sink.resetCalls, <PartAddress>[address]);
    expect(controller.materialOverrides.patchFor(address), isNull);
  });

  test('applyMaterialOverrides reapplies persisted snapshot', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));
    final snapshot = MaterialOverrideSnapshot(
      patches: <PartAddress, MaterialPatch>{
        address: const MaterialPatch(roughness: 0.7),
      },
    );

    await controller.applyMaterialOverrides(snapshot);

    expect(sink.materialCalls.single.patch.roughness, 0.7);
    expect(controller.materialOverrides.patchFor(address)?.roughness, 0.7);
  });

  test('load records unsupported diagnostics for authored glass by default',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      authoredMaterialPatches: <PartAddress, MaterialPatch>{
        address: const MaterialPatch(transmission: 1.0, ior: 1.45),
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
  });

  test(
      'load sends supported authored glass to sink without persisting override',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialExtensionSupport: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
      ),
      authoredMaterialPatches: <PartAddress, MaterialPatch>{
        address: const MaterialPatch(
          transmission: 1.0,
          ior: 1.45,
          thickness: 0.02,
        ),
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(sink.materialCalls.single.patch.transmission, 1.0);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics, isEmpty);
  });

  test('load records authored missing UV diagnostics', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      loadDiagnostics: <ViewerDiagnostic>[
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.missingUvSet,
          message: 'Authored material extension texture requires TEXCOORD_0.',
          details: <String, Object?>{'part': address.debugPath, 'uvSet': 0},
        ),
      ],
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(
        controller.diagnostics.single.code, ViewerDiagnosticCode.missingUvSet);
    expect(controller.materialOverrides.patchFor(address), isNull);
  });
}

PartTree _treeFor(
  PartAddress address, {
  bool hasTexCoords = true,
  MaterialShadingMode materialShadingMode = MaterialShadingMode.lit,
}) {
  final record = PartRecord(
    address: address,
    hasTexCoords: hasTexCoords,
    materialShadingMode: materialShadingMode,
  );
  return PartTree(
    root: PartNode(
      name: address.nodePath.first,
      nodePath: <String>[address.nodePath.first],
      records: <PartRecord>[record],
    ),
    records: <PartRecord>[record],
  );
}

final class MaterialCall {
  const MaterialCall(this.address, this.patch);

  final PartAddress address;
  final MaterialPatch patch;
}

final class MaterialSink implements ViewerCommandSink {
  MaterialSink({
    required this.partTree,
    this.loadDiagnostics = const <ViewerDiagnostic>[],
    this.materialDiagnostics = const <ViewerDiagnostic>[],
    this.materialExtensionSupport = MaterialExtensionSupport.unsupported,
    this.authoredMaterialPatches = const <PartAddress, MaterialPatch>{},
  });

  final PartTree partTree;
  final List<ViewerDiagnostic> loadDiagnostics;
  final List<ViewerDiagnostic> materialDiagnostics;
  @override
  final MaterialExtensionSupport materialExtensionSupport;
  final Map<PartAddress, MaterialPatch> authoredMaterialPatches;
  final List<MaterialCall> materialCalls = <MaterialCall>[];
  final List<PartAddress> resetCalls = <PartAddress>[];
  int renderRequests = 0;

  @override
  Future<ModelLoadResult> load(ModelSource source) async {
    return ModelLoadResult.success(
      diagnostics: loadDiagnostics,
      partTree: partTree,
      authoredMaterialPatches: authoredMaterialPatches,
    );
  }

  @override
  Future<void> fitCamera() async {}

  @override
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) async {}

  @override
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) async {}

  @override
  void requestRenderFrame() {
    renderRequests += 1;
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) async {
    resetCalls.add(address);
    return const <ViewerDiagnostic>[];
  }

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) async {
    materialCalls.add(MaterialCall(address, patch));
    return materialDiagnostics;
  }
}
