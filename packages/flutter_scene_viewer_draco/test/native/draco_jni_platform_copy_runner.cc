#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>

#include "../../android/src/main/cpp/flutter_scene_viewer_draco_jni.cc"

namespace {

enum class Mode {
  kSuccess,
  kAllocationNull,
  kAllocationException,
  kCopyException,
  kCancelAfterAllocation,
  kCancelAfterCopy,
  kNewStringException,
  kNewObjectException,
  kMapPutException,
  kListAddException,
};

Mode mode = Mode::kSuccess;
bool exception_pending = false;
int byte_array_allocations = 0;
int byte_array_copies = 0;
int local_ref_releases = 0;
int class_ref_releases = 0;
int object_ref_releases = 0;
int string_ref_releases = 0;
int previous_ref_releases = 0;
bool observed_native_charge = false;
fsv_draco::FsvDecodeControl* active_control = nullptr;
_jobject fake_array;
_jobject fake_class;
_jobject fake_object;
_jobject fake_string;
_jobject fake_previous;
_jobject fake_map;
_jobject fake_list;

void Reset(Mode next, fsv_draco::FsvDecodeControl* control) {
  mode = next;
  exception_pending = false;
  byte_array_allocations = 0;
  byte_array_copies = 0;
  local_ref_releases = 0;
  class_ref_releases = 0;
  object_ref_releases = 0;
  string_ref_releases = 0;
  previous_ref_releases = 0;
  observed_native_charge = false;
  active_control = control;
}

int Fail(int line) {
  std::cerr << "failure at line " << line << " mode="
            << static_cast<int>(mode) << " allocations="
            << byte_array_allocations << " copies=" << byte_array_copies
            << " releases=" << local_ref_releases << "\n";
  return line;
}

}  // namespace

jclass JNIEnv::FindClass(const char*) { return &fake_class; }
jmethodID JNIEnv::GetMethodID(jclass, const char*, const char*) {
  return reinterpret_cast<jmethodID>(1);
}
jboolean JNIEnv::IsInstanceOf(jobject, jclass) { return JNI_FALSE; }
jobject JNIEnv::NewObject(jclass, jmethodID, ...) {
  if (mode == Mode::kNewObjectException) exception_pending = true;
  return &fake_object;
}
jstring JNIEnv::NewStringUTF(const char*) {
  if (mode == Mode::kNewStringException) exception_pending = true;
  return &fake_string;
}
jobject JNIEnv::CallObjectMethod(jobject, jmethodID, ...) {
  if (mode == Mode::kMapPutException) {
    exception_pending = true;
    return &fake_previous;
  }
  return nullptr;
}
jint JNIEnv::CallIntMethod(jobject, jmethodID, ...) { return 0; }
jlong JNIEnv::CallLongMethod(jobject, jmethodID, ...) { return 0; }
jboolean JNIEnv::CallBooleanMethod(jobject, jmethodID, ...) {
  if (mode == Mode::kListAddException) exception_pending = true;
  return JNI_TRUE;
}
jsize JNIEnv::GetArrayLength(jarray) { return 0; }
void JNIEnv::GetByteArrayRegion(jbyteArray, jsize, jsize, jbyte*) {}
jbyteArray JNIEnv::NewByteArray(jsize) {
  ++byte_array_allocations;
  if (mode == Mode::kAllocationNull) return nullptr;
  if (mode == Mode::kAllocationException) exception_pending = true;
  if (mode == Mode::kCancelAfterAllocation) active_control->Cancel();
  return &fake_array;
}
void JNIEnv::SetByteArrayRegion(jbyteArray,
                                jsize,
                                jsize,
                                const jbyte*) {
  ++byte_array_copies;
  observed_native_charge = active_control != nullptr &&
                           active_control->live_bytes() != 0;
  if (mode == Mode::kCopyException) exception_pending = true;
  if (mode == Mode::kCancelAfterCopy) active_control->Cancel();
}
const char* JNIEnv::GetStringUTFChars(jstring, jboolean*) { return nullptr; }
void JNIEnv::ReleaseStringUTFChars(jstring, const char*) {}
jboolean JNIEnv::ExceptionCheck() {
  return exception_pending ? JNI_TRUE : JNI_FALSE;
}
void JNIEnv::ExceptionClear() { exception_pending = false; }
void JNIEnv::DeleteLocalRef(jobject value) {
  if (value == &fake_array) ++local_ref_releases;
  if (value == &fake_class) ++class_ref_releases;
  if (value == &fake_object) ++object_ref_releases;
  if (value == &fake_string) ++string_ref_releases;
  if (value == &fake_previous) ++previous_ref_releases;
}

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main() {
  JNIEnv env;
  for (const Mode current : {Mode::kSuccess, Mode::kAllocationNull,
                             Mode::kAllocationException, Mode::kCopyException,
                             Mode::kCancelAfterAllocation,
                             Mode::kCancelAfterCopy}) {
    fsv_draco::FsvDecodeControl control(1024);
    FsvDracoByteVector payload{FsvDracoAllocator<uint8_t>(&control)};
    payload.assign(32, 0x5a);
    Reset(current, &control);
    FsvDracoPlatformCopyOutcome outcome;
    jbyteArray result = ByteArray(&env, payload, &control, &outcome);
    if (current == Mode::kSuccess) {
      CHECK(outcome == FsvDracoPlatformCopyOutcome::kSuccess);
      CHECK(result == &fake_array && byte_array_allocations == 1 &&
            byte_array_copies == 1 && local_ref_releases == 0 &&
            observed_native_charge);
      env.DeleteLocalRef(result);
      CHECK(local_ref_releases == 1);
    } else if (current == Mode::kAllocationNull) {
      CHECK(outcome == FsvDracoPlatformCopyOutcome::kAllocationFailed);
      CHECK(result == nullptr && local_ref_releases == 0);
    } else if (current == Mode::kAllocationException) {
      CHECK(outcome == FsvDracoPlatformCopyOutcome::kAllocationFailed);
      CHECK(result == nullptr && local_ref_releases == 1 && !exception_pending);
    } else if (current == Mode::kCopyException) {
      CHECK(outcome == FsvDracoPlatformCopyOutcome::kCopyFailed);
      CHECK(result == nullptr && local_ref_releases == 1 && !exception_pending);
    } else {
      CHECK(outcome == FsvDracoPlatformCopyOutcome::kStopped);
      CHECK(result == nullptr && local_ref_releases == 1);
    }
  }

  Reset(Mode::kNewStringException, nullptr);
  CHECK(!MapPutString(&env, &fake_map, "key", "value"));
  CHECK(!exception_pending && string_ref_releases == 1);

  Reset(Mode::kNewObjectException, nullptr);
  CHECK(NewHashMap(&env) == nullptr);
  CHECK(!exception_pending && class_ref_releases == 1 &&
        object_ref_releases == 1);

  Reset(Mode::kMapPutException, nullptr);
  CHECK(!MapPutString(&env, &fake_map, "key", "value"));
  CHECK(!exception_pending && class_ref_releases == 1 &&
        string_ref_releases == 2 && previous_ref_releases == 1);

  Reset(Mode::kListAddException, nullptr);
  CHECK(!ListAdd(&env, &fake_list, &fake_object));
  CHECK(!exception_pending && class_ref_releases == 1);

  std::cout << "jni_platform_copy_cases=10\n";
  return 0;
}
