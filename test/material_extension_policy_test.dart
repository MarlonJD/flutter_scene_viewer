import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics-only policy exposes unsupported material extensions', () {
    const policy = ViewerMaterialExtensionPolicy.diagnosticsOnly();

    expect(policy.mode, ViewerMaterialExtensionMode.diagnosticsOnly);
    expect(policy.enableTransmission, isFalse);
    expect(policy.enableClearcoat, isFalse);
    expect(policy.support, MaterialExtensionSupport.unsupported);
  });

  test('experimental shader policy exposes transmission support by default',
      () {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders();

    expect(policy.mode,
        ViewerMaterialExtensionMode.experimentalFlutterSceneShaders);
    expect(policy.enableTransmission, isTrue);
    expect(policy.enableClearcoat, isFalse);
    expect(policy.support.transmission, isTrue);
    expect(policy.support.ior, isTrue);
    expect(policy.support.volume, isTrue);
    expect(policy.support.clearcoat, isFalse);
  });

  test('experimental shader policy exposes clearcoat only when enabled', () {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders(
      enableClearcoat: true,
    );

    expect(policy.enableClearcoat, isTrue);
    expect(policy.support.clearcoat, isTrue);
  });

  test('production shader policy requests glass and clearcoat by default', () {
    const policy = ViewerMaterialExtensionPolicy.productionShaders();

    expect(
        policy.mode, ViewerMaterialExtensionMode.productionFlutterSceneShaders);
    expect(policy.enableTransmission, isTrue);
    expect(policy.enableClearcoat, isTrue);
    expect(policy.support.transmission, isTrue);
    expect(policy.support.ior, isTrue);
    expect(policy.support.volume, isTrue);
    expect(policy.support.clearcoat, isTrue);
    expect(policy.support.productionReady, isFalse);
  });

  test('MaterialPatch validation accepts supported transmission intent', () {
    const patch = MaterialPatch(
      transmission: 1.0,
      ior: 1.45,
      thickness: 0.02,
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Glass'], primitiveIndex: 0),
      support: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
      ),
    );

    expect(diagnostics, isEmpty);
  });

  test('MaterialPatch validation keeps unsupported clearcoat diagnostic', () {
    const patch = MaterialPatch(clearcoat: 1.0);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
      support: const MaterialExtensionSupport(
        transmission: true,
        ior: true,
        volume: true,
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_clearcoat'));
  });

  test('MaterialPatch validation accepts supported clearcoat intent', () {
    const patch = MaterialPatch(clearcoat: 1.0, clearcoatRoughness: 0.12);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
      support: const MaterialExtensionSupport(clearcoat: true),
    );

    expect(diagnostics, isEmpty);
  });
}
