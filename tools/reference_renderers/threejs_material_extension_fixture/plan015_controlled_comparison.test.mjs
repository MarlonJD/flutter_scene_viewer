import assert from 'node:assert/strict';
import test from 'node:test';

import {
  generateControlledStudioHdr,
  hashBytes,
  loadControlledComparisonState,
  validateControlledComparisonState,
} from './plan015_controlled_comparison_contract.mjs';

test('Plan 015 comparison freezes camera, lighting, display, and pass state', () => {
  const state = loadControlledComparisonState();
  assert.doesNotThrow(() => validateControlledComparisonState(state));
  assert.deepEqual(state.renderPasses, ['directOnly', 'iblOnly', 'combined']);
  assert.equal(state.camera.verticalFovDegrees, 60);
  assert.equal(state.camera.fitPadding, 1.15);
  assert.equal(state.modelFrames.toycar.radius, 0.054071809790058344);
  assert.equal(
    state.rendererCoordinateMapping.threejsFromFlutterSceneWorld,
    'mirrorZCameraLightAndEnvironment',
  );
  assert.equal(state.toneMapping, 'pbrNeutral');
  assert.equal(state.outputColorSpace, 'sRGB');
  assert.equal(state.lighting.ambientOcclusion, false);
  assert.equal(state.lighting.keyLightCastsShadow, false);
  assert.equal(
    state.environment.threejsLongitudeCorrection,
    'mirrorDecodedColumns',
  );
});

test('Plan 015 synthetic HDR is deterministic and hash-pinned', () => {
  const state = loadControlledComparisonState();
  const first = generateControlledStudioHdr(state);
  const second = generateControlledStudioHdr(state);
  assert.deepEqual(first, second);
  assert.equal(hashBytes(first), state.environment.sha256);
  assert.match(first.subarray(0, 80).toString('ascii'), /#\?RADIANCE/);
  assert.equal(
    first.length,
    first.indexOf(Buffer.from(`-Y ${state.environment.height} +X ${state.environment.width}\n`)) +
      `-Y ${state.environment.height} +X ${state.environment.width}\n`.length +
      state.environment.width * state.environment.height * 4,
  );
});
