import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _basisuRgbaSha256 =
    '34219173d529d9cf97a7f8642e32142570426af0d4d52ac50eb316a614e6dae8';
const _basisuMipLevelSha256 = <String>[
  '03e1d296c115d8dcd181f3872b13afdfe11ca1672c95a07922b437de301e0827',
  'c7522e84b6b40064b5836681eb8d552db4cb04f42722d8c1abf66b5cc4560c8c',
  '48de634d3e20453e20308c66e0e80ef239ec70f4c1babd4fe2922268e85b1474',
  '7a6a9f41602ab185348240303b760d337010f58ab446dbcf3ee503d1bc322075',
];
const _ktx2E2Fixtures = <String>[
  'test/fixtures/ktx2-cts/create/encode_uastc/'
      'output_R8G8B8A8_UNORM.ktx2',
  'test/fixtures/ktx2-cts/deflate/metadata/'
      'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
  'test/fixtures/ktx2-cts/create/encode_blze/'
      'output_R8G8B8A8_UNORM.ktx2',
];
const _ktx2E3Etc1sFixtures = <String>[
  'test/fixtures/ktx2-cts/create/encode_blze/output_R8G8B8_UNORM.ktx2',
  'test/fixtures/ktx2-cts/create/encode_blze/output_R8G8B8A8_UNORM.ktx2',
  'test/fixtures/ktx2-cts/create/compare/'
      'output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2',
];

void main() {
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
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FsvDecodeRequestRegistry.java',
    );
    final iosHeader = File('ios/Classes/fsv_basisu_request_registry.h');
    final iosSource = File('ios/Classes/fsv_basisu_request_registry.cc');
    expect(await javaOwner.exists(), isTrue);
    expect(await iosHeader.exists(), isTrue);
    expect(await iosSource.exists(), isTrue);
    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_owner_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final javaRunner = File('${tempDir.path}/BasisuRegistryRunner.java');
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
        'com.marlonjd.flutter_scene_viewer_basisu.BasisuRegistryRunner',
      ],
    );
    expect(javaRun.exitCode, 0, reason: '${javaRun.stdout}\n${javaRun.stderr}');

    final nativeRunner = File('${tempDir.path}/registry_runner.cc');
    await nativeRunner.writeAsString(_nativeLifecycleRunner);
    final nativeCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-pthread',
      '-Iios/Classes',
      '-Ithird_party/basis_universal/transcoder',
      nativeRunner.path,
      'ios/Classes/fsv_basisu_control.cc',
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
      packageName: 'com.marlonjd.flutter_scene_viewer_basisu',
      runnerClass: 'BasisuRegistryRunner',
      javaSourcePath:
          'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
          'FsvDecodeRequestRegistry.java',
      javaRunner: _javaLifecycleRunner,
      nativeHeaderDirectory: 'ios/Classes',
      nativeControlPath: 'ios/Classes/fsv_basisu_control.cc',
      nativeRegistryPath: 'ios/Classes/fsv_basisu_request_registry.cc',
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
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_control_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final runner = File('${tempDir.path}/control_runner.cc');
    await runner.writeAsString(_decodeControlRunner);
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      expect(await File('$platform/fsv_basisu_control.h').exists(), isTrue);
      expect(await File('$platform/fsv_basisu_control.cc').exists(), isTrue);
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        runner.path,
        '$platform/fsv_basisu_control.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '$platform\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, const <String>[]);
      expect(run.exitCode, 0,
          reason: '$platform\n${run.stdout}\n${run.stderr}');
      final ndebugExecutable = '$executable-ndebug';
      final ndebugCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-DNDEBUG',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        'test/native/basisu_container_allocator_runner.cc',
        '$platform/fsv_basisu_control.cc',
        '-o',
        ndebugExecutable,
      ]);
      expect(ndebugCompile.exitCode, 0,
          reason:
              '$platform NDEBUG\n${ndebugCompile.stdout}\n${ndebugCompile.stderr}');
      final ndebugRun = await Process.run(ndebugExecutable, const <String>[]);
      expect(ndebugRun.exitCode, 0,
          reason: '$platform NDEBUG\n${ndebugRun.stdout}\n${ndebugRun.stderr}');
      final noExceptionExecutable = '$executable-no-exceptions';
      final noExceptionCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-DNDEBUG',
        '-fno-exceptions',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        'test/native/basisu_container_allocator_runner.cc',
        '$platform/fsv_basisu_control.cc',
        '-o',
        noExceptionExecutable,
      ]);
      expect(noExceptionCompile.exitCode, 0,
          reason:
              '$platform no-exceptions\n${noExceptionCompile.stdout}\n${noExceptionCompile.stderr}');
      final noExceptionRun = await Process.run(
        noExceptionExecutable,
        const <String>['noexceptions'],
      );
      expect(noExceptionRun.exitCode, 0,
          reason:
              '$platform no-exceptions\n${noExceptionRun.stdout}\n${noExceptionRun.stderr}');
      final lifetimeRun =
          await Process.run(ndebugExecutable, const <String>['lifetime']);
      expect(lifetimeRun.exitCode, isNot(0),
          reason:
              '$platform accepted control destruction before a vector owner');
      final containers = await File(
        'third_party/basis_universal/transcoder/basisu_containers.h',
      ).readAsString();
      final implementation = await File(
        'third_party/basis_universal/transcoder/basisu_containers_impl.h',
      ).readAsString();
      final control =
          await File('$platform/fsv_basisu_control.cc').readAsString();
      final allocatorRunner = await File(
        'test/native/basisu_container_allocator_runner.cc',
      ).readAsString();
      final bypassedAllocation = implementation.replaceFirst(
        'm_fsv_allocator->fsv_allocate(desired_size, element_alignment)',
        '([](fsv_vector_allocator* allocator, size_t bytes, size_t alignment) { fsv_allocation_result result; result.m_p = malloc(bytes); result.m_bytes = bytes; result.m_alignment = alignment; result.m_outcome = fsv_allocation_outcome::kSuccess; result.m_allocator = allocator; return result; })(m_fsv_allocator, desired_size, element_alignment)',
      );
      final missingOldRelease = implementation.replaceFirst(
        'm_p && !m_fsv_allocator->fsv_release(m_fsv_allocation, m_p, m_capacity * element_size, element_alignment)',
        'm_p && false',
      );
      final overwrittenRelocation = implementation.replaceFirst(
        'else if (m_p && m_size)\n\t\t\t\tmemcpy(new_p, m_p, m_size * element_size);',
        'if (m_p && m_size)\n\t\t\t\tmemcpy(new_p, m_p, m_size * element_size);',
      );
      final crossControlTheft = containers.replaceFirst(
        'if (m_fsv_allocator == rhs.m_fsv_allocator)\n\t\t\t\t{\n\t\t\t\t\tclear();',
        'if (true)\n\t\t\t\t{\n\t\t\t\t\tclear();',
      );
      final rawFreeControlled = containers.replaceFirst(
        'if (m_fsv_allocator)\n\t\t\t{\n\t\t\t\tif (!m_fsv_allocator->fsv_release(m_fsv_allocation, m_p, m_capacity * sizeof(T), alignof(T)))',
        'if (false)\n\t\t\t{\n\t\t\t\tif (!m_fsv_allocator->fsv_release(m_fsv_allocation, m_p, m_capacity * sizeof(T), alignof(T)))',
      );
      final missingSwapRecord = containers.replaceFirst(
        'm_fsv_allocation.swap(other.m_fsv_allocation);',
        '(void)m_fsv_allocation;',
      );
      final droppedRecordPointerSwap = containers.replaceFirst(
        'std::swap(m_p, other.m_p); std::swap(m_bytes, other.m_bytes);',
        '(void)other.m_p; std::swap(m_bytes, other.m_bytes);',
      );
      final nestedCopyRawAllocator = containers.replaceFirst(
        'new ((void*)(m_p + m_size)) T(other.m_p[i].fsv_allocator());',
        'new ((void*)(m_p + m_size)) T();',
      );
      final nestedMoveDestruction = containers.replaceFirst(
        'other.clear_no_destruction();',
        'other.clear();',
      );
      final droppedMovedFromAllocator = containers.replaceFirst(
        'other.m_capacity = 0;\n\t\t}',
        'other.m_capacity = 0;\n\t\t\tother.m_fsv_allocator = nullptr;\n\t\t}',
      );
      final droppedExactRelease = control.replaceFirst(
        'allocation.m_bytes != normalized_bytes || allocation.m_alignment != normalized_alignment',
        'false',
      );
      expect(bypassedAllocation, isNot(implementation),
          reason: 'bypassed-allocation did not mutate the implementation');
      expect(missingOldRelease, isNot(implementation),
          reason: 'missing-old-release did not mutate the implementation');
      expect(overwrittenRelocation, isNot(implementation),
          reason:
              'overwritten-relocation did not mutate the mover/memcpy branch');
      expect(crossControlTheft, isNot(containers),
          reason: 'cross-control-theft did not mutate the storage-steal path');
      expect(rawFreeControlled, isNot(containers),
          reason: 'raw-free-controlled did not mutate release_storage');
      expect(missingSwapRecord, isNot(containers),
          reason: 'swap-record did not mutate the allocation-record swap');
      expect(droppedRecordPointerSwap, isNot(containers),
          reason: 'record-pointer-swap did not mutate exact token transfer');
      expect(nestedCopyRawAllocator, isNot(containers),
          reason: 'nested-copy-raw did not mutate nested allocator retention');
      expect(nestedMoveDestruction, isNot(containers),
          reason:
              'nested-move-destruction did not mutate bitwise move release');
      expect(droppedMovedFromAllocator, isNot(containers),
          reason:
              'moved-from-allocator did not mutate source allocator retention');
      expect(droppedExactRelease, isNot(control),
          reason: 'dropped-exact-release did not mutate exact validation');
      final mutants =
          <({String label, String header, String impl, String control})>[
        (
          label: 'bypassed-allocation',
          header: containers,
          impl: bypassedAllocation,
          control: control,
        ),
        (
          label: 'missing-old-release',
          header: containers,
          impl: missingOldRelease,
          control: control,
        ),
        (
          label: 'overwritten-relocation',
          header: containers,
          impl: overwrittenRelocation,
          control: control,
        ),
        (
          label: 'cross-control-theft',
          header: crossControlTheft,
          impl: implementation,
          control: control,
        ),
        (
          label: 'raw-free-controlled',
          header: rawFreeControlled,
          impl: implementation,
          control: control,
        ),
        (
          label: 'swap-record',
          header: missingSwapRecord,
          impl: implementation,
          control: control,
        ),
        (
          label: 'record-pointer-swap',
          header: droppedRecordPointerSwap,
          impl: implementation,
          control: control,
        ),
        (
          label: 'nested-copy-raw',
          header: nestedCopyRawAllocator,
          impl: implementation,
          control: control,
        ),
        (
          label: 'nested-move-destruction',
          header: nestedMoveDestruction,
          impl: implementation,
          control: control,
        ),
        (
          label: 'moved-from-allocator',
          header: droppedMovedFromAllocator,
          impl: implementation,
          control: control,
        ),
        (
          label: 'dropped-exact-release',
          header: containers,
          impl: implementation,
          control: droppedExactRelease,
        ),
      ];
      for (final mutant in mutants) {
        expect(
            mutant.header != containers ||
                mutant.impl != implementation ||
                mutant.control != control,
            isTrue,
            reason: '${mutant.label} did not alter its target source');
        final dir = Directory(
            '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-${mutant.label}');
        await dir.create();
        await File('${dir.path}/basisu_containers.h')
            .writeAsString(mutant.header);
        await File('${dir.path}/basisu_containers_impl.h')
            .writeAsString(mutant.impl);
        final mutantControl = File('${dir.path}/fsv_basisu_control.cc');
        await mutantControl.writeAsString(mutant.control);
        final mutantExecutable = '${dir.path}/runner';
        final mutantCompile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-I${dir.path}',
          '-I$platform',
          'test/native/basisu_container_allocator_runner.cc',
          mutantControl.path,
          '-o',
          mutantExecutable,
        ]);
        expect(mutantCompile.exitCode, 0,
            reason: '${mutant.label}\n${mutantCompile.stderr}');
        final mutantRun = await Process.run(mutantExecutable, const <String>[]);
        expect(mutantRun.exitCode, isNot(0), reason: '${mutant.label} escaped');
        print(
          'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
          '${mutant.label}: source-diff=true compile-exit=0 '
          'run-exit=${mutantRun.exitCode}',
        );
      }
      final shrinkDoubleAllocation = containers.replaceFirst(
        'if (!tmp.try_copy_elements_from(*this))',
        'if (!tmp.try_copy_assign(*this))',
      );
      final copyConstructorCleanup = containers.replaceFirst(
        '\t\t\tcatch (...)\n'
            '\t\t\t{\n'
            '\t\t\t\tclear();\n'
            '\t\t\t\trelease_allocator();\n'
            '\t\t\t\tthrow;\n'
            '\t\t\t}',
        '\t\t\tcatch (...)\n'
            '\t\t\t{\n'
            '\t\t\t\tthrow;\n'
            '\t\t\t}',
      );
      final concurrentSharedControl = allocatorRunner.replaceFirst(
        'basisu::vector<uint32_t> values(&unaffected);',
        'basisu::vector<uint32_t> values(&stopped);',
      );
      for (final mutant in <({
        String label,
        String header,
        String runner,
      })>[
        (
          label: 'shrink-double-allocation',
          header: shrinkDoubleAllocation,
          runner: allocatorRunner,
        ),
        (
          label: 'copy-constructor-cleanup',
          header: copyConstructorCleanup,
          runner: allocatorRunner,
        ),
        (
          label: 'concurrent-shared-control',
          header: containers,
          runner: concurrentSharedControl,
        ),
      ]) {
        expect(
          mutant.header != containers || mutant.runner != allocatorRunner,
          isTrue,
          reason: '${mutant.label} did not alter its target source',
        );
        final dir = Directory(
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-${mutant.label}',
        );
        await dir.create();
        await File('${dir.path}/basisu_containers.h')
            .writeAsString(mutant.header);
        await File('${dir.path}/basisu_containers_impl.h')
            .writeAsString(implementation);
        final mutantControl = File('${dir.path}/fsv_basisu_control.cc');
        await mutantControl.writeAsString(control);
        final mutantRunner = File('${dir.path}/allocator_runner.cc');
        await mutantRunner.writeAsString(mutant.runner);
        final mutantExecutable = '${dir.path}/runner';
        final mutantCompile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-I${dir.path}',
          '-I$platform',
          mutantRunner.path,
          mutantControl.path,
          '-o',
          mutantExecutable,
        ]);
        expect(mutantCompile.exitCode, 0,
            reason: '${mutant.label}\n${mutantCompile.stderr}');
        final mutantRun = await Process.run(mutantExecutable, const <String>[]);
        expect(mutantRun.exitCode, isNot(0), reason: '${mutant.label} escaped');
        print(
          'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
          '${mutant.label}: source-diff=true compile-exit=0 '
          'run-exit=${mutantRun.exitCode}',
        );
      }
      final droppedShrinkNoExceptionGate = containers.replaceFirst(
        'if (!fsv_can_copy_construct_elements_from(*this))\n'
            '\t\t\t\t\treturn false;\n'
            '\t\t\t\tvector tmp(m_fsv_allocator);',
        'vector tmp(m_fsv_allocator);',
      );
      final droppedPublicCopyNoExceptionGate = containers.replaceFirst(
        'if (!fsv_can_copy_construct_elements_from(other))\n'
            '\t\t\t\tcontainer_abort("controlled vector copy construction requires nothrow copy without exceptions\\n");',
        '(void)other;',
      );
      for (final mutant in <({String label, String header})>[
        (
          label: 'shrink-noexception-copy-gate',
          header: droppedShrinkNoExceptionGate,
        ),
        (
          label: 'public-copy-noexception-gate',
          header: droppedPublicCopyNoExceptionGate,
        ),
      ]) {
        expect(mutant.header, isNot(containers),
            reason: '${mutant.label} did not alter its operation gate');
        final dir = Directory(
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-${mutant.label}',
        );
        await dir.create();
        await File('${dir.path}/basisu_containers.h')
            .writeAsString(mutant.header);
        await File('${dir.path}/basisu_containers_impl.h')
            .writeAsString(implementation);
        final mutantControl = File('${dir.path}/fsv_basisu_control.cc');
        await mutantControl.writeAsString(control);
        final mutantRunner = File('${dir.path}/allocator_runner.cc');
        await mutantRunner.writeAsString(allocatorRunner);
        final mutantExecutable = '${dir.path}/runner';
        final mutantCompile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-DNDEBUG',
          '-fno-exceptions',
          '-I${dir.path}',
          '-I$platform',
          mutantRunner.path,
          mutantControl.path,
          '-o',
          mutantExecutable,
        ]);
        expect(mutantCompile.exitCode, 0,
            reason: '${mutant.label}\n${mutantCompile.stderr}');
        final mutantRun = await Process.run(
          mutantExecutable,
          const <String>['noexceptions'],
        );
        expect(mutantRun.exitCode, isNot(0), reason: '${mutant.label} escaped');
        print(
          'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
          '${mutant.label}: source-diff=true compile-exit=0 '
          'run-exit=${mutantRun.exitCode}',
        );
      }
      final traitOnlyNestedPublicCopyPreflight = containers.replaceFirst(
        'fsv_can_copy_construct_elements_from(other)',
        '(!m_fsv_allocator || BASISU_IS_BITWISE_COPYABLE(T) || '
            'is_fsv_vector<T>::cFlag || '
            'std::is_nothrow_copy_constructible<T>::value)',
      );
      final traitOnlyNestedShrinkPreflight = containers.replaceFirst(
        'fsv_can_copy_construct_elements_from(*this)',
        '(!m_fsv_allocator || BASISU_IS_BITWISE_COPYABLE(T) || '
            'is_fsv_vector<T>::cFlag || '
            'std::is_nothrow_copy_constructible<T>::value)',
      );
      for (final mutant in <({String label, String header, String mode})>[
        (
          label: 'nested-public-copy-noexception-preflight',
          header: traitOnlyNestedPublicCopyPreflight,
          mode: 'nested-mixed-copy',
        ),
        (
          label: 'nested-shrink-noexception-preflight',
          header: traitOnlyNestedShrinkPreflight,
          mode: 'nested-mixed-shrink',
        ),
      ]) {
        expect(mutant.header, isNot(containers),
            reason: '${mutant.label} did not alter its source-aware preflight');
        final dir = Directory(
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-${mutant.label}',
        );
        await dir.create();
        await File('${dir.path}/basisu_containers.h')
            .writeAsString(mutant.header);
        await File('${dir.path}/basisu_containers_impl.h')
            .writeAsString(implementation);
        final mutantControl = File('${dir.path}/fsv_basisu_control.cc');
        await mutantControl.writeAsString(control);
        final mutantRunner = File('${dir.path}/allocator_runner.cc');
        await mutantRunner.writeAsString(allocatorRunner);
        final mutantExecutable = '${dir.path}/runner';
        final mutantCompile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-DNDEBUG',
          '-fno-exceptions',
          '-I${dir.path}',
          '-I$platform',
          mutantRunner.path,
          mutantControl.path,
          '-o',
          mutantExecutable,
        ]);
        expect(mutantCompile.exitCode, 0,
            reason: '${mutant.label}\n${mutantCompile.stderr}');
        final mutantRun = await Process.run(
          mutantExecutable,
          <String>[mutant.mode],
        );
        expect(mutantRun.exitCode, isNot(0), reason: '${mutant.label} escaped');
        print(
          'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
          '${mutant.label}: source-diff=true compile-exit=0 '
          'run-exit=${mutantRun.exitCode}',
        );
      }
      final rawIntermediateRequireNothrowMutant = containers.replaceFirst(
        'if (!require_nothrow && !m_fsv_allocator)',
        'if (!m_fsv_allocator)',
      );
      expect(rawIntermediateRequireNothrowMutant, isNot(containers),
          reason:
              'raw intermediate require-nothrow mutant did not alter source');
      final rawIntermediateDir = Directory(
        '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-raw-intermediate-require-nothrow',
      );
      await rawIntermediateDir.create();
      await File('${rawIntermediateDir.path}/basisu_containers.h')
          .writeAsString(rawIntermediateRequireNothrowMutant);
      await File('${rawIntermediateDir.path}/basisu_containers_impl.h')
          .writeAsString(implementation);
      final rawIntermediateControl =
          File('${rawIntermediateDir.path}/fsv_basisu_control.cc');
      await rawIntermediateControl.writeAsString(control);
      final rawIntermediateRunner =
          File('${rawIntermediateDir.path}/allocator_runner.cc');
      await rawIntermediateRunner.writeAsString(allocatorRunner);
      final rawIntermediateExecutable = '${rawIntermediateDir.path}/runner';
      final rawIntermediateCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-DNDEBUG',
        '-fno-exceptions',
        '-I${rawIntermediateDir.path}',
        '-I$platform',
        rawIntermediateRunner.path,
        rawIntermediateControl.path,
        '-o',
        rawIntermediateExecutable,
      ]);
      expect(rawIntermediateCompile.exitCode, 0,
          reason: 'raw-intermediate-require-nothrow\n'
              '${rawIntermediateCompile.stderr}');
      final rawIntermediateCopyRun = await Process.run(
        rawIntermediateExecutable,
        const <String>['nested-mixed-copy'],
      );
      final rawIntermediateShrinkRun = await Process.run(
        rawIntermediateExecutable,
        const <String>['nested-mixed-shrink'],
      );
      expect(rawIntermediateCopyRun.exitCode, isNot(0),
          reason: 'raw intermediate copy propagation mutant escaped');
      expect(rawIntermediateShrinkRun.exitCode, isNot(0),
          reason: 'raw intermediate shrink propagation mutant escaped');
      print(
        'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
        'raw-intermediate-require-nothrow: source-diff=true compile-exit=0 '
        'copy-run-exit=${rawIntermediateCopyRun.exitCode} '
        'shrink-run-exit=${rawIntermediateShrinkRun.exitCode}',
      );
      final controlSource =
          await File('$platform/fsv_basisu_control.cc').readAsString();
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
        '-Ithird_party/basis_universal/transcoder',
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
          '-Ithird_party/basis_universal/transcoder',
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
      await File('android/src/main/cpp/fsv_basisu_control.h').readAsString(),
      await File('ios/Classes/fsv_basisu_control.h').readAsString(),
    );
    expect(
      await File('android/src/main/cpp/fsv_basisu_control.cc').readAsString(),
      await File('ios/Classes/fsv_basisu_control.cc').readAsString(),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU vector uses the request allocator foundation', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_container_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final executable =
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        'test/native/basisu_container_allocator_runner.cc',
        '$platform/fsv_basisu_control.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '$platform\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(
        executable,
        const <String>[],
        environment: const <String, String>{
          'ASAN_OPTIONS': 'detect_leaks=0:halt_on_error=1',
          'UBSAN_OPTIONS': 'halt_on_error=1',
        },
      );
      expect(run.exitCode, 0,
          reason: '$platform\n${run.stdout}\n${run.stderr}');
    }
  });

  test('BasisU KTX2 metadata uses the request allocator and rejects animation',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_metadata_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_metadata';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const fixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    final metadata =
        await Process.run(executable, const <String>[fixture, 'metadata']);
    final animation =
        await Process.run(executable, const <String>[fixture, 'animation']);
    expect(metadata.exitCode, 0,
        reason: '${metadata.stdout}\n${metadata.stderr}');
    expect(animation.exitCode, 0,
        reason: '${animation.stdout}\n${animation.stderr}');
    expect(
      '${animation.stdout}',
      contains('basisu-ktx2-metadata-red-contract-ok'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 rejects KTXanimData before codec allocation', () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_animation_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_animation';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const fixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final animation =
        await Process.run(executable, const <String>[fixture, 'animation']);
    final zstdAnimation = await Process.run(executable, const <String>[
      fixture,
      zstdFixture,
      etc1sFixture,
      'animation-zstd',
    ]);
    expect(animation.exitCode == 0 && zstdAnimation.exitCode == 0, isTrue,
        reason: 'uastc exit=${animation.exitCode}\n'
            '${animation.stdout}${animation.stderr}\n'
            'zstd exit=${zstdAnimation.exitCode}\n'
            '${zstdAnimation.stdout}${zstdAnimation.stderr}');
    expect(
      '${animation.stdout}',
      contains('basisu-ktx2-metadata-red-contract-ok'),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 state and ETC1S metadata use the request allocator',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_e2_state_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_e2_state';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const uastcFixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final zstd = await Process.run(executable, const <String>[
      uastcFixture,
      zstdFixture,
      etc1sFixture,
      'zstd-state',
    ]);
    final etc1s = await Process.run(executable, const <String>[
      uastcFixture,
      zstdFixture,
      etc1sFixture,
      'etc1s-descriptors',
    ]);
    expect(
      zstd.exitCode == 0 && etc1s.exitCode == 0,
      isTrue,
      reason: 'zstd exit=${zstd.exitCode}\n${zstd.stdout}${zstd.stderr}\n'
          'etc1s exit=${etc1s.exitCode}\n${etc1s.stdout}${etc1s.stderr}',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 malformed metadata keeps diagnostics and cleans owners',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_malformed_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_malformed';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const uastcFixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final runs = <String, ProcessResult>{};
    for (final mode in <String>[
      'malformed-level',
      'malformed-dfd',
      'malformed-kvd',
      'animation-precedence',
    ]) {
      runs[mode] = await Process.run(executable, <String>[
        uastcFixture,
        zstdFixture,
        etc1sFixture,
        mode,
      ]);
    }
    final failures = runs.entries
        .where((entry) => entry.value.exitCode != 0)
        .map((entry) => '${entry.key} exit=${entry.value.exitCode}\n'
            '${entry.value.stdout}${entry.value.stderr}')
        .join('\n');
    expect(failures, isEmpty, reason: failures);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 allocation failures budgets and cancellation clean up',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_failures_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_failures';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const uastcFixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final runs = <String, ProcessResult>{};
    for (final mode in <String>[
      'failure-uastc',
      'failure-zstd',
      'failure-etc1s',
    ]) {
      runs[mode] = await Process.run(executable, <String>[
        uastcFixture,
        zstdFixture,
        etc1sFixture,
        mode,
      ]);
    }
    final failures = runs.entries
        .where((entry) => entry.value.exitCode != 0)
        .map((entry) => '${entry.key} exit=${entry.value.exitCode}\n'
            '${entry.value.stdout}${entry.value.stderr}')
        .join('\n');
    expect(failures, isEmpty, reason: failures);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 state reuse and concurrent controls stay isolated',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_reuse_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/basisu_ktx2_reuse';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    const uastcFixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final runs = <String, ProcessResult>{};
    for (final mode in <String>[
      'reuse-default',
      'reuse-explicit',
      'concurrency',
    ]) {
      runs[mode] = await Process.run(executable, <String>[
        uastcFixture,
        zstdFixture,
        etc1sFixture,
        mode,
      ]);
    }
    final failures = runs.entries
        .where((entry) => entry.value.exitCode != 0)
        .map((entry) => '${entry.key} exit=${entry.value.exitCode}\n'
            '${entry.value.stdout}${entry.value.stderr}')
        .join('\n');
    expect(failures, isEmpty, reason: failures);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 cancels between metadata owners with exact cleanup',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('fsv_basisu_ktx2_partial_cancel_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/partial-cancel';
    final compile = await _compileKtx2MetadataRunner(
      executable: executable,
      platform: 'android/src/main/cpp',
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      executable,
      <String>[..._ktx2E2Fixtures, 'partial-metadata-cancel'],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 rejects required malformed metadata with exact cleanup',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_malformed_e2_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/malformed-required';
    final compile = await _compileKtx2MetadataRunner(
      executable: executable,
      platform: 'android/src/main/cpp',
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      executable,
      <String>[..._ktx2E2Fixtures, 'malformed-required'],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU explicit KTX2 state safely outlives successive controls',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_state_life_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/state-outlives-controls';
    final compile = await _compileKtx2MetadataRunner(
      executable: executable,
      platform: 'android/src/main/cpp',
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      executable,
      <String>[..._ktx2E2Fixtures, 'state-outlives-controls'],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU KTX2 relocates more than eight KVD entries without termination',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_kvd_move_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final failures = <String>[];
    for (final noExceptions in <bool>[false, true]) {
      final label = noExceptions ? 'no-exceptions' : 'normal';
      final executable = '${tempDir.path}/kvd-relocation-$label';
      final compile = await _compileKtx2MetadataRunner(
        executable: executable,
        platform: 'android/src/main/cpp',
        transcoderNoExceptions: noExceptions,
      );
      if (compile.exitCode != 0) {
        failures.add('$label compile exit=${compile.exitCode}\n'
            '${compile.stdout}${compile.stderr}');
        continue;
      }
      final run = await Process.run(
        executable,
        <String>[..._ktx2E2Fixtures, 'kvd-relocation'],
      );
      if (run.exitCode != 0) {
        failures.add('$label run exit=${run.exitCode}\n'
            '${run.stdout}${run.stderr}');
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('BasisU ETC1S codec state uses the request allocator', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_etc1s_e3_red_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/etc1s-state';
    final compile = await _compileKtx2MetadataRunner(
      executable: executable,
      platform: 'android/src/main/cpp',
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      executable,
      <String>[..._ktx2E3Etc1sFixtures, 'etc1s-state'],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('etc1s-state-contract-ok'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('BasisU ETC1S failures preserve typed cleanup with no partial output',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_etc1s_e3_fail_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final executable = '${tempDir.path}/etc1s-failures';
    final compile = await _compileKtx2MetadataRunner(
      executable: executable,
      platform: 'android/src/main/cpp',
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final failures = <String>[];
    for (var index = 0; index < _ktx2E3Etc1sFixtures.length; index += 1) {
      final fixture = _ktx2E3Etc1sFixtures[index];
      final mode = index == 2 ? 'failure-etc1s-mips' : 'failure-etc1s';
      final run = await Process.run(
        executable,
        <String>[fixture, fixture, fixture, mode],
      );
      if (run.exitCode != 0) {
        failures
            .add('$fixture exit=${run.exitCode}\n${run.stdout}${run.stderr}');
      } else {
        print('ETC1S FAILURE $fixture: ${run.stdout}'.trim());
      }
    }
    final typed = await Process.run(
      executable,
      <String>[
        _ktx2E3Etc1sFixtures[1],
        _ktx2E3Etc1sFixtures[1],
        _ktx2E3Etc1sFixtures[1],
        'etc1s-codec-failures',
      ],
    );
    if (typed.exitCode != 0) {
      failures
          .add('typed exit=${typed.exitCode}\n${typed.stdout}${typed.stderr}');
    } else {
      print('ETC1S TYPED: ${typed.stdout}'.trim());
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('BasisU ETC1S allocator handoff and owner seams reject mutants',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_etc1s_e3_mutant_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final transcoderHeader = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.h',
    ).readAsString();
    final transcoderSource = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
    ).readAsString();
    final supportFiles = <String>[
      'basisu_containers.h',
      'basisu_containers_impl.h',
      'basisu_transcoder_internal.h',
      'basisu.h',
      'basisu_transcoder_uastc.h',
      'basisu_file_headers.h',
    ];
    final mutations = <({
      String label,
      String header,
      String source,
    })>[
      (
        label: 'etc1s-control-handoff',
        header: transcoderHeader.replaceFirst(
          'm_etc1s_transcoder.set_fsv_transcode_control(control);',
          'm_etc1s_transcoder.set_fsv_transcode_control(nullptr);',
        ),
        source: transcoderSource,
      ),
      (
        label: 'endpoint-persistent-owner',
        header: transcoderHeader.replaceFirst(
          'fsv_rebind_vector(m_local_endpoints, allocator);',
          'fsv_rebind_vector(m_local_endpoints, nullptr);',
        ),
        source: transcoderSource,
      ),
      (
        label: 'selector-history-temporary-owner',
        header: transcoderHeader,
        source: transcoderSource.replaceFirst(
          'approx_move_to_front selector_history_buf(allocator);',
          'approx_move_to_front selector_history_buf(nullptr);',
        ),
      ),
    ];
    final failures = <String>[];
    for (final mutation in mutations) {
      expect(
        mutation.header != transcoderHeader ||
            mutation.source != transcoderSource,
        isTrue,
        reason: '${mutation.label} was not source-different',
      );
      final mutantDir = Directory('${tempDir.path}/${mutation.label}');
      await mutantDir.create();
      await File('${mutantDir.path}/basisu_transcoder.h')
          .writeAsString(mutation.header);
      await File('${mutantDir.path}/basisu_transcoder.cpp')
          .writeAsString(mutation.source);
      for (final name in supportFiles) {
        await File('third_party/basis_universal/transcoder/$name')
            .copy('${mutantDir.path}/$name');
      }
      final executable = '${mutantDir.path}/runner';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O2',
        '-pthread',
        '-DBASISD_SUPPORT_KTX2=1',
        '-DBASISD_SUPPORT_KTX2_ZSTD=1',
        '-I${mutantDir.path}',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        'test/native/basisu_ktx2_metadata_allocator_runner.cc',
        'android/src/main/cpp/fsv_basisu_budget.cc',
        'android/src/main/cpp/fsv_basisu_control.cc',
        'android/src/main/cpp/fsv_basisu_bridge.cc',
        '${mutantDir.path}/basisu_transcoder.cpp',
        'third_party/basis_universal/zstd/zstddeclib.c',
        '-o',
        executable,
      ]);
      if (compile.exitCode != 0) {
        failures.add('${mutation.label} compile exit=${compile.exitCode}\n'
            '${compile.stdout}${compile.stderr}');
        continue;
      }
      final run = await Process.run(
        executable,
        <String>[..._ktx2E3Etc1sFixtures, 'etc1s-state'],
      );
      if (run.exitCode == 0) {
        failures.add('${mutation.label} escaped\n${run.stdout}${run.stderr}');
      }
      print('MUTANT ${mutation.label}: source-diff=true compile-exit=0 '
          'run-exit=${run.exitCode}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('BasisU KTX2 Task 5E.2 gates pass Android and iOS ASan plus UBSan',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_e2_sanitize_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const modes = <String>[
      'metadata',
      'animation',
      'animation-zstd',
      'zstd-state',
      'etc1s-descriptors',
      'malformed-level',
      'malformed-dfd',
      'malformed-kvd',
      'malformed-required',
      'animation-precedence',
      'failure-uastc',
      'failure-zstd',
      'failure-etc1s',
      'reuse-default',
      'reuse-explicit',
      'state-outlives-controls',
      'concurrency',
      'partial-metadata-cancel',
      'kvd-relocation',
    ];
    final failures = <String>[];
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final label = platform.startsWith('android') ? 'android' : 'ios';
      final executable = '${tempDir.path}/$label';
      final compile = await _compileKtx2MetadataRunner(
        executable: executable,
        platform: platform,
        sanitize: true,
      );
      if (compile.exitCode != 0) {
        failures.add('$label compile exit=${compile.exitCode}\n'
            '${compile.stdout}${compile.stderr}');
        continue;
      }
      for (final mode in modes) {
        final run = await Process.run(
          executable,
          <String>[..._ktx2E2Fixtures, mode],
          environment: const <String, String>{
            // LeakSanitizer is unavailable on this macOS host. Exact live-byte,
            // owner, release, and mismatch assertions remain enabled.
            'ASAN_OPTIONS': 'detect_leaks=0:halt_on_error=1',
            'UBSAN_OPTIONS': 'halt_on_error=1',
          },
        );
        if (run.exitCode != 0) {
          failures.add('$label $mode exit=${run.exitCode}\n'
              '${run.stdout}${run.stderr}');
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('BasisU KTX2 metadata owners and animation gate reject mutants',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ktx2_mutants_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final transcoderHeader = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.h',
    ).readAsString();
    final transcoderSource = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
    ).readAsString();
    final containersHeader = await File(
      'third_party/basis_universal/transcoder/basisu_containers.h',
    ).readAsString();
    final transcoderInternal = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder_internal.h',
    ).readAsBytes();
    final basisuHeader = await File(
      'third_party/basis_universal/transcoder/basisu.h',
    ).readAsBytes();
    final uastcHeader = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder_uastc.h',
    ).readAsBytes();
    final fileHeaders = await File(
      'third_party/basis_universal/transcoder/basisu_file_headers.h',
    ).readAsBytes();
    const uastcFixture = 'test/fixtures/ktx2-cts/create/encode_uastc/'
        'output_R8G8B8A8_UNORM.ktx2';
    const zstdFixture = 'test/fixtures/ktx2-cts/deflate/metadata/'
        'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2';
    const etc1sFixture = 'test/fixtures/ktx2-cts/create/encode_blze/'
        'output_R8G8B8A8_UNORM.ktx2';
    final transcoderMutants = <({
      String label,
      String before,
      String after,
      String mode,
    })>[
      (
        label: 'levels-owner',
        before: 'fsv_rebind_vector(m_levels, allocator);',
        after: 'fsv_rebind_vector(m_levels, nullptr);',
        mode: 'metadata',
      ),
      (
        label: 'dfd-owner',
        before: 'fsv_rebind_vector(m_dfd, allocator);',
        after: 'fsv_rebind_vector(m_dfd, nullptr);',
        mode: 'metadata',
      ),
      (
        label: 'outer-kvd-owner',
        before: 'fsv_rebind_vector(m_key_values, allocator);',
        after: 'fsv_rebind_vector(m_key_values, nullptr);',
        mode: 'metadata',
      ),
      (
        label: 'nested-key-owner',
        before: 'm_key(allocator), m_value(allocator)',
        after: 'm_key(nullptr), m_value(allocator)',
        mode: 'metadata',
      ),
      (
        label: 'nested-value-owner',
        before: 'm_key(allocator), m_value(allocator)',
        after: 'm_key(allocator), m_value(nullptr)',
        mode: 'metadata',
      ),
      (
        label: 'etc1s-descriptor-owner',
        before: 'fsv_rebind_vector(m_etc1s_image_descs, allocator);',
        after: 'fsv_rebind_vector(m_etc1s_image_descs, nullptr);',
        mode: 'etc1s-descriptors',
      ),
      (
        label: 'zstd-state-owner',
        before: 'fsv_rebind_vector(m_level_uncomp_data, allocator);',
        after: 'fsv_rebind_vector(m_level_uncomp_data, nullptr);',
        mode: 'zstd-state',
      ),
    ];

    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final bridgeSource =
          await File('$platform/fsv_basisu_bridge.cc').readAsString();
      final animationMutant = bridgeSource.replaceFirst(
        'if (animation_present) {',
        'if (false && animation_present) {',
      );
      expect(animationMutant, isNot(bridgeSource),
          reason: '$platform animation gate mutation was not source-different');
      final mutations = <({
        String label,
        String header,
        String containers,
        String bridge,
        String mode,
      })>[
        for (final mutation in transcoderMutants)
          (
            label: mutation.label,
            header: transcoderHeader.replaceFirst(
              mutation.before,
              mutation.after,
            ),
            containers: containersHeader,
            bridge: bridgeSource,
            mode: mutation.mode,
          ),
        (
          label: 'animation-profile-gate',
          header: transcoderHeader,
          containers: containersHeader,
          bridge: animationMutant,
          mode: 'animation',
        ),
        (
          label: 'kvd-nothrow-relocation',
          header: transcoderHeader,
          containers: containersHeader.replaceFirst(
            'if constexpr (std::is_nothrow_move_constructible<T>::value)\n'
                '\t\t\t\t\tnew ((void*)(pDst + constructed_count)) '
                'T(std::move(pSrc[constructed_count]));',
            'if constexpr (false && '
                'std::is_nothrow_move_constructible<T>::value)\n'
                '\t\t\t\t\tnew ((void*)(pDst + constructed_count)) '
                'T(std::move(pSrc[constructed_count]));',
          ),
          bridge: bridgeSource,
          mode: 'kvd-relocation',
        ),
      ];
      for (final mutation in mutations) {
        if (mutation.label != 'animation-profile-gate' &&
            mutation.label != 'kvd-nothrow-relocation') {
          expect(mutation.header, isNot(transcoderHeader),
              reason:
                  '$platform ${mutation.label} mutation was not source-different');
        }
        if (mutation.label == 'kvd-nothrow-relocation') {
          expect(mutation.containers, isNot(containersHeader),
              reason:
                  '$platform KVD relocation mutation was not source-different');
        }
        final mutantDir = Directory(
          '${tempDir.path}/${platform.startsWith('android') ? 'android' : 'ios'}-${mutation.label}',
        );
        await mutantDir.create();
        final header = File('${mutantDir.path}/basisu_transcoder.h');
        final source = File('${mutantDir.path}/basisu_transcoder.cpp');
        final containers = File('${mutantDir.path}/basisu_containers.h');
        final internal = File('${mutantDir.path}/basisu_transcoder_internal.h');
        final basisu = File('${mutantDir.path}/basisu.h');
        final uastc = File('${mutantDir.path}/basisu_transcoder_uastc.h');
        final headers = File('${mutantDir.path}/basisu_file_headers.h');
        final bridge = File('${mutantDir.path}/fsv_basisu_bridge.cc');
        await header.writeAsString(mutation.header);
        await source.writeAsString(transcoderSource);
        await containers.writeAsString(mutation.containers);
        await internal.writeAsBytes(transcoderInternal);
        await basisu.writeAsBytes(basisuHeader);
        await uastc.writeAsBytes(uastcHeader);
        await headers.writeAsBytes(fileHeaders);
        await bridge.writeAsString(mutation.bridge);
        final executable = '${mutantDir.path}/runner';
        final compile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-O2',
          '-pthread',
          '-DBASISD_SUPPORT_KTX2=1',
          '-DBASISD_SUPPORT_KTX2_ZSTD=1',
          '-I${mutantDir.path}',
          '-I$platform',
          '-Ithird_party/basis_universal/transcoder',
          '-Ithird_party/basis_universal/zstd',
          'test/native/basisu_ktx2_metadata_allocator_runner.cc',
          '$platform/fsv_basisu_budget.cc',
          '$platform/fsv_basisu_control.cc',
          bridge.path,
          source.path,
          'third_party/basis_universal/zstd/zstddeclib.c',
          '-o',
          executable,
        ]);
        expect(compile.exitCode, 0,
            reason: '$platform ${mutation.label}\n'
                '${compile.stdout}\n${compile.stderr}');
        final run = await Process.run(executable, <String>[
          uastcFixture,
          zstdFixture,
          etc1sFixture,
          mutation.mode,
        ]);
        expect(run.exitCode, isNot(0),
            reason: '$platform ${mutation.label} escaped\n'
                '${run.stdout}${run.stderr}');
        print(
          'MUTANT ${platform.startsWith('android') ? 'android' : 'ios'} '
          '${mutation.label}: source-diff=true compile-exit=0 '
          'run-exit=${run.exitCode}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  test('codec control records BasisU Zstd allocation provenance and release',
      () async {
    final provenance = File(
      'third_party/basis_universal/FSV_CODEC_CONTROL_PROVENANCE.sha256',
    );
    expect(await provenance.exists(), isTrue);
    final manifest = await provenance.readAsString();
    expect(
      manifest,
      contains(
        'upstream=BinomialLLC/basis_universal@882abb5320400ab650c1be33f9152e4955e83af3',
      ),
    );
    expect(manifest, contains('transcoder/basisu_transcoder.cpp'));
    expect(manifest, contains('transcoder/basisu_containers.h'));
    expect(manifest, contains('zstd/zstddeclib.c'));
    final entries = RegExp(
      r'^original=[0-9a-f]{64} patched=([0-9a-f]{64}) path=(.+)$',
      multiLine: true,
    ).allMatches(manifest).toList();
    expect(entries, isNotEmpty);
    expect(
      await _verifyCodecControlManifest(
        manifest: provenance,
        sourceRoot: Directory('third_party/basis_universal'),
      ),
      isTrue,
    );
    final mutationRoot =
        await Directory.systemTemp.createTemp('fsv_basisu_hash_mutant_');
    addTearDown(() async {
      if (await mutationRoot.exists()) {
        await mutationRoot.delete(recursive: true);
      }
    });
    for (final entry in entries) {
      final relative = entry.group(2)!;
      final target = File('${mutationRoot.path}/$relative');
      await target.parent.create(recursive: true);
      await File('third_party/basis_universal/$relative').copy(target.path);
    }
    final mutatedSource = File(
      '${mutationRoot.path}/${entries.first.group(2)}',
    );
    await mutatedSource.writeAsString(
      '${await mutatedSource.readAsString()}\n',
    );
    expect(
      await _verifyCodecControlManifest(
        manifest: provenance,
        sourceRoot: mutationRoot,
      ),
      isFalse,
    );

    final header = await File(
      'android/src/main/cpp/fsv_basisu_control.h',
    ).readAsString();
    expect(header, contains('peak_bytes() const'));
    expect(header, contains('allocation_count() const'));
    expect(header, contains('release_count() const'));
    expect(header, contains('reserve_rejection_count() const'));
    expect(header, contains('class FsvScopedWorkingReservation'));

    final transcoderHeader = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.h',
    ).readAsString();
    expect(transcoderHeader, contains('class fsv_transcode_control'));
    expect(transcoderHeader, contains('set_fsv_transcode_control'));
    final transcoder = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
    ).readAsString();
    expect(transcoder, contains('FSV LOCAL MODIFICATION'));
    expect(transcoder, contains('fsv_checkpoint("zstdOutput")'));
    expect(transcoder, contains('fsv_checkpoint("blockRow")'));
    expect(
      transcoderHeader,
      contains('fsv_rebind_vector(m_level_uncomp_data, allocator);'),
    );
    expect(
      transcoder,
      isNot(contains('fsv_try_reserve((size_t)uncomp_size)')),
    );
    expect(transcoder, contains('fsv_state_release_guard'));
    final zstd = await File(
      'third_party/basis_universal/zstd/zstddeclib.c',
    ).readAsString();
    expect(zstd, contains('dctx->fsvCheckpointOpaque'));
    expect(zstd, contains('dctx->fsvProducedBytes += decodedSize;'));
  });

  test('Zstd static DCtx workspace is request-owned and released exactly',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp.createTemp('fsv_zstd_cancel_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final runner = File('${tempDir.path}/zstd_cancel.cc');
    await runner.writeAsString(_zstdCancellationRunner);
    final binary = '${tempDir.path}/zstd_cancel';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      runner.path,
      'android/src/main/cpp/fsv_basisu_control.cc',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      binary,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    for (final mode in <String>[
      'success',
      'failure',
      'cancel',
      'heap-failure',
      'workspace-minus-one',
      'peak-minus-one',
    ]) {
      final run = await Process.run(
        binary,
        <String>[
          'test/fixtures/ktx2-cts/deflate/metadata/'
              'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
          mode,
        ],
      );
      expect(run.exitCode, 0, reason: '$mode\n${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('zstd-$mode-release-ok'));
      print('${run.stdout}');
    }
    final zstdSource = await File(
      'third_party/basis_universal/zstd/zstddeclib.c',
    ).readAsString();
    final mutations =
        <({String label, String before, String after, String mode})>[
      (
        label: 'checkpoint-seam',
        before: 'if (dctx->fsvCheckpoint != NULL &&\n'
            '            !dctx->fsvCheckpoint(dctx->fsvCheckpointOpaque,\n'
            '                                 dctx->fsvProducedBytes)) {\n'
            '            return ERROR(GENERIC);\n'
            '        }',
        after: '(void)dctx->fsvProducedBytes;',
        mode: 'cancel',
      ),
      (
        label: 'static-init-handoff',
        before: 'ZSTD_initStaticDCtx(dctxWorkspace, dctxWorkspaceSize);',
        after: 'ZSTD_initStaticDCtx(dctxWorkspace, '
            'dctxWorkspaceSize - 1);',
        mode: 'success',
      ),
    ];
    for (final mutation in mutations) {
      final source = zstdSource.replaceFirst(mutation.before, mutation.after);
      expect(source, isNot(zstdSource), reason: mutation.label);
      final mutantSource = File('${tempDir.path}/${mutation.label}.c');
      await mutantSource.writeAsString(source);
      final mutantBinary = '${tempDir.path}/${mutation.label}';
      final mutantCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        runner.path,
        'android/src/main/cpp/fsv_basisu_control.cc',
        mutantSource.path,
        '-o',
        mutantBinary,
      ]);
      expect(mutantCompile.exitCode, 0,
          reason: '${mutation.label}\n'
              '${mutantCompile.stdout}\n${mutantCompile.stderr}');
      final mutantRun = await Process.run(
        mutantBinary,
        <String>[
          'test/fixtures/ktx2-cts/deflate/metadata/'
              'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
          mutation.mode,
        ],
      );
      expect(mutantRun.exitCode, isNot(0),
          reason: '${mutation.label} mutation escaped the executable runner');
      print('${mutation.label}: source-diff=true compile-exit=0 '
          'run-exit=${mutantRun.exitCode}');
    }

    final transcoderSource = await File(
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
    ).readAsString();
    final releaseMutant = transcoderSource.replaceFirst(
      'dctx_allocation, dctx_workspace, dctx_workspace_size,\n'
          '\t\t\t\t\tdctx_alignment))',
      'dctx_allocation, dctx_workspace, dctx_workspace_size - 1,\n'
          '\t\t\t\t\tdctx_alignment))',
    );
    expect(releaseMutant, isNot(transcoderSource),
        reason: 'exact-release mutation was not source-different');
    final releaseSource = File('${tempDir.path}/release-mutant.cpp');
    await releaseSource.writeAsString(releaseMutant);
    final releaseBinary = '${tempDir.path}/release-mutant';
    final releaseCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O2',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_ktx2_metadata_allocator_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      releaseSource.path,
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      releaseBinary,
    ]);
    expect(releaseCompile.exitCode, 0,
        reason: 'exact-release\n'
            '${releaseCompile.stdout}\n${releaseCompile.stderr}');
    final releaseRun = await Process.run(releaseBinary, const <String>[
      'test/fixtures/ktx2-cts/create/encode_uastc/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
      'test/fixtures/ktx2-cts/create/encode_blze/'
          'output_R8G8B8A8_UNORM.ktx2',
      'zstd-state',
    ]);
    expect(releaseRun.exitCode, isNot(0),
        reason: 'exact-release mutation escaped the production-linked runner');
    print('exact-release: source-diff=true compile-exit=0 '
        'run-exit=${releaseRun.exitCode}');
  });

  test('native codec failures preserve typed diagnostics and release bytes',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp.createTemp('fsv_basisu_typed_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final runner = File('${tempDir.path}/basisu_typed.cc');
    await runner.writeAsString(_basisuTypedDiagnosticRunner);
    final binary = '${tempDir.path}/basisu_typed';
    Future<ProcessResult> compileTypedRunner({
      required String output,
      required String transcoderSource,
      String? firstInclude,
    }) {
      return Process.run('clang++', <String>[
        '-std=c++17',
        '-O2',
        '-DBASISD_SUPPORT_KTX2=1',
        '-DBASISD_SUPPORT_KTX2_ZSTD=1',
        if (firstInclude != null) '-I$firstInclude',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        runner.path,
        'android/src/main/cpp/fsv_basisu_budget.cc',
        'android/src/main/cpp/fsv_basisu_control.cc',
        'android/src/main/cpp/fsv_basisu_bridge.cc',
        transcoderSource,
        'third_party/basis_universal/zstd/zstddeclib.c',
        '-o',
        output,
      ]);
    }

    const transcoderPath =
        'third_party/basis_universal/transcoder/basisu_transcoder.cpp';
    final compile = await compileTypedRunner(
      output: binary,
      transcoderSource: transcoderPath,
    );
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(
      binary,
      const <String>[
        'test/fixtures/ktx2-cts/deflate/metadata/'
            'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
      ],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('basisu-typed-diagnostics-ok'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('platform handlers own bounded request registries and detach drains',
      () async {
    final android = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FlutterSceneViewerBasisuPlugin.java',
    ).readAsString();
    final androidRegistry = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FsvDecodeRequestRegistry.java',
    ).readAsString();
    final ios = await File(
      'ios/Classes/FlutterSceneViewerBasisuPlugin.mm',
    ).readAsString();
    final jni = await File(
      'android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
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
    expect(ios, contains('fsv_basisu::FsvDecodeRequestRegistry'));
    expect(ios, contains('detachFromEngineForRegistrar'));
    expect(ios, contains('dispatch_sync(_decodeQueue'));
    expect(ios, contains('_requestRegistry->DrainAfterWorkers()'));
    expect(ios, contains('kMethodCancelDecode'));
    expect(jni, contains('nativeCreateDecodeControl'));
    expect(jni, contains('nativeCancelDecodeControl'));
    expect(jni, contains('control_handle'));
    expect(cmake, contains('fsv_basisu_control.cc'));
  });

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
      'android/src/main/cpp/fsv_basisu_control.cc',
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
      'android/src/main/cpp/fsv_basisu_control.cc',
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

  test('native bridge preserves official ETC1S and UASTC mip pyramids',
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
      'android/src/main/cpp/fsv_basisu_control.cc',
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
      <String>[...fixtures, tempDir.path],
    );
    expect(
      run.exitCode,
      0,
      reason: '${run.stdout}\n${run.stderr}',
    );
    expect('${run.stdout}', contains('basisu-mip-chain-ok cases=2 levels=4'));
    final actualHashes = <String>[];
    for (var index = 0; index < _basisuMipLevelSha256.length; index += 1) {
      final hash = await Process.run(
        'shasum',
        <String>['-a', '256', '${tempDir.path}/mip-$index.rgba'],
      );
      expect(hash.exitCode, 0, reason: '${hash.stdout}\n${hash.stderr}');
      actualHashes.add(
        (hash.stdout as String).split(RegExp(r'\s+')).first,
      );
    }
    expect(actualHashes, _basisuMipLevelSha256);
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
        '-Ithird_party/basis_universal/transcoder',
        runner.path,
        '$platform/fsv_basisu_budget.cc',
        '$platform/fsv_basisu_control.cc',
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
      (
        'android/src/main/cpp/fsv_basisu_control.h',
        'ios/Classes/fsv_basisu_control.h',
      ),
      (
        'android/src/main/cpp/fsv_basisu_control.cc',
        'ios/Classes/fsv_basisu_control.cc',
      ),
      (
        'android/src/main/cpp/fsv_basisu_owned.h',
        'ios/Classes/fsv_basisu_owned.h',
      ),
      (
        'android/src/main/cpp/fsv_basisu_platform_serialization.h',
        'ios/Classes/fsv_basisu_platform_serialization.h',
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

  test('native bridge writes official KTX2 fixture raw RGBA bytes', () async {
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
      'android/src/main/cpp/fsv_basisu_control.cc',
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
        '${tempDir.path}/basisu.rgba',
      ],
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('rgba=1024 width=16 height=16'));
    expect(
      await File('${tempDir.path}/basisu.rgba').length(),
      1024,
    );
    final rgbaHash = await Process.run(
      'shasum',
      <String>['-a', '256', '${tempDir.path}/basisu.rgba'],
    );
    expect(
      rgbaHash.exitCode,
      0,
      reason: '${rgbaHash.stdout}\n${rgbaHash.stderr}',
    );
    expect(
      (rgbaHash.stdout as String).split(RegExp(r'\s+')).first,
      _basisuRgbaSha256,
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
      '-Ithird_party/basis_universal/transcoder',
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

  test('Android JNI platform copy is charged cancellable and exception-safe',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_jni_copy_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    for (final variant in <({String name, List<String> flags})>[
      (name: 'default', flags: const <String>[]),
      (
        name: 'sanitized',
        flags: const <String>[
          '-fsanitize=address,undefined',
          '-fno-omit-frame-pointer',
        ],
      ),
      (name: 'no-exceptions', flags: const <String>['-fno-exceptions']),
    ]) {
      final executable = '${tempDir.path}/jni_platform_copy_${variant.name}';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        ...variant.flags,
        '-I${tempDir.path}',
        '-Iandroid/src/main/cpp',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        'test/native/basisu_jni_platform_copy_runner.cc',
        'android/src/main/cpp/fsv_basisu_budget.cc',
        'android/src/main/cpp/fsv_basisu_control.cc',
        'android/src/main/cpp/fsv_basisu_bridge.cc',
        'ios/Classes/fsv_basisu_vendor_sources.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '${variant.name}\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(
        executable,
        const <String>[],
        environment: variant.name == 'sanitized'
            ? const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'}
            : null,
      );
      expect(run.exitCode, 0,
          reason: '${variant.name}\n${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('basisu_jni_platform_copy_cases=11'));
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('Android rejects an invalid native control before registry or decode',
      () async {
    final javac = await Process.run('javac', const <String>['-version']);
    final java = await Process.run('java', const <String>['-version']);
    if (javac.exitCode != 0 || java.exitCode != 0) {
      markTestSkipped('javac and java are required.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_control_create_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final javaStubs = Directory('test/java_stubs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.java'))
        .map((file) => file.path)
        .toList();
    final compile = await Process.run('javac', <String>[
      '-d',
      tempDir.path,
      ...javaStubs,
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
          'FsvDecodeRequestRegistry.java',
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
          'FlutterSceneViewerBasisuPlugin.java',
      'test/native/basisu_android_control_creation_runner.java',
      'test/native/basisu_android_plugin_control_failure_runner.java',
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run('java', <String>[
      '-cp',
      tempDir.path,
      'com.marlonjd.flutter_scene_viewer_basisu.'
          'BasisuAndroidControlCreationRunner',
    ]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    final pluginRun = await Process.run('java', <String>[
      '-cp',
      tempDir.path,
      'com.marlonjd.flutter_scene_viewer_basisu.'
          'BasisuAndroidPluginControlFailureRunner',
    ]);
    expect(pluginRun.exitCode, 0,
        reason: '${pluginRun.stdout}\n${pluginRun.stderr}');
    expect('${pluginRun.stdout}', contains('callbacks=1 native-entered=0'));

    final plugin = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FlutterSceneViewerBasisuPlugin.java',
    ).readAsString();
    final validity = plugin.indexOf('if (!request.isValid())');
    final registration = plugin.indexOf('requestRegistry.register(');
    expect(validity, greaterThanOrEqualTo(0));
    expect(registration, greaterThan(validity));
    expect(plugin, contains('nativeControlUnavailable'));
  });

  test(
      'iOS converts control allocation failure into atomic registration failure',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_ios_control_create_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    for (final variant in <({String name, List<String> flags})>[
      (name: 'default', flags: const <String>[]),
      (
        name: 'sanitized',
        flags: const <String>[
          '-fsanitize=address,undefined',
          '-fno-omit-frame-pointer',
        ],
      ),
    ]) {
      final executable = '${tempDir.path}/control_creation_${variant.name}';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        ...variant.flags,
        '-Iios/Classes',
        '-Ithird_party/basis_universal/transcoder',
        'test/native/basisu_ios_control_creation_runner.cc',
        'ios/Classes/fsv_basisu_control.cc',
        'ios/Classes/fsv_basisu_request_registry.cc',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '${variant.name}\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(
        executable,
        const <String>[],
        environment: variant.name == 'sanitized'
            ? const <String, String>{'ASAN_OPTIONS': 'detect_leaks=0'}
            : null,
      );
      expect(run.exitCode, 0,
          reason: '${variant.name}\n${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('ordinals=4 fresh=success'));
    }

    final plugin = await File(
      'ios/Classes/FlutterSceneViewerBasisuPlugin.mm',
    ).readAsString();
    expect(plugin, contains('FsvRegisterFailure::kControlCreationFailed'));
    expect(plugin, contains('@"nativeControlUnavailable"'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('compiled control-creation guard mutants fail atomically', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_control_mutants_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final javaRegistry = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FsvDecodeRequestRegistry.java',
    ).readAsString();
    final javaMutant = javaRegistry.replaceFirst(
      'if (control == null || !control.isValid() || detached ||\n'
          '        active.containsKey(requestId)) {',
      'if (detached || active.containsKey(requestId)) {',
    );
    expect(javaMutant, isNot(javaRegistry));
    final javaPackage = Directory(
      '${tempDir.path}/java/com/marlonjd/flutter_scene_viewer_basisu',
    );
    await javaPackage.create(recursive: true);
    final javaMutantFile = File(
      '${javaPackage.path}/FsvDecodeRequestRegistry.java',
    );
    await javaMutantFile.writeAsString(javaMutant);
    final javaCompile = await Process.run('javac', <String>[
      '-d',
      '${tempDir.path}/java-out',
      javaMutantFile.path,
      'test/native/basisu_android_control_creation_runner.java',
    ]);
    expect(javaCompile.exitCode, 0,
        reason: '${javaCompile.stdout}\n${javaCompile.stderr}');
    final javaRun = await Process.run('java', <String>[
      '-cp',
      '${tempDir.path}/java-out',
      'com.marlonjd.flutter_scene_viewer_basisu.'
          'BasisuAndroidControlCreationRunner',
    ]);
    expect(javaRun.exitCode, 160,
        reason: 'Android invalid-control registry mutant escaped');

    final pluginSource = await File(
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
      'FlutterSceneViewerBasisuPlugin.java',
    ).readAsString();
    final pluginMutant = pluginSource.replaceFirst(
      '    if (!request.isValid()) {\n'
          '      result.error(\n'
          '          "nativeControlUnavailable",\n'
          '          "Native BasisU decode control allocation failed.",\n'
          '          null);\n'
          '      return;\n'
          '    }\n',
      '',
    );
    expect(pluginMutant, isNot(pluginSource));
    final pluginPackage = Directory(
      '${tempDir.path}/plugin/com/marlonjd/flutter_scene_viewer_basisu',
    );
    await pluginPackage.create(recursive: true);
    final pluginMutantFile =
        File('${pluginPackage.path}/FlutterSceneViewerBasisuPlugin.java');
    await pluginMutantFile.writeAsString(pluginMutant);
    final javaStubs = Directory('test/java_stubs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.java'))
        .map((file) => file.path)
        .toList();
    final pluginCompile = await Process.run('javac', <String>[
      '-d',
      '${tempDir.path}/plugin-out',
      ...javaStubs,
      'android/src/main/java/com/marlonjd/flutter_scene_viewer_basisu/'
          'FsvDecodeRequestRegistry.java',
      pluginMutantFile.path,
      'test/native/basisu_android_plugin_control_failure_runner.java',
    ]);
    expect(pluginCompile.exitCode, 0,
        reason: '${pluginCompile.stdout}\n${pluginCompile.stderr}');
    final pluginRun = await Process.run('java', <String>[
      '-cp',
      '${tempDir.path}/plugin-out',
      'com.marlonjd.flutter_scene_viewer_basisu.'
          'BasisuAndroidPluginControlFailureRunner',
    ]);
    expect(pluginRun.exitCode, 160,
        reason: 'Android typed pre-registration guard mutant escaped');

    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    final jniSource = await File(
      'android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
    ).readAsString();
    final jniMutant = jniSource.replaceFirst(
      'if (control == nullptr) return nullptr;',
      '(void)control;',
    );
    expect(jniMutant, isNot(jniSource));
    final jniMutantFile = File('${tempDir.path}/jni_control_mutant.cc');
    await jniMutantFile.writeAsString(jniMutant);
    final jniRunnerSource = await File(
      'test/native/basisu_jni_platform_copy_runner.cc',
    ).readAsString();
    final jniRunner = File('${tempDir.path}/jni_control_mutant_runner.cc');
    await jniRunner.writeAsString(
      jniRunnerSource.replaceFirst(
        '#include "../../android/src/main/cpp/'
            'flutter_scene_viewer_basisu_jni.cc"',
        '#include "${jniMutantFile.path}"',
      ),
    );
    final jniExecutable = '${tempDir.path}/jni_control_mutant';
    final jniCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O1',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      jniRunner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'ios/Classes/fsv_basisu_vendor_sources.cc',
      '-o',
      jniExecutable,
    ]);
    expect(jniCompile.exitCode, 0,
        reason: '${jniCompile.stdout}\n${jniCompile.stderr}');
    final jniRun = await Process.run(jniExecutable, const <String>[]);
    expect(jniRun.exitCode, -11,
        reason: 'JNI null-control guard mutant escaped');

    final iosHeader = await File(
      'ios/Classes/fsv_basisu_request_registry.h',
    ).readAsString();
    final iosSource = await File(
      'ios/Classes/fsv_basisu_request_registry.cc',
    ).readAsString();
    final iosMutantHeader = iosHeader.replaceFirst(
      'FsvRegisterFailure* failure = nullptr) noexcept;',
      'FsvRegisterFailure* failure = nullptr);',
    );
    final iosMutantSource = iosSource
        .replaceFirst(
          'FsvRegisterFailure* failure) noexcept {',
          'FsvRegisterFailure* failure) {',
        )
        .replaceFirst(
          '} catch (const std::bad_alloc&) {\n'
              '    if (failure != nullptr) {\n'
              '      *failure = FsvRegisterFailure::kControlCreationFailed;\n'
              '    }\n'
              '    return nullptr;\n'
              '  }',
          '} catch (const std::bad_alloc&) {\n'
              '    throw;\n'
              '  }',
        );
    expect(iosMutantHeader, isNot(iosHeader));
    expect(iosMutantSource, isNot(iosSource));
    final iosInclude = Directory('${tempDir.path}/ios-mutant');
    await iosInclude.create(recursive: true);
    await File('${iosInclude.path}/fsv_basisu_request_registry.h')
        .writeAsString(iosMutantHeader);
    await File('${iosInclude.path}/fsv_basisu_request_registry.cc')
        .writeAsString(iosMutantSource);
    final iosExecutable = '${tempDir.path}/ios_control_mutant';
    final iosCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-I${iosInclude.path}',
      '-Iios/Classes',
      '-Ithird_party/basis_universal/transcoder',
      'test/native/basisu_ios_control_creation_runner.cc',
      'ios/Classes/fsv_basisu_control.cc',
      '${iosInclude.path}/fsv_basisu_request_registry.cc',
      '-o',
      iosExecutable,
    ]);
    expect(iosCompile.exitCode, 0,
        reason: '${iosCompile.stdout}\n${iosCompile.stderr}');
    final iosRun = await Process.run(iosExecutable, const <String>[]);
    expect(iosRun.exitCode, 160,
        reason: 'iOS registration allocation catch mutant escaped');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('bridge and platform lifetimes stay request-owned across both mirrors',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_lifetimes_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const fixtures = <String>[
      'test/fixtures/ktx2-cts/create/encode_blze/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/create/encode_uastc/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
    ];
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final suffix = platform.startsWith('android') ? 'android' : 'ios';
      final bridgeExecutable = '${tempDir.path}/bridge_$suffix';
      final bridgeCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        '-DNDEBUG',
        '-pthread',
        '-DBASISD_SUPPORT_KTX2=1',
        '-DBASISD_SUPPORT_KTX2_ZSTD=1',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        'test/native/basisu_bridge_platform_lifetime_runner.cc',
        '$platform/fsv_basisu_budget.cc',
        '$platform/fsv_basisu_control.cc',
        '$platform/fsv_basisu_bridge.cc',
        'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
        'third_party/basis_universal/zstd/zstddeclib.c',
        '-o',
        bridgeExecutable,
      ]);
      expect(bridgeCompile.exitCode, 0,
          reason:
              '$platform\n${bridgeCompile.stdout}\n${bridgeCompile.stderr}');
      final bridgeRun = await Process.run(bridgeExecutable, fixtures);
      expect(bridgeRun.exitCode, 0,
          reason: '$platform\n${bridgeRun.stdout}\n${bridgeRun.stderr}');
      expect(
        '${bridgeRun.stdout}',
        contains('bridge-failure-ordinals=136 concurrency=2 fresh=green'),
      );

      final copyExecutable = '${tempDir.path}/copy_$suffix';
      final copyCompile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        'test/native/basisu_platform_serialization_runner.cc',
        '$platform/fsv_basisu_control.cc',
        '-o',
        copyExecutable,
      ]);
      expect(copyCompile.exitCode, 0,
          reason: '$platform\n${copyCompile.stdout}\n${copyCompile.stderr}');
      final copyRun = await Process.run(copyExecutable, const <String>[]);
      expect(copyRun.exitCode, 0,
          reason: '$platform\n${copyRun.stdout}\n${copyRun.stderr}');
      expect('${copyRun.stdout}', contains('platforms=2 atomic/charge'));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('outer envelope is absent and direct request accounting is exact',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_exact_accounting_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const fixtures = <String>[
      'test/fixtures/ktx2-cts/create/encode_blze/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/create/encode_uastc/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
    ];
    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final suffix = platform.startsWith('android') ? 'android' : 'ios';
      final executable = '${tempDir.path}/exact_$suffix';
      final compile = await Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        '-DNDEBUG',
        '-pthread',
        '-DBASISD_SUPPORT_KTX2=1',
        '-DBASISD_SUPPORT_KTX2_ZSTD=1',
        '-I$platform',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        'test/native/basisu_outer_envelope_accounting_runner.cc',
        '$platform/fsv_basisu_budget.cc',
        '$platform/fsv_basisu_control.cc',
        '$platform/fsv_basisu_bridge.cc',
        'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
        'third_party/basis_universal/zstd/zstddeclib.c',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0,
          reason: '$platform\n${compile.stdout}\n${compile.stderr}');
      final run = await Process.run(executable, fixtures);
      expect(run.exitCode, 0,
          reason: '$platform\n${run.stdout}\n${run.stderr}');
      expect('${run.stdout}', contains('basisu-exact-accounting'));
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('compiled exact-accounting mutants reject envelope and charge bypasses',
      () async {
    final clang = await Process.run('clang++', const <String>['--version']);
    if (clang.exitCode != 0) {
      markTestSkipped('clang++ is not available on this machine.');
      return;
    }
    final tempDir = await Directory.systemTemp
        .createTemp('fsv_basisu_exact_accounting_mutants_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    const fixtures = <String>[
      'test/fixtures/ktx2-cts/create/encode_blze/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/create/encode_uastc/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
    ];

    for (final platform in <String>['android/src/main/cpp', 'ios/Classes']) {
      final suffix = platform.startsWith('android') ? 'android' : 'ios';
      final bridgeSource =
          await File('$platform/fsv_basisu_bridge.cc').readAsString();
      final outerMutant = bridgeSource.replaceFirst(
        '  BasisuCodecControlAdapter codec_control(control, testing_hooks);',
        '  fsv_basisu::FsvScopedWorkingReservation retained_output_reservation(\n'
            '      control, preflight.retained_rgba_bytes);\n'
            '  if (!retained_output_reservation.ok()) {\n'
            '    FsvBasisuRecordTerminalOutcome(&result, control);\n'
            '    return result;\n'
            '  }\n'
            '  BasisuCodecControlAdapter codec_control(control, testing_hooks);',
      );
      expect(outerMutant, isNot(bridgeSource));

      final bypassBridge = bridgeSource.replaceFirst(
        'FsvBasisuAllocator<uint8_t>(control));',
        'FsvBasisuAllocator<uint8_t>(nullptr));',
      );
      final budgetSource =
          await File('$platform/fsv_basisu_budget.h').readAsString();
      final bypassBudget = budgetSource.replaceFirst(
        'bytes(FsvBasisuAllocator<uint8_t>(control)),',
        'bytes(FsvBasisuAllocator<uint8_t>(nullptr)),',
      );
      expect(bypassBridge, isNot(bridgeSource));
      expect(bypassBudget, isNot(budgetSource));

      for (final mutation in <({String label, String bridge, String? budget})>[
        (label: 'outer-envelope', bridge: outerMutant, budget: null),
        (
          label: 'result-input-charge-bypass',
          bridge: bypassBridge,
          budget: bypassBudget,
        ),
      ]) {
        final mutantDirectory =
            Directory('${tempDir.path}/$suffix-${mutation.label}');
        await mutantDirectory.create(recursive: true);
        final mutantBridge = File('${mutantDirectory.path}/bridge.cc');
        await mutantBridge.writeAsString(mutation.bridge);
        final includeArguments = <String>[];
        if (mutation.budget != null) {
          await File('${mutantDirectory.path}/fsv_basisu_budget.h')
              .writeAsString(mutation.budget!);
          await File('$platform/fsv_basisu_bridge.h')
              .copy('${mutantDirectory.path}/fsv_basisu_bridge.h');
          includeArguments.add('-I${mutantDirectory.path}');
        }
        final executable = '${mutantDirectory.path}/runner';
        final compile = await Process.run('clang++', <String>[
          '-std=c++17',
          '-O1',
          '-DNDEBUG',
          '-pthread',
          '-DBASISD_SUPPORT_KTX2=1',
          '-DBASISD_SUPPORT_KTX2_ZSTD=1',
          ...includeArguments,
          '-I$platform',
          '-Ithird_party/basis_universal/transcoder',
          '-Ithird_party/basis_universal/zstd',
          'test/native/basisu_outer_envelope_accounting_runner.cc',
          '$platform/fsv_basisu_budget.cc',
          '$platform/fsv_basisu_control.cc',
          mutantBridge.path,
          'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
          'third_party/basis_universal/zstd/zstddeclib.c',
          '-o',
          executable,
        ]);
        expect(compile.exitCode, 0,
            reason:
                '$platform ${mutation.label}\n${compile.stdout}\n${compile.stderr}');
        final run = await Process.run(executable, fixtures);
        expect(run.exitCode, isNot(0),
            reason: '$platform ${mutation.label} mutation escaped');
        print('$suffix ${mutation.label}: source-diff=true compile-exit=0 '
            'run-exit=${run.exitCode}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('iOS managed copy stays charged and delivers atomically', () async {
    final xcrun = await Process.run(
      'xcrun',
      const <String>['--sdk', 'macosx', '--show-sdk-path'],
    );
    if (xcrun.exitCode != 0) {
      markTestSkipped('The macOS SDK is unavailable.');
      return;
    }
    final tempDir =
        await Directory.systemTemp.createTemp('fsv_basisu_objc_copy_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final flutterDirectory = Directory('${tempDir.path}/Flutter');
    await flutterDirectory.create(recursive: true);
    await File('${flutterDirectory.path}/Flutter.h')
        .writeAsString(_fakeFlutterHeader);
    final executable = '${tempDir.path}/objc_delivery';
    final compile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O1',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-x',
      'objective-c++',
      '-fobjc-arc',
      '-fobjc-runtime=macosx-10.13',
      '-fblocks',
      '-isysroot',
      '${xcrun.stdout}'.trim(),
      '-I${tempDir.path}',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      '-Iios/Classes',
      'test/native/basisu_objc_delivery_runner.mm',
      'ios/Classes/fsv_basisu_budget.cc',
      'ios/Classes/fsv_basisu_control.cc',
      'ios/Classes/fsv_basisu_bridge.cc',
      'ios/Classes/fsv_basisu_request_registry.cc',
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-framework',
      'Foundation',
      '-o',
      executable,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
    final run = await Process.run(executable, const <String>[]);
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stderr}', contains('basisu_objc_delivery_cases=8'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('compiled lifetime mutants fail the focused bridge and platform gates',
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
        await Directory.systemTemp.createTemp('fsv_basisu_lifetime_mutants_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    await File('${tempDir.path}/jni.h').writeAsString(_fakeJniHeader);
    final flutterDirectory = Directory('${tempDir.path}/Flutter');
    await flutterDirectory.create(recursive: true);
    await File('${flutterDirectory.path}/Flutter.h')
        .writeAsString(_fakeFlutterHeader);

    const fixtures = <String>[
      'test/fixtures/ktx2-cts/create/encode_blze/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/create/encode_uastc/'
          'output_R8G8B8A8_UNORM.ktx2',
      'test/fixtures/ktx2-cts/deflate/metadata/'
          'output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2',
    ];

    final bridgeSource = await File(
      'android/src/main/cpp/fsv_basisu_bridge.cc',
    ).readAsString();
    final bridgeMutant = bridgeSource
        .replaceFirst(
          'FsvBasisuTranscodeResult result(control);',
          'FsvBasisuTranscodeResult result(nullptr);',
        )
        .replaceFirst(
          'FsvBasisuDecodedImage decoded_image(control);',
          'FsvBasisuDecodedImage decoded_image(nullptr);',
        )
        .replaceFirst(
          'FsvBasisuAllocator<uint8_t>(control));',
          'FsvBasisuAllocator<uint8_t>(nullptr));',
        )
        .replaceFirst(
          'expected.level, expected.width, expected.height, std::move(rgba),\n'
              '            control));',
          'expected.level, expected.width, expected.height, std::move(rgba),\n'
              '            nullptr));',
        );
    expect(bridgeMutant, isNot(bridgeSource));
    final bridgeMutantFile = File('${tempDir.path}/bridge_mutant.cc');
    await bridgeMutantFile.writeAsString(bridgeMutant);
    final bridgeExecutable = '${tempDir.path}/bridge_mutant';
    final bridgeCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O1',
      '-DNDEBUG',
      '-pthread',
      '-DBASISD_SUPPORT_KTX2=1',
      '-DBASISD_SUPPORT_KTX2_ZSTD=1',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      'test/native/basisu_bridge_platform_lifetime_runner.cc',
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      bridgeMutantFile.path,
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
      'third_party/basis_universal/zstd/zstddeclib.c',
      '-o',
      bridgeExecutable,
    ]);
    expect(bridgeCompile.exitCode, 0,
        reason: '${bridgeCompile.stdout}\n${bridgeCompile.stderr}');
    final bridgeRun = await Process.run(bridgeExecutable, fixtures);
    expect(bridgeRun.exitCode, 160, reason: 'result-ownership mutant escaped');

    final jniSource = await File(
      'android/src/main/cpp/flutter_scene_viewer_basisu_jni.cc',
    ).readAsString();
    final jniMutant = jniSource.replaceFirst(
      'if (value_ != nullptr) env_->DeleteLocalRef(value_);',
      'if (value_ != nullptr) (void)value_;',
    );
    expect(jniMutant, isNot(jniSource));
    final jniMutantFile = File('${tempDir.path}/jni_mutant.cc');
    await jniMutantFile.writeAsString(jniMutant);
    final jniRunnerSource = await File(
      'test/native/basisu_jni_platform_copy_runner.cc',
    ).readAsString();
    final jniRunner = File('${tempDir.path}/jni_mutant_runner.cc');
    await jniRunner.writeAsString(
      jniRunnerSource.replaceFirst(
        '#include "../../android/src/main/cpp/'
            'flutter_scene_viewer_basisu_jni.cc"',
        '#include "${jniMutantFile.path}"',
      ),
    );
    final jniExecutable = '${tempDir.path}/jni_mutant';
    final jniCompile = await Process.run('clang++', <String>[
      '-std=c++17',
      '-O1',
      '-I${tempDir.path}',
      '-Iandroid/src/main/cpp',
      '-Ithird_party/basis_universal/transcoder',
      '-Ithird_party/basis_universal/zstd',
      jniRunner.path,
      'android/src/main/cpp/fsv_basisu_budget.cc',
      'android/src/main/cpp/fsv_basisu_control.cc',
      'android/src/main/cpp/fsv_basisu_bridge.cc',
      'ios/Classes/fsv_basisu_vendor_sources.cc',
      '-o',
      jniExecutable,
    ]);
    expect(jniCompile.exitCode, 0,
        reason: '${jniCompile.stdout}\n${jniCompile.stderr}');
    final jniRun = await Process.run(jniExecutable, const <String>[]);
    expect(jniRun.exitCode, 173, reason: 'JNI local-reference mutant escaped');

    Future<ProcessResult> compileObjc(File runner, String output) {
      return Process.run('clang++', <String>[
        '-std=c++17',
        '-O1',
        '-DBASISD_SUPPORT_KTX2=1',
        '-DBASISD_SUPPORT_KTX2_ZSTD=1',
        '-x',
        'objective-c++',
        '-fobjc-arc',
        '-fobjc-runtime=macosx-10.13',
        '-fblocks',
        '-isysroot',
        '${xcrun.stdout}'.trim(),
        '-I${tempDir.path}',
        '-Ithird_party/basis_universal/transcoder',
        '-Ithird_party/basis_universal/zstd',
        '-Iios/Classes',
        runner.path,
        'ios/Classes/fsv_basisu_budget.cc',
        'ios/Classes/fsv_basisu_control.cc',
        'ios/Classes/fsv_basisu_bridge.cc',
        'ios/Classes/fsv_basisu_request_registry.cc',
        'third_party/basis_universal/transcoder/basisu_transcoder.cpp',
        'third_party/basis_universal/zstd/zstddeclib.c',
        '-framework',
        'Foundation',
        '-o',
        output,
      ]);
    }

    final objcRunnerSource = await File(
      'test/native/basisu_objc_delivery_runner.mm',
    ).readAsString();
    final releaseMutant = objcRunnerSource.replaceFirst(
      'response = BuildManagedDecodeResponse(\n'
          '        diagnostics, native_result, nil, request->control.get());',
      'native_result.Reset();\n'
          '    response = BuildManagedDecodeResponse(\n'
          '        diagnostics, native_result, nil, request->control.get());',
    );
    expect(releaseMutant, isNot(objcRunnerSource));
    final releaseRunner = File('${tempDir.path}/objc_release_mutant.mm');
    await releaseRunner.writeAsString(releaseMutant);
    final releaseExecutable = '${tempDir.path}/objc_release_mutant';
    final releaseCompile = await compileObjc(releaseRunner, releaseExecutable);
    expect(releaseCompile.exitCode, 0,
        reason: '${releaseCompile.stdout}\n${releaseCompile.stderr}');
    final releaseRun = await Process.run(releaseExecutable, const <String>[]);
    expect(releaseRun.exitCode, 1,
        reason: 'Objective-C++ copy-before-release mutant escaped');

    final objcPluginSource = await File(
      'ios/Classes/FlutterSceneViewerBasisuPlugin.mm',
    ).readAsString();
    final atomicMutant = objcPluginSource.replaceFirst(
      'if (outcome != FsvBasisuPlatformCopyOutcome::kSuccess || rgba == nil) {\n'
          '          return nil;\n'
          '        }',
      'if (outcome != FsvBasisuPlatformCopyOutcome::kSuccess || rgba == nil) {\n'
          '          return @{ @"decodedImages" : decodedImages, '
          '@"diagnostics" : diagnostics };\n'
          '        }',
    );
    expect(atomicMutant, isNot(objcPluginSource));
    final atomicPlugin = File('${tempDir.path}/objc_atomic_plugin.mm');
    await atomicPlugin.writeAsString(atomicMutant);
    final atomicRunner = File('${tempDir.path}/objc_atomic_mutant.mm');
    await atomicRunner.writeAsString(
      objcRunnerSource.replaceFirst(
        '#include "../../ios/Classes/FlutterSceneViewerBasisuPlugin.mm"',
        '#include "${atomicPlugin.path}"',
      ),
    );
    final atomicExecutable = '${tempDir.path}/objc_atomic_mutant';
    final atomicCompile = await compileObjc(atomicRunner, atomicExecutable);
    expect(atomicCompile.exitCode, 0,
        reason: '${atomicCompile.stdout}\n${atomicCompile.stderr}');
    final atomicRun = await Process.run(atomicExecutable, const <String>[]);
    expect(atomicRun.exitCode, 1,
        reason: 'Objective-C++ partial-response mutant escaped');
  }, timeout: const Timeout(Duration(minutes: 5)));

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
    final itemMapCheck = jni.indexOf(
      'env->IsInstanceOf(image.get(),',
      requestParser,
    );
    final firstItemMapGet = jni.indexOf('MapGet(env, image', requestParser);
    final byteArrayCheck = jni.indexOf('FindClass(env, "[B")');
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
    expect(jni, contains('MapGet(env, image.get(), "usageRole")'));
    expect(jni, contains('StringFromValue(env, usage_role.get(), control)'));
    expect(jni, contains('FsvBasisuUsageRoleFromString('));
    expect(jni, contains('basisuImages.usageRole'));
    expect(jni, contains('MapGet(env, image.get(), "channelLayout")'));
    expect(jni, contains('FsvBasisuChannelLayoutFromString('));
    expect(jni, contains('basisuImages.channelLayout'));
    expect(jni, contains('ByteArray(env, level.rgba_bytes, control'));
    expect(jni, contains('FsvBasisuCopyBytesToPlatform('));
    expect(jni, contains('std::numeric_limits<jsize>::max()'));
    expect(jni, contains('env->ExceptionCheck()'));
    expect(jni, contains('env->ExceptionClear()'));
    expect(jni, contains('FsvBasisuPlatformCopyOutcome::kSuccess'));
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
    final retainedEnvelope = bridge.indexOf(
      'preflight.retained_rgba_bytes',
      usagePreflight,
    );
    final nativeInit = bridge.indexOf('transcoder.init(');
    final startTranscoding = bridge.indexOf('transcoder.start_transcoding()');
    final pixelAllocation = bridge.indexOf('FsvBasisuByteVector rgba(');
    expect(preflight, greaterThanOrEqualTo(0));
    expect(profilePreflight, greaterThan(preflight));
    expect(layoutPreflight, greaterThan(profilePreflight));
    expect(usagePreflight, greaterThan(layoutPreflight));
    expect(retainedEnvelope, -1);
    expect(outputReserve, greaterThan(usagePreflight));
    expect(nativeInit, greaterThan(usagePreflight));
    expect(startTranscoding, greaterThan(nativeInit));
    expect(pixelAllocation, greaterThan(startTranscoding));
    expect(bridge, isNot(contains('8192ULL')));
  });
}

Future<ProcessResult> _compileKtx2MetadataRunner({
  required String executable,
  required String platform,
  bool transcoderNoExceptions = false,
  bool sanitize = false,
}) async {
  final sanitizerFlags = sanitize
      ? const <String>[
          '-fsanitize=address,undefined',
          '-fno-omit-frame-pointer',
        ]
      : const <String>[];
  final zstdObject = '$executable-zstd.o';
  final zstdCompile = await Process.run('clang', <String>[
    '-std=c99',
    if (sanitize) '-O1' else '-O2',
    ...sanitizerFlags,
    '-Ithird_party/basis_universal/zstd',
    '-c',
    'third_party/basis_universal/zstd/zstddeclib.c',
    '-o',
    zstdObject,
  ]);
  expect(zstdCompile.exitCode, 0,
      reason: 'Zstd C compile\n${zstdCompile.stdout}\n${zstdCompile.stderr}');

  final cxxFlags = <String>[
    '-std=c++17',
    if (sanitize) '-O1' else '-O2',
    '-pthread',
    '-DBASISD_SUPPORT_KTX2=1',
    '-DBASISD_SUPPORT_KTX2_ZSTD=1',
    ...sanitizerFlags,
    if (transcoderNoExceptions) '-fno-exceptions',
    '-I$platform',
    '-Ithird_party/basis_universal/transcoder',
    '-Ithird_party/basis_universal/zstd',
  ];
  final transcoderSource =
      'third_party/basis_universal/transcoder/basisu_transcoder.cpp';
  return Process.run('clang++', <String>[
    ...cxxFlags,
    'test/native/basisu_ktx2_metadata_allocator_runner.cc',
    '$platform/fsv_basisu_budget.cc',
    '$platform/fsv_basisu_control.cc',
    '$platform/fsv_basisu_bridge.cc',
    transcoderSource,
    zstdObject,
    '-o',
    executable,
  ]);
}

const String _decodeControlRunner = r'''
#include "fsv_basisu_control.h"
#include <thread>

int main() {
  fsv_basisu::FsvDecodeControl control(16);
  if (!control.TryReserve(8) || control.live_bytes() != 8) return 1;
  if (control.peak_bytes() != 8 || control.allocation_count() != 1) return 13;
  if (control.TryReserve(9)) return 2;
  if (control.stop_reason() != fsv_basisu::FsvDecodeStopReason::kBudget) return 3;
  if (control.reserve_rejection_count() != 1) return 14;
  control.Release(8);
  if (control.live_bytes() != 0) return 4;
  if (control.release_count() != 1) return 15;
  if (control.Cancel() || control.Cancel()) return 5;
  if (control.IsCancelled()) return 6;
  if (control.stop_reason() != fsv_basisu::FsvDecodeStopReason::kBudget) return 7;
  if (control.TryReserve(1)) return 8;
  fsv_basisu::FsvDecodeControl caller_wins(0);
  const bool caller_won = caller_wins.Cancel();
  if (!caller_won ||
      caller_wins.stop_reason() !=
          fsv_basisu::FsvDecodeStopReason::kCallerCancelled) return 9;
  fsv_basisu::FsvDecodeControl scoped(16);
  {
    fsv_basisu::FsvScopedWorkingReservation reservation(&scoped, 8);
    if (!reservation.ok() || scoped.live_bytes() != 8) return 16;
  }
  if (scoped.live_bytes() != 0 || scoped.peak_bytes() != 8 ||
      scoped.allocation_count() != 1 || scoped.release_count() != 1) return 17;
  for (int iteration = 0; iteration < 500; ++iteration) {
    fsv_basisu::FsvDecodeControl raced(0);
    bool cancel_result = false;
    std::thread caller([&] { cancel_result = raced.Cancel(); });
    std::thread budget([&] { raced.TryReserve(1); });
    caller.join();
    budget.join();
    auto reason = raced.stop_reason();
    if (reason != fsv_basisu::FsvDecodeStopReason::kCallerCancelled &&
        reason != fsv_basisu::FsvDecodeStopReason::kBudget) return 10;
    if (reason == fsv_basisu::FsvDecodeStopReason::kCallerCancelled &&
        (!cancel_result || !raced.IsCancelled())) return 11;
    if (reason == fsv_basisu::FsvDecodeStopReason::kBudget &&
        (cancel_result || raced.IsCancelled())) return 12;
  }
  return 0;
}
''';

const String _zstdCancellationRunner = r'''
#include "fsv_basisu_control.h"
#include "zstd.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

uint64_t read64(const std::vector<uint8_t>& bytes, size_t offset) {
  uint64_t value = 0;
  for (int byte = 7; byte >= 0; --byte) {
    value = (value << 8) | bytes[offset + byte];
  }
  return value;
}

struct CallbackState {
  fsv_basisu::FsvDecodeControl* control;
  int checkpoints = 0;
  bool cancel_on_output = true;
};

class FailingHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  explicit FailingHeap(bool fail) : fail_(fail) {}

  void* Allocate(size_t bytes, size_t) noexcept override {
    attempts_ += 1;
    if (fail_) return nullptr;
    return std::malloc(bytes == 0 ? 1 : bytes);
  }

  void Release(void* pointer, size_t, size_t) noexcept override {
    std::free(pointer);
    releases_ += 1;
  }

  size_t attempts() const { return attempts_; }
  size_t releases() const { return releases_; }

 private:
  bool fail_;
  size_t attempts_ = 0;
  size_t releases_ = 0;
};

int checkpoint(void* opaque, size_t produced) {
  auto* state = static_cast<CallbackState*>(opaque);
  state->checkpoints += 1;
  if (produced != 0 && state->cancel_on_output) state->control->Cancel();
  return state->control->IsCancelled() ? 0 : 1;
}

int main(int argc, char** argv) {
  if (argc != 3) return 1;
  const std::string mode = argv[2];
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
  if (bytes.size() < 104) return 2;
  const uint64_t offset = read64(bytes, 80);
  const uint64_t compressed = read64(bytes, 88);
  const uint64_t uncompressed = read64(bytes, 96);
  if (offset + compressed > bytes.size() || uncompressed == 0) return 3;
  const size_t dctx_bytes = ZSTD_fsv_dctx_allocation_size();
  const size_t dctx_alignment = ZSTD_fsv_dctx_alignment();
  if (dctx_bytes == 0 || dctx_alignment != 8) return 4;
  std::vector<uint8_t> expected(uncompressed);
  const size_t expected_size = ZSTD_decompress(
      expected.data(), expected.size(), bytes.data() + offset, compressed);
  if (ZSTD_isError(expected_size) || expected_size != uncompressed) return 5;
  const bool heap_failure = mode == "heap-failure";
  const bool peak_minus_one = mode == "peak-minus-one";
  FailingHeap heap(heap_failure);
  const uint64_t byte_limit = uncompressed + dctx_bytes -
                              (peak_minus_one ? 1U : 0U);
  fsv_basisu::FsvDecodeControl control(byte_limit, &heap);
  CallbackState state{&control};
  state.cancel_on_output = mode == "cancel";
  std::vector<uint8_t> output(uncompressed);
  if (mode == "failure") bytes[offset] ^= 0x7f;
  {
    fsv_basisu::FsvScopedWorkingReservation reservation(&control, uncompressed);
    if (!reservation.ok()) return 6;
    basisu::fsv_allocation_result workspace =
        control.fsv_allocate(dctx_bytes, dctx_alignment);
    if (heap_failure || peak_minus_one) {
      const auto expected_outcome = heap_failure
          ? basisu::fsv_allocation_outcome::kHeapFailure
          : basisu::fsv_allocation_outcome::kBudgetExceeded;
      if (workspace.m_p != nullptr || workspace.m_outcome != expected_outcome ||
          control.live_bytes() != uncompressed) return 7;
      if (heap_failure &&
          control.stop_reason() !=
              fsv_basisu::FsvDecodeStopReason::kHeapFailure) return 8;
      if (peak_minus_one &&
          control.stop_reason() !=
              fsv_basisu::FsvDecodeStopReason::kBudget) return 9;
    } else {
      if (workspace.m_p == nullptr ||
          workspace.m_outcome != basisu::fsv_allocation_outcome::kSuccess ||
          reinterpret_cast<uintptr_t>(workspace.m_p) % dctx_alignment != 0)
        return 10;
      const size_t supplied_workspace = mode == "workspace-minus-one"
          ? dctx_bytes - 1
          : dctx_bytes;
    const size_t result = ZSTD_decompress_fsv(
        output.data(), output.size(), bytes.data() + offset, compressed,
          workspace.m_p, supplied_workspace, checkpoint, &state);
      if (!control.fsv_release(workspace, workspace.m_p, dctx_bytes,
                               dctx_alignment)) return 11;
    if (mode == "success") {
        if (ZSTD_isError(result) || result != uncompressed ||
            output != expected) return 12;
    } else if (mode == "cancel") {
        if (!ZSTD_isError(result) || !control.IsCancelled()) return 13;
    } else if (mode == "failure") {
        if (!ZSTD_isError(result) || control.IsCancelled()) return 14;
      } else if (mode == "workspace-minus-one") {
        if (!ZSTD_isError(result) ||
            ZSTD_getErrorCode(result) != ZSTD_error_memory_allocation)
          return 15;
    } else {
        return 16;
      }
      if (state.checkpoints < 1 || control.live_bytes() != uncompressed ||
          control.request_allocation_count() != 1 ||
          control.request_release_count() != 1 ||
          control.release_mismatch_count() != 0 || heap.attempts() != 1 ||
          heap.releases() != 1) return 17;
    }
  }
  if (control.live_bytes() != 0 ||
      control.allocation_count() != control.release_count() ||
      control.request_allocation_count() != control.request_release_count() ||
      control.release_mismatch_count() != 0) return 18;
  std::cout << "zstd-" << mode << "-release-ok checkpoints="
            << state.checkpoints << " workspace=" << dctx_bytes
            << " peak=" << control.peak_bytes();
  return 0;
}
''';

const String _basisuTypedDiagnosticRunner = r'''
#include "fsv_basisu_bridge.h"

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
#include "zstd.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <vector>

uint32_t read32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

uint64_t read64typed(const std::vector<uint8_t>& bytes, size_t offset) {
  uint64_t value = 0;
  for (int byte = 7; byte >= 0; --byte) value = (value << 8) | bytes[offset + byte];
  return value;
}

FsvBasisuImageRequest request_for(const std::vector<uint8_t>& bytes) {
  FsvBasisuImageRequest request;
  request.texture_index = 0;
  request.image_index = 0;
  request.usage_role = FsvBasisuUsageRole::kColor;
  request.channel_layout = FsvBasisuChannelLayout::kRgba;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  return request;
}

FsvBasisuDecodeBudgetMetadata budget() {
  FsvBasisuDecodeBudgetMetadata value;
  value.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  value.max_texture_pixels = FsvBasisuBudgetNumber::Integer(1LL << 30);
  value.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  value.max_native_working_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  return value;
}

FsvBasisuDecodeBudgetState state() {
  FsvBasisuDecodeBudgetState value;
  value.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  value.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  value.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
  return value;
}

bool status_is(const FsvBasisuTranscodeResult& result, const char* status) {
  return result.decoded_images.empty() && result.diagnostics.size() == 1 &&
         result.diagnostics[0].status == status;
}

bool result_is_charged(const fsv_basisu::FsvDecodeControl& control) {
  return control.request_allocation_count() >
             control.request_release_count() &&
         control.live_bytes() > 0 && control.owner_count() > 0 &&
         control.release_mismatch_count() == 0;
}

bool control_is_clean(const fsv_basisu::FsvDecodeControl& control) {
  return control.request_allocation_count() ==
             control.request_release_count() &&
         control.live_bytes() == 0 && control.owner_count() == 0 &&
         control.release_mismatch_count() == 0;
}

class WorkspaceFailingHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  void* Allocate(size_t bytes, size_t) noexcept override {
    if (bytes == ZSTD_fsv_dctx_allocation_size()) {
      saw_workspace_ = true;
      return nullptr;
    }
    return std::malloc(bytes == 0 ? 1 : bytes);
  }

  void Release(void* pointer, size_t, size_t) noexcept override {
    std::free(pointer);
  }

  bool saw_workspace() const { return saw_workspace_; }

 private:
  bool saw_workspace_ = false;
};

int main(int argc, char** argv) {
  if (argc != 2) return 1;
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
  if (bytes.size() < 104) return 2;
  const uint64_t pixels = static_cast<uint64_t>(read32(bytes, 20)) * read32(bytes, 24);
  const uint64_t outer = pixels * 4 + (pixels * 4 + read32(bytes, 24));

  fsv_basisu::FsvDecodeControl success_control(std::numeric_limits<uint64_t>::max());
  {
    auto success = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &success_control);
    if (success.decoded_images.size() != 1 || !success.diagnostics.empty() ||
        !result_is_charged(success_control)) {
      std::cerr << "success images=" << success.decoded_images.size()
                << " diagnostics=" << success.diagnostics.size()
                << " live=" << success_control.live_bytes();
      if (!success.diagnostics.empty())
        std::cerr << " status=" << success.diagnostics[0].status
                  << " field=" << success.diagnostics[0].field
                  << " message=" << success.diagnostics[0].message;
      return 3;
    }
  }
  if (!control_is_clean(success_control)) return 3;

  fsv_basisu::FsvDecodeControl budget_control(outer);
  {
    auto budget_result = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &budget_control);
    if (!budget_result.decoded_images.empty() ||
        !budget_result.diagnostics.empty() ||
        budget_result.terminal_outcome !=
            FsvBasisuTerminalOutcomeKind::kBudgetExceeded ||
        budget_control.stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kBudget ||
        !result_is_charged(budget_control)) {
      std::cerr << "budget diagnostics=" << budget_result.diagnostics.size()
                << " live=" << budget_control.live_bytes()
                << " reason=" << static_cast<int>(budget_control.stop_reason());
      if (!budget_result.diagnostics.empty())
        std::cerr << " status=" << budget_result.diagnostics[0].status;
      return 4;
    }
  }
  if (!control_is_clean(budget_control)) return 4;

  FsvBasisuTranscodeTestingHooks hooks;
  hooks.fail_next_codec_allocation = true;
  fsv_basisu::FsvDecodeControl allocation_control(std::numeric_limits<uint64_t>::max());
  {
    auto allocation_result = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &allocation_control, &hooks);
    if (!allocation_result.decoded_images.empty() ||
        !allocation_result.diagnostics.empty() ||
        allocation_result.terminal_outcome !=
            FsvBasisuTerminalOutcomeKind::kAllocationFailed ||
        allocation_control.stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        !result_is_charged(allocation_control)) return 5;
  }
  if (!control_is_clean(allocation_control)) return 5;

  WorkspaceFailingHeap workspace_heap;
  fsv_basisu::FsvDecodeControl workspace_control(
      std::numeric_limits<uint64_t>::max(), &workspace_heap);
  {
    auto workspace_result = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &workspace_control);
    if (!workspace_heap.saw_workspace() ||
        !workspace_result.decoded_images.empty() ||
        !workspace_result.diagnostics.empty() ||
        workspace_result.terminal_outcome !=
            FsvBasisuTerminalOutcomeKind::kAllocationFailed ||
        workspace_control.stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kHeapFailure ||
        !result_is_charged(workspace_control)) return 10;
  }
  if (!control_is_clean(workspace_control)) return 10;

  std::vector<uint8_t> corrupt = bytes;
  const uint64_t level_offset = read64typed(corrupt, 80);
  if (level_offset >= corrupt.size()) return 6;
  corrupt[level_offset] ^= 0x7f;
  fsv_basisu::FsvDecodeControl corrupt_control(std::numeric_limits<uint64_t>::max());
  {
    auto corrupt_result = FsvBasisuTranscodeImages(
        {request_for(corrupt)}, budget(), state(), &corrupt_control);
    if (!status_is(corrupt_result, "decodeFailed") ||
        corrupt_control.stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        !result_is_charged(corrupt_control)) return 7;
  }
  if (!control_is_clean(corrupt_control)) return 7;

  fsv_basisu::FsvDecodeControl cancelled(std::numeric_limits<uint64_t>::max());
  cancelled.Cancel();
  {
    auto cancelled_result = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &cancelled);
    if (!cancelled_result.decoded_images.empty() ||
        !cancelled_result.diagnostics.empty() ||
        cancelled_result.terminal_outcome !=
            FsvBasisuTerminalOutcomeKind::kCallerCancelled) return 8;
  }
  if (!control_is_clean(cancelled)) return 8;

  fsv_basisu::FsvDecodeControl deadline(std::numeric_limits<uint64_t>::max());
  deadline.Deadline();
  {
    auto deadline_result = FsvBasisuTranscodeImages(
        {request_for(bytes)}, budget(), state(), &deadline);
    if (!deadline_result.decoded_images.empty() ||
        !deadline_result.diagnostics.empty() ||
        deadline_result.terminal_outcome !=
            FsvBasisuTerminalOutcomeKind::kDeadline) return 9;
  }
  if (!control_is_clean(deadline)) return 9;

  std::cout << "basisu-typed-diagnostics-ok";
  return 0;
}
''';

Future<bool> _verifyCodecControlManifest({
  required File manifest,
  required Directory sourceRoot,
}) async {
  final entries = RegExp(
    r'^original=[0-9a-f]{64} patched=([0-9a-f]{64}) path=(.+)$',
    multiLine: true,
  ).allMatches(await manifest.readAsString());
  var sawEntry = false;
  for (final entry in entries) {
    sawEntry = true;
    final source = File('${sourceRoot.path}/${entry.group(2)}');
    if (!await source.exists()) return false;
    final hash = await Process.run(
      'shasum',
      <String>['-a', '256', source.path],
    );
    if (hash.exitCode != 0 ||
        '${hash.stdout}'.split(RegExp(r'\s+')).first != entry.group(1)) {
      return false;
    }
  }
  return sawEntry;
}

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
        before: 'if (control == null || !control.isValid() || detached ||\n'
            '        active.containsKey(requestId)) {',
        after: 'if (control == null || !control.isValid() || detached) {',
      ),
      (
        label: 'registration after detach',
        before: 'if (control == null || !control.isValid() || detached ||\n'
            '        active.containsKey(requestId)) {',
        after: 'if (control == null || !control.isValid() ||\n'
            '        active.containsKey(requestId)) {',
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
        before: '  if (active_.find(request_id) != active_.end()) {\n'
            '    if (failure != nullptr) *failure = FsvRegisterFailure::kDuplicate;\n'
            '    return nullptr;\n'
            '  }\n',
        after: '',
      ),
      (
        label: 'registration after detach',
        before: '  if (detached_) {\n'
            '    if (failure != nullptr) *failure = FsvRegisterFailure::kDetached;\n'
            '    return nullptr;\n'
            '  }\n',
        after: '',
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
        '-Ithird_party/basis_universal/transcoder',
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

const String _javaLifecycleRunner = r'''
package com.marlonjd.flutter_scene_viewer_basisu;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public final class BasisuRegistryRunner {
  private static final class Control implements FsvDecodeRequestRegistry.Control {
    final AtomicInteger cancels = new AtomicInteger();
    final AtomicInteger destroys = new AtomicInteger();
    public boolean isValid() { return true; }
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
#include "fsv_basisu_request_registry.h"
#include <atomic>
#include <thread>

int main() {
  fsv_basisu::FsvDecodeRequestRegistry registry;
  auto queued = registry.Register("queued", 16);
  if (registry.Register("queued", 16) != nullptr) return 1;
  if (registry.Cancel("queued") != fsv_basisu::FsvCancelStatus::kCancelled) return 1;
  if (registry.Cancel("queued") != fsv_basisu::FsvCancelStatus::kCancelled) return 2;
  if (registry.ShouldStart(queued)) return 3;
  if (registry.Finish("queued", queued) !=
      fsv_basisu::FsvFinishDisposition::kCancelled) return 4;
  if (registry.Cancel("queued") != fsv_basisu::FsvCancelStatus::kAlreadyFinished) return 5;
  if (registry.Cancel("missing") != fsv_basisu::FsvCancelStatus::kUnknownRequest) return 6;

  auto won = registry.Register("won", 16);
  if (registry.Finish("won", won) != fsv_basisu::FsvFinishDisposition::kSuccess) return 7;
  if (registry.Cancel("won") != fsv_basisu::FsvCancelStatus::kAlreadyFinished) return 8;
  if (!registry.ClaimDelivery(won) || registry.ClaimDelivery(won)) return 9;

  for (int iteration = 0; iteration < 500; ++iteration) {
    const std::string request_id = "race-" + std::to_string(iteration);
    auto raced = registry.Register(request_id, 16);
    auto control = raced->control;
    std::atomic<bool> start{false};
    fsv_basisu::FsvCancelStatus cancel_status;
    fsv_basisu::FsvFinishDisposition finish_status;
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
        cancel_status == fsv_basisu::FsvCancelStatus::kCancelled &&
        finish_status == fsv_basisu::FsvFinishDisposition::kCancelled &&
        control->IsCancelled();
    const bool finish_won =
        cancel_status == fsv_basisu::FsvCancelStatus::kAlreadyFinished &&
        finish_status == fsv_basisu::FsvFinishDisposition::kSuccess &&
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
  jboolean ExceptionCheck();
  void ExceptionClear();
  const char* GetStringUTFChars(jstring, jboolean*);
  void ReleaseStringUTFChars(jstring, const char*);
  void DeleteLocalRef(jobject);
};
''';

const String _fakeFlutterHeader = r'''
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
''';

const String _basisuBudgetRunner = r'''
#include <cstdint>
#include <iostream>
#include <vector>

#include "fsv_basisu_budget.h"

void SetLe32(FsvBasisuByteVector* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value & 0xff);
  (*bytes)[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  (*bytes)[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xff);
  (*bytes)[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

void SetLe64(FsvBasisuByteVector* bytes, size_t offset, uint64_t value) {
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
                                    int64_t native,
                                    int64_t working = -1) {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(total);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(pixels);
  budget.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(native);
  if (working >= 0) {
    budget.max_native_working_bytes = FsvBasisuBudgetNumber::Integer(working);
  }
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
      {request}, Budget(24, 6, 24), State());
  if (!exact.ok || exact.layouts.size() != 1 ||
      exact.layouts[0].pixel_count != 6 ||
      exact.layouts[0].rgba_bytes != 24 ||
      exact.layouts[0].levels.size() != 1 ||
      exact.layouts[0].levels[0].level != 0 ||
      exact.layouts[0].levels[0].width != 2 ||
      exact.layouts[0].levels[0].height != 3 ||
      exact.layouts[0].levels[0].rgba_bytes != 24 ||
      exact.retained_rgba_bytes != 24 ||
      exact.max_level_uncompressed_bytes != 0 ||
      exact.native_working_bytes != 24) {
    return 1;
  }
  if (!Fails(FsvBasisuPreflightRequests({request}, Budget(24, 5, 24), State()),
             "budgetExceeded", "texturePixels") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(24, 6, 23), State()),
             "budgetExceeded", "nativeOutputBytes") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(23, 6, 24), State()),
             "budgetExceeded", "totalDecodedBytes") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(48, 6, 48),
                                        State(0, 1, 0)),
             "budgetExceeded", "texturePixels")) {
    return 2;
  }
  const auto aggregate = FsvBasisuPreflightRequests(
      {request, Request(2, 3, 1)}, Budget(48, 12, 48, 48), State());
  if (!aggregate.ok || aggregate.layouts.size() != 2 ||
      aggregate.native_output_bytes != 48 ||
      aggregate.retained_rgba_bytes != 48 ||
      aggregate.native_working_bytes != 48 ||
      !Fails(FsvBasisuPreflightRequests(
                 {request, Request(2, 3, 1)}, Budget(48, 12, 47, 48), State()),
             "budgetExceeded", "nativeOutputBytes") ||
      !Fails(FsvBasisuPreflightRequests(
                 {request, Request(2, 3, 1)}, Budget(48, 12, 48, 47), State()),
             "budgetExceeded", "nativeWorkingBytes")) {
    return 3;
  }
  auto zstd = request;
  SetLe32(&zstd.bytes, 44, 2);
  SetLe64(&zstd.bytes, 96, 7);
  auto second_zstd = zstd;
  second_zstd.texture_index = 1;
  second_zstd.image_index = 1;
  const auto zstd_working = FsvBasisuPreflightRequests(
      {zstd, second_zstd}, Budget(48, 12, 48, 55), State());
  if (!zstd_working.ok || zstd_working.retained_rgba_bytes != 48 ||
      zstd_working.max_level_uncompressed_bytes != 7 ||
      zstd_working.native_working_bytes != 55 ||
      !Fails(FsvBasisuPreflightRequests(
                 {zstd, second_zstd}, Budget(48, 12, 48, 54), State()),
             "budgetExceeded", "nativeWorkingBytes")) {
    return 31;
  }
  FsvBasisuDecodeBudgetMetadata missing = Budget(24, 6, 24);
  missing.max_texture_pixels = FsvBasisuBudgetNumber();
  if (!Fails(FsvBasisuPreflightRequests({request}, missing, State()),
             "invalidMetadata", "maxTexturePixels")) {
    return 4;
  }
  FsvBasisuDecodeBudgetMetadata invalid = Budget(24, 6, 24);
  invalid.max_texture_pixels = FsvBasisuBudgetNumber::Invalid();
  if (!Fails(FsvBasisuPreflightRequests({request}, invalid, State()),
             "invalidMetadata", "maxTexturePixels") ||
      !Fails(FsvBasisuPreflightRequests({request}, Budget(24, -1, 24), State()),
             "invalidMetadata", "maxTexturePixels") ||
      !Fails(FsvBasisuPreflightRequests(
                 {request}, Budget(24, kFsvBasisuMaxSafeInteger + 1, 24),
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
  auto zstd_zero_uncompressed = request;
  SetLe32(&zstd_zero_uncompressed.bytes, 44, 2);
  SetLe64(&zstd_zero_uncompressed.bytes, 96, 0);
  auto none_wrong_uncompressed = request;
  SetLe64(&none_wrong_uncompressed.bytes, 96, 2);
  auto web_unsafe_uncompressed = request;
  SetLe32(&web_unsafe_uncompressed.bytes, 44, 2);
  SetLe64(&web_unsafe_uncompressed.bytes, 96,
          UINT64_C(9007199254740992));
  if (!Fails(FsvBasisuPreflightRequests(
                 {zstd_zero_uncompressed}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2UncompressedByteLength") ||
      !Fails(FsvBasisuPreflightRequests(
                 {none_wrong_uncompressed}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2UncompressedByteLength") ||
      !Fails(FsvBasisuPreflightRequests(
                 {web_unsafe_uncompressed}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2UncompressedByteLength")) {
    return 91;
  }
  auto tail = request;
  tail.bytes.push_back(0);
  if (!Fails(FsvBasisuPreflightRequests({tail}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2LevelIndex")) {
    return 92;
  }
  auto gap = Request(2, 2);
  gap.bytes.assign(131, 0);
  const uint8_t identifier[] = {
      0xab, 0x4b, 0x54, 0x58, 0x20, 0x32,
      0x30, 0xbb, 0x0d, 0x0a, 0x1a, 0x0a};
  for (size_t index = 0; index < sizeof(identifier); index += 1) {
    gap.bytes[index] = identifier[index];
  }
  SetLe32(&gap.bytes, 20, 2);
  SetLe32(&gap.bytes, 24, 2);
  SetLe32(&gap.bytes, 36, 1);
  SetLe32(&gap.bytes, 40, 2);
  SetLe64(&gap.bytes, 80, 128);
  SetLe64(&gap.bytes, 88, 1);
  SetLe64(&gap.bytes, 96, 1);
  SetLe64(&gap.bytes, 104, 130);
  SetLe64(&gap.bytes, 112, 1);
  SetLe64(&gap.bytes, 120, 1);
  auto excessive_levels = gap;
  excessive_levels.bytes.resize(152);
  SetLe32(&excessive_levels.bytes, 40, 3);
  if (!Fails(FsvBasisuPreflightRequests({gap}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2LevelIndex") ||
      !Fails(FsvBasisuPreflightRequests(
                 {excessive_levels}, Budget(95, 6, 95), State()),
             "invalidMetadata", "ktx2MipLevels")) {
    return 93;
  }
  const auto platform_message = FsvBasisuPreflightRequests(
      {Request(32768, 32768)},
      Budget(kFsvBasisuMaxSafeInteger, kFsvBasisuMaxSafeInteger,
             kFsvBasisuMaxSafeInteger),
      State());
  if (!Fails(platform_message, "invalidMetadata", "platformMessageBytes")) {
    return 94;
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
    if (image.levels.size() != 1) return 72;
    const FsvBasisuDecodedMipLevel& decoded_level = image.levels.front();
    const uint8_t* direct_bytes =
        reinterpret_cast<const uint8_t*>(direct_pixels.data());
    if (decoded_level.level != 0 ||
        decoded_level.width != level.m_orig_width ||
        decoded_level.height != level.m_orig_height ||
        decoded_level.rgba_bytes.size() !=
            direct_pixels.size() * sizeof(uint32_t) ||
        !std::equal(decoded_level.rgba_bytes.begin(),
                    decoded_level.rgba_bytes.end(), direct_bytes)) {
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
#include <string>
#include <vector>

#include "fsv_basisu_bridge.h"

template <typename Bytes>
uint32_t ReadMipLe32(const Bytes& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

template <typename Bytes>
void SetMipLe32(Bytes* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value & 0xff);
  (*bytes)[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xff);
  (*bytes)[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xff);
  (*bytes)[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xff);
}

template <typename Bytes>
uint64_t ReadMipLe64(const Bytes& bytes, size_t offset) {
  return static_cast<uint64_t>(ReadMipLe32(bytes, offset)) |
         (static_cast<uint64_t>(ReadMipLe32(bytes, offset + 4)) << 32);
}

template <typename Bytes>
void SetMipLe64(Bytes* bytes, size_t offset, uint64_t value) {
  SetMipLe32(bytes, offset, static_cast<uint32_t>(value));
  SetMipLe32(bytes, offset + 4, static_cast<uint32_t>(value >> 32));
}

int main(int argc, char** argv) {
  if (argc != 4) {
    return 64;
  }
  for (int case_index = 0; case_index < 2; case_index += 1) {
    std::ifstream input(argv[case_index + 1], std::ios::binary);
    std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                               std::istreambuf_iterator<char>());
    if (bytes.empty()) {
      return 65;
    }
    // The official compare corpus is UNORM (BT709+LINEAR), while the glTF
    // BasisU profile requires UNSPECIFIED+LINEAR for this data path. Preserve
    // the exact codec payload and normalize only DFD primaries in memory.
    const uint32_t dfd_offset = ReadMipLe32(bytes, 48);
    uint32_t dfd_bits = ReadMipLe32(bytes, dfd_offset + 12);
    dfd_bits &= ~0xff00U;
    SetMipLe32(&bytes, dfd_offset + 12, dfd_bits);
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
    if (!result.diagnostics.empty() || result.decoded_images.size() != 1) {
      if (!result.diagnostics.empty()) {
        std::cerr << "case=" << case_index
                  << " status=" << result.diagnostics.front().status
                  << " stage=" << result.diagnostics.front().stage
                  << " field=" << result.diagnostics.front().field << "\n";
      } else {
        std::cerr << "case=" << case_index
                  << " decoded=" << result.decoded_images.size() << "\n";
      }
      return 66;
    }
    const FsvBasisuDecodedImage& image = result.decoded_images.front();
    if (image.content_role != "structuralOnly" || image.levels.size() != 2 ||
        image.levels[0].level != 0 || image.levels[0].width != 8 ||
        image.levels[0].height != 8 || image.levels[0].rgba_bytes.size() != 256 ||
        image.levels[1].level != 1 || image.levels[1].width != 4 ||
        image.levels[1].height != 4 || image.levels[1].rgba_bytes.size() != 64) {
      return 67;
    }
    for (size_t level = 0; level < image.levels.size(); level += 1) {
      const std::string path = std::string(argv[3]) + "/mip-" +
          std::to_string(case_index * 2 + static_cast<int>(level)) + ".rgba";
      std::ofstream output(path, std::ios::binary);
      output.write(
          reinterpret_cast<const char*>(image.levels[level].rgba_bytes.data()),
          static_cast<std::streamsize>(image.levels[level].rgba_bytes.size()));
      if (!output) return 68;
    }
    if (case_index == 0) {
      FsvBasisuDecodeBudgetMetadata tight_budget = budget;
      tight_budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(79);
      const FsvBasisuTranscodeResult over_budget =
          FsvBasisuTranscodeImages({request}, tight_budget, state);
      if (!over_budget.decoded_images.empty() ||
          over_budget.diagnostics.size() != 1 ||
          over_budget.diagnostics[0].status != "budgetExceeded" ||
          over_budget.diagnostics[0].field != "texturePixels") return 69;

      FsvBasisuImageRequest overlapping = request;
      SetMipLe64(&overlapping.bytes, 104, ReadMipLe64(overlapping.bytes, 80));
      const FsvBasisuTranscodeResult overlap_result =
          FsvBasisuTranscodeImages({overlapping}, budget, state);
      if (!overlap_result.decoded_images.empty() ||
          overlap_result.diagnostics.size() != 1 ||
          overlap_result.diagnostics[0].status != "invalidMetadata" ||
          overlap_result.diagnostics[0].field != "ktx2LevelIndex") return 70;

      FsvBasisuImageRequest outside = request;
      SetMipLe64(&outside.bytes, 88, UINT64_C(9007199254740991));
      const FsvBasisuTranscodeResult outside_result =
          FsvBasisuTranscodeImages({outside}, budget, state);
      if (!outside_result.decoded_images.empty() ||
          outside_result.diagnostics.size() != 1 ||
          outside_result.diagnostics[0].status != "invalidMetadata" ||
          outside_result.diagnostics[0].field != "ktx2LevelIndex") return 71;

      fsv_basisu::FsvDecodeControl cancel_control(10000000);
      FsvBasisuTranscodeTestingHooks cancel_hooks;
      cancel_hooks.cancel_before_level = 1;
      {
        const FsvBasisuTranscodeResult cancelled = FsvBasisuTranscodeImages(
            {request}, budget, state, &cancel_control, &cancel_hooks);
        if (!cancelled.decoded_images.empty() ||
            !cancelled.diagnostics.empty() ||
            cancelled.terminal_outcome !=
                FsvBasisuTerminalOutcomeKind::kCallerCancelled ||
            cancel_control.stop_reason() !=
                fsv_basisu::FsvDecodeStopReason::kCallerCancelled ||
            cancel_control.request_allocation_count() <=
                cancel_control.request_release_count() ||
            cancel_control.live_bytes() == 0 ||
            cancel_control.owner_count() == 0 ||
            cancel_control.release_mismatch_count() != 0) {
          return 72;
        }
      }
      if (cancel_control.live_bytes() != 0 ||
          cancel_control.owner_count() != 0 ||
          cancel_control.request_allocation_count() !=
              cancel_control.request_release_count() ||
          cancel_control.release_mismatch_count() != 0) {
        return 72;
      }

      FsvBasisuImageRequest second = request;
      second.texture_index = 10;
      second.image_index = 10;
      FsvBasisuDecodeBudgetMetadata multi_budget = budget;
      multi_budget.max_total_decoded_bytes =
          FsvBasisuBudgetNumber::Integer(640);
      multi_budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(160);
      multi_budget.max_native_output_bytes =
          FsvBasisuBudgetNumber::Integer(640);
      multi_budget.max_native_working_bytes =
          FsvBasisuBudgetNumber::Integer(640);
      const FsvBasisuPreflightResult multi_preflight =
          FsvBasisuPreflightRequests({request, second}, multi_budget, state);
      if (!multi_preflight.ok || multi_preflight.retained_rgba_bytes != 640 ||
          multi_preflight.max_level_uncompressed_bytes != 0 ||
          multi_preflight.native_working_bytes != 640) {
        return 73;
      }
      FsvBasisuDecodeBudgetMetadata multi_tight = multi_budget;
      multi_tight.max_native_working_bytes =
          FsvBasisuBudgetNumber::Integer(639);
      const FsvBasisuPreflightResult multi_over =
          FsvBasisuPreflightRequests({request, second}, multi_tight, state);
      if (multi_over.ok || !multi_over.layouts.empty() ||
          multi_over.diagnostics.size() != 1 ||
          multi_over.diagnostics[0].status != "budgetExceeded" ||
          multi_over.diagnostics[0].field != "nativeWorkingBytes") {
        return 74;
      }
      fsv_basisu::FsvDecodeControl boundary_control(10000000);
      FsvBasisuTranscodeTestingHooks boundary_hooks;
      boundary_hooks.cancel_before_request_index = 1;
      {
        const FsvBasisuTranscodeResult boundary_cancelled =
            FsvBasisuTranscodeImages({request, second}, budget, state,
                                     &boundary_control, &boundary_hooks);
        if (!boundary_cancelled.decoded_images.empty() ||
            !boundary_cancelled.diagnostics.empty() ||
            boundary_cancelled.terminal_outcome !=
                FsvBasisuTerminalOutcomeKind::kCallerCancelled ||
            boundary_control.stop_reason() !=
                fsv_basisu::FsvDecodeStopReason::kCallerCancelled ||
            boundary_control.request_allocation_count() <=
                boundary_control.request_release_count() ||
            boundary_control.live_bytes() == 0 ||
            boundary_control.owner_count() == 0 ||
            boundary_control.release_mismatch_count() != 0) {
          return 75;
        }
      }
      if (boundary_control.live_bytes() != 0 ||
          boundary_control.owner_count() != 0 ||
          boundary_control.request_allocation_count() !=
              boundary_control.request_release_count() ||
          boundary_control.release_mismatch_count() != 0) {
        return 75;
      }
    }
  }
  std::cout << "basisu-mip-chain-ok cases=2 levels=4\n";
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
