#include <jni.h>

#include <string>
#include <utility>
#include <vector>

#include "fsv_basisu_bridge.h"

namespace {
constexpr const char* kBasisuExtension = "KHR_texture_basisu";

jobject NewHashMap(JNIEnv* env) {
  jclass map_class = env->FindClass("java/util/HashMap");
  jmethodID constructor = env->GetMethodID(map_class, "<init>", "()V");
  return env->NewObject(map_class, constructor);
}

jobject NewArrayList(JNIEnv* env) {
  jclass list_class = env->FindClass("java/util/ArrayList");
  jmethodID constructor = env->GetMethodID(list_class, "<init>", "()V");
  return env->NewObject(list_class, constructor);
}

jobject IntegerValue(JNIEnv* env, jint value) {
  jclass integer_class = env->FindClass("java/lang/Integer");
  jmethodID value_of = env->GetStaticMethodID(
      integer_class, "valueOf", "(I)Ljava/lang/Integer;");
  return env->CallStaticObjectMethod(integer_class, value_of, value);
}

jobject BooleanValue(JNIEnv* env, bool value) {
  jclass boolean_class = env->FindClass("java/lang/Boolean");
  jmethodID value_of = env->GetStaticMethodID(
      boolean_class, "valueOf", "(Z)Ljava/lang/Boolean;");
  return env->CallStaticObjectMethod(boolean_class, value_of,
                                     value ? JNI_TRUE : JNI_FALSE);
}

void ListAdd(JNIEnv* env, jobject list, jobject value) {
  jclass list_class = env->FindClass("java/util/List");
  jmethodID add = env->GetMethodID(list_class, "add", "(Ljava/lang/Object;)Z");
  env->CallBooleanMethod(list, add, value);
}

void MapPut(JNIEnv* env, jobject map, const char* key, jobject value) {
  jclass map_class = env->FindClass("java/util/Map");
  jmethodID put = env->GetMethodID(
      map_class, "put",
      "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
  jstring key_object = env->NewStringUTF(key);
  env->CallObjectMethod(map, put, key_object, value);
  env->DeleteLocalRef(key_object);
}

void MapPutString(JNIEnv* env, jobject map, const char* key,
                  const std::string& value) {
  jstring string_value = env->NewStringUTF(value.c_str());
  MapPut(env, map, key, string_value);
  env->DeleteLocalRef(string_value);
}

void MapPutInt(JNIEnv* env, jobject map, const char* key, int value) {
  jobject integer_value = IntegerValue(env, static_cast<jint>(value));
  MapPut(env, map, key, integer_value);
  env->DeleteLocalRef(integer_value);
}

void MapPutBool(JNIEnv* env, jobject map, const char* key, bool value) {
  jobject boolean_value = BooleanValue(env, value);
  MapPut(env, map, key, boolean_value);
  env->DeleteLocalRef(boolean_value);
}

void MapPutBytes(JNIEnv* env, jobject map, const char* key,
                 const std::vector<uint8_t>& value) {
  jbyteArray array = env->NewByteArray(static_cast<jsize>(value.size()));
  if (!value.empty()) {
    env->SetByteArrayRegion(
        array, 0, static_cast<jsize>(value.size()),
        reinterpret_cast<const jbyte*>(value.data()));
  }
  MapPut(env, map, key, array);
  env->DeleteLocalRef(array);
}

jobject MapGet(JNIEnv* env, jobject map, const char* key) {
  jclass map_class = env->FindClass("java/util/Map");
  jmethodID get = env->GetMethodID(
      map_class, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
  jstring key_object = env->NewStringUTF(key);
  jobject value = env->CallObjectMethod(map, get, key_object);
  env->DeleteLocalRef(key_object);
  return value;
}

int IntFromNumber(JNIEnv* env, jobject value, int fallback) {
  if (value == nullptr) {
    return fallback;
  }
  jclass number_class = env->FindClass("java/lang/Number");
  if (!env->IsInstanceOf(value, number_class)) {
    return fallback;
  }
  jmethodID int_value = env->GetMethodID(number_class, "intValue", "()I");
  return env->CallIntMethod(value, int_value);
}

std::string StringFromValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return "";
  }
  jclass string_class = env->FindClass("java/lang/String");
  if (!env->IsInstanceOf(value, string_class)) {
    return "";
  }
  const char* chars = env->GetStringUTFChars(static_cast<jstring>(value),
                                             nullptr);
  if (chars == nullptr) {
    return "";
  }
  std::string result(chars);
  env->ReleaseStringUTFChars(static_cast<jstring>(value), chars);
  return result;
}

std::vector<uint8_t> BytesFromValue(JNIEnv* env, jobject value) {
  if (value == nullptr) {
    return {};
  }
  jsize length = env->GetArrayLength(static_cast<jarray>(value));
  if (length <= 0) {
    return {};
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(length));
  env->GetByteArrayRegion(static_cast<jbyteArray>(value), 0, length,
                          reinterpret_cast<jbyte*>(bytes.data()));
  return bytes;
}

std::vector<FsvBasisuImageRequest> RequestsFromJavaList(JNIEnv* env,
                                                        jobject images) {
  std::vector<FsvBasisuImageRequest> requests;
  if (images == nullptr) {
    return requests;
  }
  jclass list_class = env->FindClass("java/util/List");
  if (!env->IsInstanceOf(images, list_class)) {
    return requests;
  }
  jmethodID size_method = env->GetMethodID(list_class, "size", "()I");
  jmethodID get_method =
      env->GetMethodID(list_class, "get", "(I)Ljava/lang/Object;");
  const jint size = env->CallIntMethod(images, size_method);
  requests.reserve(static_cast<size_t>(size));
  for (jint index = 0; index < size; index += 1) {
    jobject image = env->CallObjectMethod(images, get_method, index);
    if (image == nullptr) {
      continue;
    }
    FsvBasisuImageRequest request;
    request.texture_index =
        IntFromNumber(env, MapGet(env, image, "textureIndex"), -1);
    request.image_index = IntFromNumber(env, MapGet(env, image, "imageIndex"),
                                        -1);
    request.mime_type = StringFromValue(env, MapGet(env, image, "mimeType"));
    request.bytes = BytesFromValue(env, MapGet(env, image, "bytes"));
    requests.push_back(std::move(request));
    env->DeleteLocalRef(image);
  }
  return requests;
}

jobject DiagnosticToJava(JNIEnv* env, const FsvBasisuDiagnostic& diagnostic,
                         const std::string& source) {
  jobject details = NewHashMap(env);
  MapPutString(env, details, "extension", kBasisuExtension);
  MapPutString(env, details, "decoder", "basisu");
  MapPutBool(env, details, "required", true);
  MapPutString(env, details, "status", diagnostic.status);
  MapPutString(env, details, "pluginPackage", "flutter_scene_viewer_basisu");
  MapPutString(env, details, "configurationKey",
               "FlutterSceneViewerBasisuEnabled");
  MapPutString(env, details, "androidManifestKey",
               "flutter_scene_viewer_basisu_enabled");
  if (diagnostic.texture_index >= 0) {
    MapPutInt(env, details, "textureIndex", diagnostic.texture_index);
  }
  if (diagnostic.image_index >= 0) {
    MapPutInt(env, details, "imageIndex", diagnostic.image_index);
  }
  if (!source.empty()) {
    MapPutString(env, details, "source", source);
  }

  jobject result = NewHashMap(env);
  MapPutString(env, result, "code", "unsupportedModelFeature");
  MapPutString(env, result, "message", diagnostic.message);
  MapPut(env, result, "details", details);
  env->DeleteLocalRef(details);
  return result;
}

jobject ResultToJava(JNIEnv* env, const FsvBasisuTranscodeResult& result,
                     const std::string& source) {
  jobject decoded_images = NewArrayList(env);
  for (const FsvBasisuDecodedImage& image : result.decoded_images) {
    jobject image_map = NewHashMap(env);
    MapPutInt(env, image_map, "imageIndex", image.image_index);
    MapPutString(env, image_map, "mimeType", image.mime_type);
    MapPutBytes(env, image_map, "bytes", image.bytes);
    ListAdd(env, decoded_images, image_map);
    env->DeleteLocalRef(image_map);
  }

  jobject diagnostics = NewArrayList(env);
  for (const FsvBasisuDiagnostic& diagnostic : result.diagnostics) {
    jobject diagnostic_map = DiagnosticToJava(env, diagnostic, source);
    ListAdd(env, diagnostics, diagnostic_map);
    env->DeleteLocalRef(diagnostic_map);
  }

  jobject response = NewHashMap(env);
  MapPut(env, response, "decodedImages", decoded_images);
  MapPut(env, response, "diagnostics", diagnostics);
  env->DeleteLocalRef(decoded_images);
  env->DeleteLocalRef(diagnostics);
  return response;
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

extern "C" JNIEXPORT jobject JNICALL
Java_com_marlonjd_flutter_1scene_1viewer_1basisu_FlutterSceneViewerBasisuPlugin_nativeTranscodeImages(
    JNIEnv* env,
    jclass clazz,
    jobject basisu_images,
    jstring source) {
  (void)clazz;
  const std::string source_string = StringFromValue(env, source);
  return ResultToJava(env,
                      FsvBasisuTranscodeImages(
                          RequestsFromJavaList(env, basisu_images)),
                      source_string);
}
