// ignore_for_file: invalid_use_of_internal_member

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/geometry.dart'
    as flutter_scene_internal_geometry;
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/vertex_layout.dart'
    as flutter_scene_internal_vertex_layout;
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_authored_mip_texture.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_backend.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_extended_pbr_material.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_material_extension_backend.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('authored mip staged material binding', () {
    test('uploads one image once and binds every same-role consuming slot', () {
      final interop = _RecordingMipInterop();
      final first = flutter_scene.PhysicallyBasedMaterial();
      final second = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'root',
        mesh: flutter_scene.Mesh.primitives(
          primitives: <flutter_scene.MeshPrimitive>[
            flutter_scene.MeshPrimitive(_UvStubGeometry(), first),
            flutter_scene.MeshPrimitive(_UvStubGeometry(), second),
          ],
        ),
      );
      final plan = FlutterSceneAuthoredMipBindingPlan(
        uploads: <FlutterSceneAuthoredMipImageUpload>[
          FlutterSceneAuthoredMipImageUpload(
            imageIndex: 3,
            contentRole: FlutterSceneAuthoredMipContentRole.data,
            levels: _authoredLevels(2),
            textureBindings: <FlutterSceneAuthoredMipTextureBinding>[
              FlutterSceneAuthoredMipTextureBinding(
                textureIndex: 4,
                sampler: _authoredMipSampler,
                targets: <FlutterSceneAuthoredMipMaterialTarget>[
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: <int>[],
                    primitiveIndex: 0,
                    slot: FlutterSceneAuthoredMipMaterialSlot.metallicRoughness,
                    required: true,
                  ),
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: <int>[],
                    primitiveIndex: 1,
                    slot: FlutterSceneAuthoredMipMaterialSlot.occlusion,
                    required: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final diagnostics = debugApplyFlutterSceneAuthoredMipBindingPlan(
        root,
        plan,
        uploader: FlutterSceneAuthoredMipTextureUploader(interop: interop),
      );

      expect(diagnostics, isEmpty);
      expect(interop.allocations, hasLength(1));
      expect(interop.uploadMipLevels, <int>[0, 1]);
      final firstSource = first.metallicRoughnessTextureSource;
      final secondSource = second.occlusionTextureSource;
      expect(firstSource, isNotNull);
      expect(secondSource, same(firstSource));
    });

    test('uploads one nonColor chain once across normal and data slots', () {
      final interop = _RecordingMipInterop();
      final material = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'root',
        mesh: flutter_scene.Mesh.primitives(
          primitives: <flutter_scene.MeshPrimitive>[
            flutter_scene.MeshPrimitive(_UvStubGeometry(), material),
          ],
        ),
      );
      final plan = FlutterSceneAuthoredMipBindingPlan(
        uploads: <FlutterSceneAuthoredMipImageUpload>[
          FlutterSceneAuthoredMipImageUpload(
            imageIndex: 8,
            contentRole: FlutterSceneAuthoredMipContentRole.data,
            levels: _authoredLevels(2),
            textureBindings: <FlutterSceneAuthoredMipTextureBinding>[
              FlutterSceneAuthoredMipTextureBinding(
                textureIndex: 9,
                sampler: _authoredMipSampler,
                targets: <FlutterSceneAuthoredMipMaterialTarget>[
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: const <int>[],
                    primitiveIndex: 0,
                    slot: FlutterSceneAuthoredMipMaterialSlot.normal,
                    required: true,
                  ),
                ],
              ),
              FlutterSceneAuthoredMipTextureBinding(
                textureIndex: 10,
                sampler: const FlutterSceneAuthoredMipSamplerIntent(
                  magFilter: 9728,
                  minFilter: 9984,
                  wrapS: 33071,
                  wrapT: 33648,
                ),
                targets: <FlutterSceneAuthoredMipMaterialTarget>[
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: const <int>[],
                    primitiveIndex: 0,
                    slot: FlutterSceneAuthoredMipMaterialSlot.occlusion,
                    required: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final diagnostics = debugApplyFlutterSceneAuthoredMipBindingPlan(
        root,
        plan,
        uploader: FlutterSceneAuthoredMipTextureUploader(interop: interop),
      );

      expect(diagnostics, isEmpty);
      expect(interop.allocations, hasLength(1));
      expect(interop.uploadMipLevels, <int>[0, 1]);
      final normalSource = material.normalTextureSource;
      final occlusionSource = material.occlusionTextureSource;
      expect(normalSource, isNotNull);
      expect(occlusionSource, isNotNull);
      expect(normalSource, isNot(same(occlusionSource)));
      expect(
          normalSource!.sampledTexture, same(occlusionSource!.sampledTexture));
      expect(
        normalSource.sampledSampler.widthAddressMode,
        isNot(occlusionSource.sampledSampler.widthAddressMode),
      );
    });

    test('retains distinct sampler intent for texture indices sharing pixels',
        () {
      final interop = _RecordingMipInterop();
      final first = flutter_scene.PhysicallyBasedMaterial();
      final second = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'root',
        mesh: flutter_scene.Mesh.primitives(
          primitives: <flutter_scene.MeshPrimitive>[
            flutter_scene.MeshPrimitive(_UvStubGeometry(), first),
            flutter_scene.MeshPrimitive(_UvStubGeometry(), second),
          ],
        ),
      );
      final plan = FlutterSceneAuthoredMipBindingPlan(
        uploads: <FlutterSceneAuthoredMipImageUpload>[
          FlutterSceneAuthoredMipImageUpload(
            imageIndex: 5,
            contentRole: FlutterSceneAuthoredMipContentRole.color,
            levels: _authoredLevels(2),
            textureBindings: <FlutterSceneAuthoredMipTextureBinding>[
              FlutterSceneAuthoredMipTextureBinding(
                textureIndex: 6,
                sampler: _authoredMipSampler,
                targets: <FlutterSceneAuthoredMipMaterialTarget>[
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: <int>[],
                    primitiveIndex: 0,
                    slot: FlutterSceneAuthoredMipMaterialSlot.baseColor,
                    required: true,
                  ),
                ],
              ),
              FlutterSceneAuthoredMipTextureBinding(
                textureIndex: 7,
                sampler: const FlutterSceneAuthoredMipSamplerIntent(
                  magFilter: 9728,
                  minFilter: 9984,
                  wrapS: 33071,
                  wrapT: 33648,
                ),
                targets: <FlutterSceneAuthoredMipMaterialTarget>[
                  FlutterSceneAuthoredMipMaterialTarget(
                    nodeChildPath: <int>[],
                    primitiveIndex: 1,
                    slot: FlutterSceneAuthoredMipMaterialSlot.baseColor,
                    required: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final diagnostics = debugApplyFlutterSceneAuthoredMipBindingPlan(
        root,
        plan,
        uploader: FlutterSceneAuthoredMipTextureUploader(interop: interop),
      );

      expect(diagnostics, isEmpty);
      expect(interop.allocations, hasLength(1));
      final firstSource = first.baseColorTextureSource!;
      final secondSource = second.baseColorTextureSource!;
      expect(firstSource, isNot(same(secondSource)));
      expect(
        firstSource.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.repeat,
      );
      expect(
        secondSource.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
      );
      expect(
        secondSource.sampledSampler.heightAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.mirror,
      );
    });

    test('required later upload failure leaves every staged slot unchanged',
        () {
      final interop = _RecordingMipInterop(failAllocationAt: 2);
      final first = flutter_scene.PhysicallyBasedMaterial();
      final second = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'root',
        mesh: flutter_scene.Mesh.primitives(
          primitives: <flutter_scene.MeshPrimitive>[
            flutter_scene.MeshPrimitive(_UvStubGeometry(), first),
            flutter_scene.MeshPrimitive(_UvStubGeometry(), second),
          ],
        ),
      );
      final plan = FlutterSceneAuthoredMipBindingPlan(
        uploads: <FlutterSceneAuthoredMipImageUpload>[
          _singleTargetMipUpload(
            imageIndex: 8,
            primitiveIndex: 0,
            slot: FlutterSceneAuthoredMipMaterialSlot.baseColor,
            role: FlutterSceneAuthoredMipContentRole.color,
          ),
          _singleTargetMipUpload(
            imageIndex: 9,
            primitiveIndex: 1,
            slot: FlutterSceneAuthoredMipMaterialSlot.normal,
            role: FlutterSceneAuthoredMipContentRole.normal,
          ),
        ],
      );

      final diagnostics = debugApplyFlutterSceneAuthoredMipBindingPlan(
        root,
        plan,
        uploader: FlutterSceneAuthoredMipTextureUploader(interop: interop),
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.details['blocking'], isTrue);
      expect(diagnostics.single.details['imageIndex'], 9);
      expect(first.baseColorTextureSource, isNull);
      expect(second.normalTextureSource, isNull);
    });
  });

  test('adapter advertises opted-in sheen only after request preflight',
      () async {
    final backend = _SheenReadyExtendedPbrBackend();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
      extendedPbrBackend: backend,
    );
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );

    expect(adapter.materialExtensionSupport.sheen, isFalse);

    final diagnostic = await adapter.preflightAuthoredMaterialPatch(
      address: address,
      patch: const MaterialPatch(
        sheenColorFactor: <double>[0.4, 0.5, 0.6],
        sheenRoughness: 0.7,
      ),
    );

    expect(diagnostic, isNull);
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.hasSheen, isTrue);
    final support = adapter.materialExtensionSupport
        .supportFor(MaterialExtensionFeature.sheen);
    expect(support.available, isTrue);
    for (final target in MaterialExtensionTarget.values) {
      expect(
        support.maturityFor(target),
        MaterialExtensionMaturity.candidateOnly,
      );
      expect(
        support.evidenceFor(target),
        MaterialExtensionEvidenceStatus.notRun,
      );
    }
  });

  test('production authored sheen preflight uses the current native probe',
      () async {
    final candidateBackend = _RecordingExtendedPbrBackend();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      extendedPbrBackend: candidateBackend,
    );

    final diagnostic = await adapter.preflightAuthoredMaterialPatch(
      address: PartAddress(
        nodePath: const <String>['Fabric'],
        primitiveIndex: 0,
      ),
      patch: const MaterialPatch(
        sheenColorFactor: <double>[0.2, 0.4, 0.8],
        sheenRoughness: 0.35,
      ),
    );

    expect(diagnostic, isNull);
    expect(candidateBackend.sheenRequests, isEmpty);
    expect(candidateBackend.configs, isEmpty);
  });

  test(
      'authored combined scalar clearcoat glass sheen uses native preflight without shader load',
      () async {
    var shaderLoadCount = 0;
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      extendedPbrBackend: FlutterSceneExtendedPbrBackend(
        loadShader: (_, __) async {
          shaderLoadCount += 1;
          throw StateError('state diagnostic must precede shader load');
        },
      ),
    );
    final address = PartAddress(
      nodePath: const <String>['CoatedGlassFabric'],
      primitiveIndex: 0,
    );

    final diagnostic = await adapter.preflightAuthoredMaterialPatch(
      address: address,
      patch: const MaterialPatch(
        sheenColorFactor: <double>[0.4, 0.5, 0.6],
        clearcoat: 0.8,
        transmission: 0.5,
        thickness: 0.25,
      ),
    );

    expect(diagnostic, isNull);
    expect(shaderLoadCount, 0);
  });

  test(
      'authored native textured clearcoat glass sheen fails before decode or shader load',
      () async {
    var shaderLoadCount = 0;
    final textureFactory = _RecordingTextureFactory();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      textureFactory: textureFactory,
      extendedPbrBackend: FlutterSceneExtendedPbrBackend(
        loadShader: (_, __) async {
          shaderLoadCount += 1;
          throw StateError('composition diagnostic must precede shader load');
        },
      ),
    );
    final address = PartAddress(
      nodePath: const <String>['CoatedGlassFabric'],
      primitiveIndex: 0,
    );

    final diagnostic = await adapter.preflightAuthoredMaterialPatch(
      address: address,
      patch: MaterialPatch(
        sheenColorFactor: const <double>[0.4, 0.5, 0.6],
        clearcoat: 0.8,
        clearcoatTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat.png'),
        ),
        transmission: 0.5,
        thickness: 0.25,
      ),
    );

    expect(diagnostic, isNotNull);
    expect(
      diagnostic!.details['limitation'],
      'nativeSheenPortableSamplerLimit',
    );
    expect(diagnostic.details['decodedTextureCount'], 0);
    expect(diagnostic.details['materialReplaced'], isFalse);
    expect(textureFactory.paths, isEmpty);
    expect(shaderLoadCount, 0);
  });

  test('ready sheen never inherits renderer native release capability',
      () async {
    final backend = _RecordingExtendedPbrBackend();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      extendedPbrBackend: backend,
    );
    final root = flutter_scene.Node(
      name: 'Fabric',
      mesh: flutter_scene.Mesh(
        _UvStubGeometry(),
        flutter_scene.PhysicallyBasedMaterial(),
      ),
    );
    final nativeSupport = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.clearcoat:
            MaterialExtensionFeatureSupport(available: true),
      },
      claimedReleaseTargets: const <MaterialExtensionTarget>{
        MaterialExtensionTarget.iosSimulator,
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Fabric'], primitiveIndex: 0),
      const MaterialPatch(),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: adapter,
    );

    expect(diagnostics, isEmpty);
    final support = adapter.materialExtensionSupport;
    expect(
      support.backendKind,
      MaterialExtensionBackendKind.packageLocalCandidate,
    );
    expect(support.claimedReleaseTargets, isEmpty);
    expect(support.productionReady, isFalse);
    final sheen = support.supportFor(MaterialExtensionFeature.sheen);
    expect(sheen.available, isTrue);
    for (final target in MaterialExtensionTarget.values) {
      expect(
          sheen.maturityFor(target), MaterialExtensionMaturity.candidateOnly);
      expect(
        sheen.evidenceFor(target),
        MaterialExtensionEvidenceStatus.notRun,
      );
      expect(support.productionReadyFor(MaterialExtensionFeature.sheen, target),
          isFalse);
    }
  });

  test('ready sheen preserves native routing for unrelated no-sheen patches',
      () async {
    final backend = _RecordingExtendedPbrBackend();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      extendedPbrBackend: backend,
    );
    final nativeSupport = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        for (final feature in <MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
          MaterialExtensionFeature.clearcoat,
        ])
          feature: MaterialExtensionFeatureSupport(available: true),
      },
    );
    final coatSource = flutter_scene.PhysicallyBasedMaterial();
    final coatRoot = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), coatSource),
    );
    final glassSource = flutter_scene.PhysicallyBasedMaterial();
    final glassRoot = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), glassSource),
    );

    final coatDiagnostics = await debugApplyMaterialPatchToRoot(
      coatRoot,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      const MaterialPatch(clearcoat: 0.8, clearcoatRoughness: 0.2),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: adapter,
    );
    final glassDiagnostics = await debugApplyMaterialPatchToRoot(
      glassRoot,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      const MaterialPatch(
        transmission: 0.6,
        ior: 1.4,
        thickness: 0.1,
      ),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: adapter,
    );

    expect(
      adapter.materialExtensionSupport.backendKind,
      MaterialExtensionBackendKind.packageLocalCandidate,
    );
    expect(coatDiagnostics, isEmpty);
    final coat = coatRoot.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(coat.clearcoatFactor, 0.8);
    expect(coat.clearcoatRoughnessFactor, 0.2);
    expect(coat, isNot(isA<FlutterSceneExtendedPbrState>()));
    expect(glassDiagnostics, isEmpty);
    final glass = glassRoot.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(glass.transmissionFactor, 0.6);
    expect(glass.ior, 1.4);
    expect(glass.thicknessFactor, 0.1);
    expect(glass, isNot(isA<FlutterSceneExtendedPbrState>()));
    expect(backend.sheenRequests, isEmpty);
    expect(backend.configs, isEmpty);
  });

  test(
      'renderer-native sheen and opaque IOR bypass the package-local candidate atomically',
      () async {
    final textureFactory = _RecordingTextureFactory();
    final candidateBackend = _RecordingExtendedPbrBackend();
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      textureFactory: textureFactory,
      extendedPbrBackend: candidateBackend,
    );
    final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Fabric',
      mesh: flutter_scene.Mesh(_Uv1StubGeometry(), sourceMaterial),
    );
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.sheen: MaterialExtensionFeatureSupport(
          available: true,
          maturityByTarget: const <MaterialExtensionTarget,
              MaterialExtensionMaturity>{
            MaterialExtensionTarget.iosSimulator:
                MaterialExtensionMaturity.releasePending,
          },
        ),
        MaterialExtensionFeature.ior:
            MaterialExtensionFeatureSupport(available: true),
      },
    );
    final colorTransform = TextureTransform(
      offset: const <double>[0.1, 0.2],
      scale: const <double>[1.5, 0.75],
      rotation: 0.3,
    );
    final roughnessTransform = TextureTransform(
      offset: const <double>[0.4, 0.5],
      scale: const <double>[0.5, 2.0],
      rotation: 0.6,
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Fabric'], primitiveIndex: 0),
      MaterialPatch(
        ior: 1.45,
        sheenColorFactor: const <double>[0.2, 0.4, 0.8],
        sheenColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'native-sheen-color',
          ),
          texCoord: 1,
          transform: colorTransform,
        ),
        sheenRoughness: 0.35,
        sheenRoughnessTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'native-sheen-roughness',
          ),
          transform: roughnessTransform,
        ),
      ),
      materialExtensionSupport: support,
      runtimeAdapter: adapter,
    );

    expect(diagnostics, isEmpty);
    expect(
      adapter.materialExtensionSupport.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
    final advertisedSheen = adapter.materialExtensionSupport
        .supportFor(MaterialExtensionFeature.sheen);
    expect(advertisedSheen.available, isTrue);
    expect(
      advertisedSheen.maturityFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionMaturity.releasePending,
    );
    expect(
      advertisedSheen.evidenceFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionEvidenceStatus.notRun,
    );
    expect(candidateBackend.sheenRequests, isEmpty);
    expect(candidateBackend.configs, isEmpty);
    expect(textureFactory.createdSources, hasLength(2));
    final native = root.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(native, isNot(isA<FlutterSceneExtendedPbrState>()));
    expect(native.sheenColorFactor.x, closeTo(0.2, 0.0001));
    expect(native.sheenColorFactor.y, closeTo(0.4, 0.0001));
    expect(native.sheenColorFactor.z, closeTo(0.8, 0.0001));
    expect(native.sheenColorTexture, same(textureFactory.createdSources[0]));
    expect(native.sheenColorTextureTexCoord, 1);
    expect(native.sheenColorTextureTransform.offsetX, 0.1);
    expect(native.sheenColorTextureTransform.offsetY, 0.2);
    expect(native.sheenColorTextureTransform.rotation, 0.3);
    expect(native.sheenColorTextureTransform.scaleX, 1.5);
    expect(native.sheenColorTextureTransform.scaleY, 0.75);
    expect(native.sheenRoughnessFactor, 0.35);
    expect(
      native.sheenRoughnessTexture,
      same(textureFactory.createdSources[1]),
    );
    expect(native.sheenRoughnessTextureTexCoord, 0);
    expect(native.sheenRoughnessTextureTransform.offsetX, 0.4);
    expect(native.sheenRoughnessTextureTransform.offsetY, 0.5);
    expect(native.sheenRoughnessTextureTransform.rotation, 0.6);
    expect(native.sheenRoughnessTextureTransform.scaleX, 0.5);
    expect(native.sheenRoughnessTextureTransform.scaleY, 2.0);
    expect(native.ior, 1.45);
  });

  test('renderer-native sheen rejects unlit before visibility mutation',
      () async {
    final originalGeometry = _UvStubGeometry();
    final originalMaterial = flutter_scene.UnlitMaterial();
    final root = flutter_scene.Node(
      name: 'Fabric',
      mesh: flutter_scene.Mesh(originalGeometry, originalMaterial),
    );
    final originalMesh = root.mesh;
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.sheen:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Fabric'], primitiveIndex: 0),
      const MaterialPatch(
        sheenColorFactor: <double>[0.2, 0.4, 0.8],
        visible: false,
      ),
      materialExtensionSupport: support,
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedMaterialFeature,
    );
    expect(root.visible, isTrue);
    expect(root.mesh, same(originalMesh));
    expect(root.mesh!.primitives.single.geometry, same(originalGeometry));
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
  });

  test('native sheen sampler-limit combinations fail before texture decode',
      () async {
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        for (final feature in <MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.clearcoat,
          MaterialExtensionFeature.sheen,
        ])
          feature: MaterialExtensionFeatureSupport(available: true),
      },
    );
    final retainedClearcoatTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final cases = <({
      String name,
      flutter_scene.PhysicallyBasedMaterial source,
      MaterialPatch patch,
    })>[
      (
        name: 'same delta',
        source: flutter_scene.PhysicallyBasedMaterial(),
        patch: MaterialPatch(
          transmission: 0.5,
          sheenColorFactor: const <double>[0.2, 0.4, 0.8],
          clearcoat: 0.7,
          clearcoatTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'same-delta-clearcoat',
            ),
          ),
        ),
      ),
      (
        name: 'retained state',
        source: flutter_scene.PhysicallyBasedMaterial()
          ..transmissionFactor = 0.5
          ..clearcoatFactor = 0.7
          ..clearcoatTexture = retainedClearcoatTexture,
        patch: const MaterialPatch(
          sheenColorFactor: <double>[0.2, 0.4, 0.8],
        ),
      ),
    ];

    for (final entry in cases) {
      final textureFactory = _RecordingTextureFactory();
      final candidateBackend = _RecordingExtendedPbrBackend();
      final root = flutter_scene.Node(
        name: 'Fabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), entry.source),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(nodePath: const <String>['Fabric'], primitiveIndex: 0),
        entry.patch,
        materialExtensionSupport: support,
        runtimeAdapter: FlutterSceneRuntimeAdapter(
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(
            enableSheen: true,
          ),
          textureFactory: textureFactory,
          extendedPbrBackend: candidateBackend,
        ),
      );

      expect(diagnostics, hasLength(1), reason: entry.name);
      expect(
        diagnostics.single.details['limitation'],
        'nativeSheenPortableSamplerLimit',
        reason: entry.name,
      );
      expect(diagnostics.single.details['status'], 'blocked');
      expect(diagnostics.single.details['decodedTextureCount'], 0);
      expect(textureFactory.createdSources, isEmpty, reason: entry.name);
      expect(candidateBackend.sheenRequests, isEmpty, reason: entry.name);
      expect(
        root.mesh!.primitives.single.material,
        same(entry.source),
        reason: entry.name,
      );
    }
  });

  test('disabled sheen preserves renderer native capability identity',
      () async {
    final adapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      extendedPbrBackend: _RecordingExtendedPbrBackend(),
    );
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(
        _UvStubGeometry(),
        flutter_scene.PhysicallyBasedMaterial(),
      ),
    );
    final nativeSupport = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      claimedReleaseTargets: const <MaterialExtensionTarget>{
        MaterialExtensionTarget.iosSimulator,
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      const MaterialPatch(),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: adapter,
    );

    expect(diagnostics, isEmpty);
    expect(
      adapter.materialExtensionSupport.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
    expect(
      adapter.materialExtensionSupport.claimedReleaseTargets,
      const <MaterialExtensionTarget>{MaterialExtensionTarget.iosSimulator},
    );
    expect(adapter.materialExtensionSupport.sheen, isFalse);
  });

  test('import policy retains native sheen only for selected native support',
      () {
    flutter_scene.PhysicallyBasedMaterial material() =>
        flutter_scene.PhysicallyBasedMaterial()
          ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
          ..sheenColorTexture = _StubTextureSource(
            const flutter_scene.TextureSampling().toSamplerOptions(),
          )
          ..sheenColorTextureTexCoord = 1
          ..sheenColorTextureTransform =
              const flutter_scene.MaterialTextureTransform(offsetX: 0.2)
          ..sheenRoughnessFactor = 0.35
          ..sheenRoughnessTexture = _StubTextureSource(
            const flutter_scene.TextureSampling().toSamplerOptions(),
          )
          ..sheenRoughnessTextureTexCoord = 1
          ..sheenRoughnessTextureTransform =
              const flutter_scene.MaterialTextureTransform(scaleX: 0.5);

    final retained = material();
    final retainedRoot = flutter_scene.Node(
      name: 'Retained',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), retained),
    );
    final stripped = material();
    final strippedRoot = flutter_scene.Node(
      name: 'Stripped',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), stripped),
    );

    debugApplyRendererNativeSheenImportPolicy(
      retainedRoot,
      retainRendererNativeSheen: true,
    );
    debugApplyRendererNativeSheenImportPolicy(
      strippedRoot,
      retainRendererNativeSheen: false,
    );

    expect(retained.sheenColorFactor.x, closeTo(0.2, 0.0001));
    expect(retained.sheenColorTexture, isNotNull);
    expect(retained.sheenColorTextureTexCoord, 1);
    expect(retained.sheenColorTextureTransform.offsetX, 0.2);
    expect(retained.sheenRoughnessFactor, 0.35);
    expect(retained.sheenRoughnessTexture, isNotNull);
    expect(retained.sheenRoughnessTextureTexCoord, 1);
    expect(retained.sheenRoughnessTextureTransform.scaleX, 0.5);

    expect(stripped.sheenColorFactor, vm.Vector3.zero());
    expect(stripped.sheenColorTexture, isNull);
    expect(stripped.sheenColorTextureTexCoord, 0);
    expect(
      stripped.sheenColorTextureTransform,
      const flutter_scene.MaterialTextureTransform(),
    );
    expect(stripped.sheenRoughnessFactor, 0);
    expect(stripped.sheenRoughnessTexture, isNull);
    expect(stripped.sheenRoughnessTextureTexCoord, 0);
    expect(
      stripped.sheenRoughnessTextureTransform,
      const flutter_scene.MaterialTextureTransform(),
    );
  });

  test('authored core fallback neutralizes exact shared-material address', () {
    final sheenColorTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final sheenRoughnessTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final clearcoatTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    const colorTransform = flutter_scene.MaterialTextureTransform(
      offsetX: 0.1,
      offsetY: 0.2,
      rotation: 0.3,
      scaleX: 1.5,
      scaleY: 0.75,
    );
    const roughnessTransform = flutter_scene.MaterialTextureTransform(
      offsetX: 0.4,
      offsetY: 0.5,
      rotation: 0.6,
      scaleX: 0.5,
      scaleY: 2.0,
    );
    final sharedMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
      ..sheenColorTexture = sheenColorTexture
      ..sheenColorTextureTexCoord = 1
      ..sheenColorTextureTransform = colorTransform
      ..sheenRoughnessFactor = 0.35
      ..sheenRoughnessTexture = sheenRoughnessTexture
      ..sheenRoughnessTextureTexCoord = 1
      ..sheenRoughnessTextureTransform = roughnessTransform
      ..transmissionFactor = 0.5
      ..clearcoatFactor = 0.7
      ..clearcoatTexture = clearcoatTexture;
    final fallbackNode = flutter_scene.Node(
      name: 'FallbackFabric',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), sharedMaterial),
    );
    final validNode = flutter_scene.Node(
      name: 'ValidFabric',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), sharedMaterial),
    );
    final root = flutter_scene.Node(name: 'Root')
      ..add(fallbackNode)
      ..add(validNode);
    final fallbackAddress = PartAddress(
      nodePath: const <String>['Root', 'FallbackFabric'],
      primitiveIndex: 0,
    );

    debugApplyRendererNativeSheenImportPolicy(
      root,
      retainRendererNativeSheen: true,
      coreFallbackAddresses: <PartAddress>{fallbackAddress},
    );

    final fallbackMaterial = fallbackNode.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    final validMaterial = validNode.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(fallbackMaterial, isNot(same(sharedMaterial)));
    expect(fallbackMaterial.sheenColorFactor, vm.Vector3.zero());
    expect(fallbackMaterial.sheenColorTexture, isNull);
    expect(fallbackMaterial.sheenColorTextureTexCoord, 0);
    expect(
      fallbackMaterial.sheenColorTextureTransform,
      const flutter_scene.MaterialTextureTransform(),
    );
    expect(fallbackMaterial.sheenRoughnessFactor, 0);
    expect(fallbackMaterial.sheenRoughnessTexture, isNull);
    expect(fallbackMaterial.sheenRoughnessTextureTexCoord, 0);
    expect(
      fallbackMaterial.sheenRoughnessTextureTransform,
      const flutter_scene.MaterialTextureTransform(),
    );
    expect(fallbackMaterial.transmissionFactor, 0.5);
    expect(fallbackMaterial.clearcoatFactor, 0.7);
    expect(fallbackMaterial.clearcoatTexture, same(clearcoatTexture));

    expect(validMaterial, same(sharedMaterial));
    expect(validMaterial.sheenColorFactor.x, closeTo(0.2, 0.0001));
    expect(validMaterial.sheenColorTexture, same(sheenColorTexture));
    expect(validMaterial.sheenColorTextureTexCoord, 1);
    expect(validMaterial.sheenColorTextureTransform, colorTransform);
    expect(validMaterial.sheenRoughnessFactor, 0.35);
    expect(
      validMaterial.sheenRoughnessTexture,
      same(sheenRoughnessTexture),
    );
    expect(validMaterial.sheenRoughnessTextureTexCoord, 1);
    expect(validMaterial.sheenRoughnessTextureTransform, roughnessTransform);
    expect(validMaterial.transmissionFactor, 0.5);
    expect(validMaterial.clearcoatFactor, 0.7);
    expect(validMaterial.clearcoatTexture, same(clearcoatTexture));
  });

  group('texture binding renderer plan', () {
    test('maps symmetric repeat clamp and mirror sampler state', () {
      final expected =
          <TextureWrapMode, flutter_scene_internal_gpu.SamplerAddressMode>{
        TextureWrapMode.repeat:
            flutter_scene_internal_gpu.SamplerAddressMode.repeat,
        TextureWrapMode.clampToEdge:
            flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
        TextureWrapMode.mirroredRepeat:
            flutter_scene_internal_gpu.SamplerAddressMode.mirror,
      };

      for (final entry in expected.entries) {
        final plan = debugFlutterSceneTextureBindingPlan(
          MaterialTextureBinding(
            source: const TextureSource.asset('assets/albedo.png'),
            sampler: TextureSampler(wrapS: entry.key, wrapT: entry.key),
          ),
          MaterialTextureSlot.baseColor,
        );

        expect(plan.diagnostic, isNull, reason: entry.key.name);
        expect(plan.sampling!.addressMode, entry.value, reason: entry.key.name);
      }
    });

    test('maps every glTF min mag and mip filter intent', () {
      final cases = <TextureMinFilter,
          (
        flutter_scene_internal_gpu.MinMagFilter,
        flutter_scene_internal_gpu.MipFilter,
        bool
      )>{
        TextureMinFilter.nearest: (
          flutter_scene_internal_gpu.MinMagFilter.nearest,
          flutter_scene_internal_gpu.MipFilter.nearest,
          false,
        ),
        TextureMinFilter.linear: (
          flutter_scene_internal_gpu.MinMagFilter.linear,
          flutter_scene_internal_gpu.MipFilter.nearest,
          false,
        ),
        TextureMinFilter.nearestMipmapNearest: (
          flutter_scene_internal_gpu.MinMagFilter.nearest,
          flutter_scene_internal_gpu.MipFilter.nearest,
          true,
        ),
        TextureMinFilter.linearMipmapNearest: (
          flutter_scene_internal_gpu.MinMagFilter.linear,
          flutter_scene_internal_gpu.MipFilter.nearest,
          true,
        ),
        TextureMinFilter.nearestMipmapLinear: (
          flutter_scene_internal_gpu.MinMagFilter.nearest,
          flutter_scene_internal_gpu.MipFilter.linear,
          true,
        ),
        TextureMinFilter.linearMipmapLinear: (
          flutter_scene_internal_gpu.MinMagFilter.linear,
          flutter_scene_internal_gpu.MipFilter.linear,
          true,
        ),
      };

      for (final entry in cases.entries) {
        final plan = debugFlutterSceneTextureBindingPlan(
          MaterialTextureBinding(
            source: const TextureSource.asset('assets/data.png'),
            sampler: TextureSampler(
              magFilter: TextureMagFilter.nearest,
              minFilter: entry.key,
            ),
          ),
          MaterialTextureSlot.metallicRoughness,
        );

        expect(plan.diagnostic, isNull, reason: entry.key.name);
        expect(plan.sampling!.minFilter, entry.value.$1,
            reason: entry.key.name);
        expect(plan.sampling!.mipFilter, entry.value.$2,
            reason: entry.key.name);
        expect(plan.sampling!.mipmaps, entry.value.$3, reason: entry.key.name);
        expect(
          plan.sampling!.magFilter,
          flutter_scene_internal_gpu.MinMagFilter.nearest,
          reason: entry.key.name,
        );
      }

      final explicitLinear = debugFlutterSceneTextureBindingPlan(
        MaterialTextureBinding(
          source: const TextureSource.asset('assets/data.png'),
          sampler: const TextureSampler(
            magFilter: TextureMagFilter.linear,
          ),
        ),
        MaterialTextureSlot.metallicRoughness,
      );
      expect(explicitLinear.diagnostic, isNull);
      expect(
        explicitLinear.sampling!.magFilter,
        flutter_scene_internal_gpu.MinMagFilter.linear,
      );
    });

    test('uses the effective UV set after a transform texCoord override', () {
      final uv0Plan = debugFlutterSceneTextureBindingPlan(
        MaterialTextureBinding(
          source: const TextureSource.asset('assets/albedo.png'),
          texCoord: 1,
          transform: TextureTransform(texCoordOverride: 0),
        ),
        MaterialTextureSlot.baseColor,
      );
      final uv1Plan = debugFlutterSceneTextureBindingPlan(
        MaterialTextureBinding(
          source: const TextureSource.asset('assets/albedo.png'),
          transform: TextureTransform(texCoordOverride: 1),
        ),
        MaterialTextureSlot.baseColor,
      );
      final authoredAoUv1Plan = debugFlutterSceneTextureBindingPlan(
        MaterialTextureBinding(
          source: const TextureSource.asset('assets/ao.png'),
          transform: TextureTransform(texCoordOverride: 1),
        ),
        MaterialTextureSlot.occlusion,
        allowAuthoredOcclusionTexCoord1: true,
      );

      expect(uv0Plan.diagnostic, isNull);
      expect(uv0Plan.sampling, isNotNull);
      expect(uv1Plan.sampling, isNull);
      expect(
        uv1Plan.diagnostic!.details['limitation'],
        'perSlotTextureCoordinateContractMissing',
      );
      expect(uv1Plan.diagnostic!.details['texCoord'], 1);
      expect(authoredAoUv1Plan.diagnostic, isNull);
      expect(authoredAoUv1Plan.sampling, isNotNull);
    });

    test('passes sampler through asset image and pixel creation paths',
        () async {
      final factory = _RecordingTextureFactory();
      const sampler = TextureSampler(
        wrapS: TextureWrapMode.clampToEdge,
        wrapT: TextureWrapMode.clampToEdge,
        magFilter: TextureMagFilter.nearest,
        minFilter: TextureMinFilter.nearestMipmapLinear,
      );

      for (final entry in <(
        MaterialTextureBinding,
        MaterialTextureSlot,
        flutter_scene.TextureContent,
        double?
      )>[
        (
          MaterialTextureBinding(
            source: const TextureSource.asset('assets/albedo.png'),
            sampler: sampler,
          ),
          MaterialTextureSlot.baseColor,
          flutter_scene.TextureContent.color,
          null,
        ),
        (
          MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'orm'),
            sampler: sampler,
          ),
          MaterialTextureSlot.metallicRoughness,
          flutter_scene.TextureContent.data,
          null,
        ),
        (
          MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
            sampler: sampler,
          ),
          MaterialTextureSlot.normal,
          flutter_scene.TextureContent.normal,
          0.5,
        ),
      ]) {
        final diagnostics = await debugLoadTextureBinding(
          entry.$1,
          entry.$2,
          textureContent: entry.$3,
          normalMapScale: entry.$4,
          textureFactory: factory,
        );
        expect(diagnostics, isEmpty, reason: entry.$2.name);
      }

      expect(factory.paths, <String>['fromAsset', 'fromImage', 'fromPixels']);
      expect(factory.contents, <flutter_scene.TextureContent>[
        flutter_scene.TextureContent.color,
        flutter_scene.TextureContent.data,
        flutter_scene.TextureContent.normal,
      ]);
      for (final sampling in factory.samplings) {
        expect(
          sampling.addressMode,
          flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
        );
        expect(sampling.minFilter,
            flutter_scene_internal_gpu.MinMagFilter.nearest);
        expect(sampling.magFilter,
            flutter_scene_internal_gpu.MinMagFilter.nearest);
        expect(sampling.mipFilter, flutter_scene_internal_gpu.MipFilter.linear);
        expect(sampling.mipmaps, isTrue);
      }
    });

    test('same bytes keep distinct per-slot sampler state without mutation',
        () async {
      final factory = _RecordingTextureFactory();
      final source = TextureSource.bytes(_onePixelPng, debugName: 'shared');
      final before = Uint8List.fromList(_onePixelPng);
      final repeat = MaterialTextureBinding(source: source);
      final clamp = MaterialTextureBinding(
        source: source,
        sampler: const TextureSampler(
          wrapS: TextureWrapMode.clampToEdge,
          wrapT: TextureWrapMode.clampToEdge,
        ),
      );

      expect(
        await debugLoadTextureBinding(
          repeat,
          MaterialTextureSlot.baseColor,
          textureContent: flutter_scene.TextureContent.color,
          textureFactory: factory,
        ),
        isEmpty,
      );
      expect(
        await debugLoadTextureBinding(
          clamp,
          MaterialTextureSlot.normal,
          textureContent: flutter_scene.TextureContent.normal,
          textureFactory: factory,
        ),
        isEmpty,
      );

      expect(factory.samplings, hasLength(2));
      expect(factory.samplings.first.addressMode,
          flutter_scene_internal_gpu.SamplerAddressMode.repeat);
      expect(factory.samplings.last.addressMode,
          flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge);
      expect(
        factory.createdSources.first.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.repeat,
      );
      expect(
        factory.createdSources.last.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
      );
      expect(
        factory.createdSources.first.sampledSampler,
        isNot(same(factory.createdSources.last.sampledSampler)),
      );
      expect(_onePixelPng, before);
    });

    test('standard PBR slots retain distinct resulting sampler state',
        () async {
      final factory = _RecordingTextureFactory();
      const source = TextureSource.asset('assets/shared.png');
      final material = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Paint',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Paint'],
          primitiveIndex: 0,
        ),
        MaterialPatch(
          baseColorTextureBinding: MaterialTextureBinding(source: source),
          normalTextureBinding: MaterialTextureBinding(
            source: source,
            sampler: const TextureSampler(
              wrapS: TextureWrapMode.clampToEdge,
              wrapT: TextureWrapMode.clampToEdge,
            ),
          ),
        ),
        textureFactory: factory,
      );

      expect(diagnostics, isEmpty);
      expect(material.baseColorTextureSource, same(factory.createdSources[0]));
      expect(material.normalTextureSource, same(factory.createdSources[1]));
      expect(
        material.baseColorTextureSource!.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.repeat,
      );
      expect(
        material.normalTextureSource!.sampledSampler.widthAddressMode,
        flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
      );
    });

    test('unsupported transform diagnoses before decode or byte generation',
        () async {
      final factory = _RecordingTextureFactory();
      final before = Uint8List.fromList(_onePixelPng);
      final binding = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );

      final diagnostics = await debugLoadTextureBinding(
        binding,
        MaterialTextureSlot.baseColor,
        textureContent: flutter_scene.TextureContent.color,
        textureFactory: factory,
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code,
          ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(diagnostics.single.details['limitation'],
          'perSlotUvTransformContractMissing');
      expect(factory.paths, isEmpty);
      expect(_onePixelPng, before);
    });

    test('combined UV specular and opaque IOR route to one extended material',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.7;
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final binding = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(nodePath: const <String>['Body'], primitiveIndex: 0),
        MaterialPatch(
          baseColorTextureBinding: binding,
          specular: 0.6,
          specularTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'specular-factor',
            ),
          ),
          specularColorFactor: const <double>[1.2, 0.8, 0.4],
          specularColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'specular-color',
            ),
          ),
          ior: 1.45,
        ),
        materialExtensionSupport: MaterialExtensionSupport(
          backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
          features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
            MaterialExtensionFeature.specular:
                MaterialExtensionFeatureSupport(available: true),
            MaterialExtensionFeature.ior:
                MaterialExtensionFeatureSupport(available: true),
          },
        ),
        textureFactory: textureFactory,
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, isEmpty);
      expect(extendedBackend.preflightCount, 1);
      expect(extendedBackend.configs, hasLength(1));
      final config = extendedBackend.configs.single;
      expect(config.source, isNot(same(sourceMaterial)));
      expect(config.source.metallicFactor, 0.2);
      expect(config.source.roughnessFactor, 0.7);
      expect(
        config.transforms[MaterialTextureSlot.baseColor],
        binding.transform,
      );
      expect(config.specularFactor, 0.6);
      expect(config.specularColorFactor, <double>[1.2, 0.8, 0.4]);
      expect(config.ior, 1.45);
      expect(config.source.baseColorTexture,
          same(textureFactory.createdSources[0]));
      expect(
          config.specularFactorTexture, same(textureFactory.createdSources[1]));
      expect(
          config.specularColorTexture, same(textureFactory.createdSources[2]));
      expect(textureFactory.contents, <flutter_scene.TextureContent>[
        flutter_scene.TextureContent.color,
        flutter_scene.TextureContent.data,
        flutter_scene.TextureContent.color,
      ]);
      expect(root.mesh!.primitives.single.material,
          same(extendedBackend.createdMaterials.single));
      expect(
          root.mesh!.primitives.single.material, isNot(same(sourceMaterial)));
    });

    test('specular route preserves native opaque IOR including zero', () async {
      for (final sourceIor in <double>[1.37, 0.0]) {
        final extendedBackend = _RecordingExtendedPbrBackend();
        final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
          ..ior = sourceIor;
        final root = flutter_scene.Node(
          name: 'Body',
          mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
        );

        final diagnostics = await debugApplyMaterialPatchToRoot(
          root,
          PartAddress(nodePath: const <String>['Body'], primitiveIndex: 0),
          const MaterialPatch(specular: 0.6),
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(),
          materialExtensionSupport: _materialExtensionSupport(
            MaterialExtensionBackendKind.rendererNative,
          ),
          runtimeAdapter: FlutterSceneRuntimeAdapter(
            extendedPbrBackend: extendedBackend,
          ),
        );

        expect(diagnostics, isEmpty, reason: 'source IOR $sourceIor');
        expect(extendedBackend.configs, hasLength(1));
        expect(
          extendedBackend.configs.single.source.ior,
          sourceIor,
          reason: 'staged source IOR $sourceIor',
        );
        expect(
          extendedBackend.configs.single.ior,
          sourceIor,
          reason: 'extended config IOR $sourceIor',
        );
        expect(
          (root.mesh!.primitives.single.material
                  as flutter_scene.PhysicallyBasedMaterial)
              .ior,
          sourceIor,
          reason: 'replacement IOR $sourceIor',
        );
        expect(sourceMaterial.ior, sourceIor);
      }
    });

    test('core-only delta keeps the active extended PBR state', () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.7;
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final address = PartAddress(
        nodePath: const <String>['Body'],
        primitiveIndex: 0,
      );
      final transformedBaseColor = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(
          baseColorTextureBinding: transformedBaseColor,
          specular: 0.6,
          ior: 1.45,
        ),
        runtimeAdapter: runtimeAdapter,
      );
      final deltaDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(roughness: 0.35),
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(deltaDiagnostics, isEmpty);
      expect(extendedBackend.configs, hasLength(2));
      expect(extendedBackend.configs.last.specularFactor, 0.6);
      expect(extendedBackend.configs.last.ior, 1.45);
      expect(
        extendedBackend.configs.last.transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(extendedBackend.configs.last.source.roughnessFactor, 0.35);

      final resetDiagnostics = await runtimeAdapter.resetMaterial(address);

      expect(resetDiagnostics, isEmpty);
      expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      expect(sourceMaterial.metallicFactor, 0.2);
      expect(sourceMaterial.roughnessFactor, 0.7);
    });

    test('authored AO UV1 core patch stays on the imported standard route',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        // The pinned importer records this only after validating TEXCOORD_1.
        ..occlusionTextureTexCoord = 1;
      final root = flutter_scene.Node(
        name: 'Fabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        textureFactory: textureFactory,
      );
      final address = PartAddress(
        nodePath: const <String>['Fabric'],
        primitiveIndex: 0,
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(
          occlusionTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'authored-occlusion-uv1',
            ),
            texCoord: 1,
          ),
        ),
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, isEmpty);
      expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      expect(sourceMaterial.occlusionTexture,
          same(textureFactory.createdSources.single));
      expect(sourceMaterial.occlusionTextureTexCoord, 1);
    });

    test('explicit black sheen retains textures transforms across sparse delta',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..roughnessFactor = 0.8
        ..occlusionTextureTexCoord = 1
        ..occlusionTextureTransform =
            const flutter_scene.MaterialTextureTransform(
          offsetX: 0.2,
          offsetY: 0.3,
          rotation: 0.4,
          scaleX: 1.5,
          scaleY: 1.6,
        );
      final root = flutter_scene.Node(
        name: 'Fabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.experimentalShaders(
          enableSheen: true,
        ),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final address = PartAddress(
        nodePath: const <String>['Fabric'],
        primitiveIndex: 0,
      );
      final colorBinding = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'sheen-color'),
        transform: TextureTransform(
          offset: const <double>[0.1, 0.2],
          scale: const <double>[2, 3],
        ),
      );
      final roughnessBinding = MaterialTextureBinding(
        source: TextureSource.bytes(
          _onePixelPng,
          debugName: 'sheen-roughness',
        ),
        transform: TextureTransform(
          offset: const <double>[0.4, 0.5],
          scale: const <double>[0.5, 0.75],
        ),
      );
      final occlusionBinding = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'occlusion'),
        texCoord: 1,
        transform: TextureTransform(
          offset: const <double>[0.2, 0.3],
          scale: const <double>[1.5, 1.6],
          rotation: 0.4,
        ),
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(
          sheenColorFactor: const <double>[0, 0, 0],
          sheenColorTextureBinding: colorBinding,
          sheenRoughness: 0.65,
          sheenRoughnessTextureBinding: roughnessBinding,
          occlusionTextureBinding: occlusionBinding,
        ),
        runtimeAdapter: runtimeAdapter,
      );
      final sparseDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(roughness: 0.25),
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(sparseDiagnostics, isEmpty);
      expect(extendedBackend.configs, hasLength(2));
      expect(extendedBackend.sheenRequests, hasLength(2));
      for (final request in extendedBackend.sheenRequests) {
        expect(request.hasSheenColorTexture, isTrue);
        expect(request.hasSheenRoughnessTexture, isTrue);
        expect(request.hasSpecularFactorTexture, isFalse);
        expect(request.hasSpecularColorTexture, isFalse);
      }
      final retained = extendedBackend.configs.last;
      expect(retained.hasSheenIntent, isTrue);
      expect(retained.sheenColorFactor, <double>[0, 0, 0]);
      expect(retained.sheenRoughness, 0.65);
      expect(
          retained.sheenColorTexture, same(textureFactory.createdSources[1]));
      expect(retained.sheenRoughnessTexture,
          same(textureFactory.createdSources[2]));
      expect(
        retained.transforms[MaterialTextureSlot.sheenColor],
        colorBinding.transform,
      );
      expect(
        retained.transforms[MaterialTextureSlot.sheenRoughness],
        roughnessBinding.transform,
      );
      expect(
        retained.transforms[MaterialTextureSlot.occlusion],
        occlusionBinding.transform,
      );
      expect(retained.source.roughnessFactor, 0.25);
      for (final config in extendedBackend.configs) {
        expect(config.source.occlusionTextureTexCoord, 1);
        expect(config.source.occlusionTextureTransform.offsetX, 0.2);
        expect(config.source.occlusionTextureTransform.offsetY, 0.3);
        expect(config.source.occlusionTextureTransform.rotation, 0.4);
        expect(config.source.occlusionTextureTransform.scaleX, 1.5);
        expect(config.source.occlusionTextureTransform.scaleY, 1.6);
      }
      expect(textureFactory.contents, <flutter_scene.TextureContent>[
        flutter_scene.TextureContent.data,
        flutter_scene.TextureContent.color,
        flutter_scene.TextureContent.data,
      ]);
    });

    test('native clearcoat and local sheen select one combined candidate',
        () async {
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'CoatedFabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
        extendedPbrBackend: extendedBackend,
      );
      final nativeSupport = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.clearcoat:
              MaterialExtensionFeatureSupport(available: true),
        },
      );
      final address = PartAddress(
        nodePath: const <String>['CoatedFabric'],
        primitiveIndex: 0,
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(
          specular: 0.6,
          specularColorFactor: <double>[0.8, 0.7, 0.6],
          ior: 1.45,
          sheenColorFactor: <double>[0.4, 0.3, 0.2],
          sheenRoughness: 0.55,
          clearcoat: 0.8,
          clearcoatRoughness: 0.2,
        ),
        materialExtensionSupport: nativeSupport,
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, isEmpty);
      expect(extendedBackend.sheenRequests, hasLength(1));
      final request = extendedBackend.sheenRequests.single;
      expect(request.hasSheen, isTrue);
      expect(request.hasClearcoat, isTrue);
      expect(request.hasSpecular, isTrue);
      expect(request.hasSpecularFactorTexture, isFalse);
      expect(request.hasSpecularColorTexture, isFalse);
      expect(extendedBackend.configs, hasLength(1));
      final config = extendedBackend.configs.single;
      expect(config.specularFactor, 0.6);
      expect(config.specularColorFactor, <double>[0.8, 0.7, 0.6]);
      expect(config.ior, 1.45);
      expect(config.hasSheenIntent, isTrue);
      expect(config.source.clearcoatFactor, 0.8);
      expect(config.source.clearcoatRoughnessFactor, 0.2);
      expect(
          root.mesh!.primitives.single.material, isNot(same(sourceMaterial)));
      expect(
        runtimeAdapter.materialExtensionSupport.backendKind,
        MaterialExtensionBackendKind.packageLocalCandidate,
      );
    });

    test('combined clearcoat sheen retains coat transforms across sparse delta',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'CoatedFabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final nativeSupport = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.clearcoat:
              MaterialExtensionFeatureSupport(available: true),
        },
      );
      final address = PartAddress(
        nodePath: const <String>['CoatedFabric'],
        primitiveIndex: 0,
      );
      final clearcoatBinding = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'clearcoat'),
        transform: TextureTransform(
          offset: const <double>[0.1, 0.2],
          scale: const <double>[2, 3],
        ),
      );
      final roughnessBinding = MaterialTextureBinding(
        source: TextureSource.bytes(
          _onePixelPng,
          debugName: 'clearcoat-roughness',
        ),
        transform: TextureTransform(
          offset: const <double>[0.4, 0.5],
          scale: const <double>[0.25, 0.75],
        ),
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(
          sheenColorFactor: const <double>[0.4, 0.3, 0.2],
          sheenRoughness: 0.55,
          clearcoat: 0.8,
          clearcoatTextureBinding: clearcoatBinding,
          clearcoatRoughness: 0.2,
          clearcoatRoughnessTextureBinding: roughnessBinding,
        ),
        materialExtensionSupport: nativeSupport,
        runtimeAdapter: runtimeAdapter,
      );
      final sparseDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(roughness: 0.35),
        materialExtensionSupport: nativeSupport,
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(sparseDiagnostics, isEmpty);
      expect(extendedBackend.configs, hasLength(2));
      final retained = extendedBackend.configs.last;
      expect(
        retained.transforms[MaterialTextureSlot.clearcoat],
        clearcoatBinding.transform,
      );
      expect(
        retained.transforms[MaterialTextureSlot.clearcoatRoughness],
        roughnessBinding.transform,
      );
      expect(
        retained.source.clearcoatTexture,
        same(textureFactory.createdSources[0]),
      );
      expect(
        retained.source.clearcoatRoughnessTexture,
        same(textureFactory.createdSources[1]),
      );
      expect(retained.source.clearcoatFactor, 0.8);
      expect(retained.source.clearcoatRoughnessFactor, 0.2);
      expect(retained.source.roughnessFactor, 0.35);

      final resetDiagnostics = await runtimeAdapter.resetMaterial(address);
      expect(resetDiagnostics, isEmpty);
      expect(root.mesh!.primitives.single.material, same(sourceMaterial));
    });

    test('native clearcoat delta keeps the active transformed PBR state',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final address = PartAddress(
        nodePath: const <String>['Body'],
        primitiveIndex: 0,
      );
      final transformedBaseColor = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.clearcoat:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(baseColorTextureBinding: transformedBaseColor),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );
      final clearcoatDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(clearcoat: 0.8, clearcoatRoughness: 0.2),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(clearcoatDiagnostics, isEmpty);
      expect(extendedBackend.configs, hasLength(2));
      expect(
        extendedBackend.configs.last.transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(extendedBackend.configs.last.source.clearcoatFactor, 0.8);
      expect(
        extendedBackend.configs.last.source.clearcoatRoughnessFactor,
        0.2,
      );
      final material = root.mesh!.primitives.single.material;
      expect(material, isA<FlutterSceneExtendedPbrState>());
      expect(
        (material as FlutterSceneExtendedPbrState)
            .transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(
        (material as flutter_scene.PhysicallyBasedMaterial).clearcoatFactor,
        0.8,
      );
      expect(sourceMaterial.clearcoatFactor, 0.0);
    });

    test('native sheen delta keeps the active transformed PBR state', () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Fabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final address = PartAddress(
        nodePath: const <String>['Fabric'],
        primitiveIndex: 0,
      );
      final transformedBaseColor = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(baseColorTextureBinding: transformedBaseColor),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );
      final sheenDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(
          sheenColorFactor: <double>[0.2, 0.4, 0.8],
          sheenRoughness: 0.35,
        ),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(sheenDiagnostics, isEmpty);
      expect(extendedBackend.configs, hasLength(2));
      final retained = extendedBackend.configs.last;
      expect(
        retained.transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(retained.sheenColorFactor, <double>[0.2, 0.4, 0.8]);
      expect(retained.sheenRoughness, 0.35);
      final material = root.mesh!.primitives.single.material;
      expect(material, isA<FlutterSceneExtendedPbrState>());
      expect(
        (material as FlutterSceneExtendedPbrState)
            .transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(sourceMaterial.sheenColorFactor, vm.Vector3.zero());
    });

    test('native sheen source keeps complete state across package-owned routes',
        () async {
      const colorTransform = flutter_scene.MaterialTextureTransform(
        offsetX: 0.1,
        offsetY: 0.2,
        rotation: 0.3,
        scaleX: 1.5,
        scaleY: 0.75,
      );
      const roughnessTransform = flutter_scene.MaterialTextureTransform(
        offsetX: 0.4,
        offsetY: 0.5,
        rotation: 0.6,
        scaleX: 0.5,
        scaleY: 2.0,
      );
      final routes = <(String, MaterialPatch)>[
        (
          'transformedCore',
          MaterialPatch(
            baseColorTextureBinding: MaterialTextureBinding(
              source: TextureSource.bytes(
                _onePixelPng,
                debugName: 'native-sheen-transformed-core',
              ),
              transform: TextureTransform(
                scale: <double>[2.5, 2.5],
              ),
            ),
          ),
        ),
        ('specular', const MaterialPatch(specular: 0.7)),
        ('opaqueIor', const MaterialPatch(ior: 1.8)),
      ];
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      for (final (route, patch) in routes) {
        final textureFactory = _RecordingTextureFactory();
        final extendedBackend = _RecordingExtendedPbrBackend();
        final sheenColorTexture = _StubTextureSource(
          const flutter_scene.TextureSampling().toSamplerOptions(),
        );
        final sheenRoughnessTexture = _StubTextureSource(
          const flutter_scene.TextureSampling().toSamplerOptions(),
        );
        final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
          ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
          ..sheenColorTexture = sheenColorTexture
          ..sheenColorTextureTexCoord = 0
          ..sheenColorTextureTransform = colorTransform
          ..sheenRoughnessFactor = 0.35
          ..sheenRoughnessTexture = sheenRoughnessTexture
          ..sheenRoughnessTextureTexCoord = 0
          ..sheenRoughnessTextureTransform = roughnessTransform;
        final root = flutter_scene.Node(
          name: 'Fabric',
          mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
        );
        final runtimeAdapter = FlutterSceneRuntimeAdapter(
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(
            enableSheen: true,
          ),
          textureFactory: textureFactory,
          extendedPbrBackend: extendedBackend,
        );
        final address = PartAddress(
          nodePath: const <String>['Fabric'],
          primitiveIndex: 0,
        );

        final diagnostics = await debugApplyMaterialPatchToRoot(
          root,
          address,
          patch,
          materialExtensionSupport: support,
          runtimeAdapter: runtimeAdapter,
        );

        expect(diagnostics, isEmpty, reason: route);
        expect(extendedBackend.sheenRequests, hasLength(1), reason: route);
        expect(
          extendedBackend.sheenRequests.single.hasSheenColorTexture,
          isTrue,
          reason: route,
        );
        expect(
          extendedBackend.sheenRequests.single.hasSheenRoughnessTexture,
          isTrue,
          reason: route,
        );
        expect(extendedBackend.configs, hasLength(1), reason: route);
        final config = extendedBackend.configs.single;
        expect(config.hasSheenIntent, isTrue, reason: route);
        expect(config.sheenColorFactor[0], closeTo(0.2, 0.0001), reason: route);
        expect(config.sheenColorFactor[1], closeTo(0.4, 0.0001), reason: route);
        expect(config.sheenColorFactor[2], closeTo(0.8, 0.0001), reason: route);
        expect(config.sheenRoughness, 0.35, reason: route);
        expect(config.sheenColorTexture, same(sheenColorTexture),
            reason: route);
        expect(
          config.sheenRoughnessTexture,
          same(sheenRoughnessTexture),
          reason: route,
        );
        expect(
          config.transforms[MaterialTextureSlot.sheenColor]!.toJson(),
          TextureTransform(
            offset: <double>[0.1, 0.2],
            rotation: 0.3,
            scale: <double>[1.5, 0.75],
          ).toJson(),
          reason: route,
        );
        expect(
          config.transforms[MaterialTextureSlot.sheenRoughness]!.toJson(),
          TextureTransform(
            offset: <double>[0.4, 0.5],
            rotation: 0.6,
            scale: <double>[0.5, 2.0],
          ).toJson(),
          reason: route,
        );
        final retained = root.mesh!.primitives.single.material;
        expect(retained, isA<FlutterSceneExtendedPbrState>(), reason: route);
        final retainedState = retained as FlutterSceneExtendedPbrState;
        expect(retainedState.hasSheenIntent, isTrue, reason: route);
        expect(
          retainedState.sheenColorFactor[0],
          closeTo(0.2, 0.0001),
          reason: route,
        );
        expect(
          retainedState.sheenColorFactor[1],
          closeTo(0.4, 0.0001),
          reason: route,
        );
        expect(
          retainedState.sheenColorFactor[2],
          closeTo(0.8, 0.0001),
          reason: route,
        );
        expect(retainedState.sheenRoughness, 0.35, reason: route);
        expect(
          retainedState.sheenColorTexture,
          same(sheenColorTexture),
          reason: route,
        );
        expect(
          retainedState.sheenRoughnessTexture,
          same(sheenRoughnessTexture),
          reason: route,
        );
        expect(
          retainedState.transforms[MaterialTextureSlot.sheenColor]!.toJson(),
          config.transforms[MaterialTextureSlot.sheenColor]!.toJson(),
          reason: route,
        );
        expect(
          retainedState.transforms[MaterialTextureSlot.sheenRoughness]!
              .toJson(),
          config.transforms[MaterialTextureSlot.sheenRoughness]!.toJson(),
          reason: route,
        );
        expect(sourceMaterial.sheenColorTexture, same(sheenColorTexture));
        expect(
          sourceMaterial.sheenRoughnessTexture,
          same(sheenRoughnessTexture),
        );
      }
    });

    test('native sheen UV1 rejects package-owned routing atomically', () async {
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      for (final slot in <MaterialTextureSlot>[
        MaterialTextureSlot.sheenColor,
        MaterialTextureSlot.sheenRoughness,
      ]) {
        final textureFactory = _RecordingTextureFactory();
        final extendedBackend = _RecordingExtendedPbrBackend();
        final sheenTexture = _StubTextureSource(
          const flutter_scene.TextureSampling().toSamplerOptions(),
        );
        final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
          ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8);
        if (slot == MaterialTextureSlot.sheenColor) {
          sourceMaterial
            ..sheenColorTexture = sheenTexture
            ..sheenColorTextureTexCoord = 1;
        } else {
          sourceMaterial
            ..sheenRoughnessTexture = sheenTexture
            ..sheenRoughnessTextureTexCoord = 1;
        }
        final root = flutter_scene.Node(
          name: 'Fabric',
          mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
        );
        final runtimeAdapter = FlutterSceneRuntimeAdapter(
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(
            enableSheen: true,
          ),
          textureFactory: textureFactory,
          extendedPbrBackend: extendedBackend,
        );
        final address = PartAddress(
          nodePath: const <String>['Fabric'],
          primitiveIndex: 0,
        );

        final diagnostics = await debugApplyMaterialPatchToRoot(
          root,
          address,
          MaterialPatch(
            baseColorTextureBinding: MaterialTextureBinding(
              source: TextureSource.bytes(
                _onePixelPng,
                debugName: 'must-not-decode-${slot.name}',
              ),
              transform: TextureTransform(scale: const <double>[2, 2]),
            ),
          ),
          materialExtensionSupport: support,
          runtimeAdapter: runtimeAdapter,
        );

        expect(diagnostics, hasLength(1), reason: slot.name);
        expect(
          diagnostics.single.details['limitation'],
          'perSlotTextureCoordinateContractMissing',
          reason: slot.name,
        );
        expect(diagnostics.single.details['slot'], slot.name);
        expect(diagnostics.single.details['texCoord'], 1);
        expect(diagnostics.single.details['decodedTextureCount'], 0);
        expect(diagnostics.single.details['materialReplaced'], isFalse);
        expect(textureFactory.createdSources, isEmpty, reason: slot.name);
        expect(extendedBackend.sheenRequests, isEmpty, reason: slot.name);
        expect(extendedBackend.configs, isEmpty, reason: slot.name);
        expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      }
    });

    test('same-delta sheen UV1 rejects package-owned routing atomically',
        () async {
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      for (final slot in <MaterialTextureSlot>[
        MaterialTextureSlot.sheenColor,
        MaterialTextureSlot.sheenRoughness,
      ]) {
        final textureFactory = _RecordingTextureFactory();
        final extendedBackend = _RecordingExtendedPbrBackend();
        final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
        final root = flutter_scene.Node(
          name: 'Fabric',
          mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
        );
        final runtimeAdapter = FlutterSceneRuntimeAdapter(
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(
            enableSheen: true,
          ),
          textureFactory: textureFactory,
          extendedPbrBackend: extendedBackend,
        );
        final baseColorBinding = MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'must-not-decode-base-${slot.name}',
          ),
          transform: TextureTransform(scale: const <double>[2, 2]),
        );
        final sheenBinding = MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'must-not-decode-${slot.name}',
          ),
          texCoord: 1,
        );
        final patch = switch (slot) {
          MaterialTextureSlot.sheenColor => MaterialPatch(
              baseColorTextureBinding: baseColorBinding,
              sheenColorFactor: const <double>[0.2, 0.4, 0.8],
              sheenColorTextureBinding: sheenBinding,
            ),
          MaterialTextureSlot.sheenRoughness => MaterialPatch(
              baseColorTextureBinding: baseColorBinding,
              sheenColorFactor: const <double>[0.2, 0.4, 0.8],
              sheenRoughness: 0.35,
              sheenRoughnessTextureBinding: sheenBinding,
            ),
          _ => throw StateError('unexpected sheen slot'),
        };

        final diagnostics = await debugApplyMaterialPatchToRoot(
          root,
          PartAddress(
            nodePath: const <String>['Fabric'],
            primitiveIndex: 0,
          ),
          patch,
          materialExtensionSupport: support,
          runtimeAdapter: runtimeAdapter,
        );

        expect(diagnostics, hasLength(1), reason: slot.name);
        expect(
          diagnostics.single.details['limitation'],
          'perSlotTextureCoordinateContractMissing',
          reason: slot.name,
        );
        expect(diagnostics.single.details['slot'], slot.name);
        expect(diagnostics.single.details['texCoord'], 1);
        expect(textureFactory.createdSources, isEmpty, reason: slot.name);
        expect(extendedBackend.configs, isEmpty, reason: slot.name);
        expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      }
    });

    test('renderer-native sheen UV1 requires an authored UV1 channel',
        () async {
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      for (final slot in <MaterialTextureSlot>[
        MaterialTextureSlot.sheenColor,
        MaterialTextureSlot.sheenRoughness,
      ]) {
        final textureFactory = _RecordingTextureFactory();
        final extendedBackend = _RecordingExtendedPbrBackend();
        final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
        final root = flutter_scene.Node(
          name: 'Fabric',
          mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
        );
        final runtimeAdapter = FlutterSceneRuntimeAdapter(
          materialExtensionPolicy:
              const ViewerMaterialExtensionPolicy.productionShaders(
            enableSheen: true,
          ),
          textureFactory: textureFactory,
          extendedPbrBackend: extendedBackend,
        );
        final binding = MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'must-not-decode-${slot.name}',
          ),
          texCoord: 1,
        );
        final patch = switch (slot) {
          MaterialTextureSlot.sheenColor => MaterialPatch(
              sheenColorFactor: const <double>[0.2, 0.4, 0.8],
              sheenColorTextureBinding: binding,
            ),
          MaterialTextureSlot.sheenRoughness => MaterialPatch(
              sheenColorFactor: const <double>[0.2, 0.4, 0.8],
              sheenRoughness: 0.35,
              sheenRoughnessTextureBinding: binding,
            ),
          _ => throw StateError('unexpected sheen slot'),
        };

        final diagnostics = await debugApplyMaterialPatchToRoot(
          root,
          PartAddress(
            nodePath: const <String>['Fabric'],
            primitiveIndex: 0,
          ),
          patch,
          materialExtensionSupport: support,
          runtimeAdapter: runtimeAdapter,
        );

        expect(diagnostics, hasLength(1), reason: slot.name);
        expect(
          diagnostics.single.code,
          ViewerDiagnosticCode.missingUvSet,
          reason: slot.name,
        );
        expect(diagnostics.single.details['uvSet'], 1, reason: slot.name);
        expect(diagnostics.single.details['slot'], slot.name);
        expect(diagnostics.single.details['status'], 'blocked');
        expect(diagnostics.single.details['decodedTextureCount'], 0);
        expect(diagnostics.single.details['materialReplaced'], isFalse);
        expect(textureFactory.createdSources, isEmpty, reason: slot.name);
        expect(extendedBackend.sheenRequests, isEmpty, reason: slot.name);
        expect(extendedBackend.configs, isEmpty, reason: slot.name);
        expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      }
    });

    test('native sheen UV1 allows same-slot UV0 replacement', () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final retainedTexture = _StubTextureSource(
        const flutter_scene.TextureSampling().toSamplerOptions(),
      );
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
        ..sheenColorTexture = retainedTexture
        ..sheenColorTextureTexCoord = 1;
      final root = flutter_scene.Node(
        name: 'Fabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.sheen:
              MaterialExtensionFeatureSupport(available: true),
        },
      );
      final replacementBinding = MaterialTextureBinding(
        source: TextureSource.bytes(
          _onePixelPng,
          debugName: 'replacement-sheen-color',
        ),
        texCoord: 0,
        transform: TextureTransform(offset: const <double>[0.25, 0.5]),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Fabric'],
          primitiveIndex: 0,
        ),
        MaterialPatch(
          specular: 0.7,
          sheenColorTextureBinding: replacementBinding,
        ),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, isEmpty);
      expect(textureFactory.createdSources, hasLength(1));
      expect(extendedBackend.configs, hasLength(1));
      expect(
        extendedBackend.configs.single.sheenColorTexture,
        same(textureFactory.createdSources.single),
      );
      expect(
        extendedBackend
            .configs.single.transforms[MaterialTextureSlot.sheenColor],
        same(replacementBinding.transform),
      );
      expect(sourceMaterial.sheenColorTexture, same(retainedTexture));
      expect(sourceMaterial.sheenColorTextureTexCoord, 1);
    });

    test('native material copy preserves complete authored sheen state',
        () async {
      final sheenColorTexture = _StubTextureSource(
        const flutter_scene.TextureSampling().toSamplerOptions(),
      );
      final sheenRoughnessTexture = _StubTextureSource(
        const flutter_scene.TextureSampling().toSamplerOptions(),
      );
      const colorTransform = flutter_scene.MaterialTextureTransform(
        offsetX: 0.1,
        offsetY: 0.2,
        rotation: 0.3,
        scaleX: 1.5,
        scaleY: 0.75,
      );
      const roughnessTransform = flutter_scene.MaterialTextureTransform(
        offsetX: 0.4,
        offsetY: 0.5,
        rotation: 0.6,
        scaleX: 0.5,
        scaleY: 2.0,
      );
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..sheenColorFactor = vm.Vector3(0.2, 0.4, 0.8)
        ..sheenColorTexture = sheenColorTexture
        ..sheenColorTextureTexCoord = 1
        ..sheenColorTextureTransform = colorTransform
        ..sheenRoughnessFactor = 0.35
        ..sheenRoughnessTexture = sheenRoughnessTexture
        ..sheenRoughnessTextureTexCoord = 0
        ..sheenRoughnessTextureTransform = roughnessTransform;
      final root = flutter_scene.Node(
        name: 'CoatedFabric',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          for (final feature in <MaterialExtensionFeature>[
            MaterialExtensionFeature.clearcoat,
            MaterialExtensionFeature.sheen,
          ])
            feature: MaterialExtensionFeatureSupport(available: true),
        },
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['CoatedFabric'],
          primitiveIndex: 0,
        ),
        const MaterialPatch(clearcoat: 0.7),
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(
          enableSheen: true,
        ),
        materialExtensionSupport: support,
      );

      expect(diagnostics, isEmpty);
      final copied = root.mesh!.primitives.single.material
          as flutter_scene.PhysicallyBasedMaterial;
      expect(copied, isNot(same(sourceMaterial)));
      expect(copied.sheenColorFactor.x, closeTo(0.2, 0.0001));
      expect(copied.sheenColorFactor.y, closeTo(0.4, 0.0001));
      expect(copied.sheenColorFactor.z, closeTo(0.8, 0.0001));
      expect(copied.sheenColorTexture, same(sheenColorTexture));
      expect(copied.sheenColorTextureTexCoord, 1);
      expect(copied.sheenColorTextureTransform, colorTransform);
      expect(copied.sheenRoughnessFactor, 0.35);
      expect(copied.sheenRoughnessTexture, same(sheenRoughnessTexture));
      expect(copied.sheenRoughnessTextureTexCoord, 0);
      expect(copied.sheenRoughnessTextureTransform, roughnessTransform);
      expect(copied.clearcoatFactor, 0.7);
    });

    test('failed native clearcoat composition keeps transformed state atomic',
        () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _FailingSecondExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.productionShaders(),
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );
      final address = PartAddress(
        nodePath: const <String>['Body'],
        primitiveIndex: 0,
      );
      final transformedBaseColor = MaterialTextureBinding(
        source: TextureSource.bytes(_onePixelPng, debugName: 'repeat-2.5'),
        transform: TextureTransform(scale: const <double>[2.5, 2.5]),
      );
      final support = MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.clearcoat:
              MaterialExtensionFeatureSupport(available: true),
        },
      );

      final initialDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        MaterialPatch(baseColorTextureBinding: transformedBaseColor),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );
      final transformedMaterial = root.mesh!.primitives.single.material;
      final clearcoatDiagnostics = await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(clearcoat: 0.8),
        materialExtensionSupport: support,
        runtimeAdapter: runtimeAdapter,
      );

      expect(initialDiagnostics, isEmpty);
      expect(clearcoatDiagnostics, hasLength(1));
      expect(
        clearcoatDiagnostics.single.details['limitation'],
        'extendedPbrMaterialConstructionFailed',
      );
      expect(
        clearcoatDiagnostics.single.details['materialReplaced'],
        isFalse,
      );
      expect(root.mesh!.primitives.single.material, same(transformedMaterial));
      expect(
        (transformedMaterial as FlutterSceneExtendedPbrState)
            .transforms[MaterialTextureSlot.baseColor],
        transformedBaseColor.transform,
      );
      expect(
        (transformedMaterial as flutter_scene.PhysicallyBasedMaterial)
            .clearcoatFactor,
        0.0,
      );
      expect(sourceMaterial.clearcoatFactor, 0.0);
    });

    test('identity core texture stays on the native material', () async {
      final textureFactory = _RecordingTextureFactory();
      final extendedBackend = _RecordingExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        textureFactory: textureFactory,
        extendedPbrBackend: extendedBackend,
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Body'],
          primitiveIndex: 0,
        ),
        MaterialPatch(
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'identity'),
          ),
        ),
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, isEmpty);
      expect(extendedBackend.preflightCount, 0);
      expect(extendedBackend.configs, isEmpty);
      expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      expect(sourceMaterial.baseColorTexture,
          same(textureFactory.createdSources.single));
    });

    test('invalid extended backend result leaves live state unchanged',
        () async {
      final backend = _InvalidExtendedPbrBackend();
      final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.2
        ..roughnessFactor = 0.7;
      final geometry = _UvStubGeometry();
      final root = flutter_scene.Node(
        name: 'Body',
        mesh: flutter_scene.Mesh(geometry, sourceMaterial),
      );
      final runtimeAdapter = FlutterSceneRuntimeAdapter(
        extendedPbrBackend: backend,
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Body'],
          primitiveIndex: 0,
        ),
        MaterialPatch(
          baseColorFactor: const <double>[0.1, 0.2, 0.3, 1],
          specular: 0.6,
          visible: false,
        ),
        runtimeAdapter: runtimeAdapter,
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.details['limitation'],
          'extendedPbrMaterialConstructionFailed');
      expect(diagnostics.single.details['materialReplaced'], isFalse);
      expect(root.mesh!.primitives.single.material, same(sourceMaterial));
      expect(root.mesh!.primitives.single.geometry, same(geometry));
      expect(root.visible, isTrue);
      expect(sourceMaterial.baseColorFactor.x, 1);
      expect(sourceMaterial.metallicFactor, 0.2);
      expect(sourceMaterial.roughnessFactor, 0.7);
    });
  });

  test('binding-only transmission and thickness require feature support', () {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders();
    final transmissionBinding = MaterialPatch(
      transmissionTextureBinding: MaterialTextureBinding(
        source: const TextureSource.asset('assets/transmission.png'),
      ),
    );
    final thicknessBinding = MaterialPatch(
      thicknessTextureBinding: MaterialTextureBinding(
        source: const TextureSource.asset('assets/thickness.png'),
      ),
    );
    final volumeOnly = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.volume:
            MaterialExtensionFeatureSupport(available: true),
      },
    );
    final transmissionOnly = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.transmission:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    expect(
      debugUsesMaterialExtensionBackendFor(
        policy,
        transmissionBinding,
        support: volumeOnly,
      ),
      isFalse,
    );
    expect(
      debugUsesMaterialExtensionBackendFor(
        policy,
        thicknessBinding,
        support: transmissionOnly,
      ),
      isFalse,
    );
  });

  test('native capability checks binding-only transmission and thickness', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.ior:
            MaterialExtensionFeatureSupport(available: true),
        MaterialExtensionFeature.clearcoat:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    for (final patch in <MaterialPatch>[
      MaterialPatch(
        transmissionTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/transmission.png'),
        ),
      ),
      MaterialPatch(
        thicknessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/thickness.png'),
        ),
      ),
    ]) {
      expect(
        debugUsesNativeMaterialExtensionApplierFor(
          policy,
          patch,
          support: support,
        ),
        isFalse,
      );
    }
  });

  test('native preflight accepts selected extension textures', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    final support = _materialExtensionSupport(
      MaterialExtensionBackendKind.rendererNative,
    );

    for (final patch in <MaterialPatch>[
      MaterialPatch(
        transmissionTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/transmission.png'),
        ),
      ),
      MaterialPatch(
        thicknessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/thickness.png'),
        ),
      ),
    ]) {
      expect(
        debugUsesNativeMaterialExtensionApplierFor(
          policy,
          patch,
          support: support,
        ),
        isTrue,
      );
    }

    for (final patch in <MaterialPatch>[
      MaterialPatch(
        clearcoatTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat.png'),
        ),
      ),
      MaterialPatch(
        clearcoatRoughnessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-roughness.png'),
        ),
      ),
      MaterialPatch(
        clearcoatNormalTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-normal.png'),
        ),
      ),
    ]) {
      expect(
        debugUsesNativeMaterialExtensionApplierFor(
          policy,
          patch,
          support: support,
        ),
        isTrue,
      );
    }
  });

  test('unavailable extended shader rejects native specular intent before load',
      () async {
    final factory = _RecordingTextureFactory();
    final extendedBackend = _UnavailableExtendedPbrBackend();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Paint'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        specularTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/specular.png'),
        ),
        specularColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/specular-color.png'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      materialExtensionSupport: _materialExtensionSupport(
        MaterialExtensionBackendKind.rendererNative,
      ),
      textureFactory: factory,
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        textureFactory: factory,
        extendedPbrBackend: extendedBackend,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'extendedPbrShaderUnavailable');
    expect(factory.paths, isEmpty);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
  });

  test('sheen resource preflight fails before texture decode and mutation',
      () async {
    final factory = _RecordingTextureFactory();
    final extendedBackend = _UnavailableSheenExtendedPbrBackend();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..roughnessFactor = 0.8;
    final root = flutter_scene.Node(
      name: 'Fabric',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    final address = PartAddress(
      nodePath: const <String>['Fabric'],
      primitiveIndex: 0,
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableSheen: true,
      ),
      textureFactory: factory,
      extendedPbrBackend: extendedBackend,
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        baseColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/base-color.png'),
        ),
        sheenColorFactor: const <double>[0.4, 0.5, 0.6],
        sheenColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/sheen-color.png'),
        ),
        sheenRoughness: 0.7,
        sheenRoughnessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/sheen-roughness.png'),
        ),
      ),
      runtimeAdapter: runtimeAdapter,
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.details['limitation'],
      'sheenDirectionalAlbedoResourceUnavailable',
    );
    expect(diagnostics.single.details['decodedTextureCount'], 0);
    expect(diagnostics.single.details['materialReplaced'], isFalse);
    expect(extendedBackend.requests, hasLength(1));
    expect(extendedBackend.requests.single.hasSheenColorTexture, isTrue);
    expect(extendedBackend.requests.single.hasSheenRoughnessTexture, isTrue);
    expect(factory.paths, isEmpty);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.roughnessFactor, 0.8);
  });

  test('combined sheen reports retained transmission volume before decode',
      () async {
    final factory = _RecordingTextureFactory();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..clearcoatFactor = 0.8
      ..transmissionFactor = 0.5
      ..thicknessFactor = 0.25;
    final root = flutter_scene.Node(
      name: 'CoatedGlassFabric',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    final address = PartAddress(
      nodePath: const <String>['CoatedGlassFabric'],
      primitiveIndex: 0,
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      textureFactory: factory,
      extendedPbrBackend: FlutterSceneExtendedPbrBackend(
        loadShader: (_, __) async =>
            throw StateError('resource diagnostic must precede shader load'),
      ),
    );
    final nativeSupport = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        for (final feature in <MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
          MaterialExtensionFeature.clearcoat,
        ])
          feature: MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        baseColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/base-color.png'),
        ),
        sheenColorFactor: const <double>[0.4, 0.5, 0.6],
        sheenRoughness: 0.7,
      ),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: runtimeAdapter,
    );

    expect(diagnostics, hasLength(1));
    final diagnostic = diagnostics.single;
    expect(
      diagnostic.details['limitation'],
      'sheenCompositionStateIncompatible',
    );
    expect(
      diagnostic.details['selectedVariant'],
      'FSViewerClearcoatSheenExtendedPbr',
    );
    expect(diagnostic.details['portableLimit'], 16);
    expect(diagnostic.details['requestedSamplerCount'], 12);
    expect(
      diagnostic.details['incompatibleState'],
      <String>['transmission', 'volume'],
    );
    expect(diagnostic.details['decodedTextureCount'], 0);
    expect(diagnostic.details['materialReplaced'], isFalse);
    expect(factory.paths, isEmpty);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.transmissionFactor, 0.5);
    expect(originalMaterial.thicknessFactor, 0.25);
  });

  test('combined sheen reports same-delta transmission volume before decode',
      () async {
    final factory = _RecordingTextureFactory();
    final backend = _ResourceCheckingSheenExtendedPbrBackend();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'CoatedGlassFabric',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    final address = PartAddress(
      nodePath: const <String>['CoatedGlassFabric'],
      primitiveIndex: 0,
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(
        enableSheen: true,
      ),
      textureFactory: factory,
      extendedPbrBackend: backend,
    );
    final nativeSupport = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        for (final feature in <MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
          MaterialExtensionFeature.clearcoat,
        ])
          feature: MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        baseColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/base-color.png'),
        ),
        sheenColorFactor: const <double>[0.4, 0.5, 0.6],
        sheenRoughness: 0.7,
        clearcoat: 0.8,
        transmission: 0.5,
        thickness: 0.25,
      ),
      materialExtensionSupport: nativeSupport,
      runtimeAdapter: runtimeAdapter,
    );

    expect(diagnostics, hasLength(1));
    final diagnostic = diagnostics.single;
    expect(
      diagnostic.details['limitation'],
      'sheenCompositionStateIncompatible',
    );
    expect(
      diagnostic.details['selectedVariant'],
      'FSViewerClearcoatSheenExtendedPbr',
    );
    expect(
      diagnostic.details['incompatibleState'],
      <String>['transmission', 'volume'],
    );
    expect(diagnostic.details['decodedTextureCount'], 0);
    expect(diagnostic.details['materialReplaced'], isFalse);
    expect(backend.requests, hasLength(1));
    expect(backend.requests.single.hasTransmissionState, isTrue);
    expect(backend.requests.single.hasVolumeState, isTrue);
    expect(factory.paths, isEmpty);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.clearcoatFactor, 0);
    expect(originalMaterial.transmissionFactor, 0);
    expect(originalMaterial.thicknessFactor, 0);
  });

  test(
      'specular patch rejects existing native transmission and volume atomically',
      () async {
    final extendedBackend = _RecordingExtendedPbrBackend();
    final transmissionTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final thicknessTexture = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    const transmissionTransform = flutter_scene.MaterialTextureTransform(
      offsetX: 0.1,
      offsetY: 0.2,
      rotation: 0.3,
      scaleX: 0.8,
      scaleY: 0.9,
    );
    const thicknessTransform = flutter_scene.MaterialTextureTransform(
      offsetX: 0.4,
      offsetY: 0.5,
      rotation: 0.6,
      scaleX: 0.7,
      scaleY: 0.75,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..transmissionFactor = 0.82
      ..transmissionTexture = transmissionTexture
      ..transmissionTextureTransform = transmissionTransform
      ..ior = 1.37
      ..thicknessFactor = 0.42
      ..thicknessTexture = thicknessTexture
      ..thicknessTextureTransform = thicknessTransform
      ..attenuationDistance = 3.5
      ..attenuationColor = vm.Vector3(0.7, 0.8, 0.9);
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      const MaterialPatch(specular: 0.7),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      materialExtensionSupport: _materialExtensionSupport(
        MaterialExtensionBackendKind.rendererNative,
      ),
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        extendedPbrBackend: extendedBackend,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.details['limitation'],
      'extendedPbrNativeTransmissionVolumeCombinationUnsupported',
    );
    expect(diagnostics.single.details['materialReplaced'], isFalse);
    expect(extendedBackend.preflightCount, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.transmissionFactor, 0.82);
    expect(originalMaterial.transmissionTexture, same(transmissionTexture));
    expect(originalMaterial.transmissionTextureTransform.offsetX, 0.1);
    expect(originalMaterial.transmissionTextureTransform.offsetY, 0.2);
    expect(originalMaterial.transmissionTextureTransform.rotation, 0.3);
    expect(originalMaterial.transmissionTextureTransform.scaleX, 0.8);
    expect(originalMaterial.transmissionTextureTransform.scaleY, 0.9);
    expect(originalMaterial.ior, 1.37);
    expect(originalMaterial.thicknessFactor, 0.42);
    expect(originalMaterial.thicknessTexture, same(thicknessTexture));
    expect(originalMaterial.thicknessTextureTransform.offsetX, 0.4);
    expect(originalMaterial.thicknessTextureTransform.offsetY, 0.5);
    expect(originalMaterial.thicknessTextureTransform.rotation, 0.6);
    expect(originalMaterial.thicknessTextureTransform.scaleX, 0.7);
    expect(originalMaterial.thicknessTextureTransform.scaleY, 0.75);
    expect(originalMaterial.attenuationDistance, 3.5);
    expect(originalMaterial.attenuationColor, vm.Vector3(0.7, 0.8, 0.9));
  });

  test('unavailable extended shader rejects candidate specular before mutation',
      () async {
    final factory = _RecordingTextureFactory();
    final extendedBackend = _UnavailableExtendedPbrBackend();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.specular:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Paint'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        specular: 0.6,
        specularTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/specular.png'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionSupport: support,
      textureFactory: factory,
      runtimeAdapter: FlutterSceneRuntimeAdapter(
        textureFactory: factory,
        extendedPbrBackend: extendedBackend,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['limitation'],
        'extendedPbrShaderUnavailable');
    expect(factory.paths, isEmpty);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
  });

  test('adapter stages mixed core and native extension intent atomically',
      () async {
    final factory = _RecordingTextureFactory();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Glass'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'base-color'),
        ),
        transmission: 0.8,
        transmissionTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'transmission',
          ),
          transform: TextureTransform(
            offset: <double>[0.1, 0.2],
            rotation: 0.3,
          ),
        ),
        ior: 1.4,
        thickness: 0.25,
        thicknessTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'thickness'),
          transform: TextureTransform(scale: const <double>[0.5, 0.75]),
        ),
        attenuationDistance: 2.0,
        attenuationColor: const <double>[0.8, 0.9, 1.0],
        clearcoat: 0.6,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      materialExtensionSupport: _materialExtensionSupport(
        MaterialExtensionBackendKind.rendererNative,
      ),
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(factory.paths, <String>['fromImage', 'fromImage', 'fromImage']);
    final material = root.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(material, isNot(same(originalMaterial)));
    expect(material.baseColorFactor.x, closeTo(0.2, 1e-6));
    expect(material.baseColorTexture, same(factory.createdSources[0]));
    expect(material.transmissionFactor, 0.8);
    expect(material.transmissionTexture, same(factory.createdSources[1]));
    expect(material.transmissionTextureTransform.offsetX, 0.1);
    expect(material.transmissionTextureTransform.offsetY, 0.2);
    expect(material.transmissionTextureTransform.rotation, 0.3);
    expect(material.ior, 1.4);
    expect(material.thicknessFactor, 0.25);
    expect(material.thicknessTexture, same(factory.createdSources[2]));
    expect(material.thicknessTextureTransform.scaleX, 0.5);
    expect(material.thicknessTextureTransform.scaleY, 0.75);
    expect(material.attenuationDistance, 2.0);
    expect(material.attenuationColor, vm.Vector3(0.8, 0.9, 1.0));
    expect(material.clearcoatFactor, 0.6);
    expect(originalMaterial.baseColorFactor.x, 1.0);
    expect(originalMaterial.transmissionFactor, 0.0);
  });

  test('adapter forwards loaded occlusion and emissive to clearcoat config',
      () async {
    final factory = _RecordingTextureFactory();
    FlutterSceneClearcoatMaterialConfig? captured;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (config) async {
        captured = config;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    const clamp = TextureSampler(
      wrapS: TextureWrapMode.clampToEdge,
      wrapT: TextureWrapMode.clampToEdge,
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        clearcoat: 1.0,
        occlusionTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'occlusion'),
          sampler: clamp,
        ),
        emissiveTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'emissive'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(captured, isNotNull);
    expect(captured!.emissiveTexture, same(factory.createdSources[0]));
    expect(captured!.occlusionTexture, same(factory.createdSources[1]));
    expect(
      (captured!.emissiveTexture as flutter_scene.TextureSource)
          .sampledSampler
          .widthAddressMode,
      flutter_scene_internal_gpu.SamplerAddressMode.repeat,
    );
    expect(
      (captured!.occlusionTexture as flutter_scene.TextureSource)
          .sampledSampler
          .widthAddressMode,
      flutter_scene_internal_gpu.SamplerAddressMode.clampToEdge,
    );
  });

  test('candidate clearcoat applies core PBR fields after overlay succeeds',
      () async {
    final factory = _RecordingTextureFactory();
    FlutterSceneClearcoatMaterialConfig? capturedConfig;
    late final flutter_scene.ShaderMaterial overlayMaterial;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (config) async {
        capturedConfig = config;
        return overlayMaterial =
            flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      },
    );
    final originalSourceNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = originalSourceNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    MaterialTextureBinding binding(String name) => MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: name),
        );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        clearcoat: 0.8,
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        baseColorTextureBinding: binding('baseColor'),
        metallicRoughnessTextureBinding: binding('metallicRoughness'),
        normalTextureBinding: binding('normal'),
        normalScale: 0.5,
        metallic: 0.25,
        roughness: 0.6,
        occlusionTextureBinding: binding('occlusion'),
        occlusionStrength: 0.7,
        emissiveFactor: const <double>[0.1, 0.2, 0.3],
        emissiveTextureBinding: binding('emissive'),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(root.mesh!.primitives, hasLength(2));
    final baseMaterial = root.mesh!.primitives.first.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(baseMaterial, same(originalMaterial));
    expect(baseMaterial.baseColorFactor.x, closeTo(0.2, 0.0001));
    expect(baseMaterial.baseColorFactor.y, closeTo(0.3, 0.0001));
    expect(baseMaterial.baseColorFactor.z, closeTo(0.4, 0.0001));
    expect(baseMaterial.baseColorTexture, same(factory.createdSources[0]));
    expect(
      baseMaterial.metallicRoughnessTexture,
      same(factory.createdSources[1]),
    );
    // The retained source PBR consumes the incoming raw normal exactly once.
    // The clearcoat overlay keeps its independent coat-normal input separate.
    expect(capturedConfig!.normalTexture, same(factory.createdSources[2]));
    expect(capturedConfig!.patch.normalScale, closeTo(0.5, 0.0001));
    expect(baseMaterial.normalTextureSource, same(factory.createdSources[2]));
    expect(baseMaterial.normalScale, closeTo(0.5, 0.0001));
    final overlayParams = overlayMaterial.getUniformBlock('MaterialParams')!;
    expect(overlayParams.getFloat32(32, Endian.host), closeTo(0.5, 0.0001));
    expect(baseMaterial.emissiveTexture, same(factory.createdSources[3]));
    expect(baseMaterial.occlusionTexture, same(factory.createdSources[4]));
    expect(baseMaterial.metallicFactor, closeTo(0.25, 0.0001));
    expect(baseMaterial.roughnessFactor, closeTo(0.6, 0.0001));
    expect(baseMaterial.occlusionStrength, closeTo(0.7, 0.0001));
    expect(baseMaterial.emissiveFactor.x, closeTo(0.1, 0.0001));
    expect(baseMaterial.emissiveFactor.y, closeTo(0.2, 0.0001));
    expect(baseMaterial.emissiveFactor.z, closeTo(0.3, 0.0001));
    expect(factory.paths, everyElement('fromImage'));

    backend.resetClearcoatPatch(
      node: root,
      primitive: root.mesh!.primitives.first,
    );

    expect(root.mesh!.primitives, hasLength(1));
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(
      originalMaterial.normalTextureSource,
      same(factory.createdSources[2]),
    );
    expect(originalMaterial.normalScale, closeTo(0.5, 0.0001));
  });

  test('candidate clearcoat factor zero preserves combined core normal',
      () async {
    final factory = _RecordingTextureFactory();
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (_) async =>
          flutter_scene.ShaderMaterial(isOpaqueOverride: true),
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        clearcoat: 0.0,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(
            _onePixelPng,
            debugName: 'normal',
          ),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(
      originalMaterial.normalTextureSource,
      same(factory.createdSources.single),
    );
    expect(originalMaterial.normalScale, closeTo(0.5, 0.0001));
  });

  test('clearcoat zero retains the latest combined logical source normal',
      () async {
    final factory = _RecordingTextureFactory();
    final configs = <FlutterSceneClearcoatMaterialConfig>[];
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (config) async {
        configs.add(config);
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
    final modelNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
    );
    final address =
        PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0);

    final combinedDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-b'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
      runtimeAdapter: runtimeAdapter,
    );
    final normalB = factory.createdSources.single;
    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
      runtimeAdapter: runtimeAdapter,
    );

    expect(combinedDiagnostics, isEmpty);
    expect(zeroDiagnostics, isEmpty);
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    final replacementDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.6),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
      runtimeAdapter: runtimeAdapter,
    );

    expect(replacementDiagnostics, isEmpty);
    expect(configs, hasLength(3));
    expect(configs.last.normalTexture, same(normalB));
    expect(configs.last.sourceNormalTexture, same(normalB));
    expect(configs.last.sourceNormalScale, closeTo(0.5, 0.0001));
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    final resetDiagnostics = await runtimeAdapter.resetMaterial(address);

    expect(resetDiagnostics, isEmpty);
    // Explicit adapter reset remains distinct from factor zero and restores A.
    expect(material.normalTextureSource, same(modelNormal));
    expect(material.normalScale, closeTo(0.8, 0.0001));
  });

  test('combined clearcoat normal without scale retains prior scale once',
      () async {
    final factory = _RecordingTextureFactory();
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
    final modelNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
    );
    final address =
        PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0);

    final combinedDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-b'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalB = factory.createdSources.single;

    expect(combinedDiagnostics, isEmpty);
    expect(configs.single.sourceNormalScale, closeTo(0.8, 0.0001));
    final overlayParams = overlays.single.getUniformBlock('MaterialParams')!;
    expect(overlayParams.getFloat32(32, Endian.host), closeTo(0.8, 0.0001));
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.8, 0.0001));

    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(zeroDiagnostics, isEmpty);
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.8, 0.0001));
  });

  test('active clearcoat composes a later core-only logical normal delta',
      () async {
    final factory = _RecordingTextureFactory();
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
    final modelNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
    );
    final address =
        PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0);

    final combinedDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-b'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalB = factory.createdSources.single;
    final coreDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-c'),
        ),
        normalScale: 0.25,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalC = factory.createdSources.last;

    expect(combinedDiagnostics, isEmpty);
    expect(coreDiagnostics, isEmpty);
    expect(factory.paths, <String>['fromImage', 'fromImage']);
    expect(normalC, isNot(same(normalB)));
    expect(configs, hasLength(2));
    expect(configs.last.normalTexture, same(normalC));
    expect(configs.last.patch.clearcoat, closeTo(0.9, 0.0001));
    expect(configs.last.patch.normalScale, closeTo(0.25, 0.0001));
    final coreOverlayParams = overlays.last.getUniformBlock('MaterialParams')!;
    expect(
      coreOverlayParams.getFloat32(32, Endian.host),
      closeTo(0.25, 0.0001),
    );
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.25, 0.0001));

    final replacementDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.6),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(replacementDiagnostics, isEmpty);
    expect(configs, hasLength(3));
    expect(configs.last.normalTexture, same(normalC));
    expect(configs.last.sourceNormalTexture, same(normalC));
    expect(configs.last.sourceNormalScale, closeTo(0.25, 0.0001));
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.25, 0.0001));

    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(zeroDiagnostics, isEmpty);
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.25, 0.0001));

    backend.resetClearcoatPatch(
      node: root,
      primitive: root.mesh!.primitives.first,
    );
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.25, 0.0001));
  });

  test('active clearcoat core normal without scale retains logical scale',
      () async {
    final factory = _RecordingTextureFactory();
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
    final modelNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
    );
    final address =
        PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0);

    await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-b'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalB = factory.createdSources.single;
    final coreDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-c'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalC = factory.createdSources.last;

    expect(coreDiagnostics, isEmpty);
    expect(normalC, isNot(same(normalB)));
    expect(configs.last.sourceNormalScale, closeTo(0.5, 0.0001));
    expect(
      overlays.last.getUniformBlock('MaterialParams')!.getFloat32(
            32,
            Endian.host,
          ),
      closeTo(0.5, 0.0001),
    );
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(zeroDiagnostics, isEmpty);
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    final positiveDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.6),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(positiveDiagnostics, isEmpty);
    expect(configs.last.sourceNormalTexture, same(normalC));
    expect(configs.last.sourceNormalScale, closeTo(0.5, 0.0001));
    expect(material.normalTextureSource, same(normalC));
    expect(material.normalScale, closeTo(0.5, 0.0001));
  });

  test('active clearcoat core-normal reconfiguration failure stays atomic',
      () async {
    final factory = _RecordingTextureFactory();
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
    final modelNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final material = flutter_scene.PhysicallyBasedMaterial()
      ..normalTexture = modelNormal
      ..normalScale = 0.8;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), material),
    );
    final address =
        PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0);

    final combinedDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        clearcoat: 0.9,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-b'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final normalB = factory.createdSources.single;
    final originalOverlay = root.mesh!.primitives.last.material;
    final coreDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal-c'),
        ),
        normalScale: 0.25,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(combinedDiagnostics, isEmpty);
    expect(coreDiagnostics, hasLength(1));
    expect(coreDiagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(coreDiagnostics.single.details['feature'], 'clearcoat');
    expect(coreDiagnostics.single.details['status'], 'shaderUnavailable');
    expect(root.mesh!.primitives.last.material, same(originalOverlay));
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.5, 0.0001));

    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(clearcoat: 0.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(zeroDiagnostics, isEmpty);
    expect(material.normalTextureSource, same(normalB));
    expect(material.normalScale, closeTo(0.5, 0.0001));
  });

  test('candidate clearcoat failure does not apply core PBR fields', () async {
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final originalBaseColor = originalMaterial.baseColorFactor.clone();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );
    final backend = FlutterSceneMaterialExtensionBackend(
      createClearcoatMaterial: (_) async => throw StateError('shader missing'),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        clearcoat: 0.8,
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        metallic: 0.25,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
    );

    expect(diagnostics, hasLength(1));
    expect(root.mesh!.primitives, hasLength(1));
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.baseColorFactor, originalBaseColor);
    expect(originalMaterial.metallicFactor, 1.0);
  });

  test('candidate transmission rejects alpha intent before texture loading',
      () async {
    final factory = _RecordingTextureFactory();
    var createCalls = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        createCalls += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      MaterialPatch(
        transmission: 1.0,
        alphaMode: MaterialAlphaMode.mask,
        alphaCutoff: 0.3,
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'baseColor'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      materialExtensionSceneViews: <flutter_scene.RenderView>[],
      textureFactory: factory,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'transmissionCoreInputsUnsupported');
    expect(
      diagnostics.single.details['fields'],
      containsAll(<String>['alphaMode', 'alphaCutoff']),
    );
    expect(factory.paths, isEmpty);
    expect(createCalls, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.alphaMode, flutter_scene.AlphaMode.opaque);
  });

  test('candidate transmission preflight rejects before any texture decode',
      () async {
    final cases = <({String name, MaterialPatch patch, String limitation})>[
      (
        name: 'iorZero',
        patch: MaterialPatch(
          transmission: 1.0,
          ior: 0.0,
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          normalTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
          ),
          transmissionTextureBinding: MaterialTextureBinding(
            source:
                TextureSource.bytes(_onePixelPng, debugName: 'transmission'),
          ),
        ),
        limitation: 'packageLocalIorZeroCompatibilityContractMissing',
      ),
      (
        name: 'positiveThickness',
        patch: MaterialPatch(
          transmission: 1.0,
          thickness: 0.2,
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          normalTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
          ),
          thicknessTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'thickness'),
          ),
        ),
        limitation: 'packageLocalVolumeTransformContractMissing',
      ),
      (
        name: 'transmissionTexture',
        patch: MaterialPatch(
          transmission: 1.0,
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          normalTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
          ),
          transmissionTextureBinding: MaterialTextureBinding(
            source:
                TextureSource.bytes(_onePixelPng, debugName: 'transmission'),
          ),
        ),
        limitation: 'packageLocalTransmissionTextureBasePbrContractMissing',
      ),
    ];

    for (final entry in cases) {
      final factory = _RecordingTextureFactory();
      var shaderCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          shaderCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.0;
      final root = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
      )..layers = 0x04;
      final sceneViews = <flutter_scene.RenderView>[];

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
        entry.patch,
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.experimentalShaders(),
        materialExtensionBackend: backend,
        materialExtensionSceneViews: sceneViews,
        textureFactory: factory,
      );

      expect(diagnostics, hasLength(1), reason: entry.name);
      expect(diagnostics.single.code,
          ViewerDiagnosticCode.unsupportedMaterialFeature,
          reason: entry.name);
      expect(diagnostics.single.details['limitation'], entry.limitation,
          reason: entry.name);
      expect(factory.paths, isEmpty, reason: entry.name);
      expect(shaderCreationCount, 0, reason: entry.name);
      expect(backend.debugActivePatchCount, 0, reason: entry.name);
      expect(root.mesh!.primitives.single.material, same(originalMaterial),
          reason: entry.name);
      expect(root.layers, 0x04, reason: entry.name);
      expect(sceneViews, isEmpty, reason: entry.name);
    }
  });

  test('factor-zero transmission bypass applies core PBR while inactive',
      () async {
    final factory = _RecordingTextureFactory();
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    )..layers = 0x08;
    final sceneViews = <flutter_scene.RenderView>[];

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      MaterialPatch(
        transmission: 0.0,
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
        ),
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
        ),
        normalScale: 0.5,
        roughness: 0.35,
        transmissionTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'transmission'),
        ),
        thicknessTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'thickness'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      materialExtensionSceneViews: sceneViews,
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(factory.paths, <String>['fromImage', 'fromPixels']);
    expect(shaderCreationCount, 0);
    expect(backend.debugActivePatchCount, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(root.layers, 0x08);
    expect(sceneViews, isEmpty);
    expect(originalMaterial.baseColorFactor.x, closeTo(0.2, 0.0001));
    expect(originalMaterial.baseColorFactor.y, closeTo(0.3, 0.0001));
    expect(originalMaterial.baseColorFactor.z, closeTo(0.4, 0.0001));
    expect(originalMaterial.baseColorTextureSource,
        same(factory.createdSources[0]));
    expect(
        originalMaterial.normalTextureSource, same(factory.createdSources[1]));
    expect(originalMaterial.normalScale, closeTo(1.0, 0.0001));
    expect(originalMaterial.roughnessFactor, closeTo(0.35, 0.0001));
  });

  test('factor-zero bypass ignores extension-only binding limitations',
      () async {
    final cases = <({String name, MaterialPatch patch})>[
      (
        name: 'transmissionAsymmetricSampler',
        patch: MaterialPatch(
          transmission: 0.0,
          baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          roughness: 0.25,
          transmissionTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'transmission',
            ),
            sampler: const TextureSampler(
              wrapS: TextureWrapMode.repeat,
              wrapT: TextureWrapMode.clampToEdge,
            ),
          ),
        ),
      ),
      (
        name: 'thicknessTransform',
        patch: MaterialPatch(
          transmission: 0.0,
          baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          roughness: 0.25,
          thicknessTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'thickness'),
            transform: TextureTransform(scale: const <double>[2.0, 2.0]),
          ),
        ),
      ),
      (
        name: 'transmissionTexCoord',
        patch: MaterialPatch(
          transmission: 0.0,
          baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
          baseColorTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
          ),
          roughness: 0.25,
          transmissionTextureBinding: MaterialTextureBinding(
            source: TextureSource.bytes(
              _onePixelPng,
              debugName: 'transmission',
            ),
            texCoord: 1,
          ),
        ),
      ),
    ];

    for (final entry in cases) {
      final factory = _RecordingTextureFactory();
      var shaderCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          shaderCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
      final root = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Glass'],
          primitiveIndex: 0,
        ),
        entry.patch,
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.experimentalShaders(),
        materialExtensionBackend: backend,
        textureFactory: factory,
      );

      expect(diagnostics, isEmpty, reason: entry.name);
      expect(factory.paths, <String>['fromImage'], reason: entry.name);
      expect(shaderCreationCount, 0, reason: entry.name);
      expect(backend.debugActivePatchCount, 0, reason: entry.name);
      expect(root.mesh!.primitives.single.material, same(originalMaterial),
          reason: entry.name);
      expect(originalMaterial.baseColorFactor.x, closeTo(0.2, 0.0001),
          reason: entry.name);
      expect(originalMaterial.baseColorFactor.y, closeTo(0.3, 0.0001),
          reason: entry.name);
      expect(originalMaterial.baseColorFactor.z, closeTo(0.4, 0.0001),
          reason: entry.name);
      expect(originalMaterial.roughnessFactor, closeTo(0.25, 0.0001),
          reason: entry.name);
    }
  });

  test('positive transmission requires scene views before core texture load',
      () async {
    final factory = _RecordingTextureFactory();
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final originalBaseColor = originalMaterial.baseColorFactor.clone();
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    )..layers = 0x40;

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Glass'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        transmission: 0.8,
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code, ViewerDiagnosticCode.adapterFailure);
    expect(factory.paths, isEmpty);
    expect(diagnostics.single.details['limitation'],
        'transmissionApplySceneViewsUnavailable');
    expect(shaderCreationCount, 0);
    expect(backend.debugActivePatchCount, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(root.layers, 0x40);
    expect(originalMaterial.baseColorFactor, originalBaseColor);
  });

  test('active factor-zero reset requires scene views before core texture load',
      () async {
    final factory = _RecordingTextureFactory();
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    )..layers = 0x80;
    final address =
        PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0);
    final sceneViews = <flutter_scene.RenderView>[];

    expect(
      await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(transmission: 0.8),
        materialExtensionSceneViews: sceneViews,
        runtimeAdapter: runtimeAdapter,
      ),
      isEmpty,
    );
    final activeMaterial = root.mesh!.primitives.single.material;
    final activeView = sceneViews.single;
    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        transmission: 0.0,
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
        ),
      ),
      runtimeAdapter: runtimeAdapter,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code, ViewerDiagnosticCode.adapterFailure);
    expect(diagnostics.single.details['limitation'],
        'activeTransmissionSceneViewsUnavailable');
    expect(factory.paths, isEmpty);
    expect(shaderCreationCount, 1);
    expect(backend.debugActivePatchCount, 1);
    expect(root.mesh!.primitives.single.material, same(activeMaterial));
    expect(root.layers, FlutterSceneMaterialExtensionBackend.transmissiveLayer);
    expect(sceneViews, <flutter_scene.RenderView>[activeView]);
  });

  test('factor-zero transmission restores active state then applies core PBR',
      () async {
    final factory = _RecordingTextureFactory();
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    )..layers = 0x10;
    final address =
        PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0);
    final sceneViews = <flutter_scene.RenderView>[];

    final activeDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(transmission: 0.8),
      materialExtensionSceneViews: sceneViews,
      runtimeAdapter: runtimeAdapter,
    );
    final activeMaterial = root.mesh!.primitives.single.material;
    final activeView = sceneViews.single;
    final zeroDiagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        transmission: 0.0,
        baseColorFactor: const <double>[0.4, 0.3, 0.2, 1.0],
        baseColorTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'base'),
        ),
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
        ),
        normalScale: 0.25,
        roughness: 0.6,
        transmissionTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'transmission'),
        ),
      ),
      materialExtensionSceneViews: sceneViews,
      runtimeAdapter: runtimeAdapter,
    );

    expect(activeDiagnostics, isEmpty);
    expect(activeMaterial, isNot(same(originalMaterial)));
    expect(activeView.target, isNotNull);
    expect(zeroDiagnostics, isEmpty);
    expect(shaderCreationCount, 1);
    expect(factory.paths, <String>['fromImage', 'fromPixels']);
    expect(backend.debugActivePatchCount, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(root.layers, 0x10);
    expect(sceneViews, isEmpty);
    expect(originalMaterial.baseColorFactor.x, closeTo(0.4, 0.0001));
    expect(originalMaterial.baseColorTextureSource,
        same(factory.createdSources[0]));
    expect(
        originalMaterial.normalTextureSource, same(factory.createdSources[1]));
    expect(originalMaterial.normalScale, closeTo(1.0, 0.0001));
    expect(originalMaterial.roughnessFactor, closeTo(0.6, 0.0001));
  });

  test('failed factor-zero core load preserves active transmission atomically',
      () async {
    final factory = _RecordingTextureFactory(
      assetFailure: StateError('core texture unavailable'),
    );
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final originalBaseColor = originalMaterial.baseColorFactor.clone();
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    )..layers = 0x20;
    final address =
        PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0);
    final sceneViews = <flutter_scene.RenderView>[];

    expect(
      await debugApplyMaterialPatchToRoot(
        root,
        address,
        const MaterialPatch(transmission: 0.8),
        materialExtensionSceneViews: sceneViews,
        runtimeAdapter: runtimeAdapter,
      ),
      isEmpty,
    );
    final activeMaterial = root.mesh!.primitives.single.material;
    final activeView = sceneViews.single;
    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      MaterialPatch(
        transmission: 0.0,
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        baseColorTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('missing-core.png'),
        ),
      ),
      materialExtensionSceneViews: sceneViews,
      runtimeAdapter: runtimeAdapter,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code, ViewerDiagnosticCode.assetLoadFailure);
    expect(factory.paths, <String>['fromAsset']);
    expect(shaderCreationCount, 1);
    expect(backend.debugActivePatchCount, 1);
    expect(root.mesh!.primitives.single.material, same(activeMaterial));
    expect(root.layers, FlutterSceneMaterialExtensionBackend.transmissiveLayer);
    expect(sceneViews, <flutter_scene.RenderView>[activeView]);
    expect(originalMaterial.baseColorFactor, originalBaseColor);
  });

  test('factor-zero transmission with IOR preserves opaque-IOR diagnostic',
      () async {
    final factory = _RecordingTextureFactory();
    var shaderCreationCount = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        shaderCreationCount += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final originalBaseColor = originalMaterial.baseColorFactor.clone();
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      MaterialPatch(
        transmission: 0.0,
        ior: 1.4,
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'pinnedStandardPbrOpaqueIorContractMissing');
    expect(diagnostics.single.details['feature'], 'opaqueIor');
    expect(
      diagnostics.single.details['upstreamRevision'],
      '766351c865c621e8720c726f9aa51173ce76e786',
    );
    expect(factory.paths, isEmpty);
    expect(shaderCreationCount, 0);
    expect(backend.debugActivePatchCount, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
    expect(originalMaterial.baseColorFactor, originalBaseColor);
  });

  test('candidate extension visibility is rejected before mutation', () async {
    var createCalls = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (_) async {
        createCalls += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      },
    );
    final geometry = _UvStubGeometry();
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(geometry, originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      const MaterialPatch(clearcoat: 0.8, visible: false),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.details['limitation'],
        'packageLocalExtensionVisibilityUnsupported');
    expect(createCalls, 0);
    expect(root.mesh!.primitives, hasLength(1));
    expect(root.mesh!.primitives.single.geometry, same(geometry));
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
  });

  test('transmission candidate rejects unconsumed core intent atomically',
      () async {
    final factory = _RecordingTextureFactory();
    var createCalls = 0;
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async {
        createCalls += 1;
        return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      },
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Glass'], primitiveIndex: 0),
      MaterialPatch(
        transmission: 1.0,
        metallicRoughnessTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'orm'),
        ),
        occlusionTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'occlusion'),
        ),
        emissiveTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'emissive'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['limitation'],
        'transmissionCoreInputsUnsupported');
    expect(
      diagnostics.single.details['nextStep'],
      'useRendererContractWithCombinedCoreTransmissionSupport',
    );
    expect(
      diagnostics.single.details['fields'],
      containsAll(<String>[
        'metallicRoughnessTexture',
        'occlusionTexture',
        'emissiveTexture',
      ]),
    );
    expect(factory.paths, isEmpty);
    expect(createCalls, 0);
    expect(root.mesh!.primitives.single.material, same(originalMaterial));
  });

  test('transmission candidate rejects unconsumed existing PBR state',
      () async {
    final sampler = const flutter_scene.TextureSampling().toSamplerOptions();
    final texture = _StubTextureSource(sampler);
    final cases = <({
      String name,
      void Function(flutter_scene.PhysicallyBasedMaterial material) configure,
      List<String> fields,
    })>[
      (
        name: 'metallicRoughness',
        configure: (material) {
          material
            ..metallicFactor = 0.25
            ..roughnessFactor = 0.4
            ..metallicRoughnessTexture = texture;
        },
        fields: <String>[
          'metallic',
          'roughness',
          'metallicRoughnessTexture',
        ],
      ),
      (
        name: 'occlusion',
        configure: (material) {
          material
            ..occlusionTexture = texture
            ..occlusionStrength = 0.6;
        },
        fields: <String>['occlusionTexture', 'occlusionStrength'],
      ),
      (
        name: 'emissive',
        configure: (material) {
          material
            ..emissiveFactor = vm.Vector4(0.1, 0.2, 0.3, 1.0)
            ..emissiveTexture = texture;
        },
        fields: <String>['emissiveFactor', 'emissiveTexture'],
      ),
      (
        name: 'alphaMask',
        configure: (material) {
          material
            ..alphaMode = flutter_scene.AlphaMode.mask
            ..alphaCutoff = 0.3;
        },
        fields: <String>['alphaMode', 'alphaCutoff'],
      ),
    ];

    for (final entry in cases) {
      var createCalls = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          createCalls += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.0;
      entry.configure(originalMaterial);
      final originalMetallicRoughness =
          originalMaterial.metallicRoughnessTexture;
      final originalOcclusion = originalMaterial.occlusionTexture;
      final originalEmissive = originalMaterial.emissiveTexture;
      final originalEmissiveFactor = originalMaterial.emissiveFactor.clone();
      final root = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
      );

      final diagnostics = await debugApplyMaterialPatchToRoot(
        root,
        PartAddress(
          nodePath: const <String>['Glass'],
          primitiveIndex: 0,
        ),
        const MaterialPatch(transmission: 1.0),
        materialExtensionPolicy:
            const ViewerMaterialExtensionPolicy.experimentalShaders(),
        materialExtensionBackend: backend,
      );

      expect(diagnostics, hasLength(1), reason: entry.name);
      expect(
        diagnostics.single.details['limitation'],
        'transmissionCoreInputsUnsupported',
        reason: entry.name,
      );
      expect(
        diagnostics.single.details['fields'],
        containsAll(entry.fields),
        reason: entry.name,
      );
      final fieldOrigins =
          diagnostics.single.details['fieldOrigins'] as Map<String, Object?>;
      for (final field in entry.fields) {
        expect(fieldOrigins[field], 'sourceMaterial', reason: entry.name);
      }
      expect(createCalls, 0, reason: entry.name);
      expect(root.mesh!.primitives.single.material, same(originalMaterial));
      expect(originalMaterial.metallicRoughnessTexture,
          same(originalMetallicRoughness));
      expect(originalMaterial.occlusionTexture, same(originalOcclusion));
      expect(originalMaterial.emissiveTexture, same(originalEmissive));
      expect(originalMaterial.emissiveFactor, originalEmissiveFactor);
    }
  });

  test('candidate transmission loads normal raw and applies scale once',
      () async {
    final factory = _RecordingTextureFactory();
    final shaderMaterial =
        flutter_scene.ShaderMaterial(isOpaqueOverride: false);
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async => shaderMaterial,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Glass'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        transmission: 1.0,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      materialExtensionSceneViews: <flutter_scene.RenderView>[],
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(factory.paths, <String>['fromImage']);
    final params = shaderMaterial.getUniformBlock('MaterialParams')!;
    expect(params.getFloat32(56, Endian.host), closeTo(0.5, 0.0001));
  });

  test('candidate transmission falls back to source normal scale once',
      () async {
    final sourceNormal = _StubTextureSource(
      const flutter_scene.TextureSampling().toSamplerOptions(),
    );
    final shaderMaterial =
        flutter_scene.ShaderMaterial(isOpaqueOverride: false);
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createTransmissionMaterial: (_) async => shaderMaterial,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.0
      ..normalTexture = sourceNormal
      ..normalScale = 0.35;
    final root = flutter_scene.Node(
      name: 'Glass',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Glass'],
        primitiveIndex: 0,
      ),
      const MaterialPatch(transmission: 1.0),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(),
      materialExtensionBackend: backend,
      materialExtensionSceneViews: <flutter_scene.RenderView>[],
    );

    expect(diagnostics, isEmpty);
    final params = shaderMaterial.getUniformBlock('MaterialParams')!;
    expect(params.getFloat32(56, Endian.host), closeTo(0.35, 0.0001));
  });

  test('candidate clearcoat loads normal raw before uniform scaling', () async {
    final factory = _RecordingTextureFactory();
    final shaderMaterial = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
    final backend = FlutterSceneMaterialExtensionBackend(
      bindFallbackTextures: false,
      createClearcoatMaterial: (_) async => shaderMaterial,
    );
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), originalMaterial),
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(
        nodePath: const <String>['Paint'],
        primitiveIndex: 0,
      ),
      MaterialPatch(
        clearcoat: 1.0,
        normalTextureBinding: MaterialTextureBinding(
          source: TextureSource.bytes(_onePixelPng, debugName: 'normal'),
        ),
        normalScale: 0.5,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.experimentalShaders(
        enableClearcoat: true,
      ),
      materialExtensionBackend: backend,
      textureFactory: factory,
    );

    expect(diagnostics, isEmpty);
    expect(factory.paths, <String>['fromImage']);
    final params = shaderMaterial.getUniformBlock('MaterialParams')!;
    expect(params.getFloat32(32, Endian.host), closeTo(0.5, 0.0001));
    expect(
      originalMaterial.normalTextureSource,
      same(factory.createdSources.single),
    );
    expect(originalMaterial.normalScale, closeTo(0.5, 0.0001));
  });

  test('adapter maps public alpha modes to flutter_scene alpha modes', () {
    expect(
      debugFlutterSceneAlphaModeFor(MaterialAlphaMode.opaque),
      flutter_scene.AlphaMode.opaque,
    );
    expect(
      debugFlutterSceneAlphaModeFor(MaterialAlphaMode.mask),
      flutter_scene.AlphaMode.mask,
    );
    expect(
      debugFlutterSceneAlphaModeFor(MaterialAlphaMode.blend),
      flutter_scene.AlphaMode.blend,
    );
  });

  test('adapter routes mask and blend through family replacement', () {
    expect(
      debugRequiresPbrFamilyReplacement(
        const MaterialPatch(alphaMode: MaterialAlphaMode.mask),
      ),
      isTrue,
    );
    expect(
      debugRequiresPbrFamilyReplacement(
        const MaterialPatch(alphaMode: MaterialAlphaMode.blend),
      ),
      isTrue,
    );
    expect(
      debugRequiresPbrFamilyReplacement(const MaterialPatch(roughness: 0.5)),
      isFalse,
    );
    expect(
      debugRequiresPbrFamilyReplacement(const MaterialPatch(ior: 0)),
      isFalse,
    );
    expect(
      debugRequiresPbrFamilyReplacement(const MaterialPatch(ior: 1.5)),
      isFalse,
    );
  });

  test(
      'adapter routes only supported transmission patches to extension backend',
      () {
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
        const MaterialPatch(transmission: 1.0, ior: 1.45),
      ),
      isFalse,
    );
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.experimentalShaders(),
        const MaterialPatch(transmission: 1.0, ior: 1.45),
      ),
      isTrue,
    );
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.experimentalShaders(),
        const MaterialPatch(clearcoat: 1.0),
      ),
      isFalse,
    );
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.experimentalShaders(
          enableClearcoat: true,
        ),
        const MaterialPatch(clearcoat: 1.0, clearcoatRoughness: 0.18),
      ),
      isTrue,
    );
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.experimentalShaders(
          enableClearcoat: true,
        ),
        const MaterialPatch(transmission: 1.0, clearcoat: 1.0),
      ),
      isFalse,
    );
  });

  test('production support waits for backend preflight', () {
    expect(
      debugUsesMaterialExtensionBackendFor(
        const ViewerMaterialExtensionPolicy.productionShaders(),
        const MaterialPatch(transmission: 1.0, ior: 1.45),
      ),
      isFalse,
    );
  });

  test('adapter resolves production support from custom shader preflight', () {
    final candidate = debugResolveProductionMaterialExtensionSupport(
      NativeMaterialExtensionCapability(
        support: _materialExtensionSupport(
          MaterialExtensionBackendKind.packageLocalCandidate,
        ),
      ),
    );
    final customShader = debugResolveProductionMaterialExtensionSupport(
      const NativeMaterialExtensionCapability(
        support: MaterialExtensionSupport.unsupported,
      ),
      MaterialExtensionPreflightResult(
        support: _materialExtensionSupport(
          MaterialExtensionBackendKind.flutterSceneCustomShader,
        ),
      ),
    );
    final native = debugResolveProductionMaterialExtensionSupport(
      NativeMaterialExtensionCapability(
        support: _materialExtensionSupport(
          MaterialExtensionBackendKind.rendererNative,
        ),
      ),
    );

    expect(candidate, MaterialExtensionSupport.unsupported);
    expect(customShader.productionReady, isFalse);
    expect(
      customShader.backendKind,
      MaterialExtensionBackendKind.flutterSceneCustomShader,
    );
    expect(native.productionReady, isFalse);
    expect(
      native.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
  });

  test('production custom shader support uses package local backend', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    const patch = MaterialPatch(transmission: 1.0, ior: 1.45);
    final support = _materialExtensionSupport(
      MaterialExtensionBackendKind.flutterSceneCustomShader,
    );

    expect(
      debugUsesMaterialExtensionBackendFor(policy, patch, support: support),
      isTrue,
    );
    expect(
      debugUsesNativeMaterialExtensionApplierFor(
        policy,
        patch,
        support: support,
      ),
      isFalse,
    );
  });

  test('production renderer native support bypasses package local backend', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    const patch = MaterialPatch(transmission: 1.0, ior: 1.45);
    final support = _materialExtensionSupport(
      MaterialExtensionBackendKind.rendererNative,
    );

    expect(
      debugUsesMaterialExtensionBackendFor(policy, patch, support: support),
      isFalse,
    );
    expect(
      debugUsesNativeMaterialExtensionApplierFor(
        policy,
        patch,
        support: support,
      ),
      isTrue,
    );
  });

  test('glass on one primitive of a multi-primitive node reports limitation',
      () {
    final diagnostic = debugGlassNodeIsolationDiagnostic(
      primitiveCount: 2,
      selectedPrimitiveIndex: 0,
    );

    expect(diagnostic, isNotNull);
    expect(diagnostic!.code, ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostic.details['limitation'], 'nodeLayerIsolation');
    expect(diagnostic.details['primitiveCount'], 2);
    expect(diagnostic.details['primitiveIndex'], 0);
  });

  test('adapter resolves GLB node paths below a synthetic runtime root', () {
    final material = flutter_scene.ShaderMaterial();
    final sphere = flutter_scene.Node(
      name: 'Sphere',
      mesh: flutter_scene.Mesh(_StubGeometry(), material),
    );
    final root = flutter_scene.Node(name: 'Scene')..children.add(sphere);

    expect(
      debugCanResolvePartAddress(
        root,
        PartAddress(
          nodePath: <String>['Sphere'],
          primitiveIndex: 0,
        ),
      ),
      isTrue,
    );

    final matchingWrapper = flutter_scene.Node(name: 'Sphere')
      ..children.add(
        flutter_scene.Node(
          name: 'Sphere',
          mesh: flutter_scene.Mesh(_StubGeometry(), material),
        ),
      );

    expect(
      debugCanResolvePartAddress(
        matchingWrapper,
        PartAddress(
          nodePath: <String>['Sphere'],
          primitiveIndex: 0,
        ),
      ),
      isTrue,
    );
  });

  test('visible patch hides only the addressed primitive in a shared node',
      () async {
    final firstGeometry = _StubGeometry();
    final secondGeometry = _StubGeometry();
    final root = flutter_scene.Node(
      name: 'A1B32',
      mesh: flutter_scene.Mesh.primitives(
        primitives: <flutter_scene.MeshPrimitive>[
          flutter_scene.MeshPrimitive(
            firstGeometry,
            flutter_scene.ShaderMaterial(),
          ),
          flutter_scene.MeshPrimitive(
            secondGeometry,
            flutter_scene.ShaderMaterial(),
          ),
        ],
      ),
    );
    final originalMesh = root.mesh;

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: <String>['A1B32'], primitiveIndex: 1),
      const MaterialPatch(visible: false),
    );

    expect(diagnostics, isEmpty);
    expect(root.visible, isTrue);
    expect(root.mesh, isNot(same(originalMesh)));
    expect(root.mesh!.primitives.first.geometry, same(firstGeometry));
    expect(root.mesh!.primitives.last.geometry, isNot(same(secondGeometry)));
    expect(root.mesh!.primitives, hasLength(2));
  });

  test('opaque material patch refreshes mounted mesh wrapper', () async {
    final originalMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'A1B32',
      mesh: flutter_scene.Mesh.primitives(
        primitives: <flutter_scene.MeshPrimitive>[
          flutter_scene.MeshPrimitive(_StubGeometry(), originalMaterial),
        ],
      ),
    );
    final originalMesh = root.mesh;

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: <String>['A1B32'], primitiveIndex: 0),
      MaterialPatch(
        baseColorFactor: const <double>[1, 0, 0, 1],
        alphaMode: MaterialAlphaMode.opaque,
      ),
    );

    expect(diagnostics, isEmpty);
    expect(root.mesh, isNot(same(originalMesh)));
    final material = root.mesh!.primitives.single.material;
    expect(material, isA<flutter_scene.PhysicallyBasedMaterial>());
    expect(material, isNot(same(originalMaterial)));
    final pbr = material as flutter_scene.PhysicallyBasedMaterial;
    expect(pbr.baseColorFactor.r, 1);
    expect(pbr.baseColorFactor.g, 0);
    expect(pbr.baseColorFactor.b, 0);
    expect(pbr.alphaMode, flutter_scene.AlphaMode.opaque);
  });

  test('native clearcoat applies textures with combined core PBR state',
      () async {
    final textureFactory = _RecordingTextureFactory();
    final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
    );
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.clearcoat:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        baseColorFactor: const <double>[0.2, 0.3, 0.4, 1.0],
        clearcoat: 1.0,
        clearcoatRoughness: 0.18,
        clearcoatNormalScale: 0.7,
        clearcoatTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat.png'),
        ),
        clearcoatRoughnessTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-roughness.png'),
        ),
        clearcoatNormalTextureBinding: MaterialTextureBinding(
          source: const TextureSource.asset('assets/clearcoat-normal.png'),
        ),
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      materialExtensionSupport: support,
      textureFactory: textureFactory,
    );

    expect(diagnostics, isEmpty);
    final material = root.mesh!.primitives.single.material
        as flutter_scene.PhysicallyBasedMaterial;
    expect(material.baseColorFactor.r, closeTo(0.2, 1e-6));
    expect(material.baseColorFactor.g, closeTo(0.3, 1e-6));
    expect(material.baseColorFactor.b, closeTo(0.4, 1e-6));
    expect(material.clearcoatFactor, 1.0);
    expect(material.clearcoatRoughnessFactor, 0.18);
    expect(material.clearcoatNormalScale, 0.7);
    expect(material.clearcoatTexture, same(textureFactory.createdSources[0]));
    expect(
      material.clearcoatRoughnessTexture,
      same(textureFactory.createdSources[1]),
    );
    expect(
      material.clearcoatNormalTexture,
      same(textureFactory.createdSources[2]),
    );
  });

  test('native clearcoat invalid patch fails before any material mutation',
      () async {
    final sourceMaterial = flutter_scene.PhysicallyBasedMaterial();
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
    );
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.clearcoat:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: const <String>['Paint'], primitiveIndex: 0),
      MaterialPatch(
        baseColorFactor: const <double>[1.0, 0.0, 0.0, 1.0],
        clearcoat: 1.2,
      ),
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
      materialExtensionSupport: support,
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.code,
      ViewerDiagnosticCode.invalidMaterialOverride,
    );
    expect(root.mesh!.primitives.single.material, same(sourceMaterial));
    expect(sourceMaterial.baseColorFactor.r, 1.0);
    expect(sourceMaterial.baseColorFactor.g, 1.0);
    expect(sourceMaterial.clearcoatFactor, 0.0);
  });

  test('native glass and clearcoat reset restores original material identity',
      () async {
    final sourceMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..transmissionFactor = 0.15
      ..ior = 1.33;
    final root = flutter_scene.Node(
      name: 'Paint',
      mesh: flutter_scene.Mesh(_UvStubGeometry(), sourceMaterial),
    );
    final address = PartAddress(
      nodePath: const <String>['Paint'],
      primitiveIndex: 0,
    );
    final runtimeAdapter = FlutterSceneRuntimeAdapter(
      materialExtensionPolicy:
          const ViewerMaterialExtensionPolicy.productionShaders(),
    );
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
        MaterialExtensionFeature.transmission:
            MaterialExtensionFeatureSupport(available: true),
        MaterialExtensionFeature.ior:
            MaterialExtensionFeatureSupport(available: true),
        MaterialExtensionFeature.volume:
            MaterialExtensionFeatureSupport(available: true),
        MaterialExtensionFeature.clearcoat:
            MaterialExtensionFeatureSupport(available: true),
      },
    );

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      address,
      const MaterialPatch(
        transmission: 0.9,
        ior: 1.5,
        thickness: 0.2,
        attenuationDistance: 1.5,
        attenuationColor: <double>[0.8, 0.9, 1.0],
        clearcoat: 1.0,
        clearcoatRoughness: 0.1,
      ),
      materialExtensionSupport: support,
      runtimeAdapter: runtimeAdapter,
    );
    expect(diagnostics, isEmpty);
    final patchedMaterial = root.mesh!.primitives.single.material;
    expect(patchedMaterial, isNot(same(sourceMaterial)));
    expect(
      (patchedMaterial as flutter_scene.PhysicallyBasedMaterial)
          .clearcoatFactor,
      1.0,
    );
    expect(patchedMaterial.transmissionFactor, 0.9);
    expect(patchedMaterial.ior, 1.5);
    expect(patchedMaterial.thicknessFactor, 0.2);
    expect(sourceMaterial.clearcoatFactor, 0.0);
    expect(sourceMaterial.transmissionFactor, 0.15);
    expect(sourceMaterial.ior, 1.33);

    final resetDiagnostics = await runtimeAdapter.resetMaterial(address);

    expect(resetDiagnostics, isEmpty);
    expect(root.mesh!.primitives.single.material, same(sourceMaterial));
    expect(sourceMaterial.clearcoatFactor, 0.0);
    expect(sourceMaterial.transmissionFactor, 0.15);
    expect(sourceMaterial.ior, 1.33);
  });
}

final Uint8List _onePixelPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

final class _RecordingTextureFactory implements FlutterSceneTextureFactory {
  _RecordingTextureFactory({this.assetFailure});

  final Object? assetFailure;
  final List<String> paths = <String>[];
  final List<flutter_scene.TextureContent> contents =
      <flutter_scene.TextureContent>[];
  final List<flutter_scene.TextureSampling> samplings =
      <flutter_scene.TextureSampling>[];
  final List<flutter_scene.TextureSource> createdSources =
      <flutter_scene.TextureSource>[];

  void _record(
    String path,
    flutter_scene.TextureContent content,
    flutter_scene.TextureSampling sampling,
  ) {
    paths.add(path);
    contents.add(content);
    samplings.add(sampling);
  }

  flutter_scene.TextureSource _createSource(
    flutter_scene.TextureSampling sampling,
  ) {
    final source = _StubTextureSource(sampling.toSamplerOptions());
    createdSources.add(source);
    return source;
  }

  @override
  Future<flutter_scene.TextureSource> fromAsset(
    String assetPath, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    _record('fromAsset', content, sampling);
    final failure = assetFailure;
    if (failure != null) {
      throw failure;
    }
    return _createSource(sampling);
  }

  @override
  Future<flutter_scene.TextureSource> fromImage(
    ui.Image image, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) async {
    _record('fromImage', content, sampling);
    return _createSource(sampling);
  }

  @override
  flutter_scene.TextureSource fromPixels(
    Uint8List pixels,
    int width,
    int height, {
    required flutter_scene.TextureContent content,
    required flutter_scene.TextureSampling sampling,
  }) {
    _record('fromPixels', content, sampling);
    return _createSource(sampling);
  }
}

final class _StubTextureSource implements flutter_scene.TextureSource {
  const _StubTextureSource(this._sampler);

  final flutter_scene_internal_gpu.SamplerOptions _sampler;

  @override
  flutter_scene_internal_gpu.Texture? get sampledTexture => null;

  @override
  flutter_scene_internal_gpu.SamplerOptions get sampledSampler => _sampler;
}

final class _RecordingExtendedPbrBackend
    implements
        FlutterSceneExtendedPbrMaterialBackend,
        FlutterSceneSheenMaterialBackend {
  int preflightCount = 0;
  final List<FlutterSceneExtendedPbrResourceRequest> sheenRequests =
      <FlutterSceneExtendedPbrResourceRequest>[];
  final List<FlutterSceneExtendedPbrMaterialConfig> configs =
      <FlutterSceneExtendedPbrMaterialConfig>[];
  final List<flutter_scene.PhysicallyBasedMaterial> createdMaterials =
      <flutter_scene.PhysicallyBasedMaterial>[];

  @override
  bool get isReady => true;

  @override
  bool get isSheenReady => true;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async {
    preflightCount += 1;
    return null;
  }

  @override
  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  }) async {
    preflightCount += 1;
    sheenRequests.add(request);
    return null;
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async {
    configs.add(config);
    final material = _TestExtendedPbrMaterial(config);
    createdMaterials.add(material);
    return material;
  }
}

final class _TestExtendedPbrMaterial extends flutter_scene
    .PhysicallyBasedMaterial implements FlutterSceneExtendedPbrState {
  _TestExtendedPbrMaterial(FlutterSceneExtendedPbrMaterialConfig config)
      : transforms = Map<MaterialTextureSlot, TextureTransform>.unmodifiable(
          config.transforms,
        ),
        specularFactor = config.specularFactor,
        specularColorFactor = List<double>.unmodifiable(
          config.specularColorFactor,
        ),
        specularFactorTexture = config.specularFactorTexture,
        specularColorTexture = config.specularColorTexture,
        hasSheenIntent = config.hasSheenIntent,
        retainedSheenColorFactor =
            List<double>.unmodifiable(config.sheenColorFactor),
        sheenRoughness = config.sheenRoughness {
    ior = config.ior;
    sheenColorTexture = config.sheenColorTexture;
    sheenRoughnessTexture = config.sheenRoughnessTexture;
    baseColorFactor = config.source.baseColorFactor.clone();
    baseColorTexture = config.source.baseColorTexture;
    metallicRoughnessTexture = config.source.metallicRoughnessTexture;
    normalTexture = config.source.normalTexture;
    normalScale = config.source.normalScale;
    emissiveTexture = config.source.emissiveTexture;
    emissiveFactor = config.source.emissiveFactor.clone();
    occlusionTexture = config.source.occlusionTexture;
    occlusionStrength = config.source.occlusionStrength;
    occlusionTextureTexCoord = config.source.occlusionTextureTexCoord;
    occlusionTextureTransform = config.source.occlusionTextureTransform;
    clearcoatTexture = config.source.clearcoatTexture;
    clearcoatFactor = config.source.clearcoatFactor;
    clearcoatRoughnessTexture = config.source.clearcoatRoughnessTexture;
    clearcoatRoughnessFactor = config.source.clearcoatRoughnessFactor;
    clearcoatNormalTexture = config.source.clearcoatNormalTexture;
    clearcoatNormalScale = config.source.clearcoatNormalScale;
    metallicFactor = config.source.metallicFactor;
    roughnessFactor = config.source.roughnessFactor;
    environment = config.source.environment;
    alphaMode = config.source.alphaMode;
    alphaCutoff = config.source.alphaCutoff;
    vertexColorWeight = config.source.vertexColorWeight;
    doubleSided = config.source.doubleSided;
    specularAntiAliasingVariance = config.source.specularAntiAliasingVariance;
    specularAntiAliasingThreshold = config.source.specularAntiAliasingThreshold;
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
  @override
  final bool hasSheenIntent;
  @override
  final List<double> retainedSheenColorFactor;
  @override
  final double sheenRoughness;
}

final class _InvalidExtendedPbrBackend
    implements FlutterSceneExtendedPbrMaterialBackend {
  @override
  bool get isReady => true;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async =>
      flutter_scene.PhysicallyBasedMaterial();
}

final class _FailingSecondExtendedPbrBackend
    implements FlutterSceneExtendedPbrMaterialBackend {
  int createCount = 0;

  @override
  bool get isReady => true;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) async {
    createCount += 1;
    if (createCount == 2) {
      throw StateError('clearcoat variant construction failed');
    }
    return _TestExtendedPbrMaterial(config);
  }
}

final class _UnavailableExtendedPbrBackend
    implements FlutterSceneExtendedPbrMaterialBackend {
  @override
  bool get isReady => false;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async =>
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.unsupportedMaterialFeature,
        message: 'Extended shader unavailable for test.',
        details: <String, Object?>{
          'part': address.debugPath,
          'feature': 'FSViewerExtendedPbr',
          'limitation': 'extendedPbrShaderUnavailable',
          'status': 'blocked',
          'materialReplaced': false,
        },
      );

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) =>
      throw StateError('createMaterial must not run after failed preflight');
}

final class _UnavailableSheenExtendedPbrBackend
    implements
        FlutterSceneExtendedPbrMaterialBackend,
        FlutterSceneSheenMaterialBackend {
  final List<FlutterSceneExtendedPbrResourceRequest> requests =
      <FlutterSceneExtendedPbrResourceRequest>[];

  @override
  bool get isReady => false;

  @override
  bool get isSheenReady => false;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  }) async {
    requests.add(request);
    return ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedMaterialFeature,
      message: 'Sheen directional-albedo resource unavailable for test.',
      details: <String, Object?>{
        'part': address.debugPath,
        'feature': 'FSViewerSheenExtendedPbr',
        'extension': 'KHR_materials_sheen',
        'limitation': 'sheenDirectionalAlbedoResourceUnavailable',
        'status': 'blocked',
        'maturity': 'candidate-only',
        'renderingEvidence': 'not run',
        'materialReplaced': false,
        'decodedTextureCount': 0,
        'encodedBytesModified': false,
      },
    );
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) =>
      throw StateError('createMaterial must not run after failed preflight');
}

final class _ResourceCheckingSheenExtendedPbrBackend
    implements
        FlutterSceneExtendedPbrMaterialBackend,
        FlutterSceneSheenMaterialBackend {
  final List<FlutterSceneExtendedPbrResourceRequest> requests =
      <FlutterSceneExtendedPbrResourceRequest>[];

  @override
  bool get isReady => true;

  @override
  bool get isSheenReady => true;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  }) async {
    requests.add(request);
    return debugFlutterSceneExtendedPbrResourceDiagnostic(address, request);
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) =>
      throw StateError('Incompatible state must fail before construction.');
}

final class _SheenReadyExtendedPbrBackend
    implements
        FlutterSceneExtendedPbrMaterialBackend,
        FlutterSceneSheenMaterialBackend {
  final List<FlutterSceneExtendedPbrResourceRequest> requests =
      <FlutterSceneExtendedPbrResourceRequest>[];
  bool _isSheenReady = false;

  @override
  bool get isReady => false;

  @override
  bool get isSheenReady => _isSheenReady;

  @override
  Future<ViewerDiagnostic?> preflight(PartAddress address) async => null;

  @override
  Future<ViewerDiagnostic?> preflightSheen(
    PartAddress address, {
    required FlutterSceneExtendedPbrResourceRequest request,
  }) async {
    requests.add(request);
    _isSheenReady = true;
    return null;
  }

  @override
  Future<flutter_scene.PhysicallyBasedMaterial> createMaterial(
    FlutterSceneExtendedPbrMaterialConfig config,
  ) =>
      throw StateError('Material construction is outside this preflight test.');
}

final class _UvStubGeometry extends _StubGeometry {
  @override
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
}

final class _Uv1StubGeometry extends _UvStubGeometry {
  @override
  flutter_scene_internal_vertex_layout.VertexLayoutDescriptor?
      get instancedVertexLayout =>
          flutter_scene_internal_geometry.kUnskinnedSoAUV1ColorLayout;
}

MaterialExtensionSupport _materialExtensionSupport(
  MaterialExtensionBackendKind backendKind,
) {
  return MaterialExtensionSupport(
    backendKind: backendKind,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      for (final feature in <MaterialExtensionFeature>[
        MaterialExtensionFeature.transmission,
        MaterialExtensionFeature.ior,
        MaterialExtensionFeature.volume,
        MaterialExtensionFeature.clearcoat,
      ])
        feature: MaterialExtensionFeatureSupport(available: true),
    },
  );
}

final class _StubGeometry extends flutter_scene.Geometry {
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

const FlutterSceneAuthoredMipSamplerIntent _authoredMipSampler =
    FlutterSceneAuthoredMipSamplerIntent(
  magFilter: 9729,
  minFilter: 9987,
  wrapS: 10497,
  wrapT: 10497,
);

List<FlutterSceneAuthoredMipLevel> _authoredLevels(int count) =>
    <FlutterSceneAuthoredMipLevel>[
      if (count >= 1)
        FlutterSceneAuthoredMipLevel(
          level: 0,
          width: 2,
          height: 2,
          rgbaBytes: Uint8List.fromList(List<int>.filled(16, 1)),
        ),
      if (count >= 2)
        FlutterSceneAuthoredMipLevel(
          level: 1,
          width: 1,
          height: 1,
          rgbaBytes: Uint8List.fromList(List<int>.filled(4, 2)),
        ),
    ];

FlutterSceneAuthoredMipImageUpload _singleTargetMipUpload({
  required int imageIndex,
  required int primitiveIndex,
  required FlutterSceneAuthoredMipMaterialSlot slot,
  required FlutterSceneAuthoredMipContentRole role,
}) =>
    FlutterSceneAuthoredMipImageUpload(
      imageIndex: imageIndex,
      contentRole: role,
      levels: _authoredLevels(2),
      textureBindings: <FlutterSceneAuthoredMipTextureBinding>[
        FlutterSceneAuthoredMipTextureBinding(
          textureIndex: imageIndex,
          sampler: _authoredMipSampler,
          targets: <FlutterSceneAuthoredMipMaterialTarget>[
            FlutterSceneAuthoredMipMaterialTarget(
              nodeChildPath: const <int>[],
              primitiveIndex: primitiveIndex,
              slot: slot,
              required: true,
            ),
          ],
        ),
      ],
    );

final class _RecordingMipInterop
    implements FlutterSceneAuthoredMipTextureInterop {
  _RecordingMipInterop({this.failAllocationAt});

  final int? failAllocationAt;
  final List<(int, int, int)> allocations = <(int, int, int)>[];
  final List<int> uploadMipLevels = <int>[];
  int _allocationAttempts = 0;

  @override
  int rendererMipLevelLimit({required int width, required int height}) => 16;

  @override
  Object allocateRgba8Texture({
    required int width,
    required int height,
    required int mipLevelCount,
  }) {
    _allocationAttempts += 1;
    if (_allocationAttempts == failAllocationAt) {
      throw StateError('injected authored mip allocation failure');
    }
    allocations.add((width, height, mipLevelCount));
    return Object();
  }

  @override
  void overwriteRgba8(
    Object texture,
    ByteData rgbaBytes, {
    required int mipLevel,
  }) {
    uploadMipLevels.add(mipLevel);
  }

  @override
  flutter_scene.TextureSource wrapTexture(
    Object texture, {
    required flutter_scene_internal_gpu.SamplerOptions sampler,
  }) =>
      _StubTextureSource(sampler);
}
