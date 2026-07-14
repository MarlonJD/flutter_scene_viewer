import 'dart:isolate';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      assetMode: MaterialAssetMode.dataAssetsIfAvailable,
      materials: const <String>[
        'assets/materials/fsviewer_debug_tint.fmat',
        'assets/materials/fsviewer_transmission.fmat',
        'assets/materials/fsviewer_clearcoat.fmat',
      ],
    );
    final flutterSceneBuildHooks = await Isolate.resolvePackageUri(
      Uri.parse('package:flutter_scene/build_hooks.dart'),
    );
    if (flutterSceneBuildHooks == null) {
      throw StateError('Could not resolve flutter_scene shader includes.');
    }
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/fsviewer_extended_pbr.shaderbundle.json',
      includeDirectories: <Uri>[
        flutterSceneBuildHooks.resolve('../shaders/'),
      ],
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
      glesLanguageVersion: 300,
    );
  });
}
