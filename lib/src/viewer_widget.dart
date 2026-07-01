import 'package:flutter/widgets.dart';

import 'diagnostics.dart';
import 'material_patch.dart';
import 'model_source.dart';
import 'part_address.dart';
import 'render_policy.dart';
import 'viewer_controller.dart';
import 'viewer_lighting.dart';

/// High-level Flutter widget for viewing and configuring static GLB models.
class FlutterSceneViewer extends StatefulWidget {
  const FlutterSceneViewer({
    required this.source,
    this.controller,
    this.renderPolicy = RenderPolicy.adaptive,
    this.lighting = const ViewerLighting.studio(),
    this.onPartTapped,
    this.loadingBuilder,
    this.errorBuilder,
    super.key,
  });

  final ModelSource source;
  final FlutterSceneViewerController? controller;
  final RenderPolicy renderPolicy;
  final ViewerLighting lighting;
  final ValueChanged<PartAddress>? onPartTapped;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, ViewerDiagnostic diagnostic)?
      errorBuilder;

  @override
  State<FlutterSceneViewer> createState() => _FlutterSceneViewerState();
}

class _FlutterSceneViewerState extends State<FlutterSceneViewer>
    implements ViewerCommandSink {
  FlutterSceneViewerController? _ownedController;

  FlutterSceneViewerController get _controller =>
      widget.controller ??
      (_ownedController ??= FlutterSceneViewerController());

  @override
  void initState() {
    super.initState();
    _controller.attach(this);
  }

  @override
  void didUpdateWidget(covariant FlutterSceneViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.controller ?? _ownedController;
    final newController = widget.controller ?? _ownedController;
    if (!identical(oldController, newController)) {
      oldController?.detach(this);
      newController?.attach(this);
    }
  }

  @override
  void dispose() {
    _controller.detach(this);
    super.dispose();
  }

  @override
  Future<void> load(ModelSource source) async {
    // TODO: Implement via ModelLoader + FlutterSceneAdapter.
    _controller.recordDiagnostic(
      const ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterUnavailable,
        message: 'flutter_scene adapter is not implemented yet.',
      ),
    );
  }

  @override
  Future<void> setPartMaterial(PartAddress address, MaterialPatch patch) async {
    // TODO: Implement material patch application via adapter.
    _controller.recordDiagnostic(
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterUnavailable,
        message: 'Material override adapter is not implemented yet.',
        details: <String, Object?>{
          'part': address.debugPath,
          'empty': patch.isEmpty
        },
      ),
    );
  }

  @override
  Future<void> resetPart(PartAddress address) async {
    // TODO: Implement reset via MaterialOverrideStore.
    _controller.recordDiagnostic(
      ViewerDiagnostic(
        code: ViewerDiagnosticCode.adapterUnavailable,
        message: 'Material reset adapter is not implemented yet.',
        details: <String, Object?>{'part': address.debugPath},
      ),
    );
  }

  @override
  Future<void> fitCamera() async {
    // TODO: Implement after model bounds are available.
  }

  @override
  Widget build(BuildContext context) {
    return widget.loadingBuilder?.call(context) ??
        const Center(child: Text('flutter_scene_viewer adapter pending'));
  }
}
