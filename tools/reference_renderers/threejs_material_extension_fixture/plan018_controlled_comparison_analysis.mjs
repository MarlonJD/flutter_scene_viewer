export const PLAN018_ANALYSIS_THRESHOLDS = Object.freeze({
  backgroundMaxChannelDeltaMin: 4 / 255,
  foregroundFractionMin: 0.001,
  foregroundWidthSpanMin: 0.02,
  foregroundHeightSpanMin: 0.02,
  luminanceP99P01Min: 0.01,
  quantizedRgbBinsMin: 16,
  intraRendererMeanAbsoluteSrgbDeltaMin: 1 / 1024,
});

export function buildPlan018ExpectedCaptureInventory(state) {
  const inventory = [];
  for (const [modelId, model] of Object.entries(state.models ?? {})) {
    for (const view of Object.keys(model.cameras ?? {})) {
      for (const pass of state.renderPasses ?? []) {
        inventory.push(captureRecord(modelId, view, pass));
      }
    }
    if (model.context?.camera != null) {
      for (const pass of state.renderPasses ?? []) {
        inventory.push(captureRecord(modelId, 'context', pass));
      }
    }
  }
  return inventory;
}

export function summarizePlan018Frame(
  image,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  const { width, height, data } = image;
  if (
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    width <= 0 ||
    height <= 0 ||
    data?.length !== width * height * 4
  ) {
    throw new Error('Plan 018 image dimensions or RGBA bytes are invalid');
  }
  const background = parseSrgbHex(image.backgroundSrgbHex ?? '#121118');
  const luminance = [];
  const quantizedBins = new Set();
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  let luminanceSum = 0;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const rgb = [data[offset], data[offset + 1], data[offset + 2]];
      const delta = Math.max(
        ...rgb.map((value, channel) =>
          Math.abs(value - background[channel]) / 255,
        ),
      );
      if (delta < thresholds.backgroundMaxChannelDeltaMin) continue;
      const pixelLuminance = srgbLuminance(rgb);
      luminance.push(pixelLuminance);
      luminanceSum += pixelLuminance;
      quantizedBins.add(
        `${rgb[0] >> 3}/${rgb[1] >> 3}/${rgb[2] >> 3}`,
      );
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }

  luminance.sort((first, second) => first - second);
  const foregroundPixels = luminance.length;
  const p01 = percentile(luminance, 0.01);
  const p50 = percentile(luminance, 0.5);
  const p95 = percentile(luminance, 0.95);
  const p99 = percentile(luminance, 0.99);
  return {
    dimensions: { width, height },
    backgroundSrgbHex: image.backgroundSrgbHex ?? '#121118',
    foregroundMaskMaxChannelDelta: thresholds.backgroundMaxChannelDeltaMin,
    foregroundPixels,
    foregroundFraction: foregroundPixels / (width * height),
    foregroundWidthSpan:
      foregroundPixels === 0 ? 0 : (maxX - minX + 1) / width,
    foregroundHeightSpan:
      foregroundPixels === 0 ? 0 : (maxY - minY + 1) / height,
    foregroundBoundsNormalized: foregroundPixels === 0
      ? null
      : {
          left: minX / width,
          top: minY / height,
          right: (maxX + 1) / width,
          bottom: (maxY + 1) / height,
        },
    meanSrgbLuminance:
      foregroundPixels === 0 ? 0 : luminanceSum / foregroundPixels,
    p01SrgbLuminance: p01,
    p50SrgbLuminance: p50,
    p95SrgbLuminance: p95,
    p99SrgbLuminance: p99,
    luminanceP99P01: p99 - p01,
    quantizedRgbBins: quantizedBins.size,
  };
}

export function buildPlan018FrameHealthChecks(
  summary,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  return [
    minimumCheck(
      'frame.foregroundFraction',
      summary.foregroundFraction,
      thresholds.foregroundFractionMin,
    ),
    minimumCheck(
      'frame.foregroundWidthSpan',
      summary.foregroundWidthSpan,
      thresholds.foregroundWidthSpanMin,
    ),
    minimumCheck(
      'frame.foregroundHeightSpan',
      summary.foregroundHeightSpan,
      thresholds.foregroundHeightSpanMin,
    ),
    minimumCheck(
      'frame.luminanceP99P01',
      summary.luminanceP99P01,
      thresholds.luminanceP99P01Min,
    ),
    minimumCheck(
      'frame.quantizedRgbBins',
      summary.quantizedRgbBins,
      thresholds.quantizedRgbBinsMin,
    ),
  ];
}

export function assertPlan018FrameHealthy(
  summary,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  const failed = buildPlan018FrameHealthChecks(summary, thresholds)
    .filter((check) => !check.passed);
  if (failed.length !== 0) {
    throw new Error(
      `Plan 018 frame health failed: ${failed.map((check) => check.name).join(', ')}`,
    );
  }
}

export function summarizePlan018FrameDelta(
  first,
  second,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  if (
    first.width !== second.width ||
    first.height !== second.height ||
    first.data?.length !== first.width * first.height * 4 ||
    second.data?.length !== second.width * second.height * 4 ||
    first.backgroundSrgbHex !== second.backgroundSrgbHex
  ) {
    throw new Error('Plan 018 pass-delta images do not share one full-frame contract');
  }
  const background = parseSrgbHex(first.backgroundSrgbHex ?? '#121118');
  let absolute = 0;
  let samples = 0;
  for (let offset = 0; offset < first.data.length; offset += 4) {
    if (
      !isForeground(first.data, offset, background, thresholds) &&
      !isForeground(second.data, offset, background, thresholds)
    ) {
      continue;
    }
    for (let channel = 0; channel < 3; channel += 1) {
      absolute += Math.abs(
        first.data[offset + channel] - second.data[offset + channel],
      ) / 255;
      samples += 1;
    }
  }
  return {
    foregroundUnionRgbSamples: samples,
    meanAbsoluteSrgb: samples === 0 ? 0 : absolute / samples,
  };
}

export function buildPlan018PassDeltaChecks(
  triplet,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  const comparisons = {
    directOnlyVsIblOnly: summarizePlan018FrameDelta(
      triplet.directOnly,
      triplet.iblOnly,
      thresholds,
    ),
    combinedVsDirectOnly: summarizePlan018FrameDelta(
      triplet.combined,
      triplet.directOnly,
      thresholds,
    ),
    combinedVsIblOnly: summarizePlan018FrameDelta(
      triplet.combined,
      triplet.iblOnly,
      thresholds,
    ),
  };
  return Object.entries(comparisons).map(([name, summary]) => ({
    ...minimumCheck(
      `passDelta.${name}`,
      summary.meanAbsoluteSrgb,
      thresholds.intraRendererMeanAbsoluteSrgbDeltaMin,
    ),
    foregroundUnionRgbSamples: summary.foregroundUnionRgbSamples,
  }));
}

export function assertPlan018PassTripletHealthy(
  triplet,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  const failed = buildPlan018PassDeltaChecks(triplet, thresholds)
    .filter((check) => !check.passed);
  if (failed.length !== 0) {
    throw new Error(
      `Plan 018 pass delta failed: ${failed.map((check) => check.name).join(', ')}`,
    );
  }
}

export function buildPlan018DescriptivePair(
  pair,
  thresholds = PLAN018_ANALYSIS_THRESHOLDS,
) {
  const signedDelta = (field) => pair.flutterIos[field] - pair.threejs[field];
  return {
    structuralChecks: {
      threejs: buildPlan018FrameHealthChecks(pair.threejs, thresholds),
      flutterIos: buildPlan018FrameHealthChecks(pair.flutterIos, thresholds),
    },
    descriptive: {
      foregroundFractionSignedDelta: signedDelta('foregroundFraction'),
      meanSrgbLuminanceSignedDelta: signedDelta('meanSrgbLuminance'),
      p50SrgbLuminanceSignedDelta: signedDelta('p50SrgbLuminance'),
      p95SrgbLuminanceSignedDelta: signedDelta('p95SrgbLuminance'),
      p99SrgbLuminanceSignedDelta: signedDelta('p99SrgbLuminance'),
      luminanceP99P01SignedDelta: signedDelta('luminanceP99P01'),
      quantizedRgbBinsSignedDifference: signedDelta('quantizedRgbBins'),
    },
    comparisonBoundary:
      'descriptive direction/conformance only; no cross-renderer pixel threshold',
  };
}

export function validatePlan018CaptureInventory(expected, actual) {
  if (
    expected.length !== 27 ||
    actual.length !== 27 ||
    new Set(actual.map((record) => record.fileName)).size !== 27 ||
    JSON.stringify(actual) !== JSON.stringify(expected)
  ) {
    throw new Error('Plan 018 evidence must retain the exact ordered 27-capture inventory');
  }
}

export function validatePlan018AnalysisIdentity(expected, actual) {
  for (const label of ['state', 'camera', 'pass']) {
    const field = `${label}Sha256`;
    if (
      !isSha256(expected[field]) ||
      !isSha256(actual[field]) ||
      actual[field] !== expected[field]
    ) {
      throw new Error(`Plan 018 ${label} identity drifted`);
    }
  }
  if (
    Object.values(expected.sourceSha256 ?? {}).some((hash) => !isSha256(hash)) ||
    Object.values(actual.sourceSha256 ?? {}).some((hash) => !isSha256(hash)) ||
    JSON.stringify(actual.sourceSha256) !== JSON.stringify(expected.sourceSha256)
  ) {
    throw new Error('Plan 018 source identity drifted');
  }
}

export function validatePlan018ToyCarRoleEvidence(evidence) {
  const expectedRoles = [
    ['clearcoat', 0, ['KHR_materials_clearcoat']],
    ['sheen', 1, ['KHR_materials_sheen']],
    [
      'transmissionVolume',
      2,
      ['KHR_materials_transmission', 'KHR_materials_volume'],
    ],
  ];
  for (const source of ['authored', 'installed']) {
    const roles = evidence[source] ?? [];
    const valid =
      roles.length === expectedRoles.length &&
      expectedRoles.every(([roleName, materialIndex, allowedExtensions]) => {
        const role = roles.find((candidate) => candidate.role === roleName);
        const extensions = role?.extensions ?? [];
        const requiredExtension = allowedExtensions[0];
        return (
          role?.materialIndex === materialIndex &&
          extensions.includes(requiredExtension) &&
          extensions.every((extension) => allowedExtensions.includes(extension)) &&
          new Set(extensions).size === extensions.length &&
          role.featureActive === true &&
          Array.isArray(role.partAddresses) &&
          role.partAddresses.length > 0 &&
          role.partAddresses.every((address) =>
            typeof address === 'string' && address !== '',
          )
        );
      });
    if (!valid) {
      throw new Error(
        `Plan 018 ToyCar ${source} evidence must retain the exact generic extension roles`,
      );
    }
  }
  const installedAddresses = evidence.installed.flatMap(
    (role) => role.partAddresses,
  );
  if (new Set(installedAddresses).size !== installedAddresses.length) {
    throw new Error(
      'Plan 018 ToyCar installed generic roles must use distinct PartAddresses',
    );
  }
}

function captureRecord(modelId, view, pass) {
  return {
    modelId,
    view,
    pass,
    fileName: `${modelId}_${view}_${pass}.png`,
  };
}

function isSha256(value) {
  return /^[a-f0-9]{64}$/.test(value ?? '');
}

function parseSrgbHex(value) {
  if (!/^#[a-f0-9]{6}$/i.test(value)) {
    throw new Error('Plan 018 background must be a six-digit sRGB hex value');
  }
  return [1, 3, 5].map((offset) => Number.parseInt(value.slice(offset, offset + 2), 16));
}

function isForeground(data, offset, background, thresholds) {
  for (let channel = 0; channel < 3; channel += 1) {
    if (
      Math.abs(data[offset + channel] - background[channel]) / 255 >=
      thresholds.backgroundMaxChannelDeltaMin
    ) {
      return true;
    }
  }
  return false;
}

function srgbLuminance(rgb) {
  return (
    rgb[0] / 255 * 0.2126 +
    rgb[1] / 255 * 0.7152 +
    rgb[2] / 255 * 0.0722
  );
}

function percentile(sorted, fraction) {
  if (sorted.length === 0) return 0;
  return sorted[Math.floor((sorted.length - 1) * fraction)];
}

function minimumCheck(name, actual, minimum) {
  return {
    name,
    actual,
    expected: `>= ${minimum}`,
    passed: actual >= minimum,
  };
}
