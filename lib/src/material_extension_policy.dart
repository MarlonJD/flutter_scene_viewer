import 'package:flutter/foundation.dart';

/// How the viewer handles material extension fields that need custom backend
/// support beyond the standard flutter_scene PBR path.
enum ViewerMaterialExtensionMode {
  diagnosticsOnly,
  experimentalFlutterSceneShaders,
  productionFlutterSceneShaders,
}

/// Backend feature support available to material validation.
@immutable
final class MaterialExtensionSupport {
  const MaterialExtensionSupport({
    this.transmission = false,
    this.ior = false,
    this.volume = false,
    this.clearcoat = false,
    this.productionReady = false,
  });

  static const unsupported = MaterialExtensionSupport();

  final bool transmission;
  final bool ior;
  final bool volume;
  final bool clearcoat;
  final bool productionReady;

  @override
  bool operator ==(Object other) {
    return other is MaterialExtensionSupport &&
        other.transmission == transmission &&
        other.ior == ior &&
        other.volume == volume &&
        other.clearcoat == clearcoat &&
        other.productionReady == productionReady;
  }

  @override
  int get hashCode =>
      Object.hash(transmission, ior, volume, clearcoat, productionReady);
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
          transmission: enableTransmission,
          ior: enableTransmission,
          volume: enableTransmission,
          clearcoat: enableClearcoat,
        ),
      ViewerMaterialExtensionMode.productionFlutterSceneShaders =>
        MaterialExtensionSupport(
          transmission: enableTransmission,
          ior: enableTransmission,
          volume: enableTransmission,
          clearcoat: enableClearcoat,
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
