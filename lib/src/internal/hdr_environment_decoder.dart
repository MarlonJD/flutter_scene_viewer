import 'dart:math' as math;
import 'dart:typed_data';

import '../diagnostics.dart';
import '../viewer_environment.dart';

/// Decoded linear equirectangular HDR pixels for environment lighting.
final class DecodedHdrEnvironment {
  const DecodedHdrEnvironment({
    required this.linearPixels,
    required this.width,
    required this.height,
  });

  final Float32List linearPixels;
  final int width;
  final int height;
}

/// Exception carrying the typed viewer diagnostic for decoder failures.
final class HdrEnvironmentDecodeException implements Exception {
  const HdrEnvironmentDecodeException(this.diagnostic);

  final ViewerDiagnostic diagnostic;

  @override
  String toString() => diagnostic.toString();
}

/// Minimal environment-only decoder for raw HDRI source files.
final class HdrEnvironmentDecoder {
  const HdrEnvironmentDecoder._();

  static DecodedHdrEnvironment decode(
    Uint8List bytes, {
    required String debugName,
    ViewerEnvironmentFileFormat format = ViewerEnvironmentFileFormat.auto,
  }) {
    try {
      final resolved = _resolveFormat(bytes, debugName, format);
      return switch (resolved) {
        ViewerEnvironmentFileFormat.hdr => _decodeRadianceHdr(
            bytes,
            debugName,
          ),
        ViewerEnvironmentFileFormat.exr => _decodeOpenExr(bytes, debugName),
        ViewerEnvironmentFileFormat.auto => throw _exception(
            ViewerDiagnosticCode.environmentUnsupportedEncoding,
            'Unsupported HDR environment encoding.',
            debugName,
            <String, Object?>{'format': format.name},
          ),
      };
    } on HdrEnvironmentDecodeException {
      rethrow;
    } on Object catch (error) {
      throw _exception(
        ViewerDiagnosticCode.environmentDecodeFailure,
        'Failed to decode HDR environment pixels.',
        debugName,
        <String, Object?>{'error': error.toString()},
      );
    }
  }

  static ViewerEnvironmentFileFormat _resolveFormat(
    Uint8List bytes,
    String debugName,
    ViewerEnvironmentFileFormat requested,
  ) {
    if (requested != ViewerEnvironmentFileFormat.auto) {
      return requested;
    }
    final lowerName = debugName.toLowerCase();
    if (lowerName.endsWith('.hdr')) {
      return ViewerEnvironmentFileFormat.hdr;
    }
    if (lowerName.endsWith('.exr')) {
      return ViewerEnvironmentFileFormat.exr;
    }
    if (_startsWith(bytes, const <int>[0x23, 0x3f])) {
      return ViewerEnvironmentFileFormat.hdr;
    }
    if (_startsWith(bytes, const <int>[0x76, 0x2f, 0x31, 0x01])) {
      return ViewerEnvironmentFileFormat.exr;
    }
    throw _exception(
      ViewerDiagnosticCode.environmentUnsupportedEncoding,
      'Unsupported HDR environment encoding.',
      debugName,
      const <String, Object?>{},
    );
  }

  static DecodedHdrEnvironment _decodeRadianceHdr(
    Uint8List bytes,
    String debugName,
  ) {
    var offset = 0;
    final magic = _readAsciiLine(bytes, offset);
    offset = magic.nextOffset;
    if (!magic.value.startsWith('#?RADIANCE') &&
        !magic.value.startsWith('#?RGBE')) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'Radiance HDR environment must start with a Radiance signature.',
        debugName,
        <String, Object?>{'signature': magic.value},
      );
    }

    var hasRgbFormat = false;
    while (true) {
      final line = _readAsciiLine(bytes, offset);
      offset = line.nextOffset;
      if (line.value.isEmpty) {
        break;
      }
      if (line.value == 'FORMAT=32-bit_rle_rgbe') {
        hasRgbFormat = true;
      }
    }
    if (!hasRgbFormat) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'Radiance HDR environment must use 32-bit RGBE pixels.',
        debugName,
        const <String, Object?>{},
      );
    }

    final resolution = _readAsciiLine(bytes, offset);
    offset = resolution.nextOffset;
    final match =
        RegExp(r'^-Y\s+(\d+)\s+\+X\s+(\d+)$').firstMatch(resolution.value);
    if (match == null) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'Radiance HDR environment orientation is unsupported.',
        debugName,
        <String, Object?>{'resolution': resolution.value},
      );
    }
    final height = int.parse(match.group(1)!);
    final width = int.parse(match.group(2)!);
    _validateDimensions(width, height, debugName);

    final pixels = Float32List(width * height * 4);
    if (_usesRadianceRle(bytes, offset, width)) {
      offset = _decodeRadianceRle(bytes, offset, width, height, pixels);
    } else {
      final expectedLength = width * height * 4;
      if (bytes.lengthInBytes - offset < expectedLength) {
        throw StateError('Radiance HDR pixel data is truncated.');
      }
      for (var pixel = 0; pixel < width * height; pixel += 1) {
        _writeRgbePixel(
          pixels,
          pixel * 4,
          bytes[offset + pixel * 4],
          bytes[offset + pixel * 4 + 1],
          bytes[offset + pixel * 4 + 2],
          bytes[offset + pixel * 4 + 3],
        );
      }
      offset += expectedLength;
    }
    if (offset > bytes.lengthInBytes) {
      throw StateError('Radiance HDR pixel data is truncated.');
    }
    return DecodedHdrEnvironment(
      linearPixels: pixels,
      width: width,
      height: height,
    );
  }

  static bool _usesRadianceRle(Uint8List bytes, int offset, int width) {
    if (width < 8 || width > 0x7fff || offset + 4 > bytes.lengthInBytes) {
      return false;
    }
    return bytes[offset] == 2 &&
        bytes[offset + 1] == 2 &&
        bytes[offset + 2] == (width >> 8) &&
        bytes[offset + 3] == (width & 0xff);
  }

  static int _decodeRadianceRle(
    Uint8List bytes,
    int offset,
    int width,
    int height,
    Float32List pixels,
  ) {
    final scanline = Uint8List(width * 4);
    for (var y = 0; y < height; y += 1) {
      if (offset + 4 > bytes.lengthInBytes ||
          bytes[offset] != 2 ||
          bytes[offset + 1] != 2 ||
          bytes[offset + 2] != (width >> 8) ||
          bytes[offset + 3] != (width & 0xff)) {
        throw StateError('Radiance HDR RLE scanline header is invalid.');
      }
      offset += 4;
      for (var channel = 0; channel < 4; channel += 1) {
        var x = 0;
        while (x < width) {
          if (offset >= bytes.lengthInBytes) {
            throw StateError('Radiance HDR RLE channel is truncated.');
          }
          final count = bytes[offset];
          offset += 1;
          if (count == 0) {
            throw StateError('Radiance HDR RLE count is invalid.');
          }
          if (count > 128) {
            final runLength = count - 128;
            if (offset >= bytes.lengthInBytes || x + runLength > width) {
              throw StateError('Radiance HDR RLE run is invalid.');
            }
            final value = bytes[offset];
            offset += 1;
            for (var i = 0; i < runLength; i += 1) {
              scanline[(x + i) * 4 + channel] = value;
            }
            x += runLength;
          } else {
            if (offset + count > bytes.lengthInBytes || x + count > width) {
              throw StateError('Radiance HDR RLE literal is invalid.');
            }
            for (var i = 0; i < count; i += 1) {
              scanline[(x + i) * 4 + channel] = bytes[offset + i];
            }
            offset += count;
            x += count;
          }
        }
      }
      for (var x = 0; x < width; x += 1) {
        final rgbeOffset = x * 4;
        _writeRgbePixel(
          pixels,
          (y * width + x) * 4,
          scanline[rgbeOffset],
          scanline[rgbeOffset + 1],
          scanline[rgbeOffset + 2],
          scanline[rgbeOffset + 3],
        );
      }
    }
    return offset;
  }

  static void _writeRgbePixel(
    Float32List pixels,
    int offset,
    int r,
    int g,
    int b,
    int e,
  ) {
    if (e == 0) {
      pixels[offset] = 0;
      pixels[offset + 1] = 0;
      pixels[offset + 2] = 0;
    } else {
      final scale = math.pow(2, e - 136).toDouble();
      pixels[offset] = r * scale;
      pixels[offset + 1] = g * scale;
      pixels[offset + 2] = b * scale;
    }
    pixels[offset + 3] = 1;
  }

  static DecodedHdrEnvironment _decodeOpenExr(
    Uint8List bytes,
    String debugName,
  ) {
    final reader = _ByteReader(bytes);
    final magic = reader.readUint32();
    if (magic != 0x01312f76) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'OpenEXR environment must start with the EXR signature.',
        debugName,
        <String, Object?>{'signature': magic},
      );
    }
    final version = reader.readUint32() & 0xff;
    if (version != 2) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'Only OpenEXR version 2 scanline files are supported.',
        debugName,
        <String, Object?>{'version': version},
      );
    }

    var compression = -1;
    _Box2i? dataWindow;
    var channels = const <_ExrChannel>[];
    while (true) {
      final name = reader.readCString();
      if (name.isEmpty) {
        break;
      }
      final type = reader.readCString();
      final size = reader.readInt32();
      final value = reader.readBytes(size);
      if (name == 'compression' && type == 'compression' && value.isNotEmpty) {
        compression = value[0];
      } else if (name == 'dataWindow' && type == 'box2i') {
        dataWindow = _readBox2i(value);
      } else if (name == 'channels' && type == 'chlist') {
        channels = _readChannels(value);
      }
    }

    if (compression != 0) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'Only uncompressed OpenEXR environments are supported.',
        debugName,
        <String, Object?>{'compression': compression},
      );
    }
    if (dataWindow == null) {
      throw _exception(
        ViewerDiagnosticCode.environmentInvalidDimensions,
        'OpenEXR environment is missing a dataWindow.',
        debugName,
        const <String, Object?>{},
      );
    }
    final width = dataWindow.maxX - dataWindow.minX + 1;
    final height = dataWindow.maxY - dataWindow.minY + 1;
    _validateDimensions(width, height, debugName);

    final rgbChannels = <String, _ExrChannel>{
      for (final channel in channels) channel.name: channel,
    };
    if (!rgbChannels.containsKey('R') ||
        !rgbChannels.containsKey('G') ||
        !rgbChannels.containsKey('B')) {
      throw _exception(
        ViewerDiagnosticCode.environmentUnsupportedEncoding,
        'OpenEXR environment must include R, G, and B channels.',
        debugName,
        <String, Object?>{'channels': rgbChannels.keys.toList()},
      );
    }
    for (final channel in channels) {
      if (channel.pixelType != _ExrPixelType.float &&
          channel.pixelType != _ExrPixelType.half) {
        throw _exception(
          ViewerDiagnosticCode.environmentUnsupportedEncoding,
          'OpenEXR environment channel type is unsupported.',
          debugName,
          <String, Object?>{
            'channel': channel.name,
            'pixelType': channel.pixelType.index,
          },
        );
      }
      if (channel.xSampling != 1 || channel.ySampling != 1) {
        throw _exception(
          ViewerDiagnosticCode.environmentUnsupportedEncoding,
          'OpenEXR environment channel subsampling is unsupported.',
          debugName,
          <String, Object?>{'channel': channel.name},
        );
      }
    }

    reader.skip(height * 8);
    final pixels = Float32List(width * height * 4);
    for (var i = 0; i < width * height; i += 1) {
      pixels[i * 4 + 3] = 1;
    }
    for (var scanline = 0; scanline < height; scanline += 1) {
      final y = reader.readInt32();
      final dataSize = reader.readInt32();
      final chunkEnd = reader.offset + dataSize;
      if (y < dataWindow.minY || y > dataWindow.maxY) {
        throw StateError('OpenEXR scanline is outside the dataWindow.');
      }
      for (final channel in channels) {
        for (var x = 0; x < width; x += 1) {
          final value = switch (channel.pixelType) {
            _ExrPixelType.half => _halfToDouble(reader.readUint16()),
            _ExrPixelType.float => reader.readFloat32(),
            _ExrPixelType.uint => reader.readUint32().toDouble(),
          };
          final component = switch (channel.name) {
            'R' => 0,
            'G' => 1,
            'B' => 2,
            'A' => 3,
            _ => -1,
          };
          if (component != -1) {
            final pixelOffset = ((y - dataWindow.minY) * width + x) * 4;
            pixels[pixelOffset + component] = value;
          }
        }
      }
      if (reader.offset > chunkEnd) {
        throw StateError('OpenEXR scanline chunk is longer than declared.');
      }
      reader.offset = chunkEnd;
    }
    return DecodedHdrEnvironment(
      linearPixels: pixels,
      width: width,
      height: height,
    );
  }

  static _Box2i _readBox2i(Uint8List value) {
    final reader = _ByteReader(value);
    return _Box2i(
      minX: reader.readInt32(),
      minY: reader.readInt32(),
      maxX: reader.readInt32(),
      maxY: reader.readInt32(),
    );
  }

  static List<_ExrChannel> _readChannels(Uint8List value) {
    final reader = _ByteReader(value);
    final channels = <_ExrChannel>[];
    while (reader.offset < value.lengthInBytes) {
      final name = reader.readCString();
      if (name.isEmpty) {
        break;
      }
      final pixelType = reader.readInt32();
      reader.skip(4);
      channels.add(
        _ExrChannel(
          name: name,
          pixelType: _ExrPixelType.values[pixelType],
          xSampling: reader.readInt32(),
          ySampling: reader.readInt32(),
        ),
      );
    }
    return List<_ExrChannel>.unmodifiable(channels);
  }

  static void _validateDimensions(int width, int height, String debugName) {
    if (width <= 0 || height <= 0 || width != height * 2) {
      throw _exception(
        ViewerDiagnosticCode.environmentInvalidDimensions,
        'HDR environment must be a positive 2:1 equirectangular image.',
        debugName,
        <String, Object?>{'width': width, 'height': height},
      );
    }
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.lengthInBytes < prefix.length) {
      return false;
    }
    for (var index = 0; index < prefix.length; index += 1) {
      if (bytes[index] != prefix[index]) {
        return false;
      }
    }
    return true;
  }

  static _AsciiLine _readAsciiLine(Uint8List bytes, int offset) {
    if (offset >= bytes.lengthInBytes) {
      throw StateError('Unexpected end of text header.');
    }
    var end = offset;
    while (end < bytes.lengthInBytes && bytes[end] != 0x0a) {
      end += 1;
    }
    var lineEnd = end;
    if (lineEnd > offset && bytes[lineEnd - 1] == 0x0d) {
      lineEnd -= 1;
    }
    return _AsciiLine(
      String.fromCharCodes(bytes.sublist(offset, lineEnd)),
      end == bytes.lengthInBytes ? end : end + 1,
    );
  }

  static double _halfToDouble(int half) {
    final sign = (half & 0x8000) == 0 ? 1.0 : -1.0;
    final exponent = (half >> 10) & 0x1f;
    final fraction = half & 0x03ff;
    if (exponent == 0) {
      if (fraction == 0) {
        return sign * 0.0;
      }
      return sign * math.pow(2, -14).toDouble() * (fraction / 1024.0);
    }
    if (exponent == 0x1f) {
      return fraction == 0 ? sign * double.infinity : double.nan;
    }
    return sign *
        math.pow(2, exponent - 15).toDouble() *
        (1.0 + fraction / 1024.0);
  }

  static HdrEnvironmentDecodeException _exception(
    ViewerDiagnosticCode code,
    String message,
    String debugName,
    Map<String, Object?> details,
  ) {
    return HdrEnvironmentDecodeException(
      ViewerDiagnostic(
        code: code,
        message: message,
        details: <String, Object?>{
          'source': debugName,
          ...details,
        },
      ),
    );
  }
}

final class _AsciiLine {
  const _AsciiLine(this.value, this.nextOffset);

  final String value;
  final int nextOffset;
}

final class _Box2i {
  const _Box2i({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final int minX;
  final int minY;
  final int maxX;
  final int maxY;
}

enum _ExrPixelType { uint, half, float }

final class _ExrChannel {
  const _ExrChannel({
    required this.name,
    required this.pixelType,
    required this.xSampling,
    required this.ySampling,
  });

  final String name;
  final _ExrPixelType pixelType;
  final int xSampling;
  final int ySampling;
}

final class _ByteReader {
  _ByteReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  Uint8List readBytes(int count) {
    _ensure(count);
    final value = Uint8List.sublistView(bytes, offset, offset + count);
    offset += count;
    return value;
  }

  String readCString() {
    final start = offset;
    while (offset < bytes.lengthInBytes && bytes[offset] != 0) {
      offset += 1;
    }
    _ensure(1);
    final value = String.fromCharCodes(bytes.sublist(start, offset));
    offset += 1;
    return value;
  }

  int readUint16() {
    _ensure(2);
    final value = ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.little);
    offset += 2;
    return value;
  }

  int readUint32() {
    _ensure(4);
    final value = ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
    offset += 4;
    return value;
  }

  int readInt32() {
    _ensure(4);
    final value = ByteData.sublistView(bytes, offset, offset + 4)
        .getInt32(0, Endian.little);
    offset += 4;
    return value;
  }

  double readFloat32() {
    _ensure(4);
    final value = ByteData.sublistView(bytes, offset, offset + 4)
        .getFloat32(0, Endian.little);
    offset += 4;
    return value;
  }

  void skip(int count) {
    _ensure(count);
    offset += count;
  }

  void _ensure(int count) {
    if (count < 0 || offset + count > bytes.lengthInBytes) {
      throw StateError('Unexpected end of HDR environment data.');
    }
  }
}
