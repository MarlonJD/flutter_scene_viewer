import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  buildPlan018CaptureInventory,
  runPlan018ControlledReferenceCapture,
  validatePlan018CaptureEvidence,
} from './render_plan018_controlled_comparison.mjs';
import {
  hashBytes,
  loadPlan018ControlledComparisonState,
  repoRoot,
} from './plan018_controlled_comparison_contract.mjs';

const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const state = loadPlan018ControlledComparisonState();

function expectedInventory() {
  const inventory = [];
  for (const modelId of [
    'sheen_chair',
    'sheen_cloth',
    'glam_velvet_sofa',
    'toycar',
  ]) {
    for (const view of ['close', 'grazing']) {
      for (const pass of ['directOnly', 'iblOnly', 'combined']) {
        inventory.push({
          modelId,
          view,
          pass,
          fileName: `${modelId}_${view}_${pass}.png`,
        });
      }
    }
  }
  for (const pass of ['directOnly', 'iblOnly', 'combined']) {
    inventory.push({
      modelId: 'toycar',
      view: 'context',
      pass,
      fileName: `toycar_context_${pass}.png`,
    });
  }
  return inventory;
}

test('Plan 018 reference capture inventory is exactly 27 fixed records', () => {
  const inventory = buildPlan018CaptureInventory(state);

  assert.equal(inventory.length, 27);
  assert.deepEqual(inventory, expectedInventory());
  assert.equal(new Set(inventory.map((record) => record.fileName)).size, 27);
});

test('Plan 018 pinned Three.js capture writes and validates every PNG', async () => {
  const evidence = await runPlan018ControlledReferenceCapture();
  validatePlan018CaptureEvidence(evidence);

  assert.equal(evidence.status, 'verified locally');
  assert.equal(
    evidence.scope,
    'pinned Three.js reference direction/conformance evidence',
  );
  assert.equal(evidence.renderer.packageVersion, '0.167.1');
  assert.equal(evidence.renderer.revision, '167');
  assert.equal(evidence.loaderAudit.status, 'verified locally');
  assert.equal(evidence.loaderAudit.renderer.backendFacts.renderedPixels, false);
  assert.deepEqual(evidence.captureInventory, expectedInventory());
  assert.equal(evidence.captures.length, 27);
  assert.match(
    evidence.captureSceneBoundary,
    /default scene.*scene-used.*not pictured/i,
  );
  assert.deepEqual(
    evidence.sceneAudits.sheen_chair.authoredSheenMaterialIndices,
    [0, 4],
  );
  assert.deepEqual(
    evidence.sceneAudits.sheen_chair.loadedDependencySheenMaterialIndices,
    [0, 4],
  );
  assert.deepEqual(
    evidence.sceneAudits.sheen_chair.sceneUsedSheenMaterialIndices,
    [0],
  );

  for (const [index, capture] of evidence.captures.entries()) {
    const expected = evidence.captureInventory[index];
    assert.deepEqual(
      {
        modelId: capture.modelId,
        view: capture.view,
        pass: capture.pass,
        fileName: path.basename(capture.path),
      },
      expected,
    );
    assert.deepEqual(capture.dimensions, { width: 1206, height: 2622 });
    assert.match(capture.sha256, /^[a-f0-9]{64}$/);
    assert.ok(capture.byteLength > 24);

    const bytes = fs.readFileSync(path.join(repoRoot, capture.path));
    assert.ok(bytes.subarray(0, 8).equals(pngSignature));
    assert.equal(bytes.readUInt32BE(16), 1206);
    assert.equal(bytes.readUInt32BE(20), 2622);
    assert.equal(bytes.length, capture.byteLength);
    assert.equal(hashBytes(bytes), capture.sha256);

    const wantsDirect = capture.pass !== 'iblOnly';
    const wantsIbl = capture.pass !== 'directOnly';
    assert.equal(capture.passState.directionalLight.configured, true);
    assert.equal(
      capture.passState.directionalLight.intensity,
      wantsDirect ? 3 : 0,
    );
    assert.equal(capture.passState.environment.configured, true);
    assert.equal(
      capture.passState.environment.intensity,
      wantsIbl ? 1 : 0,
    );
  }
});

test('Plan 018 cleanup still closes server and removes profile after browser failure', async () => {
  const module = await import('./render_plan018_controlled_comparison.mjs');
  assert.equal(typeof module.cleanupPlan018CaptureResources, 'function');
  const calls = [];

  await assert.rejects(
    () =>
      module.cleanupPlan018CaptureResources({
        disposePage: async () => calls.push('page'),
        closeBrowser: async () => {
          calls.push('browser');
          throw new Error('browser close failed');
        },
        closeServer: async () => calls.push('server'),
        removeProfile: () => calls.push('profile'),
      }),
    /Plan 018 capture cleanup failed/,
  );
  assert.deepEqual(calls, ['page', 'browser', 'server', 'profile']);
});
