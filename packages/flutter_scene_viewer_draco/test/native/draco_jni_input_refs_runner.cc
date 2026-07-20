#include <cstddef>
#include <cstdint>
#include <iostream>

#include "../../android/src/main/cpp/flutter_scene_viewer_draco_jni.cc"

namespace {

enum class Mode { kSuccess, kMapGetException, kForEachException };

constexpr int kEntries = 2048;
constexpr int kExceptionEntry = 731;

Mode mode = Mode::kSuccess;
bool exception_pending = false;
int calls_after_exception = 0;
int live_local_refs = 0;
int peak_local_refs = 0;
int next_index = 0;
int callbacks = 0;

_jobject fake_map;
_jobject fake_class;
_jobject fake_string;
_jobject fake_value;
_jobject fake_set;
_jobject fake_iterator;
_jobject fake_entry;

int map_get_id;
int entry_set_id;
int iterator_id;
int has_next_id;
int next_id;
int key_id;
int value_id;
int other_id;

void NewLocal() {
  ++live_local_refs;
  if (live_local_refs > peak_local_refs) peak_local_refs = live_local_refs;
}

void Reset(Mode next) {
  mode = next;
  exception_pending = false;
  calls_after_exception = 0;
  live_local_refs = 0;
  peak_local_refs = 0;
  next_index = 0;
  callbacks = 0;
}

int Fail(int line) {
  std::cerr << "failure at line " << line << " mode="
            << static_cast<int>(mode) << " live=" << live_local_refs
            << " peak=" << peak_local_refs << " callbacks=" << callbacks
            << " calls_after_exception=" << calls_after_exception << "\n";
  return line;
}

}  // namespace

jclass JNIEnv::FindClass(const char*) {
  if (exception_pending) ++calls_after_exception;
  NewLocal();
  return &fake_class;
}
jmethodID JNIEnv::GetMethodID(jclass, const char* name, const char*) {
  if (exception_pending) ++calls_after_exception;
  if (std::strcmp(name, "get") == 0) {
    return &map_get_id;
  }
  if (std::strcmp(name, "entrySet") == 0) return &entry_set_id;
  if (std::strcmp(name, "iterator") == 0) return &iterator_id;
  if (std::strcmp(name, "hasNext") == 0) return &has_next_id;
  if (std::strcmp(name, "next") == 0) return &next_id;
  if (std::strcmp(name, "getKey") == 0) return &key_id;
  if (std::strcmp(name, "getValue") == 0) return &value_id;
  return &other_id;
}
jboolean JNIEnv::IsInstanceOf(jobject, jclass) {
  if (exception_pending) ++calls_after_exception;
  return JNI_TRUE;
}
jobject JNIEnv::NewObject(jclass, jmethodID, ...) { return nullptr; }
jstring JNIEnv::NewStringUTF(const char*) {
  if (exception_pending) ++calls_after_exception;
  NewLocal();
  return &fake_string;
}
jobject JNIEnv::CallObjectMethod(jobject, jmethodID method, ...) {
  if (exception_pending) ++calls_after_exception;
  if (method == &map_get_id) {
    NewLocal();
    if (mode == Mode::kMapGetException) exception_pending = true;
    return &fake_value;
  }
  if (method == &entry_set_id) {
    NewLocal();
    return &fake_set;
  }
  if (method == &iterator_id) {
    NewLocal();
    return &fake_iterator;
  }
  if (method == &next_id) {
    NewLocal();
    ++next_index;
    return &fake_entry;
  }
  if (method == &key_id) {
    NewLocal();
    return &fake_string;
  }
  if (method == &value_id) {
    NewLocal();
    if (mode == Mode::kForEachException && next_index == kExceptionEntry) {
      exception_pending = true;
    }
    return &fake_value;
  }
  return nullptr;
}
jint JNIEnv::CallIntMethod(jobject, jmethodID, ...) { return 0; }
jlong JNIEnv::CallLongMethod(jobject, jmethodID, ...) { return 0; }
jboolean JNIEnv::CallBooleanMethod(jobject, jmethodID method, ...) {
  if (exception_pending) ++calls_after_exception;
  if (method == &has_next_id) return next_index < kEntries ? JNI_TRUE : JNI_FALSE;
  return JNI_FALSE;
}
jsize JNIEnv::GetArrayLength(jarray) { return 0; }
void JNIEnv::GetByteArrayRegion(jbyteArray, jsize, jsize, jbyte*) {}
jbyteArray JNIEnv::NewByteArray(jsize) { return nullptr; }
void JNIEnv::SetByteArrayRegion(jbyteArray, jsize, jsize, const jbyte*) {}
const char* JNIEnv::GetStringUTFChars(jstring, jboolean*) { return nullptr; }
void JNIEnv::ReleaseStringUTFChars(jstring, const char*) {}
jboolean JNIEnv::ExceptionCheck() { return exception_pending ? JNI_TRUE : JNI_FALSE; }
void JNIEnv::ExceptionClear() { exception_pending = false; }
void JNIEnv::DeleteLocalRef(jobject value) {
  if (value != nullptr) --live_local_refs;
}

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main() {
  JNIEnv env;

  Reset(Mode::kSuccess);
  for (int index = 0; index < kEntries; ++index) {
    jobject value = MapGet(&env, &fake_map, "field");
    CHECK(value == &fake_value);
    env.DeleteLocalRef(value);
  }
  CHECK(live_local_refs == 0 && peak_local_refs <= 3);

  Reset(Mode::kMapGetException);
  CHECK(MapGet(&env, &fake_map, "field") == nullptr);
  CHECK(!exception_pending && live_local_refs == 0 &&
        calls_after_exception == 0);

  Reset(Mode::kSuccess);
  ForEachMapEntry(&env, &fake_map, [](jobject, jobject) {
    ++callbacks;
    return true;
  });
  CHECK(callbacks == kEntries && live_local_refs == 0 && peak_local_refs <= 9);

  Reset(Mode::kForEachException);
  ForEachMapEntry(&env, &fake_map, [](jobject, jobject) {
    ++callbacks;
    return true;
  });
  CHECK(callbacks == kExceptionEntry - 1 && !exception_pending &&
        live_local_refs == 0 && calls_after_exception == 0);

  std::cout << "jni_input_ref_cases=4 entries=" << kEntries << "\n";
  return 0;
}
