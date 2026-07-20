#include <atomic>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <new>

#include "fsv_basisu_request_registry.h"

namespace {
std::atomic<size_t> allocation_calls{0};
std::atomic<size_t> fail_allocation_ordinal{0};

void ResetFailure(size_t ordinal) {
  allocation_calls.store(0);
  fail_allocation_ordinal.store(ordinal);
}
}

void* operator new(std::size_t bytes) {
  const size_t ordinal = allocation_calls.fetch_add(1) + 1;
  if (fail_allocation_ordinal.load() == ordinal) throw std::bad_alloc();
  if (void* pointer = std::malloc(bytes)) return pointer;
  throw std::bad_alloc();
}

void operator delete(void* pointer) noexcept { std::free(pointer); }
void operator delete(void* pointer, std::size_t) noexcept {
  std::free(pointer);
}

int main() {
  size_t registration_allocations = 0;
  {
    fsv_basisu::FsvDecodeRequestRegistry baseline;
    ResetFailure(0);
    fsv_basisu::FsvRegisterFailure failure =
        fsv_basisu::FsvRegisterFailure::kNone;
    auto request = baseline.Register("baseline", 4096, &failure);
    registration_allocations = allocation_calls.load();
    if (request == nullptr ||
        failure != fsv_basisu::FsvRegisterFailure::kNone ||
        registration_allocations < 3) {
      return 158;
    }
    baseline.Finish("baseline", request);
  }

  for (size_t ordinal = 1; ordinal <= registration_allocations; ++ordinal) {
    fsv_basisu::FsvDecodeRequestRegistry registry;
    ResetFailure(ordinal);
    fsv_basisu::FsvRegisterFailure failure =
        fsv_basisu::FsvRegisterFailure::kNone;
    try {
      auto failed = registry.Register(
          "allocation-failure", std::numeric_limits<uint64_t>::max(),
          &failure);
      if (failed != nullptr) return 159;
    } catch (const std::bad_alloc&) {
      std::cerr << "ios-control-creation-red bad_alloc escaped ordinal="
                << ordinal << "\n";
      return 160;
    }
    if (failure !=
            fsv_basisu::FsvRegisterFailure::kControlCreationFailed ||
        registry.active_count() != 0) {
      return 161;
    }
    fail_allocation_ordinal.store(0);
    auto fresh = registry.Register("fresh", 4096);
    if (fresh == nullptr || !registry.ShouldStart(fresh) ||
        registry.Finish("fresh", fresh) !=
            fsv_basisu::FsvFinishDisposition::kSuccess ||
        registry.active_count() != 0) {
      return 162;
    }
  }
  std::cout << "ios-control-creation-green ordinals="
            << registration_allocations << " fresh=success\n";
  return 0;
}
