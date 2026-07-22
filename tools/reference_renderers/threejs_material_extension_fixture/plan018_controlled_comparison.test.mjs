import assert from 'node:assert/strict';
import test from 'node:test';

import {
  loadPlan018ControlledComparisonState,
  modelCatalog,
  plan018StateHash,
} from './plan018_controlled_comparison_contract.mjs';

const expectedModelIds = [
  'sheen_chair',
  'sheen_cloth',
  'glam_velvet_sofa',
  'toycar',
];

test('Plan 018 fixed comparison state is immutable and source complete', () => {
  const state = loadPlan018ControlledComparisonState();
  const catalog = modelCatalog(state);

  assert.equal(state.schemaVersion, 1);
  assert.equal(
    state.name,
    'plan018_khr_materials_sheen_controlled_comparison',
  );
  assert.deepEqual(Object.keys(catalog), expectedModelIds);
  assert.deepEqual(state.renderPasses, ['directOnly', 'iblOnly', 'combined']);
  assert.equal(state.toneMapping, 'pbrNeutral');
  assert.equal(state.outputColorSpace, 'sRGB');
  assert.deepEqual(state.camera, {
    verticalFovDegrees: 60,
    near: 0.1,
    far: 1000,
    up: [0, 1, 0],
  });
  assert.equal(state.referenceRenderer.packageVersion, '0.167.1');
  assert.equal(state.referenceRenderer.revision, '167');
  assert.equal(
    state.referenceRenderer.sourceCommit,
    '42a2f6aac8cffebb29524d68eb7136a756f15960',
  );
  assert.equal(state.referenceRenderer.backend, 'WebGL');
  assert.match(state.referenceRenderer.packageIntegrity, /^sha512-/);
  assert.match(state.referenceRenderer.packageLockSha256, /^[a-f0-9]{64}$/);
  assert.deepEqual(
    Object.keys(state.referenceRenderer.sourceSha256),
    [
      'gltfLoader',
      'webglRenderer',
      'physicalSheenParsFragment',
      'physicalSheenFragment',
    ],
  );
  assert.equal(
    state.assetSource.commit,
    '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf',
  );
  assert.equal(
    state.environment.sha256,
    'ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a',
  );
  assert.deepEqual(state.rendererCoordinateMapping, {
    flutterSceneImportedGltfRoot: 'mirrorZ',
    position: '[x,y,z] => [x,y,-z]',
    target: '[x,y,z] => [x,y,-z]',
    up: '[x,y,z] => [x,y,-z]',
    directionalLightTravel: '[x,y,z] => [x,y,-z]',
    environment: 'mirrorDecodedColumns',
    backdrop: 'mirrorZ',
  });
  assert.equal(state.comparisonBoundary, 'direction/conformance-only');
  assert.match(plan018StateHash(), /^[a-f0-9]{64}$/);

  for (const [modelId, model] of Object.entries(catalog)) {
    assert.match(model.sha256, /^[a-f0-9]{64}$/);
    assert.ok(model.byteLength > 0);
    assert.match(model.licenseSha256, /^[a-f0-9]{64}$/);
    assert.ok(model.sourceBounds.radius > 0, modelId);
    assert.ok(model.sheenPrimitiveBounds.radius > 0, modelId);
    assert.deepEqual(Object.keys(model.cameras), ['close', 'grazing']);
    for (const camera of Object.values(model.cameras)) {
      assert.equal(camera.position.length, 3);
      assert.equal(camera.target.length, 3);
      assert.ok(camera.position.every(Number.isFinite));
      assert.ok(camera.target.every(Number.isFinite));
    }
  }

  assert.equal(catalog.toycar.focus.material, 'Fabric');
  assert.equal(catalog.toycar.focus.ownership, 'authored-data');
  assert.equal(catalog.toycar.context.mode, 'full-scene');
  assert.equal(catalog.toycar.context.camera.coordinateSpace, 'flutterSceneWorld');
  assert.equal(catalog.toycar.context.camera.position.length, 3);
  assert.equal(catalog.toycar.context.camera.target.length, 3);
  assert.match(catalog.toycar.context.purpose, /Fabric.*ToyCar.*Glass/);
  assert.deepEqual(catalog.toycar.context.separateMaterialRoles, {
    clearcoat: ['ToyCar'],
    transmission: ['Glass'],
  });
});

test('pinned GLTFLoader consumes every authored sheen input', async () => {
  const { runPlan018SheenLoaderAudit } = await import(
    './inspect_plan018_sheen_loader.mjs'
  );
  const result = await runPlan018SheenLoaderAudit();

  assert.equal(result.status, 'verified locally');
  assert.equal(result.scope, 'Three.js GLTFLoader consumption only');
  assert.equal(result.renderer.revision, '167');
  assert.equal(result.renderer.backend, 'WebGL');
  assert.deepEqual(Object.keys(result.models), expectedModelIds);
  assert.deepEqual(result.collectiveCoverage, {
    sheenColorFactor: true,
    sheenColorTexture: true,
    sheenRoughnessFactor: true,
    sheenRoughnessTexture: true,
  });

  const cloth = result.models.sheen_cloth.materials[0];
  assert.equal(cloth.authored.materialName, 'SheenClothMat');
  assert.equal(cloth.actual.sheen, 1);
  assert.equal(cloth.actual.sheenColorMap.sourceIndex, cloth.actual.sheenRoughnessMap.sourceIndex);
  assert.equal(cloth.actual.sheenColorMap.channelRole, 'rgb');
  assert.equal(cloth.actual.sheenColorMap.colorSpace, 'srgb');
  assert.equal(cloth.actual.sheenRoughnessMap.channelRole, 'alpha');
  assert.equal(cloth.actual.sheenRoughnessMap.colorSpace, 'linear');
  assert.deepEqual(cloth.actual.sheenColorMap.transform, cloth.authored.sheenColorTexture.transform);
  assert.deepEqual(
    cloth.actual.sheenRoughnessMap.transform,
    cloth.authored.sheenRoughnessTexture.transform,
  );
});
