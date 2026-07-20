package com.marlonjd.flutter_scene_viewer_draco;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

public final class FlutterSceneViewerDracoPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "flutter_scene_viewer/draco";
  private static final String METHOD_GET_DECODER_AVAILABILITY =
      "getDecoderAvailability";
  private static final String METHOD_DECODE_GLB = "decodeGlb";
  private static final String METHOD_CANCEL_DECODE = "cancelDecode";
  private static final String DRACO_EXTENSION = "KHR_draco_mesh_compression";
  private static final String INFO_PLIST_KEY = "FlutterSceneViewerDracoEnabled";
  private static final String ANDROID_MANIFEST_KEY =
      "flutter_scene_viewer_draco_enabled";

  private static final boolean NATIVE_LIBRARY_LOADED = loadNativeLibrary();

  private MethodChannel channel;
  private Context applicationContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final FsvDecodeRequestRegistry requestRegistry =
      new FsvDecodeRequestRegistry();
  private ExecutorService decodeExecutor;
  private volatile boolean attached;

  private static boolean loadNativeLibrary() {
    try {
      System.loadLibrary("flutter_scene_viewer_draco");
      return true;
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private static native boolean nativeDecoderLinked();

  private static native boolean nativePrimitiveDecodeAvailable();

  private static native Map<String, Object> nativeDecodePrimitives(
      Object dracoPrimitives,
      Object decodeBudget,
      Object decodeBudgetState,
      String source,
      long controlHandle);

  private static native long nativeCreateDecodeControl(long workingByteLimit);

  private static native boolean nativeCancelDecodeControl(long controlHandle);

  private static native void nativeDestroyDecodeControl(long controlHandle);

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    applicationContext = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    decodeExecutor =
        new ThreadPoolExecutor(
            2,
            2,
            0L,
            TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<Runnable>(32),
            new ThreadPoolExecutor.AbortPolicy());
    attached = true;
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    attached = false;
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    applicationContext = null;
    requestRegistry.beginDetach();
    ExecutorService executor = decodeExecutor;
    decodeExecutor = null;
    if (executor != null) {
      executor.shutdownNow();
      boolean interrupted = false;
      while (!executor.isTerminated()) {
        try {
          executor.awaitTermination(1, TimeUnit.SECONDS);
        } catch (InterruptedException error) {
          interrupted = true;
        }
      }
      if (interrupted) {
        Thread.currentThread().interrupt();
      }
    }
    requestRegistry.drainAfterWorkers();
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (METHOD_GET_DECODER_AVAILABILITY.equals(call.method)) {
      result.success(availability(call));
      return;
    }
    if (METHOD_DECODE_GLB.equals(call.method)) {
      startDecode(call, result);
      return;
    }
    if (METHOD_CANCEL_DECODE.equals(call.method)) {
      result.success(cancelDecode(call));
      return;
    }
    result.notImplemented();
  }

  private Map<String, Object> availability(MethodCall call) {
    boolean requiresDraco = requiresDraco(call.argument("requiredExtensions"));
    boolean enabled = isEnabled();
    boolean linked = isNativeDecoderLinked();
    boolean primitiveDecodeAvailable = isNativePrimitiveDecodeAvailable();
    List<Map<String, Object>> diagnostics = new ArrayList<>();
    String source = call.argument("source");

    if (requiresDraco && !enabled) {
      diagnostics.add(
          diagnostic(
              "disabled", "Native Draco decoder is installed but disabled.", source));
    } else if (requiresDraco && !linked) {
      diagnostics.add(
          diagnostic(
              "nativeLibraryUnavailable",
              "Native Draco decoder is enabled but the C++ decoder is not linked.",
              source));
    } else if (requiresDraco && !primitiveDecodeAvailable) {
      diagnostics.add(
          diagnostic(
              "decodeUnavailable",
              "Native Draco decoder is linked but primitive decode is not implemented.",
              source));
    }

    Map<String, Object> capabilities = new HashMap<>();
    capabilities.put(
        "dracoMeshCompression", enabled && linked && primitiveDecodeAvailable);
    capabilities.put("meshoptCompression", false);
    capabilities.put("textureBasisu", false);

    Map<String, Object> response = new HashMap<>();
    response.put("capabilities", capabilities);
    response.put("diagnostics", diagnostics);
    return response;
  }

  private void startDecode(MethodCall call, MethodChannel.Result result) {
    String requestId = call.argument("requestId");
    ExecutorService executor = decodeExecutor;
    if (requestId == null || requestId.isEmpty() || executor == null || !attached) {
      result.error("invalidRequest", "decodeGlb requires an attached unique requestId.", null);
      return;
    }
    DecodeRequest request = new DecodeRequest(workingByteLimit(call));
    FsvDecodeRequestRegistry.Entry entry =
        requestRegistry.register(requestId, request);
    if (entry == null) {
      request.destroy();
      result.error("duplicateRequest", "requestId is already active.", null);
      return;
    }
    try {
      executor.execute(
          () -> {
          Map<String, Object> response = null;
          Throwable failure = null;
          FsvDecodeRequestRegistry.FinishDisposition disposition;
          try {
            if (requestRegistry.shouldStart(entry)) {
              response = decodeGlbNow(call, request);
            }
          } catch (Throwable error) {
            failure = error;
          } finally {
            disposition = requestRegistry.finish(requestId, entry);
          }
          final Map<String, Object> finalResponse = response;
          final Throwable finalFailure = failure;
          mainHandler.post(
              () -> {
                if (attached && requestRegistry.claimDelivery(entry)) {
                  if (disposition ==
                      FsvDecodeRequestRegistry.FinishDisposition.CANCELLED) {
                    result.error("cancelled", "Native Draco decode was cancelled.", null);
                  } else if (disposition ==
                      FsvDecodeRequestRegistry.FinishDisposition.DETACHED) {
                    return;
                  } else if (finalFailure != null) {
                    result.error("decodeFailed", finalFailure.toString(), null);
                  } else {
                    result.success(finalResponse);
                  }
                }
              });
          });
    } catch (RejectedExecutionException error) {
      FsvDecodeRequestRegistry.FinishDisposition disposition =
          requestRegistry.finish(requestId, entry);
      if (disposition != FsvDecodeRequestRegistry.FinishDisposition.DETACHED
          && attached
          && requestRegistry.claimDelivery(entry)) {
        result.error("detached", "Native Draco decode executor is unavailable.", null);
      }
    }
  }

  private Map<String, Object> cancelDecode(MethodCall call) {
    String requestId = call.argument("requestId");
    Map<String, Object> response = new HashMap<>();
    response.put(
        "status",
        requestId == null ? "unknownRequest" : requestRegistry.cancel(requestId));
    return response;
  }

  private long workingByteLimit(MethodCall call) {
    Object rawBudget = call.argument("decodeBudget");
    if (rawBudget instanceof Map<?, ?>) {
      Object value = ((Map<?, ?>) rawBudget).get("maxNativeWorkingBytes");
      if (value instanceof Number) {
        return Math.max(0L, ((Number) value).longValue());
      }
    }
    return Long.MAX_VALUE;
  }

  private Map<String, Object> decodeGlbNow(MethodCall call, DecodeRequest request) {
    boolean requiresDraco = requiresDraco(call.argument("requiredExtensions"));
    boolean enabled = isEnabled();
    boolean linked = isNativeDecoderLinked();
    boolean primitiveDecodeAvailable = isNativePrimitiveDecodeAvailable();
    List<Map<String, Object>> diagnostics = new ArrayList<>();
    String source = call.argument("source");

    if (!requiresDraco) {
      byte[] bytes = call.argument("bytes");
      Map<String, Object> response = new HashMap<>();
      response.put("bytes", bytes != null ? bytes : new byte[0]);
      response.put("diagnostics", diagnostics);
      return response;
    }

    if (!enabled) {
      diagnostics.add(
          diagnostic(
              "disabled", "Native Draco decoder is installed but disabled.", source));
    } else if (!linked) {
      diagnostics.add(
          diagnostic(
              "nativeLibraryUnavailable",
              "Native Draco decoder is enabled but the C++ decoder is not linked.",
              source));
    } else if (!primitiveDecodeAvailable) {
      diagnostics.add(
          diagnostic(
              "decodeUnavailable",
              "Native Draco decoder is linked but primitive decode is not implemented.",
              source));
    } else {
      Object primitives = call.argument("dracoPrimitives");
      if (!(primitives instanceof List<?>) || ((List<?>) primitives).isEmpty()) {
        diagnostics.add(
            diagnostic(
                "decodeFailed",
                "Native Draco decoder did not receive Draco primitive payloads.",
                source));
      } else {
        try {
          Map<String, Object> response =
              nativeDecodePrimitives(
                  primitives,
                  call.argument("decodeBudget"),
                  call.argument("decodeBudgetState"),
                  source,
                  request.controlHandle);
          if (response != null) {
            return response;
          }
          diagnostics.add(
              diagnostic(
                  "decodeFailed",
                  "Native Draco decoder returned no decode response.",
                  source));
        } catch (UnsatisfiedLinkError error) {
          diagnostics.add(
              diagnostic(
                  "nativeLibraryUnavailable",
                  "Native Draco decoder entrypoint is unavailable.",
                  source));
        }
      }
    }

    Map<String, Object> response = new HashMap<>();
    response.put("diagnostics", diagnostics);
    return response;
  }

  private static final class DecodeRequest
      implements FsvDecodeRequestRegistry.Control {
    final long controlHandle;
    boolean cancelled;
    boolean destroyed;

    DecodeRequest(long workingByteLimit) {
      controlHandle = NATIVE_LIBRARY_LOADED
          ? nativeCreateDecodeControl(workingByteLimit)
          : 0;
    }

    public void cancel() {
      if (!destroyed && !cancelled && controlHandle != 0) {
        cancelled = true;
        nativeCancelDecodeControl(controlHandle);
      }
    }

    public void destroy() {
      if (!destroyed && controlHandle != 0) {
        destroyed = true;
        nativeDestroyDecodeControl(controlHandle);
      }
    }
  }

  private boolean requiresDraco(Object requiredExtensions) {
    if (!(requiredExtensions instanceof List<?>)) {
      return false;
    }
    return ((List<?>) requiredExtensions).contains(DRACO_EXTENSION);
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

  private boolean isNativeDecoderLinked() {
    if (!NATIVE_LIBRARY_LOADED) {
      return false;
    }
    try {
      return nativeDecoderLinked();
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private boolean isNativePrimitiveDecodeAvailable() {
    if (!NATIVE_LIBRARY_LOADED) {
      return false;
    }
    try {
      return nativePrimitiveDecodeAvailable();
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private Map<String, Object> diagnostic(
      String status, String message, String source) {
    Map<String, Object> details = new HashMap<>();
    details.put("extension", DRACO_EXTENSION);
    details.put("decoder", "draco");
    details.put("required", true);
    details.put("status", status);
    details.put("pluginPackage", "flutter_scene_viewer_draco");
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
