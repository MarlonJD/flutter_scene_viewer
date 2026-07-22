import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  loadPlan018ControlledComparisonState,
  modelCatalog,
  outputRoot,
  plan018StateHash,
  repoRoot,
  statePath,
} from './plan018_controlled_comparison_contract.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

export async function runPlan018SheenLoaderAudit({ writeEvidence = true } = {}) {
  const state = loadPlan018ControlledComparisonState();
  const catalog = modelCatalog(state);
  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-sheen-loader-'),
  );
  const routes = new Map(
    Object.entries(catalog).map(([id, model]) => [
      `/__model__/${id}.glb`,
      model.absolutePath,
    ]),
  );
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

  let browser;
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', () => {
        server.off('error', reject);
        resolve();
      });
    });
    origin = `http://127.0.0.1:${server.address().port}`;
    const executablePath =
      process.env.PUPPETEER_EXECUTABLE_PATH ??
      (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
    browser = await puppeteer.launch({
      headless: true,
      executablePath,
      userDataDir: profilePath,
      args: ['--disable-background-networking', '--disable-gpu-sandbox'],
    });
    const page = await browser.newPage();
    page.on('pageerror', (error) => {
      console.error(`[browser:pageerror] ${error.message}`);
    });
    await page.setViewport({
      width: state.viewport.logicalWidth,
      height: state.viewport.logicalHeight,
      deviceScaleFactor: 1,
    });
    await page.goto(`${origin}/__runner.html`, { waitUntil: 'networkidle0' });
    await page.waitForFunction(
      'typeof globalThis.inspectPlan018SheenLoader === "function"',
      { timeout: 10000 },
    );
    const browserAudit = await page.evaluate(
      ({ modelUrls, modelContracts }) =>
        globalThis.inspectPlan018SheenLoader(modelUrls, modelContracts),
      {
        modelUrls: Object.fromEntries(
          Object.keys(catalog).map((id) => [
            id,
            `${origin}/__model__/${id}.glb`,
          ]),
        ),
        modelContracts: Object.fromEntries(
          Object.entries(catalog).map(([id, model]) => [
            id,
            {
              sourceBounds: model.sourceBounds,
              sheenPrimitiveBounds: model.sheenPrimitiveBounds,
              sheenMaterialIndices: model.sheenMaterialIndices,
            },
          ]),
        ),
      },
    );
    const result = {
      schemaVersion: 1,
      status: 'verified locally',
      scope: 'Three.js GLTFLoader consumption only',
      sourceState: path.relative(repoRoot, statePath),
      stateSha256: plan018StateHash(),
      renderer: {
        name: state.referenceRenderer.name,
        packageVersion: state.referenceRenderer.packageVersion,
        revision: browserAudit.renderer.revision,
        sourceCommit: state.referenceRenderer.sourceCommit,
        packageIntegrity: state.referenceRenderer.packageIntegrity,
        packageLockSha256: state.referenceRenderer.packageLockSha256,
        backend: browserAudit.renderer.backend,
        backendFacts: browserAudit.renderer.backendFacts,
        sourceSha256: state.referenceRenderer.sourceSha256,
      },
      browser: await browser.version(),
      host: {
        platform: process.platform,
        release: os.release(),
        architecture: process.arch,
      },
      models: browserAudit.models,
      collectiveCoverage: browserAudit.collectiveCoverage,
      cleanupContract: {
        browser: 'closed in finally',
        server: 'closed in finally',
        profile: 'unique temporary profile removed in finally',
      },
      comparisonBoundary:
        'Pinned stock Three.js importer direction/conformance evidence only; ' +
        'no reference image, Flutter load, target capture, or pixel-parity claim.',
    };
    if (writeEvidence) {
      fs.mkdirSync(outputRoot, { recursive: true });
      fs.writeFileSync(
        path.join(outputRoot, 'threejs_loader_audit.json'),
        `${JSON.stringify(result, null, 2)}\n`,
      );
    }
    return result;
  } finally {
    if (browser != null) await browser.close();
    if (server.listening) {
      await new Promise((resolve) => server.close(resolve));
    }
    fs.rmSync(profilePath, { recursive: true, force: true });
  }
}

function pageHtml(baseUrl) {
  const fixtureRoot =
    `${baseUrl}/tools/reference_renderers/threejs_material_extension_fixture/`;
  const threeUrl = `${fixtureRoot}node_modules/three/build/three.module.js`;
  const loaderUrl =
    `${fixtureRoot}node_modules/three/examples/jsm/loaders/GLTFLoader.js`;
  return `<!doctype html>
<meta charset="utf-8">
<canvas id="audit" width="16" height="16"></canvas>
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

const renderer = new THREE.WebGLRenderer({
  canvas: document.getElementById('audit'),
  antialias: false,
});

globalThis.inspectPlan018SheenLoader = async (modelUrls, modelContracts) => {
  const loader = new GLTFLoader();
  const models = {};
  const collectiveCoverage = {
    sheenColorFactor: false,
    sheenColorTexture: false,
    sheenRoughnessFactor: false,
    sheenRoughnessTexture: false,
  };
  for (const [modelId, modelUrl] of Object.entries(modelUrls)) {
    const gltf = await loader.loadAsync(modelUrl);
    models[modelId] = await auditModel(
      modelId,
      gltf,
      modelContracts[modelId],
      collectiveCoverage,
    );
    disposeGltf(gltf);
  }
  if (Object.values(collectiveCoverage).some((value) => value !== true)) {
    throw new Error('GLTFLoader audit did not consume every sheen input');
  }
  const gl = renderer.getContext();
  const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
  const backendFacts = {
    rendererType: renderer.constructor.name,
    isWebGLRenderer: renderer.isWebGLRenderer === true,
    isWebGL2:
      typeof WebGL2RenderingContext !== 'undefined' &&
      gl instanceof WebGL2RenderingContext,
    contextVersion: gl.getParameter(gl.VERSION),
    shadingLanguageVersion: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
    vendor: debugInfo == null
      ? gl.getParameter(gl.VENDOR)
      : gl.getParameter(debugInfo.UNMASKED_VENDOR_WEBGL),
    renderer: debugInfo == null
      ? gl.getParameter(gl.RENDERER)
      : gl.getParameter(debugInfo.UNMASKED_RENDERER_WEBGL),
    renderedPixels: false,
  };
  renderer.dispose();
  renderer.forceContextLoss();
  return {
    renderer: {
      revision: THREE.REVISION,
      backend: 'WebGL',
      backendFacts,
    },
    models,
    collectiveCoverage,
  };
};

async function auditModel(modelId, gltf, contract, collectiveCoverage) {
  const root = gltf.scene;
  root.updateWorldMatrix(true, true);
  const sourceBox = new THREE.Box3().setFromObject(root);
  const sourceSphere = sourceBox.getBoundingSphere(new THREE.Sphere());
  assertBounds(modelId + '/sourceBounds', sourceBox, sourceSphere, contract.sourceBounds);
  const sheenBox = new THREE.Box3();
  let sheenPrimitiveCount = 0;
  root.traverse((node) => {
    if (!node.isMesh) return;
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    if (!materials.some((material) => {
      const materialIndex = gltf.parser.associations.get(material)?.materials;
      return contract.sheenMaterialIndices.includes(materialIndex);
    })) return;
    sheenBox.union(new THREE.Box3().setFromObject(node));
    sheenPrimitiveCount += 1;
  });
  if (sheenPrimitiveCount === 0) {
    throw new Error(modelId + ' has no loaded sheen primitive');
  }
  const sheenSphere = sheenBox.getBoundingSphere(new THREE.Sphere());
  assertBounds(
    modelId + '/sheenPrimitiveBounds',
    sheenBox,
    sheenSphere,
    contract.sheenPrimitiveBounds,
  );

  const materials = [];
  for (const materialIndex of contract.sheenMaterialIndices) {
    const materialDef = gltf.parser.json.materials?.[materialIndex];
    const extension = materialDef?.extensions?.KHR_materials_sheen;
    if (extension == null) {
      throw new Error(modelId + '/material[' + materialIndex + '] lost KHR_materials_sheen');
    }
    const material = await gltf.parser.getDependency('material', materialIndex);
    const audit = auditMaterial(
      modelId,
      materialIndex,
      materialDef,
      extension,
      material,
      gltf.parser,
    );
    for (const field of Object.keys(collectiveCoverage)) {
      if (audit.authored.inputPresence[field]) collectiveCoverage[field] = true;
    }
    materials.push(audit);
  }

  const cloth = modelId === 'sheen_cloth' ? materials[0] : null;
  if (cloth != null) {
    const color = cloth.actual.sheenColorMap;
    const roughness = cloth.actual.sheenRoughnessMap;
    if (
      color?.sourceIndex !== roughness?.sourceIndex ||
      color.channelRole !== 'rgb' ||
      color.colorSpace !== 'srgb' ||
      roughness.channelRole !== 'alpha' ||
      roughness.colorSpace !== 'linear' ||
      color.sameThreeTextureObjectAsOtherMap !== false ||
      roughness.sameThreeTextureObjectAsOtherMap !== false
    ) {
      throw new Error('SheenCloth dual-role texture consumption changed');
    }
  }
  return {
    sourceBounds: boundsSummary(sourceBox, sourceSphere),
    sheenPrimitiveBounds: boundsSummary(sheenBox, sheenSphere),
    sheenPrimitiveCount,
    materials,
  };
}

function auditMaterial(modelId, materialIndex, materialDef, extension, material, parser) {
  const label = modelId + '/' + materialDef.name;
  const authored = {
    materialIndex,
    materialName: materialDef.name,
    inputPresence: {
      sheenColorFactor: Object.hasOwn(extension, 'sheenColorFactor'),
      sheenColorTexture: Object.hasOwn(extension, 'sheenColorTexture'),
      sheenRoughnessFactor: Object.hasOwn(extension, 'sheenRoughnessFactor'),
      sheenRoughnessTexture: Object.hasOwn(extension, 'sheenRoughnessTexture'),
    },
    sheenColorFactor: extension.sheenColorFactor ?? [0, 0, 0],
    sheenRoughnessFactor: extension.sheenRoughnessFactor ?? 0,
    sheenColorTexture: authoredTexture(
      extension.sheenColorTexture,
      parser.json,
      'rgb',
      'srgb',
    ),
    sheenRoughnessTexture: authoredTexture(
      extension.sheenRoughnessTexture,
      parser.json,
      'alpha',
      'linear',
    ),
  };
  if (material.isMeshPhysicalMaterial !== true || material.sheen !== 1) {
    throw new Error(label + ' is not a sheen MeshPhysicalMaterial');
  }
  assertArrayNear(label + '/sheenColor', material.sheenColor.toArray(), authored.sheenColorFactor);
  assertNear(label + '/sheenRoughness', material.sheenRoughness, authored.sheenRoughnessFactor);
  const colorMap = actualTexture(
    label + '/sheenColorMap',
    material.sheenColorMap,
    authored.sheenColorTexture,
    parser,
  );
  const roughnessMap = actualTexture(
    label + '/sheenRoughnessMap',
    material.sheenRoughnessMap,
    authored.sheenRoughnessTexture,
    parser,
  );
  if (colorMap != null && roughnessMap != null) {
    const sameObject = material.sheenColorMap === material.sheenRoughnessMap;
    colorMap.sameThreeTextureObjectAsOtherMap = sameObject;
    roughnessMap.sameThreeTextureObjectAsOtherMap = sameObject;
  }
  return {
    authored,
    actual: {
      materialName: material.name,
      type: material.type,
      isMeshPhysicalMaterial: material.isMeshPhysicalMaterial,
      sheen: material.sheen,
      sheenColor: material.sheenColor.toArray(),
      sheenRoughness: material.sheenRoughness,
      sheenColorMap: colorMap,
      sheenRoughnessMap: roughnessMap,
    },
  };
}

function authoredTexture(mapDef, json, channelRole, colorSpace) {
  if (mapDef == null) return null;
  const transform = mapDef.extensions?.KHR_texture_transform ?? {};
  const texture = json.textures?.[mapDef.index];
  return {
    textureIndex: mapDef.index,
    sourceIndex: texture?.source,
    channelRole,
    colorSpace,
    transform: {
      offset: transform.offset ?? [0, 0],
      repeat: transform.scale ?? [1, 1],
      rotation: transform.rotation ?? 0,
      center: [0, 0],
      channel: transform.texCoord ?? mapDef.texCoord ?? 0,
    },
  };
}

function actualTexture(label, texture, authored, parser) {
  if (authored == null) {
    if (texture != null) throw new Error(label + ' must be absent');
    return null;
  }
  if (texture == null) throw new Error(label + ' must be present');
  const textureIndex = parser.associations.get(texture)?.textures;
  const sourceIndex = parser.json.textures?.[textureIndex]?.source;
  const colorSpace = texture.colorSpace === THREE.SRGBColorSpace
    ? 'srgb'
    : texture.colorSpace === THREE.NoColorSpace
      ? 'linear'
      : texture.colorSpace;
  const actual = {
    name: texture.name,
    textureIndex,
    sourceIndex,
    channelRole: authored.channelRole,
    colorSpace,
    transform: {
      offset: texture.offset.toArray(),
      repeat: texture.repeat.toArray(),
      rotation: texture.rotation,
      center: texture.center.toArray(),
      channel: texture.channel,
    },
    sampler: {
      wrapS: texture.wrapS,
      wrapT: texture.wrapT,
      magFilter: texture.magFilter,
      minFilter: texture.minFilter,
    },
  };
  if (
    actual.textureIndex !== authored.textureIndex ||
    actual.sourceIndex !== authored.sourceIndex ||
    actual.colorSpace !== authored.colorSpace ||
    actual.channelRole !== authored.channelRole
  ) {
    throw new Error(label + ' source/channel/color-space intent changed');
  }
  assertTransform(label + '/transform', actual.transform, authored.transform);
  return actual;
}

function assertTransform(label, actual, expected) {
  assertArrayNear(label + '/offset', actual.offset, expected.offset);
  assertArrayNear(label + '/repeat', actual.repeat, expected.repeat);
  assertNear(label + '/rotation', actual.rotation, expected.rotation);
  assertArrayNear(label + '/center', actual.center, expected.center);
  if (actual.channel !== expected.channel) {
    throw new Error(label + '/channel ' + actual.channel + ' != ' + expected.channel);
  }
}

function assertBounds(label, box, sphere, expected) {
  assertArrayNear(label + '/min', box.min.toArray(), expected.min);
  assertArrayNear(label + '/max', box.max.toArray(), expected.max);
  assertArrayNear(label + '/center', sphere.center.toArray(), expected.center);
  assertNear(label + '/radius', sphere.radius, expected.radius);
}

function assertArrayNear(label, actual, expected) {
  if (!Array.isArray(actual) || actual.length !== expected.length) {
    throw new Error(label + ' shape mismatch');
  }
  actual.forEach((value, index) => {
    assertNear(label + '[' + index + ']', value, expected[index]);
  });
}

function assertNear(label, actual, expected) {
  if (!Number.isFinite(actual) || Math.abs(actual - expected) > 1e-9) {
    throw new Error(label + ' ' + actual + ' != ' + expected);
  }
}

function boundsSummary(box, sphere) {
  return {
    min: box.min.toArray(),
    max: box.max.toArray(),
    center: sphere.center.toArray(),
    radius: sphere.radius,
  };
}

function disposeGltf(gltf) {
  const disposedMaterials = new Set();
  const disposedTextures = new Set();
  gltf.scene.traverse((node) => {
    if (!node.isMesh) return;
    node.geometry?.dispose();
    const materials = Array.isArray(node.material) ? node.material : [node.material];
    for (const material of materials) disposeMaterial(material);
  });
  function disposeMaterial(material) {
    if (material == null || disposedMaterials.has(material.uuid)) return;
    disposedMaterials.add(material.uuid);
    for (const value of Object.values(material)) {
      if (value?.isTexture && !disposedTextures.has(value.uuid)) {
        disposedTextures.add(value.uuid);
        value.dispose();
      }
    }
    material.dispose();
  }
}
</script>`;
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

if (process.argv[1] != null && path.resolve(process.argv[1]) === scriptPath) {
  const result = await runPlan018SheenLoaderAudit();
  console.log(
    `Plan 018 Three.js GLTFLoader audit: ` +
      `${Object.keys(result.models).length} models, all sheen inputs OK`,
  );
}
