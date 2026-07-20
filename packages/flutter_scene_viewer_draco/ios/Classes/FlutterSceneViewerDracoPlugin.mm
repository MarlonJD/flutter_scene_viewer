#import "FlutterSceneViewerDracoPlugin.h"

#import "fsv_draco_bridge.h"
#import "fsv_draco_platform_serialization.h"
#import "fsv_draco_request_registry.h"

#include <cstring>
#include <limits>
#include <memory>

namespace {
NSString *const kChannelName = @"flutter_scene_viewer/draco";
NSString *const kMethodGetDecoderAvailability = @"getDecoderAvailability";
NSString *const kMethodDecodeGlb = @"decodeGlb";
NSString *const kMethodCancelDecode = @"cancelDecode";
NSString *const kDracoExtension = @"KHR_draco_mesh_compression";
NSString *const kInfoPlistKey = @"FlutterSceneViewerDracoEnabled";
NSString *const kAndroidManifestKey = @"flutter_scene_viewer_draco_enabled";

BOOL RequiresDraco(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  NSArray *required = arguments[@"requiredExtensions"];
  if (![required isKindOfClass:[NSArray class]]) {
    return NO;
  }
  return [required containsObject:kDracoExtension];
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

template <typename String>
NSString *StringFromStd(const String &value) {
  return [NSString stringWithUTF8String:value.c_str()];
}

NSDictionary *Diagnostic(NSString *status,
                         NSString *message,
                         NSString *source,
                         NSDictionary *extraDetails = nil) {
  NSMutableDictionary *details = [@{
    @"extension" : kDracoExtension,
    @"decoder" : @"draco",
    @"required" : @YES,
    @"status" : status,
    @"pluginPackage" : @"flutter_scene_viewer_draco",
    @"configurationKey" : kInfoPlistKey,
    @"androidManifestKey" : kAndroidManifestKey,
  } mutableCopy];
  if (source != nil) {
    details[@"source"] = source;
  }
  if (extraDetails != nil) {
    [details addEntriesFromDictionary:extraDetails];
  }
  return @{
    @"code" : @"unsupportedModelFeature",
    @"message" : message,
    @"details" : details,
  };
}

FsvDracoBudgetNumber BudgetNumber(id value);

FsvDracoAccessorSchema AccessorSchema(
    id value,
    fsv_draco::FsvDecodeControl *control) {
  FsvDracoAccessorSchema schema(control);
  if (![value isKindOfClass:[NSDictionary class]]) {
    return schema;
  }
  NSDictionary *dictionary = value;
  id accessorIndex = dictionary[@"accessorIndex"];
  id type = dictionary[@"type"];
  id count = dictionary[@"count"];
  if ([accessorIndex isKindOfClass:[NSNumber class]] &&
      CFGetTypeID((__bridge CFTypeRef)accessorIndex) != CFBooleanGetTypeID() &&
      !CFNumberIsFloatType((__bridge CFNumberRef)accessorIndex)) {
    schema.accessor_index = [accessorIndex longLongValue];
  }
  schema.component_type = BudgetNumber(dictionary[@"componentType"]);
  if ([type isKindOfClass:[NSString class]]) {
    schema.type.assign([type UTF8String]);
  }
  if ([count isKindOfClass:[NSNumber class]] &&
      CFGetTypeID((__bridge CFTypeRef)count) != CFBooleanGetTypeID() &&
      !CFNumberIsFloatType((__bridge CFNumberRef)count)) {
    schema.count = [count longLongValue];
  }
  schema.normalized = [dictionary[@"normalized"] boolValue];
  return schema;
}

FsvDracoBudgetNumber BudgetNumber(id value) {
  if (value == nil) {
    return FsvDracoBudgetNumber();
  }
  if (![value isKindOfClass:[NSNumber class]] ||
      CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
      CFNumberIsFloatType((__bridge CFNumberRef)value)) {
    return FsvDracoBudgetNumber::Invalid();
  }
  return FsvDracoBudgetNumber::Integer([value longLongValue]);
}

FsvDracoDecodeBudgetMetadata DecodeBudget(id arguments) {
  FsvDracoDecodeBudgetMetadata budget;
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return budget;
  }
  id value = arguments[@"decodeBudget"];
  if (![value isKindOfClass:[NSDictionary class]]) {
    return budget;
  }
  NSDictionary *dictionary = value;
  budget.max_total_decoded_bytes =
      BudgetNumber(dictionary[@"maxTotalDecodedBytes"]);
  budget.max_accessors = BudgetNumber(dictionary[@"maxAccessors"]);
  budget.max_vertices = BudgetNumber(dictionary[@"maxVertices"]);
  budget.max_indices = BudgetNumber(dictionary[@"maxIndices"]);
  budget.max_native_output_bytes =
      BudgetNumber(dictionary[@"maxNativeOutputBytes"]);
  return budget;
}

FsvDracoDecodeBudgetState DecodeBudgetState(id arguments) {
  FsvDracoDecodeBudgetState state;
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return state;
  }
  id value = arguments[@"decodeBudgetState"];
  if (![value isKindOfClass:[NSDictionary class]]) {
    return state;
  }
  NSDictionary *dictionary = value;
  state.total_decoded_bytes = BudgetNumber(dictionary[@"totalDecodedBytes"]);
  state.accessors = BudgetNumber(dictionary[@"accessors"]);
  state.vertices = BudgetNumber(dictionary[@"vertices"]);
  state.indices = BudgetNumber(dictionary[@"indices"]);
  state.native_output_bytes = BudgetNumber(dictionary[@"nativeOutputBytes"]);
  return state;
}

FsvDracoByteVector BytesVector(
    id value,
    fsv_draco::FsvDecodeControl *control) {
  FsvDracoByteVector result{FsvDracoAllocator<uint8_t>(control)};
  if (![value isKindOfClass:[FlutterStandardTypedData class]]) {
    return result;
  }
  NSData *data = [value data];
  const auto *bytes = static_cast<const uint8_t *>(data.bytes);
  result.assign(bytes, bytes + data.length);
  return result;
}

FsvDracoPrimitiveRequests DracoPrimitiveRequests(
    id arguments,
    fsv_draco::FsvDecodeControl *control) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return requests;
  }
  NSArray *rawPrimitives = arguments[@"dracoPrimitives"];
  if (![rawPrimitives isKindOfClass:[NSArray class]]) {
    return requests;
  }
  for (id rawPrimitive in rawPrimitives) {
    if (![rawPrimitive isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *dictionary = rawPrimitive;
    FsvDracoPrimitiveRequest request(control);
    request.mesh_index = [dictionary[@"meshIndex"] intValue];
    request.primitive_index = [dictionary[@"primitiveIndex"] intValue];
    request.compressed_bytes =
        BytesVector(dictionary[@"compressedBytes"], control);
    id vertexAccessorIndex = dictionary[@"vertexAccessorIndex"];
    if ([vertexAccessorIndex isKindOfClass:[NSNumber class]] &&
        CFGetTypeID((__bridge CFTypeRef)vertexAccessorIndex) !=
            CFBooleanGetTypeID() &&
        !CFNumberIsFloatType((__bridge CFNumberRef)vertexAccessorIndex)) {
      request.vertex_accessor_index = [vertexAccessorIndex longLongValue];
    }

    NSDictionary *attributes = dictionary[@"attributes"];
    if ([attributes isKindOfClass:[NSDictionary class]]) {
      for (id key in attributes) {
        if (![key isKindOfClass:[NSString class]]) {
          continue;
        }
        id value = attributes[key];
        if ([value isKindOfClass:[NSNumber class]] &&
            CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
            !CFNumberIsFloatType((__bridge CFNumberRef)value)) {
          request.attributes.emplace(
              FsvDracoString([key UTF8String],
                             FsvDracoAllocator<char>(control)),
              [value longLongValue]);
        }
      }
    }

    NSDictionary *attributeAccessors = dictionary[@"attributeAccessors"];
    if ([attributeAccessors isKindOfClass:[NSDictionary class]]) {
      for (id key in attributeAccessors) {
        if (![key isKindOfClass:[NSString class]]) {
          continue;
        }
        request.attribute_accessors.emplace(
            FsvDracoString([key UTF8String],
                           FsvDracoAllocator<char>(control)),
            AccessorSchema(attributeAccessors[key], control));
      }
    }

    id indicesAccessor = dictionary[@"indicesAccessor"];
    if ([indicesAccessor isKindOfClass:[NSDictionary class]]) {
      request.has_indices_accessor = true;
      request.indices_accessor = AccessorSchema(indicesAccessor, control);
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

template <typename ByteAllocator>
FlutterStandardTypedData *TypedDataFromBytes(
    const std::vector<uint8_t, ByteAllocator> &bytes,
    fsv_draco::FsvDecodeControl *control,
    FsvDracoPlatformCopyOutcome *outcome) {
  ObjCByteCopyContext context;
  FsvDracoPlatformCopyCallbacks callbacks;
  callbacks.context = &context;
  callbacks.allocate = AllocateObjCBytes;
  callbacks.copy = CopyObjCBytes;
  callbacks.release = ReleaseObjCBytes;
  void *destination = nullptr;
  *outcome = FsvDracoCopyBytesToPlatform(
      bytes.data(), (uint64_t)bytes.size(),
      (uint64_t)std::numeric_limits<NSInteger>::max(), control, callbacks,
      &destination);
  return *outcome == FsvDracoPlatformCopyOutcome::kSuccess
             ? context.typedData
             : nil;
}

NSArray *DecodedPrimitives(const FsvDracoDecodeResult &decodeResult,
                           fsv_draco::FsvDecodeControl *control) {
  NSMutableArray *decoded = [NSMutableArray array];
  for (const FsvDracoDecodedPrimitive &primitive :
       decodeResult.decoded_primitives) {
    if (control != nullptr && control->IsCancelled()) {
      return nil;
    }
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (const auto &entry : primitive.attributes) {
      FsvDracoPlatformCopyOutcome outcome;
      FlutterStandardTypedData *bytes =
          TypedDataFromBytes(entry.second, control, &outcome);
      if (outcome != FsvDracoPlatformCopyOutcome::kSuccess || bytes == nil) {
        return nil;  // Atomic platform-copy failure.
      }
      attributes[StringFromStd(entry.first)] = bytes;
    }
    NSMutableDictionary *dictionary = [@{
      @"meshIndex" : @(primitive.mesh_index),
      @"primitiveIndex" : @(primitive.primitive_index),
      @"attributes" : attributes,
    } mutableCopy];
    if (primitive.has_indices) {
      FsvDracoPlatformCopyOutcome outcome;
      FlutterStandardTypedData *bytes =
          TypedDataFromBytes(primitive.indices, control, &outcome);
      if (outcome != FsvDracoPlatformCopyOutcome::kSuccess || bytes == nil) {
        return nil;  // Atomic platform-copy failure.
      }
      dictionary[@"indices"] = bytes;
    }
    [decoded addObject:dictionary];
  }
  if (control != nullptr && control->IsCancelled()) {
    return nil;
  }
  return decoded;
}

NSArray *BridgeDiagnostics(const FsvDracoDecodeResult &decodeResult,
                           NSString *source) {
  NSMutableArray *diagnostics = [NSMutableArray array];
  for (const FsvDracoDiagnostic &diagnostic : decodeResult.diagnostics) {
    NSMutableDictionary *details = [@{
      @"meshIndex" : @(diagnostic.mesh_index),
      @"primitiveIndex" : @(diagnostic.primitive_index),
    } mutableCopy];
    if (!diagnostic.attribute.empty()) {
      details[@"attribute"] = StringFromStd(diagnostic.attribute);
    }
    if (!diagnostic.stage.empty()) {
      details[@"stage"] = StringFromStd(diagnostic.stage);
    }
    if (!diagnostic.field.empty()) {
      details[@"field"] = StringFromStd(diagnostic.field);
      details[@"limitation"] = diagnostic.status == "budgetExceeded"
                                    ? @"decodeBudget"
                                    : @"dracoNativeBoundary";
    }
    if (diagnostic.has_limit) {
      details[@"limit"] = @(diagnostic.limit);
    }
    if (diagnostic.has_actual) {
      details[@"actual"] = @(diagnostic.actual);
    }
    [diagnostics addObject:Diagnostic(StringFromStd(diagnostic.status),
                                      StringFromStd(diagnostic.message),
                                      source,
                                      details)];
  }
  const bool budgetExceeded =
      decodeResult.terminal_outcome.kind ==
      FsvDracoTerminalOutcomeKind::kBudgetExceeded;
  if (budgetExceeded ||
      decodeResult.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kAllocationFailed) {
    NSDictionary *details = @{
      @"meshIndex" : @(decodeResult.terminal_outcome.mesh_index),
      @"primitiveIndex" : @(decodeResult.terminal_outcome.primitive_index),
      @"stage" : @"dracoWorkingAllocation",
      @"field" : @"nativeWorkingBytes",
      @"limitation" : budgetExceeded ? @"decodeBudget"
                                      : @"dracoNativeBoundary",
    };
    [diagnostics
        addObject:Diagnostic(
                      budgetExceeded ? @"budgetExceeded" : @"allocationFailed",
                      budgetExceeded
                          ? @"Native Draco decode exceeded maxNativeWorkingBytes."
                          : @"Native Draco decode allocation failed.",
                      source,
                      details)];
  }
  return diagnostics;
}

NSDictionary *BuildManagedDecodeResponse(
    NSMutableArray *diagnostics,
    const FsvDracoDecodeResult &decodeResult,
    NSString *source,
    fsv_draco::FsvDecodeControl *control) {
  @try {
    [diagnostics addObjectsFromArray:BridgeDiagnostics(decodeResult, source)];
    NSArray *decodedPrimitives = DecodedPrimitives(decodeResult, control);
    if (decodedPrimitives == nil) {
      return nil;  // Atomic platform-copy failure.
    }
    NSDictionary *response = @{
      @"decodedPrimitives" : decodedPrimitives,
      @"diagnostics" : diagnostics,
    };
    if (control != nullptr && control->IsCancelled()) {
      return nil;
    }
    return response;
  } @catch (NSException *exception) {
    (void)exception;
    return nil;  // Atomic managed response construction failure.
  }
}

void DeliverDecodeCompletion(
    FlutterResult result,
    fsv_draco::FsvFinishDisposition disposition,
    NSDictionary *response,
    fsv_draco::FsvDecodeStopReason stopReason) {
  if (disposition == fsv_draco::FsvFinishDisposition::kDetached) {
    return;
  }
  if (stopReason == fsv_draco::FsvDecodeStopReason::kDeadline) {
    result([FlutterError errorWithCode:@"timeout"
                               message:@"Native Draco decode timed out."
                               details:nil]);
    return;
  }
  if (stopReason == fsv_draco::FsvDecodeStopReason::kCallerCancelled ||
      disposition == fsv_draco::FsvFinishDisposition::kCancelled) {
    result([FlutterError errorWithCode:@"cancelled"
                               message:@"Native Draco decode was cancelled."
                               details:nil]);
    return;
  }
  if (response == nil) {
    result([FlutterError errorWithCode:@"platformSerializationFailed"
                               message:@"Native Draco response serialization failed."
                               details:nil]);
    return;
  }
  result(response);
}
}  // namespace

@interface FlutterSceneViewerDracoPlugin () {
  dispatch_queue_t _decodeQueue;
  std::unique_ptr<fsv_draco::FsvDecodeRequestRegistry> _requestRegistry;
}
@end

@implementation FlutterSceneViewerDracoPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  FlutterSceneViewerDracoPlugin *instance =
      [[FlutterSceneViewerDracoPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _decodeQueue = dispatch_queue_create(
        "com.marlonjd.flutter_scene_viewer_draco.decode",
        DISPATCH_QUEUE_SERIAL);
    _requestRegistry =
        std::make_unique<fsv_draco::FsvDecodeRequestRegistry>();
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

  const BOOL requiresDraco = RequiresDraco(call.arguments);
  const BOOL enabled =
      [[[NSBundle mainBundle] objectForInfoDictionaryKey:kInfoPlistKey] boolValue];
  const BOOL linked = FsvDracoDecoderLinked();
  const BOOL primitiveDecodeAvailable = FsvDracoPrimitiveDecodeAvailable();
  NSMutableArray *diagnostics = [NSMutableArray array];
  NSString *source = Source(call.arguments);

  if (requiresDraco && !enabled) {
    [diagnostics addObject:Diagnostic(
                               @"disabled",
                               @"Native Draco decoder is installed but disabled.",
                               source)];
  } else if (requiresDraco && !linked) {
    [diagnostics addObject:Diagnostic(
                               @"nativeLibraryUnavailable",
                               @"Native Draco decoder is enabled but the C++ decoder is not linked.",
                               source)];
  } else if (requiresDraco && !primitiveDecodeAvailable) {
    [diagnostics addObject:Diagnostic(
                               @"decodeUnavailable",
                               @"Native Draco decoder is linked but primitive decode is not implemented.",
                               source)];
  }

  result(@{
    @"capabilities" : @{
      @"dracoMeshCompression" : @(enabled && linked && primitiveDecodeAvailable),
      @"meshoptCompression" : @NO,
      @"textureBasisu" : @NO,
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
                          control:(fsv_draco::FsvDecodeControl *)control {
  const BOOL requiresDraco = RequiresDraco(call.arguments);
  const BOOL enabled =
      [[[NSBundle mainBundle] objectForInfoDictionaryKey:kInfoPlistKey] boolValue];
  const BOOL linked = FsvDracoDecoderLinked();
  const BOOL available = FsvDracoPrimitiveDecodeAvailable();
  NSMutableArray *diagnostics = [NSMutableArray array];
  NSString *source = Source(call.arguments);
  if (!requiresDraco) {
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
                                 @"Native Draco decoder is installed but disabled.",
                                 source)];
    } else if (!linked) {
      [diagnostics addObject:Diagnostic(
                                 @"nativeLibraryUnavailable",
                                 @"Native Draco decoder is enabled but the C++ decoder is not linked.",
                                 source)];
    } else {
      [diagnostics addObject:Diagnostic(
                                 @"decodeUnavailable",
                                 @"Native Draco decoder is linked but primitive decode is not implemented.",
                                 source)];
    }
    return @{ @"diagnostics" : diagnostics };
  }
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
  FsvDracoDecodeResult decodeResult(control);
  try {
    requests = DracoPrimitiveRequests(call.arguments, control);
  } catch (const fsv_draco::FsvDecodeStopped &) {
    FsvDracoRecordTerminalOutcome(&decodeResult, control);
  } catch (const fsv_draco::FsvDecodeBudgetExceeded &) {
    FsvDracoRecordTerminalOutcome(&decodeResult, control);
  } catch (const std::bad_alloc &) {
    FsvDracoRecordTerminalOutcome(&decodeResult, control);
  }
  if (decodeResult.terminal_outcome.kind !=
      FsvDracoTerminalOutcomeKind::kNone) {
    if (control->IsCancelled()) {
      return nil;
    }
    @try {
      [diagnostics addObjectsFromArray:BridgeDiagnostics(decodeResult, source)];
      return @{ @"diagnostics" : diagnostics };
    } @catch (NSException *exception) {
      (void)exception;
      return nil;  // Atomic managed response construction failure.
    }
  }
  if (requests.empty()) {
    [diagnostics addObject:Diagnostic(
                               @"decodeFailed",
                               @"Native Draco decoder did not receive Draco primitive payloads.",
                               source)];
    return @{ @"diagnostics" : diagnostics };
  }
  decodeResult = FsvDracoDecodePrimitives(
      requests, DecodeBudget(call.arguments), DecodeBudgetState(call.arguments),
      nullptr, control);
  if (control->IsCancelled()) {
    return nil;
  }
  return BuildManagedDecodeResponse(diagnostics, decodeResult, source, control);
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
  std::string requestKey([requestId UTF8String]);
  auto request = _requestRegistry->Register(
      requestKey, [self workingByteLimit:call.arguments]);
  if (request == nullptr) {
    result([FlutterError errorWithCode:@"duplicateRequest"
                               message:@"requestId is already active."
                               details:nil]);
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
                                : fsv_draco::FsvDecodeStopReason::kNone;
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
                          ? fsv_draco::FsvCancelStatus::kUnknownRequest
                          : _requestRegistry->Cancel([requestId UTF8String]);
  NSString *status = cancelStatus == fsv_draco::FsvCancelStatus::kCancelled
                         ? @"cancelled"
                         : cancelStatus ==
                                   fsv_draco::FsvCancelStatus::kAlreadyFinished
                               ? @"alreadyFinished"
                               : @"unknownRequest";
  result(@{ @"status" : status });
}
@end
