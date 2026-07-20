#include "fsv_basisu_bridge.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <thread>
#include <vector>

#include "basisu_transcoder.h"
#include "zstd.h"

namespace {

uint32_t ReadLe32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

uint64_t ReadLe64(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint64_t>(ReadLe32(bytes, offset)) |
         (static_cast<uint64_t>(ReadLe32(bytes, offset + 4)) << 32);
}

void SetLe32(std::vector<uint8_t>* bytes, size_t offset, uint32_t value) {
  (*bytes)[offset] = static_cast<uint8_t>(value);
  (*bytes)[offset + 1] = static_cast<uint8_t>(value >> 8);
  (*bytes)[offset + 2] = static_cast<uint8_t>(value >> 16);
  (*bytes)[offset + 3] = static_cast<uint8_t>(value >> 24);
}

void SetLe64(std::vector<uint8_t>* bytes, size_t offset, uint64_t value) {
  SetLe32(bytes, offset, static_cast<uint32_t>(value));
  SetLe32(bytes, offset + 4, static_cast<uint32_t>(value >> 32));
}

std::vector<uint8_t> ReadFile(const char* path) {
  std::ifstream input(path, std::ios::binary);
  return std::vector<uint8_t>((std::istreambuf_iterator<char>(input)),
                              std::istreambuf_iterator<char>());
}

void NormalizeSelectedProfile(std::vector<uint8_t>* bytes) {
  const uint32_t dfd_offset = ReadLe32(*bytes, 48);
  uint32_t dfd_bits = ReadLe32(*bytes, dfd_offset + 12);
  dfd_bits &= ~0x0000ff00U;
  SetLe32(bytes, dfd_offset + 12, dfd_bits);
}

std::vector<uint8_t> WithAnimationEntry(const std::vector<uint8_t>& source) {
  const uint32_t kvd_offset = ReadLe32(source, 56);
  const uint32_t kvd_length = ReadLe32(source, 60);
  if (kvd_offset == 0 || kvd_length == 0 ||
      static_cast<uint64_t>(kvd_offset) + kvd_length > source.size()) {
    return {};
  }

  constexpr char kKey[] = "KTXanimData";
  constexpr uint32_t kValueWords = 3;
  const uint32_t payload_length =
      static_cast<uint32_t>(sizeof(kKey) + kValueWords * sizeof(uint32_t));
  const uint32_t padding = (4U - (payload_length & 3U)) & 3U;
  const uint32_t inserted_length = 4U + payload_length + padding;
  std::vector<uint8_t> entry(inserted_length, 0);
  SetLe32(&entry, 0, payload_length);
  std::memcpy(entry.data() + 4, kKey, sizeof(kKey));
  // duration=1, timescale=1, loopcount=0. The exact values are immaterial to
  // the selected glTF profile, which rejects this exact valid key.
  SetLe32(&entry, 4 + sizeof(kKey), 1);
  SetLe32(&entry, 4 + sizeof(kKey) + 4, 1);

  std::vector<uint8_t> result = source;
  result.insert(result.begin() + kvd_offset, entry.begin(), entry.end());
  SetLe32(&result, 60, kvd_length + inserted_length);

  const uint32_t declared_levels = ReadLe32(result, 40);
  const uint32_t level_count = declared_levels == 0 ? 1 : declared_levels;
  for (uint32_t level = 0; level < level_count; level += 1) {
    const size_t entry_offset = 80U + static_cast<size_t>(level) * 24U;
    const uint64_t level_offset = ReadLe64(result, entry_offset);
    if (level_offset >= kvd_offset) {
      SetLe64(&result, entry_offset, level_offset + inserted_length);
    }
  }
  const uint64_t sgd_offset = ReadLe64(result, 64);
  if (sgd_offset >= kvd_offset && sgd_offset != 0) {
    SetLe64(&result, 64, sgd_offset + inserted_length);
  }
  return result;
}

class ProbeControl final : public basist::fsv_transcode_control,
                           public basisu::fsv_vector_allocator {
 public:
  enum class StopReason { kNone, kCancelled, kBudget, kHeap };

  explicit ProbeControl(
      size_t byte_limit = std::numeric_limits<size_t>::max(),
      size_t fail_allocation_ordinal = 0,
      size_t budget_allocation_ordinal = 0)
      : byte_limit_(byte_limit),
        fail_allocation_ordinal_(fail_allocation_ordinal),
        budget_allocation_ordinal_(budget_allocation_ordinal) {}

  basisu::fsv_vector_allocator* fsv_get_vector_allocator() override {
    return this;
  }

  void Cancel() { SetStopReason(StopReason::kCancelled); }
  void CancelAtCheckpoint(const char* stage) { cancel_checkpoint_ = stage; }
  void InjectHeapStop() { SetStopReason(StopReason::kHeap); }

  bool fsv_checkpoint(const char* stage) override {
    checkpoints_ += 1;
    if (std::strcmp(stage, "metadataKvdRelocate") == 0) {
      relocation_allocation_ordinal_ = allocation_attempts_ + 1U;
      relocation_live_bytes_ = live_bytes_;
    }
    if (!cancel_checkpoint_.empty() && cancel_checkpoint_ == stage) Cancel();
    return stop_reason_ == StopReason::kNone;
  }
  bool fsv_try_reserve(size_t bytes) override {
    reservation_attempts_ += 1;
    if (stop_reason_ != StopReason::kNone) return false;
    if (bytes > byte_limit_ || live_bytes_ > byte_limit_ - bytes) {
      SetStopReason(StopReason::kBudget);
      return false;
    }
    live_bytes_ += bytes;
    reservation_count_ += 1;
    UpdatePeak();
    return true;
  }
  void fsv_release(size_t bytes) override {
    live_bytes_ -= std::min(live_bytes_, bytes);
    reservation_releases_ += 1;
  }
  void fsv_note_allocation_failure() override {
    allocation_failed_ = true;
    SetStopReason(StopReason::kHeap);
  }

  basisu::fsv_allocation_result fsv_allocate(size_t bytes,
                                              size_t alignment) override {
    basisu::fsv_allocation_result result;
    const size_t normalized_bytes = bytes == 0 ? 1 : bytes;
    const size_t normalized_alignment = std::max(alignment, alignof(void*));
    allocation_attempts_ += 1;
    allocation_sizes_.push_back(normalized_bytes);
    if (stop_reason_ != StopReason::kNone) {
      result.m_outcome = stop_reason_ == StopReason::kBudget
                             ? basisu::fsv_allocation_outcome::kBudgetExceeded
                             : stop_reason_ == StopReason::kHeap
                                   ? basisu::fsv_allocation_outcome::kHeapFailure
                                   : basisu::fsv_allocation_outcome::kStopped;
      return result;
    }
    if (budget_allocation_ordinal_ != 0 &&
        allocation_attempts_ == budget_allocation_ordinal_) {
      SetStopReason(StopReason::kBudget);
      result.m_outcome = basisu::fsv_allocation_outcome::kBudgetExceeded;
      return result;
    }
    if (normalized_bytes > byte_limit_ ||
        live_bytes_ > byte_limit_ - normalized_bytes) {
      SetStopReason(StopReason::kBudget);
      result.m_outcome = basisu::fsv_allocation_outcome::kBudgetExceeded;
      return result;
    }
    heap_attempts_ += 1;
    if (fail_allocation_ordinal_ != 0 &&
        allocation_attempts_ == fail_allocation_ordinal_) {
      allocation_failed_ = true;
      SetStopReason(StopReason::kHeap);
      result.m_outcome = basisu::fsv_allocation_outcome::kHeapFailure;
      return result;
    }
    void* pointer = nullptr;
    if (normalized_alignment <= alignof(std::max_align_t)) {
      pointer = std::malloc(normalized_bytes);
    } else if (posix_memalign(&pointer, normalized_alignment,
                              normalized_bytes) != 0) {
      pointer = nullptr;
    }
    if (pointer == nullptr) {
      allocation_failed_ = true;
      SetStopReason(StopReason::kHeap);
      result.m_outcome = basisu::fsv_allocation_outcome::kHeapFailure;
      return result;
    }
    result.m_p = pointer;
    result.m_bytes = normalized_bytes;
    result.m_alignment = normalized_alignment;
    result.m_outcome = basisu::fsv_allocation_outcome::kSuccess;
    result.m_allocator = this;
    live_bytes_ += normalized_bytes;
    allocations_ += 1;
    UpdatePeak();
    return result;
  }

  bool fsv_release(basisu::fsv_allocation_result& allocation, void* pointer,
                   size_t bytes, size_t alignment) override {
    const size_t normalized_bytes = bytes == 0 ? 1 : bytes;
    const size_t normalized_alignment =
        std::max(alignment, alignof(void*));
    if (allocation.m_allocator != this || allocation.m_p != pointer ||
        allocation.m_bytes != normalized_bytes ||
        allocation.m_alignment != normalized_alignment) {
      release_mismatches_ += 1;
      return false;
    }
    std::free(pointer);
    live_bytes_ -= allocation.m_bytes;
    allocation.reset();
    releases_ += 1;
    return true;
  }

  void fsv_retain_owner() noexcept override { owners_ += 1; }
  void fsv_release_owner() noexcept override { owners_ -= 1; }

  size_t live_bytes() const { return live_bytes_; }
  size_t allocations() const { return allocations_; }
  size_t allocation_attempts() const { return allocation_attempts_; }
  size_t heap_attempts() const { return heap_attempts_; }
  size_t releases() const { return releases_; }
  size_t release_mismatches() const { return release_mismatches_; }
  size_t reservation_attempts() const { return reservation_attempts_; }
  size_t reservation_count() const { return reservation_count_; }
  size_t reservation_releases() const { return reservation_releases_; }
  size_t peak_bytes() const { return peak_bytes_; }
  size_t owners() const { return owners_; }
  bool allocation_failed() const { return allocation_failed_; }
  StopReason stop_reason() const { return stop_reason_; }
  size_t checkpoints() const { return checkpoints_; }
  const std::vector<size_t>& allocation_sizes() const {
    return allocation_sizes_;
  }
  size_t relocation_allocation_ordinal() const {
    return relocation_allocation_ordinal_;
  }
  size_t relocation_live_bytes() const { return relocation_live_bytes_; }

 private:
  void SetStopReason(StopReason reason) {
    if (stop_reason_ == StopReason::kNone) stop_reason_ = reason;
  }

  void UpdatePeak() { peak_bytes_ = std::max(peak_bytes_, live_bytes_); }

  size_t byte_limit_;
  size_t fail_allocation_ordinal_;
  size_t budget_allocation_ordinal_;
  std::string cancel_checkpoint_;
  size_t live_bytes_ = 0;
  size_t peak_bytes_ = 0;
  size_t allocation_attempts_ = 0;
  size_t heap_attempts_ = 0;
  size_t allocations_ = 0;
  size_t releases_ = 0;
  size_t release_mismatches_ = 0;
  size_t reservation_attempts_ = 0;
  size_t reservation_count_ = 0;
  size_t reservation_releases_ = 0;
  size_t owners_ = 0;
  size_t checkpoints_ = 0;
  size_t relocation_allocation_ordinal_ = 0;
  size_t relocation_live_bytes_ = 0;
  std::vector<size_t> allocation_sizes_;
  bool allocation_failed_ = false;
  StopReason stop_reason_ = StopReason::kNone;
};

FsvBasisuImageRequest RequestFor(const std::vector<uint8_t>& bytes) {
  FsvBasisuImageRequest request;
  request.texture_index = 0;
  request.image_index = 0;
  request.usage_role = FsvBasisuUsageRole::kNonColor;
  request.channel_layout = FsvBasisuChannelLayout::kRgba;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;
  return request;
}

FsvBasisuDecodeBudgetMetadata Budget() {
  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(1LL << 30);
  budget.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  budget.max_native_working_bytes = FsvBasisuBudgetNumber::Integer(1LL << 32);
  return budget;
}

FsvBasisuDecodeBudgetState BudgetState() {
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);
  return state;
}

bool HasMalformedDiagnostic(const std::vector<uint8_t>& bytes,
                            const char* field) {
  fsv_basisu::FsvDecodeControl control(
      std::numeric_limits<uint64_t>::max());
  bool charged_result_contract = false;
  {
    const FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
        {RequestFor(bytes)}, Budget(), BudgetState(), &control);
    charged_result_contract =
        result.decoded_images.empty() && result.diagnostics.size() == 1 &&
        result.diagnostics[0].status == "invalidMetadata" &&
        result.diagnostics[0].stage == "basisuNativePreflight" &&
        result.diagnostics[0].field == field &&
        control.request_allocation_count() > 0 &&
        control.request_allocation_count() >
            control.request_release_count() &&
        control.live_bytes() > 0 && control.owner_count() > 0 &&
        control.release_mismatch_count() == 0;
  }
  return charged_result_contract &&
         control.request_allocation_count() ==
             control.request_release_count() &&
         control.live_bytes() == 0 && control.owner_count() == 0 &&
         control.release_mismatch_count() == 0;
}

struct DirectMalformedObservation {
  bool initialized = false;
  size_t allocations = 0;
  size_t releases = 0;
  size_t live_bytes = 0;
  size_t owners = 0;
  bool allocation_failed = false;
};

DirectMalformedObservation ObserveDirectMalformed(
    const std::vector<uint8_t>& bytes) {
  ProbeControl probe;
  DirectMalformedObservation observation;
  {
    basist::ktx2_transcoder transcoder;
    transcoder.set_fsv_transcode_control(&probe);
    observation.initialized = transcoder.init(
        bytes.data(), static_cast<uint32_t>(bytes.size()));
  }
  observation.allocations = probe.allocations();
  observation.releases = probe.releases();
  observation.live_bytes = probe.live_bytes();
  observation.owners = probe.owners();
  observation.allocation_failed = probe.allocation_failed();
  return observation;
}

bool DirectCleanupIsBalanced(const DirectMalformedObservation& observation) {
  return observation.allocations > 0 &&
         observation.allocations == observation.releases &&
         observation.live_bytes == 0 && observation.owners == 0 &&
         !observation.allocation_failed;
}

bool DirectCleanupOnly(const DirectMalformedObservation& observation) {
  return observation.allocations == observation.releases &&
         observation.live_bytes == 0 && observation.owners == 0 &&
         !observation.allocation_failed;
}

struct ControlPathObservation {
  bool initialized = false;
  bool started = false;
  bool decoded = false;
  size_t allocation_attempts = 0;
  size_t heap_attempts = 0;
  size_t allocations = 0;
  size_t releases = 0;
  size_t reservation_attempts = 0;
  size_t reservations = 0;
  size_t reservation_releases = 0;
  size_t peak_bytes = 0;
  size_t live_bytes = 0;
  size_t owners = 0;
  size_t checkpoints = 0;
  bool allocation_failed = false;
  ProbeControl::StopReason stop_reason = ProbeControl::StopReason::kNone;
  std::vector<uint8_t> rgba;
};

ControlPathObservation ObserveControlPath(const std::vector<uint8_t>& bytes,
                                          ProbeControl* probe,
                                          bool all_levels = false) {
  ControlPathObservation observation;
  {
    basist::ktx2_transcoder transcoder;
    transcoder.set_fsv_transcode_control(probe);
    observation.initialized = transcoder.init(
        bytes.data(), static_cast<uint32_t>(bytes.size()));
    if (observation.initialized) {
      observation.started = transcoder.start_transcoding();
    }
    basist::ktx2_transcoder_state state;
    state.clear();
    if (observation.started) {
      const uint32_t level_count = all_levels ? transcoder.get_levels() : 1U;
      observation.decoded = level_count > 0U;
      for (uint32_t level_index = 0; level_index < level_count;
           level_index += 1) {
        basist::ktx2_image_level_info level_info;
        if (transcoder.get_image_level_info(level_info, level_index, 0, 0)) {
          const uint64_t pixels =
              static_cast<uint64_t>(level_info.m_orig_width) *
              level_info.m_orig_height;
          if (pixels <= std::numeric_limits<uint32_t>::max() &&
              pixels <= std::numeric_limits<size_t>::max() / 4U) {
            observation.rgba.assign(static_cast<size_t>(pixels) * 4U, 0);
            observation.decoded =
                observation.decoded &&
                transcoder.transcode_image_level(
                    level_index, 0, 0, observation.rgba.data(),
                    static_cast<uint32_t>(pixels),
                    basist::transcoder_texture_format::cTFRGBA32, 0, 0, 0,
                    -1, -1, &state);
          } else {
            observation.decoded = false;
          }
        } else {
          observation.decoded = false;
        }
        if (!observation.decoded) break;
      }
    }
    state.clear();
  }
  observation.allocation_attempts = probe->allocation_attempts();
  observation.heap_attempts = probe->heap_attempts();
  observation.allocations = probe->allocations();
  observation.releases = probe->releases();
  observation.reservation_attempts = probe->reservation_attempts();
  observation.reservations = probe->reservation_count();
  observation.reservation_releases = probe->reservation_releases();
  observation.peak_bytes = probe->peak_bytes();
  observation.live_bytes = probe->live_bytes();
  observation.owners = probe->owners();
  observation.checkpoints = probe->checkpoints();
  observation.allocation_failed = probe->allocation_failed();
  observation.stop_reason = probe->stop_reason();
  return observation;
}

bool ControlCleanupIsBalanced(const ControlPathObservation& observation) {
  return observation.allocations == observation.releases &&
         observation.reservations == observation.reservation_releases &&
         observation.live_bytes == 0 && observation.owners == 0;
}

bool FreshControlSucceeds(const std::vector<uint8_t>& bytes,
                          bool all_levels = false) {
  ProbeControl fresh;
  const ControlPathObservation observation =
      ObserveControlPath(bytes, &fresh, all_levels);
  return observation.initialized && observation.started &&
         observation.decoded && observation.allocations > 0 &&
         observation.allocation_attempts == observation.allocations &&
         observation.stop_reason == ProbeControl::StopReason::kNone &&
         !observation.allocation_failed &&
         ControlCleanupIsBalanced(observation);
}

class CancellingHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  explicit CancellingHeap(size_t cancel_ordinal)
      : cancel_ordinal_(cancel_ordinal) {}

  void SetControl(fsv_basisu::FsvDecodeControl* control) { control_ = control; }

  void* Allocate(size_t bytes, size_t) noexcept override {
    allocations_ += 1;
    if (allocations_ == cancel_ordinal_ && control_ != nullptr) {
      control_->Cancel();
    }
    return std::malloc(bytes == 0 ? 1 : bytes);
  }

  void Release(void* pointer, size_t, size_t) noexcept override {
    std::free(pointer);
    releases_ += 1;
  }

  size_t allocations() const { return allocations_; }
  size_t releases() const { return releases_; }

 private:
  size_t cancel_ordinal_;
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
  size_t allocations_ = 0;
  size_t releases_ = 0;
};

class FailingHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  explicit FailingHeap(size_t fail_ordinal) : fail_ordinal_(fail_ordinal) {}

  void* Allocate(size_t bytes, size_t) noexcept override {
    attempts_ += 1;
    if (fail_ordinal_ != 0 && attempts_ == fail_ordinal_) return nullptr;
    void* pointer = std::malloc(bytes == 0 ? 1 : bytes);
    if (pointer != nullptr) allocations_ += 1;
    return pointer;
  }

  void Release(void* pointer, size_t, size_t) noexcept override {
    std::free(pointer);
    releases_ += 1;
  }

  size_t attempts() const { return attempts_; }
  size_t allocations() const { return allocations_; }
  size_t releases() const { return releases_; }

 private:
  size_t fail_ordinal_;
  size_t attempts_ = 0;
  size_t allocations_ = 0;
  size_t releases_ = 0;
};

bool BridgeCancellationAtAllocationIsTyped(const std::vector<uint8_t>& bytes,
                                           size_t ordinal) {
  CancellingHeap heap(ordinal);
  fsv_basisu::FsvDecodeControl control(
      std::numeric_limits<uint64_t>::max(), &heap);
  heap.SetControl(&control);
  const FsvBasisuTranscodeResult result = FsvBasisuTranscodeImages(
      {RequestFor(bytes)}, Budget(), BudgetState(), &control);
  const bool first_reason =
      !control.Deadline() &&
      control.stop_reason() ==
          fsv_basisu::FsvDecodeStopReason::kCallerCancelled;
  return result.decoded_images.empty() && result.diagnostics.empty() &&
         first_reason && control.live_bytes() == 0 &&
         control.request_allocation_count() ==
             control.request_release_count() &&
         control.release_mismatch_count() == 0 &&
         heap.allocations() == heap.releases();
}

int RunPartialMetadataCancellation(const std::vector<uint8_t>& bytes) {
  const char* stages[] = {"metadataLevelIndex", "metadataDfd",
                          "metadataKvdOuter", "metadataKvdEntry"};
  bool stages_ok = true;
  bool fresh_ok = true;
  bool typed_bridge_ok = true;
  size_t previous_allocations = 0;
  for (const char* stage : stages) {
    ProbeControl cancelled;
    cancelled.CancelAtCheckpoint(stage);
    const ControlPathObservation stopped = ObserveControlPath(bytes, &cancelled);
    cancelled.InjectHeapStop();
    const bool first_reason =
        cancelled.stop_reason() == ProbeControl::StopReason::kCancelled;
    const bool stage_ok = !stopped.initialized && !stopped.started &&
                          !stopped.decoded && stopped.allocations > 0 &&
                          stopped.allocations > previous_allocations &&
                          stopped.stop_reason ==
                              ProbeControl::StopReason::kCancelled &&
                          first_reason && ControlCleanupIsBalanced(stopped);
    previous_allocations = stopped.allocations;
    stages_ok = stages_ok && stage_ok;
    fresh_ok = fresh_ok && FreshControlSucceeds(bytes);
  }
  for (size_t ordinal = 1; ordinal <= 4; ordinal += 1) {
    typed_bridge_ok = typed_bridge_ok &&
                      BridgeCancellationAtAllocationIsTyped(bytes, ordinal);
  }
  if (!stages_ok || !typed_bridge_ok || !fresh_ok) {
    std::cerr << "partial-metadata-cancel-red stages=" << stages_ok
              << " typedBridge=" << typed_bridge_ok
              << " fresh=" << fresh_ok
              << " finalAllocations=" << previous_allocations << "\n";
    return 153;
  }
  std::cout << "partial-metadata-cancel-contract-ok stages=4"
            << " typedAllocations=4\n";
  return 0;
}

int RunFailureControlMatrix(const std::vector<uint8_t>& bytes,
                            const char* label, int red_exit,
                            bool all_levels = false) {
  ProbeControl baseline_probe;
  const ControlPathObservation baseline =
      ObserveControlPath(bytes, &baseline_probe, all_levels);
  const bool baseline_ok =
      baseline.initialized && baseline.started && baseline.decoded &&
      baseline.allocations > 0 &&
      baseline.allocation_attempts == baseline.allocations &&
      baseline.heap_attempts == baseline.allocations &&
      baseline.stop_reason == ProbeControl::StopReason::kNone &&
      !baseline.allocation_failed && ControlCleanupIsBalanced(baseline);

  bool ordinals_ok = baseline.allocations > 0;
  bool ordinal_fresh_ok = baseline.allocations > 0;
  for (size_t ordinal = 1; ordinal <= baseline.allocations; ordinal += 1) {
    ProbeControl failing(std::numeric_limits<size_t>::max(), ordinal);
    const ControlPathObservation failed =
        ObserveControlPath(bytes, &failing, all_levels);
    ordinals_ok =
        ordinals_ok && !failed.decoded &&
        failed.allocation_attempts == ordinal &&
        failed.heap_attempts == ordinal && failed.allocations + 1U == ordinal &&
        failed.stop_reason == ProbeControl::StopReason::kHeap &&
        failed.allocation_failed && ControlCleanupIsBalanced(failed);
    ordinal_fresh_ok =
        ordinal_fresh_ok && FreshControlSucceeds(bytes, all_levels);
  }

  bool exact_peak_ok = false;
  bool tight_budget_ok = false;
  bool budget_fresh_ok = false;
  // A legacy reservation-only peak is not direct allocator evidence. Defer
  // exact/tight replays until the baseline observes at least one owned vector
  // allocation; otherwise the old Zstd envelope could mask this RED.
  if (baseline.allocations > 0 && baseline.peak_bytes > 0) {
    ProbeControl exact_peak(baseline.peak_bytes);
    const ControlPathObservation exact =
        ObserveControlPath(bytes, &exact_peak, all_levels);
    exact_peak_ok = exact.decoded &&
                    exact.allocations == baseline.allocations &&
                    exact.peak_bytes == baseline.peak_bytes &&
                    exact.stop_reason == ProbeControl::StopReason::kNone &&
                    ControlCleanupIsBalanced(exact);

    ProbeControl tight(baseline.peak_bytes - 1U);
    const ControlPathObservation rejected =
        ObserveControlPath(bytes, &tight, all_levels);
    tight_budget_ok =
        !rejected.decoded &&
        rejected.stop_reason == ProbeControl::StopReason::kBudget &&
        rejected.heap_attempts == rejected.allocations &&
        !rejected.allocation_failed && ControlCleanupIsBalanced(rejected);
    budget_fresh_ok = FreshControlSucceeds(bytes, all_levels);
  }

  ProbeControl cancelled_before;
  cancelled_before.Cancel();
  const ControlPathObservation before =
      ObserveControlPath(bytes, &cancelled_before, all_levels);
  const bool cancel_before_ok =
      !before.initialized && !before.decoded && before.allocations == 0 &&
      before.stop_reason == ProbeControl::StopReason::kCancelled &&
      ControlCleanupIsBalanced(before);
  const bool cancel_before_fresh_ok = FreshControlSucceeds(bytes, all_levels);

  ProbeControl cancelled_later;
  cancelled_later.CancelAtCheckpoint("metadata");
  const ControlPathObservation later =
      ObserveControlPath(bytes, &cancelled_later, all_levels);
  cancelled_later.InjectHeapStop();
  const bool first_reason_ok =
      cancelled_later.stop_reason() == ProbeControl::StopReason::kCancelled;
  const bool cancel_later_ok =
      !later.initialized && !later.decoded && later.allocations > 0 &&
      later.stop_reason == ProbeControl::StopReason::kCancelled &&
      ControlCleanupIsBalanced(later);
  const bool cancel_later_fresh_ok = FreshControlSucceeds(bytes, all_levels);

  ProbeControl heap_failure(std::numeric_limits<size_t>::max(), 1);
  const ControlPathObservation heap =
      ObserveControlPath(bytes, &heap_failure, all_levels);
  const bool heap_ok =
      !heap.decoded && heap.allocation_attempts == 1 &&
      heap.heap_attempts == 1 && heap.allocations == 0 &&
      heap.stop_reason == ProbeControl::StopReason::kHeap &&
      heap.allocation_failed && ControlCleanupIsBalanced(heap);
  const bool heap_fresh_ok = FreshControlSucceeds(bytes, all_levels);

  const bool fresh_ok = ordinal_fresh_ok && budget_fresh_ok &&
                        cancel_before_fresh_ok && cancel_later_fresh_ok &&
                        heap_fresh_ok;
  if (!baseline_ok || !ordinals_ok || !exact_peak_ok || !tight_budget_ok ||
      !cancel_before_ok || !cancel_later_ok || !first_reason_ok || !heap_ok ||
      !fresh_ok) {
    std::cerr << "failure-control-" << label
              << "-red direct=" << baseline.allocations
              << " attempts=" << baseline.allocation_attempts
              << " reservations=" << baseline.reservations
              << " reservationAttempts=" << baseline.reservation_attempts
              << " peak=" << baseline.peak_bytes
              << " baseline=" << baseline_ok
              << " ordinals=" << ordinals_ok
              << " exactPeak=" << exact_peak_ok
              << " peakMinusOne=" << tight_budget_ok
              << " cancelBefore=" << cancel_before_ok
              << " cancelLater=" << cancel_later_ok
              << " firstReason=" << first_reason_ok << " heap=" << heap_ok
              << " fresh=" << fresh_ok
              << " cleanup=" << ControlCleanupIsBalanced(baseline) << "\n";
    return red_exit;
  }
  std::cout << "failure-control-" << label
            << "-contract-ok direct=" << baseline.allocations
            << " peak=" << baseline.peak_bytes << "\n";
  return 0;
}

bool MetadataBoundTo(const basist::ktx2_transcoder& transcoder,
                     basisu::fsv_vector_allocator* allocator) {
  bool nested = true;
  for (const auto& key_value : transcoder.get_key_values()) {
    nested = nested && key_value.m_key.fsv_allocator() == allocator &&
             key_value.m_value.fsv_allocator() == allocator;
  }
  return transcoder.get_level_index().fsv_allocator() == allocator &&
         transcoder.get_dfd().fsv_allocator() == allocator &&
         transcoder.get_key_values().fsv_allocator() == allocator &&
         transcoder.get_etc1s_image_descs().fsv_allocator() == allocator &&
         nested;
}

bool DecodeInitializedTranscoder(basist::ktx2_transcoder* transcoder,
                                 basist::ktx2_transcoder_state* state,
                                 std::vector<uint8_t>* rgba) {
  if (!transcoder->start_transcoding()) return false;
  basist::ktx2_image_level_info level_info;
  if (!transcoder->get_image_level_info(level_info, 0, 0, 0)) return false;
  const uint64_t pixels =
      static_cast<uint64_t>(level_info.m_orig_width) *
      level_info.m_orig_height;
  if (pixels > std::numeric_limits<uint32_t>::max() ||
      pixels > std::numeric_limits<size_t>::max() / 4U) {
    return false;
  }
  rgba->assign(static_cast<size_t>(pixels) * 4U, 0);
  return transcoder->transcode_image_level(
      0, 0, 0, rgba->data(), static_cast<uint32_t>(pixels),
      basist::transcoder_texture_format::cTFRGBA32, 0, 0, 0, -1, -1, state);
}

bool ProbeIsBalanced(const ProbeControl& probe) {
  return probe.allocations() == probe.releases() &&
         probe.reservation_count() == probe.reservation_releases() &&
         probe.live_bytes() == 0 && probe.owners() == 0 &&
         probe.release_mismatches() == 0;
}

int RunDefaultStateReuse(const std::vector<uint8_t>& bytes) {
  ProbeControl first;
  ProbeControl second;
  bool first_initialized = false;
  bool second_initialized = false;
  bool first_metadata = false;
  bool second_metadata = false;
  bool first_decoded = false;
  bool second_decoded = false;
  size_t first_init_allocations = 0;
  size_t second_init_allocations = 0;
  size_t first_allocations_before_second = 0;
  size_t first_releases_before_second = 0;
  std::vector<uint8_t> first_rgba;
  std::vector<uint8_t> second_rgba;
  {
    basist::ktx2_transcoder transcoder;
    transcoder.set_fsv_transcode_control(&first);
    first_initialized = transcoder.init(
        bytes.data(), static_cast<uint32_t>(bytes.size()));
    if (first_initialized) {
      first_metadata = MetadataBoundTo(transcoder, &first);
      first_init_allocations = first.allocations();
      first_decoded =
          DecodeInitializedTranscoder(&transcoder, nullptr, &first_rgba);
    }
    transcoder.clear();
    first_allocations_before_second = first.allocations();
    first_releases_before_second = first.releases();

    transcoder.set_fsv_transcode_control(&second);
    second_initialized = transcoder.init(
        bytes.data(), static_cast<uint32_t>(bytes.size()));
    if (second_initialized) {
      second_metadata = MetadataBoundTo(transcoder, &second);
      second_init_allocations = second.allocations();
      second_decoded =
          DecodeInitializedTranscoder(&transcoder, nullptr, &second_rgba);
    }
    transcoder.clear();
  }
  const bool state_allocated =
      first.allocations() > first_init_allocations &&
      second.allocations() > second_init_allocations;
  const bool no_cross =
      first.allocations() == first_allocations_before_second &&
      first.releases() == first_releases_before_second &&
      first.release_mismatches() == 0 && second.release_mismatches() == 0;
  const bool deterministic = first.allocations() == second.allocations() &&
                             first.peak_bytes() == second.peak_bytes();
  const bool parity = !first_rgba.empty() && first_rgba == second_rgba;
  const bool cleanup = ProbeIsBalanced(first) && ProbeIsBalanced(second);
  if (!first_initialized || !second_initialized || !first_metadata ||
      !second_metadata || !first_decoded || !second_decoded ||
      !state_allocated || !no_cross || !deterministic || !parity || !cleanup) {
    std::cerr << "reuse-default-red firstInit=" << first_initialized
              << " secondInit=" << second_initialized
              << " firstMetadata=" << first_metadata
              << " secondMetadata=" << second_metadata
              << " firstDecoded=" << first_decoded
              << " secondDecoded=" << second_decoded
              << " firstDirect=" << first.allocations()
              << " secondDirect=" << second.allocations()
              << " state=" << state_allocated << " noCross=" << no_cross
              << " deterministic=" << deterministic << " parity=" << parity
              << " firstLive=" << first.live_bytes()
              << " secondLive=" << second.live_bytes()
              << " firstOwners=" << first.owners()
              << " secondOwners=" << second.owners()
              << " cleanup=" << cleanup << "\n";
    return 150;
  }
  std::cout << "reuse-default-contract-ok direct=" << first.allocations()
            << "\n";
  return 0;
}

int RunExplicitStateReuse(const std::vector<uint8_t>& bytes) {
  ProbeControl first;
  ProbeControl second;
  bool first_initialized = false;
  bool second_initialized = false;
  bool first_metadata = false;
  bool second_metadata = false;
  bool first_decoded = false;
  bool second_decoded = false;
  bool first_state = false;
  bool second_state = false;
  size_t first_init_allocations = 0;
  size_t second_init_allocations = 0;
  size_t first_allocations_before_second = 0;
  size_t first_releases_before_second = 0;
  std::vector<uint8_t> first_rgba;
  std::vector<uint8_t> second_rgba;
  {
    basist::ktx2_transcoder_state state;
    state.clear();
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(&first);
      first_initialized = transcoder.init(
          bytes.data(), static_cast<uint32_t>(bytes.size()));
      if (first_initialized) {
        first_metadata = MetadataBoundTo(transcoder, &first);
        first_init_allocations = first.allocations();
        first_decoded =
            DecodeInitializedTranscoder(&transcoder, &state, &first_rgba);
        first_state = state.m_level_uncomp_data.fsv_allocator() == nullptr;
      }
      state.clear();
      transcoder.clear();
      first_allocations_before_second = first.allocations();
      first_releases_before_second = first.releases();

      transcoder.set_fsv_transcode_control(&second);
      second_initialized = transcoder.init(
          bytes.data(), static_cast<uint32_t>(bytes.size()));
      if (second_initialized) {
        second_metadata = MetadataBoundTo(transcoder, &second);
        second_init_allocations = second.allocations();
        second_decoded =
            DecodeInitializedTranscoder(&transcoder, &state, &second_rgba);
        second_state = state.m_level_uncomp_data.fsv_allocator() == nullptr;
      }
      state.clear();
      transcoder.clear();
    }
  }
  const bool state_allocated =
      first.allocations() > first_init_allocations &&
      second.allocations() > second_init_allocations;
  const bool no_cross =
      first.allocations() == first_allocations_before_second &&
      first.releases() == first_releases_before_second &&
      first.release_mismatches() == 0 && second.release_mismatches() == 0;
  const bool parity = !first_rgba.empty() && first_rgba == second_rgba;
  const bool cleanup = ProbeIsBalanced(first) && ProbeIsBalanced(second);
  if (!first_initialized || !second_initialized || !first_metadata ||
      !second_metadata || !first_decoded || !second_decoded || !first_state ||
      !second_state || !state_allocated || !no_cross || !parity || !cleanup) {
    std::cerr << "reuse-explicit-red firstInit=" << first_initialized
              << " secondInit=" << second_initialized
              << " firstMetadata=" << first_metadata
              << " secondMetadata=" << second_metadata
              << " firstDecoded=" << first_decoded
              << " secondDecoded=" << second_decoded
              << " firstState=" << first_state
              << " secondState=" << second_state
              << " firstDirect=" << first.allocations()
              << " secondDirect=" << second.allocations()
              << " stateAllocated=" << state_allocated
              << " noCross=" << no_cross << " parity=" << parity
              << " firstLive=" << first.live_bytes()
              << " secondLive=" << second.live_bytes()
              << " firstOwners=" << first.owners()
              << " secondOwners=" << second.owners()
              << " cleanup=" << cleanup << "\n";
    return 151;
  }
  std::cout << "reuse-explicit-contract-ok direct=" << first.allocations()
            << "\n";
  return 0;
}

int RunExplicitStateOutlivesControls(const std::vector<uint8_t>& bytes) {
  basist::ktx2_transcoder_state state;
  state.clear();
  std::vector<uint8_t> first_rgba;
  std::vector<uint8_t> second_rgba;
  bool first_ok = false;
  bool second_ok = false;
  size_t first_allocations = 0;
  size_t first_releases = 0;
  for (int request = 0; request < 2; request += 1) {
    ProbeControl control;
    bool initialized = false;
    bool decoded = false;
    size_t init_allocations = 0;
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(&control);
      initialized = transcoder.init(bytes.data(),
                                     static_cast<uint32_t>(bytes.size()));
      init_allocations = control.allocations();
      if (initialized) {
        decoded = DecodeInitializedTranscoder(
            &transcoder, &state, request == 0 ? &first_rgba : &second_rgba);
      }
      transcoder.clear();
    }
    const bool state_allocated = control.allocations() > init_allocations;
    const bool unbound = state.m_level_uncomp_data.fsv_allocator() == nullptr;
    const bool balanced = ProbeIsBalanced(control);
    const bool request_ok = initialized && decoded && state_allocated &&
                            unbound && balanced;
    if (!unbound) {
      // Keep the RED diagnostic deterministic instead of allowing the stale
      // test allocator to be dereferenced after this scope.
      state.set_fsv_vector_allocator(nullptr);
    }
    if (request == 0) {
      first_ok = request_ok;
      first_allocations = control.allocations();
      first_releases = control.releases();
    } else {
      second_ok = request_ok && first_allocations == first_releases;
    }
  }
  state.clear();
  const bool parity = !first_rgba.empty() && first_rgba == second_rgba;
  const bool state_safe = state.m_level_uncomp_data.fsv_allocator() == nullptr;
  if (!first_ok || !second_ok || !parity || !state_safe) {
    std::cerr << "state-outlives-controls-red first=" << first_ok
              << " second=" << second_ok << " parity=" << parity
              << " stateSafe=" << state_safe << "\n";
    return 154;
  }
  std::cout << "state-outlives-controls-contract-ok requests=2\n";
  return 0;
}

struct ConcurrentObservation {
  bool initialized = false;
  bool decoded = false;
  bool metadata_bound = false;
  bool state_bound = false;
  size_t allocations = 0;
  size_t releases = 0;
  size_t live_bytes = 0;
  size_t owners = 0;
  size_t mismatches = 0;
  ProbeControl::StopReason stop_reason = ProbeControl::StopReason::kNone;
  std::vector<uint8_t> rgba;
};

void ObserveConcurrentPath(const std::vector<uint8_t>& bytes,
                           ProbeControl* probe, bool cancel_at_metadata,
                           ConcurrentObservation* observation) {
  if (cancel_at_metadata) probe->CancelAtCheckpoint("metadata");
  {
    basist::ktx2_transcoder_state state;
    state.clear();
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(probe);
      observation->initialized = transcoder.init(
          bytes.data(), static_cast<uint32_t>(bytes.size()));
      observation->metadata_bound = MetadataBoundTo(transcoder, probe);
      if (observation->initialized) {
        observation->decoded =
            DecodeInitializedTranscoder(&transcoder, &state,
                                         &observation->rgba);
        observation->state_bound =
            state.m_level_uncomp_data.fsv_allocator() == nullptr;
      }
      state.clear();
      transcoder.clear();
    }
  }
  observation->allocations = probe->allocations();
  observation->releases = probe->releases();
  observation->live_bytes = probe->live_bytes();
  observation->owners = probe->owners();
  observation->mismatches = probe->release_mismatches();
  observation->stop_reason = probe->stop_reason();
}

int RunConcurrentIsolation(const std::vector<uint8_t>& bytes) {
  ProbeControl cancelled;
  ProbeControl unaffected;
  ConcurrentObservation stopped;
  ConcurrentObservation succeeded;
  std::thread stopped_thread(ObserveConcurrentPath, std::cref(bytes),
                             &cancelled, true, &stopped);
  std::thread succeeded_thread(ObserveConcurrentPath, std::cref(bytes),
                               &unaffected, false, &succeeded);
  stopped_thread.join();
  succeeded_thread.join();
  const bool stopped_ok =
      !stopped.initialized && !stopped.decoded && stopped.metadata_bound &&
      stopped.allocations > 0 && stopped.allocations == stopped.releases &&
      stopped.stop_reason == ProbeControl::StopReason::kCancelled &&
      stopped.live_bytes == 0 && stopped.owners == 0 &&
      stopped.mismatches == 0;
  const bool succeeded_ok =
      succeeded.initialized && succeeded.decoded &&
      succeeded.metadata_bound && succeeded.state_bound &&
      succeeded.allocations > 0 &&
      succeeded.allocations == succeeded.releases &&
      succeeded.stop_reason == ProbeControl::StopReason::kNone &&
      succeeded.live_bytes == 0 && succeeded.owners == 0 &&
      succeeded.mismatches == 0 && !succeeded.rgba.empty();
  const bool distinct = &cancelled != &unaffected &&
                        cancelled.allocations() == stopped.allocations &&
                        unaffected.allocations() == succeeded.allocations;
  const bool fresh = FreshControlSucceeds(bytes);
  if (!stopped_ok || !succeeded_ok || !distinct || !fresh) {
    std::cerr << "concurrency-red stoppedInit=" << stopped.initialized
              << " stoppedMetadata=" << stopped.metadata_bound
              << " stoppedDirect=" << stopped.allocations
              << " stoppedReleases=" << stopped.releases
              << " stoppedReason="
              << (stopped.stop_reason == ProbeControl::StopReason::kCancelled)
              << " succeededInit=" << succeeded.initialized
              << " succeededDecoded=" << succeeded.decoded
              << " succeededMetadata=" << succeeded.metadata_bound
              << " succeededState=" << succeeded.state_bound
              << " succeededDirect=" << succeeded.allocations
              << " succeededReleases=" << succeeded.releases
              << " succeededReasonNone="
              << (succeeded.stop_reason == ProbeControl::StopReason::kNone)
              << " distinct=" << distinct << " fresh=" << fresh
              << " stoppedLive=" << stopped.live_bytes
              << " succeededLive=" << succeeded.live_bytes
              << " stoppedOwners=" << stopped.owners
              << " succeededOwners=" << succeeded.owners << "\n";
    return 152;
  }
  std::cout << "concurrency-contract-ok stoppedDirect="
            << stopped.allocations
            << " succeededDirect=" << succeeded.allocations << "\n";
  return 0;
}

std::vector<uint8_t> WithInvalidLevelOffset(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe64(&result, 80, 0);
  return result;
}

std::vector<uint8_t> WithTruncatedLevelIndex(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  result.resize(103);
  return result;
}

std::vector<uint8_t> WithInvalidDfdRange(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe32(&result, 48, static_cast<uint32_t>(result.size() - 4U));
  SetLe32(&result, 52, 44);
  return result;
}

std::vector<uint8_t> WithInvalidDfdStructure(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  const uint32_t dfd_offset = ReadLe32(result, 48);
  SetLe32(&result, dfd_offset, 0);
  return result;
}

std::vector<uint8_t> WithInvalidKvdRange(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe32(&result, 56, static_cast<uint32_t>(result.size() - 2U));
  return result;
}

std::vector<uint8_t> WithInvalidKvdEntry(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe32(&result, ReadLe32(result, 56), 1);
  return result;
}

std::vector<uint8_t> WithUnsortedKvd(const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  const uint32_t kvd_offset = ReadLe32(result, 56);
  const uint32_t first_length = ReadLe32(result, kvd_offset);
  const size_t second_offset =
      kvd_offset + 4U + first_length + ((4U - (first_length & 3U)) & 3U);
  const uint8_t late_name[] = {'z', 0};
  const uint8_t early_name[] = {'a', 0};
  std::memcpy(result.data() + kvd_offset + 4U, late_name,
              sizeof(late_name));
  std::memcpy(result.data() + second_offset + 4U, early_name,
              sizeof(early_name));
  return result;
}

std::vector<uint8_t> WithNonzeroKvdPadding(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  const uint32_t kvd_offset = ReadLe32(result, 56);
  const uint32_t kvd_length = ReadLe32(result, 60);
  if (kvd_length != 0) result[kvd_offset + kvd_length - 1U] = 1U;
  return result;
}

void AppendKvdEntry(std::vector<uint8_t>* kvd, const std::string& key,
                    const std::vector<uint8_t>& value) {
  const uint32_t payload_length =
      static_cast<uint32_t>(key.size() + 1U + value.size());
  const uint32_t padding = (4U - (payload_length & 3U)) & 3U;
  const size_t start = kvd->size();
  kvd->resize(start + 4U + payload_length + padding, 0);
  SetLe32(kvd, start, payload_length);
  std::memcpy(kvd->data() + start + 4U, key.data(), key.size());
  if (!value.empty()) {
    std::memcpy(kvd->data() + start + 4U + key.size() + 1U, value.data(),
                value.size());
  }
}

std::vector<uint8_t> WithKvdEntries(const std::vector<uint8_t>& source,
                                    const std::vector<std::string>& keys) {
  const uint32_t kvd_offset = ReadLe32(source, 56);
  const uint32_t old_length = ReadLe32(source, 60);
  if (kvd_offset == 0 ||
      static_cast<uint64_t>(kvd_offset) + old_length > source.size()) {
    return {};
  }
  std::vector<uint8_t> kvd;
  for (size_t index = 0; index < keys.size(); index += 1) {
    AppendKvdEntry(&kvd, keys[index],
                   {static_cast<uint8_t>(index + 1U)});
  }
  std::vector<uint8_t> result = source;
  result.erase(result.begin() + kvd_offset,
               result.begin() + kvd_offset + old_length);
  result.insert(result.begin() + kvd_offset, kvd.begin(), kvd.end());
  SetLe32(&result, 60, static_cast<uint32_t>(kvd.size()));

  const int64_t delta = static_cast<int64_t>(kvd.size()) - old_length;
  const uint32_t declared_levels = ReadLe32(result, 40);
  const uint32_t level_count = declared_levels == 0 ? 1 : declared_levels;
  const uint64_t old_end = static_cast<uint64_t>(kvd_offset) + old_length;
  for (uint32_t level = 0; level < level_count; level += 1) {
    const size_t entry_offset = 80U + static_cast<size_t>(level) * 24U;
    const uint64_t level_offset = ReadLe64(result, entry_offset);
    if (level_offset >= old_end) {
      SetLe64(&result, entry_offset,
              static_cast<uint64_t>(static_cast<int64_t>(level_offset) +
                                    delta));
    }
  }
  const uint64_t sgd_offset = ReadLe64(result, 64);
  if (sgd_offset >= old_end && sgd_offset != 0) {
    SetLe64(&result, 64,
            static_cast<uint64_t>(static_cast<int64_t>(sgd_offset) + delta));
  }
  return result;
}

std::vector<uint8_t> WithManyOrderedKvdEntries(
    const std::vector<uint8_t>& source) {
  std::vector<std::string> keys;
  for (int index = 0; index < 12; index += 1) {
    keys.push_back(std::string("fsv") + (index < 10 ? "0" : "") +
                   std::to_string(index));
  }
  return WithKvdEntries(source, keys);
}

std::vector<uint8_t> WithOverflowingLevelRange(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe64(&result, 80, std::numeric_limits<uint64_t>::max() - 3U);
  SetLe64(&result, 88, 16);
  return result;
}

std::vector<uint8_t> WithOverflowingDfdRange(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe32(&result, 48, std::numeric_limits<uint32_t>::max() - 15U);
  SetLe32(&result, 52, 44);
  return result;
}

std::vector<uint8_t> WithOverflowingKvdRange(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = source;
  SetLe32(&result, 56, std::numeric_limits<uint32_t>::max() - 15U);
  SetLe32(&result, 60, 64);
  return result;
}

std::vector<uint8_t> WithMissingKeyTerminator(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = WithKvdEntries(source, {"unterminated"});
  if (result.empty()) return result;
  const uint32_t kvd_offset = ReadLe32(result, 56);
  const uint32_t entry_length = ReadLe32(result, kvd_offset);
  std::fill(result.begin() + kvd_offset + 4U,
            result.begin() + kvd_offset + 4U + entry_length, 0x61U);
  return result;
}

std::vector<uint8_t> WithTruncatedValue(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = WithKvdEntries(source, {"value"});
  if (result.empty()) return result;
  const uint32_t kvd_offset = ReadLe32(result, 56);
  const uint32_t entry_length = ReadLe32(result, kvd_offset);
  SetLe32(&result, 60, 4U + entry_length - 1U);
  return result;
}

std::vector<uint8_t> WithOverflowingValue(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> result = WithKvdEntries(source, {"value"});
  if (result.empty()) return result;
  SetLe32(&result, ReadLe32(result, 56),
          std::numeric_limits<uint32_t>::max());
  return result;
}

std::vector<uint8_t> WithDuplicateKvdKey(
    const std::vector<uint8_t>& source) {
  return WithKvdEntries(source, {"duplicate", "duplicate"});
}

int RunRequiredMalformedMatrix(const std::vector<uint8_t>& bytes) {
  const std::vector<uint8_t> level = WithOverflowingLevelRange(bytes);
  const std::vector<uint8_t> dfd = WithOverflowingDfdRange(bytes);
  const std::vector<uint8_t> kvd = WithOverflowingKvdRange(bytes);
  const std::vector<uint8_t> missing_key = WithMissingKeyTerminator(bytes);
  const std::vector<uint8_t> truncated_value = WithTruncatedValue(bytes);
  const std::vector<uint8_t> overflowing_value = WithOverflowingValue(bytes);
  const std::vector<uint8_t> duplicate = WithDuplicateKvdKey(bytes);
  const bool diagnostics =
      HasMalformedDiagnostic(level, "ktx2LevelIndex") &&
      HasMalformedDiagnostic(dfd, "ktx2Dfd") &&
      HasMalformedDiagnostic(kvd, "ktx2KeyValueData") &&
      HasMalformedDiagnostic(missing_key, "ktx2KeyValueData") &&
      HasMalformedDiagnostic(truncated_value, "ktx2KeyValueData") &&
      HasMalformedDiagnostic(overflowing_value, "ktx2KeyValueData") &&
      HasMalformedDiagnostic(duplicate, "ktx2KeyValueData");
  const DirectMalformedObservation direct_level = ObserveDirectMalformed(level);
  const DirectMalformedObservation direct_key =
      ObserveDirectMalformed(missing_key);
  const DirectMalformedObservation direct_value =
      ObserveDirectMalformed(overflowing_value);
  const DirectMalformedObservation direct_duplicate =
      ObserveDirectMalformed(duplicate);
  const bool cleanup = !direct_level.initialized &&
                       DirectCleanupOnly(direct_level) &&
                       DirectCleanupOnly(direct_key) &&
                       DirectCleanupOnly(direct_value) &&
                       DirectCleanupOnly(direct_duplicate);
  if (!diagnostics || !cleanup || missing_key.empty() ||
      truncated_value.empty() || overflowing_value.empty() ||
      duplicate.empty()) {
    std::cerr << "malformed-required-red diagnostics=" << diagnostics
              << " cleanup=" << cleanup
              << " levelInit=" << direct_level.initialized
              << " levelAllocations=" << direct_level.allocations
              << " keyAllocations=" << direct_key.allocations
              << " valueAllocations=" << direct_value.allocations
              << " duplicateAllocations=" << direct_duplicate.allocations
              << "\n";
    return 155;
  }
  std::cout << "malformed-required-contract-ok cases=7\n";
  return 0;
}

size_t FindKvdRelocationOrdinal(const ProbeControl& probe) {
  const size_t expected_bytes =
      16U * sizeof(basist::ktx2_transcoder::key_value);
  const std::vector<size_t>& sizes = probe.allocation_sizes();
  for (size_t index = 0; index < sizes.size(); index += 1) {
    if (sizes[index] == expected_bytes) return index + 1U;
  }
  return 0;
}

int RunKvdRelocationMatrix(const std::vector<uint8_t>& source) {
  const std::vector<uint8_t> bytes = WithManyOrderedKvdEntries(source);
  if (bytes.empty()) return 156;

  ProbeControl original_probe;
  const ControlPathObservation original =
      ObserveControlPath(source, &original_probe);
  ProbeControl baseline_probe;
  const ControlPathObservation baseline =
      ObserveControlPath(bytes, &baseline_probe);
  const size_t relocation_ordinal = FindKvdRelocationOrdinal(baseline_probe);
  const bool baseline_ok = baseline.initialized && baseline.started &&
                           baseline.decoded &&
                           baseline.rgba == original.rgba &&
                           baseline.stop_reason ==
                               ProbeControl::StopReason::kNone &&
                           ControlCleanupIsBalanced(baseline);

  bool ordinals_ok = baseline.allocations > 0;
  for (size_t ordinal = 1; ordinal <= baseline.allocations; ordinal += 1) {
    ProbeControl failing(std::numeric_limits<size_t>::max(), ordinal);
    const ControlPathObservation failed = ObserveControlPath(bytes, &failing);
    ordinals_ok =
        ordinals_ok && !failed.decoded &&
        failed.allocation_attempts == ordinal &&
        failed.heap_attempts == ordinal && failed.allocations + 1U == ordinal &&
        failed.stop_reason == ProbeControl::StopReason::kHeap &&
        failed.allocation_failed && ControlCleanupIsBalanced(failed);
  }

  ProbeControl relocation_heap(std::numeric_limits<size_t>::max(),
                               relocation_ordinal);
  const ControlPathObservation heap =
      ObserveControlPath(bytes, &relocation_heap);
  const bool heap_ok = relocation_ordinal > 0 && !heap.decoded &&
                       heap.allocation_attempts == relocation_ordinal &&
                       heap.stop_reason == ProbeControl::StopReason::kHeap &&
                       ControlCleanupIsBalanced(heap);

  ProbeControl relocation_cancel;
  relocation_cancel.CancelAtCheckpoint("metadataKvdRelocate");
  const ControlPathObservation cancelled =
      ObserveControlPath(bytes, &relocation_cancel);
  relocation_cancel.InjectHeapStop();
  const bool cancel_ok =
      !cancelled.initialized && !cancelled.decoded &&
      cancelled.stop_reason == ProbeControl::StopReason::kCancelled &&
      relocation_cancel.stop_reason() == ProbeControl::StopReason::kCancelled &&
      relocation_cancel.relocation_allocation_ordinal() == relocation_ordinal &&
      cancelled.allocation_attempts + 1U == relocation_ordinal &&
      ControlCleanupIsBalanced(cancelled);

  ProbeControl relocation_budget(std::numeric_limits<size_t>::max(), 0,
                                 relocation_ordinal);
  const ControlPathObservation budget =
      ObserveControlPath(bytes, &relocation_budget);
  const bool budget_ok = !budget.initialized && !budget.decoded &&
                         budget.stop_reason == ProbeControl::StopReason::kBudget &&
                         budget.allocation_attempts == relocation_ordinal &&
                         budget.heap_attempts + 1U == relocation_ordinal &&
                         ControlCleanupIsBalanced(budget);
  const bool fresh = FreshControlSucceeds(bytes);
  if (!baseline_ok || relocation_ordinal == 0 ||
      baseline_probe.relocation_allocation_ordinal() != relocation_ordinal ||
      !ordinals_ok || !heap_ok || !cancel_ok || !budget_ok || !fresh) {
    std::cerr << "kvd-relocation-red baseline=" << baseline_ok
              << " initialized=" << baseline.initialized
              << " originalInitialized=" << original.initialized
              << " checkpoints=" << baseline.checkpoints
              << " started=" << baseline.started
              << " decoded=" << baseline.decoded
              << " entries=12 direct=" << baseline.allocations
              << " attempts=" << baseline.allocation_attempts
              << " stop=" << static_cast<int>(baseline.stop_reason)
              << " owners=" << baseline.owners
              << " levelMove="
              << std::is_nothrow_move_constructible<
                     basist::ktx2_level_index>::value
              << " levelCopy="
              << std::is_nothrow_copy_constructible<
                     basist::ktx2_level_index>::value
              << " keyMove="
              << std::is_nothrow_move_constructible<
                     basist::ktx2_transcoder::key_value>::value
              << " keyCopy="
              << std::is_nothrow_copy_constructible<
                     basist::ktx2_transcoder::key_value>::value
              << " relocationOrdinal=" << relocation_ordinal
              << " checkpointOrdinal="
              << baseline_probe.relocation_allocation_ordinal()
              << " ordinals=" << ordinals_ok << " heap=" << heap_ok
              << " cancel=" << cancel_ok << " budget=" << budget_ok
              << " fresh=" << fresh << "\n";
    return 157;
  }
  std::cout << "kvd-relocation-contract-ok entries=12 direct="
            << baseline.allocations
            << " relocationOrdinal=" << relocation_ordinal << "\n";
  return 0;
}

struct Etc1sCodecObservation {
  bool initialized = false;
  bool started = false;
  bool alpha_matches = false;
  bool state_unbound = true;
  bool cleanup = false;
  size_t owners_after_bind = 0;
  size_t allocations_after_init = 0;
  size_t allocations_after_start = 0;
  size_t allocations_after_levels = 0;
  std::vector<size_t> level_allocation_deltas;
  std::vector<std::vector<uint8_t>> levels;
};

bool DecodeEtc1sWithoutControl(
    const std::vector<uint8_t>& bytes, bool expected_alpha,
    std::vector<std::vector<uint8_t>>* levels) {
  basist::ktx2_transcoder transcoder;
  if (!transcoder.init(bytes.data(), static_cast<uint32_t>(bytes.size())) ||
      !transcoder.is_etc1s() ||
      static_cast<bool>(transcoder.get_has_alpha()) != expected_alpha ||
      !transcoder.start_transcoding()) {
    return false;
  }
  basist::ktx2_transcoder_state state;
  state.clear();
  for (uint32_t level_index = 0; level_index < transcoder.get_levels();
       level_index += 1) {
    basist::ktx2_image_level_info info;
    if (!transcoder.get_image_level_info(info, level_index, 0, 0)) return false;
    const uint64_t pixels =
        static_cast<uint64_t>(info.m_orig_width) * info.m_orig_height;
    if (pixels > std::numeric_limits<uint32_t>::max() ||
        pixels > std::numeric_limits<size_t>::max() / 4U) {
      return false;
    }
    levels->emplace_back(static_cast<size_t>(pixels) * 4U, 0);
    if (!transcoder.transcode_image_level(
            level_index, 0, 0, levels->back().data(),
            static_cast<uint32_t>(pixels),
            basist::transcoder_texture_format::cTFRGBA32, 0, 0, 0, -1, -1,
            &state)) {
      return false;
    }
  }
  state.clear();
  return true;
}

Etc1sCodecObservation ObserveEtc1sCodecState(
    const std::vector<uint8_t>& bytes, bool expected_alpha) {
  ProbeControl probe;
  Etc1sCodecObservation observation;
  {
    basist::ktx2_transcoder transcoder;
    transcoder.set_fsv_transcode_control(&probe);
    observation.owners_after_bind = probe.owners();
    observation.initialized = transcoder.init(
        bytes.data(), static_cast<uint32_t>(bytes.size()));
    observation.allocations_after_init = probe.allocations();
    observation.alpha_matches =
        observation.initialized && transcoder.is_etc1s() &&
        static_cast<bool>(transcoder.get_has_alpha()) == expected_alpha;
    if (observation.initialized) {
      observation.started = transcoder.start_transcoding();
    }
    observation.allocations_after_start = probe.allocations();
    basist::ktx2_transcoder_state state;
    state.clear();
    if (observation.started) {
      for (uint32_t level_index = 0; level_index < transcoder.get_levels();
           level_index += 1) {
        basist::ktx2_image_level_info info;
        if (!transcoder.get_image_level_info(info, level_index, 0, 0)) break;
        const uint64_t pixels =
            static_cast<uint64_t>(info.m_orig_width) * info.m_orig_height;
        if (pixels > std::numeric_limits<uint32_t>::max() ||
            pixels > std::numeric_limits<size_t>::max() / 4U) {
          break;
        }
        observation.levels.emplace_back(static_cast<size_t>(pixels) * 4U, 0);
        const size_t allocations_before_level = probe.allocations();
        if (!transcoder.transcode_image_level(
                level_index, 0, 0, observation.levels.back().data(),
                static_cast<uint32_t>(pixels),
                basist::transcoder_texture_format::cTFRGBA32, 0, 0, 0, -1,
                -1, &state)) {
          observation.levels.pop_back();
          break;
        }
        observation.level_allocation_deltas.push_back(
            probe.allocations() - allocations_before_level);
        for (uint32_t alpha = 0; alpha < 2; alpha += 1) {
          observation.state_unbound =
              observation.state_unbound &&
              state.m_transcoder_state.m_block_endpoint_preds[alpha]
                      .fsv_allocator() == nullptr;
          for (uint32_t prior = 0;
               prior < basist::basisu_transcoder_state::cMaxPrevFrameLevels;
               prior += 1) {
            observation.state_unbound =
                observation.state_unbound &&
                state.m_transcoder_state.m_prev_frame_indices[alpha][prior]
                        .fsv_allocator() == nullptr;
          }
        }
      }
    }
    state.clear();
    observation.allocations_after_levels = probe.allocations();
  }
  observation.cleanup =
      probe.live_bytes() == 0 && probe.owners() == 0 &&
      probe.allocations() == probe.releases() &&
      probe.reservation_count() == probe.reservation_releases() &&
      probe.release_mismatches() == 0 && !probe.allocation_failed();
  return observation;
}

bool CorruptEtc1sSliceCleansUp(const std::vector<uint8_t>& source) {
  std::vector<uint8_t> bytes = source;
  const uint64_t sgd_offset = ReadLe64(bytes, 64);
  if (sgd_offset > bytes.size() || bytes.size() - sgd_offset < 32U) return false;
  // Keep global ETC1S codebooks valid so start_transcoding() reaches and owns
  // them, but move the RGB slice outside the source buffer. The codec rejects
  // this descriptor at its container-independent transcode boundary.
  SetLe32(&bytes, static_cast<size_t>(sgd_offset) + 24U, UINT32_MAX);
  ProbeControl probe;
  const ControlPathObservation corrupt = ObserveControlPath(bytes, &probe);
  return corrupt.initialized && corrupt.started && !corrupt.decoded &&
         corrupt.allocations > 0 && ControlCleanupIsBalanced(corrupt);
}

std::vector<uint8_t> WithCorruptEtc1sSlice(
    const std::vector<uint8_t>& source) {
  std::vector<uint8_t> bytes = source;
  const uint64_t sgd_offset = ReadLe64(bytes, 64);
  if (sgd_offset > bytes.size() || bytes.size() - sgd_offset < 32U) return {};
  SetLe32(&bytes, static_cast<size_t>(sgd_offset) + 24U, UINT32_MAX);
  return bytes;
}

bool BridgeResultHasStatus(const FsvBasisuTranscodeResult& result,
                           const char* status) {
  return result.decoded_images.empty() && result.diagnostics.size() == 1U &&
         result.diagnostics[0].status == status;
}

bool BridgeEtc1sTypedFailuresCleanUp(const std::vector<uint8_t>& bytes) {
  FailingHeap baseline_heap(0);
  fsv_basisu::FsvDecodeControl baseline_control(
      std::numeric_limits<uint64_t>::max(), &baseline_heap);
  size_t reached_ordinal = 0;
  uint64_t peak = 0;
  bool baseline_shape = false;
  {
    const FsvBasisuTranscodeResult baseline = FsvBasisuTranscodeImages(
        {RequestFor(bytes)}, Budget(), BudgetState(), &baseline_control);
    reached_ordinal = baseline_heap.attempts();
    peak = baseline_control.peak_bytes();
    baseline_shape = baseline.decoded_images.size() == 1U &&
                     baseline.diagnostics.empty() &&
                     baseline_control.live_bytes() > 0U;
  }
  const bool baseline_ok =
      baseline_shape && reached_ordinal > 4U && peak > 0U &&
      baseline_control.live_bytes() == 0U &&
      baseline_control.owner_count() == 0U &&
      baseline_control.request_allocation_count() ==
          baseline_control.request_release_count() &&
      baseline_control.release_mismatch_count() == 0U &&
      baseline_heap.allocations() == baseline_heap.releases();

  CancellingHeap cancelling_heap(reached_ordinal);
  fsv_basisu::FsvDecodeControl cancelling_control(
      std::numeric_limits<uint64_t>::max(), &cancelling_heap);
  cancelling_heap.SetControl(&cancelling_control);
  bool cancel_shape = false;
  {
    const FsvBasisuTranscodeResult cancelled = FsvBasisuTranscodeImages(
        {RequestFor(bytes)}, Budget(), BudgetState(), &cancelling_control);
    cancel_shape = cancelled.decoded_images.empty() &&
                   cancelled.diagnostics.empty() &&
                   cancelled.terminal_outcome ==
                       FsvBasisuTerminalOutcomeKind::kCallerCancelled;
  }
  const bool cancel_ok =
      cancel_shape && cancelling_control.stop_reason() ==
                          fsv_basisu::FsvDecodeStopReason::kCallerCancelled &&
      cancelling_control.live_bytes() == 0U &&
      cancelling_control.owner_count() == 0U &&
      cancelling_control.request_allocation_count() ==
          cancelling_control.request_release_count() &&
      cancelling_control.release_mismatch_count() == 0U &&
      cancelling_heap.allocations() == cancelling_heap.releases();

  FailingHeap failing_heap(reached_ordinal);
  fsv_basisu::FsvDecodeControl failing_control(
      std::numeric_limits<uint64_t>::max(), &failing_heap);
  bool heap_shape = false;
  {
    const FsvBasisuTranscodeResult failed = FsvBasisuTranscodeImages(
        {RequestFor(bytes)}, Budget(), BudgetState(), &failing_control);
    heap_shape = failed.decoded_images.empty() && failed.diagnostics.empty() &&
                 failed.terminal_outcome ==
                     FsvBasisuTerminalOutcomeKind::kAllocationFailed;
  }
  const bool heap_ok =
      heap_shape && failing_control.stop_reason() ==
                        fsv_basisu::FsvDecodeStopReason::kHeapFailure &&
      failing_control.live_bytes() == 0U &&
      failing_control.owner_count() == 0U &&
      failing_control.request_allocation_count() ==
          failing_control.request_release_count() &&
      failing_control.release_mismatch_count() == 0U &&
      failing_heap.allocations() == failing_heap.releases();

  fsv_basisu::FsvDecodeControl budget_control(peak - 1U);
  bool budget_shape = false;
  {
    const FsvBasisuTranscodeResult over_budget = FsvBasisuTranscodeImages(
        {RequestFor(bytes)}, Budget(), BudgetState(), &budget_control);
    budget_shape = over_budget.decoded_images.empty() &&
                   over_budget.diagnostics.empty() &&
                   over_budget.terminal_outcome ==
                       FsvBasisuTerminalOutcomeKind::kBudgetExceeded;
  }
  const bool budget_ok =
      budget_shape && budget_control.stop_reason() ==
                          fsv_basisu::FsvDecodeStopReason::kBudget &&
      budget_control.live_bytes() == 0U && budget_control.owner_count() == 0U &&
      budget_control.request_allocation_count() ==
          budget_control.request_release_count() &&
      budget_control.release_mismatch_count() == 0U;

  const std::vector<uint8_t> corrupt_bytes = WithCorruptEtc1sSlice(bytes);
  fsv_basisu::FsvDecodeControl corrupt_control(
      std::numeric_limits<uint64_t>::max());
  bool corrupt_shape = false;
  {
    const FsvBasisuTranscodeResult corrupt = FsvBasisuTranscodeImages(
        {RequestFor(corrupt_bytes)}, Budget(), BudgetState(), &corrupt_control);
    corrupt_shape = BridgeResultHasStatus(corrupt, "decodeFailed") &&
                    corrupt_control.live_bytes() > 0U;
  }
  const bool corrupt_ok =
      !corrupt_bytes.empty() && corrupt_shape &&
      corrupt_control.stop_reason() == fsv_basisu::FsvDecodeStopReason::kNone &&
      corrupt_control.live_bytes() == 0U &&
      corrupt_control.owner_count() == 0U &&
      corrupt_control.request_allocation_count() ==
          corrupt_control.request_release_count() &&
      corrupt_control.release_mismatch_count() == 0U;
  return baseline_ok && cancel_ok && heap_ok && budget_ok && corrupt_ok;
}

int RunEtc1sCodecFailures(const std::vector<uint8_t>& bytes) {
  ProbeControl cancelled;
  cancelled.CancelAtCheckpoint("blockRow");
  const ControlPathObservation stopped = ObserveControlPath(bytes, &cancelled);
  cancelled.InjectHeapStop();
  const bool direct_cancel =
      stopped.initialized && stopped.started && !stopped.decoded &&
      stopped.allocations > 0 &&
      stopped.stop_reason == ProbeControl::StopReason::kCancelled &&
      cancelled.stop_reason() == ProbeControl::StopReason::kCancelled &&
      ControlCleanupIsBalanced(stopped) && FreshControlSucceeds(bytes);
  const bool typed = BridgeEtc1sTypedFailuresCleanUp(bytes);
  if (!direct_cancel || !typed) {
    std::cerr << "etc1s-codec-failure-red directCancel=" << direct_cancel
              << " typed=" << typed << " allocations=" << stopped.allocations
              << " live=" << stopped.live_bytes << " owners=" << stopped.owners
              << "\n";
    return 161;
  }
  std::cout << "etc1s-codec-failure-contract-ok direct="
            << stopped.allocations << "\n";
  return 0;
}

int RunEtc1sCodecState(const std::vector<uint8_t>& rgb,
                       const std::vector<uint8_t>& rgba,
                       const std::vector<uint8_t>& mip) {
  std::vector<std::vector<uint8_t>> null_rgb;
  std::vector<std::vector<uint8_t>> null_rgba;
  std::vector<std::vector<uint8_t>> null_mip;
  const bool null_ok = DecodeEtc1sWithoutControl(rgb, false, &null_rgb) &&
                       DecodeEtc1sWithoutControl(rgba, true, &null_rgba) &&
                       DecodeEtc1sWithoutControl(mip, true, &null_mip);
  const Etc1sCodecObservation controlled_rgb =
      ObserveEtc1sCodecState(rgb, false);
  const Etc1sCodecObservation controlled_rgba =
      ObserveEtc1sCodecState(rgba, true);
  const Etc1sCodecObservation controlled_mip =
      ObserveEtc1sCodecState(mip, true);

  const auto decoded = [](const Etc1sCodecObservation& observation,
                          size_t levels) {
    return observation.initialized && observation.started &&
           observation.alpha_matches && observation.levels.size() == levels &&
           observation.level_allocation_deltas.size() == levels;
  };
  const auto temp_allocations = [](const Etc1sCodecObservation& observation) {
    size_t total = 0;
    for (const size_t delta : observation.level_allocation_deltas) total += delta;
    return total;
  };
  const size_t rgb_temp = temp_allocations(controlled_rgb);
  const size_t rgba_temp = temp_allocations(controlled_rgba);
  const size_t mip_temp = temp_allocations(controlled_mip);
  const bool owners = controlled_rgb.owners_after_bind >= 52U &&
                      controlled_rgba.owners_after_bind >= 52U &&
                      controlled_mip.owners_after_bind >= 52U;
  const bool palettes_and_tables =
      controlled_rgb.allocations_after_start >=
          controlled_rgb.allocations_after_init + 10U &&
      controlled_rgba.allocations_after_start >=
          controlled_rgba.allocations_after_init + 10U &&
      controlled_mip.allocations_after_start >=
          controlled_mip.allocations_after_init + 10U;
  const bool temporary = rgb_temp >= 3U && rgba_temp > rgb_temp &&
                         mip_temp >= rgba_temp &&
                         controlled_mip.level_allocation_deltas.size() >= 2U;
  const bool parity = null_ok && controlled_rgb.levels == null_rgb &&
                      controlled_rgba.levels == null_rgba &&
                      controlled_mip.levels == null_mip;
  const bool cleanup = controlled_rgb.cleanup && controlled_rgba.cleanup &&
                       controlled_mip.cleanup && controlled_rgb.state_unbound &&
                       controlled_rgba.state_unbound &&
                       controlled_mip.state_unbound;
  const bool corruption = CorruptEtc1sSliceCleansUp(rgba);
  if (!decoded(controlled_rgb, 1U) || !decoded(controlled_rgba, 1U) ||
      !decoded(controlled_mip, null_mip.size()) || null_mip.size() < 2U ||
      !owners || !palettes_and_tables || !temporary || !parity || !cleanup ||
      !corruption) {
    std::cerr << "etc1s-state-owner-red owners=" << owners
              << " rgbBindOwners=" << controlled_rgb.owners_after_bind
              << " rgbaBindOwners=" << controlled_rgba.owners_after_bind
              << " mipBindOwners=" << controlled_mip.owners_after_bind
              << " rgbStartDirect="
              << controlled_rgb.allocations_after_start -
                     controlled_rgb.allocations_after_init
              << " rgbaStartDirect="
              << controlled_rgba.allocations_after_start -
                     controlled_rgba.allocations_after_init
              << " mipStartDirect="
              << controlled_mip.allocations_after_start -
                     controlled_mip.allocations_after_init
              << " rgbTemp=" << rgb_temp << " rgbaTemp=" << rgba_temp
              << " mipTemp=" << mip_temp << " parity=" << parity
              << " corruption=" << corruption << " cleanup=" << cleanup
              << "\n";
    return 160;
  }
  std::cout << "etc1s-state-contract-ok cases=3 levels="
            << controlled_rgb.levels.size() + controlled_rgba.levels.size() +
                   controlled_mip.levels.size()
            << " rgbTemp=" << rgb_temp << " rgbaTemp=" << rgba_temp
            << " mipTemp=" << mip_temp << "\n";
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2 && argc != 3 && argc != 5) return 64;
  const std::string mode =
      argc == 5 ? argv[4] : argc == 3 ? argv[2] : "all";
  if (mode != "all" && mode != "metadata" && mode != "animation" &&
      mode != "animation-zstd" &&
      mode != "zstd-state" && mode != "etc1s-descriptors" &&
      mode != "malformed-level" && mode != "malformed-dfd" &&
      mode != "malformed-kvd" && mode != "animation-precedence" &&
      mode != "failure-uastc" && mode != "failure-zstd" &&
      mode != "failure-etc1s" && mode != "failure-etc1s-mips" &&
      mode != "reuse-default" && mode != "reuse-explicit" &&
      mode != "concurrency" && mode != "partial-metadata-cancel" &&
      mode != "malformed-required" &&
      mode != "state-outlives-controls" && mode != "kvd-relocation" &&
      mode != "etc1s-state" && mode != "etc1s-codec-failures") {
    return 63;
  }
  if ((mode == "animation-zstd" || mode == "zstd-state" ||
       mode == "etc1s-descriptors" ||
       mode == "malformed-level" || mode == "malformed-dfd" ||
       mode == "malformed-kvd" || mode == "animation-precedence" ||
       mode == "failure-uastc" || mode == "failure-zstd" ||
       mode == "failure-etc1s" || mode == "failure-etc1s-mips" ||
       mode == "reuse-default" || mode == "reuse-explicit" ||
       mode == "concurrency" || mode == "partial-metadata-cancel" ||
       mode == "malformed-required" ||
       mode == "state-outlives-controls" || mode == "kvd-relocation" ||
       mode == "etc1s-state" || mode == "etc1s-codec-failures") &&
      argc != 5) {
    return 62;
  }
  const char* fixture_path =
      mode == "animation-zstd" || mode == "zstd-state" ||
              mode == "failure-zstd" ||
              mode == "reuse-default" || mode == "reuse-explicit" ||
              mode == "concurrency" || mode == "state-outlives-controls"
          ? argv[2]
          : mode == "etc1s-descriptors" || mode == "failure-etc1s" ||
                    mode == "failure-etc1s-mips"
              ? argv[3]
              : argv[1];
  std::vector<uint8_t> bytes = ReadFile(fixture_path);
  if (bytes.size() < 104) return 65;
  NormalizeSelectedProfile(&bytes);
  basist::basisu_transcoder_init();

  if (mode == "etc1s-state") {
    std::vector<uint8_t> rgba = ReadFile(argv[2]);
    std::vector<uint8_t> mip = ReadFile(argv[3]);
    if (rgba.size() < 104 || mip.size() < 104) return 65;
    NormalizeSelectedProfile(&rgba);
    NormalizeSelectedProfile(&mip);
    return RunEtc1sCodecState(bytes, rgba, mip);
  }
  if (mode == "etc1s-codec-failures") {
    return RunEtc1sCodecFailures(bytes);
  }

  ProbeControl probe;
  if (mode == "failure-uastc") {
    return RunFailureControlMatrix(bytes, "uastc", 140);
  }
  if (mode == "failure-zstd") {
    return RunFailureControlMatrix(bytes, "zstd", 141);
  }
  if (mode == "failure-etc1s") {
    return RunFailureControlMatrix(bytes, "etc1s", 142);
  }
  if (mode == "failure-etc1s-mips") {
    return RunFailureControlMatrix(bytes, "etc1s-mips", 143, true);
  }
  if (mode == "reuse-default") return RunDefaultStateReuse(bytes);
  if (mode == "reuse-explicit") return RunExplicitStateReuse(bytes);
  if (mode == "concurrency") return RunConcurrentIsolation(bytes);
  if (mode == "partial-metadata-cancel") {
    return RunPartialMetadataCancellation(bytes);
  }
  if (mode == "malformed-required") return RunRequiredMalformedMatrix(bytes);
  if (mode == "state-outlives-controls") {
    return RunExplicitStateOutlivesControls(bytes);
  }
  if (mode == "kvd-relocation") return RunKvdRelocationMatrix(bytes);
  if (mode == "malformed-level") {
    const std::vector<uint8_t> invalid_offset = WithInvalidLevelOffset(bytes);
    const std::vector<uint8_t> truncated = WithTruncatedLevelIndex(bytes);
    const bool range_diagnostic =
        HasMalformedDiagnostic(invalid_offset, "ktx2LevelIndex");
    const bool truncated_diagnostic =
        HasMalformedDiagnostic(truncated, "ktx2LevelIndex");
    const DirectMalformedObservation direct =
        ObserveDirectMalformed(invalid_offset);
    if (!range_diagnostic || !truncated_diagnostic || direct.initialized ||
        !DirectCleanupIsBalanced(direct)) {
      std::cerr << "malformed-level-red status=invalidMetadata"
                << " stage=basisuNativePreflight field=ktx2LevelIndex"
                << " range=" << range_diagnostic
                << " truncated=" << truncated_diagnostic
                << " directInit=" << direct.initialized
                << " allocations=" << direct.allocations
                << " releases=" << direct.releases
                << " live=" << direct.live_bytes
                << " owners=" << direct.owners
                << " allocationFailed=" << direct.allocation_failed << "\n";
      return 130;
    }
    std::cout << "malformed-level-contract-ok allocations="
              << direct.allocations << "\n";
    return 0;
  }

  if (mode == "malformed-dfd") {
    const std::vector<uint8_t> invalid_range = WithInvalidDfdRange(bytes);
    const std::vector<uint8_t> invalid_structure =
        WithInvalidDfdStructure(bytes);
    const bool range_diagnostic =
        HasMalformedDiagnostic(invalid_range, "ktx2Dfd");
    const bool structure_diagnostic =
        HasMalformedDiagnostic(invalid_structure, "ktx2Dfd");
    const DirectMalformedObservation direct =
        ObserveDirectMalformed(invalid_structure);
    if (!range_diagnostic || !structure_diagnostic || direct.initialized ||
        !DirectCleanupIsBalanced(direct)) {
      std::cerr << "malformed-dfd-red status=invalidMetadata"
                << " stage=basisuNativePreflight field=ktx2Dfd"
                << " range=" << range_diagnostic
                << " structure=" << structure_diagnostic
                << " directInit=" << direct.initialized
                << " allocations=" << direct.allocations
                << " releases=" << direct.releases
                << " live=" << direct.live_bytes
                << " owners=" << direct.owners
                << " allocationFailed=" << direct.allocation_failed << "\n";
      return 131;
    }
    std::cout << "malformed-dfd-contract-ok allocations=" << direct.allocations
              << "\n";
    return 0;
  }

  if (mode == "malformed-kvd") {
    const std::vector<uint8_t> invalid_range = WithInvalidKvdRange(bytes);
    const std::vector<uint8_t> invalid_entry = WithInvalidKvdEntry(bytes);
    const std::vector<uint8_t> unsorted = WithUnsortedKvd(bytes);
    const std::vector<uint8_t> nonzero_padding =
        WithNonzeroKvdPadding(bytes);
    const bool range_diagnostic =
        HasMalformedDiagnostic(invalid_range, "ktx2KeyValueData");
    const bool entry_diagnostic =
        HasMalformedDiagnostic(invalid_entry, "ktx2KeyValueData");
    const bool order_diagnostic =
        HasMalformedDiagnostic(unsorted, "ktx2KeyValueData");
    const bool padding_diagnostic =
        HasMalformedDiagnostic(nonzero_padding, "ktx2KeyValueData");
    const DirectMalformedObservation direct =
        ObserveDirectMalformed(invalid_entry);
    if (!range_diagnostic || !entry_diagnostic || !order_diagnostic ||
        !padding_diagnostic || direct.initialized ||
        !DirectCleanupIsBalanced(direct)) {
      std::cerr << "malformed-kvd-red status=invalidMetadata"
                << " stage=basisuNativePreflight field=ktx2KeyValueData"
                << " range=" << range_diagnostic
                << " entry=" << entry_diagnostic
                << " order=" << order_diagnostic
                << " padding=" << padding_diagnostic
                << " directInit=" << direct.initialized
                << " allocations=" << direct.allocations
                << " releases=" << direct.releases
                << " live=" << direct.live_bytes
                << " owners=" << direct.owners
                << " allocationFailed=" << direct.allocation_failed << "\n";
      return 132;
    }
    std::cout << "malformed-kvd-contract-ok allocations=" << direct.allocations
              << "\n";
    return 0;
  }

  if (mode == "animation-precedence") {
    const std::vector<uint8_t> animated = WithAnimationEntry(bytes);
    if (animated.empty()) return 134;
    const std::vector<uint8_t> later_malformed =
        WithNonzeroKvdPadding(animated);
    const bool precedence =
        HasMalformedDiagnostic(later_malformed, "ktx2KeyValueData");
    const DirectMalformedObservation direct =
        ObserveDirectMalformed(later_malformed);
    if (!precedence || !direct.initialized ||
        !DirectCleanupIsBalanced(direct)) {
      std::cerr << "animation-precedence-red status=invalidMetadata"
                << " stage=basisuNativePreflight field=ktx2KeyValueData"
                << " precedence=" << precedence
                << " directInit=" << direct.initialized
                << " allocations=" << direct.allocations
                << " releases=" << direct.releases
                << " live=" << direct.live_bytes
                << " owners=" << direct.owners
                << " allocationFailed=" << direct.allocation_failed << "\n";
      return 133;
    }
    std::cout << "animation-precedence-contract-ok allocations="
              << direct.allocations << "\n";
    return 0;
  }

  if (mode == "zstd-state") {
    bool initialized = false;
    bool started = false;
    bool decoded = false;
    bool state_unbound = false;
    size_t init_allocations = 0;
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(&probe);
      initialized = transcoder.init(
          bytes.data(), static_cast<uint32_t>(bytes.size()));
      init_allocations = probe.allocations();
      if (initialized) started = transcoder.start_transcoding();
      basist::ktx2_transcoder_state state;
      state.clear();
      if (started) {
        basist::ktx2_image_level_info level_info;
        if (transcoder.get_image_level_info(level_info, 0, 0, 0)) {
          const uint64_t pixels =
              static_cast<uint64_t>(level_info.m_orig_width) *
              level_info.m_orig_height;
          if (pixels <= std::numeric_limits<uint32_t>::max() &&
              pixels <= std::numeric_limits<size_t>::max() / 4U) {
            std::vector<uint8_t> rgba(static_cast<size_t>(pixels) * 4U);
            decoded = transcoder.transcode_image_level(
                0, 0, 0, rgba.data(), static_cast<uint32_t>(pixels),
                basist::transcoder_texture_format::cTFRGBA32, 0, 0, 0, -1,
                -1, &state);
          }
        }
      }
      state_unbound = state.m_level_uncomp_data.fsv_allocator() == nullptr;
      state.clear();
    }
    const bool cleanup =
        probe.live_bytes() == 0 && probe.owners() == 0 &&
        probe.allocations() == probe.releases() &&
        !probe.allocation_failed();
    const bool state_allocated = probe.allocations() > init_allocations;
    const uint64_t level_uncompressed_bytes = ReadLe64(bytes, 96);
    const size_t decoded_level_allocations = static_cast<size_t>(std::count(
        probe.allocation_sizes().begin(), probe.allocation_sizes().end(),
        static_cast<size_t>(level_uncompressed_bytes)));
    const size_t zstd_workspace_allocations = static_cast<size_t>(std::count(
        probe.allocation_sizes().begin(), probe.allocation_sizes().end(),
        ZSTD_fsv_dctx_allocation_size()));
    if (!initialized || !started || !decoded || !state_unbound ||
        !state_allocated || decoded_level_allocations != 1U ||
        zstd_workspace_allocations != 1U || !cleanup) {
      std::cerr << "zstd-state-red initialized=" << initialized
                << " started=" << started << " decoded=" << decoded
                << " stateAllocated=" << state_allocated
                << " decodedLevelAllocations=" << decoded_level_allocations
                << " workspaceAllocations=" << zstd_workspace_allocations
                << " stateUnbound=" << state_unbound
                << " allocations=" << probe.allocations()
                << " releases=" << probe.releases()
                << " live=" << probe.live_bytes()
                << " owners=" << probe.owners()
                << " allocationFailed=" << probe.allocation_failed() << "\n";
      return 110;
    }
    std::cout << "zstd-state-contract-ok allocations="
              << probe.allocations()
              << " decodedLevelAllocations=" << decoded_level_allocations
              << " workspaceAllocations=" << zstd_workspace_allocations
              << "\n";
    return 0;
  }

  if (mode == "etc1s-descriptors") {
    bool initialized = false;
    bool started = false;
    bool descriptors_present = false;
    bool descriptors_bound = false;
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(&probe);
      initialized = transcoder.init(
          bytes.data(), static_cast<uint32_t>(bytes.size()));
      if (initialized) started = transcoder.start_transcoding();
      if (started) {
        descriptors_present = !transcoder.get_etc1s_image_descs().empty();
        descriptors_bound =
            transcoder.get_etc1s_image_descs().fsv_allocator() == &probe;
      }
    }
    const bool cleanup =
        probe.live_bytes() == 0 && probe.owners() == 0 &&
        probe.allocations() == probe.releases() &&
        !probe.allocation_failed();
    if (!initialized || !started || !descriptors_present ||
        !descriptors_bound || probe.allocations() == 0 || !cleanup) {
      std::cerr << "etc1s-descriptor-red initialized=" << initialized
                << " started=" << started
                << " present=" << descriptors_present
                << " descriptor=" << descriptors_bound
                << " allocations=" << probe.allocations()
                << " releases=" << probe.releases()
                << " live=" << probe.live_bytes()
                << " owners=" << probe.owners()
                << " allocationFailed=" << probe.allocation_failed() << "\n";
      return 120;
    }
    std::cout << "etc1s-descriptor-contract-ok allocations="
              << probe.allocations() << "\n";
    return 0;
  }

  if (mode != "animation" && mode != "animation-zstd") {
    {
      basist::ktx2_transcoder transcoder;
      transcoder.set_fsv_transcode_control(&probe);
      if (!transcoder.init(bytes.data(), static_cast<uint32_t>(bytes.size()))) {
        return 66;
      }
      if (transcoder.get_key_values().empty()) return 67;
      const bool persistent_bound =
          transcoder.get_level_index().fsv_allocator() == &probe &&
          transcoder.get_dfd().fsv_allocator() == &probe &&
          transcoder.get_key_values().fsv_allocator() == &probe &&
          transcoder.get_etc1s_image_descs().fsv_allocator() == &probe;
      bool nested_bound = true;
      for (const auto& key_value : transcoder.get_key_values()) {
        nested_bound = nested_bound &&
                       key_value.m_key.fsv_allocator() == &probe &&
                       key_value.m_value.fsv_allocator() == &probe;
      }
      const size_t expected_owners =
          4U + transcoder.get_key_values().size() * 2U;
      if (!persistent_bound || !nested_bound || probe.allocations() == 0 ||
          probe.owners() < expected_owners) {
        std::cerr << "metadata-owner-red persistent=" << persistent_bound
                  << " nested=" << nested_bound
                  << " allocations=" << probe.allocations()
                  << " owners=" << probe.owners()
                  << " expectedOwners=" << expected_owners << "\n";
        return 100;
      }
    }
    if (probe.live_bytes() != 0 || probe.owners() != 0 ||
        probe.allocations() != probe.releases() || probe.allocation_failed()) {
      return 101;
    }
    if (mode == "metadata") return 0;
  }

  const std::vector<uint8_t> animated = WithAnimationEntry(bytes);
  if (animated.empty()) return 102;
  basist::ktx2_transcoder direct;
  if (!direct.init(animated.data(), static_cast<uint32_t>(animated.size())) ||
      !direct.is_video()) {
    return 103;
  }
  fsv_basisu::FsvDecodeControl animation_control(
      std::numeric_limits<uint64_t>::max());
  bool animation_shape = false;
  {
    const FsvBasisuTranscodeResult animation_result = FsvBasisuTranscodeImages(
        {RequestFor(animated)}, Budget(), BudgetState(), &animation_control);
    animation_shape =
        animation_result.decoded_images.empty() &&
        animation_result.diagnostics.size() == 1 &&
        animation_result.diagnostics[0].status == "unsupportedKtx2Profile" &&
        animation_result.diagnostics[0].stage == "basisuProfilePreflight" &&
        animation_result.diagnostics[0].field == "ktx2KTXanimData" &&
        animation_control.live_bytes() > 0;
    if (!animation_shape) {
      std::cerr << "animation-profile-red decoded="
                << animation_result.decoded_images.size()
                << " diagnostics=" << animation_result.diagnostics.size();
      if (!animation_result.diagnostics.empty()) {
        std::cerr << " status=" << animation_result.diagnostics[0].status
                  << " stage=" << animation_result.diagnostics[0].stage
                  << " field=" << animation_result.diagnostics[0].field;
      }
    }
  }
  if (!animation_shape || animation_control.live_bytes() != 0 ||
      animation_control.owner_count() != 0 ||
      animation_control.request_allocation_count() !=
          animation_control.request_release_count() ||
      animation_control.release_mismatch_count() != 0) {
    std::cerr << " allocations=" << animation_control.request_allocation_count()
              << " releases=" << animation_control.request_release_count()
              << "\n";
    return 104;
  }

  std::cout << "basisu-ktx2-metadata-red-contract-ok allocations="
            << probe.allocations() << "\n";
  return 0;
}
