import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
    final licenseFile = File('test/fixtures/draco/Box/LICENSE.md');
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
  });

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
        '-I$platform',
        runner.path,
        '$platform/fsv_draco_budget.cc',
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
        'IntegralLongValueOr(env, MapGet(env, value, "count"), -1)',
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
      'FsvDracoValidateDecodedSchemas(requests, decoded_metadata)',
    );
    final firstOutputAllocation = bridge.indexOf(
      'if (!DecodeAttributeBytes(*attribute',
    );
    expect(completeValidation, greaterThanOrEqualTo(0));
    expect(firstOutputAllocation, greaterThan(completeValidation));
  });
}

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

bool FailureField(const FsvDracoPreflightResult& result,
                  const std::string& field,
                  const std::string& status = "budgetExceeded") {
  return !result.ok && result.diagnostics.size() == 1 &&
         result.diagnostics[0].field == field &&
         result.diagnostics[0].status == status;
}

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}
}  // namespace

#define CHECK(value) do { if (!(value)) return Fail(__LINE__); } while (false)

int main() {
  const FsvDracoDecodeBudgetState empty = EmptyState();
  const std::vector<FsvDracoPrimitiveRequest> one = {Request(0, 0, 0, 2)};
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

  const std::vector<FsvDracoPrimitiveRequest> two = {
      Request(0, 0, 0, 1, false), Request(0, 1, 1, 1, false)};
  CHECK(FailureField(FsvDracoPreflightRequests(two, Budget(23, 2, 2, 0, 24), empty),
                     "totalDecodedBytes"));

  const std::vector<FsvDracoPrimitiveRequest> reused = {
      Request(0, 0, 7, 1, false), Request(0, 1, 7, 1, false)};
  auto reused_result =
      FsvDracoPreflightRequests(reused, Budget(24, 1, 1, 0, 24), empty);
  CHECK(reused_result.ok);
  CHECK(reused_result.accessors == 1);
  CHECK(reused_result.vertices == 1);
  CHECK(reused_result.native_output_bytes == 24);

  const std::vector<FsvDracoPrimitiveRequest> reused_index = {
      Request(0, 0, 17, 1), Request(0, 1, 17, 1)};
  auto reused_index_result =
      FsvDracoPreflightRequests(reused_index, Budget(36, 2, 1, 3, 36), empty);
  CHECK(reused_index_result.ok);
  CHECK(reused_index_result.accessors == 2);
  CHECK(reused_index_result.vertices == 1);
  CHECK(reused_index_result.indices == 3);
  CHECK(reused_index_result.native_output_bytes == 36);

  const int64_t above_int32 = INT64_C(2147483648);
  const std::vector<FsvDracoPrimitiveRequest> large = {
      Request(0, 0, 50, above_int32, false)};
  auto large_result = FsvDracoPreflightRequests(
      large,
      Budget(above_int32 * 12, 1, above_int32, 0, above_int32 * 12),
      empty);
  CHECK(large_result.ok);
  CHECK(large_result.vertices == static_cast<uint64_t>(above_int32));

  const std::vector<FsvDracoPrimitiveRequest> product_overflow = {
      Request(0, 0, 80, kFsvDracoMaxSafeInteger, false)};
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
      FsvDracoPreflightRequests({invalid_attribute_id},
                                Budget(30, 2, 2, 3, 30), empty),
      "dracoAttributeId", "invalidMetadata"));

  for (const int64_t legal : {INT64_C(5120), INT64_C(5121), INT64_C(5122),
                              INT64_C(5123), INT64_C(5125), INT64_C(5126)}) {
    FsvDracoPrimitiveRequest legal_component = Request(0, 0, 0, 1, false);
    legal_component.attribute_accessors["POSITION"].component_type =
        FsvDracoBudgetNumber::Integer(legal);
    legal_component.attribute_accessors["POSITION"].type = "SCALAR";
    CHECK(FsvDracoPreflightRequests(
              {legal_component}, Budget(4, 1, 1, 0, 4), empty)
              .ok);
  }
  for (const int64_t legal : {INT64_C(5121), INT64_C(5123), INT64_C(5125)}) {
    FsvDracoPrimitiveRequest legal_index = Request(0, 0, 0, 1);
    legal_index.indices_accessor.component_type =
        FsvDracoBudgetNumber::Integer(legal);
    CHECK(FsvDracoPreflightRequests(
              {legal_index}, Budget(24, 2, 1, 3, 24), empty)
              .ok);
  }
  FsvDracoPrimitiveRequest missing_component = Request(0, 0, 0, 1, false);
  missing_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber();
  CHECK(FailureField(
      FsvDracoPreflightRequests({missing_component}, Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest wrong_component_type = Request(0, 0, 0, 1, false);
  wrong_component_type.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Invalid();
  CHECK(FailureField(
      FsvDracoPreflightRequests({wrong_component_type},
                                Budget(12, 1, 1, 0, 12), empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest negative_component = Request(0, 0, 0, 1, false);
  negative_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(-1);
  CHECK(FailureField(
      FsvDracoPreflightRequests({negative_component},
                                Budget(12, 1, 1, 0, 12), empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest alias_component = Request(0, 0, 0, 1, false);
  alias_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(INT64_C(5126) + (INT64_C(1) << 32));
  CHECK(FailureField(
      FsvDracoPreflightRequests({alias_component}, Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));
  FsvDracoPrimitiveRequest unsafe_component = Request(0, 0, 0, 1, false);
  unsafe_component.attribute_accessors["POSITION"].component_type =
      FsvDracoBudgetNumber::Integer(kFsvDracoMaxSafeInteger + 1);
  CHECK(FailureField(
      FsvDracoPreflightRequests({unsafe_component}, Budget(12, 1, 1, 0, 12),
                                empty),
      "accessor.componentType", "invalidMetadata"));

  FsvDracoPrimitiveRequest missing_id_request = Request(0, 0, 0, 1, false);
  missing_id_request.attributes["NORMAL"] = 9;
  FsvDracoAccessorSchema normal =
      missing_id_request.attribute_accessors["POSITION"];
  normal.accessor_index = 1;
  missing_id_request.attribute_accessors["NORMAL"] = normal;
  FsvDracoDecodedMeshMetadata decoded_mesh;
  decoded_mesh.point_count = 1;
  decoded_mesh.face_count = 0;
  decoded_mesh.attribute_unique_ids.insert(7);
  size_t output_vector_allocations = 0;
  size_t decoded_primitive_count = 0;
  const FsvDracoPostDecodeValidationResult post_decode =
      FsvDracoValidateDecodedSchemas({missing_id_request}, {decoded_mesh});
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
  FsvDracoAccessorSchema normal = position;
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
      FsvDracoDecodePrimitives({request}, budget, state, &counters);
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
#include <utility>
#include "draco/core/decoder_buffer.h"
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
  FakeStatusOr<std::unique_ptr<Mesh>> DecodeMeshFromBuffer(DecoderBuffer*) {
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
};
''';
