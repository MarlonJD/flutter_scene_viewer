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
}

PartTree _treeFor(PartAddress address, {bool hasTexCoords = true}) {
  final record = PartRecord(
    address: address,
    hasTexCoords: hasTexCoords,
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
    this.materialDiagnostics = const <ViewerDiagnostic>[],
  });

  final PartTree partTree;
  final List<ViewerDiagnostic> materialDiagnostics;
  final List<MaterialCall> materialCalls = <MaterialCall>[];
  final List<PartAddress> resetCalls = <PartAddress>[];
  int renderRequests = 0;

  @override
  Future<ModelLoadResult> load(ModelSource source) async {
    return ModelLoadResult.success(partTree: partTree);
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
