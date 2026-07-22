import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _sourcePath = 'test/fixtures/MultiMaterialAssembly.glb';
const _fixturePath = 'test/fixtures/Plan018RendererNativeSheenControl.glb';
const _generatorPath =
    'tools/generate_plan018_renderer_native_sheen_fixture.py';
const _baseStatePath = 'tools/material_extension_acceptance/fixtures/'
    'plan018_controlled_comparison_state.json';
const _controlStatePath = 'tools/material_extension_acceptance/fixtures/'
    'plan018_renderer_native_scalar_sheen_control_state.json';
const _sourceSha256 =
    '5f717f321050c3049a29cdf3e3223ad10fd05ce485a088011f77d84357b9ad5f';
const _fixtureSha256 =
    '8c0d893fbf72553b3dbf4d9bf8bfa3a1a24bbbfebd699beee5cf72a8216d967d';
const _binaryChunkSha256 =
    '8030b3e4654c54a4b6f4dc5b72832da20064ff3217c1fafccc30ac7d4bb0fdea';
const _baseStateSha256 =
    '385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843';

void main() {
  test('Plan 018 native sheen control changes only scalar material JSON',
      () async {
    final sourceFile = File(_sourcePath);
    final fixtureFile = File(_fixturePath);
    final generatorFile = File(_generatorPath);
    expect(sourceFile.existsSync(), isTrue);
    expect(fixtureFile.existsSync(), isTrue);
    expect(generatorFile.existsSync(), isTrue);

    final sourceBytes = sourceFile.readAsBytesSync();
    final fixtureBytes = fixtureFile.readAsBytesSync();
    expect(sha256.convert(sourceBytes).toString(), _sourceSha256);

    final source = _readGlb(sourceBytes);
    final fixture = _readGlb(fixtureBytes);
    expect(fixture.binaryChunk, orderedEquals(source.binaryChunk));

    final fixtureDocument = _deepCopy(fixture.document);
    expect(
      fixtureDocument.remove('extensionsUsed'),
      <Object?>['KHR_materials_sheen'],
    );
    expect(fixtureDocument.containsKey('extensionsRequired'), isFalse);
    final fixtureMaterials =
        (fixtureDocument['materials']! as List<Object?>).cast<Map>();
    final extensions = Map<String, Object?>.from(
      fixtureMaterials.first.remove('extensions')! as Map,
    );
    expect(extensions.keys, <String>['KHR_materials_sheen']);
    expect(extensions['KHR_materials_sheen'], <String, Object?>{
      'sheenColorFactor': <Object?>[1, 1, 1],
      'sheenRoughnessFactor': 0.5,
    });
    expect(
      jsonEncode(fixtureDocument),
      jsonEncode(source.document),
      reason: 'The control must not alter geometry, UVs, or core materials.',
    );
    expect(fixture.document.containsKey('textures'), isFalse);
    expect(fixture.document.containsKey('images'), isFalse);
    expect(fixture.document.containsKey('samplers'), isFalse);

    final meshes = (fixture.document['meshes']! as List<Object?>).cast<Map>();
    for (final mesh in meshes) {
      final primitives = (mesh['primitives']! as List<Object?>).cast<Map>();
      for (final primitive in primitives) {
        final attributes = Map<String, Object?>.from(
          primitive['attributes']! as Map,
        );
        expect(attributes.containsKey('NORMAL'), isTrue);
        expect(attributes.containsKey('TEXCOORD_0'), isTrue);
        expect(attributes.containsKey('TEXCOORD_1'), isFalse);
      }
    }

    final temporary = await Directory.systemTemp.createTemp(
      'plan018_renderer_native_sheen_fixture_',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final generatedPath = '${temporary.path}/control.glb';
    final generated = await Process.run(
      'python3',
      <String>[_generatorPath, '--output', generatedPath],
      environment: <String, String>{'PYTHONDONTWRITEBYTECODE': '1'},
    );
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    expect(
      File(generatedPath).readAsBytesSync(),
      orderedEquals(fixtureBytes),
    );
  });

  test('Plan 018 native sheen control has a separate honest evidence state',
      () {
    final baseStateFile = File(_baseStatePath);
    final controlStateFile = File(_controlStatePath);
    expect(
      sha256.convert(baseStateFile.readAsBytesSync()).toString(),
      _baseStateSha256,
      reason: 'The historical four-model candidate state is immutable.',
    );
    expect(controlStateFile.existsSync(), isTrue);

    final baseState = Map<String, Object?>.from(
      jsonDecode(baseStateFile.readAsStringSync()) as Map,
    );
    final controlState = Map<String, Object?>.from(
      jsonDecode(controlStateFile.readAsStringSync()) as Map,
    );
    expect(controlState['schemaVersion'], 1);
    expect(
      controlState['name'],
      'plan018_renderer_native_scalar_sheen_control',
    );
    expect(
      controlState['comparisonBoundary'],
      'renderer-local sheen on/off control only',
    );
    expect(
      controlState['sharedComparisonState'],
      <String, Object?>{
        'path': _baseStatePath,
        'sha256': _baseStateSha256,
      },
    );
    for (final key in <String>[
      'viewport',
      'background',
      'camera',
      'environment',
      'lighting',
      'renderPasses',
      'toneMapping',
      'outputColorSpace',
    ]) {
      expect(
        jsonEncode(controlState[key]),
        jsonEncode(baseState[key]),
        reason: '$key must reuse the frozen comparison state exactly.',
      );
    }
    expect(controlState.containsKey('referenceRenderer'), isFalse);
    expect(
      controlState['referenceComparison'],
      <String, Object?>{
        'status': 'not run',
        'acceptedEvidence': false,
        'claim': 'no external reference or general pixel parity',
      },
    );
    expect(
      controlState['evidence'],
      <String, Object?>{
        'runtimeAvailability': 'not run',
        'featureMaturity': 'release pending',
        'targetEvidence': <String, Object?>{
          'iosSimulator': 'not run',
          'physicalIos': 'not run',
          'android': 'not run',
          'web': 'not run',
        },
        'visualEvidence': 'not run',
        'physicalCorrectness': 'not run',
        'productionReady': 'not run',
      },
    );

    final models = Map<String, Object?>.from(controlState['models']! as Map);
    expect(
      models.keys,
      <String>[
        'renderer_native_scalar_sheen_on',
        'renderer_native_scalar_sheen_off',
      ],
    );
    final on = Map<String, Object?>.from(
      models['renderer_native_scalar_sheen_on']! as Map,
    );
    final off = Map<String, Object?>.from(
      models['renderer_native_scalar_sheen_off']! as Map,
    );
    expect(on['controlRole'], 'sheenOn');
    expect(on['expectedApplication'], 'rendererNative');
    expect(on['path'], _fixturePath);
    expect(on['sha256'], _fixtureSha256);
    expect(on['byteLength'], 2848);
    expect(on['sourcePath'], _sourcePath);
    expect(on['sourceSha256'], _sourceSha256);
    expect(on['sourceByteLength'], 2716);
    expect(on['generatorPath'], _generatorPath);
    expect(on['binaryChunkSha256'], _binaryChunkSha256);
    expect(on['binaryChunkByteLength'], 840);
    expect(on['sheenMaterialIndices'], <Object?>[0]);
    expect(off['controlRole'], 'sheenOff');
    expect(off['expectedApplication'], 'none');
    expect(off['path'], _sourcePath);
    expect(off['sha256'], _sourceSha256);
    expect(off['byteLength'], 2716);
    expect(off['sheenMaterialIndices'], isEmpty);
    expect(jsonEncode(off['cameras']), jsonEncode(on['cameras']));
    expect(jsonEncode(off['sourceBounds']), jsonEncode(on['sourceBounds']));
    expect(
      jsonEncode(off['focusPrimitiveBounds']),
      jsonEncode(on['focusPrimitiveBounds']),
    );

    final onBytes = File(on['path']! as String).readAsBytesSync();
    final offBytes = File(off['path']! as String).readAsBytesSync();
    expect(sha256.convert(onBytes).toString(), on['sha256']);
    expect(sha256.convert(offBytes).toString(), off['sha256']);
    expect(onBytes.lengthInBytes, on['byteLength']);
    expect(offBytes.lengthInBytes, off['byteLength']);
    expect(
      sha256.convert(_readGlb(onBytes).binaryChunk).toString(),
      _binaryChunkSha256,
    );
    expect(
      sha256.convert(_readGlb(offBytes).binaryChunk).toString(),
      _binaryChunkSha256,
    );
  });
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

_Glb _readGlb(Uint8List bytes) {
  if (bytes.lengthInBytes < 28) {
    throw const FormatException('GLB is too short.');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(0, Endian.little) != 0x46546c67 ||
      data.getUint32(4, Endian.little) != 2 ||
      data.getUint32(8, Endian.little) != bytes.lengthInBytes) {
    throw const FormatException('GLB header is invalid.');
  }
  final jsonLength = data.getUint32(12, Endian.little);
  if (data.getUint32(16, Endian.little) != 0x4e4f534a) {
    throw const FormatException('GLB JSON chunk is missing.');
  }
  final jsonEnd = 20 + jsonLength;
  final document = Map<String, Object?>.from(
    jsonDecode(
      utf8.decode(bytes.sublist(20, jsonEnd)).trimRight(),
    ) as Map,
  );
  if (jsonEnd + 8 > bytes.lengthInBytes ||
      data.getUint32(jsonEnd + 4, Endian.little) != 0x004e4942) {
    throw const FormatException('GLB BIN chunk is missing.');
  }
  final binaryLength = data.getUint32(jsonEnd, Endian.little);
  final binaryStart = jsonEnd + 8;
  final binaryEnd = binaryStart + binaryLength;
  if (binaryEnd != bytes.lengthInBytes) {
    throw const FormatException('GLB BIN length is invalid.');
  }
  return _Glb(
    document: document,
    binaryChunk: Uint8List.fromList(bytes.sublist(binaryStart, binaryEnd)),
  );
}

final class _Glb {
  const _Glb({required this.document, required this.binaryChunk});

  final Map<String, Object?> document;
  final Uint8List binaryChunk;
}
