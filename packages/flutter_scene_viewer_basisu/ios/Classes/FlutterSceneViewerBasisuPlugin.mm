#import "FlutterSceneViewerBasisuPlugin.h"

#import "fsv_basisu_bridge.h"
#import "fsv_basisu_platform_serialization.h"
#import "fsv_basisu_request_registry.h"

#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <utility>

namespace {
NSString *const kChannelName = @"flutter_scene_viewer/basisu";
NSString *const kMethodGetDecoderAvailability = @"getDecoderAvailability";
NSString *const kMethodDecodeGlb = @"decodeGlb";
NSString *const kMethodCancelDecode = @"cancelDecode";
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

NSDictionary *DictionaryArgument(id arguments, NSString *key) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = arguments[key];
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

FsvBasisuBudgetNumber BudgetNumber(NSDictionary *values, NSString *key) {
  if (values == nil) {
    return FsvBasisuBudgetNumber();
  }
  id value = values[key];
  if (value == nil) {
    return FsvBasisuBudgetNumber();
  }
  if (![value isKindOfClass:[NSNumber class]] ||
      CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
      CFNumberIsFloatType((__bridge CFNumberRef)value)) {
    return FsvBasisuBudgetNumber::Invalid();
  }
  return FsvBasisuBudgetNumber::Integer([value longLongValue]);
}

FsvBasisuDecodeBudgetMetadata DecodeBudget(id arguments) {
  NSDictionary *values = DictionaryArgument(arguments, @"decodeBudget");
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes =
      BudgetNumber(values, @"maxTotalDecodedBytes");
  budget.max_texture_pixels = BudgetNumber(values, @"maxTexturePixels");
  budget.max_native_output_bytes =
      BudgetNumber(values, @"maxNativeOutputBytes");
  budget.max_native_working_bytes =
      BudgetNumber(values, @"maxNativeWorkingBytes");
  return budget;
}

FsvBasisuDecodeBudgetState DecodeBudgetState(id arguments) {
  NSDictionary *values = DictionaryArgument(arguments, @"decodeBudgetState");
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = BudgetNumber(values, @"totalDecodedBytes");
  state.texture_pixels = BudgetNumber(values, @"texturePixels");
  state.native_output_bytes = BudgetNumber(values, @"nativeOutputBytes");
  return state;
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

NSArray *BasisuImages(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id images = arguments[@"basisuImages"];
  return [images isKindOfClass:[NSArray class]] ? images : nil;
}

FsvBasisuImageRequests RequestsFromNSArray(
    NSArray *images,
    fsv_basisu::FsvDecodeControl *control) {
  FsvBasisuImageRequests requests{FsvBasisuAllocator<FsvBasisuImageRequest>(
      control)};
  if (images == nil) {
    return requests;
  }
  requests.reserve([images count]);
  for (id rawImage in images) {
    FsvBasisuImageRequest request(control);
    if (![rawImage isKindOfClass:[NSDictionary class]]) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages";
      requests.push_back(std::move(request));
      continue;
    }
    NSDictionary *image = rawImage;
    id textureIndex = image[@"textureIndex"];
    if ([textureIndex respondsToSelector:@selector(intValue)]) {
      request.texture_index = [textureIndex intValue];
    }
    id imageIndex = image[@"imageIndex"];
    if ([imageIndex respondsToSelector:@selector(intValue)]) {
      request.image_index = [imageIndex intValue];
    }
    id usageRole = image[@"usageRole"];
    if (![usageRole isKindOfClass:[NSString class]] ||
        !FsvBasisuUsageRoleFromString([usageRole UTF8String] ?: "",
                                      &request.usage_role)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.usageRole";
    }
    id channelLayout = image[@"channelLayout"];
    if (![channelLayout isKindOfClass:[NSString class]] ||
        !FsvBasisuChannelLayoutFromString([channelLayout UTF8String] ?: "",
                                          &request.channel_layout)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.channelLayout";
    }
    id mimeType = image[@"mimeType"];
    if ([mimeType isKindOfClass:[NSString class]]) {
      request.mime_type.assign([mimeType UTF8String] ?: "");
    }
    id bytes = image[@"bytes"];
    if ([bytes isKindOfClass:[FlutterStandardTypedData class]]) {
      NSData *data = [bytes data];
      request.bytes.assign(static_cast<const uint8_t *>([data bytes]),
                           static_cast<const uint8_t *>([data bytes]) +
                               [data length]);
    } else {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.bytes";
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

struct ObjCByteCopyContext {
  __strong NSMutableData *data = nil;
  __strong FlutterStandardTypedData *typedData = nil;
};

bool AllocateObjCBytes(void *rawContext,
                       uint64_t bytes,
                       void **destination) noexcept {
  auto *context = static_cast<ObjCByteCopyContext *>(rawContext);
  @try {
    context->data = [NSMutableData dataWithLength:(NSUInteger)bytes];
  } @catch (NSException *exception) {
    (void)exception;
    context->data = nil;
  }
  if (context->data == nil) {
    return false;
  }
  *destination = (__bridge void *)context->data;
  return true;
}

bool CopyObjCBytes(void *rawContext,
                   void *destination,
                   const uint8_t *source,
                   uint64_t bytes) noexcept {
  auto *context = static_cast<ObjCByteCopyContext *>(rawContext);
  if ((__bridge void *)context->data != destination) {
    return false;
  }
  @try {
    if (bytes != 0) {
      std::memcpy(context->data.mutableBytes, source, (size_t)bytes);
    }
    context->typedData =
        [FlutterStandardTypedData typedDataWithBytes:context->data];
  } @catch (NSException *exception) {
    (void)exception;
    context->typedData = nil;
  }
  return context->typedData != nil;
}

void ReleaseObjCBytes(void *rawContext, void *) noexcept {
  auto *context = static_cast<ObjCByteCopyContext *>(rawContext);
  context->typedData = nil;
  context->data = nil;
}

FlutterStandardTypedData *TypedDataFromBytes(
    const FsvBasisuByteVector &bytes,
    fsv_basisu::FsvDecodeControl *control,
    FsvBasisuPlatformCopyOutcome *outcome) {
  ObjCByteCopyContext context;
  FsvBasisuPlatformCopyCallbacks callbacks;
  callbacks.context = &context;
  callbacks.allocate = AllocateObjCBytes;
  callbacks.copy = CopyObjCBytes;
  callbacks.release = ReleaseObjCBytes;
  void *destination = nullptr;
  *outcome = FsvBasisuCopyBytesToPlatform(
      bytes.data(), (uint64_t)bytes.size(),
      (uint64_t)std::numeric_limits<NSInteger>::max(), control, callbacks,
      &destination);
  return *outcome == FsvBasisuPlatformCopyOutcome::kSuccess
             ? context.typedData
             : nil;
}

NSDictionary *DiagnosticFromNative(const FsvBasisuDiagnostic &diagnostic,
                                   NSString *source) {
  NSMutableDictionary *details = [@{
    @"extension" : kBasisuExtension,
    @"decoder" : @"basisu",
    @"required" : @YES,
    @"status" : [NSString stringWithUTF8String:diagnostic.status.c_str()],
    @"stage" : [NSString stringWithUTF8String:diagnostic.stage.c_str()],
    @"field" : [NSString stringWithUTF8String:diagnostic.field.c_str()],
    @"limitation" : diagnostic.status == "budgetExceeded"
        ? @"decodeBudget"
        : @"decodedPayloadSchema",
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
  if (diagnostic.has_limit) {
    details[@"limit"] = @(diagnostic.limit);
  }
  if (diagnostic.has_actual) {
    details[@"actual"] = @(diagnostic.actual);
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

NSArray *BridgeDiagnostics(const FsvBasisuTranscodeResult &nativeResult,
                           NSString *source) {
  NSMutableArray *diagnostics = [NSMutableArray array];
  for (const FsvBasisuDiagnostic &diagnostic : nativeResult.diagnostics) {
    [diagnostics addObject:DiagnosticFromNative(diagnostic, source)];
  }
  if (nativeResult.terminal_outcome ==
          FsvBasisuTerminalOutcomeKind::kBudgetExceeded ||
      nativeResult.terminal_outcome ==
          FsvBasisuTerminalOutcomeKind::kAllocationFailed) {
    const BOOL budgetExceeded =
        nativeResult.terminal_outcome ==
        FsvBasisuTerminalOutcomeKind::kBudgetExceeded;
    [diagnostics addObject:Diagnostic(
                               budgetExceeded ? @"budgetExceeded"
                                              : @"allocationFailed",
                               budgetExceeded
                                   ? @"Native BasisU decode exceeded maxNativeWorkingBytes."
                                   : @"Native BasisU decode allocation failed.",
                               source)];
  }
  return diagnostics;
}

NSDictionary *BuildManagedDecodeResponse(
    NSMutableArray *diagnostics,
    const FsvBasisuTranscodeResult &nativeResult,
    NSString *source,
    fsv_basisu::FsvDecodeControl *control) {
  @try {
    NSMutableArray *decodedImages = [NSMutableArray array];
    for (const FsvBasisuDecodedImage &image : nativeResult.decoded_images) {
      NSMutableArray *levels = [NSMutableArray array];
      for (const FsvBasisuDecodedMipLevel &level : image.levels) {
        FsvBasisuPlatformCopyOutcome outcome;
        FlutterStandardTypedData *rgba =
            TypedDataFromBytes(level.rgba_bytes, control, &outcome);
        if (outcome != FsvBasisuPlatformCopyOutcome::kSuccess || rgba == nil) {
          return nil;
        }
        [levels addObject:@{
          @"level" : @(level.level),
          @"width" : @(level.width),
          @"height" : @(level.height),
          @"rgbaBytes" : rgba,
        }];
      }
      [decodedImages addObject:@{
        @"imageIndex" : @(image.image_index),
        @"contentRole" :
            [NSString stringWithUTF8String:image.content_role.c_str()],
        @"levels" : levels,
      }];
    }
    [diagnostics addObjectsFromArray:BridgeDiagnostics(nativeResult, source)];
    if (control != nullptr && control->IsCancelled()) {
      return nil;
    }
    return @{
      @"decodedImages" : decodedImages,
      @"diagnostics" : diagnostics,
    };
  } @catch (NSException *exception) {
    (void)exception;
    return nil;
  }
}

void DeliverDecodeCompletion(
    FlutterResult result,
    fsv_basisu::FsvFinishDisposition disposition,
    NSDictionary *response,
    fsv_basisu::FsvDecodeStopReason stopReason) {
  if (disposition == fsv_basisu::FsvFinishDisposition::kDetached) {
    return;
  }
  if (stopReason == fsv_basisu::FsvDecodeStopReason::kDeadline) {
    result([FlutterError errorWithCode:@"timeout"
                               message:@"Native BasisU decode timed out."
                               details:nil]);
    return;
  }
  if (stopReason == fsv_basisu::FsvDecodeStopReason::kCallerCancelled ||
      disposition == fsv_basisu::FsvFinishDisposition::kCancelled) {
    result([FlutterError errorWithCode:@"cancelled"
                               message:@"Native BasisU decode was cancelled."
                               details:nil]);
    return;
  }
  if (response == nil) {
    result([FlutterError errorWithCode:@"platformSerializationFailed"
                               message:@"Native BasisU response serialization failed."
                               details:nil]);
    return;
  }
  result(response);
}

void DeliverRegistrationFailure(
    FlutterResult result,
    fsv_basisu::FsvRegisterFailure failure) {
  const BOOL controlCreationFailed =
      failure == fsv_basisu::FsvRegisterFailure::kControlCreationFailed;
  result([FlutterError
      errorWithCode:controlCreationFailed ? @"nativeControlUnavailable"
                                             : @"duplicateRequest"
             message:controlCreationFailed
                         ? @"Native BasisU decode control allocation failed."
                         : @"requestId is already active."
                             details:nil]);
}
}  // namespace

@interface FlutterSceneViewerBasisuPlugin () {
  dispatch_queue_t _decodeQueue;
  std::unique_ptr<fsv_basisu::FsvDecodeRequestRegistry> _requestRegistry;
}
@end

@implementation FlutterSceneViewerBasisuPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  FlutterSceneViewerBasisuPlugin *instance =
      [[FlutterSceneViewerBasisuPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _decodeQueue = dispatch_queue_create(
        "com.marlonjd.flutter_scene_viewer_basisu.decode",
        DISPATCH_QUEUE_SERIAL);
    _requestRegistry =
        std::make_unique<fsv_basisu::FsvDecodeRequestRegistry>();
  }
  return self;
}

- (void)detachFromEngineForRegistrar:
    (NSObject<FlutterPluginRegistrar> *)registrar {
  _requestRegistry->BeginDetach();
  dispatch_sync(_decodeQueue, ^{});
  _requestRegistry->DrainAfterWorkers();
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:kMethodCancelDecode]) {
    [self cancelDecode:call result:result];
    return;
  }
  if ([call.method isEqualToString:kMethodDecodeGlb]) {
    [self startDecode:call result:result];
    return;
  }
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

  result(@{
    @"capabilities" : @{
      @"dracoMeshCompression" : @NO,
      @"meshoptCompression" : @NO,
      @"textureBasisu" : @(enabled && linked && imageTranscodeAvailable),
    },
    @"diagnostics" : diagnostics,
  });
}

- (uint64_t)workingByteLimit:(id)arguments {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return UINT64_MAX;
  }
  id budget = arguments[@"decodeBudget"];
  id value = [budget isKindOfClass:[NSDictionary class]]
                 ? budget[@"maxNativeWorkingBytes"]
                 : nil;
  return [value isKindOfClass:[NSNumber class]] ? [value unsignedLongLongValue]
                                                 : UINT64_MAX;
}

- (NSDictionary *)decodeResponse:(FlutterMethodCall *)call
                          control:(fsv_basisu::FsvDecodeControl *)control {
  const BOOL requiresBasisu = RequiresBasisu(call.arguments);
  const BOOL enabled =
      [[[NSBundle mainBundle] objectForInfoDictionaryKey:kInfoPlistKey] boolValue];
  const BOOL linked = FsvBasisuTranscoderLinked();
  const BOOL available = FsvBasisuImageTranscodeAvailable();
  NSMutableArray *diagnostics = [NSMutableArray array];
  NSString *source = Source(call.arguments);
  if (!requiresBasisu) {
    FlutterStandardTypedData *bytes = Bytes(call.arguments);
    return @{
      @"bytes" : bytes ?: [FlutterStandardTypedData typedDataWithBytes:[NSData data]],
      @"diagnostics" : diagnostics,
    };
  }
  if (!enabled || !linked || !available) {
    if (!enabled) {
      [diagnostics addObject:Diagnostic(
                                 @"disabled",
                                 @"Native BasisU/KTX2 transcoder is installed but disabled.",
                                 source)];
    } else if (!linked) {
      [diagnostics addObject:Diagnostic(
                                 @"nativeLibraryUnavailable",
                                 @"Native BasisU/KTX2 transcoder is enabled but the C++ transcoder is not linked.",
                                 source)];
    } else {
      [diagnostics addObject:Diagnostic(
                                 @"decodeUnavailable",
                                 @"Native BasisU/KTX2 transcoder is linked but image transcode is not implemented.",
                                 source)];
    }
    return @{ @"diagnostics" : diagnostics };
  }
  NSArray *images = BasisuImages(call.arguments);
  if (images == nil || images.count == 0) {
    [diagnostics addObject:Diagnostic(
                               @"decodeFailed",
                               @"Native BasisU/KTX2 transcoder did not receive image payloads.",
                               source)];
    return @{ @"diagnostics" : diagnostics };
  }
  FsvBasisuImageRequests requests{
      FsvBasisuAllocator<FsvBasisuImageRequest>(control)};
  FsvBasisuTranscodeResult nativeResult(control);
  try {
    requests = RequestsFromNSArray(images, control);
    nativeResult = FsvBasisuTranscodeImages(
        requests, DecodeBudget(call.arguments),
        DecodeBudgetState(call.arguments), control);
  } catch (const std::bad_alloc &) {
    FsvBasisuRecordTerminalOutcome(&nativeResult, control);
  }
  if (control->IsCancelled()) {
    return nil;
  }
  return BuildManagedDecodeResponse(diagnostics, nativeResult, source,
                                    control);
}

- (void)startDecode:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *requestId = [call.arguments isKindOfClass:[NSDictionary class]]
                            ? call.arguments[@"requestId"]
                            : nil;
  if (![requestId isKindOfClass:[NSString class]] || requestId.length == 0) {
    result([FlutterError errorWithCode:@"invalidRequest"
                               message:@"decodeGlb requires a unique requestId."
                               details:nil]);
    return;
  }
  std::string requestKey;
  std::shared_ptr<fsv_basisu::FsvDecodeRequestRegistry::Entry> request;
  fsv_basisu::FsvRegisterFailure registerFailure =
      fsv_basisu::FsvRegisterFailure::kNone;
  try {
    requestKey.assign([requestId UTF8String] ?: "");
    request = _requestRegistry->Register(
        requestKey, [self workingByteLimit:call.arguments], &registerFailure);
  } catch (const std::bad_alloc &) {
    registerFailure =
        fsv_basisu::FsvRegisterFailure::kControlCreationFailed;
  }
  if (request == nullptr) {
    DeliverRegistrationFailure(result, registerFailure);
    return;
  }
  dispatch_async(_decodeQueue, ^{
    NSDictionary *response = _requestRegistry->ShouldStart(request)
                                 ? [self decodeResponse:call
                                               control:request->control.get()]
                                 : nil;
    if (request->control != nullptr && request->control->IsCancelled()) {
      response = nil;
    }
    const auto stopReason = request->control != nullptr
                                ? request->control->stop_reason()
                                : fsv_basisu::FsvDecodeStopReason::kNone;
    const auto disposition = _requestRegistry->Finish(requestKey, request);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (_requestRegistry->ClaimDelivery(request)) {
        DeliverDecodeCompletion(result, disposition, response, stopReason);
      }
    });
  });
}

- (void)cancelDecode:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSString *requestId = [call.arguments isKindOfClass:[NSDictionary class]]
                            ? call.arguments[@"requestId"]
                            : nil;
  auto cancelStatus = requestId == nil
                          ? fsv_basisu::FsvCancelStatus::kUnknownRequest
                          : _requestRegistry->Cancel([requestId UTF8String]);
  NSString *status = cancelStatus == fsv_basisu::FsvCancelStatus::kCancelled
                         ? @"cancelled"
                         : cancelStatus ==
                                   fsv_basisu::FsvCancelStatus::kAlreadyFinished
                               ? @"alreadyFinished"
                               : @"unknownRequest";
  result(@{ @"status" : status });
}
@end
