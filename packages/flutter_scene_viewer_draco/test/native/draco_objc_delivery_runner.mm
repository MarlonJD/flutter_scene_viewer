#import <Foundation/Foundation.h>

enum class TypedDataBehavior { kSuccess, kReturnNil, kThrow };
TypedDataBehavior typed_data_behavior = TypedDataBehavior::kSuccess;

#include "../../ios/Classes/FlutterSceneViewerDracoPlugin.mm"

fsv_draco::FsvDecodeControl *copy_control = nullptr;
bool observed_native_charge_during_copy = false;

id FlutterMethodNotImplemented = nil;

@implementation FlutterMethodCall
@end

@implementation FlutterMethodChannel
+ (instancetype)methodChannelWithName:(NSString *)name
                      binaryMessenger:(id<FlutterBinaryMessenger>)messenger {
  (void)name;
  (void)messenger;
  return [[self alloc] init];
}
@end

@implementation FlutterStandardTypedData
+ (instancetype)typedDataWithBytes:(NSData *)data {
  (void)data;
  observed_native_charge_during_copy =
      copy_control != nullptr && copy_control->live_bytes() != 0;
  if (typed_data_behavior == TypedDataBehavior::kReturnNil) {
    return nil;
  }
  if (typed_data_behavior == TypedDataBehavior::kThrow) {
    [NSException raise:@"TypedDataFailure" format:@"injected"];
  }
  return [[self alloc] init];
}
- (NSData *)data {
  return nil;
}
@end

@interface ThrowingMutableArray : NSMutableArray
@end

@implementation ThrowingMutableArray
- (NSUInteger)count {
  return 0;
}
- (id)objectAtIndex:(NSUInteger)index {
  (void)index;
  return nil;
}
- (void)insertObject:(id)object atIndex:(NSUInteger)index {
  (void)object;
  (void)index;
}
- (void)removeObjectAtIndex:(NSUInteger)index {
  (void)index;
}
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)object {
  (void)index;
  (void)object;
}
- (void)addObjectsFromArray:(NSArray *)otherArray {
  (void)otherArray;
  [NSException raise:@"CollectionFailure" format:@"injected"];
}
@end

@implementation FlutterError
+ (instancetype)errorWithCode:(NSString *)code
                       message:(NSString *)message
                       details:(id)details {
  (void)message;
  (void)details;
  return (FlutterError *)@{ @"code" : code };
}
@end

namespace {

int failures = 0;

void CheckTerminal(NSString *label,
                   fsv_draco::FsvFinishDisposition disposition,
                   fsv_draco::FsvDecodeStopReason stopReason,
                   NSString *expectedCode) {
  __block int callbacks = 0;
  __block id delivered = nil;
  FlutterResult result = ^(id value) {
    ++callbacks;
    delivered = value;
  };
  DeliverDecodeCompletion(result, disposition, nil, stopReason);
  NSString *actualCode = [delivered isKindOfClass:[NSDictionary class]]
                             ? delivered[@"code"]
                             : nil;
  if (callbacks != 1 || ![actualCode isEqualToString:expectedCode]) {
    NSLog(@"%@ callbacks=%d code=%@", label, callbacks, actualCode);
    ++failures;
  }
}

void CheckResultLifetime() {
  fsv_draco::FsvDecodeRequestRegistry registry;
  std::shared_ptr<fsv_draco::FsvDecodeRequestRegistry::Entry> request =
      registry.Register("platform-copy", 4096);
  if (request == nullptr || request->control == nullptr) {
    ++failures;
    return;
  }
  NSDictionary *response = nil;
  {
    FsvDracoDecodeResult native_result(request->control.get());
    native_result.decoded_primitives.emplace_back(request->control.get());
    FsvDracoDecodedPrimitive &primitive =
        native_result.decoded_primitives.back();
    primitive.mesh_index = 3;
    primitive.primitive_index = 5;
    FsvDracoByteVector bytes{FsvDracoAllocator<uint8_t>(request->control.get())};
    bytes.assign(16, 0x4a);
    primitive.attributes.emplace(
        FsvDracoString("POSITION", FsvDracoAllocator<char>(request->control.get())),
        std::move(bytes));
    NSMutableArray *diagnostics = [NSMutableArray array];
    copy_control = request->control.get();
    observed_native_charge_during_copy = false;
    response = BuildManagedDecodeResponse(
        diagnostics, native_result, nil, request->control.get());
    if (response == nil || !observed_native_charge_during_copy ||
        request->control->live_bytes() == 0) {
      ++failures;
    }
    typed_data_behavior = TypedDataBehavior::kReturnNil;
    if (BuildManagedDecodeResponse(
            diagnostics, native_result, nil, request->control.get()) != nil) {
      ++failures;
    }
    typed_data_behavior = TypedDataBehavior::kSuccess;
  }
  copy_control = nullptr;
  if (request->control == nullptr || request->control->live_bytes() != 0 ||
      registry.Finish("platform-copy", request) !=
          fsv_draco::FsvFinishDisposition::kSuccess) {
    ++failures;
  }
}

}  // namespace

int main() {
  @autoreleasepool {
    for (const TypedDataBehavior behavior : {TypedDataBehavior::kReturnNil,
                                             TypedDataBehavior::kThrow}) {
      fsv_draco::FsvDecodeControl control(1024);
      FsvDracoByteVector payload{FsvDracoAllocator<uint8_t>(&control)};
      payload.assign(8, 0x4a);
      typed_data_behavior = behavior;
      FsvDracoPlatformCopyOutcome outcome;
      if (TypedDataFromBytes(payload, &control, &outcome) != nil ||
          outcome != FsvDracoPlatformCopyOutcome::kCopyFailed) {
        ++failures;
      }
      CheckTerminal(@"typed-data failure",
                    fsv_draco::FsvFinishDisposition::kSuccess,
                    fsv_draco::FsvDecodeStopReason::kNone,
                    @"platformSerializationFailed");
    }
    typed_data_behavior = TypedDataBehavior::kSuccess;

    CheckResultLifetime();

    fsv_draco::FsvDecodeControl response_control(1024);
    FsvDracoDecodeResult native_result(&response_control);
    NSDictionary *collection_exception = BuildManagedDecodeResponse(
        [[ThrowingMutableArray alloc] init], native_result, nil,
        &response_control);
    if (collection_exception != nil) {
      ++failures;
    }
    CheckTerminal(@"managed collection exception",
                  fsv_draco::FsvFinishDisposition::kSuccess,
                  fsv_draco::FsvDecodeStopReason::kNone,
                  @"platformSerializationFailed");

    NSDictionary *collection_failure = BuildManagedDecodeResponse(
        nil, native_result, nil, &response_control);
    if (collection_failure != nil) {
      ++failures;
    }
    CheckTerminal(@"managed collection allocation failure",
                  fsv_draco::FsvFinishDisposition::kSuccess,
                  fsv_draco::FsvDecodeStopReason::kNone,
                  @"platformSerializationFailed");

    CheckTerminal(@"caller cancellation",
                  fsv_draco::FsvFinishDisposition::kCancelled,
                  fsv_draco::FsvDecodeStopReason::kCallerCancelled,
                  @"cancelled");
    CheckTerminal(@"deadline wins later registry cancellation",
                  fsv_draco::FsvFinishDisposition::kCancelled,
                  fsv_draco::FsvDecodeStopReason::kDeadline, @"timeout");

    __block int callbacks = 0;
    __block id delivered = nil;
    NSDictionary *response = @{ @"decodedPrimitives" : @[] };
    DeliverDecodeCompletion(
        ^(id value) {
          ++callbacks;
          delivered = value;
        },
        fsv_draco::FsvFinishDisposition::kSuccess, response,
        fsv_draco::FsvDecodeStopReason::kNone);
    if (callbacks != 1 || delivered != response) {
      ++failures;
    }
  }
  if (failures != 0) {
    return 1;
  }
  NSLog(@"objc_delivery_cases=7 exactly_once");
  return 0;
}
