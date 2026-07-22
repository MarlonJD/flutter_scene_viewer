import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  outputRoot,
  repoRoot,
} from './plan018_controlled_comparison_contract.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const expectedDimensions = Object.freeze({ width: 1206, height: 2622 });
const modelId = 'glam_velvet_sofa';
const views = Object.freeze(['close', 'grazing']);
const passes = Object.freeze(['directOnly', 'iblOnly', 'combined']);
const renderers = Object.freeze([
  {
    id: 'threejs',
    label: 'Three.js r167',
    root: path.join(outputRoot, 'threejs'),
    evidencePath: path.join(outputRoot, 'threejs', 'evidence.json'),
  },
  {
    id: 'khronosSampleRenderer',
    label: 'Khronos Sample Renderer',
    root: path.join(outputRoot, 'khronos_sample_renderer'),
    evidencePath: path.join(
      outputRoot,
      'khronos_sample_renderer',
      'glam_velvet_sofa_evidence.json',
    ),
  },
  {
    id: 'viewerIos',
    label: 'viewer iOS',
    root: path.join(outputRoot, 'ios_simulator', 'candidate-run-08'),
    evidencePath: path.join(
      outputRoot,
      'ios_simulator',
      'candidate-run-08',
      'manifests',
      'glam_velvet_sofa.json',
    ),
  },
]);

export const glamCloseCropBox = Object.freeze({
  x: 60,
  y: 1120,
  width: 1086,
  height: 760,
});

const boardDimensions = Object.freeze({ width: 1440, height: 1180 });
const cropScale = 420 / glamCloseCropBox.width;
const cropTarget = Object.freeze({
  width: 420,
  height: Math.round(glamCloseCropBox.height * cropScale),
});

export function buildPlan018GlamCloseCropInventory() {
  const inventory = [];
  for (const renderer of renderers) {
    for (const view of views) {
      for (const pass of passes) {
        const fileName = `${modelId}_${view}_${pass}.png`;
        const absolutePath = path.join(renderer.root, fileName);
        inventory.push({
          modelId,
          rendererId: renderer.id,
          rendererLabel: renderer.label,
          view,
          pass,
          fileName,
          path: path.relative(repoRoot, absolutePath),
          absolutePath,
          visualOnly: true,
        });
      }
    }
  }
  return inventory;
}

export async function buildPlan018GlamCloseCropComparison({
  writeFiles = true,
  outputDirectory = path.join(outputRoot, 'visual_boards'),
} = {}) {
  const imageUrls = new Map();
  const sources = buildPlan018GlamCloseCropInventory().map((source) => {
    const bytes = fs.readFileSync(source.absolutePath);
    const dimensions = readPngDimensions(bytes);
    if (
      dimensions.width !== expectedDimensions.width ||
      dimensions.height !== expectedDimensions.height
    ) {
      throw new Error(`Glam crop source dimensions drifted: ${source.path}`);
    }
    assertCropWithin(dimensions, glamCloseCropBox, source.path);
    imageUrls.set(
      source.absolutePath,
      `data:image/png;base64,${bytes.toString('base64')}`,
    );
    return {
      ...source,
      dimensions,
      sha256: hashBytes(bytes),
      byteLength: bytes.length,
    };
  });
  const evidenceSources = renderers.map((renderer) => {
    const bytes = fs.readFileSync(renderer.evidencePath);
    return {
      rendererId: renderer.id,
      label: renderer.label,
      path: path.relative(repoRoot, renderer.evidencePath),
      sha256: hashBytes(bytes),
      byteLength: bytes.length,
    };
  });

  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-glam-crop-board-'),
  );
  let browser;
  try {
    const executablePath =
      process.env.PUPPETEER_EXECUTABLE_PATH ??
      (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
    browser = await puppeteer.launch({
      headless: true,
      executablePath,
      userDataDir: profilePath,
      args: ['--disable-background-networking', '--disable-gpu-sandbox'],
    });

    const boards = [];
    for (const view of views) {
      const page = await browser.newPage();
      await page.setViewport({
        ...boardDimensions,
        deviceScaleFactor: 1,
      });
      await page.setContent(renderBoardHtml({ view, sources, imageUrls }), {
        waitUntil: 'load',
      });
      await page.waitForFunction(
        () =>
          Array.from(document.images).every(
            (image) => image.complete && image.naturalWidth > 0,
          ),
        { timeout: 10000 },
      );
      const bytes = Buffer.from(await page.screenshot({
        type: 'png',
        clip: {
          x: 0,
          y: 0,
          ...boardDimensions,
        },
      }));
      await page.close();
      const fileName = `${modelId}_${view}_visual_only_close_crop_comparison.png`;
      const absolutePath = path.join(outputDirectory, fileName);
      boards.push({
        view,
        path: absolutePath,
        absolutePath,
        width: boardDimensions.width,
        height: boardDimensions.height,
        sha256: hashBytes(bytes),
        byteLength: bytes.length,
        visualOnly: true,
        bytes,
      });
    }

    const comparison = {
      schemaVersion: 1,
      status: 'visual-only',
      evidenceStatus: 'not evidence',
      executionEvidence: 'verified locally',
      modelId,
      rendererOrder: renderers.map((renderer) => renderer.id),
      views: [...views],
      passes: [...passes],
      sourceDimensions: expectedDimensions,
      cropBox: glamCloseCropBox,
      cropScale,
      comparisonBoundary: 'visual-only close crop',
      claimBoundary:
        'Usable visual review crop only; not accepted M3 evidence, not final four-model M3 evidence, not a pixel-parity oracle, not physical-correctness evidence, and not renderer-native sheen evidence.',
      claimsPixelParity: false,
      claimsPhysicalCorrectness: false,
      claimsRendererNativeSheen: false,
      m3Status: 'incomplete',
      m4Status: 'not started',
      canStartM4: false,
      sources,
      evidenceSources,
      boards,
    };
    validatePlan018GlamCloseCropComparison(comparison);

    if (writeFiles) {
      fs.mkdirSync(outputDirectory, { recursive: true });
      for (const board of boards) {
        fs.writeFileSync(board.absolutePath, board.bytes);
      }
      fs.writeFileSync(
        path.join(outputDirectory, `${modelId}_visual_only_close_crop_comparison.json`),
        `${JSON.stringify(stripBoardBytes(comparison), null, 2)}\n`,
      );
    }
    return comparison;
  } finally {
    if (browser) {
      await browser.close();
    }
    fs.rmSync(profilePath, { force: true, recursive: true });
  }
}

export function validatePlan018GlamCloseCropComparison(comparison) {
  if (
    comparison?.schemaVersion !== 1 ||
    comparison.status !== 'visual-only' ||
    comparison.evidenceStatus !== 'not evidence' ||
    comparison.executionEvidence !== 'verified locally' ||
    comparison.modelId !== modelId ||
    comparison.comparisonBoundary !== 'visual-only close crop' ||
    comparison.claimsPixelParity !== false ||
    comparison.claimsPhysicalCorrectness !== false ||
    comparison.claimsRendererNativeSheen !== false ||
    comparison.m3Status !== 'incomplete' ||
    comparison.m4Status !== 'not started' ||
    comparison.canStartM4 !== false
  ) {
    throw new Error('Plan 018 Glam crop comparison identity is invalid');
  }
  if (
    JSON.stringify(comparison.rendererOrder) !==
      JSON.stringify(renderers.map((renderer) => renderer.id)) ||
    JSON.stringify(comparison.views) !== JSON.stringify(views) ||
    JSON.stringify(comparison.passes) !== JSON.stringify(passes)
  ) {
    throw new Error('Plan 018 Glam crop comparison inventory drifted');
  }
  if (!comparison.claimBoundary.includes('not accepted M3 evidence')) {
    throw new Error('Plan 018 Glam crop comparison overclaims evidence');
  }
  assertCropWithin(expectedDimensions, comparison.cropBox, 'cropBox');
  if (!Array.isArray(comparison.sources) || comparison.sources.length !== 18) {
    throw new Error('Plan 018 Glam crop comparison source count drifted');
  }
  for (const source of comparison.sources) {
    if (
      source.modelId !== modelId ||
      !renderers.some((renderer) => renderer.id === source.rendererId) ||
      !views.includes(source.view) ||
      !passes.includes(source.pass) ||
      source.visualOnly !== true ||
      source.dimensions.width !== expectedDimensions.width ||
      source.dimensions.height !== expectedDimensions.height ||
      !/^[a-f0-9]{64}$/.test(source.sha256) ||
      !Number.isInteger(source.byteLength) ||
      source.byteLength <= 24
    ) {
      throw new Error(`Plan 018 Glam crop source is invalid: ${source.path}`);
    }
  }
  if (!Array.isArray(comparison.boards) || comparison.boards.length !== 2) {
    throw new Error('Plan 018 Glam crop board count drifted');
  }
  for (const board of comparison.boards) {
    if (
      !views.includes(board.view) ||
      board.visualOnly !== true ||
      board.width !== boardDimensions.width ||
      board.height !== boardDimensions.height ||
      !/^[a-f0-9]{64}$/.test(board.sha256) ||
      !Number.isInteger(board.byteLength) ||
      board.byteLength <= 24
    ) {
      throw new Error(`Plan 018 Glam crop board is invalid: ${board.path}`);
    }
    if (board.bytes) {
      const dimensions = readPngDimensions(board.bytes);
      if (
        dimensions.width !== board.width ||
        dimensions.height !== board.height ||
        hashBytes(board.bytes) !== board.sha256 ||
        board.bytes.length !== board.byteLength
      ) {
        throw new Error(`Plan 018 Glam crop board PNG drifted: ${board.path}`);
      }
    }
  }
}

function renderBoardHtml({ view, sources, imageUrls }) {
  const cells = [];
  cells.push('<div class="corner"></div>');
  for (const renderer of renderers) {
    cells.push(`<div class="header">${escapeHtml(renderer.label)}</div>`);
  }
  for (const pass of passes) {
    cells.push(`<div class="pass">${escapeHtml(pass)}</div>`);
    for (const renderer of renderers) {
      const source = sources.find(
        (candidate) =>
          candidate.rendererId === renderer.id &&
          candidate.view === view &&
          candidate.pass === pass,
      );
      if (!source) {
        throw new Error(`Missing Glam crop source for ${renderer.id}/${view}/${pass}`);
      }
      cells.push(
        `<div class="crop"><img alt="" src="${imageUrls.get(source.absolutePath)}"></div>`,
      );
    }
  }
  return `<!doctype html>
<meta charset="utf-8">
<style>
html, body {
  margin: 0;
  width: ${boardDimensions.width}px;
  height: ${boardDimensions.height}px;
  overflow: hidden;
  background: #0f0e14;
  color: #f4f2f8;
  font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
.title {
  position: absolute;
  left: 24px;
  top: 22px;
  font-size: 25px;
  font-weight: 650;
  letter-spacing: 0;
}
.subtitle {
  position: absolute;
  left: 24px;
  top: 58px;
  font-size: 15px;
  color: #bfb8c9;
}
.grid {
  position: absolute;
  left: 24px;
  top: 96px;
  display: grid;
  grid-template-columns: 120px repeat(3, ${cropTarget.width}px);
  grid-template-rows: 36px repeat(3, ${cropTarget.height}px);
  gap: 12px;
}
.header,
.pass {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 15px;
  font-weight: 650;
  color: #f4f2f8;
}
.pass {
  justify-content: flex-end;
  padding-right: 12px;
  color: #cfc8d9;
}
.crop {
  position: relative;
  width: ${cropTarget.width}px;
  height: ${cropTarget.height}px;
  overflow: hidden;
  background: #121118;
  outline: 1px solid #36313f;
}
.crop img {
  position: absolute;
  left: ${-glamCloseCropBox.x * cropScale}px;
  top: ${-glamCloseCropBox.y * cropScale}px;
  width: ${expectedDimensions.width * cropScale}px;
  height: ${expectedDimensions.height * cropScale}px;
}
.footer {
  position: absolute;
  left: 24px;
  bottom: 22px;
  width: 1392px;
  font-size: 14px;
  line-height: 1.35;
  color: #bfb8c9;
}
</style>
<div class="title">GlamVelvetSofa ${escapeHtml(view)} crop comparison</div>
<div class="subtitle">Three.js / Khronos Sample Renderer / viewer iOS, fixed Plan 018 state</div>
<div class="grid">${cells.join('')}</div>
<div class="footer">visual-only close crop; not accepted M3 evidence, not final four-model evidence, not a pixel-parity or physical-correctness claim</div>`;
}

function assertCropWithin(dimensions, cropBox, label) {
  if (
    !Number.isInteger(cropBox?.x) ||
    !Number.isInteger(cropBox?.y) ||
    !Number.isInteger(cropBox?.width) ||
    !Number.isInteger(cropBox?.height) ||
    cropBox.x < 0 ||
    cropBox.y < 0 ||
    cropBox.width <= 0 ||
    cropBox.height <= 0 ||
    cropBox.x + cropBox.width > dimensions.width ||
    cropBox.y + cropBox.height > dimensions.height
  ) {
    throw new Error(`Plan 018 Glam crop box leaves image bounds: ${label}`);
  }
}

function readPngDimensions(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!Buffer.from(bytes).subarray(0, 8).equals(signature)) {
    throw new Error('PNG signature is invalid');
  }
  return {
    width: Buffer.from(bytes).readUInt32BE(16),
    height: Buffer.from(bytes).readUInt32BE(20),
  };
}

function hashBytes(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function stripBoardBytes(comparison) {
  return {
    ...comparison,
    boards: comparison.boards.map(({ bytes, ...board }) => board),
  };
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    switch (character) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      case "'":
        return '&#39;';
      default:
        return character;
    }
  });
}

if (process.argv[1] === scriptPath) {
  const comparison = await buildPlan018GlamCloseCropComparison();
  process.stdout.write(`${JSON.stringify(stripBoardBytes(comparison), null, 2)}\n`);
}
