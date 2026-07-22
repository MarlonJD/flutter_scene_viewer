import 'package:flutter/foundation.dart';

import 'texture_source.dart';

/// The glTF material texture slot targeted by a runtime binding.
enum MaterialTextureSlot {
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
  sheenColor,
  sheenRoughness,
}

enum TextureWrapMode { clampToEdge, mirroredRepeat, repeat }

enum TextureMagFilter { nearest, linear }

enum TextureMinFilter {
  nearest,
  linear,
  nearestMipmapNearest,
  linearMipmapNearest,
  nearestMipmapLinear,
  linearMipmapLinear,
}

void _requireFinite(String field, double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, field, 'must be finite');
  }
}

void _requireFinitePair(String field, List<double> value) {
  if (value.length != 2) {
    throw ArgumentError.value(value, field, 'must contain exactly two values');
  }
  _requireFinite('$field[0]', value[0]);
  _requireFinite('$field[1]', value[1]);
}

/// glTF sampler state associated with one material texture binding.
@immutable
final class TextureSampler {
  const TextureSampler({
    this.wrapS = TextureWrapMode.repeat,
    this.wrapT = TextureWrapMode.repeat,
    this.magFilter,
    this.minFilter,
  });

  final TextureWrapMode wrapS;
  final TextureWrapMode wrapT;
  final TextureMagFilter? magFilter;
  final TextureMinFilter? minFilter;

  Map<String, Object?> toJson() => <String, Object?>{
        'wrapS': wrapS.name,
        'wrapT': wrapT.name,
        if (magFilter != null) 'magFilter': magFilter!.name,
        if (minFilter != null) 'minFilter': minFilter!.name,
      };

  static TextureSampler fromJson(Map<String, Object?> json) {
    return TextureSampler(
      wrapS: _enumValue(
        json['wrapS'],
        'wrapS',
        TextureWrapMode.values,
        fallback: TextureWrapMode.repeat,
      ),
      wrapT: _enumValue(
        json['wrapT'],
        'wrapT',
        TextureWrapMode.values,
        fallback: TextureWrapMode.repeat,
      ),
      magFilter: _nullableEnumValue(
        json['magFilter'],
        'magFilter',
        TextureMagFilter.values,
      ),
      minFilter: _nullableEnumValue(
        json['minFilter'],
        'minFilter',
        TextureMinFilter.values,
      ),
    );
  }
}

/// KHR_texture_transform-compatible UV transform data.
@immutable
final class TextureTransform {
  factory TextureTransform({
    List<double> offset = const <double>[0, 0],
    List<double> scale = const <double>[1, 1],
    double rotation = 0,
    int? texCoordOverride,
  }) {
    _requireFinitePair('offset', offset);
    _requireFinitePair('scale', scale);
    _requireFinite('rotation', rotation);
    if (texCoordOverride != null && texCoordOverride < 0) {
      throw ArgumentError.value(
        texCoordOverride,
        'texCoordOverride',
        'must be non-negative',
      );
    }
    return TextureTransform._(
      offsetX: offset[0],
      offsetY: offset[1],
      scaleX: scale[0],
      scaleY: scale[1],
      rotation: rotation,
      texCoordOverride: texCoordOverride,
    );
  }

  const TextureTransform._({
    required this.offsetX,
    required this.offsetY,
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
    required this.texCoordOverride,
  });

  static const identity = TextureTransform._(
    offsetX: 0,
    offsetY: 0,
    scaleX: 1,
    scaleY: 1,
    rotation: 0,
    texCoordOverride: null,
  );

  final double offsetX;
  final double offsetY;
  final double scaleX;
  final double scaleY;
  final double rotation;
  final int? texCoordOverride;

  List<double> get offset =>
      List<double>.unmodifiable(<double>[offsetX, offsetY]);

  List<double> get scale => List<double>.unmodifiable(<double>[scaleX, scaleY]);

  Map<String, Object?> toJson() => <String, Object?>{
        'offset': offset,
        'scale': scale,
        'rotation': rotation,
        if (texCoordOverride != null) 'texCoordOverride': texCoordOverride,
      };

  static TextureTransform fromJson(Map<String, Object?> json) {
    try {
      return TextureTransform(
        offset: _doublePair(json['offset'], 'offset', const <double>[0, 0]),
        scale: _doublePair(json['scale'], 'scale', const <double>[1, 1]),
        rotation: _doubleValue(json['rotation'], 'rotation', fallback: 0),
        texCoordOverride:
            _nullableIntValue(json['texCoordOverride'], 'texCoordOverride'),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString(), json);
    }
  }
}

/// A source plus the glTF textureInfo, sampler, and transform intent.
@immutable
final class MaterialTextureBinding {
  factory MaterialTextureBinding({
    required TextureSource source,
    int texCoord = 0,
    TextureSampler sampler = const TextureSampler(),
    TextureTransform transform = TextureTransform.identity,
  }) {
    if (texCoord < 0) {
      throw ArgumentError.value(texCoord, 'texCoord', 'must be non-negative');
    }
    return MaterialTextureBinding._(
      source: source,
      texCoord: texCoord,
      sampler: sampler,
      transform: transform,
    );
  }

  const MaterialTextureBinding._({
    required this.source,
    required this.texCoord,
    required this.sampler,
    required this.transform,
  });

  final TextureSource source;
  final int texCoord;
  final TextureSampler sampler;
  final TextureTransform transform;

  int get effectiveTexCoord => transform.texCoordOverride ?? texCoord;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': _sourceToBindingJson(source),
        'texCoord': texCoord,
        'sampler': sampler.toJson(),
        'transform': transform.toJson(),
      };

  static MaterialTextureBinding fromJson(Map<String, Object?> json) {
    try {
      return MaterialTextureBinding(
        source: _sourceFromBindingJson(_objectMap(json['source'], 'source')),
        texCoord: _intValue(json['texCoord'], 'texCoord', fallback: 0),
        sampler: json['sampler'] == null
            ? const TextureSampler()
            : TextureSampler.fromJson(_objectMap(json['sampler'], 'sampler')),
        transform: json['transform'] == null
            ? TextureTransform.identity
            : TextureTransform.fromJson(
                _objectMap(json['transform'], 'transform'),
              ),
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString(), json);
    }
  }
}

Map<String, Object?> _sourceToBindingJson(TextureSource source) {
  final sourceJson = source.toJson();
  return <String, Object?>{
    'kind': sourceJson['type'],
    for (final entry in sourceJson.entries)
      if (entry.key != 'type') entry.key: entry.value,
  };
}

TextureSource _sourceFromBindingJson(Map<String, Object?> json) {
  final kind = json['kind'];
  if (kind is! String) {
    throw ArgumentError.value(kind, 'source.kind', 'Expected a string');
  }
  return TextureSource.fromJson(<String, Object?>{
    'type': kind,
    for (final entry in json.entries)
      if (entry.key != 'kind') entry.key: entry.value,
  });
}

T _enumValue<T extends Enum>(
  Object? value,
  String name,
  List<T> values, {
  required T fallback,
}) {
  if (value == null) {
    return fallback;
  }
  return _nullableEnumValue(value, name, values)!;
}

T? _nullableEnumValue<T extends Enum>(
  Object? value,
  String name,
  List<T> values,
) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$name must be a string', value);
  }
  for (final candidate in values) {
    if (candidate.name == value) {
      return candidate;
    }
  }
  throw FormatException('Unsupported $name', value);
}

List<double> _doublePair(
  Object? value,
  String name,
  List<double> fallback,
) {
  if (value == null) {
    return fallback;
  }
  if (value is! List || value.length != 2) {
    throw ArgumentError.value(value, name, 'Expected exactly two numbers');
  }
  return <double>[
    _doubleValue(value[0], '$name[0]'),
    _doubleValue(value[1], '$name[1]'),
  ];
}

double _doubleValue(Object? value, String name, {double? fallback}) {
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, name, 'Expected a number');
}

int _intValue(Object? value, String name, {int? fallback}) {
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  throw ArgumentError.value(value, name, 'Expected an integer');
}

int? _nullableIntValue(Object? value, String name) {
  if (value == null) {
    return null;
  }
  return _intValue(value, name);
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'Expected a map');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw ArgumentError.value(value, name, 'Expected string keys');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}
