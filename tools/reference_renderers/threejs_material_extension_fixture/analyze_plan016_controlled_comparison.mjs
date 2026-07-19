import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import puppeteer from 'puppeteer';

import {
  buildPlan016ComparisonChecks,
  relativeError,
} from './plan016_controlled_comparison_metrics.mjs';
import {
  hashBytes,
  loadPlan016ControlledComparisonState,
  outputRoot,
  plan016StateHash,
  repoRoot,
} from './plan016_controlled_comparison_contract.mjs';

const state = loadPlan016ControlledComparisonState();
const captureArgument = process.argv[2] ?? process.env.PLAN016_IOS_CAPTURE_ROOT;
if (captureArgument == null) {
  throw new Error(
    'Usage: node analyze_plan016_controlled_comparison.mjs <capture-root>',
  );
}
const captureRoot = path.resolve(repoRoot, captureArgument);
const iosEvidencePath = path.join(captureRoot, 'evidence.json');
const iosEvidence = JSON.parse(fs.readFileSync(iosEvidencePath, 'utf8'));
const threeRoot = path.join(outputRoot, 'threejs');
const threeEvidence = JSON.parse(
  fs.readFileSync(path.join(threeRoot, 'evidence.json'), 'utf8'),
);
const threeCalibration = JSON.parse(
  fs.readFileSync(path.join(threeRoot, 'control_calibration.json'), 'utf8'),
);
const stateSha256 = plan016StateHash();
for (const evidence of [iosEvidence, threeEvidence, threeCalibration]) {
  if (evidence.stateSha256 !== stateSha256) {
    throw new Error('Plan 016 evidence is stale for image analysis');
  }
}
if (threeCalibration.status !== 'pass') {
  throw new Error('Plan 016 Three.js threshold calibration did not pass');
}

const visualsRoot = path.join(captureRoot, 'visuals');
fs.mkdirSync(visualsRoot, { recursive: true });
const profilePath = fs.mkdtempSync(
  path.join(os.tmpdir(), 'plan016-controlled-analysis-'),
);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
let origin = '';
const server = http.createServer(serveRepositoryFile);
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
origin = `http://127.0.0.1:${server.address().port}`;

let browser;
try {
  browser = await puppeteer.launch({
    headless: true,
    executablePath,
    userDataDir: profilePath,
    args: ['--disable-background-networking', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  await page.goto(`${origin}/__plan016_image_analysis__.html`, {
    waitUntil: 'networkidle0',
  });
  const roi = state.comparisonMetrics.syntheticGlassRoiNormalized;
  const dpr = state.viewport.devicePixelRatio;
  const url = (evidence, modelId, pass = 'combined') =>
    `${origin}/${evidence.artifacts[modelId][pass].path}`;

  const camera = await page.evaluate(
    (arguments_) => globalThis.plan016CameraComparison(arguments_),
    {
      referenceOffUrl: url(threeEvidence, 'control_transmission_off'),
      referenceThinUrl: url(threeEvidence, 'control_thin'),
      candidateOffUrl: url(iosEvidence, 'control_transmission_off'),
      candidateThinUrl: url(iosEvidence, 'control_thin'),
      roi,
      dpr,
    },
  );

  const alignedRendererComparisons = {};
  for (const [modelId, model] of Object.entries(state.models)) {
    if (model.kind !== 'synthetic') continue;
    alignedRendererComparisons[modelId] = await page.evaluate(
      (arguments_) => globalThis.plan016CompareImages(arguments_),
      {
        referenceUrl: url(threeEvidence, modelId),
        candidateUrl: url(iosEvidence, modelId),
        roi,
        candidateShiftPhysical: camera.alignmentShiftPhysical,
      },
    );
  }

  const maskedEffects = await page.evaluate(
    (arguments_) => globalThis.plan016CompareMaskedEffects(arguments_),
    {
      referenceOffUrl: url(threeEvidence, 'control_transmission_off'),
      referenceThinUrl: url(threeEvidence, 'control_thin'),
      referenceAttenuationUrl: url(
        threeEvidence,
        'control_attenuation_tinted',
      ),
      candidateOffUrl: url(iosEvidence, 'control_transmission_off'),
      candidateThinUrl: url(iosEvidence, 'control_thin'),
      candidateAttenuationUrl: url(
        iosEvidence,
        'control_attenuation_tinted',
      ),
      roi,
      candidateShiftPhysical: camera.alignmentShiftPhysical,
    },
  );

  const iosControlPairs = {};
  for (const [trend, [firstModel, secondModel]] of Object.entries(
    state.comparisonMetrics.calibrationControlPairs,
  )) {
    iosControlPairs[trend] = await page.evaluate(
      (arguments_) => globalThis.plan016CompareControlPair(arguments_),
      {
        firstUrl: url(iosEvidence, firstModel),
        secondUrl: url(iosEvidence, secondModel),
        roi,
        dpr,
      },
    );
    iosControlPairs[trend].models = [firstModel, secondModel];
  }

  const officialRois = {
    transmission_test: { left: 0.15, top: 0.36, width: 0.70, height: 0.31 },
    attenuation_test: { left: 0.18, top: 0.30, width: 0.64, height: 0.35 },
    glass_vase_flowers: { left: 0.14, top: 0.29, width: 0.72, height: 0.42 },
    toycar: { left: 0.11, top: 0.35, width: 0.78, height: 0.30 },
  };
  const officialDescriptiveComparisons = {};
  for (const [modelId, modelRoi] of Object.entries(officialRois)) {
    officialDescriptiveComparisons[modelId] = await page.evaluate(
      (arguments_) => globalThis.plan016CompareImages(arguments_),
      {
        referenceUrl: url(threeEvidence, modelId),
        candidateUrl: url(iosEvidence, modelId),
        roi: modelRoi,
        candidateShiftPhysical: camera.alignmentShiftPhysical,
      },
    );
  }

  const metrics = {
    camera,
    alignedRendererComparisons,
    transmittedLuminance: maskedEffects.transmittedLuminance,
    attenuation: maskedEffects.attenuation,
    ior: {
      threejsDisplacementLogical:
        threeCalibration.comparisons.ior.edgeCentroidDistanceLogical,
      iosDisplacementLogical:
        iosControlPairs.ior.edgeCentroidDistanceLogical,
      displacementRelativeError: relativeError(
        iosControlPairs.ior.edgeCentroidDistanceLogical,
        threeCalibration.comparisons.ior.edgeCentroidDistanceLogical,
      ),
      displacementAbsoluteErrorLogical: Math.abs(
        iosControlPairs.ior.edgeCentroidDistanceLogical -
          threeCalibration.comparisons.ior.edgeCentroidDistanceLogical,
      ),
    },
    roughness: {
      threejsEdgeEnergyRatio:
        threeCalibration.comparisons.roughness
          .secondToFirstEdgeEnergyRatio,
      iosEdgeEnergyRatio:
        iosControlPairs.roughness.secondToFirstEdgeEnergyRatio,
      edgeEnergyRatioAbsoluteError: Math.abs(
        iosControlPairs.roughness.secondToFirstEdgeEnergyRatio -
          threeCalibration.comparisons.roughness
            .secondToFirstEdgeEnergyRatio,
      ),
    },
    iosControlPairs,
    threejsControlPairs: threeCalibration.comparisons,
    officialDescriptiveComparisons,
  };
  const checks = buildPlan016ComparisonChecks(
    metrics,
    state.comparisonMetrics.thresholds,
  );

  const visualArtifacts = {};
  const syntheticVisualModels = [
    'control_thin',
    'control_ior_low',
    'control_ior_high',
    'control_volume',
    'control_attenuation_tinted',
    'control_rough_high',
    'control_normal_tilted',
    'control_texture_channels',
    'control_scale_two',
    'control_combined_clearcoat',
  ];
  const visualModels = [
    ...syntheticVisualModels.map((modelId) => ({ modelId, roi })),
    ...Object.entries(officialRois).map(([modelId, modelRoi]) => ({
      modelId,
      roi: modelRoi,
    })),
  ];
  for (const { modelId, roi: modelRoi } of visualModels) {
    const rendered = await page.evaluate(
      (arguments_) => globalThis.plan016RenderVisualSet(arguments_),
      {
        referenceUrl: url(threeEvidence, modelId),
        candidateUrl: url(iosEvidence, modelId),
        roi: modelRoi,
        candidateShiftPhysical: camera.alignmentShiftPhysical,
      },
    );
    visualArtifacts[modelId] = {};
    for (const [kind, dataUrl] of Object.entries(rendered)) {
      const artifactPath = path.join(visualsRoot, `${modelId}_${kind}.png`);
      fs.writeFileSync(artifactPath, decodePng(dataUrl));
      visualArtifacts[modelId][kind] = artifactRecord(artifactPath);
    }
  }

  const boardArtifacts = {};
  const dependency = iosEvidence.renderer?.dependency;
  const dependencyLabel =
    dependency?.kind === 'immutableGitPin'
      ? `immutable pin ${dependency.declaredRevision.slice(0, 8)}`
      : iosEvidence.status;
  boardArtifacts.synthetic = await renderBoard(browser, {
    title: 'Plan 016 · Renderer-native glass controls',
    subtitle:
      'Three.js r167 reference · flutter_scene iOS Simulator Impeller Metal ' +
      `${dependencyLabel} · aligned crops · combined pass`,
    modelIds: syntheticVisualModels,
    visualArtifacts,
    destination: path.join(visualsRoot, 'synthetic_comparison_board.png'),
  });
  boardArtifacts.khronos = await renderBoard(browser, {
    title: 'Plan 016 · Khronos corpus',
    subtitle:
      'Pinned Khronos assets · fixed camera, HDR, light, exposure, PBR ' +
      'Neutral, and sRGB output · combined pass',
    modelIds: Object.keys(officialRois),
    visualArtifacts,
    destination: path.join(visualsRoot, 'khronos_comparison_board.png'),
  });

  const result = {
    schemaVersion: 1,
    status: checks.every((check) => check.passed) ? 'pass' : 'fail',
    evidenceStatus: iosEvidence.status,
    scope:
      'controlled comparison metrics and visual artifacts; publication gate ' +
      'is separate',
    stateSha256,
    roi,
    thresholds: state.comparisonMetrics.thresholds,
    metrics,
    checks,
    visualArtifacts,
    boardArtifacts,
    metricBoundary:
      'Camera alignment uses an independently segmented opaque-versus-thin ' +
      'sphere silhouette. Cross-renderer RGB checks use the tracked central ' +
      'ROI after only the measured integer camera translation. Transmission ' +
      'luminance and attenuation chromaticity use the intersected sphere ' +
      'masks. IOR displacement and roughness ratios reuse the Three.js-only ' +
      'pre-capture calibration algorithm.',
    descriptiveBoundary:
      'Khronos-model RGB differences are recorded but not threshold gates: ' +
      'the assets exercise complete scenes whose independent BRDF, ' +
      'rasterization, and prefilter implementations are intentionally not ' +
      'pixel-identical.',
  };
  const destination = path.join(captureRoot, 'comparison_metrics.json');
  fs.writeFileSync(destination, `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Plan 016 controlled comparison metrics: ${result.status}`);
  for (const check of checks) {
    console.log(
      `${check.passed ? 'PASS' : 'FAIL'} ${check.name}: ` +
        `${check.actual} (${check.expected})`,
    );
  }
  console.log(`Metrics: ${path.relative(repoRoot, destination)}`);
  if (result.status !== 'pass') process.exitCode = 1;
} finally {
  if (browser != null) await browser.close();
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(profilePath, { recursive: true, force: true });
}

function serveRepositoryFile(request, response) {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__plan016_image_analysis__.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(imageAnalysisPage());
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
    response.writeHead(200, {
      'content-type': filePath.endsWith('.png')
        ? 'image/png'
        : 'application/octet-stream',
    });
    response.end(bytes);
  });
}

async function renderBoard(
  activeBrowser,
  { title, subtitle, modelIds, visualArtifacts, destination },
) {
  const boardPage = await activeBrowser.newPage();
  const rowHeight = 292;
  const height = 142 + rowHeight * modelIds.length;
  await boardPage.setViewport({ width: 1440, height, deviceScaleFactor: 1 });
  const rows = modelIds
    .map((modelId) => {
      const artifacts = visualArtifacts[modelId];
      const cells = [
        ['threejsCrop', 'Three.js r167'],
        ['iosAlignedCrop', 'flutter_scene · aligned'],
        ['overlay50', '50% overlay'],
        ['differenceHeatmap', 'absolute difference · 4×'],
      ]
        .map(
          ([kind, label]) =>
            `<figure><img src="${origin}/${artifacts[kind].path}">` +
            `<figcaption>${label}</figcaption></figure>`,
        )
        .join('');
      return `<section><h2>${escapeHtml(modelId)}</h2><div>${cells}</div></section>`;
    })
    .join('');
  await boardPage.setContent(
    `<!doctype html><meta charset="utf-8"><style>
      * { box-sizing: border-box; }
      body { margin: 0; padding: 28px 34px; background: #09090d; color: #f5f4f8;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      h1 { margin: 0; font-size: 31px; }
      p { margin: 7px 0 20px; color: #aaa6b4; font-size: 16px; }
      section { height: ${rowHeight}px; padding-top: 8px; }
      h2 { margin: 0 0 7px; color: #d9d6e0; font-size: 18px; }
      section > div { display: grid; grid-template-columns: repeat(4, 1fr); gap: 14px; }
      figure { margin: 0; height: 244px; border: 1px solid #2c2934;
        border-radius: 12px; overflow: hidden; background: #121118; }
      img { display: block; width: 100%; height: 205px; object-fit: contain;
        background: #121118; }
      figcaption { height: 39px; padding: 10px 12px; border-top: 1px solid #2c2934;
        font-size: 14px; font-weight: 650; }
    </style><h1>${escapeHtml(title)}</h1><p>${escapeHtml(subtitle)}</p>${rows}`,
    { waitUntil: 'networkidle0' },
  );
  await boardPage.screenshot({ path: destination });
  await boardPage.close();
  return artifactRecord(destination);
}

function artifactRecord(artifactPath) {
  const bytes = fs.readFileSync(artifactPath);
  return {
    path: path.relative(repoRoot, artifactPath),
    sha256: hashBytes(bytes),
    byteLength: bytes.length,
    dimensions: pngDimensions(bytes),
  };
}

function pngDimensions(bytes) {
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function decodePng(dataUrl) {
  return Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64');
}

function escapeHtml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

function imageAnalysisPage() {
  return `<!doctype html>
<meta charset="utf-8">
<script>
const maskThreshold = 0.025;

globalThis.plan016CameraComparison = async (arguments_) => {
  const [referenceOff, referenceThin, candidateOff, candidateThin] =
    await Promise.all([
      loadPixels(arguments_.referenceOffUrl),
      loadPixels(arguments_.referenceThinUrl),
      loadPixels(arguments_.candidateOffUrl),
      loadPixels(arguments_.candidateThinUrl),
    ]);
  assertSameDimensions([referenceOff, referenceThin, candidateOff, candidateThin]);
  const box = roiBox(referenceOff, arguments_.roi);
  const referenceMask = differenceMask(referenceOff, referenceThin, box);
  const candidateMask = differenceMask(candidateOff, candidateThin, box);
  const reference = maskSummary(referenceMask, box, arguments_.dpr);
  const candidate = maskSummary(candidateMask, box, arguments_.dpr);
  let intersection = 0;
  let union = 0;
  for (let index = 0; index < referenceMask.length; index += 1) {
    if (referenceMask[index] && candidateMask[index]) intersection += 1;
    if (referenceMask[index] || candidateMask[index]) union += 1;
  }
  const shift = [
    Math.round((reference.centroidLogical[0] - candidate.centroidLogical[0]) * arguments_.dpr),
    Math.round((reference.centroidLogical[1] - candidate.centroidLogical[1]) * arguments_.dpr),
  ];
  return {
    maskThreshold,
    silhouetteIou: intersection / Math.max(union, 1),
    centroidDistanceLogical: vectorDistance(
      reference.centroidLogical,
      candidate.centroidLogical,
    ),
    alignmentShiftPhysical: shift,
    alignmentShiftLogical: shift.map((value) => value / arguments_.dpr),
    reference,
    candidate,
  };
};

globalThis.plan016CompareImages = async (arguments_) => {
  const [reference, candidate] = await Promise.all([
    loadPixels(arguments_.referenceUrl),
    loadPixels(arguments_.candidateUrl),
  ]);
  assertSameDimensions([reference, candidate]);
  const box = roiBox(reference, arguments_.roi);
  const differences = [];
  let sum = 0;
  let count = 0;
  for (let y = box.top; y < box.bottom; y += 1) {
    for (let x = box.left; x < box.right; x += 1) {
      const candidateX = x - arguments_.candidateShiftPhysical[0];
      const candidateY = y - arguments_.candidateShiftPhysical[1];
      if (!contains(candidate, candidateX, candidateY)) continue;
      const referenceOffset = (y * reference.width + x) * 4;
      const candidateOffset =
        (candidateY * candidate.width + candidateX) * 4;
      for (let channel = 0; channel < 3; channel += 1) {
        const difference = Math.abs(
          reference.data[referenceOffset + channel] -
            candidate.data[candidateOffset + channel],
        ) / 255;
        differences.push(difference);
        sum += difference;
        count += 1;
      }
    }
  }
  differences.sort((first, second) => first - second);
  return {
    meanAbsoluteRgb: sum / count,
    p95AbsoluteRgb: percentile(differences, 0.95),
    sampleCount: count,
  };
};

globalThis.plan016CompareMaskedEffects = async (arguments_) => {
  const images = await Promise.all([
    arguments_.referenceOffUrl,
    arguments_.referenceThinUrl,
    arguments_.referenceAttenuationUrl,
    arguments_.candidateOffUrl,
    arguments_.candidateThinUrl,
    arguments_.candidateAttenuationUrl,
  ].map(loadPixels));
  assertSameDimensions(images);
  const [referenceOff, referenceThin, referenceAttenuation,
    candidateOff, candidateThin, candidateAttenuation] = images;
  const box = roiBox(referenceOff, arguments_.roi);
  const referenceMask = differenceMask(referenceOff, referenceThin, box);
  const candidateMask = differenceMask(candidateOff, candidateThin, box);
  const referenceThinSummary = createSummary();
  const candidateThinSummary = createSummary();
  const referenceAttenuationSummary = createSummary();
  const candidateAttenuationSummary = createSummary();
  let maskPixelCount = 0;
  for (let y = box.top; y < box.bottom; y += 1) {
    for (let x = box.left; x < box.right; x += 1) {
      const candidateX = x - arguments_.candidateShiftPhysical[0];
      const candidateY = y - arguments_.candidateShiftPhysical[1];
      if (!contains(candidateThin, candidateX, candidateY)) continue;
      const referenceMaskIndex = (y - box.top) * box.width + (x - box.left);
      const candidateMaskIndex =
        (candidateY - box.top) * box.width + (candidateX - box.left);
      if (
        candidateMaskIndex < 0 ||
        candidateMaskIndex >= candidateMask.length ||
        !referenceMask[referenceMaskIndex] ||
        !candidateMask[candidateMaskIndex]
      ) continue;
      addPixel(referenceThinSummary, referenceThin, x, y);
      addPixel(candidateThinSummary, candidateThin, candidateX, candidateY);
      addPixel(referenceAttenuationSummary, referenceAttenuation, x, y);
      addPixel(
        candidateAttenuationSummary,
        candidateAttenuation,
        candidateX,
        candidateY,
      );
      maskPixelCount += 1;
    }
  }
  const referenceThinResult = finishSummary(referenceThinSummary);
  const candidateThinResult = finishSummary(candidateThinSummary);
  const referenceAttenuationResult = finishSummary(
    referenceAttenuationSummary,
  );
  const candidateAttenuationResult = finishSummary(
    candidateAttenuationSummary,
  );
  return {
    maskPixelCount,
    transmittedLuminance: {
      threejs: referenceThinResult.meanLuminance,
      ios: candidateThinResult.meanLuminance,
      relativeError:
        Math.abs(
          candidateThinResult.meanLuminance -
            referenceThinResult.meanLuminance,
        ) / Math.max(referenceThinResult.meanLuminance, 1e-9),
    },
    attenuation: {
      threejsMeanRgb: referenceAttenuationResult.meanRgb,
      iosMeanRgb: candidateAttenuationResult.meanRgb,
      threejsChromaticity: chromaticity(referenceAttenuationResult.meanRgb),
      iosChromaticity: chromaticity(candidateAttenuationResult.meanRgb),
      chromaticityDistance: vectorDistance(
        chromaticity(referenceAttenuationResult.meanRgb),
        chromaticity(candidateAttenuationResult.meanRgb),
      ),
    },
  };
};

globalThis.plan016CompareControlPair = async (arguments_) => {
  const [first, second] = await Promise.all([
    loadPixels(arguments_.firstUrl),
    loadPixels(arguments_.secondUrl),
  ]);
  assertSameDimensions([first, second]);
  const box = roiBox(first, arguments_.roi);
  const firstSummary = summarize(first, box, arguments_.dpr);
  const secondSummary = summarize(second, box, arguments_.dpr);
  let absolute = 0;
  let count = 0;
  for (let y = box.top; y < box.bottom; y += 1) {
    for (let x = box.left; x < box.right; x += 1) {
      const offset = (y * first.width + x) * 4;
      for (let channel = 0; channel < 3; channel += 1) {
        absolute += Math.abs(
          first.data[offset + channel] - second.data[offset + channel],
        ) / 255;
        count += 1;
      }
    }
  }
  return {
    meanAbsoluteRgb: absolute / count,
    first: firstSummary,
    second: secondSummary,
    meanLuminanceRelativeDelta:
      Math.abs(secondSummary.meanLuminance - firstSummary.meanLuminance) /
      Math.max(firstSummary.meanLuminance, 1e-9),
    chromaticityDistance: vectorDistance(
      chromaticity(firstSummary.meanRgb),
      chromaticity(secondSummary.meanRgb),
    ),
    edgeCentroidDistanceLogical: vectorDistance(
      firstSummary.edgeCentroidLogical,
      secondSummary.edgeCentroidLogical,
    ),
    secondToFirstEdgeEnergyRatio:
      secondSummary.edgeEnergy / Math.max(firstSummary.edgeEnergy, 1e-9),
  };
};

globalThis.plan016RenderVisualSet = async (arguments_) => {
  const [reference, candidate] = await Promise.all([
    loadPixels(arguments_.referenceUrl),
    loadPixels(arguments_.candidateUrl),
  ]);
  assertSameDimensions([reference, candidate]);
  const box = roiBox(reference, arguments_.roi);
  const referenceCrop = cropCanvas(reference, box, [0, 0]);
  const candidateCrop = cropCanvas(
    candidate,
    box,
    arguments_.candidateShiftPhysical.map((value) => -value),
  );
  const [referencePixels, candidatePixels] = [referenceCrop, candidateCrop]
    .map((canvas) => canvas.getContext('2d', { willReadFrequently: true })
      .getImageData(0, 0, canvas.width, canvas.height));
  const overlay = new OffscreenCanvas(box.width, box.height);
  const difference = new OffscreenCanvas(box.width, box.height);
  const overlayContext = overlay.getContext('2d');
  const differenceContext = difference.getContext('2d');
  const overlayPixels = overlayContext.createImageData(box.width, box.height);
  const differencePixels = differenceContext.createImageData(box.width, box.height);
  for (let offset = 0; offset < referencePixels.data.length; offset += 4) {
    const channelDifferences = [];
    for (let channel = 0; channel < 3; channel += 1) {
      const referenceValue = referencePixels.data[offset + channel];
      const candidateValue = candidatePixels.data[offset + channel];
      overlayPixels.data[offset + channel] =
        Math.round((referenceValue + candidateValue) / 2);
      channelDifferences.push(Math.abs(referenceValue - candidateValue) / 255);
    }
    overlayPixels.data[offset + 3] = 255;
    const heat = Math.min(
      1,
      channelDifferences.reduce((sum, value) => sum + value, 0) / 3 * 4,
    );
    const color = heatColor(heat);
    differencePixels.data[offset] = color[0];
    differencePixels.data[offset + 1] = color[1];
    differencePixels.data[offset + 2] = color[2];
    differencePixels.data[offset + 3] = 255;
  }
  overlayContext.putImageData(overlayPixels, 0, 0);
  differenceContext.putImageData(differencePixels, 0, 0);
  return {
    threejsCrop: await canvasDataUrl(referenceCrop),
    iosAlignedCrop: await canvasDataUrl(candidateCrop),
    overlay50: await canvasDataUrl(overlay),
    differenceHeatmap: await canvasDataUrl(difference),
  };
};

async function loadPixels(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error('Could not load image: ' + url);
  const bitmap = await createImageBitmap(await response.blob());
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(bitmap, 0, 0);
  const image = context.getImageData(0, 0, bitmap.width, bitmap.height);
  bitmap.close();
  return { width: image.width, height: image.height, data: image.data };
}

function roiBox(image, roi) {
  const left = Math.floor(roi.left * image.width);
  const top = Math.floor(roi.top * image.height);
  const right = Math.ceil((roi.left + roi.width) * image.width);
  const bottom = Math.ceil((roi.top + roi.height) * image.height);
  return { left, top, right, bottom, width: right - left, height: bottom - top };
}

function differenceMask(first, second, box) {
  const mask = new Uint8Array(box.width * box.height);
  for (let y = box.top; y < box.bottom; y += 1) {
    for (let x = box.left; x < box.right; x += 1) {
      const offset = (y * first.width + x) * 4;
      let difference = 0;
      for (let channel = 0; channel < 3; channel += 1) {
        difference += Math.abs(
          first.data[offset + channel] - second.data[offset + channel],
        ) / 255;
      }
      const maskIndex = (y - box.top) * box.width + (x - box.left);
      mask[maskIndex] = difference / 3 >= maskThreshold ? 1 : 0;
    }
  }
  return mask;
}

function maskSummary(mask, box, dpr) {
  let count = 0;
  let sumX = 0;
  let sumY = 0;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (let y = 0; y < box.height; y += 1) {
    for (let x = 0; x < box.width; x += 1) {
      if (!mask[y * box.width + x]) continue;
      const absoluteX = box.left + x;
      const absoluteY = box.top + y;
      count += 1;
      sumX += absoluteX;
      sumY += absoluteY;
      minX = Math.min(minX, absoluteX);
      minY = Math.min(minY, absoluteY);
      maxX = Math.max(maxX, absoluteX);
      maxY = Math.max(maxY, absoluteY);
    }
  }
  return {
    pixelCount: count,
    centroidLogical: [sumX / count / dpr, sumY / count / dpr],
    boundsPhysical: { minX, minY, maxX, maxY },
  };
}

function summarize(image, box, dpr) {
  const sum = [0, 0, 0];
  let luminance = 0;
  let edgeEnergy = 0;
  let edgeWeight = 0;
  let edgeX = 0;
  let edgeY = 0;
  let count = 0;
  for (let y = box.top; y < box.bottom; y += 1) {
    for (let x = box.left; x < box.right; x += 1) {
      const offset = (y * image.width + x) * 4;
      const rgb = [
        image.data[offset] / 255,
        image.data[offset + 1] / 255,
        image.data[offset + 2] / 255,
      ];
      sum[0] += rgb[0];
      sum[1] += rgb[1];
      sum[2] += rgb[2];
      const luma = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
      luminance += luma;
      count += 1;
      if (x + 1 < box.right && y + 1 < box.bottom) {
        const gradient =
          Math.abs(pixelLuma(image, x + 1, y) - luma) +
          Math.abs(pixelLuma(image, x, y + 1) - luma);
        edgeEnergy += gradient;
        edgeWeight += gradient;
        edgeX += gradient * x / dpr;
        edgeY += gradient * y / dpr;
      }
    }
  }
  return {
    meanRgb: sum.map((value) => value / count),
    meanLuminance: luminance / count,
    edgeEnergy: edgeEnergy / count,
    edgeCentroidLogical: edgeWeight > 0
      ? [edgeX / edgeWeight, edgeY / edgeWeight]
      : [0, 0],
  };
}

function createSummary() {
  return { sum: [0, 0, 0], luminance: 0, count: 0 };
}

function addPixel(summary, image, x, y) {
  const offset = (y * image.width + x) * 4;
  const rgb = [
    image.data[offset] / 255,
    image.data[offset + 1] / 255,
    image.data[offset + 2] / 255,
  ];
  for (let channel = 0; channel < 3; channel += 1) {
    summary.sum[channel] += rgb[channel];
  }
  summary.luminance += rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
  summary.count += 1;
}

function finishSummary(summary) {
  return {
    meanRgb: summary.sum.map((value) => value / summary.count),
    meanLuminance: summary.luminance / summary.count,
    pixelCount: summary.count,
  };
}

function cropCanvas(image, box, sourceOffset) {
  const source = new OffscreenCanvas(image.width, image.height);
  source.getContext('2d').putImageData(
    new ImageData(image.data, image.width, image.height),
    0,
    0,
  );
  const crop = new OffscreenCanvas(box.width, box.height);
  crop.getContext('2d').drawImage(
    source,
    box.left + sourceOffset[0],
    box.top + sourceOffset[1],
    box.width,
    box.height,
    0,
    0,
    box.width,
    box.height,
  );
  return crop;
}

async function canvasDataUrl(canvas) {
  const blob = await canvas.convertToBlob({ type: 'image/png' });
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return 'data:image/png;base64,' + btoa(binary);
}

function heatColor(value) {
  if (value < 0.5) {
    const amount = value * 2;
    return [Math.round(76 * amount), 0, Math.round(153 * amount)];
  }
  const amount = (value - 0.5) * 2;
  return [
    Math.round(76 + 179 * amount),
    Math.round(230 * amount),
    Math.round(153 * (1 - amount)),
  ];
}

function pixelLuma(image, x, y) {
  const offset = (y * image.width + x) * 4;
  return image.data[offset] / 255 * 0.2126 +
    image.data[offset + 1] / 255 * 0.7152 +
    image.data[offset + 2] / 255 * 0.0722;
}

function chromaticity(rgb) {
  const sum = rgb[0] + rgb[1] + rgb[2];
  return sum > 0 ? rgb.map((value) => value / sum) : [0, 0, 0];
}

function vectorDistance(first, second) {
  return Math.sqrt(first.reduce(
    (sum, value, index) => sum + Math.pow(value - second[index], 2),
    0,
  ));
}

function percentile(sorted, fraction) {
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * fraction))];
}

function contains(image, x, y) {
  return x >= 0 && x < image.width && y >= 0 && y < image.height;
}

function assertSameDimensions(images) {
  const [first, ...rest] = images;
  if (rest.some((image) => image.width !== first.width || image.height !== first.height)) {
    throw new Error('Plan 016 comparison image dimensions differ');
  }
}
</script>`;
}
