#include <cstddef>
#include <cstdint>
#include <iostream>
#include <new>

#include "../../android/src/main/cpp/flutter_scene_viewer_draco_jni.cc"

namespace {

int releases = 0;

class AlwaysFailHeap final : public fsv_draco::FsvDecodeHeap {
 public:
  void* Allocate(size_t, size_t) noexcept override { return nullptr; }
  void Release(void*, size_t, size_t) noexcept override {}
};

}  // namespace

jclass JNIEnv::FindClass(const char*) { return nullptr; }
jmethodID JNIEnv::GetMethodID(jclass, const char*, const char*) {
  return nullptr;
}
jboolean JNIEnv::IsInstanceOf(jobject, jclass) { return JNI_FALSE; }
jobject JNIEnv::NewObject(jclass, jmethodID, ...) { return nullptr; }
jstring JNIEnv::NewStringUTF(const char*) { return nullptr; }
jobject JNIEnv::CallObjectMethod(jobject, jmethodID, ...) { return nullptr; }
jint JNIEnv::CallIntMethod(jobject, jmethodID, ...) { return 0; }
jlong JNIEnv::CallLongMethod(jobject, jmethodID, ...) { return 0; }
jboolean JNIEnv::CallBooleanMethod(jobject, jmethodID, ...) {
  return JNI_FALSE;
}
jsize JNIEnv::GetArrayLength(jarray) { return 0; }
void JNIEnv::GetByteArrayRegion(jbyteArray, jsize, jsize, jbyte*) {}
jbyteArray JNIEnv::NewByteArray(jsize) { return nullptr; }
void JNIEnv::SetByteArrayRegion(jbyteArray, jsize, jsize, const jbyte*) {}
const char* JNIEnv::GetStringUTFChars(jstring, jboolean*) {
  return "this request-controlled JNI string is deliberately longer than SSO";
}
void JNIEnv::ReleaseStringUTFChars(jstring, const char*) { releases += 1; }
jboolean JNIEnv::ExceptionCheck() { return JNI_FALSE; }
void JNIEnv::ExceptionClear() {}
void JNIEnv::DeleteLocalRef(jobject) {}

int main() {
  JNIEnv env;
  _jobject value;
  AlwaysFailHeap heap;
  fsv_draco::FsvDecodeControl control(1024 * 1024, &heap);
  bool failed = false;
  try {
    static_cast<void>(StringValue(&env, &value, &control));
  } catch (const std::bad_alloc&) {
    failed = true;
  }
  if (!failed || releases != 1 || control.live_bytes() != 0 ||
      control.stop_reason() !=
          fsv_draco::FsvDecodeStopReason::kAllocationFailure) {
    std::cerr << "failed=" << failed << " releases=" << releases
              << " live=" << control.live_bytes() << "\n";
    return 1;
  }
  std::cout << "jni_utf_releases=" << releases << "\n";
  return 0;
}
