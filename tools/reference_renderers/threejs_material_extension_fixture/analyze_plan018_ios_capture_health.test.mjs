import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  buildPlan018IosHealthEvidence,
  validatePlan018IosHealthEvidence,
  validateStoredPlan018IosHealthEvidence,
} from './analyze_plan018_ios_capture_health.mjs';
import {
  PLAN018_ANALYSIS_THRESHOLDS,
  buildPlan018ExpectedCaptureInventory,
  buildPlan018FrameHealthChecks,
} from './plan018_controlled_comparison_analysis.mjs';
import { repoRoot } from './plan018_controlled_comparison_contract.mjs';

const state = JSON.parse(
  fs.readFileSync(
    new URL(
      '../../material_extension_acceptance/fixtures/plan018_controlled_comparison_state.json',
      import.meta.url,
    ),
  ),
);

test('Plan 018 iOS health evidence binds all frames and pass triplets', () => {
  const runRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'plan018-ios-health-'));
  try {
    const inventory = buildPlan018ExpectedCaptureInventory(state);
    const captures = inventory.map((record, index) => {
      const bytes = Buffer.from(`capture-${index}-${record.fileName}`);
      fs.writeFileSync(path.join(runRoot, record.fileName), bytes);
      return {
        path: record.fileName,
        sha256: sha256(bytes),
        byteLength: bytes.length,
        dimensions: { width: 1206, height: 2622 },
      };
    });
    const finalEvidence = {
      status: 'candidate-only',
      stateSha256: sha256(Buffer.from(JSON.stringify(state))),
      orderedScreenshotNames: inventory.map((record) =>
        record.fileName.replace(/\.png$/u, ''),
      ),
      models: Object.keys(state.models).map((modelId) => ({
        modelId,
        artifacts: captures.filter((capture) =>
          path.basename(capture.path).startsWith(`${modelId}_`),
        ),
      })),
    };
    const frames = inventory.map((record, index) => {
      const summary = healthySummary();
      return {
        ...record,
        ...captures[index],
        summary,
        checks: buildPlan018FrameHealthChecks(summary),
      };
    });
    const passTriplets = [...new Set(
      inventory.map((record) => `${record.modelId}/${record.view}`),
    )].map((key) => {
      const [modelId, view] = key.split('/');
      return {
        modelId,
        view,
        checks: ['directVsIbl', 'combinedVsDirect', 'combinedVsIbl'].map(
          (name) => ({ name, actual: 1, expected: '>= 1', passed: true }),
        ),
      };
    });
    const evidence = buildPlan018IosHealthEvidence({
      runRoot,
      finalEvidence,
      inventory,
      frames,
      passTriplets,
      finalEvidenceSha256: 'f'.repeat(64),
      analysisSourceSha256: {
        'plan018_controlled_comparison_analysis.mjs': 'a'.repeat(64),
        'analyze_plan018_ios_capture_health.mjs': 'b'.repeat(64),
        'analyze_plan018_ios_capture_health.test.mjs': 'c'.repeat(64),
      },
    });

    assert.doesNotThrow(() => validatePlan018IosHealthEvidence(
      evidence,
      { runRoot, finalEvidence, verifyAnalysisSources: false },
    ));
    assert.equal(evidence.frames.length, 27);
    assert.equal(evidence.passTriplets.length, 9);
    assert.deepEqual(evidence.crossRendererPixelThresholds, []);

    const sourceDrift = structuredClone(evidence);
    sourceDrift.frames[0].sha256 = 'd'.repeat(64);
    assert.throws(
      () => validatePlan018IosHealthEvidence(
        sourceDrift,
        { runRoot, finalEvidence, verifyAnalysisSources: false },
      ),
      /frame identity drifted/u,
    );

    const failedHealth = structuredClone(evidence);
    failedHealth.passTriplets[0].checks[0].passed = false;
    assert.throws(
      () => validatePlan018IosHealthEvidence(
        failedHealth,
        { runRoot, finalEvidence, verifyAnalysisSources: false },
      ),
      /health checks are incomplete or failed/u,
    );
  } finally {
    fs.rmSync(runRoot, { recursive: true, force: true });
  }
});

const retainedRunRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/plan018_controlled_comparison',
  'ios_simulator/candidate-run-14',
);

test(
  'stored iOS health is recomputed from the exact retained PNG bytes',
  { skip: !fs.existsSync(path.join(retainedRunRoot, 'evidence.json')) },
  () => {
    const root = fs.mkdtempSync(
      path.join(path.dirname(retainedRunRoot), 'health-validation-test-'),
    );
    try {
      for (const name of ['evidence.json', 'ios_renderer_local_health.json']) {
        fs.copyFileSync(path.join(retainedRunRoot, name), path.join(root, name));
      }
      const finalEvidence = JSON.parse(
        fs.readFileSync(path.join(root, 'evidence.json')),
      );
      for (const name of finalEvidence.orderedScreenshotNames) {
        fs.linkSync(
          path.join(retainedRunRoot, `${name}.png`),
          path.join(root, `${name}.png`),
        );
      }

      const healthPath = path.join(root, 'ios_renderer_local_health.json');
      const health = JSON.parse(fs.readFileSync(healthPath));
      health.frames[0].summary.foregroundFraction += 0.01;
      health.frames[0].checks = buildPlan018FrameHealthChecks(
        health.frames[0].summary,
      );
      for (const sourceName of Object.keys(health.analysisSourceSha256)) {
        health.analysisSourceSha256[sourceName] = sha256(
          fs.readFileSync(path.join(path.dirname(import.meta.filename), sourceName)),
        );
      }
      fs.writeFileSync(healthPath, `${JSON.stringify(health, null, 2)}\n`);

      assert.throws(
        () => validateStoredPlan018IosHealthEvidence(root),
        /does not match current PNG analysis/u,
      );
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  },
);

function healthySummary() {
  return {
    foregroundFraction: 0.5,
    foregroundWidthSpan: 0.5,
    foregroundHeightSpan: 0.5,
    luminanceP99P01: 0.5,
    quantizedRgbBins: 100,
    meanSrgbLuminance: 0.5,
  };
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}
