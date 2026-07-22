import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  generateControlledStudioHdr,
  loadControlledComparisonState as loadPlan015State,
} from './plan015_controlled_comparison_contract.mjs';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(scriptDir, '../../..');
export const statePath = path.join(
  repoRoot,
  'tools/material_extension_acceptance/fixtures/' +
    'plan018_controlled_comparison_state.json',
);
export const outputRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/plan018_controlled_comparison',
);
const manifestPath = path.join(
  repoRoot,
  'tools/material_extension_acceptance/manifest.json',
);

const expectedModelIds = Object.freeze([
  'sheen_chair',
  'sheen_cloth',
  'glam_velvet_sofa',
  'toycar',
]);
const requiredSheenInputs = Object.freeze([
  'sheenColorFactor',
  'sheenColorTexture',
  'sheenRoughnessFactor',
  'sheenRoughnessTexture',
]);

export function loadPlan018ControlledComparisonState() {
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  validatePlan018ControlledComparisonState(state);
  return state;
}

export function validatePlan018ControlledComparisonState(state) {
  if (
    state?.schemaVersion !== 1 ||
    state.name !== 'plan018_khr_materials_sheen_controlled_comparison' ||
    state.comparisonBoundary !== 'direction/conformance-only'
  ) {
    throw new Error('Plan 018 controlled comparison identity is invalid');
  }
  validateDisplayState(state);
  validateReferenceRenderer(state.referenceRenderer);
  validatePackageCameraAdapter(state.packageCameraAdapterContract);
  validateAssetSource(state.assetSource);
  if (
    JSON.stringify(Object.keys(state.models ?? {})) !==
    JSON.stringify(expectedModelIds)
  ) {
    throw new Error('Plan 018 model catalog or order changed');
  }

  const collectiveCoverage = Object.fromEntries(
    requiredSheenInputs.map((field) => [field, false]),
  );
  const sourceJsonByModel = {};
  for (const [modelId, model] of Object.entries(state.models)) {
    sourceJsonByModel[modelId] = validateModel(
      modelId,
      model,
      collectiveCoverage,
    );
  }
  if (Object.values(collectiveCoverage).some((value) => value !== true)) {
    throw new Error('Plan 018 corpus does not cover every authored sheen input');
  }
  validateManifestCrossCheck(state);
  validateToyCarFocus(state.models.toycar, sourceJsonByModel.toycar);
}

export function modelCatalog(state) {
  validatePlan018ControlledComparisonState(state);
  return Object.fromEntries(
    Object.entries(state.models).map(([id, model]) => [
      id,
      {
        ...model,
        absolutePath: path.join(repoRoot, model.path),
        absoluteLicensePath: path.join(repoRoot, model.licensePath),
      },
    ]),
  );
}

export function plan018StateHash() {
  return hashBytes(fs.readFileSync(statePath));
}

export function hashBytes(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function validateDisplayState(state) {
  for (const key of ['logicalWidth', 'logicalHeight', 'devicePixelRatio']) {
    if (!Number.isInteger(state.viewport?.[key]) || state.viewport[key] <= 0) {
      throw new Error(`Plan 018 viewport ${key} must be a positive integer`);
    }
  }
  if (
    state.background?.srgbHex !== '#121118' ||
    state.toneMapping !== 'pbrNeutral' ||
    state.outputColorSpace !== 'sRGB' ||
    JSON.stringify(state.renderPasses) !==
      JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Plan 018 pass or display contract changed');
  }
  const camera = state.camera;
  if (
    camera?.verticalFovDegrees !== 60 ||
    camera.near !== 0.1 ||
    camera.far !== 1000 ||
    JSON.stringify(camera.up) !== JSON.stringify([0, 1, 0])
  ) {
    throw new Error('Plan 018 package camera constants changed');
  }
  const mapping = state.rendererCoordinateMapping;
  if (
    mapping?.flutterSceneImportedGltfRoot !== 'mirrorZ' ||
    mapping.position !== '[x,y,z] => [x,y,-z]' ||
    mapping.target !== '[x,y,z] => [x,y,-z]' ||
    mapping.up !== '[x,y,z] => [x,y,-z]' ||
    mapping.directionalLightTravel !== '[x,y,z] => [x,y,-z]' ||
    mapping.environment !== 'mirrorDecodedColumns' ||
    mapping.backdrop !== 'mirrorZ'
  ) {
    throw new Error('Plan 018 complete mirror-Z mapping changed');
  }
  const environment = state.environment;
  const generatedHdr = generateControlledStudioHdr(loadPlan015State());
  if (
    environment?.kind !== 'generatedRadianceHdr' ||
    environment.generator !==
      'plan015_controlled_studio_v1_reused_exact_bytes' ||
    environment.sourceStatePath !==
      'tools/material_extension_acceptance/fixtures/' +
        'plan015_controlled_comparison_state.json' ||
    environment.width !== 512 ||
    environment.height !== 256 ||
    hashBytes(generatedHdr) !== environment.sha256 ||
    environment.worldOrientation !== 'flutterSceneWorldAtanZOverX' ||
    environment.threejsLongitudeCorrection !== 'mirrorDecodedColumns' ||
    environment.intensity !== 1 ||
    environment.rotationRadians !== 0 ||
    environment.showSkybox !== false
  ) {
    throw new Error('Plan 018 exact reused HDR contract changed');
  }
  const lighting = state.lighting;
  if (
    lighting?.exposure !== 1 ||
    lighting.ambientOcclusion !== false ||
    lighting.keyLightIntensity !== 3 ||
    JSON.stringify(lighting.keyLightColorLinear) !==
      JSON.stringify([1, 1, 1]) ||
    JSON.stringify(lighting.keyLightDirectionFlutterSceneWorld) !==
      JSON.stringify([-0.45, -0.85, -0.35]) ||
    lighting.keyLightCastsShadow !== false
  ) {
    throw new Error('Plan 018 controlled lighting contract changed');
  }
}

function validateReferenceRenderer(renderer) {
  if (
    renderer?.name !== 'Three.js' ||
    renderer.packageVersion !== '0.167.1' ||
    renderer.revision !== '167' ||
    renderer.sourceCommit !==
      '42a2f6aac8cffebb29524d68eb7136a756f15960' ||
    renderer.packageIntegrity !==
      'sha512-gYTLJA/UQip6J/tJvl91YYqlZF47+D/kxiWrbTon35ZHlXEN0VOo+Qke2walF1/x92v55H6enomymg4Dak52kw==' ||
    renderer.backend !== 'WebGL'
  ) {
    throw new Error('Plan 018 Three.js identity is not exactly pinned');
  }
  const lockPath = path.join(repoRoot, renderer.packageLockPath);
  const lockBytes = fs.readFileSync(lockPath);
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(path.dirname(lockPath), 'package.json'), 'utf8'),
  );
  const lock = JSON.parse(lockBytes);
  const installed = lock.packages?.['node_modules/three'];
  if (
    hashBytes(lockBytes) !== renderer.packageLockSha256 ||
    packageJson.dependencies?.three !== renderer.packageVersion ||
    lock.packages?.['']?.dependencies?.three !== renderer.packageVersion ||
    installed?.version !== renderer.packageVersion ||
    installed?.integrity !== renderer.packageIntegrity
  ) {
    throw new Error('Plan 018 Three.js package or npm integrity drifted');
  }
  if (
    JSON.stringify(Object.keys(renderer.sourceSha256 ?? {})) !==
    JSON.stringify([
      'gltfLoader',
      'webglRenderer',
      'physicalSheenParsFragment',
      'physicalSheenFragment',
    ])
  ) {
    throw new Error('Plan 018 Three.js source inventory changed');
  }
  for (const [name, source] of Object.entries(renderer.sourceSha256)) {
    if (
      !isSafeRelativePath(source.path) ||
      hashBytes(fs.readFileSync(path.join(repoRoot, source.path))) !== source.sha256
    ) {
      throw new Error(`Plan 018 Three.js source hash drifted: ${name}`);
    }
  }
}

function validatePackageCameraAdapter(contract) {
  for (const [label, pathField, hashField] of [
    ['orbit camera', 'orbitCameraPath', 'orbitCameraSha256'],
    ['render surface', 'renderSurfacePath', 'renderSurfaceSha256'],
    ['adapter', 'adapterPath', 'adapterSha256'],
  ]) {
    if (
      !isSafeRelativePath(contract?.[pathField]) ||
      !sha256(contract?.[hashField])
    ) {
      throw new Error(`Plan 018 package ${label} provenance is invalid`);
    }
  }
  if (
    JSON.stringify(contract.adapterCameraFields) !==
    JSON.stringify([
      'position',
      'target',
      'up',
      'verticalFovRadians',
      'near',
      'far',
    ])
  ) {
    throw new Error('Plan 018 adapter camera field contract changed');
  }
}

function validateAssetSource(source) {
  if (
    source?.repository !== 'KhronosGroup/glTF-Sample-Assets' ||
    source.commit !== '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf'
  ) {
    throw new Error('Plan 018 Khronos asset source drifted');
  }
}

function validateModel(modelId, model, collectiveCoverage) {
  if (
    !['khronos-official-glb', 'khronos-official-multifile-gltf']
      .includes(model?.sourceKind) ||
    !isSafeRelativePath(model.path) ||
    !isSafeRelativePath(model.licensePath) ||
    !model.sourcePath?.startsWith('Models/') ||
    !sha256(model.sha256) ||
    !sha256(model.licenseSha256) ||
    !Number.isInteger(model.byteLength) ||
    model.byteLength <= 0 ||
    !Number.isInteger(model.licenseByteLength) ||
    model.licenseByteLength <= 0
  ) {
    throw new Error(`Plan 018 model provenance is invalid: ${modelId}`);
  }
  const bytes = fs.readFileSync(path.join(repoRoot, model.path));
  const licenseBytes = fs.readFileSync(path.join(repoRoot, model.licensePath));
  if (
    bytes.length !== model.byteLength ||
    hashBytes(bytes) !== model.sha256 ||
    licenseBytes.length !== model.licenseByteLength ||
    hashBytes(licenseBytes) !== model.licenseSha256
  ) {
    throw new Error(`Plan 018 model or license bytes drifted: ${modelId}`);
  }
  validateBounds(modelId, 'sourceBounds', model.sourceBounds);
  validateBounds(modelId, 'sheenPrimitiveBounds', model.sheenPrimitiveBounds);
  if (JSON.stringify(Object.keys(model.cameras ?? {})) !== JSON.stringify(['close', 'grazing'])) {
    throw new Error(`Plan 018 close/grazing camera catalog changed: ${modelId}`);
  }
  for (const [view, camera] of Object.entries(model.cameras)) {
    if (
      camera?.coordinateSpace !== 'flutterSceneWorld' ||
      !vec3(camera.position) ||
      !vec3(camera.target) ||
      sameVec3(camera.position, camera.target)
    ) {
      throw new Error(`Plan 018 ${modelId}/${view} camera is invalid`);
    }
  }

  const sourceJson = parseGlbJson(bytes);
  const authoredIndices = [];
  for (const [index, material] of (sourceJson.materials ?? []).entries()) {
    const extension = material.extensions?.KHR_materials_sheen;
    if (extension == null) continue;
    authoredIndices.push(index);
    for (const field of requiredSheenInputs) {
      if (Object.hasOwn(extension, field)) collectiveCoverage[field] = true;
    }
  }
  if (JSON.stringify(authoredIndices) !== JSON.stringify(model.sheenMaterialIndices)) {
    throw new Error(`Plan 018 authored sheen material indices drifted: ${modelId}`);
  }
  if (modelId === 'sheen_cloth') validateSheenCloth(model, sourceJson);
  return sourceJson;
}

function validateSheenCloth(model, sourceJson) {
  if (
    model.sourceKind !== 'khronos-official-multifile-gltf' ||
    model.stagedArtifactKind !==
      'repository-generated-deterministic-container' ||
    model.derivedContainer?.label !==
      'repository-generated deterministic container derived from the hash-pinned official multi-file source' ||
    model.derivedContainer.sha256 !== model.sha256 ||
    !sha256(model.derivedContainer.officialSourceJsonSha256) ||
    !sha256(model.derivedContainer.officialSourceBinSha256)
  ) {
    throw new Error('Plan 018 SheenCloth derived-container contract changed');
  }
  const sheen =
    sourceJson.materials?.[0]?.extensions?.KHR_materials_sheen;
  const color = sheen?.sheenColorTexture;
  const roughness = sheen?.sheenRoughnessTexture;
  if (
    color?.index !== roughness?.index ||
    color.index !== 3 ||
    JSON.stringify(color.extensions?.KHR_texture_transform) !==
      JSON.stringify({ scale: [30, -30] }) ||
    JSON.stringify(roughness.extensions?.KHR_texture_transform) !==
      JSON.stringify({ scale: [30, -30] })
  ) {
    throw new Error('Plan 018 SheenCloth authored dual-map contract changed');
  }
}

function validateManifestCrossCheck(state) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const corpus = manifest.plan018SheenCorpus;
  if (
    corpus?.sourceRepository?.name !== state.assetSource.repository ||
    corpus.sourceRepository.commit !== state.assetSource.commit ||
    JSON.stringify((corpus.fixtures ?? []).map((fixture) => fixture.id)) !==
      JSON.stringify(expectedModelIds)
  ) {
    throw new Error('Plan 018 state does not match the tracked corpus manifest');
  }
  for (const fixture of corpus.fixtures) {
    const model = state.models[fixture.id];
    const source = fixture.sourceFiles?.[0];
    const derived = fixture.derivedArtifact;
    const expectedPath = derived?.outputPath ??
      `${fixture.stagingDirectory}/source/${path.posix.basename(source.path)}`;
    const expectedSha256 = derived?.sha256 ?? source?.sha256;
    const expectedByteLength = derived?.byteLength ?? source?.byteLength;
    const expectedLicensePath = `${fixture.stagingDirectory}/source/LICENSE.md`;
    if (
      model?.name !== fixture.name ||
      model.sourceKind !== fixture.sourceKind ||
      model.path !== expectedPath ||
      model.sourcePath !== source?.path ||
      model.sha256 !== expectedSha256 ||
      model.byteLength !== expectedByteLength ||
      model.licensePath !== expectedLicensePath ||
      model.licenseSha256 !== fixture.license?.evidenceSha256 ||
      model.licenseByteLength !== fixture.license?.evidenceByteLength
    ) {
      throw new Error(`Plan 018 state/manifest model drifted: ${fixture.id}`);
    }
    if (
      fixture.id === 'sheen_cloth' &&
      (model.stagedArtifactKind !== derived?.artifactKind ||
        model.derivedContainer?.label !== derived?.provenance ||
        model.derivedContainer?.sha256 !== derived?.sha256)
    ) {
      throw new Error('Plan 018 SheenCloth derived state/manifest drifted');
    }
  }
}

function validateToyCarFocus(model, sourceJson) {
  if (
    model.focus?.material !== 'Fabric' ||
    model.focus.materialIndex !== 1 ||
    model.focus.extension !== 'KHR_materials_sheen' ||
    model.focus.ownership !== 'authored-data' ||
    model.focus.bounds !== 'sheenPrimitiveBounds' ||
    model.context?.mode !== 'full-scene' ||
    model.context.bounds !== 'sourceBounds' ||
    !vec3(model.context.camera?.position) ||
    !vec3(model.context.camera?.target) ||
    model.context.camera.coordinateSpace !== 'flutterSceneWorld' ||
    JSON.stringify(model.context.separateMaterialRoles) !==
      JSON.stringify({ clearcoat: ['ToyCar'], transmission: ['Glass'] })
  ) {
    throw new Error('Plan 018 ToyCar focus/context contract changed');
  }
  const roles = Object.fromEntries(
    (sourceJson.materials ?? []).map((material) => [
      material.name,
      Object.keys(material.extensions ?? {}),
    ]),
  );
  if (
    !roles.Fabric?.includes('KHR_materials_sheen') ||
    roles.Fabric.includes('KHR_materials_clearcoat') ||
    roles.Fabric.includes('KHR_materials_transmission') ||
    !roles.ToyCar?.includes('KHR_materials_clearcoat') ||
    !roles.Glass?.includes('KHR_materials_transmission')
  ) {
    throw new Error('Plan 018 ToyCar authored material roles drifted');
  }
}

function validateBounds(modelId, label, bounds) {
  if (
    !vec3(bounds?.min) ||
    !vec3(bounds.max) ||
    !vec3(bounds.center) ||
    !finitePositive(bounds.radius) ||
    bounds.min.some((value, index) => value > bounds.max[index])
  ) {
    throw new Error(`Plan 018 ${modelId}/${label} is invalid`);
  }
}

function parseGlbJson(bytes) {
  if (
    bytes.length < 20 ||
    bytes.readUInt32LE(0) !== 0x46546c67 ||
    bytes.readUInt32LE(4) !== 2 ||
    bytes.readUInt32LE(16) !== 0x4e4f534a
  ) {
    throw new Error('Plan 018 model is not a GLB 2.0 JSON container');
  }
  const jsonLength = bytes.readUInt32LE(12);
  return JSON.parse(
    bytes.subarray(20, 20 + jsonLength).toString('utf8').replace(/\u0000+$/u, ''),
  );
}

function isSafeRelativePath(value) {
  if (typeof value !== 'string' || value === '' || path.isAbsolute(value)) {
    return false;
  }
  const segments = value.split('/');
  return !value.includes('\\') &&
    segments.every((segment) => segment !== '' && segment !== '.' && segment !== '..');
}

function sha256(value) {
  return /^[a-f0-9]{64}$/.test(value ?? '');
}

function finitePositive(value) {
  return Number.isFinite(value) && value > 0;
}

function vec3(value) {
  return Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
}

function sameVec3(first, second) {
  return first.every((value, index) => value === second[index]);
}
