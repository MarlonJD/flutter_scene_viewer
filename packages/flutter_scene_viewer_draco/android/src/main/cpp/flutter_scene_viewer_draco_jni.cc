#include <jni.h>

#include "fsv_draco_bridge.h"

namespace {
constexpr const char* kDracoExtension = "KHR_draco_mesh_compression";
constexpr const char* kInfoPlistKey = "FlutterSceneViewerDracoEnabled";
constexpr const char* kAndroidManifestKey =
    "flutter_scene_viewer_draco_enabled";

jclass FindClass(JNIEnv* env, const char* name) {
  return env->FindClass(name);
}

jobject NewString(JNIEnv* env, const std::string& value) {
  return env->NewStringUTF(value.c_str());
}

jobject NewString(JNIEnv* env, const char* value) {
  return env->NewStringUTF(value);
}

jobject NewInteger(JNIEnv* env, int value) {
  jclass integer_class = FindClass(env, "java/lang/Integer");
  jmethodID constructor =
      env->GetMethodID(integer_class, "<init>", "(I)V");
  return env->NewObject(integer_class, constructor, value);
}

jobject NewBoolean(JNIEnv* env, bool value) {
  jclass boolean_class = FindClass(env, "java/lang/Boolean");
  jmethodID constructor =
      env->GetMethodID(boolean_class, "<init>", "(Z)V");
  return env->NewObject(boolean_class, constructor, value ? JNI_TRUE
                                                         : JNI_FALSE);
}

jobject NewHashMap(JNIEnv* env) {
  jclass map_class = FindClass(env, "java/util/HashMap");
  jmethodID constructor = env->GetMethodID(map_class, "<init>", "()V");
  return env->NewObject(map_class, constructor);
}

jobject NewArrayList(JNIEnv* env) {
  jclass list_class = FindClass(env, "java/util/ArrayList");
  jmethodID constructor = env->GetMethodID(list_class, "<init>", "()V");
  return env->NewObject(list_class, constructor);
}

void MapPutObject(JNIEnv* env, jobject map, const char* key, jobject value) {
  jclass map_class = FindClass(env, "java/util/Map");
  jmethodID put =
      env->GetMethodID(map_class, "put",
                       "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
  env->CallObjectMethod(map, put, NewString(env, key), value);
}

void MapPutString(JNIEnv* env, jobject map, const char* key, const char* value) {
  MapPutObject(env, map, key, NewString(env, value));
}

void MapPutString(JNIEnv* env,
                  jobject map,
                  const char* key,
                  const std::string& value) {
  MapPutObject(env, map, key, NewString(env, value));
}

void MapPutInt(JNIEnv* env, jobject map, const char* key, int value) {
  MapPutObject(env, map, key, NewInteger(env, value));
}

void MapPutBool(JNIEnv* env, jobject map, const char* key, bool value) {
  MapPutObject(env, map, key, NewBoolean(env, value));
}

jobject MapGet(JNIEnv* env, jobject map, const char* key) {
  if (map == nullptr) {
    return nullptr;
  }
  jclass map_class = FindClass(env, "java/util/Map");
  jmethodID get =
      env->GetMethodID(map_class, "get",
                       "(Ljava/lang/Object;)Ljava/lang/Object;");
  return env->CallObjectMethod(map, get, NewString(env, key));
}

void ListAdd(JNIEnv* env, jobject list, jobject value) {
  jclass list_class = FindClass(env, "java/util/List");
  jmethodID add =
      env->GetMethodID(list_class, "add", "(Ljava/lang/Object;)Z");
  env->CallBooleanMethod(list, add, value);
}

int ListSize(JNIEnv* env, jobject list) {
  if (list == nullptr) {
    return 0;
  }
  jclass list_class = FindClass(env, "java/util/List");
  jmethodID size = env->GetMethodID(list_class, "size", "()I");
  return env->CallIntMethod(list, size);
}

jobject ListGet(JNIEnv* env, jobject list, int index) {
  jclass list_class = FindClass(env, "java/util/List");
  jmethodID get = env->GetMethodID(list_class, "get", "(I)Ljava/lang/Object;");
  return env->CallObjectMethod(list, get, index);
}

bool IsInstance(JNIEnv* env, jobject value, const char* class_name) {
  if (value == nullptr) {
    return false;
  }
  return env->IsInstanceOf(value, FindClass(env, class_name)) == JNI_TRUE;
}

int IntValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return 0;
  }
  jclass number_class = FindClass(env, "java/lang/Number");
  jmethodID int_value = env->GetMethodID(number_class, "intValue", "()I");
  return env->CallIntMethod(value, int_value);
}

bool BoolValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return false;
  }
  jclass boolean_class = FindClass(env, "java/lang/Boolean");
  jmethodID bool_value =
      env->GetMethodID(boolean_class, "booleanValue", "()Z");
  return env->CallBooleanMethod(value, bool_value) == JNI_TRUE;
}

std::string StringValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return {};
  }
  const char* chars = env->GetStringUTFChars(static_cast<jstring>(value),
                                             nullptr);
  if (chars == nullptr) {
    return {};
  }
  std::string result(chars);
  env->ReleaseStringUTFChars(static_cast<jstring>(value), chars);
  return result;
}

std::vector<uint8_t> ByteVector(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return {};
  }
  auto array = static_cast<jbyteArray>(value);
  const jsize length = env->GetArrayLength(array);
  std::vector<uint8_t> bytes(length);
  if (length > 0) {
    env->GetByteArrayRegion(array, 0, length,
                            reinterpret_cast<jbyte*>(bytes.data()));
  }
  return bytes;
}

jbyteArray ByteArray(JNIEnv* env, const std::vector<uint8_t>& bytes) {
  jbyteArray array = env->NewByteArray(static_cast<jsize>(bytes.size()));
  if (!bytes.empty()) {
    env->SetByteArrayRegion(
        array, 0, static_cast<jsize>(bytes.size()),
        reinterpret_cast<const jbyte*>(bytes.data()));
  }
  return array;
}

FsvDracoAccessorSchema AccessorSchema(JNIEnv* env, jobject value) {
  FsvDracoAccessorSchema schema;
  if (!IsInstance(env, value, "java/util/Map")) {
    return schema;
  }
  schema.accessor_index = IntValue(env, MapGet(env, value, "accessorIndex"));
  schema.component_type = IntValue(env, MapGet(env, value, "componentType"));
  schema.type = StringValue(env, MapGet(env, value, "type"));
  schema.count = IntValue(env, MapGet(env, value, "count"));
  schema.normalized = BoolValue(env, MapGet(env, value, "normalized"));
  return schema;
}

std::vector<std::pair<std::string, jobject>> MapEntries(JNIEnv* env,
                                                        jobject map) {
  std::vector<std::pair<std::string, jobject>> entries;
  if (!IsInstance(env, map, "java/util/Map")) {
    return entries;
  }
  jclass map_class = FindClass(env, "java/util/Map");
  jmethodID entry_set =
      env->GetMethodID(map_class, "entrySet", "()Ljava/util/Set;");
  jobject set = env->CallObjectMethod(map, entry_set);
  jclass set_class = FindClass(env, "java/util/Set");
  jmethodID iterator_method =
      env->GetMethodID(set_class, "iterator", "()Ljava/util/Iterator;");
  jobject iterator = env->CallObjectMethod(set, iterator_method);
  jclass iterator_class = FindClass(env, "java/util/Iterator");
  jmethodID has_next =
      env->GetMethodID(iterator_class, "hasNext", "()Z");
  jmethodID next =
      env->GetMethodID(iterator_class, "next", "()Ljava/lang/Object;");
  jclass entry_class = FindClass(env, "java/util/Map$Entry");
  jmethodID get_key =
      env->GetMethodID(entry_class, "getKey", "()Ljava/lang/Object;");
  jmethodID get_value =
      env->GetMethodID(entry_class, "getValue", "()Ljava/lang/Object;");
  while (env->CallBooleanMethod(iterator, has_next) == JNI_TRUE) {
    jobject entry = env->CallObjectMethod(iterator, next);
    entries.emplace_back(
        StringValue(env, env->CallObjectMethod(entry, get_key)),
        env->CallObjectMethod(entry, get_value));
  }
  return entries;
}

std::vector<FsvDracoPrimitiveRequest> PrimitiveRequests(JNIEnv* env,
                                                        jobject raw_primitives) {
  std::vector<FsvDracoPrimitiveRequest> requests;
  if (!IsInstance(env, raw_primitives, "java/util/List")) {
    return requests;
  }
  const int count = ListSize(env, raw_primitives);
  for (int index = 0; index < count; index += 1) {
    jobject raw = ListGet(env, raw_primitives, index);
    if (!IsInstance(env, raw, "java/util/Map")) {
      continue;
    }
    FsvDracoPrimitiveRequest request;
    request.mesh_index = IntValue(env, MapGet(env, raw, "meshIndex"));
    request.primitive_index = IntValue(env, MapGet(env, raw, "primitiveIndex"));
    request.compressed_bytes = ByteVector(env, MapGet(env, raw, "compressedBytes"));

    for (const auto& entry : MapEntries(env, MapGet(env, raw, "attributes"))) {
      request.attributes[entry.first] = IntValue(env, entry.second);
    }
    for (const auto& entry :
         MapEntries(env, MapGet(env, raw, "attributeAccessors"))) {
      request.attribute_accessors[entry.first] =
          AccessorSchema(env, entry.second);
    }
    jobject indices_accessor = MapGet(env, raw, "indicesAccessor");
    if (IsInstance(env, indices_accessor, "java/util/Map")) {
      request.has_indices_accessor = true;
      request.indices_accessor = AccessorSchema(env, indices_accessor);
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

jobject Diagnostic(JNIEnv* env,
                   const FsvDracoDiagnostic& diagnostic,
                   jstring source) {
  jobject details = NewHashMap(env);
  MapPutString(env, details, "extension", kDracoExtension);
  MapPutString(env, details, "decoder", "draco");
  MapPutBool(env, details, "required", true);
  MapPutString(env, details, "status", diagnostic.status);
  MapPutString(env, details, "pluginPackage", "flutter_scene_viewer_draco");
  MapPutString(env, details, "configurationKey", kInfoPlistKey);
  MapPutString(env, details, "androidManifestKey", kAndroidManifestKey);
  MapPutInt(env, details, "meshIndex", diagnostic.mesh_index);
  MapPutInt(env, details, "primitiveIndex", diagnostic.primitive_index);
  if (!diagnostic.attribute.empty()) {
    MapPutString(env, details, "attribute", diagnostic.attribute);
  }
  if (source != nullptr) {
    MapPutObject(env, details, "source", source);
  }

  jobject result = NewHashMap(env);
  MapPutString(env, result, "code", "unsupportedModelFeature");
  MapPutString(env, result, "message", diagnostic.message);
  MapPutObject(env, result, "details", details);
  return result;
}

jobject BridgeDiagnostics(JNIEnv* env,
                          const FsvDracoDecodeResult& decode_result,
                          jstring source) {
  jobject diagnostics = NewArrayList(env);
  for (const FsvDracoDiagnostic& diagnostic : decode_result.diagnostics) {
    ListAdd(env, diagnostics, Diagnostic(env, diagnostic, source));
  }
  return diagnostics;
}

jobject DecodedPrimitives(JNIEnv* env,
                          const FsvDracoDecodeResult& decode_result) {
  jobject decoded = NewArrayList(env);
  for (const FsvDracoDecodedPrimitive& primitive :
       decode_result.decoded_primitives) {
    jobject attributes = NewHashMap(env);
    for (const auto& entry : primitive.attributes) {
      MapPutObject(env, attributes, entry.first.c_str(),
                   ByteArray(env, entry.second));
    }

    jobject map = NewHashMap(env);
    MapPutInt(env, map, "meshIndex", primitive.mesh_index);
    MapPutInt(env, map, "primitiveIndex", primitive.primitive_index);
    MapPutObject(env, map, "attributes", attributes);
    if (primitive.has_indices) {
      MapPutObject(env, map, "indices", ByteArray(env, primitive.indices));
    }
    ListAdd(env, decoded, map);
  }
  return decoded;
}
}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeDecoderLinked(
    JNIEnv* env, jclass clazz) {
  return FsvDracoDecoderLinked() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativePrimitiveDecodeAvailable(
    JNIEnv* env, jclass clazz) {
  return FsvDracoPrimitiveDecodeAvailable() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeDecodePrimitives(
    JNIEnv* env, jclass clazz, jobject raw_primitives, jstring source) {
  FsvDracoDecodeResult decode_result =
      FsvDracoDecodePrimitives(PrimitiveRequests(env, raw_primitives));
  jobject response = NewHashMap(env);
  MapPutObject(env, response, "decodedPrimitives",
               DecodedPrimitives(env, decode_result));
  MapPutObject(env, response, "diagnostics",
               BridgeDiagnostics(env, decode_result, source));
  return response;
}
