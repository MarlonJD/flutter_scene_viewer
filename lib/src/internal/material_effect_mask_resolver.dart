import '../diagnostics.dart';
import '../material_patch.dart';
import '../part_address.dart';

List<ViewerDiagnostic> validateMaterialEffectMaskUv(
  PartAddress address,
  MaterialPatch patch, {
  required bool hasTexCoords,
}) {
  if (patch.effectMask == null || hasTexCoords) {
    return const <ViewerDiagnostic>[];
  }
  return <ViewerDiagnostic>[
    ViewerDiagnostic(
      code: ViewerDiagnosticCode.missingUvSet,
      message: 'Material effect mask requires authored UV coordinates.',
      details: <String, Object?>{'part': address.debugPath, 'uvSet': 0},
    ),
  ];
}
