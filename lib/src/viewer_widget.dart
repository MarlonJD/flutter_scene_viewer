import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'material_patch.dart';
import 'model_loader.dart';
import 'model_source.dart';
import 'orbit_camera_controller.dart';
import 'part_address.dart';
import 'render_policy.dart';
import 'render_scheduler.dart';
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
  }) : _adapterOverride = null;

  @visibleForTesting
  const FlutterSceneViewer.test({
    required this.source,
    required FlutterSceneAdapter adapter,
    this.controller,
    this.renderPolicy = RenderPolicy.adaptive,
    this.lighting = const ViewerLighting.studio(),
    this.onPartTapped,
    this.loadingBuilder,
    this.errorBuilder,
    super.key,
  }) : _adapterOverride = adapter;

  final ModelSource source;
  final FlutterSceneViewerController? controller;
  final RenderPolicy renderPolicy;
  final ViewerLighting lighting;
  final ValueChanged<PartAddress>? onPartTapped;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, ViewerDiagnostic diagnostic)?
      errorBuilder;
  final FlutterSceneAdapter? _adapterOverride;

  @override
  State<FlutterSceneViewer> createState() => _FlutterSceneViewerState();
}

class _FlutterSceneViewerState extends State<FlutterSceneViewer>
    implements ViewerCommandSink {
  FlutterSceneViewerController? _ownedController;
  FlutterSceneViewerController? _attachedController;
  FlutterSceneAdapter? _adapter;
  ModelLoader? _modelLoader;
  late final AdaptiveRenderScheduler _renderScheduler;
  final OrbitCameraController _cameraController = OrbitCameraController();
  var _renderGeneration = 0;
  var _frameCallbackScheduled = false;
  var _lastGestureScale = 1.0;

  FlutterSceneViewerController get _controller =>
      widget.controller ??
      (_ownedController ??= FlutterSceneViewerController());

  ModelLoader get _loader => _modelLoader ??= ModelLoader(
        adapter: _activeAdapter,
      );

  FlutterSceneAdapter get _activeAdapter =>
      _adapter ??= widget._adapterOverride ?? FlutterSceneRuntimeAdapter();

  @override
  void initState() {
    super.initState();
    _renderScheduler = AdaptiveRenderScheduler(policy: widget.renderPolicy);
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
    if (!identical(widget._adapterOverride, oldWidget._adapterOverride)) {
      _modelLoader?.dispose();
      _modelLoader = null;
      _adapter = widget._adapterOverride;
      shouldLoad = true;
    }
    _renderScheduler.policy = widget.renderPolicy;
    if (shouldLoad) {
      _startLoad(widget.source);
    }
  }

  @override
  void dispose() {
    _detachController();
    _modelLoader?.dispose();
    _renderScheduler.dispose();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Future<ModelLoadResult> load(ModelSource source) => _loader.load(source);

  @override
  Future<List<ViewerDiagnostic>> setPartMaterial(
    PartAddress address,
    MaterialPatch patch,
  ) {
    return _activeAdapter.applyMaterialPatch(
      address,
      patch,
    );
  }

  @override
  Future<List<ViewerDiagnostic>> resetPart(PartAddress address) {
    return _activeAdapter.resetMaterial(address);
  }

  @override
  Future<void> fitCamera() async {
    _cameraController.fitBounds(const ViewerBounds(radius: 1));
  }

  @override
  void requestRenderFrame() {
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
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
      return _buildReady();
    }
    return widget.loadingBuilder?.call(context) ??
        const Center(child: Text('Loading model...'));
  }

  Widget _buildReady() {
    final renderScene = _activeAdapter.renderScene;
    return GestureDetector(
      key: ValueKey<String>('flutter_scene_viewer.ready.$_renderGeneration'),
      behavior: HitTestBehavior.opaque,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: renderScene?.buildView(
            key: const ValueKey<String>('flutter_scene_viewer.render_surface'),
            camera: _cameraController.state.toRenderCameraFrame(),
            autoTick: widget.renderPolicy == RenderPolicy.always,
          ) ??
          const SizedBox.expand(),
    );
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
    _renderScheduler.setLoading(
      _controller.loadState.status == ViewerLoadStatus.loading,
    );
    if (mounted) {
      setState(() {});
      _scheduleRenderFrame();
    }
  }

  void _startLoad(ModelSource source) {
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(_controller.load(source));
      }
    });
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastGestureScale = 1;
    _renderScheduler.beginInteraction();
    _scheduleRenderFrame();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount <= 1) {
      _cameraController.orbit(
        yawDeltaRadians: details.focalPointDelta.dx * 0.01,
        pitchDeltaRadians: -details.focalPointDelta.dy * 0.01,
      );
    } else {
      _cameraController.pan(
        rightDelta: -details.focalPointDelta.dx * 0.01,
        upDelta: details.focalPointDelta.dy * 0.01,
      );
      if (details.scale > 0 && details.scale.isFinite) {
        _cameraController.zoom(_lastGestureScale / details.scale);
        _lastGestureScale = details.scale;
      }
    }
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _renderScheduler.endInteraction();
    _scheduleRenderFrame();
  }

  void _scheduleRenderFrame() {
    if (!_renderScheduler.shouldRender || _frameCallbackScheduled) {
      return;
    }
    _frameCallbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameCallbackScheduled = false;
      if (!mounted || !_renderScheduler.shouldRender) {
        return;
      }
      setState(() {
        _renderGeneration += 1;
      });
      _renderScheduler.didRenderFrame();
      _scheduleRenderFrame();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}
