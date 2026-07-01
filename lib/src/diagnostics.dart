/// Machine-readable viewer diagnostic codes.
enum ViewerDiagnosticCode {
  missingUvSet,
  ambiguousNodePath,
  primitiveNotFound,
  unsupportedMaterialFeature,
  modelTooLarge,
  textureTooLarge,
  networkFailure,
  adapterUnavailable,
}

/// Diagnostic emitted when the viewer cannot satisfy a requested operation.
final class ViewerDiagnostic {
  const ViewerDiagnostic({
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final ViewerDiagnosticCode code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'ViewerDiagnostic($code, $message)';
}
