import 'package:flutter/foundation.dart';

import 'render_policy.dart';

/// Small state machine that decides whether the viewer should render a frame.
@internal
final class AdaptiveRenderScheduler extends ChangeNotifier {
  AdaptiveRenderScheduler({
    RenderPolicy policy = RenderPolicy.adaptive,
    this.tailFrameCount = 2,
  })  : assert(tailFrameCount >= 0, 'tailFrameCount must be non-negative'),
        _policy = policy;

  final int tailFrameCount;

  RenderPolicy _policy;
  bool _isLoading = false;
  bool _isInteracting = false;
  bool _animationsEnabled = false;
  int _tailFramesRemaining = 0;
  int _explicitFramesRemaining = 0;

  RenderPolicy get policy => _policy;

  set policy(RenderPolicy value) {
    if (_policy == value) {
      return;
    }
    final wasRendering = shouldRender;
    _policy = value;
    _notifyIfRenderStateChanged(wasRendering);
  }

  bool get shouldRender {
    return switch (_policy) {
      RenderPolicy.always => true,
      RenderPolicy.onDemand => _explicitFramesRemaining > 0,
      RenderPolicy.whileInteracting => _isInteracting ||
          _tailFramesRemaining > 0 ||
          _explicitFramesRemaining > 0,
      RenderPolicy.adaptive => _isLoading ||
          _isInteracting ||
          _animationsEnabled ||
          _tailFramesRemaining > 0 ||
          _explicitFramesRemaining > 0,
    };
  }

  void setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    final wasRendering = shouldRender;
    _isLoading = value;
    _notifyIfRenderStateChanged(wasRendering);
  }

  void setAnimationsEnabled(bool value) {
    if (_animationsEnabled == value) {
      return;
    }
    final wasRendering = shouldRender;
    _animationsEnabled = value;
    _notifyIfRenderStateChanged(wasRendering);
  }

  void beginInteraction() {
    if (_isInteracting) {
      return;
    }
    final wasRendering = shouldRender;
    _isInteracting = true;
    _tailFramesRemaining = 0;
    _notifyIfRenderStateChanged(wasRendering);
  }

  void endInteraction() {
    if (!_isInteracting) {
      return;
    }
    final wasRendering = shouldRender;
    _isInteracting = false;
    _tailFramesRemaining = tailFrameCount;
    _notifyIfRenderStateChanged(wasRendering);
  }

  void requestFrame({int frameCount = 1}) {
    assert(frameCount > 0, 'frameCount must be positive');
    final wasRendering = shouldRender;
    if (frameCount > _explicitFramesRemaining) {
      _explicitFramesRemaining = frameCount;
    }
    _notifyIfRenderStateChanged(wasRendering);
  }

  void didRenderFrame() {
    final wasRendering = shouldRender;
    if (_explicitFramesRemaining > 0) {
      _explicitFramesRemaining -= 1;
    }
    if (!_isInteracting && _tailFramesRemaining > 0) {
      _tailFramesRemaining -= 1;
    }
    _notifyIfRenderStateChanged(wasRendering);
  }

  void _notifyIfRenderStateChanged(bool wasRendering) {
    if (wasRendering != shouldRender) {
      notifyListeners();
    }
  }
}
