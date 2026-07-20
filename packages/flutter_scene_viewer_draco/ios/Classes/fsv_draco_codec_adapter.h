#ifndef FSV_DRACO_CODEC_ADAPTER_H_
#define FSV_DRACO_CODEC_ADAPTER_H_

#include <array>
#include <cstddef>

#include "draco/core/fsv_decode_allocator.h"
#include "fsv_draco_owned.h"

class FsvDracoCodecControlAdapter final : public draco::FsvDecodeControl {
 public:
  explicit FsvDracoCodecControlAdapter(
      fsv_draco::FsvDecodeControl* control) noexcept;
  ~FsvDracoCodecControlAdapter() override;

  FsvDracoCodecControlAdapter(const FsvDracoCodecControlAdapter&) = delete;
  FsvDracoCodecControlAdapter& operator=(
      const FsvDracoCodecControlAdapter&) = delete;

  bool ShouldStopDecoding() const override;
  AllocationResult AllocateMemory(size_t bytes,
                                  size_t alignment) noexcept override;
  bool ReleaseMemory(AllocationResult* allocation_record,
                     void* allocation, size_t bytes,
                     size_t alignment) noexcept override;

 private:
  static constexpr size_t kInlineTrackedCodecAllocations = 128;
  fsv_draco::FsvDecodeControl* control_;
  std::array<fsv_draco::FsvDecodeAllocationResult,
             kInlineTrackedCodecAllocations>
      allocation_records_{};
  FsvDracoVector<fsv_draco::FsvDecodeAllocationResult> overflow_records_;
};

#endif  // FSV_DRACO_CODEC_ADAPTER_H_
