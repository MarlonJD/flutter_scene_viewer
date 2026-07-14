import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  buildPlan014A1b32CaptureContract,
  buildPlan014A1b32CaptureEvidence,
  buildPlan014RecordedCaptureRecord,
  verifyPlan014A1b32Bytes,
} from './plan014_capture_contract.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const contract = buildPlan014A1b32CaptureContract(repoRoot);
const assetPath = path.resolve(
  process.argv[2] ??
    path.join(repoRoot, 'tools/out/material_extension_acceptance/A1B32.glb'),
);
const outputRoot = path.join(repoRoot, contract.outputRoot);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
const viewport = Object.freeze({ width: 640, height: 960, deviceScaleFactor: 1 });

const assetBytes = fs.readFileSync(assetPath);
verifyPlan014A1b32Bytes(assetBytes, contract);
fs.mkdirSync(outputRoot, { recursive: true });

let origin = '';
const server = http.createServer((request, response) => {
  const url = new URL(request.url ?? '/', 'http://127.0.0.1');
  if (url.pathname === '/__runner.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(pageHtml(origin));
    return;
  }
  if (url.pathname === '/favicon.ico') {
    response.writeHead(204);
    response.end();
    return;
  }
  if (url.pathname === '/__asset__/A1B32.glb') {
    serveFile(response, assetPath);
    return;
  }
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  const filePath = path.normalize(path.join(repoRoot, relativePath));
  if (!filePath.startsWith(`${repoRoot}${path.sep}`)) {
    response.writeHead(403);
    response.end('Forbidden');
    return;
  }
  serveFile(response, filePath);
});

await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
origin = `http://127.0.0.1:${server.address().port}`;

let browser;
try {
  browser = await puppeteer.launch({
    headless: true,
    executablePath,
    userDataDir: path.join(outputRoot, '.chrome-profile'),
    args: ['--disable-background-networking', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  page.on('console', (message) => {
    console.log(`[browser:${message.type()}] ${message.text()}`);
  });
  page.on('pageerror', (error) => {
    console.error(`[browser:pageerror] ${error.message}`);
  });
  await page.setViewport(viewport);
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(
    'typeof globalThis.renderPlan014A1B32 === "function"',
    { timeout: 10000 },
  );
  const result = await page.evaluate(
    ({ assetUrl, referenceState }) =>
      globalThis.renderPlan014A1B32(assetUrl, referenceState),
    {
      assetUrl: `${origin}/__asset__/A1B32.glb`,
      referenceState: contract.referenceState,
    },
  );

  const captures = {};
  for (const view of contract.referenceState.views) {
    const bytes = decodePng(result.views[view]);
    const artifactPath = path.join(repoRoot, contract.artifacts[view]);
    fs.writeFileSync(artifactPath, bytes);
    captures[view] = bytes;
  }
  const browserVersion = await browser.version();
  const platform = await page.evaluate(() => navigator.platform);
  const evidence = buildPlan014A1b32CaptureEvidence(contract, {
    captures,
    browser: {
      product: browserVersion.split('/')[0],
      version: browserVersion.split('/').slice(1).join('/'),
      platform,
    },
    host: {
      platform: process.platform,
      release: os.release(),
      architecture: process.arch,
      device: os.cpus()[0]?.model ?? 'unknown local reference host',
    },
    viewport,
  });
  evidence.rendererMapping = result.rendererMapping;
  evidence.sceneSummary = result.sceneSummary;
  const trackedRecord = JSON.parse(
    fs.readFileSync(
      path.join(repoRoot, 'tools/material_extension_acceptance/manifest.json'),
      'utf8',
    ),
  ).referenceCaptureEvidence;
  const actualRecord = buildPlan014RecordedCaptureRecord(contract, evidence);
  if (!isDeepStrictEqual(actualRecord, trackedRecord)) {
    throw new Error(
      'Current capture does not match manifest.referenceCaptureEvidence; ' +
        'review the local evidence before updating tracked metadata.',
    );
  }
  fs.writeFileSync(
    path.join(repoRoot, contract.artifacts.report),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
  console.log(
    `Plan 014 A1B32 Three.js reference: ${contract.referenceState.views.length} views OK`,
  );
} finally {
  if (browser != null) {
    await browser.close();
  }
  await new Promise((resolve) => server.close(resolve));
}

function pageHtml(baseUrl) {
  const fixtureRoot =
    `${baseUrl}/tools/reference_renderers/threejs_material_extension_fixture/`;
  const threeUrl = `${fixtureRoot}node_modules/three/build/three.module.js`;
  const loaderUrl = `${fixtureRoot}node_modules/three/examples/jsm/loaders/GLTFLoader.js`;
  const dracoLoaderUrl = `${fixtureRoot}node_modules/three/examples/jsm/loaders/DRACOLoader.js`;
  const roomEnvironmentUrl =
    `${fixtureRoot}node_modules/three/examples/jsm/environments/RoomEnvironment.js`;
  const dracoDecoderPath =
    `${fixtureRoot}node_modules/three/examples/jsm/libs/draco/gltf/`;

  return `<!doctype html>
<meta charset="utf-8">
<canvas id="capture" width="640" height="960"></canvas>
<script type="importmap">
{
  "imports": {
    "three": "${threeUrl}",
    "three/addons/": "${fixtureRoot}node_modules/three/examples/jsm/"
  }
}
</script>
<script type="module">
import * as THREE from '${threeUrl}';
import { GLTFLoader } from '${loaderUrl}';
import { DRACOLoader } from '${dracoLoaderUrl}';
import { RoomEnvironment } from '${roomEnvironmentUrl}';

const canvas = document.getElementById('capture');
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true,
});
renderer.setPixelRatio(1);
renderer.setSize(640, 960, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;

globalThis.renderPlan014A1B32 = async (assetUrl, referenceState) => {
  const loader = new GLTFLoader();
  const dracoLoader = new DRACOLoader();
  dracoLoader.setDecoderPath('${dracoDecoderPath}');
  loader.setDRACOLoader(dracoLoader);
  const gltf = await loader.loadAsync(assetUrl);
  const root = gltf.scene;
  root.updateWorldMatrix(true, true);

  const bounds = new THREE.Box3().setFromObject(root);
  const sphere = bounds.getBoundingSphere(new THREE.Sphere());
  if (!Number.isFinite(sphere.radius) || sphere.radius <= 0) {
    throw new Error('A1B32 bounds cannot be fitted');
  }

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xf4f1eb);
  scene.add(root);

  renderer.toneMappingExposure = referenceState.lighting.exposure;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const roomEnvironment = new RoomEnvironment();
  const environmentTarget = pmrem.fromScene(roomEnvironment, 0.04);
  scene.environment = environmentTarget.texture;
  scene.environmentIntensity =
    referenceState.environment.intensity *
    referenceState.lighting.environmentIntensity;
  if (scene.environmentRotation != null) {
    scene.environmentRotation.y = referenceState.environment.rotationRadians;
  }

  const keyColor = new THREE.Color().fromArray(
    referenceState.lighting.keyLightColor,
  );
  const key = new THREE.DirectionalLight(
    keyColor,
    referenceState.lighting.keyLightIntensity,
  );
  const keyDirection = new THREE.Vector3().fromArray(
    referenceState.lighting.keyLightDirection,
  ).normalize();
  key.position.copy(sphere.center).addScaledVector(
    keyDirection,
    -sphere.radius * 4,
  );
  key.target.position.copy(sphere.center);
  key.castShadow = referenceState.lighting.keyLightCastsShadow;
  scene.add(key, key.target);

  const verticalFovDegrees = 26;
  const verticalFovRadians = THREE.MathUtils.degToRad(verticalFovDegrees);
  const horizontalFovRadians = 2 * Math.atan(
    Math.tan(verticalFovRadians / 2) * (640 / 960),
  );
  const limitingHalfFov = Math.min(
    verticalFovRadians / 2,
    horizontalFovRadians / 2,
  );
  const distance = (sphere.radius / Math.sin(limitingHalfFov)) * 1.08;
  const camera = new THREE.PerspectiveCamera(
    verticalFovDegrees,
    640 / 960,
    Math.max(distance / 1000, 0.001),
    distance * 10,
  );
  const viewDirections = {
    front: new THREE.Vector3(0, 0, 1),
    left: new THREE.Vector3(-1, 0, 0),
    right: new THREE.Vector3(1, 0, 0),
    back: new THREE.Vector3(0, 0, -1),
  };
  const views = {};
  for (const view of referenceState.views) {
    const direction = viewDirections[view];
    if (direction == null) throw new Error('Unsupported camera view: ' + view);
    camera.position.copy(sphere.center).addScaledVector(direction, distance);
    camera.up.set(0, 1, 0);
    camera.lookAt(sphere.center);
    camera.updateMatrixWorld(true);
    renderer.render(scene, camera);
    views[view] = canvas.toDataURL('image/png');
  }

  let meshCount = 0;
  const materialNames = new Set();
  root.traverse((node) => {
    if (!node.isMesh) return;
    meshCount += 1;
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) {
      materialNames.add(material?.name ?? '');
    }
  });
  dracoLoader.dispose();
  roomEnvironment.dispose();
  environmentTarget.dispose();
  pmrem.dispose();
  renderer.dispose();

  return {
    views,
    rendererMapping: {
      toneMapping: 'ACESFilmicToneMapping',
      exposure: referenceState.lighting.exposure,
      environment: 'three.js RoomEnvironment via PMREM',
      environmentIntensity: scene.environmentIntensity,
      keyLight: 'DirectionalLight with source opposite authored direction',
      ambientOcclusion: 'disabled',
      skybox: 'not shown',
      comparison: 'directional-not-pixel-parity',
    },
    sceneSummary: {
      meshCount,
      materialCount: materialNames.size,
      bounds: {
        min: bounds.min.toArray(),
        max: bounds.max.toArray(),
        center: sphere.center.toArray(),
        radius: sphere.radius,
      },
    },
  };
};
</script>`;
}

function decodePng(dataUrl) {
  const prefix = 'data:image/png;base64,';
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith(prefix)) {
    throw new Error('capture did not return a PNG data URL');
  }
  return Buffer.from(dataUrl.slice(prefix.length), 'base64');
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
