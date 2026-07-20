#include "fsv_draco_bridge.h"

#include "fsv_draco_codec_adapter.h"

#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string_view>

#include "draco/compression/decode.h"
#include "draco/core/decoder_buffer.h"
#include "draco/mesh/mesh.h"

FsvDracoCodecControlAdapter::FsvDracoCodecControlAdapter(
    fsv_draco::FsvDecodeControl* control) noexcept
    : control_(control),
      overflow_records_(
          FsvDracoAllocator<fsv_draco::FsvDecodeAllocationResult>(control)) {}

FsvDracoCodecControlAdapter::~FsvDracoCodecControlAdapter() {
  for (const fsv_draco::FsvDecodeAllocationResult& record :
       allocation_records_) {
    if (record.outcome == fsv_draco::FsvDecodeAllocationOutcome::kSuccess) {
      std::terminate();
    }
  }
  for (const fsv_draco::FsvDecodeAllocationResult& record : overflow_records_) {
    if (record.outcome == fsv_draco::FsvDecodeAllocationOutcome::kSuccess) {
      std::terminate();
    }
  }
}

bool FsvDracoCodecControlAdapter::ShouldStopDecoding() const {
  return control_ != nullptr && control_->IsCancelled();
}

draco::FsvDecodeControl::AllocationResult
FsvDracoCodecControlAdapter::AllocateMemory(size_t bytes,
                                            size_t alignment) noexcept {
  if (control_ == nullptr) {
    return {nullptr, 0, 0, AllocationOutcome::kHeapFailure};
  }
  fsv_draco::FsvDecodeAllocationResult result =
      control_->AllocateMemory(bytes, alignment);
  AllocationOutcome outcome = AllocationOutcome::kHeapFailure;
  switch (result.outcome) {
    case fsv_draco::FsvDecodeAllocationOutcome::kSuccess:
      outcome = AllocationOutcome::kSuccess;
      break;
    case fsv_draco::FsvDecodeAllocationOutcome::kStopped:
      outcome = AllocationOutcome::kStopped;
      break;
    case fsv_draco::FsvDecodeAllocationOutcome::kBudgetExceeded:
      outcome = AllocationOutcome::kBudgetExceeded;
      break;
    case fsv_draco::FsvDecodeAllocationOutcome::kHeapFailure:
      outcome = AllocationOutcome::kHeapFailure;
      break;
  }
  if (outcome != AllocationOutcome::kSuccess) {
    return {nullptr, result.bytes, result.alignment, outcome};
  }
  for (fsv_draco::FsvDecodeAllocationResult& slot : allocation_records_) {
    if (slot.outcome != fsv_draco::FsvDecodeAllocationOutcome::kSuccess) {
      slot = result;
      return {result.allocation, result.bytes, result.alignment, outcome};
    }
  }
  for (fsv_draco::FsvDecodeAllocationResult& slot : overflow_records_) {
    if (slot.outcome != fsv_draco::FsvDecodeAllocationOutcome::kSuccess) {
      slot = result;
      return {result.allocation, result.bytes, result.alignment, outcome};
    }
  }
  try {
    overflow_records_.push_back(result);
    return {result.allocation, result.bytes, result.alignment, outcome};
  } catch (const fsv_draco::FsvDecodeStopped&) {
    outcome = AllocationOutcome::kStopped;
  } catch (const fsv_draco::FsvDecodeBudgetExceeded&) {
    outcome = AllocationOutcome::kBudgetExceeded;
  } catch (const std::bad_alloc&) {
    outcome = AllocationOutcome::kHeapFailure;
  }
  if (!control_->ReleaseMemory(&result, result.allocation, result.bytes,
                               result.alignment)) {
    std::terminate();
  }
  return {nullptr, 0, 0, outcome};
}

bool FsvDracoCodecControlAdapter::ReleaseMemory(
    AllocationResult* allocation_record,
    void* allocation,
    size_t bytes,
    size_t alignment) noexcept {
  if (control_ == nullptr || allocation_record == nullptr ||
      allocation_record->outcome != AllocationOutcome::kSuccess) {
    if (control_ != nullptr) {
      control_->RecordReleaseMismatch();
    }
    return false;
  }
  for (fsv_draco::FsvDecodeAllocationResult& slot : allocation_records_) {
    if (slot.outcome != fsv_draco::FsvDecodeAllocationOutcome::kSuccess ||
        slot.allocation != allocation_record->allocation) {
      continue;
    }
    if (allocation_record->allocation != allocation ||
        allocation_record->bytes != bytes ||
        allocation_record->alignment != alignment || slot.bytes != bytes ||
        slot.alignment != alignment) {
      control_->RecordReleaseMismatch();
      return false;
    }
    if (!control_->ReleaseMemory(&slot, slot.allocation, slot.bytes,
                                 slot.alignment)) {
      return false;
    }
    *allocation_record = AllocationResult();
    return true;
  }
  for (fsv_draco::FsvDecodeAllocationResult& slot : overflow_records_) {
    if (slot.outcome != fsv_draco::FsvDecodeAllocationOutcome::kSuccess ||
        slot.allocation != allocation_record->allocation) {
      continue;
    }
    if (allocation_record->allocation != allocation ||
        allocation_record->bytes != bytes ||
        allocation_record->alignment != alignment || slot.bytes != bytes ||
        slot.alignment != alignment) {
      control_->RecordReleaseMismatch();
      return false;
    }
    if (!control_->ReleaseMemory(&slot, slot.allocation, slot.bytes,
                                 slot.alignment)) {
      return false;
    }
    *allocation_record = AllocationResult();
    return true;
  }
  control_->RecordReleaseMismatch();
  return false;
}

namespace {

void Assign(FsvDracoString* destination, std::string_view source) {
  destination->assign(source.data(), source.size());
}

int ComponentCount(std::string_view type) {
  if (type == "SCALAR") {
    return 1;
  }
  if (type == "VEC2") {
    return 2;
  }
  if (type == "VEC3") {
    return 3;
  }
  if (type == "VEC4") {
    return 4;
  }
  return 0;
}

FsvDracoDiagnostic Diagnostic(const FsvDracoPrimitiveRequest& request,
                              std::string_view status,
                              std::string_view message,
                              std::string_view attribute = {},
                              std::string_view stage = {},
                              std::string_view field = {},
                              fsv_draco::FsvDecodeControl* control = nullptr) {
  FsvDracoDiagnostic diagnostic(control);
  Assign(&diagnostic.status, status);
  Assign(&diagnostic.message, message);
  diagnostic.mesh_index = request.mesh_index;
  diagnostic.primitive_index = request.primitive_index;
  Assign(&diagnostic.attribute, attribute);
  Assign(&diagnostic.stage, stage);
  Assign(&diagnostic.field, field);
  return diagnostic;
}

void SetTerminalOutcome(FsvDracoDecodeResult* result,
                        fsv_draco::FsvDecodeControl* control,
                        const FsvDracoPrimitiveRequests& requests) noexcept {
  int mesh_index = -1;
  int primitive_index = -1;
  if (!requests.empty()) {
    mesh_index = requests.front().mesh_index;
    primitive_index = requests.front().primitive_index;
  }
  FsvDracoRecordTerminalOutcome(result, control, mesh_index, primitive_index);
}

template <typename T>
bool AppendAttributeBytes(const draco::PointAttribute& attribute,
                          int64_t count,
                          int components,
                          FsvDracoByteVector* out,
                          FsvDracoDecodeTestingCounters* testing_counters,
                          fsv_draco::FsvDecodeControl* control) {
  if (count < 0 || components <= 0 || components > 16 || out == nullptr) {
    return false;
  }
  if (count > std::numeric_limits<int>::max() ||
      static_cast<uint64_t>(count) >
          std::numeric_limits<size_t>::max() /
              static_cast<uint64_t>(components * sizeof(T))) {
    return false;
  }
  if (testing_counters != nullptr) {
    testing_counters->output_vector_allocations += 1;
  }
  out->assign(static_cast<size_t>(count) *
                  static_cast<size_t>(components * sizeof(T)),
              0);
  T values[16] = {};
  for (int64_t point = 0; point < count; point += 1) {
    if ((point & 255) == 0 && control != nullptr && control->IsCancelled()) {
      return false;
    }
    const draco::PointIndex point_index(point);
    if (!attribute.ConvertValue<T>(
            attribute.mapped_index(point_index),
            static_cast<int8_t>(components),
            values)) {
      return false;
    }
    std::memcpy(
        out->data() + static_cast<size_t>(point) *
                          static_cast<size_t>(components * sizeof(T)),
        values,
        static_cast<size_t>(components * sizeof(T)));
  }
  return true;
}

bool DecodeAttributeBytes(const draco::PointAttribute& attribute,
                          const FsvDracoAccessorSchema& schema,
                          FsvDracoByteVector* out,
                          FsvDracoDecodeTestingCounters* testing_counters,
                          fsv_draco::FsvDecodeControl* control) {
  const int components = ComponentCount(schema.type);
  switch (schema.component_type.value) {
    case 5120:
      return AppendAttributeBytes<int8_t>(
          attribute, schema.count, components, out, testing_counters, control);
    case 5121:
      return AppendAttributeBytes<uint8_t>(
          attribute, schema.count, components, out, testing_counters, control);
    case 5122:
      return AppendAttributeBytes<int16_t>(
          attribute, schema.count, components, out, testing_counters, control);
    case 5123:
      return AppendAttributeBytes<uint16_t>(
          attribute, schema.count, components, out, testing_counters, control);
    case 5125:
      return AppendAttributeBytes<uint32_t>(
          attribute, schema.count, components, out, testing_counters, control);
    case 5126:
      return AppendAttributeBytes<float>(
          attribute, schema.count, components, out, testing_counters, control);
    default:
      return false;
  }
}

template <typename T>
bool AppendIndexValue(uint32_t value, FsvDracoByteVector* out) {
  if (value > static_cast<uint32_t>(std::numeric_limits<T>::max())) {
    return false;
  }
  const T typed_value = static_cast<T>(value);
  const auto* bytes = reinterpret_cast<const uint8_t*>(&typed_value);
  out->insert(out->end(), bytes, bytes + sizeof(T));
  return true;
}

bool DecodeIndexBytes(const draco::Mesh& mesh,
                      const FsvDracoAccessorSchema& schema,
                      FsvDracoByteVector* out,
                      FsvDracoDecodeTestingCounters* testing_counters,
                      fsv_draco::FsvDecodeControl* control) {
  const int64_t decoded_index_count =
      static_cast<int64_t>(mesh.num_faces()) * 3;
  if (schema.count != decoded_index_count || out == nullptr ||
      schema.count > std::numeric_limits<int>::max()) {
    return false;
  }
  out->clear();
  const size_t component_bytes = schema.component_type.value == 5121
                                     ? 1
                                     : schema.component_type.value == 5123 ? 2
                                                                           : 4;
  if (testing_counters != nullptr) {
    testing_counters->output_vector_allocations += 1;
  }
  out->reserve(static_cast<size_t>(schema.count) * component_bytes);
  for (draco::FaceIndex face_index(0); face_index < mesh.num_faces();
       ++face_index) {
    if ((face_index.value() & 255) == 0 && control != nullptr &&
        control->IsCancelled()) {
      return false;
    }
    const draco::Mesh::Face& face = mesh.face(face_index);
    for (int corner = 0; corner < 3; corner += 1) {
      const uint32_t value = static_cast<uint32_t>(face[corner].value());
      switch (schema.component_type.value) {
        case 5121:
          if (!AppendIndexValue<uint8_t>(value, out)) {
            return false;
          }
          break;
        case 5123:
          if (!AppendIndexValue<uint16_t>(value, out)) {
            return false;
          }
          break;
        case 5125:
          if (!AppendIndexValue<uint32_t>(value, out)) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
  }
  return true;
}
}  // namespace

void FsvDracoRecordTerminalOutcome(
    FsvDracoDecodeResult* result,
    fsv_draco::FsvDecodeControl* control,
    int mesh_index,
    int primitive_index) noexcept {
  if (result == nullptr) {
    return;
  }
  result->terminal_outcome.mesh_index = mesh_index;
  result->terminal_outcome.primitive_index = primitive_index;
  if (control == nullptr) {
    result->terminal_outcome.kind =
        FsvDracoTerminalOutcomeKind::kAllocationFailed;
    return;
  }
  switch (control->stop_reason()) {
    case fsv_draco::FsvDecodeStopReason::kCallerCancelled:
      result->terminal_outcome.kind =
          FsvDracoTerminalOutcomeKind::kCallerCancelled;
      return;
    case fsv_draco::FsvDecodeStopReason::kDeadline:
      result->terminal_outcome.kind = FsvDracoTerminalOutcomeKind::kDeadline;
      return;
    case fsv_draco::FsvDecodeStopReason::kBudget:
      result->terminal_outcome.kind =
          FsvDracoTerminalOutcomeKind::kBudgetExceeded;
      return;
    case fsv_draco::FsvDecodeStopReason::kAllocationFailure:
    case fsv_draco::FsvDecodeStopReason::kNone:
      result->terminal_outcome.kind =
          FsvDracoTerminalOutcomeKind::kAllocationFailed;
      return;
  }
}

bool FsvDracoDecoderLinked() {
  return true;
}

bool FsvDracoPrimitiveDecodeAvailable() {
  return true;
}

FsvDracoDecodeResult FsvDracoDecodePrimitives(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoDecodeResult result(control);
  try {
  if (control != nullptr && control->IsCancelled()) {
    SetTerminalOutcome(&result, control, requests);
    return result;
  }
  FsvDracoPreflightResult preflight =
      FsvDracoPreflightRequests(requests, budget, state, control);
  if (!preflight.ok) {
    result.diagnostics = std::move(preflight.diagnostics);
    return result;
  }

  if (testing_counters != nullptr && control != nullptr) {
    if (testing_counters->stop_before_codec_dispatch ==
        FsvDracoDecodeTestingBoundaryStop::kCallerCancelled) {
      control->Cancel();
    } else if (testing_counters->stop_before_codec_dispatch ==
               FsvDracoDecodeTestingBoundaryStop::kDeadline) {
      control->Deadline();
    }
  }
  if (control != nullptr && control->IsCancelled()) {
    SetTerminalOutcome(&result, control, requests);
    return result;
  }
  FsvDracoCodecControlAdapter codec_control(control);

  FsvDracoVector<std::unique_ptr<draco::Mesh>> decoded_meshes{
      FsvDracoAllocator<std::unique_ptr<draco::Mesh>>(control)};
  decoded_meshes.reserve(requests.size());
  for (const FsvDracoPrimitiveRequest& request : requests) {
    if (control != nullptr && control->IsCancelled()) {
      FsvDracoDecodeResult stopped(control);
      SetTerminalOutcome(&stopped, control, requests);
      return stopped;
    }
    if (request.compressed_bytes.empty()) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Draco primitive has no compressed bytes.",
          {}, {}, {}, control));
      break;
    }

    draco::DecoderBuffer buffer;
    buffer.Init(reinterpret_cast<const char*>(request.compressed_bytes.data()),
                request.compressed_bytes.size());
    auto geometry_type = draco::Decoder::GetEncodedGeometryType(&buffer);
    if (!geometry_type.ok() || geometry_type.value() != draco::TRIANGULAR_MESH) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Draco payload is not a triangular mesh.",
          {}, {}, {}, control));
      break;
    }

    draco::Decoder decoder;
    const uint64_t codec_allocation_start =
        control == nullptr ? 0 : control->allocation_count();
    auto decoded_mesh = decoder.DecodeMeshFromBuffer(
        &buffer, control == nullptr ? nullptr : &codec_control);
    if (testing_counters != nullptr && control != nullptr) {
      testing_counters->codec_allocation_attempts +=
          control->allocation_count() - codec_allocation_start;
    }
    if (control != nullptr && control->IsCancelled()) {
      FsvDracoDecodeResult stopped(control);
      SetTerminalOutcome(&stopped, control, requests);
      return stopped;
    }
    if (!decoded_mesh.ok()) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Google Draco failed to decode the mesh.",
          {}, {}, {}, control));
      break;
    }
    decoded_meshes.push_back(std::move(decoded_mesh).value());
  }
  if (!result.diagnostics.empty()) {
    return result;
  }

  FsvDracoVector<FsvDracoDecodedMeshMetadata> decoded_metadata{
      FsvDracoAllocator<FsvDracoDecodedMeshMetadata>(control)};
  decoded_metadata.reserve(decoded_meshes.size());
  for (size_t request_index = 0; request_index < requests.size();
       request_index += 1) {
    const FsvDracoPrimitiveRequest& request = requests[request_index];
    const draco::Mesh& mesh = *decoded_meshes[request_index];
    FsvDracoDecodedMeshMetadata metadata(control);
    metadata.point_count = mesh.num_points();
    metadata.face_count = mesh.num_faces();
    for (const auto& attribute : request.attributes) {
      if (attribute.second >= 0 &&
          static_cast<uint64_t>(attribute.second) <=
              std::numeric_limits<uint32_t>::max() &&
          mesh.GetAttributeByUniqueId(
              static_cast<uint32_t>(attribute.second)) != nullptr) {
        metadata.attribute_unique_ids.insert(
            static_cast<uint32_t>(attribute.second));
      }
    }
    decoded_metadata.push_back(std::move(metadata));
  }
  FsvDracoPostDecodeValidationResult post_decode =
      FsvDracoValidateDecodedSchemas(requests, decoded_metadata, control);
  if (!post_decode.ok) {
    result.diagnostics = std::move(post_decode.diagnostics);
    return result;
  }

  for (size_t request_index = 0; request_index < requests.size();
       request_index += 1) {
    const FsvDracoPrimitiveRequest& request = requests[request_index];
    const draco::Mesh& mesh = *decoded_meshes[request_index];

    FsvDracoDecodedPrimitive decoded(control);
    decoded.mesh_index = request.mesh_index;
    decoded.primitive_index = request.primitive_index;
    for (const auto& attribute_entry : request.attributes) {
      const FsvDracoString& attribute_name = attribute_entry.first;
      const int64_t unique_id = attribute_entry.second;
      const draco::PointAttribute* attribute =
          mesh.GetAttributeByUniqueId(static_cast<uint32_t>(unique_id));
      const auto schema_it = request.attribute_accessors.find(attribute_name);
      if (attribute == nullptr || schema_it == request.attribute_accessors.end()) {
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco did not return a requested attribute.",
            attribute_name, {}, {}, control));
        break;
      }
      FsvDracoByteVector attribute_bytes{
          FsvDracoAllocator<uint8_t>(control)};
      if (!DecodeAttributeBytes(*attribute, schema_it->second, &attribute_bytes,
                                testing_counters, control)) {
        if (control != nullptr && control->IsCancelled()) {
          FsvDracoDecodeResult stopped(control);
          SetTerminalOutcome(&stopped, control, requests);
          return stopped;
        }
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco attribute could not be converted to accessor bytes.",
            attribute_name, {}, {}, control));
        break;
      }
      decoded.attributes.emplace(
          FsvDracoString(attribute_name.data(), attribute_name.size(),
                         FsvDracoAllocator<char>(control)),
          std::move(attribute_bytes));
    }
    if (!result.diagnostics.empty()) {
      break;
    }

    if (request.has_indices_accessor) {
      decoded.has_indices = true;
      if (!DecodeIndexBytes(mesh, request.indices_accessor, &decoded.indices,
                            testing_counters, control)) {
        if (control != nullptr && control->IsCancelled()) {
          FsvDracoDecodeResult stopped(control);
          SetTerminalOutcome(&stopped, control, requests);
          return stopped;
        }
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco indices could not be converted to accessor bytes.",
            {}, {}, {}, control));
        break;
      }
    }
    result.decoded_primitives.push_back(std::move(decoded));
  }
  if (!result.diagnostics.empty()) {
    result.decoded_primitives.clear();
  }
  return result;
  } catch (const draco::FsvDecodeStopped&) {
    result.decoded_primitives.clear();
    result.diagnostics.clear();
    SetTerminalOutcome(&result, control, requests);
    return result;
  } catch (const draco::FsvDecodeBudgetExceeded&) {
    result.decoded_primitives.clear();
    result.diagnostics.clear();
    SetTerminalOutcome(&result, control, requests);
    return result;
  } catch (const fsv_draco::FsvDecodeStopped&) {
    result.decoded_primitives.clear();
    result.diagnostics.clear();
    SetTerminalOutcome(&result, control, requests);
    return result;
  } catch (const fsv_draco::FsvDecodeBudgetExceeded&) {
    result.decoded_primitives.clear();
    result.diagnostics.clear();
    SetTerminalOutcome(&result, control, requests);
    return result;
  } catch (const std::bad_alloc&) {
    result.decoded_primitives.clear();
    result.diagnostics.clear();
    SetTerminalOutcome(&result, control, requests);
    return result;
  }
}

FsvDracoDecodeResult FsvDracoDecodeOwnedPrimitives(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoDecodeResult terminal(control);
  try {
    FsvDracoPrimitiveRequests owned_requests{
        FsvDracoAllocator<FsvDracoPrimitiveRequest>(control)};
    owned_requests.reserve(requests.size());
    for (const FsvDracoPrimitiveRequest& request : requests) {
      owned_requests.emplace_back(request, control);
    }
    return FsvDracoDecodePrimitives(owned_requests, budget, state,
                                    testing_counters, control);
  } catch (const fsv_draco::FsvDecodeStopped&) {
    SetTerminalOutcome(&terminal, control, requests);
  } catch (const fsv_draco::FsvDecodeBudgetExceeded&) {
    SetTerminalOutcome(&terminal, control, requests);
  } catch (const std::bad_alloc&) {
    SetTerminalOutcome(&terminal, control, requests);
  }
  return terminal;
}
