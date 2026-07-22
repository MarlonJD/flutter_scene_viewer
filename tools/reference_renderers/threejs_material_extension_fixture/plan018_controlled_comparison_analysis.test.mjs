import assert from 'node:assert/strict';
import test from 'node:test';

import {
  PLAN018_ANALYSIS_THRESHOLDS,
  assertPlan018FrameHealthy,
  assertPlan018PassTripletHealthy,
  buildPlan018DescriptivePair,
  buildPlan018ExpectedCaptureInventory,
  buildPlan018FrameHealthChecks,
  buildPlan018PassDeltaChecks,
  summarizePlan018Frame,
  validatePlan018AnalysisIdentity,
  validatePlan018CaptureInventory,
  validatePlan018ToyCarRoleEvidence,
} from './plan018_controlled_comparison_analysis.mjs';

test('Plan 018 analysis derives the exact ordered 27-capture inventory', () => {
  const inventory = buildPlan018ExpectedCaptureInventory({
    models: {
      sheen_chair: { cameras: { close: {}, grazing: {} } },
      sheen_cloth: { cameras: { close: {}, grazing: {} } },
      glam_velvet_sofa: { cameras: { close: {}, grazing: {} } },
      toycar: {
        cameras: { close: {}, grazing: {} },
        context: { camera: {} },
      },
    },
    renderPasses: ['directOnly', 'iblOnly', 'combined'],
  });

  assert.equal(inventory.length, 27);
  assert.deepEqual(inventory[0], {
    modelId: 'sheen_chair',
    view: 'close',
    pass: 'directOnly',
    fileName: 'sheen_chair_close_directOnly.png',
  });
  assert.deepEqual(inventory.at(-1), {
    modelId: 'toycar',
    view: 'context',
    pass: 'combined',
    fileName: 'toycar_context_combined.png',
  });
});

test('Plan 018 structurally accepts wildly different cross-renderer pixels', () => {
  const threejs = summarizePlan018Frame(texturedImage([28, 38, 52], 4));
  const flutterIos = summarizePlan018Frame(texturedImage([210, 150, 60], 9));
  const pair = buildPlan018DescriptivePair({ threejs, flutterIos });

  assert.ok(pair.structuralChecks.threejs.every((check) => check.passed));
  assert.ok(pair.structuralChecks.flutterIos.every((check) => check.passed));
  assert.equal(
    pair.comparisonBoundary,
    'descriptive direction/conformance only; no cross-renderer pixel threshold',
  );
  assert.notEqual(pair.descriptive.meanSrgbLuminanceSignedDelta, 0);
  assert.deepEqual(
    Object.keys(pair.descriptive).filter((key) =>
      /pass|fail|expected|threshold/i.test(key),
    ),
    [],
  );
  assert.doesNotMatch(JSON.stringify(pair), /meanAbsoluteRgbMax|pixelParity/);
});

test('Plan 018 ToyCar evidence rejects missing or merged generic roles', () => {
  const roles = {
    authored: [
      role('clearcoat', 0, 'KHR_materials_clearcoat', '/root/body#0'),
      role('sheen', 1, 'KHR_materials_sheen', '/root/cloth#0'),
      role(
        'transmissionVolume',
        2,
        ['KHR_materials_transmission', 'KHR_materials_volume'],
        '/root/glass#0',
      ),
    ],
    installed: [
      role('clearcoat', 0, 'KHR_materials_clearcoat', '/root/body#0'),
      role('sheen', 1, 'KHR_materials_sheen', '/root/cloth#0'),
      role(
        'transmissionVolume',
        2,
        ['KHR_materials_transmission'],
        '/root/glass#0',
      ),
    ],
  };
  assert.doesNotThrow(() => validatePlan018ToyCarRoleEvidence(roles));

  const missing = structuredClone(roles);
  missing.installed.pop();
  assert.throws(
    () => validatePlan018ToyCarRoleEvidence(missing),
    /exact generic extension roles/,
  );

  const merged = structuredClone(roles);
  merged.installed[1].partAddresses = ['/root/body#0'];
  assert.throws(
    () => validatePlan018ToyCarRoleEvidence(merged),
    /distinct PartAddresses/,
  );
});

function role(roleName, materialIndex, extension, partAddress) {
  return {
    role: roleName,
    materialIndex,
    extensions: Array.isArray(extension) ? extension : [extension],
    partAddresses: [partAddress],
    featureActive: true,
  };
}

test('Plan 018 renderer-local health rejects duplicated lighting passes', () => {
  const directOnly = texturedImage([180, 40, 35], 1);
  const iblOnly = texturedImage([45, 80, 180], 2);
  const combined = texturedImage([190, 110, 185], 3);
  assert.doesNotThrow(() =>
    assertPlan018PassTripletHealthy({ directOnly, iblOnly, combined }),
  );

  const duplicated = {
    directOnly,
    iblOnly,
    combined: {
      ...iblOnly,
      data: new Uint8ClampedArray(iblOnly.data),
    },
  };
  assert.deepEqual(
    buildPlan018PassDeltaChecks(duplicated)
      .filter((check) => !check.passed)
      .map((check) => check.name),
    ['passDelta.combinedVsIblOnly'],
  );
  assert.throws(
    () => assertPlan018PassTripletHealthy(duplicated),
    /combinedVsIblOnly/,
  );
});

test('Plan 018 renderer-local health rejects blank and flat frames', () => {
  assert.deepEqual(PLAN018_ANALYSIS_THRESHOLDS, {
    backgroundMaxChannelDeltaMin: 4 / 255,
    foregroundFractionMin: 0.001,
    foregroundWidthSpanMin: 0.02,
    foregroundHeightSpanMin: 0.02,
    luminanceP99P01Min: 0.01,
    quantizedRgbBinsMin: 16,
    intraRendererMeanAbsoluteSrgbDeltaMin: 1 / 1024,
  });

  const blank = solidImage(100, 100, [18, 17, 24]);
  const blankSummary = summarizePlan018Frame(blank);
  assert.equal(blankSummary.foregroundFraction, 0);
  assert.throws(
    () => assertPlan018FrameHealthy(blankSummary),
    /foregroundFraction/,
  );

  const flat = solidImage(100, 100, [18, 17, 24]);
  fillRect(flat, 25, 25, 50, 50, [180, 32, 32]);
  const flatSummary = summarizePlan018Frame(flat);
  assert.ok(flatSummary.foregroundFraction > 0.001);
  assert.ok(flatSummary.foregroundWidthSpan > 0.02);
  assert.ok(flatSummary.foregroundHeightSpan > 0.02);
  assert.deepEqual(
    buildPlan018FrameHealthChecks(flatSummary)
      .filter((check) => !check.passed)
      .map((check) => check.name),
    ['frame.luminanceP99P01', 'frame.quantizedRgbBins'],
  );
  assert.throws(
    () => assertPlan018FrameHealthy(flatSummary),
    /luminanceP99P01.*quantizedRgbBins/,
  );
});

function solidImage(width, height, rgb) {
  const data = new Uint8ClampedArray(width * height * 4);
  for (let offset = 0; offset < data.length; offset += 4) {
    data[offset] = rgb[0];
    data[offset + 1] = rgb[1];
    data[offset + 2] = rgb[2];
    data[offset + 3] = 255;
  }
  return { width, height, data, backgroundSrgbHex: '#121118' };
}

function fillRect(image, left, top, width, height, rgb) {
  for (let y = top; y < top + height; y += 1) {
    for (let x = left; x < left + width; x += 1) {
      const offset = (y * image.width + x) * 4;
      image.data[offset] = rgb[0];
      image.data[offset + 1] = rgb[1];
      image.data[offset + 2] = rgb[2];
    }
  }
}

function texturedImage(baseRgb, phase) {
  const image = solidImage(100, 100, [18, 17, 24]);
  for (let y = 20; y < 80; y += 1) {
    for (let x = 20; x < 80; x += 1) {
      const variation = (x * 3 + y * 5 + phase * 11) % 64;
      fillRect(image, x, y, 1, 1, baseRgb.map((value) =>
        Math.min(255, value + variation),
      ));
    }
  }
  return image;
}

test('Plan 018 analysis rejects stale state, camera, pass, and source identity', () => {
  const expected = {
    stateSha256: 'a'.repeat(64),
    cameraSha256: 'b'.repeat(64),
    passSha256: 'c'.repeat(64),
    sourceSha256: {
      model: 'd'.repeat(64),
      environment: 'e'.repeat(64),
      renderer: 'f'.repeat(64),
    },
  };
  assert.doesNotThrow(() =>
    validatePlan018AnalysisIdentity(expected, structuredClone(expected)),
  );
  for (const mutation of [
    ['state', (identity) => { identity.stateSha256 = '0'.repeat(64); }],
    ['camera', (identity) => { identity.cameraSha256 = '0'.repeat(64); }],
    ['pass', (identity) => { identity.passSha256 = '0'.repeat(64); }],
    ['source', (identity) => { identity.sourceSha256.renderer = '0'.repeat(64); }],
  ]) {
    const actual = structuredClone(expected);
    mutation[1](actual);
    assert.throws(
      () => validatePlan018AnalysisIdentity(expected, actual),
      new RegExp(`Plan 018 ${mutation[0]} identity drifted`),
    );
  }
});

test('Plan 018 analysis rejects missing, extra, and reordered inventory', () => {
  const expected = Array.from({ length: 27 }, (_, index) => ({
    modelId: `model_${Math.floor(index / 3)}`,
    view: `view_${Math.floor(index / 3)}`,
    pass: ['directOnly', 'iblOnly', 'combined'][index % 3],
    fileName: `capture_${index}.png`,
  }));

  assert.doesNotThrow(() =>
    validatePlan018CaptureInventory(expected, structuredClone(expected)),
  );
  assert.throws(
    () => validatePlan018CaptureInventory(expected, expected.slice(0, -1)),
    /exact ordered 27-capture inventory/,
  );
  assert.throws(
    () =>
      validatePlan018CaptureInventory(expected, [
        ...expected,
        { ...expected[0], fileName: 'extra.png' },
      ]),
    /exact ordered 27-capture inventory/,
  );
  const reordered = structuredClone(expected);
  [reordered[0], reordered[1]] = [reordered[1], reordered[0]];
  assert.throws(
    () => validatePlan018CaptureInventory(expected, reordered),
    /exact ordered 27-capture inventory/,
  );
});
