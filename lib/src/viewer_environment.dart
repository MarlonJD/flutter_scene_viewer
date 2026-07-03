import 'dart:typed_data';

/// Encoded high-dynamic-range environment file format.
enum ViewerEnvironmentFileFormat {
  /// Infer the decoder from the source name when possible.
  auto,

  /// Radiance RGBE `.hdr`.
  hdr,

  /// OpenEXR `.exr`.
  exr,
}

/// Explicit Poly Haven HDRI resolution.
enum ViewerPolyHavenResolution {
  oneK('1k'),
  twoK('2k'),
  fourK('4k'),
  eightK('8k'),
  sixteenK('16k');

  const ViewerPolyHavenResolution(this.apiValue);

  final String apiValue;
}

/// Explicit Poly Haven HDRI file type.
enum ViewerPolyHavenFileType {
  hdr('hdr'),
  exr('exr');

  const ViewerPolyHavenFileType(this.apiValue);

  final String apiValue;
}

/// Viewer-controlled image-based lighting and optional skybox background.
sealed class ViewerEnvironment {
  const ViewerEnvironment({
    required this.intensity,
    required this.rotationRadians,
    required this.showSkybox,
    required this.skyboxBlur,
  });

  const factory ViewerEnvironment.studio({
    double intensity,
    double rotationRadians,
    bool showSkybox,
    double skyboxBlur,
  }) = ViewerStudioEnvironment;

  const factory ViewerEnvironment.empty({
    bool showSkybox,
  }) = ViewerEmptyEnvironment;

  const factory ViewerEnvironment.asset(
    String radianceImageAsset, {
    double intensity,
    double rotationRadians,
    bool showSkybox,
    double skyboxBlur,
  }) = ViewerAssetEnvironment;

  const factory ViewerEnvironment.rawAsset(
    String assetPath, {
    ViewerEnvironmentFileFormat format,
    double intensity,
    double rotationRadians,
    bool showSkybox,
    double skyboxBlur,
  }) = ViewerRawAssetEnvironment;

  const factory ViewerEnvironment.rawBytes(
    Uint8List bytes, {
    String? debugName,
    ViewerEnvironmentFileFormat format,
    double intensity,
    double rotationRadians,
    bool showSkybox,
    double skyboxBlur,
  }) = ViewerRawBytesEnvironment;

  const factory ViewerEnvironment.polyHaven({
    required String assetId,
    required ViewerPolyHavenResolution resolution,
    required String userAgent,
    ViewerPolyHavenFileType fileType,
    double intensity,
    double rotationRadians,
    bool showSkybox,
    double skyboxBlur,
  }) = ViewerPolyHavenEnvironment;

  final double intensity;
  final double rotationRadians;
  final bool showSkybox;
  final double skyboxBlur;

  Object? get _variantValue => null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ViewerEnvironment &&
            runtimeType == other.runtimeType &&
            intensity == other.intensity &&
            rotationRadians == other.rotationRadians &&
            showSkybox == other.showSkybox &&
            skyboxBlur == other.skyboxBlur &&
            _variantValue == other._variantValue;
  }

  @override
  int get hashCode => Object.hash(
        runtimeType,
        intensity,
        rotationRadians,
        showSkybox,
        skyboxBlur,
        _variantValue,
      );
}

/// Built-in neutral studio environment.
final class ViewerStudioEnvironment extends ViewerEnvironment {
  const ViewerStudioEnvironment({
    super.intensity = 1.0,
    super.rotationRadians = 0.0,
    super.showSkybox = false,
    super.skyboxBlur = 0.0,
  });
}

/// Empty environment for no image-based lighting.
final class ViewerEmptyEnvironment extends ViewerEnvironment {
  const ViewerEmptyEnvironment({
    super.showSkybox = false,
  }) : super(
          intensity: 0.0,
          rotationRadians: 0.0,
          skyboxBlur: 0.0,
        );
}

/// Asset-backed equirectangular radiance environment.
final class ViewerAssetEnvironment extends ViewerEnvironment {
  const ViewerAssetEnvironment(
    this.radianceImageAsset, {
    super.intensity = 1.0,
    super.rotationRadians = 0.0,
    super.showSkybox = false,
    super.skyboxBlur = 0.0,
  });

  final String radianceImageAsset;

  @override
  Object? get _variantValue => radianceImageAsset;
}

/// Asset-backed encoded HDR environment.
final class ViewerRawAssetEnvironment extends ViewerEnvironment {
  const ViewerRawAssetEnvironment(
    this.assetPath, {
    this.format = ViewerEnvironmentFileFormat.auto,
    super.intensity = 1.0,
    super.rotationRadians = 0.0,
    super.showSkybox = false,
    super.skyboxBlur = 0.0,
  });

  final String assetPath;
  final ViewerEnvironmentFileFormat format;

  @override
  Object? get _variantValue => (assetPath, format);
}

/// Byte-backed encoded HDR environment.
final class ViewerRawBytesEnvironment extends ViewerEnvironment {
  const ViewerRawBytesEnvironment(
    this.bytes, {
    this.debugName,
    this.format = ViewerEnvironmentFileFormat.auto,
    super.intensity = 1.0,
    super.rotationRadians = 0.0,
    super.showSkybox = false,
    super.skyboxBlur = 0.0,
  });

  final Uint8List bytes;
  final String? debugName;
  final ViewerEnvironmentFileFormat format;

  @override
  Object? get _variantValue => (bytes, debugName, format);
}

/// Explicit opt-in Poly Haven HDRI environment.
final class ViewerPolyHavenEnvironment extends ViewerEnvironment {
  const ViewerPolyHavenEnvironment({
    required this.assetId,
    required this.resolution,
    required this.userAgent,
    this.fileType = ViewerPolyHavenFileType.hdr,
    super.intensity = 1.0,
    super.rotationRadians = 0.0,
    super.showSkybox = false,
    super.skyboxBlur = 0.0,
  });

  final String assetId;
  final ViewerPolyHavenResolution resolution;
  final ViewerPolyHavenFileType fileType;
  final String userAgent;

  @override
  Object? get _variantValue => (assetId, resolution, fileType, userAgent);
}
