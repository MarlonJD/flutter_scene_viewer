import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  buildPlan014A1b32CaptureEvidence,
  buildPlan014A1b32CaptureContract,
  buildPlan014RecordedCaptureRecord,
  verifyPlan014A1b32Bytes,
} from './plan014_capture_contract.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');

test('Plan 014 A1B32 reference capture is fixed and evidence-scoped', () => {
  const contract = buildPlan014A1b32CaptureContract(repoRoot);

  assert.deepEqual(contract, {
    schemaVersion: 1,
    evidenceKind: 'reference-renderer-direction',
    status: 'configured',
    sourceAsset: {
      id: 'a1b32',
      sha256:
        'a9383e98ae7876e9589ad4c415c297c9862ee2267836f1f1e82024394c9ac592',
      byteLength: 2809824,
      materialPolicy: 'authored-materials-unmodified',
    },
    renderer: {
      name: 'three.js',
      version: '0.167.1',
      releaseTag: 'r167',
      sourceCommit: '42a2f6aac8cffebb29524d68eb7136a756f15960',
      npmIntegrity:
        'sha512-gYTLJA/UQip6J/tJvl91YYqlZF47+D/kxiWrbTon35ZHlXEN0VOo+Qke2walF1/x92v55H6enomymg4Dak52kw==',
      backend: 'WebGL',
      role: 'directional-reference-only',
    },
    referenceState: {
      path:
        'tools/material_extension_acceptance/fixtures/reference_state.json',
      schemaVersion: 1,
      sha256:
        '774fb35234176d4d949ac84cf6ba16fb05ee7afd7e8d1b70d42c00521f9db8ff',
      cameraFit: 'assetBounds',
      views: ['front', 'left', 'right', 'back'],
      environment: {
        kind: 'studio',
        intensity: 1.0,
        rotationRadians: 0.0,
        showSkybox: false,
        skyboxBlur: 0.0,
      },
      lighting: {
        kind: 'studio',
        exposure: 1.0,
        ambientOcclusion: false,
        environmentIntensity: 1.0,
        keyLightIntensity: 3.0,
        keyLightColor: [1.0, 1.0, 1.0],
        keyLightDirection: [-0.45, -0.85, -0.35],
        keyLightCastsShadow: false,
      },
    },
    passCriteria: [
      'all four configured views render non-empty PNG bytes',
      'authored materials, textures, geometry, UVs, and visibility remain unmodified',
      'capture metadata records exact source, renderer, state, view, and artifact hashes',
    ],
    outputRoot:
      'tools/out/material_extension_acceptance/a1b32_threejs_reference',
    artifacts: {
      front:
        'tools/out/material_extension_acceptance/a1b32_threejs_reference/front.png',
      left:
        'tools/out/material_extension_acceptance/a1b32_threejs_reference/left.png',
      right:
        'tools/out/material_extension_acceptance/a1b32_threejs_reference/right.png',
      back:
        'tools/out/material_extension_acceptance/a1b32_threejs_reference/back.png',
      report:
        'tools/out/material_extension_acceptance/a1b32_threejs_reference/evidence.json',
    },
    evidenceBoundary: {
      runtimeCapability: 'not established',
      releaseMaturity: 'not established',
      targetEvidence: 'not established',
      productionReadiness: 'not established',
    },
  });
});

test('Plan 014 A1B32 capture rejects any source-byte drift', () => {
  const contract = buildPlan014A1b32CaptureContract(repoRoot);
  assert.throws(
    () => verifyPlan014A1b32Bytes(Buffer.from('not A1B32'), contract),
    /A1B32 byteLength mismatch/,
  );
  assert.throws(
    () =>
      verifyPlan014A1b32Bytes(
        Buffer.alloc(contract.sourceAsset.byteLength),
        contract,
      ),
    /A1B32 SHA-256 mismatch/,
  );
});

test('Plan 014 A1B32 evidence hashes every configured view', () => {
  const contract = buildPlan014A1b32CaptureContract(repoRoot);
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64',
  );
  const captures = Object.fromEntries(
    contract.referenceState.views.map((view) => [view, png]),
  );
  const evidence = buildPlan014A1b32CaptureEvidence(contract, {
    captures,
    browser: {
      product: 'Chrome',
      version: 'test-version',
      platform: 'test-host',
    },
    host: {
      platform: 'darwin',
      release: 'test-release',
      architecture: 'arm64',
      device: 'local reference host',
    },
    viewport: { width: 640, height: 960, deviceScaleFactor: 1 },
  });

  assert.equal(evidence.status, 'verified locally');
  assert.equal(evidence.evidenceKind, 'reference-renderer-direction');
  assert.deepEqual(evidence.browser, {
    product: 'Chrome',
    version: 'test-version',
    platform: 'test-host',
  });
  assert.deepEqual(evidence.host, {
    platform: 'darwin',
    release: 'test-release',
    architecture: 'arm64',
    device: 'local reference host',
  });
  assert.deepEqual(evidence.viewport, {
    width: 640,
    height: 960,
    deviceScaleFactor: 1,
  });
  assert.deepEqual(Object.keys(evidence.captures), [
    'front',
    'left',
    'right',
    'back',
  ]);
  for (const view of contract.referenceState.views) {
    assert.deepEqual(evidence.captures[view], {
      view,
      artifactPath: contract.artifacts[view],
      byteLength: png.length,
      sha256:
        '431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460',
    });
  }
  assert.deepEqual(evidence.evidenceBoundary, contract.evidenceBoundary);
  assert.equal('capturedAt' in evidence, false);

  finalRecordChecks(
    buildPlan014RecordedCaptureRecord(contract, evidence),
    contract,
    png,
  );
});

test('Plan 014 A1B32 evidence rejects an incomplete view set', () => {
  const contract = buildPlan014A1b32CaptureContract(repoRoot);
  const png = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64',
  );
  assert.throws(
    () =>
      buildPlan014A1b32CaptureEvidence(contract, {
        captures: { front: png },
        browser: { product: 'Chrome', version: 'test', platform: 'host' },
        host: {
          platform: 'darwin',
          release: 'test',
          architecture: 'arm64',
          device: 'local reference host',
        },
        viewport: { width: 640, height: 960, deviceScaleFactor: 1 },
      }),
    /missing capture for left/,
  );
});

function finalRecordChecks(record, contract, png) {
  assert.equal(record.id, 'a1b32_threejs_four_view');
  assert.equal(record.status, 'verified locally');
  assert.equal(record.toolPath, 'tools/reference_renderers/' +
    'threejs_material_extension_fixture/render_plan014_a1b32_reference.mjs');
  assert.equal(record.reportPath, contract.artifacts.report);
  assert.deepEqual(
    record.captures.map((capture) => capture.view),
    ['front', 'left', 'right', 'back'],
  );
  assert.equal(record.captures[0].byteLength, png.length);
  assert.equal(
    record.persistence,
    'hash metadata is tracked; image artifacts stay ignored because ' +
      'redistribution is not established',
  );
  assert.deepEqual(record.targetEvidence, [
    { target: 'iOS Simulator', status: 'not run' },
    { target: 'physical iOS', status: 'not run' },
    { target: 'Android', status: 'not run' },
    { target: 'Web', status: 'not run' },
  ]);
}
