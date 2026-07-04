#import "FlutterSceneViewerBasisuPlugin.h"

#import "fsv_basisu_bridge.h"

#include <string>
#include <utility>
#include <vector>

namespace {
NSString *const kChannelName = @"flutter_scene_viewer/basisu";
NSString *const kMethodGetDecoderAvailability = @"getDecoderAvailability";
NSString *const kMethodDecodeGlb = @"decodeGlb";
NSString *const kBasisuExtension = @"KHR_texture_basisu";
NSString *const kInfoPlistKey = @"FlutterSceneViewerBasisuEnabled";
NSString *const kAndroidManifestKey = @"flutter_scene_viewer_basisu_enabled";

BOOL RequiresBasisu(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  NSArray *required = arguments[@"requiredExtensions"];
  if (![required isKindOfClass:[NSArray class]]) {
    return NO;
  }
  return [required containsObject:kBasisuExtension];
}

NSString *Source(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id source = arguments[@"source"];
  return [source isKindOfClass:[NSString class]] ? source : nil;
}

FlutterStandardTypedData *Bytes(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id bytes = arguments[@"bytes"];
  return [bytes isKindOfClass:[FlutterStandardTypedData class]] ? bytes : nil;
}

NSDictionary *Diagnostic(NSString *status, NSString *message, NSString *source) {
  NSMutableDictionary *details = [@{
    @"extension" : kBasisuExtension,
    @"decoder" : @"basisu",
    @"required" : @YES,
    @"status" : status,
    @"pluginPackage" : @"flutter_scene_viewer_basisu",
    @"configurationKey" : kInfoPlistKey,
    @"androidManifestKey" : kAndroidManifestKey,
  } mutableCopy];
  if (source != nil) {
    details[@"source"] = source;
  }
  return @{
    @"code" : @"unsupportedModelFeature",
    @"message" : message,
    @"details" : details,
  };
}

std::string StringFromNSString(NSString *value) {
  if (value == nil) {
    return std::string();
  }
  return std::string([value UTF8String] ?: "");
}

NSArray *BasisuImages(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id images = arguments[@"basisuImages"];
  return [images isKindOfClass:[NSArray class]] ? images : nil;
}

std::vector<FsvBasisuImageRequest> RequestsFromNSArray(NSArray *images) {
  std::vector<FsvBasisuImageRequest> requests;
  if (images == nil) {
    return requests;
  }
  requests.reserve([images count]);
  for (id rawImage in images) {
    if (![rawImage isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *image = rawImage;
    FsvBasisuImageRequest request;
    id textureIndex = image[@"textureIndex"];
    if ([textureIndex respondsToSelector:@selector(intValue)]) {
      request.texture_index = [textureIndex intValue];
    }
    id imageIndex = image[@"imageIndex"];
    if ([imageIndex respondsToSelector:@selector(intValue)]) {
      request.image_index = [imageIndex intValue];
    }
    id mimeType = image[@"mimeType"];
    if ([mimeType isKindOfClass:[NSString class]]) {
      request.mime_type = StringFromNSString(mimeType);
    }
    id bytes = image[@"bytes"];
    if ([bytes isKindOfClass:[FlutterStandardTypedData class]]) {
      NSData *data = [bytes data];
      request.bytes.assign(static_cast<const uint8_t *>([data bytes]),
                           static_cast<const uint8_t *>([data bytes]) +
                               [data length]);
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

NSDictionary *DiagnosticFromNative(const FsvBasisuDiagnostic &diagnostic,
                                   NSString *source) {
  NSMutableDictionary *details = [@{
    @"extension" : kBasisuExtension,
    @"decoder" : @"basisu",
    @"required" : @YES,
    @"status" : [NSString stringWithUTF8String:diagnostic.status.c_str()],
    @"pluginPackage" : @"flutter_scene_viewer_basisu",
    @"configurationKey" : kInfoPlistKey,
    @"androidManifestKey" : kAndroidManifestKey,
  } mutableCopy];
  if (diagnostic.texture_index >= 0) {
    details[@"textureIndex"] = @(diagnostic.texture_index);
  }
  if (diagnostic.image_index >= 0) {
    details[@"imageIndex"] = @(diagnostic.image_index);
  }
  if (source != nil) {
    details[@"source"] = source;
  }
  return @{
    @"code" : @"unsupportedModelFeature",
    @"message" : [NSString stringWithUTF8String:diagnostic.message.c_str()],
    @"details" : details,
  };
}

NSDictionary *ResponseFromNative(const FsvBasisuTranscodeResult &nativeResult,
                                 NSString *source) {
  NSMutableArray *decodedImages = [NSMutableArray array];
  for (const FsvBasisuDecodedImage &image : nativeResult.decoded_images) {
    NSData *data = [NSData dataWithBytes:image.bytes.data()
                                  length:image.bytes.size()];
    [decodedImages addObject:@{
      @"imageIndex" : @(image.image_index),
      @"mimeType" : [NSString stringWithUTF8String:image.mime_type.c_str()],
      @"bytes" : [FlutterStandardTypedData typedDataWithBytes:data],
    }];
  }

  NSMutableArray *diagnostics = [NSMutableArray array];
  for (const FsvBasisuDiagnostic &diagnostic : nativeResult.diagnostics) {
    [diagnostics addObject:DiagnosticFromNative(diagnostic, source)];
  }
  return @{
    @"decodedImages" : decodedImages,
    @"diagnostics" : diagnostics,
  };
}
}  // namespace

@implementation FlutterSceneViewerBasisuPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  FlutterSceneViewerBasisuPlugin *instance =
      [[FlutterSceneViewerBasisuPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if (![call.method isEqualToString:kMethodGetDecoderAvailability] &&
      ![call.method isEqualToString:kMethodDecodeGlb]) {
    result(FlutterMethodNotImplemented);
    return;
  }

  const BOOL requiresBasisu = RequiresBasisu(call.arguments);
  const BOOL enabled =
      [[[NSBundle mainBundle] objectForInfoDictionaryKey:kInfoPlistKey] boolValue];
  const BOOL linked = FsvBasisuTranscoderLinked();
  const BOOL imageTranscodeAvailable = FsvBasisuImageTranscodeAvailable();
  NSMutableArray *diagnostics = [NSMutableArray array];
  NSString *source = Source(call.arguments);

  if (requiresBasisu && !enabled) {
    [diagnostics addObject:Diagnostic(
                               @"disabled",
                               @"Native BasisU/KTX2 transcoder is installed but disabled.",
                               source)];
  } else if (requiresBasisu && !linked) {
    [diagnostics addObject:Diagnostic(
                               @"nativeLibraryUnavailable",
                               @"Native BasisU/KTX2 transcoder is enabled but the C++ transcoder is not linked.",
                               source)];
  } else if (requiresBasisu && !imageTranscodeAvailable) {
    [diagnostics addObject:Diagnostic(
                               @"decodeUnavailable",
                               @"Native BasisU/KTX2 transcoder is linked but image transcode is not implemented.",
                               source)];
  }

  if ([call.method isEqualToString:kMethodDecodeGlb] && !requiresBasisu) {
    FlutterStandardTypedData *bytes = Bytes(call.arguments);
    result(@{
      @"bytes" : bytes ?: [FlutterStandardTypedData typedDataWithBytes:[NSData data]],
      @"diagnostics" : diagnostics,
    });
    return;
  }

  if ([call.method isEqualToString:kMethodDecodeGlb] && requiresBasisu &&
      enabled && linked && imageTranscodeAvailable) {
    NSArray *images = BasisuImages(call.arguments);
    if (images == nil || [images count] == 0) {
      [diagnostics addObject:Diagnostic(
                                 @"decodeFailed",
                                 @"Native BasisU/KTX2 transcoder did not receive image payloads.",
                                 source)];
      result(@{
        @"diagnostics" : diagnostics,
      });
      return;
    }
    FsvBasisuTranscodeResult nativeResult =
        FsvBasisuTranscodeImages(RequestsFromNSArray(images));
    NSMutableArray *mergedDiagnostics = [diagnostics mutableCopy];
    NSDictionary *response = ResponseFromNative(nativeResult, source);
    [mergedDiagnostics addObjectsFromArray:response[@"diagnostics"]];
    result(@{
      @"decodedImages" : response[@"decodedImages"],
      @"diagnostics" : mergedDiagnostics,
    });
    return;
  }

  result(@{
    @"capabilities" : @{
      @"dracoMeshCompression" : @NO,
      @"meshoptCompression" : @NO,
      @"textureBasisu" : @(enabled && linked && imageTranscodeAvailable),
    },
    @"diagnostics" : diagnostics,
  });
}
@end
