#import "FlutterSceneViewerDracoPlugin.h"

#import "fsv_draco_bridge.h"

namespace {
NSString *const kChannelName = @"flutter_scene_viewer/draco";
NSString *const kMethodGetDecoderAvailability = @"getDecoderAvailability";
NSString *const kMethodDecodeGlb = @"decodeGlb";
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

NSString *StringFromStd(const std::string &value) {
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

FsvDracoAccessorSchema AccessorSchema(id value) {
  FsvDracoAccessorSchema schema;
  if (![value isKindOfClass:[NSDictionary class]]) {
    return schema;
  }
  NSDictionary *dictionary = value;
  id accessorIndex = dictionary[@"accessorIndex"];
  id componentType = dictionary[@"componentType"];
  id type = dictionary[@"type"];
  id count = dictionary[@"count"];
  if ([accessorIndex respondsToSelector:@selector(intValue)]) {
    schema.accessor_index = [accessorIndex intValue];
  }
  if ([componentType respondsToSelector:@selector(intValue)]) {
    schema.component_type = [componentType intValue];
  }
  if ([type isKindOfClass:[NSString class]]) {
    schema.type = [type UTF8String];
  }
  if ([count respondsToSelector:@selector(intValue)]) {
    schema.count = [count intValue];
  }
  schema.normalized = [dictionary[@"normalized"] boolValue];
  return schema;
}

std::vector<uint8_t> BytesVector(id value) {
  if (![value isKindOfClass:[FlutterStandardTypedData class]]) {
    return {};
  }
  NSData *data = [value data];
  const auto *bytes = static_cast<const uint8_t *>(data.bytes);
  return std::vector<uint8_t>(bytes, bytes + data.length);
}

std::vector<FsvDracoPrimitiveRequest> DracoPrimitiveRequests(id arguments) {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    return {};
  }
  NSArray *rawPrimitives = arguments[@"dracoPrimitives"];
  if (![rawPrimitives isKindOfClass:[NSArray class]]) {
    return {};
  }
  std::vector<FsvDracoPrimitiveRequest> requests;
  for (id rawPrimitive in rawPrimitives) {
    if (![rawPrimitive isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *dictionary = rawPrimitive;
    FsvDracoPrimitiveRequest request;
    request.mesh_index = [dictionary[@"meshIndex"] intValue];
    request.primitive_index = [dictionary[@"primitiveIndex"] intValue];
    request.compressed_bytes = BytesVector(dictionary[@"compressedBytes"]);

    NSDictionary *attributes = dictionary[@"attributes"];
    if ([attributes isKindOfClass:[NSDictionary class]]) {
      for (id key in attributes) {
        if (![key isKindOfClass:[NSString class]]) {
          continue;
        }
        id value = attributes[key];
        if ([value respondsToSelector:@selector(intValue)]) {
          request.attributes[[key UTF8String]] = [value intValue];
        }
      }
    }

    NSDictionary *attributeAccessors = dictionary[@"attributeAccessors"];
    if ([attributeAccessors isKindOfClass:[NSDictionary class]]) {
      for (id key in attributeAccessors) {
        if (![key isKindOfClass:[NSString class]]) {
          continue;
        }
        request.attribute_accessors[[key UTF8String]] =
            AccessorSchema(attributeAccessors[key]);
      }
    }

    id indicesAccessor = dictionary[@"indicesAccessor"];
    if ([indicesAccessor isKindOfClass:[NSDictionary class]]) {
      request.has_indices_accessor = true;
      request.indices_accessor = AccessorSchema(indicesAccessor);
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

FlutterStandardTypedData *TypedDataFromBytes(
    const std::vector<uint8_t> &bytes) {
  NSData *data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
  return [FlutterStandardTypedData typedDataWithBytes:data];
}

NSArray *DecodedPrimitives(const FsvDracoDecodeResult &decodeResult) {
  NSMutableArray *decoded = [NSMutableArray array];
  for (const FsvDracoDecodedPrimitive &primitive :
       decodeResult.decoded_primitives) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    for (const auto &entry : primitive.attributes) {
      attributes[StringFromStd(entry.first)] = TypedDataFromBytes(entry.second);
    }
    NSMutableDictionary *dictionary = [@{
      @"meshIndex" : @(primitive.mesh_index),
      @"primitiveIndex" : @(primitive.primitive_index),
      @"attributes" : attributes,
    } mutableCopy];
    if (primitive.has_indices) {
      dictionary[@"indices"] = TypedDataFromBytes(primitive.indices);
    }
    [decoded addObject:dictionary];
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
    [diagnostics addObject:Diagnostic(StringFromStd(diagnostic.status),
                                      StringFromStd(diagnostic.message),
                                      source,
                                      details)];
  }
  return diagnostics;
}
}  // namespace

@implementation FlutterSceneViewerDracoPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  FlutterSceneViewerDracoPlugin *instance =
      [[FlutterSceneViewerDracoPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
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

  if ([call.method isEqualToString:kMethodDecodeGlb]) {
    if (!requiresDraco) {
      FlutterStandardTypedData *bytes = Bytes(call.arguments);
      result(@{
        @"bytes" : bytes ?: [FlutterStandardTypedData typedDataWithBytes:[NSData data]],
        @"diagnostics" : diagnostics,
      });
      return;
    }
    if (requiresDraco && enabled && linked && primitiveDecodeAvailable) {
      std::vector<FsvDracoPrimitiveRequest> requests =
          DracoPrimitiveRequests(call.arguments);
      if (requests.empty()) {
        [diagnostics addObject:Diagnostic(
                                   @"decodeFailed",
                                   @"Native Draco decoder did not receive Draco primitive payloads.",
                                   source)];
        result(@{
          @"diagnostics" : diagnostics,
        });
        return;
      }
      FsvDracoDecodeResult decodeResult = FsvDracoDecodePrimitives(requests);
      [diagnostics addObjectsFromArray:BridgeDiagnostics(decodeResult, source)];
      if (diagnostics.count > 0) {
        result(@{
          @"diagnostics" : diagnostics,
        });
        return;
      }
      result(@{
        @"decodedPrimitives" : DecodedPrimitives(decodeResult),
        @"diagnostics" : diagnostics,
      });
      return;
    }
    result(@{
      @"diagnostics" : diagnostics,
    });
    return;
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
@end
