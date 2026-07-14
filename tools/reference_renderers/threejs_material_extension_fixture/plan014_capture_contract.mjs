import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const REFERENCE_STATE_PATH =
  'tools/material_extension_acceptance/fixtures/reference_state.json';
const MANIFEST_PATH = 'tools/material_extension_acceptance/manifest.json';
const PACKAGE_LOCK_PATH =
  'tools/reference_renderers/threejs_material_extension_fixture/package-lock.json';
const OUTPUT_ROOT =
  'tools/out/material_extension_acceptance/a1b32_threejs_reference';
const EXPECTED_VIEWS = ['front', 'left', 'right', 'back'];
const THREE_RELEASE = Object.freeze({
  version: '0.167.1',
  releaseTag: 'r167',
  sourceCommit: '42a2f6aac8cffebb29524d68eb7136a756f15960',
});

export function buildPlan014A1b32CaptureContract(repoRoot) {
  const manifest = readJson(repoRoot, MANIFEST_PATH);
  const provenance = requireObject(
    manifest.fixtureProvenance,
    'manifest.fixtureProvenance',
  );
  const fixtures = provenance.fixtures;
  if (!Array.isArray(fixtures)) {
    throw new Error('manifest.fixtureProvenance.fixtures must be an array');
  }
  const source = fixtures.find((fixture) => fixture?.id === 'a1b32');
  const sourceAsset = requireObject(source, 'A1B32 fixture provenance');

  const referenceStateBytes = fs.readFileSync(
    path.join(repoRoot, REFERENCE_STATE_PATH),
  );
  const referenceState = JSON.parse(referenceStateBytes.toString('utf8'));
  const state = requireObject(referenceState, 'reference state');
  const camera = requireObject(state.camera, 'reference state camera');
  const environment = requireObject(
    state.environment,
    'reference state environment',
  );
  const lighting = requireObject(state.lighting, 'reference state lighting');
  if (
    state.schemaVersion !== 1 ||
    camera.fit !== 'assetBounds' ||
    !sameStrings(camera.views, EXPECTED_VIEWS)
  ) {
    throw new Error('Plan 014 reference-state camera contract changed');
  }

  const packageLock = readJson(repoRoot, PACKAGE_LOCK_PATH);
  const packages = requireObject(packageLock.packages, 'package-lock packages');
  const three = requireObject(packages['node_modules/three'], 'three package');
  if (three.version !== THREE_RELEASE.version) {
    throw new Error(
      `Expected three ${THREE_RELEASE.version}; found ${three.version}`,
    );
  }
  if (typeof three.integrity !== 'string' || !three.integrity.startsWith('sha512-')) {
    throw new Error('three npm integrity is missing');
  }

  return {
    schemaVersion: 1,
    evidenceKind: 'reference-renderer-direction',
    status: 'configured',
    sourceAsset: {
      id: 'a1b32',
      sha256: sourceAsset.sourceSha256,
      byteLength: sourceAsset.byteLength,
      materialPolicy: 'authored-materials-unmodified',
    },
    renderer: {
      name: 'three.js',
      version: THREE_RELEASE.version,
      releaseTag: THREE_RELEASE.releaseTag,
      sourceCommit: THREE_RELEASE.sourceCommit,
      npmIntegrity: three.integrity,
      backend: 'WebGL',
      role: 'directional-reference-only',
    },
    referenceState: {
      path: REFERENCE_STATE_PATH,
      schemaVersion: state.schemaVersion,
      sha256: sha256(referenceStateBytes),
      cameraFit: camera.fit,
      views: [...camera.views],
      environment: structuredClone(environment),
      lighting: structuredClone(lighting),
    },
    passCriteria: [
      'all four configured views render non-empty PNG bytes',
      'authored materials, textures, geometry, UVs, and visibility remain unmodified',
      'capture metadata records exact source, renderer, state, view, and artifact hashes',
    ],
    outputRoot: OUTPUT_ROOT,
    artifacts: {
      front: `${OUTPUT_ROOT}/front.png`,
      left: `${OUTPUT_ROOT}/left.png`,
      right: `${OUTPUT_ROOT}/right.png`,
      back: `${OUTPUT_ROOT}/back.png`,
      report: `${OUTPUT_ROOT}/evidence.json`,
    },
    evidenceBoundary: {
      runtimeCapability: 'not established',
      releaseMaturity: 'not established',
      targetEvidence: 'not established',
      productionReadiness: 'not established',
    },
  };
}

export function verifyPlan014A1b32Bytes(bytes, contract) {
  const expected = contract.sourceAsset;
  if (!Buffer.isBuffer(bytes)) {
    throw new Error('A1B32 source must be a Buffer');
  }
  if (bytes.length !== expected.byteLength) {
    throw new Error(
      `A1B32 byteLength mismatch: expected ${expected.byteLength}, got ${bytes.length}`,
    );
  }
  const actualSha256 = sha256(bytes);
  if (actualSha256 !== expected.sha256) {
    throw new Error(
      `A1B32 SHA-256 mismatch: expected ${expected.sha256}, got ${actualSha256}`,
    );
  }
}

export function buildPlan014A1b32CaptureEvidence(
  contract,
  { captures, browser, host, viewport },
) {
  const captureRecords = {};
  for (const view of contract.referenceState.views) {
    const png = captures?.[view];
    if (!Buffer.isBuffer(png)) {
      throw new Error(`missing capture for ${view}`);
    }
    if (
      png.length < 8 ||
      !png.subarray(0, 8).equals(
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      )
    ) {
      throw new Error(`${view} capture is not a PNG`);
    }
    captureRecords[view] = {
      view,
      artifactPath: contract.artifacts[view],
      byteLength: png.length,
      sha256: sha256(png),
    };
  }
  if (Object.keys(captures).length !== contract.referenceState.views.length) {
    throw new Error('capture set contains unconfigured views');
  }

  return {
    schemaVersion: contract.schemaVersion,
    evidenceKind: contract.evidenceKind,
    status: 'verified locally',
    sourceAsset: structuredClone(contract.sourceAsset),
    renderer: structuredClone(contract.renderer),
    referenceState: structuredClone(contract.referenceState),
    passCriteria: [...contract.passCriteria],
    browser: structuredClone(requireObject(browser, 'browser metadata')),
    host: structuredClone(requireObject(host, 'host metadata')),
    viewport: structuredClone(requireObject(viewport, 'viewport metadata')),
    captures: captureRecords,
    evidenceBoundary: structuredClone(contract.evidenceBoundary),
  };
}

export function buildPlan014RecordedCaptureRecord(contract, evidence) {
  return {
    schemaVersion: evidence.schemaVersion,
    id: 'a1b32_threejs_four_view',
    status: evidence.status,
    evidenceKind: evidence.evidenceKind,
    toolPath:
      'tools/reference_renderers/threejs_material_extension_fixture/' +
      'render_plan014_a1b32_reference.mjs',
    contractTestPath:
      'tools/reference_renderers/threejs_material_extension_fixture/' +
      'plan014_capture_contract.test.mjs',
    reportPath: contract.artifacts.report,
    sourceAsset: structuredClone(evidence.sourceAsset),
    renderer: structuredClone(evidence.renderer),
    browser: structuredClone(evidence.browser),
    host: structuredClone(evidence.host),
    viewport: structuredClone(evidence.viewport),
    referenceState: {
      path: evidence.referenceState.path,
      schemaVersion: evidence.referenceState.schemaVersion,
      sha256: evidence.referenceState.sha256,
      cameraFit: evidence.referenceState.cameraFit,
      views: [...evidence.referenceState.views],
    },
    passCriteria: [...evidence.passCriteria],
    captures: evidence.referenceState.views.map((view) =>
      structuredClone(evidence.captures[view]),
    ),
    persistence:
      'hash metadata is tracked; image artifacts stay ignored because ' +
      'redistribution is not established',
    targetEvidence: [
      { target: 'iOS Simulator', status: 'not run' },
      { target: 'physical iOS', status: 'not run' },
      { target: 'Android', status: 'not run' },
      { target: 'Web', status: 'not run' },
    ],
    evidenceBoundary: structuredClone(evidence.evidenceBoundary),
  };
}

export function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function readJson(repoRoot, relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
}

function requireObject(value, label) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function sameStrings(actual, expected) {
  return (
    Array.isArray(actual) &&
    actual.length === expected.length &&
    actual.every((value, index) => value === expected[index])
  );
}
