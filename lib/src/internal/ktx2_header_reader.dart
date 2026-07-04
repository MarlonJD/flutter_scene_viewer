import 'dart:typed_data';

const List<int> _ktx2Identifier = <int>[
  0xAB,
  0x4B,
  0x54,
  0x58,
  0x20,
  0x32,
  0x30,
  0xBB,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

final class Ktx2HeaderRead {
  const Ktx2HeaderRead.valid(this.header) : error = null;
  const Ktx2HeaderRead.invalid(this.error) : header = null;

  final Ktx2Header? header;
  final String? error;

  bool get isValid => header != null;
}

final class Ktx2Header {
  const Ktx2Header({
    required this.vkFormat,
    required this.typeSize,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.pixelDepth,
    required this.layerCount,
    required this.faceCount,
    required this.levelCount,
    required this.supercompressionScheme,
  });

  final int vkFormat;
  final int typeSize;
  final int pixelWidth;
  final int pixelHeight;
  final int pixelDepth;
  final int layerCount;
  final int faceCount;
  final int levelCount;
  final int supercompressionScheme;

  bool get requiresBasisuTranscode =>
      vkFormat == 0 || supercompressionScheme == 1;

  String get supercompression => switch (supercompressionScheme) {
        0 => 'none',
        1 => 'basisLz',
        2 => 'zstandard',
        3 => 'zlib',
        _ => 'unknown',
      };

  Map<String, Object?> toDetails({
    int? imageIndex,
    int? bufferViewIndex,
  }) {
    return <String, Object?>{
      'headerStatus': 'valid',
      if (imageIndex != null) 'imageIndex': imageIndex,
      if (bufferViewIndex != null) 'bufferViewIndex': bufferViewIndex,
      'vkFormat': vkFormat,
      'typeSize': typeSize,
      'pixelWidth': pixelWidth,
      'pixelHeight': pixelHeight,
      'pixelDepth': pixelDepth,
      'layerCount': layerCount,
      'faceCount': faceCount,
      'levelCount': levelCount,
      'supercompressionScheme': supercompressionScheme,
      'supercompression': supercompression,
    };
  }
}

Ktx2HeaderRead readKtx2Header(Uint8List bytes) {
  if (bytes.lengthInBytes < 48) {
    return const Ktx2HeaderRead.invalid(
      'KTX2 header is shorter than 48 bytes.',
    );
  }
  for (var index = 0; index < _ktx2Identifier.length; index += 1) {
    if (bytes[index] != _ktx2Identifier[index]) {
      return const Ktx2HeaderRead.invalid('KTX2 identifier is invalid.');
    }
  }
  final data = ByteData.sublistView(bytes);
  return Ktx2HeaderRead.valid(
    Ktx2Header(
      vkFormat: data.getUint32(12, Endian.little),
      typeSize: data.getUint32(16, Endian.little),
      pixelWidth: data.getUint32(20, Endian.little),
      pixelHeight: data.getUint32(24, Endian.little),
      pixelDepth: data.getUint32(28, Endian.little),
      layerCount: data.getUint32(32, Endian.little),
      faceCount: data.getUint32(36, Endian.little),
      levelCount: data.getUint32(40, Endian.little),
      supercompressionScheme: data.getUint32(44, Endian.little),
    ),
  );
}

Map<String, Object?> ktx2UnsupportedDetails(
  Uint8List bytes, {
  int? imageIndex,
  int? bufferViewIndex,
}) {
  final read = readKtx2Header(bytes);
  final header = read.header;
  if (header == null) {
    return <String, Object?>{
      'status': 'ktx2HeaderInvalid',
      'reason': 'KTX2 texture header could not be parsed.',
      'nextStep':
          'Provide a PNG/JPEG fallback or add a real KTX2/BasisU transcoder before enabling this texture.',
      'ktx2': <String, Object?>{
        'headerStatus': 'invalid',
        if (imageIndex != null) 'imageIndex': imageIndex,
        if (bufferViewIndex != null) 'bufferViewIndex': bufferViewIndex,
        'reason': read.error,
      },
    };
  }
  return <String, Object?>{
    'status': header.requiresBasisuTranscode
        ? 'basisuTranscodeUnavailable'
        : 'ktx2TranscodeUnavailable',
    'reason': header.requiresBasisuTranscode
        ? 'KHR_texture_basisu requires Basis Universal ETC1S/UASTC transcode support, which is not available in the current Flutter GPU / flutter_scene runtime import path.'
        : 'KTX2 texture upload/transcode support is not available for imported glTF material textures in the current runtime path.',
    'nextStep': header.requiresBasisuTranscode
        ? 'Provide PNG/JPEG fallback images, or add an optional BasisU transcoder plugin/upstream flutter_scene import support before marking KHR_texture_basisu supported.'
        : 'Convert the texture to PNG/JPEG or add a runtime KTX2 upload/transcode path before marking this texture supported.',
    'ktx2': header.toDetails(
      imageIndex: imageIndex,
      bufferViewIndex: bufferViewIndex,
    ),
  };
}
