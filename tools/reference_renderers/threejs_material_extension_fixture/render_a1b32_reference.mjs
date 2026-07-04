import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const outDir = path.join(repoRoot, 'tools/out');
const assetPath = path.resolve(
  process.argv[2] ?? '/Users/marlonjd/Downloads/A1B32.glb',
);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);

if (!fs.existsSync(assetPath)) {
  throw new Error(`A1B32 GLB is missing: ${assetPath}`);
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
  if (url.pathname === '/__asset__/A1B32.glb') {
    serveFile(response, assetPath);
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
  userDataDir: path.join(outDir, 'threejs-a1b32-chrome-profile'),
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
  await page.setViewport({ width: 640, height: 960, deviceScaleFactor: 1 });
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(
    'typeof globalThis.renderA1B32 === "function"',
    { timeout: 10000 },
  );
  const result = await page.evaluate((assetUrl) => {
    return globalThis.renderA1B32(assetUrl);
  }, `${origin}/__asset__/A1B32.glb`);

  writePng(path.join(outDir, 'reference_threejs_a1b32_front_all.png'), result.all);
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_no_back.png'),
    result.noBack,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_front_only.png'),
    result.frontOnly,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_back_only.png'),
    result.backOnly,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_no_textile_overlays.png'),
    result.noTextileOverlays,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_textile_overlays_only.png'),
    result.textileOverlaysOnly,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_repaired_back.png'),
    result.repairedBack,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_repaired_back_neutral_normal.png'),
    result.repairedBackNeutralNormal,
  );
  writePng(
    path.join(outDir, 'reference_threejs_a1b32_front_repaired_body_culled.png'),
    result.repairedBodyCulled,
  );
  fs.writeFileSync(
    path.join(outDir, 'reference_threejs_a1b32_metrics.json'),
    `${JSON.stringify(result.metrics, null, 2)}\n`,
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
  const dracoLoaderUrl =
    `${origin}/tools/reference_renderers/threejs_material_extension_fixture/` +
    'node_modules/three/examples/jsm/loaders/DRACOLoader.js';
  const dracoDecoderPath =
    `${origin}/tools/reference_renderers/threejs_material_extension_fixture/` +
    'node_modules/three/examples/jsm/libs/draco/gltf/';

  return `<!doctype html>
<meta charset="utf-8">
<canvas id="c" width="640" height="960"></canvas>
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
import { DRACOLoader } from '${dracoLoaderUrl}';

const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true
});
renderer.setSize(640, 960, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;

globalThis.renderA1B32 = async (assetUrl) => {
  const loader = new GLTFLoader();
  const dracoLoader = new DRACOLoader();
  dracoLoader.setDecoderPath('${dracoDecoderPath}');
  loader.setDRACOLoader(dracoLoader);
  const gltf = await loader.loadAsync(assetUrl);
  const root = gltf.scene;
  root.updateWorldMatrix(true, true);
  const originalBounds = new THREE.Box3().setFromObject(root);
  const center = originalBounds.getCenter(new THREE.Vector3());
  const size = originalBounds.getSize(new THREE.Vector3());
  const radius = Math.max(size.length() * 0.5, 0.01);
  root.position.sub(center);
  root.updateWorldMatrix(true, true);

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf4f1eb);
  scene.add(root);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x6d7480, 2.1));
  const key = new THREE.DirectionalLight(0xffffff, 2.8);
  key.position.set(-2.6, 3.2, 4.0);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xdbe9ff, 0.9);
  fill.position.set(2.4, 1.3, 2.8);
  scene.add(fill);

  const camera = new THREE.PerspectiveCamera(26, 640 / 960, 0.01, radius * 30);
  camera.position.set(0, radius * 0.05, radius * 2.8);
  camera.lookAt(0, radius * 0.02, 0);

  const meshSummaries = [];
  root.traverse((node) => {
    if (!node.isMesh) return;
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) {
      meshSummaries.push({
        mesh: node.name,
        material: material?.name ?? '',
        visible: node.visible,
        transparent: material?.transparent ?? false,
        opacity: material?.opacity ?? null,
        side: material?.side ?? null,
        alphaTest: material?.alphaTest ?? null,
        hasMap: material?.map != null,
        hasNormalMap: material?.normalMap != null,
        hasRoughnessMap: material?.roughnessMap != null,
        hasMetalnessMap: material?.metalnessMap != null,
      });
    }
  });

  const all = renderWithMaterialFilter(scene, root, camera, () => true);
  const noBack = renderWithMaterialFilter(scene, root, camera, (name) => {
    return !name.toLowerCase().includes('back');
  });
  const frontOnly = renderWithMaterialFilter(scene, root, camera, (name) => {
    return name.toLowerCase().includes('front');
  });
  const backOnly = renderWithMaterialFilter(scene, root, camera, (name) => {
    return name.toLowerCase().includes('back');
  });
  const noTextileOverlays = renderWithMaterialFilter(
    scene,
    root,
    camera,
    (name) => {
      return !isTextileOverlay(name);
    },
  );
  const textileOverlaysOnly = renderWithMaterialFilter(
    scene,
    root,
    camera,
    (name) => {
      return isTextileOverlay(name);
    },
  );
  const repairedBack = renderWithRepairs(scene, root, camera, {
    repairBackBaseColor: true,
    repairGarmentNormal: false
  });
  const repairedBackNeutralNormal = renderWithRepairs(scene, root, camera, {
    repairBackBaseColor: true,
    repairGarmentNormal: true,
    hideInternalBody: false
  });
  const repairedBodyCulled = renderWithRepairs(scene, root, camera, {
    repairBackBaseColor: true,
    repairGarmentNormal: false,
    hideInternalBody: true
  });
  dracoLoader.dispose();
  return {
    all,
    noBack,
    frontOnly,
    backOnly,
    noTextileOverlays,
    textileOverlaysOnly,
    repairedBack,
    repairedBackNeutralNormal,
    repairedBodyCulled,
    metrics: {
      source: assetUrl,
      originalBounds: {
        min: originalBounds.min.toArray(),
        max: originalBounds.max.toArray(),
        size: size.toArray(),
        radius
      },
      meshes: meshSummaries
    }
  };
};

function renderWithMaterialFilter(scene, root, camera, shouldShowMaterial) {
  root.traverse((node) => {
    if (!node.isMesh) return;
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    node.visible = materials.some((material) => {
      return shouldShowMaterial(material?.name ?? node.name ?? '');
    });
  });
  renderer.render(scene, camera);
  return canvas.toDataURL('image/png');
}

function renderWithRepairs(scene, root, camera, options) {
  const originalStates = [];
  const whiteMap = makeSolidTexture(255, 255, 255, 255);
  const neutralNormalMap = makeSolidTexture(128, 128, 255, 255);
  root.traverse((node) => {
    if (!node.isMesh) return;
    node.visible = true;
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) {
      if (material == null) continue;
      originalStates.push({
        node,
        material,
        map: material.map,
        normalMap: material.normalMap,
        visible: node.visible,
        needsUpdate: material.needsUpdate
      });
      const materialName = material.name ?? '';
      if (options.repairBackBaseColor && materialName.toLowerCase().includes('back')) {
        material.map = whiteMap;
        material.color = new THREE.Color(0xffffff);
        material.needsUpdate = true;
      }
      if (options.repairGarmentNormal && isGarmentPanel(materialName)) {
        material.normalMap = neutralNormalMap;
        material.needsUpdate = true;
      }
      if (options.hideInternalBody && isInternalBody(materialName)) {
        node.visible = false;
      }
    }
  });
  renderer.render(scene, camera);
  const result = canvas.toDataURL('image/png');
  for (const state of originalStates) {
    state.node.visible = state.visible;
    state.material.map = state.map;
    state.material.normalMap = state.normalMap;
    state.material.needsUpdate = state.needsUpdate;
  }
  whiteMap.dispose();
  neutralNormalMap.dispose();
  return result;
}

function makeSolidTexture(r, g, b, a) {
  const texture = new THREE.DataTexture(
    new Uint8Array([r, g, b, a]),
    1,
    1,
    THREE.RGBAFormat,
  );
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.needsUpdate = true;
  return texture;
}

function isTextileOverlay(name) {
  return name === 'Material1745.042' || name === 'Material2070.042';
}

function isGarmentPanel(name) {
  const normalized = name.toLowerCase();
  return normalized.startsWith('top_') || normalized.startsWith('skirt_');
}

function isInternalBody(name) {
  return name === 'MAT_Body.040' || name === 'MAT_Legs.040';
}
</script>`;
}

function writePng(filePath, dataUrl) {
  const payload = dataUrl.replace(/^data:image\/png;base64,/, '');
  fs.writeFileSync(filePath, Buffer.from(payload, 'base64'));
}

function contentType(filePath) {
  if (filePath.endsWith('.js')) return 'text/javascript';
  if (filePath.endsWith('.glb')) return 'model/gltf-binary';
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
