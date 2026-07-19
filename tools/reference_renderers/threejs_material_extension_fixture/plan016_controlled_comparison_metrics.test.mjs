import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildPlan016ComparisonChecks,
  relativeError,
} from './plan016_controlled_comparison_metrics.mjs';

const thresholds = {
  cameraSilhouetteIouMin: 0.93,
  cameraEdgeCentroidMaxLogicalPixels: 2.5,
  alignedMeanAbsoluteRgbMax: 0.16,
  alignedP95AbsoluteRgbMax: 0.42,
  transmittedLuminanceRelativeErrorMax: 0.25,
  attenuationChromaticityDistanceMax: 0.12,
  refractedDisplacementRelativeErrorMax: 0.3,
  refractedDisplacementAbsoluteLogicalPixelsMax: 2.5,
  blurRatioAbsoluteErrorMax: 0.22,
  controlPairMeanAbsoluteRgbSignalMin: 0.015,
  controlRefractedDisplacementLogicalPixelsMin: 1,
  controlAttenuationChromaticityShiftMin: 0.035,
  controlRoughnessEdgeEnergyRatioMax: 0.9,
};

test('relativeError is symmetric around the reference denominator', () => {
  assert.equal(relativeError(12, 10), 0.2);
  assert.equal(relativeError(8, 10), 0.2);
});

test('comparison checks cover every frozen threshold family', () => {
  const metrics = passingMetrics();
  const checks = buildPlan016ComparisonChecks(metrics, thresholds);

  assert.ok(checks.length > 12);
  assert.ok(checks.every((check) => check.passed));
  assert.deepEqual(
    checks.filter((check) => check.name.startsWith('aligned.')).map(
      (check) => check.name,
    ),
    [
      'aligned.control_thin.meanAbsoluteRgb',
      'aligned.control_thin.p95AbsoluteRgb',
    ],
  );
});

test('comparison checks fail the exact metric that crosses a threshold', () => {
  const metrics = passingMetrics();
  metrics.iosControlPairs.attenuation.chromaticityDistance = 0.02;
  const checks = buildPlan016ComparisonChecks(metrics, thresholds);

  const failed = checks.filter((check) => !check.passed);
  assert.deepEqual(
    failed.map((check) => check.name),
    ['iosControl.attenuation.chromaticitySignal'],
  );
});

function passingMetrics() {
  return {
    camera: {
      silhouetteIou: 0.98,
      centroidDistanceLogical: 0.2,
    },
    alignedRendererComparisons: {
      control_thin: {
        meanAbsoluteRgb: 0.04,
        p95AbsoluteRgb: 0.2,
      },
    },
    transmittedLuminance: { relativeError: 0.1 },
    attenuation: { chromaticityDistance: 0.05 },
    ior: {
      displacementRelativeError: 0.1,
      displacementAbsoluteErrorLogical: 0.5,
    },
    roughness: { edgeEnergyRatioAbsoluteError: 0.1 },
    iosControlPairs: {
      transmission: { meanAbsoluteRgb: 0.02 },
      ior: {
        meanAbsoluteRgb: 0.02,
        edgeCentroidDistanceLogical: 2,
      },
      thickness: { meanAbsoluteRgb: 0.02 },
      attenuation: {
        meanAbsoluteRgb: 0.02,
        chromaticityDistance: 0.05,
      },
      roughness: {
        meanAbsoluteRgb: 0.02,
        secondToFirstEdgeEnergyRatio: 0.7,
      },
      normal: { meanAbsoluteRgb: 0.02 },
      worldScale: { meanAbsoluteRgb: 0.02 },
    },
  };
}
