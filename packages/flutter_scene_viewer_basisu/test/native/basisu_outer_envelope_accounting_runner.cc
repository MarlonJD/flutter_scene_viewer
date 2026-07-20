#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#include "basisu_transcoder.h"
#include "fsv_basisu_bridge.h"

namespace {

struct ExpectedAccounting {
  const char* label;
  uint64_t allocations;
  uint64_t peak;
  size_t images;
};

constexpr ExpectedAccounting kExpected[] = {
    {"etc1s", 90, 41293, 1},
    {"uastc", 27, 2781, 1},
    {"zstd", 29, 99967, 1},
    {"mixed", 140, 102541, 3},
};

struct Accounting {
  uint64_t allocations = 0;
  uint64_t releases = 0;
  uint64_t reservations = 0;
  uint64_t reservation_releases = 0;
  uint64_t peak = 0;
  bool success = false;
  bool clean = false;
};

uint32_t ReadLe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

void SetLe32(std::vector<uint8_t>* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value);
  (*bytes)[offset + 1] = static_cast<uint8_t>(value >> 8);
  (*bytes)[offset + 2] = static_cast<uint8_t>(value >> 16);
  (*bytes)[offset + 3] = static_cast<uint8_t>(value >> 24);
}

std::vector<uint8_t> ReadFixture(const char* path) {
  std::ifstream input(path, std::ios::binary);
  return std::vector<uint8_t>(std::istreambuf_iterator<char>(input), {});
}

void NormalizeLinearFixture(std::vector<uint8_t>* bytes) {
  const uint32_t dfd_offset = ReadLe32(*bytes, 48);
  uint32_t dfd_bits = ReadLe32(*bytes, dfd_offset + 12);
  const uint32_t primaries = (dfd_bits >> 8) & 0xffU;
  const uint32_t transfer = (dfd_bits >> 16) & 0xffU;
  if (primaries == basist::KTX2_DF_PRIMARIES_BT709 &&
      transfer == basist::KTX2_KHR_DF_TRANSFER_LINEAR) {
    dfd_bits &= ~0xff00U;
    SetLe32(bytes, dfd_offset + 12, dfd_bits);
  }
}

FsvBasisuDecodeBudgetMetadata Budget(
    uint64_t working = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger)) {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes =
      FsvBasisuBudgetNumber::Integer(kFsvBasisuMaxSafeInteger);
  budget.max_texture_pixels =
      FsvBasisuBudgetNumber::Integer(kFsvBasisuMaxSafeInteger);
  budget.max_native_output_bytes =
      FsvBasisuBudgetNumber::Integer(kFsvBasisuMaxSafeInteger);
  budget.max_native_working_bytes =
      FsvBasisuBudgetNumber::Integer(static_cast<int64_t>(working));
  return budget;
}

FsvBasisuDecodeBudgetState State() {
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
  return state;
}

FsvBasisuImageRequest Request(const std::vector<uint8_t>& bytes, int index,
                              fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuImageRequest request(control);
  request.texture_index = index;
  request.image_index = index;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  return request;
}

FsvBasisuImageRequests Requests(
    const std::vector<const std::vector<uint8_t>*>& fixtures,
    fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuImageRequests requests{
      FsvBasisuAllocator<FsvBasisuImageRequest>(control)};
  requests.reserve(fixtures.size());
  for (size_t index = 0; index < fixtures.size(); ++index) {
    requests.push_back(Request(*fixtures[index], static_cast<int>(index),
                               control));
  }
  return requests;
}

bool Clean(const fsv_basisu::FsvDecodeControl& control) {
  return control.live_bytes() == 0 && control.owner_count() == 0 &&
         control.request_allocation_count() ==
             control.request_release_count() &&
         control.allocation_count() == control.release_count() &&
         control.release_mismatch_count() == 0;
}

class FailingHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  void* Allocate(size_t bytes, size_t alignment) noexcept override {
    ++calls;
    if (fail_at != 0 && calls == fail_at) return nullptr;
    if (alignment <= alignof(std::max_align_t)) return std::malloc(bytes);
    void* pointer = nullptr;
    return posix_memalign(&pointer, alignment, bytes) == 0 ? pointer : nullptr;
  }

  void Release(void* pointer, size_t, size_t) noexcept override {
    std::free(pointer);
  }

  uint64_t calls = 0;
  uint64_t fail_at = 0;
};

Accounting RunSuccess(
    const std::vector<const std::vector<uint8_t>*>& fixtures,
    uint64_t working = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger),
    FailingHeap* heap = nullptr) {
  fsv_basisu::FsvDecodeControl control(working, heap);
  Accounting accounting;
  {
    FsvBasisuImageRequests requests = Requests(fixtures, &control);
    FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
        requests, Budget(working), State(), &control);
    accounting.success = result.decoded_images.size() == fixtures.size() &&
                         result.diagnostics.empty() &&
                         result.terminal_outcome ==
                             FsvBasisuTerminalOutcomeKind::kNone &&
                         control.live_bytes() != 0;
    accounting.allocations = control.request_allocation_count();
    accounting.reservations = control.allocation_count();
    accounting.peak = control.peak_bytes();
  }
  accounting.releases = control.request_release_count();
  accounting.reservation_releases = control.release_count();
  accounting.clean = Clean(control);
  return accounting;
}

bool IsAtomicTerminal(const FsvBasisuTranscodeResult& result,
                      FsvBasisuTerminalOutcomeKind expected) {
  return result.decoded_images.empty() && result.diagnostics.empty() &&
         result.terminal_outcome == expected;
}

int VerifyPeakBoundary(
    const std::vector<const std::vector<uint8_t>*>& fixtures,
    const ExpectedAccounting& expected) {
  FailingHeap exact_heap;
  const Accounting exact = RunSuccess(fixtures, expected.peak, &exact_heap);
  if (!exact.success || !exact.clean || exact.peak != expected.peak ||
      exact.allocations != expected.allocations ||
      exact_heap.calls != expected.allocations) {
    return 100;
  }

  FailingHeap rejected_heap;
  fsv_basisu::FsvDecodeControl rejected(expected.peak - 1, &rejected_heap);
  {
    FsvBasisuTranscodeResult result(&rejected);
    try {
      FsvBasisuImageRequests requests = Requests(fixtures, &rejected);
      result = FsvBasisuTranscodeImages(
          requests, Budget(expected.peak - 1), State(), &rejected);
    } catch (const std::bad_alloc&) {
      FsvBasisuRecordTerminalOutcome(&result, &rejected);
    }
    if (!IsAtomicTerminal(result,
                          FsvBasisuTerminalOutcomeKind::kBudgetExceeded) ||
        rejected.stop_reason() != fsv_basisu::FsvDecodeStopReason::kBudget ||
        rejected.peak_bytes() > expected.peak - 1 ||
        rejected_heap.calls >= expected.allocations) {
      return 101;
    }
  }
  return Clean(rejected) ? 0 : 102;
}

int VerifyMixedFailureOrdinals(
    const std::vector<const std::vector<uint8_t>*>& fixtures,
    uint64_t expected_allocations) {
  for (uint64_t ordinal = 1; ordinal <= expected_allocations; ++ordinal) {
    FailingHeap heap;
    heap.fail_at = ordinal;
    fsv_basisu::FsvDecodeControl control(
        std::numeric_limits<uint64_t>::max(), &heap);
    {
      FsvBasisuTranscodeResult result(&control);
      try {
        FsvBasisuImageRequests requests = Requests(fixtures, &control);
        result = FsvBasisuTranscodeImages(
            requests, Budget(), State(), &control);
      } catch (const std::bad_alloc&) {
        FsvBasisuRecordTerminalOutcome(&result, &control);
      }
      if (!IsAtomicTerminal(
              result, FsvBasisuTerminalOutcomeKind::kAllocationFailed) ||
          control.stop_reason() !=
              fsv_basisu::FsvDecodeStopReason::kHeapFailure ||
          heap.calls != ordinal) {
        return 110;
      }
    }
    if (!Clean(control)) return 111;
  }
  return 0;
}

int VerifyStopsAndCorruption(
    const std::vector<const std::vector<uint8_t>*>& fixtures,
    const std::vector<uint8_t>& uastc) {
  {
    fsv_basisu::FsvDecodeControl control(
        std::numeric_limits<uint64_t>::max());
    {
      FsvBasisuImageRequests requests = Requests(fixtures, &control);
      FsvBasisuTranscodeTestingHooks hooks;
      hooks.cancel_before_request_index = 1;
      FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
          requests, Budget(), State(), &control, &hooks);
      if (!IsAtomicTerminal(
              result, FsvBasisuTerminalOutcomeKind::kCallerCancelled)) {
        return 120;
      }
    }
    if (!Clean(control)) return 121;
  }
  {
    fsv_basisu::FsvDecodeControl control(
        std::numeric_limits<uint64_t>::max());
    {
      FsvBasisuImageRequests requests = Requests(fixtures, &control);
      control.Deadline();
      FsvBasisuTranscodeResult result =
          FsvBasisuTranscodeImages(requests, Budget(), State(), &control);
      if (!IsAtomicTerminal(result,
                            FsvBasisuTerminalOutcomeKind::kDeadline)) {
        return 122;
      }
    }
    if (!Clean(control)) return 123;
  }
  {
    std::vector<uint8_t> corrupt = uastc;
    corrupt[0] ^= 0xff;
    fsv_basisu::FsvDecodeControl control(
        std::numeric_limits<uint64_t>::max());
    {
      const std::vector<const std::vector<uint8_t>*> corrupt_fixture{
          &corrupt};
      FsvBasisuImageRequests requests = Requests(corrupt_fixture, &control);
      FsvBasisuTranscodeResult result =
          FsvBasisuTranscodeImages(requests, Budget(), State(), &control);
      if (!result.decoded_images.empty() || result.diagnostics.size() != 1 ||
          result.terminal_outcome != FsvBasisuTerminalOutcomeKind::kNone) {
        return 124;
      }
    }
    if (!Clean(control)) return 125;
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 4) return 64;
  std::vector<uint8_t> etc1s = ReadFixture(argv[1]);
  std::vector<uint8_t> uastc = ReadFixture(argv[2]);
  std::vector<uint8_t> zstd = ReadFixture(argv[3]);
  if (etc1s.empty() || uastc.empty() || zstd.empty()) return 65;
  NormalizeLinearFixture(&etc1s);
  NormalizeLinearFixture(&uastc);

  const std::vector<const std::vector<uint8_t>*> paths[] = {
      {&etc1s}, {&uastc}, {&zstd}, {&etc1s, &uastc, &zstd}};
  Accounting observed[4];
  bool outer_envelope_present = false;
  for (size_t index = 0; index < 4; ++index) {
    observed[index] = RunSuccess(paths[index]);
    std::cerr << kExpected[index].label
              << " allocations=" << observed[index].allocations
              << " peak=" << observed[index].peak
              << " reservations=" << observed[index].reservations << "\n";
    if (!observed[index].success || !observed[index].clean) return 66;
    outer_envelope_present |=
        observed[index].reservations != observed[index].allocations;
  }
  if (outer_envelope_present) {
    std::cerr << "outer-envelope-red extra-retained-output-reservation\n";
    return 160;
  }

  for (size_t index = 0; index < 4; ++index) {
    if (observed[index].allocations != kExpected[index].allocations ||
        observed[index].releases != kExpected[index].allocations ||
        observed[index].reservations != kExpected[index].allocations ||
        observed[index].reservation_releases !=
            kExpected[index].allocations ||
        observed[index].peak != kExpected[index].peak) {
      return 67;
    }
    const int boundary = VerifyPeakBoundary(paths[index], kExpected[index]);
    if (boundary != 0) return boundary;
  }

  const int failures =
      VerifyMixedFailureOrdinals(paths[3], kExpected[3].allocations);
  if (failures != 0) return failures;
  const int stops = VerifyStopsAndCorruption(paths[3], uastc);
  if (stops != 0) return stops;

  int first = -1;
  int second = -1;
  std::thread first_thread([&] {
    const Accounting accounting =
        RunSuccess(paths[3], kExpected[3].peak);
    first = accounting.success && accounting.clean &&
                    accounting.allocations == kExpected[3].allocations &&
                    accounting.peak == kExpected[3].peak
                ? 0
                : 1;
  });
  std::thread second_thread([&] {
    const Accounting accounting =
        RunSuccess(paths[3], kExpected[3].peak);
    second = accounting.success && accounting.clean &&
                     accounting.allocations == kExpected[3].allocations &&
                     accounting.peak == kExpected[3].peak
                 ? 0
                 : 1;
  });
  first_thread.join();
  second_thread.join();
  if (first != 0 || second != 0) return 130;

  const Accounting fresh = RunSuccess(paths[3], kExpected[3].peak);
  if (!fresh.success || !fresh.clean ||
      fresh.allocations != kExpected[3].allocations ||
      fresh.peak != kExpected[3].peak) {
    return 131;
  }

  std::cout << "basisu-exact-accounting etc1s=" << kExpected[0].allocations
            << "/" << kExpected[0].peak
            << " uastc=" << kExpected[1].allocations << "/"
            << kExpected[1].peak << " zstd=" << kExpected[2].allocations
            << "/" << kExpected[2].peak << " mixed="
            << kExpected[3].allocations << "/" << kExpected[3].peak
            << " failure-ordinals=" << kExpected[3].allocations
            << " peak-minus-one=typed-before-heap concurrency=2 fresh=green"
            << " atomic=empty cleanup=zero\n";
  return 0;
}
