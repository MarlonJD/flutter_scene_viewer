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

FsvBasisuImageRequest Request(const std::vector<uint8_t>& bytes, int index,
                              fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuImageRequest request(control);
  request.texture_index = index;
  request.image_index = index;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  return request;
}

FsvBasisuImageRequests MixedRequests(
    const std::vector<uint8_t>& etc1s, const std::vector<uint8_t>& uastc,
    const std::vector<uint8_t>& zstd,
    fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuImageRequests requests{
      FsvBasisuAllocator<FsvBasisuImageRequest>(control)};
  requests.reserve(3);
  requests.push_back(Request(etc1s, 0, control));
  requests.push_back(Request(uastc, 1, control));
  requests.push_back(Request(zstd, 2, control));
  return requests;
}

FsvBasisuDecodeBudgetMetadata Budget(
    int64_t working = INT64_C(1) << 32) {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes =
      FsvBasisuBudgetNumber::Integer(INT64_C(1) << 32);
  budget.max_texture_pixels =
      FsvBasisuBudgetNumber::Integer(INT64_C(1) << 30);
  budget.max_native_output_bytes =
      FsvBasisuBudgetNumber::Integer(INT64_C(1) << 32);
  budget.max_native_working_bytes =
      FsvBasisuBudgetNumber::Integer(working);
  return budget;
}

FsvBasisuDecodeBudgetState State() {
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
  return state;
}

bool Clean(const fsv_basisu::FsvDecodeControl& control) {
  return control.live_bytes() == 0 && control.owner_count() == 0 &&
         control.request_allocation_count() ==
             control.request_release_count() &&
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

int RunFresh(const std::vector<uint8_t>& etc1s,
             const std::vector<uint8_t>& uastc,
             const std::vector<uint8_t>& zstd) {
  fsv_basisu::FsvDecodeControl control(
      std::numeric_limits<uint64_t>::max());
  {
    FsvBasisuImageRequests requests =
        MixedRequests(etc1s, uastc, zstd, &control);
    FsvBasisuTranscodeResult result =
        FsvBasisuTranscodeImages(requests, Budget(), State(), &control);
    if (result.decoded_images.size() != 3 || !result.diagnostics.empty() ||
        result.terminal_outcome != FsvBasisuTerminalOutcomeKind::kNone ||
        control.live_bytes() == 0) {
      return 1;
    }
  }
  return Clean(control) ? 0 : 2;
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

  fsv_basisu::FsvDecodeControl control(
      std::numeric_limits<uint64_t>::max());
  {
    FsvBasisuImageRequests requests =
        MixedRequests(etc1s, uastc, zstd, &control);
    const uint64_t input_live = control.live_bytes();
    const uint64_t input_owners = control.owner_count();
    if (input_live == 0 || input_owners == 0) return 68;
    FsvBasisuTranscodeResult result =
        FsvBasisuTranscodeImages(requests, Budget(), State(), &control);
    if (!result.diagnostics.empty() || result.decoded_images.size() != 3) {
      return 66;
    }
    if (control.live_bytes() <= input_live) {
      std::cerr << "bridge-result-owner-red live=0 images=3\n";
      return 160;
    }
    std::cerr << "result-live=" << control.live_bytes()
              << " owners=" << control.owner_count()
              << " request-alloc=" << control.request_allocation_count()
              << " request-release=" << control.request_release_count()
              << " reserve=" << control.allocation_count()
              << " release=" << control.release_count() << "\n";
  }
  std::cerr << "after-result live=" << control.live_bytes()
            << " owners=" << control.owner_count()
            << " allocations=" << control.request_allocation_count()
            << " releases=" << control.request_release_count()
            << " mismatches=" << control.release_mismatch_count() << "\n";
  std::cerr << "after-total reserve=" << control.allocation_count()
            << " release=" << control.release_count() << "\n";
  if (!Clean(control)) {
    return 67;
  }

  {
    fsv_basisu::FsvDecodeControl cancelled(
        std::numeric_limits<uint64_t>::max());
    {
      FsvBasisuImageRequests requests =
          MixedRequests(etc1s, uastc, zstd, &cancelled);
      FsvBasisuTranscodeTestingHooks hooks;
      hooks.cancel_before_request_index = 1;
      FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
          requests, Budget(), State(), &cancelled, &hooks);
      if (!result.decoded_images.empty() ||
          result.terminal_outcome !=
              FsvBasisuTerminalOutcomeKind::kCallerCancelled) {
        return 69;
      }
    }
    if (!Clean(cancelled)) return 70;
  }

  {
    fsv_basisu::FsvDecodeControl budgeted(1);
    {
      FsvBasisuTranscodeResult result(&budgeted);
      try {
        FsvBasisuImageRequests requests =
            MixedRequests(etc1s, uastc, zstd, &budgeted);
        result = FsvBasisuTranscodeImages(requests, Budget(1), State(),
                                          &budgeted);
      } catch (const std::bad_alloc&) {
        FsvBasisuRecordTerminalOutcome(&result, &budgeted);
      }
      if (!result.decoded_images.empty() ||
          result.terminal_outcome !=
              FsvBasisuTerminalOutcomeKind::kBudgetExceeded) {
        return 71;
      }
    }
    if (!Clean(budgeted)) return 80;
  }

  {
    std::vector<uint8_t> corrupt = uastc;
    corrupt[0] ^= 0xff;
    fsv_basisu::FsvDecodeControl corrupt_control(
        std::numeric_limits<uint64_t>::max());
    {
      FsvBasisuImageRequests requests{
          FsvBasisuAllocator<FsvBasisuImageRequest>(&corrupt_control)};
      requests.push_back(Request(corrupt, 0, &corrupt_control));
      FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
          requests, Budget(), State(), &corrupt_control);
      if (!result.decoded_images.empty() || result.diagnostics.empty()) {
        return 72;
      }
    }
    if (!Clean(corrupt_control)) return 73;
  }

  FailingHeap baseline_heap;
  uint64_t input_calls = 0;
  uint64_t total_calls = 0;
  {
    fsv_basisu::FsvDecodeControl baseline(
        std::numeric_limits<uint64_t>::max(), &baseline_heap);
    {
      FsvBasisuImageRequests requests =
          MixedRequests(etc1s, uastc, zstd, &baseline);
      input_calls = baseline_heap.calls;
      FsvBasisuTranscodeResult result =
          FsvBasisuTranscodeImages(requests, Budget(), State(), &baseline);
      if (result.decoded_images.size() != 3) return 74;
      total_calls = baseline_heap.calls;
    }
    if (!Clean(baseline)) return 75;
  }
  for (uint64_t ordinal = input_calls + 1; ordinal <= total_calls;
       ++ordinal) {
    FailingHeap heap;
    fsv_basisu::FsvDecodeControl failed(
        std::numeric_limits<uint64_t>::max(), &heap);
    {
      FsvBasisuImageRequests requests =
          MixedRequests(etc1s, uastc, zstd, &failed);
      heap.fail_at = ordinal;
      FsvBasisuTranscodeResult result =
          FsvBasisuTranscodeImages(requests, Budget(), State(), &failed);
      if (!result.decoded_images.empty() ||
          result.terminal_outcome !=
              FsvBasisuTerminalOutcomeKind::kAllocationFailed) {
        return 76;
      }
    }
    if (!Clean(failed)) return 77;
  }

  int concurrent_a = -1;
  int concurrent_b = -1;
  std::thread first([&] {
    concurrent_a = RunFresh(etc1s, uastc, zstd);
  });
  std::thread second([&] {
    concurrent_b = RunFresh(etc1s, uastc, zstd);
  });
  first.join();
  second.join();
  if (concurrent_a != 0 || concurrent_b != 0) return 78;
  if (RunFresh(etc1s, uastc, zstd) != 0) return 79;

  std::cout << "bridge-result-owner-green peak=" << control.peak_bytes()
            << " allocations=" << control.request_allocation_count()
            << " bridge-failure-ordinals=" << (total_calls - input_calls)
            << " concurrency=2 fresh=green\n";
  return 0;
}
