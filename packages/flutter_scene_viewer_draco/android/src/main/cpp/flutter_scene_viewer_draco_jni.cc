#include <jni.h>

#include <limits>

#include "fsv_draco_bridge.h"
#include "fsv_draco_platform_serialization.h"

namespace {
constexpr const char* kDracoExtension = "KHR_draco_mesh_compression";
constexpr const char* kInfoPlistKey = "FlutterSceneViewerDracoEnabled";
constexpr const char* kAndroidManifestKey =
    "flutter_scene_viewer_draco_enabled";

bool ClearPendingJniException(JNIEnv* env) {
  if (env->ExceptionCheck() != JNI_TRUE) {
    return false;
  }
  env->ExceptionClear();
  return true;
}

// JNI locals are per-call resources, including values returned while a Java
// exception is pending.  Keep ownership explicit: the input conversion path
// can visit an unbounded number of primitive and attribute entries.
class JniLocalRef final {
 public:
  JniLocalRef(JNIEnv* env, jobject value) : env_(env), value_(value) {}
  ~JniLocalRef() {
    if (value_ != nullptr) env_->DeleteLocalRef(value_);
  }

  JniLocalRef(const JniLocalRef&) = delete;
  JniLocalRef& operator=(const JniLocalRef&) = delete;

  jobject get() const { return value_; }
  jobject release() {
    jobject value = value_;
    value_ = nullptr;
    return value;
  }

 private:
  JNIEnv* env_;
  jobject value_;
};

jmethodID GetMethodID(JNIEnv* env,
                       jclass clazz,
                       const char* name,
                       const char* signature) {
  if (clazz == nullptr) return nullptr;
  jmethodID method = env->GetMethodID(clazz, name, signature);
  return ClearPendingJniException(env) ? nullptr : method;
}

jclass FindClass(JNIEnv* env, const char* name) {
  jclass result = env->FindClass(name);
  if (!ClearPendingJniException(env)) return result;
  if (result != nullptr) env->DeleteLocalRef(result);
  return nullptr;
}

template <typename String>
jobject NewString(JNIEnv* env, const String& value) {
  jobject result = env->NewStringUTF(value.c_str());
  if (!ClearPendingJniException(env)) return result;
  if (result != nullptr) env->DeleteLocalRef(result);
  return nullptr;
}

jobject NewString(JNIEnv* env, const char* value) {
  jobject result = env->NewStringUTF(value);
  if (!ClearPendingJniException(env)) return result;
  if (result != nullptr) env->DeleteLocalRef(result);
  return nullptr;
}

jobject NewInteger(JNIEnv* env, int value) {
  jclass integer_class = FindClass(env, "java/lang/Integer");
  if (integer_class == nullptr) return nullptr;
  jmethodID constructor =
      env->GetMethodID(integer_class, "<init>", "(I)V");
  if (ClearPendingJniException(env) || constructor == nullptr) {
    env->DeleteLocalRef(integer_class);
    return nullptr;
  }
  jobject result = env->NewObject(integer_class, constructor, value);
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(integer_class);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject NewLong(JNIEnv* env, int64_t value) {
  jclass long_class = FindClass(env, "java/lang/Long");
  if (long_class == nullptr) return nullptr;
  jmethodID constructor = env->GetMethodID(long_class, "<init>", "(J)V");
  if (ClearPendingJniException(env) || constructor == nullptr) {
    env->DeleteLocalRef(long_class);
    return nullptr;
  }
  jobject result =
      env->NewObject(long_class, constructor, static_cast<jlong>(value));
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(long_class);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject NewBoolean(JNIEnv* env, bool value) {
  jclass boolean_class = FindClass(env, "java/lang/Boolean");
  if (boolean_class == nullptr) return nullptr;
  jmethodID constructor =
      env->GetMethodID(boolean_class, "<init>", "(Z)V");
  if (ClearPendingJniException(env) || constructor == nullptr) {
    env->DeleteLocalRef(boolean_class);
    return nullptr;
  }
  jobject result = env->NewObject(boolean_class, constructor,
                                  value ? JNI_TRUE : JNI_FALSE);
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(boolean_class);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject NewHashMap(JNIEnv* env) {
  jclass map_class = FindClass(env, "java/util/HashMap");
  if (map_class == nullptr) return nullptr;
  jmethodID constructor = env->GetMethodID(map_class, "<init>", "()V");
  if (ClearPendingJniException(env) || constructor == nullptr) {
    env->DeleteLocalRef(map_class);
    return nullptr;
  }
  jobject result = env->NewObject(map_class, constructor);
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(map_class);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject NewArrayList(JNIEnv* env) {
  jclass list_class = FindClass(env, "java/util/ArrayList");
  if (list_class == nullptr) return nullptr;
  jmethodID constructor = env->GetMethodID(list_class, "<init>", "()V");
  if (ClearPendingJniException(env) || constructor == nullptr) {
    env->DeleteLocalRef(list_class);
    return nullptr;
  }
  jobject result = env->NewObject(list_class, constructor);
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(list_class);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

bool MapPutObject(JNIEnv* env, jobject map, const char* key, jobject value) {
  if (map == nullptr || value == nullptr) return false;
  jclass map_class = FindClass(env, "java/util/Map");
  if (map_class == nullptr) return false;
  jmethodID put =
      env->GetMethodID(map_class, "put",
                       "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
  if (ClearPendingJniException(env) || put == nullptr) {
    env->DeleteLocalRef(map_class);
    return false;
  }
  jobject key_value = NewString(env, key);
  if (key_value == nullptr) {
    env->DeleteLocalRef(map_class);
    return false;
  }
  jobject previous = env->CallObjectMethod(map, put, key_value, value);
  const bool failed = ClearPendingJniException(env);
  if (previous != nullptr) env->DeleteLocalRef(previous);
  env->DeleteLocalRef(key_value);
  env->DeleteLocalRef(map_class);
  return !failed;
}

bool MapPutString(JNIEnv* env, jobject map, const char* key, const char* value) {
  jobject object = NewString(env, value);
  if (object == nullptr) return false;
  const bool result = MapPutObject(env, map, key, object);
  env->DeleteLocalRef(object);
  return result;
}

template <typename String>
bool MapPutString(JNIEnv* env,
                  jobject map,
                  const char* key,
                  const String& value) {
  jobject object = NewString(env, value);
  if (object == nullptr) return false;
  const bool result = MapPutObject(env, map, key, object);
  env->DeleteLocalRef(object);
  return result;
}

bool MapPutInt(JNIEnv* env, jobject map, const char* key, int value) {
  jobject object = NewInteger(env, value);
  if (object == nullptr) return false;
  const bool result = MapPutObject(env, map, key, object);
  env->DeleteLocalRef(object);
  return result;
}

bool MapPutLong(JNIEnv* env, jobject map, const char* key, uint64_t value) {
  jobject object = NewLong(env, static_cast<int64_t>(value));
  if (object == nullptr) return false;
  const bool result = MapPutObject(env, map, key, object);
  env->DeleteLocalRef(object);
  return result;
}

bool MapPutBool(JNIEnv* env, jobject map, const char* key, bool value) {
  jobject object = NewBoolean(env, value);
  if (object == nullptr) return false;
  const bool result = MapPutObject(env, map, key, object);
  env->DeleteLocalRef(object);
  return result;
}

jobject MapGet(JNIEnv* env, jobject map, const char* key) {
  if (map == nullptr) {
    return nullptr;
  }
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  jmethodID get = GetMethodID(
      env, static_cast<jclass>(map_class.get()), "get",
      "(Ljava/lang/Object;)Ljava/lang/Object;");
  if (get == nullptr) return nullptr;
  JniLocalRef key_value(env, NewString(env, key));
  if (key_value.get() == nullptr) return nullptr;
  jobject result = env->CallObjectMethod(map, get, key_value.get());
  if (ClearPendingJniException(env)) {
    if (result != nullptr) env->DeleteLocalRef(result);
    return nullptr;
  }
  return result;
}

bool ListAdd(JNIEnv* env, jobject list, jobject value) {
  if (list == nullptr || value == nullptr) return false;
  jclass list_class = FindClass(env, "java/util/List");
  if (list_class == nullptr) return false;
  jmethodID add =
      env->GetMethodID(list_class, "add", "(Ljava/lang/Object;)Z");
  if (ClearPendingJniException(env) || add == nullptr) {
    env->DeleteLocalRef(list_class);
    return false;
  }
  const jboolean added = env->CallBooleanMethod(list, add, value);
  const bool failed = ClearPendingJniException(env);
  env->DeleteLocalRef(list_class);
  return !failed && added == JNI_TRUE;
}

int ListSize(JNIEnv* env, jobject list) {
  if (list == nullptr) {
    return 0;
  }
  JniLocalRef list_class(env, FindClass(env, "java/util/List"));
  jmethodID size = GetMethodID(env, static_cast<jclass>(list_class.get()),
                               "size", "()I");
  if (size == nullptr) return 0;
  const jint result = env->CallIntMethod(list, size);
  return ClearPendingJniException(env) ? 0 : result;
}

jobject ListGet(JNIEnv* env, jobject list, int index) {
  if (list == nullptr) return nullptr;
  JniLocalRef list_class(env, FindClass(env, "java/util/List"));
  jmethodID get = GetMethodID(env, static_cast<jclass>(list_class.get()),
                              "get", "(I)Ljava/lang/Object;");
  if (get == nullptr) return nullptr;
  jobject result = env->CallObjectMethod(list, get, index);
  if (ClearPendingJniException(env)) {
    if (result != nullptr) env->DeleteLocalRef(result);
    return nullptr;
  }
  return result;
}

bool IsInstance(JNIEnv* env, jobject value, const char* class_name) {
  if (value == nullptr) {
    return false;
  }
  JniLocalRef clazz(env, FindClass(env, class_name));
  if (clazz.get() == nullptr) return false;
  const jboolean result =
      env->IsInstanceOf(value, static_cast<jclass>(clazz.get()));
  return !ClearPendingJniException(env) && result == JNI_TRUE;
}

int IntValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return 0;
  }
  JniLocalRef number_class(env, FindClass(env, "java/lang/Number"));
  jmethodID int_value = GetMethodID(
      env, static_cast<jclass>(number_class.get()), "intValue", "()I");
  if (int_value == nullptr) return 0;
  const jint result = env->CallIntMethod(value, int_value);
  return ClearPendingJniException(env) ? 0 : result;
}

int64_t LongValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return 0;
  }
  JniLocalRef number_class(env, FindClass(env, "java/lang/Number"));
  jmethodID long_value = GetMethodID(
      env, static_cast<jclass>(number_class.get()), "longValue", "()J");
  if (long_value == nullptr) return 0;
  const jlong result = env->CallLongMethod(value, long_value);
  return ClearPendingJniException(env) ? 0 : static_cast<int64_t>(result);
}

FsvDracoBudgetNumber BudgetNumber(JNIEnv* env, jobject map, const char* key) {
  JniLocalRef value(env, MapGet(env, map, key));
  if (value.get() == nullptr) {
    return FsvDracoBudgetNumber();
  }
  if (!IsInstance(env, value.get(), "java/lang/Integer") &&
      !IsInstance(env, value.get(), "java/lang/Long")) {
    return FsvDracoBudgetNumber::Invalid();
  }
  return FsvDracoBudgetNumber::Integer(LongValue(env, value.get()));
}

int64_t IntegralLongValueOr(JNIEnv* env, jobject value, int64_t fallback) {
  if (!IsInstance(env, value, "java/lang/Integer") &&
      !IsInstance(env, value, "java/lang/Long")) {
    return fallback;
  }
  return LongValue(env, value);
}

FsvDracoDecodeBudgetMetadata DecodeBudget(JNIEnv* env, jobject value) {
  FsvDracoDecodeBudgetMetadata budget;
  if (!IsInstance(env, value, "java/util/Map")) {
    return budget;
  }
  budget.max_total_decoded_bytes =
      BudgetNumber(env, value, "maxTotalDecodedBytes");
  budget.max_accessors = BudgetNumber(env, value, "maxAccessors");
  budget.max_vertices = BudgetNumber(env, value, "maxVertices");
  budget.max_indices = BudgetNumber(env, value, "maxIndices");
  budget.max_native_output_bytes =
      BudgetNumber(env, value, "maxNativeOutputBytes");
  return budget;
}

FsvDracoDecodeBudgetState DecodeBudgetState(JNIEnv* env, jobject value) {
  FsvDracoDecodeBudgetState state;
  if (!IsInstance(env, value, "java/util/Map")) {
    return state;
  }
  state.total_decoded_bytes = BudgetNumber(env, value, "totalDecodedBytes");
  state.accessors = BudgetNumber(env, value, "accessors");
  state.vertices = BudgetNumber(env, value, "vertices");
  state.indices = BudgetNumber(env, value, "indices");
  state.native_output_bytes = BudgetNumber(env, value, "nativeOutputBytes");
  return state;
}

bool BoolValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return false;
  }
  JniLocalRef boolean_class(env, FindClass(env, "java/lang/Boolean"));
  jmethodID bool_value = GetMethodID(
      env, static_cast<jclass>(boolean_class.get()), "booleanValue", "()Z");
  if (bool_value == nullptr) return false;
  const jboolean result = env->CallBooleanMethod(value, bool_value);
  return !ClearPendingJniException(env) && result == JNI_TRUE;
}

FsvDracoString StringValue(JNIEnv* env,
                           jobject value,
                           fsv_draco::FsvDecodeControl* control) {
  FsvDracoString result{FsvDracoAllocator<char>(control)};
  if (value == nullptr) {
    return result;
  }
  const char* chars = env->GetStringUTFChars(static_cast<jstring>(value),
                                             nullptr);
  if (ClearPendingJniException(env) || chars == nullptr) {
    if (chars != nullptr) {
      env->ReleaseStringUTFChars(static_cast<jstring>(value), chars);
    }
    return result;
  }
  struct UtfCharsRelease final {
    JNIEnv* env;
    jstring value;
    const char* chars;
    ~UtfCharsRelease() { env->ReleaseStringUTFChars(value, chars); }
  } release{env, static_cast<jstring>(value), chars};
  result.assign(chars);
  return result;
}

FsvDracoByteVector ByteVector(JNIEnv* env,
                              jobject value,
                              fsv_draco::FsvDecodeControl* control) {
  FsvDracoByteVector bytes{FsvDracoAllocator<uint8_t>(control)};
  if (value == nullptr) {
    return bytes;
  }
  auto array = static_cast<jbyteArray>(value);
  const jsize length = env->GetArrayLength(array);
  if (ClearPendingJniException(env) || length < 0) return bytes;
  bytes.resize(static_cast<size_t>(length));
  if (length > 0) {
    env->GetByteArrayRegion(array, 0, length,
                            reinterpret_cast<jbyte*>(bytes.data()));
    if (ClearPendingJniException(env)) bytes.clear();
  }
  return bytes;
}

struct JniByteArrayCopyContext {
  JNIEnv* env = nullptr;
};

bool AllocateJniByteArray(void* raw_context, uint64_t bytes,
                          void** destination) noexcept {
  auto* context = static_cast<JniByteArrayCopyContext*>(raw_context);
  jbyteArray array =
      context->env->NewByteArray(static_cast<jsize>(bytes));
  const bool failed = ClearPendingJniException(context->env);
  if (failed || array == nullptr) {
    if (array != nullptr) context->env->DeleteLocalRef(array);
    return false;
  }
  *destination = array;
  return true;
}

bool CopyJniByteArray(void* raw_context, void* destination,
                      const uint8_t* source, uint64_t bytes) noexcept {
  auto* context = static_cast<JniByteArrayCopyContext*>(raw_context);
  if (bytes != 0) {
    context->env->SetByteArrayRegion(
        static_cast<jbyteArray>(destination), 0, static_cast<jsize>(bytes),
        reinterpret_cast<const jbyte*>(source));
    if (ClearPendingJniException(context->env)) {
      return false;
    }
  }
  return true;
}

void ReleaseJniByteArray(void* raw_context, void* destination) noexcept {
  auto* context = static_cast<JniByteArrayCopyContext*>(raw_context);
  context->env->DeleteLocalRef(static_cast<jbyteArray>(destination));
}

template <typename ByteAllocator>
jbyteArray ByteArray(JNIEnv* env,
                     const std::vector<uint8_t, ByteAllocator>& bytes,
                     fsv_draco::FsvDecodeControl* control,
                     FsvDracoPlatformCopyOutcome* outcome) {
  JniByteArrayCopyContext context{env};
  FsvDracoPlatformCopyCallbacks callbacks;
  callbacks.context = &context;
  callbacks.allocate = AllocateJniByteArray;
  callbacks.copy = CopyJniByteArray;
  callbacks.release = ReleaseJniByteArray;
  void* destination = nullptr;
  *outcome = FsvDracoCopyBytesToPlatform(
      bytes.data(), static_cast<uint64_t>(bytes.size()),
      static_cast<uint64_t>(std::numeric_limits<jsize>::max()), control,
      callbacks, &destination);
  return static_cast<jbyteArray>(destination);
}

FsvDracoAccessorSchema AccessorSchema(
    JNIEnv* env,
    jobject value,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoAccessorSchema schema(control);
  if (!IsInstance(env, value, "java/util/Map")) {
    return schema;
  }
  JniLocalRef accessor_index(env, MapGet(env, value, "accessorIndex"));
  schema.accessor_index = IntegralLongValueOr(env, accessor_index.get(), -1);
  schema.component_type = BudgetNumber(env, value, "componentType");
  JniLocalRef type_value(env, MapGet(env, value, "type"));
  const FsvDracoString type = StringValue(env, type_value.get(), control);
  schema.type.assign(type.data(), type.size());
  JniLocalRef count(env, MapGet(env, value, "count"));
  schema.count = IntegralLongValueOr(env, count.get(), -1);
  JniLocalRef normalized(env, MapGet(env, value, "normalized"));
  schema.normalized = BoolValue(env, normalized.get());
  return schema;
}

template <typename Callback>
bool ForEachMapEntry(JNIEnv* env, jobject map, Callback callback) {
  if (map == nullptr) return true;
  if (!IsInstance(env, map, "java/util/Map")) return true;
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  jmethodID entry_set = GetMethodID(
      env, static_cast<jclass>(map_class.get()), "entrySet",
      "()Ljava/util/Set;");
  if (entry_set == nullptr) return false;
  JniLocalRef set(env, env->CallObjectMethod(map, entry_set));
  if (ClearPendingJniException(env) || set.get() == nullptr) return false;
  JniLocalRef set_class(env, FindClass(env, "java/util/Set"));
  jmethodID iterator_method = GetMethodID(
      env, static_cast<jclass>(set_class.get()), "iterator",
      "()Ljava/util/Iterator;");
  if (iterator_method == nullptr) return false;
  JniLocalRef iterator(
      env, env->CallObjectMethod(set.get(), iterator_method));
  if (ClearPendingJniException(env) || iterator.get() == nullptr) return false;
  JniLocalRef iterator_class(env, FindClass(env, "java/util/Iterator"));
  jmethodID has_next = GetMethodID(
      env, static_cast<jclass>(iterator_class.get()), "hasNext", "()Z");
  jmethodID next = GetMethodID(
      env, static_cast<jclass>(iterator_class.get()), "next",
      "()Ljava/lang/Object;");
  if (has_next == nullptr || next == nullptr) return false;
  JniLocalRef entry_class(env, FindClass(env, "java/util/Map$Entry"));
  jmethodID get_key = GetMethodID(
      env, static_cast<jclass>(entry_class.get()), "getKey",
      "()Ljava/lang/Object;");
  jmethodID get_value = GetMethodID(
      env, static_cast<jclass>(entry_class.get()), "getValue",
      "()Ljava/lang/Object;");
  if (get_key == nullptr || get_value == nullptr) return false;
  while (true) {
    const jboolean has_entry =
        env->CallBooleanMethod(iterator.get(), has_next);
    if (ClearPendingJniException(env)) return false;
    if (has_entry != JNI_TRUE) return true;
    JniLocalRef entry(env, env->CallObjectMethod(iterator.get(), next));
    if (ClearPendingJniException(env) || entry.get() == nullptr) return false;
    JniLocalRef key(env, env->CallObjectMethod(entry.get(), get_key));
    if (ClearPendingJniException(env)) return false;
    JniLocalRef value(env, env->CallObjectMethod(entry.get(), get_value));
    if (ClearPendingJniException(env)) {
      return false;
    }
    if (!callback(key.get(), value.get())) return false;
  }
}

FsvDracoPrimitiveRequests PrimitiveRequests(
    JNIEnv* env,
    jobject raw_primitives,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
  if (!IsInstance(env, raw_primitives, "java/util/List")) {
    return requests;
  }
  const int count = ListSize(env, raw_primitives);
  for (int index = 0; index < count; index += 1) {
    JniLocalRef raw(env, ListGet(env, raw_primitives, index));
    if (!IsInstance(env, raw.get(), "java/util/Map")) {
      continue;
    }
    FsvDracoPrimitiveRequest request(control);
    JniLocalRef mesh_index(env, MapGet(env, raw.get(), "meshIndex"));
    request.mesh_index = IntValue(env, mesh_index.get());
    JniLocalRef primitive_index(env, MapGet(env, raw.get(), "primitiveIndex"));
    request.primitive_index = IntValue(env, primitive_index.get());
    JniLocalRef compressed_bytes(env, MapGet(env, raw.get(), "compressedBytes"));
    request.compressed_bytes = ByteVector(env, compressed_bytes.get(), control);
    JniLocalRef vertex_accessor_index(
        env, MapGet(env, raw.get(), "vertexAccessorIndex"));
    request.vertex_accessor_index =
        IntegralLongValueOr(env, vertex_accessor_index.get(), -1);

    JniLocalRef attributes(env, MapGet(env, raw.get(), "attributes"));
    if (!ForEachMapEntry(env, attributes.get(),
                    [&](jobject raw_key, jobject raw_value) {
      request.attributes.emplace(StringValue(env, raw_key, control),
                                 IntegralLongValueOr(env, raw_value, -1));
      return true;
    })) {
      return FsvDracoPrimitiveRequests{
          FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
    }
    JniLocalRef attribute_accessors(
        env, MapGet(env, raw.get(), "attributeAccessors"));
    if (!ForEachMapEntry(env, attribute_accessors.get(),
                    [&](jobject raw_key, jobject raw_value) {
      request.attribute_accessors.emplace(
          StringValue(env, raw_key, control),
          AccessorSchema(env, raw_value, control));
      return true;
    })) {
      return FsvDracoPrimitiveRequests{
          FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
    }
    JniLocalRef indices_accessor(
        env, MapGet(env, raw.get(), "indicesAccessor"));
    if (IsInstance(env, indices_accessor.get(), "java/util/Map")) {
      request.has_indices_accessor = true;
      request.indices_accessor =
          AccessorSchema(env, indices_accessor.get(), control);
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

jobject Diagnostic(JNIEnv* env,
                   const FsvDracoDiagnostic& diagnostic,
                   jstring source) {
  jobject details = NewHashMap(env);
  bool valid = details != nullptr &&
               MapPutString(env, details, "extension", kDracoExtension) &&
               MapPutString(env, details, "decoder", "draco") &&
               MapPutBool(env, details, "required", true) &&
               MapPutString(env, details, "status", diagnostic.status);
  if (!diagnostic.stage.empty()) {
    valid = valid && MapPutString(env, details, "stage", diagnostic.stage);
  }
  if (!diagnostic.field.empty()) {
    valid = valid && MapPutString(env, details, "field", diagnostic.field) &&
            MapPutString(env, details, "limitation",
                         diagnostic.status == "budgetExceeded"
                             ? "decodeBudget"
                             : "dracoNativeBoundary");
  }
  if (diagnostic.has_limit) {
    valid = valid && MapPutLong(env, details, "limit", diagnostic.limit);
  }
  if (diagnostic.has_actual) {
    valid = valid && MapPutLong(env, details, "actual", diagnostic.actual);
  }
  valid = valid &&
          MapPutString(env, details, "pluginPackage",
                       "flutter_scene_viewer_draco") &&
          MapPutString(env, details, "configurationKey", kInfoPlistKey) &&
          MapPutString(env, details, "androidManifestKey", kAndroidManifestKey) &&
          MapPutInt(env, details, "meshIndex", diagnostic.mesh_index) &&
          MapPutInt(env, details, "primitiveIndex",
                    diagnostic.primitive_index);
  if (!diagnostic.attribute.empty()) {
    valid = valid &&
            MapPutString(env, details, "attribute", diagnostic.attribute);
  }
  if (source != nullptr) {
    valid = valid && MapPutObject(env, details, "source", source);
  }
  if (!valid) {
    if (details != nullptr) env->DeleteLocalRef(details);
    return nullptr;
  }

  jobject result = NewHashMap(env);
  valid = result != nullptr &&
          MapPutString(env, result, "code", "unsupportedModelFeature") &&
          MapPutString(env, result, "message", diagnostic.message) &&
          MapPutObject(env, result, "details", details);
  env->DeleteLocalRef(details);
  if (!valid) {
    if (result != nullptr) env->DeleteLocalRef(result);
    return nullptr;
  }
  return result;
}

jobject TerminalDiagnostic(JNIEnv* env,
                           const FsvDracoTerminalOutcome& terminal,
                           jstring source) {
  const bool budget_exceeded =
      terminal.kind == FsvDracoTerminalOutcomeKind::kBudgetExceeded;
  if (!budget_exceeded &&
      terminal.kind != FsvDracoTerminalOutcomeKind::kAllocationFailed) {
    return nullptr;
  }
  jobject details = NewHashMap(env);
  bool valid = details != nullptr &&
               MapPutString(env, details, "extension", kDracoExtension) &&
               MapPutString(env, details, "decoder", "draco") &&
               MapPutBool(env, details, "required", true) &&
               MapPutString(env, details, "status",
                            budget_exceeded ? "budgetExceeded"
                                            : "allocationFailed") &&
               MapPutString(env, details, "stage",
                            "dracoWorkingAllocation") &&
               MapPutString(env, details, "field", "nativeWorkingBytes") &&
               MapPutString(env, details, "limitation",
                            budget_exceeded ? "decodeBudget"
                                            : "dracoNativeBoundary") &&
               MapPutString(env, details, "pluginPackage",
                            "flutter_scene_viewer_draco") &&
               MapPutString(env, details, "configurationKey", kInfoPlistKey) &&
               MapPutString(env, details, "androidManifestKey",
                            kAndroidManifestKey) &&
               MapPutInt(env, details, "meshIndex", terminal.mesh_index) &&
               MapPutInt(env, details, "primitiveIndex",
                         terminal.primitive_index);
  if (source != nullptr) {
    valid = valid && MapPutObject(env, details, "source", source);
  }
  if (!valid) {
    if (details != nullptr) env->DeleteLocalRef(details);
    return nullptr;
  }
  jobject result = NewHashMap(env);
  valid = result != nullptr &&
          MapPutString(env, result, "code", "unsupportedModelFeature") &&
          MapPutString(
              env, result, "message",
              budget_exceeded
                  ? "Native Draco decode exceeded maxNativeWorkingBytes."
                  : "Native Draco decode allocation failed.") &&
          MapPutObject(env, result, "details", details);
  env->DeleteLocalRef(details);
  if (!valid) {
    if (result != nullptr) env->DeleteLocalRef(result);
    return nullptr;
  }
  return result;
}

jobject BridgeDiagnostics(JNIEnv* env,
                          const FsvDracoDecodeResult& decode_result,
                          jstring source) {
  jobject diagnostics = NewArrayList(env);
  if (diagnostics == nullptr) return nullptr;
  for (const FsvDracoDiagnostic& diagnostic : decode_result.diagnostics) {
    jobject mapped = Diagnostic(env, diagnostic, source);
    if (mapped == nullptr || !ListAdd(env, diagnostics, mapped)) {
      if (mapped != nullptr) env->DeleteLocalRef(mapped);
      env->DeleteLocalRef(diagnostics);
      return nullptr;
    }
    env->DeleteLocalRef(mapped);
  }
  const bool needs_terminal =
      decode_result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kBudgetExceeded ||
      decode_result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kAllocationFailed;
  jobject terminal =
      TerminalDiagnostic(env, decode_result.terminal_outcome, source);
  if (needs_terminal &&
      (terminal == nullptr || !ListAdd(env, diagnostics, terminal))) {
    if (terminal != nullptr) env->DeleteLocalRef(terminal);
    env->DeleteLocalRef(diagnostics);
    return nullptr;
  }
  if (terminal != nullptr) env->DeleteLocalRef(terminal);
  return diagnostics;
}

jobject DecodedPrimitives(JNIEnv* env,
                          const FsvDracoDecodeResult& decode_result,
                          fsv_draco::FsvDecodeControl* control) {
  jobject decoded = NewArrayList(env);
  if (decoded == nullptr) return nullptr;
  for (const FsvDracoDecodedPrimitive& primitive :
       decode_result.decoded_primitives) {
    if (control != nullptr && control->IsCancelled()) return nullptr;
    jobject attributes = NewHashMap(env);
    if (attributes == nullptr) return nullptr;
    for (const auto& entry : primitive.attributes) {
      FsvDracoPlatformCopyOutcome outcome;
      jbyteArray array = ByteArray(env, entry.second, control, &outcome);
      if (outcome != FsvDracoPlatformCopyOutcome::kSuccess || array == nullptr ||
          !MapPutObject(env, attributes, entry.first.c_str(), array)) {
        if (array != nullptr) env->DeleteLocalRef(array);
        return nullptr;  // Atomic platform-copy failure.
      }
      env->DeleteLocalRef(array);
    }

    jobject map = NewHashMap(env);
    if (map == nullptr ||
        !MapPutInt(env, map, "meshIndex", primitive.mesh_index) ||
        !MapPutInt(env, map, "primitiveIndex", primitive.primitive_index) ||
        !MapPutObject(env, map, "attributes", attributes)) {
      if (map != nullptr) env->DeleteLocalRef(map);
      env->DeleteLocalRef(attributes);
      return nullptr;
    }
    if (primitive.has_indices) {
      FsvDracoPlatformCopyOutcome outcome;
      jbyteArray array = ByteArray(env, primitive.indices, control, &outcome);
      if (outcome != FsvDracoPlatformCopyOutcome::kSuccess || array == nullptr ||
          !MapPutObject(env, map, "indices", array)) {
        if (array != nullptr) env->DeleteLocalRef(array);
        return nullptr;  // Atomic platform-copy failure.
      }
      env->DeleteLocalRef(array);
    }
    if (!ListAdd(env, decoded, map)) {
      env->DeleteLocalRef(attributes);
      env->DeleteLocalRef(map);
      return nullptr;
    }
    env->DeleteLocalRef(attributes);
    env->DeleteLocalRef(map);
  }
  if (control != nullptr && control->IsCancelled()) return nullptr;
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

extern "C" JNIEXPORT jlong JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeCreateDecodeControl(
    JNIEnv* env, jclass clazz, jlong working_byte_limit) {
  (void)env;
  (void)clazz;
  const uint64_t limit = working_byte_limit < 0
                             ? 0
                             : static_cast<uint64_t>(working_byte_limit);
  return reinterpret_cast<jlong>(new fsv_draco::FsvDecodeControl(limit));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeCancelDecodeControl(
    JNIEnv* env, jclass clazz, jlong handle) {
  (void)env;
  (void)clazz;
  auto* control = reinterpret_cast<fsv_draco::FsvDecodeControl*>(handle);
  return control != nullptr && control->Cancel() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeDestroyDecodeControl(
    JNIEnv* env, jclass clazz, jlong handle) {
  (void)env;
  (void)clazz;
  delete reinterpret_cast<fsv_draco::FsvDecodeControl*>(handle);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1draco_FlutterSceneViewerDracoPlugin_nativeDecodePrimitives(
    JNIEnv* env,
    jclass clazz,
    jobject raw_primitives,
    jobject raw_budget,
    jobject raw_budget_state,
    jstring source,
    jlong control_handle) {
  auto* control =
      reinterpret_cast<fsv_draco::FsvDecodeControl*>(control_handle);
  FsvDracoDecodeResult decode_result(control);
  try {
    FsvDracoPrimitiveRequests requests =
        PrimitiveRequests(env, raw_primitives, control);
    decode_result = FsvDracoDecodePrimitives(
        requests, DecodeBudget(env, raw_budget),
        DecodeBudgetState(env, raw_budget_state), nullptr, control);
  } catch (const fsv_draco::FsvDecodeStopped&) {
    FsvDracoRecordTerminalOutcome(&decode_result, control);
  } catch (const fsv_draco::FsvDecodeBudgetExceeded&) {
    FsvDracoRecordTerminalOutcome(&decode_result, control);
  } catch (const std::bad_alloc&) {
    FsvDracoRecordTerminalOutcome(&decode_result, control);
  }
  if (control != nullptr && control->IsCancelled()) return nullptr;
  jobject decoded = DecodedPrimitives(env, decode_result, control);
  if (decoded == nullptr) return nullptr;
  jobject diagnostics = BridgeDiagnostics(env, decode_result, source);
  if (diagnostics == nullptr || ClearPendingJniException(env)) return nullptr;
  jobject response = NewHashMap(env);
  if (response == nullptr || !MapPutObject(env, response, "decodedPrimitives", decoded) ||
      !MapPutObject(env, response, "diagnostics", diagnostics) ||
      (control != nullptr && control->IsCancelled())) {
    return nullptr;  // Atomic platform-copy failure.
  }
  env->DeleteLocalRef(decoded);
  env->DeleteLocalRef(diagnostics);
  return response;
}
