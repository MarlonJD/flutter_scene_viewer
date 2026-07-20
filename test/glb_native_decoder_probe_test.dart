import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_scene_viewer/src/diagnostics.dart';
import 'package:flutter_scene_viewer/src/internal/glb_capability_reader.dart';
import 'package:flutter_scene_viewer/src/internal/glb_decode_budget.dart';
import 'package:flutter_scene_viewer/src/internal/glb_native_decoder_probe.dart';
import 'package:flutter_scene_viewer/src/model_load_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BasisU request construction is included in the shared deadline',
      () async {
    final source = await File(
      'lib/src/internal/glb_native_decoder_probe.dart',
    ).readAsString();
    final methodStart = source.indexOf(
      'Future<GlbNativeDecodeResult> _decodeBasisuGlb({',
    );
    final methodEnd = source.indexOf(
      'on _NativeDecodeDeadlineExpired',
      methodStart,
    );
    final method = source.substring(methodStart, methodEnd);
    final requestBuild = method.indexOf(
      'final basisuImages = _basisuImageRequestsFromGlb(bytes);',
    );
    final remainingBudget = method.indexOf(
      'final remaining = deadline.remainingOrThrow();',
    );

    expect(requestBuild, greaterThanOrEqualTo(0));
    expect(remainingBudget, greaterThan(requestBuild));
    expect(method, contains("'basisuImages': basisuImages"));
  });

  test('pre-cancelled native load never dispatches or sends cancel', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/pre-cancelled');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      methods.add(call.method);
      return <String, Object?>{};
    });
    final cancellation = ModelLoadCancellationController()
      ..cancel('left-screen');

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(mode: 4),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      cancellationToken: cancellation.token,
      source: 'pre-cancelled.glb',
    );

    expect(methods, isEmpty);
    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code,
        ViewerDiagnosticCode.modelLoadCancelled);
    expect(result.diagnostics.single.details,
        containsPair('reason', 'left-screen'));
    expect(
      result.diagnostics.single.details,
      containsPair('nativeDispatch', 'notStarted'),
    );
    expect(result.diagnostics.single.details.containsKey('requestId'), isFalse);
  });

  test('caller cancellation sends exactly one cancel and discards late success',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/cancel-active');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final decodeStarted = Completer<String>();
    final lateDecode = Completer<Map<String, Object?>?>();
    final cancelledIds = <String>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      if (call.method == 'decodeGlb') {
        final requestId = arguments['requestId']! as String;
        decodeStarted.complete(requestId);
        return lateDecode.future;
      }
      expect(call.method, 'cancelDecode');
      cancelledIds.add(arguments['requestId']! as String);
      return <String, Object?>{'status': 'cancelled'};
    });
    final cancellation = ModelLoadCancellationController();
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());
    final future = const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(mode: 4),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: tracker,
      cancellationToken: cancellation.token,
      source: 'cancel-active.glb',
    );
    final requestId = await decodeStarted.future;

    expect(cancellation.cancel('route-changed'), isTrue);
    final result = await future;
    expect(cancelledIds, <String>[requestId]);
    expect(result.bytes, isNull);
    expect(result.diagnostics.single.code,
        ViewerDiagnosticCode.modelLoadCancelled);
    expect(result.diagnostics.single.details,
        containsPair('requestId', requestId));
    expect(result.diagnostics.single.details,
        containsPair('reason', 'route-changed'));
    expect(result.diagnostics.single.details,
        containsPair('nativeDispatch', 'started'));
    expect(result.diagnostics.single.details,
        containsPair('lateResult', 'discardedByDart'));

    lateDecode.complete(<String, Object?>{
      'diagnostics': <Object?>[],
      'bytes': _compressedGlb(mode: 4),
    });
    await Future<void>.delayed(Duration.zero);
    expect(tracker.totalDecodedBytes, 0);
    expect(cancelledIds, <String>[requestId]);
  });

  test('sequential codecs cancel only the active BasisU request', () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/sequential-cancel-draco');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/sequential-cancel-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    final requestIds = <String>[];
    final cancelledIds = <String>[];
    final basisuStarted = Completer<void>();
    final pendingBasisu = Completer<Map<String, Object?>?>();
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        final arguments = call.arguments as Map<Object?, Object?>;
        if (call.method == 'cancelDecode') {
          cancelledIds.add(arguments['requestId']! as String);
          return <String, Object?>{'status': 'cancelled'};
        }
        requestIds.add(arguments['requestId']! as String);
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'bytes': _basisuGlb(),
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        final arguments = call.arguments as Map<Object?, Object?>;
        if (call.method == 'cancelDecode') {
          cancelledIds.add(arguments['requestId']! as String);
          return <String, Object?>{'status': 'cancelled'};
        }
        requestIds.add(arguments['requestId']! as String);
        basisuStarted.complete();
        return pendingBasisu.future;
      });
    final cancellation = ModelLoadCancellationController();
    final future = const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      cancellationToken: cancellation.token,
    );
    await basisuStarted.future;
    cancellation.cancel('sequential-stop');
    final result = await future;

    expect(requestIds, hasLength(2));
    expect(requestIds.toSet(), hasLength(2));
    expect(cancelledIds, <String>[requestIds[1]]);
    expect(result.diagnostics.single.details,
        containsPair('requestId', requestIds[1]));
  });

  test('concurrent native loads use distinct collision-resistant request ids',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/concurrent-ids');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final requestIds = <String>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      requestIds.add(arguments['requestId']! as String);
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'test stop',
            'details': <String, Object?>{
              'extension': 'KHR_draco_mesh_compression',
              'status': 'testStop',
            },
          },
        ],
      };
    });
    final probe = const MethodChannelGlbNativeDecoderProbe(channel: channel);

    await Future.wait(<Future<GlbNativeDecodeResult>>[
      probe.decodeGlb(
        bytes: _compressedGlb(mode: 4),
        requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
        budget: const GlbDecodeBudget(),
        budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      ),
      probe.decodeGlb(
        bytes: _compressedGlb(mode: 4),
        requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
        budget: const GlbDecodeBudget(),
        budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      ),
    ]);

    expect(requestIds, hasLength(2));
    expect(requestIds.toSet(), hasLength(2));
    expect(requestIds.every((id) => id.split('-').length >= 3), isTrue);
  });

  test('successful native stage removes its cancellation listener', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/listener-removed');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      methods.add(call.method);
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'test stop',
            'details': <String, Object?>{
              'extension': 'KHR_draco_mesh_compression',
              'status': 'testStop',
            },
          },
        ],
      };
    });
    final cancellation = ModelLoadCancellationController();

    await const MethodChannelGlbNativeDecoderProbe(channel: channel).decodeGlb(
      bytes: _compressedGlb(mode: 4),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      cancellationToken: cancellation.token,
    );
    cancellation.cancel('after-success');
    await Future<void>.delayed(Duration.zero);

    expect(methods, <String>['decodeGlb']);
  });

  test('timeout cancels once and a later caller cancel cannot cancel twice',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/timeout-cancel');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final decodeStarted = Completer<void>();
    final cancelledIds = <String>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      if (call.method == 'cancelDecode') {
        cancelledIds.add(arguments['requestId']! as String);
        return <String, Object?>{'status': 'cancelled'};
      }
      decodeStarted.complete();
      return Completer<Map<String, Object?>?>().future;
    });
    final cancellation = ModelLoadCancellationController();
    const budget = GlbDecodeBudget(
      decodeTimeout: Duration(milliseconds: 20),
    );
    final future = const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(mode: 4),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: budget,
      budgetTracker: GlbDecodeBudgetTracker(budget),
      cancellationToken: cancellation.token,
    );
    await decodeStarted.future;
    final result = await future;
    cancellation.cancel('too-late');
    await Future<void>.delayed(Duration.zero);

    expect(
        result.diagnostics.single.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(cancelledIds, hasLength(1));
    expect(result.diagnostics.single.details,
        containsPair('nativeDispatch', 'started'));
  });

  test('native Draco timeout is typed and blocks every later decode stage',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/draco-timeout');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/basisu-after-draco-timeout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    var dracoCalls = 0;
    var basisuCalls = 0;
    messenger
      ..setMockMethodCallHandler(
        dracoChannel,
        (MethodCall call) {
          if (call.method == 'cancelDecode') {
            return Future<Map<String, Object?>?>.value(
              <String, Object?>{'status': 'cancelled'},
            );
          }
          dracoCalls += 1;
          return Future<Map<String, Object?>?>.delayed(
            const Duration(milliseconds: 100),
            () => <String, Object?>{
              'diagnostics': <Object?>[],
              'decodedPrimitives': <Object?>[
                <String, Object?>{
                  'meshIndex': 0,
                  'primitiveIndex': 0,
                  'attributes': <String, Object?>{
                    'POSITION': _float32Bytes(<double>[1, 2, 3]),
                  },
                  'indices': _uint16Bytes(<int>[0, 0, 0]),
                },
              ],
            },
          );
        },
      )
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        if (call.method == 'cancelDecode') {
          return <String, Object?>{'status': 'unknownRequest'};
        }
        basisuCalls += 1;
        return <String, Object?>{};
      });
    const budget = GlbDecodeBudget(
      decodeTimeout: Duration(milliseconds: 20),
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'native-timeout.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.diagnostics, hasLength(1));
    expect(
        result.diagnostics.single.code, ViewerDiagnosticCode.modelLoadTimeout);
    final timeoutDetails = Map<String, Object?>.of(
      result.diagnostics.single.details,
    );
    expect(timeoutDetails.remove('requestId'), isA<String>());
    expect(timeoutDetails, <String, Object?>{
      'source': 'native-timeout.glb',
      'extension': 'KHR_draco_mesh_compression',
      'decoder': 'draco',
      'required': true,
      'stage': 'nativeDecodeMethodChannel',
      'limitation': 'nativeDecodeDeadline',
      'status': 'timedOut',
      'timeoutMilliseconds': 20,
      'nativeDispatch': 'started',
      'nativeResourceRelease': 'notGuaranteed',
      'lateResult': 'discardedByDart',
      'fallback': 'diagnosticOnly',
    });
    expect(dracoCalls, 1);
    expect(basisuCalls, 0);
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);

    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(basisuCalls, 0);
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);
  });

  test('native BasisU timeout is typed and discards its late output', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-timeout');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var basisuCalls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) {
        if (call.method == 'cancelDecode') {
          return Future<Map<String, Object?>?>.value(
            <String, Object?>{'status': 'cancelled'},
          );
        }
        basisuCalls += 1;
        return Future<Map<String, Object?>?>.delayed(
          const Duration(milliseconds: 100),
          () => <String, Object?>{
            'diagnostics': <Object?>[],
            'decodedImages': <Object?>[
              <String, Object?>{
                'imageIndex': 0,
                'mimeType': 'image/png',
                'width': 1,
                'height': 1,
                'bytes': _pngBytes(width: 1, height: 1),
              },
            ],
          },
        );
      },
    );
    const budget = GlbDecodeBudget(
      decodeTimeout: Duration(milliseconds: 20),
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: budget,
      budgetTracker: tracker,
      source: 'basisu-timeout.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.diagnostics, hasLength(1));
    expect(
        result.diagnostics.single.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(
        result.diagnostics.single.details, containsPair('decoder', 'basisu'));
    expect(
      result.diagnostics.single.details,
      containsPair('nativeResourceRelease', 'notGuaranteed'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('nativeDispatch', 'started'),
    );
    expect(tracker.texturePixels, 0);
    expect(basisuCalls, 1);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);

    await Future<void>.delayed(const Duration(milliseconds: 110));
    expect(tracker.texturePixels, 0);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);
  });

  test('expired native deadline rejects before dispatching MethodChannel work',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/expired-draco-deadline');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var channelCalls = 0;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      channelCalls += 1;
      return <String, Object?>{};
    });
    const budget = GlbDecodeBudget(decodeTimeout: Duration.zero);
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(mode: 4),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: budget,
      budgetTracker: tracker,
      source: 'expired-deadline.glb',
    );
    await Future<void>.delayed(Duration.zero);

    expect(result.bytes, isNull);
    expect(
        result.diagnostics.single.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(result.diagnostics.single.details, <String, Object?>{
      'source': 'expired-deadline.glb',
      'extension': 'KHR_draco_mesh_compression',
      'decoder': 'draco',
      'required': true,
      'stage': 'nativeDecodeMethodChannel',
      'limitation': 'nativeDecodeDeadline',
      'status': 'timedOut',
      'timeoutMilliseconds': 0,
      'nativeDispatch': 'notStarted',
      'nativeResourceRelease': 'notApplicable',
      'lateResult': 'notApplicable',
      'fallback': 'diagnosticOnly',
    });
    expect(channelCalls, 0);
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);
  });

  test('native decode timeout is shared across sequential codec stages',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/shared-deadline-draco');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/shared-deadline-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    final intermediate = _basisuGlb();
    var dracoCalls = 0;
    var basisuCalls = 0;
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) {
        if (call.method == 'cancelDecode') {
          return Future<Map<String, Object?>?>.value(
            <String, Object?>{'status': 'alreadyFinished'},
          );
        }
        dracoCalls += 1;
        return Future<Map<String, Object?>?>.delayed(
          const Duration(milliseconds: 250),
          () => <String, Object?>{
            'diagnostics': <Object?>[],
            'bytes': intermediate,
          },
        );
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) {
        if (call.method == 'cancelDecode') {
          return Future<Map<String, Object?>?>.value(
            <String, Object?>{'status': 'cancelled'},
          );
        }
        basisuCalls += 1;
        return Future<Map<String, Object?>?>.delayed(
          const Duration(milliseconds: 250),
          () => <String, Object?>{
            'diagnostics': <Object?>[],
            'decodedImages': <Object?>[
              <String, Object?>{
                'imageIndex': 0,
                'mimeType': 'image/png',
                'width': 1,
                'height': 1,
                'bytes': _pngBytes(width: 1, height: 1),
              },
            ],
          },
        );
      });
    const budget = GlbDecodeBudget(
      decodeTimeout: Duration(milliseconds: 400),
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'shared-deadline.glb',
    );

    expect(result.bytes, isNull);
    expect(
        result.diagnostics.single.code, ViewerDiagnosticCode.modelLoadTimeout);
    expect(
      result.diagnostics.single.details,
      containsPair('extension', 'KHR_texture_basisu'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('nativeDispatch', 'started'),
    );
    expect(dracoCalls, 1);
    expect(basisuCalls, 1);
    expect(tracker.nativeOutputBytes, intermediate.lengthInBytes);
    expect(tracker.totalDecodedBytes, intermediate.lengthInBytes);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(tracker.nativeOutputBytes, intermediate.lengthInBytes);
    expect(tracker.totalDecodedBytes, intermediate.lengthInBytes);
  });

  test('decodeGlb rewrites native decoded Draco primitive payloads', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/draco');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final compressed = _compressedGlb(mode: 4);
    final positionBytes = _float32Bytes(<double>[1, 2, 3]);
    final indexBytes = _uint16Bytes(<int>[0, 0, 0]);
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      final primitives = arguments['dracoPrimitives'] as List<Object?>;
      expect(primitives, hasLength(1));
      final primitive = primitives.single as Map<Object?, Object?>;
      expect(primitive['meshIndex'], 0);
      expect(primitive['primitiveIndex'], 0);
      expect(
          primitive['compressedBytes'], Uint8List.fromList(<int>[9, 9, 9, 9]));
      expect(primitive['attributes'], <String, Object?>{'POSITION': 0});
      expect(primitive['vertexAccessorIndex'], 0);
      expect(
        primitive['attributeAccessors'],
        <String, Object?>{
          'POSITION': <String, Object?>{
            'accessorIndex': 0,
            'componentType': 5126,
            'type': 'VEC3',
            'count': 1,
            'normalized': false,
          },
        },
      );
      expect(
        primitive['indicesAccessor'],
        <String, Object?>{
          'accessorIndex': 1,
          'componentType': 5123,
          'type': 'SCALAR',
          'count': 3,
          'normalized': false,
        },
      );
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedPrimitives': <Object?>[
          <String, Object?>{
            'meshIndex': 0,
            'primitiveIndex': 0,
            'attributes': <String, Object?>{
              'POSITION': positionBytes,
            },
            'indices': indexBytes,
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: compressed,
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'draco.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    final capabilities = readGlbAssetCapabilities(result.bytes!);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(
      capabilities.compressedPrimitiveCounts['KHR_draco_mesh_compression'] ?? 0,
      0,
    );
  });

  test('native Draco request preserves additional uncompressed attributes',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/draco-extra-attribute');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final primitives = arguments['dracoPrimitives'] as List<Object?>;
      final primitive = primitives.single as Map<Object?, Object?>;
      expect(primitive['attributes'], <String, Object?>{'POSITION': 7});
      expect(primitive['vertexAccessorIndex'], 0);
      expect(
        primitive['attributeAccessors'],
        <String, Object?>{
          'POSITION': <String, Object?>{
            'accessorIndex': 0,
            'componentType': 5126,
            'type': 'VEC3',
            'count': 1,
            'normalized': false,
          },
          'COLOR_0': <String, Object?>{
            'accessorIndex': 1,
            'componentType': 5121,
            'type': 'VEC4',
            'count': 1,
            'normalized': true,
          },
        },
      );
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'Expected native test stop.',
            'details': <String, Object?>{
              'extension': 'KHR_draco_mesh_compression',
              'status': 'testStop',
            },
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlbWithAdditionalAttribute(),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics.single.details['status'], 'testStop');
  });

  test('malformed additional Draco accessor fails before native channel',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/draco-malformed-extra');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var channelCalls = 0;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      channelCalls += 1;
      return <String, Object?>{};
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlbWithMalformedAdditionalAttribute(),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'malformed-extra.glb',
    );

    expect(channelCalls, 0);
    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.details, <String, Object?>{
      'source': 'malformed-extra.glb',
      'extension': 'KHR_draco_mesh_compression',
      'decoder': 'draco',
      'required': true,
      'limitation': 'dracoAccessorSchema',
      'status': 'invalidMetadata',
      'stage': 'dracoNativeRequestPreflight',
      'field': 'accessors[1].componentType',
      'accessorIndex': 1,
      'attribute': 'COLOR_0',
      'actual': '5121',
    });
  });

  test('Draco TRIANGLE_STRIP fails with typed diagnostic before native channel',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/draco-triangle-strip');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var channelCalls = 0;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      channelCalls += 1;
      return <String, Object?>{};
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(mode: 5),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'triangle-strip.glb',
    );

    expect(channelCalls, 0);
    expect(result.bytes, isNull);
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedModelFeature);
    expect(result.diagnostics.single.details, <String, Object?>{
      'source': 'triangle-strip.glb',
      'extension': 'KHR_draco_mesh_compression',
      'decoder': 'draco',
      'required': true,
      'limitation': 'dracoPrimitiveMode',
      'status': 'unsupportedLayout',
      'stage': 'dracoNativeRequestPreflight',
      'field': 'meshes[0].primitives[0].mode',
      'limit': 4,
      'actual': 5,
    });
  });

  test('decodeGlb rewrites native decoded BasisU image payloads', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final compressed = _basisuGlb();
    final pngBytes = _pngBytes(width: 1, height: 1);
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'decodeGlb');
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages'] as List<Object?>;
      expect(images, hasLength(1));
      final image = images.single as Map<Object?, Object?>;
      expect(image['textureIndex'], 0);
      expect(image['imageIndex'], 0);
      expect(image['usageRole'], 'structuralOnly');
      expect(image['channelLayout'], 'structuralOnly');
      expect(image['mimeType'], 'image/ktx2');
      expect(image['bytes'], Uint8List.fromList(<int>[9, 9, 9, 9]));
      expect(arguments['decodeBudget'], <String, Object?>{
        'maxJsonBytes': 8 * 1024 * 1024,
        'maxTotalDecodedBytes': 256 * 1024 * 1024,
        'maxAccessors': 1024 * 1024,
        'maxVertices': 20 * 1024 * 1024,
        'maxIndices': 60 * 1024 * 1024,
        'maxTexturePixels': 64 * 1024 * 1024,
        'maxNativeOutputBytes': 256 * 1024 * 1024,
        'maxNativeWorkingBytes': 256 * 1024 * 1024,
      });
      expect(arguments['decodeBudgetState'], <String, Object?>{
        'totalDecodedBytes': 0,
        'nativeOutputBytes': 0,
        'accessors': 0,
        'vertices': 0,
        'indices': 0,
        'texturePixels': 0,
      });
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
            'bytes': pngBytes,
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: compressed,
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'basisu.glb',
    );

    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    final capabilities = readGlbAssetCapabilities(result.bytes!);
    expect(capabilities.basisuTextureCount, 0);
    expect(capabilities.extensionsRequired, isEmpty);
    expect(capabilities.diagnostics, isEmpty);
  });

  test('deduplicates native BasisU requests for a shared image source',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/shared-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final compressed = _basisuGlb(
      textureCount: 2,
      samplers: const <Map<String, Object?>>[
        <String, Object?>{
          'magFilter': 9728,
          'minFilter': 9984,
          'wrapS': 33071,
          'wrapT': 33648,
        },
      ],
      samplerIndices: const <int?>[0, null],
    );
    var nativeRequestCount = 0;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages'] as List<Object?>;
      nativeRequestCount = images.length;
      expect(images, hasLength(1));
      final image = images.single as Map<Object?, Object?>;
      expect(image['textureIndex'], 0);
      expect(image['imageIndex'], 0);
      expect(image['usageRole'], 'structuralOnly');
      expect(image['channelLayout'], 'structuralOnly');
      expect(image['textureBindings'], <Object?>[
        <String, Object?>{
          'textureIndex': 0,
          'samplerIndex': 0,
          'magFilter': 9728,
          'minFilter': 9984,
          'wrapS': 33071,
          'wrapT': 33648,
        },
        <String, Object?>{
          'textureIndex': 1,
          'samplerIndex': null,
          'magFilter': 9729,
          'minFilter': 9987,
          'wrapS': 10497,
          'wrapT': 10497,
        },
      ]);
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
            'bytes': _pngBytes(width: 1, height: 1),
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: compressed,
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'shared-basisu.glb',
    );

    expect(nativeRequestCount, 1);
    expect(result.diagnostics, isEmpty);
    expect(result.bytes, isNotNull);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    final capabilities = readGlbAssetCapabilities(result.bytes!);
    expect(capabilities.basisuTextureCount, 0);
    expect(capabilities.extensionsRequired, isEmpty);
    final textures = _glbJson(result.bytes!)['textures']! as List<Object?>;
    expect(textures, hasLength(2));
    for (final rawTexture in textures) {
      final texture = rawTexture! as Map<String, Object?>;
      expect(texture['source'], 0);
      expect(texture['extensions'], isNull);
    }
  });

  test('derives BasisU usage roles from every selected material texture slot',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-roles');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var requestVerified = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages']! as List<Object?>;
      expect(images, hasLength(13));
      final rolesAndLayouts = <int, List<Object?>>{
        for (final rawImage in images)
          (rawImage! as Map<Object?, Object?>)['imageIndex']! as int: <Object?>[
            (rawImage as Map<Object?, Object?>)['usageRole'],
            rawImage['channelLayout'],
          ],
      };
      expect(rolesAndLayouts, <int, List<Object?>>{
        0: <Object?>['color', 'rgb'],
        1: <Object?>['color', 'rgb'],
        2: <Object?>['color', 'rgb'],
        3: <Object?>['nonColor', 'rgb'],
        4: <Object?>['nonColor', 'rgb'],
        5: <Object?>['nonColor', 'r'],
        6: <Object?>['nonColor', 'rgba'],
        7: <Object?>['nonColor', 'rgb'],
        8: <Object?>['nonColor', 'rgb'],
        9: <Object?>['nonColor', 'rgb'],
        10: <Object?>['nonColor', 'r'],
        11: <Object?>['nonColor', 'rg'],
        12: <Object?>['structuralOnly', 'structuralOnly'],
      });
      requestVerified = true;
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuUsageSlotGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
    );

    expect(result.bytes, isNull);
    expect(requestVerified, isTrue);
  });

  test('keeps packed color RGB plus specular alpha as valid color', () async {
    const channel = MethodChannel(
      'test/flutter_scene_viewer/basisu-channel-role-matrix',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var requestVerified = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages']! as List<Object?>;
      expect(
        images
            .map((Object? raw) => raw! as Map<Object?, Object?>)
            .map((Map<Object?, Object?> image) => <Object?>[
                  image['textureIndex'],
                  image['imageIndex'],
                  image['usageRole'],
                  image['channelLayout'],
                ])
            .toList(),
        <Object?>[
          <Object?>[0, 0, 'color', 'rgb'],
          <Object?>[1, 1, 'color', 'rgba'],
          <Object?>[2, 2, 'color', 'rgba'],
          <Object?>[3, 3, 'color', 'rgba'],
          <Object?>[4, 4, 'nonColor', 'rgb'],
          <Object?>[5, 5, 'nonColor', 'rgb'],
          <Object?>[6, 6, 'ambiguous', 'rgb'],
          <Object?>[7, 7, 'color', 'rgba'],
          <Object?>[9, 8, 'structuralOnly', 'structuralOnly'],
        ],
      );
      requestVerified = true;
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuChannelRoleMatrixGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
    );

    expect(result.bytes, isNull);
    expect(requestVerified, isTrue);
  });

  test('does not widen malformed alpha modes to RGBA requests', () async {
    const channel = MethodChannel(
      'test/flutter_scene_viewer/basisu-malformed-alpha-mode',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var requestVerified = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages']! as List<Object?>;
      expect(
        images
            .map((Object? raw) => raw! as Map<Object?, Object?>)
            .map((Map<Object?, Object?> image) => <Object?>[
                  image['textureIndex'],
                  image['imageIndex'],
                  image['usageRole'],
                  image['channelLayout'],
                ])
            .toList(),
        <Object?>[
          <Object?>[0, 0, 'color', 'rgb'],
          <Object?>[1, 1, 'color', 'rgb'],
        ],
      );
      requestVerified = true;
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuMalformedAlphaModeGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
    );

    expect(result.bytes, isNull);
    expect(requestVerified, isTrue);
  });

  test('aggregates BasisU roles through shared textures and images', () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/basisu-role-aggregation');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    var requestVerified = false;
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final images = arguments['basisuImages']! as List<Object?>;
      expect(images, hasLength(3));
      expect(
        images
            .map((Object? raw) => raw! as Map<Object?, Object?>)
            .map((Map<Object?, Object?> image) => <Object?>[
                  image['textureIndex'],
                  image['imageIndex'],
                  image['usageRole'],
                  image['channelLayout'],
                ])
            .toList(),
        <Object?>[
          <Object?>[0, 0, 'ambiguous', 'rgb'],
          <Object?>[1, 1, 'ambiguous', 'rgb'],
          <Object?>[3, 2, 'structuralOnly', 'structuralOnly'],
        ],
      );
      requestVerified = true;
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuRoleAggregationGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
    );

    expect(result.bytes, isNull);
    expect(requestVerified, isTrue);
  });

  test('rejects native BasisU output missing decoded dimensions', () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/basisu-dimensions');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'bytes': _pngBytes(width: 1, height: 1),
          },
        ],
      };
    });
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: tracker,
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.diagnostics, hasLength(2));
    expect(result.diagnostics[0].details,
        containsPair('field', 'decodedImages[0].width'));
    expect(result.diagnostics[1].details,
        containsPair('field', 'decodedImages[0].height'));
    expect(tracker.texturePixels, 0);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);
  });

  test('decodeGlb carries raw multi-level output outside PNG rewrite',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-mips');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'contentRole': 'structuralOnly',
            'levels': <Object?>[
              <String, Object?>{
                'level': 0,
                'width': 4,
                'height': 4,
                'rgbaBytes': Uint8List(4 * 4 * 4),
              },
              <String, Object?>{
                'level': 1,
                'width': 2,
                'height': 2,
                'rgbaBytes': Uint8List(2 * 2 * 4),
              },
            ],
          },
        ],
      };
    });

    final topology = _basisuGlb();
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());
    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: topology,
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: tracker,
      source: 'basisu-mips.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.topologyBytes, orderedEquals(topology));
    expect(
      result.topologyOutputAccounting,
      GlbNativeDecodeOutputAccounting.none,
    );
    expect(result.diagnostics, isEmpty);
    expect(result.decodedBasisuImages, hasLength(1));
    final decoded = result.decodedBasisuImages.single;
    expect(decoded.contentRole, 'structuralOnly');
    expect(decoded.levels.map((level) => level.level), <int>[0, 1]);
    expect(
        () => decoded.levels.add(decoded.levels.first), throwsUnsupportedError);
    expect(decoded.textureBindings, hasLength(1));
    expect(decoded.textureBindings.single.textureIndex, 0);
    expect(decoded.textureBindings.single.sampler.minFilter, 9987);
    expect(tracker.texturePixels, 20);
    expect(tracker.nativeOutputBytes, 80);
    expect(tracker.totalDecodedBytes, 80);
  });

  test('decodeGlb rejects authored mip aggregate budget atomically', () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/basisu-mip-budget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'contentRole': 'structuralOnly',
            'levels': <Object?>[
              <String, Object?>{
                'level': 0,
                'width': 4,
                'height': 4,
                'rgbaBytes': Uint8List(4 * 4 * 4),
              },
              <String, Object?>{
                'level': 1,
                'width': 2,
                'height': 2,
                'rgbaBytes': Uint8List(2 * 2 * 4),
              },
            ],
          },
        ],
      };
    });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 79,
      maxNativeOutputBytes: 79,
      maxTexturePixels: 20,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: budget,
      budgetTracker: tracker,
      source: 'basisu-mip-budget.glb',
    );

    expect(result.bytes, isNull);
    expect(result.topologyBytes, isNull);
    expect(result.decodedBasisuImages, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'nativeOutputBytes'),
    );
    expect(tracker.texturePixels, 0);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);
  });

  test('decodeGlb rejects terminal diagnostics mixed with decoded payloads',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/basisu-terminal-xor');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'Native decode failed after producing a payload.',
            'details': <String, Object?>{
              'status': 'decodeFailed',
              'field': 'ktx2Payload',
            },
          },
        ],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'contentRole': 'structuralOnly',
            'levels': <Object?>[
              <String, Object?>{
                'level': 0,
                'width': 1,
                'height': 1,
                'rgbaBytes': Uint8List(4),
              },
            ],
          },
        ],
      };
    });
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget())
      ..reserveNativeOutputBytes(5, stage: 'priorDecoder');

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: tracker,
      source: 'terminal-xor.glb',
    );

    expect(result.bytes, isNull);
    expect(result.topologyBytes, isNull);
    expect(result.decodedBasisuImages, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('status', 'malformedOutput'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'methodChannelResult'),
    );
    expect(tracker.texturePixels, 0);
    expect(tracker.nativeOutputBytes, 5);
    expect(tracker.totalDecodedBytes, 5);
  });

  test('decodeGlb rejects terminal diagnostics mixed with opaque bytes',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/basisu-terminal-bytes-xor');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'Native decode failed after producing bytes.',
            'details': <String, Object?>{'status': 'decodeFailed'},
          },
        ],
        'bytes': Uint8List.fromList(<int>[1, 2, 3, 4]),
      };
    });
    final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: tracker,
      source: 'terminal-bytes-xor.glb',
    );

    expect(result.bytes, isNull);
    expect(result.topologyBytes, isNull);
    expect(result.decodedBasisuImages, isEmpty);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('status', 'malformedOutput'),
    );
    expect(tracker.texturePixels, 0);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.totalDecodedBytes, 0);
  });

  test('decodeGlb rejects returned content roles that differ from requests',
      () async {
    const cases = <(String, String)>[
      ('color', 'nonColor'),
      ('nonColor', 'structuralOnly'),
      ('structuralOnly', 'color'),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final (expectedRole, returnedRole) in cases) {
      final channel = MethodChannel(
        'test/flutter_scene_viewer/basisu-role-$expectedRole',
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
      });
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        final arguments = call.arguments! as Map<Object?, Object?>;
        final images = arguments['basisuImages']! as List<Object?>;
        expect(images.single, containsPair('usageRole', expectedRole));
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedImages': <Object?>[
            <String, Object?>{
              'imageIndex': 0,
              'contentRole': returnedRole,
              'levels': <Object?>[
                <String, Object?>{
                  'level': 0,
                  'width': 1,
                  'height': 1,
                  'rgbaBytes': Uint8List(4),
                },
              ],
            },
          ],
        };
      });
      final tracker = GlbDecodeBudgetTracker(const GlbDecodeBudget());

      final result = await MethodChannelGlbNativeDecoderProbe(
        basisuChannel: channel,
      ).decodeGlb(
        bytes: _basisuSingleRoleGlb(expectedRole),
        requiredExtensions: const <String>{'KHR_texture_basisu'},
        budget: const GlbDecodeBudget(),
        budgetTracker: tracker,
        source: '$expectedRole-role.glb',
      );

      expect(result.bytes, isNull, reason: expectedRole);
      expect(result.topologyBytes, isNull, reason: expectedRole);
      expect(result.decodedBasisuImages, isEmpty, reason: expectedRole);
      expect(result.diagnostics, hasLength(1), reason: expectedRole);
      expect(
        result.diagnostics.single.details,
        containsPair('status', 'malformedOutput'),
        reason: expectedRole,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', 'decodedImages[0].contentRole'),
        reason: expectedRole,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('limit', expectedRole),
        reason: expectedRole,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('actual', returnedRole),
        reason: expectedRole,
      );
      expect(tracker.texturePixels, 0, reason: expectedRole);
      expect(tracker.nativeOutputBytes, 0, reason: expectedRole);
      expect(tracker.totalDecodedBytes, 0, reason: expectedRole);
    }
  });

  test('decodeGlb carries Draco-rewritten topology beside authored BasisU mips',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/draco-authored-mips');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/basisu-authored-mips');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    Uint8List? basisuInput;
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedPrimitives': <Object?>[
            <String, Object?>{
              'meshIndex': 0,
              'primitiveIndex': 0,
              'attributes': <String, Object?>{
                'POSITION': _float32Bytes(<double>[1, 2, 3]),
              },
              'indices': _uint16Bytes(<int>[0, 0, 0]),
            },
          ],
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        basisuInput = Uint8List.fromList(
          (call.arguments as Map<Object?, Object?>)['bytes']! as List<int>,
        );
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedImages': <Object?>[
            <String, Object?>{
              'imageIndex': 0,
              'contentRole': 'structuralOnly',
              'levels': <Object?>[
                <String, Object?>{
                  'level': 0,
                  'width': 4,
                  'height': 4,
                  'rgbaBytes': Uint8List(4 * 4 * 4),
                },
                <String, Object?>{
                  'level': 1,
                  'width': 2,
                  'height': 2,
                  'rgbaBytes': Uint8List(2 * 2 * 4),
                },
              ],
            },
          ],
        };
      });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 1024,
      maxNativeOutputBytes: 1024,
      maxAccessors: 2,
      maxVertices: 1,
      maxIndices: 3,
    );
    final tracker = GlbDecodeBudgetTracker(budget);
    final original = _dracoAndBasisuGlb();

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: original,
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'draco-authored-mips.glb',
    );

    expect(basisuInput, isNotNull);
    expect(basisuInput, isNot(orderedEquals(original)));
    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.topologyBytes, orderedEquals(basisuInput!));
    expect(
      result.topologyOutputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    expect(result.decodedBasisuImages, hasLength(1));
    expect(result.diagnostics, isEmpty);
    expect(tracker.totalDecodedBytes, 98);
    expect(tracker.nativeOutputBytes, 98);
    expect(tracker.texturePixels, 20);
    expect(tracker.accessors, 2);
    expect(tracker.vertices, 1);
    expect(tracker.indices, 3);
  });

  test('decodeGlb accounts opaque Draco topology before authored BasisU mips',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/opaque-draco-authored-mips');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/opaque-basisu-authored-mips');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    final opaqueTopology = _basisuGlb();
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'bytes': opaqueTopology,
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedImages': <Object?>[
            <String, Object?>{
              'imageIndex': 0,
              'contentRole': 'structuralOnly',
              'levels': <Object?>[
                <String, Object?>{
                  'level': 0,
                  'width': 1,
                  'height': 1,
                  'rgbaBytes': Uint8List(4),
                },
              ],
            },
          ],
        };
      });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 4096,
      maxNativeOutputBytes: 4096,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'opaque-draco-authored-mips.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.topologyBytes, orderedEquals(opaqueTopology));
    expect(
      result.topologyOutputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    expect(result.decodedBasisuImages, hasLength(1));
    expect(result.diagnostics, isEmpty);
    expect(
      tracker.nativeOutputBytes,
      opaqueTopology.lengthInBytes + 4,
    );
    expect(
      tracker.totalDecodedBytes,
      opaqueTopology.lengthInBytes + 4,
    );
    expect(tracker.texturePixels, 1);
  });

  test('decodeGlb preserves typed BasisU profile diagnostics', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-profile');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message':
                'KTX2 DFD channels are not allowed by KHR_texture_basisu.',
            'details': <String, Object?>{
              'extension': 'KHR_texture_basisu',
              'decoder': 'basisu',
              'required': true,
              'status': 'unsupportedKtx2Profile',
              'stage': 'basisuProfilePreflight',
              'field': 'ktx2DfdChannels',
              'limitation': 'decodedPayloadSchema',
            },
          },
        ],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'basisu-profile.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostics.single.details, <String, Object?>{
      'extension': 'KHR_texture_basisu',
      'decoder': 'basisu',
      'required': true,
      'status': 'unsupportedKtx2Profile',
      'stage': 'basisuProfilePreflight',
      'field': 'ktx2DfdChannels',
      'limitation': 'decodedPayloadSchema',
    });
  });

  test('decodeGlb preserves typed BasisU usage diagnostics', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-usage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message':
                'A BasisU image shared by color and non-color material slots has an ambiguous usage role.',
            'details': <String, Object?>{
              'extension': 'KHR_texture_basisu',
              'decoder': 'basisu',
              'required': true,
              'status': 'unsupportedKtx2Usage',
              'stage': 'basisuUsagePreflight',
              'field': 'basisuUsageRole',
              'limitation': 'decodedPayloadSchema',
            },
          },
        ],
        'decodedImages': <Object?>[],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      basisuChannel: channel,
    ).decodeGlb(
      bytes: _basisuRoleAggregationGlb(),
      requiredExtensions: const <String>{'KHR_texture_basisu'},
      budget: const GlbDecodeBudget(),
      budgetTracker: GlbDecodeBudgetTracker(const GlbDecodeBudget()),
      source: 'basisu-usage.glb',
    );

    expect(result.bytes, isNull);
    expect(result.outputAccounting, GlbNativeDecodeOutputAccounting.none);
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.code,
      ViewerDiagnosticCode.unsupportedModelFeature,
    );
    expect(result.diagnostics.single.details, <String, Object?>{
      'extension': 'KHR_texture_basisu',
      'decoder': 'basisu',
      'required': true,
      'status': 'unsupportedKtx2Usage',
      'stage': 'basisuUsagePreflight',
      'field': 'basisuUsageRole',
      'limitation': 'decodedPayloadSchema',
    });
  });

  test('decodeGlb enforces user-selected Draco dimension budgets', () async {
    const channel = MethodChannel('test/flutter_scene_viewer/draco-budget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    final positionBytes = _float32Bytes(<double>[1, 2, 3]);
    final indexBytes = _uint16Bytes(<int>[0, 0, 0]);
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedPrimitives': <Object?>[
          <String, Object?>{
            'meshIndex': 0,
            'primitiveIndex': 0,
            'attributes': <String, Object?>{'POSITION': positionBytes},
            'indices': indexBytes,
          },
        ],
      };
    });
    final cases =
        <({GlbDecodeBudget budget, String field, int limit, int actual})>[
      (
        budget: const GlbDecodeBudget(maxAccessors: 1),
        field: 'accessors',
        limit: 1,
        actual: 2,
      ),
      (
        budget: const GlbDecodeBudget(maxVertices: 0),
        field: 'vertices',
        limit: 0,
        actual: 1,
      ),
      (
        budget: const GlbDecodeBudget(maxIndices: 2),
        field: 'indices',
        limit: 2,
        actual: 3,
      ),
    ];

    for (final limits in cases) {
      final tracker = GlbDecodeBudgetTracker(limits.budget);
      final result = await const MethodChannelGlbNativeDecoderProbe(
        channel: channel,
      ).decodeGlb(
        bytes: _compressedGlb(),
        requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
        budget: limits.budget,
        budgetTracker: tracker,
        source: 'draco-budget.glb',
      );

      expect(result.bytes, isNull, reason: limits.field);
      expect(
        result.outputAccounting,
        GlbNativeDecodeOutputAccounting.none,
        reason: limits.field,
      );
      expect(result.diagnostics, hasLength(1), reason: limits.field);
      expect(
        result.diagnostics.single.details,
        containsPair('limitation', 'decodeBudget'),
        reason: limits.field,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('field', limits.field),
        reason: limits.field,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('limit', limits.limit),
        reason: limits.field,
      );
      expect(
        result.diagnostics.single.details,
        containsPair('actual', limits.actual),
        reason: limits.field,
      );
      expect(tracker.totalDecodedBytes, 0, reason: limits.field);
      expect(tracker.accessors, 0, reason: limits.field);
      expect(tracker.vertices, 0, reason: limits.field);
      expect(tracker.indices, 0, reason: limits.field);
    }
  });

  test('decodeGlb forwards the exact Draco budget and current tracker state',
      () async {
    const channel =
        MethodChannel('test/flutter_scene_viewer/draco-native-budget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    const budget = GlbDecodeBudget(
      maxJsonBytes: 101,
      maxTotalDecodedBytes: 202,
      maxAccessors: 303,
      maxVertices: 404,
      maxIndices: 505,
      maxTexturePixels: 606,
      maxNativeOutputBytes: 707,
    );
    final tracker = GlbDecodeBudgetTracker(budget)
      ..reserveDecodedBytes(11, stage: 'priorDecode')
      ..reserveNativeOutputBytes(13, stage: 'priorNativeDecode')
      ..reserveAccessors(17, stage: 'priorDecode')
      ..reserveVertices(19, stage: 'priorDecode')
      ..reserveIndices(23, stage: 'priorDecode')
      ..reserveTexturePixels(width: 5, height: 7, stage: 'priorDecode');
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      expect(arguments['decodeBudget'], <String, Object?>{
        'maxJsonBytes': 101,
        'maxTotalDecodedBytes': 202,
        'maxAccessors': 303,
        'maxVertices': 404,
        'maxIndices': 505,
        'maxTexturePixels': 606,
        'maxNativeOutputBytes': 707,
        'maxNativeWorkingBytes': 256 * 1024 * 1024,
      });
      expect(arguments['decodeBudgetState'], <String, Object?>{
        'totalDecodedBytes': 24,
        'nativeOutputBytes': 13,
        'accessors': 17,
        'vertices': 19,
        'indices': 23,
        'texturePixels': 35,
      });
      return <String, Object?>{
        'diagnostics': <Object?>[
          <String, Object?>{
            'code': 'unsupportedModelFeature',
            'message': 'Expected native test stop.',
            'details': <String, Object?>{
              'extension': 'KHR_draco_mesh_compression',
              'status': 'testStop',
            },
          },
        ],
      };
    });

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: channel,
    ).decodeGlb(
      bytes: _compressedGlb(),
      requiredExtensions: const <String>{'KHR_draco_mesh_compression'},
      budget: budget,
      budgetTracker: tracker,
      source: 'native-budget.glb',
    );

    expect(result.bytes, isNull);
    expect(result.diagnostics.single.details['status'], 'testStop');
  });

  test('decodeGlb enforces aggregate BasisU output budgets atomically',
      () async {
    const channel = MethodChannel('test/flutter_scene_viewer/basisu-budget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return <String, Object?>{
        'diagnostics': <Object?>[],
        'decodedImages': <Object?>[
          <String, Object?>{
            'imageIndex': 0,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
            'bytes': _pngBytes(width: 1, height: 1),
          },
          <String, Object?>{
            'imageIndex': 1,
            'mimeType': 'image/png',
            'width': 1,
            'height': 1,
            'bytes': _pngBytes(width: 1, height: 1),
          },
        ],
      };
    });
    final cases = <({GlbDecodeBudget budget, String field})>[
      (
        budget: const GlbDecodeBudget(
          maxTotalDecodedBytes: 100,
          maxNativeOutputBytes: 49,
        ),
        field: 'nativeOutputBytes',
      ),
      (
        budget: const GlbDecodeBudget(
          maxTotalDecodedBytes: 49,
          maxNativeOutputBytes: 100,
        ),
        field: 'totalDecodedBytes',
      ),
    ];

    for (final limits in cases) {
      final tracker = GlbDecodeBudgetTracker(limits.budget)
        ..reserveNativeOutputBytes(2, stage: 'priorDecoder');
      final result = await const MethodChannelGlbNativeDecoderProbe(
        basisuChannel: channel,
      ).decodeGlb(
        bytes: _twoImageBasisuGlb(),
        requiredExtensions: const <String>{'KHR_texture_basisu'},
        budget: limits.budget,
        budgetTracker: tracker,
        source: 'basisu-budget.glb',
      );

      expect(result.bytes, isNull, reason: limits.field);
      expect(
        result.outputAccounting,
        GlbNativeDecodeOutputAccounting.none,
        reason: limits.field,
      );
      expect(result.diagnostics, hasLength(1), reason: limits.field);
      expect(
        result.diagnostics.single.details,
        containsPair('field', limits.field),
        reason: limits.field,
      );
      expect(result.diagnostics.single.details, containsPair('actual', 50));
      expect(tracker.totalDecodedBytes, 2, reason: limits.field);
      expect(tracker.nativeOutputBytes, 2, reason: limits.field);
    }
  });

  test('decodeGlb shares one tracker across sequential Draco and BasisU',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/sequential-draco');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/sequential-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedPrimitives': <Object?>[
            <String, Object?>{
              'meshIndex': 0,
              'primitiveIndex': 0,
              'attributes': <String, Object?>{
                'POSITION': _float32Bytes(<double>[1, 2, 3]),
              },
              'indices': _uint16Bytes(<int>[0, 0, 0]),
            },
          ],
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedImages': <Object?>[
            <String, Object?>{
              'imageIndex': 0,
              'mimeType': 'image/png',
              'width': 1,
              'height': 1,
              'bytes': _pngBytes(width: 1, height: 1),
            },
          ],
        };
      });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 41,
      maxNativeOutputBytes: 1024,
      maxAccessors: 2,
      maxVertices: 1,
      maxIndices: 3,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'sequential.glb',
    );

    expect(result.bytes, isNull);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.none,
    );
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('extension', 'KHR_texture_basisu'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'totalDecodedBytes'),
    );
    expect(tracker.totalDecodedBytes, 18);
    expect(tracker.nativeOutputBytes, 18);
    expect(tracker.accessors, 2);
    expect(tracker.vertices, 1);
    expect(tracker.indices, 3);
  });

  test('decodeGlb accounts an intermediate opaque Draco output before BasisU',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/opaque-intermediate-draco');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/component-final-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    final opaqueIntermediate = _basisuGlb();
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'bytes': opaqueIntermediate,
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedImages': <Object?>[
            <String, Object?>{
              'imageIndex': 0,
              'mimeType': 'image/png',
              'width': 1,
              'height': 1,
              'bytes': _pngBytes(width: 1, height: 1),
            },
          ],
        };
      });
    final accountedBytes = opaqueIntermediate.lengthInBytes + 24;
    final budget = GlbDecodeBudget(
      maxTotalDecodedBytes: accountedBytes,
      maxNativeOutputBytes: accountedBytes,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'opaque-intermediate.glb',
    );

    expect(result.bytes, isNotNull);
    expect(result.diagnostics, isEmpty);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.componentPayloadsAccounted,
    );
    expect(tracker.totalDecodedBytes, accountedBytes);
    expect(tracker.nativeOutputBytes, accountedBytes);
  });

  test('decodeGlb checks an intermediate component output before BasisU',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/component-intermediate');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/unreached-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    var basisuDecodeCalls = 0;
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedPrimitives': <Object?>[
            <String, Object?>{
              'meshIndex': 0,
              'primitiveIndex': 0,
              'attributes': <String, Object?>{
                'POSITION': _float32Bytes(<double>[1, 2, 3]),
              },
              'indices': _uint16Bytes(<int>[0, 0, 0]),
            },
          ],
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        basisuDecodeCalls += 1;
        return <String, Object?>{};
      });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 18,
      maxNativeOutputBytes: 17,
      maxAccessors: 2,
      maxVertices: 1,
      maxIndices: 3,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'component-intermediate.glb',
    );

    expect(result.bytes, isNull);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.none,
    );
    expect(result.diagnostics, hasLength(1));
    expect(
      result.diagnostics.single.details,
      containsPair('field', 'nativeOutputBytes'),
    );
    expect(
      result.diagnostics.single.details,
      containsPair('stage', 'dracoDecodedOutput'),
    );
    expect(basisuDecodeCalls, 0);
    expect(tracker.totalDecodedBytes, 0);
    expect(tracker.nativeOutputBytes, 0);
    expect(tracker.accessors, 0);
    expect(tracker.vertices, 0);
    expect(tracker.indices, 0);
  });

  test(
      'decodeGlb preserves component reservations and returns final opaque mode',
      () async {
    const dracoChannel =
        MethodChannel('test/flutter_scene_viewer/component-then-opaque-draco');
    const basisuChannel =
        MethodChannel('test/flutter_scene_viewer/component-then-opaque-basisu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(dracoChannel, null)
        ..setMockMethodCallHandler(basisuChannel, null);
    });
    final opaqueFinal = _glbWithBin(
      <String, Object?>{
        'asset': <String, Object?>{'version': '2.0'},
        'buffers': <Object?>[
          <String, Object?>{'byteLength': 0},
        ],
      },
      Uint8List(0),
    );
    messenger
      ..setMockMethodCallHandler(dracoChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'decodedPrimitives': <Object?>[
            <String, Object?>{
              'meshIndex': 0,
              'primitiveIndex': 0,
              'attributes': <String, Object?>{
                'POSITION': _float32Bytes(<double>[1, 2, 3]),
              },
              'indices': _uint16Bytes(<int>[0, 0, 0]),
            },
          ],
        };
      })
      ..setMockMethodCallHandler(basisuChannel, (MethodCall call) async {
        return <String, Object?>{
          'diagnostics': <Object?>[],
          'bytes': opaqueFinal,
        };
      });
    const budget = GlbDecodeBudget(
      maxTotalDecodedBytes: 1024,
      maxNativeOutputBytes: 1024,
      maxAccessors: 2,
      maxVertices: 1,
      maxIndices: 3,
    );
    final tracker = GlbDecodeBudgetTracker(budget);

    final result = await const MethodChannelGlbNativeDecoderProbe(
      channel: dracoChannel,
      basisuChannel: basisuChannel,
    ).decodeGlb(
      bytes: _dracoAndBasisuGlb(),
      requiredExtensions: const <String>{
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      },
      budget: budget,
      budgetTracker: tracker,
      source: 'component-then-opaque.glb',
    );

    expect(result.bytes, opaqueFinal);
    expect(result.diagnostics, isEmpty);
    expect(
      result.outputAccounting,
      GlbNativeDecodeOutputAccounting.opaqueFinalBytes,
    );
    expect(tracker.totalDecodedBytes, 18);
    expect(tracker.nativeOutputBytes, 18);
    expect(tracker.accessors, 2);
    expect(tracker.vertices, 1);
    expect(tracker.indices, 3);
  });
}

Uint8List _compressedGlb({int? mode}) {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'componentType': 5126,
          'count': 1,
          'type': 'VEC3',
        },
        <String, Object?>{
          'componentType': 5123,
          'count': 3,
          'type': 'SCALAR',
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
              'indices': 1,
              if (mode != null) 'mode': mode,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _compressedGlbWithAdditionalAttribute() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        <String, Object?>{'buffer': 0, 'byteOffset': 4, 'byteLength': 4},
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'componentType': 5126,
          'count': 1,
          'type': 'VEC3',
        },
        <String, Object?>{
          'bufferView': 1,
          'componentType': 5121,
          'count': 1,
          'type': 'VEC4',
          'normalized': true,
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{
                'POSITION': 0,
                'COLOR_0': 1,
              },
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 7},
                },
              },
            },
          ],
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9, 1, 2, 3, 4]),
  );
}

Uint8List _compressedGlbWithMalformedAdditionalAttribute() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_draco_mesh_compression'],
      'extensionsRequired': <Object?>['KHR_draco_mesh_compression'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        <String, Object?>{'buffer': 0, 'byteOffset': 4, 'byteLength': 4},
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'componentType': 5126,
          'count': 1,
          'type': 'VEC3',
        },
        <String, Object?>{
          'bufferView': 1,
          'componentType': '5121',
          'count': 1,
          'type': 'VEC4',
          'normalized': true,
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{
                'POSITION': 0,
                'COLOR_0': 1,
              },
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 7},
                },
              },
            },
          ],
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9, 1, 2, 3, 4]),
  );
}

Uint8List _basisuGlb({
  int textureCount = 1,
  List<Map<String, Object?>> samplers = const <Map<String, Object?>>[],
  List<int?> samplerIndices = const <int?>[],
}) {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      if (samplers.isNotEmpty) 'samplers': samplers,
      'textures': List<Object?>.generate(
        textureCount,
        (index) => <String, Object?>{
          if (index < samplerIndices.length && samplerIndices[index] != null)
            'sampler': samplerIndices[index],
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ),
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _basisuSingleRoleGlb(String role) {
  final textureInfo = <String, Object?>{'index': 0};
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 4},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
      if (role != 'structuralOnly')
        'materials': <Object?>[
          <String, Object?>{
            if (role == 'color')
              'pbrMetallicRoughness': <String, Object?>{
                'baseColorTexture': textureInfo,
              }
            else
              'normalTexture': textureInfo,
          },
        ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9]),
  );
}

Uint8List _basisuUsageSlotGlb() {
  const textureCount = 13;
  Map<String, Object?> textureInfo(int index, {bool transformed = false}) =>
      <String, Object?>{
        'index': index,
        if (transformed)
          'extensions': <String, Object?>{
            'KHR_texture_transform': <String, Object?>{
              'offset': <Object?>[0, 0],
            },
          },
      };
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>[
        'KHR_texture_basisu',
        'KHR_texture_transform',
        'KHR_materials_specular',
        'KHR_materials_clearcoat',
        'KHR_materials_transmission',
        'KHR_materials_volume',
        'KHR_materials_ior',
      ],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': textureCount * 4},
      ],
      'bufferViews': List<Object?>.generate(
        textureCount,
        (int index) => <String, Object?>{
          'buffer': 0,
          'byteOffset': index * 4,
          'byteLength': 4,
        },
      ),
      'images': List<Object?>.generate(
        textureCount,
        (int index) => <String, Object?>{
          'mimeType': 'image/ktx2',
          'bufferView': index,
        },
      ),
      'textures': List<Object?>.generate(
        textureCount,
        (int index) => <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': index},
          },
        },
      ),
      'materials': <Object?>[
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': textureInfo(0, transformed: true),
            'metallicRoughnessTexture': textureInfo(3),
          },
          'emissiveTexture': textureInfo(1),
          'normalTexture': textureInfo(4),
          'occlusionTexture': textureInfo(5),
          'extensions': <String, Object?>{
            'KHR_materials_specular': <String, Object?>{
              'specularColorTexture': textureInfo(2),
              'specularTexture': textureInfo(6),
            },
            'KHR_materials_clearcoat': <String, Object?>{
              'clearcoatTexture': textureInfo(7),
              'clearcoatRoughnessTexture': textureInfo(8),
              'clearcoatNormalTexture': textureInfo(9),
            },
            'KHR_materials_transmission': <String, Object?>{
              'transmissionTexture': textureInfo(10),
            },
            'KHR_materials_volume': <String, Object?>{
              'thicknessTexture': textureInfo(11),
            },
            'KHR_materials_ior': <String, Object?>{
              'ior': 1.5,
              'iorTexture': textureInfo(12),
            },
          },
        },
      ],
    },
    Uint8List(textureCount * 4),
  );
}

Uint8List _basisuChannelRoleMatrixGlb() {
  const imageCount = 9;
  Map<String, Object?> textureInfo(int index) => <String, Object?>{
        'index': index,
      };
  Map<String, Object?> texture(int source) => <String, Object?>{
        'extensions': <String, Object?>{
          'KHR_texture_basisu': <String, Object?>{'source': source},
        },
      };
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>[
        'KHR_texture_basisu',
        'KHR_materials_specular',
        'KHR_materials_clearcoat',
      ],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': imageCount * 4},
      ],
      'bufferViews': List<Object?>.generate(
        imageCount,
        (int index) => <String, Object?>{
          'buffer': 0,
          'byteOffset': index * 4,
          'byteLength': 4,
        },
      ),
      'images': List<Object?>.generate(
        imageCount,
        (int index) => <String, Object?>{
          'mimeType': 'image/ktx2',
          'bufferView': index,
        },
      ),
      'textures': <Object?>[
        for (var source = 0; source < 7; source += 1) texture(source),
        texture(7),
        texture(7),
        texture(8),
      ],
      'materials': <Object?>[
        <String, Object?>{
          'alphaMode': 'OPAQUE',
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': textureInfo(0),
          },
        },
        <String, Object?>{
          'alphaMode': 'MASK',
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': textureInfo(1),
          },
        },
        <String, Object?>{
          'alphaMode': 'BLEND',
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': textureInfo(2),
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_specular': <String, Object?>{
              'specularColorTexture': textureInfo(3),
              'specularTexture': textureInfo(3),
            },
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_clearcoat': <String, Object?>{
              'clearcoatTexture': textureInfo(4),
              'clearcoatRoughnessTexture': textureInfo(4),
            },
          },
        },
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'metallicRoughnessTexture': textureInfo(5),
          },
          'occlusionTexture': textureInfo(5),
        },
        <String, Object?>{
          'emissiveTexture': textureInfo(6),
          'occlusionTexture': textureInfo(6),
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_specular': <String, Object?>{
              'specularColorTexture': textureInfo(7),
              'specularTexture': textureInfo(8),
            },
          },
        },
      ],
    },
    Uint8List(imageCount * 4),
  );
}

Uint8List _basisuMalformedAlphaModeGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{'buffer': 0, 'byteOffset': 0, 'byteLength': 4},
        <String, Object?>{'buffer': 0, 'byteOffset': 4, 'byteLength': 4},
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 1},
      ],
      'textures': <Object?>[
        for (var index = 0; index < 2; index += 1)
          <String, Object?>{
            'extensions': <String, Object?>{
              'KHR_texture_basisu': <String, Object?>{'source': index},
            },
          },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'alphaMode': 'TRANSMISSION',
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': 0},
          },
        },
        <String, Object?>{
          'alphaMode': 7,
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': <String, Object?>{'index': 1},
          },
        },
      ],
    },
    Uint8List(8),
  );
}

Uint8List _basisuRoleAggregationGlb() {
  Map<String, Object?> textureInfo(int index, {bool transformed = false}) =>
      <String, Object?>{
        'index': index,
        if (transformed)
          'extensions': <String, Object?>{
            'KHR_texture_transform': <String, Object?>{},
          },
      };
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>[
        'KHR_texture_basisu',
        'KHR_texture_transform',
        'KHR_materials_ior',
      ],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 12},
      ],
      'bufferViews': List<Object?>.generate(
        3,
        (int index) => <String, Object?>{
          'buffer': 0,
          'byteOffset': index * 4,
          'byteLength': 4,
        },
      ),
      'images': List<Object?>.generate(
        3,
        (int index) => <String, Object?>{
          'mimeType': 'image/ktx2',
          'bufferView': index,
        },
      ),
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 1},
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 1},
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 2},
          },
        },
      ],
      'materials': <Object?>[
        <String, Object?>{
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorTexture': textureInfo(0, transformed: true),
          },
          'normalTexture': textureInfo(0),
          'emissiveTexture': textureInfo(1),
          'occlusionTexture': textureInfo(2),
          'extensions': <String, Object?>{
            'KHR_materials_ior': <String, Object?>{
              'ior': 1.4,
              'iorTexture': textureInfo(3),
            },
          },
        },
      ],
    },
    Uint8List(12),
  );
}

Uint8List _twoImageBasisuGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>['KHR_texture_basisu'],
      'extensionsRequired': <Object?>['KHR_texture_basisu'],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 4,
          'byteLength': 4,
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 0},
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 1},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 1},
          },
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9, 8, 8, 8, 8]),
  );
}

Uint8List _dracoAndBasisuGlb() {
  return _glbWithBin(
    <String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'extensionsUsed': <Object?>[
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      ],
      'extensionsRequired': <Object?>[
        'KHR_draco_mesh_compression',
        'KHR_texture_basisu',
      ],
      'buffers': <Object?>[
        <String, Object?>{'byteLength': 8},
      ],
      'bufferViews': <Object?>[
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 0,
          'byteLength': 4,
        },
        <String, Object?>{
          'buffer': 0,
          'byteOffset': 4,
          'byteLength': 4,
        },
      ],
      'accessors': <Object?>[
        <String, Object?>{
          'componentType': 5126,
          'count': 1,
          'type': 'VEC3',
        },
        <String, Object?>{
          'componentType': 5123,
          'count': 3,
          'type': 'SCALAR',
        },
      ],
      'meshes': <Object?>[
        <String, Object?>{
          'primitives': <Object?>[
            <String, Object?>{
              'attributes': <String, Object?>{'POSITION': 0},
              'indices': 1,
              'extensions': <String, Object?>{
                'KHR_draco_mesh_compression': <String, Object?>{
                  'bufferView': 0,
                  'attributes': <String, Object?>{'POSITION': 0},
                },
              },
            },
          ],
        },
      ],
      'images': <Object?>[
        <String, Object?>{'mimeType': 'image/ktx2', 'bufferView': 1},
      ],
      'textures': <Object?>[
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_texture_basisu': <String, Object?>{'source': 0},
          },
        },
      ],
    },
    Uint8List.fromList(<int>[9, 9, 9, 9, 8, 8, 8, 8]),
  );
}

Uint8List _glbWithBin(Map<String, Object?> json, Uint8List bin) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final paddedJsonLength = _align4(jsonBytes.length);
  final paddedBinLength = _align4(bin.length);
  final totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinLength;
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (var index = 20 + jsonBytes.length;
      index < 20 + paddedJsonLength;
      index += 1) {
    bytes[index] = 0x20;
  }
  final binHeaderOffset = 20 + paddedJsonLength;
  data
    ..setUint32(binHeaderOffset, paddedBinLength, Endian.little)
    ..setUint32(binHeaderOffset + 4, 0x004E4942, Endian.little);
  bytes.setRange(binHeaderOffset + 8, binHeaderOffset + 8 + bin.length, bin);
  return bytes;
}

Map<String, Object?> _glbJson(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final jsonLength = data.getUint32(12, Endian.little);
  return (jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength))) as Map)
      .cast<String, Object?>();
}

Uint8List _float32Bytes(List<double> values) {
  final bytes = Uint8List(values.length * 4);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < values.length; index += 1) {
    data.setFloat32(index * 4, values[index], Endian.little);
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

int _align4(int value) => (value + 3) & ~3;

Uint8List _pngBytes({required int width, required int height}) {
  final bytes = Uint8List(24);
  bytes.setRange(0, 8, const <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ]);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint32(8, 13)
    ..setUint32(12, 0x49484452)
    ..setUint32(16, width)
    ..setUint32(20, height);
  return bytes;
}
