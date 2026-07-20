import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/gpu.dart' as flutter_scene_gpu;
import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart' as flutter_scene_fmat;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_internal_gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_scene.dart'
    as flutter_scene_internal_render;
import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/internal/flutter_scene_material_extension_backend.dart';
import 'package:flutter_scene_viewer/src/internal/render_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../tools/material_extension_acceptance/compare_metrics.dart';

final Uint8List _singlePixelPng = Uint8List.fromList(<int>[137, 80, 78, 71]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('texture binding limitations', () {
    test('preprocessed binding resolves TextureSource texture and sampler', () {
      if (!_runFlutterSceneGpuTests) {
        markTestSkipped(_flutterSceneGpuSkipReason);
        return;
      }
      final texture = flutter_scene.Material.getWhitePlaceholderTexture();
      final sampler = flutter_scene_internal_gpu.SamplerOptions(
        minFilter: flutter_scene_internal_gpu.MinMagFilter.nearest,
        magFilter: flutter_scene_internal_gpu.MinMagFilter.nearest,
        mipFilter: flutter_scene_internal_gpu.MipFilter.nearest,
        widthAddressMode: flutter_scene_internal_gpu.SamplerAddressMode.mirror,
        heightAddressMode: flutter_scene_internal_gpu.SamplerAddressMode.mirror,
      );
      final source = flutter_scene.GpuTextureSource(texture, sampler: sampler);
      final parameters = flutter_scene.MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 0,
        parameters: const {},
        samplers: const {'baseColorTexture': null},
      );

      final outcome = debugSetPreprocessedTexture(
        address: _address,
        parameters: parameters,
        slot: 'baseColorTexture',
        texture: source,
      );

      expect(outcome.diagnostic, isNull);
      expect(outcome.texture, same(texture));
      expect(outcome.sampler, same(sampler));
      expect(parameters.assignedValues['baseColorTexture'], same(texture));
      expect(source.sampledSampler, same(sampler));
    });

    test('preprocessed binding retains raw gpu texture support', () {
      if (!_runFlutterSceneGpuTests) {
        markTestSkipped(_flutterSceneGpuSkipReason);
        return;
      }
      final texture = flutter_scene.Material.getWhitePlaceholderTexture();
      final parameters = flutter_scene.MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 0,
        parameters: const {},
        samplers: const {'baseColorTexture': null},
      );

      final outcome = debugSetPreprocessedTexture(
        address: _address,
        parameters: parameters,
        slot: 'baseColorTexture',
        texture: texture,
      );

      expect(outcome.diagnostic, isNull);
      expect(outcome.texture, same(texture));
      expect(outcome.sampler, isNull);
      expect(parameters.assignedValues['baseColorTexture'], same(texture));
    });

    test('unavailable sampled texture reports a typed clearcoat diagnostic',
        () {
      final source = flutter_scene.RenderTexture(width: 1, height: 1);
      final parameters = flutter_scene.MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 0,
        parameters: const {},
        samplers: const {'baseColorTexture': null},
      );

      final outcome = debugSetPreprocessedTexture(
        address: _address,
        parameters: parameters,
        slot: 'baseColorTexture',
        texture: source,
      );

      final diagnostic = outcome.diagnostic!;
      expect(outcome.texture, isNull);
      expect(outcome.sampler, isNull);
      expect(diagnostic.code, ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(diagnostic.details['limitation'],
          'preprocessedTextureSampleUnavailable');
      expect(diagnostic.details['slot'], 'baseColorTexture');
      expect(diagnostic.details['status'], 'blocked');
      expect(parameters.assignedValues, isNot(contains('baseColorTexture')));
    });

    test('independent wrap axes preserve intent in a typed diagnostic', () {
      final binding = MaterialTextureBinding(
        source: const TextureSource.asset('assets/albedo.png'),
        sampler: const TextureSampler(
          wrapS: TextureWrapMode.repeat,
          wrapT: TextureWrapMode.clampToEdge,
        ),
      );

      final diagnostic = flutterSceneTextureBindingDiagnostic(
        address: _address,
        slot: MaterialTextureSlot.baseColor,
        binding: binding,
      );

      expect(diagnostic, isNotNull);
      expect(diagnostic!.code, ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(diagnostic.details['feature'], 'sampler');
      expect(diagnostic.details['limitation'], 'independentWrapAxes');
      expect(diagnostic.details['slot'], 'baseColor');
      expect(diagnostic.details['sampler'], binding.sampler.toJson());
      expect(diagnostic.details['status'], 'blocked');
    });

    test('per-slot offset scale and rotation remain diagnostic-only', () {
      for (final slot in <MaterialTextureSlot>[
        MaterialTextureSlot.baseColor,
        MaterialTextureSlot.metallicRoughness,
        MaterialTextureSlot.normal,
      ]) {
        final binding = MaterialTextureBinding(
          source: TextureSource.bytes(_singlePixelPng, debugName: slot.name),
          transform: TextureTransform(
            offset: const <double>[0.25, 0.5],
            scale: const <double>[2.5, 2.5],
            rotation: 0.3,
          ),
        );
        final before = Uint8List.fromList(_singlePixelPng);

        final diagnostic = flutterSceneTextureBindingDiagnostic(
          address: _address,
          slot: slot,
          binding: binding,
        );

        expect(diagnostic, isNotNull, reason: slot.name);
        expect(
            diagnostic!.code, ViewerDiagnosticCode.unsupportedMaterialFeature,
            reason: slot.name);
        expect(diagnostic.details['feature'], 'KHR_texture_transform');
        expect(
          diagnostic.details['limitation'],
          'perSlotUvTransformContractMissing',
          reason: slot.name,
        );
        expect(diagnostic.details['slot'], slot.name);
        expect(diagnostic.details['transform'], binding.transform.toJson());
        expect(diagnostic.details['status'], 'blocked');
        expect(_singlePixelPng, before, reason: slot.name);
      }
    });
  });

  group('production preflight', () {
    test('accepted replacement retries an unavailable shader preflight',
        () async {
      var libraryLoads = 0;
      var shaderLibraryAvailable = false;
      final backend = FlutterSceneMaterialExtensionBackend(
        loadShaderLibrary: (_) async {
          libraryLoads += 1;
          if (!shaderLibraryAvailable) {
            return null;
          }
          return const _FakeShaderLibrary(
            entries: <String>{
              FlutterSceneMaterialExtensionBackend.transmissionShaderName,
              FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
            },
          );
        },
      );

      final unavailable = await backend.preflightProductionSupport();
      expect(
          unavailable.support.backendKind, MaterialExtensionBackendKind.none);
      final unavailableLoads = libraryLoads;

      shaderLibraryAvailable = true;
      backend.clear(preserveProductionPreflight: true);
      final available = await backend.preflightProductionSupport();

      expect(libraryLoads, unavailableLoads + 1);
      expect(
        available.support.backendKind,
        MaterialExtensionBackendKind.flutterSceneCustomShader,
      );
      expect(available.diagnostics, isEmpty);
    });

    test('accepted scene replacement preserves cached shader preflight',
        () async {
      var libraryLoads = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        loadShaderLibrary: (_) async {
          libraryLoads += 1;
          return const _FakeShaderLibrary(
            entries: <String>{
              FlutterSceneMaterialExtensionBackend.transmissionShaderName,
              FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
            },
          );
        },
      );

      await backend.preflightProductionSupport();
      backend.clear(preserveProductionPreflight: true);
      await backend.preflightProductionSupport();

      expect(libraryLoads, 1);
      expect(backend.debugHasProductionPreflight, isTrue);
    });

    test('production preflight reports unavailable shaders', () async {
      final backend = FlutterSceneMaterialExtensionBackend(
        loadShaderLibrary: (_) async => null,
      );

      final result = await backend.preflightProductionSupport();

      expect(result.support.productionReady, isFalse);
      expect(result.diagnostics.single.code,
          ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(result.diagnostics.single.details['stage'], 'shaderPreflight');
      expect(result.diagnostics.single.details['status'], 'unavailable');
    });

    test('shader preflight preserves candidate maturity without evidence',
        () async {
      final backend = FlutterSceneMaterialExtensionBackend(
        loadShaderLibrary: (_) async => const _FakeShaderLibrary(
          entries: <String>{
            FlutterSceneMaterialExtensionBackend.transmissionShaderName,
            FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
          },
        ),
      );

      final result = await backend.preflightProductionSupport();

      expect(result.support.productionReady, isFalse);
      expect(result.support.transmission, isTrue);
      expect(result.support.ior, isTrue);
      expect(result.support.volume, isTrue);
      expect(result.support.clearcoat, isTrue);
      expect(result.support.claimedReleaseTargets, isEmpty);
      for (final feature in <MaterialExtensionFeature>[
        MaterialExtensionFeature.transmission,
        MaterialExtensionFeature.ior,
        MaterialExtensionFeature.volume,
        MaterialExtensionFeature.clearcoat,
      ]) {
        for (final target in MaterialExtensionTarget.values) {
          expect(
            result.support.supportFor(feature).maturityFor(target),
            MaterialExtensionMaturity.candidateOnly,
          );
          expect(
            result.support.supportFor(feature).evidenceFor(target),
            MaterialExtensionEvidenceStatus.notRun,
          );
        }
      }
      expect(
        result.support.backendKind,
        MaterialExtensionBackendKind.flutterSceneCustomShader,
      );
      expect(result.diagnostics, isEmpty);
    });
  });

  group('production lifecycle', () {
    test('production glass resizes background render texture from viewport',
        () {
      final backend = FlutterSceneMaterialExtensionBackend(
        renderTextureWidth: 128,
        renderTextureHeight: 128,
      );

      final diagnostics = backend.updateViewport(
        width: 640,
        height: 480,
        pixelRatio: 2.0,
      );

      expect(diagnostics, isEmpty);
      expect(backend.debugBackgroundTextureSize, (1280, 960));
    });

    test('clear removes render views, cached states, and preflight state',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
        loadShaderLibrary: (_) async => const _FakeShaderLibrary(
          entries: <String>{
            FlutterSceneMaterialExtensionBackend.transmissionShaderName,
            FlutterSceneMaterialExtensionBackend.clearcoatShaderName,
          },
        ),
      );

      await backend.preflightProductionSupport();
      await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 1.0),
      );

      expect(sceneViews, isNotEmpty);
      expect(backend.debugActivePatchCount, 1);
      expect(backend.debugHasProductionPreflight, isTrue);

      backend.clear(sceneViews: sceneViews);

      expect(sceneViews, isEmpty);
      expect(backend.debugActivePatchCount, 0);
      expect(backend.debugHasProductionPreflight, isFalse);
    });
  });

  group('production glass limits', () {
    test(
        'multiple glass primitives share one background view and restore state',
        () async {
      final sceneViews = <flutter_scene.RenderView>[];
      final first = _glassNode('first')..node.layers = 0x02;
      final second = _glassNode('second')..node.layers = 0x04;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
      );

      await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: first.node,
        primitive: first.primitive,
        address: first.address,
        patch: const MaterialPatch(transmission: 1.0),
      );
      await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: second.node,
        primitive: second.primitive,
        address: second.address,
        patch: const MaterialPatch(transmission: 1.0),
      );

      expect(sceneViews.where((view) => view.target != null), hasLength(1));
      expect(first.node.layers,
          FlutterSceneMaterialExtensionBackend.transmissiveLayer);
      expect(second.node.layers,
          FlutterSceneMaterialExtensionBackend.transmissiveLayer);

      backend.clear(sceneViews: sceneViews);

      expect(sceneViews, isEmpty);
      expect(first.node.layers, 0x02);
      expect(second.node.layers, 0x04);
      expect(first.primitive.material, same(first.originalMaterial));
      expect(second.primitive.material, same(second.originalMaterial));
    });
  });

  group('experimental transmission backend', () {
    test('transmission fmat filters background by roughness before blending',
        () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();
      final backgroundSamples =
          RegExp(r'texture\(backgroundTexture').allMatches(source);

      expect(source, contains('RoughTransmissionBackground'));
      expect(source, contains('roughness_sample_radius'));
      expect(backgroundSamples.length, greaterThanOrEqualTo(5));
    });

    test('transmission fmat bounds transmitted energy with Fresnel', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      expect(source, contains('TransmissionViewFresnel'));
      expect(source, contains('BeerLambertAttenuation'));
      expect(source, contains('TransmissionMaterialColor'));
      expect(source, contains('return vec4(color, alpha);'));
      expect(source, isNot(contains('PremultipliedTransmissionColor')));
      expect(source, contains('glass_fresnel'));
      expect(source, contains('transmitted_energy'));
      expect(source, contains('pow(safe_color'));
    });

    test('transmission fmat uses normative red and green data channels', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      expect(
        source,
        contains(
          'transmissionIorThicknessRoughness.x * '
          'texture(transmissionTexture, v_texture_coords).r',
        ),
      );
      expect(
        source,
        contains(
          'transmissionIorThicknessRoughness.z * '
          'texture(thicknessTexture, v_texture_coords).g',
        ),
      );
      expect(
        source,
        isNot(
          contains(
            'transmissionIorThicknessRoughness.z * '
            'texture(thicknessTexture, v_texture_coords).r',
          ),
        ),
      );
    });

    test('thin transmission has no macroscopic refraction offset', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      expect(
        source,
        matches(
          RegExp(
            r'refraction_offset\s*=\s*normal_offset\s*\*\s*transmission'
            r'\s*\*\s*\(ior - 1\.0\)\s*\*\s*thickness\s*\*\s*0\.06',
          ),
        ),
      );
      expect(source, isNot(contains('0.035')));
    });

    test('optical transmission leaves alpha-as-coverage independent', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();
      final compilation = flutter_scene_fmat.compileFmat(
        source,
        fileName: 'assets/materials/fsviewer_transmission.fmat',
      );

      expect(compilation.material.shadingModel.name, 'unlit');
      expect(
        compilation.material.fragmentSource,
        matches(
          RegExp(
            r'float alpha\s*=\s*clamp\(base_color\.a,\s*0\.0,\s*1\.0\);',
          ),
        ),
      );
      expect(
        compilation.glsl,
        contains(
          'frag_color = vec4(material.base_color.rgb, 1.0) * '
          'material.base_color.a;',
        ),
      );
      expect(source, isNot(contains('mix(base_color.a')));
      expect(source, isNot(contains('0.56')));
      expect(source, isNot(contains('0.88')));
    });

    test('transmission fmat contains no authored studio or contour cues', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      for (final forbidden in <String>[
        'TransmissionSourceDetail',
        'TransmissionContourResponse',
        'TransmissionGlassContour',
        'TransmissionSpecularCue',
        'source_detail',
        'contour_response',
        'rim_response',
        'key_direction',
        'fill_direction',
        'key_exponent',
        'fill_exponent',
        'key_glint',
        'fill_glint',
        'rim_glint',
        'vec3(0.92, 1.0, 0.78)',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('transmission fmat contains no arbitrary radiance heuristics', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      for (final forbidden in <String>[
        'roughness * 0.35',
        'reflection_tint',
        'surface_reflection',
        'mix(vec3(1.0), base_color.rgb',
        'clamp(transmitted_color',
        'vec3(0.001)',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(
        source,
        contains(
          'vec3 transmitted_radiance = '
          'attenuated_background * base_color.rgb;',
        ),
      );
      expect(
        source,
        contains(
          'vec3 diffuse_source = base_color.rgb * (1.0 - transmission);',
        ),
      );
      expect(
        source,
        contains(
          'vec3 color = '
          'diffuse_source + transmitted_radiance * transmitted_energy;',
        ),
      );
    });

    test('zero transmission retains source base behavior', () {
      final source = File('assets/materials/fsviewer_transmission.fmat')
          .readAsStringSync();

      expect(
        source,
        contains(
          'vec3 diffuse_source = base_color.rgb * (1.0 - transmission);',
        ),
      );
      expect(
        source,
        contains(
          'diffuse_source + transmitted_radiance * transmitted_energy',
        ),
      );
      expect(
        source,
        contains('float transmitted_energy = transmission *'),
      );
    });

    test('zero transmission is an allocation-free no-op', () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'InactiveGlass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x04;
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      var materialCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          materialCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.0),
        transmissionTexture: Object(),
      );

      expect(diagnostics, isEmpty);
      expect(materialCreationCount, 0);
      expect(backend.debugActivePatchCount, 0);
      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x04);
      expect(sceneViews, isEmpty);
    });

    test('zero transmission restores an active candidate patch', () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'ActiveGlass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x08;
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      var materialCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          materialCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );

      final initialDiagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.8),
      );
      final zeroDiagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.0),
      );

      expect(initialDiagnostics, isEmpty);
      expect(zeroDiagnostics, isEmpty);
      expect(materialCreationCount, 1);
      expect(backend.debugActivePatchCount, 0);
      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x08);
      expect(sceneViews, isEmpty);
    });

    test('positive transmission texture rejects unlit base replacement',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'TexturedGlass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x10;
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      var materialCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          materialCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.8),
        transmissionTexture: Object(),
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code,
          ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(diagnostics.single.details['limitation'],
          'packageLocalTransmissionTextureBasePbrContractMissing');
      expect(diagnostics.single.details['transmission'], 0.8);
      expect(diagnostics.single.details['hasTransmissionTexture'], isTrue);
      expect(diagnostics.single.details['maturity'], 'candidate-only');
      expect(diagnostics.single.details['status'], 'blocked');
      expect(materialCreationCount, 0);
      expect(backend.debugActivePatchCount, 0);
      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x10);
      expect(sceneViews, isEmpty);
    });

    test('positive thickness rejects missing volume transform contract',
        () async {
      for (final thicknessTexture in <Object?>[null, Object()]) {
        final originalMaterial = flutter_scene.ShaderMaterial();
        final node = flutter_scene.Node(
          name: 'VolumeGlass',
          mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
        )..layers = 0x20;
        final primitive = node.mesh!.primitives.single;
        final sceneViews = <flutter_scene.RenderView>[];
        var materialCreationCount = 0;
        final backend = FlutterSceneMaterialExtensionBackend(
          bindFallbackTextures: false,
          createTransmissionMaterial: (_) async {
            materialCreationCount += 1;
            return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
          },
        );

        final diagnostics = await backend.applyTransmissionPatch(
          sceneViews: sceneViews,
          node: node,
          primitive: primitive,
          address: _address,
          patch: const MaterialPatch(transmission: 0.8, thickness: 0.2),
          thicknessTexture: thicknessTexture,
        );

        expect(diagnostics, hasLength(1), reason: '$thicknessTexture');
        expect(diagnostics.single.code,
            ViewerDiagnosticCode.unsupportedMaterialFeature);
        expect(diagnostics.single.details['limitation'],
            'packageLocalVolumeTransformContractMissing');
        expect(diagnostics.single.details['thickness'], 0.2);
        expect(diagnostics.single.details['hasThicknessTexture'],
            thicknessTexture != null);
        expect(diagnostics.single.details['maturity'], 'candidate-only');
        expect(diagnostics.single.details['status'], 'blocked');
        expect(materialCreationCount, 0);
        expect(backend.debugActivePatchCount, 0);
        expect(primitive.material, same(originalMaterial));
        expect(node.layers, 0x20);
        expect(sceneViews, isEmpty);
      }
    });

    test('IOR zero rejects unsupported Khronos compatibility mode', () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'CompatibilityGlass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x40;
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      var materialCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async {
          materialCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: false);
        },
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.8, ior: 0.0),
      );

      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code,
          ViewerDiagnosticCode.unsupportedMaterialFeature);
      expect(diagnostics.single.details['limitation'],
          'packageLocalIorZeroCompatibilityContractMissing');
      expect(diagnostics.single.details['ior'], 0.0);
      expect(diagnostics.single.details['compatibilityMode'],
          'specularGlossinessBackwardsCompatibility');
      expect(diagnostics.single.details['effectiveFresnel'], 1.0);
      expect(diagnostics.single.details['maturity'], 'candidate-only');
      expect(diagnostics.single.details['status'], 'blocked');
      expect(materialCreationCount, 0);
      expect(backend.debugActivePatchCount, 0);
      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x40);
      expect(sceneViews, isEmpty);
    });

    test('assigns transmissive layer, background view, and glass material',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: MaterialPatch(
          baseColorFactor: <double>[0.6, 0.7, 0.8, 1.0],
          transmission: 1.0,
          ior: 1.45,
          thickness: 0.0,
          attenuationColor: <double>[0.9, 0.95, 1.0],
          attenuationDistance: 4.0,
          roughness: 0.25,
        ),
      );

      expect(diagnostics, isEmpty);
      expect(
        node.layers,
        FlutterSceneMaterialExtensionBackend.transmissiveLayer,
      );
      expect(sceneViews, hasLength(1));
      expect(
        sceneViews.single.layerMask &
            FlutterSceneMaterialExtensionBackend.transmissiveLayer,
        0,
      );
      expect(sceneViews.single.target, isA<flutter_scene.RenderTexture>());
      final material = primitive.material as flutter_scene.ShaderMaterial;
      expect(material.isOpaque(), isFalse);
      expect(material.textureNames, contains('backgroundTexture'));
      expect(material.uniformBlockNames, contains('MaterialParams'));
      final params = material.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(0, Endian.host), closeTo(0.6, 0.0001));
      expect(params.getFloat32(16, Endian.host), closeTo(0.9, 0.0001));
      expect(params.getFloat32(32, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(36, Endian.host), closeTo(1.45, 0.0001));
    });

    test('runtime transmission patch preserves source texture slots', () {
      final source = File(
        'lib/src/internal/flutter_scene_material_extension_backend.dart',
      ).readAsStringSync();
      final configureTransmission = source.substring(
        source.indexOf('static void _configureTransmissionMaterial'),
        source.indexOf('static List<double> _materialParams'),
      );
      final transmissionConfig = source.substring(
        source.indexOf('final class FlutterSceneTransmissionMaterialConfig'),
        source.indexOf('final class FlutterSceneClearcoatMaterialConfig'),
      );

      expect(configureTransmission, contains('config.sourceBaseColorTexture'));
      expect(configureTransmission, contains('config.sourceNormalTexture'));
      expect(transmissionConfig, contains('sourceBaseColorTexture'));
      expect(transmissionConfig, contains('sourceNormalTexture'));
    });

    test('sanitizes transmission shader uniforms before assignment', () async {
      final material = flutter_scene.ShaderMaterial(isOpaqueOverride: false);
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async => material,
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: MaterialPatch(
          baseColorFactor: <double>[double.nan, -1.0, 2.0, double.infinity],
          transmission: double.nan,
          ior: -10.0,
          thickness: double.nan,
          attenuationColor: <double>[-1.0, double.nan, 2.0],
          attenuationDistance: double.infinity,
          roughness: 4.0,
          normalScale: -2.0,
        ),
      );

      expect(diagnostics, isEmpty);
      final params = material.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(0, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(4, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(8, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(12, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(16, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(20, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(24, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(28, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(32, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(36, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(40, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(44, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(56, Endian.host), closeTo(0.0, 0.0001));
    });

    test('updates background camera and restores material, layers, and view',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x04;
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
      );

      await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.8, ior: 1.4),
      );
      backend.updateCamera(
        const RenderCameraFrame(
          position: <double>[1, 2, 3],
          target: <double>[0, 0, 0],
        ),
      );

      final camera =
          sceneViews.single.camera as flutter_scene.PerspectiveCamera;
      expect(camera.position, vm.Vector3(1, 2, 3));

      backend.resetTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
      );

      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x04);
      expect(sceneViews, isEmpty);
    });

    test('preserves double-sided source culling for glass shader material',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial()
        ..doubleSided = true;
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
      );

      final diagnostics = await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 1.0),
      );

      expect(diagnostics, isEmpty);
      final material = primitive.material as flutter_scene.ShaderMaterial;
      expect(material.cullingMode, flutter_scene_internal_gpu.CullMode.none);
    });

    test('refreshes mounted render items when replacing and restoring material',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Glass',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final renderScene = flutter_scene_internal_render.RenderScene();
      node.debugMountInto(renderScene);
      final sceneViews = <flutter_scene.RenderView>[];
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createTransmissionMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: false),
      );

      expect(renderScene.items.single.material, same(originalMaterial));

      await backend.applyTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(transmission: 0.9),
      );

      expect(renderScene.items.single.material, same(primitive.material));
      expect(renderScene.items.single.material, isNot(same(originalMaterial)));

      backend.resetTransmissionPatch(
        sceneViews: sceneViews,
        node: node,
        primitive: primitive,
      );

      expect(renderScene.items.single.material, same(originalMaterial));
    });
  });

  group('experimental clearcoat backend', () {
    test('clearcoat fmat declares a lit alpha candidate overlay', () {
      final source =
          File('assets/materials/fsviewer_clearcoat.fmat').readAsStringSync();

      expect(source, contains('shading_model: lit'));
      expect(source, contains('blending: alpha'));
      expect(source, contains('clearcoatTexture'));
      expect(source, contains('clearcoatRoughnessTexture'));
      expect(source, contains('clearcoatNormalTexture'));
      expect(source, isNot(contains('key_direction')));
    });

    test('clearcoat fmat keeps candidate base attenuation bounded', () {
      final source =
          File('assets/materials/fsviewer_clearcoat.fmat').readAsStringSync();

      expect(source, contains('ClearcoatBaseEnergyLoss'));
      expect(source, contains('clearcoat * 0.04 * source_alpha'));
      expect(source, isNot(contains('ClearcoatViewFresnel')));
      expect(source, isNot(contains('clearcoat_fresnel')));
      expect(source, contains('base_energy_loss'));
      expect(source, contains('max(base_energy_loss'));
    });

    test('clearcoat fmat does not synthesize unrelated studio spots', () {
      final source =
          File('assets/materials/fsviewer_clearcoat.fmat').readAsStringSync();

      expect(source, isNot(contains('ClearcoatGlintBoost')));
      expect(source, isNot(contains('ClearcoatStudioHighlight')));
      expect(source, isNot(contains('clearcoat_glint')));
      expect(source, isNot(contains('clearcoat_studio_highlight')));
      expect(source, isNot(contains('left_spot')));
      expect(source, isNot(contains('right_spot')));
      expect(source, isNot(contains('glint_exponent')));
      expect(source, isNot(contains('coat_highlight_energy')));
      expect(source, isNot(contains('highlight_alpha')));
      expect(source, isNot(contains('coat_emissive')));
    });

    test('clearcoat fmat delegates one complete lighting evaluation to engine',
        () {
      final source =
          File('assets/materials/fsviewer_clearcoat.fmat').readAsStringSync();
      final compilation = flutter_scene_fmat.compileFmat(
        source,
        fileName: 'assets/materials/fsviewer_clearcoat.fmat',
      );

      expect(compilation.material.shadingModel.name, 'lit');
      expect(
        RegExp(
          RegExp.escape('EvaluateLighting(material)'),
        ).allMatches(compilation.glsl),
        hasLength(1),
      );
      final authoredSurface = compilation.material.fragmentSource;
      for (final forbidden in <String>[
        'ClearcoatLobe',
        'SamplePrefilteredRadiance',
        'brdf_lut',
        'frag_info.directional_light_direction',
        'frag_info.directional_light_color',
        'SampleShadow',
        'DistributionGGX',
        'VisibilitySmithGGXCorrelated',
        'FresnelSchlick',
        'material.emissive',
        'coat_emissive',
      ]) {
        expect(
          authoredSurface,
          isNot(contains(forbidden)),
          reason:
              'Surface must not manually evaluate engine lighting: $forbidden',
        );
      }
      expect(
        authoredSurface,
        contains('material.roughness = clearcoat_roughness;'),
      );
      expect(authoredSurface, contains('material.normal = clearcoat_normal;'));
      expect(
        authoredSurface,
        contains('float overlay_alpha = clearcoat <= 0.0 ? 0.0 :'),
      );
    });

    test('clearcoat fmat feeds independent coat normal to engine lighting', () {
      final source =
          File('assets/materials/fsviewer_clearcoat.fmat').readAsStringSync();

      expect(source, isNot(contains('base_detail_normal')));
      expect(source, contains('clearcoat_smooth_normal'));
      expect(source, contains('explicit_clearcoat_normal'));
      expect(
        source,
        contains(
          'normalize(mix(clearcoat_smooth_normal, explicit_clearcoat_normal,',
        ),
      );
      expect(source, contains('material.normal = clearcoat_normal;'));
      expect(
        source,
        isNot(contains('material.normal = clearcoat_smooth_normal;')),
      );
      expect(source, isNot(contains('material.normal = base_detail_normal;')));
      expect(source, isNot(contains('normalize(mix(base_normal')));
    });

    test('clearcoat adds translucent overlay without replacing source material',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Paint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x08;
      final primitive = node.mesh!.primitives.single;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: true),
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(
          clearcoat: 1.0,
          clearcoatRoughness: 0.05,
        ),
      );

      expect(diagnostics, isEmpty);
      expect(node.layers, 0x08);
      expect(node.mesh!.primitives, hasLength(2));
      expect(node.mesh!.primitives.first, same(primitive));
      expect(primitive.material, same(originalMaterial));
      final overlayPrimitive = node.mesh!.primitives.last;
      expect(overlayPrimitive, isNot(same(primitive)));
      expect(overlayPrimitive.geometry, same(primitive.geometry));
      expect(overlayPrimitive.material, isA<flutter_scene.ShaderMaterial>());
      expect(overlayPrimitive.material.isOpaque(), isFalse);

      backend.resetClearcoatPatch(node: node, primitive: primitive);

      expect(node.layers, 0x08);
      expect(node.mesh!.primitives, hasLength(1));
      expect(node.mesh!.primitives.single, same(primitive));
      expect(primitive.material, same(originalMaterial));
    });

    test(
        'package-local clearcoat rejects double-sided PBR before creating an overlay',
        () async {
      final sourceNormal = _textureSlotSource();
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..doubleSided = true
        ..normalTexture = sourceNormal
        ..normalScale = 0.8;
      final node = flutter_scene.Node(
        name: 'DoubleSidedPaint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      var materialCreationCount = 0;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async {
          materialCreationCount += 1;
          return flutter_scene.ShaderMaterial(isOpaqueOverride: true);
        },
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 1.0),
      );

      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature,
      );
      expect(
        diagnostics.single.details,
        containsPair(
          'limitation',
          'packageLocalClearcoatDoubleSidedCullingContractMissing',
        ),
      );
      expect(
        diagnostics.single.details,
        containsPair('backendKind', 'flutterSceneCustomShader'),
      );
      expect(
        diagnostics.single.details,
        containsPair('maturity', 'candidate-only'),
      );
      expect(diagnostics.single.details, containsPair('status', 'blocked'));
      expect(
        diagnostics.single.details,
        containsPair('sourceDoubleSided', true),
      );
      expect(materialCreationCount, 0);
      expect(backend.debugActivePatchCount, 0);
      expect(node.mesh!.primitives, hasLength(1));
      expect(node.mesh!.primitives.single, same(primitive));
      expect(primitive.material, same(originalMaterial));
      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(0.8, 0.0001));
    });

    test('production clearcoat binds all texture slots and factors', () async {
      final material = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      final paint = _paintNode('production-clearcoat');
      final baseColorTexture = _textureSlotSource();
      final metallicRoughnessTexture = _textureSlotSource();
      final normalTexture = _textureSlotSource();
      final clearcoatTexture = _textureSlotSource();
      final clearcoatRoughnessTexture = _textureSlotSource();
      final clearcoatNormalTexture = _textureSlotSource();
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async => material,
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: paint.node,
        primitive: paint.primitive,
        address: paint.address,
        patch: MaterialPatch(
          baseColorFactor: const <double>[0.2, 0.1, 0.05, 1.0],
          metallic: 0.0,
          roughness: 0.7,
          clearcoat: 1.0,
          clearcoatRoughness: 0.05,
          clearcoatNormalScale: 0.8,
        ),
        baseColorTexture: baseColorTexture,
        metallicRoughnessTexture: metallicRoughnessTexture,
        normalTexture: normalTexture,
        clearcoatTexture: clearcoatTexture,
        clearcoatRoughnessTexture: clearcoatRoughnessTexture,
        clearcoatNormalTexture: clearcoatNormalTexture,
      );

      expect(diagnostics, isEmpty);
      expect(material.useEnvironment, isTrue);
      expect(
          material.textureNames,
          containsAll(<String>[
            'baseColorTexture',
            'metallicRoughnessTexture',
            'normalTexture',
            'clearcoatTexture',
            'clearcoatRoughnessTexture',
            'clearcoatNormalTexture',
          ]));
      expect(material.uniformBlockNames, contains('MaterialParams'));
      final params = material.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(0, Endian.host), closeTo(0.2, 0.0001));
      expect(params.getFloat32(16, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(20, Endian.host), closeTo(0.7, 0.0001));
      expect(params.getFloat32(24, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(28, Endian.host), closeTo(0.05, 0.0001));
      expect(params.getFloat32(36, Endian.host), closeTo(0.8, 0.0001));
      expect(params.getFloat32(40, Endian.host), closeTo(1.0, 0.0001));
    });

    test('production clearcoat loader configures lit fmat parameters',
        () async {
      if (!_runFlutterSceneGpuTests) {
        markTestSkipped(_flutterSceneGpuSkipReason);
        return;
      }
      try {
        await flutter_scene.Scene.initializeStaticResources()
            .timeout(const Duration(seconds: 10));
      } on TimeoutException catch (_) {
        markTestSkipped('Timed out initializing Flutter GPU scene resources.');
        return;
      } on Object catch (error) {
        markTestSkipped('No compatible Flutter GPU scene context: $error');
        return;
      }
      final occlusionTexture = _solidColorTexture(0xFF7F7F7F);
      final emissiveTexture = _solidColorTexture(0xFF332211);
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.08, 0.1, 0.13, 1.0)
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.72
        ..occlusionTexture = occlusionTexture
        ..emissiveTexture = emissiveTexture
        ..emissiveFactor = vm.Vector4(0.1, 0.2, 0.3, 1.0);
      final node = flutter_scene.Node(
        name: 'Paint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final backend = FlutterSceneMaterialExtensionBackend();

      final diagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(
          clearcoat: 1.0,
          clearcoatRoughness: 0.05,
        ),
      );

      expect(diagnostics, isEmpty);
      expect(primitive.material, same(originalMaterial));
      expect(node.mesh!.primitives, hasLength(2));
      final material = node.mesh!.primitives.last.material
          as flutter_scene.PreprocessedMaterial;
      expect(material.shadingModel.name, 'lit');
      expect(material.isOpaque(), isFalse);
      final materialFactors =
          material.parameters.assignedValues['materialFactors'] as vm.Vector4;
      expect(materialFactors.z, closeTo(1.0, 0.0001));
      expect(materialFactors.w, closeTo(0.05, 0.0001));
      final normalFactors =
          material.parameters.assignedValues['normalFactors'] as vm.Vector4;
      expect(normalFactors.z, closeTo(0.0, 0.0001));
      expect(
        material.parameters.assignedValues['occlusionTexture'],
        same(occlusionTexture),
      );
      expect(
        material.parameters.assignedValues['emissiveTexture'],
        same(emissiveTexture),
      );
      final emissiveFactor =
          material.parameters.assignedValues['emissiveFactor'] as vm.Vector4;
      expect(emissiveFactor.x, closeTo(0.1, 0.0001));
      expect(emissiveFactor.y, closeTo(0.2, 0.0001));
      expect(emissiveFactor.z, closeTo(0.3, 0.0001));
    });

    test('assigns translucent clearcoat overlay material and preserves source',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Paint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: true),
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: MaterialPatch(
          baseColorFactor: <double>[0.4, 0.35, 0.28, 1.0],
          metallic: 0.0,
          roughness: 0.5,
          clearcoat: 1.0,
          clearcoatRoughness: 0.12,
          clearcoatNormalScale: 0.75,
        ),
      );

      expect(diagnostics, isEmpty);
      expect(primitive.material, same(originalMaterial));
      expect(node.mesh!.primitives, hasLength(2));
      final material =
          node.mesh!.primitives.last.material as flutter_scene.ShaderMaterial;
      expect(material.isOpaque(), isFalse);
      expect(material.useEnvironment, isTrue);
      expect(material.uniformBlockNames, contains('MaterialParams'));
      final params = material.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(0, Endian.host), closeTo(0.4, 0.0001));
      expect(params.getFloat32(16, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(20, Endian.host), closeTo(0.5, 0.0001));
      expect(params.getFloat32(24, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(28, Endian.host), closeTo(0.12, 0.0001));
      expect(params.getFloat32(32, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(36, Endian.host), closeTo(0.75, 0.0001));
    });

    test('positive clearcoat preserves source PBR normal texture and scale',
        () async {
      final sourceNormal = _textureSlotSource();
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..normalTexture = sourceNormal
        ..normalScale = 1.0;
      final node = flutter_scene.Node(
        name: 'FlakePaint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: true),
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(
          clearcoat: 1.0,
          clearcoatRoughness: 0.08,
        ),
      );

      expect(diagnostics, isEmpty);
      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(1.0, 0.0001));
      final overlayMaterial =
          node.mesh!.primitives.last.material as flutter_scene.ShaderMaterial;
      final params = overlayMaterial.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(32, Endian.host), closeTo(1.0, 0.0001));

      backend.resetClearcoatPatch(node: node, primitive: primitive);

      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(1.0, 0.0001));
    });

    test('factor zero leaves the already-preserved source normal unchanged',
        () async {
      final sourceNormal = _textureSlotSource();
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..normalTexture = sourceNormal
        ..normalScale = 0.8;
      final node = flutter_scene.Node(
        name: 'SequentialPaint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: true),
      );

      final activeDiagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 1.0),
      );
      expect(activeDiagnostics, isEmpty);
      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(0.8, 0.0001));

      final zeroDiagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 0.0),
      );

      expect(zeroDiagnostics, isEmpty);
      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(0.8, 0.0001));
    });

    test('replacement clearcoat preserves source PBR normal and scale',
        () async {
      final sourceNormal = _textureSlotSource();
      final originalMaterial = flutter_scene.PhysicallyBasedMaterial()
        ..normalTexture = sourceNormal
        ..normalScale = 0.8;
      final node = flutter_scene.Node(
        name: 'SequentialPaint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      );
      final primitive = node.mesh!.primitives.single;
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

      final firstDiagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 1.0),
      );
      final replacementDiagnostics = await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 0.6),
      );

      expect(firstDiagnostics, isEmpty);
      expect(replacementDiagnostics, isEmpty);
      expect(configs, hasLength(2));
      expect(configs.last.normalTexture, isNull);
      expect(configs.last.sourceNormalTexture, same(sourceNormal));
      expect(overlays, hasLength(2));
      final params = overlays.last.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(32, Endian.host), closeTo(0.8, 0.0001));
      // ignore: invalid_use_of_internal_member
      expect(originalMaterial.normalTextureSource, same(sourceNormal));
      expect(originalMaterial.normalScale, closeTo(0.8, 0.0001));
    });

    test('sanitizes clearcoat shader uniforms before assignment', () async {
      final material = flutter_scene.ShaderMaterial(isOpaqueOverride: true);
      final paint = _paintNode('sanitized-clearcoat');
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async => material,
      );

      final diagnostics = await backend.applyClearcoatPatch(
        node: paint.node,
        primitive: paint.primitive,
        address: paint.address,
        patch: MaterialPatch(
          baseColorFactor: <double>[double.nan, -1.0, 2.0, double.infinity],
          metallic: -1.0,
          roughness: 5.0,
          clearcoat: double.nan,
          clearcoatRoughness: double.infinity,
          normalScale: -2.0,
          clearcoatNormalScale: double.infinity,
        ),
      );

      expect(diagnostics, isEmpty);
      final params = material.getUniformBlock('MaterialParams')!;
      expect(params.getFloat32(0, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(4, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(8, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(12, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(16, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(20, Endian.host), closeTo(1.0, 0.0001));
      expect(params.getFloat32(24, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(28, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(32, Endian.host), closeTo(0.0, 0.0001));
      expect(params.getFloat32(36, Endian.host), closeTo(1.0, 0.0001));
    });

    test(
        'refreshes mounted render items when adding and restoring clearcoat overlay',
        () async {
      final originalMaterial = flutter_scene.ShaderMaterial();
      final node = flutter_scene.Node(
        name: 'Paint',
        mesh: flutter_scene.Mesh(_StubGeometry(), originalMaterial),
      )..layers = 0x08;
      final primitive = node.mesh!.primitives.single;
      final renderScene = flutter_scene_internal_render.RenderScene();
      node.debugMountInto(renderScene);
      final backend = FlutterSceneMaterialExtensionBackend(
        bindFallbackTextures: false,
        createClearcoatMaterial: (_) async =>
            flutter_scene.ShaderMaterial(isOpaqueOverride: true),
      );

      expect(renderScene.items.single.material, same(originalMaterial));

      await backend.applyClearcoatPatch(
        node: node,
        primitive: primitive,
        address: _address,
        patch: const MaterialPatch(clearcoat: 1.0),
      );

      expect(renderScene.items, hasLength(2));
      expect(renderScene.items.first.material, same(originalMaterial));
      expect(renderScene.items.last.material,
          same(node.mesh!.primitives.last.material));

      backend.resetClearcoatPatch(
        node: node,
        primitive: primitive,
      );

      expect(primitive.material, same(originalMaterial));
      expect(node.layers, 0x08);
      expect(renderScene.items.single.material, same(originalMaterial));
    });
  });

  test('debug tint fmat material loads through generated shader bundle',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }

    final library = await flutter_scene_gpu.loadShaderLibraryAsync(
      'build/shaderbundles/materials.shaderbundle',
    );
    final sidecarJson = jsonDecode(
      await rootBundle.loadString('build/shaderbundles/materials.fmat.json'),
    ) as Map<String, Object?>;
    final metadata =
        (sidecarJson['FSViewerDebugTint'] as Map).cast<String, Object?>();
    final material = flutter_scene.PreprocessedMaterial(
      fragmentShader: library!['FSViewerDebugTint']!,
      metadata: metadata,
    );

    expect(material, isA<flutter_scene.PreprocessedMaterial>());
    expect(material.isOpaque(), isTrue);
    expect(material.shadingModel.name, 'unlit');
  });

  test('transmission fmat shader loads through generated shader bundle',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }

    final library = await flutter_scene_gpu.loadShaderLibraryAsync(
      'build/shaderbundles/materials.shaderbundle',
    );
    final shader =
        library![FlutterSceneMaterialExtensionBackend.transmissionShaderName];
    final material = flutter_scene.ShaderMaterial(
      fragmentShader: shader!,
      isOpaqueOverride: false,
    );

    expect(shader, isNotNull);
    expect(material.isOpaque(), isFalse);
  });

  test('clearcoat fmat shader loads through generated shader bundle', () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }

    final library = await flutter_scene_gpu.loadShaderLibraryAsync(
      'build/shaderbundles/materials.shaderbundle',
    );
    final shader =
        library![FlutterSceneMaterialExtensionBackend.clearcoatShaderName];
    final material = flutter_scene.ShaderMaterial(
      fragmentShader: shader!,
      useEnvironment: true,
      isOpaqueOverride: true,
    );

    expect(shader, isNotNull);
    expect(material.useEnvironment, isTrue);
    expect(material.isOpaque(), isTrue);
  });

  test('transmission shader renders readable background refraction smoke',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }
    flutter_scene.Scene scene;
    try {
      await flutter_scene.Scene.initializeStaticResources()
          .timeout(const Duration(seconds: 10));
      scene = flutter_scene.Scene();
    } on TimeoutException catch (_) {
      markTestSkipped('Timed out initializing Flutter GPU scene resources.');
      return;
    } on Object catch (error) {
      markTestSkipped('No compatible Flutter GPU scene context: $error');
      return;
    }

    _addStripe(
      scene,
      name: 'red-stripe',
      x: -0.6,
      color: vm.Vector4(1.0, 0.05, 0.05, 1.0),
    );
    _addStripe(
      scene,
      name: 'green-stripe',
      x: 0.0,
      color: vm.Vector4(0.05, 1.0, 0.15, 1.0),
    );
    _addStripe(
      scene,
      name: 'blue-stripe',
      x: 0.6,
      color: vm.Vector4(0.05, 0.2, 1.0, 1.0),
    );

    final glassMaterial = flutter_scene.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.9, 1.0, 1.0)
      ..metallicFactor = 0.0
      ..roughnessFactor = 0.02;
    final glassNode = flutter_scene.Node(
      name: 'glass',
      mesh: flutter_scene.Mesh(
        flutter_scene.CuboidGeometry(vm.Vector3(1.7, 1.7, 0.04)),
        glassMaterial,
      ),
    )..localTransform = (vm.Matrix4.identity()
      ..translateByDouble(0.0, 0.0, 0.85, 1.0)
      ..rotateY(0.42));
    scene.add(glassNode);

    const cameraFrame = RenderCameraFrame(
      position: <double>[0.0, 0.0, 4.0],
      target: <double>[0.0, 0.0, 0.0],
    );
    final backend = FlutterSceneMaterialExtensionBackend(
      renderTextureWidth: 256,
      renderTextureHeight: 256,
    )..updateCamera(cameraFrame);
    final diagnostics = await backend.applyTransmissionPatch(
      sceneViews: scene.views,
      node: glassNode,
      primitive: glassNode.mesh!.primitives.single,
      address: _address,
      patch: MaterialPatch(
        baseColorFactor: const <double>[0.75, 0.9, 1.0, 1.0],
        transmission: 1.0,
        ior: 1.85,
        thickness: 0.55,
        attenuationColor: const <double>[0.85, 0.95, 1.0],
        attenuationDistance: 2.0,
        roughness: 0.04,
      ),
    );
    expect(diagnostics, isEmpty);

    final camera = flutter_scene.PerspectiveCamera(
      position: vm.Vector3(0, 0, 4),
      target: vm.Vector3.zero(),
    );
    final image = await _renderVisualSmokeImage(scene, camera);

    final backgroundTarget = scene.views.single.target!;
    if (backgroundTarget.texture == null) {
      markTestSkipped('Background RenderTexture did not complete a frame.');
      return;
    }

    final png = await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 10));
    final rgba = await image
        .toByteData(format: ui.ImageByteFormat.rawRgba)
        .timeout(const Duration(seconds: 10));
    expect(png, isNotNull);
    expect(rgba, isNotNull);
    Directory('tools/out').createSync(recursive: true);
    File('tools/out/fsviewer_transmission_smoke.png').writeAsBytesSync(
      png!.buffer.asUint8List(),
    );

    final pixels = rgba!.buffer.asUint8List();
    final distinctColors = _sampleDistinctColors(
      pixels,
      width: image.width,
      height: image.height,
    );
    expect(
      distinctColors,
      greaterThan(3),
    );
    final channelSpread = _sampleChannelSpread(
      pixels,
      width: image.width,
      height: image.height,
    );
    expect(
      channelSpread,
      greaterThan(80),
    );
    final dominantChannels = _sampleDominantChannels(
      pixels,
      width: image.width,
      height: image.height,
    );
    expect(
      dominantChannels,
      containsAll(<String>{'red', 'green', 'blue'}),
    );
  });

  test('production glass visual matrix responds to transmission and IOR',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }

    final GlassMatrixEvidence evidence;
    try {
      evidence = await renderGlassMatrixEvidence(
        transmissionValues: <double>[0.0, 0.5, 1.0],
        iorValues: <double>[1.0, 1.45, 1.85],
      );
    } on _VisualSmokeSkipped catch (skip) {
      markTestSkipped(skip.reason);
      return;
    }

    expect(evidence.refractionSpreadForTransmission1,
        greaterThan(evidence.refractionSpreadForTransmission0 + 20));
    expect(evidence.iorOffsetDelta, greaterThan(5));
    expect(evidence.imagePath, 'tools/out/fsviewer_glass_matrix.png');
  });

  test('clearcoat shader renders distinct second specular lobe smoke',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }
    flutter_scene.Scene scene;
    try {
      await flutter_scene.Scene.initializeStaticResources()
          .timeout(const Duration(seconds: 10));
      scene = flutter_scene.Scene()
        ..environmentIntensity = 2.0
        ..skybox = flutter_scene.Skybox(
          flutter_scene.EnvironmentSkySource(blurriness: 0.0),
        );
    } on TimeoutException catch (_) {
      markTestSkipped('Timed out initializing Flutter GPU scene resources.');
      return;
    } on Object catch (error) {
      markTestSkipped('No compatible Flutter GPU scene context: $error');
      return;
    }

    _addGlossySphere(scene, name: 'base-glossy', x: 1.05);
    final clearcoatZero = await _addClearcoatSphere(
      scene,
      name: 'clearcoat-zero',
      x: 0.0,
      clearcoat: 0.0,
      clearcoatRoughness: 0.02,
    );
    final clearcoatFull = await _addClearcoatSphere(
      scene,
      name: 'clearcoat-full',
      x: -1.05,
      clearcoat: 1.0,
      clearcoatRoughness: 0.02,
    );
    expect(clearcoatZero, isEmpty);
    expect(clearcoatFull, isEmpty);

    final camera = flutter_scene.PerspectiveCamera(
      position: vm.Vector3(0, 0, 4.2),
      target: vm.Vector3.zero(),
    );
    final image = await _renderVisualSmokeImage(scene, camera);
    final png = await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 10));
    final rgba = await image
        .toByteData(format: ui.ImageByteFormat.rawRgba)
        .timeout(const Duration(seconds: 10));
    expect(png, isNotNull);
    expect(rgba, isNotNull);
    Directory('tools/out').createSync(recursive: true);
    File('tools/out/fsviewer_clearcoat_smoke.png').writeAsBytesSync(
      png!.buffer.asUint8List(),
    );

    final pixels = rgba!.buffer.asUint8List();
    final baseGlossyLuma = _maxObjectLuminanceInBand(
      pixels,
      width: image.width,
      height: image.height,
      band: 0,
      bandCount: 3,
    );
    final clearcoatZeroLuma = _maxObjectLuminanceInBand(
      pixels,
      width: image.width,
      height: image.height,
      band: 1,
      bandCount: 3,
    );
    final clearcoatFullLuma = _maxObjectLuminanceInBand(
      pixels,
      width: image.width,
      height: image.height,
      band: 2,
      bandCount: 3,
    );
    final clearcoatFullClippedFraction = _brightObjectPixelFractionInBand(
      pixels,
      width: image.width,
      height: image.height,
      band: 2,
      bandCount: 3,
      threshold: 240,
    );
    expect(baseGlossyLuma, greaterThan(15));
    expect(clearcoatZeroLuma, greaterThan(15));
    expect(clearcoatFullLuma, greaterThan(clearcoatZeroLuma + 1));
    expect(clearcoatFullClippedFraction, lessThan(0.02));
  });

  test(
      'production clearcoat visual matrix responds to factor roughness texture and normal',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }

    final ClearcoatMatrixEvidence evidence;
    try {
      evidence = await renderClearcoatMatrixEvidence(
        clearcoatValues: const <double>[0.0, 0.5, 1.0],
        roughnessValues: const <double>[0.02, 0.35, 0.8],
        includeNormalVariant: true,
      );
    } on _VisualSmokeSkipped catch (skip) {
      markTestSkipped(skip.reason);
      return;
    }

    expect(evidence.fullClearcoatHighlight,
        greaterThanOrEqualTo(evidence.zeroClearcoatHighlight));
    expect(evidence.roughClearcoatPeak,
        lessThanOrEqualTo(evidence.smoothClearcoatPeak));
    expect(evidence.clearcoatTextureFrameDelta, greaterThan(0.25));
    expect(evidence.normalVariantHighlightPositionDelta, greaterThan(0.1));
    expect(evidence.imagePath, 'tools/out/fsviewer_clearcoat_matrix.png');
  });

  test('production visual fixture writes shared GLB for reference renderers',
      () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }

    final ProductionMaterialExtensionVisualEvidence evidence;
    try {
      evidence = await renderProductionMaterialExtensionVisualMatrix(
        writeSharedFixture: true,
      );
    } on _VisualSmokeSkipped catch (skip) {
      markTestSkipped(skip.reason);
      return;
    }

    expect(evidence.sharedFixtureGlbPath, isNotNull);
    expect(File(evidence.sharedFixtureGlbPath!).existsSync(), isTrue);
    expect(evidence.flutterSceneGlassImagePath, endsWith('.png'));
    expect(evidence.flutterSceneClearcoatImagePath, endsWith('.png'));
  });

  test('production acceptance manifest covers glass clearcoat and combined',
      () {
    final json = jsonDecode(
      File('tools/material_extension_acceptance/manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final assets = json['assets']! as List<Object?>;
    final roles = assets
        .cast<Map<String, Object?>>()
        .map((asset) => asset['role'])
        .toSet();

    expect(roles, contains('glass_only'));
    expect(roles, contains('clearcoat_only'));
    expect(roles, contains('combined_glass_clearcoat'));
  });

  test('production acceptance manifest includes Khronos visual references', () {
    final json = jsonDecode(
      File('tools/material_extension_acceptance/manifest.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final assets = json['assets']! as List<Object?>;
    final ids =
        assets.cast<Map<String, Object?>>().map((asset) => asset['id']).toSet();

    expect(ids, contains('glass_vase_flowers'));
    expect(ids, contains('clearcoat_car_paint'));
  });

  test('three.js reference fixture supports real asset screenshots', () {
    final source = File(
      'tools/reference_renderers/threejs_material_extension_fixture/'
      'render_reference.mjs',
    ).readAsStringSync();

    expect(source, contains('--real-assets'));
    expect(source, contains('GLTFLoader'));
    expect(source, contains('reference_threejs_water_bottle.png'));
    expect(
      source,
      contains('reference_threejs_clearcoat_car_paint_real_asset.png'),
    );
    expect(source, contains('reference_threejs_real_asset_metrics.json'));
  });

  test('production material extension evidence requires custom shader metrics',
      () {
    final iosEvidence = jsonDecode(
      File(
        'tools/material_extension_acceptance/fixtures/'
        'ios_simulator_custom_shader_metrics_input.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final referenceMetrics = jsonDecode(
      File(
        'tools/material_extension_acceptance/fixtures/'
        'material_extension_reference_metrics.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final metrics = compareMaterialExtensionMetrics(
      iosEvidence: iosEvidence,
      referenceMetrics: referenceMetrics,
    );

    expect(
      MaterialExtensionAcceptanceMetrics.fromJson(
        jsonDecode(
          jsonEncode(metrics.toJson()),
        ) as Map<String, Object?>,
      ).backendKind,
      metrics.backendKind,
    );

    expect(metrics.backendKind, 'flutterSceneCustomShader');
    expect(metrics.glass.transmissionSpreadDelta, greaterThan(20));
    expect(metrics.glass.iorDelta, greaterThan(5));
    expect(
        metrics.glass.roughnessBlurDirection, 'reduces_high_frequency_detail');
    expect(metrics.clearcoat.factorHighlightDelta, greaterThan(1));
    expect(metrics.clearcoat.roughPeakBelowSmoothPeak, isTrue);
    expect(metrics.clearcoat.baseMaterialPreserved, isTrue);
  });

  test('ios simulator production material extension visual matrix', () async {
    if (!_runFlutterSceneGpuTests) {
      markTestSkipped(_flutterSceneGpuSkipReason);
      return;
    }
    if (!_runFlutterSceneVisualSmoke) {
      markTestSkipped(_flutterSceneVisualSmokeSkipReason);
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      markTestSkipped(
        'iOS Simulator evidence requires an iOS test target; current target is '
        '${defaultTargetPlatform.name}.',
      );
      return;
    }

    final evidence = await renderProductionMaterialExtensionVisualMatrix(
      writeSharedFixture: true,
    );
    const glassPath = 'tools/out/fsviewer_ios_simulator_glass_matrix.png';
    const clearcoatPath =
        'tools/out/fsviewer_ios_simulator_clearcoat_matrix.png';
    const matrixPath =
        'tools/out/fsviewer_ios_simulator_material_extension_matrix.json';
    File(evidence.flutterSceneGlassImagePath).copySync(glassPath);
    File(evidence.flutterSceneClearcoatImagePath).copySync(clearcoatPath);
    File(matrixPath).writeAsStringSync(
      '${jsonEncode(<String, Object?>{
            'target': 'iOS Simulator',
            'status': 'verified locally',
            'glassMatrix': glassPath,
            'clearcoatMatrix': clearcoatPath,
            'sharedFixtureGlb': evidence.sharedFixtureGlbPath,
          })}\n',
    );

    expect(File(glassPath).existsSync(), isTrue);
    expect(File(clearcoatPath).existsSync(), isTrue);
    expect(File(matrixPath).existsSync(), isTrue);
  });
}

const bool _runFlutterSceneGpuTests = bool.fromEnvironment(
  'FLUTTER_SCENE_GPU_TESTS',
);

const bool _runFlutterSceneVisualSmoke = bool.fromEnvironment(
  'FLUTTER_SCENE_VISUAL_SMOKE',
);

const String _flutterSceneGpuSkipReason =
    'Requires --enable-impeller --enable-flutter-gpu, build-hook generated '
    '.fmat shader bundle assets, and '
    '--dart-define=FLUTTER_SCENE_GPU_TESTS=true.';

const String _flutterSceneVisualSmokeSkipReason =
    'Requires --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true. This opt-in '
    'smoke captures a direct-render screenshot and writes visual evidence '
    'under tools/out/.';

final PartAddress _address = PartAddress(
  nodePath: const <String>['Root', 'Glass'],
  primitiveIndex: 0,
);

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
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

final class _GlassNodeFixture {
  const _GlassNodeFixture({
    required this.node,
    required this.primitive,
    required this.originalMaterial,
    required this.address,
  });

  final flutter_scene.Node node;
  final flutter_scene.MeshPrimitive primitive;
  final flutter_scene.Material originalMaterial;
  final PartAddress address;
}

final class _PaintNodeFixture {
  const _PaintNodeFixture({
    required this.node,
    required this.primitive,
    required this.originalMaterial,
    required this.address,
  });

  final flutter_scene.Node node;
  final flutter_scene.MeshPrimitive primitive;
  final flutter_scene.Material originalMaterial;
  final PartAddress address;
}

final class GlassMatrixEvidence {
  const GlassMatrixEvidence({
    required this.refractionSpreadForTransmission0,
    required this.refractionSpreadForTransmission1,
    required this.iorOffsetDelta,
    required this.imagePath,
  });

  final int refractionSpreadForTransmission0;
  final int refractionSpreadForTransmission1;
  final double iorOffsetDelta;
  final String imagePath;
}

final class ClearcoatMatrixEvidence {
  const ClearcoatMatrixEvidence({
    required this.zeroClearcoatHighlight,
    required this.fullClearcoatHighlight,
    required this.smoothClearcoatPeak,
    required this.roughClearcoatPeak,
    required this.clearcoatTextureFrameDelta,
    required this.normalVariantHighlightPositionDelta,
    required this.imagePath,
  });

  final int zeroClearcoatHighlight;
  final int fullClearcoatHighlight;
  final int smoothClearcoatPeak;
  final int roughClearcoatPeak;
  final double clearcoatTextureFrameDelta;
  final double normalVariantHighlightPositionDelta;
  final String imagePath;
}

final class ProductionMaterialExtensionVisualEvidence {
  const ProductionMaterialExtensionVisualEvidence({
    required this.flutterSceneGlassImagePath,
    required this.flutterSceneClearcoatImagePath,
    this.sharedFixtureGlbPath,
  });

  final String flutterSceneGlassImagePath;
  final String flutterSceneClearcoatImagePath;
  final String? sharedFixtureGlbPath;
}

final class _VisualSmokeSkipped implements Exception {
  const _VisualSmokeSkipped(this.reason);

  final String reason;
}

_GlassNodeFixture _glassNode(String name) {
  final material = flutter_scene.ShaderMaterial();
  final node = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(_StubGeometry(), material),
  );
  return _GlassNodeFixture(
    node: node,
    primitive: node.mesh!.primitives.single,
    originalMaterial: material,
    address: PartAddress(nodePath: <String>['Root', name], primitiveIndex: 0),
  );
}

_PaintNodeFixture _paintNode(String name) {
  final material = flutter_scene.ShaderMaterial();
  final node = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(_StubGeometry(), material),
  );
  return _PaintNodeFixture(
    node: node,
    primitive: node.mesh!.primitives.single,
    originalMaterial: material,
    address: PartAddress(nodePath: <String>['Root', name], primitiveIndex: 0),
  );
}

flutter_scene.RenderTexture _textureSlotSource() =>
    flutter_scene.RenderTexture(width: 1, height: 1);

Future<GlassMatrixEvidence> renderGlassMatrixEvidence({
  required List<double> transmissionValues,
  required List<double> iorValues,
}) async {
  final cameraFrame = const RenderCameraFrame(
    position: <double>[0.0, 0.0, 4.0],
    target: <double>[0.0, 0.0, 0.0],
  );
  final scene = await _createVisualSmokeScene();
  _addStripe(
    scene,
    name: 'red-stripe',
    x: -0.6,
    color: vm.Vector4(1.0, 0.05, 0.05, 1.0),
  );
  _addStripe(
    scene,
    name: 'green-stripe',
    x: 0.0,
    color: vm.Vector4(0.05, 1.0, 0.15, 1.0),
  );
  _addStripe(
    scene,
    name: 'blue-stripe',
    x: 0.6,
    color: vm.Vector4(0.05, 0.2, 1.0, 1.0),
  );

  final backend = FlutterSceneMaterialExtensionBackend(
    renderTextureWidth: 256,
    renderTextureHeight: 256,
  )..updateCamera(cameraFrame);
  final values = transmissionValues.isEmpty
      ? const <double>[0.0, 1.0]
      : transmissionValues;
  for (var index = 0; index < values.length; index += 1) {
    final x =
        values.length == 1 ? 0.0 : -1.05 + index * (2.1 / (values.length - 1));
    await _addGlassPanel(
      scene,
      backend: backend,
      name: 'glass-transmission-$index',
      x: x,
      transmission: values[index],
      ior: 1.45,
      thickness: 0.55,
      roughness: 0.04,
    );
  }

  final camera = flutter_scene.PerspectiveCamera(
    position: vm.Vector3(0, 0, 4),
    target: vm.Vector3.zero(),
  );
  final image = await _renderVisualSmokeImage(scene, camera);
  final png = await image
      .toByteData(format: ui.ImageByteFormat.png)
      .timeout(const Duration(seconds: 10));
  final rgba = await image
      .toByteData(format: ui.ImageByteFormat.rawRgba)
      .timeout(const Duration(seconds: 10));
  if (png == null || rgba == null) {
    throw const _VisualSmokeSkipped('Could not read glass matrix pixels.');
  }
  const imagePath = 'tools/out/fsviewer_glass_matrix.png';
  Directory('tools/out').createSync(recursive: true);
  File(imagePath).writeAsBytesSync(png.buffer.asUint8List());

  final pixels = rgba.buffer.asUint8List();
  final firstBandSpread = _sampleChannelSpreadInBand(
    pixels,
    width: image.width,
    height: image.height,
    band: 0,
    bandCount: values.length,
  );
  final lastBandSpread = _sampleChannelSpreadInBand(
    pixels,
    width: image.width,
    height: image.height,
    band: values.length - 1,
    bandCount: values.length,
  );

  final lowIorImage = await _renderSingleGlassImage(
    transmission: 1.0,
    ior: iorValues.isEmpty ? 1.0 : iorValues.first,
    cameraFrame: cameraFrame,
  );
  final highIorImage = await _renderSingleGlassImage(
    transmission: 1.0,
    ior: iorValues.isEmpty ? 1.85 : iorValues.last,
    cameraFrame: cameraFrame,
  );
  final lowIorPixels =
      await lowIorImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  final highIorPixels =
      await highIorImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (lowIorPixels == null || highIorPixels == null) {
    throw const _VisualSmokeSkipped('Could not read IOR comparison pixels.');
  }

  return GlassMatrixEvidence(
    refractionSpreadForTransmission0: firstBandSpread,
    refractionSpreadForTransmission1: lastBandSpread,
    iorOffsetDelta: _meanAbsolutePixelDeltaInCenter(
      lowIorPixels.buffer.asUint8List(),
      highIorPixels.buffer.asUint8List(),
      width: lowIorImage.width,
      height: lowIorImage.height,
    ),
    imagePath: imagePath,
  );
}

Future<ClearcoatMatrixEvidence> renderClearcoatMatrixEvidence({
  required List<double> clearcoatValues,
  required List<double> roughnessValues,
  required bool includeNormalVariant,
}) async {
  final scene = await _createVisualSmokeScene();
  scene
    ..environmentIntensity = 2.2
    ..skybox = flutter_scene.Skybox(
      flutter_scene.EnvironmentSkySource(blurriness: 0.0),
    );
  final values =
      clearcoatValues.isEmpty ? const <double>[0.0, 1.0] : clearcoatValues;
  for (var index = 0; index < values.length; index += 1) {
    final x =
        values.length == 1 ? 0.0 : 0.85 - index * (1.7 / (values.length - 1));
    final diagnostics = await _addClearcoatSphere(
      scene,
      name: 'clearcoat-factor-$index',
      x: x,
      y: 0.55,
      radius: 0.32,
      clearcoat: values[index],
      clearcoatRoughness: 0.02,
    );
    if (diagnostics.isNotEmpty) {
      throw _VisualSmokeSkipped(diagnostics.single.message);
    }
  }

  final roughnesses =
      roughnessValues.isEmpty ? const <double>[0.02, 0.8] : roughnessValues;
  for (var index = 0; index < roughnesses.length; index += 1) {
    final x = roughnesses.length == 1
        ? 0.0
        : 0.85 - index * (1.7 / (roughnesses.length - 1));
    final diagnostics = await _addClearcoatSphere(
      scene,
      name: 'clearcoat-roughness-$index',
      x: x,
      y: -0.55,
      radius: 0.32,
      clearcoat: 1.0,
      clearcoatRoughness: roughnesses[index],
    );
    if (diagnostics.isNotEmpty) {
      throw _VisualSmokeSkipped(diagnostics.single.message);
    }
  }

  final image = await _renderVisualSmokeImage(
    scene,
    flutter_scene.PerspectiveCamera(
      position: vm.Vector3(0, 0, 4.5),
      target: vm.Vector3.zero(),
    ),
  );
  final png = await image
      .toByteData(format: ui.ImageByteFormat.png)
      .timeout(const Duration(seconds: 10));
  final rgba = await image
      .toByteData(format: ui.ImageByteFormat.rawRgba)
      .timeout(const Duration(seconds: 10));
  if (png == null || rgba == null) {
    throw const _VisualSmokeSkipped('Could not read clearcoat matrix pixels.');
  }

  const imagePath = 'tools/out/fsviewer_clearcoat_matrix.png';
  Directory('tools/out').createSync(recursive: true);
  File(imagePath).writeAsBytesSync(png.buffer.asUint8List());

  final pixels = rgba.buffer.asUint8List();
  final zeroClearcoatHighlight = _maxObjectLuminanceInCell(
    pixels,
    width: image.width,
    height: image.height,
    row: 0,
    rowCount: 2,
    column: 0,
    columnCount: values.length,
  );
  final fullClearcoatHighlight = _maxObjectLuminanceInCell(
    pixels,
    width: image.width,
    height: image.height,
    row: 0,
    rowCount: 2,
    column: values.length - 1,
    columnCount: values.length,
  );
  final smoothClearcoatPeak = _maxObjectLuminanceInCell(
    pixels,
    width: image.width,
    height: image.height,
    row: 1,
    rowCount: 2,
    column: 0,
    columnCount: roughnesses.length,
  );
  final roughClearcoatPeak = _maxObjectLuminanceInCell(
    pixels,
    width: image.width,
    height: image.height,
    row: 1,
    rowCount: 2,
    column: roughnesses.length - 1,
    columnCount: roughnesses.length,
  );

  return ClearcoatMatrixEvidence(
    zeroClearcoatHighlight: zeroClearcoatHighlight,
    fullClearcoatHighlight: fullClearcoatHighlight,
    smoothClearcoatPeak: smoothClearcoatPeak,
    roughClearcoatPeak: roughClearcoatPeak,
    clearcoatTextureFrameDelta: await _clearcoatTextureFrameDelta(),
    normalVariantHighlightPositionDelta: includeNormalVariant
        ? await _clearcoatNormalHighlightPositionDelta()
        : 0.0,
    imagePath: imagePath,
  );
}

Future<ProductionMaterialExtensionVisualEvidence>
    renderProductionMaterialExtensionVisualMatrix({
  required bool writeSharedFixture,
}) async {
  final glass = await renderGlassMatrixEvidence(
    transmissionValues: const <double>[0.0, 0.5, 1.0],
    iorValues: const <double>[1.0, 1.45, 1.85],
  );
  final clearcoat = await renderClearcoatMatrixEvidence(
    clearcoatValues: const <double>[0.0, 0.5, 1.0],
    roughnessValues: const <double>[0.02, 0.35, 0.8],
    includeNormalVariant: true,
  );
  return ProductionMaterialExtensionVisualEvidence(
    flutterSceneGlassImagePath: glass.imagePath,
    flutterSceneClearcoatImagePath: clearcoat.imagePath,
    sharedFixtureGlbPath:
        writeSharedFixture ? _writeSharedMaterialExtensionFixtureGlb() : null,
  );
}

String _writeSharedMaterialExtensionFixtureGlb() {
  const path = 'tools/out/fsviewer_material_extension_reference_fixture.glb';
  Directory('tools/out').createSync(recursive: true);
  final bin = BytesBuilder(copy: false);
  final positionView = _appendFloats(bin, const <double>[
    -0.5,
    -0.5,
    0.0,
    0.5,
    -0.5,
    0.0,
    0.5,
    0.5,
    0.0,
    -0.5,
    0.5,
    0.0,
  ]);
  final normalView = _appendFloats(bin, const <double>[
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    1.0,
  ]);
  final uvView = _appendFloats(bin, const <double>[
    0.0,
    0.0,
    1.0,
    0.0,
    1.0,
    1.0,
    0.0,
    1.0,
  ]);
  final indexView = _appendUint16(bin, const <int>[0, 1, 2, 0, 2, 3]);
  final binary = bin.toBytes();
  final materials = <Map<String, Object?>>[
    _pbrMaterial('stripe-red', <double>[1.0, 0.05, 0.05, 1.0]),
    _pbrMaterial('stripe-green', <double>[0.05, 1.0, 0.15, 1.0]),
    _pbrMaterial('stripe-blue', <double>[0.05, 0.2, 1.0, 1.0]),
    _glassReferenceMaterial('glass-transmission-0', 0.0, 1.45, 0.2),
    _glassReferenceMaterial('glass-transmission-05', 0.5, 1.45, 0.35),
    _glassReferenceMaterial('glass-transmission-1', 1.0, 1.45, 0.55),
    _glassReferenceMaterial('glass-ior-low', 1.0, 1.0, 0.55),
    _glassReferenceMaterial('glass-ior-high', 1.0, 1.85, 0.75),
    _clearcoatReferenceMaterial('clearcoat-0', 0.0, 0.02),
    _clearcoatReferenceMaterial('clearcoat-05', 0.5, 0.02),
    _clearcoatReferenceMaterial('clearcoat-1', 1.0, 0.02),
    _clearcoatReferenceMaterial('clearcoat-rough', 1.0, 0.8),
  ];
  final nodes = <Map<String, Object?>>[
    _fixtureNode(
        'stripe-red', 0, <double>[-0.7, 0.62, -0.2], <double>[0.6, 0.42, 1.0]),
    _fixtureNode(
        'stripe-green', 1, <double>[0.0, 0.62, -0.2], <double>[0.6, 0.42, 1.0]),
    _fixtureNode(
        'stripe-blue', 2, <double>[0.7, 0.62, -0.2], <double>[0.6, 0.42, 1.0]),
    _fixtureNode('glass-transmission-0', 3, <double>[-0.85, 0.62, 0.0],
        <double>[0.5, 0.6, 1.0]),
    _fixtureNode('glass-transmission-05', 4, <double>[0.0, 0.62, 0.0],
        <double>[0.5, 0.6, 1.0]),
    _fixtureNode('glass-transmission-1', 5, <double>[0.85, 0.62, 0.0],
        <double>[0.5, 0.6, 1.0]),
    _fixtureNode('glass-ior-low', 6, <double>[-0.42, 0.0, 0.0],
        <double>[0.44, 0.44, 1.0]),
    _fixtureNode('glass-ior-high', 7, <double>[0.42, 0.0, 0.0],
        <double>[0.44, 0.44, 1.0]),
    _fixtureNode('clearcoat-0', 8, <double>[-1.2, -0.62, 0.0],
        <double>[0.48, 0.48, 1.0]),
    _fixtureNode('clearcoat-05', 9, <double>[-0.4, -0.62, 0.0],
        <double>[0.48, 0.48, 1.0]),
    _fixtureNode('clearcoat-1', 10, <double>[0.4, -0.62, 0.0],
        <double>[0.48, 0.48, 1.0]),
    _fixtureNode('clearcoat-rough', 11, <double>[1.2, -0.62, 0.0],
        <double>[0.48, 0.48, 1.0]),
  ];
  final json = <String, Object?>{
    'asset': <String, Object?>{
      'version': '2.0',
      'generator': 'flutter_scene_viewer material extension visual fixture',
    },
    'extensionsUsed': <String>[
      'KHR_materials_transmission',
      'KHR_materials_ior',
      'KHR_materials_volume',
      'KHR_materials_clearcoat',
    ],
    'scene': 0,
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <int>[for (var i = 0; i < nodes.length; i += 1) i],
      },
    ],
    'nodes': nodes,
    'meshes': <Object?>[
      for (var material = 0; material < materials.length; material += 1)
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{
                'POSITION': 0,
                'NORMAL': 1,
                'TEXCOORD_0': 2,
              },
              'indices': 3,
              'material': material,
            },
          ],
        },
    ],
    'materials': materials,
    'buffers': <Object?>[
      <String, Object?>{'byteLength': binary.length},
    ],
    'bufferViews': <Object?>[
      _bufferView(positionView, target: 34962),
      _bufferView(normalView, target: 34962),
      _bufferView(uvView, target: 34962),
      _bufferView(indexView, target: 34963),
    ],
    'accessors': <Object?>[
      <String, Object?>{
        'bufferView': 0,
        'componentType': 5126,
        'count': 4,
        'type': 'VEC3',
        'min': <double>[-0.5, -0.5, 0.0],
        'max': <double>[0.5, 0.5, 0.0],
      },
      <String, Object?>{
        'bufferView': 1,
        'componentType': 5126,
        'count': 4,
        'type': 'VEC3',
      },
      <String, Object?>{
        'bufferView': 2,
        'componentType': 5126,
        'count': 4,
        'type': 'VEC2',
      },
      <String, Object?>{
        'bufferView': 3,
        'componentType': 5123,
        'count': 6,
        'type': 'SCALAR',
      },
    ],
  };
  File(path).writeAsBytesSync(_glbBytes(json, binary));
  return path;
}

Future<double> _clearcoatNormalHighlightPositionDelta() async {
  final flatImage = await _renderSingleClearcoatImage(
    clearcoatNormalTexture: null,
  );
  final tiltedImage = await _renderSingleClearcoatImage(
    clearcoatNormalTexture: _tiltedClearcoatNormalTexture(),
  );
  final flatPixels =
      await flatImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  final tiltedPixels =
      await tiltedImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (flatPixels == null || tiltedPixels == null) {
    throw const _VisualSmokeSkipped(
      'Could not read clearcoat normal comparison pixels.',
    );
  }
  final flatX = _highlightCentroidX(
    flatPixels.buffer.asUint8List(),
    width: flatImage.width,
    height: flatImage.height,
  );
  final tiltedX = _highlightCentroidX(
    tiltedPixels.buffer.asUint8List(),
    width: tiltedImage.width,
    height: tiltedImage.height,
  );
  return (tiltedX - flatX).abs();
}

Future<double> _clearcoatTextureFrameDelta() async {
  final blackImage = await _renderSingleClearcoatImage(
    clearcoatTexture: _solidClearcoatTexture(red: 0),
    clearcoatNormalTexture: null,
  );
  final whiteImage = await _renderSingleClearcoatImage(
    clearcoatTexture: _solidClearcoatTexture(red: 255),
    clearcoatNormalTexture: null,
  );
  final blackPixels =
      await blackImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  final whitePixels =
      await whiteImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (blackPixels == null || whitePixels == null) {
    throw const _VisualSmokeSkipped(
      'Could not read clearcoat texture comparison pixels.',
    );
  }
  return _meanAbsolutePixelDeltaInCenter(
    blackPixels.buffer.asUint8List(),
    whitePixels.buffer.asUint8List(),
    width: blackImage.width,
    height: blackImage.height,
  );
}

Future<ui.Image> _renderSingleClearcoatImage({
  Object? clearcoatTexture,
  required Object? clearcoatNormalTexture,
}) async {
  final scene = await _createVisualSmokeScene();
  scene
    ..environmentIntensity = 2.2
    ..skybox = flutter_scene.Skybox(
      flutter_scene.EnvironmentSkySource(blurriness: 0.0),
    );
  final diagnostics = await _addClearcoatSphere(
    scene,
    name: 'clearcoat-normal',
    x: 0.0,
    clearcoat: 1.0,
    clearcoatRoughness: 0.02,
    clearcoatNormalScale: clearcoatNormalTexture == null ? 1.0 : 2.5,
    clearcoatTexture: clearcoatTexture,
    clearcoatNormalTexture: clearcoatNormalTexture,
  );
  if (diagnostics.isNotEmpty) {
    throw _VisualSmokeSkipped(diagnostics.single.message);
  }
  return _renderVisualSmokeImage(
    scene,
    flutter_scene.PerspectiveCamera(
      position: vm.Vector3(0, 0, 4.2),
      target: vm.Vector3.zero(),
    ),
  );
}

flutter_scene.TextureSource _tiltedClearcoatNormalTexture() {
  final texture = flutter_scene_internal_gpu.gpuContext.createTexture(
    flutter_scene_internal_gpu.StorageMode.hostVisible,
    2,
    1,
  );
  texture.overwrite(
    Uint32List.fromList(<int>[0xFFFF7F20, 0xFFFF7FFF]).buffer.asByteData(),
  );
  return flutter_scene.GpuTextureSource(texture);
}

flutter_scene.TextureSource _solidClearcoatTexture({required int red}) {
  return _solidColorTexture(0xFF000000 | red.clamp(0, 255));
}

flutter_scene.TextureSource _solidColorTexture(int argb) {
  final texture = flutter_scene_internal_gpu.gpuContext.createTexture(
    flutter_scene_internal_gpu.StorageMode.hostVisible,
    1,
    1,
  );
  texture.overwrite(
    Uint32List.fromList(<int>[argb]).buffer.asByteData(),
  );
  return flutter_scene.GpuTextureSource(texture);
}

_BufferSlice _appendFloats(BytesBuilder builder, List<double> values) {
  _padBuilder4(builder);
  final offset = builder.length;
  final bytes = ByteData(values.length * 4);
  for (var index = 0; index < values.length; index += 1) {
    bytes.setFloat32(index * 4, values[index], Endian.little);
  }
  builder.add(bytes.buffer.asUint8List());
  return _BufferSlice(offset: offset, length: bytes.lengthInBytes);
}

_BufferSlice _appendUint16(BytesBuilder builder, List<int> values) {
  _padBuilder4(builder);
  final offset = builder.length;
  final bytes = ByteData(values.length * 2);
  for (var index = 0; index < values.length; index += 1) {
    bytes.setUint16(index * 2, values[index], Endian.little);
  }
  builder.add(bytes.buffer.asUint8List());
  _padBuilder4(builder);
  return _BufferSlice(offset: offset, length: bytes.lengthInBytes);
}

void _padBuilder4(BytesBuilder builder) {
  while (builder.length % 4 != 0) {
    builder.addByte(0);
  }
}

Map<String, Object?> _bufferView(
  _BufferSlice slice, {
  required int target,
}) {
  return <String, Object?>{
    'buffer': 0,
    'byteOffset': slice.offset,
    'byteLength': slice.length,
    'target': target,
  };
}

Map<String, Object?> _fixtureNode(
  String name,
  int mesh,
  List<double> translation,
  List<double> scale,
) {
  return <String, Object?>{
    'name': name,
    'mesh': mesh,
    'translation': translation,
    'scale': scale,
  };
}

Map<String, Object?> _pbrMaterial(String name, List<double> baseColor) {
  return <String, Object?>{
    'name': name,
    'pbrMetallicRoughness': <String, Object?>{
      'baseColorFactor': baseColor,
      'metallicFactor': 0.0,
      'roughnessFactor': 0.72,
    },
  };
}

Map<String, Object?> _glassReferenceMaterial(
  String name,
  double transmission,
  double ior,
  double thickness,
) {
  return <String, Object?>{
    'name': name,
    'alphaMode': 'BLEND',
    'pbrMetallicRoughness': <String, Object?>{
      'baseColorFactor': <double>[0.75, 0.9, 1.0, 1.0],
      'metallicFactor': 0.0,
      'roughnessFactor': 0.04,
    },
    'extensions': <String, Object?>{
      'KHR_materials_transmission': <String, Object?>{
        'transmissionFactor': transmission,
      },
      'KHR_materials_ior': <String, Object?>{
        'ior': ior,
      },
      'KHR_materials_volume': <String, Object?>{
        'thicknessFactor': thickness,
        'attenuationColor': <double>[0.85, 0.95, 1.0],
        'attenuationDistance': 2.0,
      },
    },
  };
}

Map<String, Object?> _clearcoatReferenceMaterial(
  String name,
  double clearcoat,
  double clearcoatRoughness,
) {
  return <String, Object?>{
    'name': name,
    'pbrMetallicRoughness': <String, Object?>{
      'baseColorFactor': <double>[0.08, 0.1, 0.13, 1.0],
      'metallicFactor': 0.0,
      'roughnessFactor': 0.72,
    },
    'extensions': <String, Object?>{
      'KHR_materials_clearcoat': <String, Object?>{
        'clearcoatFactor': clearcoat,
        'clearcoatRoughnessFactor': clearcoatRoughness,
      },
    },
  };
}

Uint8List _glbBytes(Map<String, Object?> json, Uint8List binary) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final paddedBinLength = _align4(binary.length);
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
  final binHeader = 20 + paddedJsonLength;
  data
    ..setUint32(binHeader, paddedBinLength, Endian.little)
    ..setUint32(binHeader + 4, 0x004E4942, Endian.little);
  bytes.setRange(binHeader + 8, binHeader + 8 + binary.length, binary);
  return bytes;
}

int _align4(int value) => (value + 3) & ~3;

final class _BufferSlice {
  const _BufferSlice({required this.offset, required this.length});

  final int offset;
  final int length;
}

Future<flutter_scene.Scene> _createVisualSmokeScene() async {
  try {
    await flutter_scene.Scene.initializeStaticResources()
        .timeout(const Duration(seconds: 10));
    return flutter_scene.Scene();
  } on TimeoutException catch (_) {
    throw const _VisualSmokeSkipped(
      'Timed out initializing Flutter GPU scene resources.',
    );
  } on Object catch (error) {
    throw _VisualSmokeSkipped(
        'No compatible Flutter GPU scene context: $error');
  }
}

Future<void> _addGlassPanel(
  flutter_scene.Scene scene, {
  required FlutterSceneMaterialExtensionBackend backend,
  required String name,
  required double x,
  required double transmission,
  required double ior,
  required double thickness,
  required double roughness,
}) async {
  final glassMaterial = flutter_scene.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.75, 0.9, 1.0, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.02;
  final glassNode = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(
      flutter_scene.CuboidGeometry(vm.Vector3(0.56, 1.7, 0.04)),
      glassMaterial,
    ),
  )..localTransform = (vm.Matrix4.identity()
    ..translateByDouble(x, 0.0, 0.85, 1.0)
    ..rotateY(0.42));
  scene.add(glassNode);
  final diagnostics = await backend.applyTransmissionPatch(
    sceneViews: scene.views,
    node: glassNode,
    primitive: glassNode.mesh!.primitives.single,
    address: PartAddress(nodePath: <String>['Root', name], primitiveIndex: 0),
    patch: MaterialPatch(
      baseColorFactor: const <double>[0.75, 0.9, 1.0, 1.0],
      transmission: transmission,
      ior: ior,
      thickness: thickness,
      attenuationColor: const <double>[0.85, 0.95, 1.0],
      attenuationDistance: 2.0,
      roughness: roughness,
    ),
  );
  if (diagnostics.isNotEmpty) {
    throw _VisualSmokeSkipped(diagnostics.single.message);
  }
}

Future<ui.Image> _renderSingleGlassImage({
  required double transmission,
  required double ior,
  required RenderCameraFrame cameraFrame,
}) async {
  final scene = await _createVisualSmokeScene();
  _addStripe(
    scene,
    name: 'red-stripe',
    x: -0.6,
    color: vm.Vector4(1.0, 0.05, 0.05, 1.0),
  );
  _addStripe(
    scene,
    name: 'green-stripe',
    x: 0.0,
    color: vm.Vector4(0.05, 1.0, 0.15, 1.0),
  );
  _addStripe(
    scene,
    name: 'blue-stripe',
    x: 0.6,
    color: vm.Vector4(0.05, 0.2, 1.0, 1.0),
  );
  final backend = FlutterSceneMaterialExtensionBackend(
    renderTextureWidth: 256,
    renderTextureHeight: 256,
  )..updateCamera(cameraFrame);
  await _addGlassPanel(
    scene,
    backend: backend,
    name: 'glass-ior',
    x: 0.0,
    transmission: transmission,
    ior: ior,
    thickness: 0.55,
    roughness: 0.04,
  );
  return _renderVisualSmokeImage(
    scene,
    flutter_scene.PerspectiveCamera(
      position: vm.Vector3(0, 0, 4),
      target: vm.Vector3.zero(),
    ),
  );
}

final class _FakeShaderLibrary implements MaterialExtensionShaderLibrary {
  const _FakeShaderLibrary({required this.entries});

  final Set<String> entries;

  @override
  Object? operator [](String shaderName) =>
      entries.contains(shaderName) ? Object() : null;
}

Future<ui.Image> _renderVisualSmokeImage(
  flutter_scene.Scene scene,
  flutter_scene.Camera camera,
) async {
  ui.Image? latest;
  for (var frame = 0; frame < 6; frame += 1) {
    latest?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    scene.render(
      camera,
      canvas,
      viewport: const ui.Rect.fromLTWH(0, 0, 240, 240),
      pixelRatio: 1.0,
    );
    final picture = recorder.endRecording();
    latest = await picture.toImage(240, 240).timeout(
          const Duration(seconds: 10),
        );
    picture.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return latest!;
}

void _addStripe(
  flutter_scene.Scene scene, {
  required String name,
  required double x,
  required vm.Vector4 color,
}) {
  final material = flutter_scene.UnlitMaterial()..baseColorFactor = color;
  final node = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(
      flutter_scene.CuboidGeometry(vm.Vector3(0.58, 1.9, 0.08)),
      material,
    ),
  )..localTransform = vm.Matrix4.translationValues(x, 0.0, -0.15);
  scene.add(node);
}

void _addGlossySphere(
  flutter_scene.Scene scene, {
  required String name,
  required double x,
}) {
  final material = flutter_scene.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.08, 0.1, 0.13, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.18;
  final node = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(
      flutter_scene.SphereGeometry(radius: 0.48, segments: 48, rings: 24),
      material,
    ),
  )..localTransform = vm.Matrix4.translationValues(x, 0.0, 0.0);
  scene.add(node);
}

Future<List<ViewerDiagnostic>> _addClearcoatSphere(
  flutter_scene.Scene scene, {
  required String name,
  required double x,
  double y = 0.0,
  double radius = 0.48,
  required double clearcoat,
  required double clearcoatRoughness,
  double baseRoughness = 0.72,
  double clearcoatNormalScale = 1.0,
  Object? clearcoatTexture,
  Object? clearcoatNormalTexture,
}) async {
  final baseMaterial = flutter_scene.PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.08, 0.1, 0.13, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = baseRoughness;
  final node = flutter_scene.Node(
    name: name,
    mesh: flutter_scene.Mesh(
      flutter_scene.SphereGeometry(radius: radius, segments: 48, rings: 24),
      baseMaterial,
    ),
  )..localTransform = vm.Matrix4.translationValues(x, y, 0.0);
  scene.add(node);
  final backend = FlutterSceneMaterialExtensionBackend();
  return backend.applyClearcoatPatch(
    node: node,
    primitive: node.mesh!.primitives.single,
    address: _address,
    patch: MaterialPatch(
      clearcoat: clearcoat,
      clearcoatRoughness: clearcoatRoughness,
      clearcoatNormalScale: clearcoatNormalScale,
    ),
    clearcoatTexture: clearcoatTexture,
    clearcoatNormalTexture: clearcoatNormalTexture,
  );
}

int _sampleDistinctColors(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return 0;
  }
  final colors = <int>{};
  for (final y in _sampleCoordinates(height)) {
    for (final x in _sampleCoordinates(width)) {
      final offset = (y * width + x) * 4;
      final r = pixels[offset] ~/ 24;
      final g = pixels[offset + 1] ~/ 24;
      final b = pixels[offset + 2] ~/ 24;
      colors.add((r << 16) | (g << 8) | b);
    }
  }
  return colors.length;
}

int _sampleChannelSpread(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return 0;
  }
  var minValue = 255;
  var maxValue = 0;
  for (final y in _sampleCoordinates(height)) {
    for (final x in _sampleCoordinates(width)) {
      final offset = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel += 1) {
        final value = pixels[offset + channel];
        if (value < minValue) {
          minValue = value;
        }
        if (value > maxValue) {
          maxValue = value;
        }
      }
    }
  }
  return maxValue - minValue;
}

int _sampleChannelSpreadInBand(
  Uint8List pixels, {
  required int width,
  required int height,
  required int band,
  required int bandCount,
}) {
  if (width <= 0 || height <= 0 || bandCount <= 0) {
    return 0;
  }
  final bandStartX = (width * band) ~/ bandCount;
  final bandEndX = (width * (band + 1)) ~/ bandCount;
  final bandWidth = bandEndX - bandStartX;
  final startX = bandStartX + (bandWidth * 32) ~/ 100;
  final endX = bandEndX - (bandWidth * 32) ~/ 100;
  final startY = (height * 28) ~/ 100;
  final endY = (height * 72) ~/ 100;
  var minValue = 255;
  var maxValue = 0;
  for (var y = startY; y < endY; y += 1) {
    for (var x = startX; x < endX; x += 1) {
      final offset = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel += 1) {
        final value = pixels[offset + channel];
        if (value < minValue) {
          minValue = value;
        }
        if (value > maxValue) {
          maxValue = value;
        }
      }
    }
  }
  return maxValue - minValue;
}

double _meanAbsolutePixelDeltaInCenter(
  Uint8List first,
  Uint8List second, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0 || first.length != second.length) {
    return 0;
  }
  final startX = width ~/ 4;
  final endX = (width * 3) ~/ 4;
  final startY = height ~/ 4;
  final endY = (height * 3) ~/ 4;
  var total = 0;
  var count = 0;
  for (var y = startY; y < endY; y += 1) {
    for (var x = startX; x < endX; x += 1) {
      final offset = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel += 1) {
        total += (first[offset + channel] - second[offset + channel]).abs();
        count += 1;
      }
    }
  }
  return count == 0 ? 0 : total / count;
}

Set<String> _sampleDominantChannels(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return const <String>{};
  }
  final channels = <String>{};
  for (final y in _sampleCoordinates(height)) {
    for (final x in _sampleCoordinates(width)) {
      final offset = (y * width + x) * 4;
      final r = pixels[offset];
      final g = pixels[offset + 1];
      final b = pixels[offset + 2];
      final maxChannel = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final minChannel = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (maxChannel < 80 || maxChannel - minChannel < 35) {
        continue;
      }
      if (r == maxChannel) {
        channels.add('red');
      } else if (g == maxChannel) {
        channels.add('green');
      } else {
        channels.add('blue');
      }
    }
  }
  return channels;
}

int _maxObjectLuminanceInBand(
  Uint8List pixels, {
  required int width,
  required int height,
  required int band,
  required int bandCount,
}) {
  if (width <= 0 || height <= 0 || bandCount <= 0) {
    return 0;
  }
  final bandStartX = (width * band) ~/ bandCount;
  final bandEndX = (width * (band + 1)) ~/ bandCount;
  final centerX = (bandStartX + bandEndX) ~/ 2;
  final centerY = height ~/ 2;
  final radius = ((bandEndX - bandStartX) * 42) ~/ 100;
  final radiusSquared = radius * radius;
  var maxLuma = 0;
  for (var y = centerY - radius; y <= centerY + radius; y += 1) {
    for (var x = centerX - radius; x <= centerX + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      final dx = x - centerX;
      final dy = y - centerY;
      if (dx * dx + dy * dy > radiusSquared) {
        continue;
      }
      final offset = (y * width + x) * 4;
      final luma = (pixels[offset] * 299 +
              pixels[offset + 1] * 587 +
              pixels[offset + 2] * 114) ~/
          1000;
      if (luma > maxLuma) {
        maxLuma = luma;
      }
    }
  }
  return maxLuma;
}

double _brightObjectPixelFractionInBand(
  Uint8List pixels, {
  required int width,
  required int height,
  required int band,
  required int bandCount,
  required int threshold,
}) {
  if (width <= 0 || height <= 0 || bandCount <= 0) {
    return 0;
  }
  final bandStartX = (width * band) ~/ bandCount;
  final bandEndX = (width * (band + 1)) ~/ bandCount;
  final centerX = (bandStartX + bandEndX) ~/ 2;
  final centerY = height ~/ 2;
  final radius = ((bandEndX - bandStartX) * 42) ~/ 100;
  final radiusSquared = radius * radius;
  var bright = 0;
  var total = 0;
  for (var y = centerY - radius; y <= centerY + radius; y += 1) {
    for (var x = centerX - radius; x <= centerX + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      final dx = x - centerX;
      final dy = y - centerY;
      if (dx * dx + dy * dy > radiusSquared) {
        continue;
      }
      final offset = (y * width + x) * 4;
      final luma = (pixels[offset] * 299 +
              pixels[offset + 1] * 587 +
              pixels[offset + 2] * 114) ~/
          1000;
      if (luma > threshold) {
        bright += 1;
      }
      total += 1;
    }
  }
  return total == 0 ? 0 : bright / total;
}

int _maxObjectLuminanceInCell(
  Uint8List pixels, {
  required int width,
  required int height,
  required int row,
  required int rowCount,
  required int column,
  required int columnCount,
}) {
  if (width <= 0 ||
      height <= 0 ||
      rowCount <= 0 ||
      columnCount <= 0 ||
      row < 0 ||
      column < 0 ||
      row >= rowCount ||
      column >= columnCount) {
    return 0;
  }
  final cellStartX = (width * column) ~/ columnCount;
  final cellEndX = (width * (column + 1)) ~/ columnCount;
  final cellStartY = (height * row) ~/ rowCount;
  final cellEndY = (height * (row + 1)) ~/ rowCount;
  final centerX = (cellStartX + cellEndX) ~/ 2;
  final centerY = rowCount == 2
      ? (height * (row == 0 ? 35 : 65)) ~/ 100
      : (cellStartY + cellEndY) ~/ 2;
  final radius = (((cellEndX - cellStartX) < (cellEndY - cellStartY)
              ? cellEndX - cellStartX
              : cellEndY - cellStartY) *
          32) ~/
      100;
  final radiusSquared = radius * radius;
  var maxLuma = 0;
  for (var y = centerY - radius; y <= centerY + radius; y += 1) {
    for (var x = centerX - radius; x <= centerX + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      final dx = x - centerX;
      final dy = y - centerY;
      if (dx * dx + dy * dy > radiusSquared) {
        continue;
      }
      final offset = (y * width + x) * 4;
      final luma = (pixels[offset] * 299 +
              pixels[offset + 1] * 587 +
              pixels[offset + 2] * 114) ~/
          1000;
      if (luma > maxLuma) {
        maxLuma = luma;
      }
    }
  }
  return maxLuma;
}

double _highlightCentroidX(
  Uint8List pixels, {
  required int width,
  required int height,
}) {
  if (width <= 0 || height <= 0) {
    return 0;
  }
  final centerX = width ~/ 2;
  final centerY = height ~/ 2;
  final radius = (width < height ? width : height) ~/ 5;
  final radiusSquared = radius * radius;
  var maxLuma = 0;
  for (var y = centerY - radius; y <= centerY + radius; y += 1) {
    for (var x = centerX - radius; x <= centerX + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      final dx = x - centerX;
      final dy = y - centerY;
      if (dx * dx + dy * dy > radiusSquared) {
        continue;
      }
      final offset = (y * width + x) * 4;
      final luma = (pixels[offset] * 299 +
              pixels[offset + 1] * 587 +
              pixels[offset + 2] * 114) ~/
          1000;
      if (luma > maxLuma) {
        maxLuma = luma;
      }
    }
  }
  if (maxLuma == 0) {
    return width / 2;
  }
  final threshold = (maxLuma - 8).clamp(0, 255);
  var totalX = 0;
  var count = 0;
  for (var y = centerY - radius; y <= centerY + radius; y += 1) {
    for (var x = centerX - radius; x <= centerX + radius; x += 1) {
      if (x < 0 || y < 0 || x >= width || y >= height) {
        continue;
      }
      final dx = x - centerX;
      final dy = y - centerY;
      if (dx * dx + dy * dy > radiusSquared) {
        continue;
      }
      final offset = (y * width + x) * 4;
      final luma = (pixels[offset] * 299 +
              pixels[offset + 1] * 587 +
              pixels[offset + 2] * 114) ~/
          1000;
      if (luma >= threshold) {
        totalX += x;
        count += 1;
      }
    }
  }
  return count == 0 ? width / 2 : totalX / count;
}

List<int> _sampleCoordinates(int extent) {
  if (extent <= 1) {
    return const <int>[0];
  }
  return <int>[
    for (var index = 1; index <= 5; index += 1) ((extent - 1) * index) ~/ 6,
  ];
}
