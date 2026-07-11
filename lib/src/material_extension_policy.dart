import 'package:flutter/foundation.dart';

/// How the viewer handles material extension fields that need custom backend
/// support beyond the standard flutter_scene PBR path.
enum ViewerMaterialExtensionMode {
  diagnosticsOnly,
  experimentalFlutterSceneShaders,
  productionFlutterSceneShaders,
}

/// Backend class that supplies material extension fields.
enum MaterialExtensionBackendKind {
  none,
  packageLocalCandidate,
  flutterSceneCustomShader,
  rendererNative,
}

/// glTF material extension feature selected for capability queries.
enum MaterialExtensionFeature {
  transmission,
  ior,
  volume,
  clearcoat,
  specular,
}

/// Release maturity of one material extension feature on one target.
enum MaterialExtensionMaturity {
  diagnosticOnly,
  candidateOnly,
  releasePending,
  productionReady,
}

/// Explicit runtime target for material extension capability evidence.
enum MaterialExtensionTarget {
  iosSimulator,
  iosPhysical,
  android,
  web,
}

/// Whether one material extension feature was exercised on one target.
enum MaterialExtensionEvidenceStatus {
  notRun,
  verifiedLocally,
}

/// Per-target maturity and evidence for one material extension feature.
@immutable
final class MaterialExtensionFeatureSupport {
  factory MaterialExtensionFeatureSupport({
    required bool available,
    Map<MaterialExtensionTarget, MaterialExtensionMaturity> maturityByTarget =
        const <MaterialExtensionTarget, MaterialExtensionMaturity>{},
    Map<MaterialExtensionTarget, MaterialExtensionEvidenceStatus> evidenceByTarget =
        const <MaterialExtensionTarget, MaterialExtensionEvidenceStatus>{},
  }) {
    return MaterialExtensionFeatureSupport._(
      available: available,
      maturityByTarget:
          Map<MaterialExtensionTarget, MaterialExtensionMaturity>.unmodifiable(
              maturityByTarget),
      evidenceByTarget: Map<MaterialExtensionTarget,
          MaterialExtensionEvidenceStatus>.unmodifiable(evidenceByTarget),
    );
  }

  const MaterialExtensionFeatureSupport._({
    required this.available,
    required this.maturityByTarget,
    required this.evidenceByTarget,
  });

  static const unsupported = MaterialExtensionFeatureSupport._(
    available: false,
    maturityByTarget: <MaterialExtensionTarget, MaterialExtensionMaturity>{},
    evidenceByTarget: <MaterialExtensionTarget,
        MaterialExtensionEvidenceStatus>{},
  );

  final bool available;
  final Map<MaterialExtensionTarget, MaterialExtensionMaturity>
      maturityByTarget;
  final Map<MaterialExtensionTarget, MaterialExtensionEvidenceStatus>
      evidenceByTarget;

  MaterialExtensionMaturity maturityFor(MaterialExtensionTarget target) =>
      maturityByTarget[target] ?? MaterialExtensionMaturity.diagnosticOnly;

  MaterialExtensionEvidenceStatus evidenceFor(
    MaterialExtensionTarget target,
  ) =>
      evidenceByTarget[target] ?? MaterialExtensionEvidenceStatus.notRun;

  bool productionReadyFor(MaterialExtensionTarget target) =>
      available &&
      maturityFor(target) == MaterialExtensionMaturity.productionReady &&
      evidenceFor(target) == MaterialExtensionEvidenceStatus.verifiedLocally;

  @override
  bool operator ==(Object other) {
    return other is MaterialExtensionFeatureSupport &&
        other.available == available &&
        mapEquals(other.maturityByTarget, maturityByTarget) &&
        mapEquals(other.evidenceByTarget, evidenceByTarget);
  }

  @override
  int get hashCode => Object.hash(
        available,
        _mapHash(maturityByTarget),
        _mapHash(evidenceByTarget),
      );
}

/// Backend feature support available to material validation and application.
@immutable
final class MaterialExtensionSupport {
  factory MaterialExtensionSupport({
    required MaterialExtensionBackendKind backendKind,
    Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport> features =
        const <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{},
    Set<MaterialExtensionTarget> claimedReleaseTargets =
        const <MaterialExtensionTarget>{},
  }) {
    if (claimedReleaseTargets.isNotEmpty &&
        !_isActualReleaseBackendKind(backendKind)) {
      throw ArgumentError.value(
        claimedReleaseTargets,
        'claimedReleaseTargets',
        '$backendKind cannot claim release targets.',
      );
    }
    return MaterialExtensionSupport._(
      backendKind: backendKind,
      features: Map<MaterialExtensionFeature,
          MaterialExtensionFeatureSupport>.unmodifiable(features),
      claimedReleaseTargets:
          Set<MaterialExtensionTarget>.unmodifiable(claimedReleaseTargets),
    );
  }

  const MaterialExtensionSupport._({
    required this.backendKind,
    required this.features,
    required this.claimedReleaseTargets,
  });

  static const unsupported = MaterialExtensionSupport._(
    backendKind: MaterialExtensionBackendKind.none,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{},
    claimedReleaseTargets: <MaterialExtensionTarget>{},
  );

  final MaterialExtensionBackendKind backendKind;
  final Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport> features;
  final Set<MaterialExtensionTarget> claimedReleaseTargets;

  MaterialExtensionFeatureSupport supportFor(
    MaterialExtensionFeature feature,
  ) =>
      features[feature] ?? MaterialExtensionFeatureSupport.unsupported;

  bool get transmission =>
      supportFor(MaterialExtensionFeature.transmission).available;
  bool get ior => supportFor(MaterialExtensionFeature.ior).available;
  bool get volume => supportFor(MaterialExtensionFeature.volume).available;
  bool get clearcoat =>
      supportFor(MaterialExtensionFeature.clearcoat).available;
  bool get specular => supportFor(MaterialExtensionFeature.specular).available;

  bool productionReadyFor(
    MaterialExtensionFeature feature,
    MaterialExtensionTarget target,
  ) =>
      supportFor(feature).productionReadyFor(target);

  bool get productionReady =>
      _isActualReleaseBackendKind(backendKind) &&
      claimedReleaseTargets.isNotEmpty &&
      MaterialExtensionFeature.values.every(
        (feature) => claimedReleaseTargets.every(
          (target) => productionReadyFor(feature, target),
        ),
      );

  @override
  bool operator ==(Object other) {
    return other is MaterialExtensionSupport &&
        other.backendKind == backendKind &&
        mapEquals(other.features, features) &&
        setEquals(other.claimedReleaseTargets, claimedReleaseTargets);
  }

  @override
  int get hashCode => Object.hash(
        backendKind,
        _mapHash(features),
        Object.hashAllUnordered(claimedReleaseTargets),
      );
}

/// Public policy for opt-in material extension backends.
@immutable
final class ViewerMaterialExtensionPolicy {
  const ViewerMaterialExtensionPolicy.diagnosticsOnly()
      : mode = ViewerMaterialExtensionMode.diagnosticsOnly,
        enableTransmission = false,
        enableClearcoat = false;

  const ViewerMaterialExtensionPolicy.experimentalShaders({
    this.enableTransmission = true,
    this.enableClearcoat = false,
  }) : mode = ViewerMaterialExtensionMode.experimentalFlutterSceneShaders;

  const ViewerMaterialExtensionPolicy.productionShaders({
    this.enableTransmission = true,
    this.enableClearcoat = true,
  }) : mode = ViewerMaterialExtensionMode.productionFlutterSceneShaders;

  final ViewerMaterialExtensionMode mode;
  final bool enableTransmission;
  final bool enableClearcoat;

  MaterialExtensionSupport get support {
    return switch (mode) {
      ViewerMaterialExtensionMode.diagnosticsOnly =>
        MaterialExtensionSupport.unsupported,
      ViewerMaterialExtensionMode.experimentalFlutterSceneShaders =>
        MaterialExtensionSupport(
          backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
          features: _candidateFeatures(
            enableTransmission: enableTransmission,
            enableClearcoat: enableClearcoat,
          ),
        ),
      ViewerMaterialExtensionMode.productionFlutterSceneShaders =>
        MaterialExtensionSupport(
          backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
          features: _candidateFeatures(
            enableTransmission: enableTransmission,
            enableClearcoat: enableClearcoat,
          ),
        ),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ViewerMaterialExtensionPolicy &&
        other.mode == mode &&
        other.enableTransmission == enableTransmission &&
        other.enableClearcoat == enableClearcoat;
  }

  @override
  int get hashCode => Object.hash(mode, enableTransmission, enableClearcoat);
}

Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport>
    _candidateFeatures({
  required bool enableTransmission,
  required bool enableClearcoat,
}) {
  final transmissionSupport = _candidateFeatureSupport(enableTransmission);
  return <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
    MaterialExtensionFeature.transmission: transmissionSupport,
    MaterialExtensionFeature.ior: transmissionSupport,
    MaterialExtensionFeature.volume: transmissionSupport,
    MaterialExtensionFeature.clearcoat:
        _candidateFeatureSupport(enableClearcoat),
  };
}

MaterialExtensionFeatureSupport _candidateFeatureSupport(bool available) {
  if (!available) {
    return MaterialExtensionFeatureSupport.unsupported;
  }
  return MaterialExtensionFeatureSupport(
    available: true,
    maturityByTarget: <MaterialExtensionTarget, MaterialExtensionMaturity>{
      for (final target in MaterialExtensionTarget.values)
        target: MaterialExtensionMaturity.candidateOnly,
    },
  );
}

int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered(
      map.entries.map((entry) => Object.hash(entry.key, entry.value)),
    );

bool _isActualReleaseBackendKind(MaterialExtensionBackendKind backendKind) =>
    backendKind == MaterialExtensionBackendKind.flutterSceneCustomShader ||
    backendKind == MaterialExtensionBackendKind.rendererNative;
