// Copyright 2017 The Draco Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
#include "draco/metadata/geometry_metadata.h"

#include <utility>

namespace draco {

AttributeMetadata::AttributeMetadata(const AttributeMetadata &metadata)
    : AttributeMetadata(metadata, nullptr) {}

AttributeMetadata::AttributeMetadata(const AttributeMetadata &metadata,
                                     FsvDecodeControl *control)
    : Metadata(metadata, control), att_unique_id_(metadata.att_unique_id_) {}

AttributeMetadata::AttributeMetadata(AttributeMetadata &&metadata)
    : AttributeMetadata(static_cast<const AttributeMetadata &>(metadata),
                        nullptr) {}

AttributeMetadata::AttributeMetadata(AttributeMetadata &&metadata,
                                     FsvDecodeControl *control)
    : AttributeMetadata(static_cast<const AttributeMetadata &>(metadata),
                        control) {}

GeometryMetadata::GeometryMetadata(const GeometryMetadata &metadata)
    : GeometryMetadata(metadata, nullptr) {}

GeometryMetadata::GeometryMetadata(const GeometryMetadata &metadata,
                                   FsvDecodeControl *control)
    : Metadata(metadata, control),
      controlled_att_metadatas_(
          FsvDecodeAllocator<std::unique_ptr<AttributeMetadata>>(control)) {
  if (metadata.fsv_decode_control() == nullptr) {
    for (const auto &attribute : metadata.att_metadatas_) {
      AddAttributeMetadata(std::unique_ptr<AttributeMetadata>(
          new (control) AttributeMetadata(*attribute, control)));
    }
  } else {
    for (const auto &attribute : metadata.controlled_att_metadatas_) {
      AddAttributeMetadata(std::unique_ptr<AttributeMetadata>(
          new (control) AttributeMetadata(*attribute, control)));
    }
  }
}

GeometryMetadata::GeometryMetadata(GeometryMetadata &&metadata)
    : GeometryMetadata(static_cast<const GeometryMetadata &>(metadata),
                       nullptr) {}

GeometryMetadata::GeometryMetadata(GeometryMetadata &&metadata,
                                   FsvDecodeControl *control)
    : GeometryMetadata(static_cast<const GeometryMetadata &>(metadata),
                       control) {}

const AttributeMetadata *GeometryMetadata::GetAttributeMetadataByStringEntry(
    const std::string &entry_name, const std::string &entry_value) const {
  if (fsv_decode_control() == nullptr) {
    for (auto &&att_metadata : att_metadatas_) {
      std::string value;
      if (att_metadata->GetEntryString(entry_name, &value) &&
          value == entry_value) {
        return att_metadata.get();
      }
    }
  } else {
    for (auto &&att_metadata : controlled_att_metadatas_) {
      std::string value;
      if (att_metadata->GetEntryString(entry_name, &value) &&
          value == entry_value) {
        return att_metadata.get();
      }
    }
  }
  // No attribute has the requested entry.
  return nullptr;
}

bool GeometryMetadata::AddAttributeMetadata(
    std::unique_ptr<AttributeMetadata> att_metadata) {
  if (!att_metadata) {
    return false;
  }
  if (fsv_decode_control() == nullptr) {
    if (att_metadata->fsv_decode_control() != nullptr) {
      att_metadata.reset(new AttributeMetadata(*att_metadata));
    }
    att_metadatas_.push_back(std::move(att_metadata));
    return true;
  }
  if (att_metadata->fsv_decode_control() != fsv_decode_control()) {
    att_metadata.reset(new (fsv_decode_control()) AttributeMetadata(
        *att_metadata, fsv_decode_control()));
  }
  controlled_att_metadatas_.push_back(std::move(att_metadata));
  return true;
}

const std::vector<std::unique_ptr<AttributeMetadata>> &
GeometryMetadata::attribute_metadatas() const {
  if (fsv_decode_control() == nullptr) {
    return att_metadatas_;
  }
  public_att_metadatas_cache_.clear();
  for (const auto &attribute : controlled_att_metadatas_) {
    public_att_metadatas_cache_.push_back(
        std::unique_ptr<AttributeMetadata>(new AttributeMetadata(*attribute)));
  }
  return public_att_metadatas_cache_;
}
}  // namespace draco
