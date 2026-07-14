import 'dart:math' as math;
import 'dart:typed_data';

enum MeshoptCompressionMode {
  attributes,
  triangles,
  indices;

  static MeshoptCompressionMode? fromJson(Object? value) {
    return switch (value) {
      'ATTRIBUTES' => MeshoptCompressionMode.attributes,
      'TRIANGLES' => MeshoptCompressionMode.triangles,
      'INDICES' => MeshoptCompressionMode.indices,
      _ => null,
    };
  }
}

enum MeshoptCompressionFilter {
  none,
  octahedral,
  quaternion,
  exponential;

  static MeshoptCompressionFilter? fromJson(Object? value) {
    return switch (value) {
      null || 'NONE' => MeshoptCompressionFilter.none,
      'OCTAHEDRAL' => MeshoptCompressionFilter.octahedral,
      'QUATERNION' => MeshoptCompressionFilter.quaternion,
      'EXPONENTIAL' => MeshoptCompressionFilter.exponential,
      _ => null,
    };
  }
}

final class MeshoptDecodeException implements Exception {
  const MeshoptDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cooperative deadline control for the synchronous pure-Dart Meshopt path.
///
/// [checkInterval] is interpreted as approximate decoded output bytes between
/// elapsed-time reads. It is not an external cancellation signal.
final class MeshoptDecodeControl {
  MeshoptDecodeControl({
    required this.timeout,
    required this.checkInterval,
    required Duration Function() elapsed,
  }) : _elapsed = elapsed {
    if (timeout.isNegative) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    if (checkInterval <= 0) {
      throw ArgumentError.value(
        checkInterval,
        'checkInterval',
        'must be positive',
      );
    }
  }

  factory MeshoptDecodeControl.running({
    required Duration timeout,
    required int checkInterval,
  }) {
    final stopwatch = Stopwatch()..start();
    return MeshoptDecodeControl(
      timeout: timeout,
      checkInterval: checkInterval,
      elapsed: () => stopwatch.elapsed,
    );
  }

  final Duration timeout;
  final int checkInterval;
  final Duration Function() _elapsed;
  int _workSinceCheck = 0;

  void checkpoint({
    required String stage,
    int decodedBytes = 0,
    bool force = false,
  }) {
    if (decodedBytes < 0) {
      throw ArgumentError.value(
        decodedBytes,
        'decodedBytes',
        'must not be negative',
      );
    }
    if (!force && decodedBytes < checkInterval - _workSinceCheck) {
      _workSinceCheck += decodedBytes;
      return;
    }
    _workSinceCheck = 0;
    if (_elapsed() >= timeout) {
      throw MeshoptDecodeDeadlineExceeded(stage: stage, timeout: timeout);
    }
  }
}

final class MeshoptDecodeDeadlineExceeded implements Exception {
  const MeshoptDecodeDeadlineExceeded({
    required this.stage,
    required this.timeout,
  });

  final String stage;
  final Duration timeout;

  @override
  String toString() =>
      'Meshopt decode exceeded ${timeout.inMicroseconds} us at $stage.';
}

const int _vertexHeader = 0xa0;
const int _indexHeader = 0xe0;
const int _sequenceHeader = 0xd0;
const int _decodeVertexVersion = 1;
const int _decodeIndexVersion = 1;
const int _vertexBlockSizeBytes = 8192;
const int _vertexBlockMaxSize = 256;
const int _byteGroupSize = 16;
const int _tailMinSizeV0 = 32;
const int _tailMinSizeV1 = 24;
const List<int> _bitsV0 = <int>[0, 2, 4, 8];
const List<int> _bitsV1 = <int>[0, 1, 2, 4, 8];

Uint8List decodeMeshoptGltfBuffer(
  Uint8List source, {
  required int count,
  required int byteStride,
  required MeshoptCompressionMode mode,
  required MeshoptCompressionFilter filter,
  MeshoptDecodeControl? control,
}) {
  if (count < 0 || byteStride <= 0) {
    throw const MeshoptDecodeException('Invalid meshopt count or byteStride.');
  }
  control?.checkpoint(stage: 'meshoptDecodeStart', force: true);
  final decoded = switch (mode) {
    MeshoptCompressionMode.attributes => _decodeVertexBuffer(
        source,
        vertexCount: count,
        vertexSize: byteStride,
        control: control,
      ),
    MeshoptCompressionMode.triangles => _decodeIndexBuffer(
        source,
        indexCount: count,
        indexSize: byteStride,
        control: control,
      ),
    MeshoptCompressionMode.indices => _decodeIndexSequence(
        source,
        indexCount: count,
        indexSize: byteStride,
        control: control,
      ),
  };
  _applyFilter(
    decoded,
    count: count,
    byteStride: byteStride,
    filter: filter,
    control: control,
  );
  control?.checkpoint(stage: 'meshoptDecodeComplete', force: true);
  return decoded;
}

Uint8List _decodeVertexBuffer(
  Uint8List source, {
  required int vertexCount,
  required int vertexSize,
  required MeshoptDecodeControl? control,
}) {
  if (vertexSize <= 0 || vertexSize > 256 || vertexSize % 4 != 0) {
    throw const MeshoptDecodeException(
      'ATTRIBUTES byteStride must be a positive multiple of 4 up to 256.',
    );
  }
  if (source.isEmpty) {
    throw const MeshoptDecodeException('ATTRIBUTES stream is empty.');
  }
  final header = source[0];
  if ((header & 0xf0) != _vertexHeader) {
    throw const MeshoptDecodeException('ATTRIBUTES stream header is invalid.');
  }
  final version = header & 0x0f;
  if (version > _decodeVertexVersion) {
    throw const MeshoptDecodeException(
      'ATTRIBUTES stream version is not supported.',
    );
  }

  final tailSize = vertexSize + (version == 0 ? 0 : vertexSize ~/ 4);
  final tailSizeMin = version == 0 ? _tailMinSizeV0 : _tailMinSizeV1;
  final tailSizePad = math.max(tailSize, tailSizeMin);
  if (source.lengthInBytes < 1 + tailSizePad) {
    throw const MeshoptDecodeException('ATTRIBUTES stream is truncated.');
  }

  final tailOffset = source.lengthInBytes - tailSize;
  final lastVertex = Uint8List.fromList(
    source.sublist(tailOffset, tailOffset + vertexSize),
  );
  final channels = version == 0
      ? null
      : source.sublist(tailOffset + vertexSize, tailOffset + tailSize);
  final target = Uint8List(vertexCount * vertexSize);
  final blockSize = _vertexBlockSize(vertexSize);
  var dataOffset = 1;
  final dataEnd = source.lengthInBytes - tailSizePad;
  for (var vertexOffset = 0;
      vertexOffset < vertexCount;
      vertexOffset += blockSize) {
    final blockVertexCount = math.min(blockSize, vertexCount - vertexOffset);
    control?.checkpoint(
      stage: 'meshoptAttributes',
      decodedBytes: blockVertexCount * vertexSize,
    );
    dataOffset = _decodeVertexBlock(
      source,
      dataOffset: dataOffset,
      dataEnd: dataEnd,
      target: target,
      targetOffset: vertexOffset * vertexSize,
      vertexCount: blockVertexCount,
      vertexSize: vertexSize,
      lastVertex: lastVertex,
      channels: channels,
      version: version,
    );
  }
  if (dataOffset != dataEnd) {
    throw const MeshoptDecodeException(
      'ATTRIBUTES stream contains trailing compressed data.',
    );
  }
  return target;
}

int _decodeVertexBlock(
  Uint8List source, {
  required int dataOffset,
  required int dataEnd,
  required Uint8List target,
  required int targetOffset,
  required int vertexCount,
  required int vertexSize,
  required Uint8List lastVertex,
  required Uint8List? channels,
  required int version,
}) {
  final vertexCountAligned = _align(vertexCount, _byteGroupSize);
  final buffer = Uint8List(vertexCountAligned * 4);
  final controlSize = version == 0 ? 0 : vertexSize ~/ 4;
  if (dataOffset + controlSize > dataEnd) {
    throw const MeshoptDecodeException(
        'ATTRIBUTES block control is truncated.');
  }
  final control = source.sublist(dataOffset, dataOffset + controlSize);
  dataOffset += controlSize;

  for (var k = 0; k < vertexSize; k += 4) {
    final controlByte = version == 0 ? 0 : control[k ~/ 4];
    for (var j = 0; j < 4; j += 1) {
      final ctrl = (controlByte >> (j * 2)) & 3;
      final bufferOffset = j * vertexCount;
      if (ctrl == 3) {
        if (dataOffset + vertexCount > dataEnd) {
          throw const MeshoptDecodeException(
            'ATTRIBUTES literal block is truncated.',
          );
        }
        buffer.setRange(
          bufferOffset,
          bufferOffset + vertexCount,
          source,
          dataOffset,
        );
        dataOffset += vertexCount;
      } else if (ctrl == 2) {
        for (var index = 0; index < vertexCount; index += 1) {
          buffer[bufferOffset + index] = 0;
        }
      } else {
        final bits = version == 0 ? _bitsV0 : _bitsV1.sublist(ctrl);
        dataOffset = _decodeBytes(
          source,
          dataOffset: dataOffset,
          dataEnd: dataEnd,
          output: buffer,
          outputOffset: bufferOffset,
          bufferSize: vertexCountAligned,
          bits: bits,
        );
      }
    }

    final channel = version == 0 ? 0 : channels![k ~/ 4];
    _decodeDeltas(
      buffer,
      target,
      targetOffset: targetOffset + k,
      vertexCount: vertexCount,
      vertexSize: vertexSize,
      lastVertex: lastVertex,
      lastVertexOffset: k,
      channel: channel,
    );
  }

  lastVertex.setRange(
    0,
    vertexSize,
    target,
    targetOffset + (vertexCount - 1) * vertexSize,
  );
  return dataOffset;
}

int _decodeBytes(
  Uint8List source, {
  required int dataOffset,
  required int dataEnd,
  required Uint8List output,
  required int outputOffset,
  required int bufferSize,
  required List<int> bits,
}) {
  final groupCount = bufferSize ~/ _byteGroupSize;
  final headerSize = (groupCount + 3) ~/ 4;
  if (dataOffset + headerSize > dataEnd) {
    throw const MeshoptDecodeException('ATTRIBUTES byte header is truncated.');
  }
  final headerOffset = dataOffset;
  dataOffset += headerSize;
  for (var offset = 0; offset < bufferSize; offset += _byteGroupSize) {
    final headerIndex = offset ~/ _byteGroupSize;
    final bitsIndex =
        (source[headerOffset + headerIndex ~/ 4] >> ((headerIndex % 4) * 2)) &
            3;
    dataOffset = _decodeBytesGroup(
      source,
      dataOffset: dataOffset,
      dataEnd: dataEnd,
      output: output,
      outputOffset: outputOffset + offset,
      bits: bits[bitsIndex],
    );
  }
  return dataOffset;
}

int _decodeBytesGroup(
  Uint8List source, {
  required int dataOffset,
  required int dataEnd,
  required Uint8List output,
  required int outputOffset,
  required int bits,
}) {
  if (bits == 0) {
    for (var index = 0; index < _byteGroupSize; index += 1) {
      output[outputOffset + index] = 0;
    }
    return dataOffset;
  }
  if (bits == 8) {
    if (dataOffset + _byteGroupSize > dataEnd) {
      throw const MeshoptDecodeException('ATTRIBUTES byte group is truncated.');
    }
    output.setRange(
      outputOffset,
      outputOffset + _byteGroupSize,
      source,
      dataOffset,
    );
    return dataOffset + _byteGroupSize;
  }

  final packedBytes = switch (bits) {
    1 => 2,
    2 => 4,
    4 => 8,
    _ => throw const MeshoptDecodeException(
        'ATTRIBUTES byte group bit width is invalid.',
      ),
  };
  if (dataOffset + packedBytes > dataEnd) {
    throw const MeshoptDecodeException('ATTRIBUTES byte group is truncated.');
  }
  var variableOffset = dataOffset + packedBytes;
  var out = outputOffset;
  final sentinel = (1 << bits) - 1;
  for (var packedIndex = 0; packedIndex < packedBytes; packedIndex += 1) {
    final packed = source[dataOffset + packedIndex];
    final valuesPerByte = 8 ~/ bits;
    for (var valueIndex = 0; valueIndex < valuesPerByte; valueIndex += 1) {
      final encoded = bits == 1
          ? (packed >> valueIndex) & 1
          : (packed >> (8 - bits * (valueIndex + 1))) & sentinel;
      if (encoded == sentinel) {
        if (variableOffset >= dataEnd) {
          throw const MeshoptDecodeException(
            'ATTRIBUTES byte group sentinel data is truncated.',
          );
        }
        output[out] = source[variableOffset];
        variableOffset += 1;
      } else {
        output[out] = encoded;
      }
      out += 1;
    }
  }
  return variableOffset;
}

void _decodeDeltas(
  Uint8List buffer,
  Uint8List target, {
  required int targetOffset,
  required int vertexCount,
  required int vertexSize,
  required Uint8List lastVertex,
  required int lastVertexOffset,
  required int channel,
}) {
  switch (channel & 3) {
    case 0:
      _decodeDeltaElements(
        buffer,
        target,
        targetOffset: targetOffset,
        vertexCount: vertexCount,
        vertexSize: vertexSize,
        lastVertex: lastVertex,
        lastVertexOffset: lastVertexOffset,
        elementSize: 1,
        xor: false,
        rotateBits: 0,
      );
    case 1:
      _decodeDeltaElements(
        buffer,
        target,
        targetOffset: targetOffset,
        vertexCount: vertexCount,
        vertexSize: vertexSize,
        lastVertex: lastVertex,
        lastVertexOffset: lastVertexOffset,
        elementSize: 2,
        xor: false,
        rotateBits: 0,
      );
    case 2:
      _decodeDeltaElements(
        buffer,
        target,
        targetOffset: targetOffset,
        vertexCount: vertexCount,
        vertexSize: vertexSize,
        lastVertex: lastVertex,
        lastVertexOffset: lastVertexOffset,
        elementSize: 4,
        xor: true,
        rotateBits: (32 - (channel >> 4)) & 31,
      );
    default:
      throw const MeshoptDecodeException(
        'ATTRIBUTES channel encoding is invalid.',
      );
  }
}

void _decodeDeltaElements(
  Uint8List buffer,
  Uint8List target, {
  required int targetOffset,
  required int vertexCount,
  required int vertexSize,
  required Uint8List lastVertex,
  required int lastVertexOffset,
  required int elementSize,
  required bool xor,
  required int rotateBits,
}) {
  final mask = elementSize == 4 ? 0xffffffff : (1 << (elementSize * 8)) - 1;
  for (var elementOffset = 0; elementOffset < 4; elementOffset += elementSize) {
    var previous = _readLittleEndian(
      lastVertex,
      lastVertexOffset + elementOffset,
      elementSize,
    );
    final base = elementOffset * vertexCount;
    for (var vertex = 0; vertex < vertexCount; vertex += 1) {
      var value = 0;
      for (var byteIndex = 0; byteIndex < elementSize; byteIndex += 1) {
        value |=
            buffer[base + vertex + vertexCount * byteIndex] << (byteIndex * 8);
      }
      if (xor) {
        value = (_rotate32(value, rotateBits) ^ previous) & mask;
      } else {
        value = (_unzigzag(value) + previous) & mask;
      }
      for (var byteIndex = 0; byteIndex < elementSize; byteIndex += 1) {
        target[targetOffset + vertex * vertexSize + elementOffset + byteIndex] =
            (value >> (byteIndex * 8)) & 0xff;
      }
      previous = value;
    }
  }
}

Uint8List _decodeIndexBuffer(
  Uint8List source, {
  required int indexCount,
  required int indexSize,
  required MeshoptDecodeControl? control,
}) {
  if (indexCount % 3 != 0 || (indexSize != 2 && indexSize != 4)) {
    throw const MeshoptDecodeException(
      'TRIANGLES count must be divisible by 3 and byteStride must be 2 or 4.',
    );
  }
  if (source.lengthInBytes < 1 + indexCount ~/ 3 + 16) {
    throw const MeshoptDecodeException('TRIANGLES stream is truncated.');
  }
  if ((source[0] & 0xf0) != _indexHeader) {
    throw const MeshoptDecodeException('TRIANGLES stream header is invalid.');
  }
  final version = source[0] & 0x0f;
  if (version > _decodeIndexVersion) {
    throw const MeshoptDecodeException(
      'TRIANGLES stream version is not supported.',
    );
  }

  final output = Uint8List(indexCount * indexSize);
  final edgeFifo = List<List<int>>.generate(16, (_) => <int>[0, 0]);
  final vertexFifo = List<int>.filled(16, 0);
  var edgeFifoOffset = 0;
  var vertexFifoOffset = 0;
  var next = 0;
  var last = 0;
  final fecMax = version >= 1 ? 13 : 15;
  var codeOffset = 1;
  var dataOffset = codeOffset + indexCount ~/ 3;
  final dataSafeEnd = source.lengthInBytes - 16;
  final codeauxTable = dataSafeEnd;

  void pushEdge(int a, int b) {
    edgeFifo[edgeFifoOffset][0] = a;
    edgeFifo[edgeFifoOffset][1] = b;
    edgeFifoOffset = (edgeFifoOffset + 1) & 15;
  }

  void pushVertex(int value, [bool condition = true]) {
    vertexFifo[vertexFifoOffset] = value;
    if (condition) {
      vertexFifoOffset = (vertexFifoOffset + 1) & 15;
    }
  }

  int decodeIndex() {
    final read = _decodeVByte(source, dataOffset, dataSafeEnd);
    dataOffset = read.nextOffset;
    final delta = _unzigzag(read.value);
    last = (last + delta) & 0xffffffff;
    return last;
  }

  for (var index = 0; index < indexCount; index += 3) {
    control?.checkpoint(
      stage: 'meshoptTriangles',
      decodedBytes: 3 * indexSize,
    );
    if (dataOffset > dataSafeEnd) {
      throw const MeshoptDecodeException('TRIANGLES stream is malformed.');
    }
    final codeTri = source[codeOffset];
    codeOffset += 1;
    if (codeTri < 0xf0) {
      final fe = codeTri >> 4;
      final edge = edgeFifo[(edgeFifoOffset - 1 - fe) & 15];
      final a = edge[0];
      final b = edge[1];
      final fec = codeTri & 15;
      int c;
      if (fec < fecMax) {
        final cf = vertexFifo[(vertexFifoOffset - 1 - fec) & 15];
        c = fec == 0 ? next : cf;
        if (fec == 0) {
          next += 1;
          pushVertex(c);
        } else {
          pushVertex(c, false);
        }
      } else {
        if (fec == 15) {
          c = decodeIndex();
        } else {
          c = (last + (fec - (fec ^ 3))) & 0xffffffff;
          last = c;
        }
        pushVertex(c);
      }
      pushEdge(c, b);
      pushEdge(a, c);
      _writeIndex(output, index, indexSize, a);
      _writeIndex(output, index + 1, indexSize, b);
      _writeIndex(output, index + 2, indexSize, c);
    } else if (codeTri < 0xfe) {
      final codeaux = source[codeauxTable + (codeTri & 15)];
      final feb = codeaux >> 4;
      final fec = codeaux & 15;
      final a = next;
      next += 1;
      final bf = vertexFifo[(vertexFifoOffset - feb) & 15];
      final b = feb == 0 ? next : bf;
      final feb0 = feb == 0;
      if (feb0) {
        next += 1;
      }
      final cf = vertexFifo[(vertexFifoOffset - fec) & 15];
      final c = fec == 0 ? next : cf;
      final fec0 = fec == 0;
      if (fec0) {
        next += 1;
      }
      _writeIndex(output, index, indexSize, a);
      _writeIndex(output, index + 1, indexSize, b);
      _writeIndex(output, index + 2, indexSize, c);
      pushVertex(a);
      pushVertex(b, feb0);
      pushVertex(c, fec0);
      pushEdge(b, a);
      pushEdge(c, b);
      pushEdge(a, c);
    } else {
      if (dataOffset >= dataSafeEnd) {
        throw const MeshoptDecodeException('TRIANGLES stream is truncated.');
      }
      final codeaux = source[dataOffset];
      dataOffset += 1;
      final fea = codeTri == 0xfe ? 0 : 15;
      final feb = codeaux >> 4;
      final fec = codeaux & 15;
      if (codeaux == 0) {
        next = 0;
      }
      var a = fea == 0 ? next++ : 0;
      var b = feb == 0 ? next++ : vertexFifo[(vertexFifoOffset - feb) & 15];
      var c = fec == 0 ? next++ : vertexFifo[(vertexFifoOffset - fec) & 15];
      if (fea == 15) {
        a = decodeIndex();
      }
      if (feb == 15) {
        b = decodeIndex();
      }
      if (fec == 15) {
        c = decodeIndex();
      }
      _writeIndex(output, index, indexSize, a);
      _writeIndex(output, index + 1, indexSize, b);
      _writeIndex(output, index + 2, indexSize, c);
      pushVertex(a);
      pushVertex(b, feb == 0 || feb == 15);
      pushVertex(c, fec == 0 || fec == 15);
      pushEdge(b, a);
      pushEdge(c, b);
      pushEdge(a, c);
    }
  }
  if (dataOffset != dataSafeEnd) {
    throw const MeshoptDecodeException(
      'TRIANGLES stream contains trailing compressed data.',
    );
  }
  return output;
}

Uint8List _decodeIndexSequence(
  Uint8List source, {
  required int indexCount,
  required int indexSize,
  required MeshoptDecodeControl? control,
}) {
  if (indexSize != 2 && indexSize != 4) {
    throw const MeshoptDecodeException('INDICES byteStride must be 2 or 4.');
  }
  if (source.lengthInBytes < 1 + indexCount + 4) {
    throw const MeshoptDecodeException('INDICES stream is truncated.');
  }
  if ((source[0] & 0xf0) != _sequenceHeader) {
    throw const MeshoptDecodeException('INDICES stream header is invalid.');
  }
  final version = source[0] & 0x0f;
  if (version > _decodeIndexVersion) {
    throw const MeshoptDecodeException(
      'INDICES stream version is not supported.',
    );
  }
  final output = Uint8List(indexCount * indexSize);
  final last = <int>[0, 0];
  var dataOffset = 1;
  final dataSafeEnd = source.lengthInBytes - 4;
  for (var index = 0; index < indexCount; index += 1) {
    control?.checkpoint(
      stage: 'meshoptIndices',
      decodedBytes: indexSize,
    );
    if (dataOffset >= dataSafeEnd) {
      throw const MeshoptDecodeException('INDICES stream is malformed.');
    }
    final read = _decodeVByte(source, dataOffset, dataSafeEnd);
    dataOffset = read.nextOffset;
    var value = read.value;
    final current = value & 1;
    value >>= 1;
    final delta = _unzigzag(value);
    final decoded = (last[current] + delta) & 0xffffffff;
    last[current] = decoded;
    _writeIndex(output, index, indexSize, decoded);
  }
  if (dataOffset != dataSafeEnd) {
    throw const MeshoptDecodeException(
      'INDICES stream contains trailing compressed data.',
    );
  }
  return output;
}

void _applyFilter(
  Uint8List data, {
  required int count,
  required int byteStride,
  required MeshoptCompressionFilter filter,
  required MeshoptDecodeControl? control,
}) {
  switch (filter) {
    case MeshoptCompressionFilter.none:
      return;
    case MeshoptCompressionFilter.octahedral:
      _decodeFilterOct(
        data,
        count: count,
        stride: byteStride,
        control: control,
      );
    case MeshoptCompressionFilter.quaternion:
      _decodeFilterQuat(
        data,
        count: count,
        stride: byteStride,
        control: control,
      );
    case MeshoptCompressionFilter.exponential:
      _decodeFilterExp(
        data,
        count: count,
        stride: byteStride,
        control: control,
      );
  }
}

void _decodeFilterOct(
  Uint8List data, {
  required int count,
  required int stride,
  required MeshoptDecodeControl? control,
}) {
  if (stride != 4 && stride != 8) {
    throw const MeshoptDecodeException(
      'OCTAHEDRAL filter requires byteStride 4 or 8.',
    );
  }
  final componentSize = stride ~/ 4;
  final max = componentSize == 1 ? 127.0 : 32767.0;
  for (var index = 0; index < count; index += 1) {
    control?.checkpoint(
      stage: 'meshoptOctahedralFilter',
      decodedBytes: stride,
    );
    final offset = index * stride;
    final xRaw = _readSignedComponent(data, offset, componentSize);
    final yRaw =
        _readSignedComponent(data, offset + componentSize, componentSize);
    final zRaw = _readSignedComponent(
      data,
      offset + componentSize * 2,
      componentSize,
    );
    var x = xRaw.toDouble();
    var y = yRaw.toDouble();
    final z = zRaw.toDouble() - x.abs() - y.abs();
    final t = z >= 0 ? 0.0 : z;
    x += x >= 0 ? t : -t;
    y += y >= 0 ? t : -t;
    final length = math.sqrt(x * x + y * y + z * z);
    if (length == 0) {
      continue;
    }
    final scale = max / length;
    _writeSignedComponent(data, offset, componentSize, _roundSigned(x * scale));
    _writeSignedComponent(
      data,
      offset + componentSize,
      componentSize,
      _roundSigned(y * scale),
    );
    _writeSignedComponent(
      data,
      offset + componentSize * 2,
      componentSize,
      _roundSigned(z * scale),
    );
  }
}

void _decodeFilterQuat(
  Uint8List data, {
  required int count,
  required int stride,
  required MeshoptDecodeControl? control,
}) {
  if (stride != 8) {
    throw const MeshoptDecodeException(
        'QUATERNION filter requires byteStride 8.');
  }
  final scale = 32767.0 / math.sqrt2;
  for (var index = 0; index < count; index += 1) {
    control?.checkpoint(
      stage: 'meshoptQuaternionFilter',
      decodedBytes: stride,
    );
    final offset = index * stride;
    final x = _readSignedComponent(data, offset, 2).toDouble();
    final y = _readSignedComponent(data, offset + 2, 2).toDouble();
    final z = _readSignedComponent(data, offset + 4, 2).toDouble();
    final wAndComponent = _readSignedComponent(data, offset + 6, 2);
    final s = (wAndComponent | 3).toDouble();
    final ww = s * s * 2.0 - x * x - y * y - z * z;
    final w = math.sqrt(math.max(0.0, ww));
    final ss = scale / s;
    final values = <int>[
      _roundSigned(w * ss),
      _roundSigned(x * ss),
      _roundSigned(y * ss),
      _roundSigned(z * ss),
    ];
    final maxComponent = wAndComponent & 3;
    for (var component = 0; component < 4; component += 1) {
      _writeSignedComponent(
        data,
        offset + ((maxComponent + component) & 3) * 2,
        2,
        values[component],
      );
    }
  }
}

void _decodeFilterExp(
  Uint8List data, {
  required int count,
  required int stride,
  required MeshoptDecodeControl? control,
}) {
  if (stride <= 0 || stride % 4 != 0) {
    throw const MeshoptDecodeException(
      'EXPONENTIAL filter requires byteStride divisible by 4.',
    );
  }
  final words = count * (stride ~/ 4);
  final view = ByteData.sublistView(data);
  for (var index = 0; index < words; index += 1) {
    control?.checkpoint(
      stage: 'meshoptExponentialFilter',
      decodedBytes: 4,
    );
    final value = view.getUint32(index * 4, Endian.little);
    final exponent = _signExtend(value >> 24, 8);
    final mantissa = _signExtend(value & 0x00ffffff, 24);
    view.setFloat32(
      index * 4,
      math.pow(2.0, exponent).toDouble() * mantissa,
      Endian.little,
    );
  }
}

int _vertexBlockSize(int vertexSize) {
  final result = (_vertexBlockSizeBytes ~/ vertexSize) & ~(_byteGroupSize - 1);
  return result < _vertexBlockMaxSize ? result : _vertexBlockMaxSize;
}

({int value, int nextOffset}) _decodeVByte(
  Uint8List source,
  int offset,
  int end,
) {
  if (offset >= end) {
    throw const MeshoptDecodeException('Varint stream is truncated.');
  }
  final lead = source[offset];
  offset += 1;
  if (lead < 128) {
    return (value: lead, nextOffset: offset);
  }
  var result = lead & 127;
  var shift = 7;
  for (var index = 0; index < 4; index += 1) {
    if (offset >= end) {
      throw const MeshoptDecodeException('Varint stream is truncated.');
    }
    final group = source[offset];
    offset += 1;
    result |= (group & 127) << shift;
    shift += 7;
    if (group < 128) {
      break;
    }
  }
  return (value: result, nextOffset: offset);
}

int _unzigzag(int value) => (-(value & 1)) ^ (value >> 1);

int _rotate32(int value, int rotateBits) {
  final shift = rotateBits & 31;
  value &= 0xffffffff;
  if (shift == 0) {
    return value;
  }
  return ((value << shift) | (value >> (32 - shift))) & 0xffffffff;
}

int _readLittleEndian(Uint8List bytes, int offset, int length) {
  var value = 0;
  for (var index = 0; index < length; index += 1) {
    value |= bytes[offset + index] << (index * 8);
  }
  return value;
}

void _writeIndex(Uint8List output, int index, int indexSize, int value) {
  final offset = index * indexSize;
  if (indexSize == 2) {
    output[offset] = value & 0xff;
    output[offset + 1] = (value >> 8) & 0xff;
  } else {
    output[offset] = value & 0xff;
    output[offset + 1] = (value >> 8) & 0xff;
    output[offset + 2] = (value >> 16) & 0xff;
    output[offset + 3] = (value >> 24) & 0xff;
  }
}

int _readSignedComponent(Uint8List data, int offset, int componentSize) {
  return _signExtend(
      _readLittleEndian(data, offset, componentSize), componentSize * 8);
}

void _writeSignedComponent(
  Uint8List data,
  int offset,
  int componentSize,
  int value,
) {
  final mask = componentSize == 1 ? 0xff : 0xffff;
  final encoded = value & mask;
  for (var index = 0; index < componentSize; index += 1) {
    data[offset + index] = (encoded >> (index * 8)) & 0xff;
  }
}

int _signExtend(int value, int bits) {
  final sign = 1 << (bits - 1);
  final mask = (1 << bits) - 1;
  value &= mask;
  return (value ^ sign) - sign;
}

int _roundSigned(double value) {
  return value >= 0 ? (value + 0.5).floor() : (value - 0.5).ceil();
}

int _align(int value, int alignment) {
  return (value + alignment - 1) & ~(alignment - 1);
}
