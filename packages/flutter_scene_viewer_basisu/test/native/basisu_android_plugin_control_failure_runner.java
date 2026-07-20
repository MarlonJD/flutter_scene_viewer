package com.marlonjd.flutter_scene_viewer_basisu;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

final class BasisuAndroidPluginControlFailureRunner {
  private static final class FakePackageManager extends PackageManager {
    public ApplicationInfo getApplicationInfo(String name, int flags) {
      return new ApplicationInfo();
    }
  }

  private static final class FakeContext extends Context {
    private final PackageManager manager = new FakePackageManager();
    public PackageManager getPackageManager() { return manager; }
    public String getPackageName() { return "test"; }
  }

  private static final class FakeMessenger implements BinaryMessenger {}

  private static final class FakeBinding
      implements FlutterPlugin.FlutterPluginBinding {
    private final Context context = new FakeContext();
    private final BinaryMessenger messenger = new FakeMessenger();
    public Context getApplicationContext() { return context; }
    public BinaryMessenger getBinaryMessenger() { return messenger; }
  }

  private static final class CaptureResult implements MethodChannel.Result {
    int callbacks;
    String errorCode;
    public void success(Object value) { callbacks += 1; }
    public void error(String code, String message, Object details) {
      callbacks += 1;
      errorCode = code;
    }
    public void notImplemented() { callbacks += 1; }
  }

  public static void main(String[] args) {
    FlutterSceneViewerBasisuPlugin plugin =
        new FlutterSceneViewerBasisuPlugin();
    FakeBinding binding = new FakeBinding();
    plugin.onAttachedToEngine(binding);
    Map<String, Object> arguments = new HashMap<>();
    arguments.put("requestId", "control-failure");
    arguments.put("requiredExtensions", Arrays.asList("KHR_texture_basisu"));
    CaptureResult result = new CaptureResult();
    plugin.onMethodCall(new MethodCall("decodeGlb", arguments), result);
    plugin.onDetachedFromEngine(binding);
    if (result.callbacks != 1 ||
        !"nativeControlUnavailable".equals(result.errorCode)) {
      System.err.println("android-plugin-control-red callbacks=" +
          result.callbacks + " code=" + result.errorCode);
      System.exit(160);
    }
    System.out.println(
        "android-plugin-control-green callbacks=1 native-entered=0");
  }
}
