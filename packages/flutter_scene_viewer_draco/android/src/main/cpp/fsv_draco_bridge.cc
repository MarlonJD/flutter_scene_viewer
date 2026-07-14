#include "fsv_draco_bridge.h"

#include <cstring>
#include <limits>
#include <memory>

#include "draco/compression/decode.h"
#include "draco/core/decoder_buffer.h"
#include "draco/mesh/mesh.h"

namespace {
int ComponentCount(const std::string& type) {
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
                              std::string status,
                              std::string message,
                              std::string attribute = std::string(),
                              std::string stage = std::string(),
                              std::string field = std::string()) {
  FsvDracoDiagnostic diagnostic;
  diagnostic.status = std::move(status);
  diagnostic.message = std::move(message);
  diagnostic.mesh_index = request.mesh_index;
  diagnostic.primitive_index = request.primitive_index;
  diagnostic.attribute = std::move(attribute);
  diagnostic.stage = std::move(stage);
  diagnostic.field = std::move(field);
  return diagnostic;
}

template <typename T>
bool AppendAttributeBytes(const draco::PointAttribute& attribute,
                          int64_t count,
                          int components,
                          std::vector<uint8_t>* out,
                          FsvDracoDecodeTestingCounters* testing_counters) {
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
                          std::vector<uint8_t>* out,
                          FsvDracoDecodeTestingCounters* testing_counters) {
  const int components = ComponentCount(schema.type);
  switch (schema.component_type.value) {
    case 5120:
      return AppendAttributeBytes<int8_t>(
          attribute, schema.count, components, out, testing_counters);
    case 5121:
      return AppendAttributeBytes<uint8_t>(
          attribute, schema.count, components, out, testing_counters);
    case 5122:
      return AppendAttributeBytes<int16_t>(
          attribute, schema.count, components, out, testing_counters);
    case 5123:
      return AppendAttributeBytes<uint16_t>(
          attribute, schema.count, components, out, testing_counters);
    case 5125:
      return AppendAttributeBytes<uint32_t>(
          attribute, schema.count, components, out, testing_counters);
    case 5126:
      return AppendAttributeBytes<float>(
          attribute, schema.count, components, out, testing_counters);
    default:
      return false;
  }
}

template <typename T>
bool AppendIndexValue(uint32_t value, std::vector<uint8_t>* out) {
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
                      std::vector<uint8_t>* out,
                      FsvDracoDecodeTestingCounters* testing_counters) {
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

bool FsvDracoDecoderLinked() {
  return true;
}

bool FsvDracoPrimitiveDecodeAvailable() {
  return true;
}

FsvDracoDecodeResult FsvDracoDecodePrimitives(
    const std::vector<FsvDracoPrimitiveRequest>& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters) {
  FsvDracoDecodeResult result;
  FsvDracoPreflightResult preflight =
      FsvDracoPreflightRequests(requests, budget, state);
  if (!preflight.ok) {
    result.diagnostics = std::move(preflight.diagnostics);
    return result;
  }

  std::vector<std::unique_ptr<draco::Mesh>> decoded_meshes;
  decoded_meshes.reserve(requests.size());
  for (const FsvDracoPrimitiveRequest& request : requests) {
    if (request.compressed_bytes.empty()) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Draco primitive has no compressed bytes."));
      break;
    }

    draco::DecoderBuffer buffer;
    buffer.Init(reinterpret_cast<const char*>(request.compressed_bytes.data()),
                request.compressed_bytes.size());
    auto geometry_type = draco::Decoder::GetEncodedGeometryType(&buffer);
    if (!geometry_type.ok() || geometry_type.value() != draco::TRIANGULAR_MESH) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Draco payload is not a triangular mesh."));
      break;
    }

    draco::Decoder decoder;
    auto decoded_mesh = decoder.DecodeMeshFromBuffer(&buffer);
    if (!decoded_mesh.ok()) {
      result.diagnostics.push_back(Diagnostic(
          request, "decodeFailed", "Google Draco failed to decode the mesh."));
      break;
    }
    decoded_meshes.push_back(std::move(decoded_mesh).value());
  }
  if (!result.diagnostics.empty()) {
    return result;
  }

  std::vector<FsvDracoDecodedMeshMetadata> decoded_metadata;
  decoded_metadata.reserve(decoded_meshes.size());
  for (size_t request_index = 0; request_index < requests.size();
       request_index += 1) {
    const FsvDracoPrimitiveRequest& request = requests[request_index];
    const draco::Mesh& mesh = *decoded_meshes[request_index];
    FsvDracoDecodedMeshMetadata metadata;
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
      FsvDracoValidateDecodedSchemas(requests, decoded_metadata);
  if (!post_decode.ok) {
    result.diagnostics = std::move(post_decode.diagnostics);
    return result;
  }

  for (size_t request_index = 0; request_index < requests.size();
       request_index += 1) {
    const FsvDracoPrimitiveRequest& request = requests[request_index];
    const draco::Mesh& mesh = *decoded_meshes[request_index];

    FsvDracoDecodedPrimitive decoded;
    decoded.mesh_index = request.mesh_index;
    decoded.primitive_index = request.primitive_index;
    for (const auto& attribute_entry : request.attributes) {
      const std::string& attribute_name = attribute_entry.first;
      const int64_t unique_id = attribute_entry.second;
      const draco::PointAttribute* attribute =
          mesh.GetAttributeByUniqueId(static_cast<uint32_t>(unique_id));
      const auto schema_it = request.attribute_accessors.find(attribute_name);
      if (attribute == nullptr || schema_it == request.attribute_accessors.end()) {
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco did not return a requested attribute.",
            attribute_name));
        break;
      }
      std::vector<uint8_t> attribute_bytes;
      if (!DecodeAttributeBytes(*attribute, schema_it->second, &attribute_bytes,
                                testing_counters)) {
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco attribute could not be converted to accessor bytes.",
            attribute_name));
        break;
      }
      decoded.attributes[attribute_name] = std::move(attribute_bytes);
    }
    if (!result.diagnostics.empty()) {
      break;
    }

    if (request.has_indices_accessor) {
      decoded.has_indices = true;
      if (!DecodeIndexBytes(mesh, request.indices_accessor, &decoded.indices,
                            testing_counters)) {
        result.diagnostics.push_back(Diagnostic(
            request,
            "decodeFailed",
            "Google Draco indices could not be converted to accessor bytes."));
        break;
      }
    }
    result.decoded_primitives.push_back(std::move(decoded));
  }
  if (!result.diagnostics.empty()) {
    result.decoded_primitives.clear();
  }
  return result;
}
