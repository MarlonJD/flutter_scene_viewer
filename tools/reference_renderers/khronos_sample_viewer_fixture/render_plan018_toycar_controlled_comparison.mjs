import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import puppeteer from 'puppeteer';

import {
  generateControlledStudioHdr,
  loadControlledComparisonState as loadPlan015State,
} from '../threejs_material_extension_fixture/plan015_controlled_comparison_contract.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const repoRoot = path.resolve(scriptDir, '../../..');
const stateRelativePath =
  'tools/material_extension_acceptance/fixtures/' +
  'plan018_controlled_comparison_state.json';
const statePath = path.join(repoRoot, stateRelativePath);
const modelRelativePath =
  'tools/out/material_extension_acceptance/plan018_sheen_corpus/' +
  'toycar/source/ToyCar.glb';
const modelPath = path.join(repoRoot, modelRelativePath);
const glamVelvetSofaModelRelativePath =
  'tools/out/material_extension_acceptance/plan018_sheen_corpus/' +
  'glam_velvet_sofa/source/GlamVelvetSofa.glb';
const glamVelvetSofaModelPath =
  path.join(repoRoot, glamVelvetSofaModelRelativePath);
const outputRelativeRoot =
  'tools/out/material_extension_acceptance/plan018_controlled_comparison/' +
  'khronos_sample_renderer';
const outputRoot = path.join(repoRoot, outputRelativeRoot);
const mappedHdrPath = path.join(outputRoot, 'plan018_controlled_studio_mapped.hdr');
const evidencePath = path.join(outputRoot, 'evidence.json');
const glamVelvetSofaEvidencePath =
  path.join(outputRoot, 'glam_velvet_sofa_evidence.json');
const vendorModuleRelativePath =
  'tools/reference_renderers/khronos_sample_viewer_fixture/' +
  'vendor/gltf-viewer.module.js';
const vendorModulePath = path.join(repoRoot, vendorModuleRelativePath);
const wasmRelativePath =
  'tools/reference_renderers/khronos_sample_viewer_fixture/' +
  'vendor/libs/mikktspace_bg.wasm';
const wasmPath = path.join(repoRoot, wasmRelativePath);
const sheenLutRelativePath =
  'tools/reference_renderers/khronos_sample_viewer_fixture/' +
  'assets/lut_sheen_E.png';
const sheenLutPath = path.join(repoRoot, sheenLutRelativePath);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const expectedDimensions = Object.freeze({ width: 1206, height: 2622 });
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

const expectedStateSha256 =
  '385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843';
const expectedModelSha256 =
  '01a60862de55cd4b9f3acfab0b0def86451800f9c42467fcd61052c16cb9838c';
const expectedGlamVelvetSofaModelSha256 =
  '67202c74a1a33377771f162dc7fad612a6c9bd51ee15124c488e9851d9ac5266';
const expectedSourceHdrSha256 =
  'ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a';
const expectedMappedHdrSha256 =
  'bbfb66543521716d53c5aa4b812dbe0e2278e25f63c6b4801311b923e19d0ef7';
const expectedMappedHdrByteLength = 524390;
const expectedRenderer = Object.freeze({
  name: 'Khronos glTF Sample Renderer',
  sourceRepository: 'KhronosGroup/glTF-Sample-Renderer',
  sourceCommit: 'bec106e53da4a6a398aa3205f0f96563519a657e',
  sourceArchiveSha256:
    'd96863aa8ccd0cbefc0453290306c2384835bf5dfe52f4078da484d080f11955',
  viewerCommit: '6b4012c8cd58f933565401fbe4404a40380ee0fb',
  backend: 'WebGL2',
  sourceSha256: {
    gltfViewerModule: {
      path: vendorModuleRelativePath,
      sha256:
        'ca863c37b8deb6fcaa456e2a59da46311867aab2baf0d15bac48f5239b3a4f4b',
    },
    mikktspaceWasm: {
      path: wasmRelativePath,
      sha256:
        'd734e040ae6480a0d00ba08b8aaae29c2eb59c8705c38b7bc120885fc94c54e2',
    },
    sheenEnergyLut: {
      path: sheenLutRelativePath,
      sha256:
        '7f21d7754dd3a2a972d9d1298ee3e67e20c5b2f21969095d322a1bc20f8b2f04',
    },
  },
});
const expectedDirectionalLight = Object.freeze({
  injection: 'source-pinned internal getVisibleLights hook',
  publicApiExactCombinedLightAvailable: false,
  shaderModified: false,
  sourceAssetModified: false,
  authoredLightCount: 0,
  type: 'directional',
  intensity: 3,
  colorLinear: [1, 1, 1],
  travelFlutterSceneWorld: [-0.45, -0.85, -0.35],
  travelKhronosRawGltfWorldNormalized: [
    -0.43967877187142834,
    -0.8305043468682535,
    0.34197237812222203,
  ],
});
const expectedGlamVelvetSofaDirectionalLight = Object.freeze({
  ...expectedDirectionalLight,
  authoredLightCount: 1,
});
const expectedGlamVelvetSofaAuthoredSheen = Object.freeze([
  Object.freeze({
    materialIndex: 2,
    materialName: 'GlamVelvetSofa_fabric_champagne',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: Object.freeze([0.9, 0.7, 0.6]),
    sheenRoughnessFactor: 0.6,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  }),
  Object.freeze({
    materialIndex: 3,
    materialName: 'GlamVelvetSofa_fabric_navy',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: Object.freeze([0.05, 0.17, 0.5]),
    sheenRoughnessFactor: 0.6,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  }),
  Object.freeze({
    materialIndex: 4,
    materialName: 'GlamVelvetSofa_fabric_gray',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: Object.freeze([0.85, 0.9, 1]),
    sheenRoughnessFactor: 1,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  }),
  Object.freeze({
    materialIndex: 5,
    materialName: 'GlamVelvetSofa_fabric_black',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: Object.freeze([0.12, 0.12, 0.13]),
    sheenRoughnessFactor: 0.3,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  }),
  Object.freeze({
    materialIndex: 6,
    materialName: 'GlamVelvetSofa_fabric_palepink',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: Object.freeze([1, 0.9, 0.9]),
    sheenRoughnessFactor: 0.85,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  }),
]);
const expectedGlamVelvetSofaRendererMaterialAudits = Object.freeze(
  expectedGlamVelvetSofaAuthoredSheen.map((expected) =>
    Object.freeze({
      materialIndex: expected.materialIndex,
      materialName: expected.materialName,
      sheenColorFactor: expected.sheenColorFactor,
      sheenRoughnessFactor: expected.sheenRoughnessFactor,
      sheenColorTexture: null,
      sheenRoughnessTexture: null,
    }),
  ),
);
const expectedGlamVelvetSofaSceneSheen = Object.freeze({
  materialIndex: 3,
  materialName: 'GlamVelvetSofa_fabric_navy',
  sheenColorFactor: Object.freeze([0.05, 0.17, 0.5]),
  sheenRoughnessFactor: 0.6,
});
const cameraWorldMatrices = Object.freeze({
  close: [
    -0.8191520442889918, 0, -0.573576436351046, 0,
    -0.21949819938655477, 0.9238795325112867, 0.31347591593739144, 0,
    0.5299155298754943, 0.3826834323650898, -0.7567978077333787, 0,
    0.13608483103483424, 0.08943138180507922, -0.19188377384089728, 1,
  ],
  grazing: [
    -0.3420201433256689, 0, 0.9396926207859083, 0,
    0.12265449964846553, 0.9914448613738105, 0.04464258697085585, 0,
    -0.9316534201490776, 0.1305261922200516, -0.3390941135865686, 0,
    -0.23449150777715316, 0.025497684488703973, -0.08597627923890486, 1,
  ],
  context: [
    -0.7071067811865476, 0, -0.7071067811865474, 0,
    -0.2988362387301198, 0.9063077870366498, 0.29883623873011983, 0,
    0.6408563820557884, 0.42261826174069944, -0.6408563820557887, 0,
    0.18191814339498086, 0.1170341921564537, -0.18019177829922697, 1,
  ],
});
const glamVelvetSofaCameraWorldMatrices = Object.freeze({
  close: [
    -0.8191520442889917, 0, -0.5735764363510463, 0,
    -0.21949819938655485, 0.9238795325112867, 0.3134759159373914, 0,
    0.5299155298754944, 0.3826834323650898, -0.7567978077333785, 0,
    3.121613314956088, 2.768151214951412, -4.5984673295256275, 1,
  ],
  grazing: [
    -0.34202014332566893, 0, 0.9396926207859084, 0,
    0.12265449964846555, 0.9914448613738105, 0.04464258697085586, 0,
    -0.9316534201490775, 0.1305261922200516, -0.33909411358656855, 0,
    -5.542638204698064, 1.2733508833750504, -2.122299601197924, 1,
  ],
});

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function loadFrozenState() {
  const bytes = fs.readFileSync(statePath);
  if (sha256(bytes) !== expectedStateSha256) {
    throw new Error('Plan 018 frozen state hash changed');
  }
  const state = JSON.parse(bytes.toString('utf8'));
  if (
    state.name !== 'plan018_khr_materials_sheen_controlled_comparison' ||
    JSON.stringify(state.renderPasses) !==
      JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Plan 018 frozen state contract changed');
  }
  return state;
}

export function buildPlan018KhronosToycarCaptureInventory(state) {
  if (
    state?.name !== 'plan018_khr_materials_sheen_controlled_comparison' ||
    state.models?.toycar?.context?.mode !== 'full-scene' ||
    JSON.stringify(state.renderPasses) !==
      JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Khronos ToyCar inventory requires the frozen Plan 018 state');
  }
  const inventory = [];
  for (const view of ['close', 'grazing', 'context']) {
    for (const pass of state.renderPasses) {
      inventory.push({
        modelId: 'toycar',
        view,
        pass,
        fileName: `toycar_${view}_${pass}.png`,
      });
    }
  }
  return inventory;
}

export function buildPlan018KhronosGlamVelvetSofaCaptureInventory(state) {
  if (
    state?.name !== 'plan018_khr_materials_sheen_controlled_comparison' ||
    JSON.stringify(state.models?.glam_velvet_sofa?.sheenMaterialIndices) !==
      JSON.stringify([2, 3, 4, 5, 6]) ||
    JSON.stringify(state.renderPasses) !==
      JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error(
      'Khronos GlamVelvetSofa inventory requires the frozen Plan 018 state',
    );
  }
  const inventory = [];
  for (const view of ['close', 'grazing']) {
    for (const pass of state.renderPasses) {
      inventory.push({
        modelId: 'glam_velvet_sofa',
        view,
        pass,
        fileName: `glam_velvet_sofa_${view}_${pass}.png`,
      });
    }
  }
  return inventory;
}

export async function runPlan018KhronosToycarControlledReferenceCapture({
  writeEvidence = true,
} = {}) {
  const state = loadFrozenState();
  const inventory = buildPlan018KhronosToycarCaptureInventory(state);
  assertPinnedInputs();
  const authored = inspectToycarAuthoredSheen();

  const sourceHdr = generateControlledStudioHdr(loadPlan015State());
  if (sha256(sourceHdr) !== expectedSourceHdrSha256) {
    throw new Error('Plan 018 controlled source HDR bytes changed');
  }
  const mappedHdr = mirrorRgbeColumns(
    sourceHdr,
    state.environment.width,
    state.environment.height,
  );
  if (
    mappedHdr.length !== expectedMappedHdrByteLength ||
    sha256(mappedHdr) !== expectedMappedHdrSha256
  ) {
    throw new Error('Plan 018 Khronos HDR coordinate mapping changed');
  }
  fs.mkdirSync(outputRoot, { recursive: true });
  fs.writeFileSync(mappedHdrPath, mappedHdr);

  const routes = new Map([
    ['/vendor/gltf-viewer.module.js', vendorModulePath],
    ['/vendor/libs/mikktspace_bg.wasm', wasmPath],
    ['/assets/lut_sheen_E.png', sheenLutPath],
    ['/model/ToyCar.glb', modelPath],
    ['/environment/controlled-mapped.hdr', mappedHdrPath],
  ]);
  let origin = '';
  const server = http.createServer((request, response) => {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    if (url.pathname === '/runner.html') {
      response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      response.end(khronosRunnerHtml());
      return;
    }
    if (url.pathname === '/favicon.ico') {
      response.writeHead(204);
      response.end();
      return;
    }
    const filePath = routes.get(url.pathname);
    if (filePath == null) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    serveFile(response, filePath);
  });
  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-khronos-capture-'),
  );
  let browser;
  let page;
  let disposed = false;
  let primaryError;
  try {
    await listenLocalOnly(server);
    origin = `http://127.0.0.1:${server.address().port}`;
    const executablePath =
      process.env.PUPPETEER_EXECUTABLE_PATH ??
      (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
    browser = await puppeteer.launch({
      headless: true,
      executablePath,
      userDataDir: profilePath,
      args: [
        '--disable-background-networking',
        '--disable-component-update',
        '--disable-default-apps',
        '--disable-gpu-sandbox',
        '--no-first-run',
        '--no-default-browser-check',
      ],
    });
    page = await browser.newPage();
    page.setDefaultTimeout(120000);
    page.on('console', (message) => {
      console.log(`[khronos:${message.type()}] ${message.text()}`);
    });
    page.on('pageerror', (error) => {
      console.error(`[khronos:pageerror] ${error.message}`);
    });
    await page.setRequestInterception(true);
    page.on('request', (request) => {
      const requestUrl = request.url();
      if (requestUrl.startsWith(`${origin}/`) || requestUrl === 'about:blank') {
        request.continue();
      } else {
        request.abort('blockedbyclient');
      }
    });
    await page.setViewport({
      width: state.viewport.logicalWidth,
      height: state.viewport.logicalHeight,
      deviceScaleFactor: state.viewport.devicePixelRatio,
    });
    await page.goto(`${origin}/runner.html`, { waitUntil: 'networkidle0' });
    await page.waitForFunction(
      'typeof globalThis.initializePlan018Khronos === "function"',
    );
    const rendererFacts = await page.evaluate(
      (configuration) => globalThis.initializePlan018Khronos(configuration),
      {
        moduleCommit: expectedRenderer.sourceCommit,
        modelUrl: `${origin}/model/ToyCar.glb`,
        environmentUrl: `${origin}/environment/controlled-mapped.hdr`,
        sheenLutUrl: 'assets/lut_sheen_E.png',
        libsUrl: `${origin}/vendor/libs/`,
        dimensions: expectedDimensions,
        clearColor: [0x12 / 255, 0x11 / 255, 0x18 / 255, 1],
        directionalLight: expectedDirectionalLight,
        camera: state.camera,
      },
    );
    assertRendererFacts(rendererFacts, authored);

    const captures = [];
    for (const record of inventory) {
      const flutterSceneWorld =
        record.view === 'context'
          ? state.models.toycar.context.camera
          : state.models.toycar.cameras[record.view];
      const result = await page.evaluate(
        (configuration) => globalThis.renderPlan018Khronos(configuration),
        {
          record,
          flutterSceneWorld,
          worldMatrix: cameraWorldMatrices[record.view],
          directionalLight: expectedDirectionalLight,
          camera: state.camera,
          environmentIntensity: state.environment.intensity,
        },
      );
      const bytes = decodePng(result.dataUrl);
      const dimensions = pngDimensions(bytes);
      if (
        dimensions.width !== expectedDimensions.width ||
        dimensions.height !== expectedDimensions.height
      ) {
        throw new Error(`Khronos capture dimensions changed: ${record.fileName}`);
      }
      const artifactPath = path.join(outputRoot, record.fileName);
      fs.writeFileSync(artifactPath, bytes);
      captures.push({
        modelId: record.modelId,
        view: record.view,
        pass: record.pass,
        path: path.relative(repoRoot, artifactPath),
        sha256: sha256(bytes),
        byteLength: bytes.length,
        dimensions,
        camera: result.camera,
        passState: result.passState,
      });
      console.log(`Plan 018 Khronos capture: ${record.fileName} OK`);
    }
    await page.evaluate(() => globalThis.disposePlan018Khronos());
    disposed = true;

    const evidence = {
      schemaVersion: 1,
      status: 'verified locally',
      scope:
        'pinned Khronos glTF Sample Renderer ToyCar ' +
        'direction/conformance evidence',
      comparisonBoundary: 'direction/conformance-only',
      claimBoundary:
        'Reference output establishes direction/conformance evidence only; ' +
        'it does not establish pixel parity or Flutter target capability.',
      sourceState: stateRelativePath,
      stateSha256: expectedStateSha256,
      renderer: {
        ...expectedRenderer,
        browser: await browser.version(),
        backendFacts: rendererFacts.backendFacts,
        renderedPixels: true,
        host: {
          platform: process.platform,
          release: os.release(),
          architecture: process.arch,
        },
      },
      toycar: {
        modelId: 'toycar',
        name: 'ToyCar',
        path: modelRelativePath,
        sha256: expectedModelSha256,
        authoredSheen: authored,
      },
      environment: {
        sourceSha256: expectedSourceHdrSha256,
        mappedPath: path.relative(repoRoot, mappedHdrPath),
        mappedSha256: expectedMappedHdrSha256,
        mappedByteLength: expectedMappedHdrByteLength,
        coordinateMapping: 'mirrorRgbeColumns',
        intensity: 1,
        rotationDegrees: 0,
        skyboxShown: false,
        sheenEnergyLut: {
          path: sheenLutRelativePath,
          sha256: expectedRenderer.sourceSha256.sheenEnergyLut.sha256,
          runtimeBoundary:
            'Current source uploads the sRGB-encoded PNG as linear GL.RGBA; ' +
            'this behavior is retained and disclosed, not treated as an oracle.',
        },
      },
      rendererMapping: {
        directionalLight: expectedDirectionalLight,
        output: {
          requestedColorSpace: 'sRGB',
          actualTransfer: 'renderer-native pow(linear, 1/2.2)',
          toneMapping: 'Khronos PBR Neutral',
        },
        ambientOcclusion:
          'ToyCar authored occlusion remains enabled; current renderer has no ' +
          'equivalent global AO-disable control and no material mutation was applied.',
      },
      rendererAudit: rendererFacts,
      captureInventory: inventory,
      captures,
      cleanupContract: {
        pageRenderer:
          'WebGL context explicitly lost before browser closure; pinned ' +
          'renderer.destroy is not called because its current program cleanup ' +
          'uses an invalid this.deleteProgram receiver.',
        browser: 'closed or process-killed in finally',
        server: '127.0.0.1 ephemeral listener closed in finally',
        profile: 'unique temporary profile removed in finally',
      },
    };
    validatePlan018KhronosToycarCaptureEvidence(evidence);
    if (writeEvidence) {
      fs.writeFileSync(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`);
    }
    return evidence;
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    if (page != null && !page.isClosed() && !disposed) {
      try {
        await page.evaluate(() => globalThis.disposePlan018Khronos?.());
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (browser != null) {
      try {
        await closeBrowserWithBackstop(browser);
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (server.listening) {
      try {
        server.closeAllConnections?.();
        await new Promise((resolve, reject) => {
          server.close((error) => (error == null ? resolve() : reject(error)));
        });
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    try {
      fs.rmSync(profilePath, { recursive: true, force: true });
    } catch (error) {
      cleanupErrors.push(error);
    }
    if (cleanupErrors.length !== 0 && primaryError == null) {
      throw new AggregateError(cleanupErrors, 'Khronos capture cleanup failed');
    }
  }
}

export async function runPlan018KhronosGlamVelvetSofaControlledReferenceCapture({
  writeEvidence = true,
} = {}) {
  const state = loadFrozenState();
  const inventory = buildPlan018KhronosGlamVelvetSofaCaptureInventory(state);
  assertPinnedInputs();
  assertPinnedGlamVelvetSofaInputs();
  const authored = inspectGlamVelvetSofaAuthoredSheen();

  const sourceHdr = generateControlledStudioHdr(loadPlan015State());
  if (sha256(sourceHdr) !== expectedSourceHdrSha256) {
    throw new Error('Plan 018 controlled source HDR bytes changed');
  }
  const mappedHdr = mirrorRgbeColumns(
    sourceHdr,
    state.environment.width,
    state.environment.height,
  );
  if (
    mappedHdr.length !== expectedMappedHdrByteLength ||
    sha256(mappedHdr) !== expectedMappedHdrSha256
  ) {
    throw new Error('Plan 018 Khronos HDR coordinate mapping changed');
  }
  fs.mkdirSync(outputRoot, { recursive: true });
  fs.writeFileSync(mappedHdrPath, mappedHdr);

  const routes = new Map([
    ['/vendor/gltf-viewer.module.js', vendorModulePath],
    ['/vendor/libs/mikktspace_bg.wasm', wasmPath],
    ['/assets/lut_sheen_E.png', sheenLutPath],
    ['/model/GlamVelvetSofa.glb', glamVelvetSofaModelPath],
    ['/environment/controlled-mapped.hdr', mappedHdrPath],
  ]);
  let origin = '';
  const server = http.createServer((request, response) => {
    const url = new URL(request.url ?? '/', 'http://127.0.0.1');
    if (url.pathname === '/runner.html') {
      response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      response.end(khronosRunnerHtml());
      return;
    }
    if (url.pathname === '/favicon.ico') {
      response.writeHead(204);
      response.end();
      return;
    }
    const filePath = routes.get(url.pathname);
    if (filePath == null) {
      response.writeHead(404);
      response.end('Not found');
      return;
    }
    serveFile(response, filePath);
  });
  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-khronos-capture-'),
  );
  let browser;
  let page;
  let disposed = false;
  let primaryError;
  try {
    await listenLocalOnly(server);
    origin = `http://127.0.0.1:${server.address().port}`;
    const executablePath =
      process.env.PUPPETEER_EXECUTABLE_PATH ??
      (fs.existsSync(systemChromePath) ? systemChromePath : undefined);
    browser = await puppeteer.launch({
      headless: true,
      executablePath,
      userDataDir: profilePath,
      args: [
        '--disable-background-networking',
        '--disable-component-update',
        '--disable-default-apps',
        '--disable-gpu-sandbox',
        '--no-first-run',
        '--no-default-browser-check',
      ],
    });
    page = await browser.newPage();
    page.setDefaultTimeout(120000);
    page.on('console', (message) => {
      console.log(`[khronos:${message.type()}] ${message.text()}`);
    });
    page.on('pageerror', (error) => {
      console.error(`[khronos:pageerror] ${error.message}`);
    });
    await page.setRequestInterception(true);
    page.on('request', (request) => {
      const requestUrl = request.url();
      if (requestUrl.startsWith(`${origin}/`) || requestUrl === 'about:blank') {
        request.continue();
      } else {
        request.abort('blockedbyclient');
      }
    });
    await page.setViewport({
      width: state.viewport.logicalWidth,
      height: state.viewport.logicalHeight,
      deviceScaleFactor: state.viewport.devicePixelRatio,
    });
    await page.goto(`${origin}/runner.html`, { waitUntil: 'networkidle0' });
    await page.waitForFunction(
      'typeof globalThis.initializePlan018Khronos === "function"',
    );
    const rendererFacts = await page.evaluate(
      (configuration) => globalThis.initializePlan018Khronos(configuration),
      {
        moduleCommit: expectedRenderer.sourceCommit,
        modelUrl: `${origin}/model/GlamVelvetSofa.glb`,
        modelLabel: 'GlamVelvetSofa',
        environmentUrl: `${origin}/environment/controlled-mapped.hdr`,
        sheenLutUrl: 'assets/lut_sheen_E.png',
        libsUrl: `${origin}/vendor/libs/`,
        dimensions: expectedDimensions,
        clearColor: [0x12 / 255, 0x11 / 255, 0x18 / 255, 1],
        directionalLight: expectedGlamVelvetSofaDirectionalLight,
        authoredLightCount:
          expectedGlamVelvetSofaDirectionalLight.authoredLightCount,
        authoredSheenMaterials: authored,
        sceneMaterialIndex: expectedGlamVelvetSofaSceneSheen.materialIndex,
        ambientOcclusionBoundary:
          'GlamVelvetSofa authored ambient occlusion and inactive material ' +
          'variants remain unchanged; authored punctual lights are recorded ' +
          'and suppressed for the controlled studio-light comparison.',
        camera: state.camera,
      },
    );
    assertGlamVelvetSofaRendererFacts(rendererFacts, authored);

    const captures = [];
    for (const record of inventory) {
      const flutterSceneWorld =
        state.models.glam_velvet_sofa.cameras[record.view];
      const result = await page.evaluate(
        (configuration) => globalThis.renderPlan018Khronos(configuration),
        {
          record,
          flutterSceneWorld,
          worldMatrix: glamVelvetSofaCameraWorldMatrices[record.view],
          directionalLight: expectedGlamVelvetSofaDirectionalLight,
          camera: state.camera,
          environmentIntensity: state.environment.intensity,
        },
      );
      const bytes = decodePng(result.dataUrl);
      const dimensions = pngDimensions(bytes);
      if (
        dimensions.width !== expectedDimensions.width ||
        dimensions.height !== expectedDimensions.height
      ) {
        throw new Error(`Khronos capture dimensions changed: ${record.fileName}`);
      }
      const artifactPath = path.join(outputRoot, record.fileName);
      fs.writeFileSync(artifactPath, bytes);
      captures.push({
        modelId: record.modelId,
        view: record.view,
        pass: record.pass,
        path: path.relative(repoRoot, artifactPath),
        sha256: sha256(bytes),
        byteLength: bytes.length,
        dimensions,
        camera: result.camera,
        passState: result.passState,
      });
      console.log(`Plan 018 Khronos capture: ${record.fileName} OK`);
    }
    await page.evaluate(() => globalThis.disposePlan018Khronos());
    disposed = true;

    const evidence = {
      schemaVersion: 1,
      status: 'verified locally',
      scope:
        'pinned Khronos glTF Sample Renderer GlamVelvetSofa ' +
        'direction/conformance evidence',
      comparisonBoundary: 'direction/conformance-only',
      claimBoundary:
        'Reference output establishes direction/conformance evidence only; ' +
        'it does not establish pixel parity or Flutter target capability.',
      sourceState: stateRelativePath,
      stateSha256: expectedStateSha256,
      renderer: {
        ...expectedRenderer,
        browser: await browser.version(),
        backendFacts: rendererFacts.backendFacts,
        renderedPixels: true,
        host: {
          platform: process.platform,
          release: os.release(),
          architecture: process.arch,
        },
      },
      glamVelvetSofa: {
        modelId: 'glam_velvet_sofa',
        name: 'GlamVelvetSofa',
        path: glamVelvetSofaModelRelativePath,
        sha256: expectedGlamVelvetSofaModelSha256,
        authoredSheen: authored,
        authoredLightCount:
          expectedGlamVelvetSofaDirectionalLight.authoredLightCount,
        sceneUsedSheen: expectedGlamVelvetSofaSceneSheen,
      },
      environment: {
        sourceSha256: expectedSourceHdrSha256,
        mappedPath: path.relative(repoRoot, mappedHdrPath),
        mappedSha256: expectedMappedHdrSha256,
        mappedByteLength: expectedMappedHdrByteLength,
        coordinateMapping: 'mirrorRgbeColumns',
        intensity: 1,
        rotationDegrees: 0,
        skyboxShown: false,
        sheenEnergyLut: {
          path: sheenLutRelativePath,
          sha256: expectedRenderer.sourceSha256.sheenEnergyLut.sha256,
          runtimeBoundary:
            'Current source uploads the sRGB-encoded PNG as linear GL.RGBA; ' +
            'this behavior is retained and disclosed, not treated as an oracle.',
        },
      },
      rendererMapping: {
        directionalLight: expectedGlamVelvetSofaDirectionalLight,
        authoredLightsBoundary:
          'The default GLB authors one directional light; authored punctual ' +
          'lights are recorded and suppressed before rendering so the ' +
          'controlled studio key is the only active direct light.',
        output: {
          requestedColorSpace: 'sRGB',
          actualTransfer: 'renderer-native pow(linear, 1/2.2)',
          toneMapping: 'Khronos PBR Neutral',
        },
        ambientOcclusion:
          'GlamVelvetSofa authored occlusion remains enabled; no material ' +
          'mutation was applied.',
      },
      rendererAudit: rendererFacts,
      captureInventory: inventory,
      captures,
      cleanupContract: {
        pageRenderer:
          'WebGL context explicitly lost before browser closure; pinned ' +
          'renderer.destroy is not called because its current program cleanup ' +
          'uses an invalid this.deleteProgram receiver.',
        browser: 'closed or process-killed in finally',
        server: '127.0.0.1 ephemeral listener closed in finally',
        profile: 'unique temporary profile removed in finally',
      },
    };
    validatePlan018KhronosGlamVelvetSofaCaptureEvidence(evidence);
    if (writeEvidence) {
      fs.writeFileSync(
        glamVelvetSofaEvidencePath,
        `${JSON.stringify(evidence, null, 2)}\n`,
      );
    }
    return evidence;
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    if (page != null && !page.isClosed() && !disposed) {
      try {
        await page.evaluate(() => globalThis.disposePlan018Khronos?.());
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (browser != null) {
      try {
        await closeBrowserWithBackstop(browser);
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (server.listening) {
      try {
        server.closeAllConnections?.();
        await new Promise((resolve, reject) => {
          server.close((error) => (error == null ? resolve() : reject(error)));
        });
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    try {
      fs.rmSync(profilePath, { recursive: true, force: true });
    } catch (error) {
      cleanupErrors.push(error);
    }
    if (cleanupErrors.length !== 0 && primaryError == null) {
      throw new AggregateError(cleanupErrors, 'Khronos capture cleanup failed');
    }
  }
}

export function validatePlan018KhronosToycarCaptureEvidence(evidence) {
  const state = loadFrozenState();
  const inventory = buildPlan018KhronosToycarCaptureInventory(state);
  assertPinnedInputs();
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.scope !==
      'pinned Khronos glTF Sample Renderer ToyCar ' +
        'direction/conformance evidence' ||
    evidence.comparisonBoundary !== 'direction/conformance-only' ||
    evidence.sourceState !== stateRelativePath ||
    evidence.stateSha256 !== expectedStateSha256 ||
    JSON.stringify(evidence.captureInventory) !== JSON.stringify(inventory) ||
    evidence.captures?.length !== inventory.length
  ) {
    throw new Error('Khronos capture evidence identity or inventory changed');
  }
  if (
    evidence.renderer?.name !== expectedRenderer.name ||
    evidence.renderer.sourceRepository !== expectedRenderer.sourceRepository ||
    evidence.renderer.sourceCommit !== expectedRenderer.sourceCommit ||
    evidence.renderer.viewerCommit !== expectedRenderer.viewerCommit ||
    evidence.renderer.backend !== expectedRenderer.backend ||
    evidence.renderer.renderedPixels !== true ||
    JSON.stringify(evidence.renderer.sourceSha256) !==
      JSON.stringify(expectedRenderer.sourceSha256)
  ) {
    throw new Error('Khronos renderer evidence changed');
  }
  const mappedBytes = fs.readFileSync(safeEvidencePath(evidence.environment.mappedPath));
  if (
    evidence.environment.sourceSha256 !== expectedSourceHdrSha256 ||
    evidence.environment.mappedSha256 !== expectedMappedHdrSha256 ||
    evidence.environment.mappedByteLength !== expectedMappedHdrByteLength ||
    evidence.environment.coordinateMapping !== 'mirrorRgbeColumns' ||
    mappedBytes.length !== expectedMappedHdrByteLength ||
    sha256(mappedBytes) !== expectedMappedHdrSha256
  ) {
    throw new Error('Khronos mapped HDR evidence changed');
  }
  if (
    evidence.toycar?.path !== modelRelativePath ||
    evidence.toycar.sha256 !== expectedModelSha256 ||
    JSON.stringify(evidence.toycar.authoredSheen) !==
      JSON.stringify(inspectToycarAuthoredSheen()) ||
    JSON.stringify(evidence.rendererMapping?.directionalLight) !==
      JSON.stringify(expectedDirectionalLight)
  ) {
    throw new Error('Khronos ToyCar or light evidence changed');
  }
  if (
    evidence.rendererAudit?.materialAudit?.materialIndex !== 1 ||
    evidence.rendererAudit.materialAudit.materialName !== 'Fabric' ||
    evidence.rendererAudit.environment?.sheenEnergyLutConfigured !== true ||
    evidence.rendererAudit.environment.initializedBeforeFirstRender !== false
  ) {
    throw new Error('Khronos renderer audit evidence changed');
  }
  for (const view of ['close', 'grazing', 'context']) {
    const hashes = evidence.captures
      .filter((capture) => capture.view === view)
      .map((capture) => capture.sha256);
    if (hashes.length !== 3 || new Set(hashes).size !== 3) {
      throw new Error(`Khronos ${view} pixel passes are not distinct`);
    }
  }
  for (const [index, record] of inventory.entries()) {
    const capture = evidence.captures[index];
    if (
      capture?.modelId !== record.modelId ||
      capture.view !== record.view ||
      capture.pass !== record.pass ||
      path.basename(capture.path) !== record.fileName
    ) {
      throw new Error(`Khronos capture order changed at index ${index}`);
    }
    const bytes = fs.readFileSync(safeEvidencePath(capture.path));
    const dimensions = pngDimensions(bytes);
    if (
      bytes.length !== capture.byteLength ||
      sha256(bytes) !== capture.sha256 ||
      JSON.stringify(dimensions) !== JSON.stringify(expectedDimensions) ||
      JSON.stringify(capture.dimensions) !== JSON.stringify(expectedDimensions)
    ) {
      throw new Error(`Khronos PNG evidence changed: ${record.fileName}`);
    }
    const expectedCamera =
      record.view === 'context'
        ? state.models.toycar.context.camera
        : state.models.toycar.cameras[record.view];
    if (
      JSON.stringify(capture.camera?.flutterSceneWorld) !==
        JSON.stringify(expectedCamera) ||
      !arraysNear(
        capture.camera?.khronosRawGltfWorld?.worldMatrix,
        cameraWorldMatrices[record.view],
        1e-7,
      )
    ) {
      throw new Error(`Khronos camera evidence changed: ${record.fileName}`);
    }
    const wantsDirect = record.pass !== 'iblOnly';
    const wantsIbl = record.pass !== 'directOnly';
    if (
      capture.passState?.directEnabled !== wantsDirect ||
      capture.passState.iblEnabled !== wantsIbl ||
      capture.passState.directionalLight?.injected !== wantsDirect ||
      capture.passState.directionalLight?.visibleLightCount !==
        (wantsDirect ? 1 : 0) ||
      capture.passState.directionalLight?.intensity !== (wantsDirect ? 3 : 0) ||
      !validDirectionalLightAudit(
        capture.passState.directionalLight,
        wantsDirect,
      ) ||
      !validFabricShaderAudit(
        capture.passState.fabricShader,
        wantsDirect,
        wantsIbl,
      ) ||
      capture.passState.environment?.configured !== true ||
      capture.passState.environment?.intensity !== (wantsIbl ? 1 : 0) ||
      capture.passState.environment?.sheenEnergyLutInitialized !== true ||
      capture.passState.toneMapping !== 'Khronos PBR Neutral' ||
      capture.passState.requestedOutputColorSpace !== 'sRGB' ||
      capture.passState.actualOutputTransfer !==
        'renderer-native pow(linear, 1/2.2)'
    ) {
      throw new Error(`Khronos pass-state evidence changed: ${record.fileName}`);
    }
  }
}

export function validatePlan018KhronosGlamVelvetSofaCaptureEvidence(evidence) {
  const state = loadFrozenState();
  const inventory = buildPlan018KhronosGlamVelvetSofaCaptureInventory(state);
  assertPinnedInputs();
  assertPinnedGlamVelvetSofaInputs();
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.scope !==
      'pinned Khronos glTF Sample Renderer GlamVelvetSofa ' +
        'direction/conformance evidence' ||
    evidence.comparisonBoundary !== 'direction/conformance-only' ||
    evidence.sourceState !== stateRelativePath ||
    evidence.stateSha256 !== expectedStateSha256 ||
    JSON.stringify(evidence.captureInventory) !== JSON.stringify(inventory) ||
    evidence.captures?.length !== inventory.length
  ) {
    throw new Error('Khronos capture evidence identity or inventory changed');
  }
  if (
    evidence.renderer?.name !== expectedRenderer.name ||
    evidence.renderer.sourceRepository !== expectedRenderer.sourceRepository ||
    evidence.renderer.sourceCommit !== expectedRenderer.sourceCommit ||
    evidence.renderer.viewerCommit !== expectedRenderer.viewerCommit ||
    evidence.renderer.backend !== expectedRenderer.backend ||
    evidence.renderer.renderedPixels !== true ||
    JSON.stringify(evidence.renderer.sourceSha256) !==
      JSON.stringify(expectedRenderer.sourceSha256)
  ) {
    throw new Error('Khronos renderer evidence changed');
  }
  const mappedBytes = fs.readFileSync(
    safeEvidencePath(evidence.environment.mappedPath),
  );
  if (
    evidence.environment.sourceSha256 !== expectedSourceHdrSha256 ||
    evidence.environment.mappedSha256 !== expectedMappedHdrSha256 ||
    evidence.environment.mappedByteLength !== expectedMappedHdrByteLength ||
    evidence.environment.coordinateMapping !== 'mirrorRgbeColumns' ||
    mappedBytes.length !== expectedMappedHdrByteLength ||
    sha256(mappedBytes) !== expectedMappedHdrSha256
  ) {
    throw new Error('Khronos mapped HDR evidence changed');
  }
  if (
    evidence.glamVelvetSofa?.path !== glamVelvetSofaModelRelativePath ||
    evidence.glamVelvetSofa.sha256 !== expectedGlamVelvetSofaModelSha256 ||
    evidence.glamVelvetSofa.authoredLightCount !==
      expectedGlamVelvetSofaDirectionalLight.authoredLightCount ||
    JSON.stringify(evidence.glamVelvetSofa.authoredSheen) !==
      JSON.stringify(inspectGlamVelvetSofaAuthoredSheen()) ||
    JSON.stringify(evidence.glamVelvetSofa.sceneUsedSheen) !==
      JSON.stringify(expectedGlamVelvetSofaSceneSheen) ||
    JSON.stringify(evidence.rendererMapping?.directionalLight) !==
      JSON.stringify(expectedGlamVelvetSofaDirectionalLight) ||
    !evidence.rendererMapping.authoredLightsBoundary?.includes('suppressed') ||
    !evidence.rendererMapping.authoredLightsBoundary?.includes(
      'controlled studio key',
    )
  ) {
    throw new Error('Khronos GlamVelvetSofa or light evidence changed');
  }
  if (
    evidence.rendererAudit?.authoredLightCount !==
      expectedGlamVelvetSofaDirectionalLight.authoredLightCount ||
    JSON.stringify(evidence.rendererAudit.materialAudits) !==
      JSON.stringify(expectedGlamVelvetSofaRendererMaterialAudits) ||
    JSON.stringify(evidence.rendererAudit.sceneMaterialAudit) !==
      JSON.stringify({
        materialIndex: expectedGlamVelvetSofaSceneSheen.materialIndex,
        materialName: expectedGlamVelvetSofaSceneSheen.materialName,
        sheenColorFactor: expectedGlamVelvetSofaSceneSheen.sheenColorFactor,
        sheenRoughnessFactor:
          expectedGlamVelvetSofaSceneSheen.sheenRoughnessFactor,
        sheenColorTexture: null,
        sheenRoughnessTexture: null,
      }) ||
    evidence.rendererAudit.environment?.sheenEnergyLutConfigured !== true ||
    evidence.rendererAudit.environment.initializedBeforeFirstRender !== false
  ) {
    throw new Error('Khronos renderer audit evidence changed');
  }
  for (const view of ['close', 'grazing']) {
    const hashes = evidence.captures
      .filter((capture) => capture.view === view)
      .map((capture) => capture.sha256);
    if (hashes.length !== 3 || new Set(hashes).size !== 3) {
      throw new Error(`Khronos ${view} pixel passes are not distinct`);
    }
  }
  for (const [index, record] of inventory.entries()) {
    const capture = evidence.captures[index];
    if (
      capture?.modelId !== record.modelId ||
      capture.view !== record.view ||
      capture.pass !== record.pass ||
      path.basename(capture.path) !== record.fileName
    ) {
      throw new Error(`Khronos capture order changed at index ${index}`);
    }
    const bytes = fs.readFileSync(safeEvidencePath(capture.path));
    const dimensions = pngDimensions(bytes);
    if (
      bytes.length !== capture.byteLength ||
      sha256(bytes) !== capture.sha256 ||
      JSON.stringify(dimensions) !== JSON.stringify(expectedDimensions) ||
      JSON.stringify(capture.dimensions) !== JSON.stringify(expectedDimensions)
    ) {
      throw new Error(`Khronos PNG evidence changed: ${record.fileName}`);
    }
    const expectedCamera = state.models.glam_velvet_sofa.cameras[record.view];
    if (
      JSON.stringify(capture.camera?.flutterSceneWorld) !==
        JSON.stringify(expectedCamera) ||
      !arraysNear(
        capture.camera?.khronosRawGltfWorld?.worldMatrix,
        glamVelvetSofaCameraWorldMatrices[record.view],
        1e-7,
      )
    ) {
      throw new Error(`Khronos camera evidence changed: ${record.fileName}`);
    }
    const wantsDirect = record.pass !== 'iblOnly';
    const wantsIbl = record.pass !== 'directOnly';
    if (
      capture.passState?.directEnabled !== wantsDirect ||
      capture.passState.iblEnabled !== wantsIbl ||
      capture.passState.directionalLight?.injected !== wantsDirect ||
      capture.passState.directionalLight?.visibleLightCount !==
        (wantsDirect ? 1 : 0) ||
      capture.passState.directionalLight?.intensity !== (wantsDirect ? 3 : 0) ||
      !validDirectionalLightAudit(
        capture.passState.directionalLight,
        wantsDirect,
      ) ||
      !validGlamVelvetSofaSceneSheenShaderAudit(
        capture.passState.sceneSheenShader,
        wantsDirect,
        wantsIbl,
      ) ||
      capture.passState.environment?.configured !== true ||
      capture.passState.environment?.intensity !== (wantsIbl ? 1 : 0) ||
      capture.passState.environment?.sheenEnergyLutInitialized !== true ||
      capture.passState.toneMapping !== 'Khronos PBR Neutral' ||
      capture.passState.requestedOutputColorSpace !== 'sRGB' ||
      capture.passState.actualOutputTransfer !==
        'renderer-native pow(linear, 1/2.2)'
    ) {
      throw new Error(`Khronos pass-state evidence changed: ${record.fileName}`);
    }
  }
}

function validDirectionalLightAudit(audit, wantsDirect) {
  if (!wantsDirect) {
    return (
      audit.sourceDirection === null &&
      audit.preparedUniform === null &&
      audit.shaderUniform === null
    );
  }
  const expectedDirection =
    expectedDirectionalLight.travelKhronosRawGltfWorldNormalized;
  return (
    arraysNear(audit.sourceDirection, expectedDirection, 1e-7) &&
    arraysNear(audit.preparedUniform?.direction, expectedDirection, 1e-7) &&
    arraysNear(audit.preparedUniform?.colorLinear, [1, 1, 1], 1e-7) &&
    audit.preparedUniform?.intensity === 3 &&
    audit.preparedUniform?.type === 0 &&
    arraysNear(audit.shaderUniform?.direction, expectedDirection, 1e-7) &&
    arraysNear(audit.shaderUniform?.colorLinear, [1, 1, 1], 1e-7) &&
    audit.shaderUniform?.intensity === 3 &&
    audit.shaderUniform?.type === 0
  );
}

function validFabricShaderAudit(audit, wantsDirect, wantsIbl) {
  if (
    audit?.materialIndex !== 1 ||
    audit.materialName !== 'Fabric' ||
    !Number.isInteger(audit.fragmentHash) ||
    typeof audit.programHash !== 'string' ||
    audit.programHash.length === 0 ||
    !Array.isArray(audit.defines) ||
    !audit.defines.includes('MATERIAL_SHEEN 1') ||
    audit.defines.includes('USE_PUNCTUAL 1') !== wantsDirect ||
    audit.defines.includes('LIGHT_COUNT 1') !== wantsDirect ||
    audit.defines.includes('USE_IBL 1') !== wantsIbl ||
    !arraysNear(audit.uniforms?.sheenColorFactor, [1, 0, 0], 1e-7) ||
    audit.uniforms?.sheenRoughnessFactor !== 0.5
  ) {
    return false;
  }
  if (!wantsDirect) {
    return audit.uniforms.directionalLight === null;
  }
  const light = audit.uniforms.directionalLight;
  return (
    arraysNear(
      light?.direction,
      expectedDirectionalLight.travelKhronosRawGltfWorldNormalized,
      1e-7,
    ) &&
    arraysNear(light?.colorLinear, [1, 1, 1], 1e-7) &&
    light?.intensity === 3 &&
    light?.type === 0
  );
}

function validGlamVelvetSofaSceneSheenShaderAudit(
  audit,
  wantsDirect,
  wantsIbl,
) {
  if (
    audit?.materialIndex !== expectedGlamVelvetSofaSceneSheen.materialIndex ||
    audit.materialName !== expectedGlamVelvetSofaSceneSheen.materialName ||
    !Number.isInteger(audit.fragmentHash) ||
    typeof audit.programHash !== 'string' ||
    audit.programHash.length === 0 ||
    !Array.isArray(audit.defines) ||
    !audit.defines.includes('MATERIAL_SHEEN 1') ||
    audit.defines.includes('USE_PUNCTUAL 1') !== wantsDirect ||
    audit.defines.includes('LIGHT_COUNT 1') !== wantsDirect ||
    audit.defines.includes('USE_IBL 1') !== wantsIbl ||
    !arraysNear(
      audit.uniforms?.sheenColorFactor,
      expectedGlamVelvetSofaSceneSheen.sheenColorFactor,
      1e-7,
    ) ||
    !Number.isFinite(audit.uniforms?.sheenRoughnessFactor) ||
    Math.abs(
      audit.uniforms.sheenRoughnessFactor -
        expectedGlamVelvetSofaSceneSheen.sheenRoughnessFactor,
    ) > 1e-7
  ) {
    return false;
  }
  if (!wantsDirect) {
    return audit.uniforms.directionalLight === null;
  }
  const light = audit.uniforms.directionalLight;
  return (
    arraysNear(
      light?.direction,
      expectedDirectionalLight.travelKhronosRawGltfWorldNormalized,
      1e-7,
    ) &&
    arraysNear(light?.colorLinear, [1, 1, 1], 1e-7) &&
    light?.intensity === 3 &&
    light?.type === 0
  );
}

function assertPinnedInputs() {
  const checks = [
    [vendorModulePath, expectedRenderer.sourceSha256.gltfViewerModule.sha256],
    [wasmPath, expectedRenderer.sourceSha256.mikktspaceWasm.sha256],
    [sheenLutPath, expectedRenderer.sourceSha256.sheenEnergyLut.sha256],
    [modelPath, expectedModelSha256],
  ];
  for (const [filePath, expected] of checks) {
    const bytes = fs.readFileSync(filePath);
    if (sha256(bytes) !== expected) {
      throw new Error(`Pinned Khronos capture input changed: ${filePath}`);
    }
  }
}

function assertPinnedGlamVelvetSofaInputs() {
  const bytes = fs.readFileSync(glamVelvetSofaModelPath);
  if (sha256(bytes) !== expectedGlamVelvetSofaModelSha256) {
    throw new Error(
      `Pinned Khronos GlamVelvetSofa input changed: ${glamVelvetSofaModelPath}`,
    );
  }
}

function inspectToycarAuthoredSheen() {
  const json = extractGlbJson(fs.readFileSync(modelPath));
  const material = json.materials?.[1];
  const sheen = material?.extensions?.KHR_materials_sheen;
  if (
    material?.name !== 'Fabric' ||
    JSON.stringify(sheen?.sheenColorFactor) !== JSON.stringify([1, 0, 0]) ||
    sheen?.sheenRoughnessFactor !== 0.5 ||
    sheen?.sheenColorTexture != null ||
    sheen?.sheenRoughnessTexture != null
  ) {
    throw new Error('ToyCar authored Fabric sheen inputs changed');
  }
  const authoredLights = json.extensions?.KHR_lights_punctual?.lights ?? [];
  if (authoredLights.length !== 0) {
    throw new Error('ToyCar unexpectedly authors punctual lights');
  }
  return {
    materialIndex: 1,
    materialName: 'Fabric',
    extension: 'KHR_materials_sheen',
    sheenColorFactor: [1, 0, 0],
    sheenRoughnessFactor: 0.5,
    sheenColorTexture: null,
    sheenRoughnessTexture: null,
  };
}

function inspectGlamVelvetSofaAuthoredSheen() {
  const json = extractGlbJson(fs.readFileSync(glamVelvetSofaModelPath));
  const authored = expectedGlamVelvetSofaAuthoredSheen.map((expected) => {
    const material = json.materials?.[expected.materialIndex];
    const sheen = material?.extensions?.KHR_materials_sheen;
    if (
      material?.name !== expected.materialName ||
      JSON.stringify(sheen?.sheenColorFactor) !==
        JSON.stringify(expected.sheenColorFactor) ||
      sheen?.sheenRoughnessFactor !== expected.sheenRoughnessFactor ||
      sheen?.sheenColorTexture != null ||
      sheen?.sheenRoughnessTexture != null
    ) {
      throw new Error('GlamVelvetSofa authored sheen inputs changed');
    }
    return {
      materialIndex: expected.materialIndex,
      materialName: expected.materialName,
      extension: 'KHR_materials_sheen',
      sheenColorFactor: [...expected.sheenColorFactor],
      sheenRoughnessFactor: expected.sheenRoughnessFactor,
      sheenColorTexture: null,
      sheenRoughnessTexture: null,
    };
  });
  const authoredLights = json.extensions?.KHR_lights_punctual?.lights ?? [];
  if (
    authoredLights.length !== 1 ||
    authoredLights[0].type !== 'directional' ||
    authoredLights[0].intensity !== 3
  ) {
    throw new Error('GlamVelvetSofa authored light inputs changed');
  }
  return authored;
}

function extractGlbJson(bytes) {
  if (bytes.toString('utf8', 0, 4) !== 'glTF') {
    throw new Error('Expected a binary glTF container');
  }
  const version = bytes.readUInt32LE(4);
  const declaredLength = bytes.readUInt32LE(8);
  const jsonLength = bytes.readUInt32LE(12);
  const jsonType = bytes.toString('ascii', 16, 20);
  if (
    version !== 2 ||
    declaredLength !== bytes.length ||
    jsonType !== 'JSON' ||
    20 + jsonLength > bytes.length
  ) {
    throw new Error('ToyCar GLB header or JSON chunk changed');
  }
  return JSON.parse(bytes.toString('utf8', 20, 20 + jsonLength).trimEnd());
}

function mirrorRgbeColumns(bytes, width, height) {
  const pixelByteLength = width * height * 4;
  const headerByteLength = bytes.length - pixelByteLength;
  if (headerByteLength <= 0) {
    throw new Error('Controlled HDR is not the expected flat RGBE payload');
  }
  const mapped = Buffer.from(bytes);
  for (let y = 0; y < height; y += 1) {
    const rowStart = headerByteLength + y * width * 4;
    for (let x = 0; x < Math.floor(width / 2); x += 1) {
      const left = rowStart + x * 4;
      const right = rowStart + (width - 1 - x) * 4;
      for (let channel = 0; channel < 4; channel += 1) {
        const value = mapped[left + channel];
        mapped[left + channel] = mapped[right + channel];
        mapped[right + channel] = value;
      }
    }
  }
  return mapped;
}

function khronosRunnerHtml() {
  return `<!doctype html>
<meta charset="utf-8">
<style>
html, body { margin: 0; overflow: hidden; background: #121118; }
canvas { display: block; width: 402px; height: 874px; }
</style>
<canvas id="capture"></canvas>
<script type="module">
import {
  GltfState,
  GltfView,
  ResourceLoader,
} from '/vendor/gltf-viewer.module.js';

const canvas = document.getElementById('capture');
const runtime = {
  gl: null,
  view: null,
  state: null,
  key: null,
  directEnabled: false,
  lastPbrFragmentSelection: null,
  fabricShader: null,
  disposed: false,
};

globalThis.initializePlan018Khronos = async (configuration) => {
  canvas.width = configuration.dimensions.width;
  canvas.height = configuration.dimensions.height;
  const gl = canvas.getContext('webgl2', {
    alpha: false,
    antialias: true,
    premultipliedAlpha: false,
    preserveDrawingBuffer: true,
  });
  if (gl == null) throw new Error('WebGL2 unavailable');
  const colorBufferFloat = gl.getExtension('EXT_color_buffer_float');
  const floatLinear = gl.getExtension('OES_texture_float_linear');
  if (colorBufferFloat == null || floatLinear == null) {
    throw new Error('Required float environment extensions unavailable');
  }
  const view = new GltfView(gl);
  const loader = new ResourceLoader(view, configuration.libsUrl);
  const gltf = await loader.loadGltf(configuration.modelUrl);
  const environment = await loader.loadEnvironment(
    configuration.environmentUrl,
    { lut_sheen_E_file: configuration.sheenLutUrl },
  );
  if (environment == null || environment.iblIntensityScale !== 1) {
    throw new Error('Controlled environment failed exact scale preflight');
  }
  const modelLabel = configuration.modelLabel ?? 'ToyCar';
  const expectedAuthoredLightCount =
    configuration.authoredLightCount ??
    configuration.directionalLight.authoredLightCount;
  const expectedAuthoredSheenMaterials =
    configuration.authoredSheenMaterials ?? [{
      materialIndex: 1,
      materialName: 'Fabric',
      extension: 'KHR_materials_sheen',
      sheenColorFactor: [1, 0, 0],
      sheenRoughnessFactor: 0.5,
      sheenColorTexture: null,
      sheenRoughnessTexture: null,
    }];
  const sceneMaterialIndex =
    configuration.sceneMaterialIndex ??
    expectedAuthoredSheenMaterials[0].materialIndex;
  const state = view.createState();
  state.gltf = gltf;
  state.environment = environment;
  state.sceneIndex = Number.isInteger(gltf.scene) ? gltf.scene : 0;
  state.cameraNodeIndex = undefined;
  const parameters = state.renderingParameters;
  parameters.enabledExtensions.KHR_materials_sheen = true;
  parameters.exposure = 1;
  parameters.usePunctual = true;
  parameters.useIBL = true;
  parameters.iblIntensity = 1;
  parameters.renderEnvironmentMap = false;
  parameters.blurEnvironmentMap = false;
  parameters.environmentRotation = 0;
  parameters.useDirectionalLightsWithDisabledIBL = false;
  parameters.toneMap = GltfState.ToneMaps.KHR_PBR_NEUTRAL;
  parameters.clearColor = configuration.clearColor;

  const scene = gltf.scenes[state.sceneIndex];
  if (scene == null) throw new Error(modelLabel + ' default scene unavailable');
  const originalGetVisibleLights = view.renderer.getVisibleLights.bind(
    view.renderer,
  );
  const authoredLights = originalGetVisibleLights(gltf, scene.nodes);
  if (authoredLights.length !== expectedAuthoredLightCount) {
    throw new Error(modelLabel + ' authored light count changed');
  }
  const key = view.renderer.lightKey;
  key.type = configuration.directionalLight.type;
  key.color = [...configuration.directionalLight.colorLinear];
  key.intensity = configuration.directionalLight.intensity;
  key.direction.set(
    configuration.directionalLight.travelKhronosRawGltfWorldNormalized,
  );
  view.renderer.getVisibleLights = () =>
    runtime.directEnabled ? [[null, key]] : [];

  const materialAudits = expectedAuthoredSheenMaterials.map((expected) => {
    const material = gltf.materials[expected.materialIndex];
    const sheen = material?.extensions?.KHR_materials_sheen;
    const audit = {
      materialIndex: expected.materialIndex,
      materialName: material?.name,
      sheenColorFactor: Array.from(sheen?.sheenColorFactor ?? []),
      sheenRoughnessFactor: sheen?.sheenRoughnessFactor,
      sheenColorTexture: sheen?.sheenColorTexture == null ? null : 'present',
      sheenRoughnessTexture:
        sheen?.sheenRoughnessTexture == null ? null : 'present',
    };
    if (
      audit.materialName !== expected.materialName ||
      JSON.stringify(audit.sheenColorFactor) !==
        JSON.stringify(expected.sheenColorFactor) ||
      audit.sheenRoughnessFactor !== expected.sheenRoughnessFactor ||
      audit.sheenColorTexture !==
        (expected.sheenColorTexture == null ? null : 'present') ||
      audit.sheenRoughnessTexture !==
        (expected.sheenRoughnessTexture == null ? null : 'present')
    ) {
      throw new Error(modelLabel + ' authored sheen inputs changed');
    }
    return audit;
  });
  const materialAudit = materialAudits.find(
    (audit) => audit.materialIndex === sceneMaterialIndex,
  );
  if (materialAudit == null) {
    throw new Error(modelLabel + ' scene-used sheen material is not audited');
  }
  const sheenEnergyTexture =
    environment.textures[environment.sheenELUT.index];
  if (sheenEnergyTexture == null) {
    throw new Error('Khronos sheen energy LUT texture unavailable');
  }

  const originalSelectShader = view.renderer.shaderCache.selectShader.bind(
    view.renderer.shaderCache,
  );
  view.renderer.shaderCache.selectShader = (identifier, defines) => {
    const hash = originalSelectShader(identifier, defines);
    if (identifier === 'pbr.frag') {
      runtime.lastPbrFragmentSelection = {
        fragmentHash: hash,
        defines: [...defines],
      };
    }
    return hash;
  };
  const originalDrawPrimitive = view.renderer.drawPrimitive.bind(view.renderer);
  view.renderer.drawPrimitive = (...args) => {
    const result = originalDrawPrimitive(...args);
    const primitive = args[2];
    const renderpassConfiguration = args[1];
    if (
      primitive?.material === materialAudit.materialIndex &&
      renderpassConfiguration?.scatter !== true
    ) {
      const shader = view.renderer.shader;
      const selection = runtime.lastPbrFragmentSelection;
      if (shader?.program == null || selection == null) {
        throw new Error('Khronos scene sheen shader audit unavailable');
      }
      runtime.fabricShader = {
        materialIndex: materialAudit.materialIndex,
        materialName: materialAudit.materialName,
        fragmentHash: selection.fragmentHash,
        programHash: String(shader.hash),
        defines: [...selection.defines],
        uniforms: {
          sheenColorFactor: readShaderUniform(
            shader,
            'u_SheenColorFactor',
          ),
          sheenRoughnessFactor: readShaderUniform(
            shader,
            'u_SheenRoughnessFactor',
          ),
          directionalLight: runtime.directEnabled
            ? readDirectionalLightShaderUniform(shader)
            : null,
        },
      };
    }
    return result;
  };

  runtime.gl = gl;
  runtime.view = view;
  runtime.state = state;
  runtime.key = key;
  return {
    backendFacts: {
      isWebGL2: gl instanceof WebGL2RenderingContext,
      contextVersion: gl.getParameter(gl.VERSION),
      shadingLanguageVersion: gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
      vendor: gl.getParameter(gl.VENDOR),
      renderer: gl.getParameter(gl.RENDERER),
      colorBufferFloat: colorBufferFloat != null,
      floatLinear: floatLinear != null,
      renderedPixels: true,
    },
    materialAudit,
    materialAudits,
    sceneMaterialAudit: materialAudit,
    authoredLightCount: authoredLights.length,
    environment: {
      configured: true,
      iblIntensityScale: environment.iblIntensityScale,
      sheenEnergyLutConfigured: true,
      initializedBeforeFirstRender: sheenEnergyTexture.initialized,
    },
    fixedState: {
      canvas: { width: canvas.width, height: canvas.height },
      toneMapping: parameters.toneMap,
      exposure: parameters.exposure,
      environmentRotation: parameters.environmentRotation,
      skyboxShown: parameters.renderEnvironmentMap,
      shaderModified: false,
      sourceAssetModified: false,
      ambientOcclusion:
        configuration.ambientOcclusionBoundary ??
        'authored ToyCar occlusion remains enabled; no material mutation',
    },
  };
};

globalThis.renderPlan018Khronos = async (configuration) => {
  if (runtime.state == null || runtime.view == null || runtime.gl == null) {
    throw new Error('Khronos runner is not initialized');
  }
  const wantsDirect = configuration.record.pass !== 'iblOnly';
  const wantsIbl = configuration.record.pass !== 'directOnly';
  runtime.directEnabled = wantsDirect;
  runtime.fabricShader = null;
  runtime.key.intensity = wantsDirect
    ? configuration.directionalLight.intensity
    : 0;
  const parameters = runtime.state.renderingParameters;
  parameters.usePunctual = wantsDirect;
  parameters.useIBL = wantsIbl;
  parameters.iblIntensity = wantsIbl ? configuration.environmentIntensity : 0;
  parameters.renderEnvironmentMap = false;
  parameters.environmentRotation = 0;
  parameters.toneMap = GltfState.ToneMaps.KHR_PBR_NEUTRAL;

  runtime.state.userCamera.transform = new Float32Array(
    configuration.worldMatrix,
  );
  runtime.state.userCamera.type = 'perspective';
  runtime.state.userCamera.perspective.yfov =
    configuration.camera.verticalFovDegrees * Math.PI / 180;
  runtime.state.userCamera.perspective.znear = configuration.camera.near;
  runtime.state.userCamera.perspective.zfar = configuration.camera.far;
  const dx = configuration.flutterSceneWorld.position[0] -
    configuration.flutterSceneWorld.target[0];
  const dy = configuration.flutterSceneWorld.position[1] -
    configuration.flutterSceneWorld.target[1];
  const dz = configuration.flutterSceneWorld.position[2] -
    configuration.flutterSceneWorld.target[2];
  runtime.state.userCamera.distance = Math.hypot(dx, dy, dz);

  runtime.view.renderFrame(runtime.state, canvas.width, canvas.height);
  runtime.view.renderFrame(runtime.state, canvas.width, canvas.height);
  runtime.gl.finish();
  if (runtime.fabricShader == null) {
    throw new Error('Khronos scene sheen material was not drawn');
  }
  const shaderUniform = runtime.fabricShader.uniforms.directionalLight;
  const sheenEnergyTexture = runtime.state.environment.textures[
    runtime.state.environment.sheenELUT.index
  ];
  return {
    dataUrl: canvas.toDataURL('image/png'),
    camera: {
      flutterSceneWorld: configuration.flutterSceneWorld,
      khronosRawGltfWorld: {
        coordinateMapping: 'mirrorZ camera world transform',
        worldMatrix: Array.from(runtime.state.userCamera.transform),
      },
    },
    passState: {
      directEnabled: wantsDirect,
      iblEnabled: wantsIbl,
      directionalLight: {
        injected: wantsDirect,
        visibleLightCount: runtime.view.renderer.visibleLights.length,
        intensity: runtime.key.intensity,
        sourceDirection: wantsDirect
          ? Array.from(runtime.key.direction)
          : null,
        preparedUniform: wantsDirect
          ? serializeDirectionalLightUniform(runtime.key.toUniform(null))
          : null,
        shaderUniform,
      },
      environment: {
        configured: runtime.state.environment != null,
        intensity: parameters.iblIntensity,
        sheenEnergyLutInitialized: sheenEnergyTexture.initialized,
      },
      fabricShader: runtime.fabricShader,
      sceneSheenShader: runtime.fabricShader,
      toneMapping: parameters.toneMap,
      requestedOutputColorSpace: 'sRGB',
      actualOutputTransfer: 'renderer-native pow(linear, 1/2.2)',
    },
  };
};

function readDirectionalLightShaderUniform(shader) {
  if (shader?.program == null) {
    throw new Error('Khronos directional-light shader program unavailable');
  }
  return {
    direction: readShaderUniform(shader, 'u_Lights[0].direction'),
    colorLinear: readShaderUniform(shader, 'u_Lights[0].color'),
    intensity: readShaderUniform(shader, 'u_Lights[0].intensity'),
    type: readShaderUniform(shader, 'u_Lights[0].type'),
  };
}

function readShaderUniform(shader, name) {
  const location = runtime.gl.getUniformLocation(shader.program, name);
  if (location == null) {
    throw new Error('Khronos shader uniform unavailable: ' + name);
  }
  const value = runtime.gl.getUniform(shader.program, location);
  return ArrayBuffer.isView(value) ? Array.from(value) : value;
}

function serializeDirectionalLightUniform(uniform) {
  return {
    direction: Array.from(uniform.direction),
    colorLinear: Array.from(uniform.color),
    intensity: uniform.intensity,
    type: uniform.type,
  };
}

globalThis.disposePlan018Khronos = () => {
  if (runtime.disposed) return;
  runtime.disposed = true;
  runtime.gl?.getExtension('WEBGL_lose_context')?.loseContext();
  runtime.key = null;
  runtime.state = null;
  runtime.view = null;
  runtime.gl = null;
};
</script>`;
}

function assertRendererFacts(facts, authored) {
  if (
    facts?.backendFacts?.isWebGL2 !== true ||
    facts.backendFacts.renderedPixels !== true ||
    facts.authoredLightCount !== 0 ||
    facts.materialAudit?.materialIndex !== 1 ||
    facts.environment?.configured !== true ||
    facts.environment.iblIntensityScale !== 1 ||
    facts.environment.sheenEnergyLutConfigured !== true ||
    facts.environment.initializedBeforeFirstRender !== false ||
    facts.fixedState?.canvas?.width !== expectedDimensions.width ||
    facts.fixedState.canvas.height !== expectedDimensions.height ||
    facts.fixedState.toneMapping !== 'Khronos PBR Neutral' ||
    facts.fixedState.exposure !== 1 ||
    facts.fixedState.skyboxShown !== false
  ) {
    throw new Error('Khronos renderer fixed-state preflight changed');
  }
  if (
    facts.materialAudit?.materialName !== authored.materialName ||
    JSON.stringify(facts.materialAudit.sheenColorFactor) !==
      JSON.stringify(authored.sheenColorFactor) ||
    facts.materialAudit.sheenRoughnessFactor !== authored.sheenRoughnessFactor ||
    facts.materialAudit.sheenColorTexture !== null ||
    facts.materialAudit.sheenRoughnessTexture !== null
  ) {
    throw new Error('Khronos loader did not retain ToyCar authored sheen inputs');
  }
}

function assertGlamVelvetSofaRendererFacts(facts, authored) {
  if (
    facts?.backendFacts?.isWebGL2 !== true ||
    facts.backendFacts.renderedPixels !== true ||
    facts.authoredLightCount !==
      expectedGlamVelvetSofaDirectionalLight.authoredLightCount ||
    facts.sceneMaterialAudit?.materialIndex !==
      expectedGlamVelvetSofaSceneSheen.materialIndex ||
    facts.environment?.configured !== true ||
    facts.environment.iblIntensityScale !== 1 ||
    facts.environment.sheenEnergyLutConfigured !== true ||
    facts.environment.initializedBeforeFirstRender !== false ||
    facts.fixedState?.canvas?.width !== expectedDimensions.width ||
    facts.fixedState.canvas.height !== expectedDimensions.height ||
    facts.fixedState.toneMapping !== 'Khronos PBR Neutral' ||
    facts.fixedState.exposure !== 1 ||
    facts.fixedState.skyboxShown !== false
  ) {
    throw new Error('Khronos GlamVelvetSofa fixed-state preflight changed');
  }
  if (
    JSON.stringify(facts.materialAudits) !==
      JSON.stringify(expectedGlamVelvetSofaRendererMaterialAudits) ||
    facts.sceneMaterialAudit.materialName !==
      expectedGlamVelvetSofaSceneSheen.materialName ||
    JSON.stringify(facts.sceneMaterialAudit.sheenColorFactor) !==
      JSON.stringify(expectedGlamVelvetSofaSceneSheen.sheenColorFactor) ||
    facts.sceneMaterialAudit.sheenRoughnessFactor !==
      expectedGlamVelvetSofaSceneSheen.sheenRoughnessFactor ||
    facts.sceneMaterialAudit.sheenColorTexture !== null ||
    facts.sceneMaterialAudit.sheenRoughnessTexture !== null
  ) {
    throw new Error(
      'Khronos loader did not retain GlamVelvetSofa authored sheen inputs',
    );
  }
}

function arraysNear(actual, expected, tolerance) {
  if (!Array.isArray(actual) || actual.length !== expected.length) return false;
  return expected.every(
    (value, index) =>
      Number.isFinite(actual[index]) &&
      Math.abs(actual[index] - value) <= tolerance,
  );
}

function decodePng(dataUrl) {
  const prefix = 'data:image/png;base64,';
  if (!dataUrl.startsWith(prefix)) {
    throw new Error('Khronos runner did not return a PNG data URL');
  }
  return Buffer.from(dataUrl.slice(prefix.length), 'base64');
}

function pngDimensions(bytes) {
  if (!bytes.subarray(0, pngSignature.length).equals(pngSignature)) {
    throw new Error('Khronos capture is not a PNG');
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function safeEvidencePath(relativePath) {
  if (path.isAbsolute(relativePath)) {
    throw new Error('Khronos evidence paths must be repository-relative');
  }
  const resolved = path.resolve(repoRoot, relativePath);
  if (!resolved.startsWith(`${repoRoot}${path.sep}`)) {
    throw new Error('Khronos evidence path escaped the repository');
  }
  return resolved;
}

function serveFile(response, filePath) {
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    response.writeHead(404);
    response.end('Not found');
    return;
  }
  const extension = path.extname(filePath).toLowerCase();
  const contentType = {
    '.glb': 'model/gltf-binary',
    '.hdr': 'image/vnd.radiance',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.png': 'image/png',
    '.wasm': 'application/wasm',
  }[extension] ?? 'application/octet-stream';
  response.writeHead(200, {
    'content-type': contentType,
    'content-length': fs.statSync(filePath).size,
    'cache-control': 'no-store',
  });
  fs.createReadStream(filePath).pipe(response);
}

function listenLocalOnly(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

async function closeBrowserWithBackstop(browser) {
  const process = browser.process();
  let timer;
  try {
    await Promise.race([
      browser.close(),
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error('Khronos browser close timed out')),
          10000,
        );
      }),
    ]);
  } catch (error) {
    if (process != null && process.exitCode == null && process.signalCode == null) {
      process.kill('SIGKILL');
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

if (process.argv[1] != null && pathToFileURL(process.argv[1]).href === import.meta.url) {
  runPlan018KhronosToycarControlledReferenceCapture().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
