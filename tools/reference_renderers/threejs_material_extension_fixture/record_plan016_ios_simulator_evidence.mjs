import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  hashBytes,
  loadPlan016ControlledComparisonState,
  outputRoot,
  plan016StateHash,
  repoRoot,
  statePath,
} from './plan016_controlled_comparison_contract.mjs';

const state = loadPlan016ControlledComparisonState();
const captureArgument = process.argv[2] ?? process.env.PLAN016_IOS_CAPTURE_ROOT;
if (captureArgument == null) {
  throw new Error(
    'Usage: node record_plan016_ios_simulator_evidence.mjs <capture-root>',
  );
}

const captureRoot = path.resolve(repoRoot, captureArgument);
const iosRoot = path.join(outputRoot, 'ios_simulator');
if (!isWithin(captureRoot, iosRoot)) {
  throw new Error(`Plan 016 capture root must be inside ${iosRoot}`);
}
const logPath = path.join(captureRoot, 'flutter-run.log');
const logBytes = fs.readFileSync(logPath);
const log = logBytes.toString('utf8');
const threeEvidencePath = path.join(outputRoot, 'threejs', 'evidence.json');
const threeEvidence = JSON.parse(fs.readFileSync(threeEvidencePath, 'utf8'));
const stateSha256 = plan016StateHash();
if (threeEvidence.stateSha256 !== stateSha256) {
  throw new Error('Plan 016 Three.js evidence is stale for this capture');
}

const readyRecords = parseReadyRecords(log);
const expectedStages = Object.keys(state.models).flatMap((modelId) =>
  state.renderPasses.map((pass) => ({ modelId, pass })),
);
if (readyRecords.length !== expectedStages.length) {
  throw new Error(
    `Expected ${expectedStages.length} PLAN016_READY records; found ` +
      `${readyRecords.length}`,
  );
}

const expectedPhysicalWidth =
  state.viewport.logicalWidth * state.viewport.devicePixelRatio;
const expectedPhysicalHeight =
  state.viewport.logicalHeight * state.viewport.devicePixelRatio;
const artifacts = {};
const diagnostics = {};
for (let stage = 0; stage < expectedStages.length; stage += 1) {
  const expected = expectedStages[stage];
  const record = readyRecords[stage];
  assertReadyRecord(record, expected, stage, {
    expectedPhysicalWidth,
    expectedPhysicalHeight,
    stateSha256,
  });
  artifacts[expected.modelId] ??= {};
  diagnostics[expected.modelId] ??= {};
  const artifactPath = path.join(
    captureRoot,
    `${expected.modelId}_${expected.pass}.png`,
  );
  const bytes = fs.readFileSync(artifactPath);
  const dimensions = pngDimensions(bytes);
  if (
    dimensions.width !== expectedPhysicalWidth ||
    dimensions.height !== expectedPhysicalHeight
  ) {
    throw new Error(
      `${expected.modelId}/${expected.pass} is ` +
        `${dimensions.width}x${dimensions.height}; expected ` +
        `${expectedPhysicalWidth}x${expectedPhysicalHeight}`,
    );
  }
  artifacts[expected.modelId][expected.pass] = {
    path: path.relative(repoRoot, artifactPath),
    sha256: hashBytes(bytes),
    byteLength: bytes.length,
    dimensions,
  };
  diagnostics[expected.modelId][expected.pass] = {
    count: record.diagnosticCount,
    codes: record.diagnosticCodes,
    totalAtCapture: record.diagnosticsTotal,
  };
}

const capturedPngs = fs
  .readdirSync(captureRoot)
  .filter((name) => name.endsWith('.png'))
  .sort();
if (capturedPngs.length !== expectedStages.length) {
  throw new Error(
    `Expected exactly ${expectedStages.length} PNG captures; found ` +
      `${capturedPngs.length}`,
  );
}

if (!log.includes('Using the Impeller rendering backend (Metal).')) {
  throw new Error('Capture log does not prove the Impeller Metal backend');
}
const complete = parseCompleteRecord(log);
if (
  complete.stages !== expectedStages.length ||
  complete.stateSha256 !== stateSha256 ||
  complete.diagnostics !== readyRecords.at(-1).diagnosticsTotal
) {
  throw new Error('PLAN016_COMPLETE does not match the capture contract');
}
const failureLines = log
  .split(/\r?\n/)
  .filter((line) => /\b(?:ERROR|Exception|Failed)\b/.test(line));
if (failureLines.length !== 0) {
  throw new Error(`Capture log contains failure text: ${failureLines[0]}`);
}

const dependency = dependencyProvenance();
const candidateOnly = dependency.kind === 'pathOverride';
const evidence = {
  schemaVersion: 1,
  status: candidateOnly ? 'candidate-only' : 'verified locally',
  scope: 'flutter_scene iOS Simulator controlled comparison captures',
  sourceState: path.relative(repoRoot, statePath),
  stateSha256,
  state,
  environment: threeEvidence.environment,
  models: threeEvidence.models,
  renderer: {
    name: 'flutter_scene via flutter_scene_viewer',
    dependency,
    backend: 'Impeller Metal',
    device: process.env.PLAN016_IOS_DEVICE ?? 'iPhone 17 Simulator',
    operatingSystem: process.env.PLAN016_IOS_VERSION ?? 'iOS 26.5',
    host: {
      platform: process.platform,
      release: os.release(),
      architecture: process.arch,
    },
    coordinateMapping: 'native flutter_scene imported-glTF mirrorZ world',
    camera:
      'frozen per-model canonical bounding sphere; fixed fit padding, ' +
      'yaw, pitch, FOV, near, and far',
    toneMapping: 'Khronos PBR Neutral',
    outputColorSpace: 'sRGB',
    directLight:
      'one directional light; fixed linear color and travel direction',
    environment:
      'same hash-pinned Radiance HDR bytes; fixed intensity and rotation',
    ambientOcclusion: 'disabled',
    shadows: 'disabled',
    skybox: 'not shown',
  },
  captureContract: {
    readyRecordCount: readyRecords.length,
    complete,
    logicalDimensions: {
      width: state.viewport.logicalWidth,
      height: state.viewport.logicalHeight,
    },
    physicalDimensions: {
      width: expectedPhysicalWidth,
      height: expectedPhysicalHeight,
    },
    devicePixelRatio: state.viewport.devicePixelRatio,
    framesPerSecond: [...new Set(readyRecords.map((record) => record.fps))],
    log: {
      path: path.relative(repoRoot, logPath),
      sha256: hashBytes(logBytes),
      byteLength: logBytes.length,
    },
  },
  diagnostics,
  artifacts,
  diagnosticBoundary:
    'The nine TransmissionTest ambiguousNodePath diagnostics come from ' +
    'duplicate authored Khronos node paths in the viewer public-addressing ' +
    'layer. The native importer still supplies the model material state; no ' +
    'renderer, shader, capability, or material-adapter error was emitted.',
  captureBoundary:
    'System screenshots include the Simulator display boundary and Dynamic ' +
    'Island. Comparison metrics use the tracked central model ROI.',
  comparisonBoundary:
    'Matched source state and coordinate mapping; independent renderer BRDF, ' +
    'rasterization, and HDR-prefilter implementations prevent a pixel-parity ' +
    'claim.',
  publicationBoundary: candidateOnly
    ? 'Candidate-only: the viewer used an unpublished path override. This is ' +
      'not immutable-pin or externally reachable revision evidence.'
    : 'The capture used the viewer dependency declaration without a path ' +
      'override. External reachability is recorded separately.',
};

const destination = path.join(captureRoot, 'evidence.json');
fs.writeFileSync(destination, `${JSON.stringify(evidence, null, 2)}\n`);
console.log(
  `Plan 016 controlled iOS evidence: ${evidence.status}; ` +
    `${Object.keys(state.models).length} models x ` +
    `${state.renderPasses.length} passes OK`,
);
console.log(`Evidence: ${path.relative(repoRoot, destination)}`);

function parseReadyRecords(contents) {
  const expression =
    /PLAN016_READY model=(\S+) pass=(\S+) stage=(\d+) diagnostics=(\d+) diagnosticsTotal=(\d+) diagnosticCodes=(\S+) parts=(\d+) state=([a-f0-9]{64}) logical=([\d.]+)x([\d.]+) physical=(\d+)x(\d+) dpr=([\d.]+) distance=([\d.]+) target=\[([^\]]+)\] camera=\[([^\]]+)\] fps=(\d+)/g;
  return [...contents.matchAll(expression)].map((match) => ({
    modelId: match[1],
    pass: match[2],
    stage: Number(match[3]),
    diagnosticCount: Number(match[4]),
    diagnosticsTotal: Number(match[5]),
    diagnosticCodes:
      match[6] === 'none' ? [] : match[6].split(',').filter(Boolean),
    partCount: Number(match[7]),
    stateSha256: match[8],
    logicalWidth: Number(match[9]),
    logicalHeight: Number(match[10]),
    physicalWidth: Number(match[11]),
    physicalHeight: Number(match[12]),
    devicePixelRatio: Number(match[13]),
    distance: Number(match[14]),
    target: parseVector(match[15]),
    camera: parseVector(match[16]),
    fps: Number(match[17]),
  }));
}

function parseCompleteRecord(contents) {
  const matches = [
    ...contents.matchAll(
      /PLAN016_COMPLETE stages=(\d+) state=([a-f0-9]{64}) diagnostics=(\d+)/g,
    ),
  ];
  if (matches.length !== 1) {
    throw new Error(
      `Expected one PLAN016_COMPLETE record; found ${matches.length}`,
    );
  }
  return {
    stages: Number(matches[0][1]),
    stateSha256: matches[0][2],
    diagnostics: Number(matches[0][3]),
  };
}

function assertReadyRecord(record, expected, stage, dimensions) {
  if (
    record.modelId !== expected.modelId ||
    record.pass !== expected.pass ||
    record.stage !== stage ||
    record.stateSha256 !== dimensions.stateSha256 ||
    record.logicalWidth !== state.viewport.logicalWidth ||
    record.logicalHeight !== state.viewport.logicalHeight ||
    record.physicalWidth !== dimensions.expectedPhysicalWidth ||
    record.physicalHeight !== dimensions.expectedPhysicalHeight ||
    record.devicePixelRatio !== state.viewport.devicePixelRatio ||
    record.fps !== 60 ||
    record.partCount <= 0 ||
    record.distance <= 0 ||
    record.target.length !== 3 ||
    record.camera.length !== 3 ||
    record.diagnosticCodes.length !== record.diagnosticCount
  ) {
    throw new Error(
      `PLAN016_READY stage ${stage} violates the fixed capture contract`,
    );
  }
  const frame = state.frames[state.models[expected.modelId].cameraFrame];
  if (!vectorsClose(record.target, frame.centerFlutterSceneWorld, 1e-9)) {
    throw new Error(`PLAN016_READY stage ${stage} camera target drifted`);
  }
  const cameraDistance = vectorDistance(record.camera, record.target);
  if (Math.abs(cameraDistance - record.distance) > 1e-9) {
    throw new Error(`PLAN016_READY stage ${stage} camera distance drifted`);
  }
}

function dependencyProvenance() {
  const overridePath = path.join(repoRoot, 'pubspec_overrides.yaml');
  if (fs.existsSync(overridePath)) {
    const contents = fs.readFileSync(overridePath, 'utf8');
    const match = contents.match(/flutter_scene:\s*\n\s*path:\s*(.+)\s*$/m);
    if (match == null) {
      throw new Error('Could not parse flutter_scene path override');
    }
    const packagePath = path.resolve(repoRoot, match[1].trim());
    const checkoutPath = path.resolve(packagePath, '../..');
    return {
      kind: 'pathOverride',
      packagePath,
      checkoutPath,
      gitHead: git(checkoutPath, ['rev-parse', 'HEAD']),
      gitWorkingTreeDirty: git(checkoutPath, ['status', '--porcelain']) !== '',
      publicationStatus: 'unpublished',
    };
  }
  const declaredRevision =
    process.env.PLAN016_FLUTTER_SCENE_REVISION ?? 'not-recorded';
  return {
    kind: 'immutableGitPin',
    declaredRevision,
    publicationStatus:
      process.env.PLAN016_DEPENDENCY_REACHABILITY ?? 'not-recorded',
  };
}

function git(workingDirectory, arguments_) {
  return execFileSync('git', ['-C', workingDirectory, ...arguments_], {
    encoding: 'utf8',
  }).trim();
}

function parseVector(value) {
  return value.split(',').map(Number);
}

function vectorsClose(first, second, epsilon) {
  return first.every(
    (value, index) => Math.abs(value - second[index]) <= epsilon,
  );
}

function vectorDistance(first, second) {
  return Math.sqrt(
    first.reduce(
      (sum, value, index) => sum + (value - second[index]) ** 2,
      0,
    ),
  );
}

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

function isWithin(candidate, parent) {
  return candidate === parent || candidate.startsWith(`${parent}${path.sep}`);
}
