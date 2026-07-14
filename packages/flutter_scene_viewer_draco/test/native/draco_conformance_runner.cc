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
int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

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
  schema.type = std::move(type);
  schema.count = count;
  return schema;
}

bool WriteBytes(const std::string& path, const std::vector<uint8_t>& bytes) {
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

  FsvDracoPrimitiveRequest request;
  request.mesh_index = 0;
  request.primitive_index = 0;
  request.compressed_bytes = compressed;
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
  const FsvDracoDecodeResult bridge_result =
      FsvDracoDecodePrimitives({request}, budget, state);
  CHECK(bridge_result.diagnostics.empty());
  CHECK(bridge_result.decoded_primitives.size() == 1);
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
  return 0;
}
