#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <future>
#include <iostream>
#include <iterator>
#include <cstdlib>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include "draco/compression/decode.h"
#include "draco/core/decoder_buffer.h"
#include "draco/core/status.h"
#include "draco/mesh/mesh.h"
#include "draco/metadata/geometry_metadata.h"
#include "fsv_draco_bridge.h"

namespace {
thread_local bool g_track_host_allocations = false;
thread_local uint64_t g_host_allocation_count = 0;
#if defined(__has_feature)
#if __has_feature(address_sanitizer)
constexpr bool kCanTrackHostAllocations = false;
#else
constexpr bool kCanTrackHostAllocations = true;
#endif
#else
constexpr bool kCanTrackHostAllocations = true;
#endif
}  // namespace

void *operator new(std::size_t size) {
  if (g_track_host_allocations) {
    ++g_host_allocation_count;
  }
  if (void *const allocation = std::malloc(size)) {
    return allocation;
  }
  throw std::bad_alloc();
}

void operator delete(void *allocation) noexcept { std::free(allocation); }
void operator delete(void *allocation, std::size_t) noexcept {
  std::free(allocation);
}

namespace {

constexpr uint64_t kExpectedMetadataAllocationOrdinals = 47;
constexpr uint64_t kExpectedMetadataBridgeAllocationOrdinals = 63;
constexpr uint64_t kExpectedMetadataBridgePeakBytes = 30083;
constexpr uint64_t kExpectedMetadataSourceAllocations = 47;
constexpr uint64_t kExpectedMetadataDestinationAllocations = 22;
constexpr uint64_t kExpectedMetadataBlobStopAllocations = 14;
constexpr uint64_t kExpectedMetadataCorruptAllocations = 26;
constexpr char kLongStatusLiteral[] =
    "A controlled Draco decode error literal deliberately exceeds small-string "
    "storage so construction must read it through a nonallocating view and "
    "charge only the request-owned destination string allocation, without "
    "first materializing an ordinary host std::string temporary.";

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

class TrackingControl final : public draco::FsvDecodeControl {
 public:
  explicit TrackingControl(uint64_t fail_at = 0) : fail_at_(fail_at) {}

  bool ShouldStopDecoding() const override {
    if (!stopped_ && blob_allocated_ && blob_stop_after_checks_ != 0) {
      ++blob_check_count_;
      if (blob_check_count_ >= blob_stop_after_checks_) {
        stopped_ = true;
      }
    }
    return stopped_;
  }

  AllocationResult AllocateMemory(size_t bytes,
                                  size_t alignment) noexcept override {
    ++allocation_attempt_count_;
    if (stopped_) {
      ++post_stop_allocation_attempts_;
      return {nullptr, AllocationOutcome::kStopped};
    }
    if (allocation_attempt_count_ == fail_at_) {
      return {nullptr, AllocationOutcome::kHeapFailure};
    }
    void *allocation = nullptr;
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      allocation = ::operator new(bytes, std::align_val_t(alignment),
                                  std::nothrow);
    } else {
#endif
      allocation = ::operator new(bytes, std::nothrow);
#if defined(__cpp_aligned_new)
    }
#endif
    if (allocation == nullptr) {
      return {nullptr, AllocationOutcome::kHeapFailure};
    }
    ++allocation_count_;
    live_bytes_ += bytes;
    if (bytes == 4096) {
      blob_allocated_ = true;
    }
    return {allocation, bytes, alignment, AllocationOutcome::kSuccess};
  }

  bool ReleaseMemory(AllocationResult *allocation_record,
                     void *allocation, size_t bytes,
                     size_t alignment) noexcept override {
    if (allocation_record == nullptr ||
        allocation_record->allocation != allocation ||
        allocation_record->bytes != bytes ||
        allocation_record->alignment != alignment ||
        allocation_record->outcome != AllocationOutcome::kSuccess) {
      return false;
    }
    *allocation_record = AllocationResult();
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      ::operator delete(allocation, std::align_val_t(alignment));
    } else {
#endif
      ::operator delete(allocation);
#if defined(__cpp_aligned_new)
    }
#endif
    ++release_count_;
    live_bytes_ -= bytes;
    return true;
  }

  void Stop() { stopped_ = true; }
  void StopDuringBlobAfter(uint64_t checks) {
    blob_stop_after_checks_ = checks;
  }
  uint64_t blob_check_count() const { return blob_check_count_; }
  uint64_t allocation_count() const { return allocation_count_; }
  uint64_t allocation_attempt_count() const {
    return allocation_attempt_count_;
  }
  uint64_t release_count() const { return release_count_; }
  uint64_t post_stop_allocation_attempts() const {
    return post_stop_allocation_attempts_;
  }
  size_t live_bytes() const { return live_bytes_; }

 private:
  uint64_t fail_at_ = 0;
  mutable bool stopped_ = false;
  mutable bool blob_allocated_ = false;
  mutable uint64_t blob_check_count_ = 0;
  uint64_t blob_stop_after_checks_ = 0;
  uint64_t allocation_count_ = 0;
  uint64_t allocation_attempt_count_ = 0;
  uint64_t release_count_ = 0;
  uint64_t post_stop_allocation_attempts_ = 0;
  size_t live_bytes_ = 0;
};

class OrdinalFailingHeap : public fsv_draco::FsvDecodeHeap {
 public:
  explicit OrdinalFailingHeap(uint64_t fail_at = 0) : fail_at_(fail_at) {}

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

  void Release(void *allocation, size_t, size_t alignment) noexcept override {
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
  uint64_t fail_at_;
  uint64_t allocation_calls_ = 0;
  uint64_t release_calls_ = 0;
};

class StoppingHeap final : public OrdinalFailingHeap {
 public:
  enum class Kind { kCancel, kDeadline };
  StoppingHeap(uint64_t stop_at, Kind kind)
      : OrdinalFailingHeap(), stop_at_(stop_at), kind_(kind) {}

  void SetControl(fsv_draco::FsvDecodeControl *control) { control_ = control; }

  void *Allocate(size_t bytes, size_t alignment) noexcept override {
    ++calls_;
    if (calls_ == stop_at_ && control_ != nullptr) {
      if (kind_ == Kind::kCancel) {
        control_->Cancel();
      } else {
        control_->Deadline();
      }
    }
    return OrdinalFailingHeap::Allocate(bytes, alignment);
  }

 private:
  uint64_t stop_at_;
  Kind kind_;
  uint64_t calls_ = 0;
  fsv_draco::FsvDecodeControl *control_ = nullptr;
};

std::string LongName(char value) { return std::string(120, value); }

bool MetadataMatches(const draco::GeometryMetadata &metadata) {
  std::string geometry_value;
  if (!metadata.GetEntryString(LongName('g'), &geometry_value) ||
      geometry_value != std::string(180, 'G')) {
    return false;
  }
  std::vector<uint8_t> blob;
  if (!metadata.GetEntryBinary("non_trivial_blob", &blob) ||
      blob.size() != 4096) {
    return false;
  }
  for (size_t i = 0; i < blob.size(); ++i) {
    if (blob[i] != static_cast<uint8_t>((i * 37 + 11) & 0xff)) {
      return false;
    }
  }
  const draco::AttributeMetadata *attribute =
      metadata.GetAttributeMetadataByUniqueId(0);
  std::string attribute_value;
  if (attribute == nullptr ||
      !attribute->GetEntryString(LongName('a'), &attribute_value) ||
      attribute_value != std::string(170, 'A')) {
    return false;
  }
  const draco::Metadata *nested = metadata.GetSubMetadata(LongName('s'));
  if (nested == nullptr) {
    return false;
  }
  std::string nested_value;
  if (!nested->GetEntryString(LongName('n'), &nested_value) ||
      nested_value != std::string(160, 'N')) {
    return false;
  }
  const draco::Metadata *leaf = nested->GetSubMetadata(LongName('l'));
  int32_t leaf_value = 0;
  return leaf != nullptr && leaf->GetEntryInt("leaf_value", &leaf_value) &&
         leaf_value == 1701;
}

size_t PristineMetadataHash(const draco::Metadata &metadata) {
  size_t hash = draco::HashCombine(metadata.entries().size(),
                                   metadata.sub_metadatas().size());
  draco::EntryValueHasher entry_value_hasher;
  for (const auto &entry : metadata.entries()) {
    hash = draco::HashCombine(
        std::string(entry.first.begin(), entry.first.end()), hash);
    hash = draco::HashCombine(entry_value_hasher(entry.second), hash);
  }
  for (const auto &sub_metadata : metadata.sub_metadatas()) {
    hash = draco::HashCombine(
        std::string(sub_metadata.first.begin(), sub_metadata.first.end()), hash);
    hash = draco::HashCombine(PristineMetadataHash(*sub_metadata.second), hash);
  }
  return hash;
}

std::vector<uint8_t> PositionBytes(const draco::Mesh &mesh) {
  const draco::PointAttribute *position = mesh.GetAttributeByUniqueId(0);
  if (position == nullptr) return {};
  std::vector<uint8_t> bytes(36);
  float value[3];
  for (int point = 0; point < 3; ++point) {
    if (!position->ConvertValue<float>(
            position->mapped_index(draco::PointIndex(point)), 3, value)) {
      return {};
    }
    std::memcpy(bytes.data() + point * 12, value, 12);
  }
  return bytes;
}

std::vector<uint8_t> IndexBytes(const draco::Mesh &mesh) {
  std::vector<uint8_t> bytes;
  for (draco::FaceIndex face(0); face < mesh.num_faces(); ++face) {
    for (int corner = 0; corner < 3; ++corner) {
      const uint16_t value =
          static_cast<uint16_t>(mesh.face(face)[corner].value());
      const uint8_t *raw = reinterpret_cast<const uint8_t *>(&value);
      bytes.insert(bytes.end(), raw, raw + 2);
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

FsvDracoPrimitiveRequest Request(const std::vector<uint8_t> &compressed) {
  FsvDracoPrimitiveRequest request;
  request.mesh_index = 0;
  request.primitive_index = 0;
  request.compressed_bytes.assign(compressed.begin(), compressed.end());
  request.attributes["POSITION"] = 0;
  request.attribute_accessors["POSITION"] =
      Accessor(1, 5126, "VEC3", 3);
  request.vertex_accessor_index = 1;
  request.has_indices_accessor = true;
  request.indices_accessor = Accessor(0, 5123, "SCALAR", 3);
  return request;
}

FsvDracoPrimitiveRequests Requests(
    std::initializer_list<const FsvDracoPrimitiveRequest *> sources) {
  FsvDracoPrimitiveRequests requests{
      FsvDracoAllocator<FsvDracoPrimitiveRequest>(nullptr)};
  for (const FsvDracoPrimitiveRequest *source : sources) {
    requests.emplace_back(*source, nullptr);
  }
  return requests;
}

FsvDracoDecodeBudgetMetadata Budget() {
  FsvDracoDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvDracoBudgetNumber::Integer(42);
  budget.max_accessors = FsvDracoBudgetNumber::Integer(2);
  budget.max_vertices = FsvDracoBudgetNumber::Integer(3);
  budget.max_indices = FsvDracoBudgetNumber::Integer(3);
  budget.max_native_output_bytes = FsvDracoBudgetNumber::Integer(42);
  return budget;
}

FsvDracoDecodeBudgetState State() {
  FsvDracoDecodeBudgetState state;
  state.total_decoded_bytes = FsvDracoBudgetNumber::Integer(0);
  state.accessors = FsvDracoBudgetNumber::Integer(0);
  state.vertices = FsvDracoBudgetNumber::Integer(0);
  state.indices = FsvDracoBudgetNumber::Integer(0);
  state.native_output_bytes = FsvDracoBudgetNumber::Integer(0);
  return state;
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
  CHECK(compressed.size() == 5332);

  TrackingControl destination_control;
  std::unique_ptr<draco::GeometryMetadata> destination;
  std::unique_ptr<draco::GeometryMetadata> detached_copy;
  std::unique_ptr<draco::GeometryMetadata> detached_move;
  std::vector<uint8_t> direct_positions;
  std::vector<uint8_t> direct_indices;
  uint64_t source_allocations = 0;
  size_t metadata_hash = 0;
  uint64_t accepted_decode_host_allocations = 0;
  {
    TrackingControl source_control;
    {
      draco::DecoderBuffer buffer;
      buffer.Init(reinterpret_cast<const char *>(compressed.data()),
                  compressed.size());
      draco::Decoder decoder;
      g_host_allocation_count = 0;
      g_track_host_allocations = kCanTrackHostAllocations;
      auto result = decoder.DecodeMeshFromBuffer(&buffer, &source_control);
      g_track_host_allocations = false;
      accepted_decode_host_allocations = g_host_allocation_count;
      CHECK(result.ok());
      std::unique_ptr<draco::Mesh> mesh = std::move(result).value();
      CHECK(mesh != nullptr && mesh->GetMetadata() != nullptr);
      CHECK(MetadataMatches(*mesh->GetMetadata()));
      CHECK(draco::MetadataHasher()(*mesh->GetMetadata()) ==
            PristineMetadataHash(*mesh->GetMetadata()));
      metadata_hash = draco::MetadataHasher()(*mesh->GetMetadata());
      direct_positions = PositionBytes(*mesh);
      direct_indices = IndexBytes(*mesh);
      destination.reset(new (&destination_control) draco::GeometryMetadata(
          *mesh->GetMetadata(), &destination_control));
      detached_copy.reset(new draco::GeometryMetadata(*mesh->GetMetadata()));
      detached_move.reset(
          new draco::GeometryMetadata(std::move(*detached_copy)));
      source_allocations = source_control.allocation_count();
    }
    CHECK(source_control.live_bytes() == 0);
    CHECK(source_control.allocation_count() == source_control.release_count());
  }
  CHECK(destination != nullptr);
  CHECK(MetadataMatches(*destination));
  CHECK(detached_move != nullptr && MetadataMatches(*detached_move));
  std::cout << "metadata_source_allocations=" << source_allocations << "\n";
  std::cout << "metadata_accepted_host_allocations="
            << accepted_decode_host_allocations << "\n";
  std::cout << "metadata_hash_matches_pristine=" << metadata_hash << "\n";
  std::cout << "metadata_destination_allocations="
            << destination_control.allocation_count() << "\n";
  CHECK(source_allocations == kExpectedMetadataSourceAllocations);
  CHECK(!kCanTrackHostAllocations ||
        accepted_decode_host_allocations == source_allocations);
  CHECK(destination_control.allocation_count() ==
        kExpectedMetadataDestinationAllocations);
  for (uint64_t ordinal = 1;
       ordinal <= kExpectedMetadataDestinationAllocations; ++ordinal) {
    TrackingControl failing_destination_control(ordinal);
    bool allocation_failed = false;
    try {
      std::unique_ptr<draco::GeometryMetadata> failed_copy(
          new (&failing_destination_control) draco::GeometryMetadata(
              *destination, &failing_destination_control));
    } catch (const std::bad_alloc &) {
      allocation_failed = true;
    }
    CHECK(allocation_failed);
    CHECK(failing_destination_control.allocation_attempt_count() == ordinal);
    CHECK(failing_destination_control.allocation_count() ==
          failing_destination_control.release_count());
    CHECK(failing_destination_control.live_bytes() == 0);
  }
  std::cout << "metadata_destination_copy_ordinals="
            << kExpectedMetadataDestinationAllocations << "\n";
  destination.reset();
  detached_copy.reset();
  detached_move.reset();
  CHECK(destination_control.live_bytes() == 0);
  CHECK(destination_control.allocation_count() ==
        destination_control.release_count());

  TrackingControl status_destination_control;
  std::unique_ptr<draco::Status> destination_status;
  std::unique_ptr<draco::Status> detached_status;
  {
    TrackingControl status_source_control;
    {
      const std::string long_message(300, 'E');
      draco::Status source(draco::Status::DRACO_ERROR, long_message,
                           &status_source_control);
      CHECK(status_source_control.allocation_count() == 1);
      destination_status.reset(new draco::Status(
          source, &status_destination_control));
      detached_status.reset(new draco::Status(std::move(source)));
      CHECK(status_destination_control.allocation_count() == 1);
    }
    CHECK(status_source_control.live_bytes() == 0);
    CHECK(status_source_control.allocation_count() == 1);
    CHECK(status_source_control.release_count() == 1);
  }
  CHECK(destination_status->error_msg_string().size() == 300);
  CHECK(detached_status->error_msg_string().size() == 300);
  destination_status.reset();
  detached_status.reset();
  CHECK(status_destination_control.live_bytes() == 0);
  CHECK(status_destination_control.allocation_count() == 1);
  CHECK(status_destination_control.release_count() == 1);

  TrackingControl literal_status_control;
  uint64_t literal_host_allocation_count = 0;
  g_host_allocation_count = 0;
  g_track_host_allocations = kCanTrackHostAllocations;
  {
    draco::Status literal_status(draco::Status::DRACO_ERROR,
                                 kLongStatusLiteral, &literal_status_control);
    g_track_host_allocations = false;
    CHECK(literal_status_control.allocation_count() == 1);
    literal_host_allocation_count = g_host_allocation_count;
    CHECK(std::strcmp(literal_status.error_msg(), kLongStatusLiteral) == 0);
  }
  g_track_host_allocations = false;
  CHECK(literal_status_control.live_bytes() == 0);
  CHECK(literal_status_control.allocation_count() ==
        literal_status_control.release_count());
  std::cout << "status_literal_host_temporaries=0\n";

  TrackingControl stopped_status_control;
  {
    const std::string long_message(300, 'E');
    draco::Status target(draco::Status::DRACO_ERROR, long_message,
                         &stopped_status_control);
    draco::Status source(draco::Status::DRACO_ERROR, long_message);
    stopped_status_control.Stop();
    target = source;
    CHECK(target.error_msg_string().empty());
    CHECK(stopped_status_control.post_stop_allocation_attempts() == 0);
    draco::Status stopped(draco::Status::DRACO_ERROR, long_message,
                          &stopped_status_control);
    CHECK(stopped.error_msg_string().empty());
    CHECK(stopped_status_control.post_stop_allocation_attempts() == 0);
  }
  CHECK(stopped_status_control.live_bytes() == 0);
  CHECK(stopped_status_control.allocation_count() ==
        stopped_status_control.release_count());
  std::cout << "status_source_destination_allocations=1/1\n";

  TrackingControl entry_destination_control;
  std::unique_ptr<draco::EntryValue> entry_destination_copy;
  std::unique_ptr<draco::EntryValue> entry_destination_move;
  std::unique_ptr<draco::EntryValue> entry_detached_copy;
  std::unique_ptr<draco::EntryValue> entry_detached_move;
  {
    TrackingControl entry_source_control;
    {
      const std::vector<uint8_t> value(300, 0x5a);
      draco::EntryValue source_copy(value, &entry_source_control);
      draco::EntryValue source_move(value, &entry_source_control);
      draco::EntryValue source_detached_copy(value, &entry_source_control);
      draco::EntryValue source_detached_move(value, &entry_source_control);
      entry_destination_copy.reset(new draco::EntryValue(
          source_copy, &entry_destination_control));
      entry_destination_move.reset(new draco::EntryValue(
          std::move(source_move), &entry_destination_control));
      entry_detached_copy.reset(new draco::EntryValue(source_detached_copy));
      entry_detached_move.reset(
          new draco::EntryValue(std::move(source_detached_move)));
      CHECK(entry_source_control.allocation_count() == 4);
      CHECK(entry_destination_control.allocation_count() == 2);
    }
    CHECK(entry_source_control.live_bytes() == 0);
    CHECK(entry_source_control.allocation_count() == 4);
    CHECK(entry_source_control.release_count() == 4);
  }
  for (const draco::EntryValue *entry :
       {entry_destination_copy.get(), entry_destination_move.get(),
        entry_detached_copy.get(), entry_detached_move.get()}) {
    std::vector<uint8_t> value;
    CHECK(entry != nullptr && entry->GetValue(&value));
    CHECK(value == std::vector<uint8_t>(300, 0x5a));
  }
  entry_destination_copy.reset();
  entry_destination_move.reset();
  entry_detached_copy.reset();
  entry_detached_move.reset();
  CHECK(entry_destination_control.live_bytes() == 0);
  CHECK(entry_destination_control.allocation_count() == 2);
  CHECK(entry_destination_control.release_count() == 2);
  std::cout << "entry_value_source_destination_allocations=4/2\n";

  std::unique_ptr<draco::Metadata> detached_metadata_copy;
  std::unique_ptr<draco::Metadata> detached_metadata_move;
  {
    TrackingControl metadata_source_control;
    {
      draco::Metadata source(&metadata_source_control);
      source.AddEntryString(LongName('d'), std::string(200, 'D'));
      detached_metadata_copy.reset(new draco::Metadata(source));
      detached_metadata_move.reset(new draco::Metadata(std::move(source)));
      CHECK(metadata_source_control.allocation_count() == 3);
    }
    CHECK(metadata_source_control.live_bytes() == 0);
    CHECK(metadata_source_control.allocation_count() == 3);
    CHECK(metadata_source_control.release_count() == 3);
  }
  for (const draco::Metadata *metadata :
       {detached_metadata_copy.get(), detached_metadata_move.get()}) {
    std::string value;
    CHECK(metadata != nullptr &&
          metadata->GetEntryString(LongName('d'), &value));
    CHECK(value == std::string(200, 'D'));
  }
  detached_metadata_copy.reset();
  detached_metadata_move.reset();
  std::cout << "metadata_detached_source_allocations=3\n";

  TrackingControl blob_checkpoint_control;
  blob_checkpoint_control.StopDuringBlobAfter(3);
  {
    draco::DecoderBuffer buffer;
    buffer.Init(reinterpret_cast<const char *>(compressed.data()),
                compressed.size());
    draco::Decoder decoder;
    auto result =
        decoder.DecodeMeshFromBuffer(&buffer, &blob_checkpoint_control);
    CHECK(!result.ok());
  }
  CHECK(blob_checkpoint_control.blob_check_count() == 3);
  CHECK(blob_checkpoint_control.live_bytes() == 0);
  CHECK(blob_checkpoint_control.allocation_count() ==
        blob_checkpoint_control.release_count());
  CHECK(blob_checkpoint_control.allocation_count() ==
        kExpectedMetadataBlobStopAllocations);
  CHECK(blob_checkpoint_control.post_stop_allocation_attempts() == 0);
  std::cout << "metadata_blob_stop_allocations="
            << blob_checkpoint_control.allocation_count() << "\n";

  const FsvDracoPrimitiveRequest request = Request(compressed);
  const FsvDracoDecodeBudgetMetadata budget = Budget();
  const FsvDracoDecodeBudgetState state = State();
  OrdinalFailingHeap success_heap;
  fsv_draco::FsvDecodeControl success_control(1024 * 1024, &success_heap);
  FsvDracoDecodeTestingCounters success_counters;
  {
    const FsvDracoDecodeResult result = FsvDracoDecodeOwnedPrimitives(
        Requests({&request}), budget, state, &success_counters, &success_control);
    CHECK(result.diagnostics.empty());
    CHECK(result.decoded_primitives.size() == 1);
    CHECK(result.decoded_primitives.front().attributes.at("POSITION") ==
          direct_positions);
    CHECK(result.decoded_primitives.front().indices == direct_indices);
  }
  CHECK(success_control.live_bytes() == 0);
  CHECK(success_control.allocation_count() == success_control.release_count());
  CHECK(success_heap.allocation_calls() == success_heap.release_calls());
  const uint64_t allocation_ordinals = success_heap.allocation_calls();
  std::cout << "metadata_allocation_ordinals=" << allocation_ordinals << "\n";
  std::cout << "metadata_codec_allocation_ordinals="
            << success_counters.codec_allocation_attempts << "\n";
  std::cout << "metadata_peak_bytes=" << success_control.peak_bytes() << "\n";
  CHECK(success_counters.codec_allocation_attempts ==
        kExpectedMetadataAllocationOrdinals);
  CHECK(allocation_ordinals == kExpectedMetadataBridgeAllocationOrdinals);
  CHECK(success_control.peak_bytes() == kExpectedMetadataBridgePeakBytes);

  for (uint64_t ordinal = 1; ordinal <= allocation_ordinals; ++ordinal) {
    OrdinalFailingHeap failing_heap(ordinal);
    fsv_draco::FsvDecodeControl failing_control(1024 * 1024, &failing_heap);
    {
      const FsvDracoDecodeResult result = FsvDracoDecodeOwnedPrimitives(
          Requests({&request}), budget, state, nullptr, &failing_control);
      CHECK(result.decoded_primitives.empty());
      CHECK(result.diagnostics.empty());
      CHECK(result.terminal_outcome.kind ==
            FsvDracoTerminalOutcomeKind::kAllocationFailed);
    }
    CHECK(failing_control.stop_reason() ==
          fsv_draco::FsvDecodeStopReason::kAllocationFailure);
    CHECK(failing_control.live_bytes() == 0);
    CHECK(failing_control.allocation_count() == failing_control.release_count());
    CHECK(failing_heap.release_calls() + 1 == failing_heap.allocation_calls());
  }

  CHECK(success_control.peak_bytes() > 0);
  fsv_draco::FsvDecodeControl budget_control(success_control.peak_bytes() - 1);
  {
    const FsvDracoDecodeResult result = FsvDracoDecodeOwnedPrimitives(
        Requests({&request}), budget, state, nullptr, &budget_control);
    CHECK(result.decoded_primitives.empty());
    CHECK(result.diagnostics.empty());
    CHECK(result.terminal_outcome.kind ==
          FsvDracoTerminalOutcomeKind::kBudgetExceeded);
  }
  CHECK(budget_control.live_bytes() == 0);
  CHECK(budget_control.allocation_count() == budget_control.release_count());

  for (const auto kind : {StoppingHeap::Kind::kCancel,
                          StoppingHeap::Kind::kDeadline}) {
    StoppingHeap stopping_heap(10, kind);
    fsv_draco::FsvDecodeControl stopping_control(1024 * 1024, &stopping_heap);
    stopping_heap.SetControl(&stopping_control);
    const FsvDracoDecodeResult result = FsvDracoDecodeOwnedPrimitives(
        Requests({&request}), budget, state, nullptr, &stopping_control);
    CHECK(result.decoded_primitives.empty());
    CHECK(result.diagnostics.empty());
    CHECK(result.terminal_outcome.kind ==
          (kind == StoppingHeap::Kind::kCancel
               ? FsvDracoTerminalOutcomeKind::kCallerCancelled
               : FsvDracoTerminalOutcomeKind::kDeadline));
    CHECK(stopping_control.live_bytes() == 0);
    CHECK(stopping_control.allocation_count() ==
          stopping_control.release_count());
    CHECK(stopping_control.stop_reason() ==
          (kind == StoppingHeap::Kind::kCancel
               ? fsv_draco::FsvDecodeStopReason::kCallerCancelled
               : fsv_draco::FsvDecodeStopReason::kDeadline));
  }

  std::vector<uint8_t> corrupt = compressed;
  corrupt.resize(2048);
  TrackingControl final_status_control;
  uint64_t final_status_allocation_attempts = 0;
  {
    draco::DecoderBuffer buffer;
    buffer.Init(reinterpret_cast<const char *>(corrupt.data()), corrupt.size());
    draco::Decoder decoder;
    auto result = decoder.DecodeMeshFromBuffer(&buffer, &final_status_control);
    CHECK(!result.ok());
    CHECK(std::strcmp(result.status().error_msg(),
                      "Failed to decode metadata.") == 0);
    CHECK(final_status_control.allocation_count() ==
          final_status_control.release_count() + 1);
    CHECK(final_status_control.live_bytes() > 0);
    final_status_allocation_attempts =
        final_status_control.allocation_attempt_count();
  }
  CHECK(final_status_control.live_bytes() == 0);
  CHECK(final_status_control.allocation_count() ==
        final_status_control.release_count());
  CHECK(!kCanTrackHostAllocations ||
        literal_host_allocation_count ==
            literal_status_control.allocation_count());
  std::cout << "metadata_final_status_allocations="
            << final_status_allocation_attempts << "\n";

  TrackingControl failed_status_control(final_status_allocation_attempts);
  bool final_status_allocation_failed = false;
  try {
    draco::DecoderBuffer buffer;
    buffer.Init(reinterpret_cast<const char *>(corrupt.data()), corrupt.size());
    draco::Decoder decoder;
    auto result = decoder.DecodeMeshFromBuffer(&buffer, &failed_status_control);
    (void)result;
  } catch (const std::bad_alloc &) {
    final_status_allocation_failed = true;
  }
  CHECK(final_status_allocation_failed);
  CHECK(failed_status_control.allocation_attempt_count() ==
        final_status_allocation_attempts);
  CHECK(failed_status_control.live_bytes() == 0);
  CHECK(failed_status_control.allocation_count() ==
        failed_status_control.release_count());
  std::cout << "metadata_final_status_failure_ordinal="
            << final_status_allocation_attempts << "\n";

  fsv_draco::FsvDecodeControl corrupt_control(1024 * 1024);
  const FsvDracoPrimitiveRequest corrupt_request = Request(corrupt);
  {
    const FsvDracoDecodeResult result = FsvDracoDecodeOwnedPrimitives(
        Requests({&corrupt_request}), budget, state, nullptr, &corrupt_control);
    CHECK(result.decoded_primitives.empty());
    CHECK(result.diagnostics.size() == 1);
    CHECK(result.diagnostics.front().status == "decodeFailed");
  }
  CHECK(corrupt_control.live_bytes() == 0);
  CHECK(corrupt_control.allocation_count() == corrupt_control.release_count());
  std::cout << "metadata_corrupt_allocations="
            << corrupt_control.allocation_count() << "\n";
  CHECK(corrupt_control.allocation_count() ==
        kExpectedMetadataCorruptAllocations);

  OrdinalFailingHeap concurrent_heap;
  fsv_draco::FsvDecodeControl concurrent_control(1024 * 1024,
                                                  &concurrent_heap);
  StoppingHeap concurrent_stopping_heap(10, StoppingHeap::Kind::kCancel);
  fsv_draco::FsvDecodeControl concurrent_stopping_control(
      1024 * 1024, &concurrent_stopping_heap);
  concurrent_stopping_heap.SetControl(&concurrent_stopping_control);
  auto success_future = std::async(std::launch::async, [&]() {
    return FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state, nullptr,
                                    &concurrent_control);
  });
  auto stopped_future = std::async(std::launch::async, [&]() {
    return FsvDracoDecodeOwnedPrimitives(Requests({&request}), budget, state, nullptr,
                                    &concurrent_stopping_control);
  });
  const FsvDracoDecodeResult concurrent_result = success_future.get();
  const FsvDracoDecodeResult stopped_result = stopped_future.get();
  CHECK(concurrent_result.diagnostics.empty());
  CHECK(concurrent_result.decoded_primitives.size() == 1);
  CHECK(stopped_result.diagnostics.empty());
  CHECK(stopped_result.decoded_primitives.empty());
  CHECK(stopped_result.terminal_outcome.kind ==
        FsvDracoTerminalOutcomeKind::kCallerCancelled);
  CHECK(concurrent_heap.allocation_calls() == allocation_ordinals);
  CHECK(concurrent_control.live_bytes() > 0);
  CHECK(concurrent_stopping_control.live_bytes() == 0);
  CHECK(concurrent_stopping_control.allocation_count() ==
        concurrent_stopping_control.release_count());
  CHECK(concurrent_stopping_control.stop_reason() ==
        fsv_draco::FsvDecodeStopReason::kCallerCancelled);
  return 0;
}
