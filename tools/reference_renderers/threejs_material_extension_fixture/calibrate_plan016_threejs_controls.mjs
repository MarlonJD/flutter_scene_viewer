import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import puppeteer from 'puppeteer';

import {
  loadPlan016ControlledComparisonState,
  outputRoot,
  plan016StateHash,
  repoRoot,
} from './plan016_controlled_comparison_contract.mjs';

const state = loadPlan016ControlledComparisonState();
const threeRoot = path.join(outputRoot, 'threejs');
const evidencePath = path.join(threeRoot, 'evidence.json');
const evidence = JSON.parse(fs.readFileSync(evidencePath, 'utf8'));
if (evidence.stateSha256 !== plan016StateHash()) {
  throw new Error('Plan 016 Three.js evidence is stale for control calibration');
}

const profilePath = fs.mkdtempSync(
  path.join(os.tmpdir(), 'plan016-control-calibration-'),
);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
let origin = '';
const server = http.createServer((request, response) => {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__runner.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(pageHtml());
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
      'content-type': filePath.endsWith('.png') ? 'image/png' : 'application/octet-stream',
    });
    response.end(bytes);
  });
});

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
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  const comparisons = {};
  for (const [trend, [firstModel, secondModel]] of Object.entries(
    state.comparisonMetrics.calibrationControlPairs,
  )) {
    const firstPath = evidence.artifacts[firstModel].combined.path;
    const secondPath = evidence.artifacts[secondModel].combined.path;
    comparisons[trend] = await page.evaluate(
      ({ firstUrl, secondUrl, roi, dpr }) =>
        globalThis.comparePlan016ControlPair(firstUrl, secondUrl, roi, dpr),
      {
        firstUrl: `${origin}/${firstPath}`,
        secondUrl: `${origin}/${secondPath}`,
        roi: state.comparisonMetrics.syntheticGlassRoiNormalized,
        dpr: state.viewport.devicePixelRatio,
      },
    );
    comparisons[trend].models = [firstModel, secondModel];
  }

  const checks = calibrateChecks(
    comparisons,
    state.comparisonMetrics.thresholds,
  );
  const result = {
    schemaVersion: 1,
    status: checks.every((check) => check.passed) ? 'pass' : 'fail',
    scope: 'Three.js-only threshold sensitivity calibration before Flutter capture',
    stateSha256: plan016StateHash(),
    renderer: evidence.renderer,
    roi: state.comparisonMetrics.syntheticGlassRoiNormalized,
    thresholds: state.comparisonMetrics.thresholds,
    comparisons,
    checks,
    calibrationBoundary:
      'Only stock Three.js control-pair sensitivity was visible while these ' +
      'thresholds were calibrated; no Flutter comparison image existed.',
  };
  const destination = path.join(threeRoot, 'control_calibration.json');
  fs.writeFileSync(destination, `${JSON.stringify(result, null, 2)}\n`);
  console.log(`Plan 016 Three.js control calibration: ${result.status}`);
  for (const check of checks) {
    console.log(`${check.passed ? 'PASS' : 'FAIL'} ${check.name}: ${check.actual}`);
  }
  if (result.status !== 'pass') process.exitCode = 1;
} finally {
  if (browser != null) await browser.close();
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(profilePath, { recursive: true, force: true });
}

function calibrateChecks(comparisons, thresholds) {
  return [
    ...Object.entries(comparisons).map(([trend, metrics]) => ({
      name: `${trend}.meanAbsoluteRgbSignal`,
      actual: metrics.meanAbsoluteRgb,
      expected: `>= ${thresholds.controlPairMeanAbsoluteRgbSignalMin}`,
      passed:
        metrics.meanAbsoluteRgb >=
        thresholds.controlPairMeanAbsoluteRgbSignalMin,
    })),
    {
      name: 'ior.refractedDisplacementSignal',
      actual: comparisons.ior.edgeCentroidDistanceLogical,
      expected: `>= ${thresholds.controlRefractedDisplacementLogicalPixelsMin}`,
      passed:
        comparisons.ior.edgeCentroidDistanceLogical >=
        thresholds.controlRefractedDisplacementLogicalPixelsMin,
    },
    {
      name: 'attenuation.chromaticitySignal',
      actual: comparisons.attenuation.chromaticityDistance,
      expected: `>= ${thresholds.controlAttenuationChromaticityShiftMin}`,
      passed:
        comparisons.attenuation.chromaticityDistance >=
        thresholds.controlAttenuationChromaticityShiftMin,
    },
    {
      name: 'roughness.blurSignal',
      actual: comparisons.roughness.secondToFirstEdgeEnergyRatio,
      expected: `<= ${thresholds.controlRoughnessEdgeEnergyRatioMax}`,
      passed:
        comparisons.roughness.secondToFirstEdgeEnergyRatio <=
        thresholds.controlRoughnessEdgeEnergyRatioMax,
    },
  ];
}

function pageHtml() {
  return `<!doctype html>
<meta charset="utf-8">
<script>
globalThis.comparePlan016ControlPair = async (firstUrl, secondUrl, roi, dpr) => {
  const [first, second] = await Promise.all([loadPixels(firstUrl), loadPixels(secondUrl)]);
  if (first.width !== second.width || first.height !== second.height) {
    throw new Error('Plan 016 control pair dimensions differ');
  }
  const left = Math.floor(roi.left * first.width);
  const top = Math.floor(roi.top * first.height);
  const right = Math.ceil((roi.left + roi.width) * first.width);
  const bottom = Math.ceil((roi.top + roi.height) * first.height);
  const firstSummary = summarize(first, left, top, right, bottom, dpr);
  const secondSummary = summarize(second, left, top, right, bottom, dpr);
  let absolute = 0;
  let count = 0;
  for (let y = top; y < bottom; y += 1) {
    for (let x = left; x < right; x += 1) {
      const offset = (y * first.width + x) * 4;
      for (let channel = 0; channel < 3; channel += 1) {
        absolute += Math.abs(first.data[offset + channel] - second.data[offset + channel]) / 255;
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

async function loadPixels(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error('Could not load control image: ' + url);
  const bitmap = await createImageBitmap(await response.blob());
  const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(bitmap, 0, 0);
  const image = context.getImageData(0, 0, bitmap.width, bitmap.height);
  bitmap.close();
  return { width: image.width, height: image.height, data: image.data };
}

function summarize(image, left, top, right, bottom, dpr) {
  const sum = [0, 0, 0];
  let luminance = 0;
  let edgeEnergy = 0;
  let edgeWeight = 0;
  let edgeX = 0;
  let edgeY = 0;
  let count = 0;
  for (let y = top; y < bottom; y += 1) {
    for (let x = left; x < right; x += 1) {
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
      if (x + 1 < right && y + 1 < bottom) {
        const rightLuma = pixelLuma(image, x + 1, y);
        const downLuma = pixelLuma(image, x, y + 1);
        const gradient = Math.abs(rightLuma - luma) + Math.abs(downLuma - luma);
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
</script>`;
}
