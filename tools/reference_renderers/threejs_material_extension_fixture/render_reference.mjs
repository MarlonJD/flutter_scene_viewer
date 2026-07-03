import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const outDir = path.join(repoRoot, 'tools/out');
const fixturePath = path.join(
  outDir,
  'fsviewer_material_extension_reference_fixture.glb',
);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);

if (!fs.existsSync(fixturePath)) {
  throw new Error(`Shared fixture GLB is missing: ${fixturePath}`);
}

fs.mkdirSync(outDir, { recursive: true });

let origin = '';
const server = http.createServer((request, response) => {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__runner.html') {
    response.writeHead(200, { 'content-type': 'text/html' });
    response.end(pageHtml(origin));
    return;
  }
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  const filePath = path.normalize(path.join(repoRoot, relativePath));
  if (!filePath.startsWith(repoRoot)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(data);
  });
});

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
origin = `http://127.0.0.1:${port}`;

const browser = await puppeteer.launch({
  headless: true,
  executablePath,
  userDataDir: path.join(outDir, 'threejs-reference-chrome-profile'),
  args: ['--disable-gpu-sandbox', '--no-sandbox'],
});

try {
  const page = await browser.newPage();
  page.on('console', (message) => {
    console.log(`[browser:${message.type()}] ${message.text()}`);
  });
  page.on('pageerror', (error) => {
    console.error(`[browser:pageerror] ${error.message}`);
  });
  await page.setViewport({ width: 512, height: 512, deviceScaleFactor: 1 });
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(
    'typeof globalThis.renderFixture === "function"',
    { timeout: 10000 },
  );
  const result = await page.evaluate(async (fixtureUrl) => {
    return globalThis.renderFixture(fixtureUrl);
  }, `${origin}/tools/out/fsviewer_material_extension_reference_fixture.glb`);

  writePng(
    path.join(outDir, 'reference_threejs_glass_matrix.png'),
    result.glassPng,
  );
  writePng(
    path.join(outDir, 'reference_threejs_clearcoat_matrix.png'),
    result.clearcoatPng,
  );
  fs.writeFileSync(
    path.join(outDir, 'material_extension_reference_metrics.json'),
    `${JSON.stringify(result.metrics, null, 2)}\n`,
  );

  assertTrend(
    result.metrics.threejs.glass.transmission1Spread >
      result.metrics.threejs.glass.transmission0Spread,
    'three.js transmission 1.0 did not reveal more background variation.',
  );
  assertTrend(
    result.metrics.threejs.glass.iorDelta > 0,
    'three.js IOR variation did not move the sampled image.',
  );
  assertTrend(
    result.metrics.threejs.clearcoat.fullHighlight >
      result.metrics.threejs.clearcoat.zeroHighlight,
    'three.js clearcoat 1.0 did not increase highlight strength.',
  );
  assertTrend(
    result.metrics.threejs.clearcoat.roughPeak <
      result.metrics.threejs.clearcoat.smoothPeak,
    'three.js rough clearcoat did not reduce peak highlight.',
  );
} finally {
  await browser.close();
  server.close();
}

function pageHtml(origin) {
  const threeUrl =
    `${origin}/tools/reference_renderers/threejs_material_extension_fixture/` +
    'node_modules/three/build/three.module.js';
  const loaderUrl =
    `${origin}/tools/reference_renderers/threejs_material_extension_fixture/` +
    'node_modules/three/examples/jsm/loaders/GLTFLoader.js';
  return `<!doctype html>
<meta charset="utf-8">
<canvas id="c" width="512" height="512"></canvas>
<script type="importmap">
{
  "imports": {
    "three": "${threeUrl}",
    "three/addons/": "${origin}/tools/reference_renderers/threejs_material_extension_fixture/node_modules/three/examples/jsm/"
  }
}
</script>
<script type="module">
import * as THREE from '${threeUrl}';
import { GLTFLoader } from '${loaderUrl}';

const canvas = document.getElementById('c');
const readback = document.createElement('canvas');
readback.width = 512;
readback.height = 512;
const readbackContext = readback.getContext('2d', { willReadFrequently: true });
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true
});
renderer.setSize(512, 512, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;

globalThis.renderFixture = async (fixtureUrl) => {
  const loader = new GLTFLoader();
  const gltf = await loader.loadAsync(fixtureUrl);
  prepareClearcoatGeometry(gltf.scene);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf0f2f5);
  scene.add(gltf.scene);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x4c5666, 2.2));
  const key = new THREE.DirectionalLight(0xffffff, 3.2);
  key.position.set(-2.5, 3.0, 4.0);
  scene.add(key);

  const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 20);

  const glassImage = renderMode(gltf.scene, scene, camera, 'glass');
  const glassPixels = readPixels();
  const clearcoatImage = renderMode(gltf.scene, scene, camera, 'clearcoat');
  const clearcoatPixels = readPixels();

  return {
    glassPng: glassImage,
    clearcoatPng: clearcoatImage,
    metrics: {
      source: 'tools/out/fsviewer_material_extension_reference_fixture.glb',
      threejs: {
        glass: {
          transmission0Spread: channelSpread(glassPixels, 0, 0, 3, 3),
          transmission1Spread: channelSpread(glassPixels, 2, 0, 3, 3),
          iorDelta: meanDelta(glassPixels, 0, 1, 2, 3)
        },
        clearcoat: {
          zeroHighlight: maxLuma(clearcoatPixels, 0, 0, 4, 1),
          fullHighlight: maxLuma(clearcoatPixels, 2, 0, 4, 1),
          smoothPeak: maxLuma(clearcoatPixels, 2, 0, 4, 1),
          roughPeak: maxLuma(clearcoatPixels, 3, 0, 4, 1)
        }
      },
      flutterScene: {
        glass: {
          transmissionDirection: 'transmission1Spread > transmission0Spread',
          iorDirection: 'iorOffsetDelta > 0'
        },
        clearcoat: {
          factorDirection: 'fullHighlight > zeroHighlight',
          roughnessDirection: 'roughPeak < smoothPeak',
          normalDirection: 'normalVariantHighlightPositionDelta > 0'
        }
      }
    }
  };
};

function renderMode(root, scene, camera, mode) {
  root.traverse((node) => {
    if (!node.isMesh) return;
    const name = node.name || '';
    node.visible = mode === 'glass'
      ? name.startsWith('stripe') || name.startsWith('glass')
      : name.startsWith('clearcoat');
  });
  const targetY = mode === 'glass' ? 0.32 : -0.62;
  camera.position.set(0, targetY, 4.0);
  camera.lookAt(0, targetY, 0);
  renderer.render(scene, camera);
  return canvas.toDataURL('image/png');
}

function prepareClearcoatGeometry(root) {
  root.traverse((node) => {
    if (!node.isMesh || !(node.name || '').startsWith('clearcoat')) return;
    node.geometry = new THREE.SphereGeometry(0.5, 64, 32);
  });
}

function readPixels() {
  readbackContext.drawImage(renderer.domElement, 0, 0);
  return readbackContext.getImageData(0, 0, 512, 512);
}

function pixelOffset(x, y) {
  return (y * 512 + x) * 4;
}

function channelSpread(image, column, row, columns, rows) {
  const bounds = cellBounds(column, row, columns, rows);
  let min = 255;
  let max = 0;
  for (let y = bounds.y0; y < bounds.y1; y += 1) {
    for (let x = bounds.x0; x < bounds.x1; x += 1) {
      const offset = pixelOffset(x, y);
      for (let channel = 0; channel < 3; channel += 1) {
        const value = image.data[offset + channel];
        min = Math.min(min, value);
        max = Math.max(max, value);
      }
    }
  }
  return max - min;
}

function maxLuma(image, column, row, columns, rows) {
  const bounds = circleBounds(column, row, columns, rows);
  let max = 0;
  for (let y = bounds.y0; y < bounds.y1; y += 1) {
    for (let x = bounds.x0; x < bounds.x1; x += 1) {
      const dx = x - bounds.cx;
      const dy = y - bounds.cy;
      if (dx * dx + dy * dy > bounds.radius * bounds.radius) continue;
      const offset = pixelOffset(x, y);
      const luma = Math.round(
        image.data[offset] * 0.299 +
        image.data[offset + 1] * 0.587 +
        image.data[offset + 2] * 0.114
      );
      max = Math.max(max, luma);
    }
  }
  return max;
}

function meanDelta(image, firstColumn, secondColumn, columns, rows) {
  const first = cellBounds(firstColumn, 1, columns, rows);
  const second = cellBounds(secondColumn, 1, columns, rows);
  let total = 0;
  let count = 0;
  for (let y = 0; y < Math.min(first.y1 - first.y0, second.y1 - second.y0); y += 1) {
    for (let x = 0; x < Math.min(first.x1 - first.x0, second.x1 - second.x0); x += 1) {
      const a = pixelOffset(first.x0 + x, first.y0 + y);
      const b = pixelOffset(second.x0 + x, second.y0 + y);
      for (let channel = 0; channel < 3; channel += 1) {
        total += Math.abs(image.data[a + channel] - image.data[b + channel]);
        count += 1;
      }
    }
  }
  return count === 0 ? 0 : total / count;
}

function cellBounds(column, row, columns, rows) {
  const x0 = Math.floor((512 * column) / columns + 24);
  const x1 = Math.floor((512 * (column + 1)) / columns - 24);
  const y0 = Math.floor((512 * row) / rows + 24);
  const y1 = Math.floor((512 * (row + 1)) / rows - 24);
  return { x0, x1, y0, y1 };
}

function circleBounds(column, row, columns, rows) {
  const cell = cellBounds(column, row, columns, rows);
  const cx = Math.floor((cell.x0 + cell.x1) / 2);
  const cy = Math.floor((cell.y0 + cell.y1) / 2);
  const radius = Math.floor(Math.min(cell.x1 - cell.x0, cell.y1 - cell.y0) * 0.42);
  return {
    cx,
    cy,
    radius,
    x0: Math.max(0, cx - radius),
    x1: Math.min(512, cx + radius),
    y0: Math.max(0, cy - radius),
    y1: Math.min(512, cy + radius)
  };
}
</script>`;
}

function writePng(filePath, dataUrl) {
  const payload = dataUrl.replace(/^data:image\/png;base64,/, '');
  fs.writeFileSync(filePath, Buffer.from(payload, 'base64'));
}

function assertTrend(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function contentType(filePath) {
  if (filePath.endsWith('.js')) return 'text/javascript';
  if (filePath.endsWith('.glb')) return 'model/gltf-binary';
  if (filePath.endsWith('.json')) return 'application/json';
  if (filePath.endsWith('.wasm')) return 'application/wasm';
  return 'application/octet-stream';
}
