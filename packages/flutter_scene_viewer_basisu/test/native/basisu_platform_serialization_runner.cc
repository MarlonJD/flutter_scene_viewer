#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>

#include "fsv_basisu_owned.h"
#include "fsv_basisu_platform_serialization.h"

namespace {

struct FakePlatform {
  fsv_basisu::FsvDecodeControl* control = nullptr;
  bool fail_allocation = false;
  bool fail_copy = false;
  bool cancel_after_allocation = false;
  bool cancel_during_copy = false;
  bool require_live_charge = false;
  int allocations = 0;
  int copies = 0;
  int releases = 0;
  uint8_t storage[32] = {};
};

bool Allocate(void* context, uint64_t bytes, void** destination) noexcept {
  auto* platform = static_cast<FakePlatform*>(context);
  ++platform->allocations;
  if (platform->fail_allocation || bytes > sizeof(platform->storage)) {
    return false;
  }
  *destination = platform->storage;
  if (platform->cancel_after_allocation) platform->control->Cancel();
  return true;
}

bool Copy(void* context, void* destination, const uint8_t* source,
          uint64_t bytes) noexcept {
  auto* platform = static_cast<FakePlatform*>(context);
  ++platform->copies;
  if ((platform->require_live_charge &&
       platform->control->live_bytes() == 0) ||
      platform->fail_copy) {
    return false;
  }
  std::memcpy(destination, source, static_cast<size_t>(bytes));
  if (platform->cancel_during_copy) platform->control->Cancel();
  return true;
}

void Release(void* context, void*) noexcept {
  ++static_cast<FakePlatform*>(context)->releases;
}

FsvBasisuPlatformCopyCallbacks Callbacks(FakePlatform* platform) {
  FsvBasisuPlatformCopyCallbacks callbacks;
  callbacks.context = platform;
  callbacks.allocate = Allocate;
  callbacks.copy = Copy;
  callbacks.release = Release;
  return callbacks;
}

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

}  // namespace

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main() {
  for (int platform_index = 0; platform_index < 2; ++platform_index) {
    fsv_basisu::FsvDecodeControl control(4096);
    FsvBasisuByteVector payload{FsvBasisuAllocator<uint8_t>(&control)};
    payload.assign({1, 2, 3, 4});
    FakePlatform success{&control};
    success.require_live_charge = true;
    void* managed = nullptr;
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &control,
              Callbacks(&success), &managed) ==
          FsvBasisuPlatformCopyOutcome::kSuccess);
    CHECK(managed == success.storage && success.allocations == 1 &&
          success.copies == 1 && success.releases == 0);

    FakePlatform size{&control};
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(),
              static_cast<uint64_t>(std::numeric_limits<int32_t>::max()) + 1,
              std::numeric_limits<int32_t>::max(), &control, Callbacks(&size),
              &managed) == FsvBasisuPlatformCopyOutcome::kSizeRejected);

    FakePlatform allocation{&control};
    allocation.fail_allocation = true;
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &control,
              Callbacks(&allocation), &managed) ==
          FsvBasisuPlatformCopyOutcome::kAllocationFailed);

    FakePlatform copy{&control};
    copy.fail_copy = true;
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &control, Callbacks(&copy),
              &managed) == FsvBasisuPlatformCopyOutcome::kCopyFailed);
    CHECK(copy.releases == 1 && managed == nullptr);

    fsv_basisu::FsvDecodeControl before_control(4096);
    before_control.Cancel();
    FakePlatform before{&before_control};
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &before_control,
              Callbacks(&before), &managed) ==
          FsvBasisuPlatformCopyOutcome::kStopped);
    CHECK(before.allocations == 0);

    fsv_basisu::FsvDecodeControl after_allocation_control(4096);
    FakePlatform after_allocation{&after_allocation_control};
    after_allocation.cancel_after_allocation = true;
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &after_allocation_control,
              Callbacks(&after_allocation), &managed) ==
          FsvBasisuPlatformCopyOutcome::kStopped);
    CHECK(after_allocation.copies == 0 && after_allocation.releases == 1);

    fsv_basisu::FsvDecodeControl after_copy_control(4096);
    FakePlatform after_copy{&after_copy_control};
    after_copy.cancel_during_copy = true;
    CHECK(FsvBasisuCopyBytesToPlatform(
              payload.data(), payload.size(),
              std::numeric_limits<int32_t>::max(), &after_copy_control,
              Callbacks(&after_copy), &managed) ==
          FsvBasisuPlatformCopyOutcome::kStopped);
    CHECK(after_copy.copies == 1 && after_copy.releases == 1);
  }
  std::cout << "basisu-platform-copy platforms=2 atomic/charge/failure/cancel\n";
  return 0;
}
