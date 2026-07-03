import '../material_patch.dart';

enum MaterialBaseFamily {
  opaque,
  maskedCutout,
  translucentBlend,
  realisticGlass,
}

enum MaterialBaseAlphaMode {
  opaque,
  mask,
  blend,
}

MaterialBaseFamily resolveMaterialBaseFamily(
  MaterialPatch patch, {
  MaterialBaseAlphaMode alphaMode = MaterialBaseAlphaMode.opaque,
}) {
  if (patch.hasGlassOverride) {
    return MaterialBaseFamily.realisticGlass;
  }

  if (alphaMode == MaterialBaseAlphaMode.mask) {
    return MaterialBaseFamily.maskedCutout;
  }

  if (alphaMode == MaterialBaseAlphaMode.blend ||
      _hasTransparentBaseColorFactor(patch)) {
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
