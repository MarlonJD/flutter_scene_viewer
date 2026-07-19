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
    'plan016_controlled_comparison_state.json',
);
export const outputRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/' +
    'plan016_controlled_comparison',
);
export const hdrPath = path.join(outputRoot, 'plan016_controlled_studio.hdr');

const expectedModelIds = Object.freeze([
  'control_transmission_off',
  'control_thin',
  'control_ior_low',
  'control_ior_high',
  'control_volume',
  'control_attenuation_tinted',
  'control_rough_high',
  'control_normal_tilted',
  'control_texture_channels',
  'control_scale_one',
  'control_scale_two',
  'control_combined_clearcoat',
  'transmission_test',
  'attenuation_test',
  'glass_vase_flowers',
  'toycar',
]);

export function loadPlan016ControlledComparisonState() {
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  validatePlan016ControlledComparisonState(state);
  return state;
}

export function validatePlan016ControlledComparisonState(state) {
  if (
    state?.schemaVersion !== 1 ||
    state.name !==
      'plan016_renderer_native_transmission_volume_controlled_comparison'
  ) {
    throw new Error('Plan 016 controlled comparison identity is invalid');
  }
  if (state.toneMapping !== 'pbrNeutral' || state.outputColorSpace !== 'sRGB') {
    throw new Error('Plan 016 must use PBR Neutral and sRGB output');
  }
  validateViewport(state.viewport);
  validateCamera(state.camera);
  validateCoordinateMapping(state.rendererCoordinateMapping);
  validateEnvironment(state.environment);
  validateLighting(state.lighting);
  if (
    JSON.stringify(state.renderPasses) !==
    JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Plan 016 render passes changed');
  }
  validateReferenceRenderer(state.referenceRenderer);
  validateSources(state.assetSources);
  validateFrames(state.frames);
  if (
    JSON.stringify(Object.keys(state.models ?? {})) !==
    JSON.stringify(expectedModelIds)
  ) {
    throw new Error('Plan 016 model catalog or order changed');
  }
  for (const [modelId, model] of Object.entries(state.models)) {
    validateModel(state, modelId, model);
  }
  validateMetrics(state.comparisonMetrics, state.models);
}

export function resolveMaterialAssertions(state, profileName) {
  const raw = state.materialAssertionProfiles?.[profileName];
  if (raw == null) {
    throw new Error(`Unknown Plan 016 material assertion profile: ${profileName}`);
  }
  const entries = Array.isArray(raw) ? raw : [raw];
  return entries.map((entry) => resolveAssertion(state, entry, [profileName]));
}

export function modelCatalog(state) {
  return Object.fromEntries(
    Object.entries(state.models).map(([id, model]) => [
      id,
      {
        ...model,
        absolutePath: path.join(repoRoot, model.path),
        cameraFrame: state.frames[model.cameraFrame],
        materialAssertions: resolveMaterialAssertions(
          state,
          model.materialAssertionProfile,
        ),
      },
    ]),
  );
}

export function plan016StateHash() {
  return hashBytes(fs.readFileSync(statePath));
}

export function generatePlan016ControlledStudioHdr(state) {
  validatePlan016ControlledComparisonState(state);
  const bytes = generateControlledStudioHdr(loadPlan015State());
  const sha256 = hashBytes(bytes);
  if (sha256 !== state.environment.sha256) {
    throw new Error(
      `Plan 016 reused HDR hash drifted: ${sha256} != ${state.environment.sha256}`,
    );
  }
  return bytes;
}

export function writePlan016ControlledStudioHdr(
  state,
  destination = hdrPath,
) {
  const bytes = generatePlan016ControlledStudioHdr(state);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, bytes);
  return {
    bytes,
    sha256: hashBytes(bytes),
    destination,
  };
}

export function hashBytes(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function resolveAssertion(state, rawEntry, stack) {
  if (!isObject(rawEntry)) {
    throw new Error(`Plan 016 material assertion ${stack.join(' -> ')} is invalid`);
  }
  const entry = { ...rawEntry };
  const baseName = entry.extends;
  delete entry.extends;
  if (baseName == null) return entry;
  if (stack.includes(baseName)) {
    throw new Error(`Plan 016 assertion profile cycle: ${[...stack, baseName].join(' -> ')}`);
  }
  const base = state.materialAssertionProfiles?.[baseName];
  if (base == null || Array.isArray(base)) {
    throw new Error(`Plan 016 assertion base must be one object: ${baseName}`);
  }
  return {
    ...resolveAssertion(state, base, [...stack, baseName]),
    ...entry,
  };
}

function validateViewport(viewport) {
  for (const key of ['logicalWidth', 'logicalHeight', 'devicePixelRatio']) {
    if (!Number.isInteger(viewport?.[key]) || viewport[key] <= 0) {
      throw new Error(`Plan 016 viewport ${key} must be a positive integer`);
    }
  }
}

function validateCamera(camera) {
  if (
    camera?.fit !== 'frozenCanonicalBoundingSphere' ||
    !finitePositive(camera.verticalFovDegrees) ||
    camera.verticalFovDegrees >= 180 ||
    !finitePositive(camera.fitPadding) ||
    !Number.isFinite(camera.yawRadians) ||
    !Number.isFinite(camera.pitchRadians) ||
    !finitePositive(camera.near) ||
    !finitePositive(camera.far) ||
    camera.near >= camera.far
  ) {
    throw new Error('Plan 016 camera contract is invalid');
  }
}

function validateCoordinateMapping(mapping) {
  if (
    mapping?.flutterSceneImportedGltfRoot !== 'mirrorZ' ||
    mapping.threejsFromFlutterSceneWorld !==
      'mirrorZCameraLightEnvironmentAndBackdrop'
  ) {
    throw new Error('Plan 016 coordinate mapping is invalid');
  }
}

function validateEnvironment(environment) {
  if (
    environment?.kind !== 'generatedRadianceHdr' ||
    environment.generator !== 'plan015_controlled_studio_v1_reused_exact_bytes' ||
    environment.width !== 512 ||
    environment.height !== 256 ||
    !/^[a-f0-9]{64}$/.test(environment.sha256 ?? '') ||
    environment.worldOrientation !== 'flutterSceneWorldAtanZOverX' ||
    environment.threejsLongitudeCorrection !== 'mirrorDecodedColumns' ||
    !finiteNonNegative(environment.intensity) ||
    !Number.isFinite(environment.rotationRadians) ||
    environment.showSkybox !== false
  ) {
    throw new Error('Plan 016 environment contract is invalid');
  }
}

function validateLighting(lighting) {
  if (
    !finitePositive(lighting?.exposure) ||
    lighting.ambientOcclusion !== false ||
    !finiteNonNegative(lighting.keyLightIntensity) ||
    !linearRgb(lighting.keyLightColorLinear) ||
    !direction(lighting.keyLightDirection) ||
    lighting.keyLightCastsShadow !== false
  ) {
    throw new Error('Plan 016 lighting contract is invalid');
  }
}

function validateReferenceRenderer(renderer) {
  if (
    renderer?.name !== 'Three.js' ||
    renderer.packageVersion !== '0.167.1' ||
    renderer.revision !== '167' ||
    !renderer.packageIntegrity?.startsWith('sha512-')
  ) {
    throw new Error('Plan 016 Three.js identity is not exactly pinned');
  }
  const lockPath = path.join(repoRoot, renderer.packageLockPath);
  const lockBytes = fs.readFileSync(lockPath);
  if (hashBytes(lockBytes) !== renderer.packageLockSha256) {
    throw new Error('Plan 016 package-lock hash drifted');
  }
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(path.dirname(lockPath), 'package.json'), 'utf8'),
  );
  const lock = JSON.parse(lockBytes);
  const installed = lock.packages?.['node_modules/three'];
  if (
    packageJson.dependencies?.three !== renderer.packageVersion ||
    lock.packages?.['']?.dependencies?.three !== renderer.packageVersion ||
    installed?.version !== renderer.packageVersion ||
    installed?.integrity !== renderer.packageIntegrity
  ) {
    throw new Error('Plan 016 Three.js semver or npm integrity drifted');
  }
}

function validateSources(sources) {
  if (
    sources?.khronos?.repository !== 'KhronosGroup/glTF-Sample-Assets' ||
    sources.khronos.commit !==
      '2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf'
  ) {
    throw new Error('Plan 016 Khronos source commit drifted');
  }
  const synthetic = sources.synthetic;
  const generatorPath = path.join(repoRoot, synthetic.generatorPath);
  if (
    synthetic.license !== 'repository test fixture' ||
    hashBytes(fs.readFileSync(generatorPath)) !== synthetic.generatorSha256
  ) {
    throw new Error('Plan 016 synthetic generator provenance drifted');
  }
}

function validateFrames(frames) {
  for (const [name, frame] of Object.entries(frames ?? {})) {
    if (!vec3(frame?.centerFlutterSceneWorld) || !finitePositive(frame.radius)) {
      throw new Error(`Plan 016 frame is invalid: ${name}`);
    }
  }
}

function validateModel(state, modelId, model) {
  if (
    !['synthetic', 'khronos'].includes(model?.kind) ||
    !/^[a-f0-9]{64}$/.test(model.sha256 ?? '') ||
    !Number.isInteger(model.byteLength) ||
    model.byteLength <= 0 ||
    !Array.isArray(model.extensions) ||
    !vec3(model.sourceBoundsThree?.center) ||
    !finitePositive(model.sourceBoundsThree.radius) ||
    state.frames[model.cameraFrame] == null
  ) {
    throw new Error(`Plan 016 model contract is invalid: ${modelId}`);
  }
  const bytes = fs.readFileSync(path.join(repoRoot, model.path));
  if (bytes.length !== model.byteLength || hashBytes(bytes) !== model.sha256) {
    throw new Error(`Plan 016 model bytes drifted: ${modelId}`);
  }
  if (model.kind === 'khronos') {
    const license = fs.readFileSync(path.join(repoRoot, model.licensePath));
    if (
      !model.sourcePath?.startsWith('Models/') ||
      hashBytes(license) !== model.licenseSha256
    ) {
      throw new Error(`Plan 016 Khronos license provenance drifted: ${modelId}`);
    }
  }
  const assertions = resolveMaterialAssertions(
    state,
    model.materialAssertionProfile,
  );
  if (assertions.length === 0) {
    throw new Error(`Plan 016 model has no material assertion: ${modelId}`);
  }
  for (const assertion of assertions) {
    for (const field of [
      'name',
      'isMeshPhysicalMaterial',
      'transmission',
      'ior',
      'thickness',
      'attenuationDistance',
      'attenuationColor',
      'transmissionMap',
      'thicknessMap',
      'normalMap',
      'clearcoat',
      'clearcoatRoughness',
      'metalness',
      'roughness',
    ]) {
      if (!(field in assertion)) {
        throw new Error(`Plan 016 ${modelId} assertion omits ${field}`);
      }
    }
    if (assertion.isMeshPhysicalMaterial !== true) {
      throw new Error(`Plan 016 ${modelId} must assert MeshPhysicalMaterial`);
    }
  }
}

function validateMetrics(metrics, models) {
  if (
    !['candidate-before-flutter-capture', 'calibrated-before-flutter-capture']
      .includes(metrics?.calibrationStatus)
  ) {
    throw new Error('Plan 016 comparison metric calibration status is invalid');
  }
  for (const pair of Object.values(metrics.calibrationControlPairs ?? {})) {
    if (
      !Array.isArray(pair) ||
      pair.length !== 2 ||
      pair.some((modelId) => models[modelId] == null)
    ) {
      throw new Error('Plan 016 calibration control pair is invalid');
    }
  }
  const roi = metrics.syntheticGlassRoiNormalized;
  if (
    !finiteUnit(roi?.left) ||
    !finiteUnit(roi.top) ||
    !finitePositive(roi.width) ||
    !finitePositive(roi.height) ||
    roi.left + roi.width > 1 ||
    roi.top + roi.height > 1
  ) {
    throw new Error('Plan 016 synthetic glass ROI is invalid');
  }
  for (const [name, value] of Object.entries(metrics.thresholds ?? {})) {
    if (!finiteNonNegative(value)) {
      throw new Error(`Plan 016 comparison threshold is invalid: ${name}`);
    }
  }
  if (metrics.calibrationStatus === 'calibrated-before-flutter-capture') {
    const signals = metrics.calibratedThreejsControlSignals;
    if (
      !isObject(signals) ||
      Object.keys(signals).length !== 10 ||
      Object.values(signals).some((value) => !finiteNonNegative(value))
    ) {
      throw new Error('Plan 016 calibrated Three.js control signals are invalid');
    }
  }
}

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}

function finitePositive(value) {
  return Number.isFinite(value) && value > 0;
}

function finiteNonNegative(value) {
  return Number.isFinite(value) && value >= 0;
}

function finiteUnit(value) {
  return Number.isFinite(value) && value >= 0 && value <= 1;
}

function vec3(value) {
  return Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
}

function linearRgb(value) {
  return Array.isArray(value) && value.length === 3 && value.every(finiteNonNegative);
}

function direction(value) {
  return vec3(value) && value.some((component) => component !== 0);
}
