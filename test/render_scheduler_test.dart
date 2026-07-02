import 'package:flutter_scene_viewer/flutter_scene_viewer.dart';
import 'package:flutter_scene_viewer/src/render_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adaptive scheduler renders while loading and stops when idle', () {
    final scheduler = AdaptiveRenderScheduler(policy: RenderPolicy.adaptive);

    expect(scheduler.shouldRender, isFalse);

    scheduler.setLoading(true);

    expect(scheduler.shouldRender, isTrue);

    scheduler.setLoading(false);

    expect(scheduler.shouldRender, isFalse);
  });

  test('adaptive scheduler keeps a finite tail after interaction', () {
    final scheduler = AdaptiveRenderScheduler(
      policy: RenderPolicy.adaptive,
      tailFrameCount: 2,
    );

    scheduler.beginInteraction();
    expect(scheduler.shouldRender, isTrue);

    scheduler.endInteraction();
    expect(scheduler.shouldRender, isTrue);

    scheduler.didRenderFrame();
    expect(scheduler.shouldRender, isTrue);

    scheduler.didRenderFrame();
    expect(scheduler.shouldRender, isFalse);
  });

  test('on demand scheduler consumes explicit frame requests', () {
    final scheduler = AdaptiveRenderScheduler(policy: RenderPolicy.onDemand);

    expect(scheduler.shouldRender, isFalse);

    scheduler.requestFrame();
    expect(scheduler.shouldRender, isTrue);

    scheduler.didRenderFrame();
    expect(scheduler.shouldRender, isFalse);
  });
}
