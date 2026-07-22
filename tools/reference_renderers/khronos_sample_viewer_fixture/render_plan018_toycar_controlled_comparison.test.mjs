import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const renderModulePath = path.join(
  scriptDir,
  'render_plan018_toycar_controlled_comparison.mjs',
);
const stateRelativePath =
  'tools/material_extension_acceptance/fixtures/' +
  'plan018_controlled_comparison_state.json';
const statePath = path.join(repoRoot, stateRelativePath);
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

const expectedStateSha256 =
  '385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843';
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
      path:
        'tools/reference_renderers/khronos_sample_viewer_fixture/' +
        'vendor/gltf-viewer.module.js',
      sha256:
        'ca863c37b8deb6fcaa456e2a59da46311867aab2baf0d15bac48f5239b3a4f4b',
    },
    mikktspaceWasm: {
      path:
        'tools/reference_renderers/khronos_sample_viewer_fixture/' +
        'vendor/libs/mikktspace_bg.wasm',
      sha256:
        'd734e040ae6480a0d00ba08b8aaae29c2eb59c8705c38b7bc120885fc94c54e2',
    },
    sheenEnergyLut: {
      path:
        'tools/reference_renderers/khronos_sample_viewer_fixture/' +
        'assets/lut_sheen_E.png',
      sha256:
        '7f21d7754dd3a2a972d9d1298ee3e67e20c5b2f21969095d322a1bc20f8b2f04',
    },
  },
});
const expectedEnvironment = Object.freeze({
  sourceSha256:
    'ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a',
  mappedSha256:
    'bbfb66543521716d53c5aa4b812dbe0e2278e25f63c6b4801311b923e19d0ef7',
  mappedByteLength: 524390,
  coordinateMapping: 'mirrorRgbeColumns',
});
const expectedLight = Object.freeze({
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
const expectedCameraWorldMatrices = Object.freeze({
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

function expectedInventory() {
  const inventory = [];
  for (const view of ['close', 'grazing', 'context']) {
    for (const pass of ['directOnly', 'iblOnly', 'combined']) {
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

function expectedGlamVelvetSofaInventory() {
  const inventory = [];
  for (const view of ['close', 'grazing']) {
    for (const pass of ['directOnly', 'iblOnly', 'combined']) {
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

const expectedGlamVelvetSofaSceneSheen = Object.freeze({
  materialIndex: 3,
  materialName: 'GlamVelvetSofa_fabric_navy',
  sheenColorFactor: Object.freeze([0.05, 0.17, 0.5]),
  sheenRoughnessFactor: 0.6,
});

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function assertArrayNear(actual, expected, tolerance = 1e-7) {
  assert.equal(actual.length, expected.length);
  for (const [index, value] of expected.entries()) {
    assert.ok(
      Number.isFinite(actual[index]) &&
        Math.abs(actual[index] - value) <= tolerance,
      `value[${index}] ${actual[index]} != ${value}`,
    );
  }
}

async function loadRequiredRenderModule() {
  try {
    return await import(pathToFileURL(renderModulePath));
  } catch (error) {
    if (error?.code === 'ERR_MODULE_NOT_FOUND') {
      assert.fail(
        'Plan 018 Khronos ToyCar render module and evidence are not yet ' +
          `implemented: ${error.message}`,
      );
    }
    throw error;
  }
}

test(
  'Plan 018 Khronos GlamVelvetSofa inventory is exactly six fixed records',
  async () => {
    const module = await loadRequiredRenderModule();
    assert.equal(
      typeof module.buildPlan018KhronosGlamVelvetSofaCaptureInventory,
      'function',
    );

    const stateBytes = fs.readFileSync(statePath);
    const state = JSON.parse(stateBytes.toString('utf8'));
    assert.equal(sha256(stateBytes), expectedStateSha256);

    const inventory =
      module.buildPlan018KhronosGlamVelvetSofaCaptureInventory(state);
    assert.deepEqual(inventory, expectedGlamVelvetSofaInventory());
    assert.equal(inventory.length, 6);
    assert.equal(new Set(inventory.map((record) => record.fileName)).size, 6);
  },
);

test(
  'Plan 018 Khronos GlamVelvetSofa capture writes and validates every PNG',
  async () => {
    const module = await loadRequiredRenderModule();
    assert.equal(
      typeof module.runPlan018KhronosGlamVelvetSofaControlledReferenceCapture,
      'function',
    );
    assert.equal(
      typeof module.validatePlan018KhronosGlamVelvetSofaCaptureEvidence,
      'function',
    );

    const evidence =
      await module.runPlan018KhronosGlamVelvetSofaControlledReferenceCapture();
    module.validatePlan018KhronosGlamVelvetSofaCaptureEvidence(evidence);

    assert.equal(evidence.schemaVersion, 1);
    assert.equal(evidence.status, 'verified locally');
    assert.equal(
      evidence.scope,
      'pinned Khronos glTF Sample Renderer GlamVelvetSofa ' +
        'direction/conformance evidence',
    );
    assert.equal(evidence.comparisonBoundary, 'direction/conformance-only');
    assert.equal(
      evidence.claimBoundary,
      'Reference output establishes direction/conformance evidence only; ' +
        'it does not establish pixel parity or Flutter target capability.',
    );
    assert.equal(evidence.sourceState, stateRelativePath);
    assert.equal(evidence.stateSha256, expectedStateSha256);
    assert.equal(evidence.renderer.name, expectedRenderer.name);
    assert.equal(evidence.renderer.sourceCommit, expectedRenderer.sourceCommit);
    assert.equal(evidence.renderer.renderedPixels, true);
    assert.equal(evidence.rendererAudit.authoredLightCount, 1);
    assert.equal(
      evidence.rendererAudit.sceneMaterialAudit.materialIndex,
      expectedGlamVelvetSofaSceneSheen.materialIndex,
    );
    assert.equal(
      evidence.rendererAudit.sceneMaterialAudit.materialName,
      expectedGlamVelvetSofaSceneSheen.materialName,
    );

    assert.equal(evidence.glamVelvetSofa.modelId, 'glam_velvet_sofa');
    assert.equal(evidence.glamVelvetSofa.name, 'GlamVelvetSofa');
    assert.equal(
      evidence.glamVelvetSofa.path,
      'tools/out/material_extension_acceptance/plan018_sheen_corpus/' +
        'glam_velvet_sofa/source/GlamVelvetSofa.glb',
    );
    assert.equal(
      evidence.glamVelvetSofa.sha256,
      '67202c74a1a33377771f162dc7fad612a6c9bd51ee15124c488e9851d9ac5266',
    );
    assert.deepEqual(
      evidence.glamVelvetSofa.authoredSheen,
      expectedGlamVelvetSofaAuthoredSheen,
    );
    assert.equal(evidence.glamVelvetSofa.authoredLightCount, 1);
    assert.deepEqual(
      evidence.glamVelvetSofa.sceneUsedSheen,
      expectedGlamVelvetSofaSceneSheen,
    );

    assert.deepEqual(
      evidence.rendererMapping.directionalLight,
      {...expectedLight, authoredLightCount: 1},
    );
    assert.match(
      evidence.rendererMapping.authoredLightsBoundary,
      /suppressed.*controlled studio key/i,
    );
    assert.deepEqual(
      evidence.captureInventory,
      expectedGlamVelvetSofaInventory(),
    );
    assert.equal(evidence.captures.length, 6);

    for (const [index, capture] of evidence.captures.entries()) {
      const expected = evidence.captureInventory[index];
      assert.deepEqual(
        {
          modelId: capture.modelId,
          view: capture.view,
          pass: capture.pass,
          fileName: path.basename(capture.path),
        },
        expected,
      );
      assert.deepEqual(capture.dimensions, { width: 1206, height: 2622 });
      assert.match(capture.sha256, /^[a-f0-9]{64}$/);
      assert.ok(capture.byteLength > 24);
      const artifactBytes = fs.readFileSync(
        path.join(repoRoot, capture.path),
      );
      assert.ok(artifactBytes.subarray(0, 8).equals(pngSignature));
      assert.equal(artifactBytes.readUInt32BE(16), 1206);
      assert.equal(artifactBytes.readUInt32BE(20), 2622);
      assert.equal(artifactBytes.length, capture.byteLength);
      assert.equal(sha256(artifactBytes), capture.sha256);

      const wantsDirect = expected.pass !== 'iblOnly';
      const wantsIbl = expected.pass !== 'directOnly';
      const sceneShader = capture.passState.sceneSheenShader;
      assert.equal(
        sceneShader.materialIndex,
        expectedGlamVelvetSofaSceneSheen.materialIndex,
      );
      assert.equal(
        sceneShader.materialName,
        expectedGlamVelvetSofaSceneSheen.materialName,
      );
      assert.ok(sceneShader.defines.includes('MATERIAL_SHEEN 1'));
      assert.equal(
        sceneShader.defines.includes('USE_PUNCTUAL 1'),
        wantsDirect,
      );
      assert.equal(sceneShader.defines.includes('LIGHT_COUNT 1'), wantsDirect);
      assert.equal(sceneShader.defines.includes('USE_IBL 1'), wantsIbl);
      assertArrayNear(
        sceneShader.uniforms.sheenColorFactor,
        expectedGlamVelvetSofaSceneSheen.sheenColorFactor,
      );
      assert.ok(
        Math.abs(
          sceneShader.uniforms.sheenRoughnessFactor -
            expectedGlamVelvetSofaSceneSheen.sheenRoughnessFactor,
        ) <= 1e-7,
      );
      if (wantsDirect) {
        assertArrayNear(
          sceneShader.uniforms.directionalLight.direction,
          expectedLight.travelKhronosRawGltfWorldNormalized,
        );
      } else {
        assert.equal(sceneShader.uniforms.directionalLight, null);
      }
      assert.equal(capture.passState.environment.configured, true);
      assert.equal(
        capture.passState.environment.sheenEnergyLutInitialized,
        true,
      );
      assert.equal(
        capture.passState.environment.intensity,
        wantsIbl ? 1 : 0,
      );
    }

    for (const view of ['close', 'grazing']) {
      const triplet = Object.fromEntries(
        evidence.captures
          .filter((capture) => capture.view === view)
          .map((capture) => [capture.pass, capture.sha256]),
      );
      assert.notEqual(
        triplet.directOnly,
        triplet.iblOnly,
        `${view}: direct-only and IBL-only pixels must differ`,
      );
      assert.notEqual(
        triplet.combined,
        triplet.directOnly,
        `${view}: combined and direct-only pixels must differ`,
      );
      assert.notEqual(
        triplet.combined,
        triplet.iblOnly,
        `${view}: combined must contain the injected direct light`,
      );
    }

    const invalidSceneUniform = structuredClone(evidence);
    invalidSceneUniform.captures[0].passState.sceneSheenShader.uniforms
      .directionalLight.direction = [0, 0, 0];
    assert.throws(
      () => module.validatePlan018KhronosGlamVelvetSofaCaptureEvidence(
        invalidSceneUniform,
      ),
      /Khronos pass-state evidence changed/,
    );

    const duplicateCombinedPixels = structuredClone(evidence);
    const closeIbl = duplicateCombinedPixels.captures.find(
      (capture) => capture.view === 'close' && capture.pass === 'iblOnly',
    );
    const closeCombined = duplicateCombinedPixels.captures.find(
      (capture) => capture.view === 'close' && capture.pass === 'combined',
    );
    closeCombined.sha256 = closeIbl.sha256;
    assert.throws(
      () => module.validatePlan018KhronosGlamVelvetSofaCaptureEvidence(
        duplicateCombinedPixels,
      ),
      /Khronos close pixel passes are not distinct/,
    );
  },
);

test(
  'Plan 018 Khronos ToyCar capture preserves the frozen direction/conformance contract',
  async () => {
    const stateBytes = fs.readFileSync(statePath);
    const state = JSON.parse(stateBytes.toString('utf8'));
    assert.equal(sha256(stateBytes), expectedStateSha256);

    const module = await loadRequiredRenderModule();
    assert.equal(
      typeof module.buildPlan018KhronosToycarCaptureInventory,
      'function',
    );
    assert.equal(
      typeof module.runPlan018KhronosToycarControlledReferenceCapture,
      'function',
    );
    assert.equal(
      typeof module.validatePlan018KhronosToycarCaptureEvidence,
      'function',
    );

    const inventory =
      module.buildPlan018KhronosToycarCaptureInventory(state);
    assert.deepEqual(inventory, expectedInventory());
    assert.equal(inventory.length, 9);
    assert.equal(new Set(inventory.map((record) => record.fileName)).size, 9);

    const evidence =
      await module.runPlan018KhronosToycarControlledReferenceCapture();
    module.validatePlan018KhronosToycarCaptureEvidence(evidence);

    assert.equal(evidence.schemaVersion, 1);
    assert.equal(evidence.status, 'verified locally');
    assert.equal(
      evidence.scope,
      'pinned Khronos glTF Sample Renderer ToyCar ' +
        'direction/conformance evidence',
    );
    assert.equal(evidence.comparisonBoundary, 'direction/conformance-only');
    assert.equal(
      evidence.claimBoundary,
      'Reference output establishes direction/conformance evidence only; ' +
        'it does not establish pixel parity or Flutter target capability.',
    );
    assert.equal(evidence.sourceState, stateRelativePath);
    assert.equal(evidence.stateSha256, expectedStateSha256);

    assert.equal(evidence.renderer.name, expectedRenderer.name);
    assert.equal(
      evidence.renderer.sourceRepository,
      expectedRenderer.sourceRepository,
    );
    assert.equal(
      evidence.renderer.sourceCommit,
      expectedRenderer.sourceCommit,
    );
    assert.equal(
      evidence.renderer.sourceArchiveSha256,
      expectedRenderer.sourceArchiveSha256,
    );
    assert.equal(
      evidence.renderer.viewerCommit,
      expectedRenderer.viewerCommit,
    );
    assert.equal(evidence.renderer.backend, expectedRenderer.backend);
    assert.deepEqual(
      evidence.renderer.sourceSha256,
      expectedRenderer.sourceSha256,
    );
    assert.equal(evidence.renderer.renderedPixels, true);
    assert.equal(evidence.rendererAudit.materialAudit.materialIndex, 1);
    assert.equal(
      evidence.rendererAudit.environment.sheenEnergyLutConfigured,
      true,
    );
    assert.equal(
      evidence.rendererAudit.environment.initializedBeforeFirstRender,
      false,
    );

    assert.equal(evidence.toycar.modelId, 'toycar');
    assert.equal(evidence.toycar.name, 'ToyCar');
    assert.equal(
      evidence.toycar.path,
      'tools/out/material_extension_acceptance/plan018_sheen_corpus/' +
        'toycar/source/ToyCar.glb',
    );
    assert.equal(
      evidence.toycar.sha256,
      '01a60862de55cd4b9f3acfab0b0def86451800f9c42467fcd61052c16cb9838c',
    );
    assert.deepEqual(evidence.toycar.authoredSheen, {
      materialIndex: 1,
      materialName: 'Fabric',
      extension: 'KHR_materials_sheen',
      sheenColorFactor: [1, 0, 0],
      sheenRoughnessFactor: 0.5,
      sheenColorTexture: null,
      sheenRoughnessTexture: null,
    });

    assert.equal(
      evidence.environment.sourceSha256,
      expectedEnvironment.sourceSha256,
    );
    assert.equal(
      evidence.environment.mappedSha256,
      expectedEnvironment.mappedSha256,
    );
    assert.equal(
      evidence.environment.mappedByteLength,
      expectedEnvironment.mappedByteLength,
    );
    assert.equal(
      evidence.environment.coordinateMapping,
      expectedEnvironment.coordinateMapping,
    );
    assert.equal(evidence.environment.intensity, 1);
    assert.equal(evidence.environment.rotationDegrees, 0);
    assert.equal(evidence.environment.skyboxShown, false);

    assert.deepEqual(
      evidence.rendererMapping.directionalLight,
      expectedLight,
    );
    assert.equal(
      evidence.rendererMapping.output.requestedColorSpace,
      'sRGB',
    );
    assert.equal(
      evidence.rendererMapping.output.actualTransfer,
      'renderer-native pow(linear, 1/2.2)',
    );
    assert.equal(
      evidence.rendererMapping.output.toneMapping,
      'Khronos PBR Neutral',
    );

    assert.deepEqual(evidence.captureInventory, expectedInventory());
    assert.equal(evidence.captures.length, 9);
    for (const [index, capture] of evidence.captures.entries()) {
      const expected = evidence.captureInventory[index];
      assert.deepEqual(
        {
          modelId: capture.modelId,
          view: capture.view,
          pass: capture.pass,
          fileName: path.basename(capture.path),
        },
        expected,
      );
      assert.deepEqual(capture.dimensions, { width: 1206, height: 2622 });
      assert.match(capture.sha256, /^[a-f0-9]{64}$/);
      assert.ok(capture.byteLength > 24);

      const artifactBytes = fs.readFileSync(
        path.join(repoRoot, capture.path),
      );
      assert.ok(artifactBytes.subarray(0, 8).equals(pngSignature));
      assert.equal(artifactBytes.readUInt32BE(16), 1206);
      assert.equal(artifactBytes.readUInt32BE(20), 2622);
      assert.equal(artifactBytes.length, capture.byteLength);
      assert.equal(sha256(artifactBytes), capture.sha256);

      assert.deepEqual(
        capture.camera.flutterSceneWorld,
        expected.view === 'context'
          ? state.models.toycar.context.camera
          : state.models.toycar.cameras[expected.view],
      );
      assertArrayNear(
        capture.camera.khronosRawGltfWorld.worldMatrix,
        expectedCameraWorldMatrices[expected.view],
      );

      const wantsDirect = expected.pass !== 'iblOnly';
      const wantsIbl = expected.pass !== 'directOnly';
      assert.equal(capture.passState.directEnabled, wantsDirect);
      assert.equal(capture.passState.iblEnabled, wantsIbl);
      assert.equal(capture.passState.directionalLight.injected, wantsDirect);
      assert.equal(
        capture.passState.directionalLight.visibleLightCount,
        wantsDirect ? 1 : 0,
      );
      assert.equal(
        capture.passState.directionalLight.intensity,
        wantsDirect ? 3 : 0,
      );
      if (wantsDirect) {
        assertArrayNear(
          capture.passState.directionalLight.sourceDirection,
          expectedLight.travelKhronosRawGltfWorldNormalized,
        );
        assertArrayNear(
          capture.passState.directionalLight.preparedUniform.direction,
          expectedLight.travelKhronosRawGltfWorldNormalized,
        );
        assert.equal(
          capture.passState.directionalLight.shaderUniform.type,
          0,
        );
        assertArrayNear(
          capture.passState.directionalLight.shaderUniform.direction,
          expectedLight.travelKhronosRawGltfWorldNormalized,
        );
        assertArrayNear(
          capture.passState.directionalLight.shaderUniform.colorLinear,
          [1, 1, 1],
        );
        assert.equal(
          capture.passState.directionalLight.shaderUniform.intensity,
          3,
        );
      } else {
        assert.equal(
          capture.passState.directionalLight.shaderUniform,
          null,
        );
      }
      const fabricShader = capture.passState.fabricShader;
      assert.equal(fabricShader.materialIndex, 1);
      assert.equal(fabricShader.materialName, 'Fabric');
      assert.ok(Number.isInteger(fabricShader.fragmentHash));
      assert.equal(typeof fabricShader.programHash, 'string');
      assert.ok(fabricShader.defines.includes('MATERIAL_SHEEN 1'));
      assert.equal(
        fabricShader.defines.includes('USE_PUNCTUAL 1'),
        wantsDirect,
      );
      assert.equal(
        fabricShader.defines.includes('LIGHT_COUNT 1'),
        wantsDirect,
      );
      assert.equal(fabricShader.defines.includes('USE_IBL 1'), wantsIbl);
      assertArrayNear(
        fabricShader.uniforms.sheenColorFactor,
        [1, 0, 0],
      );
      assert.equal(fabricShader.uniforms.sheenRoughnessFactor, 0.5);
      if (wantsDirect) {
        assertArrayNear(
          fabricShader.uniforms.directionalLight.direction,
          expectedLight.travelKhronosRawGltfWorldNormalized,
        );
        assert.equal(fabricShader.uniforms.directionalLight.intensity, 3);
        assert.equal(fabricShader.uniforms.directionalLight.type, 0);
      } else {
        assert.equal(fabricShader.uniforms.directionalLight, null);
      }
      assert.equal(capture.passState.environment.configured, true);
      assert.equal(
        capture.passState.environment.sheenEnergyLutInitialized,
        true,
      );
      assert.equal(
        capture.passState.environment.intensity,
        wantsIbl ? 1 : 0,
      );
      assert.equal(
        capture.passState.toneMapping,
        'Khronos PBR Neutral',
      );
      assert.equal(capture.passState.requestedOutputColorSpace, 'sRGB');
      assert.equal(
        capture.passState.actualOutputTransfer,
        'renderer-native pow(linear, 1/2.2)',
      );
    }

    for (const view of ['close', 'grazing', 'context']) {
      const triplet = Object.fromEntries(
        evidence.captures
          .filter((capture) => capture.view === view)
          .map((capture) => [capture.pass, capture.sha256]),
      );
      assert.notEqual(
        triplet.directOnly,
        triplet.iblOnly,
        `${view}: direct-only and IBL-only pixels must differ`,
      );
      assert.notEqual(
        triplet.combined,
        triplet.directOnly,
        `${view}: combined and direct-only pixels must differ`,
      );
      assert.notEqual(
        triplet.combined,
        triplet.iblOnly,
        `${view}: combined must contain the injected direct light`,
      );
    }

    const invalidFabricUniform = structuredClone(evidence);
    invalidFabricUniform.captures[0].passState.fabricShader.uniforms
      .directionalLight.direction = [0, 0, 0];
    assert.throws(
      () => module.validatePlan018KhronosToycarCaptureEvidence(
        invalidFabricUniform,
      ),
      /Khronos pass-state evidence changed/,
    );

    const duplicateCombinedPixels = structuredClone(evidence);
    const closeIbl = duplicateCombinedPixels.captures.find(
      (capture) => capture.view === 'close' && capture.pass === 'iblOnly',
    );
    const closeCombined = duplicateCombinedPixels.captures.find(
      (capture) => capture.view === 'close' && capture.pass === 'combined',
    );
    closeCombined.sha256 = closeIbl.sha256;
    assert.throws(
      () => module.validatePlan018KhronosToycarCaptureEvidence(
        duplicateCombinedPixels,
      ),
      /Khronos close pixel passes are not distinct/,
    );
  },
);
