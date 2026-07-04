import 'dart:convert';
import 'dart:io';

final class MaterialExtensionAcceptanceMetrics {
  const MaterialExtensionAcceptanceMetrics({
    required this.backendKind,
    required this.target,
    required this.glass,
    required this.clearcoat,
  });

  factory MaterialExtensionAcceptanceMetrics.fromJson(
    Map<String, Object?> json,
  ) {
    return MaterialExtensionAcceptanceMetrics(
      backendKind: _string(json, 'backendKind'),
      target: _string(json, 'target'),
      glass: GlassAcceptanceMetrics.fromJson(_map(json, 'glass')),
      clearcoat: ClearcoatAcceptanceMetrics.fromJson(
        _map(json, 'clearcoat'),
      ),
    );
  }

  final String backendKind;
  final String target;
  final GlassAcceptanceMetrics glass;
  final ClearcoatAcceptanceMetrics clearcoat;

  Map<String, Object?> toJson() => <String, Object?>{
        'backendKind': backendKind,
        'target': target,
        'glass': glass.toJson(),
        'clearcoat': clearcoat.toJson(),
      };
}

final class GlassAcceptanceMetrics {
  const GlassAcceptanceMetrics({
    required this.transmissionSpreadDelta,
    required this.iorDelta,
    required this.roughnessBlurDirection,
  });

  factory GlassAcceptanceMetrics.fromJson(Map<String, Object?> json) {
    return GlassAcceptanceMetrics(
      transmissionSpreadDelta: _number(json, 'transmissionSpreadDelta'),
      iorDelta: _number(json, 'iorDelta'),
      roughnessBlurDirection: _string(json, 'roughnessBlurDirection'),
    );
  }

  final double transmissionSpreadDelta;
  final double iorDelta;
  final String roughnessBlurDirection;

  Map<String, Object?> toJson() => <String, Object?>{
        'transmissionSpreadDelta': transmissionSpreadDelta,
        'iorDelta': iorDelta,
        'roughnessBlurDirection': roughnessBlurDirection,
      };
}

final class ClearcoatAcceptanceMetrics {
  const ClearcoatAcceptanceMetrics({
    required this.factorHighlightDelta,
    required this.roughPeakBelowSmoothPeak,
    required this.baseMaterialPreserved,
  });

  factory ClearcoatAcceptanceMetrics.fromJson(Map<String, Object?> json) {
    return ClearcoatAcceptanceMetrics(
      factorHighlightDelta: _number(json, 'factorHighlightDelta'),
      roughPeakBelowSmoothPeak: _bool(json, 'roughPeakBelowSmoothPeak'),
      baseMaterialPreserved: _bool(json, 'baseMaterialPreserved'),
    );
  }

  final double factorHighlightDelta;
  final bool roughPeakBelowSmoothPeak;
  final bool baseMaterialPreserved;

  Map<String, Object?> toJson() => <String, Object?>{
        'factorHighlightDelta': factorHighlightDelta,
        'roughPeakBelowSmoothPeak': roughPeakBelowSmoothPeak,
        'baseMaterialPreserved': baseMaterialPreserved,
      };
}

Future<void> main(List<String> arguments) async {
  final iosEvidencePath = arguments.isNotEmpty
      ? arguments[0]
      : 'tools/out/fsviewer_ios_simulator_material_extension_matrix.json';
  final referenceMetricsPath = arguments.length > 1
      ? arguments[1]
      : 'tools/out/material_extension_reference_metrics.json';
  final outputPath = arguments.length > 2
      ? arguments[2]
      : 'tools/out/material_extension_acceptance_metrics.json';

  try {
    final metrics = compareMaterialExtensionMetrics(
      iosEvidence: _readJsonFile(iosEvidencePath),
      referenceMetrics: _readJsonFile(referenceMetricsPath),
    );
    File(outputPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${jsonEncode(metrics.toJson())}\n');
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

MaterialExtensionAcceptanceMetrics compareMaterialExtensionMetrics({
  required Map<String, Object?> iosEvidence,
  required Map<String, Object?> referenceMetrics,
}) {
  final backendKind = _string(iosEvidence, 'backendKind');
  if (backendKind != 'rendererNative') {
    throw StateError(
      'Native acceptance metrics require rendererNative evidence; found '
      '$backendKind.',
    );
  }

  final glass = _map(iosEvidence, 'glass');
  final clearcoat = _map(iosEvidence, 'clearcoat');
  final referenceGlass = _optionalMap(referenceMetrics, 'glass');
  final referenceClearcoat = _optionalMap(referenceMetrics, 'clearcoat');

  final transmissionSpreadDelta = _number(glass, 'transmission1Spread') -
      _number(glass, 'transmission0Spread');
  final iorDelta = _number(glass, 'iorDelta');
  final factorHighlightDelta =
      _number(clearcoat, 'fullHighlight') - _number(clearcoat, 'zeroHighlight');
  final smoothPeak = _number(clearcoat, 'smoothPeak');
  final roughPeak = _number(clearcoat, 'roughPeak');

  _requireDirectionalReference(
    referenceGlass,
    referenceClearcoat,
    transmissionSpreadDelta: transmissionSpreadDelta,
    iorDelta: iorDelta,
    factorHighlightDelta: factorHighlightDelta,
    roughPeakBelowSmoothPeak: roughPeak <= smoothPeak,
  );

  return MaterialExtensionAcceptanceMetrics(
    backendKind: backendKind,
    target: _string(iosEvidence, 'target'),
    glass: GlassAcceptanceMetrics(
      transmissionSpreadDelta: transmissionSpreadDelta,
      iorDelta: iorDelta,
      roughnessBlurDirection: _string(
        glass,
        'roughnessBlurDirection',
        fallback: 'reduces_high_frequency_detail',
      ),
    ),
    clearcoat: ClearcoatAcceptanceMetrics(
      factorHighlightDelta: factorHighlightDelta,
      roughPeakBelowSmoothPeak: roughPeak <= smoothPeak,
      baseMaterialPreserved: _bool(
        clearcoat,
        'baseMaterialPreserved',
        fallback: false,
      ),
    ),
  );
}

void _requireDirectionalReference(
  Map<String, Object?>? referenceGlass,
  Map<String, Object?>? referenceClearcoat, {
  required double transmissionSpreadDelta,
  required double iorDelta,
  required double factorHighlightDelta,
  required bool roughPeakBelowSmoothPeak,
}) {
  if (referenceGlass == null || referenceClearcoat == null) {
    return;
  }
  if (transmissionSpreadDelta <= 0 || iorDelta <= 0) {
    throw StateError(
        'Native glass metrics do not move in reference direction.');
  }
  if (factorHighlightDelta <= 0 || !roughPeakBelowSmoothPeak) {
    throw StateError(
      'Native clearcoat metrics do not move in reference direction.',
    );
  }
}

Map<String, Object?> _readJsonFile(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  throw StateError('$path must contain a JSON object.');
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw StateError('$key must be a JSON object.');
}

Map<String, Object?>? _optionalMap(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map ? value.cast<String, Object?>() : null;
}

String _string(
  Map<String, Object?> json,
  String key, {
  String? fallback,
}) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  if (fallback != null) {
    return fallback;
  }
  throw StateError('$key must be a string.');
}

double _number(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    return value.toDouble();
  }
  throw StateError('$key must be a number.');
}

bool _bool(
  Map<String, Object?> json,
  String key, {
  bool? fallback,
}) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  if (fallback != null) {
    return fallback;
  }
  throw StateError('$key must be a boolean.');
}
