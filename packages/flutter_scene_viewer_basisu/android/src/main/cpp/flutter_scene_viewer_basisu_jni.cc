#include <jni.h>

#include <limits>
#include <new>
#include <utility>

#include "fsv_basisu_bridge.h"
#include "fsv_basisu_platform_serialization.h"

namespace {
constexpr const char* kBasisuExtension = "KHR_texture_basisu";

bool ClearPendingJniException(JNIEnv* env) {
  if (env->ExceptionCheck() != JNI_TRUE) return false;
  env->ExceptionClear();
  return true;
}

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

jclass FindClass(JNIEnv* env, const char* name) {
  jclass result = env->FindClass(name);
  if (!ClearPendingJniException(env)) return result;
  if (result != nullptr) env->DeleteLocalRef(result);
  return nullptr;
}

jmethodID GetMethodID(JNIEnv* env, jclass clazz, const char* name,
                      const char* signature) {
  if (clazz == nullptr) return nullptr;
  jmethodID result = env->GetMethodID(clazz, name, signature);
  return ClearPendingJniException(env) ? nullptr : result;
}

jobject NewHashMap(JNIEnv* env) {
  JniLocalRef map_class(env, FindClass(env, "java/util/HashMap"));
  jmethodID constructor = GetMethodID(
      env, static_cast<jclass>(map_class.get()), "<init>", "()V");
  if (constructor == nullptr) return nullptr;
  jobject result = env->NewObject(static_cast<jclass>(map_class.get()),
                                  constructor);
  const bool failed = ClearPendingJniException(env);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject NewArrayList(JNIEnv* env) {
  JniLocalRef list_class(env, FindClass(env, "java/util/ArrayList"));
  jmethodID constructor = GetMethodID(
      env, static_cast<jclass>(list_class.get()), "<init>", "()V");
  if (constructor == nullptr) return nullptr;
  jobject result = env->NewObject(static_cast<jclass>(list_class.get()),
                                  constructor);
  const bool failed = ClearPendingJniException(env);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject IntegerValue(JNIEnv* env, jint value) {
  JniLocalRef integer_class(env, FindClass(env, "java/lang/Integer"));
  jmethodID constructor = GetMethodID(
      env, static_cast<jclass>(integer_class.get()), "<init>", "(I)V");
  if (constructor == nullptr) return nullptr;
  jobject result = env->NewObject(static_cast<jclass>(integer_class.get()),
                                  constructor, value);
  const bool failed = ClearPendingJniException(env);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject LongValue(JNIEnv* env, jlong value) {
  JniLocalRef long_class(env, FindClass(env, "java/lang/Long"));
  jmethodID constructor = GetMethodID(
      env, static_cast<jclass>(long_class.get()), "<init>", "(J)V");
  if (constructor == nullptr) return nullptr;
  jobject result = env->NewObject(static_cast<jclass>(long_class.get()),
                                  constructor, value);
  const bool failed = ClearPendingJniException(env);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

jobject BooleanValue(JNIEnv* env, bool value) {
  JniLocalRef boolean_class(env, FindClass(env, "java/lang/Boolean"));
  jmethodID constructor = GetMethodID(
      env, static_cast<jclass>(boolean_class.get()), "<init>", "(Z)V");
  if (constructor == nullptr) return nullptr;
  jobject result = env->NewObject(static_cast<jclass>(boolean_class.get()),
                                  constructor,
                                  value ? JNI_TRUE : JNI_FALSE);
  const bool failed = ClearPendingJniException(env);
  if (failed && result != nullptr) env->DeleteLocalRef(result);
  return failed ? nullptr : result;
}

bool ListAdd(JNIEnv* env, jobject list, jobject value) {
  if (list == nullptr || value == nullptr) return false;
  JniLocalRef list_class(env, FindClass(env, "java/util/List"));
  jmethodID add = GetMethodID(env, static_cast<jclass>(list_class.get()),
                              "add", "(Ljava/lang/Object;)Z");
  if (add == nullptr) return false;
  const jboolean added = env->CallBooleanMethod(list, add, value);
  return !ClearPendingJniException(env) && added == JNI_TRUE;
}

bool MapPut(JNIEnv* env, jobject map, const char* key, jobject value) {
  if (map == nullptr || value == nullptr) return false;
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  jmethodID put = GetMethodID(
      env, static_cast<jclass>(map_class.get()), "put",
      "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
  if (put == nullptr) return false;
  jobject raw_key = env->NewStringUTF(key);
  if (ClearPendingJniException(env)) {
    if (raw_key != nullptr) env->DeleteLocalRef(raw_key);
    return false;
  }
  JniLocalRef key_object(env, raw_key);
  if (key_object.get() == nullptr) return false;
  JniLocalRef previous(
      env, env->CallObjectMethod(map, put, key_object.get(), value));
  return !ClearPendingJniException(env);
}

template <typename String>
bool MapPutString(JNIEnv* env, jobject map, const char* key,
                  const String& value) {
  jobject raw_value = env->NewStringUTF(value.c_str());
  if (ClearPendingJniException(env)) {
    if (raw_value != nullptr) env->DeleteLocalRef(raw_value);
    return false;
  }
  JniLocalRef string_value(env, raw_value);
  return string_value.get() != nullptr &&
         MapPut(env, map, key, string_value.get());
}

bool MapPutString(JNIEnv* env, jobject map, const char* key,
                  const char* value) {
  jobject raw_value = env->NewStringUTF(value);
  if (ClearPendingJniException(env)) {
    if (raw_value != nullptr) env->DeleteLocalRef(raw_value);
    return false;
  }
  JniLocalRef string_value(env, raw_value);
  return string_value.get() != nullptr &&
         MapPut(env, map, key, string_value.get());
}

bool MapPutInt(JNIEnv* env, jobject map, const char* key, int value) {
  JniLocalRef integer_value(env, IntegerValue(env, static_cast<jint>(value)));
  return integer_value.get() != nullptr &&
         MapPut(env, map, key, integer_value.get());
}

bool MapPutLong(JNIEnv* env, jobject map, const char* key, uint64_t value) {
  JniLocalRef long_value(env, LongValue(env, static_cast<jlong>(value)));
  return long_value.get() != nullptr &&
         MapPut(env, map, key, long_value.get());
}

bool MapPutBool(JNIEnv* env, jobject map, const char* key, bool value) {
  JniLocalRef boolean_value(env, BooleanValue(env, value));
  return boolean_value.get() != nullptr &&
         MapPut(env, map, key, boolean_value.get());
}

jobject MapGet(JNIEnv* env, jobject map, const char* key) {
  if (map == nullptr) return nullptr;
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  jmethodID get = GetMethodID(
      env, static_cast<jclass>(map_class.get()), "get",
      "(Ljava/lang/Object;)Ljava/lang/Object;");
  if (get == nullptr) return nullptr;
  jobject raw_key = env->NewStringUTF(key);
  if (ClearPendingJniException(env)) {
    if (raw_key != nullptr) env->DeleteLocalRef(raw_key);
    return nullptr;
  }
  JniLocalRef key_object(env, raw_key);
  if (key_object.get() == nullptr) return nullptr;
  jobject value = env->CallObjectMethod(map, get, key_object.get());
  if (ClearPendingJniException(env)) {
    if (value != nullptr) env->DeleteLocalRef(value);
    return nullptr;
  }
  return value;
}

int IntFromNumber(JNIEnv* env, jobject value, int fallback) {
  if (value == nullptr) return fallback;
  JniLocalRef number_class(env, FindClass(env, "java/lang/Number"));
  if (number_class.get() == nullptr ||
      env->IsInstanceOf(value, static_cast<jclass>(number_class.get())) !=
          JNI_TRUE ||
      ClearPendingJniException(env)) {
    return fallback;
  }
  jmethodID int_value = GetMethodID(
      env, static_cast<jclass>(number_class.get()), "intValue", "()I");
  if (int_value == nullptr) return fallback;
  const jint parsed = env->CallIntMethod(value, int_value);
  return ClearPendingJniException(env) ? fallback : parsed;
}

FsvBasisuBudgetNumber BudgetNumberFromMap(JNIEnv* env,
                                         jobject map,
                                         const char* key) {
  if (map == nullptr) {
    return FsvBasisuBudgetNumber();
  }
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  if (map_class.get() == nullptr ||
      env->IsInstanceOf(map, static_cast<jclass>(map_class.get())) != JNI_TRUE ||
      ClearPendingJniException(env)) {
    return FsvBasisuBudgetNumber::Invalid();
  }
  JniLocalRef value(env, MapGet(env, map, key));
  if (value.get() == nullptr) {
    return FsvBasisuBudgetNumber();
  }
  JniLocalRef integer_class(env, FindClass(env, "java/lang/Integer"));
  JniLocalRef long_class(env, FindClass(env, "java/lang/Long"));
  if ((env->IsInstanceOf(value.get(),
                         static_cast<jclass>(integer_class.get())) != JNI_TRUE &&
       env->IsInstanceOf(value.get(),
                         static_cast<jclass>(long_class.get())) != JNI_TRUE) ||
      ClearPendingJniException(env)) {
    return FsvBasisuBudgetNumber::Invalid();
  }
  JniLocalRef number_class(env, FindClass(env, "java/lang/Number"));
  jmethodID long_value = GetMethodID(
      env, static_cast<jclass>(number_class.get()), "longValue", "()J");
  if (long_value == nullptr) return FsvBasisuBudgetNumber::Invalid();
  const jlong parsed = env->CallLongMethod(value.get(), long_value);
  if (ClearPendingJniException(env)) return FsvBasisuBudgetNumber::Invalid();
  return FsvBasisuBudgetNumber::Integer(static_cast<int64_t>(parsed));
}

FsvBasisuDecodeBudgetMetadata BudgetFromJavaMap(JNIEnv* env, jobject map) {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes =
      BudgetNumberFromMap(env, map, "maxTotalDecodedBytes");
  budget.max_texture_pixels =
      BudgetNumberFromMap(env, map, "maxTexturePixels");
  budget.max_native_output_bytes =
      BudgetNumberFromMap(env, map, "maxNativeOutputBytes");
  budget.max_native_working_bytes =
      BudgetNumberFromMap(env, map, "maxNativeWorkingBytes");
  return budget;
}

FsvBasisuDecodeBudgetState StateFromJavaMap(JNIEnv* env, jobject map) {
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes =
      BudgetNumberFromMap(env, map, "totalDecodedBytes");
  state.texture_pixels = BudgetNumberFromMap(env, map, "texturePixels");
  state.native_output_bytes =
      BudgetNumberFromMap(env, map, "nativeOutputBytes");
  return state;
}

FsvBasisuString StringFromValue(
    JNIEnv* env, jobject value,
    fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuString result{FsvBasisuAllocator<char>(control)};
  if (value == nullptr) return result;
  JniLocalRef string_class(env, FindClass(env, "java/lang/String"));
  if (string_class.get() == nullptr ||
      env->IsInstanceOf(value, static_cast<jclass>(string_class.get())) !=
          JNI_TRUE ||
      ClearPendingJniException(env)) {
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
  struct ReleaseUtfChars final {
    JNIEnv* env;
    jstring value;
    const char* chars;
    ~ReleaseUtfChars() { env->ReleaseStringUTFChars(value, chars); }
  } release{env, static_cast<jstring>(value), chars};
  result.assign(chars);
  return result;
}

bool BytesFromValue(JNIEnv* env,
                    jobject value,
                    FsvBasisuByteVector* bytes) {
  if (value == nullptr) {
    return false;
  }
  JniLocalRef byte_array_class(env, FindClass(env, "[B"));
  if (byte_array_class.get() == nullptr ||
      env->IsInstanceOf(value, static_cast<jclass>(byte_array_class.get())) !=
          JNI_TRUE ||
      ClearPendingJniException(env)) {
    return false;
  }
  jsize length = env->GetArrayLength(static_cast<jarray>(value));
  if (ClearPendingJniException(env) || length < 0) return false;
  if (length <= 0) {
    bytes->clear();
    return true;
  }
  bytes->resize(static_cast<size_t>(length));
  env->GetByteArrayRegion(static_cast<jbyteArray>(value), 0, length,
                          reinterpret_cast<jbyte*>(bytes->data()));
  if (ClearPendingJniException(env)) {
    bytes->clear();
    return false;
  }
  return true;
}

FsvBasisuImageRequests RequestsFromJavaList(
    JNIEnv* env, jobject images,
    fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuImageRequests requests{
      FsvBasisuAllocator<FsvBasisuImageRequest>(control)};
  if (images == nullptr) {
    return requests;
  }
  JniLocalRef list_class(env, FindClass(env, "java/util/List"));
  if (list_class.get() == nullptr ||
      env->IsInstanceOf(images, static_cast<jclass>(list_class.get())) !=
          JNI_TRUE ||
      ClearPendingJniException(env)) {
    return requests;
  }
  jmethodID size_method = GetMethodID(
      env, static_cast<jclass>(list_class.get()), "size", "()I");
  jmethodID get_method = GetMethodID(
      env, static_cast<jclass>(list_class.get()), "get",
      "(I)Ljava/lang/Object;");
  JniLocalRef map_class(env, FindClass(env, "java/util/Map"));
  if (size_method == nullptr || get_method == nullptr ||
      map_class.get() == nullptr) {
    return requests;
  }
  const jint size = env->CallIntMethod(images, size_method);
  if (ClearPendingJniException(env) || size < 0) return requests;
  requests.reserve(static_cast<size_t>(size));
  for (jint index = 0; index < size; index += 1) {
    JniLocalRef image(
        env, env->CallObjectMethod(images, get_method, index));
    if (ClearPendingJniException(env)) return FsvBasisuImageRequests{
        FsvBasisuAllocator<FsvBasisuImageRequest>(control)};
    FsvBasisuImageRequest request(control);
    if (image.get() == nullptr ||
        env->IsInstanceOf(image.get(),
                          static_cast<jclass>(map_class.get())) != JNI_TRUE ||
        ClearPendingJniException(env)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages";
      requests.push_back(std::move(request));
      continue;
    }
    JniLocalRef texture_index(env, MapGet(env, image.get(), "textureIndex"));
    request.texture_index = IntFromNumber(env, texture_index.get(), -1);
    JniLocalRef image_index(env, MapGet(env, image.get(), "imageIndex"));
    request.image_index = IntFromNumber(env, image_index.get(), -1);
    JniLocalRef usage_role(env, MapGet(env, image.get(), "usageRole"));
    if (!FsvBasisuUsageRoleFromString(
            StringFromValue(env, usage_role.get(), control),
                                      &request.usage_role)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.usageRole";
    }
    JniLocalRef channel_layout(
        env, MapGet(env, image.get(), "channelLayout"));
    if (!FsvBasisuChannelLayoutFromString(
            StringFromValue(env, channel_layout.get(), control),
            &request.channel_layout)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.channelLayout";
    }
    JniLocalRef mime_type(env, MapGet(env, image.get(), "mimeType"));
    request.mime_type = StringFromValue(env, mime_type.get(), control);
    JniLocalRef bytes(env, MapGet(env, image.get(), "bytes"));
    if (!BytesFromValue(env, bytes.get(), &request.bytes)) {
      request.metadata_valid = false;
      request.metadata_field = "basisuImages.bytes";
    }
    requests.push_back(std::move(request));
  }
  return requests;
}

jobject DiagnosticToJava(JNIEnv* env, const FsvBasisuDiagnostic& diagnostic,
                         jstring source) {
  JniLocalRef details(env, NewHashMap(env));
  bool valid = details.get() != nullptr &&
               MapPutString(env, details.get(), "extension", kBasisuExtension) &&
               MapPutString(env, details.get(), "decoder", "basisu") &&
               MapPutBool(env, details.get(), "required", true) &&
               MapPutString(env, details.get(), "status", diagnostic.status) &&
               MapPutString(env, details.get(), "stage", diagnostic.stage) &&
               MapPutString(env, details.get(), "field", diagnostic.field) &&
               MapPutString(
                   env, details.get(), "limitation",
                   diagnostic.status == "budgetExceeded"
                       ? "decodeBudget"
                       : "decodedPayloadSchema") &&
               MapPutString(env, details.get(), "pluginPackage",
                            "flutter_scene_viewer_basisu") &&
               MapPutString(env, details.get(), "configurationKey",
                            "FlutterSceneViewerBasisuEnabled") &&
               MapPutString(env, details.get(), "androidManifestKey",
                            "flutter_scene_viewer_basisu_enabled");
  if (diagnostic.texture_index >= 0) {
    valid = valid && MapPutInt(env, details.get(), "textureIndex",
                               diagnostic.texture_index);
  }
  if (diagnostic.image_index >= 0) {
    valid = valid && MapPutInt(env, details.get(), "imageIndex",
                               diagnostic.image_index);
  }
  if (diagnostic.has_limit) {
    valid = valid && MapPutLong(env, details.get(), "limit", diagnostic.limit);
  }
  if (diagnostic.has_actual) {
    valid = valid &&
            MapPutLong(env, details.get(), "actual", diagnostic.actual);
  }
  if (source != nullptr) {
    valid = valid && MapPut(env, details.get(), "source", source);
  }
  if (!valid) return nullptr;

  JniLocalRef result(env, NewHashMap(env));
  valid = result.get() != nullptr &&
          MapPutString(env, result.get(), "code", "unsupportedModelFeature") &&
          MapPutString(env, result.get(), "message", diagnostic.message) &&
          MapPut(env, result.get(), "details", details.get());
  return valid ? result.release() : nullptr;
}

struct JniByteArrayCopyContext {
  JNIEnv* env = nullptr;
};

bool AllocateJniByteArray(void* raw_context, uint64_t bytes,
                          void** destination) noexcept {
  auto* context = static_cast<JniByteArrayCopyContext*>(raw_context);
  jbyteArray array = context->env->NewByteArray(static_cast<jsize>(bytes));
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
    if (ClearPendingJniException(context->env)) return false;
  }
  return true;
}

void ReleaseJniByteArray(void* raw_context, void* destination) noexcept {
  static_cast<JniByteArrayCopyContext*>(raw_context)
      ->env->DeleteLocalRef(static_cast<jbyteArray>(destination));
}

jbyteArray ByteArray(JNIEnv* env, const FsvBasisuByteVector& bytes,
                     fsv_basisu::FsvDecodeControl* control,
                     FsvBasisuPlatformCopyOutcome* outcome) {
  JniByteArrayCopyContext context{env};
  FsvBasisuPlatformCopyCallbacks callbacks;
  callbacks.context = &context;
  callbacks.allocate = AllocateJniByteArray;
  callbacks.copy = CopyJniByteArray;
  callbacks.release = ReleaseJniByteArray;
  void* destination = nullptr;
  *outcome = FsvBasisuCopyBytesToPlatform(
      bytes.data(), bytes.size(),
      static_cast<uint64_t>(std::numeric_limits<jsize>::max()), control,
      callbacks, &destination);
  return static_cast<jbyteArray>(destination);
}

jobject TerminalDiagnosticToJava(
    JNIEnv* env, FsvBasisuTerminalOutcomeKind terminal, jstring source) {
  const bool budget =
      terminal == FsvBasisuTerminalOutcomeKind::kBudgetExceeded;
  if (!budget &&
      terminal != FsvBasisuTerminalOutcomeKind::kAllocationFailed) {
    return nullptr;
  }
  JniLocalRef details(env, NewHashMap(env));
  bool valid = details.get() != nullptr &&
               MapPutString(env, details.get(), "extension", kBasisuExtension) &&
               MapPutString(env, details.get(), "decoder", "basisu") &&
               MapPutBool(env, details.get(), "required", true) &&
               MapPutString(env, details.get(), "status",
                            budget ? "budgetExceeded" : "allocationFailed") &&
               MapPutString(env, details.get(), "stage",
                            "basisuWorkingAllocation") &&
               MapPutString(env, details.get(), "field",
                            "nativeWorkingBytes") &&
               MapPutString(env, details.get(), "limitation",
                            budget ? "decodeBudget"
                                   : "decodedPayloadSchema") &&
               MapPutString(env, details.get(), "pluginPackage",
                            "flutter_scene_viewer_basisu") &&
               MapPutString(env, details.get(), "configurationKey",
                            "FlutterSceneViewerBasisuEnabled") &&
               MapPutString(env, details.get(), "androidManifestKey",
                            "flutter_scene_viewer_basisu_enabled");
  if (source != nullptr) {
    valid = valid && MapPut(env, details.get(), "source", source);
  }
  if (!valid) return nullptr;
  JniLocalRef result(env, NewHashMap(env));
  valid = result.get() != nullptr &&
          MapPutString(env, result.get(), "code", "unsupportedModelFeature") &&
          MapPutString(
              env, result.get(), "message",
              budget
                  ? "Native BasisU decode exceeded maxNativeWorkingBytes."
                  : "Native BasisU decode allocation failed.") &&
          MapPut(env, result.get(), "details", details.get());
  return valid ? result.release() : nullptr;
}

jobject ResultToJava(JNIEnv* env, const FsvBasisuTranscodeResult& result,
                     jstring source,
                     fsv_basisu::FsvDecodeControl* control) {
  JniLocalRef decoded_images(env, NewArrayList(env));
  if (decoded_images.get() == nullptr) return nullptr;
  for (const FsvBasisuDecodedImage& image : result.decoded_images) {
    if (control != nullptr && control->IsCancelled()) return nullptr;
    JniLocalRef image_map(env, NewHashMap(env));
    JniLocalRef levels(env, NewArrayList(env));
    if (image_map.get() == nullptr || levels.get() == nullptr ||
        !MapPutInt(env, image_map.get(), "imageIndex", image.image_index) ||
        !MapPutString(env, image_map.get(), "contentRole",
                      image.content_role)) {
      return nullptr;
    }
    for (const FsvBasisuDecodedMipLevel& level : image.levels) {
      JniLocalRef level_map(env, NewHashMap(env));
      FsvBasisuPlatformCopyOutcome outcome;
      JniLocalRef array(env, ByteArray(env, level.rgba_bytes, control,
                                       &outcome));
      if (level_map.get() == nullptr ||
          outcome != FsvBasisuPlatformCopyOutcome::kSuccess ||
          array.get() == nullptr ||
          !MapPutLong(env, level_map.get(), "level", level.level) ||
          !MapPutLong(env, level_map.get(), "width", level.width) ||
          !MapPutLong(env, level_map.get(), "height", level.height) ||
          !MapPut(env, level_map.get(), "rgbaBytes", array.get()) ||
          !ListAdd(env, levels.get(), level_map.get())) {
        return nullptr;
      }
    }
    if (!MapPut(env, image_map.get(), "levels", levels.get()) ||
        !ListAdd(env, decoded_images.get(), image_map.get())) {
      return nullptr;
    }
  }

  JniLocalRef diagnostics(env, NewArrayList(env));
  if (diagnostics.get() == nullptr) return nullptr;
  for (const FsvBasisuDiagnostic& diagnostic : result.diagnostics) {
    JniLocalRef diagnostic_map(env, DiagnosticToJava(env, diagnostic, source));
    if (diagnostic_map.get() == nullptr ||
        !ListAdd(env, diagnostics.get(), diagnostic_map.get())) {
      return nullptr;
    }
  }
  const bool needs_terminal =
      result.terminal_outcome ==
          FsvBasisuTerminalOutcomeKind::kBudgetExceeded ||
      result.terminal_outcome ==
          FsvBasisuTerminalOutcomeKind::kAllocationFailed;
  JniLocalRef terminal(
      env, TerminalDiagnosticToJava(env, result.terminal_outcome, source));
  if (needs_terminal &&
      (terminal.get() == nullptr ||
       !ListAdd(env, diagnostics.get(), terminal.get()))) {
    return nullptr;
  }

  JniLocalRef response(env, NewHashMap(env));
  if (response.get() == nullptr ||
      !MapPut(env, response.get(), "decodedImages", decoded_images.get()) ||
      !MapPut(env, response.get(), "diagnostics", diagnostics.get()) ||
      (control != nullptr && control->IsCancelled())) {
    return nullptr;
  }
  return response.release();
}
}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeTranscoderLinked(
    JNIEnv* env,
    jclass clazz) {
  (void)env;
  (void)clazz;
  return FsvBasisuTranscoderLinked() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeImageTranscodeAvailable(
    JNIEnv* env,
    jclass clazz) {
  (void)env;
  (void)clazz;
  return FsvBasisuImageTranscodeAvailable() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeCreateDecodeControl(
    JNIEnv* env, jclass clazz, jlong working_byte_limit) {
  (void)env;
  (void)clazz;
  const uint64_t limit = working_byte_limit < 0
                             ? 0
                             : static_cast<uint64_t>(working_byte_limit);
  return reinterpret_cast<jlong>(
      new (std::nothrow) fsv_basisu::FsvDecodeControl(limit));
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeCancelDecodeControl(
    JNIEnv* env, jclass clazz, jlong handle) {
  (void)env;
  (void)clazz;
  auto* control = reinterpret_cast<fsv_basisu::FsvDecodeControl*>(handle);
  return control != nullptr && control->Cancel() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeDestroyDecodeControl(
    JNIEnv* env, jclass clazz, jlong handle) {
  (void)env;
  (void)clazz;
  delete reinterpret_cast<fsv_basisu::FsvDecodeControl*>(handle);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeTranscodeImages(
    JNIEnv* env,
    jclass clazz,
    jobject basisu_images,
    jobject decode_budget,
    jobject decode_budget_state,
    jstring source,
    jlong control_handle) {
  (void)clazz;
  auto* control = reinterpret_cast<fsv_basisu::FsvDecodeControl*>(
      control_handle);
  if (control == nullptr) return nullptr;
  FsvBasisuTranscodeResult result(control);
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
  try {
#endif
    FsvBasisuImageRequests requests =
        RequestsFromJavaList(env, basisu_images, control);
    result = FsvBasisuTranscodeImages(
        requests, BudgetFromJavaMap(env, decode_budget),
        StateFromJavaMap(env, decode_budget_state), control);
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
  } catch (const std::bad_alloc&) {
    FsvBasisuRecordTerminalOutcome(&result, control);
  }
#endif
  if (control->IsCancelled()) return nullptr;
  return ResultToJava(env, result, source, control);
}
