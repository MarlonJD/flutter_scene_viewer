import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import {
  PLAN018_ANALYSIS_THRESHOLDS,
  buildPlan018FrameHealthChecks,
  summarizePlan018Frame,
  summarizePlan018FrameDelta,
} from './plan018_controlled_comparison_analysis.mjs';
import {
  hashBytes,
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
  'analyze_plan018_renderer_native_sheen_control.test.mjs',
);
const statePath = path.join(
  repoRoot,
  'tools/material_extension_acceptance/fixtures/' +
    'plan018_renderer_native_scalar_sheen_control_state.json',
);
const expectedStateSha256 =
  'e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63';
const expectedModelIds = Object.freeze([
  'renderer_native_scalar_sheen_on',
  'renderer_native_scalar_sheen_off',
]);
const expectedPasses = Object.freeze(['directOnly', 'iblOnly', 'combined']);
const comparisonBoundary = 'renderer-local sheen on/off control only';

export function buildPlan018RendererNativeControlInventory(state) {
  validateState(state);
  return expectedModelIds.flatMap((modelId) => expectedPasses.map((pass) => ({
    modelId,
    controlRole: state.models[modelId].controlRole,
    application: state.models[modelId].expectedApplication,
    view: 'grazing',
    pass,
    fileName: `${modelId}_grazing_${pass}.png`,
  })));
}

export function buildPlan018RendererNativeControlVisualAnalysis({
  state,
  stateSha256,
  inventory,
  images,
  captures,
  analysisSourceSha256,
}) {
  validateState(state);
  const expectedInventory = buildPlan018RendererNativeControlInventory(state);
  if (JSON.stringify(inventory) !== JSON.stringify(expectedInventory)) {
    throw new Error('Plan 018 renderer-native visual inventory drifted');
  }
  if (stateSha256 !== expectedStateSha256) {
    throw new Error('Plan 018 renderer-native visual state bytes drifted');
  }

  const frames = inventory.map((record) => {
    const image = images[record.fileName];
    const capture = captures[record.fileName];
    if (image == null || capture == null) {
      throw new Error(`Plan 018 renderer-native visual frame is missing: ${record.fileName}`);
    }
    const summary = summarizePlan018Frame(image);
    const checks = buildPlan018FrameHealthChecks(summary);
    if (checks.some((check) => !check.passed)) {
      throw new Error(
        `Plan 018 renderer-native frame health failed: ${record.fileName}`,
      );
    }
    return { ...record, ...capture, summary, checks };
  });

  const onOffComparisons = expectedPasses.map((pass) => {
    const onFileName =
      `renderer_native_scalar_sheen_on_grazing_${pass}.png`;
    const offFileName =
      `renderer_native_scalar_sheen_off_grazing_${pass}.png`;
    const summary = summarizePlan018FrameDelta(
      images[onFileName],
      images[offFileName],
    );
    const minimum =
      PLAN018_ANALYSIS_THRESHOLDS.intraRendererMeanAbsoluteSrgbDeltaMin;
    const check = {
      name: `sheenOnOffDelta.${pass}`,
      actual: summary.meanAbsoluteSrgb,
      expected: `>= ${minimum}`,
      passed: summary.meanAbsoluteSrgb >= minimum,
    };
    if (!check.passed) {
      throw new Error(`Plan 018 renderer-native sheen on/off delta failed: ${pass}`);
    }
    return { pass, onFileName, offFileName, summary, check };
  });

  return {
    schemaVersion: 1,
    status: 'verified locally',
    executionEvidence: 'verified locally',
    visualEvidence: 'verified locally',
    scope:
      'flutter_scene_viewer iOS Simulator renderer-native sheen visual control',
    application: {
      sheenOn: 'rendererNative',
      sheenOff: 'none',
    },
    runtimeAvailability: 'available',
    featureMaturity: 'release pending',
    comparisonBoundary,
    stateSha256,
    thresholds: PLAN018_ANALYSIS_THRESHOLDS,
    thresholdBoundary:
      'Existing Plan 018 renderer-local structural and mean absolute sRGB delta thresholds.',
    fullFrameOnly: true,
    externalReference: 'not run',
    crossRendererPixelThresholds: [],
    inventory,
    frameCount: frames.length,
    onOffComparisonCount: onOffComparisons.length,
    frames,
    onOffComparisons,
    minimumObserved: {
      foregroundFraction: Math.min(
        ...frames.map((frame) => frame.summary.foregroundFraction),
      ),
      foregroundWidthSpan: Math.min(
        ...frames.map((frame) => frame.summary.foregroundWidthSpan),
      ),
      foregroundHeightSpan: Math.min(
        ...frames.map((frame) => frame.summary.foregroundHeightSpan),
      ),
      luminanceP99P01: Math.min(
        ...frames.map((frame) => frame.summary.luminanceP99P01),
      ),
      quantizedRgbBins: Math.min(
        ...frames.map((frame) => frame.summary.quantizedRgbBins),
      ),
      sheenOnOffMeanAbsoluteSrgbDelta: Math.min(
        ...onOffComparisons.map((comparison) => comparison.check.actual),
      ),
    },
    analysisSourceSha256,
    physicalIos: 'not run',
    android: 'not run',
    web: 'not run',
    physicalCorrectness: 'not run',
    generalPixelParity: 'not run',
    productionReadiness: 'not run',
    claimBoundary:
      'Renderer-local scalar sheen on/off visual effect and structural frame health only; no external reference, physical correctness, general pixel parity, physical-target, release, or production-ready claim.',
  };
}

export function validatePlan018RendererNativeControlVisualAnalysis(
  evidence,
  {
    state,
    stateSha256,
    inventory,
    captures,
    verifyAnalysisSources = true,
  },
) {
  validateState(state);
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.executionEvidence !== 'verified locally' ||
    evidence.visualEvidence !== 'verified locally' ||
    evidence.scope !==
      'flutter_scene_viewer iOS Simulator renderer-native sheen visual control' ||
    JSON.stringify(evidence.application) !==
      JSON.stringify({ sheenOn: 'rendererNative', sheenOff: 'none' }) ||
    evidence.runtimeAvailability !== 'available' ||
    evidence.featureMaturity !== 'release pending' ||
    evidence.comparisonBoundary !== comparisonBoundary ||
    evidence.stateSha256 !== stateSha256 ||
    evidence.stateSha256 !== expectedStateSha256 ||
    evidence.fullFrameOnly !== true ||
    evidence.externalReference !== 'not run' ||
    JSON.stringify(evidence.crossRendererPixelThresholds) !== '[]' ||
    evidence.physicalIos !== 'not run' ||
    evidence.android !== 'not run' ||
    evidence.web !== 'not run' ||
    evidence.physicalCorrectness !== 'not run' ||
    evidence.generalPixelParity !== 'not run' ||
    evidence.productionReadiness !== 'not run' ||
    JSON.stringify(evidence.thresholds) !==
      JSON.stringify(PLAN018_ANALYSIS_THRESHOLDS)
  ) {
    throw new Error('Plan 018 renderer-native visual evidence boundary changed');
  }
  const expectedInventory = buildPlan018RendererNativeControlInventory(state);
  if (
    JSON.stringify(inventory) !== JSON.stringify(expectedInventory) ||
    JSON.stringify(evidence.inventory) !== JSON.stringify(expectedInventory) ||
    evidence.frameCount !== 6 ||
    evidence.frames?.length !== 6 ||
    evidence.onOffComparisonCount !== 3 ||
    evidence.onOffComparisons?.length !== 3
  ) {
    throw new Error('Plan 018 renderer-native visual evidence inventory drifted');
  }

  for (const [index, record] of inventory.entries()) {
    const frame = evidence.frames[index];
    const capture = captures[record.fileName];
    if (
      capture == null ||
      frame.modelId !== record.modelId ||
      frame.controlRole !== record.controlRole ||
      frame.application !== record.application ||
      frame.view !== record.view ||
      frame.pass !== record.pass ||
      frame.fileName !== record.fileName ||
      frame.path !== capture.path ||
      frame.sha256 !== capture.sha256 ||
      frame.byteLength !== capture.byteLength ||
      JSON.stringify(frame.dimensions) !== JSON.stringify(capture.dimensions) ||
      JSON.stringify(frame.summary?.dimensions) !==
        JSON.stringify(capture.dimensions) ||
      frame.checks?.some((check) => !check.passed) !== false ||
      JSON.stringify(frame.checks) !==
        JSON.stringify(buildPlan018FrameHealthChecks(frame.summary))
    ) {
      throw new Error(
        `Plan 018 renderer-native visual frame identity drifted: ${record.fileName}`,
      );
    }
  }

  for (const [index, pass] of expectedPasses.entries()) {
    const comparison = evidence.onOffComparisons[index];
    const minimum =
      PLAN018_ANALYSIS_THRESHOLDS.intraRendererMeanAbsoluteSrgbDeltaMin;
    if (
      comparison?.pass !== pass ||
      comparison.onFileName !==
        `renderer_native_scalar_sheen_on_grazing_${pass}.png` ||
      comparison.offFileName !==
        `renderer_native_scalar_sheen_off_grazing_${pass}.png` ||
      comparison.check?.name !== `sheenOnOffDelta.${pass}` ||
      comparison.check?.actual !== comparison.summary?.meanAbsoluteSrgb ||
      comparison.check?.expected !== `>= ${minimum}` ||
      comparison.check?.passed !== true ||
      comparison.check.actual < minimum
    ) {
      throw new Error(
        `Plan 018 renderer-native sheen on/off evidence drifted: ${pass}`,
      );
    }
  }

  if (verifyAnalysisSources) {
    if (
      JSON.stringify(evidence.analysisSourceSha256) !==
      JSON.stringify(currentAnalysisSourceSha256())
    ) {
      throw new Error('Plan 018 renderer-native visual analysis source drifted');
    }
  }
}

export function runPlan018RendererNativeControlVisualAnalysis(runRootArgument) {
  const runRoot = safeRunRoot(runRootArgument);
  const stateBytes = fs.readFileSync(statePath);
  const stateSha256 = hashBytes(stateBytes);
  if (stateSha256 !== expectedStateSha256) {
    throw new Error('Plan 018 renderer-native control-state bytes drifted');
  }
  const state = JSON.parse(stateBytes);
  const inventory = buildPlan018RendererNativeControlInventory(state);
  const conversionRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-native-sheen-bmp-'),
  );
  const images = {};
  const captures = {};
  try {
    for (const record of inventory) {
      const filePath = path.join(runRoot, record.fileName);
      const bytes = fs.readFileSync(filePath);
      captures[record.fileName] = {
        path: record.fileName,
        sha256: hashBytes(bytes),
        byteLength: bytes.length,
      };
      images[record.fileName] = decodePngWithSips(
        filePath,
        path.join(conversionRoot, `${record.fileName}.bmp`),
        state.background.srgbHex,
      );
      const expectedDimensions = {
        width: state.viewport.logicalWidth * state.viewport.devicePixelRatio,
        height: state.viewport.logicalHeight * state.viewport.devicePixelRatio,
      };
      const actualDimensions = {
        width: images[record.fileName].width,
        height: images[record.fileName].height,
      };
      if (JSON.stringify(actualDimensions) !== JSON.stringify(expectedDimensions)) {
        throw new Error(
          `Plan 018 renderer-native PNG dimensions drifted: ${record.fileName}`,
        );
      }
      captures[record.fileName].dimensions = actualDimensions;
    }
    const evidence = buildPlan018RendererNativeControlVisualAnalysis({
      state,
      stateSha256,
      inventory,
      images,
      captures,
      analysisSourceSha256: currentAnalysisSourceSha256(),
    });
    validatePlan018RendererNativeControlVisualAnalysis(evidence, {
      state,
      stateSha256,
      inventory,
      captures,
    });
    return evidence;
  } finally {
    fs.rmSync(conversionRoot, { recursive: true, force: true });
  }
}

function validateState(state) {
  if (
    state?.schemaVersion !== 1 ||
    state.name !== 'plan018_renderer_native_scalar_sheen_control' ||
    state.comparisonBoundary !== comparisonBoundary ||
    JSON.stringify(Object.keys(state.models ?? {})) !==
      JSON.stringify(expectedModelIds) ||
    JSON.stringify(state.renderPasses) !== JSON.stringify(expectedPasses) ||
    state.models.renderer_native_scalar_sheen_on?.controlRole !== 'sheenOn' ||
    state.models.renderer_native_scalar_sheen_on?.expectedApplication !==
      'rendererNative' ||
    state.models.renderer_native_scalar_sheen_off?.controlRole !== 'sheenOff' ||
    state.models.renderer_native_scalar_sheen_off?.expectedApplication !== 'none' ||
    Object.keys(
      state.models.renderer_native_scalar_sheen_on?.cameras ?? {},
    ).join(',') !== 'grazing' ||
    Object.keys(
      state.models.renderer_native_scalar_sheen_off?.cameras ?? {},
    ).join(',') !== 'grazing'
  ) {
    throw new Error('Plan 018 renderer-native visual control state drifted');
  }
}

function currentAnalysisSourceSha256() {
  return Object.fromEntries(
    [analysisModulePath, scriptPath, testPath].map((sourcePath) => [
      path.basename(sourcePath),
      hashBytes(fs.readFileSync(sourcePath)),
    ]),
  );
}

function decodePngWithSips(pngPath, bmpPath, backgroundSrgbHex) {
  const result = spawnSync(
    '/usr/bin/sips',
    ['-s', 'format', 'bmp', pngPath, '--out', bmpPath],
    { encoding: 'utf8', maxBuffer: 1024 * 1024 },
  );
  if (result.status !== 0) {
    throw new Error(
      `Plan 018 renderer-native PNG decode failed: ${path.basename(pngPath)}: ` +
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
    throw new Error(`Plan 018 renderer-native BMP contract changed: ${bmpPath}`);
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
    throw new Error(`Plan 018 renderer-native BMP dimensions changed: ${bmpPath}`);
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
  const outputRoot = path.join(
    repoRoot,
    'tools/out/material_extension_acceptance/plan018_controlled_comparison/' +
      'ios_simulator',
  );
  const resolved = path.resolve(argument);
  if (
    path.dirname(resolved) !== outputRoot ||
    !path.basename(resolved).startsWith('renderer-native-run-')
  ) {
    throw new Error('Plan 018 renderer-native visual run root is outside scope');
  }
  return resolved;
}

if (process.argv[1] != null && path.resolve(process.argv[1]) === scriptPath) {
  if (process.argv.length !== 3) {
    throw new Error(
      'Usage: node analyze_plan018_renderer_native_sheen_control.mjs RUN_ROOT',
    );
  }
  console.log(JSON.stringify(
    runPlan018RendererNativeControlVisualAnalysis(process.argv[2]),
  ));
}
