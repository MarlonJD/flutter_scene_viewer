import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(scriptDir, '../../..');
export const statePath = path.join(
  repoRoot,
  'tools/material_extension_acceptance/fixtures/' +
    'plan015_controlled_comparison_state.json',
);
export const outputRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/' +
    'plan015_controlled_comparison',
);
export const hdrPath = path.join(outputRoot, 'plan015_controlled_studio.hdr');

export function loadControlledComparisonState() {
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  validateControlledComparisonState(state);
  return state;
}

export function validateControlledComparisonState(state) {
  if (state?.schemaVersion !== 1) {
    throw new Error('Plan 015 controlled comparison schemaVersion must be 1');
  }
  if (state.toneMapping !== 'pbrNeutral') {
    throw new Error('Plan 015 comparison must use Khronos PBR Neutral');
  }
  if (state.outputColorSpace !== 'sRGB') {
    throw new Error('Plan 015 comparison must resolve to sRGB');
  }
  const viewport = state.viewport;
  for (const key of ['logicalWidth', 'logicalHeight', 'devicePixelRatio']) {
    if (!Number.isInteger(viewport?.[key]) || viewport[key] <= 0) {
      throw new Error(`Plan 015 viewport ${key} must be a positive integer`);
    }
  }
  const camera = state.camera;
  if (
    camera?.fit !== 'canonicalModelBoundingSphere' ||
    !isFinitePositive(camera.verticalFovDegrees) ||
    camera.verticalFovDegrees >= 180 ||
    !isFinitePositive(camera.fitPadding) ||
    !Number.isFinite(camera.yawRadians) ||
    !Number.isFinite(camera.pitchRadians) ||
    !isFinitePositive(camera.near) ||
    !isFinitePositive(camera.far) ||
    camera.near >= camera.far
  ) {
    throw new Error('Plan 015 camera contract is invalid');
  }
  const requiredModels = [
    'clearcoat_test',
    'clearcoat_car_paint',
    'toycar',
  ];
  if (
    JSON.stringify(Object.keys(state.modelFrames ?? {})) !==
      JSON.stringify(requiredModels) ||
    requiredModels.some((modelId) => {
      const frame = state.modelFrames[modelId];
      return !isFiniteVec3(frame?.centerFlutterSceneWorld) ||
        !isFinitePositive(frame?.radius);
    })
  ) {
    throw new Error('Plan 015 canonical model frames are invalid');
  }
  const environment = state.environment;
  const coordinateMapping = state.rendererCoordinateMapping;
  if (
    coordinateMapping?.flutterSceneImportedGltfRoot !== 'mirrorZ' ||
    coordinateMapping.threejsFromFlutterSceneWorld !==
      'mirrorZCameraLightAndEnvironment'
  ) {
    throw new Error('Plan 015 renderer coordinate mapping is invalid');
  }
  if (
    environment?.kind !== 'generatedRadianceHdr' ||
    environment.generator !== 'plan015_controlled_studio_v1' ||
    environment.worldOrientation !== 'flutterSceneWorldAtanZOverX' ||
    environment.threejsLongitudeCorrection !== 'mirrorDecodedColumns' ||
    !Number.isInteger(environment.width) ||
    !Number.isInteger(environment.height) ||
    environment.width !== environment.height * 2 ||
    !isFiniteNonNegative(environment.intensity) ||
    !Number.isFinite(environment.rotationRadians) ||
    environment.showSkybox !== false
  ) {
    throw new Error('Plan 015 environment contract is invalid');
  }
  const lighting = state.lighting;
  if (
    !isFinitePositive(lighting?.exposure) ||
    lighting.ambientOcclusion !== false ||
    !isFiniteNonNegative(lighting.keyLightIntensity) ||
    !isLinearRgb(lighting.keyLightColorLinear) ||
    !isDirection(lighting.keyLightDirection) ||
    lighting.keyLightCastsShadow !== false
  ) {
    throw new Error('Plan 015 lighting contract is invalid');
  }
  if (
    JSON.stringify(state.renderPasses) !==
    JSON.stringify(['directOnly', 'iblOnly', 'combined'])
  ) {
    throw new Error('Plan 015 render passes changed');
  }
}

export function generateControlledStudioHdr(state) {
  validateControlledComparisonState(state);
  const { width, height } = state.environment;
  const header = Buffer.from(
    '#?RADIANCE\n' +
      '# flutter_scene_viewer Plan 015 controlled studio v1\n' +
      'FORMAT=32-bit_rle_rgbe\n\n' +
      `-Y ${height} +X ${width}\n`,
    'ascii',
  );
  const pixels = Buffer.alloc(width * height * 4);
  let offset = 0;
  for (let y = 0; y < height; y += 1) {
    const v = (y + 0.5) / height;
    const latitude = (0.5 - v) * Math.PI;
    for (let x = 0; x < width; x += 1) {
      const u = (x + 0.5) / width;
      const longitude = u * Math.PI * 2 - Math.PI;
      const color = controlledStudioRadiance(longitude, latitude);
      const rgbe = encodeRgbe(color);
      pixels[offset] = rgbe[0];
      pixels[offset + 1] = rgbe[1];
      pixels[offset + 2] = rgbe[2];
      pixels[offset + 3] = rgbe[3];
      offset += 4;
    }
  }
  return Buffer.concat([header, pixels]);
}

export function writeControlledStudioHdr(state, destination = hdrPath) {
  const bytes = generateControlledStudioHdr(state);
  const sha256 = hashBytes(bytes);
  if (state.environment.sha256 !== sha256) {
    throw new Error(
      'Generated Plan 015 HDR hash does not match the controlled state: ' +
        `${sha256} != ${state.environment.sha256}`,
    );
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, bytes);
  return { bytes, sha256, destination };
}

export function hashBytes(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function controlledStudioRadiance(longitude, latitude) {
  const horizon = Math.exp(-Math.pow(latitude / 0.42, 2));
  const upper = Math.max(Math.sin(latitude), 0);
  const lower = Math.max(-Math.sin(latitude), 0);
  const color = [
    0.018 + horizon * 0.055 + upper * 0.018,
    0.021 + horizon * 0.06 + upper * 0.021,
    0.026 + horizon * 0.07 + upper * 0.028,
  ];
  addPanel(color, longitude, latitude, {
    longitude: -0.72,
    latitude: 0.5,
    halfWidth: 0.34,
    halfHeight: 0.22,
    radiance: [9.0, 8.2, 7.4],
  });
  addPanel(color, longitude, latitude, {
    longitude: 1.22,
    latitude: 0.12,
    halfWidth: 0.3,
    halfHeight: 0.42,
    radiance: [2.0, 3.1, 5.2],
  });
  addPanel(color, longitude, latitude, {
    longitude: 2.58,
    latitude: 0.32,
    halfWidth: 0.25,
    halfHeight: 0.3,
    radiance: [5.0, 2.1, 1.15],
  });
  addPanel(color, longitude, latitude, {
    longitude: -2.25,
    latitude: -0.05,
    halfWidth: 0.52,
    halfHeight: 0.16,
    radiance: [1.7, 1.75, 1.8],
  });
  color[0] += lower * 0.004;
  color[1] += lower * 0.003;
  color[2] += lower * 0.002;
  return color;
}

function addPanel(color, longitude, latitude, panel) {
  const dx = Math.abs(wrapRadians(longitude - panel.longitude));
  const dy = Math.abs(latitude - panel.latitude);
  const distance = Math.max(dx / panel.halfWidth, dy / panel.halfHeight);
  const weight = 1 - smoothstep(0.72, 1, distance);
  color[0] += panel.radiance[0] * weight;
  color[1] += panel.radiance[1] * weight;
  color[2] += panel.radiance[2] * weight;
}

function encodeRgbe(color) {
  const peak = Math.max(color[0], color[1], color[2]);
  if (!(peak > 1e-32)) return [0, 0, 0, 0];
  const exponent = Math.ceil(Math.log2(peak));
  const scale = 256 / 2 ** exponent;
  return [
    clampByte(Math.floor(color[0] * scale)),
    clampByte(Math.floor(color[1] * scale)),
    clampByte(Math.floor(color[2] * scale)),
    clampByte(exponent + 128),
  ];
}

function wrapRadians(value) {
  let wrapped = value;
  while (wrapped < -Math.PI) wrapped += Math.PI * 2;
  while (wrapped > Math.PI) wrapped -= Math.PI * 2;
  return wrapped;
}

function smoothstep(edge0, edge1, value) {
  const t = Math.min(Math.max((value - edge0) / (edge1 - edge0), 0), 1);
  return t * t * (3 - 2 * t);
}

function clampByte(value) {
  return Math.min(Math.max(value, 0), 255);
}

function isFinitePositive(value) {
  return Number.isFinite(value) && value > 0;
}

function isFiniteNonNegative(value) {
  return Number.isFinite(value) && value >= 0;
}

function isLinearRgb(value) {
  return Array.isArray(value) && value.length === 3 && value.every(isFiniteNonNegative);
}

function isDirection(value) {
  return (
    Array.isArray(value) &&
    value.length === 3 &&
    value.every(Number.isFinite) &&
    value.some((component) => component !== 0)
  );
}

function isFiniteVec3(value) {
  return Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
}
