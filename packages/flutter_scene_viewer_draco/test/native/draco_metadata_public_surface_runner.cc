#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include "draco/core/status.h"
#include "draco/metadata/geometry_metadata.h"
#include "draco/metadata/metadata.h"

using EntryData = const std::vector<uint8_t> &;
using EntryMap = const std::map<std::string, draco::EntryValue> &;
using SubMetadataMap =
    const std::map<std::string, std::unique_ptr<draco::Metadata>> &;
using AttributeMetadataVector =
    const std::vector<std::unique_ptr<draco::AttributeMetadata>> &;

static_assert(std::is_same<
              decltype(std::declval<const draco::EntryValue &>().data()),
              EntryData>::value,
              "EntryValue::data must preserve the upstream public type");
static_assert(std::is_same<
              decltype(std::declval<const draco::Metadata &>().entries()),
              EntryMap>::value,
              "Metadata::entries must preserve the upstream public type");
static_assert(
    std::is_same<decltype(std::declval<const draco::Metadata &>()
                              .sub_metadatas()),
                 SubMetadataMap>::value,
    "Metadata::sub_metadatas must preserve the upstream public type");
static_assert(
    std::is_same<decltype(std::declval<const draco::GeometryMetadata &>()
                              .attribute_metadatas()),
                 AttributeMetadataVector>::value,
    "GeometryMetadata::attribute_metadatas must preserve the upstream type");
static_assert(
    std::is_same<decltype(std::declval<const draco::Status &>()
                              .error_msg_string()),
                 const std::string &>::value,
    "Status::error_msg_string must preserve the upstream public type");
static_assert(!std::is_polymorphic<draco::Metadata>::value,
              "Metadata must not gain a needless vptr");
static_assert(!std::has_virtual_destructor<draco::Metadata>::value,
              "Metadata must preserve its non-virtual destructor");

int main() {
  draco::Metadata metadata;
  metadata.AddEntryString("name", "value");
  if (metadata.entries().at("name").data() !=
      std::vector<uint8_t>({'v', 'a', 'l', 'u', 'e'})) {
    return 1;
  }

  draco::GeometryMetadata geometry;
  std::unique_ptr<draco::AttributeMetadata> attribute(
      new draco::AttributeMetadata());
  const draco::AttributeMetadata *const original_attribute = attribute.get();
  if (!geometry.AddAttributeMetadata(std::move(attribute)) ||
      geometry.attribute_metadatas().front().get() != original_attribute) {
    return 2;
  }

  const draco::Status status(draco::Status::DRACO_ERROR, "public error");
  if (status.error_msg_string() != "public error") {
    return 3;
  }
  std::cout << "metadata_internal_layout_bytes=" << sizeof(draco::Status)
            << "/" << sizeof(draco::EntryValue) << "/"
            << sizeof(draco::Metadata) << "/"
            << sizeof(draco::GeometryMetadata) << "\n";
  return 0;
}
