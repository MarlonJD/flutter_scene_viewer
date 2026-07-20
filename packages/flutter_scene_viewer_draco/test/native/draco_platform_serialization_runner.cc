#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>

#include "fsv_draco_platform_serialization.h"

namespace {

struct FakePlatform {
  fsv_draco::FsvDecodeControl* control = nullptr;
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
  if (platform->cancel_after_allocation) {
    platform->control->Cancel();
  }
  return true;
}

bool Copy(void* context,
          void* destination,
          const uint8_t* source,
          uint64_t bytes) noexcept {
  auto* platform = static_cast<FakePlatform*>(context);
  ++platform->copies;
  if (platform->require_live_charge && platform->control->live_bytes() == 0) {
    return false;
  }
  if (platform->fail_copy) {
    return false;
  }
  std::memcpy(destination, source, static_cast<size_t>(bytes));
  if (platform->cancel_during_copy) {
    platform->control->Cancel();
  }
  return true;
}

void Release(void* context, void*) noexcept {
  ++static_cast<FakePlatform*>(context)->releases;
}

FsvDracoPlatformCopyCallbacks Callbacks(FakePlatform* platform) {
  FsvDracoPlatformCopyCallbacks callbacks;
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
  const uint8_t payload[] = {1, 2, 3, 4};

  for (int platform_index = 0; platform_index < 2; ++platform_index) {
    fsv_draco::FsvDecodeControl success_control(32);
    auto allocation = success_control.AllocateMemory(4, alignof(uint8_t));
    CHECK(allocation.allocation != nullptr);
    std::memcpy(allocation.allocation, payload, sizeof(payload));
    FakePlatform success{&success_control};
    success.require_live_charge = true;
    void* managed = nullptr;
    CHECK(FsvDracoCopyBytesToPlatform(
              static_cast<const uint8_t*>(allocation.allocation), 4,
              std::numeric_limits<int32_t>::max(), &success_control,
              Callbacks(&success), &managed) ==
          FsvDracoPlatformCopyOutcome::kSuccess);
    CHECK(managed == success.storage && success.allocations == 1 &&
          success.copies == 1 && success.releases == 0);
    CHECK(std::memcmp(success.storage, payload, sizeof(payload)) == 0);
    CHECK(success_control.ReleaseMemory(&allocation, allocation.allocation, 4,
                                        alignof(uint8_t)));
    CHECK(success_control.live_bytes() == 0);

    fsv_draco::FsvDecodeControl size_control(32);
    FakePlatform size{&size_control};
    managed = reinterpret_cast<void*>(1);
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, static_cast<uint64_t>(std::numeric_limits<int32_t>::max()) + 1,
              std::numeric_limits<int32_t>::max(), &size_control,
              Callbacks(&size), &managed) ==
          FsvDracoPlatformCopyOutcome::kSizeRejected);
    CHECK(managed == nullptr && size.allocations == 0 && size.copies == 0);

    fsv_draco::FsvDecodeControl allocation_control(32);
    FakePlatform allocation_failure{&allocation_control};
    allocation_failure.fail_allocation = true;
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, 4, std::numeric_limits<int32_t>::max(),
              &allocation_control, Callbacks(&allocation_failure), &managed) ==
          FsvDracoPlatformCopyOutcome::kAllocationFailed);
    CHECK(managed == nullptr && allocation_failure.releases == 0);

    fsv_draco::FsvDecodeControl copy_control(32);
    FakePlatform copy_failure{&copy_control};
    copy_failure.fail_copy = true;
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, 4, std::numeric_limits<int32_t>::max(), &copy_control,
              Callbacks(&copy_failure), &managed) ==
          FsvDracoPlatformCopyOutcome::kCopyFailed);
    CHECK(managed == nullptr && copy_failure.releases == 1);

    fsv_draco::FsvDecodeControl pre_cancelled(32);
    CHECK(pre_cancelled.Cancel());
    FakePlatform before{&pre_cancelled};
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, 4, std::numeric_limits<int32_t>::max(), &pre_cancelled,
              Callbacks(&before), &managed) ==
          FsvDracoPlatformCopyOutcome::kStopped);
    CHECK(before.allocations == 0 && before.copies == 0 && before.releases == 0);

    fsv_draco::FsvDecodeControl after_allocation_control(32);
    FakePlatform after_allocation{&after_allocation_control};
    after_allocation.cancel_after_allocation = true;
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, 4, std::numeric_limits<int32_t>::max(),
              &after_allocation_control, Callbacks(&after_allocation), &managed) ==
          FsvDracoPlatformCopyOutcome::kStopped);
    CHECK(after_allocation.allocations == 1 && after_allocation.copies == 0 &&
          after_allocation.releases == 1 && managed == nullptr);

    fsv_draco::FsvDecodeControl after_copy_control(32);
    FakePlatform after_copy{&after_copy_control};
    after_copy.cancel_during_copy = true;
    CHECK(FsvDracoCopyBytesToPlatform(
              payload, 4, std::numeric_limits<int32_t>::max(),
              &after_copy_control, Callbacks(&after_copy), &managed) ==
          FsvDracoPlatformCopyOutcome::kStopped);
    CHECK(after_copy.allocations == 1 && after_copy.copies == 1 &&
          after_copy.releases == 1 && managed == nullptr);
  }

  std::cout << "platform_copy_contracts=2 size/copy/cancel/charge/atomic\n";
  return 0;
}
