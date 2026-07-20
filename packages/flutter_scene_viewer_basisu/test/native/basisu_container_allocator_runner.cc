#include <atomic>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <inttypes.h>
#include <limits>
#include <stdexcept>
#include <string>
#include <sys/types.h>
#include <sys/wait.h>
#include <thread>
#include <vector>
#include <type_traits>
#include <unistd.h>

#include "basisu_containers.h"
#define BASISU_NOTE_UNUSED(x) (void)(x)
#include "basisu_containers_impl.h"
#include "fsv_basisu_control.h"

static_assert(!std::is_copy_constructible<basisu::fsv_allocation_result>::value,
              "controlled allocation records must be linear");
static_assert(std::is_move_constructible<basisu::fsv_allocation_result>::value,
              "controlled allocation records must retain move transfer");
static_assert(!std::is_copy_assignable<basisu::fsv_allocation_result>::value,
              "controlled allocation records must not duplicate ownership");
static_assert(!std::is_move_assignable<basisu::fsv_allocation_result>::value,
              "a live controlled allocation record must not be overwritable");

struct alignas(64) OverAlignedValue {
  uint64_t value = 0;
};

struct NonTrivialValue {
  static uint64_t destruction_count;

  explicit NonTrivialValue(uint32_t new_value = 0) noexcept : value(new_value) {}
  NonTrivialValue(const NonTrivialValue& other) noexcept : value(other.value) {}
  NonTrivialValue(NonTrivialValue&& other) noexcept : value(other.value) {
    other.value = 0;
  }
  NonTrivialValue& operator=(const NonTrivialValue& other) noexcept {
    value = other.value;
    return *this;
  }
  NonTrivialValue& operator=(NonTrivialValue&& other) noexcept {
    value = other.value;
    other.value = 0;
    return *this;
  }
  ~NonTrivialValue() {
    value = 0;
    ++destruction_count;
  }

  uint32_t value;
};
uint64_t NonTrivialValue::destruction_count = 0;
static_assert(!std::is_trivially_copyable<NonTrivialValue>::value,
              "nontrivial runner coverage must use the relocation callback");

struct PotentiallyThrowingValue {
  explicit PotentiallyThrowingValue(uint32_t new_value = 0) : value(new_value) {}
  PotentiallyThrowingValue(const PotentiallyThrowingValue& other)
      : value(other.value) {}
  PotentiallyThrowingValue(PotentiallyThrowingValue&& other)
      : value(other.value) {
    other.value = 0;
  }
  PotentiallyThrowingValue& operator=(const PotentiallyThrowingValue&) = default;
  PotentiallyThrowingValue& operator=(PotentiallyThrowingValue&&) = default;
  ~PotentiallyThrowingValue() {}

  uint32_t value;
};
static_assert(!std::is_nothrow_copy_constructible<PotentiallyThrowingValue>::value,
              "the no-exception gate needs a potentially throwing copy");
static_assert(!std::is_nothrow_move_constructible<PotentiallyThrowingValue>::value,
              "the no-exception gate needs a potentially throwing move");

struct MixedTraitValue {
  explicit MixedTraitValue(uint32_t new_value = 0) noexcept : value(new_value) {}
  MixedTraitValue(const MixedTraitValue& other) : value(other.value) {}
  MixedTraitValue(MixedTraitValue&& other) noexcept : value(other.value) {
    other.value = 0;
  }
  MixedTraitValue& operator=(const MixedTraitValue&) = default;
  MixedTraitValue& operator=(MixedTraitValue&&) noexcept = default;
  ~MixedTraitValue() {}

  uint32_t value;
};
static_assert(!std::is_nothrow_copy_constructible<MixedTraitValue>::value,
              "the mixed-trait gate needs a potentially throwing copy");
static_assert(std::is_nothrow_move_constructible<MixedTraitValue>::value,
              "the mixed-trait gate needs a noexcept move");

#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
struct ThrowingCopyValue {
  static uint64_t live_count;
  static uint64_t copy_count;
  static uint64_t throw_on_copy;

  explicit ThrowingCopyValue(uint32_t new_value = 0) noexcept
      : value(new_value) {
    ++live_count;
  }
  ThrowingCopyValue(const ThrowingCopyValue& other) : value(other.value) {
    ++copy_count;
    if (throw_on_copy != 0 && copy_count == throw_on_copy) {
      throw std::runtime_error("injected vector copy failure");
    }
    ++live_count;
  }
  ThrowingCopyValue(ThrowingCopyValue&& other) noexcept : value(other.value) {
    other.value = 0;
    ++live_count;
  }
  ~ThrowingCopyValue() { --live_count; }

  uint32_t value;
};
uint64_t ThrowingCopyValue::live_count = 0;
uint64_t ThrowingCopyValue::copy_count = 0;
uint64_t ThrowingCopyValue::throw_on_copy = 0;
#endif

class TestHeap final : public fsv_basisu::FsvAllocationHeap {
 public:
  explicit TestHeap(uint64_t fail_ordinal = 0) : fail_ordinal_(fail_ordinal) {}

  void* Allocate(size_t bytes, size_t alignment) noexcept override {
    ++allocations_;
    if (unexpected_allocation_exit_ != 0) {
      std::_Exit(unexpected_allocation_exit_);
    }
    if (fail_ordinal_ == allocations_) return nullptr;
    if (alignment <= alignof(std::max_align_t)) return std::malloc(bytes);
    void* pointer = nullptr;
    return posix_memalign(&pointer, alignment, bytes) == 0 ? pointer : nullptr;
  }

  void Release(void* pointer, size_t, size_t) noexcept override { std::free(pointer); }

  uint64_t allocations() const { return allocations_; }
  void ExitOnUnexpectedAllocation(int exit_code) {
    unexpected_allocation_exit_ = exit_code;
  }

 private:
  uint64_t fail_ordinal_;
  uint64_t allocations_ = 0;
  int unexpected_allocation_exit_ = 0;
};

class TrackingAllocator final : public basisu::fsv_vector_allocator {
 public:
  TrackingAllocator(uint64_t working_byte_limit, TestHeap* heap)
      : control_(working_byte_limit, heap) {}

  basisu::fsv_allocation_result fsv_allocate(size_t bytes,
                                              size_t alignment) override {
    return control_.fsv_allocate(bytes, alignment);
  }

  bool fsv_release(basisu::fsv_allocation_result& allocation, void* pointer,
                   size_t bytes, size_t alignment) override {
    return control_.fsv_release(allocation, pointer, bytes, alignment);
  }

  void fsv_retain_owner() noexcept override {
    ++owner_count_;
    ++owner_retain_count_;
    if (unexpected_owner_exit_ != 0) std::_Exit(unexpected_owner_exit_);
  }

  void fsv_release_owner() noexcept override {
    if (owner_count_ == 0) std::_Exit(39);
    --owner_count_;
    ++owner_release_count_;
  }

  void ExitOnUnexpectedOwnerMutation(int exit_code) {
    unexpected_owner_exit_ = exit_code;
  }

  uint64_t owner_count() const { return owner_count_; }
  uint64_t owner_retain_count() const { return owner_retain_count_; }
  uint64_t owner_release_count() const { return owner_release_count_; }
  fsv_basisu::FsvDecodeControl& control() { return control_; }
  const fsv_basisu::FsvDecodeControl& control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl control_;
  uint64_t owner_count_ = 0;
  uint64_t owner_retain_count_ = 0;
  uint64_t owner_release_count_ = 0;
  int unexpected_owner_exit_ = 0;
};

struct TrackingAllocatorSnapshot {
  uint64_t live_bytes;
  uint64_t request_allocations;
  uint64_t request_releases;
  uint64_t owners;
  uint64_t owner_retains;
  uint64_t owner_releases;
  uint64_t heap_allocations;
  fsv_basisu::FsvDecodeStopReason stop_reason;
};

TrackingAllocatorSnapshot CaptureTrackingAllocator(
    const TrackingAllocator& allocator, const TestHeap& heap) {
  return {
      allocator.control().live_bytes(),
      allocator.control().request_allocation_count(),
      allocator.control().request_release_count(),
      allocator.owner_count(),
      allocator.owner_retain_count(),
      allocator.owner_release_count(),
      heap.allocations(),
      allocator.control().stop_reason(),
  };
}

bool MatchesTrackingAllocator(const TrackingAllocator& allocator,
                              const TestHeap& heap,
                              const TrackingAllocatorSnapshot& snapshot) {
  return allocator.control().live_bytes() == snapshot.live_bytes &&
         allocator.control().request_allocation_count() ==
             snapshot.request_allocations &&
         allocator.control().request_release_count() ==
             snapshot.request_releases &&
         allocator.owner_count() == snapshot.owners &&
         allocator.owner_retain_count() == snapshot.owner_retains &&
         allocator.owner_release_count() == snapshot.owner_releases &&
         heap.allocations() == snapshot.heap_allocations &&
         allocator.control().stop_reason() == snapshot.stop_reason;
}

bool ExerciseGrowth(basisu::vector<uint32_t>* values) {
  for (uint32_t value = 0; value < 33; ++value) {
    const size_t old_size = values->size();
    if (!values->try_push_back(value)) {
      if (values->size() != old_size) return false;
      for (size_t index = 0; index < old_size; ++index) {
        if ((*values)[index] != index) return false;
      }
      return true;
    }
  }
  return values->size() == 33;
}

int CheckAllocationRecordTransfer() {
  fsv_basisu::FsvDecodeControl control(4096);
  fsv_basisu::FsvDecodeControl second_control(4096);
  basisu::fsv_allocation_result original = control.fsv_allocate(32, 16);
  void* const pointer = original.m_p;
  const size_t bytes = original.m_bytes;
  const size_t alignment = original.m_alignment;
  if (!pointer || original.m_allocator != &control) return 50;

  basisu::fsv_allocation_result constructed(std::move(original));
  if (original.m_p || original.m_bytes || original.m_alignment ||
      original.m_allocator || constructed.m_p != pointer ||
      constructed.m_bytes != bytes || constructed.m_alignment != alignment ||
      constructed.m_allocator != &control) {
    return 51;
  }

  basisu::fsv_allocation_result second = second_control.fsv_allocate(48, 32);
  void* const second_pointer = second.m_p;
  const size_t second_bytes = second.m_bytes;
  const size_t second_alignment = second.m_alignment;
  if (!second_pointer || second.m_allocator != &second_control) return 52;
  constructed.swap(second);
  if (constructed.m_p != second_pointer || constructed.m_bytes != second_bytes ||
      constructed.m_alignment != second_alignment ||
      constructed.m_allocator != &second_control || second.m_p != pointer ||
      second.m_bytes != bytes || second.m_alignment != alignment ||
      second.m_allocator != &control) {
    return 52;
  }
  if (!control.fsv_release(second, pointer, bytes, alignment) ||
      !second_control.fsv_release(constructed, second_pointer, second_bytes,
                                  second_alignment) ||
      control.live_bytes() != 0 ||
      second_control.live_bytes() != 0 ||
      control.request_allocation_count() != control.request_release_count() ||
      second_control.request_allocation_count() !=
          second_control.request_release_count()) {
    return 53;
  }
  return 0;
}

int CheckDirectRelease() {
  fsv_basisu::FsvDecodeControl control(4096);
  basisu::fsv_allocation_result first = control.fsv_allocate(0, 1);
  basisu::fsv_allocation_result second = control.fsv_allocate(16, 16);
  if (!first.m_p || first.m_bytes != 1 || first.m_alignment < alignof(void*)) return 20;
  if (!second.m_p) return 21;
  if (control.fsv_release(second, first.m_p, second.m_bytes, second.m_alignment)) return 22;
  if (control.fsv_release(second, second.m_p, second.m_bytes + 1, second.m_alignment)) return 23;
  if (control.fsv_release(second, second.m_p, second.m_bytes, second.m_alignment * 2)) return 24;
  if (control.fsv_release(first, first.m_p, first.m_bytes, first.m_alignment)) {
    // This one is exact and intentionally establishes that a separate record
    // cannot make the second pointer's releases succeed.
  } else {
    return 25;
  }
  if (!control.fsv_release(second, second.m_p, second.m_bytes, second.m_alignment)) return 26;
  if (control.fsv_release(second, second.m_p, second.m_bytes, second.m_alignment)) return 27;
  if (control.release_mismatch_count() != 4 || control.live_bytes() != 0) return 28;
  return 0;
}

int CheckCrossControlTransfers() {
  fsv_basisu::FsvDecodeControl first(1 << 20);
  fsv_basisu::FsvDecodeControl second(1 << 20);
  {
    basisu::vector<uint32_t> source(&first);
    if (!source.try_push_back(1) || !source.try_push_back(2)) return 30;
    basisu::vector<uint32_t> copy(&second);
    copy = source;
    if (copy.size() != 2 || copy[1] != 2) return 31;
    const uint64_t copy_construct_before = first.request_allocation_count();
    basisu::vector<uint32_t> copy_constructed(source);
    if (copy_constructed.size() != 2 || copy_constructed[1] != 2 ||
        first.request_allocation_count() <= copy_construct_before) return 66;
    const uint64_t move_construct_before = first.request_allocation_count();
    basisu::vector<uint32_t> move_constructed(std::move(copy_constructed));
    if (move_constructed.size() != 2 || !copy_constructed.empty() ||
        first.request_allocation_count() != move_construct_before) return 67;
    basisu::vector<uint32_t> same_copy(&first);
    same_copy = source;
    if (same_copy.size() != 2 || same_copy[1] != 2) return 68;
    basisu::vector<uint32_t> moved(&second);
    if (!moved.try_move_assign(source)) return 32;
    if (moved.size() != 2 || !source.empty()) return 32;
    basisu::vector<uint32_t> operator_source(&first);
    basisu::vector<uint32_t> operator_moved(&second);
    if (!operator_source.try_push_back(7) ||
        !operator_moved.try_push_back(8)) return 54;
    operator_moved = std::move(operator_source);
    if (operator_moved.size() != 1 || operator_moved[0] != 7 ||
        !operator_source.empty()) return 55;
    basisu::vector<uint32_t> first_values(&first);
    basisu::vector<uint32_t> second_values(&second);
    if (!first_values.try_push_back(3) || !second_values.try_push_back(4)) return 33;
    const uint64_t same_before = first.request_allocation_count();
    basisu::vector<uint32_t> same(&first);
    if (!same.try_move_assign(first_values)) return 45;
    if (first.request_allocation_count() != same_before || same.size() != 1) return 46;
    if (!first_values.try_push_back(3)) return 49;
    if (!first_values.try_swap(second_values)) return 34;
    if (first_values[0] != 4 || second_values[0] != 3) return 34;
    basisu::vector<uint32_t> same_swap_left(&first);
    basisu::vector<uint32_t> same_swap_right(&first);
    if (!same_swap_left.try_push_back(5) ||
        !same_swap_right.try_push_back(6)) return 69;
    const uint64_t same_swap_before = first.request_allocation_count();
    if (!same_swap_left.try_swap(same_swap_right) ||
        same_swap_left[0] != 6 || same_swap_right[0] != 5 ||
        first.request_allocation_count() != same_swap_before) return 70;
    basisu::vector<basisu::vector<uint32_t>> nested(&first);
    basisu::vector<uint32_t> nested_value(&second);
    if (!nested_value.try_push_back(9) || !nested.try_push_back(std::move(nested_value))) return 35;
    const uint64_t nested_allocator_before = second.request_allocation_count();
    if (!nested[0].try_push_back(10) || nested[0][0] != 9 ||
        nested[0][1] != 10 ||
        second.request_allocation_count() <= nested_allocator_before) return 36;
  }
  return (first.live_bytes() == 0 && second.live_bytes() == 0 &&
          first.request_allocation_count() == first.request_release_count() &&
          second.request_allocation_count() == second.request_release_count()) ? 0 : 37;
}

int CheckCrossControlFailureAtomicity() {
  fsv_basisu::FsvDecodeControl source_control(4096);
  TestHeap failing_heap(2);
  fsv_basisu::FsvDecodeControl destination_control(4096, &failing_heap);
  basisu::vector<uint32_t> source(&source_control);
  basisu::vector<uint32_t> destination(&destination_control);
  if (!source.try_push_back(1) || !destination.try_push_back(9)) return 38;
  if (destination.try_move_assign(source)) return 39;
  if (source.size() != 1 || source[0] != 1 || destination.size() != 1 || destination[0] != 9) return 40;
  return 0;
}

int CheckCopyAndShrinkFailureAtomicity() {
  fsv_basisu::FsvDecodeControl source_control(4096);
  basisu::vector<uint32_t> source(&source_control);
  if (!source.try_resize(8)) return 59;
  for (uint32_t index = 0; index < source.size(); ++index) source[index] = index;

  TestHeap copy_heap(2);
  fsv_basisu::FsvDecodeControl copy_control(4096, &copy_heap);
  basisu::vector<uint32_t> destination(&copy_control);
  if (!destination.try_push_back(99)) return 60;
  if (destination.try_copy_assign(source)) return 61;
  if (destination.size() != 1 || destination[0] != 99 ||
      source.size() != 8 || source[7] != 7) return 62;

  TestHeap shrink_heap(2);
  fsv_basisu::FsvDecodeControl shrink_control(4096, &shrink_heap);
  basisu::vector<uint32_t> shrinking(&shrink_control);
  if (!shrinking.try_reserve(8) || !shrinking.try_resize(4)) return 63;
  for (uint32_t index = 0; index < shrinking.size(); ++index) {
    shrinking[index] = index + 10;
  }
  const size_t original_capacity = shrinking.capacity();
  if (shrinking.try_reserve(4)) return 64;
  if (shrinking.capacity() != original_capacity || shrinking.size() != 4 ||
      shrinking[0] != 10 || shrinking[3] != 13 ||
      shrink_heap.allocations() != 2) return 65;
  return 0;
}

int CheckNestedAllocatorIdentityAndAtomicity() {
  fsv_basisu::FsvDecodeControl outer_source_control(1 << 20);
  fsv_basisu::FsvDecodeControl outer_destination_control(1 << 20);
  fsv_basisu::FsvDecodeControl child_control(1 << 20);
  {
    basisu::vector<basisu::vector<uint32_t>> source(&outer_source_control);
    for (uint32_t index = 0; index < 9; ++index) {
      basisu::vector<uint32_t> child(&child_control);
      if (!child.try_push_back(index + 100) ||
          !source.try_push_back(std::move(child))) {
        return 71;
      }
      for (size_t child_index = 0; child_index < source.size(); ++child_index) {
        if (source[child_index].fsv_allocator() != &child_control ||
            source[child_index][0] != child_index + 100) {
          return 72;
        }
      }
    }

    basisu::vector<basisu::vector<uint32_t>> copied(
        &outer_destination_control);
    if (!copied.try_copy_assign(source) || copied.size() != source.size()) {
      return 73;
    }
    for (size_t index = 0; index < copied.size(); ++index) {
      if (copied[index].fsv_allocator() != &child_control ||
          copied[index][0] != index + 100) {
        return 74;
      }
    }

    basisu::vector<basisu::vector<uint32_t>> moved(
        &outer_source_control);
    if (!moved.try_move_assign(copied) || !copied.empty() ||
        moved.size() != source.size()) {
      return 75;
    }
    for (size_t index = 0; index < moved.size(); ++index) {
      if (moved[index].fsv_allocator() != &child_control ||
          moved[index][0] != index + 100) {
        return 76;
      }
    }

    basisu::vector<basisu::vector<uint32_t>> swap_target(
        &outer_destination_control);
    basisu::vector<uint32_t> target_child(&outer_destination_control);
    if (!target_child.try_push_back(999) ||
        !swap_target.try_push_back(std::move(target_child)) ||
        !moved.try_swap(swap_target)) {
      return 77;
    }
    if (moved.size() != 1 || moved[0].fsv_allocator() !=
                                 &outer_destination_control ||
        moved[0][0] != 999 || swap_target.size() != source.size()) {
      return 78;
    }
    for (size_t index = 0; index < swap_target.size(); ++index) {
      if (swap_target[index].fsv_allocator() != &child_control ||
          swap_target[index][0] != index + 100) {
        return 79;
      }
    }
  }
  if (outer_source_control.live_bytes() ||
      outer_destination_control.live_bytes() || child_control.live_bytes()) {
    return 80;
  }

  TestHeap child_heap(2);
  fsv_basisu::FsvDecodeControl failing_child_control(1 << 20, &child_heap);
  fsv_basisu::FsvDecodeControl source_outer_control(1 << 20);
  fsv_basisu::FsvDecodeControl destination_outer_control(1 << 20);
  {
    basisu::vector<basisu::vector<uint32_t>> source(&source_outer_control);
    basisu::vector<uint32_t> child(&failing_child_control);
    if (!child.try_push_back(11) || !source.try_push_back(std::move(child))) {
      return 81;
    }
    basisu::vector<basisu::vector<uint32_t>> destination(
        &destination_outer_control);
    basisu::vector<uint32_t> sentinel(&destination_outer_control);
    if (!sentinel.try_push_back(22) ||
        !destination.try_push_back(std::move(sentinel))) {
      return 82;
    }
    if (destination.try_copy_assign(source)) return 83;
    if (source.size() != 1 || source[0].fsv_allocator() !=
                                  &failing_child_control ||
        source[0][0] != 11 || destination.size() != 1 ||
        destination[0].fsv_allocator() != &destination_outer_control ||
        destination[0][0] != 22) {
      return 84;
    }
  }
  if (failing_child_control.live_bytes() || source_outer_control.live_bytes() ||
      destination_outer_control.live_bytes()) {
    return 85;
  }

  TestHeap shrink_heap(2);
  fsv_basisu::FsvDecodeControl shrink_outer_control(1 << 20, &shrink_heap);
  fsv_basisu::FsvDecodeControl shrink_child_control(1 << 20);
  {
    basisu::vector<basisu::vector<uint32_t>> shrinking(
        &shrink_outer_control);
    if (!shrinking.try_reserve(8)) return 86;
    for (uint32_t value = 0; value < 2; ++value) {
      basisu::vector<uint32_t> child(&shrink_child_control);
      if (!child.try_push_back(value + 31) ||
          !shrinking.try_push_back(std::move(child))) {
        return 87;
      }
    }
    const size_t original_capacity = shrinking.capacity();
    if (shrinking.try_reserve(2) || shrinking.capacity() != original_capacity ||
        shrinking.size() != 2 ||
        shrinking[0].fsv_allocator() != &shrink_child_control ||
        shrinking[0][0] != 31 || shrinking[1][0] != 32) {
      return 88;
    }
  }
  return shrink_outer_control.live_bytes() || shrink_child_control.live_bytes()
             ? 89
             : 0;
}

int CheckNonTrivialContractAndAtomicity() {
  static_assert(std::is_nothrow_copy_constructible<NonTrivialValue>::value,
                "controlled copies require nothrow construction");
  static_assert(std::is_nothrow_move_constructible<NonTrivialValue>::value,
                "controlled relocation requires nothrow construction");
  TestHeap heap(2);
  fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
  const uint64_t destruction_count_before = NonTrivialValue::destruction_count;
  basisu::vector<NonTrivialValue> values(&control);
  if (!values.try_push_back(NonTrivialValue(41))) return 90;
  if (values.try_push_back(NonTrivialValue(42)) || values.size() != 1 ||
      values[0].value != 41 || heap.allocations() != 2) {
    return 91;
  }
  values.clear();

  fsv_basisu::FsvDecodeControl first(1 << 20);
  fsv_basisu::FsvDecodeControl second(1 << 20);
  {
    basisu::vector<NonTrivialValue> source(&first);
    basisu::vector<NonTrivialValue> destination(&second);
    for (uint32_t value = 1; value <= 3; ++value) {
      if (!source.try_push_back(NonTrivialValue(value))) return 92;
    }
    if (!destination.try_push_back(NonTrivialValue(99)) ||
        !destination.try_copy_assign(source) || destination.size() != 3 ||
        destination[2].value != 3) {
      return 93;
    }
    basisu::vector<NonTrivialValue> moved(&first);
    if (!moved.try_push_back(NonTrivialValue(77))) return 102;
    if (!moved.try_move_assign(destination)) return 103;
    if (!destination.empty()) return 104;
    if (moved.size() != 3) return 105;
    if (moved[1].value != 2) return 106;
    basisu::vector<NonTrivialValue> swapped(&second);
    if (!swapped.try_push_back(NonTrivialValue(55)) ||
        !moved.try_swap(swapped) || moved.size() != 1 ||
        moved[0].value != 55 || swapped.size() != 3 ||
        swapped[2].value != 3) {
      return 95;
    }
    const size_t original_capacity = swapped.capacity();
    if (!swapped.try_reserve(swapped.size()) || swapped.size() != 3 ||
        swapped[0].value != 1 || swapped.capacity() > original_capacity) {
      return 96;
    }
  }
  if (first.live_bytes() || second.live_bytes()) return 97;

  TestHeap failing_copy_heap(2);
  fsv_basisu::FsvDecodeControl failing_copy_control(1 << 20,
                                                    &failing_copy_heap);
  fsv_basisu::FsvDecodeControl stable_source_control(1 << 20);
  {
    basisu::vector<NonTrivialValue> source(&stable_source_control);
    basisu::vector<NonTrivialValue> destination(&failing_copy_control);
    if (!source.try_push_back(NonTrivialValue(61)) ||
        !source.try_push_back(NonTrivialValue(62)) ||
        !destination.try_push_back(NonTrivialValue(63))) {
      return 98;
    }
    if (destination.try_copy_assign(source) || destination.size() != 1 ||
        destination[0].value != 63 || source.size() != 2 ||
        source[1].value != 62) {
      return 100;
    }
  }
  if (failing_copy_control.live_bytes() || stable_source_control.live_bytes()) {
    return 101;
  }
  return NonTrivialValue::destruction_count > destruction_count_before ? 0
                                                                        : 107;
}

int CheckMovedFromControlledReuse() {
  TestHeap heap;
  fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
  {
    basisu::vector<uint32_t> source(&control);
    if (!source.try_push_back(11) || heap.allocations() != 1) return 108;
    basisu::vector<uint32_t> destination(std::move(source));
    if (source.fsv_allocator() != &control ||
        destination.fsv_allocator() != &control || source.size() != 0 ||
        destination.size() != 1 || destination[0] != 11) {
      return 109;
    }
    const uint64_t allocation_count = control.request_allocation_count();
    if (!source.try_push_back(12) || source[0] != 12 ||
        control.request_allocation_count() != allocation_count + 1 ||
        heap.allocations() != 2 || destination[0] != 11) {
      return 110;
    }
  }
  if (control.live_bytes() ||
      control.request_allocation_count() != control.request_release_count()) {
    return 111;
  }

  TestHeap failing_heap(2);
  fsv_basisu::FsvDecodeControl failing_control(1 << 20, &failing_heap);
  {
    basisu::vector<uint32_t> source(&failing_control);
    if (!source.try_push_back(21)) return 112;
    basisu::vector<uint32_t> destination(std::move(source));
    if (source.try_push_back(22) || source.fsv_allocator() != &failing_control ||
        source.size() != 0 || destination.size() != 1 ||
        destination[0] != 21 || failing_heap.allocations() != 2 ||
        failing_control.last_allocation_outcome() !=
            fsv_basisu::FsvAllocationOutcome::kHeapFailure) {
      return 113;
    }
  }
  if (failing_control.live_bytes()) return 114;

  fsv_basisu::FsvDecodeControl cancelled_control(1 << 20);
  {
    basisu::vector<uint32_t> source(&cancelled_control);
    if (!source.try_push_back(31)) return 115;
    basisu::vector<uint32_t> destination(std::move(source));
    cancelled_control.Cancel();
    if (source.try_push_back(32) ||
        source.fsv_allocator() != &cancelled_control || source.size() != 0 ||
        destination.size() != 1 || destination[0] != 31 ||
        cancelled_control.last_allocation_outcome() !=
            fsv_basisu::FsvAllocationOutcome::kStopped) {
      return 116;
    }
  }
  return cancelled_control.live_bytes() ? 117 : 0;
}

int CheckNoExceptionControlledContract() {
#if !defined(__cpp_exceptions) && !defined(__EXCEPTIONS) && !defined(_CPPUNWIND)
  basisu::vector<PotentiallyThrowingValue> raw;
  if (!raw.try_push_back(PotentiallyThrowingValue(1)) || raw[0].value != 1) {
    return 118;
  }
  TestHeap heap;
  fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
  basisu::vector<PotentiallyThrowingValue> controlled(&control);
  if (controlled.try_push_back(PotentiallyThrowingValue(2)) ||
      !controlled.empty() || heap.allocations() != 0 || control.live_bytes()) {
    return 119;
  }
#endif
  return 0;
}

int CheckMixedTraitNoExceptionShrink() {
#if !defined(__cpp_exceptions) && !defined(__EXCEPTIONS) && !defined(_CPPUNWIND)
  {
    basisu::vector<MixedTraitValue> raw;
    if (!raw.try_reserve(8) || !raw.try_emplace_back(1) ||
        !raw.try_emplace_back(2) || !raw.try_emplace_back(3) ||
        !raw.try_emplace_back(4) || !raw.try_reserve(6) ||
        raw.capacity() != 6 || raw.size() != 4 || raw[3].value != 4) {
      return 40;
    }
  }
  TestHeap heap;
  fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
  {
    basisu::vector<MixedTraitValue> controlled(&control);
    if (!controlled.try_reserve(8) || !controlled.try_emplace_back(1) ||
        !controlled.try_emplace_back(2) || !controlled.try_emplace_back(3) ||
        !controlled.try_emplace_back(4)) {
      return 41;
    }
    const uint64_t live_before = control.live_bytes();
    const uint64_t allocations_before = heap.allocations();
    if (controlled.try_reserve(6)) return 42;
    if (controlled.capacity() != 8 || controlled.size() != 4 ||
        controlled[0].value != 1 || controlled[3].value != 4 ||
        control.live_bytes() != live_before ||
        heap.allocations() != allocations_before ||
        control.stop_reason() != fsv_basisu::FsvDecodeStopReason::kNone) {
      return 44;
    }
  }
  if (control.live_bytes() ||
      control.request_allocation_count() != control.request_release_count()) {
    return 45;
  }
#endif
  return 0;
}

int CheckMixedTraitNoExceptionCopyConstructor() {
#if !defined(__cpp_exceptions) && !defined(__EXCEPTIONS) && !defined(_CPPUNWIND)
  {
    basisu::vector<MixedTraitValue> raw;
    if (!raw.try_emplace_back(7) || !raw.try_emplace_back(8)) return 46;
    basisu::vector<MixedTraitValue> copied(raw);
    if (copied.size() != 2 || copied[0].value != 7 || copied[1].value != 8) {
      return 47;
    }
  }
  TestHeap heap;
  fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
  {
    basisu::vector<MixedTraitValue> source(&control);
    if (!source.try_reserve(3) || !source.try_emplace_back(11) ||
        !source.try_emplace_back(12) || !source.try_emplace_back(13)) {
      return 48;
    }
    const uint64_t live_before = control.live_bytes();
    const uint64_t allocations_before = heap.allocations();
    heap.ExitOnUnexpectedAllocation(43);
    const pid_t child = fork();
    if (child < 0) return 49;
    if (child == 0) {
      basisu::vector<MixedTraitValue> copied(source);
      (void)copied;
      std::_Exit(42);
    }
    int status = 0;
    if (waitpid(child, &status, 0) != child) return 50;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT) return 51;
    if (source.size() != 3 || source[0].value != 11 ||
        source[2].value != 13 || control.live_bytes() != live_before ||
        heap.allocations() != allocations_before ||
        control.request_allocation_count() != 1 ||
        control.request_release_count() != 0) {
      return 52;
    }
  }
  if (control.live_bytes() ||
      control.request_allocation_count() != control.request_release_count()) {
    return 53;
  }
#endif
  return 0;
}

int CheckNestedMixedTraitNoExceptionCopyConstructor() {
#if !defined(__cpp_exceptions) && !defined(__EXCEPTIONS) && !defined(_CPPUNWIND)
  {
    basisu::vector<basisu::vector<MixedTraitValue>> raw;
    basisu::vector<MixedTraitValue> child;
    if (!child.try_emplace_back(21) || !child.try_emplace_back(22) ||
        !raw.try_push_back(std::move(child))) {
      return 54;
    }
    basisu::vector<basisu::vector<MixedTraitValue>> copied(raw);
    if (copied.size() != 1 || copied[0].size() != 2 ||
        copied[0][0].value != 21 || copied[0][1].value != 22 ||
        copied[0].fsv_allocator() != nullptr) {
      return 55;
    }
  }

  TestHeap outer_heap;
  TestHeap child_heap;
  TrackingAllocator outer_allocator(1 << 20, &outer_heap);
  TrackingAllocator child_allocator(1 << 20, &child_heap);
  {
    basisu::vector<basisu::vector<MixedTraitValue>> source(&outer_allocator);
    basisu::vector<MixedTraitValue> child(&child_allocator);
    if (!child.try_emplace_back(31) || !child.try_emplace_back(32) ||
        !source.try_push_back(std::move(child))) {
      return 56;
    }
    const auto* const source_data = source.data();
    const auto* const child_data = source[0].data();
    const size_t source_capacity = source.capacity();
    const size_t child_capacity = source[0].capacity();
    const uint64_t outer_live = outer_allocator.control().live_bytes();
    const uint64_t outer_allocations =
        outer_allocator.control().request_allocation_count();
    const uint64_t outer_releases =
        outer_allocator.control().request_release_count();
    const uint64_t outer_owners = outer_allocator.owner_count();
    const uint64_t outer_owner_retains = outer_allocator.owner_retain_count();
    const uint64_t outer_owner_releases = outer_allocator.owner_release_count();
    const uint64_t child_live = child_allocator.control().live_bytes();
    const uint64_t child_allocations =
        child_allocator.control().request_allocation_count();
    const uint64_t child_releases =
        child_allocator.control().request_release_count();
    const uint64_t child_owners = child_allocator.owner_count();
    const uint64_t child_owner_retains = child_allocator.owner_retain_count();
    const uint64_t child_owner_releases = child_allocator.owner_release_count();
    const uint64_t outer_heap_allocations = outer_heap.allocations();
    const uint64_t child_heap_allocations = child_heap.allocations();

    const pid_t child_process = fork();
    if (child_process < 0) return 57;
    if (child_process == 0) {
      outer_allocator.ExitOnUnexpectedOwnerMutation(58);
      child_allocator.ExitOnUnexpectedOwnerMutation(59);
      outer_heap.ExitOnUnexpectedAllocation(60);
      child_heap.ExitOnUnexpectedAllocation(61);
      basisu::vector<basisu::vector<MixedTraitValue>> copied(source);
      (void)copied;
      std::_Exit(62);
    }
    int status = 0;
    if (waitpid(child_process, &status, 0) != child_process) return 63;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT) return 64;
    if (source.data() != source_data || source.capacity() != source_capacity ||
        source.size() != 1 || source[0].data() != child_data ||
        source[0].capacity() != child_capacity || source[0].size() != 2 ||
        source[0][0].value != 31 || source[0][1].value != 32 ||
        source[0].fsv_allocator() != &child_allocator ||
        outer_allocator.control().live_bytes() != outer_live ||
        outer_allocator.control().request_allocation_count() !=
            outer_allocations ||
        outer_allocator.control().request_release_count() != outer_releases ||
        outer_allocator.control().stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        outer_allocator.owner_count() != outer_owners ||
        outer_allocator.owner_retain_count() != outer_owner_retains ||
        outer_allocator.owner_release_count() != outer_owner_releases ||
        child_allocator.control().live_bytes() != child_live ||
        child_allocator.control().request_allocation_count() !=
            child_allocations ||
        child_allocator.control().request_release_count() != child_releases ||
        child_allocator.control().stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        child_allocator.owner_count() != child_owners ||
        child_allocator.owner_retain_count() != child_owner_retains ||
        child_allocator.owner_release_count() != child_owner_releases ||
        outer_heap.allocations() != outer_heap_allocations ||
        child_heap.allocations() != child_heap_allocations) {
      return 65;
    }
  }
  if (outer_allocator.control().live_bytes() ||
      child_allocator.control().live_bytes() ||
      outer_allocator.control().request_allocation_count() !=
          outer_allocator.control().request_release_count() ||
      child_allocator.control().request_allocation_count() !=
          child_allocator.control().request_release_count() ||
      outer_allocator.owner_count() || child_allocator.owner_count() ||
      outer_allocator.owner_retain_count() !=
          outer_allocator.owner_release_count() ||
      child_allocator.owner_retain_count() !=
          child_allocator.owner_release_count()) {
    return 66;
  }

  using UnsafeVector = basisu::vector<MixedTraitValue>;
  using RawIntermediate = basisu::vector<UnsafeVector>;
  using ControlledOuter = basisu::vector<RawIntermediate>;
  TestHeap raw_intermediate_outer_heap;
  TestHeap raw_intermediate_descendant_heap;
  TrackingAllocator raw_intermediate_outer_allocator(
      1 << 20, &raw_intermediate_outer_heap);
  TrackingAllocator raw_intermediate_descendant_allocator(
      1 << 20, &raw_intermediate_descendant_heap);
  {
    ControlledOuter source(&raw_intermediate_outer_allocator);
    RawIntermediate raw_intermediate;
    UnsafeVector unsafe_descendant(&raw_intermediate_descendant_allocator);
    if (!unsafe_descendant.try_emplace_back(61) ||
        !unsafe_descendant.try_emplace_back(62) ||
        !raw_intermediate.try_push_back(std::move(unsafe_descendant)) ||
        !source.try_push_back(std::move(raw_intermediate))) {
      return 75;
    }
    const auto* const source_data = source.data();
    const auto* const intermediate_data = source[0].data();
    const auto* const descendant_data = source[0][0].data();
    const size_t source_capacity = source.capacity();
    const size_t intermediate_capacity = source[0].capacity();
    const size_t descendant_capacity = source[0][0].capacity();
    const TrackingAllocatorSnapshot outer_snapshot = CaptureTrackingAllocator(
        raw_intermediate_outer_allocator, raw_intermediate_outer_heap);
    const TrackingAllocatorSnapshot descendant_snapshot =
        CaptureTrackingAllocator(raw_intermediate_descendant_allocator,
                                 raw_intermediate_descendant_heap);

    const pid_t child_process = fork();
    if (child_process < 0) return 76;
    if (child_process == 0) {
      raw_intermediate_outer_allocator.ExitOnUnexpectedOwnerMutation(77);
      raw_intermediate_descendant_allocator.ExitOnUnexpectedOwnerMutation(78);
      raw_intermediate_outer_heap.ExitOnUnexpectedAllocation(79);
      raw_intermediate_descendant_heap.ExitOnUnexpectedAllocation(80);
      ControlledOuter copied(source);
      (void)copied;
      std::_Exit(81);
    }
    int status = 0;
    if (waitpid(child_process, &status, 0) != child_process) return 82;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (!WIFSIGNALED(status) || WTERMSIG(status) != SIGABRT) return 83;
    if (source.data() != source_data || source.capacity() != source_capacity ||
        source.size() != 1 || source[0].data() != intermediate_data ||
        source[0].capacity() != intermediate_capacity ||
        source[0].size() != 1 || source[0][0].data() != descendant_data ||
        source[0][0].capacity() != descendant_capacity ||
        source[0][0].size() != 2 || source[0][0][0].value != 61 ||
        source[0][0][1].value != 62 ||
        source.fsv_allocator() != &raw_intermediate_outer_allocator ||
        source[0].fsv_allocator() != nullptr ||
        source[0][0].fsv_allocator() !=
            &raw_intermediate_descendant_allocator ||
        !MatchesTrackingAllocator(raw_intermediate_outer_allocator,
                                  raw_intermediate_outer_heap, outer_snapshot) ||
        !MatchesTrackingAllocator(raw_intermediate_descendant_allocator,
                                  raw_intermediate_descendant_heap,
                                  descendant_snapshot)) {
      return 84;
    }
  }
  if (raw_intermediate_outer_allocator.control().live_bytes() ||
      raw_intermediate_descendant_allocator.control().live_bytes() ||
      raw_intermediate_outer_allocator.control().request_allocation_count() !=
          raw_intermediate_outer_allocator.control().request_release_count() ||
      raw_intermediate_descendant_allocator.control()
              .request_allocation_count() !=
          raw_intermediate_descendant_allocator.control()
              .request_release_count() ||
      raw_intermediate_outer_allocator.owner_count() ||
      raw_intermediate_descendant_allocator.owner_count() ||
      raw_intermediate_outer_allocator.owner_retain_count() !=
          raw_intermediate_outer_allocator.owner_release_count() ||
      raw_intermediate_descendant_allocator.owner_retain_count() !=
          raw_intermediate_descendant_allocator.owner_release_count()) {
    return 85;
  }
#endif
  return 0;
}

int CheckNestedMixedTraitNoExceptionShrink() {
#if !defined(__cpp_exceptions) && !defined(__EXCEPTIONS) && !defined(_CPPUNWIND)
  {
    basisu::vector<basisu::vector<MixedTraitValue>> raw;
    if (!raw.try_reserve(8)) return 67;
    for (uint32_t value = 0; value < 2; ++value) {
      basisu::vector<MixedTraitValue> child;
      if (!child.try_emplace_back(value + 41) ||
          !raw.try_push_back(std::move(child))) {
        return 68;
      }
    }
    if (!raw.try_reserve(4) || raw.capacity() != 4 || raw.size() != 2 ||
        raw[0][0].value != 41 || raw[1][0].value != 42 ||
        raw[0].fsv_allocator() != nullptr ||
        raw[1].fsv_allocator() != nullptr) {
      return 69;
    }
  }

  TestHeap outer_heap;
  TestHeap child_heap;
  TrackingAllocator outer_allocator(1 << 20, &outer_heap);
  TrackingAllocator child_allocator(1 << 20, &child_heap);
  {
    basisu::vector<basisu::vector<MixedTraitValue>> source(&outer_allocator);
    if (!source.try_reserve(8)) return 70;
    for (uint32_t value = 0; value < 2; ++value) {
      basisu::vector<MixedTraitValue> child(&child_allocator);
      if (!child.try_emplace_back(value + 51) ||
          !source.try_push_back(std::move(child))) {
        return 71;
      }
    }
    const auto* const source_data = source.data();
    const auto* const first_child_data = source[0].data();
    const auto* const second_child_data = source[1].data();
    const size_t source_capacity = source.capacity();
    const uint64_t outer_live = outer_allocator.control().live_bytes();
    const uint64_t outer_allocations =
        outer_allocator.control().request_allocation_count();
    const uint64_t outer_releases =
        outer_allocator.control().request_release_count();
    const uint64_t outer_owners = outer_allocator.owner_count();
    const uint64_t outer_owner_retains = outer_allocator.owner_retain_count();
    const uint64_t outer_owner_releases = outer_allocator.owner_release_count();
    const uint64_t child_live = child_allocator.control().live_bytes();
    const uint64_t child_allocations =
        child_allocator.control().request_allocation_count();
    const uint64_t child_releases =
        child_allocator.control().request_release_count();
    const uint64_t child_owners = child_allocator.owner_count();
    const uint64_t child_owner_retains = child_allocator.owner_retain_count();
    const uint64_t child_owner_releases = child_allocator.owner_release_count();
    const uint64_t outer_heap_allocations = outer_heap.allocations();
    const uint64_t child_heap_allocations = child_heap.allocations();

    if (source.try_reserve(4)) return 72;
    if (source.data() != source_data || source.capacity() != source_capacity ||
        source.size() != 2 || source[0].data() != first_child_data ||
        source[1].data() != second_child_data ||
        source[0][0].value != 51 || source[1][0].value != 52 ||
        source[0].fsv_allocator() != &child_allocator ||
        source[1].fsv_allocator() != &child_allocator ||
        outer_allocator.control().live_bytes() != outer_live ||
        outer_allocator.control().request_allocation_count() !=
            outer_allocations ||
        outer_allocator.control().request_release_count() != outer_releases ||
        outer_allocator.control().stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        outer_allocator.owner_count() != outer_owners ||
        outer_allocator.owner_retain_count() != outer_owner_retains ||
        outer_allocator.owner_release_count() != outer_owner_releases ||
        child_allocator.control().live_bytes() != child_live ||
        child_allocator.control().request_allocation_count() !=
            child_allocations ||
        child_allocator.control().request_release_count() != child_releases ||
        child_allocator.control().stop_reason() !=
            fsv_basisu::FsvDecodeStopReason::kNone ||
        child_allocator.owner_count() != child_owners ||
        child_allocator.owner_retain_count() != child_owner_retains ||
        child_allocator.owner_release_count() != child_owner_releases ||
        outer_heap.allocations() != outer_heap_allocations ||
        child_heap.allocations() != child_heap_allocations) {
      return 73;
    }
  }
  if (outer_allocator.control().live_bytes() ||
      child_allocator.control().live_bytes() ||
      outer_allocator.control().request_allocation_count() !=
          outer_allocator.control().request_release_count() ||
      child_allocator.control().request_allocation_count() !=
          child_allocator.control().request_release_count() ||
      outer_allocator.owner_count() || child_allocator.owner_count() ||
      outer_allocator.owner_retain_count() !=
          outer_allocator.owner_release_count() ||
      child_allocator.owner_retain_count() !=
          child_allocator.owner_release_count()) {
    return 74;
  }

  using UnsafeVector = basisu::vector<MixedTraitValue>;
  using RawIntermediate = basisu::vector<UnsafeVector>;
  using ControlledOuter = basisu::vector<RawIntermediate>;
  TestHeap raw_intermediate_outer_heap;
  TestHeap raw_intermediate_descendant_heap;
  TrackingAllocator raw_intermediate_outer_allocator(
      1 << 20, &raw_intermediate_outer_heap);
  TrackingAllocator raw_intermediate_descendant_allocator(
      1 << 20, &raw_intermediate_descendant_heap);
  {
    ControlledOuter source(&raw_intermediate_outer_allocator);
    if (!source.try_reserve(8)) return 86;
    RawIntermediate raw_intermediate;
    UnsafeVector unsafe_descendant(&raw_intermediate_descendant_allocator);
    if (!unsafe_descendant.try_emplace_back(71) ||
        !unsafe_descendant.try_emplace_back(72) ||
        !raw_intermediate.try_push_back(std::move(unsafe_descendant)) ||
        !source.try_push_back(std::move(raw_intermediate))) {
      return 87;
    }
    const auto* const source_data = source.data();
    const auto* const intermediate_data = source[0].data();
    const auto* const descendant_data = source[0][0].data();
    const size_t source_capacity = source.capacity();
    const size_t intermediate_capacity = source[0].capacity();
    const size_t descendant_capacity = source[0][0].capacity();
    const TrackingAllocatorSnapshot outer_snapshot = CaptureTrackingAllocator(
        raw_intermediate_outer_allocator, raw_intermediate_outer_heap);
    const TrackingAllocatorSnapshot descendant_snapshot =
        CaptureTrackingAllocator(raw_intermediate_descendant_allocator,
                                 raw_intermediate_descendant_heap);

    if (source.try_reserve(4)) return 88;
    if (source.data() != source_data || source.capacity() != source_capacity ||
        source.size() != 1 || source[0].data() != intermediate_data ||
        source[0].capacity() != intermediate_capacity ||
        source[0].size() != 1 || source[0][0].data() != descendant_data ||
        source[0][0].capacity() != descendant_capacity ||
        source[0][0].size() != 2 || source[0][0][0].value != 71 ||
        source[0][0][1].value != 72 ||
        source.fsv_allocator() != &raw_intermediate_outer_allocator ||
        source[0].fsv_allocator() != nullptr ||
        source[0][0].fsv_allocator() !=
            &raw_intermediate_descendant_allocator ||
        !MatchesTrackingAllocator(raw_intermediate_outer_allocator,
                                  raw_intermediate_outer_heap, outer_snapshot) ||
        !MatchesTrackingAllocator(raw_intermediate_descendant_allocator,
                                  raw_intermediate_descendant_heap,
                                  descendant_snapshot)) {
      return 89;
    }
  }
  if (raw_intermediate_outer_allocator.control().live_bytes() ||
      raw_intermediate_descendant_allocator.control().live_bytes() ||
      raw_intermediate_outer_allocator.control().request_allocation_count() !=
          raw_intermediate_outer_allocator.control().request_release_count() ||
      raw_intermediate_descendant_allocator.control()
              .request_allocation_count() !=
          raw_intermediate_descendant_allocator.control()
              .request_release_count() ||
      raw_intermediate_outer_allocator.owner_count() ||
      raw_intermediate_descendant_allocator.owner_count() ||
      raw_intermediate_outer_allocator.owner_retain_count() !=
          raw_intermediate_outer_allocator.owner_release_count() ||
      raw_intermediate_descendant_allocator.owner_retain_count() !=
          raw_intermediate_descendant_allocator.owner_release_count()) {
    return 90;
  }
#endif
  return 0;
}

int CheckAllNoExceptionContracts() {
  const int existing = CheckNoExceptionControlledContract();
  if (existing) return existing;
  const int shrink = CheckMixedTraitNoExceptionShrink();
  if (shrink) return shrink;
  const int copy = CheckMixedTraitNoExceptionCopyConstructor();
  if (copy) return copy;
  const int nested_copy = CheckNestedMixedTraitNoExceptionCopyConstructor();
  if (nested_copy) return nested_copy;
  return CheckNestedMixedTraitNoExceptionShrink();
}

int CheckShrinkContract(int mode) {
  TestHeap heap(mode == 2 ? 3 : 0);
  const uint64_t limit = mode == 1 ? 14 * sizeof(uint32_t) : 1 << 20;
  fsv_basisu::FsvDecodeControl control(limit, &heap);
  {
    basisu::vector<uint32_t> values(&control);
    if (!values.try_reserve(8)) return 120;
    for (uint32_t value = 0; value < 4; ++value) {
      if (!values.try_push_back(value)) return 120;
    }
    if (!values.try_reserve(6)) return mode == 1 ? 121 : 122;
    if (values.capacity() != 6 || values.size() != 4 ||
        values[0] != 0 || values[3] != 3 || heap.allocations() != 2 ||
        control.peak_bytes() != 14 * sizeof(uint32_t) ||
        control.stop_reason() != fsv_basisu::FsvDecodeStopReason::kNone) {
      return 120;
    }
  }
  if (control.live_bytes() ||
      control.request_allocation_count() != control.request_release_count()) {
    return 127;
  }
  return 0;
}

int CheckThrowingCopyConstructorCleanup() {
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
  auto* control = new fsv_basisu::FsvDecodeControl(1 << 20);
  {
    basisu::vector<ThrowingCopyValue> source(control);
    if (!source.try_reserve(3) || !source.try_emplace_back(1) ||
        !source.try_emplace_back(2) || !source.try_emplace_back(3)) {
      return 123;
    }
    const uint64_t source_bytes = control->live_bytes();
    ThrowingCopyValue::copy_count = 0;
    ThrowingCopyValue::throw_on_copy = 2;
    bool caught = false;
    try {
      basisu::vector<ThrowingCopyValue> copied(source);
      (void)copied;
    } catch (const std::runtime_error&) {
      caught = true;
    }
    ThrowingCopyValue::throw_on_copy = 0;
    if (!caught || source.size() != 3 || source[0].value != 1 ||
        source[1].value != 2 || source[2].value != 3) {
      return 124;
    }
    if (control->live_bytes() != source_bytes ||
        control->request_allocation_count() !=
            control->request_release_count() + 1 ||
        ThrowingCopyValue::live_count != source.size()) {
      return 125;
    }
  }
  if (control->live_bytes() ||
      control->request_allocation_count() !=
          control->request_release_count() ||
      ThrowingCopyValue::live_count != 0) {
    return 126;
  }
  delete control;
#endif
  return 0;
}

int CheckIsolatedConcurrentStop(bool use_deadline) {
  fsv_basisu::FsvDecodeControl stopped(1 << 20);
  fsv_basisu::FsvDecodeControl unaffected(1 << 20);
  std::atomic<bool> stop_set{false};
  std::atomic<bool> peer_done{false};
  int stopped_result = 0;
  int unaffected_result = 0;
  std::thread stop_thread([&] {
    basisu::vector<uint32_t> values(&stopped);
    if (!values.try_reserve(1) || !values.try_push_back(7)) {
      stopped_result = 128;
      stop_set.store(true);
      return;
    }
    const bool won = use_deadline ? stopped.Deadline() : stopped.Cancel();
    if (!won) stopped_result = 129;
    stop_set.store(true);
    while (!peer_done.load()) std::this_thread::yield();
    if (values.try_push_back(8)) {
      stopped_result = 130;
    } else if (stopped.last_allocation_outcome() !=
               fsv_basisu::FsvAllocationOutcome::kStopped) {
      stopped_result = 133;
    }
  });
  std::thread unaffected_thread([&] {
    while (!stop_set.load()) std::this_thread::yield();
    basisu::vector<uint32_t> values(&unaffected);
    if (unaffected.stop_reason() != fsv_basisu::FsvDecodeStopReason::kNone ||
        !ExerciseGrowth(&values) || values.size() != 33 || values[32] != 32) {
      unaffected_result = 131;
    }
    peer_done.store(true);
  });
  stop_thread.join();
  unaffected_thread.join();
  const fsv_basisu::FsvDecodeStopReason expected =
      use_deadline ? fsv_basisu::FsvDecodeStopReason::kDeadline
                   : fsv_basisu::FsvDecodeStopReason::kCallerCancelled;
  if (stopped_result || unaffected_result || stopped.live_bytes() ||
      unaffected.live_bytes() || stopped.stop_reason() != expected ||
      unaffected.stop_reason() != fsv_basisu::FsvDecodeStopReason::kNone ||
      stopped.request_allocation_count() != stopped.request_release_count() ||
      unaffected.request_allocation_count() !=
          unaffected.request_release_count()) {
    return stopped_result ? stopped_result
                          : unaffected_result ? unaffected_result : 132;
  }
  return 0;
}

int CheckConcurrentControls() {
  const int cancellation = CheckIsolatedConcurrentStop(false);
  if (cancellation) return cancellation;
  return CheckIsolatedConcurrentStop(true);
}

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "lifetime") {
    auto* control = new fsv_basisu::FsvDecodeControl(4096);
    auto* values = new basisu::vector<uint32_t>(control);
    delete control;
    delete values;
    return 99;
  }
  if (argc == 2 && std::string(argv[1]) == "noexceptions") {
    return CheckAllNoExceptionContracts();
  }
  if (argc == 2 && std::string(argv[1]) == "mixed-shrink") {
    return CheckMixedTraitNoExceptionShrink();
  }
  if (argc == 2 && std::string(argv[1]) == "mixed-copy") {
    return CheckMixedTraitNoExceptionCopyConstructor();
  }
  if (argc == 2 && std::string(argv[1]) == "nested-mixed-copy") {
    return CheckNestedMixedTraitNoExceptionCopyConstructor();
  }
  if (argc == 2 && std::string(argv[1]) == "nested-mixed-shrink") {
    return CheckNestedMixedTraitNoExceptionShrink();
  }
  if (argc == 2 && std::string(argv[1]) == "shrink-capacity") {
    return CheckShrinkContract(0);
  }
  if (argc == 2 && std::string(argv[1]) == "shrink-budget") {
    return CheckShrinkContract(1);
  }
  if (argc == 2 && std::string(argv[1]) == "shrink-heap") {
    return CheckShrinkContract(2);
  }
  if (argc == 2 && std::string(argv[1]) == "throwing-copy") {
    return CheckThrowingCopyConstructorCleanup();
  }
  if (argc == 2 && std::string(argv[1]) == "concurrent-stop") {
    return CheckConcurrentControls();
  }
  {  // Null retains the upstream allocation path and successful output bytes.
    basisu::vector<uint32_t> upstream;
    if (!ExerciseGrowth(&upstream) || upstream.size() != 33 || upstream[32] != 32) return 1;
    TestHeap heap;
    fsv_basisu::FsvDecodeControl control(1 << 20, &heap);
    basisu::vector<uint32_t> values(&control);
    if (!ExerciseGrowth(&values) || values.size() != upstream.size() ||
        std::memcmp(values.data(), upstream.data(), upstream.size_in_bytes())) return 2;
    const size_t capacity = values.capacity();
    if (!values.try_resize(17) || values.capacity() != capacity ||
        values[16] != 16) return 3;
    if (!values.try_reserve(capacity) || values.capacity() != capacity) return 3;
    values.clear();
    if (control.live_bytes() || control.request_allocation_count() != control.request_release_count()) return 4;
  }
  {
    basisu::vector<uint32_t> raw_values;
    auto* raw = static_cast<uint32_t*>(std::malloc(sizeof(uint32_t)));
    if (!raw) return 56;
    *raw = 77;
    if (!raw_values.grant_ownership(raw, 1, 1) || raw_values[0] != 77 ||
        raw_values.assume_ownership() != raw) return 57;
    std::free(raw);

    fsv_basisu::FsvDecodeControl control(4096);
    basisu::vector<uint32_t> values(&control);
    if (!values.try_push_back(1) || values.assume_ownership() != nullptr || values.size() != 1) return 47;
    void* controlled_raw = std::malloc(sizeof(uint32_t));
    if (!controlled_raw || values.grant_ownership(static_cast<uint32_t*>(controlled_raw), 1, 1)) return 48;
    std::free(controlled_raw);
  }
  {
    TestHeap baseline_heap;
    fsv_basisu::FsvDecodeControl baseline(1 << 20, &baseline_heap);
    basisu::vector<uint32_t> values(&baseline);
    if (!ExerciseGrowth(&values)) return 5;
    const uint64_t ordinals = baseline_heap.allocations();
    const uint64_t peak = baseline.peak_bytes();
    values.clear();
    if (!ordinals) return 6;
    TestHeap tight_heap;
    fsv_basisu::FsvDecodeControl tight(peak - 1, &tight_heap);
    basisu::vector<uint32_t> tight_values(&tight);
    if (!ExerciseGrowth(&tight_values) ||
        tight.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kBudgetExceeded ||
        tight_heap.allocations() + 1 != ordinals) return 43;
    tight_values.clear();
    if (tight.live_bytes()) return 44;
    for (uint64_t ordinal = 1; ordinal <= ordinals; ++ordinal) {
      TestHeap failing_heap(ordinal);
      fsv_basisu::FsvDecodeControl failing(1 << 20, &failing_heap);
      basisu::vector<uint32_t> failing_values(&failing);
      if (!ExerciseGrowth(&failing_values) ||
          failing.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kHeapFailure) return 7;
      failing_values.clear();
      if (failing.live_bytes()) return 8;
    }
  }
  {
    fsv_basisu::FsvDecodeControl budget(7);
    basisu::vector<uint64_t> values(&budget);
    if (values.try_push_back(1) || budget.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kBudgetExceeded) return 9;
    fsv_basisu::FsvDecodeControl cancelled(4096);
    cancelled.Cancel();
    basisu::vector<uint32_t> cancelled_values(&cancelled);
    if (cancelled_values.try_push_back(1) || cancelled.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kStopped) return 10;
    fsv_basisu::FsvDecodeControl deadline(4096);
    deadline.Deadline();
    basisu::vector<uint32_t> deadline_values(&deadline);
    if (deadline_values.try_push_back(1) || deadline.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kStopped) return 11;
    fsv_basisu::FsvDecodeControl fresh(4096);
    basisu::vector<uint32_t> fresh_values(&fresh);
    if (!fresh_values.try_push_back(1)) return 12;
    fsv_basisu::FsvDecodeControl caller_first(4096);
    caller_first.Cancel(); caller_first.Deadline();
    if (caller_first.stop_reason() != fsv_basisu::FsvDecodeStopReason::kCallerCancelled) return 17;
    fsv_basisu::FsvDecodeControl deadline_first(4096);
    deadline_first.Deadline(); deadline_first.Cancel();
    if (deadline_first.stop_reason() != fsv_basisu::FsvDecodeStopReason::kDeadline) return 18;
  }
  {
    TestHeap failing_heap(1);
    fsv_basisu::FsvDecodeControl failed(4096, &failing_heap);
    basisu::vector<uint32_t> values(&failed);
    if (values.try_push_back(1) || failed.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kHeapFailure) return 13;
    if (values.try_push_back(2) || failed.last_allocation_outcome() != fsv_basisu::FsvAllocationOutcome::kHeapFailure) return 16;
  }
  {
    fsv_basisu::FsvDecodeControl control(1 << 20);
    basisu::vector<OverAlignedValue> aligned(&control);
    if (!aligned.try_resize(2) || reinterpret_cast<uintptr_t>(aligned.data()) % alignof(OverAlignedValue)) return 14;
    if (aligned.try_reserve(std::numeric_limits<size_t>::max()) || aligned.size() != 2) return 15;
    aligned.clear();
  }
  {
    fsv_basisu::FsvDecodeControl many(1 << 20);
    std::vector<basisu::vector<uint32_t>*> values;
    for (size_t i = 0; i < 300; ++i) {
      values.push_back(new basisu::vector<uint32_t>(&many));
      if (!values.back()->try_push_back(static_cast<uint32_t>(i))) return 19;
    }
    if (!many.live_bytes() || many.request_allocation_count() != 300) return 58;
    for (basisu::vector<uint32_t>* value : values) delete value;
    if (many.live_bytes()) return 29;
  }
  if (const int record = CheckAllocationRecordTransfer()) return record;
  if (const int direct = CheckDirectRelease()) return direct;
  if (const int transfer = CheckCrossControlTransfers()) return transfer;
  if (const int failure_atomicity = CheckCrossControlFailureAtomicity()) return failure_atomicity;
  if (const int copy_and_shrink = CheckCopyAndShrinkFailureAtomicity()) return copy_and_shrink;
  if (const int nested = CheckNestedAllocatorIdentityAndAtomicity()) return nested;
  if (const int nontrivial = CheckNonTrivialContractAndAtomicity()) return nontrivial;
  if (const int moved_from = CheckMovedFromControlledReuse()) return moved_from;
  for (int shrink_mode = 0; shrink_mode < 3; ++shrink_mode) {
    if (const int shrink = CheckShrinkContract(shrink_mode)) return shrink;
  }
  if (const int throwing_copy = CheckThrowingCopyConstructorCleanup()) {
    return throwing_copy;
  }
  if (const int concurrent = CheckConcurrentControls()) return concurrent;
  return 0;
}
