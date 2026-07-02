import 'dart:async';

import 'package:flutter/widgets.dart';

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'material_patch.dart';
import 'model_loader.dart';
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
  FlutterSceneViewerController? _attachedController;
  FlutterSceneAdapter? _adapter;
  ModelLoader? _modelLoader;

  FlutterSceneViewerController get _controller =>
      widget.controller ??
      (_ownedController ??= FlutterSceneViewerController());

  ModelLoader get _loader => _modelLoader ??= ModelLoader(
        adapter: _adapter ??= FlutterSceneRuntimeAdapter(),
      );

  @override
  void initState() {
    super.initState();
    _attachController(_controller);
    _startLoad(widget.source);
  }

  @override
  void didUpdateWidget(covariant FlutterSceneViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    var shouldLoad = !identical(widget.source, oldWidget.source);
    if (!identical(_attachedController, _controller)) {
      _detachController();
      _attachController(_controller);
      shouldLoad = true;
    }
    if (shouldLoad) {
      _startLoad(widget.source);
    }
  }

  @override
  void dispose() {
    _detachController();
    _modelLoader?.dispose();
    super.dispose();
  }

  @override
  Future<ModelLoadResult> load(ModelSource source) => _loader.load(source);

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) {
    return (_adapter ??= FlutterSceneRuntimeAdapter()).applyMaterialPatch(
      address,
      patch,
    );
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) {
    return (_adapter ??= FlutterSceneRuntimeAdapter()).resetMaterial(address);
  }

  @override
  Future<void> fitCamera() async {
    // TODO: Implement after model bounds are available.
  }

  @override
  Widget build(BuildContext context) {
    final loadState = _controller.loadState;
    if (loadState.status == ViewerLoadStatus.error &&
        loadState.diagnostic != null) {
      return widget.errorBuilder?.call(context, loadState.diagnostic!) ??
          Center(child: Text(loadState.diagnostic!.message));
    }
    if (loadState.status == ViewerLoadStatus.success) {
      return const SizedBox.shrink();
    }
    return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
  }

  void _attachController(FlutterSceneViewerController controller) {
    _attachedController = controller;
    controller.attach(this);
    controller.addListener(_handleControllerChanged);
  }

  void _detachController() {
    final controller = _attachedController;
    if (controller == null) {
      return;
    }
    controller.removeListener(_handleControllerChanged);
    controller.detach(this);
    _attachedController = null;
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startLoad(ModelSource source) {
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(_controller.load(source));
      }
    });
  }
}
