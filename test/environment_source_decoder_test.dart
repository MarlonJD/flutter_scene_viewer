import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/hdr_environment_decoder.dart';
import 'package:flutter_scene_viewer/src/viewer_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes Radiance RGBE HDR pixels to linear RGBA floats', () {
    final decoded = HdrEnvironmentDecoder.decode(
      _radianceHdr(
        width: 2,
        height: 1,
        rgbe: const <int>[
          128,
          64,
          32,
          129,
          64,
          128,
          255,
          130,
        ],
      ),
      debugName: 'inline.hdr',
      format: ViewerEnvironmentFileFormat.hdr,
    );

    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.linearPixels, hasLength(8));
    expect(decoded.linearPixels[0], 1.0);
    expect(decoded.linearPixels[1], 0.5);
    expect(decoded.linearPixels[2], 0.25);
    expect(decoded.linearPixels[3], 1.0);
    expect(decoded.linearPixels[4], 1.0);
    expect(decoded.linearPixels[5], 2.0);
    expect(decoded.linearPixels[6], closeTo(3.984375, 1e-9));
    expect(decoded.linearPixels[7], 1.0);
  });

  test('rejects non-equirectangular HDR dimensions', () {
    expect(
      () => HdrEnvironmentDecoder.decode(
        _radianceHdr(
          width: 1,
          height: 1,
          rgbe: const <int>[128, 128, 128, 129],
        ),
        debugName: 'square.hdr',
        format: ViewerEnvironmentFileFormat.hdr,
      ),
      throwsA(
        isA<HdrEnvironmentDecodeException>().having(
          (error) => error.diagnostic.code,
          'diagnostic code',
          ViewerDiagnosticCode.environmentInvalidDimensions,
        ),
      ),
    );
  });

  test('decodes uncompressed OpenEXR float scanlines', () {
    final decoded = HdrEnvironmentDecoder.decode(
      _openExr(
        width: 2,
        height: 1,
        pixels: const <double>[
          0.25,
          0.5,
          0.75,
          1.0,
          2.0,
          3.0,
          4.0,
          0.5,
        ],
      ),
      debugName: 'inline.exr',
      format: ViewerEnvironmentFileFormat.exr,
    );

    expect(decoded.width, 2);
    expect(decoded.height, 1);
    expect(decoded.linearPixels, <double>[
      0.25,
      0.5,
      0.75,
      1.0,
      2.0,
      3.0,
      4.0,
      0.5,
    ]);
  });

  test('reports unsupported EXR compression as an environment diagnostic', () {
    expect(
      () => HdrEnvironmentDecoder.decode(
        _openExr(
          width: 2,
          height: 1,
          compression: 3,
          pixels: const <double>[
            0.25,
            0.5,
            0.75,
            1.0,
            2.0,
            3.0,
            4.0,
            0.5,
          ],
        ),
        debugName: 'zip.exr',
        format: ViewerEnvironmentFileFormat.exr,
      ),
      throwsA(
        isA<HdrEnvironmentDecodeException>().having(
          (error) => error.diagnostic.code,
          'diagnostic code',
          ViewerDiagnosticCode.environmentUnsupportedEncoding,
        ),
      ),
    );
  });

  test('reports truncated environment files as decode failures', () {
    expect(
      () => HdrEnvironmentDecoder.decode(
        Uint8List.fromList(<int>[0x76, 0x2f, 0x31, 0x01]),
        debugName: 'broken.exr',
        format: ViewerEnvironmentFileFormat.exr,
      ),
      throwsA(
        isA<HdrEnvironmentDecodeException>().having(
          (error) => error.diagnostic.code,
          'diagnostic code',
          ViewerDiagnosticCode.environmentDecodeFailure,
        ),
      ),
    );
  });
}

Uint8List _radianceHdr({
  required int width,
  required int height,
  required List<int> rgbe,
}) {
  final bytes = BytesBuilder();
  bytes.add(
    '#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y $height +X $width\n'.codeUnits,
  );
  bytes.add(rgbe);
  return bytes.toBytes();
}

Uint8List _openExr({
  required int width,
  required int height,
  int compression = 0,
  required List<double> pixels,
}) {
  final bytes = BytesBuilder();
  void addU8(int value) => bytes.add(<int>[value & 0xff]);
  void addU32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void addI32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void addU64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void addCString(String value) {
    bytes.add(value.codeUnits);
    addU8(0);
  }

  void addAttribute(String name, String type, Uint8List value) {
    addCString(name);
    addCString(type);
    addU32(value.length);
    bytes.add(value);
  }

  Uint8List makeValue(void Function(BytesBuilder out) write) {
    final out = BytesBuilder();
    write(out);
    return out.toBytes();
  }

  Uint8List box2i(int minX, int minY, int maxX, int maxY) {
    return makeValue((out) {
      void writeI32(int value) {
        final data = ByteData(4)..setInt32(0, value, Endian.little);
        out.add(data.buffer.asUint8List());
      }

      writeI32(minX);
      writeI32(minY);
      writeI32(maxX);
      writeI32(maxY);
    });
  }

  Uint8List chlist() {
    return makeValue((out) {
      void writeChannel(String name) {
        out.add(name.codeUnits);
        out.add(<int>[0]);
        final data = ByteData(16)
          ..setInt32(0, 2, Endian.little)
          ..setUint8(4, 0)
          ..setUint8(5, 0)
          ..setUint8(6, 0)
          ..setUint8(7, 0)
          ..setInt32(8, 1, Endian.little)
          ..setInt32(12, 1, Endian.little);
        out.add(data.buffer.asUint8List());
      }

      writeChannel('R');
      writeChannel('G');
      writeChannel('B');
      writeChannel('A');
      out.add(<int>[0]);
    });
  }

  bytes.add(<int>[0x76, 0x2f, 0x31, 0x01]);
  addU32(2);
  addAttribute('channels', 'chlist', chlist());
  addAttribute(
      'compression',
      'compression',
      Uint8List.fromList(<int>[
        compression,
      ]));
  addAttribute('dataWindow', 'box2i', box2i(0, 0, width - 1, height - 1));
  addAttribute('displayWindow', 'box2i', box2i(0, 0, width - 1, height - 1));
  addU8(0);

  for (var y = 0; y < height; y += 1) {
    addU64(0);
  }

  for (var y = 0; y < height; y += 1) {
    final chunk = BytesBuilder();
    void addChunkF32(double value) {
      final data = ByteData(4)..setFloat32(0, value, Endian.little);
      chunk.add(data.buffer.asUint8List());
    }

    for (final channelOffset in const <int>[0, 1, 2, 3]) {
      for (var x = 0; x < width; x += 1) {
        final pixelOffset = (y * width + x) * 4;
        addChunkF32(pixels[pixelOffset + channelOffset]);
      }
    }

    addI32(y);
    addU32(chunk.length);
    bytes.add(chunk.toBytes());
  }

  return bytes.toBytes();
}
