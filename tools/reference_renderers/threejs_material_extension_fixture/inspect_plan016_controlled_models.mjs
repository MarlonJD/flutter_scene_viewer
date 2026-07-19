import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const stagedRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/' +
    'plan016_renderer_native_transmission',
);
const syntheticManifest = JSON.parse(
  fs.readFileSync(path.join(stagedRoot, 'synthetic/manifest.json'), 'utf8'),
);
const models = {
  ...Object.fromEntries(
    Object.entries(syntheticManifest.variants).map(([id, entry]) => [
      id,
      path.join(repoRoot, entry.path),
    ]),
  ),
  transmission_test: path.join(stagedRoot, 'transmission_test/TransmissionTest.glb'),
  attenuation_test: path.join(stagedRoot, 'attenuation_test/AttenuationTest.glb'),
  glass_vase_flowers: path.join(
    stagedRoot,
    'glass_vase_flowers/GlassVaseFlowers.glb',
  ),
  toycar: path.join(stagedRoot, 'toycar/ToyCar.glb'),
};

for (const [id, modelPath] of Object.entries(models)) {
  if (!fs.existsSync(modelPath)) {
    throw new Error(`Plan 016 model is missing (${id}): ${modelPath}`);
  }
}

const profilePath = fs.mkdtempSync(path.join(os.tmpdir(), 'plan016-inspect-'));
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
    response.end(pageHtml(origin));
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
      'content-type': filePath.endsWith('.js')
        ? 'text/javascript'
        : 'application/octet-stream',
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
  page.on('pageerror', (error) => console.error(error.message));
  await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
  await page.waitForFunction(
    'typeof globalThis.inspectPlan016Models === "function"',
    { timeout: 10000 },
  );
  const urls = Object.fromEntries(
    Object.entries(models).map(([id, modelPath]) => [
      id,
      `${origin}/${path.relative(repoRoot, modelPath)}`,
    ]),
  );
  const inspection = await page.evaluate(
    (modelUrls) => globalThis.inspectPlan016Models(modelUrls),
    urls,
  );
  const output = {
    schemaVersion: 1,
    renderer: {
      name: 'Three.js',
      revision: inspection.revision,
      browser: await browser.version(),
    },
    models: inspection.models,
  };
  const destination = path.join(stagedRoot, 'inspection.json');
  fs.writeFileSync(destination, `${JSON.stringify(output, null, 2)}\n`);
  console.log(`Plan 016 model inspection: ${Object.keys(models).length} GLBs OK`);
  console.log(destination);
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
  return `<!doctype html>
<meta charset="utf-8">
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

globalThis.inspectPlan016Models = async (modelUrls) => {
  const loader = new GLTFLoader();
  const models = {};
  for (const [id, url] of Object.entries(modelUrls)) {
    const gltf = await loader.loadAsync(url);
    const root = gltf.scene;
    root.updateWorldMatrix(true, true);
    const bounds = new THREE.Box3().setFromObject(root);
    const sphere = bounds.getBoundingSphere(new THREE.Sphere());
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
        materials.push(materialSummary(material));
      }
    });
    models[id] = {
      bounds: {
        min: bounds.min.toArray(),
        max: bounds.max.toArray(),
        center: sphere.center.toArray(),
        radius: sphere.radius,
      },
      materials,
    };
    root.traverse((node) => {
      if (!node.isMesh) return;
      node.geometry?.dispose();
      const nodeMaterials = Array.isArray(node.material)
        ? node.material
        : [node.material];
      for (const material of nodeMaterials) material?.dispose();
    });
  }
  return { revision: THREE.REVISION, models };
};

function materialSummary(material) {
  return {
    name: material.name,
    type: material.type,
    isMeshPhysicalMaterial: material.isMeshPhysicalMaterial === true,
    transmission: finite(material.transmission),
    ior: finite(material.ior),
    thickness: finite(material.thickness),
    attenuationDistance: Number.isFinite(material.attenuationDistance)
      ? material.attenuationDistance
      : 'Infinity',
    attenuationColor: material.attenuationColor?.toArray() ?? null,
    transmissionMap: textureSummary(material.transmissionMap),
    thicknessMap: textureSummary(material.thicknessMap),
    normalMap: textureSummary(material.normalMap),
    clearcoat: finite(material.clearcoat),
    clearcoatRoughness: finite(material.clearcoatRoughness),
    metalness: finite(material.metalness),
    roughness: finite(material.roughness),
    transparent: material.transparent === true,
    side: material.side,
  };
}

function textureSummary(texture) {
  if (texture == null) return null;
  return {
    name: texture.name,
    offset: texture.offset.toArray(),
    repeat: texture.repeat.toArray(),
    rotation: texture.rotation,
    channel: texture.channel,
  };
}

function finite(value) {
  return Number.isFinite(value) ? value : null;
}
</script>`;
}
