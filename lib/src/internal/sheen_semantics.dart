import 'dart:math' as math;
import 'dart:typed_data';

const double _minimumSheenEvaluationRoughness = 0.07;
const double _minimumSheenCosine = 1e-6;
const double _minimumCharlieSinSquared = 0.0078125;

/// CPU-resolved KHR_materials_sheen inputs after glTF factor/sample semantics.
///
/// This is intentionally renderer-independent. Later shader and evidence work
/// can use it as the scalar/color reference without claiming a rendered lobe.
final class ResolvedGltfSheenSample {
  ResolvedGltfSheenSample({
    required List<double> linearColor,
    required this.roughness,
  }) : linearColor = List<double>.unmodifiable(linearColor);

  final List<double> linearColor;
  final double roughness;

  bool get isEnabled => linearColor.any((component) => component != 0);
}

/// Resolves the normative defaults and texture multiplication for one sample.
ResolvedGltfSheenSample resolveGltfSheenSample({
  List<double>? colorFactor,
  double? roughnessFactor,
  List<double>? colorTextureSampleSrgb,
  List<double>? roughnessTextureSampleLinear,
}) {
  final factor = colorFactor ?? const <double>[0, 0, 0];
  final colorSample = colorTextureSampleSrgb;
  final roughnessSample = roughnessTextureSampleLinear;
  return ResolvedGltfSheenSample(
    linearColor: <double>[
      for (var channel = 0; channel < 3; channel += 1)
        factor[channel] *
            (colorSample == null ? 1 : _srgbToLinear(colorSample[channel])),
    ],
    roughness: (roughnessFactor ?? 0) *
        (roughnessSample == null ? 1 : roughnessSample[3]),
  );
}

double _srgbToLinear(double component) => component <= 0.04045
    ? component / 12.92
    : math.pow((component + 0.055) / 1.055, 2.4).toDouble();

/// Returns the numerical roughness used by the Charlie evaluator.
///
/// The authored value is never rewritten; the floor exists only to keep the
/// lobe numerically well behaved at the zero-roughness glTF default.
double effectiveSheenRoughnessForEvaluation(double authoredRoughness) =>
    math.max(authoredRoughness, _minimumSheenEvaluationRoughness);

/// Evaluates the Khronos Charlie sheen distribution for one half-vector.
double evaluateCharlieDistribution({
  required double nDotH,
  required double roughness,
}) {
  final evaluationRoughness = effectiveSheenRoughnessForEvaluation(roughness);
  final alphaG = evaluationRoughness * evaluationRoughness;
  final inverseAlphaG = 1 / alphaG;
  final cosine = nDotH.abs().clamp(0.0, 1.0).toDouble();
  final sinSquared = math.max(
    1 - cosine * cosine,
    _minimumCharlieSinSquared,
  );
  return (2 + inverseAlphaG) *
      math.pow(sinSquared, 0.5 * inverseAlphaG) /
      (2 * math.pi);
}

/// Evaluates the full Khronos fitted Conty-Kulla sheen visibility term.
double evaluateCharlieVisibility({
  required double nDotV,
  required double nDotL,
  required double roughness,
}) {
  final evaluationRoughness = effectiveSheenRoughnessForEvaluation(roughness);
  final alphaG = evaluationRoughness * evaluationRoughness;
  final viewCosine = _clampSheenCosine(nDotV);
  final lightCosine = _clampSheenCosine(nDotL);
  final denominator = (1 +
          _evaluateCharlieLambda(viewCosine, alphaG) +
          _evaluateCharlieLambda(lightCosine, alphaG)) *
      4 *
      viewCosine *
      lightCosine;
  return 1 / denominator;
}

/// Integrates unit-color Charlie reflectance over the incident hemisphere.
///
/// Samples are stratified against the Charlie NDF rather than a uniform
/// hemisphere so the narrow grazing lobe remains deterministic at the
/// evaluation roughness floor. The result is the directional-albedo value
/// stored in the package-owned DFG LUT.
double integrateCharlieDirectionalAlbedo({
  required double nDotV,
  required double roughness,
  int thetaSampleCount = 16,
  int phiSampleCount = 32,
}) {
  if (thetaSampleCount <= 0 || phiSampleCount <= 0) {
    throw ArgumentError.value(
      (thetaSampleCount, phiSampleCount),
      'sampleCounts',
      'Charlie integration sample counts must both be positive.',
    );
  }

  final viewCosine = _clampSheenCosine(nDotV);
  final viewX = math.sqrt(math.max(1 - viewCosine * viewCosine, 0));
  final evaluationRoughness = effectiveSheenRoughnessForEvaluation(roughness);
  final alphaG = evaluationRoughness * evaluationRoughness;
  var sum = 0.0;

  for (var thetaIndex = 0; thetaIndex < thetaSampleCount; thetaIndex += 1) {
    final xi = (thetaIndex + 0.5) / thetaSampleCount;
    final sinTheta = math.pow(xi, alphaG / (2 * alphaG + 1)).toDouble();
    final nDotH = math.sqrt(math.max(1 - sinTheta * sinTheta, 0));
    final evaluatedDistribution = evaluateCharlieDistribution(
      nDotH: nDotH,
      roughness: roughness,
    );
    final samplingDistribution = _evaluateUnflooredCharlieDistribution(
      nDotH,
      alphaG,
    );

    for (var phiIndex = 0; phiIndex < phiSampleCount; phiIndex += 1) {
      final phi = 2 * math.pi * (phiIndex + 0.5) / phiSampleCount;
      final halfX = math.cos(phi) * sinTheta;
      final vDotH = viewX * halfX + viewCosine * nDotH;
      if (vDotH <= 0) continue;

      final lightCosine = 2 * vDotH * nDotH - viewCosine;
      if (lightCosine <= 0) continue;

      final lightPdf = samplingDistribution * nDotH / (4 * vDotH);
      if (lightPdf <= 0 || !lightPdf.isFinite) continue;

      sum += evaluatedDistribution *
          evaluateCharlieVisibility(
            nDotV: viewCosine,
            nDotL: lightCosine,
            roughness: roughness,
          ) *
          lightCosine /
          lightPdf;
    }
  }

  final sampleCount = thetaSampleCount * phiSampleCount;
  return (sum / sampleCount).clamp(0.0, 1.0).toDouble();
}

/// Builds package-owned RGBA16F DFG data for the sheen shader variant.
///
/// R/G deliberately reproduce flutter_scene revision
/// 8e2e2221405b04c517189428d0faf8474cf7f708 byte-for-byte. B contains the
/// Charlie directional albedo and A remains half-float one. Keeping this as
/// half data lets the material backend upload it without mutating the pinned
/// dependency's LUT source or consuming a second sampler.
Uint16List buildCombinedSheenDfgLutHalfData({
  int size = 64,
  int ggxSampleCount = 1024,
  int sheenThetaSampleCount = 16,
  int sheenPhiSampleCount = 32,
}) {
  if (size <= 0 ||
      ggxSampleCount <= 0 ||
      sheenThetaSampleCount <= 0 ||
      sheenPhiSampleCount <= 0) {
    throw ArgumentError(
      'DFG LUT dimensions and sample counts must all be positive.',
    );
  }

  final halfData = Uint16List(size * size * 4);
  for (var y = 0; y < size; y += 1) {
    final roughness = (y + 0.5) / size;
    for (var x = 0; x < size; x += 1) {
      final nDotV = (x + 0.5) / size;
      final (scale, bias) = _integratePinnedGgxBrdf(
        nDotV,
        roughness,
        ggxSampleCount,
      );
      final charlieAlbedo = integrateCharlieDirectionalAlbedo(
        nDotV: nDotV,
        roughness: roughness,
        thetaSampleCount: sheenThetaSampleCount,
        phiSampleCount: sheenPhiSampleCount,
      );
      final offset = (y * size + x) * 4;
      halfData[offset] = _floatToHalf(scale);
      halfData[offset + 1] = _floatToHalf(bias);
      halfData[offset + 2] = _floatToHalf(charlieAlbedo);
      halfData[offset + 3] = 0x3C00;
    }
  }
  return halfData;
}

(double, double) _integratePinnedGgxBrdf(
  double nDotV,
  double roughness,
  int sampleCount,
) {
  final viewX = math.sqrt((1 - nDotV * nDotV).clamp(0.0, 1.0));
  final alpha = roughness * roughness;
  final alphaSquaredMinusOne = alpha * alpha - 1;
  final k = alpha / 2;
  var scale = 0.0;
  var bias = 0.0;

  for (var index = 0; index < sampleCount; index += 1) {
    final xi1 = index / sampleCount;
    final xi2 = _radicalInverseVdC(index);
    final phi = 2 * math.pi * xi1;
    final cosTheta = math.sqrt(
      ((1 - xi2) / (1 + alphaSquaredMinusOne * xi2)).clamp(0.0, 1.0),
    );
    final sinTheta = math.sqrt((1 - cosTheta * cosTheta).clamp(0.0, 1.0));
    final halfX = math.cos(phi) * sinTheta;
    final vDotH = viewX * halfX + nDotV * cosTheta;
    final nDotL = 2 * vDotH * cosTheta - nDotV;
    if (nDotL <= 0) continue;

    final clampedVDotH = vDotH < 0 ? 0.0 : vDotH;
    final geometry = _ggxSmith(nDotV, nDotL, k);
    final geometryVisibility = geometry * clampedVDotH / (cosTheta * nDotV);
    final fresnel = _pow5(1 - clampedVDotH);
    scale += (1 - fresnel) * geometryVisibility;
    bias += fresnel * geometryVisibility;
  }
  return (scale / sampleCount, bias / sampleCount);
}

double _ggxSmith(double nDotV, double nDotL, double k) {
  double schlick(double cosine) => cosine / (cosine * (1 - k) + k);
  return schlick(nDotV) * schlick(nDotL);
}

double _pow5(double value) {
  final squared = value * value;
  return squared * squared * value;
}

double _radicalInverseVdC(int index) {
  var bits = index & 0xFFFFFFFF;
  bits = ((bits << 16) | (bits >> 16)) & 0xFFFFFFFF;
  bits = (((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)) & 0xFFFFFFFF;
  bits = (((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)) & 0xFFFFFFFF;
  bits = (((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)) & 0xFFFFFFFF;
  bits = (((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)) & 0xFFFFFFFF;
  return bits * 2.3283064365386963e-10;
}

final ByteData _float32 = ByteData(4);

int _floatToHalf(double value) {
  _float32.setFloat32(0, value, Endian.little);
  final bits = _float32.getUint32(0, Endian.little);
  final sign = (bits >> 16) & 0x8000;
  final exponent = (bits >> 23) & 0xFF;
  var mantissa = bits & 0x7FFFFF;
  if (exponent == 0xFF) {
    return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0);
  }
  final adjustedExponent = exponent - 127 + 15;
  if (adjustedExponent >= 0x1F) return sign | 0x7C00;
  if (adjustedExponent <= 0) {
    if (adjustedExponent < -10) return sign;
    mantissa |= 0x800000;
    final shift = 14 - adjustedExponent;
    var half = mantissa >> shift;
    if ((mantissa >> (shift - 1)) & 1 != 0) half += 1;
    return sign | half;
  }
  var half = (adjustedExponent << 10) | (mantissa >> 13);
  if ((mantissa & 0x1000) != 0) half += 1;
  return sign | half;
}

double _evaluateUnflooredCharlieDistribution(double nDotH, double alphaG) {
  final inverseAlphaG = 1 / alphaG;
  final sinSquared = math.max(1 - nDotH * nDotH, 0);
  return (2 + inverseAlphaG) *
      math.pow(sinSquared, 0.5 * inverseAlphaG) /
      (2 * math.pi);
}

double _evaluateCharlieLambda(double cosine, double alphaG) {
  if (cosine < 0.5) {
    return math.exp(_evaluateCharlieL(cosine, alphaG));
  }
  return math.exp(
    2 * _evaluateCharlieL(0.5, alphaG) - _evaluateCharlieL(1 - cosine, alphaG),
  );
}

double _evaluateCharlieL(double cosine, double alphaG) {
  final oneMinusAlphaSquared = (1 - alphaG) * (1 - alphaG);
  final a = _mix(21.5473, 25.3245, oneMinusAlphaSquared);
  final b = _mix(3.82987, 3.32435, oneMinusAlphaSquared);
  final c = _mix(0.19823, 0.16801, oneMinusAlphaSquared);
  final d = _mix(-1.97760, -1.27393, oneMinusAlphaSquared);
  final e = _mix(-4.32054, -4.85967, oneMinusAlphaSquared);
  return a / (1 + b * math.pow(cosine, c)) + d * cosine + e;
}

double _clampSheenCosine(double value) =>
    value.abs().clamp(_minimumSheenCosine, 1.0).toDouble();

double _mix(double start, double end, double amount) =>
    start * (1 - amount) + end * amount;
