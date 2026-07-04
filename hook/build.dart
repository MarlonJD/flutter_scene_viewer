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
  });
}
