package io.flutter.embedding.engine.plugins;

import android.content.Context;
import io.flutter.plugin.common.BinaryMessenger;

public interface FlutterPlugin {
  interface FlutterPluginBinding {
    Context getApplicationContext();
    BinaryMessenger getBinaryMessenger();
  }

  void onAttachedToEngine(FlutterPluginBinding binding);
  void onDetachedFromEngine(FlutterPluginBinding binding);
}
