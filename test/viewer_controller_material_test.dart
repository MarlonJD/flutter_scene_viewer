import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_backend.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_material.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_material_extension_backend.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_patch_group.dart';
import 'package:flutter_scene_viewer/src/model_loader.dart';
import 'package:flutter_scene_viewer/src/viewer_controller.dart'
    show ViewerCommandSink;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

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

  test('setPartMaterial keeps mixed public patches atomic', () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(partTree: _treeFor(address));
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        baseColorTexture: TextureSource.asset('assets/albedo.png'),
        specular: 0.6,
      ),
    );

    expect(sink.materialCalls, isEmpty);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(
      controller.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
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
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
        },
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
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
        },
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
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.clearcoat},
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
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
          MaterialExtensionFeature.clearcoat,
        },
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

  test('setPartTextureBinding routes every explicit material slot', () async {
    for (final slot in MaterialTextureSlot.values) {
      final controller = FlutterSceneViewerController();
      final sink = MaterialSink(
        partTree: _treeFor(address),
        materialExtensionSupport: _materialExtensionSupport(
          MaterialExtensionFeature.values.toSet(),
        ),
      );
      controller.attach(sink);
      await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));
      final binding = MaterialTextureBinding(
        source: TextureSource.asset('assets/${slot.name}.png'),
      );

      await controller.setPartTextureBinding(address, slot, binding);

      expect(sink.materialCalls, hasLength(1), reason: slot.name);
      final patch = sink.materialCalls.single.patch;
      expect(
        _bindingFields(patch)[slot],
        same(binding),
        reason: slot.name,
      );
      expect(
        _bindingFields(patch).values.whereType<MaterialTextureBinding>(),
        hasLength(1),
        reason: slot.name,
      );
    }
  });

  test(
      'extended PBR contract unavailability leaves material persistence and render count unchanged',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.35
      ..roughnessFactor = 0.65;
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: MaterialExtensionSupport.unsupported,
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        extendedPbrBackend: FlutterSceneExtendedPbrBackend(
          loadShader: (_, __) async => null,
        ),
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartTextureBinding(
      address,
      MaterialTextureSlot.baseColor,
      MaterialTextureBinding(
        source: TextureSource.bytes(
          Uint8List.fromList(<int>[1, 2, 3]),
          debugName: 'red-contract',
        ),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      ),
    );

    expect(controller.diagnostics, hasLength(1));
    expect(
      controller.diagnostics.single.details['limitation'],
      'extendedPbrShaderUnavailable',
    );
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(sink.renderRequests, 0);
    expect(body.mesh!.primitives.single.material, same(material));
    expect(material.metallicFactor, 0.35);
    expect(material.roughnessFactor, 0.65);
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
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.transmissionVolume:
              const MaterialPatch(transmission: 1.0, ior: 1.45),
        },
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
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
        },
      ),
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.transmissionVolume: const MaterialPatch(
            transmission: 1.0,
            ior: 1.45,
            thickness: 0.02,
          ),
        },
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(sink.materialCalls.single.patch.transmission, 1.0);
    expect(controller.materialOverrides.patchFor(address), isNull);
    expect(controller.diagnostics, isEmpty);
  });

  test('unsupported authored specular and IOR do not block imported core',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      authoredCoreMaterialPatches: <PartAddress, MaterialPatch>{
        address: const MaterialPatch(
          baseColorTexture: TextureSource.asset('assets/albedo.png'),
          normalTexture: TextureSource.asset('assets/normal.png'),
        ),
      },
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.opaqueIor: const MaterialPatch(ior: 1.45),
          MaterialExtensionPatchGroup.specular:
              const MaterialPatch(specular: 0.6),
        },
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(sink.materialCalls, hasLength(1));
    expect(sink.materialCalls.single.patch.baseColorTexture, isNotNull);
    expect(sink.materialCalls.single.patch.normalTexture, isNotNull);
    final extensionDetails = controller.diagnostics
        .map((diagnostic) => diagnostic.details['extensions']);
    expect(extensionDetails, anyElement(contains('KHR_materials_ior')));
    expect(extensionDetails, anyElement(contains('KHR_materials_specular')));
  });

  test('unsupported authored specular does not block clearcoat or opaque IOR',
      () async {
    final controller = FlutterSceneViewerController();
    final sink = MaterialSink(
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.clearcoat,
        },
      ),
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.opaqueIor: const MaterialPatch(ior: 1.45),
          MaterialExtensionPatchGroup.specular:
              const MaterialPatch(specular: 0.6),
          MaterialExtensionPatchGroup.clearcoat:
              const MaterialPatch(clearcoat: 0.9),
        },
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    expect(sink.materialCalls, hasLength(2));
    expect(sink.materialCalls.first.patch.ior, 1.45);
    expect(sink.materialCalls.last.patch.ior, isNull);
    expect(sink.materialCalls.last.patch.clearcoat, 0.9);
    expect(sink.materialCalls.last.patch.specular, isNull);
    expect(controller.diagnostics, hasLength(1));
    expect(
      controller.diagnostics.single.details['extensions'],
      contains('KHR_materials_specular'),
    );
  });

  test('unavailable extended shader rejects opaque IOR atomically', () async {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders();

    for (final ior in <double>[0, 1.45]) {
      final material = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.3
        ..roughnessFactor = 0.7;
      final body = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
      );
      final root = flutter_scene.Node(name: 'Root')..children.add(body);
      final controller = FlutterSceneViewerController();
      final sink = AdapterMaterialSink(
        root: root,
        partTree: _treeFor(address),
        materialExtensionSupport: policy.support,
        authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
        authoredExtensionMaterialPatches: const <PartAddress,
            Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
        materialExtensionPolicy: policy,
        runtimeAdapter: FlutterSceneRuntimeAdapter(
          materialExtensionPolicy: policy,
          extendedPbrBackend: FlutterSceneExtendedPbrBackend(
            loadShader: (_, __) async => null,
          ),
        ),
      );
      controller.attach(sink);
      await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

      await controller.setPartMaterial(address, MaterialPatch(ior: ior));

      expect(controller.diagnostics, hasLength(1), reason: '$ior');
      expect(
        controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature,
        reason: '$ior',
      );
      expect(
        controller.diagnostics.single.details['limitation'],
        'extendedPbrShaderUnavailable',
        reason: '$ior',
      );
      expect(controller.materialOverrides.patchFor(address), isNull);
      expect(sink.renderRequests, 0);
      expect(body.mesh!.primitives.single.material, same(material));
      expect(material.metallicFactor, 0.3);
      expect(material.roughnessFactor, 0.7);
    }
  });

  test('renderer-native material keeps the opaque IOR application path',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.ior},
        backendKind: MaterialExtensionBackendKind.rendererNative,
      ),
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(ior: 1.45),
    );

    expect(controller.diagnostics, isEmpty);
    final applied = body.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(applied, isNot(same(material)));
    expect(applied.ior, 1.45);
    expect(controller.materialOverrides.patchFor(address)?.ior, 1.45);
    expect(sink.renderRequests, 1);
  });

  test('failed native texture load preserves live and persisted glass state',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final textureFactory = _ControllerTextureFactory(
      assetFailure: StateError('expected texture load failure'),
    );
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy: policy,
      textureFactory: textureFactory,
    );
    final support = _materialExtensionSupport(
      const <MaterialExtensionFeature>{
        MaterialExtensionFeature.transmission,
        MaterialExtensionFeature.ior,
        MaterialExtensionFeature.volume,
        MaterialExtensionFeature.clearcoat,
      },
      backendKind: MaterialExtensionBackendKind.rendererNative,
    );
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: support,
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: runtimeAdapter,
      materialExtensionPolicy: policy,
    );
    final controller = FlutterSceneViewerController()..attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(transmission: 0.6, ior: 1.4),
    );
    final liveAfterSuccess = body.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(liveAfterSuccess.transmissionFactor, 0.6);
    expect(controller.materialOverrides.patchFor(address)?.transmission, 0.6);
    expect(sink.renderRequests, 1);

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        transmission: 0.9,
        transmissionTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/failing.png'),
        ),
      ),
    );

    expect(controller.diagnostics, hasLength(1));
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.assetLoadFailure);
    expect(body.mesh!.primitives.single.material, same(liveAfterSuccess));
    expect(liveAfterSuccess.transmissionFactor, 0.6);
    final persisted = controller.materialOverrides.patchFor(address)!;
    expect(persisted.transmission, 0.6);
    expect(persisted.ior, 1.4);
    expect(persisted.transmissionTextureBinding, isNull);
    expect(sink.renderRequests, 1);
  });

  test('automatic extended PBR stores specular IOR only after replacement',
      () async {
    final source = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.25
      ..roughnessFactor = 0.75;
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), source),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final backend = _ControllerExtendedPbrBackend();
    final support = _materialExtensionSupport(
      const <MaterialExtensionFeature>{
        MaterialExtensionFeature.specular,
        MaterialExtensionFeature.ior,
      },
      backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
    );
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: support,
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        extendedPbrBackend: backend,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(
        specular: 0.6,
        specularColorFactor: <double>[1.2, 0.8, 0.4],
        ior: 1.45,
      ),
    );

    expect(controller.diagnostics, isEmpty);
    expect(backend.configs, hasLength(1));
    expect(backend.configs.single.specularFactor, 0.6);
    expect(backend.configs.single.ior, 1.45);
    expect(body.mesh!.primitives.single.material, same(backend.created.single));
    expect(controller.materialOverrides.patchFor(address)?.specular, 0.6);
    expect(controller.materialOverrides.patchFor(address)?.ior, 1.45);
    expect(sink.renderRequests, 1);
  });

  test('authored groups reach the renderer-native adapter independently',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final originalMesh = body.mesh!;
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.clearcoat,
        },
        backendKind: MaterialExtensionBackendKind.rendererNative,
      ),
      authoredCoreMaterialPatches: <PartAddress, MaterialPatch>{
        address: MaterialPatch(
          baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
          roughness: 0.65,
          alphaMode: MaterialAlphaMode.mask,
          alphaCutoff: 0.35,
        ),
      },
      authoredExtensionMaterialPatches: <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{
        address: <MaterialExtensionPatchGroup, MaterialPatch>{
          MaterialExtensionPatchGroup.specular:
              const MaterialPatch(specular: 0.6),
          MaterialExtensionPatchGroup.clearcoat:
              const MaterialPatch(clearcoat: 0.8),
          MaterialExtensionPatchGroup.transmissionVolume:
              const MaterialPatch(transmission: 0.9, ior: 1.45),
        },
      },
    );
    controller.attach(sink);

    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    final applied = body.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(applied.baseColorFactor.x, closeTo(0.2, 0.0001));
    expect(applied.baseColorFactor.y, closeTo(0.3, 0.0001));
    expect(applied.baseColorFactor.z, closeTo(0.4, 0.0001));
    expect(applied.roughnessFactor, closeTo(0.65, 0.0001));
    expect(body.mesh, isNot(same(originalMesh)));
    expect(applied, isNot(same(material)));
    expect(applied.alphaMode, flutter_scene.AlphaMode.mask);
    expect(applied.alphaCutoff, closeTo(0.35, 0.0001));
    expect(applied.clearcoatFactor, closeTo(0.8, 0.0001));
    expect(applied.transmissionFactor, closeTo(0.9, 0.0001));
    expect(applied.ior, closeTo(1.45, 0.0001));
    expect(controller.diagnostics, hasLength(1));
    expect(
      controller.diagnostics.single.details['extensions'],
      contains('KHR_materials_specular'),
    );
  });

  test('resetPart restores model normal after clearcoat zero retains delta',
      () async {
    final modelNormal = _ControllerTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final factory = _ControllerTextureFactory();
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (_) async =>
          flutter_scene.ShaderMaterial(isOpaqueOverride: true),
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.clearcoat},
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: runtimeAdapter,
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('normal-b'),
        ),
        normalScale: 0.5,
      ),
    );
    expect(
      controller.diagnostics,
      isEmpty,
      reason: controller.diagnostics
          .map((diagnostic) => <String, Object?>{
                'code': diagnostic.code.name,
                'message': diagnostic.message,
                'details': diagnostic.details,
              })
          .toList()
          .toString(),
    );
    final normalB = factory.createdSources.single;
    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 0.0),
    );

    // ignore: invalid_use_of_internal_member
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    await controller.resetPart(address);

    // ignore: invalid_use_of_internal_member
    expect(material.normalTextureSource, same(modelNormal));
    expect(material.normalScale, closeTo(0.8, 0.0001));
    expect(controller.materialOverrides.patchFor(address), isNull);
  });

  test('sparse clearcoat deltas preserve live config and persisted intent',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final factory = _ControllerTextureFactory();
    final configs = <FlutterSceneClearcoatMaterialConfig>[];
    final overlays = <flutter_scene.ShaderMaterial>[];
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (config) async {
        configs.add(config);
        final overlay = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
        overlays.add(overlay);
        return overlay;
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.clearcoat},
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: runtimeAdapter,
    );
    final factorBinding = MaterialTextureBinding(
      source: const TextureSource.asset('clearcoat-factor'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.clampToEdge,
        wrapT: TextureWrapMode.clampToEdge,
        magFilter: TextureMagFilter.nearest,
        minFilter: TextureMinFilter.nearest,
      ),
    );
    final roughnessBinding = MaterialTextureBinding(
      source: const TextureSource.asset('clearcoat-roughness'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.mirroredRepeat,
        wrapT: TextureWrapMode.mirroredRepeat,
        magFilter: TextureMagFilter.linear,
        minFilter: TextureMinFilter.linearMipmapLinear,
      ),
    );
    final normalBinding = MaterialTextureBinding(
      source: const TextureSource.asset('clearcoat-normal'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.repeat,
        wrapT: TextureWrapMode.repeat,
        magFilter: TextureMagFilter.linear,
        minFilter: TextureMinFilter.linear,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        clearcoat: 0.8,
        clearcoatRoughness: 0.25,
        clearcoatNormalScale: 0.7,
        clearcoatTextureBinding: factorBinding,
        clearcoatRoughnessTextureBinding: roughnessBinding,
        clearcoatNormalTextureBinding: normalBinding,
      ),
    );
    final factorTexture = factory.createdSources[0];
    final roughnessTexture = factory.createdSources[1];
    final normalTexture = factory.createdSources[2];

    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 0.0),
    );
    final zeroConfig = configs.last;
    final zeroParams = overlays.last.getUniformBlock('MaterialParams')!;

    expect(zeroConfig.patch.clearcoat, 0.0);
    expect(zeroConfig.patch.clearcoatRoughness, 0.25);
    expect(zeroConfig.patch.clearcoatNormalScale, 0.7);
    expect(zeroConfig.clearcoatTexture, same(factorTexture));
    expect(zeroConfig.clearcoatRoughnessTexture, same(roughnessTexture));
    expect(zeroConfig.clearcoatNormalTexture, same(normalTexture));
    expect(zeroParams.getFloat32(24, Endian.host), closeTo(0.0, 0.0001));
    expect(zeroParams.getFloat32(28, Endian.host), closeTo(0.25, 0.0001));
    expect(zeroParams.getFloat32(36, Endian.host), closeTo(0.7, 0.0001));
    expect(zeroParams.getFloat32(40, Endian.host), closeTo(1.0, 0.0001));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 0.6),
    );

    expect(controller.diagnostics, isEmpty);
    final persisted = controller.materialOverrides.patchFor(address)!;
    final positiveConfig = configs.last;
    final positiveParams = overlays.last.getUniformBlock('MaterialParams')!;
    expect(persisted.clearcoat, 0.6);
    expect(persisted.clearcoatRoughness, 0.25);
    expect(persisted.clearcoatNormalScale, 0.7);
    expect(persisted.clearcoatTextureBinding, same(factorBinding));
    expect(persisted.clearcoatRoughnessTextureBinding, same(roughnessBinding));
    expect(persisted.clearcoatNormalTextureBinding, same(normalBinding));
    expect(positiveConfig.patch.clearcoat, persisted.clearcoat);
    expect(
        positiveConfig.patch.clearcoatRoughness, persisted.clearcoatRoughness);
    expect(positiveConfig.patch.clearcoatNormalScale,
        persisted.clearcoatNormalScale);
    expect(positiveConfig.clearcoatTexture, same(factorTexture));
    expect(positiveConfig.clearcoatRoughnessTexture, same(roughnessTexture));
    expect(positiveConfig.clearcoatNormalTexture, same(normalTexture));
    expect(
      factorTexture.sampledSampler.widthAddressMode,
      flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
    );
    expect(
      roughnessTexture.sampledSampler.widthAddressMode,
      flutter_scene_internal_gpu.SamplerAddressMode.mirror,
    );
    expect(
      normalTexture.sampledSampler.widthAddressMode,
      flutter_scene_internal_gpu.SamplerAddressMode.repeat,
    );
    expect(positiveParams.getFloat32(24, Endian.host), closeTo(0.6, 0.0001));
    expect(positiveParams.getFloat32(28, Endian.host), closeTo(0.25, 0.0001));
    expect(positiveParams.getFloat32(36, Endian.host), closeTo(0.7, 0.0001));
    expect(positiveParams.getFloat32(40, Endian.host), closeTo(1.0, 0.0001));
    expect(body.mesh!.primitives.last.material, same(overlays.last));
  });

  test('active clearcoat composes base alpha and occlusion core deltas',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final factory = _ControllerTextureFactory();
    final configs = <FlutterSceneClearcoatMaterialConfig>[];
    final overlays = <flutter_scene.ShaderMaterial>[];
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (config) async {
        configs.add(config);
        final overlay = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
        overlays.add(overlay);
        return overlay;
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.clearcoat},
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: runtimeAdapter,
    );
    final baseA = MaterialTextureBinding(
      source: const TextureSource.asset('base-a'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.clampToEdge,
        wrapT: TextureWrapMode.clampToEdge,
      ),
    );
    final occlusionO1 = MaterialTextureBinding(
      source: const TextureSource.asset('occlusion-o1'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.mirroredRepeat,
        wrapT: TextureWrapMode.mirroredRepeat,
      ),
    );
    final baseB = MaterialTextureBinding(
      source: const TextureSource.asset('base-b'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.repeat,
        wrapT: TextureWrapMode.repeat,
      ),
    );
    final occlusionO2 = MaterialTextureBinding(
      source: const TextureSource.asset('occlusion-o2'),
      sampler: const TextureSampler(
        wrapS: TextureWrapMode.clampToEdge,
        wrapT: TextureWrapMode.clampToEdge,
      ),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        baseColorFactor: const <double>[0.1, 0.2, 0.3, 0.4],
        baseColorTextureBinding: baseA,
        occlusionTextureBinding: occlusionO1,
        clearcoat: 0.8,
      ),
    );
    expect(controller.diagnostics, isEmpty);
    final baseATexture = factory.createdSources[0];
    final occlusionO1Texture = factory.createdSources[1];

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        baseColorFactor: const <double>[0.6, 0.5, 0.4, 0.35],
        baseColorTextureBinding: baseB,
        occlusionTextureBinding: occlusionO2,
      ),
    );

    expect(controller.diagnostics, isEmpty);
    expect(configs, hasLength(2));
    final baseBTexture = factory.createdSources[2];
    final occlusionO2Texture = factory.createdSources[3];
    final replacementConfig = configs.last;
    final replacementParams = overlays.last.getUniformBlock('MaterialParams')!;
    expect(replacementConfig.patch.clearcoat, 0.8);
    expect(replacementConfig.patch.baseColorFactor,
        const <double>[0.6, 0.5, 0.4, 0.35]);
    expect(replacementConfig.baseColorTexture, same(baseBTexture));
    expect(replacementConfig.occlusionTexture, same(occlusionO2Texture));
    expect(
        replacementParams.getFloat32(12, Endian.host), closeTo(0.35, 0.0001));

    final liveBase = body.mesh!.primitives.first.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(liveBase.baseColorFactor, vm.Vector4(0.6, 0.5, 0.4, 0.35));
    // ignore: invalid_use_of_internal_member
    expect(liveBase.baseColorTextureSource, same(baseBTexture));
    // ignore: invalid_use_of_internal_member
    expect(liveBase.occlusionTextureSource, same(occlusionO2Texture));
    expect(body.mesh!.primitives.last.material, same(overlays.last));

    final persisted = controller.materialOverrides.patchFor(address)!;
    expect(persisted.clearcoat, 0.8);
    expect(persisted.baseColorFactor, const <double>[0.6, 0.5, 0.4, 0.35]);
    expect(persisted.baseColorTextureBinding, same(baseB));
    expect(persisted.occlusionTextureBinding, same(occlusionO2));

    await controller.setPartMaterial(
      address,
      const MaterialPatch(clearcoat: 0.6),
    );

    expect(configs, hasLength(3));
    expect(configs.last.patch.clearcoat, 0.6);
    expect(configs.last.patch.baseColorFactor,
        const <double>[0.6, 0.5, 0.4, 0.35]);
    expect(configs.last.baseColorTexture, same(baseBTexture));
    expect(configs.last.occlusionTexture, same(occlusionO2Texture));
    expect(
        overlays.last.getUniformBlock('MaterialParams')!.getFloat32(
              12,
              Endian.host,
            ),
        closeTo(0.35, 0.0001));
    final finalPersisted = controller.materialOverrides.patchFor(address)!;
    expect(finalPersisted.baseColorTextureBinding, same(baseB));
    expect(finalPersisted.occlusionTextureBinding, same(occlusionO2));
    expect(baseATexture, isNot(same(baseBTexture)));
    expect(occlusionO1Texture, isNot(same(occlusionO2Texture)));
  });

  test('active clearcoat core input reconfiguration failure stays atomic',
      () async {
    final material = flutter_scene.PhysicallyBasedMaterial();
    final body = flutter_scene.Node(
      name: 'Body',
      mesh: flutter_scene.Mesh(_AdapterUvGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Root')..children.add(body);
    final factory = _ControllerTextureFactory();
    var createCalls = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (_) async {
        createCalls += 1;
        if (createCalls == 2) {
          throw StateError('replacement unavailable');
        }
        return flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final controller = FlutterSceneViewerController();
    final sink = AdapterMaterialSink(
      root: root,
      partTree: _treeFor(address),
      materialExtensionSupport: _materialExtensionSupport(
        const <MaterialExtensionFeature>{MaterialExtensionFeature.clearcoat},
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      ),
      authoredCoreMaterialPatches: const <PartAddress, MaterialPatch>{},
      authoredExtensionMaterialPatches: const <PartAddress,
          Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
      runtimeAdapter: runtimeAdapter,
    );
    final baseA = MaterialTextureBinding(
      source: const TextureSource.asset('base-a'),
    );
    final occlusionO1 = MaterialTextureBinding(
      source: const TextureSource.asset('occlusion-o1'),
    );
    final baseB = MaterialTextureBinding(
      source: const TextureSource.asset('base-b'),
    );
    final occlusionO2 = MaterialTextureBinding(
      source: const TextureSource.asset('occlusion-o2'),
    );
    controller.attach(sink);
    await controller.load(ModelSource.bytes(Uint8List.fromList(<int>[1])));

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        baseColorFactor: const <double>[0.1, 0.2, 0.3, 0.4],
        baseColorTextureBinding: baseA,
        occlusionTextureBinding: occlusionO1,
        clearcoat: 0.8,
      ),
    );
    expect(controller.diagnostics, isEmpty);
    final liveBase = body.mesh!.primitives.first.material
        as flutter_scene.PhysicallyBasedMaterial;
    final originalOverlay = body.mesh!.primitives.last.material;
    final baseATexture = factory.createdSources[0];
    final occlusionO1Texture = factory.createdSources[1];

    await controller.setPartMaterial(
      address,
      MaterialPatch(
        baseColorFactor: const <double>[0.6, 0.5, 0.4, 0.35],
        baseColorTextureBinding: baseB,
        occlusionTextureBinding: occlusionO2,
      ),
    );

    expect(controller.diagnostics, hasLength(1));
    expect(controller.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(controller.diagnostics.single.details['feature'], 'clearcoat');
    expect(
        controller.diagnostics.single.details['status'], 'shaderUnavailable');
    expect(body.mesh!.primitives.first.material, same(liveBase));
    expect(body.mesh!.primitives.last.material, same(originalOverlay));
    expect(liveBase.baseColorFactor, vm.Vector4(0.1, 0.2, 0.3, 0.4));
    // ignore: invalid_use_of_internal_member
    expect(liveBase.baseColorTextureSource, same(baseATexture));
    // ignore: invalid_use_of_internal_member
    expect(liveBase.occlusionTextureSource, same(occlusionO1Texture));
    final persisted = controller.materialOverrides.patchFor(address)!;
    expect(persisted.clearcoat, 0.8);
    expect(persisted.baseColorFactor, const <double>[0.1, 0.2, 0.3, 0.4]);
    expect(persisted.baseColorTextureBinding, same(baseA));
    expect(persisted.occlusionTextureBinding, same(occlusionO1));
    expect(factory.createdSources, hasLength(4));
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

Map<MaterialTextureSlot, MaterialTextureBinding?> _bindingFields(
  MaterialPatch patch,
) {
  return <MaterialTextureSlot, MaterialTextureBinding?>{
    MaterialTextureSlot.baseColor: patch.baseColorTextureBinding,
    MaterialTextureSlot.metallicRoughness:
        patch.metallicRoughnessTextureBinding,
    MaterialTextureSlot.normal: patch.normalTextureBinding,
    MaterialTextureSlot.occlusion: patch.occlusionTextureBinding,
    MaterialTextureSlot.emissive: patch.emissiveTextureBinding,
    MaterialTextureSlot.transmission: patch.transmissionTextureBinding,
    MaterialTextureSlot.thickness: patch.thicknessTextureBinding,
    MaterialTextureSlot.clearcoat: patch.clearcoatTextureBinding,
    MaterialTextureSlot.clearcoatRoughness:
        patch.clearcoatRoughnessTextureBinding,
    MaterialTextureSlot.clearcoatNormal: patch.clearcoatNormalTextureBinding,
    MaterialTextureSlot.specular: patch.specularTextureBinding,
    MaterialTextureSlot.specularColor: patch.specularColorTextureBinding,
  };
}

MaterialExtensionSupport _materialExtensionSupport(
  Set<MaterialExtensionFeature> availableFeatures, {
  MaterialExtensionBackendKind backendKind =
      MaterialExtensionBackendKind.packageLocalCandidate,
}) {
  return MaterialExtensionSupport(
    backendKind: backendKind,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      for (final feature in availableFeatures)
        feature: MaterialExtensionFeatureSupport(available: true),
    },
  );
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
    this.authoredCoreMaterialPatches = const <PartAddress, MaterialPatch>{},
    this.authoredExtensionMaterialPatches =
        const <PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>{},
  });

  final PartTree partTree;
  final List<ViewerDiagnostic> loadDiagnostics;
  final List<ViewerDiagnostic> materialDiagnostics;
  @override
  final MaterialExtensionSupport materialExtensionSupport;
  final Map<PartAddress, MaterialPatch> authoredCoreMaterialPatches;
  final Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>
      authoredExtensionMaterialPatches;
  final List<MaterialCall> materialCalls = <MaterialCall>[];
  final List<PartAddress> resetCalls = <PartAddress>[];
  int renderRequests = 0;

  @override
  Future<ModelLoadResult> load(
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) async {
    return ModelLoadResult.success(
      diagnostics: loadDiagnostics,
      partTree: partTree,
      authoredCoreMaterialPatches: authoredCoreMaterialPatches,
      authoredExtensionMaterialPatches: authoredExtensionMaterialPatches,
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

final class AdapterMaterialSink implements ViewerCommandSink {
  AdapterMaterialSink({
    required this.root,
    required this.partTree,
    required this.materialExtensionSupport,
    required this.authoredCoreMaterialPatches,
    required this.authoredExtensionMaterialPatches,
    this.runtimeAdapter,
    this.materialExtensionPolicy =
        const ViewerMaterialExtensionPolicy.productionShaders(),
  });

  final flutter_scene.Node root;
  final PartTree partTree;
  @override
  final MaterialExtensionSupport materialExtensionSupport;
  final Map<PartAddress, MaterialPatch> authoredCoreMaterialPatches;
  final Map<PartAddress, Map<MaterialExtensionPatchGroup, MaterialPatch>>
      authoredExtensionMaterialPatches;
  final FlutterSceneRuntimeAdapter? runtimeAdapter;
  final ViewerMaterialExtensionPolicy materialExtensionPolicy;
  int renderRequests = 0;

  @override
  Future<ModelLoadResult> load(
    ModelSource source, {
    ModelLoadCancellationToken? cancellationToken,
    bool Function()? tryAcceptPublication,
    void Function()? onPublicationRejected,
  }) async =>
      ModelLoadResult.success(
        partTree: partTree,
        authoredCoreMaterialPatches: authoredCoreMaterialPatches,
        authoredExtensionMaterialPatches: authoredExtensionMaterialPatches,
      );

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) =>
      debugApplyMaterialPatchToRoot(
        root,
        address,
        patch,
        materialExtensionPolicy: materialExtensionPolicy,
        materialExtensionSupport: materialExtensionSupport,
        runtimeAdapter: runtimeAdapter,
      );

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) async {
    final adapter = runtimeAdapter;
    return adapter == null
        ? const <ViewerDiagnostic>[]
        : adapter.resetMaterial(address);
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
}

final class _ControllerExtendedPbrBackend
    implements FlutterSceneExtendedPbrMaterialBackend {
  final List<FlutterSceneExtendedPbrMaterialConfig> configs =
      <FlutterSceneExtendedPbrMaterialConfig>[];
  final List<flutter_scene.PhysicallyBasedMaterial> created =
      <flutter_scene.PhysicallyBasedMaterial>[];

  @override
  bool get isReady => true;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async {
    configs.add(config);
    final material = _ControllerExtendedPbrMaterial(config);
    created.add(material);
    return material;
  }
}

final class _ControllerExtendedPbrMaterial extends flutter_scene
    .PhysicallyBasedMaterial implements FlutterSceneExtendedPbrState {
  _ControllerExtendedPbrMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  )   : transforms = Map<MaterialTextureSlot, TextureTransform>.unmodifiable(
          config.transforms,
        ),
        specularFactor = config.specularFactor,
        specularColorFactor = List<double>.unmodifiable(
          config.specularColorFactor,
        ),
        specularFactorTexture = config.specularFactorTexture,
        specularColorTexture = config.specularColorTexture {
    ior = config.ior;
    metallicFactor = config.source.metallicFactor;
    roughnessFactor = config.source.roughnessFactor;
  }

  @override
  final Map<MaterialTextureSlot, TextureTransform> transforms;
  @override
  final double specularFactor;
  @override
  final List<double> specularColorFactor;
  @override
  final flutter_scene.TextureSource? specularFactorTexture;
  @override
  final flutter_scene.TextureSource? specularColorTexture;
}

final class _ControllerTextureFactory implements FlutterSceneTextureFactory {
  _ControllerTextureFactory({this.assetFailure});

  final Object? assetFailure;
  final List<flutter_scene.TextureSource> createdSources =
      <flutter_scene.TextureSource>[];

  flutter_scene.TextureSource _create(
    flutter_scene.TextureSampling sampling,
  ) {
    final source = _ControllerTextureSource(sampling.toSamplerOptions());
    createdSources.add(source);
    return source;
  }

  @override
  Future<flutter_scene.TextureSource> fromAsset(
    String assetPath, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    final failure = assetFailure;
    if (failure != null) throw failure;
    return _create(sampling);
  }

  @override
  Future<flutter_scene.TextureSource> fromImage(
    ui.Image image, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async =>
      _create(sampling);

  @override
  flutter_scene.TextureSource fromPixels(
    Uint8List pixels,
    int width,
    int height, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) =>
      _create(sampling);
}

final class _ControllerTextureSource implements flutter_scene.TextureSource {
  const _ControllerTextureSource(this._sampler);

  final flutter_scene_internal_gpu.SamplerOptions _sampler;

  @override
  flutter_scene_internal_gpu.Texture? get sampledTexture => null;

  @override
  flutter_scene_internal_gpu.SamplerOptions get sampledSampler => _sampler;
}

final class _AdapterUvGeometry extends flutter_scene.Geometry {
  @override
  // ignore: invalid_use_of_internal_member
  ({
    ByteData? vertices,
    Float32List? positions,
    Float32List? texCoords,
    ByteData? indices,
    flutter_scene_internal_gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  }) get cpuMeshData {
    final vertices = ByteData(48)
      ..setFloat32(24, 0.5, Endian.little)
      ..setFloat32(28, 0.5, Endian.little);
    return (
      vertices: vertices,
      positions: null,
      texCoords: null,
      indices: null,
      indexType: flutter_scene_internal_gpu.IndexType.int16,
      vertexCount: 1,
      indexCount: 0,
    );
  }

  @override
  void bind(
    flutter_scene_internal_gpu.RenderPass pass,
    flutter_scene_internal_gpu.HostBuffer transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    flutter_scene_internal_gpu.Shader? shaderOverride,
  }) {
    throw UnsupportedError('Stub geometry is not renderable.');
  }
}
