import 'dart:typed_data';

import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('studio environment defaults are const-friendly viewer defaults', () {
    const environment = ViewerEnvironment.studio();

    expect(environment, isA<ViewerStudioEnvironment>());
    expect(environment.intensity, 1.0);
    expect(environment.rotationRadians, 0.0);
    expect(environment.showSkybox, isFalse);
    expect(environment.skyboxBlur, 0.0);
  });

  test('empty environment keeps only the optional skybox flag', () {
    const environment = ViewerEnvironment.empty(showSkybox: true);

    expect(environment, isA<ViewerEmptyEnvironment>());
    expect(environment.intensity, 0.0);
    expect(environment.rotationRadians, 0.0);
    expect(environment.showSkybox, isTrue);
    expect(environment.skyboxBlur, 0.0);
  });

  test('asset environment stores radiance image and presentation controls', () {
    const environment = ViewerEnvironment.asset(
      'assets/env/studio.png',
      intensity: 0.65,
      rotationRadians: 1.25,
      showSkybox: true,
      skyboxBlur: 0.4,
    );

    expect(environment, isA<ViewerAssetEnvironment>());
    expect(
      (environment as ViewerAssetEnvironment).radianceImageAsset,
      'assets/env/studio.png',
    );
    expect(environment.intensity, 0.65);
    expect(environment.rotationRadians, 1.25);
    expect(environment.showSkybox, isTrue);
    expect(environment.skyboxBlur, 0.4);
  });

  test('raw asset environment stores HDR decoder controls', () {
    const environment = ViewerEnvironment.rawAsset(
      'assets/env/studio.hdr',
      format: ViewerEnvironmentFileFormat.hdr,
      intensity: 0.75,
      rotationRadians: 0.5,
      showSkybox: true,
      skyboxBlur: 0.25,
    );

    expect(environment, isA<ViewerRawAssetEnvironment>());
    final raw = environment as ViewerRawAssetEnvironment;
    expect(raw.assetPath, 'assets/env/studio.hdr');
    expect(raw.format, ViewerEnvironmentFileFormat.hdr);
    expect(environment.intensity, 0.75);
    expect(environment.rotationRadians, 0.5);
    expect(environment.showSkybox, isTrue);
    expect(environment.skyboxBlur, 0.25);
  });

  test('raw byte environment compares by byte identity and debug name', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);

    expect(
      ViewerEnvironment.rawBytes(
        bytes,
        debugName: 'inline.exr',
        format: ViewerEnvironmentFileFormat.exr,
      ),
      ViewerEnvironment.rawBytes(
        bytes,
        debugName: 'inline.exr',
        format: ViewerEnvironmentFileFormat.exr,
      ),
    );
    expect(
      ViewerEnvironment.rawBytes(Uint8List.fromList(<int>[1, 2, 3])),
      isNot(
        ViewerEnvironment.rawBytes(Uint8List.fromList(<int>[1, 2, 3])),
      ),
    );
  });

  test('Poly Haven environment requires explicit id, resolution, and agent',
      () {
    const environment = ViewerEnvironment.polyHaven(
      assetId: 'venice_sunset',
      resolution: ViewerPolyHavenResolution.oneK,
      fileType: ViewerPolyHavenFileType.hdr,
      userAgent: 'flutter_scene_viewer_test/1.0',
      intensity: 0.9,
      showSkybox: true,
    );

    expect(environment, isA<ViewerPolyHavenEnvironment>());
    final polyHaven = environment as ViewerPolyHavenEnvironment;
    expect(polyHaven.assetId, 'venice_sunset');
    expect(polyHaven.resolution.apiValue, '1k');
    expect(polyHaven.fileType.apiValue, 'hdr');
    expect(polyHaven.userAgent, 'flutter_scene_viewer_test/1.0');
    expect(polyHaven.intensity, 0.9);
    expect(polyHaven.showSkybox, isTrue);
  });

  test('environment values compare by variant and constructor fields', () {
    expect(
      const ViewerEnvironment.studio(
        intensity: 0.8,
        rotationRadians: 0.2,
        showSkybox: true,
        skyboxBlur: 0.1,
      ),
      const ViewerEnvironment.studio(
        intensity: 0.8,
        rotationRadians: 0.2,
        showSkybox: true,
        skyboxBlur: 0.1,
      ),
    );
    expect(
      const ViewerEnvironment.asset('assets/a.png'),
      isNot(const ViewerEnvironment.asset('assets/b.png')),
    );
    expect(
      const ViewerEnvironment.studio(),
      isNot(const ViewerEnvironment.empty()),
    );
    expect(
      const ViewerEnvironment.rawAsset(
        'assets/a.hdr',
        format: ViewerEnvironmentFileFormat.hdr,
      ),
      isNot(
        const ViewerEnvironment.rawAsset(
          'assets/a.exr',
          format: ViewerEnvironmentFileFormat.exr,
        ),
      ),
    );
    expect(
      const ViewerEnvironment.polyHaven(
        assetId: 'a',
        resolution: ViewerPolyHavenResolution.oneK,
        userAgent: 'test-agent',
      ),
      isNot(
        const ViewerEnvironment.polyHaven(
          assetId: 'a',
          resolution: ViewerPolyHavenResolution.twoK,
          userAgent: 'test-agent',
        ),
      ),
    );
  });
}
