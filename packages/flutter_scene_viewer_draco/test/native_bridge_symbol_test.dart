import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dracoUpstreamCommit = '8786740086a9f4d83f44aa83badfbea4dce7a1b5';
const _dracoSourceObject = '8794499f9f7e72c1cd64aea7242081a2d1ed5da3';
const _dracoSourceArchiveHash =
    'feded3996b7e9d0d40f6ef51804397083b4f66a786ecfe392f1d04e06f255841';
const _dracoLicenseHash =
    'd3709b0fb4b8a94bbb1d02b8a2e484f258b0d9c5c5a01f940391f3fe662cd1a4';
const _sequentialGeneratorHash =
    'e651166cac6509017ad8cdb80cc3ed43020229b4f2357c7d8b602fc5caa2bfe8';
const _sequentialPayloadHash =
    '5113cbc836363cae9a59526d983e12ee95d32cf2f342bf192be7b2fdc2321b33';
const _metadataGeneratorHash =
    '198ff16d02f08e2dd4eedf62adbf7d2a6de2b6eed52cc2939a791d37b4c33aba';
const _metadataPayloadHash =
    'cc5e86aaaf9876274d773d7b71a9cdf85e263a6f50de91e842188a3cf9b922c6';

void main() {
  test('native bridge request preflight and result ownership is controlled',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('fsv_draco_bridge_ownership_red_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/bridge_ownership';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      'test/native/draco_bridge_ownership_runner.cc',
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(
      const LineSplitter().convert('${run.stdout}'),
      contains('owner_family_allocations=17'),
    );
  });

  test('compiled bridge-owner mutants cannot bypass request accounting',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_owner_mutants_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const sourceRoot = 'android/src/main/cpp';
    const names = <String>[
      'fsv_draco_owned.h',
      'fsv_draco_codec_adapter.h',
      'fsv_draco_budget.h',
      'fsv_draco_budget.cc',
      'fsv_draco_control.h',
      'fsv_draco_control.cc',
      'fsv_draco_bridge.h',
      'fsv_draco_bridge.cc',
    ];
    final baseline = <String, String>{};
    for (final name in names) {
      baseline[name] = await File('$sourceRoot/$name').readAsString();
    }
    final mutants =
        <({String label, String file, String from, String to, bool box})>[
      (
        label: 'allocator_move_propagation',
        file: 'fsv_draco_owned.h',
        from: 'using propagate_on_container_move_assignment = std::true_type;',
        to: 'using propagate_on_container_move_assignment = std::false_type;',
        box: false,
      ),
      (
        label: 'allocator_swap_propagation',
        file: 'fsv_draco_owned.h',
        from: 'using propagate_on_container_swap = std::true_type;',
        to: 'using propagate_on_container_swap = std::false_type;',
        box: false,
      ),
      (
        label: 'request_bytes',
        file: 'fsv_draco_budget.h',
        from: 'compressed_bytes(FsvDracoAllocator<uint8_t>(control))',
        to: 'compressed_bytes(FsvDracoAllocator<uint8_t>(nullptr))',
        box: false,
      ),
      (
        label: 'accessor_string',
        file: 'fsv_draco_budget.h',
        from: 'type(FsvDracoAllocator<char>(control))',
        to: 'type(FsvDracoAllocator<char>(nullptr))',
        box: false,
      ),
      (
        label: 'request_attribute_map',
        file: 'fsv_draco_budget.h',
        from: 'std::pair<const FsvDracoString, int64_t>>(\n'
            '                                    control)',
        to: 'std::pair<const FsvDracoString, int64_t>>(\n'
            '                                    nullptr)',
        box: false,
      ),
      (
        label: 'request_accessor_map',
        file: 'fsv_draco_budget.h',
        from: 'FsvDracoAccessorSchema>>(control)',
        to: 'FsvDracoAccessorSchema>>(nullptr)',
        box: false,
      ),
      (
        label: 'preflight_vector',
        file: 'fsv_draco_budget.h',
        from: 'diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(control))',
        to: 'diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(nullptr))',
        box: false,
      ),
      (
        label: 'decoded_index',
        file: 'fsv_draco_bridge.h',
        from: 'indices(FsvDracoAllocator<uint8_t>(control))',
        to: 'indices(FsvDracoAllocator<uint8_t>(nullptr))',
        box: false,
      ),
      (
        label: 'decoded_result',
        file: 'fsv_draco_bridge.h',
        from: 'FsvDracoAllocator<FsvDracoDecodedPrimitive>(control)',
        to: 'FsvDracoAllocator<FsvDracoDecodedPrimitive>(nullptr)',
        box: false,
      ),
      (
        label: 'decoded_attribute_map',
        file: 'fsv_draco_bridge.h',
        from: 'FsvDracoByteVector>>(control)',
        to: 'FsvDracoByteVector>>(nullptr)',
        box: false,
      ),
      (
        label: 'result_diagnostics',
        file: 'fsv_draco_bridge.h',
        from: 'diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(control))',
        to: 'diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(nullptr))',
        box: false,
      ),
      (
        label: 'diagnostic_message',
        file: 'fsv_draco_budget.h',
        from: 'message(FsvDracoAllocator<char>(control))',
        to: 'message(FsvDracoAllocator<char>(nullptr))',
        box: false,
      ),
      (
        label: 'destination_copy',
        file: 'fsv_draco_bridge.h',
        from: ': FsvDracoDecodeResult(control) {',
        to: ': FsvDracoDecodeResult(nullptr) {',
        box: false,
      ),
      (
        label: 'same_control_result_move',
        file: 'fsv_draco_bridge.h',
        from: 'if (control_ == other.control_) {\n'
            '        decoded_primitives = std::move(other.decoded_primitives);',
        to: 'if (false) {\n'
            '        decoded_primitives = std::move(other.decoded_primitives);',
        box: false,
      ),
      (
        label: 'destination_move',
        file: 'fsv_draco_bridge.h',
        from: ': FsvDracoDecodeResult(other, control) {',
        to: ': FsvDracoDecodeResult(other, nullptr) {',
        box: false,
      ),
      (
        label: 'control_before_result',
        file: 'fsv_draco_control.cc',
        from: 'if (owner_count_.load() != 0 || live_bytes_.load() != 0) {',
        to: 'if (false) {',
        box: false,
      ),
      (
        label: 'preflight_set',
        file: 'fsv_draco_budget.cc',
        from: 'FsvDracoAllocator<std::pair<int, int>>(control)',
        to: 'FsvDracoAllocator<std::pair<int, int>>(nullptr)',
        box: true,
      ),
      (
        label: 'preflight_map',
        file: 'fsv_draco_budget.cc',
        from: 'FsvDracoAllocator<std::pair<const int64_t, '
            'FsvDracoAccessorSchema>>(\n          control)',
        to: 'FsvDracoAllocator<std::pair<const int64_t, '
            'FsvDracoAccessorSchema>>(\n          nullptr)',
        box: true,
      ),
      (
        label: 'preflight_vertex_map',
        file: 'fsv_draco_budget.cc',
        from: 'FsvDracoAllocator<std::pair<const int64_t, uint64_t>>(control)',
        to: 'FsvDracoAllocator<std::pair<const int64_t, uint64_t>>(nullptr)',
        box: true,
      ),
      (
        label: 'decoded_metadata',
        file: 'fsv_draco_budget.h',
        from: 'attribute_unique_ids(FsvDracoAllocator<uint32_t>(control))',
        to: 'attribute_unique_ids(FsvDracoAllocator<uint32_t>(nullptr))',
        box: true,
      ),
      (
        label: 'decoded_mesh_vector',
        file: 'fsv_draco_bridge.cc',
        from: 'FsvDracoAllocator<std::unique_ptr<draco::Mesh>>(control)',
        to: 'FsvDracoAllocator<std::unique_ptr<draco::Mesh>>(nullptr)',
        box: true,
      ),
      (
        label: 'decoded_metadata_vector',
        file: 'fsv_draco_bridge.cc',
        from: 'FsvDracoAllocator<FsvDracoDecodedMeshMetadata>(control)',
        to: 'FsvDracoAllocator<FsvDracoDecodedMeshMetadata>(nullptr)',
        box: true,
      ),
      (
        label: 'attribute_bytes',
        file: 'fsv_draco_bridge.cc',
        from: 'FsvDracoByteVector attribute_bytes{\n'
            '          FsvDracoAllocator<uint8_t>(control)};',
        to: 'FsvDracoByteVector attribute_bytes{\n'
            '          FsvDracoAllocator<uint8_t>(nullptr)};',
        box: true,
      ),
    ];
    for (final mutant in mutants) {
      final directory = Directory('${tempDir.path}/${mutant.label}');
      await directory.create();
      for (final name in names) {
        var source = baseline[name]!;
        if (name == mutant.file) {
          source = source.replaceFirst(mutant.from, mutant.to);
          expect(source, isNot(baseline[name]), reason: mutant.label);
        }
        await File('${directory.path}/$name').writeAsString(source);
      }
      final runner = mutant.box
          ? 'test/native/draco_conformance_runner.cc'
          : 'test/native/draco_bridge_ownership_runner.cc';
      final executable = '${directory.path}/runner';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-Ithird_party/draco/src',
        '-I${directory.path}',
        runner,
        '${directory.path}/fsv_draco_budget.cc',
        '${directory.path}/fsv_draco_control.cc',
        '${directory.path}/fsv_draco_bridge.cc',
        'ios/Classes/fsv_draco_vendor_sources.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '${mutant.label}: ${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(
        executable,
        mutant.box
            ? const <String>['test/fixtures/draco/Box/glTF-Draco/Box.bin']
            : const <String>[],
      );
      expect(run.exitCode, isNot(0),
          reason: '${mutant.label} escaped: ${run.stdout}\n${run.stderr}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('compiled codec release mutants cannot bypass causal records', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_codec_release_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const sourceRoot = 'android/src/main/cpp';
    const names = <String>[
      'fsv_draco_owned.h',
      'fsv_draco_codec_adapter.h',
      'fsv_draco_budget.h',
      'fsv_draco_budget.cc',
      'fsv_draco_control.h',
      'fsv_draco_control.cc',
      'fsv_draco_bridge.h',
      'fsv_draco_bridge.cc',
    ];
    final baseline = <String, String>{};
    for (final name in names) {
      baseline[name] = await File('$sourceRoot/$name').readAsString();
    }
    final mutants = <({String label, String file, String from, String to})>[
      (
        label: 'wrong_pointer',
        file: 'fsv_draco_bridge.cc',
        from: 'allocation_record->allocation != allocation ||',
        to: 'false ||',
      ),
      (
        label: 'wrong_bytes',
        file: 'fsv_draco_bridge.cc',
        from: 'allocation_record->bytes != bytes ||',
        to: 'false ||',
      ),
      (
        label: 'wrong_alignment',
        file: 'fsv_draco_bridge.cc',
        from: 'allocation_record->alignment != alignment ||',
        to: 'false ||',
      ),
      (
        label: 'double_release',
        file: 'fsv_draco_control.cc',
        from: '*allocation_record = FsvDecodeAllocationResult();',
        to: '(void)allocation_record;',
      ),
    ];
    for (final mutant in mutants) {
      final directory = Directory('${tempDir.path}/${mutant.label}');
      await directory.create();
      for (final name in names) {
        var source = baseline[name]!;
        if (name == mutant.file) {
          source = source.replaceAll(mutant.from, mutant.to);
          if (mutant.label == 'wrong_bytes') {
            source = source.replaceAll('slot.bytes != bytes ||', 'false ||');
          } else if (mutant.label == 'wrong_alignment') {
            source = source.replaceAll(
              'slot.alignment != alignment)',
              'false)',
            );
          }
          expect(source, isNot(baseline[name]), reason: mutant.label);
        }
        await File('${directory.path}/$name').writeAsString(source);
      }
      final executable = '${directory.path}/runner';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-Ithird_party/draco/src',
        '-I${directory.path}',
        'test/native/draco_bridge_ownership_runner.cc',
        '${directory.path}/fsv_draco_budget.cc',
        '${directory.path}/fsv_draco_control.cc',
        '${directory.path}/fsv_draco_bridge.cc',
        'ios/Classes/fsv_draco_vendor_sources.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '${mutant.label}: ${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, isNot(0),
          reason: '${mutant.label} escaped: ${run.stdout}\n${run.stderr}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('Draco metadata and status owners use the request control', () async {
    final metadata = await File(
      'third_party/draco/src/draco/metadata/metadata.h',
    ).readAsString();
    final geometry = await File(
      'third_party/draco/src/draco/metadata/geometry_metadata.h',
    ).readAsString();
    final decoder = await File(
      'third_party/draco/src/draco/metadata/metadata_decoder.cc',
    ).readAsString();
    final status = await File(
      'third_party/draco/src/draco/core/status.h',
    ).readAsString();
    final pointCloudDecoder = await File(
      'third_party/draco/src/draco/compression/point_cloud/'
      'point_cloud_decoder.cc',
    ).readAsString();

    expect(metadata, contains('class Metadata : public FsvDecodeAllocated'));
    expect(metadata, contains('FsvString'));
    expect(metadata, contains('FsvMap'));
    expect(
      geometry,
      contains('FsvVector<std::unique_ptr<AttributeMetadata>> '
          'controlled_att_metadatas_'),
    );
    expect(decoder, contains('MetadataDecoder(FsvDecodeControl *control)'));
    expect(decoder, contains('ShouldStopDecoding()'));
    expect(decoder, contains('kFsvMetadataCopyChunkBytes'));
    expect(status, contains('FsvDecodeControl *control'));
    expect(status, contains('FsvString controlled_error_msg_'));
    expect(
      status,
      contains('const std::string &error_msg_string() const'),
    );
    expect(metadata, isNot(contains('std::string host_name')));
    expect(
      pointCloudDecoder,
      contains('new (fsv_decode_control_)\n'
          '                                            GeometryMetadata('),
    );
    expect(
      pointCloudDecoder,
      contains('MetadataDecoder metadata_decoder(fsv_decode_control_)'),
    );
  });

  test('Draco metadata preserves its pristine public source surface', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_metadata_surface_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final pristineEncoder = await Process.run(
        'git',
        <String>[
          'show',
          '$_dracoSourceObject:packages/flutter_scene_viewer_draco/'
              'third_party/draco/src/draco/metadata/metadata_encoder.cc',
        ],
        workingDirectory: '../..');
    expect(pristineEncoder.exitCode, 0,
        reason: '${pristineEncoder.stdout}\n${pristineEncoder.stderr}');
    final encoderSource = File('${tempDir.path}/metadata_encoder.cc');
    await encoderSource.writeAsString('${pristineEncoder.stdout}');
    final encoderCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      '-c',
      encoderSource.path,
      '-o',
      '${tempDir.path}/metadata_encoder.o',
    ]);
    expect(encoderCompile.exitCode, 0,
        reason: '${encoderCompile.stdout}\n${encoderCompile.stderr}');

    final surfaceRunner = 'test/native/draco_metadata_public_surface_runner.cc';
    final surfaceExecutable = '${tempDir.path}/metadata_surface';
    final surfaceCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      surfaceRunner,
      'third_party/draco/src/draco/core/status.cc',
      'third_party/draco/src/draco/metadata/metadata.cc',
      'third_party/draco/src/draco/metadata/geometry_metadata.cc',
      '-o',
      surfaceExecutable,
    ]);
    expect(surfaceCompile.exitCode, 0,
        reason: '${surfaceCompile.stdout}\n${surfaceCompile.stderr}');
    final surfaceRun = await Process.run(surfaceExecutable, const <String>[]);
    expect(surfaceRun.exitCode, 0,
        reason: '${surfaceRun.stdout}\n${surfaceRun.stderr}');
    expect(
      '${surfaceRun.stdout}',
      matches(RegExp(r'metadata_internal_layout_bytes=\d+/\d+/\d+/\d+')),
    );

    final androidBridge =
        await File('android/src/main/cpp/fsv_draco_bridge.cc').readAsString();
    final iosBridge =
        await File('ios/Classes/fsv_draco_bridge.cc').readAsString();
    expect(iosBridge, androidBridge);
    expect(androidBridge, contains('decoder.DecodeMeshFromBuffer('));
    for (final headerPath in <String>[
      'android/src/main/cpp/fsv_draco_bridge.h',
      'ios/Classes/fsv_draco_bridge.h',
    ]) {
      final header = await File(headerPath).readAsString();
      expect(header, isNot(contains('#include "draco/')));
      expect(header, isNot(matches(RegExp(r'\bdraco::'))));
    }
  });

  test('metadata fixture parity sweeps ownership and rejects bypass mutants',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    const fixtureRoot = 'test/fixtures/draco/Metadata';
    final fixture = File('$fixtureRoot/metadata_nested_blob.drc');
    final generator = File('$fixtureRoot/generate_fixture.cc');
    final readme = File('$fixtureRoot/README.md');
    expect(await fixture.length(), 5332);
    expect(await _sha256(fixture), _metadataPayloadHash);
    expect(await _sha256(generator), _metadataGeneratorHash);
    final provenance = await readme.readAsString();
    for (final value in <String>[
      _dracoUpstreamCommit,
      _dracoSourceObject,
      _dracoSourceArchiveHash,
      _dracoLicenseHash,
      _metadataGeneratorHash,
      _metadataPayloadHash,
      'Apache-2.0',
    ]) {
      expect(provenance, contains(value));
    }

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_metadata_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final runner = File('test/native/draco_metadata_conformance_runner.cc');
    final executable = '${tempDir.path}/metadata';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-pthread',
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      runner.path,
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, <String>[fixture.path]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    final output = const LineSplitter().convert('${run.stdout}');
    expect(output, contains('metadata_source_allocations=47'));
    expect(output, contains('metadata_accepted_host_allocations=47'));
    expect(
      output.any((line) => line.startsWith('metadata_hash_matches_pristine=')),
      isTrue,
    );
    expect(output, contains('metadata_destination_allocations=22'));
    expect(output, contains('metadata_destination_copy_ordinals=22'));
    expect(output, contains('status_source_destination_allocations=1/1'));
    expect(output, contains('status_literal_host_temporaries=0'));
    expect(
      output,
      contains('entry_value_source_destination_allocations=4/2'),
    );
    expect(output, contains('metadata_detached_source_allocations=3'));
    expect(output, contains('metadata_blob_stop_allocations=14'));
    expect(output, contains('metadata_allocation_ordinals=63'));
    expect(output, contains('metadata_codec_allocation_ordinals=47'));
    expect(output, contains('metadata_peak_bytes=30083'));
    expect(output, contains('metadata_corrupt_allocations=26'));
    expect(output, contains('metadata_final_status_allocations=14'));
    expect(output, contains('metadata_final_status_failure_ordinal=14'));

    final mutations = <({
      String label,
      String path,
      String before,
      String after,
      bool header,
    })>[
      (
        label: 'accepted decode legacy metadata snapshot',
        path: 'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.cc',
        before: 'point_cloud_->AddMetadata(std::move(metadata));',
        after: '(void)metadata->entries();\n'
            '  point_cloud_->AddMetadata(std::move(metadata));',
        header: false,
      ),
      (
        label: 'geometry object',
        path: 'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.cc',
        before: 'new (fsv_decode_control_)\n'
            '                                            GeometryMetadata(',
        after: 'new GeometryMetadata(',
        header: false,
      ),
      (
        label: 'attribute metadata object',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before: 'new (control_) AttributeMetadata(control_)',
        after: 'new AttributeMetadata(control_)',
        header: false,
      ),
      (
        label: 'nested metadata object',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before: 'new (control_) Metadata(control_)',
        after: 'new Metadata(control_)',
        header: false,
      ),
      (
        label: 'entry map nodes',
        path: 'third_party/draco/src/draco/metadata/metadata.cc',
        before:
            'FsvDecodeAllocator<std::pair<const FsvString, EntryValue>>(control)',
        after:
            'FsvDecodeAllocator<std::pair<const FsvString, EntryValue>>(nullptr)',
        header: false,
      ),
      (
        label: 'submetadata map nodes',
        path: 'third_party/draco/src/draco/metadata/metadata.cc',
        before:
            'std::pair<const FsvString, std::unique_ptr<Metadata>>>(control)',
        after:
            'std::pair<const FsvString, std::unique_ptr<Metadata>>>(nullptr)',
        header: false,
      ),
      (
        label: 'attribute metadata vector',
        path: 'third_party/draco/src/draco/metadata/geometry_metadata.cc',
        before: 'FsvDecodeAllocator<std::unique_ptr<AttributeMetadata>>('
            'control)',
        after: 'FsvDecodeAllocator<std::unique_ptr<AttributeMetadata>>('
            'nullptr)',
        header: false,
      ),
      (
        label: 'decoded attribute metadata vector',
        path: 'third_party/draco/src/draco/metadata/geometry_metadata.h',
        before: 'FsvDecodeAllocator<std::unique_ptr<AttributeMetadata>>('
            'control)) {}',
        after: 'FsvDecodeAllocator<std::unique_ptr<AttributeMetadata>>('
            'nullptr)) {}',
        header: true,
      ),
      (
        label: 'decoded names',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before: 'FsvString entry_name{FsvDecodeAllocator<char>(control_)}',
        after: 'FsvString entry_name{FsvDecodeAllocator<char>(nullptr)}',
        header: false,
      ),
      (
        label: 'decoded submetadata names',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before:
            'FsvString sub_metadata_name{FsvDecodeAllocator<char>(control_)}',
        after: 'FsvString sub_metadata_name{FsvDecodeAllocator<char>(nullptr)}',
        header: false,
      ),
      (
        label: 'entry blob',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before:
            'FsvVector<uint8_t> entry_value{FsvDecodeAllocator<uint8_t>(control_)}',
        after:
            'FsvVector<uint8_t> entry_value{FsvDecodeAllocator<uint8_t>(nullptr)}',
        header: false,
      ),
      (
        label: 'decoder stack',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before: 'FsvDecodeAllocator<MetadataTuple>(control_)',
        after: 'FsvDecodeAllocator<MetadataTuple>(nullptr)',
        header: false,
      ),
      (
        label: 'decoder control handoff',
        path: 'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.cc',
        before: 'MetadataDecoder metadata_decoder(fsv_decode_control_)',
        after: 'MetadataDecoder metadata_decoder(nullptr)',
        header: false,
      ),
      (
        label: 'blob checkpoint',
        path: 'third_party/draco/src/draco/metadata/metadata_decoder.cc',
        before: 'if (ShouldStopDecoding()) {\n      return false;\n    }\n'
            '    const size_t chunk =',
        after: 'if (false) {\n      return false;\n    }\n'
            '    const size_t chunk =',
        header: false,
      ),
      (
        label: 'destination metadata control',
        path: 'third_party/draco/src/draco/metadata/geometry_metadata.cc',
        before: ': Metadata(metadata, control),',
        after: ': Metadata(metadata, nullptr),',
        header: false,
      ),
      (
        label: 'destination EntryValue control',
        path: 'third_party/draco/src/draco/metadata/metadata.cc',
        before: 'EntryValue::EntryValue(const EntryValue &value, '
            'FsvDecodeControl *control)\n'
            '    : control_(control),\n'
            '      controlled_data_(FsvDecodeAllocator<uint8_t>(control))',
        after: 'EntryValue::EntryValue(const EntryValue &value, '
            'FsvDecodeControl *control)\n'
            '    : control_(control),\n'
            '      controlled_data_(FsvDecodeAllocator<uint8_t>(nullptr))',
        header: false,
      ),
      (
        label: 'ordinary EntryValue move detach',
        path: 'third_party/draco/src/draco/metadata/metadata.cc',
        before: ': EntryValue(std::move(value), nullptr) {}',
        after: ': EntryValue(std::move(value), value.control_) {}',
        header: false,
      ),
      (
        label: 'ordinary metadata detach',
        path: 'third_party/draco/src/draco/metadata/metadata.cc',
        before: 'Metadata::Metadata(const Metadata &metadata) : '
            'Metadata(metadata, nullptr)',
        after: 'Metadata::Metadata(const Metadata &metadata) : '
            'Metadata(metadata, metadata.fsv_decode_control())',
        header: false,
      ),
      (
        label: 'metadata hash semantics',
        path: 'third_party/draco/src/draco/metadata/metadata.h',
        before:
            'std::string_view(entry.first.data(), entry.first.size()), hash);',
        after: 'std::string_view(), hash);',
        header: true,
      ),
      (
        label: 'status literal request storage',
        path: 'third_party/draco/src/draco/core/status.cc',
        before: 'Status::Status(Code code, std::string_view error_msg,\n'
            '               FsvDecodeControl *control)\n'
            '    : code_(code),\n'
            '      control_(control),\n'
            '      controlled_error_msg_(FsvDecodeAllocator<char>(control))',
        after: 'Status::Status(Code code, std::string_view error_msg,\n'
            '               FsvDecodeControl *control)\n'
            '    : code_(code),\n'
            '      control_(control),\n'
            '      controlled_error_msg_(FsvDecodeAllocator<char>(nullptr))',
        header: false,
      ),
      (
        label: 'destination Status copy control',
        path: 'third_party/draco/src/draco/core/status.cc',
        before: 'Status::Status(const Status &status, '
            'FsvDecodeControl *control)\n'
            '    : code_(status.code_),\n'
            '      control_(control),\n'
            '      controlled_error_msg_(FsvDecodeAllocator<char>(control))',
        after: 'Status::Status(const Status &status, '
            'FsvDecodeControl *control)\n'
            '    : code_(status.code_),\n'
            '      control_(control),\n'
            '      controlled_error_msg_(FsvDecodeAllocator<char>(nullptr))',
        header: false,
      ),
      (
        label: 'ordinary Status move detach',
        path: 'third_party/draco/src/draco/core/status.cc',
        before: 'Status::Status(Status &&status) : Status(status, nullptr)',
        after: 'Status::Status(Status &&status)\n'
            '    : Status(status, status.control_)',
        header: false,
      ),
      (
        label: 'status literal host temporary',
        path: 'third_party/draco/src/draco/core/status.cc',
        before: 'Status::Status(Code code, const char *error_msg, '
            'FsvDecodeControl *control)\n'
            '    : Status(code, std::string_view(error_msg), control) {}',
        after: 'Status::Status(Code code, const char *error_msg, '
            'FsvDecodeControl *control)\n'
            '    : Status(code, std::string(error_msg), control) {}',
        header: false,
      ),
      (
        label: 'DRACO_RETURN status handoff',
        path: 'third_party/draco/src/draco/core/status.h',
        before: 'return draco::MoveStatusPreservingControl(',
        after: 'return (',
        header: true,
      ),
      (
        label: 'StatusOr rvalue status handoff',
        path: 'third_party/draco/src/draco/core/status_or.h',
        before: 'StatusOr(Status &&status)\n'
            '      : status_(MoveStatusPreservingControl(std::move(status))) {}',
        after: 'StatusOr(Status &&status) : status_(status) {}',
        header: true,
      ),
      (
        label: 'decode Status control handoff',
        path: 'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.cc',
        before: '"Failed to decode metadata.",\n'
            '                  fsv_decode_control_)',
        after: '"Failed to decode metadata.", nullptr)',
        header: false,
      ),
      (
        label: 'status stopped assignment',
        path: 'third_party/draco/src/draco/core/status.cc',
        before: 'if (control_ != nullptr && control_->ShouldStopDecoding()) {',
        after: 'if (false) {',
        header: false,
      ),
    ];
    for (final mutation in mutations) {
      final source = await File(mutation.path).readAsString();
      final mutated = source.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(source), reason: mutation.label);
      final mutant = await _compileDracoAggregateMutant(
        tempDir: tempDir,
        runner: runner,
        label: mutation.label.replaceAll(' ', '_'),
        mutatedSources: mutation.header
            ? const <String, String>{}
            : <String, String>{mutation.path: mutated},
        mutatedHeaders: mutation.header
            ? <String, String>{mutation.path: mutated}
            : const <String, String>{},
      );
      final mutantRun = await Process.run(mutant, <String>[fixture.path]);
      expect(mutantRun.exitCode, isNot(0), reason: mutation.label);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('metadata fixture regenerates offline from immutable pinned source',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_metadata_regen_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final archive = File('${tempDir.path}/draco.tar');
    final archiveResult = await Process.run(
      'git',
      <String>[
        'archive',
        '--format=tar',
        '--output=${archive.path}',
        _dracoSourceObject,
        'packages/flutter_scene_viewer_draco/third_party/draco',
      ],
      workingDirectory: '../..',
    );
    expect(archiveResult.exitCode, 0,
        reason: '${archiveResult.stdout}\n${archiveResult.stderr}');
    expect(await _sha256(archive), _dracoSourceArchiveHash);
    final sourceDir = Directory('${tempDir.path}/source');
    await sourceDir.create();
    final extract = await Process.run('tar', <String>[
      '-xf',
      archive.path,
      '-C',
      sourceDir.path,
      '--strip-components=4',
    ]);
    expect(extract.exitCode, 0, reason: '${extract.stdout}\n${extract.stderr}');
    expect(await _sha256(File('${sourceDir.path}/LICENSE')), _dracoLicenseHash);
    final sources = <String>[];
    await for (final entity
        in Directory('${sourceDir.path}/src/draco').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.cc')) continue;
      final basename = entity.uri.pathSegments.last;
      if (basename.contains('test') ||
          entity.path.contains('/javascript/') ||
          entity.path.contains('/tools/') ||
          entity.path.contains('/unity/')) {
        continue;
      }
      sources.add(entity.path);
    }
    sources.sort();
    final generator = File('test/fixtures/draco/Metadata/generate_fixture.cc');
    final executable = '${tempDir.path}/generator';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${sourceDir.path}/src',
      generator.path,
      ...sources,
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final regenerated = File('${tempDir.path}/metadata.drc');
    final generate = await Process.run(executable, <String>[regenerated.path]);
    expect(generate.exitCode, 0,
        reason: '${generate.stdout}\n${generate.stderr}');
    expect(
      await regenerated.readAsBytes(),
      await File('test/fixtures/draco/Metadata/metadata_nested_blob.drc')
          .readAsBytes(),
    );
    final readme =
        await File('test/fixtures/draco/Metadata/README.md').readAsString();
    expect(
      _metadataFixtureProvenanceViolations(
        readme: readme,
        licenseHash: _dracoLicenseHash,
        generatorHash: await _sha256(generator),
        payloadHash: await _sha256(regenerated),
      ),
      isEmpty,
    );
    for (final mutation in <({
      String label,
      String readme,
      String license,
      String generator,
      String payload
    })>[
      (
        label: 'commit',
        readme: readme.replaceAll(_dracoUpstreamCommit, ''.padRight(40, '0')),
        license: _dracoLicenseHash,
        generator: _metadataGeneratorHash,
        payload: _metadataPayloadHash,
      ),
      (
        label: 'source',
        readme: readme.replaceFirst(_dracoSourceObject, ''.padRight(40, '0')),
        license: _dracoLicenseHash,
        generator: _metadataGeneratorHash,
        payload: _metadataPayloadHash,
      ),
      (
        label: 'source archive',
        readme:
            readme.replaceFirst(_dracoSourceArchiveHash, ''.padRight(64, '0')),
        license: _dracoLicenseHash,
        generator: _metadataGeneratorHash,
        payload: _metadataPayloadHash,
      ),
      (
        label: 'license',
        readme: readme,
        license: ''.padRight(64, '0'),
        generator: _metadataGeneratorHash,
        payload: _metadataPayloadHash,
      ),
      (
        label: 'generator',
        readme: readme,
        license: _dracoLicenseHash,
        generator: ''.padRight(64, '0'),
        payload: _metadataPayloadHash,
      ),
      (
        label: 'payload',
        readme: readme,
        license: _dracoLicenseHash,
        generator: _metadataGeneratorHash,
        payload: ''.padRight(64, '0'),
      ),
    ]) {
      expect(
        _metadataFixtureProvenanceViolations(
          readme: mutation.readme,
          licenseHash: mutation.license,
          generatorHash: mutation.generator,
          payloadHash: mutation.payload,
        ),
        isNotEmpty,
        reason: mutation.label,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('structural metadata population is unreachable from mesh decode closure',
      () async {
    final closure = await _readPrunedDracoDecoderClosure();
    expect(closure.android, orderedEquals(closure.ios));
    final sources = await _readReachableDracoSources(
      closure.android,
    );
    expect(sources, isNotEmpty);
    expect(sources, contains('metadata/structural_metadata.cc'));

    // The owner is compiled because Mesh embeds StructuralMetadata, but its
    // population functions must not be retained by the accepted decode path.
    final tempDir = await Directory.systemTemp.createTemp('fsv_structural_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final deadStripFlag = Platform.isMacOS
        ? '-Wl,-dead_strip'
        : Platform.isLinux
            ? '-Wl,--gc-sections'
            : null;
    if (deadStripFlag == null) {
      markTestSkipped(
        'Structural metadata link reachability is supported on macOS/Linux.',
      );
      return;
    }
    final executable = '${tempDir.path}/metadata_dead_strip';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-pthread',
      '-ffunction-sections',
      '-fdata-sections',
      deadStripFlag,
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      'test/native/draco_metadata_conformance_runner.cc',
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final symbols = await Process.run('nm', <String>['-C', executable]);
    expect(symbols.exitCode, 0, reason: '${symbols.stdout}\n${symbols.stderr}');
    final symbolText = '${symbols.stdout}';
    expect(_structuralMetadataPopulationSymbols(symbolText), isEmpty);
    expect(
      _structuralMetadataPopulationSymbols(
        '$symbolText\n00000000 T draco::StructuralMetadata::SetSchema()',
      ),
      contains('StructuralMetadata::SetSchema'),
    );
  });

  test('Draco and BasisU controls coexist in one executable', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp.createTemp('fsv_controls_link_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/combined_controls.cc');
    await runner.writeAsString(_combinedControlsRunner);
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Iandroid/src/main/cpp',
      '-I../flutter_scene_viewer_basisu/android/src/main/cpp',
      runner.path,
      'android/src/main/cpp/fsv_draco_control.cc',
      '../flutter_scene_viewer_basisu/android/src/main/cpp/fsv_basisu_control.cc',
      '-o',
      '${tempDir.path}/combined_controls',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      '${tempDir.path}/combined_controls',
      const <String>[],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  });

  test('actual Android and iOS request owners pass executable lifecycle races',
      () async {
    final javac = await Process.run('javac', const <String>['-version']);
    final java = await Process.run('java', const <String>['-version']);
    final clang = await Process.run('clang++', const <String>['--version']);
    if (javac.exitCode != 0 || java.exitCode != 0 || clang.exitCode != 0) {
      markTestSkipped('javac, java, and clang++ are required.');
      return;
    }
    final javaOwner = File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/'
      'FsvDecodeRequestRegistry.java',
    );
    final iosHeader = File('ios/Classes/fsv_draco_request_registry.h');
    final iosSource = File('ios/Classes/fsv_draco_request_registry.cc');
    expect(await javaOwner.exists(), isTrue);
    expect(await iosHeader.exists(), isTrue);
    expect(await iosSource.exists(), isTrue);
    final tempDir = await Directory.systemTemp.createTemp('fsv_draco_owner_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final javaRunner = File('${tempDir.path}/DracoRegistryRunner.java');
    await javaRunner.writeAsString(_javaLifecycleRunner);
    final javaCompile = await Process.run('javac', <String>[
      '-d',
      tempDir.path,
      javaOwner.path,
      javaRunner.path,
    ]);
    expect(javaCompile.exitCode, 0,
        reason: '${javaCompile.stdout}\n${javaCompile.stderr}');
    final javaRun = await Process.run(
      'java',
      <String>[
        '-cp',
        tempDir.path,
        'com.marlonjd.flutter_scene_viewer_draco.DracoRegistryRunner',
      ],
    );
    expect(javaRun.exitCode, 0, reason: '${javaRun.stdout}\n${javaRun.stderr}');

    final nativeRunner = File('${tempDir.path}/registry_runner.cc');
    await nativeRunner.writeAsString(_nativeLifecycleRunner);
    final nativeCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-pthread',
      '-Iios/Classes',
      nativeRunner.path,
      'ios/Classes/fsv_draco_control.cc',
      iosSource.path,
      '-o',
      '${tempDir.path}/registry_runner',
    ]);
    expect(nativeCompile.exitCode, 0,
        reason: '${nativeCompile.stdout}\n${nativeCompile.stderr}');
    final nativeRun = await Process.run(
      '${tempDir.path}/registry_runner',
      const <String>[],
    );
    expect(nativeRun.exitCode, 0,
        reason: '${nativeRun.stdout}\n${nativeRun.stderr}');
  });

  test('lifecycle runner rejects owner state mutations', () async {
    await _expectOwnerMutationsRejected(
      packageName: 'com.marlonjd.flutter_scene_viewer_draco',
      runnerClass: 'DracoRegistryRunner',
      javaSourcePath:
          'android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/'
          'FsvDecodeRequestRegistry.java',
      javaRunner: _javaLifecycleRunner,
      nativeHeaderDirectory: 'ios/Classes',
      nativeControlPath: 'ios/Classes/fsv_draco_control.cc',
      nativeRegistryPath: 'ios/Classes/fsv_draco_request_registry.cc',
      nativeRunner: _nativeLifecycleRunner,
    );
  });

  test('mirrored decode control is cancellable and releases reservations',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp.createTemp('fsv_draco_control_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/control_runner.cc');
    await runner.writeAsString(_decodeControlRunner);
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      expect(await File('$platform/fsv_draco_control.h').exists(), isTrue);
      expect(await File('$platform/fsv_draco_control.cc').exists(), isTrue);
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I$platform',
        runner.path,
        '$platform/fsv_draco_control.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '$platform\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, 0,
          reason: '$platform\n${run.stdout}\n${run.stderr}');
      final controlSource =
          await File('$platform/fsv_draco_control.cc').readAsString();
      final mutantSource = controlSource.replaceFirst(
        'return stop_reason_.compare_exchange_strong(\n'
            '      reason, FsvDecodeStopReason::kCallerCancelled);',
        'const bool won = stop_reason_.compare_exchange_strong(\n'
            '      reason, FsvDecodeStopReason::kCallerCancelled);\n'
            '  return won && working_byte_limit_ != 0;',
      );
      expect(mutantSource, isNot(controlSource));
      final mutant = File('${tempDir.path}/control_mutant.cc');
      await mutant.writeAsString(mutantSource);
      final mutantExecutable = '$executable-mutant';
      final mutantCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-pthread',
        '-I$platform',
        runner.path,
        mutant.path,
        '-o',
        mutantExecutable,
      ]);
      expect(mutantCompile.exitCode, 0,
          reason: '$platform mutant\n'
              '${mutantCompile.stdout}\n${mutantCompile.stderr}');
      final mutantRun = await Process.run(mutantExecutable, const <String>[]);
      expect(mutantRun.exitCode, isNot(0),
          reason: '$platform Cancel() result mutation escaped the race runner');
      for (final mutation in <({String label, String before, String after})>[
        (
          label: 'reservation call',
          before: 'control == nullptr || control->TryReserve(bytes)',
          after: 'true',
        ),
        (
          label: 'RAII release call',
          before: 'control_->Release(bytes_);',
          after: '(void)bytes_;',
        ),
      ]) {
        final source = controlSource.replaceFirst(
          mutation.before,
          mutation.after,
        );
        expect(source, isNot(controlSource), reason: mutation.label);
        final file = File('${tempDir.path}/${mutation.label}.cc');
        await file.writeAsString(source);
        final output = '$executable-${mutation.label}';
        final compileMutation = await Process.run('clang++', <String>[
          '-std=c++17',
          '-pthread',
          '-I$platform',
          runner.path,
          file.path,
          '-o',
          output,
        ]);
        expect(compileMutation.exitCode, 0,
            reason: '$platform ${mutation.label}\n'
                '${compileMutation.stdout}\n${compileMutation.stderr}');
        final runMutation = await Process.run(output, const <String>[]);
        expect(runMutation.exitCode, isNot(0),
            reason: '$platform ${mutation.label} mutation escaped');
      }
    }
    expect(
      await File('android/src/main/cpp/fsv_draco_control.h').readAsString(),
      await File('ios/Classes/fsv_draco_control.h').readAsString(),
    );
    expect(
      await File('android/src/main/cpp/fsv_draco_control.cc').readAsString(),
      await File('ios/Classes/fsv_draco_control.cc').readAsString(),
    );
  });

  test('Android and iOS bridge ownership sources are byte-identical', () async {
    for (final name in <String>[
      'fsv_draco_control.h',
      'fsv_draco_control.cc',
      'fsv_draco_owned.h',
      'fsv_draco_codec_adapter.h',
      'fsv_draco_budget.h',
      'fsv_draco_budget.cc',
      'fsv_draco_bridge.h',
      'fsv_draco_bridge.cc',
    ]) {
      expect(
        await File('android/src/main/cpp/$name').readAsBytes(),
        await File('ios/Classes/$name').readAsBytes(),
        reason: '$name must remain mechanically mirrored',
      );
    }
    expect(
      await File('android/src/main/cpp/fsv_draco_budget.h').readAsString(),
      contains('#include "fsv_draco_owned.h"'),
    );
  });

  test('codec control records request-owned allocation provenance and release',
      () async {
    final provenance = File(
      'third_party/draco/FSV_CODEC_CONTROL_PROVENANCE.sha256',
    );
    expect(await provenance.exists(), isTrue);
    final manifest = await provenance.readAsString();
    expect(manifest, contains('upstream=google/draco@1.5.7'));
    expect(manifest, contains('compression/decode.cc'));
    expect(manifest, contains('mesh/mesh_edgebreaker_decoder_impl.cc'));
    final entries = RegExp(
      r'^original=[0-9a-f]{64} patched=([0-9a-f]{64}) path=(.+)$',
      multiLine: true,
    ).allMatches(manifest).toList();
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      final source = File('third_party/draco/${entry.group(2)}');
      final hash = await Process.run(
        'shasum',
        <String>['-a', '256', source.path],
      );
      expect(hash.exitCode, 0, reason: '${hash.stdout}\n${hash.stderr}');
      expect('${hash.stdout}'.split(' ').first, entry.group(1),
          reason: source.path);
    }
    final mutation = File('${Directory.systemTemp.path}/fsv_draco_hash_mutant');
    await mutation.writeAsString(
      '${await File('third_party/draco/${entries.first.group(2)}').readAsString()}\n',
    );
    addTearDown(() async {
      if (await mutation.exists()) await mutation.delete();
    });
    final mutatedHash = await Process.run(
      'shasum',
      <String>['-a', '256', mutation.path],
    );
    expect('${mutatedHash.stdout}'.split(' ').first,
        isNot(entries.first.group(1)));

    final header = await File(
      'android/src/main/cpp/fsv_draco_control.h',
    ).readAsString();
    expect(header, contains('peak_bytes() const'));
    expect(header, contains('allocation_count() const'));
    expect(header, contains('release_count() const'));
    expect(header, contains('reserve_rejection_count() const'));
    expect(header, contains('class FsvScopedWorkingReservation'));

    final allocatorHeader = await File(
      'third_party/draco/src/draco/core/fsv_decode_allocator.h',
    ).readAsString();
    expect(allocatorHeader, contains('class FsvDecodeControl'));
    expect(allocatorHeader, contains('class FsvDecodeAllocator'));
    expect(allocatorHeader, contains('class FsvDecodeBudgetExceeded'));

    final decodeHeader = await File(
      'third_party/draco/src/draco/compression/decode.h',
    ).readAsString();
    expect(decodeHeader, contains('draco/core/fsv_decode_allocator.h'));
    expect(decodeHeader, contains('DecodeMeshFromBuffer('));
    expect(decodeHeader, contains('FsvDecodeControl *control'));

    final edgebreaker = await File(
      'third_party/draco/src/draco/compression/mesh/mesh_edgebreaker_decoder_impl.cc',
    ).readAsString();
    expect(edgebreaker, contains('FSV LOCAL MODIFICATION'));
    expect(edgebreaker, contains('ShouldStopDecoding()'));
  });

  test(
      'request-scoped allocator foundation reserves before allocation and releases',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_allocator_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('test/native/draco_allocator_runner.cc');
    expect(await runner.exists(), isTrue);
    final executable = '${tempDir.path}/draco_allocator';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      runner.path,
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  });

  test('attribute deep copy and allocation headers retain exact control',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final runner = File('test/native/draco_attribute_copy_runner.cc');
    expect(await runner.exists(), isTrue);
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_attribute_copy_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/draco_attribute_copy';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      runner.path,
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('source_allocations=6'));
    expect('${run.stdout}', contains('destination_allocations=5'));
    expect('${run.stdout}', contains('header_edge_cases=4'));

    final copyPath =
        'third_party/draco/src/draco/attributes/point_attribute.cc';
    final copySource = await File(copyPath).readAsString();
    final copyControlMutant = copySource.replaceFirst(
      'AttributeTransformData(*src_att.attribute_transform_data_,\n'
          '                                   fsv_decode_control_)',
      'AttributeTransformData(*src_att.attribute_transform_data_)',
    );
    expect(copyControlMutant, isNot(copySource));
    final copyExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'transform_copy_control',
      mutatedSources: <String, String>{copyPath: copyControlMutant},
    );
    final copyRun = await Process.run(copyExecutable, const <String>[]);
    expect(copyRun.exitCode, isNot(0));
    expect('${copyRun.stdout}', contains('source_allocations=6'));
    expect('${copyRun.stdout}', contains('destination_allocations=4'));
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('allocation outcome atomically preserves heap-stop race winner',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_alloc_race_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('test/native/draco_allocation_race_runner.cc');
    expect(await runner.exists(), isTrue);
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_allocation_race';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-pthread',
        '-I$platform',
        runner.path,
        '$platform/fsv_draco_control.cc',
        '-o',
        executable,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '$platform\n${compile.stdout}\n${compile.stderr}',
      );
      final run = await Process.run(executable, const <String>[]);
      expect(
        run.exitCode,
        0,
        reason: '$platform\n${run.stdout}\n${run.stderr}',
      );
    }
  });

  test('Android and iOS compile identical pruned Draco decoder sources',
      () async {
    final closure = await _readPrunedDracoDecoderClosure();
    expect(closure.android, isNotEmpty);
    expect(closure.ios, closure.android);
  });

  test('Draco direct decoded objects use request allocation headers', () async {
    final sources = <String, String>{
      for (final path in <String>[
        'third_party/draco/src/draco/point_cloud/point_cloud.h',
        'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.h',
        'third_party/draco/src/draco/compression/mesh/'
            'mesh_edgebreaker_decoder_impl_interface.h',
        'third_party/draco/src/draco/compression/attributes/'
            'attributes_decoder_interface.h',
        'third_party/draco/src/draco/compression/attributes/'
            'points_sequencer.h',
        'third_party/draco/src/draco/compression/attributes/'
            'sequential_attribute_decoder.h',
        'third_party/draco/src/draco/attributes/point_attribute.h',
        'third_party/draco/src/draco/core/data_buffer.h',
        'third_party/draco/src/draco/attributes/attribute_transform_data.h',
        'third_party/draco/src/draco/compression/decode.cc',
      ])
        path: await File(path).readAsString(),
    };

    for (final owner in <({String path, String declaration})>[
      (
        path: 'third_party/draco/src/draco/point_cloud/point_cloud.h',
        declaration: 'class PointCloud : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/compression/point_cloud/'
            'point_cloud_decoder.h',
        declaration: 'class PointCloudDecoder : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/compression/mesh/'
            'mesh_edgebreaker_decoder_impl_interface.h',
        declaration: 'class MeshEdgebreakerDecoderImplInterface : '
            'public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/compression/attributes/'
            'attributes_decoder_interface.h',
        declaration:
            'class AttributesDecoderInterface : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/compression/attributes/'
            'points_sequencer.h',
        declaration: 'class PointsSequencer : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/compression/attributes/'
            'sequential_attribute_decoder.h',
        declaration:
            'class SequentialAttributeDecoder : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/attributes/point_attribute.h',
        declaration: 'class PointAttribute : public GeometryAttribute,\n'
            '                       public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/core/data_buffer.h',
        declaration: 'class DataBuffer : public FsvDecodeAllocated',
      ),
      (
        path: 'third_party/draco/src/draco/attributes/'
            'attribute_transform_data.h',
        declaration: 'class AttributeTransformData : public FsvDecodeAllocated',
      ),
    ]) {
      expect(
        sources[owner.path],
        contains(owner.declaration),
        reason: owner.path,
      );
    }

    final decode =
        sources['third_party/draco/src/draco/compression/decode.cc']!;
    expect(decode, contains('new (control) Mesh(control)'));
    expect(decode, contains('new (control) MeshSequentialDecoder(control)'));
    expect(decode, contains('new (control) MeshEdgebreakerDecoder(control)'));
  });

  test('Draco attribute value and transform storage uses the request allocator',
      () async {
    final generic = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'sequential_attribute_decoder.cc',
    ).readAsString();
    final integer = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'sequential_integer_attribute_decoder.cc',
    ).readAsString();
    final quantizationHeader = await File(
      'third_party/draco/src/draco/attributes/'
      'attribute_quantization_transform.h',
    ).readAsString();
    final quantizationSource = await File(
      'third_party/draco/src/draco/attributes/'
      'attribute_quantization_transform.cc',
    ).readAsString();
    final transform = await File(
      'third_party/draco/src/draco/attributes/attribute_transform.cc',
    ).readAsString();

    expect(generic, contains('FsvVector<uint8_t> value_data('));
    expect(integer, contains('FsvVector<AttributeTypeT> att_val('));
    expect(
      integer,
      contains('new (control) PointAttribute(ga, control)'),
    );
    expect(
      quantizationHeader,
      contains('FsvVector<float> min_values_'),
    );
    expect(
      quantizationSource,
      contains('FsvVector<float> att_val('),
    );
    expect(
      transform,
      contains('new (control) AttributeTransformData(control)'),
    );
    expect(
      transform,
      contains('new (control) PointAttribute(ga, control)'),
    );
  });

  test('Task 5C exact owner wiring rejects source mutants', () async {
    await _expectTask5cWiringMutations();
  });

  test('Edgebreaker wires request control into connectivity owners', () async {
    final decoder = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder.cc',
    ).readAsString();
    final implementationHeader = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.h',
    ).readAsString();
    final implementation = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.cc',
    ).readAsString();

    expect(
      decoder,
      contains('fsv_decode_control())'),
      reason: 'Every production Edgebreaker implementation needs the request.',
    );
    expect(
      implementationHeader,
      contains(
        'explicit MeshEdgebreakerDecoderImpl(FsvDecodeControl *control);',
      ),
    );
    expect(
      implementationHeader,
      contains('explicit AttributeData(FsvDecodeControl *control)'),
    );
    expect(
      implementation,
      contains('pos_encoding_data_(control)'),
    );
    expect(
      implementation,
      contains(
        'new (decoder_->fsv_decode_control())\n'
        '          CornerTable(decoder_->fsv_decode_control())',
      ),
    );
    expect(
      implementation,
      contains(
        'attribute_data_.emplace_back(decoder_->fsv_decode_control())',
      ),
    );
  });

  test('Edgebreaker topology scratch uses the request allocator', () async {
    final header = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.h',
    ).readAsString();
    final source = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.cc',
    ).readAsString();

    for (final marker in <String>[
      'FsvVector<CornerIndex> corner_traversal_stack_',
      'FsvVector<TopologySplitEventData> topology_split_data_',
      'FsvVector<bool> visited_faces_',
      'FsvUnorderedMap<int, int> new_to_parent_vertex_map_',
      'FsvVector<int32_t> attribute_seam_corners',
      'FsvVector<AttributeData> attribute_data_',
    ]) {
      expect(header, contains(marker), reason: marker);
    }
    for (final marker in <String>[
      'FsvVector<CornerIndex> active_corner_stack(',
      'FsvUnorderedMap<int, CornerIndex> topology_split_active_corners(',
      'FsvVector<VertexIndex> invalid_vertices(',
      'FsvVector<int32_t> point_to_corner_map(',
      'FsvVector<int32_t> corner_to_point_map(',
    ]) {
      expect(source, contains(marker), reason: marker);
    }
  });

  test('Edgebreaker traversal scratch uses the request allocator', () async {
    final standard = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_traversal_decoder.h',
    ).readAsString();
    final predictive = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_traversal_predictive_decoder.h',
    ).readAsString();
    final valence = await File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_traversal_valence_decoder.h',
    ).readAsString();
    final controller = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'sequential_attribute_decoders_controller.h',
    ).readAsString();
    final traverserBase = await File(
      'third_party/draco/src/draco/compression/mesh/traverser/'
      'traverser_base.h',
    ).readAsString();
    final depthFirst = await File(
      'third_party/draco/src/draco/compression/mesh/traverser/'
      'depth_first_traverser.h',
    ).readAsString();
    final maxPrediction = await File(
      'third_party/draco/src/draco/compression/mesh/traverser/'
      'max_prediction_degree_traverser.h',
    ).readAsString();

    expect(
      standard,
      contains('explicit MeshEdgebreakerTraversalDecoder('),
    );
    expect(standard, contains('FsvVector<BinaryDecoder>'));
    expect(predictive, contains('FsvVector<int> vertex_valences_'));
    expect(
      valence,
      contains('FsvVector<FsvVector<uint32_t>> context_symbols_'),
    );
    expect(valence, contains('FsvVector<int> context_counters_'));
    expect(controller, contains('FsvVector<PointIndex> point_ids_'));
    expect(traverserBase, contains('FsvVector<bool> is_face_visited_'));
    expect(traverserBase, contains('FsvVector<bool> is_vertex_visited_'));
    expect(
        depthFirst, contains('FsvVector<CornerIndex> corner_traversal_stack_'));
    expect(maxPrediction, contains('FsvVector<CornerIndex> traversal_stacks_'));
    expect(maxPrediction, contains('prediction_degree_(control)'));
  });

  test('Draco entropy decoder storage uses the request allocator', () async {
    final symbolDecoder = await File(
      'third_party/draco/src/draco/compression/entropy/'
      'rans_symbol_decoder.h',
    ).readAsString();
    final ans = await File(
      'third_party/draco/src/draco/compression/entropy/ans.h',
    ).readAsString();
    final symbolDecoding = await File(
      'third_party/draco/src/draco/compression/entropy/'
      'symbol_decoding.cc',
    ).readAsString();
    final integerDecoder = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'sequential_integer_attribute_decoder.cc',
    ).readAsString();

    expect(symbolDecoder, contains('explicit RAnsSymbolDecoder('));
    expect(symbolDecoder, contains('FsvVector<uint32_t> probability_table_'));
    expect(ans, contains('explicit RAnsDecoder(FsvDecodeControl *control)'));
    expect(ans, contains('FsvVector<uint32_t> lut_table_'));
    expect(ans, contains('FsvVector<rans_sym> probability_table_'));
    expect(symbolDecoding, contains('FsvDecodeControl *control'));
    expect(symbolDecoding, contains('tag_decoder(control)'));
    expect(integerDecoder, contains('decoder()->fsv_decode_control()'));
  });

  test('symbol bit decoder is unreachable from the mesh decode slice',
      () async {
    final closure = await _readPrunedDracoDecoderClosure();
    expect(closure.ios, closure.android);
    const entropySource = 'compression/entropy/symbol_decoding.cc';
    const entropyHeader = 'compression/entropy/symbol_decoding.h';
    expect(
      closure.android,
      contains(entropySource),
      reason: 'The reachability audit must use the real pruned compiled '
          'closure, including compiled entropy/helper sources.',
    );
    expect(closure.android, contains(_symbolBitDecoderDefinitionSource));

    final sources = await _readReachableDracoSources(closure.android);
    expect(
      sources,
      contains(entropyHeader),
      reason: 'The reachability audit must recursively include repo-local '
          'headers used by the selected translation units.',
    );
    expect(sources.keys, containsAll(_symbolBitDecoderOwnerSources));
    expect(
      _symbolBitDecoderUseSites(sources),
      isEmpty,
      reason: 'The unconverted SymbolBitDecoder storage is allowed only while '
          'the mesh decoder slice has no reference to that codec.',
    );

    final entropyMutation = <String, String>{
      ...sources,
      entropySource: '${sources[entropySource]}\n'
          'void FsvInjectedSymbolBitUse(SymbolBitDecoder* decoder);\n',
    };
    expect(
      _symbolBitDecoderUseSites(entropyMutation),
      <String>[entropySource],
      reason: 'A use added to a compiled entropy/helper source must fail the '
          'same actual-closure reachability contract.',
    );

    final headerMutation = <String, String>{
      ...sources,
      entropyHeader: '${sources[entropyHeader]}\n'
          'void FsvInjectedHeaderSymbolBitUse(SymbolBitDecoder* decoder);\n',
    };
    expect(
      _symbolBitDecoderUseSites(headerMutation),
      <String>[entropyHeader],
      reason: 'A use added to a reachable repo-local header must fail the '
          'same actual-closure reachability contract.',
    );
  });

  test('mesh prediction objects and scratch use the request allocator',
      () async {
    final factory = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/prediction_scheme_decoder_factory.h',
    ).readAsString();
    final delta = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/prediction_scheme_delta_decoder.h',
    ).readAsString();
    final parallelogram = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/mesh_prediction_scheme_parallelogram_decoder.h',
    ).readAsString();
    final constrained = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/'
      'mesh_prediction_scheme_constrained_multi_parallelogram_decoder.h',
    ).readAsString();
    final portableTexCoords = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/'
      'mesh_prediction_scheme_tex_coords_portable_predictor.h',
    ).readAsString();
    final wrap = await File(
      'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/prediction_scheme_wrap_transform_base.h',
    ).readAsString();

    expect(factory, contains('new (decoder->fsv_decode_control())'));
    expect(factory, contains('FsvPredictionTransform<TransformT>('));
    expect(delta, contains('FsvVector<DataTypeT> zero_vals('));
    expect(parallelogram, contains('FsvVector<DataTypeT> pred_vals('));
    expect(constrained, contains('FsvVector<bool> is_crease_edge_'));
    expect(constrained, contains('FsvVector<DataTypeT> pred_vals'));
    expect(portableTexCoords, contains('FsvVector<bool> orientations_'));
    expect(wrap, contains('FsvVector<DataTypeT> clamped_value_'));
    await _expectTask5bWiringMutations();
  });

  test('platform handlers own bounded request registries and detach drains',
      () async {
    final android = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/'
      'FlutterSceneViewerDracoPlugin.java',
    ).readAsString();
    final androidRegistry = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/'
      'FsvDecodeRequestRegistry.java',
    ).readAsString();
    final ios = await File('ios/Classes/FlutterSceneViewerDracoPlugin.mm')
        .readAsString();
    final jni = await File(
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
    ).readAsString();
    final cmake = await File('android/CMakeLists.txt').readAsString();
    expect(android, contains('new ArrayBlockingQueue<Runnable>(32)'));
    expect(android, contains('requestRegistry.register(requestId, request)'));
    expect(android, contains('METHOD_CANCEL_DECODE'));
    expect(android, contains('executor.shutdownNow()'));
    expect(android, contains('while (!executor.isTerminated())'));
    expect(android, contains('requestRegistry.drainAfterWorkers()'));
    expect(androidRegistry, contains('synchronized String cancel('));
    expect(androidRegistry, contains('synchronized FinishDisposition finish('));
    expect(androidRegistry, contains('entry.control.destroy()'));
    expect(ios, contains('DISPATCH_QUEUE_SERIAL'));
    expect(ios, contains('fsv_draco::FsvDecodeRequestRegistry'));
    expect(ios, contains('detachFromEngineForRegistrar'));
    expect(ios, contains('dispatch_sync(_decodeQueue'));
    expect(ios, contains('_requestRegistry->DrainAfterWorkers()'));
    expect(ios, contains('kMethodCancelDecode'));
    expect(jni, contains('nativeCreateDecodeControl'));
    expect(jni, contains('nativeCancelDecodeControl'));
    expect(jni, contains('control_handle'));
    expect(cmake, contains('fsv_draco_control.cc'));
  });

  test('real bridge matches Google Draco 1.5.7 for official bitstream 2.2 Box',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    const fixtureRoot = 'test/fixtures/draco/Box/glTF-Draco';
    final gltfFile = File('$fixtureRoot/Box.gltf');
    final binFile = File('$fixtureRoot/Box.bin');
    final licenseFile = File('test/fixtures/draco/Box/LICENSE.txt');
    expect(await gltfFile.exists(), isTrue);
    expect(await binFile.exists(), isTrue);
    expect(await licenseFile.exists(), isTrue);

    final gltf = Map<String, Object?>.from(
      jsonDecode(await gltfFile.readAsString()) as Map,
    );
    final meshes = gltf['meshes']! as List<Object?>;
    final mesh = Map<String, Object?>.from(meshes.single! as Map);
    final primitives = mesh['primitives']! as List<Object?>;
    final primitive = Map<String, Object?>.from(primitives.single! as Map);
    final extensions = Map<String, Object?>.from(
      primitive['extensions']! as Map,
    );
    final draco = Map<String, Object?>.from(
      extensions['KHR_draco_mesh_compression']! as Map,
    );
    expect(primitive['mode'], 4);
    expect(
      Map<String, Object?>.from(primitive['attributes']! as Map),
      <String, Object?>{'NORMAL': 1, 'POSITION': 2},
    );
    expect(
      Map<String, Object?>.from(draco['attributes']! as Map),
      <String, Object?>{'NORMAL': 0, 'POSITION': 1},
    );
    final accessors = (gltf['accessors']! as List<Object?>)
        .map((entry) => Map<String, Object?>.from(entry! as Map))
        .toList(growable: false);
    expect(accessors[0], containsPair('count', 36));
    expect(accessors[0], containsPair('componentType', 5123));
    expect(accessors[1], containsPair('count', 24));
    expect(accessors[1], containsPair('componentType', 5126));
    expect(accessors[1], containsPair('type', 'VEC3'));
    expect(accessors[2], containsPair('count', 24));
    expect(accessors[2], containsPair('componentType', 5126));
    expect(accessors[2], containsPair('type', 'VEC3'));

    final bin = await binFile.readAsBytes();
    expect(bin, hasLength(120));
    expect(bin.sublist(0, 7), <int>[0x44, 0x52, 0x41, 0x43, 0x4f, 2, 2]);

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_conformance_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('test/native/draco_conformance_runner.cc');
    expect(await runner.exists(), isTrue);
    final executable = '${tempDir.path}/draco_conformance';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      runner.path,
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(executable, <String>[binFile.path]);
    expect(
      run.exitCode,
      0,
      reason: '${run.stdout}\n${run.stderr}',
    );
    expect(
      const LineSplitter().convert('${run.stdout}'),
      containsAll(<String>[
        'box_allocation_ordinals=132',
        'box_codec_allocation_ordinals=110',
        'box_bridge_peak_bytes=24926',
        'codec_dispatch_cancel=attributed',
        'codec_dispatch_deadline=attributed',
        'box_peak_minus_one=budgetExceeded',
        'two_primitive_allocation_ordinals=256',
        'two_primitive_bridge_peak_bytes=27594',
      ]),
    );

    final bridgeSource = await File(
      'android/src/main/cpp/fsv_draco_bridge.cc',
    ).readAsString();
    final terminalMutants = <String, String>{
      'codec_dispatch_cancel_terminal': bridgeSource.replaceFirst(
        'FsvDracoTerminalOutcomeKind::kCallerCancelled;\n      return;',
        'FsvDracoTerminalOutcomeKind::kNone;\n      return;',
      ),
      'codec_dispatch_deadline_terminal': bridgeSource.replaceFirst(
        'FsvDracoTerminalOutcomeKind::kDeadline;\n      return;',
        'FsvDracoTerminalOutcomeKind::kNone;\n      return;',
      ),
      'codec_dispatch_post_stop_diagnostic': bridgeSource.replaceFirst(
        'SetTerminalOutcome(&result, control, requests);\n'
            '    return result;\n  }\n  FsvDracoCodecControlAdapter',
        'SetTerminalOutcome(&result, control, requests);\n'
            '    result.diagnostics.emplace_back(control);\n'
            '    return result;\n  }\n  FsvDracoCodecControlAdapter',
      ),
      'outer_reservation_reintroduced': bridgeSource.replaceFirst(
        'FsvDracoCodecControlAdapter codec_control(control);',
        'fsv_draco::FsvScopedWorkingReservation outer_reservation(\n'
            '      control, preflight.native_output_bytes);\n'
            '  if (!outer_reservation.ok()) return result;\n'
            '  FsvDracoCodecControlAdapter codec_control(control);',
      ),
    };
    for (final entry in terminalMutants.entries) {
      expect(entry.value, isNot(bridgeSource), reason: entry.key);
      final mutantBridge = File('${tempDir.path}/${entry.key}.cc');
      await mutantBridge.writeAsString(entry.value);
      final mutantExecutable = '${tempDir.path}/${entry.key}';
      final mutantCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-Ithird_party/draco/src',
        '-Iandroid/src/main/cpp',
        runner.path,
        'android/src/main/cpp/fsv_draco_budget.cc',
        'android/src/main/cpp/fsv_draco_control.cc',
        mutantBridge.path,
        'ios/Classes/fsv_draco_vendor_sources.cc',
        '-o',
        mutantExecutable,
      ]);
      expect(
        mutantCompile.exitCode,
        0,
        reason:
            '${entry.key}: ${mutantCompile.stdout}\n${mutantCompile.stderr}',
      );
      final mutantRun = await Process.run(mutantExecutable, <String>[
        binFile.path,
      ]);
      expect(
        mutantRun.exitCode,
        isNot(0),
        reason: '${entry.key} escaped: ${mutantRun.stdout}\n'
            '${mutantRun.stderr}',
      );
    }

    final implementation = File(
      'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.cc',
    );
    final implementationSource = await implementation.readAsString();
    const reachedOwner = 'FsvVector<CornerIndex> active_corner_stack(\n'
        '      FsvDecodeAllocator<CornerIndex>('
        'decoder_->fsv_decode_control()));';
    const bypassedOwner = 'FsvVector<CornerIndex> active_corner_stack(\n'
        '      FsvDecodeAllocator<CornerIndex>(nullptr));';
    final mutantImplementation = implementationSource.replaceFirst(
      reachedOwner,
      bypassedOwner,
    );
    expect(mutantImplementation, isNot(implementationSource));
    final mutantImplementationFile =
        File('${tempDir.path}/mesh_edgebreaker_decoder_impl_mutant.cc');
    await mutantImplementationFile.writeAsString(mutantImplementation);

    final aggregate = await File(
      'ios/Classes/fsv_draco_vendor_sources.cc',
    ).readAsString();
    final absoluteAggregate = aggregate.replaceAllMapped(
      RegExp(r'^#include "([^"]+\.cc)"$', multiLine: true),
      (match) {
        final included = match.group(1)!;
        if (included.endsWith('/mesh_edgebreaker_decoder_impl.cc')) {
          return '#include "${mutantImplementationFile.path}"';
        }
        return '#include "${File('ios/Classes/$included').absolute.path}"';
      },
    );
    final mutantAggregate = File('${tempDir.path}/vendor_sources_mutant.cc');
    await mutantAggregate.writeAsString(absoluteAggregate);
    final mutantExecutable = '${tempDir.path}/draco_conformance_mutant';
    final mutantCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      runner.path,
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      mutantAggregate.path,
      '-o',
      mutantExecutable,
    ]);
    expect(
      mutantCompile.exitCode,
      0,
      reason: '${mutantCompile.stdout}\n${mutantCompile.stderr}',
    );
    final mutantRun = await Process.run(
      mutantExecutable,
      <String>[binFile.path],
    );
    expect(
      mutantRun.exitCode,
      isNot(0),
      reason: 'A reached-owner allocator bypass shrank the dynamic sweep to '
          '${mutantRun.stdout} without failing the locked Box baseline.',
    );

    final decodePath = 'third_party/draco/src/draco/compression/decode.cc';
    final decodeSource = await File(decodePath).readAsString();
    final directObjectMutant = decodeSource.replaceFirst(
      'new (control) Mesh(control)',
      'new Mesh(control)',
    );
    expect(directObjectMutant, isNot(decodeSource));
    final directObjectExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'direct_object',
      mutatedSources: <String, String>{decodePath: directObjectMutant},
    );
    final directObjectRun = await Process.run(
      directObjectExecutable,
      <String>[binFile.path],
    );
    expect(directObjectRun.exitCode, isNot(0));
    expect(
      '${directObjectRun.stdout}',
      contains('box_codec_allocation_ordinals=109'),
      reason: 'The compiled direct Mesh-owner bypass must be detected by the '
          'exact Box baseline.',
    );

    final cornerTablePath = 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc';
    final cornerTableSource = await File(cornerTablePath).readAsString();
    final cornerTableMutant = cornerTableSource.replaceFirst(
      'new (decoder_->fsv_decode_control())\n'
          '          CornerTable(decoder_->fsv_decode_control())',
      'new CornerTable(decoder_->fsv_decode_control())',
    );
    expect(cornerTableMutant, isNot(cornerTableSource));
    final cornerTableExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'corner_table_object',
      mutatedSources: <String, String>{cornerTablePath: cornerTableMutant},
    );
    final cornerTableRun =
        await Process.run(cornerTableExecutable, <String>[binFile.path]);
    expect(cornerTableRun.exitCode, isNot(0));
    expect(
      '${cornerTableRun.stdout}',
      contains('box_codec_allocation_ordinals=109'),
      reason: 'The compiled CornerTable object bypass must reduce the exact '
          'Box baseline by one.',
    );
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('sequential mesh fixture matches direct Draco and sweeps allocations',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    const fixtureRoot = 'test/fixtures/draco/Sequential';
    final fixture = File('$fixtureRoot/sequential_quantized_generic.drc');
    final generator = File('$fixtureRoot/generate_fixture.cc');
    final fixtureReadme = File('$fixtureRoot/README.md');
    expect(await fixture.exists(), isTrue);
    expect(await generator.exists(), isTrue);
    expect(await fixtureReadme.exists(), isTrue);
    expect(await fixture.length(), 132);
    final hashes = await Future.wait(<Future<ProcessResult>>[
      Process.run('shasum', <String>['-a', '256', fixture.path]),
      Process.run('shasum', <String>['-a', '256', generator.path]),
    ]);
    expect('${hashes[0].stdout}'.split(' ').first, _sequentialPayloadHash);
    expect('${hashes[1].stdout}'.split(' ').first, _sequentialGeneratorHash);

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_sequential_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('test/native/draco_sequential_conformance_runner.cc');
    expect(await runner.exists(), isTrue);
    final executable = '${tempDir.path}/draco_sequential_conformance';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Ithird_party/draco/src',
      '-Iandroid/src/main/cpp',
      runner.path,
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, <String>[fixture.path]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(
      const LineSplitter().convert('${run.stdout}'),
      containsAll(<String>[
        'sequential_allocation_ordinals=96',
        'sequential_codec_allocation_ordinals=68',
        'sequential_bridge_peak_bytes=20921',
      ]),
    );

    final pointAttributePath =
        'third_party/draco/src/draco/compression/attributes/'
        'attributes_decoder.cc';
    final pointAttributeSource = await File(pointAttributePath).readAsString();
    final pointAttributeMutant = pointAttributeSource.replaceFirst(
      'new (pc->fsv_decode_control())\n'
          '            PointAttribute(ga, pc->fsv_decode_control())',
      'new PointAttribute(ga, pc->fsv_decode_control())',
    );
    expect(pointAttributeMutant, isNot(pointAttributeSource));
    final pointAttributeExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'decoded_point_attribute',
      mutatedSources: <String, String>{
        pointAttributePath: pointAttributeMutant,
      },
    );
    final pointAttributeRun =
        await Process.run(pointAttributeExecutable, <String>[fixture.path]);
    expect(pointAttributeRun.exitCode, isNot(0));
    expect(
      '${pointAttributeRun.stdout}',
      contains('sequential_codec_allocation_ordinals=65'),
      reason: 'Bypassing the three decoded PointAttribute object allocations '
          'must reduce the exact sequential baseline by three.',
    );

    final quantizationHeaderPath = 'third_party/draco/src/draco/attributes/'
        'attribute_quantization_transform.h';
    final quantizationHeaderSource =
        await File(quantizationHeaderPath).readAsString();
    final quantizationMinimumMutant = quantizationHeaderSource.replaceFirst(
      'min_values_(FsvDecodeAllocator<float>(control))',
      'min_values_(FsvDecodeAllocator<float>(nullptr))',
    );
    expect(quantizationMinimumMutant, isNot(quantizationHeaderSource));
    final quantizationMinimumExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'quantization_minimum_storage',
      mutatedSources: const <String, String>{},
      mutatedHeaders: <String, String>{
        quantizationHeaderPath: quantizationMinimumMutant,
      },
    );
    final quantizationMinimumRun = await Process.run(
      quantizationMinimumExecutable,
      <String>[fixture.path],
    );
    expect(quantizationMinimumRun.exitCode, isNot(0));
    expect(
      '${quantizationMinimumRun.stdout}',
      contains('sequential_codec_allocation_ordinals=67'),
      reason: 'The compiled quantization-minimum allocator bypass must reduce '
          'the exact sequential baseline by one.',
    );

    final inverseQuantizationPath = 'third_party/draco/src/draco/attributes/'
        'attribute_quantization_transform.cc';
    final inverseQuantizationSource =
        await File(inverseQuantizationPath).readAsString();
    final inverseQuantizationMutant = inverseQuantizationSource.replaceFirst(
      'FsvDecodeAllocator<float>(fsv_decode_control_)',
      'FsvDecodeAllocator<float>(nullptr)',
    );
    expect(inverseQuantizationMutant, isNot(inverseQuantizationSource));
    final inverseQuantizationExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'inverse_quantization_scratch',
      mutatedSources: <String, String>{
        inverseQuantizationPath: inverseQuantizationMutant,
      },
    );
    final inverseQuantizationRun = await Process.run(
      inverseQuantizationExecutable,
      <String>[fixture.path],
    );
    expect(inverseQuantizationRun.exitCode, isNot(0));
    expect(
      '${inverseQuantizationRun.stdout}',
      contains('sequential_codec_allocation_ordinals=67'),
      reason: 'The compiled inverse-quantization scratch bypass must reduce '
          'the exact sequential baseline by one.',
    );

    final sequentialPath = 'third_party/draco/src/draco/compression/mesh/'
        'mesh_sequential_decoder.cc';
    final sequentialSource = await File(sequentialPath).readAsString();
    final topologyMutant = sequentialSource.replaceFirst(
      'FsvDecodeAllocator<uint32_t>(fsv_decode_control())',
      'FsvDecodeAllocator<uint32_t>(nullptr)',
    );
    expect(topologyMutant, isNot(sequentialSource));
    final topologyExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'sequential_topology',
      mutatedSources: <String, String>{sequentialPath: topologyMutant},
    );
    final topologyRun = await Process.run(
      topologyExecutable,
      <String>[fixture.path],
    );
    expect(topologyRun.exitCode, isNot(0));
    expect('${topologyRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final integerPath = 'third_party/draco/src/draco/compression/attributes/'
        'sequential_integer_attribute_decoder.cc';
    final integerSource = await File(integerPath).readAsString();
    final attributeStorageMutant = integerSource.replaceFirst(
      'FsvDecodeAllocator<AttributeTypeT>(control)',
      'FsvDecodeAllocator<AttributeTypeT>(nullptr)',
    );
    expect(attributeStorageMutant, isNot(integerSource));
    final attributeStorageExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'attribute_storage',
      mutatedSources: <String, String>{
        integerPath: attributeStorageMutant,
      },
    );
    final attributeStorageRun = await Process.run(
      attributeStorageExecutable,
      <String>[fixture.path],
    );
    expect(attributeStorageRun.exitCode, isNot(0));
    expect('${attributeStorageRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final genericPath = 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoder.cc';
    final genericSource = await File(genericPath).readAsString();
    final genericScratchMutant = genericSource.replaceFirst(
      'FsvDecodeAllocator<uint8_t>(control)',
      'FsvDecodeAllocator<uint8_t>(nullptr)',
    );
    expect(genericScratchMutant, isNot(genericSource));
    final genericScratchExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'generic_scratch',
      mutatedSources: <String, String>{genericPath: genericScratchMutant},
    );
    final genericScratchRun = await Process.run(
      genericScratchExecutable,
      <String>[fixture.path],
    );
    expect(
      genericScratchRun.exitCode,
      isNot(0),
      reason: 'The sequential fixture must reach generic raw-value scratch.',
    );
    expect('${genericScratchRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final decodePath = 'third_party/draco/src/draco/compression/decode.cc';
    final decodeSource = await File(decodePath).readAsString();
    final concreteDecoderMutant = decodeSource.replaceFirst(
      'new (control) MeshSequentialDecoder(control)',
      'new MeshSequentialDecoder(control)',
    );
    expect(concreteDecoderMutant, isNot(decodeSource));
    final concreteDecoderExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'concrete_decoder',
      mutatedSources: <String, String>{decodePath: concreteDecoderMutant},
    );
    final concreteDecoderRun = await Process.run(
      concreteDecoderExecutable,
      <String>[fixture.path],
    );
    expect(concreteDecoderRun.exitCode, isNot(0));
    expect('${concreteDecoderRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final controllerMutant = sequentialSource.replaceFirst(
      'new (fsv_decode_control()) SequentialAttributeDecodersController(',
      'new SequentialAttributeDecodersController(',
    );
    expect(controllerMutant, isNot(sequentialSource));
    final controllerExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'attributes_controller',
      mutatedSources: <String, String>{sequentialPath: controllerMutant},
    );
    final controllerRun =
        await Process.run(controllerExecutable, <String>[fixture.path]);
    expect(controllerRun.exitCode, isNot(0));
    expect('${controllerRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final sequencerMutant = sequentialSource.replaceFirst(
      'new (fsv_decode_control())\n                      LinearSequencer(',
      'new LinearSequencer(',
    );
    expect(sequencerMutant, isNot(sequentialSource));
    final sequencerExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'points_sequencer',
      mutatedSources: <String, String>{sequentialPath: sequencerMutant},
    );
    final sequencerRun =
        await Process.run(sequencerExecutable, <String>[fixture.path]);
    expect(sequencerRun.exitCode, isNot(0));
    expect('${sequencerRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final transformPath =
        'third_party/draco/src/draco/attributes/attribute_transform.cc';
    final transformSource = await File(transformPath).readAsString();
    final transformObjectMutant = transformSource.replaceFirst(
      'new (control) AttributeTransformData(control)',
      'new AttributeTransformData(control)',
    );
    expect(transformObjectMutant, isNot(transformSource));
    final transformObjectExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'transform_object',
      mutatedSources: <String, String>{transformPath: transformObjectMutant},
    );
    final transformObjectRun =
        await Process.run(transformObjectExecutable, <String>[fixture.path]);
    expect(transformObjectRun.exitCode, isNot(0));
    expect('${transformObjectRun.stdout}',
        contains('sequential_codec_allocation_ordinals=67'));

    final transformDataPath =
        'third_party/draco/src/draco/attributes/attribute_transform_data.h';
    final transformDataSource = await File(transformDataPath).readAsString();
    final transformBufferMutant = transformDataSource.replaceFirst(
      'buffer_(control)',
      'buffer_(nullptr)',
    );
    expect(transformBufferMutant, isNot(transformDataSource));
    final transformBufferExecutable = await _compileDracoAggregateMutant(
      tempDir: tempDir,
      runner: runner,
      label: 'transform_data_buffer',
      mutatedSources: const <String, String>{},
      mutatedHeaders: <String, String>{
        transformDataPath: transformBufferMutant,
      },
    );
    final transformBufferRun =
        await Process.run(transformBufferExecutable, <String>[fixture.path]);
    expect(transformBufferRun.exitCode, isNot(0));
    expect('${transformBufferRun.stdout}',
        contains('sequential_codec_allocation_ordinals=64'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('sequential fixture regenerates from immutable pinned source archive',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    final git = await Process.run('git', const <String>['--version']);
    final tar = await Process.run('tar', const <String>['--version']);
    if (clang.exitCode != 0 || git.exitCode != 0 || tar.exitCode != 0) {
      markTestSkipped('clang++, git, and tar are required.');
      return;
    }

    const fixtureRoot = 'test/fixtures/draco/Sequential';
    final fixture = File('$fixtureRoot/sequential_quantized_generic.drc');
    final generator = File('$fixtureRoot/generate_fixture.cc');
    final fixtureReadme = File('$fixtureRoot/README.md');
    final readme = await fixtureReadme.readAsString();
    final generatorHash = await _sha256(generator);
    final payloadHash = await _sha256(fixture);
    expect(
      _sequentialFixtureProvenanceViolations(
        readme: readme,
        licenseHash: _dracoLicenseHash,
        generatorHash: generatorHash,
        payloadHash: payloadHash,
      ),
      isEmpty,
    );

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_pinned_fixture_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final archive = File('${tempDir.path}/draco-1.5.7.tar');
    final archiveResult = await Process.run(
        'git',
        <String>[
          'archive',
          '--format=tar',
          '--output=${archive.path}',
          _dracoSourceObject,
          'packages/flutter_scene_viewer_draco/third_party/draco',
        ],
        workingDirectory: '../..');
    expect(
      archiveResult.exitCode,
      0,
      reason: '${archiveResult.stdout}\n${archiveResult.stderr}',
    );
    expect(await _sha256(archive), _dracoSourceArchiveHash);

    final sourceDir = Directory('${tempDir.path}/source');
    await sourceDir.create();
    final extract = await Process.run(
      'tar',
      <String>[
        '-xf',
        archive.path,
        '-C',
        sourceDir.path,
        '--strip-components=4',
      ],
    );
    expect(extract.exitCode, 0, reason: '${extract.stdout}\n${extract.stderr}');
    final pinnedLicense = File('${sourceDir.path}/LICENSE');
    expect(await _sha256(pinnedLicense), _dracoLicenseHash);
    expect(
      await pinnedLicense.readAsString(),
      contains('Apache License\n                           Version 2.0'),
    );

    final sources = <String>[];
    await for (final entity
        in Directory('${sourceDir.path}/src/draco').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.cc')) continue;
      final basename = entity.uri.pathSegments.last;
      if (basename.contains('test') ||
          entity.path.contains('/javascript/') ||
          entity.path.contains('/tools/') ||
          entity.path.contains('/unity/')) {
        continue;
      }
      sources.add(entity.path);
    }
    sources.sort();
    expect(sources, isNotEmpty);
    final executable = '${tempDir.path}/generate_fixture';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${sourceDir.path}/src',
      generator.path,
      ...sources,
      '-o',
      executable,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final regenerated = File('${tempDir.path}/regenerated.drc');
    final generate = await Process.run(executable, <String>[regenerated.path]);
    expect(
      generate.exitCode,
      0,
      reason: '${generate.stdout}\n${generate.stderr}',
    );
    expect(await regenerated.readAsBytes(), await fixture.readAsBytes());

    final mutations = <({String label, List<String> violations})>[
      (
        label: 'commit',
        violations: _sequentialFixtureProvenanceViolations(
          readme: readme.replaceFirst(
            _dracoUpstreamCommit,
            ''.padRight(40, '0'),
          ),
          licenseHash: _dracoLicenseHash,
          generatorHash: generatorHash,
          payloadHash: payloadHash,
        ),
      ),
      (
        label: 'license',
        violations: _sequentialFixtureProvenanceViolations(
          readme: readme,
          licenseHash: ''.padRight(64, '0'),
          generatorHash: generatorHash,
          payloadHash: payloadHash,
        ),
      ),
      (
        label: 'generator',
        violations: _sequentialFixtureProvenanceViolations(
          readme: readme,
          licenseHash: _dracoLicenseHash,
          generatorHash: ''.padRight(64, '0'),
          payloadHash: payloadHash,
        ),
      ),
      (
        label: 'payload',
        violations: _sequentialFixtureProvenanceViolations(
          readme: readme,
          licenseHash: _dracoLicenseHash,
          generatorHash: generatorHash,
          payloadHash: ''.padRight(64, '0'),
        ),
      ),
    ];
    for (final mutation in mutations) {
      expect(
        mutation.violations,
        contains(mutation.label),
        reason: '${mutation.label} provenance mutation escaped',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'Android and iOS native budget preflight accept exact limits and reject overflow',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final androidHeader = File('android/src/main/cpp/fsv_draco_budget.h');
    final androidSource = File('android/src/main/cpp/fsv_draco_budget.cc');
    final iosHeader = File('ios/Classes/fsv_draco_budget.h');
    final iosSource = File('ios/Classes/fsv_draco_budget.cc');
    expect(await androidHeader.exists(), isTrue);
    expect(await androidSource.exists(), isTrue);
    expect(await iosHeader.exists(), isTrue);
    expect(await iosSource.exists(), isTrue);
    expect(await androidHeader.readAsString(), await iosHeader.readAsString());
    expect(await androidSource.readAsString(), await iosSource.readAsString());
    expect(
      await File('android/src/main/cpp/fsv_draco_bridge.h').readAsString(),
      await File('ios/Classes/fsv_draco_bridge.h').readAsString(),
    );
    expect(
      await File('android/src/main/cpp/fsv_draco_bridge.cc').readAsString(),
      await File('ios/Classes/fsv_draco_bridge.cc').readAsString(),
    );

    final tempDir = await Directory.systemTemp.createTemp('fsv_draco_budget_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/budget_preflight_test.cc');
    await runner.writeAsString(_budgetPreflightRunner);

    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_budget';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I$platform',
        runner.path,
        '$platform/fsv_draco_budget.cc',
        '$platform/fsv_draco_control.cc',
        '-o',
        executable,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '$platform\n${compile.stdout}\n${compile.stderr}',
      );
      final run = await Process.run(executable, const <String>[]);
      expect(
        run.exitCode,
        0,
        reason: '$platform\n${run.stdout}\n${run.stderr}',
      );
    }
  });

  test('Android and iOS bridges define the identical primitive decode symbol',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_draco_bridge_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final objectPath =
          '${tempDir.path}/fsv_draco_bridge_${platform.startsWith('android') ? 'android' : 'ios'}.o';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-Ithird_party/draco/src',
        '-I$platform',
        '-c',
        '$platform/fsv_draco_bridge.cc',
        '-o',
        objectPath,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '$platform\n${compile.stdout}\n${compile.stderr}',
      );

      final symbols = await Process.run('nm', <String>[objectPath]);
      expect(
        symbols.exitCode,
        0,
        reason: '${symbols.stdout}\n${symbols.stderr}',
      );
      expect(
        '${symbols.stdout}\n${symbols.stderr}',
        contains('FsvDracoDecodePrimitives'),
      );
    }
  });

  test('post-decode missing attribute allocates no output vectors', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_post_decode_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final fakeRoot = Directory('${tempDir.path}/fake');
    await Directory('${fakeRoot.path}/draco/compression')
        .create(recursive: true);
    await Directory('${fakeRoot.path}/draco/core').create(recursive: true);
    await Directory('${fakeRoot.path}/draco/mesh').create(recursive: true);
    await File('${fakeRoot.path}/draco/mesh/mesh.h')
        .writeAsString(_fakeDracoMeshHeader);
    await File('${fakeRoot.path}/draco/core/decoder_buffer.h')
        .writeAsString(_fakeDracoBufferHeader);
    await File('${fakeRoot.path}/draco/compression/decode.h')
        .writeAsString(_fakeDracoDecodeHeader);
    final runner = File('${tempDir.path}/post_decode_test.cc');
    await runner.writeAsString(_postDecodeBridgeRunner);

    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_post_decode';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I${fakeRoot.path}',
        '-Ithird_party/draco/src',
        '-I$platform',
        runner.path,
        '$platform/fsv_draco_budget.cc',
        '$platform/fsv_draco_control.cc',
        '$platform/fsv_draco_bridge.cc',
        '-o',
        executable,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '$platform\n${compile.stdout}\n${compile.stderr}',
      );
      final run = await Process.run(executable, const <String>[]);
      expect(
        run.exitCode,
        0,
        reason: '$platform\n${run.stdout}\n${run.stderr}',
      );
    }
  });

  test('Android JNI defines primitive decode MethodChannel bridge', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_draco_jni_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);

    final objectPath = '${tempDir.path}/flutter_scene_viewer_draco_jni.o';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/draco/src',
      '-c',
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
      '-o',
      objectPath,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );

    final symbols = await Process.run('nm', <String>[objectPath]);
    expect(
      symbols.exitCode,
      0,
      reason: '${symbols.stdout}\n${symbols.stderr}',
    );
    expect(
      '${symbols.stdout}\n${symbols.stderr}',
      contains(
        'Java_com_marlonjd_flutter_1scene_1viewer_1draco_'
        'FlutterSceneViewerDracoPlugin_nativeDecodePrimitives',
      ),
    );
  });

  test('Android JNI releases UTF chars when controlled assign fails', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_jni_utf_raii_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    final executable = '${tempDir.path}/jni_utf_raii';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/draco/src',
      'test/native/draco_jni_string_runner.cc',
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('jni_utf_releases=1'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('platform adapters keep 64-bit budget and accessor conversions',
      () async {
    final java = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_draco/FlutterSceneViewerDracoPlugin.java',
    ).readAsString();
    final jni = await File(
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
    ).readAsString();
    final ios = await File('ios/Classes/FlutterSceneViewerDracoPlugin.mm')
        .readAsString();
    expect(java, contains('Object decodeBudgetState'));
    expect(jni, contains('"java/lang/Integer"'));
    expect(jni, contains('"java/lang/Long"'));
    expect(jni, contains('"longValue", "()J"'));
    expect(
      jni,
      contains(
        'JniLocalRef count(env, MapGet(env, value, "count"));\n'
        '  schema.count = IntegralLongValueOr(env, count.get(), -1);',
      ),
    );
    expect(ios, contains('[count longLongValue]'));
    expect(ios, contains('CFBooleanGetTypeID()'));
    expect(ios, contains('CFNumberIsFloatType'));
    expect(
      jni,
      contains('BudgetNumber(env, value, "componentType")'),
    );
    expect(
      ios,
      contains('BudgetNumber(dictionary[@"componentType"])'),
    );
    expect(ios, contains('DecodeBudgetState(call.arguments)'));

    final bridge = await File(
      'android/src/main/cpp/fsv_draco_bridge.cc',
    ).readAsString();
    final completeValidation = bridge.indexOf(
      'FsvDracoValidateDecodedSchemas(requests, decoded_metadata, control)',
    );
    final firstOutputAllocation = bridge.indexOf(
      'if (!DecodeAttributeBytes(*attribute',
    );
    expect(completeValidation, greaterThanOrEqualTo(0));
    expect(firstOutputAllocation, greaterThan(completeValidation));
  });

  test('iOS adapter compiles and destroys native results before control finish',
      () async {
    final xcrun = await Process.run(
      'xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
    );
    if (xcrun.exitCode != 0) {
      markTestSkipped('The macOS SDK is unavailable.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_objc_compile_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final flutterDirectory = Directory('${tempDir.path}/Flutter');
    await flutterDirectory.create(recursive: true);
    await File('${flutterDirectory.path}/Flutter.h').writeAsString(r'''
#import <Foundation/Foundation.h>

typedef void (^FlutterResult)(id result);
@protocol FlutterBinaryMessenger <NSObject>
@end
@class FlutterMethodChannel;
@protocol FlutterPluginRegistrar <NSObject>
- (id<FlutterBinaryMessenger>)messenger;
- (void)addMethodCallDelegate:(id)delegate
                      channel:(FlutterMethodChannel *)channel;
@end
@protocol FlutterPlugin <NSObject>
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end
@interface FlutterMethodCall : NSObject
@property(nonatomic, readonly) NSString *method;
@property(nonatomic, readonly) id arguments;
@end
@interface FlutterMethodChannel : NSObject
+ (instancetype)methodChannelWithName:(NSString *)name
                      binaryMessenger:(id<FlutterBinaryMessenger>)messenger;
@end
@interface FlutterStandardTypedData : NSObject
@property(nonatomic, readonly) NSData *data;
+ (instancetype)typedDataWithBytes:(NSData *)data;
@end
@interface FlutterError : NSObject
+ (instancetype)errorWithCode:(NSString *)code
                       message:(NSString *)message
                       details:(id)details;
@end
FOUNDATION_EXPORT id FlutterMethodNotImplemented;
''');
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-x',
      'objective-c++',
      '-fobjc-arc',
      '-fobjc-runtime=macosx-10.13',
      '-fblocks',
      '-isysroot',
      '${xcrun.stdout}'.trim(),
      '-I${tempDir.path}',
      '-Ithird_party/draco/src',
      '-Iios/Classes',
      '-c',
      'ios/Classes/FlutterSceneViewerDracoPlugin.mm',
      '-o',
      '${tempDir.path}/plugin.o',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

    final source = await File(
      'ios/Classes/FlutterSceneViewerDracoPlugin.mm',
    ).readAsString();
    expect(_iosResultControlOrderingViolations(source), isEmpty);
    const finish =
        'const auto disposition = _requestRegistry->Finish(requestKey, request);';
    final mutant = source.replaceFirst(finish, '').replaceFirst(
          'NSDictionary *response = _requestRegistry->ShouldStart(request)',
          '$finish\n    NSDictionary *response = '
              '_requestRegistry->ShouldStart(request)',
        );
    expect(mutant, isNot(source));
    expect(
      _iosResultControlOrderingViolations(mutant),
      contains('registry finish precedes decode response destruction'),
    );
  });

  test('iOS serialization failure delivers exactly one typed terminal callback',
      () async {
    final xcrun = await Process.run(
      'xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
    );
    if (xcrun.exitCode != 0) {
      markTestSkipped('The macOS SDK is unavailable.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_objc_delivery_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final flutterDirectory = Directory('${tempDir.path}/Flutter');
    await flutterDirectory.create(recursive: true);
    await File('${flutterDirectory.path}/Flutter.h').writeAsString(r'''
#import <Foundation/Foundation.h>

typedef void (^FlutterResult)(id result);
@protocol FlutterBinaryMessenger <NSObject>
@end
@class FlutterMethodChannel;
@protocol FlutterPluginRegistrar <NSObject>
- (id<FlutterBinaryMessenger>)messenger;
- (void)addMethodCallDelegate:(id)delegate
                      channel:(FlutterMethodChannel *)channel;
@end
@protocol FlutterPlugin <NSObject>
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar;
@end
@interface FlutterMethodCall : NSObject
@property(nonatomic, readonly) NSString *method;
@property(nonatomic, readonly) id arguments;
@end
@interface FlutterMethodChannel : NSObject
+ (instancetype)methodChannelWithName:(NSString *)name
                      binaryMessenger:(id<FlutterBinaryMessenger>)messenger;
@end
@interface FlutterStandardTypedData : NSObject
@property(nonatomic, readonly) NSData *data;
+ (instancetype)typedDataWithBytes:(NSData *)data;
@end
@interface FlutterError : NSObject
+ (instancetype)errorWithCode:(NSString *)code
                       message:(NSString *)message
                       details:(id)details;
@end
FOUNDATION_EXPORT id FlutterMethodNotImplemented;
''');

    Future<ProcessResult> runBounded(
      String executable,
      List<String> arguments,
      Duration timeout,
      Map<String, String>? environment,
    ) async {
      final process = await Process.start(
        executable,
        arguments,
        environment: environment,
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(timeout, onTimeout: () {
        timedOut = true;
        process.kill();
        return -124;
      });
      final output = await stdout;
      final errors = await stderr;
      return ProcessResult(
        process.pid,
        exitCode,
        output,
        timedOut ? '$errors\nprocess timed out after $timeout' : errors,
      );
    }

    Future<ProcessResult> compile(File runner, String executable) {
      return runBounded(
          'clang++',
          <String>[
            '-std=c++17',
            '-x',
            'objective-c++',
            '-fobjc-arc',
            '-fobjc-runtime=macosx-10.13',
            '-fblocks',
            '-fsanitize=address,undefined',
            '-fno-omit-frame-pointer',
            '-isysroot',
            '${xcrun.stdout}'.trim(),
            '-I${tempDir.path}',
            '-Ithird_party/draco/src',
            '-Iios/Classes',
            runner.path,
            'ios/Classes/fsv_draco_budget.cc',
            'ios/Classes/fsv_draco_control.cc',
            'ios/Classes/fsv_draco_bridge.cc',
            'ios/Classes/fsv_draco_request_registry.cc',
            'ios/Classes/fsv_draco_vendor_sources.cc',
            '-framework',
            'Foundation',
            '-o',
            executable,
          ],
          const Duration(minutes: 2),
          null);
    }

    final runner = File('test/native/draco_objc_delivery_runner.mm');
    final executable = '${tempDir.path}/objc_delivery';
    final baselineCompile = await compile(runner, executable);
    expect(
      baselineCompile.exitCode,
      0,
      reason: '${baselineCompile.stdout}\n${baselineCompile.stderr}',
    );
    final baselineRun = await Process.run(
      executable,
      const <String>[],
      environment: const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'},
    );
    expect(
      baselineRun.exitCode,
      0,
      reason: '${baselineRun.stdout}\n${baselineRun.stderr}',
    );
    expect('${baselineRun.stderr}', contains('objc_delivery_cases=7'));

    final source = await File(
      'ios/Classes/FlutterSceneViewerDracoPlugin.mm',
    ).readAsString();
    final runnerSource = await runner.readAsString();
    final mutations = <({String label, String before, String after})>[
      (
        label: 'omitted success-null terminal callback',
        before: 'if (response == nil) {\n'
            '    result([FlutterError errorWithCode:@"platformSerializationFailed"',
        after: 'if (response == nil) {\n'
            '    return;\n'
            '    result([FlutterError errorWithCode:@"platformSerializationFailed"',
      ),
      (
        label: 'double success-null terminal callback',
        before: '    result([FlutterError '
            'errorWithCode:@"platformSerializationFailed"\n'
            '                               message:'
            '@"Native Draco response serialization failed."\n'
            '                               details:nil]);\n'
            '    return;',
        after: '    result([FlutterError '
            'errorWithCode:@"platformSerializationFailed"\n'
            '                               message:'
            '@"Native Draco response serialization failed."\n'
            '                               details:nil]);\n'
            '    result([FlutterError errorWithCode:@"platformSerializationFailed"\n'
            '                                 message:@"duplicate"\n'
            '                                 details:nil]);\n'
            '    return;',
      ),
    ];
    for (var index = 0; index < mutations.length; index += 1) {
      final mutation = mutations[index];
      final mutated = source.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(source), reason: mutation.label);
      final mutantSource = File('${tempDir.path}/mutated_plugin_$index.mm');
      await mutantSource.writeAsString(mutated);
      final mutantRunner = File('${tempDir.path}/mutant_runner_$index.mm');
      await mutantRunner.writeAsString(
        runnerSource.replaceFirst(
          '#include "../../ios/Classes/FlutterSceneViewerDracoPlugin.mm"',
          '#include "${mutantSource.path}"',
        ),
      );
      final mutantExecutable = '${tempDir.path}/objc_delivery_mutant_$index';
      final mutantCompile = await compile(mutantRunner, mutantExecutable);
      expect(
        mutantCompile.exitCode,
        0,
        reason: '${mutation.label}\n'
            '${mutantCompile.stdout}\n${mutantCompile.stderr}',
      );
      final mutantRun = await runBounded(
        mutantExecutable,
        const <String>[],
        const Duration(seconds: 20),
        const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'},
      );
      expect(
        mutantRun.exitCode,
        isNot(0),
        reason: '${mutation.label} mutation escaped',
      );
    }

    final lifetimeMutations = <({String label, String before, String after})>[
      (
        label: 'native result destroyed before Objective-C++ platform copy',
        before: 'response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
        after: 'native_result = FsvDracoDecodeResult(request->control.get());\n'
            '    response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
      ),
      (
        label: 'registry control Finish before Objective-C++ platform copy',
        before: 'response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
        after: 'registry.Finish("platform-copy", request);\n'
            '    response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
      ),
      (
        label: 'retained native charge released during Objective-C++ copy',
        before: 'response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
        after: 'native_result.decoded_primitives.clear();\n'
            '    response = BuildManagedDecodeResponse(\n'
            '        diagnostics, native_result, nil, request->control.get());',
      ),
    ];
    for (var index = 0; index < lifetimeMutations.length; index += 1) {
      final mutation = lifetimeMutations[index];
      final mutatedRunner =
          runnerSource.replaceFirst(mutation.before, mutation.after);
      expect(mutatedRunner, isNot(runnerSource), reason: mutation.label);
      final mutantRunner = File('${tempDir.path}/lifetime_runner_$index.mm');
      await mutantRunner.writeAsString(mutatedRunner);
      final mutantExecutable = '${tempDir.path}/objc_lifetime_mutant_$index';
      final mutantCompile = await compile(mutantRunner, mutantExecutable);
      expect(mutantCompile.exitCode, 0,
          reason: '${mutation.label}\n'
              '${mutantCompile.stdout}\n${mutantCompile.stderr}');
      final mutantRun = await runBounded(
        mutantExecutable,
        const <String>[],
        const Duration(seconds: 20),
        const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'},
      );
      expect(mutantRun.exitCode, isNot(0),
          reason: '${mutation.label} mutation escaped');
    }

    const partialResponseBefore = 'if (decodedPrimitives == nil) {\n'
        '      return nil;  // Atomic platform-copy failure.\n'
        '    }';
    const partialResponseAfter = 'if (decodedPrimitives == nil) {\n'
        '      return @{ @"decodedPrimitives" : @[], @"diagnostics" : diagnostics };\n'
        '    }';
    final partialResponsePlugin =
        source.replaceFirst(partialResponseBefore, partialResponseAfter);
    expect(partialResponsePlugin, isNot(source));
    final partialPluginFile =
        File('${tempDir.path}/partial_response_plugin.mm');
    await partialPluginFile.writeAsString(partialResponsePlugin);
    final partialRunner = File('${tempDir.path}/partial_response_runner.mm');
    await partialRunner.writeAsString(
      runnerSource.replaceFirst(
        '#include "../../ios/Classes/FlutterSceneViewerDracoPlugin.mm"',
        '#include "${partialPluginFile.path}"',
      ),
    );
    final partialExecutable = '${tempDir.path}/objc_partial_response_mutant';
    final partialCompile = await compile(partialRunner, partialExecutable);
    expect(partialCompile.exitCode, 0,
        reason: '${partialCompile.stdout}\n${partialCompile.stderr}');
    final partialRun = await runBounded(
      partialExecutable,
      const <String>[],
      const Duration(seconds: 20),
      const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'},
    );
    expect(partialRun.exitCode, isNot(0),
        reason: 'partial Objective-C++ response mutation escaped');
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('platform serialization is signed-size guarded cancellable and atomic',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_platform_copy_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_platform_copy';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I$platform',
        'test/native/draco_platform_serialization_runner.cc',
        '$platform/fsv_draco_control.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '$platform\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, 0,
          reason: '$platform\n${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('platform_copy_contracts=2'));

      final source = await File(
        '$platform/fsv_draco_platform_serialization.h',
      ).readAsString();
      final mutations = <({String label, String before, String after})>[
        (
          label: 'signed size guard',
          before: 'if (bytes > signed_platform_max ||',
          after: 'if (false ||',
        ),
        (
          label: 'pre-copy stop',
          before: 'if (control != nullptr && control->IsCancelled()) {\n'
              '    return FsvDracoPlatformCopyOutcome::kStopped;\n'
              '  }\n  if (bytes > signed_platform_max',
          after: 'if (false) {\n'
              '    return FsvDracoPlatformCopyOutcome::kStopped;\n'
              '  }\n  if (bytes > signed_platform_max',
        ),
        (
          label: 'post-allocation stop',
          before: 'managed == nullptr) {\n'
              '    return FsvDracoPlatformCopyOutcome::kAllocationFailed;\n'
              '  }\n  if (control != nullptr && control->IsCancelled()) {',
          after: 'managed == nullptr) {\n'
              '    return FsvDracoPlatformCopyOutcome::kAllocationFailed;\n'
              '  }\n  if (false) {',
        ),
        (
          label: 'post-copy stop',
          before: 'return FsvDracoPlatformCopyOutcome::kCopyFailed;\n'
              '  }\n  if (control != nullptr && control->IsCancelled()) {',
          after: 'return FsvDracoPlatformCopyOutcome::kCopyFailed;\n'
              '  }\n  if (false) {',
        ),
        (
          label: 'partial managed cleanup',
          before: 'callbacks.release(callbacks.context, managed);\n'
              '    return FsvDracoPlatformCopyOutcome::kCopyFailed;',
          after: 'return FsvDracoPlatformCopyOutcome::kCopyFailed;',
        ),
      ];
      for (var index = 0; index < mutations.length; index += 1) {
        final mutation = mutations[index];
        final mutated = source.replaceFirst(mutation.before, mutation.after);
        expect(mutated, isNot(source), reason: mutation.label);
        final mutantDirectory = Directory(
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_mutant_$index',
        )..createSync();
        await File(
          '${mutantDirectory.path}/fsv_draco_platform_serialization.h',
        ).writeAsString(mutated);
        final mutantExecutable = '${mutantDirectory.path}/runner';
        final mutantCompile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-I${mutantDirectory.path}',
          '-I$platform',
          'test/native/draco_platform_serialization_runner.cc',
          '$platform/fsv_draco_control.cc',
          '-o',
          mutantExecutable,
        ]);
        expect(mutantCompile.exitCode, 0,
            reason: '${mutation.label}\n'
                '${mutantCompile.stdout}\n${mutantCompile.stderr}');
        final mutantRun = await Process.run(mutantExecutable, const <String>[]);
        expect(mutantRun.exitCode, isNot(0),
            reason: '${platform} ${mutation.label} mutation escaped');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('JNI and ObjC adapters route every native payload through copy control',
      () async {
    final jni = await File(
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
    ).readAsString();
    final ios = await File(
      'ios/Classes/FlutterSceneViewerDracoPlugin.mm',
    ).readAsString();
    expect(jni, contains('#include "fsv_draco_platform_serialization.h"'));
    expect(ios, contains('#import "fsv_draco_platform_serialization.h"'));
    expect(jni, contains('FsvDracoCopyBytesToPlatform('));
    expect(ios, contains('FsvDracoCopyBytesToPlatform('));
    expect(jni, contains('env->ExceptionCheck()'));
    expect(jni, contains('env->ExceptionClear()'));
    expect(jni, contains('env->DeleteLocalRef(array)'));
    expect(jni, contains('return nullptr;  // Atomic platform-copy failure.'));
    expect(ios, contains('std::numeric_limits<NSInteger>::max()'));
    expect(ios, contains('@catch (NSException *exception)'));
    expect(ios, contains('return nil;  // Atomic platform-copy failure.'));
    expect(ios, contains('if (control->IsCancelled())'));
  });

  test('fake JNI rejects exceptions and releases every partial byte array',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_jni_platform_copy_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    final executable = '${tempDir.path}/jni_platform_copy';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/draco/src',
      'test/native/draco_jni_platform_copy_runner.cc',
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('jni_platform_copy_cases=10'));

    final source = await File(
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
    ).readAsString();
    final runnerSource = await File(
      'test/native/draco_jni_platform_copy_runner.cc',
    ).readAsString();
    final mutations = <({String label, String before, String after})>[
      (
        label: 'JNI exception clear',
        before: 'env->ExceptionClear();',
        after: '(void)env;',
      ),
      (
        label: 'NewByteArray exception local ref',
        before: 'if (array != nullptr) context->env->DeleteLocalRef(array);',
        after: '(void)array;',
      ),
      (
        label: 'SetByteArrayRegion exception check',
        before: 'if (ClearPendingJniException(context->env)) {\n'
            '      return false;\n'
            '    }',
        after: 'if (false) {\n      return false;\n    }',
      ),
      (
        label: 'partial byte array release',
        before:
            'context->env->DeleteLocalRef(static_cast<jbyteArray>(destination));',
        after: '(void)destination;',
      ),
      (
        label: 'NewString exception local ref',
        before: 'jobject NewString(JNIEnv* env, const char* value) {\n'
            '  jobject result = env->NewStringUTF(value);\n'
            '  if (!ClearPendingJniException(env)) return result;\n'
            '  if (result != nullptr) env->DeleteLocalRef(result);',
        after: 'jobject NewString(JNIEnv* env, const char* value) {\n'
            '  jobject result = env->NewStringUTF(value);\n'
            '  if (!ClearPendingJniException(env)) return result;\n'
            '  (void)result;',
      ),
      (
        label: 'managed object exception local ref',
        before: '  env->DeleteLocalRef(map_class);\n'
            '  if (failed && result != nullptr) env->DeleteLocalRef(result);\n'
            '  return failed ? nullptr : result;\n'
            '}\n\n'
            'jobject NewArrayList',
        after: '  env->DeleteLocalRef(map_class);\n'
            '  (void)failed;\n'
            '  return failed ? nullptr : result;\n'
            '}\n\n'
            'jobject NewArrayList',
      ),
      (
        label: 'managed map failure propagation',
        before: '  const bool result = MapPutObject(env, map, key, object);\n'
            '  env->DeleteLocalRef(object);\n'
            '  return result;',
        after: '  static_cast<void>(MapPutObject(env, map, key, object));\n'
            '  env->DeleteLocalRef(object);\n'
            '  return true;',
      ),
      (
        label: 'managed list failure propagation',
        before: '  return !failed && added == JNI_TRUE;',
        after: '  return true;',
      ),
    ];
    for (var index = 0; index < mutations.length; index += 1) {
      final mutation = mutations[index];
      final mutated = source.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(source), reason: mutation.label);
      final mutantSource = File('${tempDir.path}/mutated_jni_$index.cc');
      final mutantRunner = File('${tempDir.path}/mutant_runner_$index.cc');
      await mutantSource.writeAsString(mutated);
      await mutantRunner.writeAsString(
        runnerSource.replaceFirst(
          '#include "../../android/src/main/cpp/flutter_scene_viewer_draco_jni.cc"',
          '#include "${mutantSource.path}"',
        ),
      );
      final mutantExecutable = '${tempDir.path}/jni_mutant_$index';
      final mutantCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I${tempDir.path}',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/draco/src',
        mutantRunner.path,
        'android/src/main/cpp/fsv_draco_budget.cc',
        'android/src/main/cpp/fsv_draco_control.cc',
        'android/src/main/cpp/fsv_draco_bridge.cc',
        'ios/Classes/fsv_draco_vendor_sources.cc',
        '-o',
        mutantExecutable,
      ]);
      expect(mutantCompile.exitCode, 0,
          reason: '${mutation.label}\n'
              '${mutantCompile.stdout}\n${mutantCompile.stderr}');
      final mutantRun = await Process.run(mutantExecutable, const <String>[]);
      expect(mutantRun.exitCode, isNot(0),
          reason: '${mutation.label} mutation escaped');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('JNI input conversion bounds local refs and stops after exceptions',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_draco_jni_input_refs_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    final executable = '${tempDir.path}/jni_input_refs';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/draco/src',
      'test/native/draco_jni_input_refs_runner.cc',
      'android/src/main/cpp/fsv_draco_budget.cc',
      'android/src/main/cpp/fsv_draco_control.cc',
      'android/src/main/cpp/fsv_draco_bridge.cc',
      'ios/Classes/fsv_draco_vendor_sources.cc',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('jni_input_ref_cases=4 entries=2048'));

    final source = await File(
      'android/src/main/cpp/flutter_scene_viewer_draco_jni.cc',
    ).readAsString();
    final runnerSource = await File(
      'test/native/draco_jni_input_refs_runner.cc',
    ).readAsString();
    final mutations = <({String label, String before, String after})>[
      (
        label: 'MapGet key local reference cleanup',
        before: 'if (value_ != nullptr) env_->DeleteLocalRef(value_);',
        after: '(void)value_;',
      ),
      (
        label: 'MapGet call exception propagation',
        before: 'if (ClearPendingJniException(env)) {\n'
            '    if (result != nullptr) env->DeleteLocalRef(result);\n'
            '    return nullptr;\n'
            '  }',
        after: 'if (false) {\n'
            '    if (result != nullptr) env->DeleteLocalRef(result);\n'
            '    return nullptr;\n'
            '  }',
      ),
      (
        label: 'ForEach entry local reference cleanup',
        before:
            'JniLocalRef entry(env, env->CallObjectMethod(iterator.get(), next));\n'
                '    if (ClearPendingJniException(env)',
        after:
            'JniLocalRef entry(env, env->CallObjectMethod(iterator.get(), next));\n'
                '    entry.release();\n'
                '    if (ClearPendingJniException(env)',
      ),
      (
        label: 'ForEach value exception propagation',
        before:
            'JniLocalRef value(env, env->CallObjectMethod(entry.get(), get_value));\n'
                '    if (ClearPendingJniException(env)) {\n'
                '      return false;\n'
                '    }',
        after:
            'JniLocalRef value(env, env->CallObjectMethod(entry.get(), get_value));\n'
                '    if (false) {\n'
                '      return false;\n'
                '    }',
      ),
    ];
    for (var index = 0; index < mutations.length; index += 1) {
      final mutation = mutations[index];
      final mutated = source.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(source), reason: mutation.label);
      final mutantSource = File('${tempDir.path}/input_mutant_$index.cc');
      final mutantRunner =
          File('${tempDir.path}/input_mutant_runner_$index.cc');
      await mutantSource.writeAsString(mutated);
      await mutantRunner.writeAsString(
        runnerSource.replaceFirst(
          '#include "../../android/src/main/cpp/flutter_scene_viewer_draco_jni.cc"',
          '#include "${mutantSource.path}"',
        ),
      );
      final mutantExecutable = '${tempDir.path}/input_mutant_$index';
      final mutantCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I${tempDir.path}',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/draco/src',
        mutantRunner.path,
        'android/src/main/cpp/fsv_draco_budget.cc',
        'android/src/main/cpp/fsv_draco_control.cc',
        'android/src/main/cpp/fsv_draco_bridge.cc',
        'ios/Classes/fsv_draco_vendor_sources.cc',
        '-o',
        mutantExecutable,
      ]);
      expect(mutantCompile.exitCode, 0,
          reason: '${mutation.label}\n'
              '${mutantCompile.stdout}\n${mutantCompile.stderr}');
      final mutantRun = await Process.run(mutantExecutable, const <String>[]);
      expect(mutantRun.exitCode, isNot(0),
          reason: '${mutation.label} mutation escaped');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Draco bridge has no conservative outer working reservation', () async {
    final android = await File(
      'android/src/main/cpp/fsv_draco_bridge.cc',
    ).readAsString();
    final ios = await File('ios/Classes/fsv_draco_bridge.cc').readAsString();
    expect(android, ios);
    expect(android, isNot(contains('FsvScopedWorkingReservation')));
    expect(android, isNot(contains('working_reservation')));
    expect(android, contains('stop_before_codec_dispatch'));
  });

  test('all multi-owner fixture runners lock exact peak-minus-one rejection',
      () async {
    final box = await File(
      'test/native/draco_conformance_runner.cc',
    ).readAsString();
    final sequential = await File(
      'test/native/draco_sequential_conformance_runner.cc',
    ).readAsString();
    final metadata = await File(
      'test/native/draco_metadata_conformance_runner.cc',
    ).readAsString();
    expect(box, contains('two_primitive_peak_minus_one=budgetExceeded'));
    expect(sequential, contains('sequential_peak_minus_one=budgetExceeded'));
    expect(metadata, contains('success_control.peak_bytes() - 1'));
  });
}

List<String> _iosResultControlOrderingViolations(String source) {
  final violations = <String>[];
  final decodeStart = source.indexOf('- (NSDictionary *)decodeResponse:');
  final result = source.indexOf(
    'FsvDracoDecodeResult decodeResult(control);',
    decodeStart,
  );
  final managedResponse = source.indexOf(
    'NSDictionary *BuildManagedDecodeResponse(',
  );
  final decodedCopy = source.indexOf(
    'DecodedPrimitives(decodeResult, control)',
    managedResponse,
  );
  final diagnosticCopy = source.indexOf(
    'BridgeDiagnostics(decodeResult, source)',
    managedResponse,
  );
  final managedResponseCall = source.indexOf(
    'return BuildManagedDecodeResponse(diagnostics, decodeResult, source, '
    'control);',
    result,
  );
  final decodeCall = source.indexOf(
    'NSDictionary *response = _requestRegistry->ShouldStart(request)',
  );
  final stopReason = source.indexOf(
    'const auto stopReason = request->control != nullptr',
    decodeCall,
  );
  final finish = source.indexOf(
    'const auto disposition = _requestRegistry->Finish(requestKey, request);',
  );
  if (decodeStart < 0 ||
      result < decodeStart ||
      managedResponse < 0 ||
      decodedCopy < managedResponse ||
      diagnosticCopy < managedResponse ||
      managedResponseCall < result) {
    violations.add('native result is not serialized inside decodeResponse');
  }
  if (decodeCall < 0 || finish < decodeCall) {
    violations.add('registry finish precedes decode response destruction');
  }
  if (stopReason < decodeCall || stopReason > finish) {
    violations.add('first stop reason is not captured before control finish');
  }
  return violations;
}

Future<String> _sha256(File file) async {
  final result = await Process.run(
    'shasum',
    <String>['-a', '256', file.path],
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  return '${result.stdout}'.split(' ').first;
}

List<String> _sequentialFixtureProvenanceViolations({
  required String readme,
  required String licenseHash,
  required String generatorHash,
  required String payloadHash,
}) {
  final violations = <String>[];
  if (!readme.contains('google/draco@1.5.7') ||
      !readme.contains(_dracoUpstreamCommit)) {
    violations.add('commit');
  }
  if (!readme.contains(_dracoSourceObject) ||
      !readme.contains(_dracoSourceArchiveHash) ||
      readme.contains('HEAD:')) {
    violations.add('source archive');
  }
  if (licenseHash != _dracoLicenseHash ||
      !readme.contains(_dracoLicenseHash) ||
      !readme.contains('Apache-2.0')) {
    violations.add('license');
  }
  if (generatorHash != _sequentialGeneratorHash ||
      !readme.contains(_sequentialGeneratorHash) ||
      !readme.contains('MESH_SEQUENTIAL_ENCODING') ||
      !readme.contains('compress_connectivity')) {
    violations.add('generator');
  }
  if (payloadHash != _sequentialPayloadHash ||
      !readme.contains(_sequentialPayloadHash)) {
    violations.add('payload');
  }
  return violations;
}

List<String> _metadataFixtureProvenanceViolations({
  required String readme,
  required String licenseHash,
  required String generatorHash,
  required String payloadHash,
}) {
  final violations = <String>[];
  if (!readme.contains('google/draco@1.5.7') ||
      !readme.contains(_dracoUpstreamCommit)) {
    violations.add('commit');
  }
  if (!readme.contains(_dracoSourceObject) ||
      !readme.contains(_dracoSourceArchiveHash)) {
    violations.add('source archive');
  }
  if (licenseHash != _dracoLicenseHash ||
      !readme.contains(_dracoLicenseHash) ||
      !readme.contains('Apache-2.0')) {
    violations.add('license');
  }
  if (generatorHash != _metadataGeneratorHash ||
      !readme.contains(_metadataGeneratorHash)) {
    violations.add('generator');
  }
  if (payloadHash != _metadataPayloadHash ||
      !readme.contains(_metadataPayloadHash)) {
    violations.add('payload');
  }
  return violations;
}

List<String> _structuralMetadataPopulationSymbols(String symbols) {
  const names = <String>[
    'StructuralMetadata::Copy',
    'StructuralMetadata::SetSchema',
    'StructuralMetadata::AddPropertyTable',
    'StructuralMetadata::RemovePropertyTable',
    'StructuralMetadata::AddPropertyAttribute',
    'StructuralMetadata::RemovePropertyAttribute',
    'StructuralMetadataSchema::Object::Copy',
    'StructuralMetadataSchema::Object::SetString',
    'StructuralMetadataSchema::Object::SetInteger',
    'StructuralMetadataSchema::Object::SetBoolean',
    'PropertyTable::Copy',
    'PropertyTable::SetName',
    'PropertyTable::SetClass',
    'PropertyTable::SetCount',
    'PropertyTable::AddProperty',
    'PropertyTable::RemoveProperty',
    'PropertyTable::Property::Copy',
    'PropertyTable::Property::SetName',
    'PropertyAttribute::Copy',
    'PropertyAttribute::SetName',
    'PropertyAttribute::SetClass',
    'PropertyAttribute::AddProperty',
    'PropertyAttribute::RemoveProperty',
    'PropertyAttribute::Property::Copy',
    'PropertyAttribute::Property::SetName',
    'PropertyAttribute::Property::SetAttributeName',
    'Mesh::AddPropertyAttributesIndex',
    'Mesh::AddPropertyAttributesIndexMaterialMask',
    'Mesh::GetStructuralMetadata',
  ];
  return names.where(symbols.contains).toList();
}

const _symbolBitDecoderDefinitionSource =
    'compression/bit_coders/symbol_bit_decoder.cc';
const _symbolBitDecoderOwnerSources = <String>{
  _symbolBitDecoderDefinitionSource,
  'compression/bit_coders/symbol_bit_decoder.h',
};

Future<({List<String> android, List<String> ios})>
    _readPrunedDracoDecoderClosure() async {
  const sourceRoot = 'third_party/draco/src/draco';
  final cmake = await File('android/CMakeLists.txt').readAsString();
  final sourceDirectories = RegExp(
    r'"\$\{FSV_DRACO_SRC\}/draco/([^/]+)/\*\.cc"',
  ).allMatches(cmake).map((match) => match.group(1)!).toList();
  final exclusionPatterns = RegExp(
    r'list\(FILTER FSV_DRACO_DECODER_SOURCES EXCLUDE REGEX "([^"]+)"\)',
  )
      .allMatches(cmake)
      .map((match) => RegExp(match.group(1)!.replaceAll('\\\\', '\\')))
      .toList();
  if (sourceDirectories.isEmpty || exclusionPatterns.isEmpty) {
    return (android: <String>[], ios: <String>[]);
  }

  final androidSources = <String>[];
  for (final directoryName in sourceDirectories) {
    await for (final entity
        in Directory('$sourceRoot/$directoryName').list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.cc')) continue;
      final source =
          entity.path.substring('third_party/draco/src/draco/'.length);
      if (exclusionPatterns.any(
        (pattern) => pattern.hasMatch('/draco/$source'),
      )) {
        continue;
      }
      androidSources.add(source);
    }
  }
  androidSources.sort();

  final iosAggregate = await File(
    'ios/Classes/fsv_draco_vendor_sources.cc',
  ).readAsString();
  final iosSources = RegExp(
    r'^#include "\.\./\.\./third_party/draco/src/draco/(.+\.cc)"$',
    multiLine: true,
  ).allMatches(iosAggregate).map((match) => match.group(1)!).toList()
    ..sort();
  return (android: androidSources, ios: iosSources);
}

Future<String> _compileDracoAggregateMutant({
  required Directory tempDir,
  required File runner,
  required String label,
  required Map<String, String> mutatedSources,
  Map<String, String> mutatedHeaders = const <String, String>{},
}) async {
  const sourcePrefix = 'third_party/draco/src/draco/';
  final replacements = <String, File>{};
  for (final entry in mutatedSources.entries) {
    expect(entry.key, startsWith(sourcePrefix));
    final mutantFile = File(
      '${tempDir.path}/${label}_${entry.key.substring(sourcePrefix.length).replaceAll('/', '_')}',
    );
    await mutantFile.writeAsString(entry.value);
    replacements[entry.key.substring(sourcePrefix.length)] = mutantFile;
  }

  final mutantIncludeRoot = Directory('${tempDir.path}/include_$label');
  for (final entry in mutatedHeaders.entries) {
    expect(entry.key, startsWith(sourcePrefix));
    final mutantHeader = File(
      '${mutantIncludeRoot.path}/draco/'
      '${entry.key.substring(sourcePrefix.length)}',
    );
    await mutantHeader.parent.create(recursive: true);
    await mutantHeader.writeAsString(entry.value);
  }

  final aggregate =
      await File('ios/Classes/fsv_draco_vendor_sources.cc').readAsString();
  final absoluteAggregate = aggregate.replaceAllMapped(
    RegExp(r'^#include "([^\"]+\.cc)"$', multiLine: true),
    (match) {
      final included = match.group(1)!;
      const aggregatePrefix = '../../third_party/draco/src/draco/';
      if (included.startsWith(aggregatePrefix)) {
        final source = included.substring(aggregatePrefix.length);
        final replacement = replacements[source];
        if (replacement != null) return '#include "${replacement.path}"';
      }
      return '#include "${File('ios/Classes/$included').absolute.path}"';
    },
  );
  for (final source in replacements.keys) {
    expect(
      absoluteAggregate,
      contains(replacements[source]!.path),
      reason: 'Mutated source is not in the production iOS aggregate: $source',
    );
  }
  final mutantAggregate = File('${tempDir.path}/vendor_sources_$label.cc');
  await mutantAggregate.writeAsString(absoluteAggregate);
  final executable = '${tempDir.path}/draco_conformance_$label';
  final compile = await Process.run('clang++', <String>[
    '-std=c++17',
    if (mutatedHeaders.isNotEmpty) '-I${mutantIncludeRoot.path}',
    '-Ithird_party/draco/src',
    '-Iandroid/src/main/cpp',
    runner.path,
    'android/src/main/cpp/fsv_draco_budget.cc',
    'android/src/main/cpp/fsv_draco_control.cc',
    'android/src/main/cpp/fsv_draco_bridge.cc',
    mutantAggregate.path,
    '-o',
    executable,
  ]);
  expect(
    compile.exitCode,
    0,
    reason: '$label\n${compile.stdout}\n${compile.stderr}',
  );
  return executable;
}

Future<Map<String, String>> _readReachableDracoSources(
  List<String> translationUnits,
) async {
  const sourceRoot = 'third_party/draco/src/draco';
  final pending = <String>[...translationUnits];
  final discovered = translationUnits.toSet();
  final sources = <String, String>{};
  final includePattern = RegExp(
    r'^\s*#\s*include\s+"draco/([^"]+)"',
    multiLine: true,
  );

  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    final source = await File('$sourceRoot/$path').readAsString();
    sources[path] = source;
    for (final match in includePattern.allMatches(source)) {
      final dependency = match.group(1)!;
      if (discovered.contains(dependency)) continue;
      if (!await File('$sourceRoot/$dependency').exists()) continue;
      discovered.add(dependency);
      pending.add(dependency);
    }
  }
  return sources;
}

List<String> _symbolBitDecoderUseSites(Map<String, String> sources) {
  final uses = <String>[];
  for (final entry in sources.entries) {
    if (_symbolBitDecoderOwnerSources.contains(entry.key)) continue;
    if (entry.value.contains('SymbolBitDecoder')) {
      uses.add(entry.key);
    }
  }
  uses.sort();
  return uses;
}

typedef _Task5cWiringRule = ({
  String path,
  String label,
  String marker,
  int count,
});

Future<void> _expectTask5cWiringMutations() async {
  final paths = _task5cWiringRules.map((rule) => rule.path).toSet();
  final sources = <String, String>{
    for (final path in paths) path: await File(path).readAsString(),
  };
  expect(_task5cWiringViolations(sources), isEmpty);

  final escaped = <String>[];
  for (final rule in _task5cWiringRules) {
    final source = sources[rule.path]!;
    final mutated = source.replaceFirst(rule.marker, 'FSV_TASK_5C_MUTANT');
    expect(mutated, isNot(source), reason: rule.label);
    final mutantSources = <String, String>{
      ...sources,
      rule.path: mutated,
    };
    if (_task5cWiringViolations(mutantSources).isEmpty) {
      escaped.add(rule.label);
    }
  }
  expect(
    escaped,
    isEmpty,
    reason: 'Source mutants escaped the exact Task 5C owner contract.',
  );
}

List<String> _task5cWiringViolations(Map<String, String> sources) {
  final violations = <String>[];
  for (final rule in _task5cWiringRules) {
    final source = sources[rule.path];
    if (source == null) {
      violations.add('${rule.label}: missing source ${rule.path}');
      continue;
    }
    final actual = RegExp(RegExp.escape(rule.marker)).allMatches(source).length;
    if (actual != rule.count) {
      violations.add(
        '${rule.label}: expected ${rule.count} exact occurrence(s), '
        'found $actual',
      );
    }
  }
  return violations;
}

const _task5cWiringRules = <_Task5cWiringRule>[
  (
    path: 'third_party/draco/src/draco/point_cloud/point_cloud.h',
    label: 'PointCloud allocation header',
    marker: 'class PointCloud : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/point_cloud/'
        'point_cloud_decoder.h',
    label: 'PointCloudDecoder allocation header',
    marker: 'class PointCloudDecoder : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl_interface.h',
    label: 'Edgebreaker implementation allocation header',
    marker: 'public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'attributes_decoder_interface.h',
    label: 'attributes decoder allocation header',
    marker: 'public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'points_sequencer.h',
    label: 'points sequencer allocation header',
    marker: 'class PointsSequencer : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoder.h',
    label: 'sequential attribute decoder allocation header',
    marker: 'public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/point_attribute.h',
    label: 'PointAttribute allocation header',
    marker: 'public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/core/data_buffer.h',
    label: 'DataBuffer allocation header',
    marker: 'class DataBuffer : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/'
        'attribute_transform_data.h',
    label: 'attribute transform data allocation header',
    marker: 'class AttributeTransformData : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/mesh/corner_table.h',
    label: 'CornerTable allocation header',
    marker: 'class CornerTable : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/decode.cc',
    label: 'decoded Mesh placement control',
    marker: 'new (control) Mesh(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/decode.cc',
    label: 'sequential decoder placement control',
    marker: 'new (control) MeshSequentialDecoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/decode.cc',
    label: 'Edgebreaker decoder placement control',
    marker: 'new (control) MeshEdgebreakerDecoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder.cc',
    label: 'concrete Edgebreaker implementation placement control',
    marker: 'new (fsv_decode_control())',
    count: 3,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'Edgebreaker sequencer/controller/table placement control',
    marker: 'new (decoder_->fsv_decode_control())',
    count: 4,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_sequential_decoder.cc',
    label: 'sequential controller and sequencer placement control',
    marker: 'new (fsv_decode_control())',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_sequential_decoder.cc',
    label: 'sequential topology allocator control',
    marker: 'FsvDecodeAllocator<uint32_t>(fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'attributes_decoder.cc',
    label: 'decoded PointAttribute placement control',
    marker: 'new (pc->fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoders_controller.cc',
    label: 'concrete sequential attribute decoder placement control',
    marker: 'new (control)',
    count: 4,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/point_attribute.cc',
    label: 'PointAttribute owned buffer placement control',
    marker: 'new (fsv_decode_control_)',
    count: 4,
  ),
  (
    path: 'third_party/draco/src/draco/point_cloud/point_cloud.cc',
    label: 'PointCloud-created attribute placement control',
    marker: 'new (fsv_decode_control_)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoder.cc',
    label: 'generic attribute value allocator control',
    marker: 'FsvDecodeAllocator<uint8_t>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_integer_attribute_decoder.cc',
    label: 'integer attribute value allocator control',
    marker: 'FsvDecodeAllocator<AttributeTypeT>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_integer_attribute_decoder.cc',
    label: 'portable integer PointAttribute placement control',
    marker: 'new (control) PointAttribute(ga, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/attribute_transform.cc',
    label: 'attribute transform owned-object placement control',
    marker: 'new (control)',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/'
        'attribute_quantization_transform.h',
    label: 'quantization minimum storage allocator control',
    marker: 'min_values_(FsvDecodeAllocator<float>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/attributes/'
        'attribute_quantization_transform.cc',
    label: 'inverse quantization scratch allocator control',
    marker: 'FsvDecodeAllocator<float>(fsv_decode_control_)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_quantization_attribute_decoder.cc',
    label: 'quantization transform retained control',
    marker: ': quantization_transform_(control)',
    count: 1,
  ),
];

Future<void> _expectTask5bWiringMutations() async {
  final sources = await _readTask5bWiringSources();
  expect(_task5bWiringViolations(sources), isEmpty);

  Map<String, String> mutate(
    String path,
    String before,
    String after,
  ) {
    final source = sources[path]!;
    final mutated = source.replaceFirst(before, after);
    expect(mutated, isNot(source), reason: path);
    return <String, String>{...sources, path: mutated};
  }

  Map<String, String> mutateOccurrence(
    String path,
    String before,
    String after,
    int occurrence,
  ) {
    final source = sources[path]!;
    var searchStart = 0;
    var matchIndex = -1;
    for (var index = 0; index <= occurrence; index += 1) {
      matchIndex = source.indexOf(before, searchStart);
      expect(matchIndex, greaterThanOrEqualTo(0), reason: path);
      searchStart = matchIndex + before.length;
    }
    final mutated = source.replaceRange(
      matchIndex,
      matchIndex + before.length,
      after,
    );
    return <String, String>{...sources, path: mutated};
  }

  const implementation = 'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_decoder_impl.cc';
  const factory = 'third_party/draco/src/draco/compression/attributes/'
      'prediction_schemes/prediction_scheme_decoder_factory.h';
  const valence = 'third_party/draco/src/draco/compression/mesh/'
      'mesh_edgebreaker_traversal_valence_decoder.h';
  const allocator = 'third_party/draco/src/draco/core/fsv_decode_allocator.h';

  final mutations = <Map<String, String>>[
    mutate(
      implementation,
      'TraverserT att_traverser(decoder_->fsv_decode_control());',
      'TraverserT att_traverser(nullptr);',
    ),
    mutate(
      factory,
      'new (control) MeshPredictionSchemeTexCoordsPortableDecoder<',
      'new MeshPredictionSchemeTexCoordsPortableDecoder<',
    ),
    mutate(
      valence,
      'context_symbols_.emplace_back('
          'FsvDecodeAllocator<uint32_t>(control_));',
      'context_symbols_.emplace_back();',
    ),
    mutate(
      allocator,
      'using propagate_on_container_move_assignment = std::true_type;',
      'using propagate_on_container_move_assignment = std::false_type;',
    ),
    mutate(
      allocator,
      'using propagate_on_container_swap = std::true_type;',
      'using propagate_on_container_swap = std::false_type;',
    ),
    for (var occurrence = 0; occurrence < 3; occurrence += 1)
      mutateOccurrence(
        factory,
        'FsvDecodeControl *const control = mesh_data.fsv_decode_control();',
        'FsvDecodeControl *const control = nullptr;',
        occurrence,
      ),
    mutate(
      valence,
      'control_(control) {}',
      'control_(nullptr) {}',
    ),
    mutate(
      valence,
      'context_symbols_[i].data(), control_)',
      'context_symbols_[i].data(), nullptr)',
    ),
  ];
  const mutationLabels = <String>[
    'attribute traverser call-site control',
    'portable texture factory placement control',
    'valence nested inner allocator control',
    'move-assignment allocator propagation',
    'swap allocator propagation',
    'factory control-source assignment 1',
    'factory control-source assignment 2',
    'factory control-source assignment 3',
    'valence retained member control',
    'valence entropy-call control',
  ];
  final escapedMutations = <String>[];
  for (var index = 0; index < mutations.length; index += 1) {
    if (_task5bWiringViolations(mutations[index]).isEmpty) {
      escapedMutations.add(mutationLabels[index]);
    }
  }
  expect(
    escapedMutations,
    isEmpty,
    reason: 'Mutations escaped the exact Task 5B wiring contract.',
  );
}

typedef _Task5bWiringRule = ({
  String path,
  String label,
  String marker,
  int count,
});

Future<Map<String, String>> _readTask5bWiringSources() async {
  final paths = _task5bWiringRules.map((rule) => rule.path).toSet();
  return <String, String>{
    for (final path in paths) path: await File(path).readAsString(),
  };
}

List<String> _task5bWiringViolations(Map<String, String> sources) {
  final violations = <String>[];
  for (final rule in _task5bWiringRules) {
    final source = sources[rule.path];
    if (source == null) {
      violations.add('${rule.label}: missing source ${rule.path}');
      continue;
    }
    final actual = RegExp(RegExp.escape(rule.marker)).allMatches(source).length;
    if (actual != rule.count) {
      violations.add(
        '${rule.label}: expected ${rule.count} exact wiring occurrence(s), '
        'found $actual',
      );
    }
  }
  return violations;
}

const _task5bWiringRules = <_Task5bWiringRule>[
  (
    path: 'third_party/draco/src/draco/core/fsv_decode_allocator.h',
    label: 'move-assignment allocator propagation',
    marker: 'using propagate_on_container_move_assignment = std::true_type;',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/core/fsv_decode_allocator.h',
    label: 'swap allocator propagation',
    marker: 'using propagate_on_container_swap = std::true_type;',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.h',
    label: 'attribute connectivity constructor control',
    marker: 'connectivity_data(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.h',
    label: 'attribute encoding constructor control',
    marker: 'encoding_data(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.h',
    label: 'attribute seam constructor control',
    marker: 'attribute_seam_corners(FsvDecodeAllocator<int32_t>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'implementation CornerIndex member controls',
    marker: 'FsvDecodeAllocator<CornerIndex>(control)',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'implementation integer member controls',
    marker: 'FsvDecodeAllocator<int>(control)',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'topology split member control',
    marker: 'FsvDecodeAllocator<TopologySplitEventData>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'hole event member control',
    marker: 'FsvDecodeAllocator<HoleEventData>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'implementation bool member controls',
    marker: 'FsvDecodeAllocator<bool>(control)',
    count: 4,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'new-to-parent node and bucket control',
    marker: 'FsvDecodeAllocator<std::pair<const int, int>>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'processed corner member control',
    marker: 'FsvDecodeAllocator<int32_t>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'attribute-data member control',
    marker: 'FsvDecodeAllocator<AttributeData>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'position encoding member control',
    marker: 'pos_encoding_data_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'traversal decoder member control',
    marker: 'traversal_decoder_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_decoder_impl.cc',
    label: 'all implementation runtime call-site controls',
    marker: 'decoder_->fsv_decode_control()',
    count: 16,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_decoder.h',
    label: 'standard traversal decoder array control',
    marker: 'FsvDecodeAllocator<BinaryDecoder>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_predictive_decoder.h',
    label: 'predictive base constructor control',
    marker: 'MeshEdgebreakerTraversalDecoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_predictive_decoder.h',
    label: 'predictive valence control',
    marker: 'vertex_valences_(FsvDecodeAllocator<int>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence base constructor control',
    marker: 'MeshEdgebreakerTraversalDecoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence indexed vector control',
    marker: 'vertex_valences_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence outer context control',
    marker: 'FsvDecodeAllocator<FsvVector<uint32_t>>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence counter control',
    marker: 'context_counters_(FsvDecodeAllocator<int>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence nested inner control',
    marker: 'context_symbols_.emplace_back('
        'FsvDecodeAllocator<uint32_t>(control_));',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence retained member control',
    marker: 'control_(control) {}',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_edgebreaker_traversal_valence_decoder.h',
    label: 'valence entropy-call control',
    marker: 'context_symbols_[i].data(), control_)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'traverser_base.h',
    label: 'traverser visited controls',
    marker: 'FsvDecodeAllocator<bool>(control)',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'depth_first_traverser.h',
    label: 'DFS base constructor control',
    marker: ': Base(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'depth_first_traverser.h',
    label: 'DFS stack control',
    marker: 'FsvDecodeAllocator<CornerIndex>(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'max_prediction_degree_traverser.h',
    label: 'max-prediction base and degree control',
    marker: ': Base(control), prediction_degree_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'max_prediction_degree_traverser.h',
    label: 'max-prediction fixed-array stack control',
    marker: 'stack = FsvVector<CornerIndex>('
        'FsvDecodeAllocator<CornerIndex>(control));',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/traverser/'
        'mesh_traversal_sequencer.h',
    label: 'mesh traversal sequencer control',
    marker: ': traverser_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoders_controller.cc',
    label: 'sequential controller base control',
    marker: ': AttributesDecoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoders_controller.cc',
    label: 'sequential decoder object-vector control',
    marker: 'FsvDecodeAllocator<std::unique_ptr<SequentialAttributeDecoder>>('
        '\n'
        '              control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_attribute_decoders_controller.cc',
    label: 'sequential point-id control',
    marker: 'point_ids_(FsvDecodeAllocator<PointIndex>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/ans.h',
    label: 'RANS lookup control',
    marker: 'lut_table_(FsvDecodeAllocator<uint32_t>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/ans.h',
    label: 'RANS probability control',
    marker: 'probability_table_(FsvDecodeAllocator<rans_sym>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'rans_symbol_decoder.h',
    label: 'symbol probability control',
    marker: 'probability_table_(FsvDecodeAllocator<uint32_t>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'rans_symbol_decoder.h',
    label: 'symbol nested RANS control',
    marker: 'ans_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'symbol_decoding.cc',
    label: 'tagged symbol constructor control',
    marker: 'tag_decoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'symbol_decoding.cc',
    label: 'raw symbol constructor control',
    marker: 'SymbolDecoderT decoder(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'symbol_decoding.cc',
    label: 'tagged symbol dispatch control',
    marker:
        'src_buffer, out_values,\n                                                  control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'symbol_decoding.cc',
    label: 'raw symbol dispatch control',
    marker:
        'src_buffer,\n                                               out_values, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/entropy/'
        'symbol_decoding.cc',
    label: 'raw symbol precision-branch controls',
    marker: 'num_values, src_buffer, out_values, control)',
    count: 18,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'sequential_integer_attribute_decoder.cc',
    label: 'integer symbol-call control',
    marker: 'decoder()->fsv_decode_control()',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/mesh/'
        'mesh_sequential_decoder.cc',
    label: 'sequential mesh symbol-call control',
    marker:
        'indices_buffer.data(),\n                     fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_interface.h',
    label: 'prediction object request allocator base',
    marker: 'PredictionSchemeInterface : public FsvDecodeAllocated',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder.h',
    label: 'prediction base control retention',
    marker: 'attribute_(attribute), transform_(transform), control_(control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_decoder.h',
    label: 'mesh prediction base constructor control',
    marker:
        'attribute, transform,\n                                                       control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'prediction factory control-source assignments',
    marker: 'FsvDecodeControl *const control = '
        'mesh_data.fsv_decode_control();',
    count: 3,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'parallelogram factory object control',
    marker: 'new (control) MeshPredictionSchemeParallelogramDecoder<',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'multi-parallelogram factory object control',
    marker: 'new (control) MeshPredictionSchemeMultiParallelogramDecoder<',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'constrained factory object control',
    marker: 'new (control)\n'
        '                MeshPredictionSchemeConstrainedMultiParallelogramDecoder<',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'deprecated texture factory object control',
    marker: 'new (control) MeshPredictionSchemeTexCoordsDecoder<',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'portable texture factory object control',
    marker: 'new (control) MeshPredictionSchemeTexCoordsPortableDecoder<',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'geometric-normal factory object controls',
    marker: 'new (control) MeshPredictionSchemeGeometricNormalDecoder<',
    count: 3,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'all mesh factory constructor controls',
    marker: 'mesh_data, control));',
    count: 7,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'deprecated texture constructor control',
    marker: 'attribute, transform, mesh_data, bitstream_version, control));',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'mesh factory data propagation control',
    marker: 'decoder->fsv_decode_control()',
    count: 4,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'delta factory object control',
    marker: 'new (decoder->fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_decoder_factory.h',
    label: 'allocator-aware default transform control',
    marker: 'return TransformT(control);',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_factory.h',
    label: 'mesh prediction data Set controls',
    marker: '&encoding_data->vertex_to_encoded_attribute_value_index_map,\n'
        '             control);',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_data.h',
    label: 'mesh prediction data retained control',
    marker: 'control_ = control;',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_delta_decoder.h',
    label: 'delta base constructor control',
    marker:
        'attribute, transform,\n                                                       control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_delta_decoder.h',
    label: 'delta scratch control',
    marker: 'FsvDecodeAllocator<DataTypeT>(this->fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_parallelogram_decoder.h',
    label: 'parallelogram base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_parallelogram_decoder.h',
    label: 'parallelogram scratch control',
    marker: 'FsvDecodeAllocator<DataTypeT>(this->fsv_decode_control())',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_multi_parallelogram_decoder.h',
    label: 'multi-parallelogram base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_multi_parallelogram_decoder.h',
    label: 'multi-parallelogram scratch controls',
    marker: 'FsvDecodeAllocator<DataTypeT>(this->fsv_decode_control())',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/'
        'mesh_prediction_scheme_constrained_multi_parallelogram_decoder.h',
    label: 'constrained base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/'
        'mesh_prediction_scheme_constrained_multi_parallelogram_decoder.h',
    label: 'constrained fixed-array assignment control',
    marker: 'flags = FsvVector<bool>(FsvDecodeAllocator<bool>(control));',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/'
        'mesh_prediction_scheme_constrained_multi_parallelogram_decoder.h',
    label: 'constrained runtime scratch controls',
    marker: 'this->fsv_decode_control()',
    count: 3,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_tex_coords_decoder.h',
    label: 'deprecated texture base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_tex_coords_decoder.h',
    label: 'deprecated texture constructor controls',
    marker: 'FsvDecodeAllocator<',
    count: 2,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_tex_coords_portable_decoder.h',
    label: 'portable texture base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_tex_coords_portable_decoder.h',
    label: 'portable texture predictor constructor control',
    marker: 'predictor_(mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/'
        'mesh_prediction_scheme_tex_coords_portable_predictor.h',
    label: 'portable texture orientation control',
    marker: 'orientations_(FsvDecodeAllocator<bool>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/mesh_prediction_scheme_geometric_normal_decoder.h',
    label: 'geometric-normal base constructor control',
    marker: 'attribute, transform, mesh_data, control)',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_wrap_transform_base.h',
    label: 'wrap/clamp scratch control',
    marker: 'clamped_value_(FsvDecodeAllocator<DataTypeT>(control))',
    count: 1,
  ),
  (
    path: 'third_party/draco/src/draco/compression/attributes/'
        'prediction_schemes/prediction_scheme_wrap_decoding_transform.h',
    label: 'wrap decoding base constructor control',
    marker: ': PredictionSchemeWrapTransformBase<DataTypeT>(control)',
    count: 1,
  ),
];

const String _combinedControlsRunner = r'''
#include "fsv_draco_control.h"
#include "fsv_basisu_control.h"

int main() {
  fsv_draco::FsvDecodeControl draco(8);
  fsv_basisu::FsvDecodeControl basisu(8);
  if (!draco.TryReserve(1) || !basisu.TryReserve(1)) return 1;
  draco.Release(1);
  basisu.Release(1);
  return 0;
}
''';

Future<void> _expectOwnerMutationsRejected({
  required String packageName,
  required String runnerClass,
  required String javaSourcePath,
  required String javaRunner,
  required String nativeHeaderDirectory,
  required String nativeControlPath,
  required String nativeRegistryPath,
  required String nativeRunner,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('fsv_owner_mutations_');
  try {
    final javaSource = await File(javaSourcePath).readAsString();
    final javaMutations = <({String label, String before, String after})>[
      (
        label: 'duplicate registration',
        before: 'if (detached || active.containsKey(requestId)) {',
        after: 'if (detached) {',
      ),
      (
        label: 'registration after detach',
        before: 'if (detached || active.containsKey(requestId)) {',
        after: 'if (active.containsKey(requestId)) {',
      ),
      (
        label: 'queued shouldStart',
        before: 'return !detached && entry.state == Entry.State.ACTIVE;',
        after: 'return !detached;',
      ),
      (
        label: 'delivery after detach',
        before: 'if (detached || entry.delivered) {',
        after: 'if (entry.delivered) {',
      ),
      (
        label: 'unknown request status',
        before:
            'return finished.contains(requestId) ? "alreadyFinished" : "unknownRequest";',
        after: 'return "alreadyFinished";',
      ),
    ];
    for (var index = 0; index < javaMutations.length; index += 1) {
      final mutation = javaMutations[index];
      final mutated = javaSource.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(javaSource), reason: mutation.label);
      final directory = Directory('${tempDir.path}/java-$index')..createSync();
      final sourceFile =
          File('${directory.path}/FsvDecodeRequestRegistry.java');
      final runnerFile = File('${directory.path}/$runnerClass.java');
      await sourceFile.writeAsString(mutated);
      await runnerFile.writeAsString(javaRunner);
      final compile = await Process.run('javac', <String>[
        '-d',
        directory.path,
        sourceFile.path,
        runnerFile.path,
      ]);
      expect(compile.exitCode, 0,
          reason: '${mutation.label}\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(
        'java',
        <String>['-cp', directory.path, '$packageName.$runnerClass'],
      );
      expect(run.exitCode, isNot(0),
          reason: '${mutation.label} Java mutation escaped the runner');
    }

    final nativeSource = await File(nativeRegistryPath).readAsString();
    final nativeMutations = <({String label, String before, String after})>[
      (
        label: 'duplicate registration',
        before: 'if (detached_ || active_.find(request_id) != active_.end()) {',
        after: 'if (detached_) {',
      ),
      (
        label: 'registration after detach',
        before: 'if (detached_ || active_.find(request_id) != active_.end()) {',
        after: 'if (active_.find(request_id) != active_.end()) {',
      ),
      (
        label: 'queued ShouldStart',
        before: 'return !detached_ && entry != nullptr &&\n'
            '         entry->state == Entry::State::kActive;',
        after: 'return !detached_ && entry != nullptr;',
      ),
      (
        label: 'delivery after detach',
        before: 'if (detached_ || entry == nullptr || entry->delivered) {',
        after: 'if (entry == nullptr || entry->delivered) {',
      ),
      (
        label: 'unknown request status',
        before: ': FsvCancelStatus::kUnknownRequest;',
        after: ': FsvCancelStatus::kAlreadyFinished;',
      ),
    ];
    for (var index = 0; index < nativeMutations.length; index += 1) {
      final mutation = nativeMutations[index];
      final mutated =
          nativeSource.replaceFirst(mutation.before, mutation.after);
      expect(mutated, isNot(nativeSource), reason: mutation.label);
      final sourceFile = File('${tempDir.path}/registry-$index.cc');
      final runnerFile = File('${tempDir.path}/registry-runner-$index.cc');
      final executable = '${tempDir.path}/registry-$index';
      await sourceFile.writeAsString(mutated);
      await runnerFile.writeAsString(nativeRunner);
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-pthread',
        '-I$nativeHeaderDirectory',
        runnerFile.path,
        nativeControlPath,
        sourceFile.path,
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '${mutation.label}\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, isNot(0),
          reason: '${mutation.label} C++ mutation escaped the runner');
    }
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

const String _decodeControlRunner = r'''
#include "fsv_draco_control.h"
#include <cstddef>
#include <thread>

int main() {
  fsv_draco::FsvDecodeControl control(16);
  if (!control.TryReserve(8) || control.live_bytes() != 8) return 1;
  if (control.peak_bytes() != 8 || control.allocation_count() != 1) return 13;
  if (control.TryReserve(9)) return 2;
  if (control.stop_reason() != fsv_draco::FsvDecodeStopReason::kBudget) return 3;
  if (control.reserve_rejection_count() != 1) return 14;
  control.Release(8);
  if (control.live_bytes() != 0) return 4;
  if (control.release_count() != 1) return 15;
  if (control.Cancel() || control.Cancel()) return 5;
  if (control.IsCancelled()) return 6;
  if (control.stop_reason() != fsv_draco::FsvDecodeStopReason::kBudget) return 7;
  if (control.TryReserve(1)) return 8;
  fsv_draco::FsvDecodeControl caller_wins(0);
  const bool caller_won = caller_wins.Cancel();
  if (!caller_won ||
      caller_wins.stop_reason() !=
          fsv_draco::FsvDecodeStopReason::kCallerCancelled) return 9;
  fsv_draco::FsvDecodeControl scoped(16);
  {
    fsv_draco::FsvScopedWorkingReservation reservation(&scoped, 8);
    if (!reservation.ok() || scoped.live_bytes() != 8) return 16;
  }
  if (scoped.live_bytes() != 0 || scoped.peak_bytes() != 8 ||
      scoped.allocation_count() != 1 || scoped.release_count() != 1) return 17;
  fsv_draco::FsvDecodeControl allocated(16);
  auto allocation =
      allocated.AllocateMemory(8, alignof(std::max_align_t));
  void* bytes = allocation.allocation;
  if (allocation.outcome !=
          fsv_draco::FsvDecodeAllocationOutcome::kSuccess ||
      bytes == nullptr || allocated.live_bytes() != 8 ||
      allocated.allocation_count() != 1) return 18;
  if (!allocated.ReleaseMemory(
          &allocation, bytes, 8, alignof(std::max_align_t))) return 19;
  if (allocated.live_bytes() != 0 || allocated.release_count() != 1) return 19;
  fsv_draco::FsvDecodeControl rejected(7);
  const auto rejection =
      rejected.AllocateMemory(8, alignof(std::max_align_t));
  if (rejection.allocation != nullptr ||
      rejection.outcome !=
          fsv_draco::FsvDecodeAllocationOutcome::kBudgetExceeded ||
      rejected.stop_reason() != fsv_draco::FsvDecodeStopReason::kBudget ||
      rejected.live_bytes() != 0) return 20;
  for (int iteration = 0; iteration < 500; ++iteration) {
    fsv_draco::FsvDecodeControl raced(0);
    bool cancel_result = false;
    std::thread caller([&] { cancel_result = raced.Cancel(); });
    std::thread budget([&] { raced.TryReserve(1); });
    caller.join();
    budget.join();
    auto reason = raced.stop_reason();
    if (reason != fsv_draco::FsvDecodeStopReason::kCallerCancelled &&
        reason != fsv_draco::FsvDecodeStopReason::kBudget) return 10;
    if (reason == fsv_draco::FsvDecodeStopReason::kCallerCancelled &&
        (!cancel_result || !raced.IsCancelled())) return 11;
    if (reason == fsv_draco::FsvDecodeStopReason::kBudget &&
        (cancel_result || raced.IsCancelled())) return 12;
  }
  return 0;
}
''';

const String _javaLifecycleRunner = r'''
package com.marlonjd.flutter_scene_viewer_draco;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public final class DracoRegistryRunner {
  private static final class Control implements FsvDecodeRequestRegistry.Control {
    final AtomicInteger cancels = new AtomicInteger();
    final AtomicInteger destroys = new AtomicInteger();
    public void cancel() { cancels.incrementAndGet(); }
    public void destroy() { destroys.incrementAndGet(); }
  }

  public static void main(String[] args) throws Exception {
    FsvDecodeRequestRegistry registry = new FsvDecodeRequestRegistry();
    Control queued = new Control();
    FsvDecodeRequestRegistry.Entry queuedEntry = registry.register("queued", queued);
    if (registry.register("queued", new Control()) != null) System.exit(1);
    if (!"cancelled".equals(registry.cancel("queued"))) System.exit(1);
    if (!"cancelled".equals(registry.cancel("queued"))) System.exit(2);
    if (queued.cancels.get() != 1) System.exit(3);
    if (registry.shouldStart(queuedEntry)) System.exit(4);
    if (registry.finish("queued", queuedEntry) !=
        FsvDecodeRequestRegistry.FinishDisposition.CANCELLED) System.exit(5);
    if (!"alreadyFinished".equals(registry.cancel("queued"))) System.exit(6);
    if (!"unknownRequest".equals(registry.cancel("missing"))) System.exit(7);
    if (queued.destroys.get() != 1) System.exit(8);

    Control during = new Control();
    FsvDecodeRequestRegistry.Entry duringEntry = registry.register("during", during);
    CountDownLatch start = new CountDownLatch(1);
    Thread cancel = new Thread(() -> {
      try { start.await(); } catch (InterruptedException error) { throw new RuntimeException(error); }
      registry.cancel("during");
    });
    cancel.start();
    start.countDown();
    cancel.join();
    if (registry.finish("during", duringEntry) !=
        FsvDecodeRequestRegistry.FinishDisposition.CANCELLED) System.exit(9);

    Control won = new Control();
    FsvDecodeRequestRegistry.Entry wonEntry = registry.register("won", won);
    if (registry.finish("won", wonEntry) !=
        FsvDecodeRequestRegistry.FinishDisposition.SUCCESS) System.exit(10);
    if (!"alreadyFinished".equals(registry.cancel("won"))) System.exit(11);
    if (!registry.claimDelivery(wonEntry) || registry.claimDelivery(wonEntry)) System.exit(12);

    for (int iteration = 0; iteration < 500; iteration += 1) {
      String requestId = "race-" + iteration;
      Control raced = new Control();
      FsvDecodeRequestRegistry.Entry racedEntry = registry.register(requestId, raced);
      CountDownLatch raceStart = new CountDownLatch(1);
      AtomicReference<String> cancelStatus = new AtomicReference<>();
      AtomicReference<FsvDecodeRequestRegistry.FinishDisposition> finishStatus =
          new AtomicReference<>();
      Thread racedCancel = new Thread(() -> {
        try { raceStart.await(); } catch (InterruptedException error) { throw new RuntimeException(error); }
        cancelStatus.set(registry.cancel(requestId));
      });
      Thread racedFinish = new Thread(() -> {
        try { raceStart.await(); } catch (InterruptedException error) { throw new RuntimeException(error); }
        finishStatus.set(registry.finish(requestId, racedEntry));
      });
      racedCancel.start();
      racedFinish.start();
      raceStart.countDown();
      racedCancel.join();
      racedFinish.join();
      boolean cancelWon = "cancelled".equals(cancelStatus.get()) &&
          finishStatus.get() == FsvDecodeRequestRegistry.FinishDisposition.CANCELLED &&
          raced.cancels.get() == 1;
      boolean finishWon = "alreadyFinished".equals(cancelStatus.get()) &&
          finishStatus.get() == FsvDecodeRequestRegistry.FinishDisposition.SUCCESS &&
          raced.cancels.get() == 0;
      if ((!cancelWon && !finishWon) || raced.destroys.get() != 1) System.exit(13);
      if (!registry.claimDelivery(racedEntry) || registry.claimDelivery(racedEntry)) System.exit(14);
    }

    Control detached = new Control();
    FsvDecodeRequestRegistry.Entry detachedEntry = registry.register("detached", detached);
    registry.beginDetach();
    if (registry.claimDelivery(detachedEntry)) System.exit(15);
    if (registry.register("after-detach", new Control()) != null) System.exit(16);
    registry.drainAfterWorkers();
    if (registry.activeCount() != 0 || detached.cancels.get() != 1 ||
        detached.destroys.get() != 1) System.exit(17);
  }
}
''';

const String _nativeLifecycleRunner = r'''
#include "fsv_draco_request_registry.h"
#include <atomic>
#include <thread>

int main() {
  fsv_draco::FsvDecodeRequestRegistry registry;
  auto queued = registry.Register("queued", 16);
  if (registry.Register("queued", 16) != nullptr) return 1;
  if (registry.Cancel("queued") != fsv_draco::FsvCancelStatus::kCancelled) return 1;
  if (registry.Cancel("queued") != fsv_draco::FsvCancelStatus::kCancelled) return 2;
  if (registry.ShouldStart(queued)) return 3;
  if (registry.Finish("queued", queued) !=
      fsv_draco::FsvFinishDisposition::kCancelled) return 4;
  if (registry.Cancel("queued") != fsv_draco::FsvCancelStatus::kAlreadyFinished) return 5;
  if (registry.Cancel("missing") != fsv_draco::FsvCancelStatus::kUnknownRequest) return 6;

  auto won = registry.Register("won", 16);
  if (registry.Finish("won", won) != fsv_draco::FsvFinishDisposition::kSuccess) return 7;
  if (registry.Cancel("won") != fsv_draco::FsvCancelStatus::kAlreadyFinished) return 8;
  if (!registry.ClaimDelivery(won) || registry.ClaimDelivery(won)) return 9;

  for (int iteration = 0; iteration < 500; ++iteration) {
    const std::string request_id = "race-" + std::to_string(iteration);
    auto raced = registry.Register(request_id, 16);
    auto control = raced->control;
    std::atomic<bool> start{false};
    fsv_draco::FsvCancelStatus cancel_status;
    fsv_draco::FsvFinishDisposition finish_status;
    std::thread cancel([&] {
      while (!start.load(std::memory_order_acquire)) {}
      cancel_status = registry.Cancel(request_id);
    });
    std::thread finish([&] {
      while (!start.load(std::memory_order_acquire)) {}
      finish_status = registry.Finish(request_id, raced);
    });
    start.store(true, std::memory_order_release);
    cancel.join();
    finish.join();
    const bool cancel_won =
        cancel_status == fsv_draco::FsvCancelStatus::kCancelled &&
        finish_status == fsv_draco::FsvFinishDisposition::kCancelled &&
        control->IsCancelled();
    const bool finish_won =
        cancel_status == fsv_draco::FsvCancelStatus::kAlreadyFinished &&
        finish_status == fsv_draco::FsvFinishDisposition::kSuccess &&
        !control->IsCancelled();
    if (!cancel_won && !finish_won) return 10;
    if (!registry.ClaimDelivery(raced) || registry.ClaimDelivery(raced)) return 11;
  }

  auto detached = registry.Register("detach", 16);
  registry.BeginDetach();
  if (registry.ClaimDelivery(detached)) return 12;
  if (registry.Register("after-detach", 16) != nullptr) return 13;
  registry.DrainAfterWorkers();
  return registry.active_count() == 0 ? 0 : 14;
}
''';

const String _budgetPreflightRunner = r'''
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "fsv_draco_budget.h"

namespace {
FsvDracoDecodeBudgetMetadata Budget(int64_t decoded,
                                    int64_t accessors,
                                    int64_t vertices,
                                    int64_t indices,
                                    int64_t native_output) {
  FsvDracoDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(decoded);
  budget.max_accessors = FsvDracoBudgetNumber::Integer(accessors);
  budget.max_vertices = FsvDracoBudgetNumber::Integer(vertices);
  budget.max_indices = FsvDracoBudgetNumber::Integer(indices);
  budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(native_output);
  return budget;
}

FsvDracoDecodeBudgetState EmptyState() {
  FsvDracoDecodeBudgetState state;
  state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
  state.accessors = FsvDracoBudgetNumber::Integer(0);
  state.vertices = FsvDracoBudgetNumber::Integer(0);
  state.indices = FsvDracoBudgetNumber::Integer(0);
  state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);
  return state;
}

FsvDracoPrimitiveRequest Request(int mesh,
                                 int primitive,
                                 int64_t accessor,
                                 int64_t vertex_count,
                                 bool indexed = true) {
  FsvDracoPrimitiveRequest request;
  request.mesh_index = mesh;
  request.primitive_index = primitive;
  request.vertex_accessor_index = accessor;
  request.attributes["POSITION"] = 7;
  FsvDracoAccessorSchema position;
  position.accessor_index = accessor;
  position.component_type = FsvDracoBudgetNumber::Integer(5126);
  position.type = "VEC3";
  position.count = vertex_count;
  request.attribute_accessors["POSITION"] = position;
  if (indexed) {
    request.has_indices_accessor = true;
    request.indices_accessor.accessor_index = accessor + 1;
    request.indices_accessor.component_type =
        FsvDracoBudgetNumber::Integer(5123);
    request.indices_accessor.type = "SCALAR";
    request.indices_accessor.count = 3;
  }
  return request;
}

FsvDracoPrimitiveRequests Requests(
    const FsvDracoPrimitiveRequest& first,
    const FsvDracoPrimitiveRequest* second = nullptr) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(nullptr)};
  requests.emplace_back(first, nullptr);
  if (second != nullptr) requests.emplace_back(*second, nullptr);
  return requests;
}

bool FailureField(const FsvDracoPreflightResult& result,
                  const std::string& field,
                  const std::string& status = "budgetExceeded") {
  return !result.ok && result.diagnostics.size() == 1 &&
         result.diagnostics[0].field == field.c_str() &&
         result.diagnostics[0].status == status.c_str();
}

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}
}  // namespace

#define CHECK(value) do { if (!(value)) return Fail(__LINE__); } while (false)

int main() {
  const FsvDracoDecodeBudgetState empty = EmptyState();
  const FsvDracoPrimitiveRequest one_request = Request(0, 0, 0, 2);
  const FsvDracoPrimitiveRequests one = Requests(one_request);
  auto exact = FsvDracoPreflightRequests(one, Budget(30, 2, 2, 3, 30), empty);
  CHECK(exact.ok);
  CHECK(exact.total_decoded_bytes == 30);
  CHECK(exact.native_output_bytes == 30);
  CHECK(exact.accessors == 2);
  CHECK(exact.vertices == 2);
  CHECK(exact.indices == 3);
  CHECK(FailureField(FsvDracoPreflightRequests(one, Budget(29, 2, 2, 3, 30), empty),
                     "totalDecodedBytes"));
  CHECK(FailureField(FsvDracoPreflightRequests(one, Budget(30, 1, 2, 3, 30), empty),
                     "accessors"));
  CHECK(FailureField(FsvDracoPreflightRequests(one, Budget(30, 2, 1, 3, 30), empty),
                     "vertices"));
  CHECK(FailureField(FsvDracoPreflightRequests(one, Budget(30, 2, 2, 2, 30), empty),
                     "indices"));
  CHECK(FailureField(FsvDracoPreflightRequests(one, Budget(30, 2, 2, 3, 29), empty),
                     "nativeOutputBytes"));

  const FsvDracoPrimitiveRequest two_first = Request(0, 0, 0, 1, false);
  const FsvDracoPrimitiveRequest two_second = Request(0, 1, 1, 1, false);
  const FsvDracoPrimitiveRequests two = Requests(two_first, &two_second);
  CHECK(FailureField(FsvDracoPreflightRequests(two, Budget(23, 2, 2, 0, 24), empty),
                     "totalDecodedBytes"));

  const FsvDracoPrimitiveRequest reused_first = Request(0, 0, 7, 1, false);
  const FsvDracoPrimitiveRequest reused_second = Request(0, 1, 7, 1, false);
  const FsvDracoPrimitiveRequests reused =
      Requests(reused_first, &reused_second);
  auto reused_result =
      FsvDracoPreflightRequests(reused, Budget(24, 1, 1, 0, 24), empty);
  CHECK(reused_result.ok);
  CHECK(reused_result.accessors == 1);
  CHECK(reused_result.vertices == 1);
  CHECK(reused_result.native_output_bytes == 24);

  const FsvDracoPrimitiveRequest reused_index_first = Request(0, 0, 17, 1);
  const FsvDracoPrimitiveRequest reused_index_second = Request(0, 1, 17, 1);
  const FsvDracoPrimitiveRequests reused_index =
      Requests(reused_index_first, &reused_index_second);
  auto reused_index_result =
      FsvDracoPreflightRequests(reused_index, Budget(36, 2, 1, 3, 36), empty);
  CHECK(reused_index_result.ok);
  CHECK(reused_index_result.accessors == 2);
  CHECK(reused_index_result.vertices == 1);
  CHECK(reused_index_result.indices == 3);
  CHECK(reused_index_result.native_output_bytes == 36);

  const int64_t above_int32 = INT64_C(2147483648);
  const FsvDracoPrimitiveRequest large_request =
      Request(0, 0, 50, above_int32, false);
  const FsvDracoPrimitiveRequests large = Requests(large_request);
  auto large_result = FsvDracoPreflightRequests(
      large,
      Budget(above_int32 * 12, 1, above_int32, 0, above_int32 * 12),
      empty);
  CHECK(large_result.ok);
  CHECK(large_result.vertices == static_cast<uint64_t>(above_int32));

  const FsvDracoPrimitiveRequest product_overflow_request =
      Request(0, 0, 80, kFsvDracoMaxSafeInteger, false);
  const FsvDracoPrimitiveRequests product_overflow =
      Requests(product_overflow_request);
  CHECK(FailureField(
      FsvDracoPreflightRequests(
          product_overflow,
          Budget(kFsvDracoMaxSafeInteger, 1, kFsvDracoMaxSafeInteger, 0,
                 kFsvDracoMaxSafeInteger),
          empty),
      "accessor.count", "invalidMetadata"));

  FsvDracoDecodeBudgetMetadata missing;
  CHECK(FailureField(FsvDracoPreflightRequests(one, missing, empty),
                     "maxTotalDecodedBytes", "invalidMetadata"));
  auto negative = Budget(30, 2, 2, 3, 30);
  negative.max_vertices = FsvDracoBudgetNumber::Integer(-1);
  CHECK(FailureField(FsvDracoPreflightRequests(one, negative, empty),
                     "maxVertices", "invalidMetadata"));
  auto wrong_type = Budget(30, 2, 2, 3, 30);
  wrong_type.max_vertices = FsvDracoBudgetNumber::Invalid();
  CHECK(FailureField(FsvDracoPreflightRequests(one, wrong_type, empty),
                     "maxVertices", "invalidMetadata"));
  FsvDracoPrimitiveRequest invalid_attribute_id = Request(0, 0, 0, 2);
  invalid_attribute_id.attributes["POSITION"] = -1;
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(invalid_attribute_id),
                                Budget(30, 2, 2, 3, 30), empty),
      "dracoAttributeId", "invalidMetadata"));

  for (const int64_t legal : {INT64_C(5120), INT64_C(5121), INT64_C(5122),
                              INT64_C(5123), INT64_C(5125), INT64_C(5126)}) {
    FsvDracoPrimitiveRequest legal_component = Request(0, 0, 0, 1, false);
    legal_component.attribute_accessors["POSITION"].component_type =
        FsvDracoBudgetNumber::Integer(legal);
    legal_component.attribute_accessors["POSITION"].type = "SCALAR";
    CHECK(FsvDracoPreflightRequests(
              Requests(legal_component), Budget(4, 1, 1, 0, 4), empty)
              .ok);
  }
  for (const int64_t legal : {INT64_C(5121), INT64_C(5123), INT64_C(5125)}) {
    FsvDracoPrimitiveRequest legal_index = Request(0, 0, 0, 1);
    legal_index.indices_accessor.component_type =
        FsvDracoBudgetNumber::Integer(legal);
    CHECK(FsvDracoPreflightRequests(
              Requests(legal_index), Budget(24, 2, 1, 3, 24), empty)
              .ok);
  }
  FsvDracoPrimitiveRequest missing_component = Request(0, 0, 0, 1, false);
  missing_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber();
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(missing_component), Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest wrong_component_type = Request(0, 0, 0, 1, false);
  wrong_component_type.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Invalid();
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(wrong_component_type),
                                Budget(12, 1, 1, 0, 12), empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest negative_component = Request(0, 0, 0, 1, false);
  negative_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(-1);
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(negative_component),
                                Budget(12, 1, 1, 0, 12), empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest alias_component = Request(0, 0, 0, 1, false);
  alias_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(INT64_C(5126) + (INT64_C(1) << 32));
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(alias_component), Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest unsafe_component = Request(0, 0, 0, 1, false);
  unsafe_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(kFsvDracoMaxSafeInteger + 1);
  CHECK(FailureField(
      FsvDracoPreflightRequests(Requests(unsafe_component), Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));

  FsvDracoPrimitiveRequest missing_id_request = Request(0, 0, 0, 1, false);
  missing_id_request.attributes["NORMAL"] = 9;
  FsvDracoAccessorSchema normal(
      missing_id_request.attribute_accessors["POSITION"], nullptr);
  normal.accessor_index = 1;
  missing_id_request.attribute_accessors["NORMAL"] = normal;
  FsvDracoDecodedMeshMetadata decoded_mesh;
  decoded_mesh.point_count = 1;
  decoded_mesh.face_count = 0;
  decoded_mesh.attribute_unique_ids.insert(7);
  size_t output_vector_allocations = 0;
  size_t decoded_primitive_count = 0;
  const FsvDracoPostDecodeValidationResult post_decode =
      FsvDracoValidateDecodedSchemas(Requests(missing_id_request),
                                     {decoded_mesh});
  if (post_decode.ok) {
    output_vector_allocations += 1;
    decoded_primitive_count += 1;
  }
  CHECK(!post_decode.ok);
  CHECK(post_decode.diagnostics.size() == 1);
  CHECK(post_decode.diagnostics[0].field == "dracoAttributeId");
  CHECK(post_decode.diagnostics[0].attribute == "NORMAL");
  CHECK(output_vector_allocations == 0);
  CHECK(decoded_primitive_count == 0);
  return 0;
}
''';

const String _postDecodeBridgeRunner = r'''
#include "fsv_draco_bridge.h"

FsvDracoPrimitiveRequests Requests(const FsvDracoPrimitiveRequest& source) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(nullptr)};
  requests.emplace_back(source, nullptr);
  return requests;
}

int main() {
  FsvDracoPrimitiveRequest request;
  request.mesh_index = 0;
  request.primitive_index = 0;
  request.compressed_bytes = {1};
  request.attributes["POSITION"] = 7;
  request.attributes["NORMAL"] = 9;
  request.vertex_accessor_index = 0;
  FsvDracoAccessorSchema position;
  position.accessor_index = 0;
  position.component_type = FsvDracoBudgetNumber::Integer(5126);
  position.type = "VEC3";
  position.count = 1;
  request.attribute_accessors["POSITION"] = position;
  FsvDracoAccessorSchema normal(position, nullptr);
  normal.accessor_index = 1;
  request.attribute_accessors["NORMAL"] = normal;

  FsvDracoDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(24);
  budget.max_accessors = FsvDracoBudgetNumber::Integer(2);
  budget.max_vertices = FsvDracoBudgetNumber::Integer(1);
  budget.max_indices = FsvDracoBudgetNumber::Integer(0);
  budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(24);
  FsvDracoDecodeBudgetState state;
  state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
  state.accessors = FsvDracoBudgetNumber::Integer(0);
  state.vertices = FsvDracoBudgetNumber::Integer(0);
  state.indices = FsvDracoBudgetNumber::Integer(0);
  state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);
  FsvDracoDecodeTestingCounters counters;

  const FsvDracoDecodeResult result =
      FsvDracoDecodePrimitives(Requests(request), budget, state, &counters);
  if (!result.decoded_primitives.empty() || result.diagnostics.size() != 1 ||
      result.diagnostics[0].status != "malformedOutput" ||
      result.diagnostics[0].field != "dracoAttributeId" ||
      result.diagnostics[0].attribute != "NORMAL" ||
      counters.output_vector_allocations != 0) {
    return 1;
  }
  return 0;
}
''';

const String _fakeDracoMeshHeader = r'''
#pragma once
#include <array>
#include <cstdint>

namespace draco {
class PointIndex {
 public:
  explicit PointIndex(int64_t value) : value_(static_cast<int>(value)) {}
  int value() const { return value_; }
 private:
  int value_;
};

class AttributeValueIndex {
 public:
  explicit AttributeValueIndex(int value) : value_(value) {}
  int value() const { return value_; }
 private:
  int value_;
};

class PointAttribute {
 public:
  AttributeValueIndex mapped_index(PointIndex point) const {
    return AttributeValueIndex(point.value());
  }
  template <typename T>
  bool ConvertValue(AttributeValueIndex, int8_t components, T* values) const {
    for (int index = 0; index < components; ++index) values[index] = T{};
    return true;
  }
};

class FaceIndex {
 public:
  explicit FaceIndex(int value) : value_(value) {}
  FaceIndex& operator++() { ++value_; return *this; }
  int value() const { return value_; }
 private:
  int value_;
};
inline bool operator<(const FaceIndex& index, int count) {
  return index.value() < count;
}

class CornerIndex {
 public:
  CornerIndex(int value = 0) : value_(value) {}
  int value() const { return value_; }
 private:
  int value_;
};

class Mesh {
 public:
  using Face = std::array<CornerIndex, 3>;
  int num_points() const { return 1; }
  int num_faces() const { return 0; }
  const PointAttribute* GetAttributeByUniqueId(uint32_t id) const {
    return id == 7 ? &position_ : nullptr;
  }
  const Face& face(FaceIndex) const { return face_; }
 private:
  PointAttribute position_;
  Face face_{};
};
}  // namespace draco
''';

const String _fakeDracoBufferHeader = r'''
#pragma once
#include <cstddef>
namespace draco {
class DecoderBuffer {
 public:
  void Init(const char*, size_t) {}
};
}  // namespace draco
''';

const String _fakeDracoDecodeHeader = r'''
#pragma once
#include <memory>
#include <exception>
#include <new>
#include <utility>
#include "draco/core/decoder_buffer.h"
#include "draco/core/fsv_decode_allocator.h"
#include "draco/mesh/mesh.h"

namespace draco {
enum EncodedGeometryType { INVALID_GEOMETRY = -1, TRIANGULAR_MESH = 1 };

template <typename T>
class FakeStatusOr {
 public:
  explicit FakeStatusOr(T value) : value_(std::move(value)) {}
  bool ok() const { return true; }
  T& value() & { return value_; }
  T&& value() && { return std::move(value_); }
 private:
  T value_;
};

class Decoder {
 public:
  static FakeStatusOr<EncodedGeometryType> GetEncodedGeometryType(
      DecoderBuffer*) {
    return FakeStatusOr<EncodedGeometryType>(TRIANGULAR_MESH);
  }
  FakeStatusOr<std::unique_ptr<Mesh>> DecodeMeshFromBuffer(
      DecoderBuffer*, FsvDecodeControl* = nullptr) {
    return FakeStatusOr<std::unique_ptr<Mesh>>(std::make_unique<Mesh>());
  }
};
}  // namespace draco
''';

const String _fakeJniHeader = r'''
#pragma once
#include <cstddef>
#include <cstdint>

#define JNIEXPORT
#define JNICALL
#define JNI_TRUE 1
#define JNI_FALSE 0

using jboolean = unsigned char;
using jbyte = signed char;
using jint = int;
using jlong = long long;
using jsize = int;
using jmethodID = void*;

struct _jobject {};
using jobject = _jobject*;
using jclass = jobject;
using jstring = jobject;
using jarray = jobject;
using jbyteArray = jobject;

struct JNIEnv {
  jclass FindClass(const char*);
  jmethodID GetMethodID(jclass, const char*, const char*);
  jboolean IsInstanceOf(jobject, jclass);
  jobject NewObject(jclass, jmethodID, ...);
  jstring NewStringUTF(const char*);
  jobject CallObjectMethod(jobject, jmethodID, ...);
  jint CallIntMethod(jobject, jmethodID, ...);
  jlong CallLongMethod(jobject, jmethodID, ...);
  jboolean CallBooleanMethod(jobject, jmethodID, ...);
  jsize GetArrayLength(jarray);
  void GetByteArrayRegion(jbyteArray, jsize, jsize, jbyte*);
  jbyteArray NewByteArray(jsize);
  void SetByteArrayRegion(jbyteArray, jsize, jsize, const jbyte*);
  const char* GetStringUTFChars(jstring, jboolean*);
  void ReleaseStringUTFChars(jstring, const char*);
  jboolean ExceptionCheck();
  void ExceptionClear();
  void DeleteLocalRef(jobject);
};
''';
