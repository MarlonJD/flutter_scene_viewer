import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import {
  buildPlan018GlamCloseCropComparison,
  buildPlan018GlamCloseCropInventory,
  validatePlan018GlamCloseCropComparison,
} from './build_plan018_glam_close_crop_board.mjs';
import {
  hashBytes,
  outputRoot,
  repoRoot,
} from './plan018_controlled_comparison_contract.mjs';

const expectedRenderers = ['threejs', 'khronosSampleRenderer', 'viewerIos'];
const expectedViews = ['close', 'grazing'];
const expectedPasses = ['directOnly', 'iblOnly', 'combined'];
const expectedEvidenceSources = [
  {
    rendererId: 'threejs',
    path: 'tools/out/material_extension_acceptance/plan018_controlled_comparison/threejs/evidence.json',
    sha256:
      '1e35873f061f85afcefb0218a2b60677eebd4731beb63e245e35e06983bda3a1',
  },
  {
    rendererId: 'khronosSampleRenderer',
    path: 'tools/out/material_extension_acceptance/plan018_controlled_comparison/khronos_sample_renderer/glam_velvet_sofa_evidence.json',
    sha256:
      '9ffcc341478d3ba3be7ad2a3c7994155f9e584006bd1d65e0f7f07cb929d3c64',
  },
  {
    rendererId: 'viewerIos',
    path: 'tools/out/material_extension_acceptance/plan018_controlled_comparison/ios_simulator/candidate-run-08/manifests/glam_velvet_sofa.json',
    sha256:
      '9d497431aa2a498bda31089a777bce1b2ab0cd878bd147315567c967630097cd',
  },
];
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

test('Plan 018 Glam crop board inventory uses current visual-only artifacts', () => {
  const inventory = buildPlan018GlamCloseCropInventory();

  assert.equal(inventory.length, 18);
  assert.deepEqual([...new Set(inventory.map((item) => item.rendererId))], expectedRenderers);
  assert.deepEqual([...new Set(inventory.map((item) => item.view))], expectedViews);
  assert.deepEqual([...new Set(inventory.map((item) => item.pass))], expectedPasses);
  assert.equal(new Set(inventory.map((item) => item.path)).size, 18);

  for (const item of inventory) {
    assert.equal(item.modelId, 'glam_velvet_sofa');
    assert.equal(item.visualOnly, true);
    assert.match(item.path, /glam_velvet_sofa_(close|grazing)_(directOnly|iblOnly|combined)\.png$/);
    assert.ok(fs.existsSync(item.absolutePath), item.path);
  }
});

test(
  'Plan 018 Glam crop board is visual-only and refuses evidence claims',
  { timeout: 120_000 },
  async () => {
    const comparison = await buildPlan018GlamCloseCropComparison({
      writeFiles: false,
    });
    validatePlan018GlamCloseCropComparison(comparison);

    assert.equal(comparison.status, 'visual-only');
    assert.equal(comparison.modelId, 'glam_velvet_sofa');
    assert.equal(comparison.evidenceStatus, 'not evidence');
    assert.equal(comparison.comparisonBoundary, 'visual-only close crop');
    assert.equal(comparison.claimsPixelParity, false);
    assert.equal(comparison.claimsPhysicalCorrectness, false);
    assert.equal(comparison.m3Status, 'incomplete');
    assert.equal(comparison.m4Status, 'not started');
    assert.equal(comparison.canStartM4, false);
    assert.deepEqual(comparison.boards.map((board) => board.view), expectedViews);
    assert.deepEqual(
      comparison.evidenceSources.map((source) => ({
        rendererId: source.rendererId,
        path: source.path,
        sha256: source.sha256,
      })),
      expectedEvidenceSources,
    );
    for (const source of comparison.evidenceSources) {
      const absolutePath = `${repoRoot}/${source.path}`;
      assert.equal(source.byteLength, fs.statSync(absolutePath).size);
      assert.equal(hashBytes(fs.readFileSync(absolutePath)), source.sha256);
    }
    assert.equal(comparison.sources.length, 18);
    assert.equal(comparison.cropBox.x, 60);
    assert.equal(comparison.cropBox.y, 1120);
    assert.equal(comparison.cropBox.width, 1086);
    assert.equal(comparison.cropBox.height, 760);

    for (const source of comparison.sources) {
      assert.equal(source.dimensions.width, 1206);
      assert.equal(source.dimensions.height, 2622);
      assert.match(source.sha256, /^[a-f0-9]{64}$/);
      assert.equal(source.byteLength, fs.statSync(source.absolutePath).size);
      assert.equal(hashBytes(fs.readFileSync(source.absolutePath)), source.sha256);
    }

    for (const board of comparison.boards) {
      assert.equal(board.visualOnly, true);
      assert.equal(board.width, 1440);
      assert.equal(board.height, 1180);
      assert.match(board.sha256, /^[a-f0-9]{64}$/);
      assert.ok(board.byteLength > 24);
      assert.ok(board.path.startsWith(`${outputRoot}/visual_boards/`));
      assert.ok(board.absolutePath.startsWith(`${repoRoot}/`));
      assert.ok(board.bytes.subarray(0, 8).equals(pngSignature));
      assert.equal(board.bytes.readUInt32BE(16), board.width);
      assert.equal(board.bytes.readUInt32BE(20), board.height);
      assert.equal(hashBytes(board.bytes), board.sha256);
      assert.equal(board.bytes.length, board.byteLength);
    }
  },
);
