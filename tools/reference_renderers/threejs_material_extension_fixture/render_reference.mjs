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
const args = process.argv.slice(2);
const realAssetFlagIndex = args.indexOf('--real-assets');
const hasRealAssets = realAssetFlagIndex !== -1;
const renderTarget = hasRealAssets
  ? {
      kind: 'realAssets',
      waterBottlePath: path.resolve(args[realAssetFlagIndex + 1] ?? ''),
      clearcoatPath: path.resolve(args[realAssetFlagIndex + 2] ?? ''),
    }
  : { kind: 'fixture' };
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);

if (hasRealAssets && args.length < realAssetFlagIndex + 3) {
  throw new Error(
    'Usage: npm run render -- --real-assets <WaterBottle.glb> '
      + '<ClearCoatCarPaint.glb>',
  );
}
if (renderTarget.kind === 'fixture' && !fs.existsSync(fixturePath)) {
  throw new Error(`Shared fixture GLB is missing: ${fixturePath}`);
}
if (renderTarget.kind === 'realAssets') {
  if (!fs.existsSync(renderTarget.waterBottlePath)) {
    throw new Error(`WaterBottle GLB is missing: ${renderTarget.waterBottlePath}`);
  }
  if (!fs.existsSync(renderTarget.clearcoatPath)) {
    throw new Error(
      `ClearCoatCarPaint GLB is missing: ${renderTarget.clearcoatPath}`,
    );
  }
}

fs.mkdirSync(outDir, { recursive: true });

let origin = '';
const realAssetRoutes =
  renderTarget.kind === 'realAssets'
    ? new Map([
        ['/__real_asset__/water_bottle.glb', renderTarget.waterBottlePath],
        [
          '/__real_asset__/clearcoat_car_paint.glb',
          renderTarget.clearcoatPath,
        ],
      ])
    : new Map();
const server = http.createServer((request, response) => {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__runner.html') {
    response.writeHead(200, { 'content-type': 'text/html' });
    response.end(pageHtml(origin));
    return;
  }
  const realAssetPath = realAssetRoutes.get(url.pathname);
  if (realAssetPath != null) {
    serveFile(response, realAssetPath);
    return;
  }
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  const filePath = path.normalize(path.join(repoRoot, relativePath));
  if (!filePath.startsWith(repoRoot)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  serveFile(response, filePath);
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

  if (renderTarget.kind === 'realAssets') {
    await page.waitForFunction(
      'typeof globalThis.renderRealAssets === "function"',
      { timeout: 10000 },
    );
    const result = await page.evaluate(
      async (waterBottleUrl, clearcoatUrl) => {
        return globalThis.renderRealAssets(waterBottleUrl, clearcoatUrl);
      },
      `${origin}/__real_asset__/water_bottle.glb`,
      `${origin}/__real_asset__/clearcoat_car_paint.glb`,
    );

    writePng(
      path.join(outDir, 'reference_threejs_water_bottle.png'),
      result.waterBottlePng,
    );
    writePng(
      path.join(outDir, 'reference_threejs_clearcoat_car_paint_real_asset.png'),
      result.clearcoatPng,
    );
    fs.writeFileSync(
      path.join(outDir, 'reference_threejs_real_asset_metrics.json'),
      `${JSON.stringify(result.metrics, null, 2)}\n`,
    );
  } else {
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
  }
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

globalThis.renderRealAssets = async (waterBottleUrl, clearcoatUrl) => {
  const loader = new GLTFLoader();
  const waterBottle = await loader.loadAsync(waterBottleUrl);
  const clearcoat = await loader.loadAsync(clearcoatUrl);

  const waterBottleResult = renderRealAsset(waterBottle.scene, {
    preset: 'glass-front',
    background: 0xf3f6f8,
    keyPosition: new THREE.Vector3(-2.4, 3.2, 4.0),
    fillPosition: new THREE.Vector3(2.5, 1.8, 2.5)
  });
  const waterBottlePixels = readPixels();
  const clearcoatResult = renderRealAsset(clearcoat.scene, {
    preset: 'clearcoat-front',
    background: 0xf2f4f7,
    keyPosition: new THREE.Vector3(-1.4, 2.0, 3.8),
    fillPosition: new THREE.Vector3(2.8, 1.2, 2.2)
  });
  const clearcoatPixels = readPixels();

  return {
    waterBottlePng: waterBottleResult.png,
    clearcoatPng: clearcoatResult.png,
    metrics: {
      source: {
        waterBottle: waterBottleUrl,
        clearcoat: clearcoatUrl
      },
      threejs: {
        waterBottle: {
          cameraPreset: 'glass-front',
          centralSpread: channelSpreadForBounds(
            waterBottlePixels,
            waterBottleResult.bounds.central
          ),
          rimContrast: edgeContrast(
            waterBottlePixels,
            waterBottleResult.bounds.outer
          )
        },
        clearcoat: {
          cameraPreset: 'clearcoat-front',
          highlightPeak: maxLumaForBounds(
            clearcoatPixels,
            clearcoatResult.bounds.highlight
          ),
          surfaceSpread: channelSpreadForBounds(
            clearcoatPixels,
            clearcoatResult.bounds.central
          )
        }
      }
    }
  };
};

function renderRealAsset(root, options) {
  const bounds = new THREE.Box3().setFromObject(root);
  const center = bounds.getCenter(new THREE.Vector3());
  const size = bounds.getSize(new THREE.Vector3());
  const radius = Math.max(size.length() * 0.5, 0.01);
  root.position.sub(center);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(options.background);
  scene.add(makeNeutralBackdrop(radius));
  scene.add(root);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x647080, 2.3));
  const key = new THREE.DirectionalLight(0xffffff, 3.4);
  key.position.copy(options.keyPosition);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xbfdcff, 1.1);
  fill.position.copy(options.fillPosition);
  scene.add(fill);

  const camera = new THREE.PerspectiveCamera(34, 1, 0.01, radius * 20);
  const target = new THREE.Vector3(
    0,
    options.preset === 'glass-front' ? radius * 0.05 : 0,
    0
  );
  const cameraY = options.preset === 'glass-front'
    ? radius * 0.18
    : radius * 0.04;
  camera.position.set(0, cameraY, radius * 2.7);
  camera.lookAt(target);
  renderer.render(scene, camera);
  return {
    png: canvas.toDataURL('image/png'),
    bounds: realAssetMetricBounds(options.preset)
  };
}

function makeNeutralBackdrop(radius) {
  const group = new THREE.Group();
  const materialA = new THREE.MeshBasicMaterial({
    color: 0xd7dde3,
    side: THREE.DoubleSide
  });
  const materialB = new THREE.MeshBasicMaterial({
    color: 0xbfc8d0,
    side: THREE.DoubleSide
  });
  const stripeWidth = radius * 0.38;
  for (let index = 0; index < 6; index += 1) {
    const stripe = new THREE.Mesh(
      new THREE.PlaneGeometry(stripeWidth, radius * 3.8),
      index % 2 === 0 ? materialA : materialB
    );
    stripe.position.set((index - 2.5) * stripeWidth, 0, -radius * 1.35);
    group.add(stripe);
  }
  group.position.set(0, 0, -radius * 2.8);
  return group;
}

function realAssetMetricBounds(preset) {
  if (preset === 'glass-front') {
    return {
      central: { x0: 196, y0: 190, x1: 316, y1: 370 },
      outer: { x0: 154, y0: 120, x1: 358, y1: 430 }
    };
  }
  return {
    central: { x0: 136, y0: 136, x1: 376, y1: 376 },
    highlight: { x0: 156, y0: 260, x1: 356, y1: 420 }
  };
}

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
  return channelSpreadForBounds(image, bounds);
}

function channelSpreadForBounds(image, bounds) {
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
  return maxLumaForBounds(image, bounds);
}

function maxLumaForBounds(image, bounds) {
  let max = 0;
  for (let y = bounds.y0; y < bounds.y1; y += 1) {
    for (let x = bounds.x0; x < bounds.x1; x += 1) {
      if (bounds.radius != null) {
        const dx = x - bounds.cx;
        const dy = y - bounds.cy;
        if (dx * dx + dy * dy > bounds.radius * bounds.radius) continue;
      }
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

function edgeContrast(image, bounds) {
  const inset = 16;
  const outer = averageLuma(image, bounds);
  const inner = averageLuma(image, {
    x0: bounds.x0 + inset,
    y0: bounds.y0 + inset,
    x1: bounds.x1 - inset,
    y1: bounds.y1 - inset
  });
  return Math.abs(outer - inner);
}

function averageLuma(image, bounds) {
  let total = 0;
  let count = 0;
  for (let y = bounds.y0; y < bounds.y1; y += 1) {
    for (let x = bounds.x0; x < bounds.x1; x += 1) {
      const offset = pixelOffset(x, y);
      total +=
        image.data[offset] * 0.299 +
        image.data[offset + 1] * 0.587 +
        image.data[offset + 2] * 0.114;
      count += 1;
    }
  }
  return count === 0 ? 0 : total / count;
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

function serveFile(response, filePath) {
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    response.writeHead(200, { 'content-type': contentType(filePath) });
    response.end(data);
  });
}
