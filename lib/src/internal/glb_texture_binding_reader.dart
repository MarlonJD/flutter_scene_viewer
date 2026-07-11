import '../diagnostics.dart';
import '../texture_binding.dart';
import '../texture_source.dart';

const String _textureTransformExtension = 'KHR_texture_transform';

/// Result of decoding one glTF textureInfo into viewer binding metadata.
final class GlbTextureBindingReadResult {
  const GlbTextureBindingReadResult({
    required this.binding,
    this.diagnostics = const <ViewerDiagnostic>[],
    this.hasBlockingDiagnostics = false,
  });

  final MaterialTextureBinding? binding;
  final List<ViewerDiagnostic> diagnostics;
  final bool hasBlockingDiagnostics;
}

/// Decodes the glTF sampler and KHR_texture_transform state for one slot.
///
/// Image resolution and color/data/normal role selection deliberately remain
/// outside this reader. This function owns the shared validation and mapping of
/// the binding metadata that is common to core and extension texture slots.
GlbTextureBindingReadResult readGlbTextureBinding({
  required Map<String, Object?> textureInfo,
  required List<Object?> textures,
  required List<Object?> samplers,
  required TextureSource source,
  required Set<int> availableTexCoords,
  required bool textureTransformRequired,
  required String slot,
  required String debugName,
}) {
  final textureIndex = _nonNegativeInt(textureInfo['index']);
  if (textureIndex == null || textureIndex >= textures.length) {
    return _blockingMalformed(
      debugName: debugName,
      slot: slot,
      field: 'textureInfo.index',
      value: textureInfo['index'],
      reason: 'Texture index is outside the glTF textures array.',
    );
  }
  final texture = _objectMap(textures[textureIndex]);
  if (texture == null) {
    return _blockingMalformed(
      debugName: debugName,
      slot: slot,
      field: 'textures[$textureIndex]',
      value: textures[textureIndex],
      reason: 'Texture entry must be a JSON object.',
    );
  }

  final texCoord = textureInfo.containsKey('texCoord')
      ? _nonNegativeInt(textureInfo['texCoord'])
      : 0;
  if (texCoord == null) {
    return _blockingMalformed(
      debugName: debugName,
      slot: slot,
      field: 'textureInfo.texCoord',
      value: textureInfo['texCoord'],
      reason: 'Texture coordinate index must be a non-negative integer.',
    );
  }

  final samplerRead = _readSampler(
    texture: texture,
    textureIndex: textureIndex,
    samplers: samplers,
    debugName: debugName,
    slot: slot,
  );
  if (samplerRead.result != null) {
    return samplerRead.result!;
  }

  final transformRead = _readTransform(textureInfo);
  final diagnostics = <ViewerDiagnostic>[];
  TextureTransform transform;
  if (transformRead.malformed) {
    final diagnostic = _transformDiagnostic(
      debugName: debugName,
      slot: slot,
      textureIndex: textureIndex,
      required: textureTransformRequired,
      reason: transformRead.reason!,
      value: transformRead.malformedValue,
    );
    if (textureTransformRequired) {
      return GlbTextureBindingReadResult(
        binding: null,
        diagnostics: <ViewerDiagnostic>[diagnostic],
        hasBlockingDiagnostics: true,
      );
    }
    diagnostics.add(diagnostic);
    transform = TextureTransform.identity;
  } else {
    transform = transformRead.transform!;
  }

  final effectiveTexCoord = transform.texCoordOverride ?? texCoord;
  if (!availableTexCoords.contains(effectiveTexCoord)) {
    return GlbTextureBindingReadResult(
      binding: null,
      diagnostics: <ViewerDiagnostic>[
        ...diagnostics,
        ViewerDiagnostic(
          code: ViewerDiagnosticCode.missingUvSet,
          message: 'Imported GLB texture requires missing UV coordinates.',
          details: <String, Object?>{
            'source': debugName,
            'textureSlot': slot,
            'textureIndex': textureIndex,
            'uvSet': effectiveTexCoord,
            'blocking': false,
          },
        ),
      ],
      hasBlockingDiagnostics: false,
    );
  }

  return GlbTextureBindingReadResult(
    binding: MaterialTextureBinding(
      source: source,
      texCoord: texCoord,
      sampler: samplerRead.sampler!,
      transform: transform,
    ),
    diagnostics: List<ViewerDiagnostic>.unmodifiable(diagnostics),
  );
}

_SamplerRead _readSampler({
  required Map<String, Object?> texture,
  required int textureIndex,
  required List<Object?> samplers,
  required String debugName,
  required String slot,
}) {
  if (!texture.containsKey('sampler')) {
    return const _SamplerRead(sampler: TextureSampler());
  }
  final samplerIndex = _nonNegativeInt(texture['sampler']);
  if (samplerIndex == null || samplerIndex >= samplers.length) {
    return _SamplerRead(
      result: _blockingMalformed(
        debugName: debugName,
        slot: slot,
        field: 'textures[$textureIndex].sampler',
        value: texture['sampler'],
        reason:
            'Sampler index is not a valid entry in the glTF samplers array.',
      ),
    );
  }
  final sampler = _objectMap(samplers[samplerIndex]);
  if (sampler == null) {
    return _SamplerRead(
      result: _blockingMalformed(
        debugName: debugName,
        slot: slot,
        field: 'samplers[$samplerIndex]',
        value: samplers[samplerIndex],
        reason: 'Sampler entry must be a JSON object.',
      ),
    );
  }

  final wrapS =
      _wrapMode(sampler['wrapS'], absent: !sampler.containsKey('wrapS'));
  final wrapT =
      _wrapMode(sampler['wrapT'], absent: !sampler.containsKey('wrapT'));
  final magFilter = _magFilter(
    sampler['magFilter'],
    absent: !sampler.containsKey('magFilter'),
  );
  final minFilter = _minFilter(
    sampler['minFilter'],
    absent: !sampler.containsKey('minFilter'),
  );
  if (wrapS == null ||
      wrapT == null ||
      (sampler.containsKey('magFilter') && magFilter == null) ||
      (sampler.containsKey('minFilter') && minFilter == null)) {
    return _SamplerRead(
      result: _blockingMalformed(
        debugName: debugName,
        slot: slot,
        field: 'samplers[$samplerIndex]',
        value: sampler,
        reason: 'Sampler contains an unsupported glTF enum value.',
      ),
    );
  }
  return _SamplerRead(
    sampler: TextureSampler(
      wrapS: wrapS,
      wrapT: wrapT,
      magFilter: magFilter,
      minFilter: minFilter,
    ),
  );
}

_TransformRead _readTransform(Map<String, Object?> textureInfo) {
  final rawExtensions = textureInfo['extensions'];
  if (rawExtensions == null) {
    return const _TransformRead.value(TextureTransform.identity);
  }
  final extensions = _objectMap(rawExtensions);
  if (extensions == null) {
    return _TransformRead.malformed(
      malformedValue: rawExtensions,
      reason: 'textureInfo.extensions must be a JSON object.',
    );
  }
  if (!extensions.containsKey(_textureTransformExtension)) {
    return const _TransformRead.value(TextureTransform.identity);
  }
  final rawTransform = extensions[_textureTransformExtension];
  final transform = _objectMap(rawTransform);
  if (transform == null) {
    return _TransformRead.malformed(
      malformedValue: rawTransform,
      reason: 'KHR_texture_transform must be a JSON object.',
    );
  }

  final offset = transform.containsKey('offset')
      ? _finitePair(transform['offset'])
      : const <double>[0, 0];
  final scale = transform.containsKey('scale')
      ? _finitePair(transform['scale'])
      : const <double>[1, 1];
  final rotation = transform.containsKey('rotation')
      ? _finiteDouble(transform['rotation'])
      : 0.0;
  final texCoordOverride = transform.containsKey('texCoord')
      ? _nonNegativeInt(transform['texCoord'])
      : null;
  if (offset == null ||
      scale == null ||
      rotation == null ||
      (transform.containsKey('texCoord') && texCoordOverride == null)) {
    return _TransformRead.malformed(
      malformedValue: rawTransform,
      reason:
          'KHR_texture_transform fields must have finite numeric values and a non-negative integer texCoord.',
    );
  }
  return _TransformRead.value(
    TextureTransform(
      offset: offset,
      scale: scale,
      rotation: rotation,
      texCoordOverride: texCoordOverride,
    ),
  );
}

GlbTextureBindingReadResult _blockingMalformed({
  required String debugName,
  required String slot,
  required String field,
  required Object? value,
  required String reason,
}) {
  return GlbTextureBindingReadResult(
    binding: null,
    diagnostics: <ViewerDiagnostic>[
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterFailure,
        message: 'Imported GLB texture binding is malformed.',
        details: <String, Object?>{
          'source': debugName,
          'textureSlot': slot,
          'field': field,
          'value': value,
          'reason': reason,
          'status': 'malformedAsset',
          'blocking': true,
        },
      ),
    ],
    hasBlockingDiagnostics: true,
  );
}

ViewerDiagnostic _transformDiagnostic({
  required String debugName,
  required String slot,
  required int textureIndex,
  required bool required,
  required String reason,
  required Object? value,
}) {
  return ViewerDiagnostic(
    code: required
        ? ViewerDiagnosticCode.adapterFailure
        : ViewerDiagnosticCode.unsupportedModelFeature,
    message: required
        ? 'Required KHR_texture_transform data is malformed.'
        : 'Malformed optional KHR_texture_transform was ignored.',
    details: <String, Object?>{
      'source': debugName,
      'textureSlot': slot,
      'textureIndex': textureIndex,
      'extension': _textureTransformExtension,
      'required': required,
      'blocking': required,
      'fallback': required ? 'none' : 'parentTextureInfo',
      'reason': reason,
      'value': value,
    },
  );
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

int? _nonNegativeInt(Object? value) =>
    value is int && value >= 0 ? value : null;

double? _finiteDouble(Object? value) {
  if (value is! num) {
    return null;
  }
  final result = value.toDouble();
  return result.isFinite ? result : null;
}

List<double>? _finitePair(Object? value) {
  if (value is! List || value.length != 2) {
    return null;
  }
  final first = _finiteDouble(value[0]);
  final second = _finiteDouble(value[1]);
  if (first == null || second == null) {
    return null;
  }
  return <double>[first, second];
}

TextureWrapMode? _wrapMode(Object? value, {required bool absent}) {
  if (absent) {
    return TextureWrapMode.repeat;
  }
  return switch (value) {
    33071 => TextureWrapMode.clampToEdge,
    33648 => TextureWrapMode.mirroredRepeat,
    10497 => TextureWrapMode.repeat,
    _ => null,
  };
}

TextureMagFilter? _magFilter(Object? value, {required bool absent}) {
  if (absent) {
    return null;
  }
  return switch (value) {
    9728 => TextureMagFilter.nearest,
    9729 => TextureMagFilter.linear,
    _ => null,
  };
}

TextureMinFilter? _minFilter(Object? value, {required bool absent}) {
  if (absent) {
    return null;
  }
  return switch (value) {
    9728 => TextureMinFilter.nearest,
    9729 => TextureMinFilter.linear,
    9984 => TextureMinFilter.nearestMipmapNearest,
    9985 => TextureMinFilter.linearMipmapNearest,
    9986 => TextureMinFilter.nearestMipmapLinear,
    9987 => TextureMinFilter.linearMipmapLinear,
    _ => null,
  };
}

final class _SamplerRead {
  const _SamplerRead({this.sampler, this.result});

  final TextureSampler? sampler;
  final GlbTextureBindingReadResult? result;
}

final class _TransformRead {
  const _TransformRead.value(this.transform)
      : malformed = false,
        reason = null,
        malformedValue = null;
  const _TransformRead.malformed({
    required this.malformedValue,
    required this.reason,
  })  : malformed = true,
        transform = null;

  final TextureTransform? transform;
  final Object? malformedValue;
  final bool malformed;
  final String? reason;
}
