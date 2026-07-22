import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  PLAN018_ANALYSIS_THRESHOLDS,
  buildPlan018ExpectedCaptureInventory,
  buildPlan018FrameHealthChecks,
  validatePlan018AnalysisIdentity,
  validatePlan018CaptureInventory,
} from './plan018_controlled_comparison_analysis.mjs';
import {
  hashBytes,
  loadPlan018ControlledComparisonState,
  outputRoot,
  plan018StateHash,
  repoRoot,
  statePath,
} from './plan018_controlled_comparison_contract.mjs';
import {
  validatePlan018CaptureEvidence,
} from './render_plan018_controlled_comparison.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const analysisModulePath = path.join(
  scriptDir,
  'plan018_controlled_comparison_analysis.mjs',
);
const analysisTestPath = path.join(
  scriptDir,
  'plan018_controlled_comparison_analysis.test.mjs',
);
const healthTestPath = path.join(
  scriptDir,
  'analyze_plan018_controlled_comparison_health.test.mjs',
);
const threeEvidencePath = path.join(outputRoot, 'threejs', 'evidence.json');
export const plan018ThreeHealthBaselinePath = path.join(
  outputRoot,
  'threejs',
  'health_baseline.json',
);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

export async function cleanupPlan018AnalysisResources({
  disposePage,
  closeBrowser,
  closeServer,
  removeProfile,
}) {
  const errors = [];
  for (const action of [
    disposePage,
    closeBrowser,
    closeServer,
    removeProfile,
  ]) {
    try {
      await action();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length !== 0) {
    throw new AggregateError(errors, 'Plan 018 analysis cleanup failed');
  }
}

export async function runPlan018ThreeCaptureHealthAnalysis({
  writeEvidence = true,
} = {}) {
  const state = loadPlan018ControlledComparisonState();
  const stateSha256 = plan018StateHash();
  const threeEvidenceBytes = fs.readFileSync(threeEvidencePath);
  const threeEvidence = JSON.parse(threeEvidenceBytes);
  const captureEvidenceSourceDrifts = validateCurrentCaptureEvidence(
    threeEvidence,
  );
  const inventory = buildPlan018ExpectedCaptureInventory(state);
  validatePlan018CaptureInventory(inventory, threeEvidence.captureInventory);
  if (threeEvidence.stateSha256 !== stateSha256) {
    throw new Error('Plan 018 Three capture evidence has a stale state hash');
  }

  const captureByFileName = Object.fromEntries(
    threeEvidence.captures.map((capture) => [
      path.basename(capture.path),
      capture,
    ]),
  );
  const groups = groupInventory(inventory);
  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-comparison-analysis-'),
  );
  const server = http.createServer(serveRepositoryFile);
  let origin = '';
  let browser;
  let page;
  let result;
  let failure;

  try {
    await listenLocalOnly(server);
    origin = `http://127.0.0.1:${server.address().port}`;
    const executablePath =
      process.env.PUPPETEER_EXECUTABLE_PATH ??
      (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
    browser = await puppeteer.launch({
      headless: true,
      executablePath,
      userDataDir: profilePath,
      args: ['--disable-background-networking', '--disable-gpu-sandbox'],
    });
    page = await browser.newPage();
    await page.goto(`${origin}/__plan018_health__.html`, {
      waitUntil: 'load',
    });

    const frames = [];
    const passTriplets = [];
    for (const group of groups) {
      const records = Object.fromEntries(
        group.records.map((record) => [record.pass, record]),
      );
      const browserResult = await page.evaluate(
        analyzeTripletInBrowser,
        {
          analysisModuleUrl: repositoryUrl(origin, analysisModulePath),
          backgroundSrgbHex: state.background.srgbHex,
          imageUrls: Object.fromEntries(
            Object.entries(records).map(([pass, record]) => [
              pass,
              repositoryUrl(
                origin,
                safeEvidencePath(captureByFileName[record.fileName].path),
              ),
            ]),
          ),
        },
      );
      for (const record of group.records) {
        const capture = captureByFileName[record.fileName];
        const summary = browserResult.summaries[record.pass];
        const checks = buildPlan018FrameHealthChecks(summary);
        if (checks.some((check) => !check.passed)) {
          throw new Error(
            `Plan 018 Three frame health failed: ${record.fileName}`,
          );
        }
        const identity = captureIdentity(state, stateSha256, record, capture);
        validatePlan018AnalysisIdentity(identity.expected, identity.actual);
        frames.push({
          ...record,
          path: capture.path,
          sha256: capture.sha256,
          byteLength: capture.byteLength,
          dimensions: capture.dimensions,
          identity: identity.actual,
          summary,
          checks,
        });
      }
      if (browserResult.checks.some((check) => !check.passed)) {
        throw new Error(
          `Plan 018 Three pass delta failed: ${group.modelId}/${group.view}`,
        );
      }
      passTriplets.push({
        modelId: group.modelId,
        view: group.view,
        checks: browserResult.checks,
      });
    }

    result = buildEvidence({
      state,
      stateSha256,
      threeEvidence,
      threeEvidenceBytes,
      captureEvidenceSourceDrifts,
      inventory,
      frames,
      passTriplets,
    });
    validatePlan018ThreeHealthEvidence(result);
  } catch (error) {
    failure = error;
  }

  try {
    await cleanupPlan018AnalysisResources({
      disposePage: async () => {
        if (page != null && !page.isClosed()) await page.close();
      },
      closeBrowser: async () => {
        if (browser != null) await browser.close();
      },
      closeServer: async () => closeServer(server),
      removeProfile: () =>
        fs.rmSync(profilePath, { recursive: true, force: true }),
    });
  } catch (cleanupError) {
    failure = failure == null
      ? cleanupError
      : new AggregateError(
          [failure, cleanupError],
          'Plan 018 health analysis and cleanup failed',
        );
  }
  if (failure != null) throw failure;

  if (writeEvidence) {
    fs.mkdirSync(path.dirname(plan018ThreeHealthBaselinePath), {
      recursive: true,
    });
    fs.writeFileSync(
      plan018ThreeHealthBaselinePath,
      `${JSON.stringify(result, null, 2)}\n`,
    );
  }
  console.log(
    'Plan 018 Three health baseline: 27 frames / 9 pass triplets OK',
  );
  console.log(
    `Darkest mean: ${result.darkestFrames.byMeanSrgbLuminance.fileName} ` +
      `(${result.darkestFrames.byMeanSrgbLuminance.actual})`,
  );
  console.log(
    `Minimum pass delta: ${result.minimumObserved.intraRendererMeanAbsoluteSrgbDelta}`,
  );
  return result;
}

export function validatePlan018ThreeHealthEvidence(evidence) {
  const state = loadPlan018ControlledComparisonState();
  const expectedInventory = buildPlan018ExpectedCaptureInventory(state);
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.scope !== 'pinned Three.js renderer-local capture health baseline' ||
    evidence.stateSha256 !== plan018StateHash() ||
    evidence.featureMaturity !== 'candidate-only' ||
    evidence.flutterIosStatus !== 'not run' ||
    evidence.fullFrameOnly !== true ||
    evidence.boardsProduced !== false ||
    evidence.captureEvidenceStatus !== 'current' ||
    JSON.stringify(evidence.captureEvidenceSourceDrifts) !== '[]' ||
    JSON.stringify(evidence.crossRendererPixelThresholds) !== '[]' ||
    JSON.stringify(evidence.thresholds) !==
      JSON.stringify(PLAN018_ANALYSIS_THRESHOLDS)
  ) {
    throw new Error('Plan 018 Three health evidence boundary changed');
  }
  validatePlan018CaptureInventory(expectedInventory, evidence.inventory);
  if (
    evidence.frames?.length !== 27 ||
    evidence.passTriplets?.length !== 9 ||
    evidence.frames.some((frame) =>
      frame.checks?.some((check) => !check.passed) ?? true,
    ) ||
    evidence.passTriplets.some((triplet) =>
      triplet.checks?.some((check) => !check.passed) ?? true,
    )
  ) {
    throw new Error('Plan 018 Three health checks are incomplete or failed');
  }
  for (const source of Object.values(
    evidence.sourceIdentity.analysisSources,
  )) {
    const bytes = fs.readFileSync(path.join(repoRoot, source.path));
    if (hashBytes(bytes) !== source.sha256) {
      throw new Error(`Plan 018 analysis source drifted: ${source.path}`);
    }
  }
  if (
    JSON.stringify(evidence.toycarAuthoredMaterialRoles) !==
      JSON.stringify([
        {
          role: 'clearcoat',
          materialIndex: 0,
          extensions: ['KHR_materials_clearcoat'],
        },
        {
          role: 'sheen',
          materialIndex: 1,
          extensions: ['KHR_materials_sheen'],
        },
        {
          role: 'transmissionVolume',
          materialIndex: 2,
          extensions: ['KHR_materials_transmission'],
        },
      ])
  ) {
    throw new Error('Plan 018 ToyCar authored generic roles drifted');
  }
}

function validateCurrentCaptureEvidence(evidence) {
  const drifts = [];
  for (const [relativePath, recorded] of Object.entries(
    evidence.renderHarness?.sources ?? {},
  )) {
    const bytes = fs.readFileSync(path.join(repoRoot, relativePath));
    const current = {
      sha256: hashBytes(bytes),
      byteLength: bytes.length,
    };
    if (
      current.sha256 !== recorded.sha256 ||
      current.byteLength !== recorded.byteLength
    ) {
      drifts.push({ relativePath, recorded, current });
    }
  }
  if (drifts.length !== 0) {
    throw new Error('Plan 018 current capture evidence has render-harness drift');
  }
  validatePlan018CaptureEvidence(evidence);
  return drifts;
}

function buildEvidence({
  state,
  stateSha256,
  threeEvidence,
  threeEvidenceBytes,
  captureEvidenceSourceDrifts,
  inventory,
  frames,
  passTriplets,
}) {
  return {
    schemaVersion: 1,
    status: 'verified locally',
    scope: 'pinned Three.js renderer-local capture health baseline',
    captureEvidenceStatus: 'current',
    captureEvidenceSourceDrifts,
    featureMaturity: 'candidate-only',
    flutterIosStatus: 'not run',
    physicalIosStatus: 'not run',
    androidStatus: 'not run',
    webTargetStatus: 'not run',
    sourceState: path.relative(repoRoot, statePath),
    stateSha256,
    thresholds: PLAN018_ANALYSIS_THRESHOLDS,
    thresholdFreezeBoundary:
      'Frozen from the existing Three.js source set before any Flutter/iOS comparison image existed; renderer-local structural gates only.',
    fullFrameOnly: true,
    analysisOperations: [
      'full-frame decode',
      'background-derived foreground summary',
      'renderer-local direct/IBL/combined delta',
    ],
    crossRendererPixelThresholds: [],
    boardsProduced: false,
    inventory,
    frames,
    passTriplets,
    minimumObserved: minimumObserved(frames, passTriplets),
    darkestFrames: {
      byMeanSrgbLuminance: minimumFrame(
        frames,
        'meanSrgbLuminance',
      ),
      byLuminanceSpread: minimumFrame(frames, 'luminanceP99P01'),
    },
    toycarAuthoredMaterialRoles: readToyCarAuthoredRoles(state),
    sourceIdentity: {
      state: {
        path: path.relative(repoRoot, statePath),
        sha256: stateSha256,
      },
      threeEvidence: {
        path: path.relative(repoRoot, threeEvidencePath),
        sha256: hashBytes(threeEvidenceBytes),
      },
      environmentSha256: state.environment.sha256,
      modelSha256: Object.fromEntries(
        Object.entries(state.models).map(([modelId, model]) => [
          modelId,
          model.sha256,
        ]),
      ),
      renderer: threeEvidence.renderer,
      analysisSources: Object.fromEntries(
        [analysisModulePath, scriptPath, analysisTestPath, healthTestPath]
          .map((sourcePath) => {
            const relativePath = path.relative(repoRoot, sourcePath);
            return [
              path.basename(sourcePath),
              {
                path: relativePath,
                sha256: hashBytes(fs.readFileSync(sourcePath)),
              },
            ];
          }),
      ),
    },
    comparisonBoundary:
      'Three.js reference direction/conformance health only. No Flutter/iOS image exists in this baseline; there is no cross-renderer similarity gate, alignment, crop, overlay, difference heatmap, pixel-parity claim, or physical-target claim.',
  };
}

function captureIdentity(state, stateSha256, record, capture) {
  const model = state.models[record.modelId];
  const sourceSha256 = {
    state: stateSha256,
    environment: state.environment.sha256,
    model: model.sha256,
    packageLock: state.referenceRenderer.packageLockSha256,
    capture: capture.sha256,
  };
  const actual = {
    stateSha256,
    cameraSha256: hashCanonicalJson(capture.camera),
    passSha256: hashCanonicalJson(capture.passState),
    sourceSha256,
  };
  return { expected: structuredClone(actual), actual };
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

function minimumObserved(frames, passTriplets) {
  const frameMinimum = (field) =>
    Math.min(...frames.map((frame) => frame.summary[field]));
  return {
    foregroundFraction: frameMinimum('foregroundFraction'),
    foregroundWidthSpan: frameMinimum('foregroundWidthSpan'),
    foregroundHeightSpan: frameMinimum('foregroundHeightSpan'),
    luminanceP99P01: frameMinimum('luminanceP99P01'),
    quantizedRgbBins: frameMinimum('quantizedRgbBins'),
    intraRendererMeanAbsoluteSrgbDelta: Math.min(
      ...passTriplets.flatMap((triplet) =>
        triplet.checks.map((check) => check.actual),
      ),
    ),
  };
}

function minimumFrame(frames, field) {
  const frame = frames.reduce((minimum, candidate) =>
    candidate.summary[field] < minimum.summary[field] ? candidate : minimum,
  );
  return { fileName: frame.fileName, actual: frame.summary[field] };
}

function readToyCarAuthoredRoles(state) {
  const bytes = fs.readFileSync(path.join(repoRoot, state.models.toycar.path));
  const jsonLength = bytes.readUInt32LE(12);
  const gltf = JSON.parse(
    bytes.subarray(20, 20 + jsonLength).toString('utf8').replace(/\u0000+$/u, ''),
  );
  const roles = [];
  for (const [materialIndex, material] of (gltf.materials ?? []).entries()) {
    const extensions = Object.keys(material.extensions ?? {});
    if (extensions.includes('KHR_materials_clearcoat')) {
      roles.push({
        role: 'clearcoat',
        materialIndex,
        extensions: ['KHR_materials_clearcoat'],
      });
    }
    if (extensions.includes('KHR_materials_sheen')) {
      roles.push({
        role: 'sheen',
        materialIndex,
        extensions: ['KHR_materials_sheen'],
      });
    }
    if (extensions.includes('KHR_materials_transmission')) {
      roles.push({
        role: 'transmissionVolume',
        materialIndex,
        extensions: extensions.filter((extension) =>
          extension === 'KHR_materials_transmission' ||
          extension === 'KHR_materials_volume',
        ),
      });
    }
  }
  return roles;
}

function hashCanonicalJson(value) {
  return hashBytes(Buffer.from(JSON.stringify(canonicalize(value))));
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value != null && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

async function analyzeTripletInBrowser(arguments_) {
  const analysis = await import(arguments_.analysisModuleUrl);
  const images = Object.fromEntries(
    await Promise.all(
      Object.entries(arguments_.imageUrls).map(async ([pass, url]) => [
        pass,
        await loadImage(url, arguments_.backgroundSrgbHex),
      ]),
    ),
  );
  return {
    summaries: Object.fromEntries(
      Object.entries(images).map(([pass, image]) => [
        pass,
        analysis.summarizePlan018Frame(image),
      ]),
    ),
    checks: analysis.buildPlan018PassDeltaChecks(images),
  };

  async function loadImage(url, backgroundSrgbHex) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Could not load Plan 018 image: ${url}`);
    const bitmap = await createImageBitmap(await response.blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(bitmap, 0, 0);
    const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height);
    bitmap.close();
    return {
      width: pixels.width,
      height: pixels.height,
      data: pixels.data,
      backgroundSrgbHex,
    };
  }
}

function repositoryUrl(origin, absolutePath) {
  const relativePath = path.relative(repoRoot, absolutePath);
  if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
    throw new Error('Plan 018 analysis source path escapes the repository');
  }
  return `${origin}/${relativePath.split(path.sep).map(encodeURIComponent).join('/')}`;
}

function safeEvidencePath(relativePath) {
  if (typeof relativePath !== 'string' || path.isAbsolute(relativePath)) {
    throw new Error('Plan 018 evidence path is not repository-relative');
  }
  const resolved = path.resolve(repoRoot, relativePath);
  if (!resolved.startsWith(`${repoRoot}${path.sep}`)) {
    throw new Error('Plan 018 evidence path escapes the repository');
  }
  return resolved;
}

function serveRepositoryFile(request, response) {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__plan018_health__.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end('<!doctype html><meta charset="utf-8"><title>Plan 018 health</title>');
    return;
  }
  if (url.pathname === '/favicon.ico') {
    response.writeHead(204);
    response.end();
    return;
  }
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  const filePath = path.normalize(path.join(repoRoot, relativePath));
  if (!filePath.startsWith(`${repoRoot}${path.sep}`)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  fs.readFile(filePath, (error, bytes) => {
    if (error) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(bytes);
  });
}

function contentType(filePath) {
  if (filePath.endsWith('.mjs') || filePath.endsWith('.js')) {
    return 'text/javascript';
  }
  if (filePath.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

function listenLocalOnly(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

function closeServer(server) {
  if (!server.listening) return Promise.resolve();
  return new Promise((resolve, reject) =>
    server.close((error) => error == null ? resolve() : reject(error)),
  );
}

if (process.argv[1] != null && path.resolve(process.argv[1]) === scriptPath) {
  await runPlan018ThreeCaptureHealthAnalysis();
}
