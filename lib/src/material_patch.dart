import 'package:flutter/foundation.dart';

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
        ),
        assert(metallic == null || (metallic >= 0 && metallic <= 1)),
        assert(roughness == null || (roughness >= 0 && roughness <= 1));

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
}
