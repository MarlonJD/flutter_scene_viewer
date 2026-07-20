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
constexpr uint64_t kExpectedSequentialAllocationOrdinals = 68;
constexpr uint64_t kExpectedSequentialBridgeAllocationOrdinals = 96;
constexpr uint64_t kExpectedSequentialBridgePeakBytes = 20921;

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

class OrdinalFailingHeap final : public fsv_draco::FsvDecodeHeap {
 public:
  explicit OrdinalFailingHeap(uint64_t fail_at) : fail_at_(fail_at) {}

  void *Allocate(size_t bytes, size_t alignment) noexcept override {
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

  void Release(void *allocation, size_t bytes,
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
std::vector<uint8_t> AttributeBytes(const draco::PointAttribute &attribute,
                                    int count, int component_count) {
  std::vector<uint8_t> bytes(
      static_cast<size_t>(count * component_count) * sizeof(T));
  std::vector<T> values(static_cast<size_t>(component_count));
  for (int point = 0; point < count; ++point) {
    const draco::PointIndex point_index(point);
    if (!attribute.ConvertValue<T>(attribute.mapped_index(point_index),
                                   static_cast<int8_t>(component_count),
                                   values.data())) {
      return {};
    }
    std::memcpy(bytes.data() +
                    static_cast<size_t>(point * component_count) * sizeof(T),
                values.data(),
                static_cast<size_t>(component_count) * sizeof(T));
  }
  return bytes;
}

std::vector<uint8_t> IndexBytes(const draco::Mesh &mesh) {
  std::vector<uint8_t> bytes;
  bytes.reserve(static_cast<size_t>(mesh.num_faces()) * 3 * sizeof(uint16_t));
  for (draco::FaceIndex face_index(0); face_index < mesh.num_faces();
       ++face_index) {
    const draco::Mesh::Face &face = mesh.face(face_index);
    for (int corner = 0; corner < 3; ++corner) {
      const uint16_t value = static_cast<uint16_t>(face[corner].value());
      const auto *value_bytes = reinterpret_cast<const uint8_t *>(&value);
      bytes.insert(bytes.end(), value_bytes, value_bytes + sizeof(value));
    }
  }
  return bytes;
}

FsvDracoAccessorSchema Accessor(int index, int component_type,
                                std::string type, int64_t count) {
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
}  // namespace

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main(int argc, char **argv) {
  CHECK(argc == 2);
  std::ifstream input(argv[1], std::ios::binary);
  CHECK(input.good());
  const std::vector<uint8_t> compressed(
      (std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  CHECK(compressed.size() == 132);
  CHECK(compressed[0] == 'D' && compressed[1] == 'R' &&
        compressed[2] == 'A' && compressed[3] == 'C' &&
        compressed[4] == 'O');
  CHECK(compressed[5] == 2 && compressed[6] == 2);
  CHECK(compressed[7] == draco::TRIANGULAR_MESH);
  CHECK(compressed[8] == draco::MESH_SEQUENTIAL_ENCODING);

  draco::DecoderBuffer direct_buffer;
  direct_buffer.Init(reinterpret_cast<const char *>(compressed.data()),
                     compressed.size());
  draco::Decoder direct_decoder;
  auto direct_result = direct_decoder.DecodeMeshFromBuffer(&direct_buffer);
  CHECK(direct_result.ok());
  std::unique_ptr<draco::Mesh> direct_mesh = std::move(direct_result).value();
  CHECK(direct_mesh != nullptr);
  CHECK(direct_mesh->num_points() == 4);
  CHECK(direct_mesh->num_faces() == 2);
  const draco::PointAttribute *position =
      direct_mesh->GetAttributeByUniqueId(0);
  const draco::PointAttribute *feature = direct_mesh->GetAttributeByUniqueId(1);
  const draco::PointAttribute *raw = direct_mesh->GetAttributeByUniqueId(2);
  CHECK(position != nullptr);
  CHECK(feature != nullptr);
  CHECK(raw != nullptr);
  const std::vector<uint8_t> expected_position =
      AttributeBytes<float>(*position, 4, 3);
  const std::vector<uint8_t> expected_feature =
      AttributeBytes<uint16_t>(*feature, 4, 1);
  const std::vector<uint8_t> expected_raw = AttributeBytes<float>(*raw, 4, 1);
  const std::vector<uint8_t> expected_indices = IndexBytes(*direct_mesh);
  CHECK(expected_position.size() == 48);
  CHECK(expected_feature.size() == 8);
  CHECK(expected_raw.size() == 16);
  CHECK(expected_indices.size() == 12);

  FsvDracoPrimitiveRequest request;
  request.mesh_index = 0;
  request.primitive_index = 0;
  request.compressed_bytes.assign(compressed.begin(), compressed.end());
  request.attributes["POSITION"] = 0;
  request.attributes["_FEATURE_ID_0"] = 1;
  request.attributes["_RAW_0"] = 2;
  request.attribute_accessors["POSITION"] = Accessor(1, 5126, "VEC3", 4);
  request.attribute_accessors["_FEATURE_ID_0"] =
      Accessor(2, 5123, "SCALAR", 4);
  request.attribute_accessors["_RAW_0"] = Accessor(3, 5126, "SCALAR", 4);
  request.vertex_accessor_index = 1;
  request.has_indices_accessor = true;
  request.indices_accessor = Accessor(0, 5123, "SCALAR", 6);

  FsvDracoDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(84);
  budget.max_accessors = FsvDracoBudgetNumber::Integer(4);
  budget.max_vertices = FsvDracoBudgetNumber::Integer(4);
  budget.max_indices = FsvDracoBudgetNumber::Integer(6);
  budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(84);
  FsvDracoDecodeBudgetState state;
  state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
  state.accessors = FsvDracoBudgetNumber::Integer(0);
  state.vertices = FsvDracoBudgetNumber::Integer(0);
  state.indices = FsvDracoBudgetNumber::Integer(0);
  state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);

  OrdinalFailingHeap successful_heap(0);
  fsv_draco::FsvDecodeControl control(1024 * 1024, &successful_heap);
  FsvDracoDecodeTestingCounters success_counters;
  {
    const FsvDracoDecodeResult bridge_result =
        FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state, &success_counters,
                                 &control);
    CHECK(bridge_result.diagnostics.empty());
    CHECK(bridge_result.decoded_primitives.size() == 1);
    const FsvDracoDecodedPrimitive &decoded =
        bridge_result.decoded_primitives.front();
    CHECK(decoded.attributes.at("POSITION") == expected_position);
    CHECK(decoded.attributes.at("_FEATURE_ID_0") == expected_feature);
    CHECK(decoded.attributes.at("_RAW_0") == expected_raw);
    CHECK(decoded.has_indices);
    CHECK(decoded.indices == expected_indices);
  }
  CHECK(control.live_bytes() == 0);
  CHECK(control.allocation_count() == control.release_count());
  CHECK(successful_heap.allocation_calls() == successful_heap.release_calls());

  const uint64_t sequential_allocation_ordinals =
      successful_heap.allocation_calls();
  std::cout << "sequential_allocation_ordinals="
            << sequential_allocation_ordinals << "\n";
  std::cout << "sequential_codec_allocation_ordinals="
            << success_counters.codec_allocation_attempts << "\n";
  std::cout << "sequential_bridge_peak_bytes=" << control.peak_bytes() << "\n";
  CHECK(success_counters.codec_allocation_attempts ==
        kExpectedSequentialAllocationOrdinals);
  CHECK(sequential_allocation_ordinals ==
        kExpectedSequentialBridgeAllocationOrdinals);
  CHECK(control.peak_bytes() == kExpectedSequentialBridgePeakBytes);
  for (uint64_t ordinal = 1; ordinal <= sequential_allocation_ordinals;
       ++ordinal) {
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

  fsv_draco::FsvDecodeControl constrained_control(
      kExpectedSequentialBridgePeakBytes - 1);
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
  std::cout << "sequential_peak_minus_one=budgetExceeded\n";
  return 0;
}
