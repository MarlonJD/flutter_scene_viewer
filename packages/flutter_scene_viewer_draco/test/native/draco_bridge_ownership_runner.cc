#include <cstdint>
#include <array>
#include <iostream>
#include <memory>
#include <string>
#include <type_traits>

#if defined(__APPLE__) || defined(__linux__)
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "fsv_draco_bridge.h"
#include "fsv_draco_codec_adapter.h"

namespace {
int Fail(int line) { return line; }

struct alignas(128) OverAlignedValue {
  uint8_t bytes[128] = {};
};

class AlwaysFailHeap final : public fsv_draco::FsvDecodeHeap {
 public:
  void* Allocate(size_t bytes, size_t alignment) noexcept override {
    static_cast<void>(bytes);
    static_cast<void>(alignment);
    return nullptr;
  }
  void Release(void* allocation, size_t bytes,
               size_t alignment) noexcept override {
    static_cast<void>(allocation);
    static_cast<void>(bytes);
    static_cast<void>(alignment);
  }
};
}  // namespace

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main() {
  static_assert(!std::is_copy_constructible<FsvDracoAccessorSchema>::value,
                "accessor schemas require an explicit destination control");
  static_assert(!std::is_copy_constructible<FsvDracoPrimitiveRequest>::value,
                "primitive requests require an explicit destination control");
  static_assert(!std::is_copy_constructible<FsvDracoDiagnostic>::value,
                "diagnostics require an explicit destination control");

  fsv_draco::FsvDecodeControl control(1024 * 1024);

  fsv_draco::FsvDecodeAllocationResult allocation =
      control.AllocateMemory(17, 64);
  CHECK(allocation.outcome ==
        fsv_draco::FsvDecodeAllocationOutcome::kSuccess);
  CHECK(allocation.allocation != nullptr);
  CHECK(allocation.bytes == 17);
  CHECK(allocation.alignment == 64);
  CHECK(!control.ReleaseMemory(&allocation, allocation.allocation, 18, 64));
  CHECK(control.release_mismatch_count() == 1);
  CHECK(control.ReleaseMemory(&allocation, allocation.allocation, 17, 64));
  CHECK(!control.ReleaseMemory(&allocation, allocation.allocation, 17, 64));
  CHECK(control.release_mismatch_count() == 2);

  {
    FsvDracoCodecControlAdapter codec_control(&control);
    draco::FsvDecodeControl::AllocationResult codec_allocation =
        codec_control.AllocateMemory(41, 64);
    CHECK(codec_allocation.outcome ==
          draco::FsvDecodeControl::AllocationOutcome::kSuccess);
    auto duplicate_allocation = codec_allocation;
    CHECK(codec_allocation.allocation != nullptr);
    CHECK(codec_allocation.bytes == 41);
    CHECK(codec_allocation.alignment == 64);
    void* const original = codec_allocation.allocation;
    CHECK(!codec_control.ReleaseMemory(
        &codec_allocation, static_cast<uint8_t*>(original) + 1, 41, 64));
    CHECK(!codec_control.ReleaseMemory(&codec_allocation, original, 42, 64));
    CHECK(!codec_control.ReleaseMemory(&codec_allocation, original, 41, 32));
    CHECK(codec_allocation.allocation == original);
    CHECK(codec_allocation.outcome ==
          draco::FsvDecodeControl::AllocationOutcome::kSuccess);
    CHECK(codec_control.ReleaseMemory(&codec_allocation, original, 41, 64));
    CHECK(!codec_control.ReleaseMemory(&duplicate_allocation, original, 41,
                                       64));
  }
  CHECK(control.live_bytes() == 0);

  {
    FsvDracoCodecControlAdapter codec_control(&control);
    std::array<draco::FsvDecodeControl::AllocationResult, 129> allocations;
    const uint64_t allocation_start = control.allocation_count();
    for (auto& record : allocations) {
      record = codec_control.AllocateMemory(1, alignof(uint8_t));
      CHECK(record.outcome ==
            draco::FsvDecodeControl::AllocationOutcome::kSuccess);
    }
    CHECK(control.allocation_count() == allocation_start + 130);
    for (auto& record : allocations) {
      void* const allocation_pointer = record.allocation;
      CHECK(codec_control.ReleaseMemory(
          &record, allocation_pointer, 1, alignof(uint8_t)));
    }
  }
  CHECK(control.live_bytes() == 0);

  {
    fsv_draco::FsvDecodeControl left_control(1024);
    fsv_draco::FsvDecodeControl right_control(1024);
    FsvDracoCodecControlAdapter left(&left_control);
    FsvDracoCodecControlAdapter right(&right_control);
    auto left_record = left.AllocateMemory(32, alignof(uint64_t));
    auto right_record = right.AllocateMemory(32, alignof(uint64_t));
    CHECK(!right.ReleaseMemory(&left_record, left_record.allocation, 32,
                               alignof(uint64_t)));
    CHECK(left_control.release_mismatch_count() == 0);
    CHECK(right_control.release_mismatch_count() == 1);
    void* const left_pointer = left_record.allocation;
    void* const right_pointer = right_record.allocation;
    CHECK(left.ReleaseMemory(&left_record, left_pointer, 32,
                             alignof(uint64_t)));
    CHECK(right.ReleaseMemory(&right_record, right_pointer, 32,
                              alignof(uint64_t)));
  }

  {
    FsvDracoAllocator<uint32_t> allocator(&control);
    uint32_t* const zero = allocator.allocate(0);
    CHECK(zero != nullptr);
    allocator.deallocate(zero, 0);

    FsvDracoVector<OverAlignedValue> aligned{
        FsvDracoAllocator<OverAlignedValue>(&control)};
    aligned.resize(2);
    CHECK(reinterpret_cast<uintptr_t>(aligned.data()) %
              alignof(OverAlignedValue) ==
          0);

    fsv_draco::FsvDecodeControl propagation_control(1024 * 1024);
    FsvDracoVector<uint32_t> moved{
        FsvDracoAllocator<uint32_t>(&control)};
    moved.assign(32, 7);
    FsvDracoVector<uint32_t> destination{
        FsvDracoAllocator<uint32_t>(&propagation_control)};
    destination.assign(8, 9);
    destination = std::move(moved);
    CHECK(destination.get_allocator().control() == &control);
    FsvDracoVector<uint32_t> swapped{
        FsvDracoAllocator<uint32_t>(&propagation_control)};
    swapped.assign(16, 3);
    destination.swap(swapped);
    CHECK(destination.get_allocator().control() == &propagation_control);
    CHECK(swapped.get_allocator().control() == &control);
    CHECK(propagation_control.live_bytes() > 0);
  }
  CHECK(control.live_bytes() == 0);

  AlwaysFailHeap failing_heap;
  fsv_draco::FsvDecodeControl failing_control(1024, &failing_heap);
  bool allocation_failed = false;
  try {
    FsvDracoAllocator<uint64_t> allocator(&failing_control);
    static_cast<void>(allocator.allocate(4));
  } catch (const std::bad_alloc&) {
    allocation_failed = true;
  }
  CHECK(allocation_failed);
  CHECK(failing_control.stop_reason() ==
        fsv_draco::FsvDecodeStopReason::kAllocationFailure);
  CHECK(failing_control.live_bytes() == 0);
  CHECK(failing_control.allocation_count() == 1);
  CHECK(failing_control.release_count() == 1);

  const uint64_t owner_start = control.allocation_count();
  {
    FsvDracoPrimitiveRequest request(&control);
    request.compressed_bytes.assign(300, 0x5a);
    request.attributes.emplace(
        FsvDracoString(120, 'a', FsvDracoAllocator<char>(&control)), 7);
    FsvDracoAccessorSchema schema(&control);
    schema.type.assign(120, 't');
    request.attribute_accessors.emplace(
        FsvDracoString(120, 's', FsvDracoAllocator<char>(&control)),
        std::move(schema));

    FsvDracoPreflightResult preflight(&control);
    FsvDracoDiagnostic diagnostic(&control);
    diagnostic.status.assign(120, 'x');
    diagnostic.message.assign(300, 'm');
    preflight.diagnostics.push_back(std::move(diagnostic));

    FsvDracoDecodeResult result(&control);
    FsvDracoDecodedPrimitive primitive(&control);
    primitive.indices.assign(600, 0x11);
    primitive.attributes.emplace(
        FsvDracoString(120, 'o', FsvDracoAllocator<char>(&control)),
        FsvDracoByteVector(700, 0x22,
                           FsvDracoAllocator<uint8_t>(&control)));
    result.decoded_primitives.push_back(std::move(primitive));
    FsvDracoDiagnostic result_diagnostic(&control);
    result_diagnostic.status.assign(120, 'd');
    result_diagnostic.message.assign(300, 'e');
    result.diagnostics.push_back(std::move(result_diagnostic));
    CHECK(request.control() == &control);
    CHECK(preflight.control() == &control);
    CHECK(result.control() == &control);
    CHECK(request.attributes.begin()->first.get_allocator().control() ==
          &control);
    CHECK(request.attribute_accessors.begin()
              ->first.get_allocator().control() == &control);
    CHECK(request.attribute_accessors.begin()
              ->second.type.get_allocator().control() == &control);
    CHECK(result.decoded_primitives.front()
              .attributes.begin()->first.get_allocator().control() ==
          &control);
    CHECK(result.decoded_primitives.front()
              .attributes.begin()->second.get_allocator().control() ==
          &control);
    CHECK(result.diagnostics.get_allocator().control() == &control);
    CHECK(result.diagnostics.front().message.get_allocator().control() ==
          &control);
    CHECK(result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kNone);
    std::cout << "owner_family_allocations="
              << control.allocation_count() - owner_start << "\n";
    CHECK(control.allocation_count() == owner_start + 17);
    CHECK(control.live_bytes() > 0);
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());

  {
    FsvDracoPrimitiveRequests invalid_requests{
        FsvDracoAllocator<FsvDracoPrimitiveRequest>(&control)};
    FsvDracoPrimitiveRequest invalid_request(&control);
    invalid_request.mesh_index = 4;
    invalid_request.primitive_index = 2;
    invalid_request.attributes.emplace(
        FsvDracoString("LONG_ATTRIBUTE_NAME_FOR_CONTROLLED_DIAGNOSTIC",
                       FsvDracoAllocator<char>(&control)),
        0);
    FsvDracoAccessorSchema invalid_schema(&control);
    invalid_schema.accessor_index = 8;
    invalid_schema.component_type = FsvDracoBudgetNumber::Integer(5126);
    invalid_schema.type.assign("VEC3");
    invalid_schema.count = 0;
    invalid_request.attribute_accessors.emplace(
        FsvDracoString("LONG_ATTRIBUTE_NAME_FOR_CONTROLLED_DIAGNOSTIC",
                       FsvDracoAllocator<char>(&control)),
        std::move(invalid_schema));
    invalid_request.vertex_accessor_index = 8;
    invalid_requests.push_back(std::move(invalid_request));
    FsvDracoDecodeBudgetMetadata budget;
    budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(4096);
    budget.max_accessors = FsvDracoBudgetNumber::Integer(8);
    budget.max_vertices = FsvDracoBudgetNumber::Integer(256);
    budget.max_indices = FsvDracoBudgetNumber::Integer(256);
    budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(4096);
    FsvDracoDecodeBudgetState state;
    state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
    state.accessors = FsvDracoBudgetNumber::Integer(0);
    state.vertices = FsvDracoBudgetNumber::Integer(0);
    state.indices = FsvDracoBudgetNumber::Integer(0);
    state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);
    const FsvDracoPreflightResult invalid =
        FsvDracoPreflightRequests(invalid_requests, budget, state, &control);
    CHECK(!invalid.ok);
    CHECK(invalid.diagnostics.size() == 1);
    CHECK(invalid.diagnostics.get_allocator().control() == &control);
    CHECK(invalid.diagnostics.front().message.get_allocator().control() ==
          &control);
    CHECK(invalid.diagnostics.front().attribute.get_allocator().control() ==
          &control);
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());

  {
    FsvDracoDecodeResult same_control_source(&control);
    FsvDracoDecodedPrimitive same_control_primitive(&control);
    same_control_primitive.indices.assign(512, 0x71);
    same_control_source.decoded_primitives.push_back(
        std::move(same_control_primitive));
    same_control_source.terminal_outcome.kind =
        FsvDracoTerminalOutcomeKind::kDeadline;
    FsvDracoDecodeResult same_control_destination(&control);
    const uint64_t allocations_before_move = control.allocation_count();
    const uint64_t peak_before_move = control.peak_bytes();
    same_control_destination = std::move(same_control_source);
    CHECK(control.allocation_count() == allocations_before_move);
    CHECK(control.peak_bytes() == peak_before_move);
    CHECK(same_control_source.decoded_primitives.empty());
    CHECK(same_control_destination.decoded_primitives.front().indices.size() ==
          512);
    CHECK(same_control_destination.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kDeadline);
    CHECK(same_control_source.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kNone);
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());

  {
    fsv_draco::FsvDecodeControl tight_control(2048);
    FsvDracoDecodeResult platform_source(&tight_control);
    FsvDracoDecodedPrimitive platform_primitive(&tight_control);
    platform_primitive.indices.assign(1500, 0x6d);
    platform_source.decoded_primitives.push_back(
        std::move(platform_primitive));
    platform_source.terminal_outcome.kind =
        FsvDracoTerminalOutcomeKind::kBudgetExceeded;
    FsvDracoDecodeResult platform_destination(&tight_control);
    const uint64_t allocations_before_move = tight_control.allocation_count();
    const uint64_t peak_before_move = tight_control.peak_bytes();
    platform_destination = std::move(platform_source);
    CHECK(tight_control.stop_reason() ==
          fsv_draco::FsvDecodeStopReason::kNone);
    CHECK(tight_control.allocation_count() == allocations_before_move);
    CHECK(tight_control.peak_bytes() == peak_before_move);
    CHECK(platform_source.decoded_primitives.empty());
    CHECK(platform_destination.decoded_primitives.front().indices.size() ==
          1500);
    CHECK(platform_destination.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kBudgetExceeded);
  }

  {
    FsvDracoAccessorSchema schema_source(&control);
    schema_source.type.assign(300, 'q');
    FsvDracoAccessorSchema schema_destination(&control);
    uint64_t before = control.allocation_count();
    schema_destination = std::move(schema_source);
    CHECK(control.allocation_count() == before);
    CHECK(schema_source.type.empty());
    CHECK(schema_destination.type.size() == 300);

    FsvDracoPrimitiveRequest request_source(&control);
    request_source.compressed_bytes.assign(500, 0x31);
    request_source.attributes.emplace(
        FsvDracoString(180, 'r', FsvDracoAllocator<char>(&control)), 5);
    FsvDracoPrimitiveRequest request_destination(&control);
    before = control.allocation_count();
    request_destination = std::move(request_source);
    CHECK(control.allocation_count() == before);
    CHECK(request_source.compressed_bytes.empty());
    CHECK(request_destination.compressed_bytes.size() == 500);

    FsvDracoDecodedPrimitive primitive_source(&control);
    primitive_source.indices.assign(500, 0x42);
    primitive_source.attributes.emplace(
        FsvDracoString(180, 'p', FsvDracoAllocator<char>(&control)),
        FsvDracoByteVector(400, 0x51,
                           FsvDracoAllocator<uint8_t>(&control)));
    FsvDracoDecodedPrimitive primitive_destination(&control);
    before = control.allocation_count();
    primitive_destination = std::move(primitive_source);
    CHECK(control.allocation_count() == before);
    CHECK(primitive_source.indices.empty());
    CHECK(primitive_destination.indices.size() == 500);
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());

  fsv_draco::FsvDecodeControl destination_control(1024 * 1024);
  auto source_control =
      std::make_unique<fsv_draco::FsvDecodeControl>(1024 * 1024);
  auto source_result =
      std::make_unique<FsvDracoDecodeResult>(source_control.get());
  {
    FsvDracoDecodedPrimitive source_primitive(source_control.get());
    source_primitive.indices.assign(300, 0x33);
    source_result->decoded_primitives.push_back(std::move(source_primitive));
  }
  FsvDracoDecodeResult destination_copy(*source_result,
                                        &destination_control);
  FsvDracoDecodeResult destination_move(std::move(*source_result),
                                        &destination_control);
  CHECK(source_result->decoded_primitives.empty());
  source_result.reset();
  source_control.reset();
  CHECK(destination_copy.decoded_primitives.front().indices.size() == 300);
  CHECK(destination_move.decoded_primitives.front().indices.size() == 300);
  CHECK(destination_copy.control() == &destination_control);
  CHECK(destination_move.control() == &destination_control);
  CHECK(destination_copy.decoded_primitives.get_allocator().control() ==
        &destination_control);
  CHECK(destination_move.decoded_primitives.get_allocator().control() ==
        &destination_control);
  CHECK(destination_copy.decoded_primitives.front()
            .indices.get_allocator().control() == &destination_control);
  CHECK(destination_move.decoded_primitives.front()
            .indices.get_allocator().control() == &destination_control);

#if defined(__APPLE__) || defined(__linux__)
  const pid_t child = fork();
  CHECK(child >= 0);
  if (child == 0) {
    auto* doomed_control = new fsv_draco::FsvDecodeControl(1024);
    auto* doomed_result = new FsvDracoDecodeResult(doomed_control);
    (void)doomed_result;
    delete doomed_control;
    _exit(0);
  }
  int status = 0;
  CHECK(waitpid(child, &status, 0) == child);
  CHECK(!WIFEXITED(status) || WEXITSTATUS(status) != 0);
#endif
  return 0;
}
