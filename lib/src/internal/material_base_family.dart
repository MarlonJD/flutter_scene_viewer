import '../material_patch.dart';

enum MaterialBaseFamily {
  opaque,
  maskedCutout,
  translucentBlend,
  realisticGlass,
}

MaterialBaseFamily resolveMaterialBaseFamily(MaterialPatch patch) {
  if (patch.hasTransmissionOrVolumeOverride) {
    return MaterialBaseFamily.realisticGlass;
  }

  if (patch.alphaMode == MaterialAlphaMode.mask) {
    return MaterialBaseFamily.maskedCutout;
  }

  if (patch.alphaMode == MaterialAlphaMode.blend) {
    return MaterialBaseFamily.translucentBlend;
  }

  if (patch.alphaMode == MaterialAlphaMode.opaque) {
    return MaterialBaseFamily.opaque;
  }

  if (_hasTransparentBaseColorFactor(patch)) {
    return MaterialBaseFamily.translucentBlend;
  }

  return MaterialBaseFamily.opaque;
}

bool _hasTransparentBaseColorFactor(MaterialPatch patch) {
  final baseColorFactor = patch.baseColorFactor;
  return baseColorFactor != null &&
      baseColorFactor.length >= 4 &&
      baseColorFactor[3] < 1.0;
}
