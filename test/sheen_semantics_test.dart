import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/sheen_semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves exact glTF sheen defaults without texture samples', () {
    final resolved = resolveGltfSheenSample();

    expect(resolved.linearColor, <double>[0, 0, 0]);
    expect(resolved.roughness, 0);
    expect(resolved.isEnabled, isFalse);
  });

  test('multiplies linear factors by sRGB RGB and linear alpha samples', () {
    final resolved = resolveGltfSheenSample(
      colorFactor: const <double>[0.5, 1, 0.25],
      roughnessFactor: 0.8,
      colorTextureSampleSrgb: const <double>[0.5, 0.25, 1, 0.1],
      roughnessTextureSampleLinear: const <double>[0.9, 0.8, 0.7, 0.25],
    );

    expect(resolved.linearColor[0], closeTo(0.10702057, 1e-8));
    expect(resolved.linearColor[1], closeTo(0.05087609, 1e-8));
    expect(resolved.linearColor[2], 0.25);
    expect(resolved.roughness, 0.2);
    expect(resolved.isEnabled, isTrue);
  });

  test('uses multiplicative identity when valid factors have no textures', () {
    final resolved = resolveGltfSheenSample(
      colorFactor: const <double>[0.1, 0.2, 0.3],
      roughnessFactor: 0.4,
    );

    expect(resolved.linearColor, <double>[0.1, 0.2, 0.3]);
    expect(resolved.roughness, 0.4);
  });

  test(
      'Charlie evaluation floors only the evaluated roughness and stays finite',
      () {
    final resolved = resolveGltfSheenSample(
      colorFactor: const <double>[1, 1, 1],
      roughnessFactor: 0,
    );

    expect(resolved.roughness, 0);
    expect(effectiveSheenRoughnessForEvaluation(resolved.roughness), 0.07);
    expect(
      evaluateCharlieDistribution(nDotH: 0.5, roughness: 0),
      evaluateCharlieDistribution(nDotH: 0.5, roughness: 0.07),
    );

    for (final nDotH in <double>[0, 1]) {
      final distribution = evaluateCharlieDistribution(
        nDotH: nDotH,
        roughness: resolved.roughness,
      );
      expect(distribution.isFinite, isTrue);
      expect(distribution, greaterThanOrEqualTo(0));
    }
    for (final (nDotV, nDotL) in <(double, double)>[
      (0, 0),
      (0, 1),
      (1, 0),
      (1, 1),
    ]) {
      final visibility = evaluateCharlieVisibility(
        nDotV: nDotV,
        nDotL: nDotL,
        roughness: resolved.roughness,
      );
      expect(visibility.isFinite, isTrue);
      expect(visibility, greaterThanOrEqualTo(0));
    }

    expect(resolved.roughness, 0);
  });

  test('matches pinned Charlie points and bounds directional albedo energy',
      () {
    expect(
      evaluateCharlieDistribution(nDotH: 0.5, roughness: 0.5),
      closeTo(0.5371479329351467, 1e-14),
    );
    expect(
      evaluateCharlieVisibility(
        nDotV: 0.25,
        nDotL: 0.75,
        roughness: 0.5,
      ),
      closeTo(0.2601306469146447, 1e-14),
    );

    for (final roughness in <double>[0, 0.07, 0.25, 0.5, 1]) {
      for (final nDotV in <double>[0, 0.01, 0.25, 0.5, 1]) {
        final albedo = integrateCharlieDirectionalAlbedo(
          nDotV: nDotV,
          roughness: roughness,
        );
        expect(albedo.isFinite, isTrue);
        expect(albedo, inInclusiveRange(0, 1));
        const sheenIntensity = 0.8;
        final baseEnergyScale = 1 - sheenIntensity * albedo;
        final unitWhiteEnergy = sheenIntensity * albedo + baseEnergyScale;
        expect(baseEnergyScale, inInclusiveRange(0, 1));
        expect(unitWhiteEnergy, lessThanOrEqualTo(1));
      }
    }
    expect(
      integrateCharlieDirectionalAlbedo(nDotV: 0.5, roughness: 0.5),
      closeTo(0.1881790967542281, 1e-12),
    );
  });

  test('builds a deterministic combined half-float DFG LUT', () {
    const size = 4;
    const ggxSampleCount = 64;
    final actual = buildCombinedSheenDfgLutHalfData(
      size: size,
      ggxSampleCount: ggxSampleCount,
      sheenThetaSampleCount: 8,
      sheenPhiSampleCount: 16,
    );
    final expectedGgx = _buildPinnedGgxHalfData(
      size: size,
      sampleCount: ggxSampleCount,
    );

    var hasNonzeroCharlieAlbedo = false;
    for (var texel = 0; texel < size * size; texel += 1) {
      final offset = texel * 4;
      expect(actual[offset], expectedGgx[offset]);
      expect(actual[offset + 1], expectedGgx[offset + 1]);
      final charlieAlbedo = _halfToDouble(actual[offset + 2]);
      expect(charlieAlbedo.isFinite, isTrue);
      expect(charlieAlbedo, inInclusiveRange(0, 1));
      hasNonzeroCharlieAlbedo |= charlieAlbedo > 0;
      expect(actual[offset + 3], 0x3C00);
    }
    expect(hasNonzeroCharlieAlbedo, isTrue);
    expect(
      _sha256Hex(ByteData.sublistView(actual).buffer.asUint8List()),
      '587584940d45b1b25b5f4e73d3045b4c5dd830659323fbbdbed08ce8a81ed0d8',
    );
  });

  test('keeps the default combined DFG LUT content hash stable', () {
    final actual = buildCombinedSheenDfgLutHalfData();

    expect(actual, hasLength(64 * 64 * 4));
    expect(
      _sha256Hex(ByteData.sublistView(actual).buffer.asUint8List()),
      '8d87845f620fe09ba0a7ac8d540229f4642036d98cce9d1a5d2160d70f8d691f',
    );
  });
}

Uint16List _buildPinnedGgxHalfData({
  required int size,
  required int sampleCount,
}) {
  final result = Uint16List(size * size * 4);
  for (var y = 0; y < size; y += 1) {
    final roughness = (y + 0.5) / size;
    for (var x = 0; x < size; x += 1) {
      final nDotV = (x + 0.5) / size;
      final (scale, bias) = _integratePinnedGgx(
        nDotV,
        roughness,
        sampleCount,
      );
      final offset = (y * size + x) * 4;
      result[offset] = _referenceFloatToHalf(scale);
      result[offset + 1] = _referenceFloatToHalf(bias);
      result[offset + 3] = 0x3C00;
    }
  }
  return result;
}

(double, double) _integratePinnedGgx(
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
    final xi2 = _referenceRadicalInverse(index);
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
    final geometry = _referenceGSmith(nDotV, nDotL, k);
    final geometryVisibility = geometry * clampedVDotH / (cosTheta * nDotV);
    final fresnel = _referencePow5(1 - clampedVDotH);
    scale += (1 - fresnel) * geometryVisibility;
    bias += fresnel * geometryVisibility;
  }
  return (scale / sampleCount, bias / sampleCount);
}

double _referenceGSmith(double nDotV, double nDotL, double k) {
  double schlick(double cosine) => cosine / (cosine * (1 - k) + k);
  return schlick(nDotV) * schlick(nDotL);
}

double _referencePow5(double value) {
  final squared = value * value;
  return squared * squared * value;
}

double _referenceRadicalInverse(int index) {
  var bits = index & 0xFFFFFFFF;
  bits = ((bits << 16) | (bits >> 16)) & 0xFFFFFFFF;
  bits = (((bits & 0x55555555) << 1) | ((bits & 0xAAAAAAAA) >> 1)) & 0xFFFFFFFF;
  bits = (((bits & 0x33333333) << 2) | ((bits & 0xCCCCCCCC) >> 2)) & 0xFFFFFFFF;
  bits = (((bits & 0x0F0F0F0F) << 4) | ((bits & 0xF0F0F0F0) >> 4)) & 0xFFFFFFFF;
  bits = (((bits & 0x00FF00FF) << 8) | ((bits & 0xFF00FF00) >> 8)) & 0xFFFFFFFF;
  return bits * 2.3283064365386963e-10;
}

final ByteData _referenceFloat32 = ByteData(4);

int _referenceFloatToHalf(double value) {
  _referenceFloat32.setFloat32(0, value, Endian.little);
  final bits = _referenceFloat32.getUint32(0, Endian.little);
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

double _halfToDouble(int half) {
  final sign = (half & 0x8000) == 0 ? 1.0 : -1.0;
  final exponent = (half >> 10) & 0x1F;
  final mantissa = half & 0x03FF;
  if (exponent == 0) {
    return sign * math.pow(2, -14) * (mantissa / 1024);
  }
  if (exponent == 0x1F) {
    return mantissa == 0 ? sign * double.infinity : double.nan;
  }
  return sign * math.pow(2, exponent - 15) * (1 + mantissa / 1024);
}

String _sha256Hex(Uint8List input) {
  const initial = <int>[
    0x6A09E667,
    0xBB67AE85,
    0x3C6EF372,
    0xA54FF53A,
    0x510E527F,
    0x9B05688C,
    0x1F83D9AB,
    0x5BE0CD19,
  ];
  const roundConstants = <int>[
    0x428A2F98,
    0x71374491,
    0xB5C0FBCF,
    0xE9B5DBA5,
    0x3956C25B,
    0x59F111F1,
    0x923F82A4,
    0xAB1C5ED5,
    0xD807AA98,
    0x12835B01,
    0x243185BE,
    0x550C7DC3,
    0x72BE5D74,
    0x80DEB1FE,
    0x9BDC06A7,
    0xC19BF174,
    0xE49B69C1,
    0xEFBE4786,
    0x0FC19DC6,
    0x240CA1CC,
    0x2DE92C6F,
    0x4A7484AA,
    0x5CB0A9DC,
    0x76F988DA,
    0x983E5152,
    0xA831C66D,
    0xB00327C8,
    0xBF597FC7,
    0xC6E00BF3,
    0xD5A79147,
    0x06CA6351,
    0x14292967,
    0x27B70A85,
    0x2E1B2138,
    0x4D2C6DFC,
    0x53380D13,
    0x650A7354,
    0x766A0ABB,
    0x81C2C92E,
    0x92722C85,
    0xA2BFE8A1,
    0xA81A664B,
    0xC24B8B70,
    0xC76C51A3,
    0xD192E819,
    0xD6990624,
    0xF40E3585,
    0x106AA070,
    0x19A4C116,
    0x1E376C08,
    0x2748774C,
    0x34B0BCB5,
    0x391C0CB3,
    0x4ED8AA4A,
    0x5B9CCA4F,
    0x682E6FF3,
    0x748F82EE,
    0x78A5636F,
    0x84C87814,
    0x8CC70208,
    0x90BEFFFA,
    0xA4506CEB,
    0xBEF9A3F7,
    0xC67178F2,
  ];
  const mask = 0xFFFFFFFF;
  final message = input.toList()..add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  final bitLength = input.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    message.add((bitLength >>> shift) & 0xFF);
  }

  final hash = List<int>.from(initial);
  for (var offset = 0; offset < message.length; offset += 64) {
    final words = List<int>.filled(64, 0);
    for (var index = 0; index < 16; index += 1) {
      final byteOffset = offset + index * 4;
      words[index] = (message[byteOffset] << 24) |
          (message[byteOffset + 1] << 16) |
          (message[byteOffset + 2] << 8) |
          message[byteOffset + 3];
    }
    for (var index = 16; index < 64; index += 1) {
      final x = words[index - 15];
      final y = words[index - 2];
      final sigma0 = _rotateRight(x, 7) ^ _rotateRight(x, 18) ^ (x >>> 3);
      final sigma1 = _rotateRight(y, 17) ^ _rotateRight(y, 19) ^ (y >>> 10);
      words[index] =
          (words[index - 16] + sigma0 + words[index - 7] + sigma1) & mask;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index += 1) {
      final sum1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choice = (e & f) ^ ((~e) & g);
      final temporary1 =
          (h + sum1 + choice + roundConstants[index] + words[index]) & mask;
      final sum0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temporary2 = (sum0 + majority) & mask;
      h = g;
      g = f;
      f = e;
      e = (d + temporary1) & mask;
      d = c;
      c = b;
      b = a;
      a = (temporary1 + temporary2) & mask;
    }
    hash[0] = (hash[0] + a) & mask;
    hash[1] = (hash[1] + b) & mask;
    hash[2] = (hash[2] + c) & mask;
    hash[3] = (hash[3] + d) & mask;
    hash[4] = (hash[4] + e) & mask;
    hash[5] = (hash[5] + f) & mask;
    hash[6] = (hash[6] + g) & mask;
    hash[7] = (hash[7] + h) & mask;
  }
  return hash.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int count) =>
    ((value >>> count) | (value << (32 - count))) & 0xFFFFFFFF;
