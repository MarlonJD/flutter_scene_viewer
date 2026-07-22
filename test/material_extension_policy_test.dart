import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics-only policy exposes unsupported material extensions', () {
    const policy = ViewerMaterialExtensionPolicy.diagnosticsOnly();

    expect(policy.mode, ViewerMaterialExtensionMode.diagnosticsOnly);
    expect(policy.enableTransmission, isFalse);
    expect(policy.enableClearcoat, isFalse);
    expect(policy.support, MaterialExtensionSupport.unsupported);
  });

  test('experimental shader policy exposes transmission support by default',
      () {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders();

    expect(policy.mode,
        ViewerMaterialExtensionMode.experimentalFlutterSceneShaders);
    expect(policy.enableTransmission, isTrue);
    expect(policy.enableClearcoat, isFalse);
    expect(policy.support.transmission, isTrue);
    expect(policy.support.ior, isTrue);
    expect(policy.support.volume, isTrue);
    expect(policy.support.clearcoat, isFalse);
    expect(policy.support.specular, isFalse);
  });

  test('experimental shader policy exposes clearcoat only when enabled', () {
    const policy = ViewerMaterialExtensionPolicy.experimentalShaders(
      enableClearcoat: true,
    );

    expect(policy.enableClearcoat, isTrue);
    expect(policy.support.clearcoat, isTrue);
  });

  test(
      'package-local shader policy is candidate-only without target release evidence',
      () {
    final support =
        const ViewerMaterialExtensionPolicy.productionShaders().support;

    expect(
      support.backendKind,
      MaterialExtensionBackendKind.flutterSceneCustomShader,
    );
    expect(
      support
          .supportFor(MaterialExtensionFeature.clearcoat)
          .maturityFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionMaturity.candidateOnly,
    );
    expect(
      support
          .supportFor(MaterialExtensionFeature.clearcoat)
          .evidenceFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionEvidenceStatus.notRun,
    );
    expect(support.productionReady, isFalse);
  });

  test('candidate maturity can coexist with verified local target evidence',
      () {
    final feature = MaterialExtensionFeatureSupport(
      available: true,
      maturityByTarget: const <MaterialExtensionTarget,
          MaterialExtensionMaturity>{
        MaterialExtensionTarget.iosSimulator:
            MaterialExtensionMaturity.candidateOnly,
      },
      evidenceByTarget: const <MaterialExtensionTarget,
          MaterialExtensionEvidenceStatus>{
        MaterialExtensionTarget.iosSimulator:
            MaterialExtensionEvidenceStatus.verifiedLocally,
      },
    );

    expect(
      feature.maturityFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionMaturity.candidateOnly,
    );
    expect(
      feature.evidenceFor(MaterialExtensionTarget.iosSimulator),
      MaterialExtensionEvidenceStatus.verifiedLocally,
    );
    expect(
      feature.productionReadyFor(MaterialExtensionTarget.iosSimulator),
      isFalse,
    );
  });

  test('candidate shader backend cannot report production ready', () {
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
      features: _availableFeatures(MaterialExtensionFeature.values),
    );

    expect(support.productionReady, isFalse);
    expect(
      support.backendKind,
      MaterialExtensionBackendKind.packageLocalCandidate,
    );
  });

  test('non-release backends reject claimed release targets', () {
    for (final backendKind in <MaterialExtensionBackendKind>[
      MaterialExtensionBackendKind.none,
      MaterialExtensionBackendKind.packageLocalCandidate,
    ]) {
      expect(
        () => _productionReadySupport(backendKind: backendKind),
        throwsArgumentError,
        reason: backendKind.name,
      );
    }
  });

  test('renderer native backend can report production ready', () {
    final support = _productionReadySupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
    );

    expect(support.productionReady, isTrue);
  });

  test('flutter_scene custom shader backend can report production ready', () {
    final support = _productionReadySupport(
      backendKind: MaterialExtensionBackendKind.flutterSceneCustomShader,
    );

    expect(support.productionReady, isTrue);
  });

  test('material extension support equality includes backend kind', () {
    expect(
      MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        features: _availableFeatures(MaterialExtensionFeature.values),
      ),
      isNot(
        MaterialExtensionSupport(
          backendKind: MaterialExtensionBackendKind.rendererNative,
          features: _availableFeatures(
            MaterialExtensionFeature.values.where(
                (feature) => feature != MaterialExtensionFeature.specular),
          ),
        ),
      ),
    );
  });

  test('material extension support equality includes target evidence', () {
    MaterialExtensionSupport supportWithEvidence(
      MaterialExtensionEvidenceStatus evidence,
    ) {
      return MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.rendererNative,
        features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
          MaterialExtensionFeature.clearcoat: MaterialExtensionFeatureSupport(
            available: true,
            maturityByTarget: const <MaterialExtensionTarget,
                MaterialExtensionMaturity>{
              MaterialExtensionTarget.iosPhysical:
                  MaterialExtensionMaturity.releasePending,
            },
            evidenceByTarget: <MaterialExtensionTarget,
                MaterialExtensionEvidenceStatus>{
              MaterialExtensionTarget.iosPhysical: evidence,
            },
          ),
        },
      );
    }

    expect(
      supportWithEvidence(MaterialExtensionEvidenceStatus.notRun),
      isNot(
        supportWithEvidence(
          MaterialExtensionEvidenceStatus.verifiedLocally,
        ),
      ),
    );
  });

  test('MaterialPatch validation accepts supported transmission intent', () {
    const patch = MaterialPatch(
      transmission: 1.0,
      ior: 1.45,
      thickness: 0.02,
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Glass'], primitiveIndex: 0),
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        features: _availableFeatures(<MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
        ]),
      ),
    );

    expect(diagnostics, isEmpty);
  });

  test('MaterialPatch validation keeps unsupported clearcoat diagnostic', () {
    const patch = MaterialPatch(clearcoat: 1.0);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        features: _availableFeatures(<MaterialExtensionFeature>[
          MaterialExtensionFeature.transmission,
          MaterialExtensionFeature.ior,
          MaterialExtensionFeature.volume,
        ]),
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.code,
        ViewerDiagnosticCode.unsupportedMaterialFeature);
    expect(diagnostics.single.details['extensions'],
        contains('KHR_materials_clearcoat'));
  });

  test('MaterialPatch validation accepts supported clearcoat intent', () {
    const patch = MaterialPatch(clearcoat: 1.0, clearcoatRoughness: 0.12);

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Paint'], primitiveIndex: 0),
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        features: _availableFeatures(
          const <MaterialExtensionFeature>[
            MaterialExtensionFeature.clearcoat,
          ],
        ),
      ),
    );

    expect(diagnostics, isEmpty);
  });

  test('MaterialPatch validation rejects malformed clearcoat atomically', () {
    final support = MaterialExtensionSupport(
      backendKind: MaterialExtensionBackendKind.rendererNative,
      features: _availableFeatures(
        const <MaterialExtensionFeature>[
          MaterialExtensionFeature.clearcoat,
        ],
      ),
    );
    final address = PartAddress(
      nodePath: const <String>['Root', 'Paint'],
      primitiveIndex: 0,
    );

    for (final patch in <MaterialPatch>[
      const MaterialPatch(clearcoat: -0.01),
      const MaterialPatch(clearcoat: 1.01),
      const MaterialPatch(clearcoatRoughness: double.nan),
      const MaterialPatch(clearcoatNormalScale: double.infinity),
    ]) {
      final diagnostics = patch.validate(address, support: support);
      expect(diagnostics, hasLength(1), reason: patch.toJson().toString());
      expect(
        diagnostics.single.code,
        ViewerDiagnosticCode.invalidMaterialOverride,
      );
    }
  });

  test('MaterialPatch validation accepts supported specular intent', () {
    const patch = MaterialPatch(
      specular: 0.4,
      specularColorFactor: <double>[0.7, 0.8, 0.9],
    );

    final diagnostics = patch.validate(
      PartAddress(nodePath: <String>['Root', 'Fabric'], primitiveIndex: 0),
      support: MaterialExtensionSupport(
        backendKind: MaterialExtensionBackendKind.packageLocalCandidate,
        features: _availableFeatures(
          const <MaterialExtensionFeature>[
            MaterialExtensionFeature.specular,
          ],
        ),
      ),
    );

    expect(diagnostics, isEmpty);
  });

  test('pinned policies keep specular unavailable with separate status axes',
      () {
    for (final policy in <ViewerMaterialExtensionPolicy>[
      const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
      const ViewerMaterialExtensionPolicy.experimentalShaders(),
      const ViewerMaterialExtensionPolicy.productionShaders(),
    ]) {
      final support = policy.support;
      final specular = support.supportFor(MaterialExtensionFeature.specular);

      expect(specular.available, isFalse, reason: policy.mode.name);
      for (final target in MaterialExtensionTarget.values) {
        expect(
          specular.maturityFor(target),
          MaterialExtensionMaturity.diagnosticOnly,
          reason: '${policy.mode.name}/${target.name}',
        );
        expect(
          specular.evidenceFor(target),
          MaterialExtensionEvidenceStatus.notRun,
          reason: '${policy.mode.name}/${target.name}',
        );
      }
    }
  });

  test('all default policies keep sheen diagnostic-only and not run', () {
    for (final policy in <ViewerMaterialExtensionPolicy>[
      const ViewerMaterialExtensionPolicy.diagnosticsOnly(),
      const ViewerMaterialExtensionPolicy.experimentalShaders(),
      const ViewerMaterialExtensionPolicy.productionShaders(),
    ]) {
      final support = policy.support.supportFor(MaterialExtensionFeature.sheen);

      expect(support.available, isFalse, reason: policy.mode.name);
      for (final target in MaterialExtensionTarget.values) {
        expect(
          support.maturityFor(target),
          MaterialExtensionMaturity.diagnosticOnly,
        );
        expect(
          support.evidenceFor(target),
          MaterialExtensionEvidenceStatus.notRun,
        );
      }
    }
  });

  test('sheen candidate is explicit opt-in and remains candidate-only', () {
    const experimental = ViewerMaterialExtensionPolicy.experimentalShaders(
      enableSheen: true,
    );
    const production = ViewerMaterialExtensionPolicy.productionShaders(
      enableSheen: true,
    );

    for (final policy in <ViewerMaterialExtensionPolicy>[
      experimental,
      production,
    ]) {
      expect(policy.enableSheen, isTrue);
      final support = policy.support.supportFor(MaterialExtensionFeature.sheen);
      expect(support.available, isTrue);
      for (final target in MaterialExtensionTarget.values) {
        expect(
          support.maturityFor(target),
          MaterialExtensionMaturity.candidateOnly,
          reason: '${policy.mode.name}/${target.name}',
        );
        expect(
          support.evidenceFor(target),
          MaterialExtensionEvidenceStatus.notRun,
          reason: '${policy.mode.name}/${target.name}',
        );
      }
    }

    expect(
      const ViewerMaterialExtensionPolicy.diagnosticsOnly().support.sheen,
      isFalse,
    );
    expect(experimental,
        isNot(const ViewerMaterialExtensionPolicy.experimentalShaders()));
    expect(
        experimental.hashCode,
        isNot(const ViewerMaterialExtensionPolicy.experimentalShaders()
            .hashCode));
  });
}

Map<MaterialExtensionFeature, MaterialExtensionFeatureSupport>
    _availableFeatures(Iterable<MaterialExtensionFeature> features) {
  return <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
    for (final feature in features)
      feature: MaterialExtensionFeatureSupport(available: true),
  };
}

MaterialExtensionSupport _productionReadySupport({
  required MaterialExtensionBackendKind backendKind,
}) {
  const target = MaterialExtensionTarget.iosPhysical;
  return MaterialExtensionSupport(
    backendKind: backendKind,
    features: <MaterialExtensionFeature, MaterialExtensionFeatureSupport>{
      for (final feature in MaterialExtensionFeature.values)
        feature: MaterialExtensionFeatureSupport(
          available: true,
          maturityByTarget: const <MaterialExtensionTarget,
              MaterialExtensionMaturity>{
            target: MaterialExtensionMaturity.productionReady,
          },
          evidenceByTarget: const <MaterialExtensionTarget,
              MaterialExtensionEvidenceStatus>{
            target: MaterialExtensionEvidenceStatus.verifiedLocally,
          },
        ),
    },
    claimedReleaseTargets: const <MaterialExtensionTarget>{target},
  );
}
