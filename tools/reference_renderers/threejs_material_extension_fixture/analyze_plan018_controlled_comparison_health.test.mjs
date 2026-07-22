import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  plan018ThreeHealthBaselinePath,
  cleanupPlan018AnalysisResources,
  runPlan018ThreeCaptureHealthAnalysis,
  validatePlan018ThreeHealthEvidence,
} from './analyze_plan018_controlled_comparison_health.mjs';

test(
  'Plan 018 current Three captures pass frozen renderer-local health',
  { timeout: 120_000 },
  async () => {
    const evidence = await runPlan018ThreeCaptureHealthAnalysis();
    assert.doesNotThrow(() => validatePlan018ThreeHealthEvidence(evidence));
    assert.equal(evidence.status, 'verified locally');
    assert.equal(
      evidence.scope,
      'pinned Three.js renderer-local capture health baseline',
    );
    assert.equal(evidence.frames.length, 27);
    assert.equal(evidence.passTriplets.length, 9);
    assert.ok(
      evidence.frames.every((frame) =>
        frame.checks.every((check) => check.passed),
      ),
    );
    assert.ok(
      evidence.passTriplets.every((triplet) =>
        triplet.checks.every((check) => check.passed),
      ),
    );
    assert.deepEqual(evidence.crossRendererPixelThresholds, []);
    assert.equal(evidence.boardsProduced, false);
    assert.equal(evidence.fullFrameOnly, true);
    assert.equal(evidence.captureEvidenceStatus, 'current');
    assert.deepEqual(evidence.captureEvidenceSourceDrifts, []);
    assert.equal(evidence.darkestFrames.byMeanSrgbLuminance.fileName.length > 0, true);
    assert.equal(evidence.darkestFrames.byLuminanceSpread.fileName.length > 0, true);

    const recorded = JSON.parse(
      fs.readFileSync(plan018ThreeHealthBaselinePath, 'utf8'),
    );
    assert.deepEqual(recorded, evidence);
  },
);

test('Plan 018 analysis cleanup attempts every resource after failure', async () => {
  const calls = [];
  await assert.rejects(
    () =>
      cleanupPlan018AnalysisResources({
        disposePage: async () => calls.push('page'),
        closeBrowser: async () => {
          calls.push('browser');
          throw new Error('browser close failed');
        },
        closeServer: async () => calls.push('server'),
        removeProfile: () => calls.push('profile'),
      }),
    /Plan 018 analysis cleanup failed/,
  );
  assert.deepEqual(calls, ['page', 'browser', 'server', 'profile']);
});
