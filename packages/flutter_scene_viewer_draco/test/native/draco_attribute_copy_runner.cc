#include <cstddef>
#include <cstdint>
#include <exception>
#include <iostream>
#include <memory>
#include <new>
#include <utility>

#include "draco/attributes/attribute_transform_data.h"
#include "draco/attributes/point_attribute.h"
#include "draco/core/data_buffer.h"
#include "draco/core/fsv_decode_allocator.h"

namespace {

int Fail(int line) {
  std::cerr << "failure at line " << line << "\n";
  return line;
}

class TrackingControl final : public draco::FsvDecodeControl {
 public:
  bool ShouldStopDecoding() const override { return false; }

  AllocationResult AllocateMemory(size_t bytes,
                                  size_t alignment) noexcept override {
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

  uint64_t allocation_count() const { return allocation_count_; }
  uint64_t release_count() const { return release_count_; }
  size_t live_bytes() const { return live_bytes_; }

 private:
  uint64_t allocation_count_ = 0;
  uint64_t release_count_ = 0;
  size_t live_bytes_ = 0;
};

class SizedObject final : public draco::FsvDecodeAllocated {};

class VirtualObject : public draco::FsvDecodeAllocated {
 public:
  virtual ~VirtualObject() = default;
};

class alignas(64) OverAlignedObject final : public VirtualObject {
 public:
  uint64_t payload[8] = {};
};

class ThrowingObject final : public draco::FsvDecodeAllocated {
 public:
  ThrowingObject() { throw 7; }
};

}  // namespace

#define CHECK(value)         \
  do {                       \
    if (!(value)) {          \
      return Fail(__LINE__); \
    }                        \
  } while (false)

int main() {
  TrackingControl destination_control;
  std::unique_ptr<draco::PointAttribute> destination(
      new (&destination_control) draco::PointAttribute(&destination_control));

  {
    TrackingControl source_control;
    {
      draco::GeometryAttribute descriptor;
      descriptor.Init(draco::GeometryAttribute::GENERIC, nullptr, 1,
                      draco::DT_FLOAT32, false, sizeof(float), 0);
      std::unique_ptr<draco::PointAttribute> source(
          new (&source_control)
              draco::PointAttribute(descriptor, &source_control));
      source->SetIdentityMapping();
      CHECK(source->Reset(1));
      const float source_value = 42.5f;
      source->SetAttributeValue(draco::AttributeValueIndex(0), &source_value);

      std::unique_ptr<draco::AttributeTransformData> transform(
          new (&source_control)
              draco::AttributeTransformData(&source_control));
      transform->set_transform_type(draco::ATTRIBUTE_QUANTIZATION_TRANSFORM);
      const float minimum = -3.25f;
      const int32_t quantization_bits = 12;
      transform->AppendParameterValue(minimum);
      transform->AppendParameterValue(quantization_bits);
      source->SetAttributeTransformData(std::move(transform));

      destination->CopyFrom(*source);
      std::cout << "source_allocations=" << source_control.allocation_count()
                << "\n";
      CHECK(source_control.allocation_count() == 6);
      CHECK(source_control.live_bytes() > 0);
    }
    CHECK(source_control.release_count() == 6);
    CHECK(source_control.live_bytes() == 0);
  }

  std::cout << "destination_allocations="
            << destination_control.allocation_count() << "\n";
  CHECK(destination_control.allocation_count() == 5);
  float copied_value = 0.f;
  destination->GetValue(draco::AttributeValueIndex(0), &copied_value);
  CHECK(copied_value == 42.5f);
  const draco::AttributeTransformData *copied_transform =
      destination->GetAttributeTransformData();
  CHECK(copied_transform != nullptr);
  CHECK(copied_transform->transform_type() ==
        draco::ATTRIBUTE_QUANTIZATION_TRANSFORM);
  CHECK(copied_transform->GetParameterValue<float>(0) == -3.25f);
  CHECK(copied_transform->GetParameterValue<int32_t>(sizeof(float)) == 12);
  destination.reset();
  CHECK(destination_control.release_count() == 5);
  CHECK(destination_control.live_bytes() == 0);

  {
    TrackingControl control;
    void *memory = draco::FsvDecodeAllocated::operator new(
        sizeof(SizedObject), &control);
    auto *object = ::new (memory) SizedObject();
    object->~SizedObject();
    draco::FsvDecodeAllocated::operator delete(memory, sizeof(SizedObject));
    CHECK(control.allocation_count() == 1);
    CHECK(control.release_count() == 1);
    CHECK(control.live_bytes() == 0);
  }

  {
    TrackingControl control;
    VirtualObject *object = new (&control) OverAlignedObject();
    CHECK(reinterpret_cast<uintptr_t>(object) % alignof(OverAlignedObject) == 0);
    delete object;
    CHECK(control.allocation_count() == 1);
    CHECK(control.release_count() == 1);
    CHECK(control.live_bytes() == 0);
  }

  {
    TrackingControl control;
    try {
      static_cast<void>(new (&control) ThrowingObject());
      return Fail(__LINE__);
    } catch (int value) {
      CHECK(value == 7);
    } catch (...) {
      return Fail(__LINE__);
    }
    CHECK(control.allocation_count() == 1);
    CHECK(control.release_count() == 1);
    CHECK(control.live_bytes() == 0);
  }

  {
    TrackingControl source_control;
    TrackingControl moved_control;
    std::unique_ptr<draco::DataBuffer> source(
        new (&source_control) draco::DataBuffer(&source_control));
    const uint32_t value = UINT32_C(0x1234abcd);
    CHECK(source->Update(&value, sizeof(value)));
    std::unique_ptr<draco::DataBuffer> moved(
        new (&moved_control)
            draco::DataBuffer(std::move(*source), &moved_control));
    source.reset();
    CHECK(source_control.allocation_count() == 2);
    CHECK(source_control.release_count() == 2);
    CHECK(source_control.live_bytes() == 0);
    uint32_t moved_value = 0;
    moved->Read(0, &moved_value, sizeof(moved_value));
    CHECK(moved_value == value);
    moved.reset();
    CHECK(moved_control.allocation_count() == 2);
    CHECK(moved_control.release_count() == 2);
    CHECK(moved_control.live_bytes() == 0);
  }

  std::cout << "header_edge_cases=4\n";
  return 0;
}
