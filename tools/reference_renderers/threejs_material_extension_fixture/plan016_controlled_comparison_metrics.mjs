export function buildPlan016ComparisonChecks(metrics, thresholds) {
  return [
    minimumCheck(
      'camera.silhouetteIou',
      metrics.camera.silhouetteIou,
      thresholds.cameraSilhouetteIouMin,
    ),
    maximumCheck(
      'camera.edgeCentroidDistanceLogical',
      metrics.camera.centroidDistanceLogical,
      thresholds.cameraEdgeCentroidMaxLogicalPixels,
    ),
    ...Object.entries(metrics.alignedRendererComparisons).flatMap(
      ([modelId, comparison]) => [
        maximumCheck(
          `aligned.${modelId}.meanAbsoluteRgb`,
          comparison.meanAbsoluteRgb,
          thresholds.alignedMeanAbsoluteRgbMax,
        ),
        maximumCheck(
          `aligned.${modelId}.p95AbsoluteRgb`,
          comparison.p95AbsoluteRgb,
          thresholds.alignedP95AbsoluteRgbMax,
        ),
      ],
    ),
    maximumCheck(
      'transmission.luminanceRelativeError',
      metrics.transmittedLuminance.relativeError,
      thresholds.transmittedLuminanceRelativeErrorMax,
    ),
    maximumCheck(
      'attenuation.chromaticityDistance',
      metrics.attenuation.chromaticityDistance,
      thresholds.attenuationChromaticityDistanceMax,
    ),
    maximumCheck(
      'ior.displacementRelativeError',
      metrics.ior.displacementRelativeError,
      thresholds.refractedDisplacementRelativeErrorMax,
    ),
    maximumCheck(
      'ior.displacementAbsoluteErrorLogical',
      metrics.ior.displacementAbsoluteErrorLogical,
      thresholds.refractedDisplacementAbsoluteLogicalPixelsMax,
    ),
    maximumCheck(
      'roughness.edgeEnergyRatioAbsoluteError',
      metrics.roughness.edgeEnergyRatioAbsoluteError,
      thresholds.blurRatioAbsoluteErrorMax,
    ),
    ...Object.entries(metrics.iosControlPairs).map(([trend, comparison]) =>
      minimumCheck(
        `iosControl.${trend}.meanAbsoluteRgbSignal`,
        comparison.meanAbsoluteRgb,
        thresholds.controlPairMeanAbsoluteRgbSignalMin,
      ),
    ),
    minimumCheck(
      'iosControl.ior.refractedDisplacementSignal',
      metrics.iosControlPairs.ior.edgeCentroidDistanceLogical,
      thresholds.controlRefractedDisplacementLogicalPixelsMin,
    ),
    minimumCheck(
      'iosControl.attenuation.chromaticitySignal',
      metrics.iosControlPairs.attenuation.chromaticityDistance,
      thresholds.controlAttenuationChromaticityShiftMin,
    ),
    maximumCheck(
      'iosControl.roughness.blurSignal',
      metrics.iosControlPairs.roughness.secondToFirstEdgeEnergyRatio,
      thresholds.controlRoughnessEdgeEnergyRatioMax,
    ),
  ];
}

export function relativeError(actual, reference) {
  return Math.abs(actual - reference) / Math.max(Math.abs(reference), 1e-9);
}

function minimumCheck(name, actual, minimum) {
  return {
    name,
    actual,
    expected: `>= ${minimum}`,
    passed: actual >= minimum,
  };
}

function maximumCheck(name, actual, maximum) {
  return {
    name,
    actual,
    expected: `<= ${maximum}`,
    passed: actual <= maximum,
  };
}
