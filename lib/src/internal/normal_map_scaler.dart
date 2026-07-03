import 'dart:math' as math;
import 'dart:typed_data';

/// Applies a normal-map intensity multiplier to raw RGBA normal-map pixels.
///
/// Normal maps store X/Y around 0.5 and Z toward 1. Scaling X/Y around that
/// center increases or decreases the visible bump strength. Z is reconstructed
/// so the output remains a normalized tangent-space normal.
Uint8List scaleNormalMapRgba(Uint8List rgba, double scale) {
  if (rgba.length % 4 != 0) {
    throw ArgumentError.value(rgba.length, 'rgba.length', 'Expected RGBA data');
  }
  final safeScale = scale.isFinite ? math.max(0.0, scale) : 1.0;
  final scaled = Uint8List.fromList(rgba);
  for (var offset = 0; offset < rgba.length; offset += 4) {
    var x = _decodeNormalChannel(rgba[offset]) * safeScale;
    var y = _decodeNormalChannel(rgba[offset + 1]) * safeScale;
    var xyLengthSquared = x * x + y * y;
    if (xyLengthSquared > 1) {
      final inverseLength = 1 / math.sqrt(xyLengthSquared);
      x *= inverseLength;
      y *= inverseLength;
      xyLengthSquared = 1;
    }
    final z = math.sqrt(math.max(0.0, 1 - xyLengthSquared));
    scaled[offset] = _encodeNormalChannel(x);
    scaled[offset + 1] = _encodeNormalChannel(y);
    scaled[offset + 2] = _encodeNormalChannel(z);
  }
  return scaled;
}

double _decodeNormalChannel(int value) => value / 255 * 2 - 1;

int _encodeNormalChannel(double value) {
  return ((value * 0.5 + 0.5) * 255).round().clamp(0, 255);
}
