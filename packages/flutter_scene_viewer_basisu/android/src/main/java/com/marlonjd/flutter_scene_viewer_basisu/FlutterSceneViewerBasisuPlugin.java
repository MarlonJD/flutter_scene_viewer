package com.marlonjd.flutter_scene_viewer_basisu;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class FlutterSceneViewerBasisuPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "flutter_scene_viewer/basisu";
  private static final String METHOD_GET_DECODER_AVAILABILITY =
      "getDecoderAvailability";
  private static final String METHOD_DECODE_GLB = "decodeGlb";
  private static final String BASISU_EXTENSION = "KHR_texture_basisu";
  private static final String INFO_PLIST_KEY = "FlutterSceneViewerBasisuEnabled";
  private static final String ANDROID_MANIFEST_KEY =
      "flutter_scene_viewer_basisu_enabled";

  private static final boolean NATIVE_LIBRARY_LOADED = loadNativeLibrary();

  private MethodChannel channel;
  private Context applicationContext;

  private static boolean loadNativeLibrary() {
    try {
      System.loadLibrary("flutter_scene_viewer_basisu");
      return true;
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private static native boolean nativeTranscoderLinked();

  private static native boolean nativeImageTranscodeAvailable();

  private static native Map<String, Object> nativeTranscodeImages(
      Object basisuImages, String source);

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    applicationContext = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    applicationContext = null;
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (METHOD_GET_DECODER_AVAILABILITY.equals(call.method)) {
      result.success(availability(call));
      return;
    }
    if (METHOD_DECODE_GLB.equals(call.method)) {
      result.success(decodeGlb(call));
      return;
    }
    result.notImplemented();
  }

  private Map<String, Object> availability(MethodCall call) {
    boolean requiresBasisu = requiresBasisu(call.argument("requiredExtensions"));
    boolean enabled = isEnabled();
    boolean linked = isNativeTranscoderLinked();
    boolean imageTranscodeAvailable = isNativeImageTranscodeAvailable();
    List<Map<String, Object>> diagnostics = new ArrayList<>();
    String source = call.argument("source");

    if (requiresBasisu && !enabled) {
      diagnostics.add(
          diagnostic(
              "disabled",
              "Native BasisU/KTX2 transcoder is installed but disabled.",
              source));
    } else if (requiresBasisu && !linked) {
      diagnostics.add(
          diagnostic(
              "nativeLibraryUnavailable",
              "Native BasisU/KTX2 transcoder is enabled but the C++ transcoder is not linked.",
              source));
    } else if (requiresBasisu && !imageTranscodeAvailable) {
      diagnostics.add(
          diagnostic(
              "decodeUnavailable",
              "Native BasisU/KTX2 transcoder is linked but image transcode is not implemented.",
              source));
    }

    Map<String, Object> capabilities = new HashMap<>();
    capabilities.put("dracoMeshCompression", false);
    capabilities.put("meshoptCompression", false);
    capabilities.put(
        "textureBasisu", enabled && linked && imageTranscodeAvailable);

    Map<String, Object> response = new HashMap<>();
    response.put("capabilities", capabilities);
    response.put("diagnostics", diagnostics);
    return response;
  }

  private Map<String, Object> decodeGlb(MethodCall call) {
    boolean requiresBasisu = requiresBasisu(call.argument("requiredExtensions"));
    boolean enabled = isEnabled();
    boolean linked = isNativeTranscoderLinked();
    boolean imageTranscodeAvailable = isNativeImageTranscodeAvailable();
    List<Map<String, Object>> diagnostics = new ArrayList<>();
    String source = call.argument("source");

    if (!requiresBasisu) {
      byte[] bytes = call.argument("bytes");
      Map<String, Object> response = new HashMap<>();
      response.put("bytes", bytes != null ? bytes : new byte[0]);
      response.put("diagnostics", diagnostics);
      return response;
    }

    if (!enabled) {
      diagnostics.add(
          diagnostic(
              "disabled",
              "Native BasisU/KTX2 transcoder is installed but disabled.",
              source));
    } else if (!linked) {
      diagnostics.add(
          diagnostic(
              "nativeLibraryUnavailable",
              "Native BasisU/KTX2 transcoder is enabled but the C++ transcoder is not linked.",
              source));
    } else if (!imageTranscodeAvailable) {
      diagnostics.add(
          diagnostic(
              "decodeUnavailable",
              "Native BasisU/KTX2 transcoder is linked but image transcode is not implemented.",
              source));
    } else {
      Object images = call.argument("basisuImages");
      if (!(images instanceof List<?>) || ((List<?>) images).isEmpty()) {
        diagnostics.add(
            diagnostic(
                "decodeFailed",
                "Native BasisU/KTX2 transcoder did not receive image payloads.",
                source));
      } else {
        try {
          Map<String, Object> response = nativeTranscodeImages(images, source);
          if (response != null) {
            return response;
          }
          diagnostics.add(
              diagnostic(
                  "decodeFailed",
                  "Native BasisU/KTX2 transcoder returned no decode response.",
                  source));
        } catch (UnsatisfiedLinkError error) {
          diagnostics.add(
              diagnostic(
                  "nativeLibraryUnavailable",
                  "Native BasisU/KTX2 transcoder entrypoint is unavailable.",
                  source));
        }
      }
    }

    Map<String, Object> response = new HashMap<>();
    response.put("diagnostics", diagnostics);
    return response;
  }

  private boolean requiresBasisu(Object requiredExtensions) {
    if (!(requiredExtensions instanceof List<?>)) {
      return false;
    }
    return ((List<?>) requiredExtensions).contains(BASISU_EXTENSION);
  }

  private boolean isEnabled() {
    if (applicationContext == null) {
      return false;
    }
    try {
      ApplicationInfo info =
          applicationContext
              .getPackageManager()
              .getApplicationInfo(
                  applicationContext.getPackageName(),
                  PackageManager.GET_META_DATA);
      Bundle metadata = info.metaData;
      return metadata != null && metadata.getBoolean(ANDROID_MANIFEST_KEY, false);
    } catch (PackageManager.NameNotFoundException error) {
      return false;
    }
  }

  private boolean isNativeTranscoderLinked() {
    if (!NATIVE_LIBRARY_LOADED) {
      return false;
    }
    try {
      return nativeTranscoderLinked();
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private boolean isNativeImageTranscodeAvailable() {
    if (!NATIVE_LIBRARY_LOADED) {
      return false;
    }
    try {
      return nativeImageTranscodeAvailable();
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private Map<String, Object> diagnostic(
      String status, String message, String source) {
    Map<String, Object> details = new HashMap<>();
    details.put("extension", BASISU_EXTENSION);
    details.put("decoder", "basisu");
    details.put("required", true);
    details.put("status", status);
    details.put("pluginPackage", "flutter_scene_viewer_basisu");
    details.put("configurationKey", INFO_PLIST_KEY);
    details.put("androidManifestKey", ANDROID_MANIFEST_KEY);
    if (source != null) {
      details.put("source", source);
    }

    Map<String, Object> diagnostic = new HashMap<>();
    diagnostic.put("code", "unsupportedModelFeature");
    diagnostic.put("message", message);
    diagnostic.put("details", details);
    return diagnostic;
  }
}
