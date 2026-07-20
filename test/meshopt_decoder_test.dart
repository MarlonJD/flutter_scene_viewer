import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene_viewer/src/internal/meshopt_decoder.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes ATTRIBUTES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.none,
    );

    expect(decoded, <int>[1, 2, 3, 4]);
  });

  test('applies OCTAHEDRAL filters to ATTRIBUTES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      _attributeStream(<int>[0, 0, 127, 5], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.octahedral,
    );

    expect(decoded, <int>[0, 0, 127, 5]);
  });

  test('applies QUATERNION filters to ATTRIBUTES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      _attributeStream(<int>[0, 0, 0, 0, 0, 0, 0, 0], byteStride: 8),
      count: 1,
      byteStride: 8,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.quaternion,
    );

    expect(decoded, _uint16Bytes(<int>[32767, 0, 0, 0]));
  });

  test('applies EXPONENTIAL filters to ATTRIBUTES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      _attributeStream(<int>[1, 0, 0, 0], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.exponential,
    );

    expect(decoded, _float32Bytes(<double>[1]));
  });

  test('decodes TRIANGLES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      Uint8List.fromList(<int>[
        0xe1,
        0xf0,
        0x00,
        0x76,
        0x87,
        0x56,
        0x67,
        0x78,
        0xa9,
        0x86,
        0x65,
        0x89,
        0x68,
        0x98,
        0x01,
        0x69,
        0x00,
        0x00,
      ]),
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.triangles,
      filter: MeshoptCompressionFilter.none,
    );

    expect(decoded, _uint16Bytes(<int>[0, 1, 2]));
  });

  test('decodes INDICES streams', () async {
    final decoded = await decodeMeshoptGltfBuffer(
      Uint8List.fromList(<int>[
        0xd1,
        0x00,
        0x04,
        0x04,
        0x00,
        0x00,
        0x00,
        0x00,
      ]),
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.indices,
      filter: MeshoptCompressionFilter.none,
    );

    expect(decoded, _uint16Bytes(<int>[0, 1, 2]));
  });

  test('stops ATTRIBUTES decode at a cooperative deadline checkpoint',
      () async {
    var elapsedReads = 0;
    final control = MeshoptDecodeControl(
      timeout: const Duration(milliseconds: 1),
      checkInterval: 1,
      elapsed: () =>
          elapsedReads++ == 0 ? Duration.zero : const Duration(milliseconds: 2),
    );

    await expectLater(
      decodeMeshoptGltfBuffer(
        _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
        count: 1,
        byteStride: 4,
        mode: MeshoptCompressionMode.attributes,
        filter: MeshoptCompressionFilter.none,
        control: control,
      ),
      throwsA(
        isA<MeshoptDecodeStopped>()
            .having(
              (error) => error.kind,
              'kind',
              MeshoptDecodeStopKind.timeout,
            )
            .having(
              (error) => error.stage,
              'stage',
              'meshoptAttributes',
            ),
      ),
    );
    expect(elapsedReads, 2);
  });

  test('rejects an expired deadline before decode allocation', () async {
    var elapsedReads = 0;
    final control = MeshoptDecodeControl(
      timeout: Duration.zero,
      checkInterval: 4096,
      elapsed: () {
        elapsedReads += 1;
        return Duration.zero;
      },
    );

    await expectLater(
      decodeMeshoptGltfBuffer(
        _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
        count: 1,
        byteStride: 4,
        mode: MeshoptCompressionMode.attributes,
        filter: MeshoptCompressionFilter.none,
        control: control,
      ),
      throwsA(
        isA<MeshoptDecodeStopped>()
            .having(
              (error) => error.kind,
              'kind',
              MeshoptDecodeStopKind.timeout,
            )
            .having(
              (error) => error.stage,
              'stage',
              'meshoptDecodeStart',
            ),
      ),
    );
    expect(elapsedReads, 1);
  });

  final deadlineCases = <({
    String name,
    String stage,
    Uint8List source,
    int count,
    int byteStride,
    MeshoptCompressionMode mode,
    MeshoptCompressionFilter filter,
    int checkInterval,
    int safeElapsedReads,
  })>[
    (
      name: 'TRIANGLES',
      stage: 'meshoptTriangles',
      source: Uint8List.fromList(<int>[
        0xe1,
        0xf0,
        0x00,
        0x76,
        0x87,
        0x56,
        0x67,
        0x78,
        0xa9,
        0x86,
        0x65,
        0x89,
        0x68,
        0x98,
        0x01,
        0x69,
        0x00,
        0x00,
      ]),
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.triangles,
      filter: MeshoptCompressionFilter.none,
      checkInterval: 6,
      safeElapsedReads: 1,
    ),
    (
      name: 'INDICES',
      stage: 'meshoptIndices',
      source: Uint8List.fromList(<int>[
        0xd1,
        0x00,
        0x04,
        0x04,
        0x00,
        0x00,
        0x00,
        0x00,
      ]),
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.indices,
      filter: MeshoptCompressionFilter.none,
      checkInterval: 2,
      safeElapsedReads: 1,
    ),
    (
      name: 'OCTAHEDRAL filter',
      stage: 'meshoptOctahedralFilter',
      source: _attributeStream(<int>[0, 0, 127, 5], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.octahedral,
      checkInterval: 8,
      safeElapsedReads: 1,
    ),
    (
      name: 'QUATERNION filter',
      stage: 'meshoptQuaternionFilter',
      source: _attributeStream(
        <int>[0, 0, 0, 0, 0, 0, 0, 0],
        byteStride: 8,
      ),
      count: 1,
      byteStride: 8,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.quaternion,
      checkInterval: 16,
      safeElapsedReads: 1,
    ),
    (
      name: 'EXPONENTIAL filter',
      stage: 'meshoptExponentialFilter',
      source: _attributeStream(<int>[1, 0, 0, 0], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.exponential,
      checkInterval: 8,
      safeElapsedReads: 1,
    ),
  ];
  for (final deadlineCase in deadlineCases) {
    test('stops ${deadlineCase.name} at its deadline checkpoint', () async {
      var elapsedReads = 0;
      final control = MeshoptDecodeControl(
        timeout: const Duration(milliseconds: 1),
        checkInterval: deadlineCase.checkInterval,
        elapsed: () => elapsedReads++ < deadlineCase.safeElapsedReads
            ? Duration.zero
            : const Duration(milliseconds: 2),
      );

      await expectLater(
        decodeMeshoptGltfBuffer(
          deadlineCase.source,
          count: deadlineCase.count,
          byteStride: deadlineCase.byteStride,
          mode: deadlineCase.mode,
          filter: deadlineCase.filter,
          control: control,
        ),
        throwsA(
          isA<MeshoptDecodeStopped>()
              .having(
                (error) => error.kind,
                'kind',
                MeshoptDecodeStopKind.timeout,
              )
              .having(
                (error) => error.stage,
                'stage',
                deadlineCase.stage,
              ),
        ),
      );
      expect(elapsedReads, deadlineCase.safeElapsedReads + 1);
    });
  }

  final cancellationCases = <({
    String name,
    String stage,
    Uint8List source,
    int count,
    int byteStride,
    MeshoptCompressionMode mode,
    MeshoptCompressionFilter filter,
    int checkInterval,
  })>[
    (
      name: 'ATTRIBUTES',
      stage: 'meshoptAttributes',
      source: _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.none,
      checkInterval: 4,
    ),
    (
      name: 'TRIANGLES',
      stage: 'meshoptTriangles',
      source: deadlineCases[0].source,
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.triangles,
      filter: MeshoptCompressionFilter.none,
      checkInterval: 6,
    ),
    (
      name: 'INDICES',
      stage: 'meshoptIndices',
      source: deadlineCases[1].source,
      count: 3,
      byteStride: 2,
      mode: MeshoptCompressionMode.indices,
      filter: MeshoptCompressionFilter.none,
      checkInterval: 2,
    ),
    (
      name: 'OCTAHEDRAL',
      stage: 'meshoptOctahedralFilter',
      source: deadlineCases[2].source,
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.octahedral,
      checkInterval: 8,
    ),
    (
      name: 'QUATERNION',
      stage: 'meshoptQuaternionFilter',
      source: deadlineCases[3].source,
      count: 1,
      byteStride: 8,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.quaternion,
      checkInterval: 16,
    ),
    (
      name: 'EXPONENTIAL',
      stage: 'meshoptExponentialFilter',
      source: deadlineCases[4].source,
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.exponential,
      checkInterval: 8,
    ),
  ];
  for (final cancellationCase in cancellationCases) {
    test('observes external cancellation in ${cancellationCase.name}',
        () async {
      final cancellation = ModelLoadCancellationController();
      final decode = decodeMeshoptGltfBuffer(
        cancellationCase.source,
        count: cancellationCase.count,
        byteStride: cancellationCase.byteStride,
        mode: cancellationCase.mode,
        filter: cancellationCase.filter,
        control: MeshoptDecodeControl(
          timeout: const Duration(hours: 1),
          checkInterval: cancellationCase.checkInterval,
          elapsed: () => Duration.zero,
        ),
        cancellationToken: cancellation.token,
      );
      scheduleMicrotask(
          () => cancellation.cancel('stop-${cancellationCase.name}'));

      await expectLater(
        decode,
        throwsA(
          isA<MeshoptDecodeStopped>()
              .having(
                (error) => error.kind,
                'kind',
                MeshoptDecodeStopKind.cancelled,
              )
              .having(
                (error) => error.stage,
                'stage',
                cancellationCase.stage,
              ),
        ),
      );
    });
  }

  test('ATTRIBUTES observes cancellation at the declared multi-interval bound',
      () async {
    const count = 256;
    const byteStride = 32;
    const checkInterval = 4096;
    final cancellation = ModelLoadCancellationController();
    final decode = decodeMeshoptGltfBuffer(
      _attributeStream(
        List<int>.filled(count * byteStride, 0),
        byteStride: byteStride,
      ),
      count: count,
      byteStride: byteStride,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.none,
      control: MeshoptDecodeControl(
        timeout: const Duration(hours: 1),
        checkInterval: checkInterval,
        elapsed: () => Duration.zero,
      ),
      cancellationToken: cancellation.token,
    );
    Timer.run(() => cancellation.cancel('second-interval'));

    await expectLater(
      decode,
      throwsA(
        isA<MeshoptDecodeStopped>()
            .having(
              (error) => error.kind,
              'kind',
              MeshoptDecodeStopKind.cancelled,
            )
            .having(
              (error) => error.stage,
              'stage',
              'meshoptAttributes',
            ),
      ),
    );
  });

  test('checkpoint accounting preserves residual work across forced checks',
      () async {
    var elapsedReads = 0;
    final control = MeshoptDecodeControl(
      timeout: const Duration(hours: 1),
      checkInterval: 4096,
      elapsed: () {
        elapsedReads += 1;
        return Duration.zero;
      },
    );

    expect(
      control.checkpoint(stage: 'partial', decodedBytes: 3000),
      isNull,
    );
    expect(
      control.checkpoint(stage: 'forced', force: true),
      isNull,
    );
    final interval = control.checkpoint(
      stage: 'residual',
      decodedBytes: 1096,
    );
    expect(interval, isNotNull);
    await interval;

    expect(elapsedReads, 2);
  });

  test('caller cancellation wins when observed before an expired deadline',
      () async {
    final cancellation = ModelLoadCancellationController();
    var elapsedReads = 0;
    final decode = decodeMeshoptGltfBuffer(
      _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.none,
      control: MeshoptDecodeControl(
        timeout: const Duration(milliseconds: 1),
        checkInterval: 4,
        elapsed: () => elapsedReads++ == 0
            ? Duration.zero
            : const Duration(milliseconds: 2),
      ),
      cancellationToken: cancellation.token,
    );
    scheduleMicrotask(() => cancellation.cancel('caller-first'));

    await expectLater(
      decode,
      throwsA(
        isA<MeshoptDecodeStopped>().having(
          (error) => error.kind,
          'kind',
          MeshoptDecodeStopKind.cancelled,
        ),
      ),
    );
  });

  test('deadline wins when observed before caller cancellation', () async {
    final cancellation = ModelLoadCancellationController();
    var elapsedReads = 0;
    final decode = decodeMeshoptGltfBuffer(
      _attributeStream(<int>[1, 2, 3, 4], byteStride: 4),
      count: 1,
      byteStride: 4,
      mode: MeshoptCompressionMode.attributes,
      filter: MeshoptCompressionFilter.none,
      control: MeshoptDecodeControl(
        timeout: const Duration(milliseconds: 1),
        checkInterval: 4,
        elapsed: () => elapsedReads++ == 0
            ? Duration.zero
            : const Duration(milliseconds: 2),
      ),
      cancellationToken: cancellation.token,
    );
    Timer.run(() => cancellation.cancel('caller-late'));

    await expectLater(
      decode,
      throwsA(
        isA<MeshoptDecodeStopped>().having(
          (error) => error.kind,
          'kind',
          MeshoptDecodeStopKind.timeout,
        ),
      ),
    );
  });
}

Uint8List _attributeStream(List<int> values, {required int byteStride}) {
  final controlSize = byteStride ~/ 4;
  final tailSize = byteStride + controlSize;
  final tailSizePad = tailSize < 24 ? 24 : tailSize;
  final bytes = Uint8List(1 + controlSize + values.length + tailSizePad);
  bytes[0] = 0xa1;
  for (var index = 0; index < controlSize; index += 1) {
    bytes[1 + index] = 0xff;
  }
  for (var index = 0; index < values.length; index += 1) {
    bytes[1 + controlSize + index] = values[index] * 2;
  }
  return bytes;
}

Uint8List _uint16Bytes(List<int> values) {
  final bytes = Uint8List(values.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setUint16(index * 2, values[index], Endian.little);
  }
  return bytes;
}

Uint8List _float32Bytes(List<double> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setFloat32(index * 4, values[index], Endian.little);
  }
  return bytes;
}
