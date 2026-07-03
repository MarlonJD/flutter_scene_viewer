import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'diagnostics.dart';
import 'internal/flutter_scene_adapter.dart';
import 'internal/render_surface.dart';
import 'material_patch.dart';
import 'material_shading_mode.dart';
import 'model_loader.dart';
import 'model_source.dart';
import 'orbit_camera_controller.dart';
import 'part_address.dart';
import 'render_policy.dart';
import 'render_scheduler.dart';
import 'viewer_controller.dart';
import 'viewer_environment.dart';
import 'viewer_lighting.dart';
import 'viewer_stats.dart';

/// High-level Flutter widget for viewing and configuring static GLB models.
class FlutterSceneViewer extends StatefulWidget {
  const FlutterSceneViewer({
    required this.source,
    this.controller,
    this.renderPolicy = RenderPolicy.adaptive,
    this.lighting = const ViewerLighting.studio(),
    this.environment = const ViewerEnvironment.studio(),
    this.materialShadingPolicy = MaterialShadingPolicy.authored,
    this.debugShowStatsOverlay = false,
    this.onStats,
    this.autoOrbit = false,
    this.autoOrbitSpeedRadiansPerSecond = 0.35,
    this.allowCameraInsideModel = false,
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
    this.environment = const ViewerEnvironment.studio(),
    this.materialShadingPolicy = MaterialShadingPolicy.authored,
    this.debugShowStatsOverlay = false,
    this.onStats,
    this.autoOrbit = false,
    this.autoOrbitSpeedRadiansPerSecond = 0.35,
    this.allowCameraInsideModel = false,
    this.onPartTapped,
    this.loadingBuilder,
    this.errorBuilder,
    super.key,
  }) : _adapterOverride = adapter;

  final ModelSource source;
  final FlutterSceneViewerController? controller;
  final RenderPolicy renderPolicy;
  final ViewerLighting lighting;
  final ViewerEnvironment environment;
  final MaterialShadingPolicy materialShadingPolicy;
  final bool debugShowStatsOverlay;
  final ValueChanged<ViewerStatsSnapshot>? onStats;
  final bool autoOrbit;
  final double autoOrbitSpeedRadiansPerSecond;
  final bool allowCameraInsideModel;
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
  static const double _tapSlop = 8.0;

  FlutterSceneViewerController? _ownedController;
  FlutterSceneViewerController? _attachedController;
  FlutterSceneAdapter? _adapter;
  ModelLoader? _modelLoader;
  late final AdaptiveRenderScheduler _renderScheduler;
  final OrbitCameraController _cameraController = OrbitCameraController();
  Completer<void>? _pendingFitCamera;
  double? _viewportAspectRatio;
  var _renderGeneration = 0;
  var _frameCallbackScheduled = false;
  var _pendingFitCameraFrameScheduled = false;
  var _lastPanZoomScale = 1.0;
  var _debugFrameCount = 0;
  var _debugFramesPerSecond = 0;
  final List<double> _debugFrameIntervalSamples = <double>[];
  var _environmentConfigurationGeneration = 0;
  ModelLoadResult? _lastModelLoadResult;
  ViewerStatsSnapshot? _lastStatsSnapshot;
  Duration? _lastAutoOrbitFrameTimestamp;
  Duration? _lastStatsFrameTimestamp;
  Timer? _debugStatsTimer;
  ViewerEnvironment? _lastEnvironmentConfigurationAttempt;
  FlutterSceneAdapter? _lastEnvironmentConfigurationAdapter;
  Size? _viewportSize;
  final Map<int, Offset> _activeTouchPositions = <int, Offset>{};
  Offset? _lastTouchCentroid;
  double? _lastTouchSpan;
  int? _tapCandidatePointer;
  Offset? _tapCandidatePosition;
  var _tapCandidateCanceled = false;

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
    _syncDebugStatsTimer();
    _syncAutoOrbit();
    _startLoad(widget.source);
  }

  @override
  void didUpdateWidget(covariant FlutterSceneViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    var shouldLoad = widget.source != oldWidget.source ||
        widget.materialShadingPolicy != oldWidget.materialShadingPolicy;
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
    _syncDebugStatsTimer();
    _syncAutoOrbit();
    if (shouldLoad) {
      _resetEnvironmentConfigurationAttempt();
      _startLoad(widget.source);
    } else if (widget.environment != oldWidget.environment) {
      _resetEnvironmentConfigurationAttempt();
      unawaited(_configureEnvironmentIfReady());
    }
  }

  @override
  void dispose() {
    _debugStatsTimer?.cancel();
    _completePendingFitCamera();
    _detachController();
    _modelLoader?.dispose();
    _renderScheduler.dispose();
    _cameraController.dispose();
    _activeTouchPositions.clear();
    super.dispose();
  }

  @override
  Future<ModelLoadResult> load(ModelSource source) async {
    final result = await _loader.load(
      source,
      materialShadingPolicy: widget.materialShadingPolicy,
    );
    _lastModelLoadResult = result.isSuccess ? result : null;
    return result;
  }

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
    if (_viewportAspectRatio == null &&
        _controller.loadState.status == ViewerLoadStatus.success) {
      final pending = _pendingFitCamera ??= Completer<void>();
      return pending.future;
    }
    _fitCameraToCurrentBounds();
  }

  @override
  Future<void> setCameraOrbit({
    List<double>? target,
    double? distance,
    double? yawRadians,
    double? pitchRadians,
  }) async {
    _cameraController.setOrbit(
      target: target,
      distance: distance,
      yawRadians: yawRadians,
      pitchRadians: pitchRadians,
    );
  }

  @override
  Future<void> setCameraPosition({
    required List<double> position,
    required List<double> target,
  }) async {
    _cameraController.setPosition(position: position, target: target);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportAspectRatio = _aspectRatioFor(constraints);
        _viewportSize = _sizeFor(constraints);
        _schedulePendingFitCamera();
        final renderScene = _activeAdapter.renderScene;
        final viewer = Listener(
          key: ValueKey<String>(
            'flutter_scene_viewer.ready.$_renderGeneration',
          ),
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          onPointerPanZoomStart: _handlePointerPanZoomStart,
          onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
          onPointerPanZoomEnd: _handlePointerPanZoomEnd,
          child: renderScene?.buildView(
                key: const ValueKey<String>(
                  'flutter_scene_viewer.render_surface',
                ),
                camera: _cameraController.state.toRenderCameraFrame(),
                lighting: _renderLightingFrame(widget.lighting),
                environment: _renderEnvironmentFrame(widget.environment),
                autoTick: widget.renderPolicy == RenderPolicy.always,
              ) ??
              const SizedBox.expand(),
        );
        if (!widget.debugShowStatsOverlay) {
          return viewer;
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            viewer,
            Positioned(
              top: 8,
              left: 8,
              child: _DebugStatsOverlay(
                snapshot: _lastStatsSnapshot ??
                    _buildStatsSnapshot(
                      framesPerSecond: _debugFramesPerSecond,
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _fitCameraToCurrentBounds() {
    final modelBounds = _activeAdapter.modelBounds;
    _cameraController.fitBounds(
      modelBounds == null
          ? const ViewerBounds(radius: 1)
          : ViewerBounds(
              center: modelBounds.center,
              radius: modelBounds.radius,
            ),
      aspectRatio: _viewportAspectRatio ?? 1,
      padding: 1.15,
      minDistanceFactor: widget.allowCameraInsideModel
          ? OrbitCameraController.allowModelEntryMinDistanceFactor
          : OrbitCameraController.preventModelEntryMinDistanceFactor,
    );
  }

  void _schedulePendingFitCamera() {
    if (_pendingFitCamera == null || _pendingFitCameraFrameScheduled) {
      return;
    }
    _pendingFitCameraFrameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingFitCameraFrameScheduled = false;
      if (mounted) {
        _fitCameraToCurrentBounds();
      }
      _completePendingFitCamera();
    });
  }

  void _completePendingFitCamera() {
    final pending = _pendingFitCamera;
    _pendingFitCamera = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
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
    _syncAutoOrbit();
    if (_controller.loadState.status == ViewerLoadStatus.success) {
      unawaited(_configureEnvironmentIfReady());
    }
    if (mounted) {
      setState(() {});
      _scheduleRenderFrame();
    }
  }

  void _startLoad(ModelSource source) {
    _resetEnvironmentConfigurationAttempt();
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(_controller.load(source));
      }
    });
  }

  void _resetEnvironmentConfigurationAttempt() {
    _environmentConfigurationGeneration += 1;
    _lastEnvironmentConfigurationAttempt = null;
    _lastEnvironmentConfigurationAdapter = null;
  }

  Future<void> _configureEnvironmentIfReady() async {
    if (_controller.loadState.status != ViewerLoadStatus.success) {
      return;
    }
    final adapter = _activeAdapter;
    final environment = widget.environment;
    if (_lastEnvironmentConfigurationAttempt == environment &&
        identical(_lastEnvironmentConfigurationAdapter, adapter)) {
      return;
    }
    _lastEnvironmentConfigurationAttempt = environment;
    _lastEnvironmentConfigurationAdapter = adapter;
    final generation = _environmentConfigurationGeneration;
    final diagnostics = await adapter.configureEnvironment(
      _renderEnvironmentFrame(environment),
      isCanceled: () =>
          !mounted || generation != _environmentConfigurationGeneration,
    );
    if (!mounted || generation != _environmentConfigurationGeneration) {
      return;
    }
    if (diagnostics.isNotEmpty) {
      for (final diagnostic in diagnostics) {
        _controller.recordDiagnostic(diagnostic);
      }
      return;
    }
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_activeTouchPositions.isEmpty && widget.onPartTapped != null) {
      _tapCandidatePointer = event.pointer;
      _tapCandidatePosition = event.localPosition;
      _tapCandidateCanceled = false;
    } else {
      _cancelTapCandidate();
    }
    _activeTouchPositions[event.pointer] = event.localPosition;
    if (_activeTouchPositions.length > 1) {
      _cancelTapCandidate();
    }
    _resetTouchReference();
    _renderScheduler.beginInteraction();
    _scheduleRenderFrame();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final previous = _activeTouchPositions[event.pointer];
    if (previous == null) {
      return;
    }
    if (_tapCandidatePointer == event.pointer) {
      final tapStart = _tapCandidatePosition;
      if (tapStart == null ||
          (event.localPosition - tapStart).distance > _tapSlop) {
        _tapCandidateCanceled = true;
      }
    }
    _activeTouchPositions[event.pointer] = event.localPosition;
    if (_activeTouchPositions.length <= 1) {
      final delta = event.localPosition - previous;
      _cameraController.orbit(
        yawDeltaRadians: delta.dx * 0.01,
        pitchDeltaRadians: delta.dy * 0.01,
      );
    } else {
      final centroid = _touchCentroid();
      final span = _touchSpan(centroid);
      final previousCentroid = _lastTouchCentroid ?? centroid;
      final previousSpan = _lastTouchSpan ?? span;
      final centroidDelta = centroid - previousCentroid;
      _cameraController.pan(
        rightDelta: -centroidDelta.dx * 0.01,
        upDelta: centroidDelta.dy * 0.01,
      );
      if (span > 0 && previousSpan > 0) {
        _cameraController.zoom(previousSpan / span);
      }
      _lastTouchCentroid = centroid;
      _lastTouchSpan = span;
    }
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
  }

  void _handlePointerUp(PointerUpEvent event) {
    final shouldPick = _shouldPickForPointerUp(event);
    _activeTouchPositions.remove(event.pointer);
    _handlePointerFinished();
    _clearTapCandidateFor(event.pointer);
    if (shouldPick) {
      unawaited(_pickPartAt(event.localPosition));
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activeTouchPositions.remove(event.pointer);
    _handlePointerFinished();
    _clearTapCandidateFor(event.pointer);
  }

  void _handlePointerFinished() {
    _resetTouchReference();
    if (_activeTouchPositions.isEmpty) {
      _renderScheduler.endInteraction();
    }
    _scheduleRenderFrame();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    _cancelTapCandidate();
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta;
    if (delta.dx.abs() > delta.dy.abs()) {
      _cameraController.orbit(
        yawDeltaRadians: delta.dx * 0.01,
        pitchDeltaRadians: 0,
      );
    } else {
      _cameraController.zoom(1 + delta.dy * 0.001);
    }
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _cancelTapCandidate();
    _lastPanZoomScale = 1;
    _renderScheduler.beginInteraction();
    _scheduleRenderFrame();
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _cameraController.orbit(
      yawDeltaRadians: event.panDelta.dx * 0.01,
      pitchDeltaRadians: event.panDelta.dy * 0.01,
    );
    if (event.scale > 0 && event.scale.isFinite) {
      _cameraController.zoom(_lastPanZoomScale / event.scale);
      _lastPanZoomScale = event.scale;
    }
    _renderScheduler.requestFrame();
    _scheduleRenderFrame();
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _renderScheduler.endInteraction();
    _scheduleRenderFrame();
  }

  bool _shouldPickForPointerUp(PointerUpEvent event) {
    if (widget.onPartTapped == null ||
        _tapCandidatePointer != event.pointer ||
        _tapCandidateCanceled ||
        _activeTouchPositions.length != 1) {
      return false;
    }
    final tapStart = _tapCandidatePosition;
    if (tapStart == null) {
      return false;
    }
    return (event.localPosition - tapStart).distance <= _tapSlop;
  }

  Future<void> _pickPartAt(Offset localPosition) async {
    final callback = widget.onPartTapped;
    final viewportSize = _viewportSize;
    if (callback == null ||
        viewportSize == null ||
        _controller.loadState.status != ViewerLoadStatus.success) {
      return;
    }
    final address = await _activeAdapter.pickPart(
      localPosition: localPosition,
      viewportSize: viewportSize,
      camera: _cameraController.state.toRenderCameraFrame(),
    );
    if (!mounted || address == null) {
      return;
    }
    callback(address);
  }

  void _cancelTapCandidate() {
    _tapCandidateCanceled = true;
  }

  void _clearTapCandidateFor(int pointer) {
    if (_tapCandidatePointer != pointer) {
      return;
    }
    _tapCandidatePointer = null;
    _tapCandidatePosition = null;
    _tapCandidateCanceled = false;
  }

  void _resetTouchReference() {
    if (_activeTouchPositions.length >= 2) {
      final centroid = _touchCentroid();
      _lastTouchCentroid = centroid;
      _lastTouchSpan = _touchSpan(centroid);
    } else {
      _lastTouchCentroid = null;
      _lastTouchSpan = null;
    }
  }

  Offset _touchCentroid() {
    var x = 0.0;
    var y = 0.0;
    for (final position in _activeTouchPositions.values) {
      x += position.dx;
      y += position.dy;
    }
    final count = _activeTouchPositions.length;
    return Offset(x / count, y / count);
  }

  double _touchSpan(Offset centroid) {
    var total = 0.0;
    for (final position in _activeTouchPositions.values) {
      total += (position - centroid).distance;
    }
    return total / _activeTouchPositions.length;
  }

  void _syncDebugStatsTimer() {
    if (!_statsEnabled) {
      _debugStatsTimer?.cancel();
      _debugStatsTimer = null;
      _debugFrameCount = 0;
      _debugFramesPerSecond = 0;
      _debugFrameIntervalSamples.clear();
      _lastStatsFrameTimestamp = null;
      _lastStatsSnapshot = null;
      return;
    }
    _debugStatsTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final snapshot = _buildStatsSnapshot(framesPerSecond: _debugFrameCount);
      if (widget.debugShowStatsOverlay) {
        setState(() {
          _debugFramesPerSecond = _debugFrameCount;
          _debugFrameCount = 0;
          _debugFrameIntervalSamples.clear();
          _lastStatsSnapshot = snapshot;
        });
      } else {
        _debugFramesPerSecond = _debugFrameCount;
        _debugFrameCount = 0;
        _debugFrameIntervalSamples.clear();
        _lastStatsSnapshot = snapshot;
      }
      widget.onStats?.call(snapshot);
    });
  }

  bool get _statsEnabled =>
      widget.debugShowStatsOverlay || widget.onStats != null;

  void _recordStatsFrame(Duration timestamp) {
    if (!_statsEnabled) {
      return;
    }
    final previous = _lastStatsFrameTimestamp;
    _lastStatsFrameTimestamp = timestamp;
    if (previous != null) {
      final intervalMs = (timestamp - previous).inMicroseconds / 1000.0;
      if (intervalMs >= 0 && intervalMs.isFinite) {
        _debugFrameIntervalSamples.add(intervalMs);
        if (_debugFrameIntervalSamples.length > 120) {
          _debugFrameIntervalSamples.removeAt(0);
        }
      }
    }
    _debugFrameCount += 1;
  }

  ViewerStatsSnapshot _buildStatsSnapshot({required int framesPerSecond}) {
    final intervals = _debugFrameIntervalSamples;
    var averageMs = 0.0;
    var minMs = 0.0;
    var maxMs = 0.0;
    if (intervals.isNotEmpty) {
      var totalMs = 0.0;
      minMs = intervals.first;
      maxMs = intervals.first;
      for (final interval in intervals) {
        totalMs += interval;
        minMs = math.min(minMs, interval);
        maxMs = math.max(maxMs, interval);
      }
      averageMs = totalMs / intervals.length;
    }
    final diagnostics = _controller.diagnostics;
    final camera = _cameraController.state;
    final loadResult = _lastModelLoadResult;
    return ViewerStatsSnapshot(
      framesPerSecond: framesPerSecond,
      frameIntervalAverageMs: averageMs,
      frameIntervalMinMs: minMs,
      frameIntervalMaxMs: maxMs,
      renderPolicyActive: _renderScheduler.shouldRender,
      autoTick: widget.renderPolicy == RenderPolicy.always,
      autoOrbit: _autoOrbitEnabled,
      cameraDistance: camera.distance,
      cameraPosition: List<double>.unmodifiable(camera.position),
      diagnosticsCount: diagnostics.length,
      lastDiagnosticCode:
          diagnostics.isEmpty ? null : diagnostics.last.code.name,
      modelLoadDuration: loadResult?.modelLoadDuration,
      modelByteSize: loadResult?.modelByteSize,
      nodeCount: loadResult?.nodeCount,
      meshCount: loadResult?.meshCount,
      materialCount: loadResult?.materialCount,
      primitiveCount: loadResult?.primitiveCount,
    );
  }

  bool get _autoOrbitEnabled {
    return widget.autoOrbit &&
        widget.autoOrbitSpeedRadiansPerSecond.isFinite &&
        widget.autoOrbitSpeedRadiansPerSecond != 0 &&
        _controller.loadState.status == ViewerLoadStatus.success;
  }

  void _syncAutoOrbit() {
    final enabled = _autoOrbitEnabled;
    _renderScheduler.setAnimationsEnabled(enabled);
    if (!enabled) {
      _lastAutoOrbitFrameTimestamp = null;
      return;
    }
    _scheduleRenderFrame();
  }

  void _applyAutoOrbitForFrame(Duration timestamp) {
    if (!_autoOrbitEnabled) {
      _lastAutoOrbitFrameTimestamp = null;
      return;
    }
    final previous = _lastAutoOrbitFrameTimestamp;
    _lastAutoOrbitFrameTimestamp = timestamp;
    if (previous == null) {
      return;
    }
    final elapsedSeconds =
        (timestamp - previous).inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0 || !elapsedSeconds.isFinite) {
      return;
    }
    final cappedElapsedSeconds = math.min(elapsedSeconds, 0.1);
    _cameraController.orbit(
      yawDeltaRadians:
          widget.autoOrbitSpeedRadiansPerSecond * cappedElapsedSeconds,
      pitchDeltaRadians: 0,
    );
  }

  void _scheduleRenderFrame() {
    if (!_renderScheduler.shouldRender || _frameCallbackScheduled) {
      return;
    }
    _frameCallbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((timestamp) {
      _frameCallbackScheduled = false;
      if (!mounted || !_renderScheduler.shouldRender) {
        return;
      }
      setState(() {
        _applyAutoOrbitForFrame(timestamp);
        _renderGeneration += 1;
        _recordStatsFrame(timestamp);
      });
      _renderScheduler.didRenderFrame();
      _scheduleRenderFrame();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

final class _DebugStatsOverlay extends StatelessWidget {
  const _DebugStatsOverlay({
    required this.snapshot,
  });

  final ViewerStatsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('flutter_scene_viewer.debug_stats'),
      decoration: BoxDecoration(
        color: const Color(0xB0000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 12,
            height: 1.25,
          ),
          child: Text(
            'debug evidence\n'
            'FPS: ${snapshot.framesPerSecond}\n'
            'frame ms: ${_formatDebugDouble(snapshot.frameIntervalAverageMs)} '
            'avg / ${_formatDebugDouble(snapshot.frameIntervalMinMs)} min / '
            '${_formatDebugDouble(snapshot.frameIntervalMaxMs)} max\n'
            'tick: ${snapshot.renderPolicyActive ? 'active' : 'idle'}\n'
            'autoTick: ${snapshot.autoTick ? 'on' : 'off'}\n'
            'autoOrbit: ${snapshot.autoOrbit ? 'on' : 'off'}\n'
            'diagnostics: ${snapshot.diagnosticsCount}\n'
            'model bytes: ${_formatOptionalInt(snapshot.modelByteSize)}\n'
            'nodes: ${_formatOptionalInt(snapshot.nodeCount)}\n'
            'meshes: ${_formatOptionalInt(snapshot.meshCount)}\n'
            'materials: ${_formatOptionalInt(snapshot.materialCount)}\n'
            'primitives: ${_formatOptionalInt(snapshot.primitiveCount)}\n'
            'dist: ${_formatDebugDouble(snapshot.cameraDistance)}\n'
            'pos: ${_formatDebugVector(snapshot.cameraPosition)}',
          ),
        ),
      ),
    );
  }
}

String _formatDebugVector(List<double> values) {
  return '${_formatDebugDouble(values[0])}, '
      '${_formatDebugDouble(values[1])}, '
      '${_formatDebugDouble(values[2])}';
}

String _formatDebugDouble(double value) {
  if (!value.isFinite) {
    return value.toString();
  }
  return value.toStringAsFixed(2);
}

String _formatOptionalInt(int? value) => value?.toString() ?? 'unknown';

RenderLightingFrame _renderLightingFrame(ViewerLighting lighting) {
  return switch (lighting.kind) {
    ViewerLightingKind.studio => RenderLightingFrame(
        kind: RenderLightingKind.studio,
        exposure: lighting.exposure,
        ambientOcclusionEnabled: lighting.ambientOcclusion,
        environmentIntensity: lighting.environmentIntensity,
        keyLightIntensity: lighting.keyLightIntensity,
        keyLightColor: lighting.keyLightColor,
        keyLightDirection: lighting.keyLightDirection,
        keyLightCastsShadow: lighting.keyLightCastsShadow,
        keyLightShadowMapResolution: lighting.keyLightShadowMapResolution,
        keyLightShadowMaxDistance: lighting.keyLightShadowMaxDistance,
        keyLightShadowSoftness: lighting.keyLightShadowSoftness,
        keyLightShadowFadeRange: lighting.keyLightShadowFadeRange,
        keyLightShadowDepthBias: lighting.keyLightShadowDepthBias,
        keyLightShadowNormalBias: lighting.keyLightShadowNormalBias,
        keyLightShadowCascadeCount: lighting.keyLightShadowCascadeCount,
        keyLightShadowCascadeSplitLambda:
            lighting.keyLightShadowCascadeSplitLambda,
      ),
    ViewerLightingKind.none => RenderLightingFrame(
        kind: RenderLightingKind.none,
        exposure: lighting.exposure,
        environmentIntensity: 0,
        keyLightIntensity: 0,
        keyLightColor: const <double>[0, 0, 0],
        keyLightCastsShadow: false,
      ),
  };
}

RenderEnvironmentFrame _renderEnvironmentFrame(ViewerEnvironment environment) {
  return switch (environment) {
    ViewerStudioEnvironment() => RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.studio,
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
    ViewerEmptyEnvironment() => RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.empty,
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
    ViewerAssetEnvironment(:final radianceImageAsset) => RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.asset,
        assetPath: radianceImageAsset,
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
    ViewerRawAssetEnvironment(:final assetPath, :final format) =>
      RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.rawAsset,
        assetPath: assetPath,
        rawFormat: _renderEnvironmentFileFormat(format),
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
    ViewerRawBytesEnvironment(:final bytes, :final debugName, :final format) =>
      RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.rawBytes,
        rawBytes: bytes,
        rawDebugName: debugName,
        rawFormat: _renderEnvironmentFileFormat(format),
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
    ViewerPolyHavenEnvironment(
      :final assetId,
      :final resolution,
      :final fileType,
      :final userAgent
    ) =>
      RenderEnvironmentFrame(
        kind: RenderEnvironmentKind.polyHaven,
        polyHavenAssetId: assetId,
        polyHavenResolution: resolution.apiValue,
        polyHavenFileType: fileType.apiValue,
        polyHavenUserAgent: userAgent,
        intensity: environment.intensity,
        rotationRadians: environment.rotationRadians,
        showSkybox: environment.showSkybox,
        skyboxBlur: environment.skyboxBlur,
      ),
  };
}

RenderEnvironmentFileFormat _renderEnvironmentFileFormat(
  ViewerEnvironmentFileFormat format,
) {
  return switch (format) {
    ViewerEnvironmentFileFormat.auto => RenderEnvironmentFileFormat.auto,
    ViewerEnvironmentFileFormat.hdr => RenderEnvironmentFileFormat.hdr,
    ViewerEnvironmentFileFormat.exr => RenderEnvironmentFileFormat.exr,
  };
}

double _aspectRatioFor(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return 1;
  }
  return width / height;
}

Size? _sizeFor(BoxConstraints constraints) {
  final width = constraints.maxWidth;
  final height = constraints.maxHeight;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    return null;
  }
  return Size(width, height);
}
