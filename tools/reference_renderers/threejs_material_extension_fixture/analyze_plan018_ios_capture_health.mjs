import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import {
  PLAN018_ANALYSIS_THRESHOLDS,
  buildPlan018ExpectedCaptureInventory,
  buildPlan018FrameHealthChecks,
  buildPlan018PassDeltaChecks,
  summarizePlan018Frame,
  validatePlan018CaptureInventory,
} from './plan018_controlled_comparison_analysis.mjs';
import {
  hashBytes,
  loadPlan018ControlledComparisonState,
  plan018StateHash,
  repoRoot,
} from './plan018_controlled_comparison_contract.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const analysisModulePath = path.join(
  scriptDir,
  'plan018_controlled_comparison_analysis.mjs',
);
const testPath = path.join(
  scriptDir,
  'analyze_plan018_ios_capture_health.test.mjs',
);
export function runPlan018IosCaptureHealthAnalysis(runRootArgument) {
  const runRoot = safeRunRoot(runRootArgument);
  const finalEvidencePath = path.join(runRoot, 'evidence.json');
  const finalEvidenceBytes = fs.readFileSync(finalEvidencePath);
  const finalEvidence = JSON.parse(finalEvidenceBytes);
  const state = loadPlan018ControlledComparisonState();
  const inventory = buildPlan018ExpectedCaptureInventory(state);
  validateFinalCaptureIdentity(finalEvidence, inventory);

  const analysis = analyzeIosCaptureSet(
    runRoot,
    finalEvidence,
    state,
    inventory,
  );
  const evidence = buildPlan018IosHealthEvidence({
    runRoot,
    finalEvidence,
    inventory,
    frames: analysis.frames,
    passTriplets: analysis.passTriplets,
    finalEvidenceSha256: hashBytes(finalEvidenceBytes),
    analysisSourceSha256: currentAnalysisSourceSha256(),
  });
  validatePlan018IosHealthEvidence(evidence, { runRoot, finalEvidence });

  const outputPath = path.join(runRoot, 'ios_renderer_local_health.json');
  fs.writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
  console.log('Plan 018 iOS health: 27 frames / 9 pass triplets OK');
  console.log(`Evidence: ${path.relative(repoRoot, outputPath)}`);
  return evidence;
}

export function validateStoredPlan018IosHealthEvidence(runRootArgument) {
  const runRoot = safeRunRoot(runRootArgument);
  const finalEvidence = JSON.parse(
    fs.readFileSync(path.join(runRoot, 'evidence.json')),
  );
  const healthEvidence = JSON.parse(
    fs.readFileSync(path.join(runRoot, 'ios_renderer_local_health.json')),
  );
  validatePlan018IosHealthEvidence(healthEvidence, { runRoot, finalEvidence });
  const state = loadPlan018ControlledComparisonState();
  const inventory = buildPlan018ExpectedCaptureInventory(state);
  const analysis = analyzeIosCaptureSet(
    runRoot,
    finalEvidence,
    state,
    inventory,
  );
  const recomputed = buildPlan018IosHealthEvidence({
    runRoot,
    finalEvidence,
    inventory,
    frames: analysis.frames,
    passTriplets: analysis.passTriplets,
    finalEvidenceSha256: hashBytes(
      fs.readFileSync(path.join(runRoot, 'evidence.json')),
    ),
    analysisSourceSha256: currentAnalysisSourceSha256(),
  });
  if (JSON.stringify(healthEvidence) !== JSON.stringify(recomputed)) {
    throw new Error(
      'Plan 018 stored iOS health does not match current PNG analysis',
    );
  }
  return healthEvidence;
}

export function buildPlan018IosHealthEvidence({
  runRoot,
  finalEvidence,
  inventory,
  frames,
  passTriplets,
  finalEvidenceSha256,
  analysisSourceSha256,
}) {
  return {
    schemaVersion: 1,
    status: 'verified locally',
    executionEvidence: 'verified locally',
    scope: 'flutter_scene_viewer iOS Simulator renderer-local capture health',
    featureMaturity: 'candidate-only',
    stateSha256: finalEvidence.stateSha256,
    captureEvidence: {
      path: 'evidence.json',
      sha256: finalEvidenceSha256 ?? hashBytes(
        fs.readFileSync(path.join(runRoot, 'evidence.json')),
      ),
      status: finalEvidence.status,
    },
    thresholds: PLAN018_ANALYSIS_THRESHOLDS,
    thresholdBoundary:
      'Existing frozen Plan 018 renderer-local structural thresholds; no cross-renderer threshold.',
    fullFrameOnly: true,
    crossRendererPixelThresholds: [],
    physicalIos: 'not run',
    android: 'not run',
    web: 'not run',
    productionReadiness: 'not run',
    inventory,
    frameCount: frames.length,
    passTripletCount: passTriplets.length,
    frames,
    passTriplets,
    minimumObserved: minimumObserved(frames, passTriplets),
    analysisSourceSha256,
    claimBoundary:
      'Renderer-local blank, flat, framing, and pass-delta health only; no pixel parity, physical correctness, physical-target, release, or production-ready claim.',
  };
}

export function validatePlan018IosHealthEvidence(
  evidence,
  { runRoot, finalEvidence, verifyAnalysisSources = true },
) {
  const state = loadPlan018ControlledComparisonState();
  const expectedInventory = buildPlan018ExpectedCaptureInventory(state);
  validatePlan018CaptureInventory(expectedInventory, evidence.inventory);
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.executionEvidence !== 'verified locally' ||
    evidence.scope !==
      'flutter_scene_viewer iOS Simulator renderer-local capture health' ||
    evidence.featureMaturity !== 'candidate-only' ||
    evidence.stateSha256 !== finalEvidence.stateSha256 ||
    evidence.captureEvidence?.path !== 'evidence.json' ||
    evidence.captureEvidence?.status !== 'candidate-only' ||
    evidence.fullFrameOnly !== true ||
    JSON.stringify(evidence.crossRendererPixelThresholds) !== '[]' ||
    evidence.physicalIos !== 'not run' ||
    evidence.android !== 'not run' ||
    evidence.web !== 'not run' ||
    evidence.productionReadiness !== 'not run' ||
    JSON.stringify(evidence.thresholds) !==
      JSON.stringify(PLAN018_ANALYSIS_THRESHOLDS)
  ) {
    throw new Error('Plan 018 iOS health evidence boundary changed');
  }
  const finalEvidencePath = path.join(runRoot, 'evidence.json');
  if (
    fs.existsSync(finalEvidencePath) &&
    evidence.captureEvidence.sha256 !== hashBytes(fs.readFileSync(finalEvidencePath))
  ) {
    throw new Error('Plan 018 iOS health capture evidence drifted');
  }
  if (
    evidence.frameCount !== 27 ||
    evidence.passTripletCount !== 9 ||
    evidence.frames?.length !== 27 ||
    evidence.passTriplets?.length !== 9 ||
    evidence.frames.some((frame) =>
      frame.checks?.some((check) => !check.passed) ?? true,
    ) ||
    evidence.passTriplets.some((triplet) =>
      triplet.checks?.some((check) => !check.passed) ?? true,
    )
  ) {
    throw new Error('Plan 018 iOS health checks are incomplete or failed');
  }

  const captures = captureRecords(finalEvidence);
  for (const [index, record] of expectedInventory.entries()) {
    const frame = evidence.frames[index];
    const capture = captures[record.fileName];
    const filePath = path.join(runRoot, record.fileName);
    const current = {
      path: capture.path,
      sha256: hashBytes(fs.readFileSync(filePath)),
      byteLength: fs.statSync(filePath).size,
    };
    if (
      frame.modelId !== record.modelId ||
      frame.view !== record.view ||
      frame.pass !== record.pass ||
      frame.fileName !== record.fileName ||
      frame.path !== capture.path ||
      frame.sha256 !== capture.sha256 ||
      frame.byteLength !== capture.byteLength ||
      JSON.stringify(frame.dimensions) !== JSON.stringify(capture.dimensions) ||
      current.path !== capture.path ||
      current.sha256 !== capture.sha256 ||
      current.byteLength !== capture.byteLength
    ) {
      throw new Error(`Plan 018 iOS frame identity drifted: ${record.fileName}`);
    }
    const expectedChecks = buildPlan018FrameHealthChecks(frame.summary);
    if (JSON.stringify(frame.checks) !== JSON.stringify(expectedChecks)) {
      throw new Error(`Plan 018 iOS frame checks drifted: ${record.fileName}`);
    }
  }

  const expectedGroups = groupInventory(expectedInventory);
  for (const [index, group] of expectedGroups.entries()) {
    const triplet = evidence.passTriplets[index];
    if (
      triplet.modelId !== group.modelId ||
      triplet.view !== group.view ||
      triplet.checks?.length !== 3 ||
      triplet.checks.some((check) =>
        check.passed !== true ||
        typeof check.actual !== 'number' ||
        check.actual < PLAN018_ANALYSIS_THRESHOLDS
          .intraRendererMeanAbsoluteSrgbDeltaMin,
      )
    ) {
      throw new Error('Plan 018 iOS health checks are incomplete or failed');
    }
  }

  if (verifyAnalysisSources) {
    const currentSources = currentAnalysisSourceSha256();
    if (
      JSON.stringify(evidence.analysisSourceSha256) !==
      JSON.stringify(currentSources)
    ) {
      throw new Error('Plan 018 iOS health analysis source drifted');
    }
  }
}

function validateFinalCaptureIdentity(finalEvidence, inventory) {
  if (
    finalEvidence?.status !== 'candidate-only' ||
    finalEvidence.stateSha256 !== plan018StateHash() ||
    JSON.stringify(finalEvidence.orderedScreenshotNames) !== JSON.stringify(
      inventory.map((record) => record.fileName.replace(/\.png$/u, '')),
    )
  ) {
    throw new Error('Plan 018 final iOS capture identity drifted');
  }
  captureRecords(finalEvidence);
}

function captureRecords(finalEvidence) {
  const captures = Object.fromEntries(
    (finalEvidence.models ?? []).flatMap((model) =>
      (model.artifacts ?? []).map((artifact) => [path.basename(artifact.path), artifact]),
    ),
  );
  if (Object.keys(captures).length !== 27) {
    throw new Error('Plan 018 final evidence lacks the exact 27 captures');
  }
  return captures;
}

function currentAnalysisSourceSha256() {
  return Object.fromEntries(
    [analysisModulePath, scriptPath, testPath].map((sourcePath) => [
      path.basename(sourcePath),
      hashBytes(fs.readFileSync(sourcePath)),
    ]),
  );
}

function minimumObserved(frames, passTriplets) {
  const minimum = (field) => Math.min(
    ...frames.map((frame) => frame.summary[field]),
  );
  return {
    foregroundFraction: minimum('foregroundFraction'),
    foregroundWidthSpan: minimum('foregroundWidthSpan'),
    foregroundHeightSpan: minimum('foregroundHeightSpan'),
    luminanceP99P01: minimum('luminanceP99P01'),
    quantizedRgbBins: minimum('quantizedRgbBins'),
    intraRendererMeanAbsoluteSrgbDelta: Math.min(
      ...passTriplets.flatMap((triplet) =>
        triplet.checks.map((check) => check.actual),
      ),
    ),
  };
}

function groupInventory(inventory) {
  const groups = [];
  for (const record of inventory) {
    let group = groups.find(
      (candidate) =>
        candidate.modelId === record.modelId && candidate.view === record.view,
    );
    if (group == null) {
      group = { modelId: record.modelId, view: record.view, records: [] };
      groups.push(group);
    }
    group.records.push(record);
  }
  return groups;
}

function analyzeIosCaptureSet(runRoot, finalEvidence, state, inventory) {
  const captures = captureRecords(finalEvidence);
  const conversionRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-ios-health-bmp-'),
  );
  const frames = [];
  const passTriplets = [];
  try {
    for (const group of groupInventory(inventory)) {
      const images = Object.fromEntries(
        group.records.map((record) => [
          record.pass,
          decodePngWithSips(
            path.join(runRoot, record.fileName),
            path.join(conversionRoot, `${record.fileName}.bmp`),
            state.background.srgbHex,
          ),
        ]),
      );
      for (const record of group.records) {
        const summary = summarizePlan018Frame(images[record.pass]);
        const checks = buildPlan018FrameHealthChecks(summary);
        if (checks.some((check) => !check.passed)) {
          throw new Error(`Plan 018 iOS frame health failed: ${record.fileName}`);
        }
        frames.push({
          ...record,
          ...captures[record.fileName],
          summary,
          checks,
        });
      }
      const checks = buildPlan018PassDeltaChecks(images);
      if (checks.some((check) => !check.passed)) {
        throw new Error(
          `Plan 018 iOS pass delta failed: ${group.modelId}/${group.view}`,
        );
      }
      passTriplets.push({
        modelId: group.modelId,
        view: group.view,
        checks,
      });
    }
  } finally {
    fs.rmSync(conversionRoot, { recursive: true, force: true });
  }
  return { frames, passTriplets };
}

function decodePngWithSips(pngPath, bmpPath, backgroundSrgbHex) {
  const result = spawnSync(
    '/usr/bin/sips',
    ['-s', 'format', 'bmp', pngPath, '--out', bmpPath],
    { encoding: 'utf8', maxBuffer: 1024 * 1024 },
  );
  if (result.status !== 0) {
    throw new Error(
      `Plan 018 iOS PNG decode failed: ${path.basename(pngPath)}: ` +
        `${result.stderr || result.stdout}`.trim(),
    );
  }
  const bytes = fs.readFileSync(bmpPath);
  if (
    bytes.toString('ascii', 0, 2) !== 'BM' ||
    bytes.readUInt32LE(14) < 40 ||
    bytes.readUInt16LE(26) !== 1 ||
    bytes.readUInt16LE(28) !== 32 ||
    ![0, 3].includes(bytes.readUInt32LE(30))
  ) {
    throw new Error(`Plan 018 iOS BMP decode contract changed: ${bmpPath}`);
  }
  const width = bytes.readInt32LE(18);
  const signedHeight = bytes.readInt32LE(22);
  const height = Math.abs(signedHeight);
  const pixelOffset = bytes.readUInt32LE(10);
  const rowBytes = width * 4;
  if (
    width <= 0 ||
    height <= 0 ||
    pixelOffset + rowBytes * height !== bytes.length
  ) {
    throw new Error(`Plan 018 iOS BMP dimensions changed: ${bmpPath}`);
  }
  const data = new Uint8ClampedArray(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    const sourceY = signedHeight < 0 ? y : height - y - 1;
    for (let x = 0; x < width; x += 1) {
      const source = pixelOffset + sourceY * rowBytes + x * 4;
      const target = (y * width + x) * 4;
      data[target] = bytes[source + 2];
      data[target + 1] = bytes[source + 1];
      data[target + 2] = bytes[source];
      data[target + 3] = bytes[source + 3];
    }
  }
  return { width, height, data, backgroundSrgbHex };
}

function safeRunRoot(argument) {
  const resolved = path.resolve(argument);
  if (!resolved.startsWith(`${repoRoot}${path.sep}`)) {
    throw new Error('Plan 018 iOS health run root escapes the repository');
  }
  return resolved;
}

if (process.argv[1] != null && path.resolve(process.argv[1]) === scriptPath) {
  if (process.argv[2] === '--validate' && process.argv.length === 4) {
    const evidence = validateStoredPlan018IosHealthEvidence(process.argv[3]);
    console.log(JSON.stringify({
      status: evidence.status,
      frameCount: evidence.frameCount,
      passTripletCount: evidence.passTripletCount,
    }));
  } else if (process.argv.length === 3) {
    runPlan018IosCaptureHealthAnalysis(process.argv[2]);
  } else {
    throw new Error(
      'Usage: node analyze_plan018_ios_capture_health.mjs [--validate] RUN_ROOT',
    );
  }
}
