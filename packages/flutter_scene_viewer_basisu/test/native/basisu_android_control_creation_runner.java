package com.marlonjd.flutter_scene_viewer_basisu;

final class BasisuAndroidControlCreationRunner {
  private static final class TestControl
      implements FsvDecodeRequestRegistry.Control {
    TestControl(boolean valid) {
      this.valid = valid;
    }

    public boolean isValid() {
      return valid;
    }

    public void cancel() {
      cancelled = true;
    }

    public void destroy() {
      destroyed = true;
    }

    final boolean valid;
    boolean cancelled;
    boolean destroyed;
  }

  public static void main(String[] args) {
    FsvDecodeRequestRegistry registry = new FsvDecodeRequestRegistry();
    TestControl invalid = new TestControl(false);
    if (registry.register("invalid", invalid) != null ||
        registry.activeCount() != 0 || invalid.cancelled || invalid.destroyed) {
      System.err.println("android-control-creation-red invalid control registered");
      System.exit(160);
    }

    TestControl fresh = new TestControl(true);
    FsvDecodeRequestRegistry.Entry entry = registry.register("fresh", fresh);
    if (entry == null || !registry.shouldStart(entry) ||
        registry.finish("fresh", entry) !=
            FsvDecodeRequestRegistry.FinishDisposition.SUCCESS ||
        !fresh.destroyed || registry.activeCount() != 0) {
      System.exit(161);
    }
    System.out.println("android-control-creation-green fresh=success");
  }
}
