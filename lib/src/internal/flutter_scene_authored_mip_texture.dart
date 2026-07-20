import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart' as flutter_scene;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as flutter_scene_gpu;

import '../diagnostics.dart';
import 'glb_basisu_rewriter.dart';

/// glTF semantic role retained alongside an authored RGBA8 mip chain.
///
/// The role is metadata for binding the existing material slots. It does not
/// select or modify a renderer shader.
enum FlutterSceneAuthoredMipContentRole { color, data, normal }

/// Native decoded-pixel storage class used to deduplicate a raw GPU upload.
///
/// Material-slot semantics remain on [FlutterSceneAuthoredMipMaterialTarget].
/// In particular, normal and scalar/data slots share `nonColor` storage without
/// becoming interchangeable material inputs.
enum FlutterSceneAuthoredMipStorageRole { color, nonColor }

enum FlutterSceneAuthoredMipMaterialSlot {
  baseColor,
  metallicRoughness,
  normal,
  occlusion,
  emissive,
  transmission,
  thickness,
  clearcoat,
  clearcoatRoughness,
  clearcoatNormal,
  specular,
  specularColor,
}

/// One owned, immutable RGBA8888 mip level.
final class FlutterSceneAuthoredMipLevel {
  FlutterSceneAuthoredMipLevel({
    required this.level,
    required this.width,
    required this.height,
    required Uint8List rgbaBytes,
  }) : _rgbaBytes = Uint8List.fromList(rgbaBytes);

  final int level;
  final int width;
  final int height;
  final Uint8List _rgbaBytes;

  /// Returns an isolated copy so callers cannot mutate the upload payload.
  Uint8List get rgbaBytes => Uint8List.fromList(_rgbaBytes);

  ByteData get _byteData => ByteData.sublistView(_rgbaBytes);

  int get _byteLength => _rgbaBytes.lengthInBytes;
}

/// Immutable glTF sampler values associated with one texture index.
final class FlutterSceneAuthoredMipSamplerIntent {
  const FlutterSceneAuthoredMipSamplerIntent({
    required this.magFilter,
    required this.minFilter,
    required this.wrapS,
    required this.wrapT,
  });

  final int magFilter;
  final int minFilter;
  final int wrapS;
  final int wrapT;
}

final class FlutterSceneAuthoredMipMaterialTarget {
  FlutterSceneAuthoredMipMaterialTarget({
    required List<int> nodeChildPath,
    required this.primitiveIndex,
    required this.slot,
    required this.required,
  }) : nodeChildPath = List<int>.unmodifiable(nodeChildPath);

  final List<int> nodeChildPath;
  final int primitiveIndex;
  final FlutterSceneAuthoredMipMaterialSlot slot;
  final bool required;
}

final class FlutterSceneAuthoredMipTextureBinding {
  FlutterSceneAuthoredMipTextureBinding({
    required this.textureIndex,
    required this.sampler,
    required List<FlutterSceneAuthoredMipMaterialTarget> targets,
  }) : targets =
            List<FlutterSceneAuthoredMipMaterialTarget>.unmodifiable(targets);

  final int textureIndex;
  final FlutterSceneAuthoredMipSamplerIntent sampler;
  final List<FlutterSceneAuthoredMipMaterialTarget> targets;
}

final class FlutterSceneAuthoredMipImageUpload {
  FlutterSceneAuthoredMipImageUpload({
    required this.imageIndex,
    required this.contentRole,
    FlutterSceneAuthoredMipStorageRole? storageRole,
    required List<FlutterSceneAuthoredMipLevel> levels,
    required List<FlutterSceneAuthoredMipTextureBinding> textureBindings,
  })  : storageRole = storageRole ?? _storageRoleForContentRole(contentRole),
        levels = List<FlutterSceneAuthoredMipLevel>.unmodifiable(levels),
        textureBindings =
            List<FlutterSceneAuthoredMipTextureBinding>.unmodifiable(
          textureBindings,
        );

  final int imageIndex;
  final FlutterSceneAuthoredMipContentRole contentRole;
  final FlutterSceneAuthoredMipStorageRole storageRole;
  final List<FlutterSceneAuthoredMipLevel> levels;
  final List<FlutterSceneAuthoredMipTextureBinding> textureBindings;
}

final class FlutterSceneAuthoredMipBindingPlan {
  FlutterSceneAuthoredMipBindingPlan({
    required List<FlutterSceneAuthoredMipImageUpload> uploads,
  }) : uploads = List<FlutterSceneAuthoredMipImageUpload>.unmodifiable(uploads);

  final List<FlutterSceneAuthoredMipImageUpload> uploads;

  bool get isEmpty => uploads.isEmpty;
}

final class FlutterSceneAuthoredMipPlanResult {
  FlutterSceneAuthoredMipPlanResult({
    this.plan,
    List<ViewerDiagnostic> diagnostics = const <ViewerDiagnostic>[],
  }) : diagnostics = List<ViewerDiagnostic>.unmodifiable(diagnostics);

  final FlutterSceneAuthoredMipBindingPlan? plan;
  final List<ViewerDiagnostic> diagnostics;
}

FlutterSceneAuthoredMipPlanResult buildFlutterSceneAuthoredMipBindingPlan(
  Uint8List glbBytes, {
  required List<GlbDecodedBasisuImage> decodedImages,
  String? debugName,
}) {
  final json = _readGlbJson(glbBytes);
  if (json == null) {
    return FlutterSceneAuthoredMipPlanResult(
      diagnostics: <ViewerDiagnostic>[
        _planDiagnostic(
          'Authored mip binding requires a valid single-file GLB container.',
          debugName: debugName,
          limitation: 'authoredMipBindingPlanGlb',
          status: 'malformedAsset',
        ),
      ],
    );
  }
  final textures = _objectList(json['textures']);
  final materials = _objectList(json['materials']);
  final meshes = _objectList(json['meshes']);
  final nodes = _objectList(json['nodes']);
  final scenes = _objectList(json['scenes']);
  if (textures == null ||
      materials == null ||
      meshes == null ||
      nodes == null ||
      scenes == null) {
    return FlutterSceneAuthoredMipPlanResult(
      diagnostics: <ViewerDiagnostic>[
        _planDiagnostic(
          'Authored mip binding requires array texture/material/topology metadata.',
          debugName: debugName,
          limitation: 'authoredMipBindingPlanSchema',
          status: 'malformedAsset',
        ),
      ],
    );
  }

  final required =
      (_objectList(json['extensionsRequired']) ?? const <Object?>[])
          .contains('KHR_texture_basisu');
  final decodedByTexture = <int,
      ({
    GlbDecodedBasisuImage image,
    GlbDecodedBasisuTextureBinding binding
  })>{};
  for (final image in decodedImages) {
    for (final binding in image.textureBindings) {
      if (binding.textureIndex < 0 ||
          binding.textureIndex >= textures.length ||
          decodedByTexture.containsKey(binding.textureIndex)) {
        return FlutterSceneAuthoredMipPlanResult(
          diagnostics: <ViewerDiagnostic>[
            _planDiagnostic(
              'Decoded authored mip texture bindings must be unique and in range.',
              debugName: debugName,
              limitation: 'authoredMipBindingPlanSchema',
              status: 'malformedOutput',
              details: <String, Object?>{
                'imageIndex': image.imageIndex,
                'textureIndex': binding.textureIndex,
              },
            ),
          ],
        );
      }
      decodedByTexture[binding.textureIndex] = (image: image, binding: binding);
    }
  }

  final builders = <String, _AuthoredMipUploadBuilder>{};
  final diagnostics = <ViewerDiagnostic>[];
  final missingDecodedTextures = <int>{};

  void addTarget(
    int textureIndex,
    FlutterSceneAuthoredMipMaterialSlot slot,
    List<int> nodeChildPath,
    int primitiveIndex,
  ) {
    final decoded = decodedByTexture[textureIndex];
    if (decoded == null) {
      final texture = textureIndex >= 0 && textureIndex < textures.length
          ? _objectMap(textures[textureIndex])
          : null;
      final extensions = _objectMap(texture?['extensions']);
      if (extensions?.containsKey('KHR_texture_basisu') == true &&
          missingDecodedTextures.add(textureIndex)) {
        diagnostics.add(
          _planDiagnostic(
            'Decoded authored mip output is missing its consuming texture binding.',
            debugName: debugName,
            limitation: 'authoredMipBindingPlanSchema',
            status: 'malformedOutput',
            details: <String, Object?>{
              'required': required,
              'textureIndex': textureIndex,
              'slot': slot.name,
            },
          ),
        );
      }
      return;
    }
    final role = _roleForSlot(slot);
    final expectedNativeRole = _nativeStorageRoleForContentRole(role);
    if (decoded.image.contentRole != expectedNativeRole) {
      diagnostics.add(
        _planDiagnostic(
          'Decoded authored mip content role does not match its material slot.',
          debugName: debugName,
          limitation: 'authoredMipContentRole',
          status: 'malformedOutput',
          details: <String, Object?>{
            'blocking': required,
            'required': required,
            'imageIndex': decoded.image.imageIndex,
            'textureIndex': textureIndex,
            'slot': slot.name,
            'contentRole': decoded.image.contentRole,
            'expectedContentRole': expectedNativeRole,
          },
        ),
      );
      return;
    }
    final key = '${decoded.image.imageIndex}:${decoded.image.contentRole}';
    final builder = builders.putIfAbsent(
      key,
      () => _AuthoredMipUploadBuilder(
        decoded.image,
        _storageRoleForNativeName(decoded.image.contentRole),
      ),
    );
    builder.add(
      decoded.binding,
      FlutterSceneAuthoredMipMaterialTarget(
        nodeChildPath: nodeChildPath,
        primitiveIndex: primitiveIndex,
        slot: slot,
        required: required,
      ),
    );
  }

  void addMaterialTargets(
    Map<String, Object?> material,
    List<int> nodeChildPath,
    int primitiveIndex,
  ) {
    final pbr = _objectMap(material['pbrMetallicRoughness']);
    _addTextureInfoTarget(
      pbr?['baseColorTexture'],
      FlutterSceneAuthoredMipMaterialSlot.baseColor,
      nodeChildPath,
      primitiveIndex,
      addTarget,
    );
    _addTextureInfoTarget(
      pbr?['metallicRoughnessTexture'],
      FlutterSceneAuthoredMipMaterialSlot.metallicRoughness,
      nodeChildPath,
      primitiveIndex,
      addTarget,
    );
    _addTextureInfoTarget(
        material['normalTexture'],
        FlutterSceneAuthoredMipMaterialSlot.normal,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        material['occlusionTexture'],
        FlutterSceneAuthoredMipMaterialSlot.occlusion,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        material['emissiveTexture'],
        FlutterSceneAuthoredMipMaterialSlot.emissive,
        nodeChildPath,
        primitiveIndex,
        addTarget);

    final extensions = _objectMap(material['extensions']);
    final transmission = _objectMap(extensions?['KHR_materials_transmission']);
    final volume = _objectMap(extensions?['KHR_materials_volume']);
    final clearcoat = _objectMap(extensions?['KHR_materials_clearcoat']);
    final specular = _objectMap(extensions?['KHR_materials_specular']);
    _addTextureInfoTarget(
        transmission?['transmissionTexture'],
        FlutterSceneAuthoredMipMaterialSlot.transmission,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        volume?['thicknessTexture'],
        FlutterSceneAuthoredMipMaterialSlot.thickness,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        clearcoat?['clearcoatTexture'],
        FlutterSceneAuthoredMipMaterialSlot.clearcoat,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        clearcoat?['clearcoatRoughnessTexture'],
        FlutterSceneAuthoredMipMaterialSlot.clearcoatRoughness,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        clearcoat?['clearcoatNormalTexture'],
        FlutterSceneAuthoredMipMaterialSlot.clearcoatNormal,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        specular?['specularTexture'],
        FlutterSceneAuthoredMipMaterialSlot.specular,
        nodeChildPath,
        primitiveIndex,
        addTarget);
    _addTextureInfoTarget(
        specular?['specularColorTexture'],
        FlutterSceneAuthoredMipMaterialSlot.specularColor,
        nodeChildPath,
        primitiveIndex,
        addTarget);
  }

  final active = <int>{};
  void visitNode(int nodeIndex, List<int> path) {
    if (nodeIndex < 0 || nodeIndex >= nodes.length || !active.add(nodeIndex)) {
      diagnostics.add(
        _planDiagnostic(
          'Authored mip scene topology contains an invalid or cyclic node reference.',
          debugName: debugName,
          limitation: 'authoredMipBindingPlanTopology',
          status: 'malformedAsset',
          details: <String, Object?>{'nodeIndex': nodeIndex},
        ),
      );
      return;
    }
    final node = _objectMap(nodes[nodeIndex]);
    final meshIndex = _int(node?['mesh']);
    if (meshIndex != null && meshIndex >= 0 && meshIndex < meshes.length) {
      final mesh = _objectMap(meshes[meshIndex]);
      final primitives = _objectList(mesh?['primitives']);
      if (primitives != null) {
        var renderedPrimitiveIndex = 0;
        for (final rawPrimitive in primitives) {
          final primitive = _objectMap(rawPrimitive);
          final mode = _int(primitive?['mode']) ?? 4;
          if (mode != 4) {
            continue;
          }
          final materialIndex = _int(primitive?['material']);
          if (materialIndex != null &&
              materialIndex >= 0 &&
              materialIndex < materials.length) {
            final material = _objectMap(materials[materialIndex]);
            if (material != null) {
              addMaterialTargets(material, path, renderedPrimitiveIndex);
            }
          }
          renderedPrimitiveIndex += 1;
        }
      }
    }
    final children = _objectList(node?['children']) ?? const <Object?>[];
    for (var childPosition = 0;
        childPosition < children.length;
        childPosition += 1) {
      final childIndex = _int(children[childPosition]);
      if (childIndex != null) {
        visitNode(childIndex, <int>[...path, childPosition]);
      }
    }
    active.remove(nodeIndex);
  }

  final sceneIndex = _int(json['scene']) ?? 0;
  if (sceneIndex < 0 || sceneIndex >= scenes.length) {
    diagnostics.add(
      _planDiagnostic(
        'Authored mip binding could not resolve the default glTF scene.',
        debugName: debugName,
        limitation: 'authoredMipBindingPlanTopology',
        status: 'malformedAsset',
      ),
    );
  } else {
    final scene = _objectMap(scenes[sceneIndex]);
    final roots = _objectList(scene?['nodes']) ?? const <Object?>[];
    for (var rootPosition = 0; rootPosition < roots.length; rootPosition += 1) {
      final rootIndex = _int(roots[rootPosition]);
      if (rootIndex != null) {
        visitNode(rootIndex, <int>[rootPosition]);
      }
    }
  }

  if (diagnostics.any(
    (diagnostic) =>
        diagnostic.details['blocking'] == true ||
        diagnostic.details['status'] == 'malformedAsset' ||
        diagnostic.details['status'] == 'malformedOutput',
  )) {
    return FlutterSceneAuthoredMipPlanResult(diagnostics: diagnostics);
  }
  return FlutterSceneAuthoredMipPlanResult(
    plan: FlutterSceneAuthoredMipBindingPlan(
      uploads: <FlutterSceneAuthoredMipImageUpload>[
        for (final builder in builders.values) builder.build(),
      ],
    ),
    diagnostics: diagnostics,
  );
}

final class _AuthoredMipUploadBuilder {
  _AuthoredMipUploadBuilder(this.image, this.storageRole);

  final GlbDecodedBasisuImage image;
  final FlutterSceneAuthoredMipStorageRole storageRole;
  final Map<int, _AuthoredMipTextureBindingBuilder> bindings =
      <int, _AuthoredMipTextureBindingBuilder>{};

  void add(
    GlbDecodedBasisuTextureBinding binding,
    FlutterSceneAuthoredMipMaterialTarget target,
  ) {
    (bindings[binding.textureIndex] ??=
            _AuthoredMipTextureBindingBuilder(binding))
        .targets
        .add(target);
  }

  FlutterSceneAuthoredMipImageUpload build() =>
      FlutterSceneAuthoredMipImageUpload(
        imageIndex: image.imageIndex,
        contentRole: storageRole == FlutterSceneAuthoredMipStorageRole.color
            ? FlutterSceneAuthoredMipContentRole.color
            : FlutterSceneAuthoredMipContentRole.data,
        storageRole: storageRole,
        levels: <FlutterSceneAuthoredMipLevel>[
          for (final level in image.levels)
            FlutterSceneAuthoredMipLevel(
              level: level.level,
              width: level.width,
              height: level.height,
              rgbaBytes: level.rgbaBytes,
            ),
        ],
        textureBindings: <FlutterSceneAuthoredMipTextureBinding>[
          for (final builder in bindings.values) builder.build(),
        ],
      );
}

final class _AuthoredMipTextureBindingBuilder {
  _AuthoredMipTextureBindingBuilder(this.binding);

  final GlbDecodedBasisuTextureBinding binding;
  final List<FlutterSceneAuthoredMipMaterialTarget> targets =
      <FlutterSceneAuthoredMipMaterialTarget>[];

  FlutterSceneAuthoredMipTextureBinding build() =>
      FlutterSceneAuthoredMipTextureBinding(
        textureIndex: binding.textureIndex,
        sampler: FlutterSceneAuthoredMipSamplerIntent(
          magFilter: binding.sampler.magFilter,
          minFilter: binding.sampler.minFilter,
          wrapS: binding.sampler.wrapS,
          wrapT: binding.sampler.wrapT,
        ),
        targets: targets,
      );
}

typedef _AddTextureTarget = void Function(
  int textureIndex,
  FlutterSceneAuthoredMipMaterialSlot slot,
  List<int> nodeChildPath,
  int primitiveIndex,
);

void _addTextureInfoTarget(
  Object? rawTextureInfo,
  FlutterSceneAuthoredMipMaterialSlot slot,
  List<int> nodeChildPath,
  int primitiveIndex,
  _AddTextureTarget add,
) {
  final textureInfo = _objectMap(rawTextureInfo);
  final textureIndex = _int(textureInfo?['index']);
  if (textureIndex != null) {
    add(textureIndex, slot, nodeChildPath, primitiveIndex);
  }
}

FlutterSceneAuthoredMipContentRole _roleForSlot(
  FlutterSceneAuthoredMipMaterialSlot slot,
) =>
    switch (slot) {
      FlutterSceneAuthoredMipMaterialSlot.baseColor ||
      FlutterSceneAuthoredMipMaterialSlot.emissive ||
      FlutterSceneAuthoredMipMaterialSlot.specularColor =>
        FlutterSceneAuthoredMipContentRole.color,
      FlutterSceneAuthoredMipMaterialSlot.normal ||
      FlutterSceneAuthoredMipMaterialSlot.clearcoatNormal =>
        FlutterSceneAuthoredMipContentRole.normal,
      _ => FlutterSceneAuthoredMipContentRole.data,
    };

FlutterSceneAuthoredMipStorageRole _storageRoleForContentRole(
  FlutterSceneAuthoredMipContentRole role,
) =>
    role == FlutterSceneAuthoredMipContentRole.color
        ? FlutterSceneAuthoredMipStorageRole.color
        : FlutterSceneAuthoredMipStorageRole.nonColor;

String _nativeStorageRoleForContentRole(
  FlutterSceneAuthoredMipContentRole role,
) =>
    _storageRoleForContentRole(role).name;

FlutterSceneAuthoredMipStorageRole _storageRoleForNativeName(String role) =>
    switch (role) {
      'color' => FlutterSceneAuthoredMipStorageRole.color,
      'nonColor' => FlutterSceneAuthoredMipStorageRole.nonColor,
      _ => throw StateError('Unsupported decoded authored mip role: $role'),
    };

Map<String, Object?>? _readGlbJson(Uint8List bytes) {
  if (bytes.lengthInBytes < 20) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46546c67 ||
      data.getUint32(4, Endian.little) != 2 ||
      data.getUint32(8, Endian.little) != bytes.lengthInBytes) {
    return null;
  }
  final jsonLength = data.getUint32(12, Endian.little);
  final jsonType = data.getUint32(16, Endian.little);
  final jsonEnd = 20 + jsonLength;
  if (jsonType != 0x4e4f534a || jsonEnd > bytes.lengthInBytes) {
    return null;
  }
  try {
    final decoded = jsonDecode(
      utf8.decode(Uint8List.sublistView(bytes, 20, jsonEnd)).trimRight(),
    );
    return _objectMap(decoded);
  } on Object {
    return null;
  }
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

List<Object?>? _objectList(Object? value) =>
    value is List ? value.cast<Object?>() : null;

int? _int(Object? value) => value is int ? value : null;

ViewerDiagnostic _planDiagnostic(
  String message, {
  required String? debugName,
  required String limitation,
  required String status,
  Map<String, Object?> details = const <String, Object?>{},
}) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message: message,
      details: <String, Object?>{
        if (debugName != null) 'source': debugName,
        'extension': 'KHR_texture_basisu',
        'limitation': limitation,
        'status': status,
        'blocking': true,
        ...details,
      },
    );

/// Injectable boundary around the exact pinned flutter_scene GPU operations.
abstract interface class FlutterSceneAuthoredMipTextureInterop {
  int rendererMipLevelLimit({required int width, required int height});

  Object allocateRgba8Texture({
    required int width,
    required int height,
    required int mipLevelCount,
  });

  void overwriteRgba8(
    Object texture,
    ByteData rgbaBytes, {
    required int mipLevel,
  });

  flutter_scene.TextureSource wrapTexture(
    Object texture, {
    required flutter_scene_gpu.SamplerOptions sampler,
  });
}

final class FlutterSceneAuthoredMipTextureUploadResult {
  FlutterSceneAuthoredMipTextureUploadResult._({
    List<flutter_scene.TextureSource> textureSources =
        const <flutter_scene.TextureSource>[],
    this.diagnostic,
    this.contentRole,
  }) : textureSources =
            List<flutter_scene.TextureSource>.unmodifiable(textureSources);

  final List<flutter_scene.TextureSource> textureSources;
  final ViewerDiagnostic? diagnostic;
  final FlutterSceneAuthoredMipContentRole? contentRole;

  flutter_scene.TextureSource? get textureSource =>
      textureSources.isEmpty ? null : textureSources.first;
}

/// Validates and uploads an authored mip chain without generating replacement
/// levels or routing level zero through an encoded-image path.
final class FlutterSceneAuthoredMipTextureUploader {
  FlutterSceneAuthoredMipTextureUploader({
    FlutterSceneAuthoredMipTextureInterop? interop,
  }) : _interop = interop ?? const _PinnedFlutterSceneMipTextureInterop();

  final FlutterSceneAuthoredMipTextureInterop _interop;

  FlutterSceneAuthoredMipTextureUploadResult upload({
    required List<FlutterSceneAuthoredMipLevel> levels,
    required FlutterSceneAuthoredMipContentRole contentRole,
    required FlutterSceneAuthoredMipSamplerIntent sampler,
    List<FlutterSceneAuthoredMipSamplerIntent> additionalSamplers =
        const <FlutterSceneAuthoredMipSamplerIntent>[],
  }) {
    final validation = _validateLevels(levels);
    if (validation != null) {
      return FlutterSceneAuthoredMipTextureUploadResult._(
        diagnostic: validation,
      );
    }
    final base = levels.first;
    final samplerIntents = <FlutterSceneAuthoredMipSamplerIntent>[
      sampler,
      ...additionalSamplers,
    ];
    final samplerOptions = <flutter_scene_gpu.SamplerOptions>[];
    for (var index = 0; index < samplerIntents.length; index += 1) {
      final samplerResult = _samplerOptions(
        samplerIntents[index],
        hasMultipleLevels: levels.length > 1,
      );
      final samplerDiagnostic = samplerResult.diagnostic;
      if (samplerDiagnostic != null) {
        return FlutterSceneAuthoredMipTextureUploadResult._(
          diagnostic: ViewerDiagnostic(
            code: samplerDiagnostic.code,
            message: samplerDiagnostic.message,
            details: <String, Object?>{
              ...samplerDiagnostic.details,
              'samplerIndex': index,
            },
          ),
        );
      }
      samplerOptions.add(samplerResult.options!);
    }

    final rendererLimit = _interop.rendererMipLevelLimit(
      width: base.width,
      height: base.height,
    );
    if (levels.length > rendererLimit) {
      return FlutterSceneAuthoredMipTextureUploadResult._(
        diagnostic: ViewerDiagnostic(
          code: ViewerDiagnosticCode.unsupportedModelFeature,
          message:
              'The pinned renderer cannot allocate the complete authored mip chain.',
          details: <String, Object?>{
            'limitation': 'rendererMipCountLimit',
            'status': 'unsupported',
            'requestedMipLevelCount': levels.length,
            'rendererMipLevelCount': rendererLimit,
            'width': base.width,
            'height': base.height,
            'contentRole': contentRole.name,
          },
        ),
      );
    }

    final Object texture;
    try {
      texture = _interop.allocateRgba8Texture(
        width: base.width,
        height: base.height,
        mipLevelCount: levels.length,
      );
    } on Object catch (error) {
      return FlutterSceneAuthoredMipTextureUploadResult._(
        diagnostic: _gpuFailure(
          'The pinned renderer failed to allocate the authored mip texture.',
          limitation: 'rendererTextureAllocation',
          error: error,
          levels: levels,
          contentRole: contentRole,
        ),
      );
    }

    try {
      for (final level in levels) {
        _interop.overwriteRgba8(
          texture,
          level._byteData,
          mipLevel: level.level,
        );
      }
      final sources = <flutter_scene.TextureSource>[
        for (final sampler in samplerOptions)
          _interop.wrapTexture(texture, sampler: sampler),
      ];
      return FlutterSceneAuthoredMipTextureUploadResult._(
        textureSources: sources,
        contentRole: contentRole,
      );
    } on Object catch (error) {
      return FlutterSceneAuthoredMipTextureUploadResult._(
        diagnostic: _gpuFailure(
          'The pinned renderer failed to upload the complete authored mip chain.',
          limitation: 'rendererTextureUpload',
          error: error,
          levels: levels,
          contentRole: contentRole,
        ),
      );
    }
  }
}

ViewerDiagnostic? _validateLevels(List<FlutterSceneAuthoredMipLevel> levels) {
  if (levels.isEmpty) {
    return _invalidChain('Authored mip chains must contain at least level 0.');
  }
  final base = levels.first;
  if (base.width <= 0 || base.height <= 0) {
    return _invalidChain(
      'Authored mip base dimensions must be positive.',
      level: base.level,
      width: base.width,
      height: base.height,
    );
  }
  for (var index = 0; index < levels.length; index += 1) {
    final level = levels[index];
    final expectedWidth = _mipDimension(base.width, index);
    final expectedHeight = _mipDimension(base.height, index);
    final expectedBytes = expectedWidth * expectedHeight * 4;
    if (level.level != index ||
        level.width != expectedWidth ||
        level.height != expectedHeight ||
        level._byteLength != expectedBytes) {
      return _invalidChain(
        'Authored mip levels must be ordered, canonical, and exact RGBA8888.',
        level: level.level,
        width: level.width,
        height: level.height,
        details: <String, Object?>{
          'index': index,
          'expectedLevel': index,
          'expectedWidth': expectedWidth,
          'expectedHeight': expectedHeight,
          'expectedByteLength': expectedBytes,
          'actualByteLength': level._byteLength,
        },
      );
    }
  }
  return null;
}

int _mipDimension(int base, int level) {
  final shifted = base >> level;
  return shifted < 1 ? 1 : shifted;
}

ViewerDiagnostic _invalidChain(
  String message, {
  int? level,
  int? width,
  int? height,
  Map<String, Object?> details = const <String, Object?>{},
}) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message: message,
      details: <String, Object?>{
        'limitation': 'invalidAuthoredMipChain',
        'status': 'malformedOutput',
        if (level != null) 'level': level,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        ...details,
      },
    );

typedef _SamplerResult = ({
  flutter_scene_gpu.SamplerOptions? options,
  ViewerDiagnostic? diagnostic,
});

_SamplerResult _samplerOptions(
  FlutterSceneAuthoredMipSamplerIntent intent, {
  required bool hasMultipleLevels,
}) {
  final magFilter = switch (intent.magFilter) {
    9728 => flutter_scene_gpu.MinMagFilter.nearest,
    9729 => flutter_scene_gpu.MinMagFilter.linear,
    _ => null,
  };
  final minAndMip = switch (intent.minFilter) {
    9728 => (
        flutter_scene_gpu.MinMagFilter.nearest,
        flutter_scene_gpu.MipFilter.nearest,
        false,
      ),
    9729 => (
        flutter_scene_gpu.MinMagFilter.linear,
        flutter_scene_gpu.MipFilter.nearest,
        false,
      ),
    9984 => (
        flutter_scene_gpu.MinMagFilter.nearest,
        flutter_scene_gpu.MipFilter.nearest,
        true,
      ),
    9985 => (
        flutter_scene_gpu.MinMagFilter.linear,
        flutter_scene_gpu.MipFilter.nearest,
        true,
      ),
    9986 => (
        flutter_scene_gpu.MinMagFilter.nearest,
        flutter_scene_gpu.MipFilter.linear,
        true,
      ),
    9987 => (
        flutter_scene_gpu.MinMagFilter.linear,
        flutter_scene_gpu.MipFilter.linear,
        true,
      ),
    _ => null,
  };
  final wrapS = _addressMode(intent.wrapS);
  final wrapT = _addressMode(intent.wrapT);
  if (magFilter == null ||
      minAndMip == null ||
      wrapS == null ||
      wrapT == null) {
    return (
      options: null,
      diagnostic: _unsupportedSampler(intent, 'invalid glTF sampler value'),
    );
  }
  if (hasMultipleLevels && !minAndMip.$3) {
    return (
      options: null,
      diagnostic: _unsupportedSampler(
        intent,
        'the pinned WebGL2 path cannot retain a no-mip min filter on a multi-level texture',
      ),
    );
  }
  return (
    options: flutter_scene_gpu.SamplerOptions(
      minFilter: minAndMip.$1,
      magFilter: magFilter,
      mipFilter: minAndMip.$2,
      widthAddressMode: wrapS,
      heightAddressMode: wrapT,
      maxAnisotropy: 1,
    ),
    diagnostic: null,
  );
}

flutter_scene_gpu.SamplerAddressMode? _addressMode(int value) =>
    switch (value) {
      33071 => flutter_scene_gpu.SamplerAddressMode.clampToEdge,
      33648 => flutter_scene_gpu.SamplerAddressMode.mirror,
      10497 => flutter_scene_gpu.SamplerAddressMode.repeat,
      _ => null,
    };

ViewerDiagnostic _unsupportedSampler(
  FlutterSceneAuthoredMipSamplerIntent intent,
  String reason,
) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.unsupportedModelFeature,
      message: 'The authored mip sampler cannot be represented exactly.',
      details: <String, Object?>{
        'limitation': 'unsupportedSamplerIntent',
        'status': 'unsupported',
        'reason': reason,
        'magFilter': intent.magFilter,
        'minFilter': intent.minFilter,
        'wrapS': intent.wrapS,
        'wrapT': intent.wrapT,
      },
    );

ViewerDiagnostic _gpuFailure(
  String message, {
  required String limitation,
  required Object error,
  required List<FlutterSceneAuthoredMipLevel> levels,
  required FlutterSceneAuthoredMipContentRole contentRole,
}) =>
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.adapterFailure,
      message: message,
      details: <String, Object?>{
        'limitation': limitation,
        'status': 'failed',
        'mipLevelCount': levels.length,
        'contentRole': contentRole.name,
        'deterministicDispose': 'unavailable',
        'error': error.toString(),
      },
    );

final class _PinnedFlutterSceneMipTextureInterop
    implements FlutterSceneAuthoredMipTextureInterop {
  const _PinnedFlutterSceneMipTextureInterop();

  @override
  int rendererMipLevelLimit({required int width, required int height}) =>
      flutter_scene_gpu.Texture.fullMipCount(width, height);

  @override
  Object allocateRgba8Texture({
    required int width,
    required int height,
    required int mipLevelCount,
  }) =>
      flutter_scene_gpu.gpuContext.createTexture(
        flutter_scene_gpu.StorageMode.hostVisible,
        width,
        height,
        format: flutter_scene_gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
        enableShaderWriteUsage: false,
        mipLevelCount: mipLevelCount,
      );

  @override
  void overwriteRgba8(
    Object texture,
    ByteData rgbaBytes, {
    required int mipLevel,
  }) {
    (texture as flutter_scene_gpu.Texture).overwrite(
      rgbaBytes,
      mipLevel: mipLevel,
    );
  }

  @override
  flutter_scene.TextureSource wrapTexture(
    Object texture, {
    required flutter_scene_gpu.SamplerOptions sampler,
  }) =>
      flutter_scene.GpuTextureSource(
        texture as flutter_scene_gpu.Texture,
        sampler: sampler,
      );
}
