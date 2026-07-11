import 'dart:convert';
import 'dart:io';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('acceptance reference state matches studio lighting defaults', () {
    final referenceState = jsonDecode(
      File(
        'tools/material_extension_acceptance/fixtures/reference_state.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    const lighting = ViewerLighting.studio();

    expect(referenceState['schemaVersion'], 1);
    expect(
      referenceState['lighting'],
      <String, Object?>{
        'kind': lighting.kind.name,
        'exposure': lighting.exposure,
        'ambientOcclusion': lighting.ambientOcclusion,
        'environmentIntensity': lighting.environmentIntensity,
        'keyLightIntensity': lighting.keyLightIntensity,
        'keyLightColor': lighting.keyLightColor,
        'keyLightDirection': lighting.keyLightDirection,
        'keyLightCastsShadow': lighting.keyLightCastsShadow,
      },
    );
  });

  test('studio lighting exposes opt-in key-light shadow quality controls', () {
    const lighting = ViewerLighting.studio(
      keyLightCastsShadow: true,
      keyLightShadowMapResolution: 4096,
      keyLightShadowMaxDistance: 8,
      keyLightShadowSoftness: 0.03,
      keyLightShadowFadeRange: 0.75,
      keyLightShadowDepthBias: 0.01,
      keyLightShadowNormalBias: 0.015,
      keyLightShadowCascadeCount: 2,
      keyLightShadowCascadeSplitLambda: 0.75,
    );

    expect(lighting.keyLightCastsShadow, isTrue);
    expect(lighting.keyLightShadowMapResolution, 4096);
    expect(lighting.keyLightShadowMaxDistance, 8);
    expect(lighting.keyLightShadowSoftness, 0.03);
    expect(lighting.keyLightShadowFadeRange, 0.75);
    expect(lighting.keyLightShadowDepthBias, 0.01);
    expect(lighting.keyLightShadowNormalBias, 0.015);
    expect(lighting.keyLightShadowCascadeCount, 2);
    expect(lighting.keyLightShadowCascadeSplitLambda, 0.75);
  });

  test('key-light shadows stay disabled by default', () {
    const lighting = ViewerLighting.studio();

    expect(lighting.keyLightCastsShadow, isFalse);
    expect(lighting.keyLightShadowMapResolution, 1024);
    expect(lighting.keyLightShadowMaxDistance, 150);
  });
}
