import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import test from 'node:test';

import {
  buildPlan018RendererNativeControlInventory,
  buildPlan018RendererNativeControlVisualAnalysis,
  validatePlan018RendererNativeControlVisualAnalysis,
} from './analyze_plan018_renderer_native_sheen_control.mjs';

const stateBytes = fs.readFileSync(new URL(
  '../../material_extension_acceptance/fixtures/' +
    'plan018_renderer_native_scalar_sheen_control_state.json',
  import.meta.url,
));
const state = JSON.parse(stateBytes);
const stateSha256 = sha256(stateBytes);

test('renderer-native control binds six healthy frames and three on/off deltas', () => {
  const inventory = buildPlan018RendererNativeControlInventory(state);
  assert.deepEqual(
    inventory.map((record) => record.fileName),
    [
      'renderer_native_scalar_sheen_on_grazing_directOnly.png',
      'renderer_native_scalar_sheen_on_grazing_iblOnly.png',
      'renderer_native_scalar_sheen_on_grazing_combined.png',
      'renderer_native_scalar_sheen_off_grazing_directOnly.png',
      'renderer_native_scalar_sheen_off_grazing_iblOnly.png',
      'renderer_native_scalar_sheen_off_grazing_combined.png',
    ],
  );

  const images = healthyControlImages(inventory);
  const captures = Object.fromEntries(inventory.map((record, index) => [
    record.fileName,
    {
      path: record.fileName,
      sha256: index.toString(16).padStart(64, '0'),
      byteLength: 1000 + index,
      dimensions: { width: 32, height: 32 },
    },
  ]));
  const analysis = buildPlan018RendererNativeControlVisualAnalysis({
    state,
    stateSha256,
    inventory,
    images,
    captures,
    analysisSourceSha256: {
      'plan018_controlled_comparison_analysis.mjs': 'a'.repeat(64),
      'analyze_plan018_renderer_native_sheen_control.mjs': 'b'.repeat(64),
      'analyze_plan018_renderer_native_sheen_control.test.mjs': 'c'.repeat(64),
    },
  });

  assert.doesNotThrow(() =>
    validatePlan018RendererNativeControlVisualAnalysis(analysis, {
      state,
      stateSha256,
      inventory,
      captures,
      verifyAnalysisSources: false,
    }),
  );
  assert.equal(analysis.status, 'verified locally');
  assert.equal(analysis.visualEvidence, 'verified locally');
  assert.equal(analysis.featureMaturity, 'release pending');
  assert.deepEqual(analysis.application, {
    sheenOn: 'rendererNative',
    sheenOff: 'none',
  });
  assert.equal(analysis.frameCount, 6);
  assert.equal(analysis.onOffComparisonCount, 3);
  assert.deepEqual(analysis.crossRendererPixelThresholds, []);
  assert.equal(analysis.externalReference, 'not run');
  assert.equal(analysis.physicalIos, 'not run');
  assert.equal(analysis.android, 'not run');
  assert.equal(analysis.web, 'not run');
  assert.equal(analysis.physicalCorrectness, 'not run');
  assert.equal(analysis.generalPixelParity, 'not run');
  assert.equal(analysis.productionReadiness, 'not run');
  assert.ok(
    analysis.onOffComparisons.every((comparison) => comparison.check.passed),
  );

  const noVisualEffect = { ...images };
  noVisualEffect[
    'renderer_native_scalar_sheen_on_grazing_combined.png'
  ] = structuredClone(
    images['renderer_native_scalar_sheen_off_grazing_combined.png'],
  );
  assert.throws(
    () => buildPlan018RendererNativeControlVisualAnalysis({
      state,
      stateSha256,
      inventory,
      images: noVisualEffect,
      captures,
      analysisSourceSha256: {},
    }),
    /renderer-native sheen on\/off delta failed: combined/u,
  );

  const candidateLabel = structuredClone(analysis);
  candidateLabel.featureMaturity = 'candidate-only';
  assert.throws(
    () => validatePlan018RendererNativeControlVisualAnalysis(candidateLabel, {
      state,
      stateSha256,
      inventory,
      captures,
      verifyAnalysisSources: false,
    }),
    /renderer-native visual evidence boundary changed/u,
  );
});

test('renderer-native control has a dedicated aggregate verification script', () => {
  const packageJson = JSON.parse(
    fs.readFileSync(new URL('./package.json', import.meta.url)),
  );
  assert.equal(
    packageJson.scripts['test:plan018-native-analysis'],
    'node --test analyze_plan018_renderer_native_sheen_control.test.mjs',
  );
});

function healthyControlImages(inventory) {
  const passBase = {
    directOnly: 44,
    iblOnly: 72,
    combined: 104,
  };
  return Object.fromEntries(inventory.map((record) => [
    record.fileName,
    image(
      passBase[record.pass] +
        (record.modelId.endsWith('_on') ? 24 : 0),
    ),
  ]));
}

function image(base) {
  const width = 32;
  const height = 32;
  const data = new Uint8ClampedArray(width * height * 4);
  for (let offset = 0; offset < data.length; offset += 4) {
    data[offset] = 18;
    data[offset + 1] = 17;
    data[offset + 2] = 24;
    data[offset + 3] = 255;
  }
  for (let y = 4; y < 28; y += 1) {
    for (let x = 4; x < 28; x += 1) {
      const offset = (y * width + x) * 4;
      const variation = (x * 7 + y * 11) % 96;
      data[offset] = Math.min(255, base + variation);
      data[offset + 1] = Math.min(255, base + ((variation * 3) % 80));
      data[offset + 2] = Math.min(255, base + ((variation * 5) % 72));
    }
  }
  return { width, height, data, backgroundSrgbHex: '#121118' };
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}
