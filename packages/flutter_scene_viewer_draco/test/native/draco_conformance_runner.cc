#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "draco/compression/decode.h"
#include "draco/core/decoder_buffer.h"
#include "draco/mesh/mesh.h"
#include "fsv_draco_bridge.h"

namespace {
constexpr uint64_t kExpectedBoxAllocationOrdinals = 110;
constexpr uint64_t kExpectedBoxBridgeAllocationOrdinals = 132;
constexpr uint64_t kExpectedBoxBridgePeakBytes = 24926;
constexpr uint64_t kExpectedTwoPrimitiveBridgeAllocationOrdinals = 256;
constexpr uint64_t kExpectedTwoPrimitiveBridgePeakBytes = 27594;

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

class StopOnAllocationControl final : public draco::FsvDecodeControl {
 public:
  bool ShouldStopDecoding() const override { return stopped_; }

  AllocationResult AllocateMemory(size_t bytes,
                                  size_t alignment) noexcept override {
    static_cast<void>(bytes);
    static_cast<void>(alignment);
    stopped_ = true;
    return {nullptr, AllocationOutcome::kStopped};
  }

  bool ReleaseMemory(AllocationResult* allocation_record,
                     void* allocation, size_t bytes,
                     size_t alignment) noexcept override {
    static_cast<void>(allocation_record);
    static_cast<void>(allocation);
    static_cast<void>(bytes);
    static_cast<void>(alignment);
    return true;
  }

 private:
  bool stopped_ = false;
};


class OrdinalFailingHeap final : public fsv_draco::FsvDecodeHeap {
 public:
  explicit OrdinalFailingHeap(uint64_t fail_at) : fail_at_(fail_at) {}

  void* Allocate(size_t bytes, size_t alignment) noexcept override {
    ++allocation_calls_;
    if (allocation_calls_ == fail_at_) {
      return nullptr;
    }
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      return ::operator new(bytes, std::align_val_t(alignment), std::nothrow);
    }
#endif
    return ::operator new(bytes, std::nothrow);
  }

  void Release(void* allocation, size_t bytes,
               size_t alignment) noexcept override {
    static_cast<void>(bytes);
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      ::operator delete(allocation, std::align_val_t(alignment));
    } else {
#endif
      ::operator delete(allocation);
#if defined(__cpp_aligned_new)
    }
#endif
    ++release_calls_;
  }

  uint64_t allocation_calls() const { return allocation_calls_; }
  uint64_t release_calls() const { return release_calls_; }

 private:
  const uint64_t fail_at_;
  uint64_t allocation_calls_ = 0;
  uint64_t release_calls_ = 0;
};

template <typename T>
std::vector<uint8_t> AttributeBytes(const draco::PointAttribute& attribute,
                                    int count,
                                    int component_count) {
  std::vector<uint8_t> bytes(
      static_cast<size_t>(count * component_count) * sizeof(T));
  std::vector<T> values(static_cast<size_t>(component_count));
  for (int point = 0; point < count; ++point) {
    const draco::PointIndex point_index(point);
    if (!attribute.ConvertValue<T>(
            attribute.mapped_index(point_index),
            static_cast<int8_t>(component_count), values.data())) {
      return {};
    }
    std::memcpy(bytes.data() +
                    static_cast<size_t>(point * component_count) * sizeof(T),
                values.data(),
                static_cast<size_t>(component_count) * sizeof(T));
  }
  return bytes;
}

std::vector<uint8_t> IndexBytes(const draco::Mesh& mesh) {
  std::vector<uint8_t> bytes;
  bytes.reserve(static_cast<size_t>(mesh.num_faces()) * 3 * sizeof(uint16_t));
  for (draco::FaceIndex face_index(0); face_index < mesh.num_faces();
       ++face_index) {
    const draco::Mesh::Face& face = mesh.face(face_index);
    for (int corner = 0; corner < 3; ++corner) {
      const uint16_t value = static_cast<uint16_t>(face[corner].value());
      const auto* value_bytes = reinterpret_cast<const uint8_t*>(&value);
      bytes.insert(bytes.end(), value_bytes, value_bytes + sizeof(value));
    }
  }
  return bytes;
}

FsvDracoAccessorSchema Accessor(int index,
                                int component_type,
                                std::string type,
                                int64_t count) {
  FsvDracoAccessorSchema schema;
  schema.accessor_index = index;
  schema.component_type = FsvDracoBudgetNumber::Integer(component_type);
  schema.type.assign(type.data(), type.size());
  schema.count = count;
  return schema;
}

FsvDracoPrimitiveRequests Requests(
    std::initializer_list<const FsvDracoPrimitiveRequest*> sources) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(nullptr)};
  for (const FsvDracoPrimitiveRequest* source : sources) {
    requests.emplace_back(*source, nullptr);
  }
  return requests;
}

template <typename Allocator>
bool WriteBytes(const std::string& path,
                const std::vector<uint8_t, Allocator>& bytes) {
  std::ofstream output(path, std::ios::binary);
  output.write(reinterpret_cast<const char*>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
  return output.good();
}
}  // namespace

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main(int argc, char** argv) {
  CHECK(argc == 2 || argc == 4);
  const bool write_outputs = argc == 4;
  if (write_outputs) {
    CHECK(std::string(argv[2]) == "--output-directory");
    CHECK(std::string(argv[3]).size() > 0);
  }

  std::ifstream input(argv[1], std::ios::binary);
  CHECK(input.good());
  std::vector<uint8_t> container((std::istreambuf_iterator<char>(input)),
                                 std::istreambuf_iterator<char>());
  CHECK(container.size() == 120);
  CHECK(container[0] == 'D' && container[1] == 'R' && container[2] == 'A' &&
        container[3] == 'C' && container[4] == 'O');
  CHECK(container[5] == 2 && container[6] == 2);
  const std::vector<uint8_t> compressed(container.begin(),
                                        container.begin() + 118);

  draco::DecoderBuffer direct_buffer;
  direct_buffer.Init(reinterpret_cast<const char*>(compressed.data()),
                     compressed.size());
  auto geometry_type = draco::Decoder::GetEncodedGeometryType(&direct_buffer);
  CHECK(geometry_type.ok());
  CHECK(geometry_type.value() == draco::TRIANGULAR_MESH);
  draco::Decoder direct_decoder;
  auto direct_result = direct_decoder.DecodeMeshFromBuffer(&direct_buffer);
  CHECK(direct_result.ok());
  std::unique_ptr<draco::Mesh> direct_mesh = std::move(direct_result).value();
  CHECK(direct_mesh != nullptr);
  CHECK(direct_mesh->num_points() == 24);
  CHECK(direct_mesh->num_faces() == 12);
  const draco::PointAttribute* normal = direct_mesh->GetAttributeByUniqueId(0);
  const draco::PointAttribute* position =
      direct_mesh->GetAttributeByUniqueId(1);
  CHECK(normal != nullptr);
  CHECK(position != nullptr);
  const std::vector<uint8_t> expected_normal =
      AttributeBytes<float>(*normal, 24, 3);
  const std::vector<uint8_t> expected_position =
      AttributeBytes<float>(*position, 24, 3);
  const std::vector<uint8_t> expected_indices = IndexBytes(*direct_mesh);
  CHECK(expected_normal.size() == 288);
  CHECK(expected_position.size() == 288);
  CHECK(expected_indices.size() == 72);

  draco::DecoderBuffer stopped_buffer;
  stopped_buffer.Init(reinterpret_cast<const char*>(compressed.data()),
                      compressed.size());
  StopOnAllocationControl stopped_control;
  try {
    static_cast<void>(
        direct_decoder.DecodeMeshFromBuffer(&stopped_buffer, &stopped_control));
    return Fail(__LINE__);
  } catch (const draco::FsvDecodeStopped&) {
  } catch (...) {
    return Fail(__LINE__);
  }

  FsvDracoPrimitiveRequest request;
  request.mesh_index = 0;
  request.primitive_index = 0;
  request.compressed_bytes.assign(compressed.begin(), compressed.end());
  request.attributes["NORMAL"] = 0;
  request.attributes["POSITION"] = 1;
  request.attribute_accessors["NORMAL"] = Accessor(1, 5126, "VEC3", 24);
  request.attribute_accessors["POSITION"] = Accessor(2, 5126, "VEC3", 24);
  request.vertex_accessor_index = 2;
  request.has_indices_accessor = true;
  request.indices_accessor = Accessor(0, 5123, "SCALAR", 36);

  FsvDracoDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(648);
  budget.max_accessors = FsvDracoBudgetNumber::Integer(3);
  budget.max_vertices = FsvDracoBudgetNumber::Integer(24);
  budget.max_indices = FsvDracoBudgetNumber::Integer(36);
  budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(648);
  FsvDracoDecodeBudgetState state;
  state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
  state.accessors = FsvDracoBudgetNumber::Integer(0);
  state.vertices = FsvDracoBudgetNumber::Integer(0);
  state.indices = FsvDracoBudgetNumber::Integer(0);
  state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);

  CHECK(FsvDracoDecoderLinked());
  CHECK(FsvDracoPrimitiveDecodeAvailable());
  OrdinalFailingHeap successful_heap(0);
  fsv_draco::FsvDecodeControl control(1024 * 1024, &successful_heap);
  FsvDracoDecodeTestingCounters success_counters;
  {
    const FsvDracoDecodeResult bridge_result =
        FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state, &success_counters,
                                 &control);
    CHECK(bridge_result.diagnostics.empty());
    CHECK(bridge_result.decoded_primitives.size() == 1);
    CHECK(control.allocation_count() > 1);
    const FsvDracoDecodedPrimitive& decoded =
        bridge_result.decoded_primitives.front();
    CHECK(decoded.mesh_index == 0);
    CHECK(decoded.primitive_index == 0);
    CHECK(decoded.attributes.size() == 2);
    CHECK(decoded.attributes.at("NORMAL") == expected_normal);
    CHECK(decoded.attributes.at("POSITION") == expected_position);
    CHECK(decoded.has_indices);
    CHECK(decoded.indices == expected_indices);

    if (write_outputs) {
      const std::string output_directory(argv[3]);
      CHECK(WriteBytes(output_directory + "/normal.bin",
                       decoded.attributes.at("NORMAL")));
      CHECK(WriteBytes(output_directory + "/position.bin",
                       decoded.attributes.at("POSITION")));
      CHECK(WriteBytes(output_directory + "/indices.bin", decoded.indices));
    }
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());
  CHECK(successful_heap.allocation_calls() >= 32);
  CHECK(successful_heap.allocation_calls() == successful_heap.release_calls());

  const uint64_t box_allocation_ordinals = successful_heap.allocation_calls();
  std::cout << "box_allocation_ordinals=" << box_allocation_ordinals << "\n";
  std::cout << "box_codec_allocation_ordinals="
            << success_counters.codec_allocation_attempts << "\n";
  std::cout << "box_bridge_peak_bytes=" << control.peak_bytes() << "\n";
  CHECK(success_counters.codec_allocation_attempts ==
        kExpectedBoxAllocationOrdinals);
  CHECK(box_allocation_ordinals == kExpectedBoxBridgeAllocationOrdinals);
  CHECK(control.peak_bytes() == kExpectedBoxBridgePeakBytes);
  for (uint64_t ordinal = 1; ordinal <= box_allocation_ordinals; ++ordinal) {
    OrdinalFailingHeap failing_heap(ordinal);
    fsv_draco::FsvDecodeControl failing_control(1024 * 1024, &failing_heap);
    {
      const FsvDracoDecodeResult failing_result = FsvDracoDecodeOwnedPrimitives(
          Requests({&request}), budget, state, nullptr, &failing_control);
      CHECK(failing_result.decoded_primitives.empty());
      CHECK(failing_result.diagnostics.empty());
      CHECK(failing_result.terminal_outcome.kind ==
            FsvDracoTerminalOutcomeKind::kAllocationFailed);
    }
    CHECK(failing_control.stop_reason() ==
          fsv_draco::FsvDecodeStopReason::kAllocationFailure);
    CHECK(failing_control.live_bytes() == 0);
    CHECK(failing_control.allocation_count() ==
          failing_control.release_count());
    CHECK(failing_heap.release_calls() + 1 == failing_heap.allocation_calls());
  }

  for (const auto boundary_stop :
       {FsvDracoDecodeTestingBoundaryStop::kCallerCancelled,
        FsvDracoDecodeTestingBoundaryStop::kDeadline}) {
    fsv_draco::FsvDecodeControl stopping_control(1024 * 1024);
    FsvDracoDecodeTestingCounters stopping_counters;
    stopping_counters.stop_before_codec_dispatch = boundary_stop;
    {
      const FsvDracoDecodeResult stopped_result =
          FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state,
                                        &stopping_counters,
                                        &stopping_control);
      CHECK(stopped_result.decoded_primitives.empty());
      CHECK(stopped_result.diagnostics.empty());
      CHECK(stopped_result.terminal_outcome.kind ==
            (boundary_stop ==
                     FsvDracoDecodeTestingBoundaryStop::kCallerCancelled
                 ? FsvDracoTerminalOutcomeKind::kCallerCancelled
                 : FsvDracoTerminalOutcomeKind::kDeadline));
      CHECK(stopping_control.reserve_rejection_count() == 0);
    }
    CHECK(stopping_control.live_bytes() == 0);
    CHECK(stopping_control.allocation_count() ==
          stopping_control.release_count());
  }
  std::cout << "codec_dispatch_cancel=attributed\n";
  std::cout << "codec_dispatch_deadline=attributed\n";

  FsvDracoPrimitiveRequest second_request(request, nullptr);
  second_request.mesh_index = 1;
  FsvDracoDecodeBudgetMetadata two_primitive_budget = budget;
  two_primitive_budget.max_total_decoded_bytes =
      FsvDracoBudgetNumber::Integer(1296);
  two_primitive_budget.max_native_output_bytes =
      FsvDracoBudgetNumber::Integer(1296);
  OrdinalFailingHeap two_primitive_heap(0);
  fsv_draco::FsvDecodeControl two_primitive_control(
      1024 * 1024, &two_primitive_heap);
  {
    const FsvDracoDecodeResult two_primitive_result =
        FsvDracoDecodeOwnedPrimitives(
            Requests({&request, &second_request}), two_primitive_budget, state, nullptr,
            &two_primitive_control);
    CHECK(two_primitive_result.diagnostics.empty());
    CHECK(two_primitive_result.decoded_primitives.size() == 2);
    for (const FsvDracoDecodedPrimitive& decoded :
         two_primitive_result.decoded_primitives) {
      CHECK(decoded.attributes.at("NORMAL") == expected_normal);
      CHECK(decoded.attributes.at("POSITION") == expected_position);
      CHECK(decoded.indices == expected_indices);
    }
  }
  CHECK(two_primitive_control.live_bytes() == 0);
  CHECK(two_primitive_control.allocation_count() ==
        two_primitive_control.release_count());
  const uint64_t two_primitive_allocation_ordinals =
      two_primitive_heap.allocation_calls();
  std::cout << "two_primitive_allocation_ordinals="
            << two_primitive_allocation_ordinals << "\n";
  std::cout << "two_primitive_bridge_peak_bytes="
            << two_primitive_control.peak_bytes() << "\n";
  CHECK(two_primitive_allocation_ordinals ==
        kExpectedTwoPrimitiveBridgeAllocationOrdinals);
  CHECK(two_primitive_control.peak_bytes() ==
        kExpectedTwoPrimitiveBridgePeakBytes);
  for (uint64_t ordinal = 1;
       ordinal <= two_primitive_allocation_ordinals; ++ordinal) {
    OrdinalFailingHeap failing_heap(ordinal);
    fsv_draco::FsvDecodeControl failing_control(1024 * 1024, &failing_heap);
    {
      const FsvDracoDecodeResult failing_result =
          FsvDracoDecodeOwnedPrimitives(
              Requests({&request, &second_request}), two_primitive_budget, state, nullptr,
              &failing_control);
      CHECK(failing_result.decoded_primitives.empty());
      CHECK(failing_result.diagnostics.empty());
      CHECK(failing_result.terminal_outcome.kind ==
            FsvDracoTerminalOutcomeKind::kAllocationFailed);
    }
    CHECK(failing_control.live_bytes() == 0);
    CHECK(failing_control.allocation_count() ==
          failing_control.release_count());
    CHECK(failing_heap.release_calls() + 1 == failing_heap.allocation_calls());
  }

  fsv_draco::FsvDecodeControl two_primitive_budget_control(
      kExpectedTwoPrimitiveBridgePeakBytes - 1);
  {
    const FsvDracoDecodeResult constrained_result =
        FsvDracoDecodeOwnedPrimitives(
            Requests({&request, &second_request}), two_primitive_budget, state,
            nullptr, &two_primitive_budget_control);
    CHECK(constrained_result.decoded_primitives.empty());
    CHECK(constrained_result.diagnostics.empty());
    CHECK(constrained_result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kBudgetExceeded);
  }
  CHECK(two_primitive_budget_control.live_bytes() == 0);
  CHECK(two_primitive_budget_control.allocation_count() ==
        two_primitive_budget_control.release_count());
  std::cout << "two_primitive_peak_minus_one=budgetExceeded\n";

  fsv_draco::FsvDecodeControl constrained_control(
      kExpectedBoxBridgePeakBytes - 1);
  {
    const FsvDracoDecodeResult constrained_result = FsvDracoDecodeOwnedPrimitives(
        Requests({&request}), budget, state, nullptr, &constrained_control);
    CHECK(constrained_result.decoded_primitives.empty());
    CHECK(constrained_result.diagnostics.empty());
    CHECK(constrained_result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kBudgetExceeded);
  }
  CHECK(constrained_control.stop_reason() ==
        fsv_draco::FsvDecodeStopReason::kBudget);
  CHECK(constrained_control.live_bytes() == 0);
  CHECK(constrained_control.allocation_count() ==
        constrained_control.release_count());
  std::cout << "box_peak_minus_one=budgetExceeded\n";

  fsv_draco::FsvDecodeControl cancelled_control(1024 * 1024);
  CHECK(cancelled_control.Cancel());
  const FsvDracoDecodeResult cancelled_result = FsvDracoDecodeOwnedPrimitives(
      Requests({&request}), budget, state, nullptr, &cancelled_control);
  CHECK(cancelled_result.decoded_primitives.empty());
  CHECK(cancelled_result.diagnostics.empty());
  CHECK(cancelled_result.terminal_outcome.kind ==
        FsvDracoTerminalOutcomeKind::kCallerCancelled);
  CHECK(cancelled_control.stop_reason() ==
        fsv_draco::FsvDecodeStopReason::kCallerCancelled);
  CHECK(cancelled_control.live_bytes() == 0);
  CHECK(cancelled_control.allocation_count() ==
        cancelled_control.release_count());

  FsvDracoPrimitiveRequest corrupted_request(request, nullptr);
  corrupted_request.compressed_bytes.resize(24);
  fsv_draco::FsvDecodeControl corrupted_control(1024 * 1024);
  {
    const FsvDracoDecodeResult corrupted_result = FsvDracoDecodeOwnedPrimitives(
        Requests({&corrupted_request}), budget, state, nullptr, &corrupted_control);
    CHECK(corrupted_result.decoded_primitives.empty());
    CHECK(corrupted_result.diagnostics.size() == 1);
    CHECK(corrupted_result.diagnostics.front().status == "decodeFailed");
  }
  CHECK(corrupted_control.live_bytes() == 0);
  CHECK(corrupted_control.allocation_count() ==
        corrupted_control.release_count());
  CHECK(corrupted_control.allocation_count() > 1);
  std::cout << "corrupted_allocation_count="
            << corrupted_control.allocation_count() << "\n";

  fsv_draco::FsvDecodeControl deadline_control(1024 * 1024);
  CHECK(deadline_control.Deadline());
  const FsvDracoDecodeResult deadline_result =
      FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state, nullptr,
                               &deadline_control);
  CHECK(deadline_result.decoded_primitives.empty());
  CHECK(deadline_result.diagnostics.empty());
  CHECK(deadline_result.terminal_outcome.kind ==
        FsvDracoTerminalOutcomeKind::kDeadline);
  CHECK(deadline_control.stop_reason() ==
        fsv_draco::FsvDecodeStopReason::kDeadline);
  CHECK(deadline_control.live_bytes() == 0);
  CHECK(deadline_control.allocation_count() ==
        deadline_control.release_count());
  return 0;
}
