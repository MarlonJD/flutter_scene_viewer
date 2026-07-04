import 'package:flutter_scene/scene.dart' as flutter_scene;
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_adapter.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_material_extension_backend.dart';
import 'package:flutter_scene_viewer/src/internal/material_extension_native_capability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
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
      const NativeMaterialExtensionCapability(
        support: MaterialExtensionSupport(
          transmission: true,
          ior: true,
          volume: true,
          clearcoat: true,
          backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        ),
      ),
    );
    final customShader = debugResolveProductionMaterialExtensionSupport(
      const NativeMaterialExtensionCapability(
        support: MaterialExtensionSupport.unsupported,
      ),
      const MaterialExtensionPreflightResult(
        support: MaterialExtensionSupport(
          transmission: true,
          ior: true,
          volume: true,
          clearcoat: true,
          backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
        ),
      ),
    );
    final native = debugResolveProductionMaterialExtensionSupport(
      const NativeMaterialExtensionCapability(
        support: MaterialExtensionSupport(
          transmission: true,
          ior: true,
          volume: true,
          clearcoat: true,
          backendKind: MaterialExtensionBackendKind.rendererNative,
        ),
      ),
    );

    expect(candidate, MaterialExtensionSupport.unsupported);
    expect(customShader.productionReady, isTrue);
    expect(
      customShader.backendKind,
      MaterialExtensionBackendKind.flutterSceneCustomShader,
    );
    expect(native.productionReady, isTrue);
    expect(
      native.backendKind,
      MaterialExtensionBackendKind.rendererNative,
    );
  });

  test('production custom shader support uses package local backend', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();
    const patch = MaterialPatch(transmission: 1.0, ior: 1.45);
    const support = MaterialExtensionSupport(
      transmission: true,
      ior: true,
      volume: true,
      clearcoat: true,
      backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
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
    const support = MaterialExtensionSupport(
      transmission: true,
      ior: true,
      volume: true,
      clearcoat: true,
      backendKind: MaterialExtensionBackendKind.rendererNative,
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

    final diagnostics = await debugApplyMaterialPatchToRoot(
      root,
      PartAddress(nodePath: <String>['A1B32'], primitiveIndex: 1),
      const MaterialPatch(visible: false),
    );

    expect(diagnostics, isEmpty);
    expect(root.visible, isTrue);
    expect(root.mesh!.primitives.first.geometry, same(firstGeometry));
    expect(root.mesh!.primitives.last.geometry, isNot(same(secondGeometry)));
    expect(root.mesh!.primitives, hasLength(2));
  });
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
