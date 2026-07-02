import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'part_address.dart';
import 'texture_source.dart';

/// Runtime patch for core glTF metallic-roughness material controls.
@immutable
final class MaterialPatch {
  const MaterialPatch({
    this.baseColorFactor,
    this.baseColorTexture,
    this.metallic,
    this.roughness,
    this.emissiveFactor,
    this.visible,
  })  : assert(
          baseColorFactor == null || baseColorFactor.length == 4,
          'baseColorFactor must be RGBA',
        ),
        assert(
          emissiveFactor == null || emissiveFactor.length == 3,
          'emissiveFactor must be RGB',
        );

  /// Linear or engine-adapted RGBA factor. Adapter owns color-space details.
  final List<double>? baseColorFactor;

  final TextureSource? baseColorTexture;

  final double? metallic;

  final double? roughness;

  final List<double>? emissiveFactor;

  final bool? visible;

  bool get isEmpty =>
      baseColorFactor == null &&
      baseColorTexture == null &&
      metallic == null &&
      roughness == null &&
      emissiveFactor == null &&
      visible == null;

  MaterialPatch merge(MaterialPatch next) => MaterialPatch(
        baseColorFactor: next.baseColorFactor ?? baseColorFactor,
        baseColorTexture: next.baseColorTexture ?? baseColorTexture,
        metallic: next.metallic ?? metallic,
        roughness: next.roughness ?? roughness,
        emissiveFactor: next.emissiveFactor ?? emissiveFactor,
        visible: next.visible ?? visible,
      );

  List<ViewerDiagnostic> validate(PartAddress address) {
    return <ViewerDiagnostic>[
      if (!_isUnitInterval(metallic))
        _rangeDiagnostic(address, 'metallic', metallic!),
      if (!_isUnitInterval(roughness))
        _rangeDiagnostic(address, 'roughness', roughness!),
    ];
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (baseColorFactor != null)
          'baseColorFactor': List<double>.of(baseColorFactor!),
        if (baseColorTexture != null)
          'baseColorTexture': baseColorTexture!.toJson(),
        if (metallic != null) 'metallic': metallic,
        if (roughness != null) 'roughness': roughness,
        if (emissiveFactor != null)
          'emissiveFactor': List<double>.of(emissiveFactor!),
        if (visible != null) 'visible': visible,
      };

  static MaterialPatch fromJson(Map<String, Object?> json) {
    final rawTexture = json['baseColorTexture'];
    return MaterialPatch(
      baseColorFactor: _doubleList(json['baseColorFactor'], 'baseColorFactor'),
      baseColorTexture: rawTexture == null
          ? null
          : TextureSource.fromJson(_objectMap(rawTexture, 'baseColorTexture')),
      metallic: _doubleValue(json['metallic'], 'metallic'),
      roughness: _doubleValue(json['roughness'], 'roughness'),
      emissiveFactor: _doubleList(json['emissiveFactor'], 'emissiveFactor'),
      visible: json['visible'] as bool?,
    );
  }
}

bool _isUnitInterval(double? value) =>
    value == null || (value >= 0 && value <= 1);

ViewerDiagnostic _rangeDiagnostic(
  PartAddress address,
  String field,
  double value,
) {
  return ViewerDiagnostic(
    code: ViewerDiagnosticCode.invalidMaterialOverride,
    message: 'Material override value must be in the 0..1 range.',
    details: <String, Object?>{
      'part': address.debugPath,
      'field': field,
      'value': value,
      'min': 0,
      'max': 1,
    },
  );
}

double? _doubleValue(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, name, 'Expected a number');
}

List<double>? _doubleList(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw ArgumentError.value(value, name, 'Expected a list');
  }
  return List<double>.unmodifiable(
    value.map((item) {
      if (item is num) {
        return item.toDouble();
      }
      throw ArgumentError.value(value, name, 'Expected numeric values');
    }),
  );
}

Map<String, Object?> _objectMap(Object value, String name) {
  if (value is! Map) {
    throw ArgumentError.value(value, name, 'Expected a map');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}
