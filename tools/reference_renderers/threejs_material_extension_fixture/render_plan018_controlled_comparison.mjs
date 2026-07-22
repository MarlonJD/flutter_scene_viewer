import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer';

import {
  generateControlledStudioHdr,
  loadControlledComparisonState as loadPlan015State,
} from './plan015_controlled_comparison_contract.mjs';
import {
  hashBytes,
  loadPlan018ControlledComparisonState,
  modelCatalog,
  outputRoot,
  plan018StateHash,
  repoRoot,
  statePath,
} from './plan018_controlled_comparison_contract.mjs';
import { runPlan018SheenLoaderAudit } from './inspect_plan018_sheen_loader.mjs';

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const systemChromePath =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const expectedDimensions = Object.freeze({ width: 1206, height: 2622 });
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const renderHarnessPaths = Object.freeze([
  path.relative(repoRoot, scriptPath),
  path.relative(
    repoRoot,
    path.join(scriptDir, 'render_plan018_controlled_comparison.test.mjs'),
  ),
  path.relative(
    repoRoot,
    path.join(scriptDir, 'plan018_controlled_comparison_contract.mjs'),
  ),
  path.relative(
    repoRoot,
    path.join(scriptDir, 'inspect_plan018_sheen_loader.mjs'),
  ),
  path.relative(repoRoot, path.join(scriptDir, 'package.json')),
]);

export function buildPlan018CaptureInventory(state) {
  if (
    state?.name !== 'plan018_khr_materials_sheen_controlled_comparison' ||
    JSON.stringify(state.renderPasses) !==
      JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Plan 018 capture inventory requires the frozen state');
  }
  const inventory = [];
  for (const modelId of Object.keys(state.models ?? {})) {
    for (const view of Object.keys(state.models[modelId].cameras ?? {})) {
      for (const pass of state.renderPasses) {
        inventory.push({
          modelId,
          view,
          pass,
          fileName: `${modelId}_${view}_${pass}.png`,
        });
      }
    }
  }
  if (state.models?.toycar?.context?.mode === 'full-scene') {
    for (const pass of state.renderPasses) {
      inventory.push({
        modelId: 'toycar',
        view: 'context',
        pass,
        fileName: `toycar_context_${pass}.png`,
      });
    }
  }
  if (inventory.length !== 27) {
    throw new Error(`Plan 018 capture inventory has ${inventory.length} records`);
  }
  return inventory;
}

export async function cleanupPlan018CaptureResources({
  disposePage,
  closeBrowser,
  closeServer,
  removeProfile,
}) {
  const errors = [];
  for (const action of [
    disposePage,
    closeBrowser,
    closeServer,
    removeProfile,
  ]) {
    try {
      await action();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length !== 0) {
    throw new AggregateError(errors, 'Plan 018 capture cleanup failed');
  }
}

export async function runPlan018ControlledReferenceCapture({
  writeEvidence = true,
} = {}) {
  const state = loadPlan018ControlledComparisonState();
  const catalog = modelCatalog(state);
  const inventory = buildPlan018CaptureInventory(state);
  const loaderAudit = await runPlan018SheenLoaderAudit({
    writeEvidence: false,
  });
  assertLoaderAudit(state, catalog, loaderAudit);

  const generatedHdrBytes = generateControlledStudioHdr(loadPlan015State());
  if (hashBytes(generatedHdrBytes) !== state.environment.sha256) {
    throw new Error('Plan 018 generated HDR bytes drifted before capture');
  }
  const threeOutputRoot = path.join(outputRoot, 'threejs');
  const hdrPath = path.join(outputRoot, 'plan018_controlled_studio.hdr');
  fs.mkdirSync(threeOutputRoot, { recursive: true });
  fs.writeFileSync(hdrPath, generatedHdrBytes);

  const routes = new Map([
    ['/__environment__/controlled.hdr', hdrPath],
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
  const profilePath = fs.mkdtempSync(
    path.join(os.tmpdir(), 'plan018-threejs-capture-'),
  );
  let browser;
  let page;
  let pageDisposed = false;
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
      args: ['--disable-background-networking', '--disable-gpu-sandbox'],
    });
    page = await browser.newPage();
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
      'typeof globalThis.initializePlan018Comparison === "function"',
      { timeout: 10000 },
    );
    const renderer = await page.evaluate(
      ({ environmentUrl, referenceState }) =>
        globalThis.initializePlan018Comparison(
          environmentUrl,
          referenceState,
        ),
      {
        environmentUrl: `${origin}/__environment__/controlled.hdr`,
        referenceState: state,
      },
    );
    assertRendererFacts(state, renderer);

    const captures = [];
    const sceneAudits = {};
    for (const [modelId, model] of Object.entries(catalog)) {
      sceneAudits[modelId] = await page.evaluate(
        ({ id, url, modelContract, referenceState }) =>
          globalThis.loadPlan018Model(
            id,
            url,
            modelContract,
            referenceState,
          ),
        {
          id: modelId,
          url: `${origin}/__model__/${modelId}.glb`,
          modelContract: browserModelContract(model),
          referenceState: state,
        },
      );
      assertSceneAudit(modelId, model, loaderAudit.models[modelId], sceneAudits[modelId]);

      const modelInventory = inventory.filter(
        (record) => record.modelId === modelId,
      );
      for (const record of modelInventory) {
        const cameraContract = cameraForRecord(model, record.view);
        const result = await page.evaluate(
          ({ captureRecord, camera, referenceState }) =>
            globalThis.renderPlan018Pass(
              captureRecord,
              camera,
              referenceState,
            ),
          {
            captureRecord: record,
            camera: cameraContract,
            referenceState: state,
          },
        );
        const bytes = decodePng(result.dataUrl);
        const dimensions = pngDimensions(bytes);
        assertPngDimensions(record.fileName, dimensions);
        const artifactPath = path.join(threeOutputRoot, record.fileName);
        fs.writeFileSync(artifactPath, bytes);
        captures.push({
          modelId,
          view: record.view,
          pass: record.pass,
          path: path.relative(repoRoot, artifactPath),
          sha256: hashBytes(bytes),
          byteLength: bytes.length,
          dimensions,
          camera: result.camera,
          passState: result.passState,
          materialState: result.materialState,
        });
      }
      console.log(
        `Plan 018 Three.js captures: ${modelId} ` +
          `(${modelInventory.length}) OK`,
      );
    }
    if (captures.length !== inventory.length) {
      throw new Error('Plan 018 capture loop did not produce the exact inventory');
    }
    await page.evaluate(() => globalThis.disposePlan018Comparison());
    pageDisposed = true;

    const evidence = {
      schemaVersion: 1,
      status: 'verified locally',
      scope: 'pinned Three.js reference direction/conformance evidence',
      sourceState: path.relative(repoRoot, statePath),
      stateSha256: plan018StateHash(),
      state,
      environment: {
        path: path.relative(repoRoot, hdrPath),
        sha256: hashBytes(generatedHdrBytes),
        byteLength: generatedHdrBytes.length,
        decodedColumnMapping: state.rendererCoordinateMapping.environment,
      },
      models: Object.fromEntries(
        Object.entries(catalog).map(([id, model]) => [
          id,
          {
            name: model.name,
            path: model.path,
            sourceKind: model.sourceKind,
            sourcePath: model.sourcePath,
            sha256: model.sha256,
            byteLength: model.byteLength,
            licensePath: model.licensePath,
            licenseSha256: model.licenseSha256,
            sheenMaterialIndices: model.sheenMaterialIndices,
          },
        ]),
      ),
      renderer: {
        name: state.referenceRenderer.name,
        packageVersion: state.referenceRenderer.packageVersion,
        revision: renderer.revision,
        sourceCommit: state.referenceRenderer.sourceCommit,
        packageIntegrity: state.referenceRenderer.packageIntegrity,
        packageLockPath: state.referenceRenderer.packageLockPath,
        packageLockSha256: state.referenceRenderer.packageLockSha256,
        sourceSha256: state.referenceRenderer.sourceSha256,
        browser: await browser.version(),
        backend: state.referenceRenderer.backend,
        backendFacts: renderer.backendFacts,
        fixedState: renderer.fixedState,
        host: {
          platform: process.platform,
          release: os.release(),
          architecture: process.arch,
        },
      },
      renderHarness: {
        sources: Object.fromEntries(
          renderHarnessPaths.map((source) => [
            source,
            {
              sha256: hashBytes(fs.readFileSync(path.join(repoRoot, source))),
              byteLength: fs.statSync(path.join(repoRoot, source)).size,
            },
          ]),
        ),
      },
      loaderAudit,
      sceneAudits,
      captureInventory: inventory,
      captures,
      cleanupContract: {
        browser: 'closed in finally',
        server: '127.0.0.1 ephemeral listener closed in finally',
        profile: 'unique temporary profile removed in finally',
      },
      captureSceneBoundary:
        'Captures render only each GLB default scene and therefore only its ' +
        'scene-used material subset; authored material dependencies that are ' +
        'not scene-used are audited as loaded dependencies but are not pictured.',
      comparisonBoundary:
        'Pinned stock Three.js reference direction/conformance evidence only; ' +
        'no material, texture, geometry, visibility, normal, UV, shader, ' +
        'camera, lighting, or exposure patch was applied. Flutter/iOS is not ' +
        'run, and independent renderer implementations prevent a pixel-parity ' +
        'or physical-target claim.',
    };
    validatePlan018CaptureEvidence(evidence);
    if (writeEvidence) {
      fs.writeFileSync(
        path.join(threeOutputRoot, 'evidence.json'),
        `${JSON.stringify(evidence, null, 2)}\n`,
      );
    }
    console.log('Plan 018 controlled Three.js reference: 27 captures OK');
    return evidence;
  } finally {
    await cleanupPlan018CaptureResources({
      disposePage: async () => {
        if (page == null || page.isClosed() || pageDisposed) return;
        try {
          await page.evaluate(() => globalThis.disposePlan018Comparison?.());
        } catch {
          // Browser closure below remains the renderer cleanup backstop.
        }
      },
      closeBrowser: async () => {
        if (browser != null) await browser.close();
      },
      closeServer: async () => {
        if (server.listening) {
          await new Promise((resolve) => server.close(resolve));
        }
      },
      removeProfile: () => {
        fs.rmSync(profilePath, { recursive: true, force: true });
      },
    });
  }
}

export function validatePlan018CaptureEvidence(evidence) {
  const state = loadPlan018ControlledComparisonState();
  const catalog = modelCatalog(state);
  const inventory = buildPlan018CaptureInventory(state);
  if (
    evidence?.schemaVersion !== 1 ||
    evidence.status !== 'verified locally' ||
    evidence.scope !==
      'pinned Three.js reference direction/conformance evidence' ||
    evidence.sourceState !== path.relative(repoRoot, statePath) ||
    evidence.stateSha256 !== plan018StateHash() ||
    JSON.stringify(evidence.state) !== JSON.stringify(state) ||
    JSON.stringify(evidence.captureInventory) !== JSON.stringify(inventory) ||
    evidence.captures?.length !== 27
  ) {
    throw new Error('Plan 018 capture evidence identity or inventory changed');
  }
  const hdrBytes = fs.readFileSync(path.join(repoRoot, evidence.environment.path));
  if (
    evidence.environment.sha256 !== state.environment.sha256 ||
    evidence.environment.decodedColumnMapping !== 'mirrorDecodedColumns' ||
    hdrBytes.length !== evidence.environment.byteLength ||
    hashBytes(hdrBytes) !== evidence.environment.sha256
  ) {
    throw new Error('Plan 018 capture HDR evidence changed');
  }
  assertRendererEvidence(state, evidence.renderer);
  assertLoaderAudit(state, catalog, evidence.loaderAudit);
  for (const [source, record] of Object.entries(
    evidence.renderHarness?.sources ?? {},
  )) {
    const absolutePath = safeEvidencePath(source);
    const bytes = fs.readFileSync(absolutePath);
    if (
      bytes.length !== record.byteLength ||
      hashBytes(bytes) !== record.sha256
    ) {
      throw new Error(`Plan 018 render harness source drifted: ${source}`);
    }
  }
  if (
    JSON.stringify(Object.keys(evidence.renderHarness?.sources ?? {})) !==
    JSON.stringify(renderHarnessPaths)
  ) {
    throw new Error('Plan 018 render harness source inventory changed');
  }
  for (const [modelId, model] of Object.entries(catalog)) {
    const recorded = evidence.models?.[modelId];
    if (
      recorded?.sha256 !== model.sha256 ||
      recorded.byteLength !== model.byteLength ||
      recorded.licenseSha256 !== model.licenseSha256 ||
      JSON.stringify(recorded.sheenMaterialIndices) !==
        JSON.stringify(model.sheenMaterialIndices)
    ) {
      throw new Error(`Plan 018 capture model evidence drifted: ${modelId}`);
    }
    assertSceneAudit(
      modelId,
      model,
      evidence.loaderAudit.models[modelId],
      evidence.sceneAudits?.[modelId],
    );
  }
  for (const [index, record] of inventory.entries()) {
    const capture = evidence.captures[index];
    if (
      capture?.modelId !== record.modelId ||
      capture.view !== record.view ||
      capture.pass !== record.pass ||
      path.basename(capture.path) !== record.fileName
    ) {
      throw new Error(`Plan 018 capture order changed at index ${index}`);
    }
    const bytes = fs.readFileSync(safeEvidencePath(capture.path));
    const dimensions = pngDimensions(bytes);
    assertPngDimensions(record.fileName, dimensions);
    if (
      bytes.length !== capture.byteLength ||
      hashBytes(bytes) !== capture.sha256 ||
      JSON.stringify(capture.dimensions) !== JSON.stringify(dimensions)
    ) {
      throw new Error(`Plan 018 PNG evidence drifted: ${record.fileName}`);
    }
    assertCaptureState(state, catalog[record.modelId], record, capture);
  }
  if (
    !evidence.captureSceneBoundary?.includes('default scene') ||
    !evidence.captureSceneBoundary.includes('scene-used') ||
    !evidence.captureSceneBoundary.includes('not pictured') ||
    !evidence.comparisonBoundary?.includes('Flutter/iOS is not run') ||
    !evidence.comparisonBoundary.includes('pixel-parity')
  ) {
    throw new Error('Plan 018 capture evidence boundary changed');
  }
}

function pageHtml(baseUrl) {
  const fixtureRoot =
    `${baseUrl}/tools/reference_renderers/threejs_material_extension_fixture/`;
  const threeUrl = `${fixtureRoot}node_modules/three/build/three.module.js`;
  const loaderUrl =
    `${fixtureRoot}node_modules/three/examples/jsm/loaders/GLTFLoader.js`;
  const rgbeLoaderUrl =
    `${fixtureRoot}node_modules/three/examples/jsm/loaders/RGBELoader.js`;
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
  hdrTexture: null,
  pmrem: null,
  environmentTarget: null,
  environment: null,
  current: null,
};

globalThis.initializePlan018Comparison = async (environmentUrl, state) => {
  if (THREE.REVISION !== state.referenceRenderer.revision) {
    throw new Error('Three.js revision drifted: ' + THREE.REVISION);
  }
  renderer.setPixelRatio(state.viewport.devicePixelRatio);
  renderer.setSize(
    state.viewport.logicalWidth,
    state.viewport.logicalHeight,
    false,
  );
  renderer.toneMappingExposure = state.lighting.exposure;
  if (canvas.width !== 1206 || canvas.height !== 2622) {
    throw new Error('Plan 018 physical canvas dimensions changed');
  }
  context.hdrTexture = await new RGBELoader().loadAsync(environmentUrl);
  mirrorDecodedColumns(context.hdrTexture);
  context.hdrTexture.mapping = THREE.EquirectangularReflectionMapping;
  context.pmrem = new THREE.PMREMGenerator(renderer);
  context.pmrem.compileEquirectangularShader();
  context.environmentTarget = context.pmrem.fromEquirectangular(
    context.hdrTexture,
  );
  context.environment = context.environmentTarget.texture;
  const gl = renderer.getContext();
  const debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
  return {
    revision: THREE.REVISION,
    backendFacts: {
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
      renderedPixels: true,
    },
    fixedState: {
      canvas: { width: canvas.width, height: canvas.height },
      toneMapping: 'NeutralToneMapping / Khronos PBR Neutral',
      exposure: renderer.toneMappingExposure,
      outputColorSpace: 'SRGBColorSpace',
      environment: 'exact hash-pinned Radiance HDR via RGBELoader + PMREM',
      environmentLongitudeCorrection: 'mirrorDecodedColumns',
      environmentIntensity: state.environment.intensity,
      environmentRotationRadians: state.environment.rotationRadians,
      directionalLightTravelMapping: 'mirrorZ',
      ambientOcclusion: false,
      shadows: renderer.shadowMap.enabled,
      skybox: false,
      materialPatches: 'none',
      camera: 'explicit tracked Flutter-scene-world record mapped by mirrorZ',
    },
  };
};

globalThis.loadPlan018Model = async (
  modelId,
  modelUrl,
  contract,
  state,
) => {
  disposeCurrent();
  const gltf = await context.loader.loadAsync(modelUrl);
  const root = gltf.scene;
  root.updateWorldMatrix(true, true);
  const sourceBox = new THREE.Box3().setFromObject(root);
  const sourceSphere = sourceBox.getBoundingSphere(new THREE.Sphere());
  assertBounds(
    modelId + '/sourceBounds',
    sourceBox,
    sourceSphere,
    contract.sourceBounds,
  );
  const sheenBox = new THREE.Box3();
  const sceneSheenMaterialIndices = new Set();
  let sheenPrimitiveCount = 0;
  root.traverse((node) => {
    if (!node.isMesh) return;
    const materials = Array.isArray(node.material)
      ? node.material
      : [node.material];
    let hasSheen = false;
    for (const material of materials) {
      const materialIndex = gltf.parser.associations.get(material)?.materials;
      if (contract.sheenMaterialIndices.includes(materialIndex)) {
        sceneSheenMaterialIndices.add(materialIndex);
        hasSheen = true;
      }
    }
    if (!hasSheen) return;
    sheenBox.union(new THREE.Box3().setFromObject(node));
    sheenPrimitiveCount += 1;
  });
  const authoredIndices = (gltf.parser.json.materials ?? [])
    .map((material, index) =>
      material.extensions?.KHR_materials_sheen == null ? null : index,
    )
    .filter((index) => index != null);
  if (JSON.stringify(authoredIndices) !== JSON.stringify(contract.sheenMaterialIndices)) {
    throw new Error(modelId + ' authored sheen material indices changed');
  }
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
  const materialState = [];
  for (const materialIndex of contract.sheenMaterialIndices) {
    const material = await gltf.parser.getDependency('material', materialIndex);
    if (material.isMeshPhysicalMaterial !== true || material.sheen !== 1) {
      throw new Error(modelId + '/material[' + materialIndex + '] lost sheen');
    }
    materialState.push(sheenMaterialSummary(materialIndex, material));
  }
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(state.background.srgbHex);
  scene.environmentIntensity = state.environment.intensity;
  scene.environmentRotation.y = state.environment.rotationRadians;
  scene.add(root);
  context.current = {
    modelId,
    gltf,
    root,
    scene,
    sourceRadius: sourceSphere.radius,
    authoredSheenMaterialIndices: authoredIndices,
    loadedDependencySheenMaterialIndices: materialState.map(
      (material) => material.materialIndex,
    ),
    sceneUsedSheenMaterialIndices: [...sceneSheenMaterialIndices].sort(
      (a, b) => a - b,
    ),
    materialState,
  };
  return {
    sourceBounds: boundsSummary(sourceBox, sourceSphere),
    sheenPrimitiveBounds: boundsSummary(sheenBox, sheenSphere),
    sheenPrimitiveCount,
    authoredSheenMaterialIndices: authoredIndices,
    loadedDependencySheenMaterialIndices: materialState.map(
      (material) => material.materialIndex,
    ),
    sceneUsedSheenMaterialIndices: [...sceneSheenMaterialIndices].sort(
      (a, b) => a - b,
    ),
    materialState,
  };
};

globalThis.renderPlan018Pass = async (record, cameraContract, state) => {
  const current = context.current;
  if (current == null || current.modelId !== record.modelId) {
    throw new Error('Plan 018 requested capture for an unloaded model');
  }
  if (!state.renderPasses.includes(record.pass)) {
    throw new Error('Unexpected Plan 018 pass: ' + record.pass);
  }
  if (
    record.view !== 'close' &&
    record.view !== 'grazing' &&
    !(record.modelId === 'toycar' && record.view === 'context')
  ) {
    throw new Error('Unexpected Plan 018 view: ' + record.view);
  }
  const position = mirrorZ(cameraContract.position);
  const targetPosition = mirrorZ(cameraContract.target);
  const up = mirrorZ(state.camera.up);
  const aspect = state.viewport.logicalWidth / state.viewport.logicalHeight;
  const camera = new THREE.PerspectiveCamera(
    state.camera.verticalFovDegrees,
    aspect,
    state.camera.near,
    state.camera.far,
  );
  camera.position.fromArray(position);
  camera.up.fromArray(up);
  camera.lookAt(new THREE.Vector3().fromArray(targetPosition));
  camera.updateMatrixWorld(true);

  const travel = new THREE.Vector3().fromArray(
    mirrorZ(state.lighting.keyLightDirectionFlutterSceneWorld),
  ).normalize();
  const keyTarget = new THREE.Object3D();
  keyTarget.position.fromArray(targetPosition);
  const key = new THREE.DirectionalLight(
    new THREE.Color().fromArray(state.lighting.keyLightColorLinear),
    state.lighting.keyLightIntensity,
  );
  key.position.copy(keyTarget.position).addScaledVector(
    travel,
    -Math.max(current.sourceRadius * 4, 1),
  );
  key.target = keyTarget;
  key.castShadow = state.lighting.keyLightCastsShadow;

  const wantsIbl = record.pass === 'iblOnly' || record.pass === 'combined';
  const wantsDirect = record.pass === 'directOnly' || record.pass === 'combined';
  current.scene.environment = context.environment;
  current.scene.environmentIntensity = wantsIbl
    ? state.environment.intensity
    : 0;
  key.intensity = wantsDirect ? state.lighting.keyLightIntensity : 0;
  current.scene.add(key, keyTarget);
  await renderer.compileAsync(current.scene, camera);
  renderer.render(current.scene, camera);
  renderer.render(current.scene, camera);
  renderer.getContext().finish();
  const actualTravel = keyTarget.position.clone().sub(key.position).normalize();
  const result = {
    dataUrl: canvas.toDataURL('image/png'),
    camera: {
      coordinateSpace: 'flutterSceneWorld mapped to Three.js by mirrorZ',
      flutterSceneWorld: {
        position: cameraContract.position,
        target: cameraContract.target,
        up: state.camera.up,
      },
      threejs: {
        position: camera.position.toArray(),
        target: targetPosition,
        up: camera.up.toArray(),
        verticalFovDegrees: camera.fov,
        aspect: camera.aspect,
        near: camera.near,
        far: camera.far,
      },
    },
    passState: {
      directEnabled: wantsDirect,
      iblEnabled: wantsIbl,
      backgroundSrgbHex: state.background.srgbHex,
      directionalLight: {
        configured: true,
        intensity: key.intensity,
        colorLinear: key.color.toArray(),
        castsShadow: key.castShadow,
        travelFlutterSceneWorld:
          state.lighting.keyLightDirectionFlutterSceneWorld,
        travelThreeMappedRaw: mirrorZ(
          state.lighting.keyLightDirectionFlutterSceneWorld,
        ),
        travelThreeActualNormalized: actualTravel.toArray(),
      },
      environment: {
        configured: true,
        enabled: wantsIbl,
        intensity: current.scene.environmentIntensity,
        rotationRadians: current.scene.environmentRotation.y,
        decodedColumnMapping: 'mirrorDecodedColumns',
        skyboxShown: false,
      },
      ambientOcclusion: false,
      shadows: renderer.shadowMap.enabled,
      toneMapping: 'NeutralToneMapping / Khronos PBR Neutral',
      exposure: renderer.toneMappingExposure,
      outputColorSpace: 'SRGBColorSpace',
    },
    materialState: current.materialState,
  };
  current.scene.remove(key, keyTarget);
  key.dispose();
  return result;
};

globalThis.disposePlan018Comparison = () => {
  disposeCurrent();
  context.hdrTexture?.dispose();
  context.environmentTarget?.dispose();
  context.pmrem?.dispose();
  renderer.dispose();
  renderer.forceContextLoss();
};

function mirrorZ(vector) {
  return [vector[0], vector[1], -vector[2]];
}

function sheenMaterialSummary(materialIndex, material) {
  return {
    materialIndex,
    name: material.name,
    type: material.type,
    isMeshPhysicalMaterial: material.isMeshPhysicalMaterial,
    sheen: material.sheen,
    sheenColor: material.sheenColor.toArray(),
    sheenRoughness: material.sheenRoughness,
    sheenColorMap: textureSummary(material.sheenColorMap),
    sheenRoughnessMap: textureSummary(material.sheenRoughnessMap),
  };
}

function textureSummary(texture) {
  if (texture == null) return null;
  return {
    name: texture.name,
    offset: texture.offset.toArray(),
    repeat: texture.repeat.toArray(),
    rotation: texture.rotation,
    center: texture.center.toArray(),
    channel: texture.channel,
    colorSpace: texture.colorSpace,
  };
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

function mirrorDecodedColumns(texture) {
  const image = texture.image;
  const data = image?.data;
  const width = image?.width;
  const height = image?.height;
  if (data == null || !Number.isInteger(width) || !Number.isInteger(height)) {
    throw new Error('RGBELoader did not expose decoded HDR pixels');
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
  current.scene.remove(current.root);
  const disposedGeometry = new Set();
  const disposedMaterials = new Set();
  const disposedTextures = new Set();
  current.root.traverse((node) => {
    if (!node.isMesh) return;
    if (node.geometry != null && !disposedGeometry.has(node.geometry.uuid)) {
      disposedGeometry.add(node.geometry.uuid);
      node.geometry.dispose();
    }
    const materials = Array.isArray(node.material)
      ? node.material
      : [node.material];
    for (const material of materials) {
      if (material == null || disposedMaterials.has(material.uuid)) continue;
      disposedMaterials.add(material.uuid);
      for (const value of Object.values(material)) {
        if (value?.isTexture && !disposedTextures.has(value.uuid)) {
          disposedTextures.add(value.uuid);
          value.dispose();
        }
      }
      material.dispose();
    }
  });
  context.current = null;
}
</script>`;
}

function browserModelContract(model) {
  return {
    sourceBounds: model.sourceBounds,
    sheenPrimitiveBounds: model.sheenPrimitiveBounds,
    sheenMaterialIndices: model.sheenMaterialIndices,
  };
}

function cameraForRecord(model, view) {
  if (view === 'context') return model.context.camera;
  return model.cameras[view];
}

function assertLoaderAudit(state, catalog, audit) {
  if (
    audit?.status !== 'verified locally' ||
    audit.scope !== 'Three.js GLTFLoader consumption only' ||
    audit.stateSha256 !== plan018StateHash() ||
    audit.renderer?.revision !== state.referenceRenderer.revision ||
    audit.renderer.backend !== state.referenceRenderer.backend ||
    audit.renderer.backendFacts?.renderedPixels !== false ||
    JSON.stringify(Object.keys(audit.models ?? {})) !==
      JSON.stringify(Object.keys(catalog)) ||
    JSON.stringify(audit.collectiveCoverage) !==
      JSON.stringify({
        sheenColorFactor: true,
        sheenColorTexture: true,
        sheenRoughnessFactor: true,
        sheenRoughnessTexture: true,
      })
  ) {
    throw new Error('Plan 018 Slice 2 loader audit is not current');
  }
  for (const [modelId, model] of Object.entries(catalog)) {
    const loaded = audit.models[modelId];
    assertBoundsSummary(`${modelId}/loader/source`, loaded.sourceBounds, model.sourceBounds);
    assertBoundsSummary(
      `${modelId}/loader/sheen`,
      loaded.sheenPrimitiveBounds,
      model.sheenPrimitiveBounds,
    );
    if (
      JSON.stringify(loaded.materials.map((item) => item.authored.materialIndex)) !==
      JSON.stringify(model.sheenMaterialIndices)
    ) {
      throw new Error(`${modelId} loader sheen indices changed`);
    }
  }
}

function assertRendererFacts(state, renderer) {
  if (
    renderer?.revision !== state.referenceRenderer.revision ||
    renderer.backendFacts?.rendererType !== 'WebGLRenderer' ||
    renderer.backendFacts.isWebGLRenderer !== true ||
    renderer.backendFacts.renderedPixels !== true ||
    !renderer.backendFacts.contextVersion?.includes('WebGL') ||
    !renderer.backendFacts.shadingLanguageVersion ||
    JSON.stringify(renderer.fixedState?.canvas) !==
      JSON.stringify(expectedDimensions) ||
    renderer.fixedState.toneMapping !==
      'NeutralToneMapping / Khronos PBR Neutral' ||
    renderer.fixedState.exposure !== state.lighting.exposure ||
    renderer.fixedState.outputColorSpace !== 'SRGBColorSpace' ||
    renderer.fixedState.environmentLongitudeCorrection !==
      'mirrorDecodedColumns' ||
    renderer.fixedState.ambientOcclusion !== false ||
    renderer.fixedState.shadows !== false ||
    renderer.fixedState.skybox !== false ||
    renderer.fixedState.materialPatches !== 'none'
  ) {
    throw new Error('Plan 018 render backend or fixed state changed');
  }
}

function assertRendererEvidence(state, renderer) {
  if (
    renderer?.name !== state.referenceRenderer.name ||
    renderer.packageVersion !== state.referenceRenderer.packageVersion ||
    renderer.revision !== state.referenceRenderer.revision ||
    renderer.sourceCommit !== state.referenceRenderer.sourceCommit ||
    renderer.packageIntegrity !== state.referenceRenderer.packageIntegrity ||
    renderer.packageLockSha256 !==
      state.referenceRenderer.packageLockSha256 ||
    JSON.stringify(renderer.sourceSha256) !==
      JSON.stringify(state.referenceRenderer.sourceSha256) ||
    renderer.backend !== state.referenceRenderer.backend ||
    typeof renderer.browser !== 'string' ||
    renderer.browser.length === 0
  ) {
    throw new Error('Plan 018 renderer evidence changed');
  }
  assertRendererFacts(state, {
    revision: renderer.revision,
    backendFacts: renderer.backendFacts,
    fixedState: renderer.fixedState,
  });
  for (const [name, source] of Object.entries(renderer.sourceSha256)) {
    if (hashBytes(fs.readFileSync(safeEvidencePath(source.path))) !== source.sha256) {
      throw new Error(`Plan 018 renderer source drifted: ${name}`);
    }
  }
}

function assertSceneAudit(modelId, model, loaderModel, sceneAudit) {
  if (
    sceneAudit?.sheenPrimitiveCount !== loaderModel.sheenPrimitiveCount ||
    JSON.stringify(sceneAudit.authoredSheenMaterialIndices) !==
      JSON.stringify(model.sheenMaterialIndices) ||
    JSON.stringify(sceneAudit.loadedDependencySheenMaterialIndices) !==
      JSON.stringify(model.sheenMaterialIndices) ||
    !Array.isArray(sceneAudit.sceneUsedSheenMaterialIndices) ||
    sceneAudit.sceneUsedSheenMaterialIndices.length === 0 ||
    sceneAudit.sceneUsedSheenMaterialIndices.some(
      (index) => !model.sheenMaterialIndices.includes(index),
    ) ||
    JSON.stringify(sceneAudit.materialState.map((item) => item.materialIndex)) !==
      JSON.stringify(model.sheenMaterialIndices) ||
    sceneAudit.materialState.some(
      (item) => item.isMeshPhysicalMaterial !== true || item.sheen !== 1,
    )
  ) {
    throw new Error(`${modelId} render scene/material audit changed`);
  }
  assertBoundsSummary(
    `${modelId}/render/source`,
    sceneAudit.sourceBounds,
    loaderModel.sourceBounds,
  );
  assertBoundsSummary(
    `${modelId}/render/sheen`,
    sceneAudit.sheenPrimitiveBounds,
    loaderModel.sheenPrimitiveBounds,
  );
}

function assertCaptureState(state, model, record, capture) {
  const camera = cameraForRecord(model, record.view);
  const mappedPosition = mirrorZ(camera.position);
  const mappedTarget = mirrorZ(camera.target);
  const mappedUp = mirrorZ(state.camera.up);
  if (
    JSON.stringify(capture.camera?.flutterSceneWorld) !==
      JSON.stringify({
        position: camera.position,
        target: camera.target,
        up: state.camera.up,
      }) ||
    JSON.stringify(capture.camera.threejs?.position) !==
      JSON.stringify(mappedPosition) ||
    JSON.stringify(capture.camera.threejs.target) !==
      JSON.stringify(mappedTarget) ||
    JSON.stringify(capture.camera.threejs.up) !== JSON.stringify(mappedUp) ||
    capture.camera.threejs.verticalFovDegrees !==
      state.camera.verticalFovDegrees ||
    capture.camera.threejs.near !== state.camera.near ||
    capture.camera.threejs.far !== state.camera.far
  ) {
    throw new Error(`Plan 018 camera evidence changed: ${record.fileName}`);
  }
  const wantsDirect = record.pass === 'directOnly' || record.pass === 'combined';
  const wantsIbl = record.pass === 'iblOnly' || record.pass === 'combined';
  const passState = capture.passState;
  if (
    passState?.directEnabled !== wantsDirect ||
    passState.iblEnabled !== wantsIbl ||
    passState.backgroundSrgbHex !== state.background.srgbHex ||
    passState.directionalLight.configured !== true ||
    passState.directionalLight.intensity !==
      (wantsDirect ? state.lighting.keyLightIntensity : 0) ||
    JSON.stringify(passState.directionalLight.colorLinear) !==
      JSON.stringify(state.lighting.keyLightColorLinear) ||
    passState.directionalLight.castsShadow !== false ||
    JSON.stringify(passState.directionalLight.travelFlutterSceneWorld) !==
      JSON.stringify(state.lighting.keyLightDirectionFlutterSceneWorld) ||
    JSON.stringify(passState.directionalLight.travelThreeMappedRaw) !==
      JSON.stringify(mirrorZ(state.lighting.keyLightDirectionFlutterSceneWorld)) ||
    passState.environment.configured !== true ||
    passState.environment.enabled !== wantsIbl ||
    passState.environment.intensity !==
      (wantsIbl ? state.environment.intensity : 0) ||
    passState.environment.rotationRadians !== state.environment.rotationRadians ||
    passState.environment.decodedColumnMapping !== 'mirrorDecodedColumns' ||
    passState.environment.skyboxShown !== false ||
    passState.ambientOcclusion !== false ||
    passState.shadows !== false ||
    passState.exposure !== state.lighting.exposure ||
    passState.outputColorSpace !== 'SRGBColorSpace' ||
    JSON.stringify(capture.materialState?.map((item) => item.materialIndex)) !==
      JSON.stringify(model.sheenMaterialIndices) ||
    capture.materialState.some(
      (item) => item.isMeshPhysicalMaterial !== true || item.sheen !== 1,
    )
  ) {
    throw new Error(`Plan 018 pass evidence changed: ${record.fileName}`);
  }
}

function assertBoundsSummary(label, actual, expected) {
  for (const field of ['min', 'max', 'center']) {
    if (
      !Array.isArray(actual?.[field]) ||
      actual[field].length !== expected[field].length ||
      actual[field].some(
        (value, index) => Math.abs(value - expected[field][index]) > 1e-9,
      )
    ) {
      throw new Error(`${label}/${field} changed`);
    }
  }
  if (Math.abs(actual.radius - expected.radius) > 1e-9) {
    throw new Error(`${label}/radius changed`);
  }
}

function decodePng(dataUrl) {
  const prefix = 'data:image/png;base64,';
  if (typeof dataUrl !== 'string' || !dataUrl.startsWith(prefix)) {
    throw new Error('Plan 018 capture did not return a PNG data URL');
  }
  return Buffer.from(dataUrl.slice(prefix.length), 'base64');
}

function pngDimensions(bytes) {
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(pngSignature)) {
    throw new Error('Plan 018 capture is not a PNG');
  }
  return {
    width: bytes.readUInt32BE(16),
    height: bytes.readUInt32BE(20),
  };
}

function assertPngDimensions(label, dimensions) {
  if (
    dimensions.width !== expectedDimensions.width ||
    dimensions.height !== expectedDimensions.height
  ) {
    throw new Error(
      `${label} dimensions ${dimensions.width}x${dimensions.height} != ` +
        `${expectedDimensions.width}x${expectedDimensions.height}`,
    );
  }
}

function safeEvidencePath(relativePath) {
  if (
    typeof relativePath !== 'string' ||
    relativePath === '' ||
    path.isAbsolute(relativePath)
  ) {
    throw new Error('Plan 018 evidence path is not repository-relative');
  }
  const resolved = path.resolve(repoRoot, relativePath);
  if (!resolved.startsWith(`${repoRoot}${path.sep}`)) {
    throw new Error('Plan 018 evidence path escapes the repository');
  }
  return resolved;
}

function mirrorZ(vector) {
  return [vector[0], vector[1], -vector[2]];
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

function contentType(filePath) {
  if (filePath.endsWith('.js') || filePath.endsWith('.mjs')) {
    return 'text/javascript';
  }
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

if (process.argv[1] != null && path.resolve(process.argv[1]) === scriptPath) {
  await runPlan018ControlledReferenceCapture();
}
