import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _basisuPngSha256 =
    'e4df96db13158a2722ad9aad3ec8dd84dcfb9bc248b0c6721261b4777e41366b';

void main() {
  test('Khronos CTS sources and derived UASTC-RG fixture are pinned', () async {
    const fixtureRoot = 'test/fixtures/ktx2-cts';
    for (final path in const <String>[
      'LICENSE',
      'create/encode_blze/output_R8G8B8A8_UNORM.ktx2',
      'create/encode_blze/output_R8G8B8_UNORM.ktx2',
      'create/encode_blze/output_R8G8_UNORM.ktx2',
      'create/encode_blze/output_R8_UNORM.ktx2',
      'create/encode_uastc/output_R8G8B8A8_UNORM.ktx2',
      'create/encode_uastc/output_R8G8B8_UNORM.ktx2',
      'create/encode_uastc/output_R8G8_UNORM.ktx2',
      'create/encode_uastc/output_R8_UNORM.ktx2',
      'input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2',
      'derived/khr_texture_basisu_uastc_rg.ktx2',
      'deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
      'create/compare/'
          'output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2',
      'create/compare/'
          'output_uastc_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2',
      'validate/3101/'
          'error_InvalidSupercompressionGLTFBU_UASTC_ZLIB.ktx2',
      'validate/3103/'
          'error_InvalidPixelWidthHeightGLTFBU_bothUnaligned.ktx2',
      'validate/6301/error_IncorrectModelGLTFBU_ASTC.ktx2',
      'validate/6303/error_InvalidChannelGLTFBU_ETC1S_GGG.ktx2',
      'validate/6303/error_InvalidChannelGLTFBU_UASTC_RRRG.ktx2',
      'validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_ADOBERGB.ktx2',
      'validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_BT709_LINEAR.ktx2',
      'validate/7201/error_KTXswizzleInvalidGLTFBU_ETC1S_bgra.ktx2',
      'validate/7202/error_KTXorientationInvalidGLTFBU_ETC1S_lu.ktx2',
    ]) {
      expect(
        await File('$fixtureRoot/$path').exists(),
        isTrue,
        reason: 'Missing pinned Khronos KTX-Software-CTS fixture: $path',
      );
    }
    final derivation = await Process.run(
      'python3',
      <String>[
        '../../tools/derive_basisu_uastc_rg_fixture.py',
        '--check',
        '--source',
        '$fixtureRoot/input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2',
        '--output',
        '$fixtureRoot/derived/khr_texture_basisu_uastc_rg.ktx2',
      ],
    );
    expect(
      derivation.exitCode,
      0,
      reason: '${derivation.stdout}\n${derivation.stderr}',
    );
  });

  test('real bridge matches pinned transcoder for BasisU codec corpus',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    const fixtureRoot = 'test/fixtures/ktx2-cts';
    final fixtures = <String>[
      '$fixtureRoot/create/encode_blze/output_R8G8B8A8_UNORM.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8G8B8_UNORM.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8G8_UNORM.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8G8B8A8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8G8B8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8G8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8_UNORM.ktx2',
      '$fixtureRoot/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
      '$fixtureRoot/derived/khr_texture_basisu_uastc_rg.ktx2',
    ];
    for (final fixture in fixtures) {
      expect(await File(fixture).exists(), isTrue, reason: fixture);
    }

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_conformance_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/basisu_conformance_runner.cc');
    await runner.writeAsString(_basisuConformanceRunner);
    final binary = '${tempDir.path}/basisu_conformance_runner';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      runner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      binary,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(binary, fixtures);
    expect(
      run.exitCode,
      0,
      reason: '${run.stdout}\n${run.stderr}',
    );
    expect('${run.stdout}', contains('basisu-conformance-ok cases=10'));
  });

  test('native bridge enforces the KHR_texture_basisu KTX2 profile', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    const fixtureRoot = 'test/fixtures/ktx2-cts';
    final fixtures = <String>[
      '$fixtureRoot/validate/3101/'
          'error_InvalidSupercompressionGLTFBU_UASTC_ZLIB.ktx2',
      '$fixtureRoot/validate/3103/'
          'error_InvalidPixelWidthHeightGLTFBU_bothUnaligned.ktx2',
      '$fixtureRoot/validate/6301/error_IncorrectModelGLTFBU_ASTC.ktx2',
      '$fixtureRoot/validate/6303/'
          'error_InvalidChannelGLTFBU_ETC1S_GGG.ktx2',
      '$fixtureRoot/validate/6303/'
          'error_InvalidChannelGLTFBU_UASTC_RRRG.ktx2',
      '$fixtureRoot/validate/6304/'
          'error_InvalidColorSpaceGLTFBU_ETC1S_ADOBERGB.ktx2',
      '$fixtureRoot/validate/6304/'
          'error_InvalidColorSpaceGLTFBU_ETC1S_BT709_LINEAR.ktx2',
      '$fixtureRoot/validate/7201/'
          'error_KTXswizzleInvalidGLTFBU_ETC1S_bgra.ktx2',
      '$fixtureRoot/validate/7202/'
          'error_KTXorientationInvalidGLTFBU_ETC1S_lu.ktx2',
      '$fixtureRoot/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8_UNORM.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8G8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8_UNORM.ktx2',
      '$fixtureRoot/create/encode_blze/output_R8G8B8_UNORM.ktx2',
      '$fixtureRoot/derived/khr_texture_basisu_uastc_rg.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8G8B8_UNORM.ktx2',
      '$fixtureRoot/create/encode_uastc/output_R8G8_UNORM.ktx2',
    ];
    for (final fixture in fixtures) {
      expect(await File(fixture).exists(), isTrue, reason: fixture);
    }

    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_profile_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/basisu_profile_runner.cc');
    await runner.writeAsString(_basisuProfileDiagnosticRunner);
    final binary = '${tempDir.path}/basisu_profile_runner';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      runner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      binary,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(binary, fixtures);
    expect(
      run.exitCode,
      0,
      reason: '${run.stdout}\n${run.stderr}',
    );
    expect(
      '${run.stdout}',
      contains(
        'basisu-profile-diagnostic-ok negatives=14 positives=3 malformed=7 '
        'usagePositive=2 usageNegative=3 layoutPositive=7 layoutNegative=7',
      ),
    );
  });

  test('native bridge rejects authored mip pyramids before transcode',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    const fixtureRoot = 'test/fixtures/ktx2-cts/create/compare';
    final fixtures = <String>[
      '$fixtureRoot/output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2',
      '$fixtureRoot/output_uastc_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2',
    ];
    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_mips_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/basisu_mip_runner.cc');
    await runner.writeAsString(_basisuMipDiagnosticRunner);
    final binary = '${tempDir.path}/basisu_mip_runner';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      runner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      binary,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
    final run = await Process.run(binary, fixtures);
    expect(
      run.exitCode,
      0,
      reason: '${run.stdout}\n${run.stderr}',
    );
    expect('${run.stdout}', contains('basisu-mip-diagnostic-ok cases=2'));
  });

  test('pure native preflight enforces exact and aggregate budgets', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_budget_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/basisu_budget_runner.cc');
    await runner.writeAsString(_basisuBudgetRunner);
    for (final platform in const <String>[
      'android/src/main/cpp',
      'ios/Classes',
    ]) {
      final binary =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}_basisu_budget_runner';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I$platform',
        runner.path,
        '$platform/fsv_basisu_budget.cc',
        '-o',
        binary,
      ]);
      expect(
        compile.exitCode,
        0,
        reason: '$platform\n${compile.stdout}\n${compile.stderr}',
      );
      final run = await Process.run(binary, const <String>[]);
      expect(
        run.exitCode,
        0,
        reason: '$platform\n${run.stdout}\n${run.stderr}',
      );
      expect('${run.stdout}', contains('basisu-budget-ok'));
    }
  });

  test('Android and iOS budget and bridge sources remain byte-identical',
      () async {
    for (final pair in const <(String, String)>[
      (
        'android/src/main/cpp/fsv_basisu_budget.h',
        'ios/Classes/fsv_basisu_budget.h',
      ),
      (
        'android/src/main/cpp/fsv_basisu_budget.cc',
        'ios/Classes/fsv_basisu_budget.cc',
      ),
      (
        'android/src/main/cpp/fsv_basisu_bridge.h',
        'ios/Classes/fsv_basisu_bridge.h',
      ),
      (
        'android/src/main/cpp/fsv_basisu_bridge.cc',
        'ios/Classes/fsv_basisu_bridge.cc',
      ),
    ]) {
      expect(
        await File(pair.$1).readAsBytes(),
        await File(pair.$2).readAsBytes(),
        reason: '${pair.$1} must match ${pair.$2}',
      );
    }
  });

  test('Android bridge defines BasisU transcode symbol', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_bridge_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final objectPath = '${tempDir.path}/fsv_basisu_bridge_android.o';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      '-c',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
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
      contains('FsvBasisuTranscodeImages'),
    );
  });

  test('native bridge writes official KTX2 fixture PNG bytes', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_run_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('test/native/basisu_output_runner.cc');
    expect(
      runner.existsSync(),
      isTrue,
      reason: 'The package and root validator must share one tracked runner.',
    );
    final binary = '${tempDir.path}/basisu_runner';

    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      runner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      binary,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );

    final run = await Process.run(
      binary,
      <String>[
        'test/fixtures/ktx2-cts/deflate/metadata/'
            'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
        '${tempDir.path}/basisu.png',
      ],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('png=1108 width=16 height=16'));
    expect(
      await File('${tempDir.path}/basisu.png').length(),
      1108,
    );
    final pngHash = await Process.run(
      'shasum',
      <String>['-a', '256', '${tempDir.path}/basisu.png'],
    );
    expect(
      pngHash.exitCode,
      0,
      reason: '${pngHash.stdout}\n${pngHash.stderr}',
    );
    expect(
      (pngHash.stdout as String).split(RegExp(r'\s+')).first,
      _basisuPngSha256,
    );
  });

  test('iOS vendor source aggregator compiles BasisU implementation', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_ios_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final objectPath = '${tempDir.path}/fsv_basisu_vendor_sources.o';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-c',
      'ios/Classes/fsv_basisu_vendor_sources.cc',
      '-o',
      objectPath,
    ]);
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );
  });

  test('Android JNI defines BasisU MethodChannel bridge', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_jni_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);

    final objectPath = '${tempDir.path}/flutter_scene_viewer_basisu_jni.o';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-c',
      'android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
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
        'Java_com_marlonjd_flutter_1scene_1viewer_1basisu_'
        'FlutterSceneViewerBasisuPlugin_nativeTranscodeImages',
      ),
    );
  });

  test('platform adapters preserve presence-aware 64-bit budget values',
      () async {
    final java = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/FlutterSceneViewerBasisuPlugin.java',
    ).readAsString();
    final jni = await File(
      'android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
    ).readAsString();
    final ios = await File(
      'ios/Classes/FlutterSceneViewerBasisuPlugin.mm',
    ).readAsString();
    expect(java, contains('Object decodeBudgetState'));
    expect(java, contains('call.argument("decodeBudget")'));
    expect(jni, contains('"java/lang/Integer"'));
    expect(jni, contains('"java/lang/Long"'));
    expect(jni, contains('"longValue", "()J"'));
    expect(jni, contains('FsvBasisuBudgetNumber::Invalid()'));
    final requestParser = jni.indexOf('RequestsFromJavaList(');
    final itemMapCheck =
        jni.indexOf('env->IsInstanceOf(image, map_class)', requestParser);
    final firstItemMapGet = jni.indexOf('MapGet(env, image', requestParser);
    final byteArrayCheck = jni.indexOf('env->FindClass("[B")');
    final byteArrayLength = jni.indexOf('env->GetArrayLength(');
    expect(itemMapCheck, greaterThanOrEqualTo(0));
    expect(firstItemMapGet, greaterThan(itemMapCheck));
    expect(byteArrayCheck, greaterThanOrEqualTo(0));
    expect(byteArrayLength, greaterThan(byteArrayCheck));
    expect(ios, contains('CFBooleanGetTypeID()'));
    expect(ios, contains('CFNumberIsFloatType'));
    expect(ios, contains('[value longLongValue]'));
    expect(ios, contains('DecodeBudgetState(call.arguments)'));
    expect(ios, contains('request.metadata_valid = false'));
    expect(jni, contains('request.metadata_valid = false'));
    expect(jni, contains('MapGet(env, image, "usageRole")'));
    expect(jni, contains('StringFromValue(env, usage_role)'));
    expect(jni, contains('FsvBasisuUsageRoleFromString('));
    expect(jni, contains('basisuImages.usageRole'));
    expect(jni, contains('MapGet(env, image, "channelLayout")'));
    expect(jni, contains('FsvBasisuChannelLayoutFromString('));
    expect(jni, contains('basisuImages.channelLayout'));
    expect(ios, contains('image[@"usageRole"]'));
    expect(ios, contains('[usageRole isKindOfClass:[NSString class]]'));
    expect(ios, contains('FsvBasisuUsageRoleFromString('));
    expect(ios, contains('basisuImages.usageRole'));
    expect(ios, contains('image[@"channelLayout"]'));
    expect(ios, contains('[channelLayout isKindOfClass:[NSString class]]'));
    expect(ios, contains('FsvBasisuChannelLayoutFromString('));
    expect(ios, contains('basisuImages.channelLayout'));

    final bridge = await File(
      'android/src/main/cpp/fsv_basisu_bridge.cc',
    ).readAsString();
    final preflight = bridge.indexOf('FsvBasisuPreflightRequests(');
    final profilePreflight = bridge.indexOf(
      'ValidateKhrTextureBasisuProfile(',
      preflight,
    );
    final usagePreflight = bridge.indexOf(
      'ValidateKhrTextureBasisuUsage(',
      profilePreflight,
    );
    final layoutPreflight = bridge.indexOf(
      'ValidateKhrTextureBasisuChannelLayout(',
      profilePreflight,
    );
    final outputReserve = bridge.indexOf('result.decoded_images.reserve(');
    final nativeInit = bridge.indexOf('transcoder.init(');
    final startTranscoding = bridge.indexOf('transcoder.start_transcoding()');
    final pixelAllocation = bridge.indexOf('std::vector<uint32_t> pixels(');
    expect(preflight, greaterThanOrEqualTo(0));
    expect(profilePreflight, greaterThan(preflight));
    expect(layoutPreflight, greaterThan(profilePreflight));
    expect(usagePreflight, greaterThan(layoutPreflight));
    expect(outputReserve, greaterThan(usagePreflight));
    expect(nativeInit, greaterThan(usagePreflight));
    expect(startTranscoding, greaterThan(nativeInit));
    expect(pixelAllocation, greaterThan(startTranscoding));
    expect(bridge, isNot(contains('8192ULL')));
  });
}

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
  jmethodID GetStaticMethodID(jclass, const char*, const char*);
  jboolean IsInstanceOf(jobject, jclass);
  jobject NewObject(jclass, jmethodID, ...);
  jstring NewStringUTF(const char*);
  jobject CallObjectMethod(jobject, jmethodID, ...);
  jobject CallStaticObjectMethod(jclass, jmethodID, ...);
  jint CallIntMethod(jobject, jmethodID, ...);
  jlong CallLongMethod(jobject, jmethodID, ...);
  jboolean CallBooleanMethod(jobject, jmethodID, ...);
  jsize GetArrayLength(jarray);
  void GetByteArrayRegion(jbyteArray, jsize, jsize, jbyte*);
  jbyteArray NewByteArray(jsize);
  void SetByteArrayRegion(jbyteArray, jsize, jsize, const jbyte*);
  const char* GetStringUTFChars(jstring, jboolean*);
  void ReleaseStringUTFChars(jstring, const char*);
  void DeleteLocalRef(jobject);
};
''';

const String _basisuBudgetRunner = r'''
#include <cstdint>
#include <iostream>
#include <vector>

#include "fsv_basisu_budget.h"

void SetLe32(std::vector<uint8_t>* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value & 0xff);
  (*bytes)[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  (*bytes)[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xff);
  (*bytes)[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

void SetLe64(std::vector<uint8_t>* bytes, size_t offset, uint64_t value) {
  SetLe32(bytes, offset, static_cast<uint32_t>(value & 0xffffffffU));
  SetLe32(bytes, offset + 4, static_cast<uint32_t>(value >> 32));
}

FsvBasisuImageRequest Request(uint32_t width, uint32_t height, int image = 0) {
  FsvBasisuImageRequest request;
  request.texture_index = image;
  request.image_index = image;
  request.mime_type = "image/ktx2";
  request.bytes.assign(105, 0);
  const uint8_t identifier[] = {
      0xab, 0x4b, 0x54, 0x58, 0x20, 0x32,
      0x30, 0xbb, 0x0d, 0x0a, 0x1a, 0x0a};
  for (size_t index = 0; index < sizeof(identifier); index += 1) {
    request.bytes[index] = identifier[index];
  }
  SetLe32(&request.bytes, 20, width);
  SetLe32(&request.bytes, 24, height);
  SetLe32(&request.bytes, 28, 0);
  SetLe32(&request.bytes, 32, 0);
  SetLe32(&request.bytes, 36, 1);
  SetLe32(&request.bytes, 40, 1);
  SetLe64(&request.bytes, 80, 104);
  SetLe64(&request.bytes, 88, 1);
  SetLe64(&request.bytes, 96, 1);
  request.bytes[104] = 0;
  return request;
}

FsvBasisuDecodeBudgetMetadata Budget(int64_t total, int64_t pixels,
                                    int64_t native) {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(total);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(pixels);
  budget.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(native);
  return budget;
}

FsvBasisuDecodeBudgetState State(int64_t total = 0, int64_t pixels = 0,
                                int64_t native = 0) {
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(total);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(pixels);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(native);
  return state;
}

bool Fails(const FsvBasisuPreflightResult& result, const char* status,
           const char* field) {
  return !result.ok && result.layouts.empty() &&
         result.diagnostics.size() == 1 &&
         result.diagnostics[0].status == status &&
         result.diagnostics[0].field == field;
}

int main() {
  const FsvBasisuImageRequest request = Request(2, 3);
  const auto exact = FsvBasisuPreflightRequests(
      {request}, Budget(95, 6, 95), State());
  if (!exact.ok || exact.layouts.size() != 1 ||
      exact.layouts[0].pixel_count != 6 ||
      exact.layouts[0].rgba_bytes != 24 ||
      exact.layouts[0].raw_scanline_bytes != 27 ||
      exact.layouts[0].zlib_bytes != 38 ||
      exact.layouts[0].png_bytes != 95) {
    return 1;
  }
  if (!Fails(FsvBasisuPreflightRequests({request}, Budget(95, 5, 95), State()),
             "budgetExceeded", "texturePixels") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(95, 6, 94), State()),
             "budgetExceeded", "nativeOutputBytes") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(94, 6, 95), State()),
             "budgetExceeded", "totalDecodedBytes") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(190, 6, 190),
                                        State(0, 1, 0)),
             "budgetExceeded", "texturePixels")) {
    return 2;
  }
  const auto aggregate = FsvBasisuPreflightRequests(
      {request, Request(2, 3, 1)}, Budget(190, 12, 190), State());
  if (!aggregate.ok || aggregate.layouts.size() != 2 ||
      aggregate.native_output_bytes != 190 ||
      !Fails(FsvBasisuPreflightRequests(
                 {request, Request(2, 3, 1)}, Budget(190, 12, 189), State()),
             "budgetExceeded", "nativeOutputBytes")) {
    return 3;
  }
  FsvBasisuDecodeBudgetMetadata missing = Budget(95, 6, 95);
  missing.max_texture_pixels = FsvBasisuBudgetNumber();
  if (!Fails(FsvBasisuPreflightRequests({request}, missing, State()),
             "invalidMetadata", "maxTexturePixels")) {
    return 4;
  }
  FsvBasisuDecodeBudgetMetadata invalid = Budget(95, 6, 95);
  invalid.max_texture_pixels = FsvBasisuBudgetNumber::Invalid();
  if (!Fails(FsvBasisuPreflightRequests({request}, invalid, State()),
             "invalidMetadata", "maxTexturePixels") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(95, -1, 95), State()),
             "invalidMetadata", "maxTexturePixels") ||
      !Fails(FsvBasisuPreflightRequests(
                 {request}, Budget(95, kFsvBasisuMaxSafeInteger + 1, 95),
                 State()),
             "invalidMetadata", "maxTexturePixels")) {
    return 5;
  }
  auto invalid_item = request;
  invalid_item.metadata_valid = false;
  invalid_item.metadata_field = "basisuImages";
  auto invalid_bytes = request;
  invalid_bytes.metadata_valid = false;
  invalid_bytes.metadata_field = "basisuImages.bytes";
  auto invalid_role = request;
  invalid_role.metadata_valid = false;
  invalid_role.metadata_field = "basisuImages.usageRole";
  auto invalid_layout = request;
  invalid_layout.metadata_valid = false;
  invalid_layout.metadata_field = "basisuImages.channelLayout";
  if (!Fails(FsvBasisuPreflightRequests({invalid_item}, Budget(95, 6, 95), State()),
             "invalidMetadata", "basisuImages") ||
      !Fails(FsvBasisuPreflightRequests({invalid_bytes}, Budget(95, 6, 95), State()),
             "invalidMetadata", "basisuImages.bytes") ||
      !Fails(FsvBasisuPreflightRequests({invalid_role}, Budget(95, 6, 95), State()),
             "invalidMetadata", "basisuImages.usageRole") ||
      !Fails(FsvBasisuPreflightRequests({invalid_layout}, Budget(95, 6, 95), State()),
             "invalidMetadata", "basisuImages.channelLayout")) {
    return 51;
  }
  FsvBasisuUsageRole parsed_role;
  if (!FsvBasisuUsageRoleFromString("color", &parsed_role) ||
      parsed_role != FsvBasisuUsageRole::kColor ||
      !FsvBasisuUsageRoleFromString("nonColor", &parsed_role) ||
      parsed_role != FsvBasisuUsageRole::kNonColor ||
      !FsvBasisuUsageRoleFromString("structuralOnly", &parsed_role) ||
      parsed_role != FsvBasisuUsageRole::kStructuralOnly ||
      !FsvBasisuUsageRoleFromString("ambiguous", &parsed_role) ||
      parsed_role != FsvBasisuUsageRole::kAmbiguous ||
      FsvBasisuUsageRoleFromString("", &parsed_role) ||
      FsvBasisuUsageRoleFromString("COLOR", &parsed_role) ||
      FsvBasisuUsageRoleFromString("unknown", &parsed_role)) {
    return 52;
  }
  FsvBasisuChannelLayout parsed_layout;
  if (!FsvBasisuChannelLayoutFromString("r", &parsed_layout) ||
      parsed_layout != FsvBasisuChannelLayout::kR ||
      !FsvBasisuChannelLayoutFromString("rg", &parsed_layout) ||
      parsed_layout != FsvBasisuChannelLayout::kRg ||
      !FsvBasisuChannelLayoutFromString("rgb", &parsed_layout) ||
      parsed_layout != FsvBasisuChannelLayout::kRgb ||
      !FsvBasisuChannelLayoutFromString("rgba", &parsed_layout) ||
      parsed_layout != FsvBasisuChannelLayout::kRgba ||
      !FsvBasisuChannelLayoutFromString("structuralOnly", &parsed_layout) ||
      parsed_layout != FsvBasisuChannelLayout::kStructuralOnly ||
      FsvBasisuChannelLayoutFromString("", &parsed_layout) ||
      FsvBasisuChannelLayoutFromString("RGB", &parsed_layout) ||
      FsvBasisuChannelLayoutFromString("ambiguous", &parsed_layout)) {
    return 53;
  }
  auto malformed = request;
  malformed.bytes[0] = 0;
  if (!Fails(FsvBasisuPreflightRequests({malformed}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Identifier")) {
    return 6;
  }
  auto layout = request;
  SetLe32(&layout.bytes, 28, 1);
  if (!Fails(FsvBasisuPreflightRequests({layout}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Layout")) {
    return 7;
  }
  layout = request;
  SetLe32(&layout.bytes, 32, 1);
  if (!Fails(FsvBasisuPreflightRequests({layout}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Layout")) {
    return 71;
  }
  layout = request;
  SetLe32(&layout.bytes, 36, 6);
  if (!Fails(FsvBasisuPreflightRequests({layout}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Layout") ||
      !Fails(FsvBasisuPreflightRequests({Request(0, 3)}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Layout")) {
    return 72;
  }
  auto short_header = request;
  short_header.bytes.resize(40);
  auto short_fixed_header = request;
  short_fixed_header.bytes.resize(79);
  auto short_level_index = request;
  short_level_index.bytes.resize(103);
  auto truncated_mip_index = request;
  SetLe32(&truncated_mip_index.bytes, 40, 2);
  if (!Fails(FsvBasisuPreflightRequests({short_header}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Header") ||
      !Fails(FsvBasisuPreflightRequests({short_fixed_header}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2Header") ||
      !Fails(FsvBasisuPreflightRequests({short_level_index}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2LevelIndex") ||
      !Fails(FsvBasisuPreflightRequests({truncated_mip_index}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2LevelIndex")) {
    return 8;
  }
  auto wrong_mime = request;
  wrong_mime.mime_type = "";
  if (!Fails(FsvBasisuPreflightRequests({wrong_mime}, Budget(95, 6, 95), State()),
             "invalidMetadata", "mimeType")) {
    return 9;
  }
  const auto overflow = FsvBasisuPreflightRequests(
      {Request(0xffffffffU, 0xffffffffU)},
      Budget(kFsvBasisuMaxSafeInteger, kFsvBasisuMaxSafeInteger,
             kFsvBasisuMaxSafeInteger),
      State());
  if (!Fails(overflow, "invalidMetadata", "texturePixels")) {
    return 10;
  }
  std::cout << "basisu-budget-ok\n";
  return 0;
}
''';

const String _basisuConformanceRunner = r'''
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

#include "basisu_transcoder.h"
#include "fsv_basisu_bridge.h"

struct ExpectedCase {
  bool etc1s;
  uint32_t supercompression;
  uint32_t samples;
  basist::ktx2_df_channel_id channel0;
  basist::ktx2_df_channel_id channel1;
};

uint32_t ReadBe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return (static_cast<uint32_t>(bytes[offset]) << 24) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 8) |
         static_cast<uint32_t>(bytes[offset + 3]);
}

uint32_t ReadLe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

void SetLe32(std::vector<uint8_t>* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value & 0xff);
  (*bytes)[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  (*bytes)[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xff);
  (*bytes)[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

std::vector<uint8_t> DecodeStoredPng(const std::vector<uint8_t>& png,
                                     uint32_t width, uint32_t height) {
  const uint8_t signature[] = {
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
  if (png.size() < sizeof(signature) ||
      std::memcmp(png.data(), signature, sizeof(signature)) != 0) {
    return {};
  }
  std::vector<uint8_t> zlib;
  size_t offset = sizeof(signature);
  while (offset + 12 <= png.size()) {
    const uint32_t length = ReadBe32(png, offset);
    if (offset + 12ULL + length > png.size()) {
      return {};
    }
    const char* type = reinterpret_cast<const char*>(png.data() + offset + 4);
    if (std::memcmp(type, "IDAT", 4) == 0) {
      zlib.insert(zlib.end(), png.begin() + static_cast<ptrdiff_t>(offset + 8),
                  png.begin() + static_cast<ptrdiff_t>(offset + 8 + length));
    }
    offset += 12ULL + length;
  }
  if (zlib.size() < 11 || zlib[0] != 0x78 || zlib[1] != 0x01) {
    return {};
  }

  std::vector<uint8_t> raw;
  offset = 2;
  bool final_block = false;
  while (!final_block) {
    if (offset + 5 > zlib.size() - 4) {
      return {};
    }
    const uint8_t header = zlib[offset++];
    final_block = (header & 1U) != 0;
    if ((header & 0x06U) != 0) {
      return {};
    }
    const uint16_t length = static_cast<uint16_t>(zlib[offset]) |
                            (static_cast<uint16_t>(zlib[offset + 1]) << 8);
    const uint16_t inverse = static_cast<uint16_t>(zlib[offset + 2]) |
                             (static_cast<uint16_t>(zlib[offset + 3]) << 8);
    offset += 4;
    if (static_cast<uint16_t>(~length) != inverse ||
        offset + length > zlib.size() - 4) {
      return {};
    }
    raw.insert(raw.end(), zlib.begin() + static_cast<ptrdiff_t>(offset),
               zlib.begin() + static_cast<ptrdiff_t>(offset + length));
    offset += length;
  }

  const size_t row_bytes = static_cast<size_t>(width) * 4U;
  if (raw.size() != (row_bytes + 1U) * height) {
    return {};
  }
  std::vector<uint8_t> rgba;
  rgba.reserve(row_bytes * height);
  for (uint32_t row = 0; row < height; row += 1) {
    const size_t row_offset = static_cast<size_t>(row) * (row_bytes + 1U);
    if (raw[row_offset] != 0) {
      return {};
    }
    rgba.insert(rgba.end(),
                raw.begin() + static_cast<ptrdiff_t>(row_offset + 1U),
                raw.begin() + static_cast<ptrdiff_t>(row_offset + 1U + row_bytes));
  }
  return rgba;
}

int main(int argc, char** argv) {
  if (argc != 11) {
    return 64;
  }
  const ExpectedCase expected[] = {
      {true, basist::KTX2_SS_BASISLZ, 2,
       basist::KTX2_DF_CHANNEL_ETC1S_RGB,
       basist::KTX2_DF_CHANNEL_ETC1S_AAA},
      {true, basist::KTX2_SS_BASISLZ, 1,
       basist::KTX2_DF_CHANNEL_ETC1S_RGB,
       basist::KTX2_DF_CHANNEL_ETC1S_RGB},
      {true, basist::KTX2_SS_BASISLZ, 2,
       basist::KTX2_DF_CHANNEL_ETC1S_RRR,
       basist::KTX2_DF_CHANNEL_ETC1S_GGG},
      {true, basist::KTX2_SS_BASISLZ, 1,
       basist::KTX2_DF_CHANNEL_ETC1S_RRR,
       basist::KTX2_DF_CHANNEL_ETC1S_RRR},
      {false, basist::KTX2_SS_NONE, 1,
       basist::KTX2_DF_CHANNEL_UASTC_RGBA,
       basist::KTX2_DF_CHANNEL_UASTC_RGBA},
      {false, basist::KTX2_SS_NONE, 1,
       basist::KTX2_DF_CHANNEL_UASTC_RGB,
       basist::KTX2_DF_CHANNEL_UASTC_RGB},
      {false, basist::KTX2_SS_NONE, 1,
       // The official source-layout RG fixture uses generic UASTC DATA(0),
       // not the KHR_texture_basisu-required UASTC_RG(6) channel ID.
       basist::KTX2_DF_CHANNEL_UASTC_DATA,
       basist::KTX2_DF_CHANNEL_UASTC_DATA},
      {false, basist::KTX2_SS_NONE, 1,
       basist::KTX2_DF_CHANNEL_UASTC_RRR,
       basist::KTX2_DF_CHANNEL_UASTC_RRR},
      {false, basist::KTX2_SS_ZSTANDARD, 1,
       basist::KTX2_DF_CHANNEL_UASTC_RGBA,
       basist::KTX2_DF_CHANNEL_UASTC_RGBA},
      {false, basist::KTX2_SS_NONE, 1,
       basist::KTX2_DF_CHANNEL_UASTC_RG,
       basist::KTX2_DF_CHANNEL_UASTC_RG},
  };

  basist::basisu_transcoder_init();
  for (int case_index = 0; case_index < 10; case_index += 1) {
    std::ifstream input(argv[case_index + 1], std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    if (bytes.empty()) {
      return 65;
    }

    // The generic CTS encode corpus exercises codec/channel shapes rather
    // than the glTF profile. Its UNORM outputs use BT709+LINEAR, which
    // KHR_texture_basisu forbids. Normalize only this in-memory test copy to
    // the allowed UNSPECIFIED+LINEAR pair before comparing decoded pixels.
    const uint32_t dfd_offset = ReadLe32(bytes, 48);
    uint32_t dfd_bits = ReadLe32(bytes, dfd_offset + 12);
    const uint32_t primaries = (dfd_bits >> 8) & 0xffU;
    const uint32_t transfer = (dfd_bits >> 16) & 0xffU;
    if (primaries == basist::KTX2_DF_PRIMARIES_BT709 &&
        transfer == basist::KTX2_KHR_DF_TRANSFER_LINEAR) {
      dfd_bits &= ~0xff00U;
      SetLe32(&bytes, dfd_offset + 12, dfd_bits);
    }

    basist::ktx2_transcoder direct;
    if (!direct.init(bytes.data(), static_cast<uint32_t>(bytes.size()))) {
      return 66;
    }
    const ExpectedCase& expectation = expected[case_index];
    const uint64_t supercompression =
        direct.get_header().m_supercompression_scheme.get_uint64();
    if (direct.get_levels() != 1 || direct.get_faces() != 1 ||
        direct.get_layers() != 0 || direct.is_etc1s() != expectation.etc1s ||
        direct.is_uastc() != !expectation.etc1s ||
        supercompression != expectation.supercompression ||
        direct.get_dfd_total_samples() != expectation.samples ||
        direct.get_dfd_channel_id0() != expectation.channel0 ||
        (expectation.samples == 2 &&
         direct.get_dfd_channel_id1() != expectation.channel1)) {
      std::cerr << "metadata mismatch case=" << case_index
                << " etc1s=" << direct.is_etc1s()
                << " uastc=" << direct.is_uastc()
                << " supercompression=" << supercompression
                << " samples=" << direct.get_dfd_total_samples()
                << " channel0=" << direct.get_dfd_channel_id0()
                << " channel1=" << direct.get_dfd_channel_id1() << "\n";
      for (const auto& key_value : direct.get_key_values()) {
        std::cerr << reinterpret_cast<const char*>(key_value.m_key.data())
                  << "="
                  << reinterpret_cast<const char*>(key_value.m_value.data())
                  << "\n";
      }
      return 67;
    }
    if (!direct.start_transcoding()) {
      return 68;
    }
    basist::ktx2_image_level_info level;
    if (!direct.get_image_level_info(level, 0, 0, 0)) {
      return 69;
    }
    std::vector<uint32_t> direct_pixels(
        static_cast<size_t>(level.m_orig_width) * level.m_orig_height);
    if (!direct.transcode_image_level(
            0, 0, 0, direct_pixels.data(),
            static_cast<uint32_t>(direct_pixels.size()),
            basist::transcoder_texture_format::cTFRGBA32)) {
      return 70;
    }

    FsvBasisuImageRequest request;
    request.texture_index = case_index;
    request.image_index = case_index;
    request.mime_type = "image/ktx2";
    request.bytes = bytes;
    FsvBasisuDecodeBudgetMetadata budget;
    budget.max_total_decoded_bytes =
        FsvBasisuBudgetNumber::Integer(10000000);
    budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(1000000);
    budget.max_native_output_bytes =
        FsvBasisuBudgetNumber::Integer(10000000);
    FsvBasisuDecodeBudgetState state;
    state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
    state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
    state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
    const FsvBasisuTranscodeResult bridge =
        FsvBasisuTranscodeImages({request}, budget, state);
    if (!bridge.diagnostics.empty() || bridge.decoded_images.size() != 1) {
      if (!bridge.diagnostics.empty()) {
        std::cerr << bridge.diagnostics.front().status << ": "
                  << bridge.diagnostics.front().message << "\n";
      }
      return 71;
    }
    const FsvBasisuDecodedImage& image = bridge.decoded_images.front();
    const std::vector<uint8_t> png_pixels =
        DecodeStoredPng(image.bytes, image.width, image.height);
    const uint8_t* direct_bytes =
        reinterpret_cast<const uint8_t*>(direct_pixels.data());
    if (image.width != level.m_orig_width ||
        image.height != level.m_orig_height ||
        png_pixels.size() != direct_pixels.size() * sizeof(uint32_t) ||
        !std::equal(png_pixels.begin(), png_pixels.end(), direct_bytes)) {
      return 72;
    }
  }
  std::cout << "basisu-conformance-ok cases=10\n";
  return 0;
}
''';

const String _basisuMipDiagnosticRunner = r'''
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

#include "fsv_basisu_bridge.h"

int main(int argc, char** argv) {
  if (argc != 3) {
    return 64;
  }
  for (int case_index = 0; case_index < 2; case_index += 1) {
    std::ifstream input(argv[case_index + 1], std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    if (bytes.empty()) {
      return 65;
    }
    FsvBasisuImageRequest request;
    request.texture_index = case_index;
    request.image_index = case_index;
    request.mime_type = "image/ktx2";
    request.bytes = bytes;
    FsvBasisuDecodeBudgetMetadata budget;
    budget.max_total_decoded_bytes =
        FsvBasisuBudgetNumber::Integer(10000000);
    budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(1000000);
    budget.max_native_output_bytes =
        FsvBasisuBudgetNumber::Integer(10000000);
    FsvBasisuDecodeBudgetState state;
    state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
    state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
    state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
    const FsvBasisuTranscodeResult result =
        FsvBasisuTranscodeImages({request}, budget, state);
    if (!result.decoded_images.empty() || result.diagnostics.size() != 1) {
      return 66;
    }
    const FsvBasisuDiagnostic& diagnostic = result.diagnostics.front();
    if (diagnostic.status != "unsupportedKtx2Layout" ||
        diagnostic.stage != "basisuNativePreflight" ||
        diagnostic.field != "ktx2MipLevels" ||
        !diagnostic.has_limit || diagnostic.limit != 1 ||
        !diagnostic.has_actual || diagnostic.actual != 2) {
      std::cerr << "status=" << diagnostic.status
                << " stage=" << diagnostic.stage
                << " field=" << diagnostic.field
                << " limit=" << diagnostic.limit
                << " actual=" << diagnostic.actual << "\n";
      return 67;
    }
  }
  std::cout << "basisu-mip-diagnostic-ok cases=2\n";
  return 0;
}
''';

const String _basisuProfileDiagnosticRunner = r'''
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

#include "fsv_basisu_bridge.h"

struct ExpectedDiagnostic {
  const char* field;
};

uint32_t ReadLe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

void SetLe32(std::vector<uint8_t>* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value & 0xff);
  (*bytes)[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  (*bytes)[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xff);
  (*bytes)[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

std::vector<uint8_t> ReadFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(input)),
                              std::istreambuf_iterator<char>());
}

bool ReplaceBytes(std::vector<uint8_t>* bytes, const char* before,
                  const char* after, size_t size) {
  for (size_t offset = 0; offset + size <= bytes->size(); offset += 1) {
    if (std::memcmp(bytes->data() + offset, before, size) == 0) {
      std::memcpy(bytes->data() + offset, after, size);
      return true;
    }
  }
  return false;
}

FsvBasisuTranscodeResult Transcode(
    const std::vector<uint8_t>& bytes, int case_index,
    FsvBasisuUsageRole usage_role =
        FsvBasisuUsageRole::kStructuralOnly,
    FsvBasisuChannelLayout channel_layout =
        FsvBasisuChannelLayout::kStructuralOnly) {
  FsvBasisuImageRequest request;
  request.texture_index = case_index;
  request.image_index = case_index;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  request.usage_role = usage_role;
  request.channel_layout = channel_layout;
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(10000000);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(1000000);
  budget.max_native_output_bytes =
      FsvBasisuBudgetNumber::Integer(10000000);
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
  return FsvBasisuTranscodeImages({request}, budget, state);
}

bool IsProfileDiagnostic(const FsvBasisuTranscodeResult& result,
                         const char* field, int case_index) {
  if (!result.decoded_images.empty() || result.diagnostics.size() != 1) {
    std::cerr << "case=" << case_index << " expected one diagnostic\n";
    return false;
  }
  const FsvBasisuDiagnostic& diagnostic = result.diagnostics.front();
  if (diagnostic.status != "unsupportedKtx2Profile" ||
      diagnostic.stage != "basisuProfilePreflight" ||
      diagnostic.field != field) {
    std::cerr << "case=" << case_index << " status=" << diagnostic.status
              << " stage=" << diagnostic.stage
              << " field=" << diagnostic.field << "\n";
    return false;
  }
  return true;
}

bool IsAccepted(const std::vector<uint8_t>& bytes, int case_index) {
  const FsvBasisuTranscodeResult result = Transcode(bytes, case_index);
  if (!result.diagnostics.empty() || result.decoded_images.size() != 1) {
    if (!result.diagnostics.empty()) {
      std::cerr << "positive=" << case_index
                << " status=" << result.diagnostics.front().status
                << " field=" << result.diagnostics.front().field << "\n";
    }
    return false;
  }
  return true;
}

bool IsAcceptedForUsage(const std::vector<uint8_t>& bytes, int case_index,
                        FsvBasisuUsageRole usage_role,
                        FsvBasisuChannelLayout channel_layout) {
  const FsvBasisuTranscodeResult result =
      Transcode(bytes, case_index, usage_role, channel_layout);
  if (!result.diagnostics.empty() || result.decoded_images.size() != 1) {
    if (!result.diagnostics.empty()) {
      std::cerr << "usage-positive=" << case_index
                << " status=" << result.diagnostics.front().status
                << " field=" << result.diagnostics.front().field << "\n";
    }
    return false;
  }
  return true;
}

bool IsUsageDiagnostic(const std::vector<uint8_t>& bytes, int case_index,
                       FsvBasisuUsageRole usage_role,
                       FsvBasisuChannelLayout channel_layout) {
  const FsvBasisuTranscodeResult result =
      Transcode(bytes, case_index, usage_role, channel_layout);
  if (!result.decoded_images.empty() || result.diagnostics.size() != 1) {
    std::cerr << "usage-negative=" << case_index
              << " expected one diagnostic\n";
    return false;
  }
  const FsvBasisuDiagnostic& diagnostic = result.diagnostics.front();
  if (diagnostic.status != "unsupportedKtx2Usage" ||
      diagnostic.stage != "basisuUsagePreflight" ||
      diagnostic.field != "basisuUsageRole") {
    std::cerr << "usage-negative=" << case_index
              << " status=" << diagnostic.status
              << " stage=" << diagnostic.stage
              << " field=" << diagnostic.field << "\n";
    return false;
  }
  return true;
}

bool IsUsageColorSpaceDiagnostic(const std::vector<uint8_t>& bytes,
                                 int case_index,
                                 FsvBasisuUsageRole usage_role,
                                 FsvBasisuChannelLayout channel_layout) {
  return IsProfileDiagnostic(
      Transcode(bytes, case_index, usage_role, channel_layout),
      "ktx2DfdColorSpace", case_index);
}

bool IsChannelLayoutDiagnostic(const std::vector<uint8_t>& bytes,
                               int case_index,
                               FsvBasisuUsageRole usage_role,
                               FsvBasisuChannelLayout channel_layout) {
  return IsProfileDiagnostic(
      Transcode(bytes, case_index, usage_role, channel_layout),
      "ktx2DfdChannels", case_index);
}

bool IsMalformedDiagnostic(const std::vector<uint8_t>& bytes,
                           const char* field, int case_index) {
  const FsvBasisuTranscodeResult result = Transcode(bytes, case_index);
  if (!result.decoded_images.empty() || result.diagnostics.size() != 1) {
    std::cerr << "malformed=" << case_index
              << " expected one diagnostic\n";
    return false;
  }
  const FsvBasisuDiagnostic& diagnostic = result.diagnostics.front();
  if (diagnostic.status != "invalidMetadata" ||
      diagnostic.stage != "basisuNativePreflight" ||
      diagnostic.field != field) {
    std::cerr << "malformed=" << case_index
              << " status=" << diagnostic.status
              << " stage=" << diagnostic.stage
              << " field=" << diagnostic.field << "\n";
    return false;
  }
  return true;
}

int main(int argc, char** argv) {
  if (argc != 18) {
    return 64;
  }
  const ExpectedDiagnostic expected[] = {
      {"ktx2SupercompressionScheme"},
      {"ktx2Dimensions"},
      {"ktx2DfdColorModel"},
      {"ktx2DfdChannels"},
      {"ktx2DfdChannels"},
      {"ktx2DfdColorSpace"},
      {"ktx2DfdColorSpace"},
      {"ktx2KTXswizzle"},
      {"ktx2KTXorientation"},
      {"ktx2PremultipliedAlpha"},
  };

  std::vector<std::vector<uint8_t>> fixtures;
  for (int case_index = 0; case_index < 17; case_index += 1) {
    fixtures.push_back(ReadFile(argv[case_index + 1]));
    if (fixtures.back().empty()) {
      return 65;
    }
  }

  // The CTS has no selected-profile premultiplied-alpha negative. Derive one
  // from the pinned positive by setting KHR_DF_FLAG_ALPHA_PREMULTIPLIED (bit 0)
  // in the Basic Data Format Descriptor flags byte.
  std::vector<uint8_t>& premultiplied = fixtures[9];
  const uint32_t dfd_offset = ReadLe32(premultiplied, 48);
  if (dfd_offset + 15 >= premultiplied.size()) {
    return 66;
  }
  const std::vector<uint8_t> omitted_metadata_positive = premultiplied;
  premultiplied[dfd_offset + 15] |= 1U;

  for (int case_index = 0; case_index < 10; case_index += 1) {
    if (!IsProfileDiagnostic(Transcode(fixtures[case_index], case_index),
                             expected[case_index].field, case_index)) {
      return 67;
    }
  }

  std::vector<uint8_t> swizzle_positive = fixtures[7];
  if (!ReplaceBytes(&swizzle_positive, "bgra\0", "rgba\0", 5) ||
      !IsAccepted(swizzle_positive, 10)) {
    return 68;
  }
  std::vector<uint8_t> orientation_positive = fixtures[8];
  if (!ReplaceBytes(&orientation_positive, "lu\0", "rd\0", 3) ||
      !IsAccepted(orientation_positive, 11)) {
    return 69;
  }
  if (!IsAccepted(omitted_metadata_positive, 12)) {
    return 70;
  }
  if (!IsAcceptedForUsage(omitted_metadata_positive, 24,
                          FsvBasisuUsageRole::kColor,
                          FsvBasisuChannelLayout::kRgba) ||
      !IsAcceptedForUsage(orientation_positive, 25,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kRgba) ||
      !IsUsageColorSpaceDiagnostic(omitted_metadata_positive, 26,
                                   FsvBasisuUsageRole::kNonColor,
                                   FsvBasisuChannelLayout::kRgba) ||
      !IsUsageColorSpaceDiagnostic(orientation_positive, 27,
                                   FsvBasisuUsageRole::kColor,
                                   FsvBasisuChannelLayout::kRgba) ||
      !IsUsageDiagnostic(omitted_metadata_positive, 28,
                         FsvBasisuUsageRole::kAmbiguous,
                         FsvBasisuChannelLayout::kRgba)) {
    return 701;
  }
  // The pinned R/RG/RGB codec sources use BT709 primaries with a linear
  // transfer function. Derive the selected KHR profile pair by changing only
  // the DFD primaries to UNSPECIFIED; the codec payloads remain pinned.
  std::vector<uint8_t> profile_r = fixtures[10];
  std::vector<uint8_t> profile_rg = fixtures[11];
  std::vector<uint8_t> profile_rgb = fixtures[13];
  std::vector<uint8_t> profile_uastc_rgb = fixtures[15];
  std::vector<uint8_t> generic_uastc_rg_data0 = fixtures[16];
  for (std::vector<uint8_t>* bytes : {&profile_r, &profile_rg, &profile_rgb,
                                      &profile_uastc_rgb,
                                      &generic_uastc_rg_data0}) {
    const uint32_t offset = ReadLe32(*bytes, 48);
    uint32_t bits = ReadLe32(*bytes, offset + 12);
    bits &= ~0x0000ff00U;
    SetLe32(bytes, offset + 12, bits);
  }
  if (!IsAcceptedForUsage(profile_r, 29,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kR) ||
      !IsAcceptedForUsage(profile_rg, 30,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kRg) ||
      !IsAcceptedForUsage(profile_rgb, 31,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kRgb) ||
      !IsAcceptedForUsage(omitted_metadata_positive, 32,
                          FsvBasisuUsageRole::kColor,
                          FsvBasisuChannelLayout::kRgba) ||
      !IsChannelLayoutDiagnostic(omitted_metadata_positive, 33,
                                 FsvBasisuUsageRole::kColor,
                                 FsvBasisuChannelLayout::kRgb) ||
      !IsChannelLayoutDiagnostic(profile_rgb, 34,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kRgba) ||
      !IsChannelLayoutDiagnostic(profile_r, 35,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kRg) ||
      !IsChannelLayoutDiagnostic(profile_rg, 36,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kR) ||
      !IsAcceptedForUsage(fixtures[14], 37,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kRg) ||
      !IsChannelLayoutDiagnostic(fixtures[14], 38,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kRgb) ||
      !IsAcceptedForUsage(profile_uastc_rgb, 40,
                          FsvBasisuUsageRole::kNonColor,
                          FsvBasisuChannelLayout::kRgb) ||
      !IsChannelLayoutDiagnostic(profile_uastc_rgb, 41,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kRg) ||
      !IsChannelLayoutDiagnostic(generic_uastc_rg_data0, 42,
                                 FsvBasisuUsageRole::kNonColor,
                                 FsvBasisuChannelLayout::kRg)) {
    return 702;
  }

  std::vector<uint8_t> malformed_dfd = omitted_metadata_positive;
  SetLe32(&malformed_dfd, 48,
          static_cast<uint32_t>(malformed_dfd.size() - 4));
  SetLe32(&malformed_dfd, 52, 44);
  if (!IsMalformedDiagnostic(malformed_dfd, "ktx2Dfd", 13)) {
    return 71;
  }
  std::vector<uint8_t> malformed_kvd = omitted_metadata_positive;
  SetLe32(&malformed_kvd, 56,
          static_cast<uint32_t>(malformed_kvd.size() - 2));
  if (!IsMalformedDiagnostic(malformed_kvd, "ktx2KeyValueData", 14)) {
    return 72;
  }

  int remediation_failures = 0;
  for (int fixture_index = 10; fixture_index < 13; fixture_index += 1) {
    std::vector<uint8_t> srgb_single_or_dual_channel =
        fixtures[fixture_index];
    const uint32_t color_dfd_offset =
        ReadLe32(srgb_single_or_dual_channel, 48);
    uint32_t dfd_bits =
        ReadLe32(srgb_single_or_dual_channel, color_dfd_offset + 12);
    dfd_bits = (dfd_bits & ~0x00ff0000U) | (2U << 16);
    SetLe32(&srgb_single_or_dual_channel, color_dfd_offset + 12, dfd_bits);
    if (!IsProfileDiagnostic(
            Transcode(srgb_single_or_dual_channel, 15 + fixture_index - 10),
            "ktx2DfdColorSpace", 15 + fixture_index - 10)) {
      remediation_failures += 1;
    }
  }

  // The derived fixture retains the exact official R8G8 UASTC payload and
  // changes only the two DFD fields required by KHR_texture_basisu. Prove its
  // linear RG profile is accepted and its sRGB mutation is rejected.
  std::vector<uint8_t> derived_uastc_rg_srgb = fixtures[14];
  const uint32_t derived_rg_dfd_offset =
      ReadLe32(derived_uastc_rg_srgb, 48);
  uint32_t derived_rg_dfd_bits =
      ReadLe32(derived_uastc_rg_srgb, derived_rg_dfd_offset + 12);
  derived_rg_dfd_bits =
      (derived_rg_dfd_bits & ~0x00ff0000U) | (2U << 16);
  SetLe32(&derived_uastc_rg_srgb, derived_rg_dfd_offset + 12,
          derived_rg_dfd_bits);
  if (!IsProfileDiagnostic(Transcode(derived_uastc_rg_srgb, 39),
                           "ktx2DfdColorSpace", 39)) {
    remediation_failures += 1;
  }

  const uint32_t positive_kvd_offset =
      ReadLe32(omitted_metadata_positive, 56);
  const uint32_t first_entry_length =
      ReadLe32(omitted_metadata_positive, positive_kvd_offset);
  const size_t second_entry_offset =
      positive_kvd_offset + 4U + first_entry_length +
      ((4U - (first_entry_length & 3U)) & 3U);
  const uint32_t second_entry_length =
      ReadLe32(omitted_metadata_positive, second_entry_offset);
  const size_t first_key_offset = positive_kvd_offset + 4U;
  const size_t second_key_offset = second_entry_offset + 4U;

  std::vector<uint8_t> duplicate_key = omitted_metadata_positive;
  const uint8_t duplicate_name[] = {'d', 'u', 'p', 0};
  std::memcpy(duplicate_key.data() + first_key_offset, duplicate_name,
              sizeof(duplicate_name));
  std::memcpy(duplicate_key.data() + second_key_offset, duplicate_name,
              sizeof(duplicate_name));
  // Equality is both a duplicate and a strict-ordering violation.
  if (!IsMalformedDiagnostic(duplicate_key, "ktx2KeyValueData", 19)) {
    remediation_failures += 1;
  }

  std::vector<uint8_t> unsorted_keys = omitted_metadata_positive;
  const uint8_t late_name[] = {'z', 0};
  const uint8_t early_name[] = {'a', 0};
  std::memcpy(unsorted_keys.data() + first_key_offset, late_name,
              sizeof(late_name));
  std::memcpy(unsorted_keys.data() + second_key_offset, early_name,
              sizeof(early_name));
  if (!IsMalformedDiagnostic(unsorted_keys, "ktx2KeyValueData", 20)) {
    remediation_failures += 1;
  }

  size_t second_key_length = 0;
  while (omitted_metadata_positive[second_key_offset + second_key_length] !=
         0) {
    second_key_length += 1;
  }
  if (second_key_length == 0) {
    return 73;
  }
  std::vector<uint8_t> invalid_utf8_key = omitted_metadata_positive;
  invalid_utf8_key[second_key_offset + second_key_length - 1U] = 0x80U;
  if (!IsMalformedDiagnostic(invalid_utf8_key, "ktx2KeyValueData", 21)) {
    remediation_failures += 1;
  }

  std::vector<uint8_t> leading_bom_key = omitted_metadata_positive;
  const uint8_t utf8_bom_key[] = {0xEFU, 0xBBU, 0xBFU, 0};
  std::memcpy(leading_bom_key.data() + second_key_offset, utf8_bom_key,
              sizeof(utf8_bom_key));
  if (!IsMalformedDiagnostic(leading_bom_key, "ktx2KeyValueData", 22)) {
    remediation_failures += 1;
  }

  const size_t second_padding_offset =
      second_entry_offset + 4U + second_entry_length;
  const size_t second_padding_length =
      (4U - (second_entry_length & 3U)) & 3U;
  if (second_padding_length == 0) {
    return 74;
  }
  std::vector<uint8_t> nonzero_padding = omitted_metadata_positive;
  nonzero_padding[second_padding_offset] = 1U;
  if (!IsMalformedDiagnostic(nonzero_padding, "ktx2KeyValueData", 23)) {
    remediation_failures += 1;
  }
  if (remediation_failures != 0) {
    std::cerr << "remediation-failures=" << remediation_failures << "\n";
    return 75;
  }

  std::cout << "basisu-profile-diagnostic-ok negatives=14 positives=3 "
               "malformed=7 usagePositive=2 usageNegative=3 "
               "layoutPositive=7 layoutNegative=7\n";
  return 0;
}
''';
