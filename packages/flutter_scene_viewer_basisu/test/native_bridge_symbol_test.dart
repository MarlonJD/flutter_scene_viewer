import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('native bridge transcodes KTX2 fixture into PNG bytes', () async {
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
    final runner = File('${tempDir.path}/basisu_runner.cc');
    await runner.writeAsString(_basisuRunner);
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
      const <String>['test/fixtures/kodim23.ktx2'],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('png='));
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

const String _basisuRunner = r'''
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

#include "fsv_basisu_bridge.h"

int main(int argc, char** argv) {
  if (argc != 2) {
    return 64;
  }
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> bytes(
      (std::istreambuf_iterator<char>(input)),
      std::istreambuf_iterator<char>());
  if (bytes.empty()) {
    return 65;
  }

  FsvBasisuImageRequest request;
  request.texture_index = 3;
  request.image_index = 7;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages({request});
  if (!result.diagnostics.empty()) {
    std::cerr << result.diagnostics.front().status << ": "
              << result.diagnostics.front().message << "\n";
    return 2;
  }
  if (result.decoded_images.size() != 1) {
    return 3;
  }
  const FsvBasisuDecodedImage& image = result.decoded_images.front();
  if (image.image_index != 7 || image.mime_type != "image/png") {
    return 4;
  }
  const uint8_t signature[] = {
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
  if (image.bytes.size() < sizeof(signature)) {
    return 5;
  }
  for (size_t i = 0; i < sizeof(signature); i += 1) {
    if (image.bytes[i] != signature[i]) {
      return 6;
    }
  }
  std::cout << "png=" << image.bytes.size() << "\n";
  return 0;
}
''';
