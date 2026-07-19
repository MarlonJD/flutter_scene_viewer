import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  hashBytes,
  loadPlan016ControlledComparisonState,
  modelCatalog,
  outputRoot,
  plan016StateHash,
  repoRoot,
  statePath,
  writePlan016ControlledStudioHdr,
} from './plan016_controlled_comparison_contract.mjs';

const state = loadPlan016ControlledComparisonState();
const catalog = modelCatalog(state);
const threeOutputRoot = path.join(outputRoot, 'threejs');
fs.mkdirSync(threeOutputRoot, { recursive: true });
const generatedHdr = writePlan016ControlledStudioHdr(state);

const routes = new Map([
  ['/__environment__/controlled.hdr', generatedHdr.destination],
  ...Object.entries(catalog).map(([id, model]) => [
    `/__model__/${id}.glb`,
    model.absolutePath,
  ]),
]);
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

const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const executablePath =
  process.env.PUPPETEER_EXECUTABLE_PATH ??
  (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
const profilePath = fs.mkdtempSync(
  path.join(os.tmpdir(), 'plan016-threejs-controlled-'),
);
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
    'typeof globalThis.initializePlan016Comparison === "function"',
    { timeout: 10000 },
  );
  const rendererMapping = await page.evaluate(
    ({ environmentUrl, referenceState }) =>
      globalThis.initializePlan016Comparison(environmentUrl, referenceState),
    {
      environmentUrl: `${origin}/__environment__/controlled.hdr`,
      referenceState: state,
    },
  );

  const artifacts = {};
  const sceneSummaries = {};
  const materialAssertionAudit = {};
  const pixelSummaries = {};
  for (const [modelId, model] of Object.entries(catalog)) {
    const browserContract = {
      sourceBoundsThree: model.sourceBoundsThree,
      cameraFrame: model.cameraFrame,
      materialAssertions: model.materialAssertions,
    };
    sceneSummaries[modelId] = await page.evaluate(
      ({ id, url, contract, referenceState }) =>
        globalThis.loadPlan016Model(id, url, contract, referenceState),
      {
        id: modelId,
        url: `${origin}/__model__/${modelId}.glb`,
        contract: browserContract,
        referenceState: state,
      },
    );
    artifacts[modelId] = {};
    materialAssertionAudit[modelId] = {};
    pixelSummaries[modelId] = {};
    for (const pass of state.renderPasses) {
      const capture = await page.evaluate(
        ({ capturePass, referenceState }) =>
          globalThis.renderPlan016Pass(capturePass, referenceState),
        { capturePass: pass, referenceState: state },
      );
      const bytes = decodePng(capture.dataUrl);
      const artifactPath = path.join(
        threeOutputRoot,
        `${modelId}_${pass}.png`,
      );
      fs.writeFileSync(artifactPath, bytes);
      artifacts[modelId][pass] = {
        path: path.relative(repoRoot, artifactPath),
        sha256: hashBytes(bytes),
        byteLength: bytes.length,
        dimensions: pngDimensions(bytes),
      };
      materialAssertionAudit[modelId][pass] = capture.materialAssertions;
      pixelSummaries[modelId][pass] = capture.pixelSummary;
    }
    console.log(`Plan 016 Three.js captures: ${modelId} OK`);
  }
  await page.evaluate(() => globalThis.disposePlan016Comparison());

  const evidence = {
    schemaVersion: 1,
    status: 'verified locally',
    scope: 'stock Three.js r167 controlled reference only',
    sourceState: path.relative(repoRoot, statePath),
    stateSha256: plan016StateHash(),
    state,
    environment: {
      path: path.relative(repoRoot, generatedHdr.destination),
      sha256: generatedHdr.sha256,
      byteLength: generatedHdr.bytes.length,
    },
    models: Object.fromEntries(
      Object.entries(catalog).map(([id, model]) => [
        id,
        {
          path: model.path,
          sha256: model.sha256,
          byteLength: model.byteLength,
          kind: model.kind,
          extensions: model.extensions,
          sourcePath: model.sourcePath ?? null,
          licensePath: model.licensePath ?? null,
          licenseSha256: model.licenseSha256 ?? null,
        },
      ]),
    ),
    renderer: {
      name: 'Three.js',
      packageVersion: state.referenceRenderer.packageVersion,
      revision: rendererMapping.version,
      packageIntegrity: state.referenceRenderer.packageIntegrity,
      packageLockSha256: state.referenceRenderer.packageLockSha256,
      browser: await browser.version(),
      host: {
        platform: process.platform,
        release: os.release(),
        architecture: process.arch,
      },
      mapping: rendererMapping,
    },
    sceneSummaries,
    materialAssertionAudit,
    pixelSummaries,
    artifacts,
    assertionBoundary:
      'Every model/pass capture re-ran exact MeshPhysicalMaterial assertions ' +
      'for transmission, IOR, thickness, attenuation, texture maps and ' +
      'transforms, clearcoat, metalness, roughness, and normal-map presence.',
    comparisonBoundary:
      'Stock pinned Three.js reference; no material patching, exposure nudges, ' +
      'camera overrides, environment boosts, or asset repairs were applied. ' +
      'Independent BRDF, rasterization, and HDR-prefilter implementations ' +
      'prevent a pixel-parity claim.',
  };
  fs.writeFileSync(
    path.join(threeOutputRoot, 'evidence.json'),
    `${JSON.stringify(evidence, null, 2)}\n`,
  );
  console.log(
    `Plan 016 controlled Three.js reference: ` +
      `${Object.keys(catalog).length} models x ${state.renderPasses.length} passes OK`,
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
const context = {
  loader: new GLTFLoader(),
  environmentTarget: null,
  environment: null,
  pmrem: null,
  hdrTexture: null,
  current: null,
};

globalThis.initializePlan016Comparison = async (environmentUrl, referenceState) => {
  const viewport = referenceState.viewport;
  renderer.setPixelRatio(viewport.devicePixelRatio);
  renderer.setSize(viewport.logicalWidth, viewport.logicalHeight, false);
  renderer.toneMappingExposure = referenceState.lighting.exposure;
  context.hdrTexture = await new RGBELoader().loadAsync(environmentUrl);
  mirrorDecodedColumns(context.hdrTexture);
  context.hdrTexture.mapping = THREE.EquirectangularReflectionMapping;
  context.pmrem = new THREE.PMREMGenerator(renderer);
  context.pmrem.compileEquirectangularShader();
  context.environmentTarget = context.pmrem.fromEquirectangular(context.hdrTexture);
  context.environment = context.environmentTarget.texture;
  return {
    version: THREE.REVISION,
    toneMapping: 'NeutralToneMapping / Khronos PBR Neutral',
    exposure: referenceState.lighting.exposure,
    outputColorSpace: 'SRGBColorSpace',
    environment: 'same hash-pinned Radiance HDR bytes via RGBELoader + PMREM',
    environmentWorldOrientation: referenceState.environment.worldOrientation,
    environmentLongitudeCorrection:
      'decoded columns mirrored as the environment part of the shared Z mirror',
    environmentIntensity: referenceState.environment.intensity,
    environmentRotationRadians: referenceState.environment.rotationRadians,
    coordinateMapping:
      referenceState.rendererCoordinateMapping.threejsFromFlutterSceneWorld,
    directLight:
      'one DirectionalLight; flutter_scene travel direction mirrored on Z',
    ambientOcclusion: 'disabled',
    shadows: 'disabled',
    skybox: 'not shown',
    camera: 'frozen per-model canonical frame from tracked state',
    materialPatches: 'none',
  };
};

globalThis.loadPlan016Model = async (
  modelId,
  modelUrl,
  modelContract,
  referenceState,
) => {
  disposeCurrent();
  const gltf = await context.loader.loadAsync(modelUrl);
  const root = gltf.scene;
  root.updateWorldMatrix(true, true);
  const bounds = new THREE.Box3().setFromObject(root);
  const sourceSphere = bounds.getBoundingSphere(new THREE.Sphere());
  assertSourceBounds(modelId, sourceSphere, modelContract.sourceBoundsThree);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(referenceState.background.srgbHex);
  scene.environmentIntensity = referenceState.environment.intensity;
  scene.environmentRotation.y = referenceState.environment.rotationRadians;
  scene.add(root);
  const camera = fittedCamera(modelContract.cameraFrame, referenceState);
  const cameraTarget = new THREE.Vector3(
    modelContract.cameraFrame.centerFlutterSceneWorld[0],
    modelContract.cameraFrame.centerFlutterSceneWorld[1],
    -modelContract.cameraFrame.centerFlutterSceneWorld[2],
  );
  const key = directionalKey(
    cameraTarget,
    modelContract.cameraFrame.radius,
    referenceState.lighting,
  );
  context.current = {
    modelId,
    root,
    scene,
    camera,
    cameraTarget,
    key,
    materialAssertions: modelContract.materialAssertions,
  };
  return {
    sourceBounds: {
      min: bounds.min.toArray(),
      max: bounds.max.toArray(),
      center: sourceSphere.center.toArray(),
      radius: sourceSphere.radius,
    },
    camera: {
      position: camera.position.toArray(),
      target: cameraTarget.toArray(),
      verticalFovDegrees: camera.fov,
      aspect: camera.aspect,
      near: camera.near,
      far: camera.far,
    },
    cameraFrame: modelContract.cameraFrame,
  };
};

globalThis.renderPlan016Pass = async (pass, referenceState) => {
  const current = context.current;
  if (current == null) throw new Error('Plan 016 model is not loaded');
  const materialAssertions = assertMaterialContract(
    current.modelId,
    current.root,
    current.materialAssertions,
  );
  const wantsIbl = pass === 'iblOnly' || pass === 'combined';
  const wantsDirect = pass === 'directOnly' || pass === 'combined';
  if (!referenceState.renderPasses.includes(pass)) {
    throw new Error('Unexpected Plan 016 pass: ' + pass);
  }
  current.scene.environment = wantsIbl ? context.environment : null;
  if (wantsDirect) {
    current.scene.add(current.key.light, current.key.target);
  } else {
    current.scene.remove(current.key.light, current.key.target);
  }
  await renderer.compileAsync(current.scene, current.camera);
  renderer.render(current.scene, current.camera);
  renderer.render(current.scene, current.camera);
  const pixelSummary = summarizePixels(referenceState.comparisonMetrics);
  renderer.getContext().finish();
  return {
    dataUrl: canvas.toDataURL('image/png'),
    materialAssertions,
    pixelSummary,
  };
};

globalThis.disposePlan016Comparison = () => {
  disposeCurrent();
  context.hdrTexture?.dispose();
  context.environmentTarget?.dispose();
  context.pmrem?.dispose();
  renderer.dispose();
};

function assertMaterialContract(modelId, root, expectedAssertions) {
  const materials = [];
  const seen = new Set();
  root.traverse((node) => {
    if (!node.isMesh) return;
    const nodeMaterials = Array.isArray(node.material)
      ? node.material
      : [node.material];
    for (const material of nodeMaterials) {
      if (material == null || seen.has(material.uuid)) continue;
      seen.add(material.uuid);
      materials.push(material);
    }
  });
  return expectedAssertions.map((expected) => {
    const candidates = materials.filter((material) => material.name === expected.name);
    if (candidates.length === 0) {
      throw new Error(modelId + ' missing material ' + expected.name);
    }
    let lastError;
    for (const material of candidates) {
      try {
        assertMaterial(modelId, material, expected);
        return materialSummary(material);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  });
}

function assertMaterial(modelId, material, expected) {
  const prefix = modelId + '/' + expected.name;
  if (material.isMeshPhysicalMaterial !== expected.isMeshPhysicalMaterial) {
    throw new Error(prefix + ' is not the expected MeshPhysicalMaterial');
  }
  for (const field of [
    'transmission',
    'ior',
    'thickness',
    'clearcoat',
    'clearcoatRoughness',
    'metalness',
    'roughness',
  ]) {
    assertNear(prefix + '/' + field, material[field], expected[field]);
  }
  if (expected.attenuationDistance === 'Infinity') {
    if (material.attenuationDistance !== Infinity) {
      throw new Error(prefix + '/attenuationDistance must be Infinity');
    }
  } else {
    assertNear(
      prefix + '/attenuationDistance',
      material.attenuationDistance,
      expected.attenuationDistance,
    );
  }
  assertArrayNear(
    prefix + '/attenuationColor',
    material.attenuationColor.toArray(),
    expected.attenuationColor,
  );
  assertTexture(prefix + '/transmissionMap', material.transmissionMap, expected.transmissionMap);
  assertTexture(prefix + '/thicknessMap', material.thicknessMap, expected.thicknessMap);
  assertTexture(prefix + '/normalMap', material.normalMap, expected.normalMap);
}

function assertTexture(label, texture, expected) {
  if (expected == null) {
    if (texture != null) throw new Error(label + ' must be absent');
    return;
  }
  if (texture == null) throw new Error(label + ' must be present');
  if (texture.name !== expected.name) {
    throw new Error(label + '/name ' + texture.name + ' != ' + expected.name);
  }
  if (expected.offset != null) {
    assertArrayNear(label + '/offset', texture.offset.toArray(), expected.offset);
  }
  if (expected.repeat != null) {
    assertArrayNear(label + '/repeat', texture.repeat.toArray(), expected.repeat);
  }
  if (expected.rotation != null) {
    assertNear(label + '/rotation', texture.rotation, expected.rotation);
  }
}

function assertNear(label, actual, expected) {
  if (!Number.isFinite(actual) || Math.abs(actual - expected) > 1e-6) {
    throw new Error(label + ' ' + actual + ' != ' + expected);
  }
}

function assertArrayNear(label, actual, expected) {
  if (!Array.isArray(actual) || actual.length !== expected.length) {
    throw new Error(label + ' shape mismatch');
  }
  actual.forEach((value, index) => assertNear(label + '[' + index + ']', value, expected[index]));
}

function materialSummary(material) {
  return {
    name: material.name,
    type: material.type,
    transmission: material.transmission,
    ior: material.ior,
    thickness: material.thickness,
    attenuationDistance: Number.isFinite(material.attenuationDistance)
      ? material.attenuationDistance
      : 'Infinity',
    attenuationColor: material.attenuationColor.toArray(),
    transmissionMap: textureSummary(material.transmissionMap),
    thicknessMap: textureSummary(material.thicknessMap),
    normalMap: textureSummary(material.normalMap),
    clearcoat: material.clearcoat,
    clearcoatRoughness: material.clearcoatRoughness,
    metalness: material.metalness,
    roughness: material.roughness,
  };
}

function textureSummary(texture) {
  if (texture == null) return null;
  return {
    name: texture.name,
    offset: texture.offset.toArray(),
    repeat: texture.repeat.toArray(),
    rotation: texture.rotation,
  };
}

function fittedCamera(canonicalFrame, referenceState) {
  const viewport = referenceState.viewport;
  const cameraState = referenceState.camera;
  const aspect = viewport.logicalWidth / viewport.logicalHeight;
  const verticalFovRadians = THREE.MathUtils.degToRad(
    cameraState.verticalFovDegrees,
  );
  const halfVerticalFov = verticalFovRadians / 2;
  const halfHorizontalFov = Math.atan(Math.tan(halfVerticalFov) * aspect);
  const limitingHalfFov = Math.min(halfVerticalFov, halfHorizontalFov);
  const distance =
    canonicalFrame.radius * cameraState.fitPadding / Math.sin(limitingHalfFov);
  const pitchCos = Math.cos(cameraState.pitchRadians);
  const target = new THREE.Vector3(
    canonicalFrame.centerFlutterSceneWorld[0],
    canonicalFrame.centerFlutterSceneWorld[1],
    -canonicalFrame.centerFlutterSceneWorld[2],
  );
  const position = new THREE.Vector3(
    target.x + distance * Math.sin(cameraState.yawRadians) * pitchCos,
    target.y + distance * Math.sin(cameraState.pitchRadians),
    target.z - distance * Math.cos(cameraState.yawRadians) * pitchCos,
  );
  const camera = new THREE.PerspectiveCamera(
    cameraState.verticalFovDegrees,
    aspect,
    cameraState.near,
    cameraState.far,
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

function assertSourceBounds(modelId, observed, expected) {
  const expectedCenter = new THREE.Vector3().fromArray(expected.center);
  const centerError = observed.center.distanceTo(expectedCenter);
  const radiusError = Math.abs(observed.radius - expected.radius);
  if (centerError > 1e-9 || radiusError > 1e-9) {
    throw new Error(
      modelId + ' source bounds drifted: centerError=' + centerError +
        ' radiusError=' + radiusError,
    );
  }
}

function summarizePixels(metricState) {
  const gl = renderer.getContext();
  const width = gl.drawingBufferWidth;
  const height = gl.drawingBufferHeight;
  const pixels = new Uint8Array(width * height * 4);
  gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  const roi = metricState.syntheticGlassRoiNormalized;
  const left = Math.floor(roi.left * width);
  const right = Math.ceil((roi.left + roi.width) * width);
  const bottom = Math.floor((1 - roi.top - roi.height) * height);
  const top = Math.ceil((1 - roi.top) * height);
  const sum = [0, 0, 0];
  let luminance = 0;
  let count = 0;
  let edgeEnergy = 0;
  let edgeWeight = 0;
  let edgeX = 0;
  let edgeY = 0;
  for (let y = bottom; y < top; y += 1) {
    for (let x = left; x < right; x += 1) {
      const offset = (y * width + x) * 4;
      const red = pixels[offset] / 255;
      const green = pixels[offset + 1] / 255;
      const blue = pixels[offset + 2] / 255;
      sum[0] += red;
      sum[1] += green;
      sum[2] += blue;
      luminance += red * 0.2126 + green * 0.7152 + blue * 0.0722;
      count += 1;
      if (x + 1 < right && y + 1 < top) {
        const rightOffset = offset + 4;
        const upOffset = ((y + 1) * width + x) * 4;
        const luma = red * 0.2126 + green * 0.7152 + blue * 0.0722;
        const rightLuma =
          pixels[rightOffset] / 255 * 0.2126 +
          pixels[rightOffset + 1] / 255 * 0.7152 +
          pixels[rightOffset + 2] / 255 * 0.0722;
        const upLuma =
          pixels[upOffset] / 255 * 0.2126 +
          pixels[upOffset + 1] / 255 * 0.7152 +
          pixels[upOffset + 2] / 255 * 0.0722;
        const gradient = Math.abs(rightLuma - luma) + Math.abs(upLuma - luma);
        edgeEnergy += gradient;
        edgeWeight += gradient;
        edgeX += gradient * (x / referencePixelRatio(metricState));
        edgeY += gradient * ((height - 1 - y) / referencePixelRatio(metricState));
      }
    }
  }
  return {
    roiDevicePixels: { left, top: height - top, width: right - left, height: top - bottom },
    meanRgb: sum.map((value) => value / count),
    meanLuminance: luminance / count,
    edgeEnergy: edgeEnergy / count,
    edgeCentroidLogical: edgeWeight > 0
      ? [edgeX / edgeWeight, edgeY / edgeWeight]
      : null,
  };
}

function referencePixelRatio() {
  return renderer.getPixelRatio();
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

function disposeCurrent() {
  const current = context.current;
  if (current == null) return;
  current.scene.remove(current.root, current.key.light, current.key.target);
  current.root.traverse((node) => {
    if (!node.isMesh) return;
    node.geometry?.dispose();
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) material?.dispose();
  });
  context.current = null;
}
</script>`;
}

function decodePng(dataUrl) {
  const prefix = 'data:image/png;base64,';
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith(prefix)) {
    throw new Error('Plan 016 capture did not return a PNG data URL');
  }
  return Buffer.from(dataUrl.slice(prefix.length), 'base64');
}

function pngDimensions(bytes) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature)) {
    throw new Error('Plan 016 capture is not a PNG');
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
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
