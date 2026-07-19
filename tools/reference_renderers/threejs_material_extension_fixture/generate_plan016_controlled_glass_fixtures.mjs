import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '../../..');
const outputRoot = path.join(
  repoRoot,
  'tools/out/material_extension_acceptance/' +
    'plan016_renderer_native_transmission/synthetic',
);

const textureTransform = Object.freeze({
  offset: [0.125, 0.25],
  scale: [0.75, 0.5],
  rotation: 0.2,
});

const variants = Object.freeze({
  control_transmission_off: {
    transmission: 0,
    ior: 1.5,
    thickness: 0,
  },
  control_thin: {
    transmission: 1,
    ior: 1.5,
    thickness: 0,
  },
  control_ior_low: {
    transmission: 1,
    ior: 1.1,
    thickness: 0.65,
  },
  control_ior_high: {
    transmission: 1,
    ior: 2,
    thickness: 0.65,
  },
  control_volume: {
    transmission: 1,
    ior: 1.5,
    thickness: 0.65,
  },
  control_attenuation_tinted: {
    transmission: 1,
    ior: 1.5,
    thickness: 0.65,
    attenuationColor: [0.18, 0.58, 0.98],
    attenuationDistance: 0.45,
  },
  control_rough_high: {
    transmission: 1,
    ior: 1.5,
    thickness: 0,
    roughness: 0.62,
  },
  control_normal_tilted: {
    transmission: 1,
    ior: 1.5,
    thickness: 0,
    normalTexture: true,
  },
  control_texture_channels: {
    transmission: 1,
    ior: 1.5,
    thickness: 0.8,
    transmissionTexture: true,
    thicknessTexture: true,
  },
  control_scale_one: {
    transmission: 1,
    ior: 1.5,
    thickness: 0.55,
    attenuationColor: [0.42, 0.78, 0.96],
    attenuationDistance: 1,
    glassScale: 0.78,
  },
  control_scale_two: {
    transmission: 1,
    ior: 1.5,
    thickness: 0.55,
    attenuationColor: [0.42, 0.78, 0.96],
    attenuationDistance: 1,
    glassScale: 1.16,
  },
  control_combined_clearcoat: {
    transmission: 0.82,
    ior: 1.62,
    thickness: 0.58,
    attenuationColor: [0.65, 0.88, 0.98],
    attenuationDistance: 1.4,
    roughness: 0.16,
    baseColor: [0.72, 0.9, 1, 1],
    clearcoat: 0.75,
    clearcoatRoughness: 0.11,
  },
});

function main() {
  fs.mkdirSync(outputRoot, { recursive: true });
  const manifest = {
    schemaVersion: 1,
    generator: path.relative(repoRoot, fileURLToPath(import.meta.url)),
    variants: {},
  };

  for (const [id, sourceConfig] of Object.entries(variants)) {
    const config = {
      roughness: 0.06,
      metallic: 0,
      baseColor: [0.92, 0.97, 1, 1],
      glassScale: 1,
      clearcoat: 0,
      clearcoatRoughness: 0,
      ...sourceConfig,
    };
    const bytes = buildFixture(id, config);
    const destination = path.join(outputRoot, `${id}.glb`);
    fs.writeFileSync(destination, bytes);
    manifest.variants[id] = {
      path: path.relative(repoRoot, destination),
      sha256: hash(bytes),
      byteLength: bytes.length,
      material: config,
    };
  }

  const manifestPath = path.join(outputRoot, 'manifest.json');
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `Plan 016 synthetic glass fixtures: ${Object.keys(variants).length} hash-pinned GLBs OK`,
  );
}

function buildFixture(id, config) {
  const binary = new BinaryBuilder();
  const sphere = sphereGeometry(48, 24);
  const plane = planeGeometry();

  const spherePositions = binary.appendFloat32(sphere.positions);
  const sphereNormals = binary.appendFloat32(sphere.normals);
  const sphereUvs = binary.appendFloat32(sphere.uvs);
  const sphereIndices = binary.appendUint16(sphere.indices);
  const planePositions = binary.appendFloat32(plane.positions);
  const planeNormals = binary.appendFloat32(plane.normals);
  const planeUvs = binary.appendFloat32(plane.uvs);
  const planeIndices = binary.appendUint16(plane.indices);

  const transmissionPng = checkerPng(
    8,
    8,
    [255, 37, 211, 255],
    [32, 229, 17, 255],
  );
  const thicknessPng = checkerPng(
    8,
    8,
    [243, 255, 19, 255],
    [17, 48, 237, 255],
  );
  const normalPng = checkerPng(
    8,
    8,
    [192, 112, 238, 255],
    [164, 142, 246, 255],
  );
  const transmissionImage = binary.appendBytes(transmissionPng);
  const thicknessImage = binary.appendBytes(thicknessPng);
  const normalImage = binary.appendBytes(normalPng);

  const bufferViews = [
    bufferView(spherePositions, 34962),
    bufferView(sphereNormals, 34962),
    bufferView(sphereUvs, 34962),
    bufferView(sphereIndices, 34963),
    bufferView(planePositions, 34962),
    bufferView(planeNormals, 34962),
    bufferView(planeUvs, 34962),
    bufferView(planeIndices, 34963),
    bufferView(transmissionImage),
    bufferView(thicknessImage),
    bufferView(normalImage),
  ];
  const accessors = [
    accessor(0, 5126, sphere.positions.length / 3, 'VEC3', [-1, -1, -1], [1, 1, 1]),
    accessor(1, 5126, sphere.normals.length / 3, 'VEC3'),
    accessor(2, 5126, sphere.uvs.length / 2, 'VEC2'),
    accessor(3, 5123, sphere.indices.length, 'SCALAR'),
    accessor(4, 5126, 4, 'VEC3', [-1, -1, 0], [1, 1, 0]),
    accessor(5, 5126, 4, 'VEC3'),
    accessor(6, 5126, 4, 'VEC2'),
    accessor(7, 5123, 6, 'SCALAR'),
  ];

  const materials = [
    glassMaterial(config),
    opaqueMaterial('backdrop-neutral', [0.18, 0.2, 0.24, 1]),
    opaqueMaterial('feature-red', [0.95, 0.055, 0.035, 1]),
    opaqueMaterial('feature-green', [0.035, 0.9, 0.12, 1]),
    opaqueMaterial('feature-blue', [0.035, 0.17, 0.95, 1]),
    opaqueMaterial('feature-white', [0.92, 0.92, 0.92, 1]),
    opaqueMaterial('feature-black', [0.008, 0.008, 0.01, 1]),
  ];
  const meshes = [
    {
      name: 'glass-sphere',
      primitives: [{
        attributes: { POSITION: 0, NORMAL: 1, TEXCOORD_0: 2 },
        indices: 3,
        material: 0,
      }],
    },
    ...materials.slice(1).map((material, index) => ({
      name: material.name,
      primitives: [{
        attributes: { POSITION: 4, NORMAL: 5, TEXCOORD_0: 6 },
        indices: 7,
        material: index + 1,
      }],
    })),
  ];
  const nodes = [
    {
      name: 'Glass',
      mesh: 0,
      scale: [config.glassScale, config.glassScale, config.glassScale],
    },
    fixtureNode('Backdrop', 1, [0, 0, 1.58], [1.78, 1.78, 1]),
    fixtureNode('RedFeature', 2, [-0.82, 0, 1.55], [0.12, 1.52, 1]),
    fixtureNode('GreenFeature', 3, [-0.41, 0, 1.55], [0.1, 1.52, 1]),
    fixtureNode('BlueFeature', 4, [0, 0, 1.55], [0.1, 1.52, 1]),
    fixtureNode('WhiteFeature', 5, [0.41, 0, 1.55], [0.1, 1.52, 1]),
    fixtureNode('BlackFeature', 6, [0.82, 0, 1.55], [0.12, 1.52, 1]),
    fixtureNode('HorizontalWhite', 5, [0, 0.56, 1.54], [1.52, 0.075, 1]),
    fixtureNode('HorizontalBlack', 6, [0, -0.56, 1.54], [1.52, 0.075, 1]),
  ];

  const extensionsUsed = [
    'KHR_materials_transmission',
    'KHR_materials_volume',
    'KHR_materials_ior',
  ];
  if (config.transmissionTexture || config.thicknessTexture) {
    extensionsUsed.push('KHR_texture_transform');
  }
  if (config.clearcoat > 0) extensionsUsed.push('KHR_materials_clearcoat');

  const json = {
    asset: {
      version: '2.0',
      generator: 'flutter_scene_viewer Plan 016 controlled glass fixture v1',
      extras: { fixtureId: id },
    },
    extensionsUsed,
    scene: 0,
    scenes: [{ nodes: nodes.map((_, index) => index) }],
    nodes,
    meshes,
    materials,
    samplers: [{
      magFilter: 9729,
      minFilter: 9987,
      wrapS: 10497,
      wrapT: 10497,
    }],
    textures: [
      { name: 'transmission-red-channel', sampler: 0, source: 0 },
      { name: 'thickness-green-channel', sampler: 0, source: 1 },
      { name: 'tilted-normal', sampler: 0, source: 2 },
    ],
    images: [
      { name: 'transmission-red-channel', mimeType: 'image/png', bufferView: 8 },
      { name: 'thickness-green-channel', mimeType: 'image/png', bufferView: 9 },
      { name: 'tilted-normal', mimeType: 'image/png', bufferView: 10 },
    ],
    buffers: [{ byteLength: binary.length }],
    bufferViews,
    accessors,
  };
  return glbBytes(json, binary.bytes());
}

function glassMaterial(config) {
  const transmissionInfo = { transmissionFactor: config.transmission };
  if (config.transmissionTexture) {
    transmissionInfo.transmissionTexture = transformedTextureInfo(0);
  }
  const volumeInfo = { thicknessFactor: config.thickness };
  if (config.thicknessTexture) {
    volumeInfo.thicknessTexture = transformedTextureInfo(1);
  }
  if (config.attenuationColor != null) {
    volumeInfo.attenuationColor = config.attenuationColor;
  }
  if (config.attenuationDistance != null) {
    volumeInfo.attenuationDistance = config.attenuationDistance;
  }
  const extensions = {
    KHR_materials_transmission: transmissionInfo,
    KHR_materials_volume: volumeInfo,
    KHR_materials_ior: { ior: config.ior },
  };
  if (config.clearcoat > 0) {
    extensions.KHR_materials_clearcoat = {
      clearcoatFactor: config.clearcoat,
      clearcoatRoughnessFactor: config.clearcoatRoughness,
    };
  }
  const material = {
    name: 'ControlledGlass',
    doubleSided: config.thickness === 0,
    pbrMetallicRoughness: {
      baseColorFactor: config.baseColor,
      metallicFactor: config.metallic,
      roughnessFactor: config.roughness,
    },
    extensions,
  };
  if (config.normalTexture) {
    material.normalTexture = { index: 2, texCoord: 0, scale: 1 };
  }
  return material;
}

function transformedTextureInfo(index) {
  return {
    index,
    texCoord: 0,
    extensions: {
      KHR_texture_transform: textureTransform,
    },
  };
}

function opaqueMaterial(name, baseColorFactor) {
  return {
    name,
    pbrMetallicRoughness: {
      baseColorFactor,
      metallicFactor: 0,
      roughnessFactor: 1,
    },
  };
}

function fixtureNode(name, mesh, translation, scale) {
  return { name, mesh, translation, scale };
}

function sphereGeometry(widthSegments, heightSegments) {
  const positions = [];
  const normals = [];
  const uvs = [];
  const indices = [];
  for (let row = 0; row <= heightSegments; row += 1) {
    const v = row / heightSegments;
    const theta = v * Math.PI;
    const sinTheta = Math.sin(theta);
    const cosTheta = Math.cos(theta);
    for (let column = 0; column <= widthSegments; column += 1) {
      const u = column / widthSegments;
      const phi = u * Math.PI * 2;
      const x = sinTheta * Math.cos(phi);
      const y = cosTheta;
      const z = sinTheta * Math.sin(phi);
      positions.push(x, y, z);
      normals.push(x, y, z);
      uvs.push(u, 1 - v);
    }
  }
  const stride = widthSegments + 1;
  for (let row = 0; row < heightSegments; row += 1) {
    for (let column = 0; column < widthSegments; column += 1) {
      const a = row * stride + column;
      const b = (row + 1) * stride + column;
      const c = b + 1;
      const d = a + 1;
      if (row !== 0) indices.push(a, d, b);
      if (row !== heightSegments - 1) indices.push(d, c, b);
    }
  }
  return { positions, normals, uvs, indices };
}

function planeGeometry() {
  return {
    positions: [-1, -1, 0, -1, 1, 0, 1, 1, 0, 1, -1, 0],
    normals: [0, 0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1],
    uvs: [0, 0, 0, 1, 1, 1, 1, 0],
    indices: [0, 1, 2, 0, 2, 3],
  };
}

function checkerPng(width, height, first, second) {
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const color = (x + y) % 2 === 0 ? first : second;
      const offset = (y * width + x) * 4;
      rgba.set(color, offset);
    }
  }
  return pngBytes(width, height, rgba);
}

function pngBytes(width, height, rgba) {
  const scanlines = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y += 1) {
    const outputOffset = y * (1 + width * 4);
    scanlines[outputOffset] = 0;
    rgba.copy(scanlines, outputOffset + 1, y * width * 4, (y + 1) * width * 4);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk('IHDR', header),
    pngChunk('IDAT', zlib.deflateSync(scanlines)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, 'ascii');
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  typeBytes.copy(chunk, 4);
  data.copy(chunk, 8);
  chunk.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 8 + data.length);
  return chunk;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function accessor(bufferViewIndex, componentType, count, type, min, max) {
  const value = { bufferView: bufferViewIndex, componentType, count, type };
  if (min != null) value.min = min;
  if (max != null) value.max = max;
  return value;
}

function bufferView(slice, target) {
  const value = {
    buffer: 0,
    byteOffset: slice.offset,
    byteLength: slice.length,
  };
  if (target != null) value.target = target;
  return value;
}

function glbBytes(json, binary) {
  const jsonBytes = Buffer.from(JSON.stringify(json), 'utf8');
  const paddedJsonLength = align4(jsonBytes.length);
  const paddedBinaryLength = align4(binary.length);
  const totalLength = 12 + 8 + paddedJsonLength + 8 + paddedBinaryLength;
  const output = Buffer.alloc(totalLength, 0);
  output.writeUInt32LE(0x46546c67, 0);
  output.writeUInt32LE(2, 4);
  output.writeUInt32LE(totalLength, 8);
  output.writeUInt32LE(paddedJsonLength, 12);
  output.writeUInt32LE(0x4e4f534a, 16);
  jsonBytes.copy(output, 20);
  output.fill(0x20, 20 + jsonBytes.length, 20 + paddedJsonLength);
  const binaryHeader = 20 + paddedJsonLength;
  output.writeUInt32LE(paddedBinaryLength, binaryHeader);
  output.writeUInt32LE(0x004e4942, binaryHeader + 4);
  binary.copy(output, binaryHeader + 8);
  return output;
}

function align4(value) {
  return (value + 3) & ~3;
}

function hash(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

class BinaryBuilder {
  constructor() {
    this.parts = [];
    this.length = 0;
  }

  appendFloat32(values) {
    const bytes = Buffer.alloc(values.length * 4);
    values.forEach((value, index) => bytes.writeFloatLE(value, index * 4));
    return this.appendBytes(bytes);
  }

  appendUint16(values) {
    const bytes = Buffer.alloc(values.length * 2);
    values.forEach((value, index) => bytes.writeUInt16LE(value, index * 2));
    return this.appendBytes(bytes);
  }

  appendBytes(bytes) {
    this.pad4();
    const slice = { offset: this.length, length: bytes.length };
    this.parts.push(bytes);
    this.length += bytes.length;
    return slice;
  }

  pad4() {
    const padding = align4(this.length) - this.length;
    if (padding === 0) return;
    this.parts.push(Buffer.alloc(padding));
    this.length += padding;
  }

  bytes() {
    this.pad4();
    return Buffer.concat(this.parts, this.length);
  }
}

main();
