import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  loadControlledComparisonState,
  outputRoot,
  repoRoot,
  writeControlledStudioHdr,
} from './plan015_controlled_comparison_contract.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const state = loadControlledComparisonState();
const stagedRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/plan015_renderer_native_clearcoat',
);
const models = Object.freeze({
  clearcoat_test: path.join(
    stagedRoot,
    'clearcoat_test/ClearCoatTest.glb',
  ),
  clearcoat_car_paint: path.join(
    stagedRoot,
    'clearcoat_car_paint/ClearCoatCarPaint.glb',
  ),
  toycar: path.join(stagedRoot, 'toycar/ToyCar.glb'),
});
for (const [id, modelPath] of Object.entries(models)) {
  if (!fs.existsSync(modelPath)) {
    throw new Error(`Plan 015 staged model is missing (${id}): ${modelPath}`);
  }
}

const threeOutputRoot = path.join(outputRoot, 'threejs');
fs.mkdirSync(threeOutputRoot, { recursive: true });
const generatedHdr = writeControlledStudioHdr(state);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
const profilePath = fs.mkdtempSync(
  path.join(os.tmpdir(), 'plan015-threejs-controlled-'),
);

let origin = '';
const routes = new Map([
  ['/__environment__/controlled.hdr', generatedHdr.destination],
  ...Object.entries(models).map(([id, modelPath]) => [
    `/__model__/${id}.glb`,
    modelPath,
  ]),
]);
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
  const routedPath = routes.get(url.pathname);
  if (routedPath != null) {
    serveFile(response, routedPath);
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
    userDataDir: profilePath,
    args: ['--disable-background-networking', '--disable-gpu-sandbox'],
  });
  const page = await browser.newPage();
  page.on('console', (message) => {
    console.log(`[browser:${message.type()}] ${message.text()}`);
  });
  page.on('pageerror', (error) => {
    console.error(`[browser:pageerror] ${error.message}`);
  });
  await page.setViewport({
    width: state.viewport.logicalWidth,
    height: state.viewport.logicalHeight,
    deviceScaleFactor: state.viewport.devicePixelRatio,
  });
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(
    'typeof globalThis.renderPlan015ControlledComparison === "function"',
    { timeout: 10000 },
  );
  const modelUrls = Object.fromEntries(
    Object.keys(models).map((id) => [id, `${origin}/__model__/${id}.glb`]),
  );
  const result = await page.evaluate(
    ({ modelUrls: urls, environmentUrl, referenceState }) =>
      globalThis.renderPlan015ControlledComparison(
        urls,
        environmentUrl,
        referenceState,
      ),
    {
      modelUrls,
      environmentUrl: `${origin}/__environment__/controlled.hdr`,
      referenceState: state,
    },
  );

  const artifacts = {};
  for (const [modelId, passes] of Object.entries(result.captures)) {
    artifacts[modelId] = {};
    for (const [pass, dataUrl] of Object.entries(passes)) {
      const bytes = decodePng(dataUrl);
      const artifactPath = path.join(
        threeOutputRoot,
        `${modelId}_${pass}.png`,
      );
      fs.writeFileSync(artifactPath, bytes);
      artifacts[modelId][pass] = {
        path: path.relative(repoRoot, artifactPath),
        sha256: hash(bytes),
        byteLength: bytes.length,
      };
    }
  }
  const browserVersion = await browser.version();
  const evidence = {
    schemaVersion: 1,
    status: 'verified locally',
    scope: 'Three.js controlled reference only',
    sourceState: path.relative(
      repoRoot,
      path.join(
        repoRoot,
        'tools/material_extension_acceptance/fixtures/' +
          'plan015_controlled_comparison_state.json',
      ),
    ),
    state,
    environment: {
      path: path.relative(repoRoot, generatedHdr.destination),
      sha256: generatedHdr.sha256,
      byteLength: generatedHdr.bytes.length,
    },
    models: Object.fromEntries(
      Object.entries(models).map(([id, modelPath]) => [
        id,
        {
          path: path.relative(repoRoot, modelPath),
          sha256: hash(fs.readFileSync(modelPath)),
        },
      ]),
    ),
    renderer: {
      name: 'Three.js',
      version: result.rendererMapping.version,
      browser: browserVersion,
      host: {
        platform: process.platform,
        release: os.release(),
        architecture: process.arch,
      },
      mapping: result.rendererMapping,
    },
    sceneSummaries: result.sceneSummaries,
    artifacts,
    comparisonBoundary:
      'Matched source state; independent renderer BRDF and HDR prefilter ' +
      'implementations prevent a pixel-parity claim.',
  };
  fs.writeFileSync(
    path.join(threeOutputRoot, 'evidence.json'),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
  console.log(
    `Plan 015 controlled Three.js reference: ` +
      `${Object.keys(models).length} models x ${state.renderPasses.length} passes OK`,
  );
} finally {
  if (browser != null) await browser.close();
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(profilePath, { recursive: true, force: true });
}

function pageHtml(baseUrl) {
  const fixtureRoot =
    `${baseUrl}/tools/reference_renderers/threejs_material_extension_fixture/`;
  const threeUrl = `${fixtureRoot}node_modules/three/build/three.module.js`;
  const loaderUrl = `${fixtureRoot}node_modules/three/examples/jsm/loaders/GLTFLoader.js`;
  const rgbeLoaderUrl = `${fixtureRoot}node_modules/three/examples/jsm/loaders/RGBELoader.js`;
  return `<!doctype html>
<meta charset="utf-8">
<style>
html, body { margin: 0; overflow: hidden; background: #121118; }
canvas { display: block; width: 402px; height: 874px; }
</style>
<canvas id="capture"></canvas>
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
import { RGBELoader } from '${rgbeLoaderUrl}';

const canvas = document.getElementById('capture');
const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  preserveDrawingBuffer: true,
});
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.NeutralToneMapping;
renderer.shadowMap.enabled = false;

globalThis.renderPlan015ControlledComparison = async (
  modelUrls,
  environmentUrl,
  referenceState,
) => {
  const viewport = referenceState.viewport;
  renderer.setPixelRatio(viewport.devicePixelRatio);
  renderer.setSize(viewport.logicalWidth, viewport.logicalHeight, false);
  renderer.toneMappingExposure = referenceState.lighting.exposure;

  const hdrTexture = await new RGBELoader().loadAsync(environmentUrl);
  mirrorDecodedColumns(hdrTexture);
  hdrTexture.mapping = THREE.EquirectangularReflectionMapping;
  const pmrem = new THREE.PMREMGenerator(renderer);
  pmrem.compileEquirectangularShader();
  const environmentTarget = pmrem.fromEquirectangular(hdrTexture);
  const environment = environmentTarget.texture;
  const loader = new GLTFLoader();
  const captures = {};
  const sceneSummaries = {};

  for (const [modelId, modelUrl] of Object.entries(modelUrls)) {
    const gltf = await loader.loadAsync(modelUrl);
    const root = gltf.scene;
    root.updateWorldMatrix(true, true);
    const bounds = new THREE.Box3().setFromObject(root);
    const sphere = bounds.getBoundingSphere(new THREE.Sphere());
    if (!Number.isFinite(sphere.radius) || sphere.radius <= 0) {
      throw new Error(modelId + ' bounds cannot be fitted');
    }
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(referenceState.background.srgbHex);
    scene.environmentIntensity = referenceState.environment.intensity;
    scene.environmentRotation.y = referenceState.environment.rotationRadians;
    scene.add(root);
    const canonicalFrame = referenceState.modelFrames[modelId];
    assertCanonicalSourceBounds(modelId, sphere, canonicalFrame);
    const camera = fittedCamera(canonicalFrame, referenceState);
    const cameraTarget = new THREE.Vector3(
      canonicalFrame.centerFlutterSceneWorld[0],
      canonicalFrame.centerFlutterSceneWorld[1],
      -canonicalFrame.centerFlutterSceneWorld[2],
    );
    const key = directionalKey(cameraTarget, canonicalFrame.radius, referenceState.lighting);
    captures[modelId] = {};

    for (const pass of referenceState.renderPasses) {
      const wantsIbl = pass === 'iblOnly' || pass === 'combined';
      const wantsDirect = pass === 'directOnly' || pass === 'combined';
      scene.environment = wantsIbl ? environment : null;
      if (wantsDirect) {
        scene.add(key.light, key.target);
      } else {
        scene.remove(key.light, key.target);
      }
      await renderer.compileAsync(scene, camera);
      renderer.render(scene, camera);
      renderer.render(scene, camera);
      captures[modelId][pass] = canvas.toDataURL('image/png');
    }
    scene.remove(root, key.light, key.target);
    root.traverse((node) => {
      if (!node.isMesh) return;
      node.geometry?.dispose();
      const materials = Array.isArray(node.material) ? node.material : [node.material];
      for (const material of materials) material?.dispose();
    });
    sceneSummaries[modelId] = {
      bounds: {
        min: bounds.min.toArray(),
        max: bounds.max.toArray(),
        center: sphere.center.toArray(),
        radius: sphere.radius,
      },
      camera: {
        position: camera.position.toArray(),
        target: cameraTarget.toArray(),
        verticalFovDegrees: camera.fov,
        aspect: camera.aspect,
        near: camera.near,
        far: camera.far,
      },
      canonicalFrame,
    };
  }

  hdrTexture.dispose();
  environmentTarget.dispose();
  pmrem.dispose();
  renderer.dispose();
  return {
    captures,
    sceneSummaries,
    rendererMapping: {
      version: THREE.REVISION,
      toneMapping: 'NeutralToneMapping / Khronos PBR Neutral',
      exposure: referenceState.lighting.exposure,
      outputColorSpace: 'SRGBColorSpace',
      environment: 'same generated Radiance HDR bytes via RGBELoader + PMREM',
      environmentWorldOrientation: referenceState.environment.worldOrientation,
      environmentLongitudeCorrection:
        'decoded columns mirrored as the environment part of the shared Z mirror',
      environmentIntensity: referenceState.environment.intensity,
      environmentRotationRadians: referenceState.environment.rotationRadians,
      coordinateMapping:
        referenceState.rendererCoordinateMapping.threejsFromFlutterSceneWorld,
      directLight:
        'one DirectionalLight; flutter_scene travel direction mirrored on Z for Three.js',
      ambientOcclusion: 'disabled',
      shadows: 'disabled',
      skybox: 'not shown',
      camera: 'asset bounding sphere with viewer-equivalent fit/orbit math',
    },
  };
};

function fittedCamera(canonicalFrame, referenceState) {
  const viewport = referenceState.viewport;
  const state = referenceState.camera;
  const aspect = viewport.logicalWidth / viewport.logicalHeight;
  const verticalFovRadians = THREE.MathUtils.degToRad(state.verticalFovDegrees);
  const halfVerticalFov = verticalFovRadians / 2;
  const halfHorizontalFov = Math.atan(Math.tan(halfVerticalFov) * aspect);
  const limitingHalfFov = Math.min(halfVerticalFov, halfHorizontalFov);
  const distance =
    canonicalFrame.radius * state.fitPadding / Math.sin(limitingHalfFov);
  const pitchCos = Math.cos(state.pitchRadians);
  const target = new THREE.Vector3(
    canonicalFrame.centerFlutterSceneWorld[0],
    canonicalFrame.centerFlutterSceneWorld[1],
    -canonicalFrame.centerFlutterSceneWorld[2],
  );
  const position = new THREE.Vector3(
    target.x + distance * Math.sin(state.yawRadians) * pitchCos,
    target.y + distance * Math.sin(state.pitchRadians),
    target.z - distance * Math.cos(state.yawRadians) * pitchCos,
  );
  const camera = new THREE.PerspectiveCamera(
    state.verticalFovDegrees,
    aspect,
    state.near,
    state.far,
  );
  camera.position.copy(position);
  camera.up.set(0, 1, 0);
  camera.lookAt(target);
  camera.updateMatrixWorld(true);
  return camera;
}

function directionalKey(targetPosition, radius, lighting) {
  const direction = new THREE.Vector3()
    .set(
      lighting.keyLightDirection[0],
      lighting.keyLightDirection[1],
      -lighting.keyLightDirection[2],
    )
    .normalize();
  const target = new THREE.Object3D();
  target.position.copy(targetPosition);
  const light = new THREE.DirectionalLight(
    new THREE.Color().fromArray(lighting.keyLightColorLinear),
    lighting.keyLightIntensity,
  );
  light.position.copy(targetPosition).addScaledVector(
    direction,
    -Math.max(radius * 4, 1),
  );
  light.target = target;
  light.castShadow = lighting.keyLightCastsShadow;
  return { light, target };
}

function assertCanonicalSourceBounds(modelId, observedSphere, canonicalFrame) {
  const expectedCenter = new THREE.Vector3(
    canonicalFrame.centerFlutterSceneWorld[0],
    canonicalFrame.centerFlutterSceneWorld[1],
    -canonicalFrame.centerFlutterSceneWorld[2],
  );
  const centerError = observedSphere.center.distanceTo(expectedCenter);
  const radiusError = Math.abs(observedSphere.radius - canonicalFrame.radius);
  if (centerError > 1e-9 || radiusError > 1e-9) {
    throw new Error(
      modelId + ' canonical frame drifted: centerError=' + centerError +
        ' radiusError=' + radiusError,
    );
  }
}

function mirrorDecodedColumns(texture) {
  const image = texture.image;
  const data = image?.data;
  const width = image?.width;
  const height = image?.height;
  if (data == null || !Number.isInteger(width) || !Number.isInteger(height)) {
    throw new Error('RGBELoader did not expose decoded equirectangular pixels');
  }
  const channels = data.length / (width * height);
  if (!Number.isInteger(channels) || channels < 3) {
    throw new Error('Decoded HDR channel layout cannot be mirrored');
  }
  for (let y = 0; y < height; y += 1) {
    for (let left = 0; left < Math.floor(width / 2); left += 1) {
      const right = width - 1 - left;
      const leftOffset = (y * width + left) * channels;
      const rightOffset = (y * width + right) * channels;
      for (let channel = 0; channel < channels; channel += 1) {
        const temporary = data[leftOffset + channel];
        data[leftOffset + channel] = data[rightOffset + channel];
        data[rightOffset + channel] = temporary;
      }
    }
  }
  texture.needsUpdate = true;
}

</script>`;
}

function decodePng(dataUrl) {
  const prefix = 'data:image/png;base64,';
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith(prefix)) {
    throw new Error('capture did not return a PNG data URL');
  }
  return Buffer.from(dataUrl.slice(prefix.length), 'base64');
}

function hash(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function contentType(filePath) {
  if (filePath.endsWith('.js')) return 'text/javascript';
  if (filePath.endsWith('.glb')) return 'model/gltf-binary';
  if (filePath.endsWith('.hdr')) return 'application/octet-stream';
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
