import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  loadControlledComparisonState,
  outputRoot,
  repoRoot,
} from './plan015_controlled_comparison_contract.mjs';

const state = loadControlledComparisonState();
const iosOutputRoot = path.join(outputRoot, 'ios_simulator');
const threeEvidencePath = path.join(outputRoot, 'threejs', 'evidence.json');
const threeEvidence = JSON.parse(fs.readFileSync(threeEvidencePath, 'utf8'));
const modelIds = Object.keys(state.modelFrames);
const artifacts = {};

for (const modelId of modelIds) {
  artifacts[modelId] = {};
  for (const pass of state.renderPasses) {
    const artifactPath = path.join(iosOutputRoot, `${modelId}_${pass}.png`);
    const bytes = fs.readFileSync(artifactPath);
    const dimensions = pngDimensions(bytes);
    const expectedWidth =
      state.viewport.logicalWidth * state.viewport.devicePixelRatio;
    const expectedHeight =
      state.viewport.logicalHeight * state.viewport.devicePixelRatio;
    if (
      dimensions.width !== expectedWidth ||
      dimensions.height !== expectedHeight
    ) {
      throw new Error(
        `${modelId}/${pass} is ${dimensions.width}x${dimensions.height}; ` +
          `expected ${expectedWidth}x${expectedHeight}`,
      );
    }
    artifacts[modelId][pass] = {
      path: path.relative(repoRoot, artifactPath),
      sha256: hash(bytes),
      byteLength: bytes.length,
      dimensions,
    };
  }
}

const transmissionDiagnostic = {
  code: 'unsupportedMaterialFeature',
  part: 'Glass#0',
  extensions: ['KHR_materials_transmission'],
  status: 'unsupported',
};
const diagnostics = {
  clearcoat_test: Object.fromEntries(
    state.renderPasses.map((pass) => [pass, []]),
  ),
  clearcoat_car_paint: Object.fromEntries(
    state.renderPasses.map((pass) => [pass, []]),
  ),
  toycar: Object.fromEntries(
    state.renderPasses.map((pass) => [pass, [transmissionDiagnostic]]),
  ),
};

const evidence = {
  schemaVersion: 1,
  status: 'verified locally',
  scope: 'flutter_scene iOS Simulator controlled comparison captures',
  sourceState: path.relative(
    repoRoot,
    path.join(
      repoRoot,
      'tools/material_extension_acceptance/fixtures/' +
        'plan015_controlled_comparison_state.json',
    ),
  ),
  state,
  environment: threeEvidence.environment,
  models: threeEvidence.models,
  renderer: {
    name: 'flutter_scene via flutter_scene_viewer',
    flutterSceneCommit: 'ccf7372428961ebe0abb053727fe443150547a74',
    backend: 'Impeller Metal',
    device: 'iPhone 17 Simulator',
    operatingSystem: 'iOS 26.5',
    host: {
      platform: process.platform,
      release: os.release(),
      architecture: process.arch,
    },
    coordinateMapping: 'native flutter_scene imported-glTF mirrorZ world',
    camera:
      'canonical per-model bounding sphere; 1.15 fit padding; fixed yaw/pitch/FOV',
    toneMapping: 'Khronos PBR Neutral',
    outputColorSpace: 'sRGB',
    directLight: 'one directional light; fixed linear color and travel direction',
    ambientOcclusion: 'disabled',
    shadows: 'disabled',
    skybox: 'not shown',
  },
  diagnostics,
  artifacts,
  captureBoundary:
    'System screenshots include the Simulator display chrome. ClearCoatTest ' +
    'and ClearCoatCarPaint have zero diagnostics. ToyCar retains an explicit ' +
    'unsupported KHR_materials_transmission diagnostic and is not a clean ' +
    'transmission-parity reference.',
  comparisonBoundary:
    'Matched source state and coordinate mapping; independent renderer BRDF ' +
    'and HDR prefilter implementations prevent a pixel-parity claim.',
};

fs.writeFileSync(
  path.join(iosOutputRoot, 'evidence.json'),
  `${JSON.stringify(evidence, null, 2)}\n`,
);
console.log(
  `Plan 015 controlled iOS evidence: ${modelIds.length} models x ` +
    `${state.renderPasses.length} passes OK`,
);

function pngDimensions(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature)) {
    throw new Error('Capture is not a PNG');
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function hash(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}
