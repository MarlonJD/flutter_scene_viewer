package com.marlonjd.flutter_scene_viewer_basisu;

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

public final class FlutterSceneViewerBasisuPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "flutter_scene_viewer/basisu";
  private static final String METHOD_GET_DECODER_AVAILABILITY =
      "getDecoderAvailability";
  private static final String METHOD_DECODE_GLB = "decodeGlb";
  private static final String METHOD_CANCEL_DECODE = "cancelDecode";
  private static final String BASISU_EXTENSION = "KHR_texture_basisu";
  private static final String INFO_PLIST_KEY = "FlutterSceneViewerBasisuEnabled";
  private static final String ANDROID_MANIFEST_KEY =
      "flutter_scene_viewer_basisu_enabled";

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
      System.loadLibrary("flutter_scene_viewer_basisu");
      return true;
    } catch (UnsatisfiedLinkError error) {
      return false;
    }
  }

  private static native boolean nativeTranscoderLinked();

  private static native boolean nativeImageTranscodeAvailable();

  private static native Map<String, Object> nativeTranscodeImages(
      Object basisuImages,
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

  private void startDecode(MethodCall call, MethodChannel.Result result) {
    String requestId = call.argument("requestId");
    ExecutorService executor = decodeExecutor;
    if (requestId == null || requestId.isEmpty() || executor == null || !attached) {
      result.error("invalidRequest", "decodeGlb requires an attached unique requestId.", null);
      return;
    }
    DecodeRequest request = new DecodeRequest(workingByteLimit(call));
    if (!request.isValid()) {
      result.error(
          "nativeControlUnavailable",
          "Native BasisU decode control allocation failed.",
          null);
      return;
    }
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
                    result.error("cancelled", "Native BasisU decode was cancelled.", null);
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
        result.error("detached", "Native BasisU decode executor is unavailable.", null);
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
          Map<String, Object> response =
              nativeTranscodeImages(
                  images,
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

  private static final class DecodeRequest
      implements FsvDecodeRequestRegistry.Control {
    final long controlHandle;
    boolean cancelled;
    boolean destroyed;

    DecodeRequest(long workingByteLimit) {
      long handle = 0;
      if (NATIVE_LIBRARY_LOADED) {
        try {
          handle = nativeCreateDecodeControl(workingByteLimit);
        } catch (UnsatisfiedLinkError error) {
          handle = 0;
        }
      }
      controlHandle = handle;
    }

    public boolean isValid() {
      return !destroyed && controlHandle != 0;
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
