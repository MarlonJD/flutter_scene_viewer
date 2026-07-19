import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  generatePlan016ControlledStudioHdr,
  hashBytes,
  loadPlan016ControlledComparisonState,
  modelCatalog,
  plan016StateHash,
  resolveMaterialAssertions,
  statePath,
  validatePlan016ControlledComparisonState,
} from './plan016_controlled_comparison_contract.mjs';

test('Plan 016 freezes renderer, camera, lighting, display, and pass state', () => {
  const state = loadPlan016ControlledComparisonState();
  assert.doesNotThrow(() => validatePlan016ControlledComparisonState(state));
  assert.equal(state.referenceRenderer.packageVersion, '0.167.1');
  assert.equal(state.referenceRenderer.revision, '167');
  assert.match(state.referenceRenderer.packageIntegrity, /^sha512-/);
  assert.deepEqual(state.renderPasses, ['directOnly', 'iblOnly', 'combined']);
  assert.equal(state.camera.fit, 'frozenCanonicalBoundingSphere');
  assert.equal(state.toneMapping, 'pbrNeutral');
  assert.equal(state.outputColorSpace, 'sRGB');
  assert.equal(state.lighting.ambientOcclusion, false);
  assert.equal(state.lighting.keyLightCastsShadow, false);
  assert.equal(
    state.rendererCoordinateMapping.threejsFromFlutterSceneWorld,
    'mirrorZCameraLightEnvironmentAndBackdrop',
  );
  assert.match(plan016StateHash(), /^[a-f0-9]{64}$/);
  assert.equal(hashBytes(fs.readFileSync(statePath)), plan016StateHash());
});

test('Plan 016 reuses the exact deterministic hash-pinned controlled HDR', () => {
  const state = loadPlan016ControlledComparisonState();
  const first = generatePlan016ControlledStudioHdr(state);
  const second = generatePlan016ControlledStudioHdr(state);
  assert.deepEqual(first, second);
  assert.equal(hashBytes(first), state.environment.sha256);
  assert.match(first.subarray(0, 80).toString('ascii'), /#\?RADIANCE/);
});

test('Plan 016 catalog pins every GLB, license, frame, and material contract', () => {
  const state = loadPlan016ControlledComparisonState();
  const catalog = modelCatalog(state);
  assert.equal(Object.keys(catalog).length, 16);
  assert.deepEqual(
    state.assetSources.khronos,
    {
      repository: 'KhronosGroup/glTF-Sample-Assets',
      commit: '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf',
    },
  );
  for (const model of Object.values(catalog)) {
    assert.match(model.sha256, /^[a-f0-9]{64}$/);
    assert.ok(model.byteLength > 0);
    assert.ok(model.cameraFrame.radius > 0);
    assert.ok(model.materialAssertions.length > 0);
  }
});

test('Plan 016 assertions cover physical glass fields before every capture', () => {
  const state = loadPlan016ControlledComparisonState();
  for (const model of Object.values(state.models)) {
    const assertions = resolveMaterialAssertions(
      state,
      model.materialAssertionProfile,
    );
    for (const assertion of assertions) {
      assert.equal(assertion.isMeshPhysicalMaterial, true);
      for (const field of [
        'transmission',
        'ior',
        'thickness',
        'attenuationDistance',
        'attenuationColor',
        'transmissionMap',
        'thicknessMap',
        'normalMap',
        'clearcoat',
        'clearcoatRoughness',
      ]) {
        assert.ok(field in assertion, `${assertion.name} omits ${field}`);
      }
    }
  }
});

test('Plan 016 thresholds and control pairs exist before Flutter capture', () => {
  const state = loadPlan016ControlledComparisonState();
  assert.equal(
    state.comparisonMetrics.calibrationStatus,
    'calibrated-before-flutter-capture',
  );
  assert.deepEqual(
    state.comparisonMetrics.calibrationControlPairs.transmission,
    ['control_transmission_off', 'control_thin'],
  );
  assert.equal(
    state.comparisonMetrics.thresholds.cameraSilhouetteIouMin,
    0.93,
  );
  assert.equal(
    state.comparisonMetrics.thresholds.alignedMeanAbsoluteRgbMax,
    0.16,
  );
  assert.equal(
    state.comparisonMetrics.thresholds.controlRoughnessEdgeEnergyRatioMax,
    0.9,
  );
  assert.equal(
    state.comparisonMetrics.calibratedThreejsControlSignals
      .attenuationChromaticityDistance,
    0.05336143184846318,
  );
});
